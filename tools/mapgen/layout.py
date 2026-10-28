"""Turn a land mask plus province seed points into a playable province graph.

Steps: nearest-seed regions clipped to land, contiguity clean-up, neighbours,
straits (curated plus automatic fixes), start territories, validation.
The result is written as layout.json, the draft that MapData is built from.
"""

from __future__ import annotations

import json
import math
from collections import deque
from dataclasses import dataclass, field

import numpy as np

START_SIZE = 8  # provinces each nation owns at the start (~40% of land stays neutral)
RACES = ("Humans", "Elves", "Orcs", "Dwarves")  # every nation has one (docs/DESIGN.md "Races"); every map mixes all four
MIN_SHARED_BORDER = 3  # pixels of shared border before two provinces count as neighbours


@dataclass
class Seed:
    name: str
    x: float
    y: float
    biome: str
    dev: int | None = None
    nation: str | None = None  # set on the 10 start capitals
    garrison: int | None = None  # neutral garrison override, in men


@dataclass
class ZoneSeed:
    """A named sea zone (docs/DESIGN.md "Navies"): water goes to the nearest of its seed points along a path over
    water. The first point is where its name and its fleets stand."""

    name: str
    points: list[tuple[float, float]]  # layout pixels


@dataclass
class Layout:
    map_id: str
    title: str
    theme: str
    width: int
    height: int
    labels: np.ndarray  # (H, W) province index (0-based) or -1
    land: np.ndarray
    seeds: list[Seed]
    terrain_of: dict[str, str]
    neighbors: list[set[int]] = field(default_factory=list)
    straits: list[dict] = field(default_factory=list)
    centers: list[tuple[int, int]] = field(default_factory=list)
    areas: list[int] = field(default_factory=list)
    owner: list[int | None] = field(default_factory=list)  # nation slot index or None
    nations: list[dict] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    # sea zones (build_sea_zones): zone index (0-based) per layout pixel, -1 on land and on water no zone reaches
    zones: np.ndarray | None = None
    zone_names: list[str] = field(default_factory=list)
    zone_centers: list[tuple[int, int]] = field(default_factory=list)
    zone_areas: list[int] = field(default_factory=list)
    zone_neighbors: list[set[int]] = field(default_factory=list)
    zone_coasts: list[list[int]] = field(default_factory=list)  # provinces touching each zone, by province index
    province_zones: list[list[int]] = field(default_factory=list)  # zones each province touches, most coast first
    zone_range: tuple[int, int] = (0, 0)  # how many zones the map should have (validate)
    zone_wrap: bool = False  # the sea runs on across the map's left and right edges (Earth)
    ship: str = ""  # the map's one ship type, by name (docs/DESIGN.md "Navies")

    def terrain(self, i: int) -> str:
        return self.terrain_of[self.seeds[i].biome]

    def passable(self, i: int) -> bool:
        return self.terrain(i) != "Mountain"


# ---------------------------------------------------------------- connected components


def components(values: np.ndarray, background: int = -1) -> np.ndarray:
    """4-connected components of equal values (run-based union-find). Returns ids, -1 for background."""
    h, w = values.shape
    runs: list[tuple[int, int, int, int]] = []  # row, start, end(excl), value
    row_runs: list[list[int]] = []
    for y in range(h):
        row = values[y]
        change = np.flatnonzero(np.diff(row)) + 1
        starts = np.concatenate(([0], change))
        ends = np.concatenate((change, [w]))
        idx = []
        for s, e in zip(starts.tolist(), ends.tolist()):
            v = int(row[s])
            if v != background:
                idx.append(len(runs))
                runs.append((y, s, e, v))
        row_runs.append(idx)
    parent = list(range(len(runs)))

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for y in range(1, h):
        prev, cur = row_runs[y - 1], row_runs[y]
        i = j = 0
        while i < len(prev) and j < len(cur):
            _, ps, pe, pv = runs[prev[i]]
            _, cs, ce, cv = runs[cur[j]]
            if ps < ce and cs < pe and pv == cv:
                ra, rb = find(prev[i]), find(cur[j])
                if ra != rb:
                    parent[ra] = rb
            if pe <= ce:
                i += 1
            else:
                j += 1
    out = np.full((h, w), -1, dtype=np.int32)
    remap: dict[int, int] = {}
    for k, (y, s, e, _) in enumerate(runs):
        r = find(k)
        if r not in remap:
            remap[r] = len(remap)
        out[y, s:e] = remap[r]
    return out


# ---------------------------------------------------------------- regions


def snap_to_land(land: np.ndarray, x: float, y: float) -> tuple[int, int, float]:
    xi, yi = int(round(x)), int(round(y))
    h, w = land.shape
    xi, yi = min(max(xi, 0), w - 1), min(max(yi, 0), h - 1)
    if land[yi, xi]:
        return xi, yi, 0.0
    ys, xs = np.nonzero(land)
    d = (xs - x) ** 2 + (ys - y) ** 2
    k = int(np.argmin(d))
    return int(xs[k]), int(ys[k]), float(np.sqrt(d[k]))


def grow_into(labels: np.ndarray, land: np.ndarray) -> np.ndarray:
    """Fill unlabelled land pixels from labelled 4-neighbours until stable."""
    labels = labels.copy()
    while True:
        hole = land & (labels < 0)
        if not hole.any():
            return labels
        changed = False
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            src = np.roll(np.roll(labels, dy, 0), dx, 1)
            take = hole & (src >= 0) & (labels < 0)
            if take.any():
                labels[take] = src[take]
                changed = True
        if not changed:
            return labels


def build_regions(land: np.ndarray, seeds: list[Seed], notes: list[str]) -> tuple[np.ndarray, list[Seed]]:
    h, w = land.shape
    snapped: list[Seed] = []
    for s in seeds:
        x, y, moved = snap_to_land(land, s.x, s.y)
        if moved > 2:
            notes.append(f"seed '{s.name}' was {moved:.0f}px off land; snapped to the nearest coast")
        snapped.append(Seed(s.name, x, y, s.biome, s.dev, s.nation, s.garrison))
    ys, xs = np.nonzero(land)
    best = np.full(xs.shape, np.inf)
    lab = np.full(xs.shape, -1, dtype=np.int32)
    for i, s in enumerate(snapped):
        d = (xs - s.x) ** 2 + (ys - s.y) ** 2
        closer = d < best
        best[closer] = d[closer]
        lab[closer] = i
    labels = np.full((h, w), -1, dtype=np.int32)
    labels[ys, xs] = lab

    # keep each province's piece that holds its seed; pieces cut off on a landmass
    # that has its own seeds are handed to the surrounding provinces
    land_comp = components(np.where(land, 0, -1))
    seeded_masses = {int(land_comp[s.y, s.x]) for s in snapped}
    comp = components(labels)
    main_piece = {int(comp[s.y, s.x]) for s in snapped}
    orphan = (labels >= 0) & ~np.isin(comp, list(main_piece)) & np.isin(land_comp, list(seeded_masses))
    labels[orphan] = -1
    labels = grow_into(labels, land)
    # islands without a seed go whole to the province that already holds most of them
    ys, xs = np.nonzero(land & ~np.isin(land_comp, list(seeded_masses)))
    if len(ys):
        n = len(snapped)
        lc = land_comp[ys, xs].astype(np.int64)
        votes = np.bincount(lc * n + labels[ys, xs], minlength=(lc.max() + 1) * n).reshape(-1, n)
        labels[ys, xs] = votes.argmax(axis=1)[lc]
    return labels, snapped


def find_neighbors(labels: np.ndarray, n: int) -> list[set[int]]:
    nb: list[set[int]] = [set() for _ in range(n)]
    pairs = []
    for a, b in ((labels[:, :-1], labels[:, 1:]), (labels[:-1, :], labels[1:, :])):
        m = (a >= 0) & (b >= 0) & (a != b)
        lo = np.minimum(a[m], b[m]).astype(np.int64)
        hi = np.maximum(a[m], b[m]).astype(np.int64)
        pairs.append(lo * 100000 + hi)
    codes, counts = np.unique(np.concatenate(pairs), return_counts=True)
    for c, k in zip(codes.tolist(), counts.tolist()):
        if k >= MIN_SHARED_BORDER:
            a, b = divmod(c, 100000)
            nb[a].add(b)
            nb[b].add(a)
    return nb


def find_centers(labels: np.ndarray, seeds: list[Seed]) -> tuple[list[tuple[int, int]], list[int]]:
    """Deepest interior point of each province (where its army token and label sit)."""
    n = len(seeds)
    # depth = how many erosion steps a pixel survives inside its own province
    depth = np.zeros(labels.shape, dtype=np.int32)
    cur = labels >= 0
    edge_free = np.ones(labels.shape, dtype=bool)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        edge_free &= np.roll(np.roll(labels, dy, 0), dx, 1) == labels
    cur &= edge_free
    for _ in range(60):
        if not cur.any():
            break
        depth += cur
        nxt = cur.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nxt &= np.roll(np.roll(cur, dy, 0), dx, 1)
        cur = nxt
    ys, xs = np.nonzero(labels >= 0)
    lab = labels[ys, xs]
    dep = depth[ys, xs]
    areas = np.bincount(lab, minlength=n).tolist()
    centers: list[tuple[int, int]] = []
    for i, s in enumerate(seeds):
        sel = lab == i
        if not sel.any():
            centers.append((s.x, s.y))
            continue
        d = dep[sel]
        cand_x, cand_y = xs[sel], ys[sel]
        top = d >= d.max() - 1
        # among the deepest points prefer the one nearest the seed (keeps islands sensible)
        dist = (cand_x[top] - s.x) ** 2 + (cand_y[top] - s.y) ** 2
        k = int(np.argmin(dist))
        centers.append((int(cand_x[top][k]), int(cand_y[top][k])))
    return centers, areas


def edge_points(labels: np.ndarray, n: int, cap: int = 120) -> list[np.ndarray]:
    """Coastal pixels of each province, subsampled, as (k, 2) arrays of (x, y)."""
    land = labels >= 0
    coast = land & ~(np.roll(land, 1, 0) & np.roll(land, -1, 0) & np.roll(land, 1, 1) & np.roll(land, -1, 1))
    ys, xs = np.nonzero(coast)
    lab = labels[ys, xs]
    out = []
    for i in range(n):
        sel = np.flatnonzero(lab == i)
        if len(sel) > cap:
            sel = sel[np.linspace(0, len(sel) - 1, cap).astype(int)]
        out.append(np.stack([xs[sel], ys[sel]], axis=1) if len(sel) else np.zeros((0, 2), dtype=int))
    return out


def closest_points(pa: np.ndarray, pb: np.ndarray) -> tuple[float, tuple[int, int], tuple[int, int]]:
    if len(pa) == 0 or len(pb) == 0:
        return np.inf, (0, 0), (0, 0)
    d = ((pa[:, None, :] - pb[None, :, :]) ** 2).sum(-1)
    k = int(np.argmin(d))
    i, j = divmod(k, d.shape[1])
    return float(np.sqrt(d[i, j])), tuple(pa[i].tolist()), tuple(pb[j].tolist())  # type: ignore[return-value]


# ---------------------------------------------------------------- graph


def passable_components(lay: Layout) -> list[set[int]]:
    n = len(lay.seeds)
    seen = [False] * n
    comps = []
    for s in range(n):
        if seen[s] or not lay.passable(s):
            continue
        q = deque([s])
        seen[s] = True
        comp = {s}
        while q:
            a = q.popleft()
            for b in lay.neighbors[a]:
                if not seen[b] and lay.passable(b):
                    seen[b] = True
                    comp.add(b)
                    q.append(b)
        comps.append(comp)
    return sorted(comps, key=len, reverse=True)


def add_strait(lay: Layout, a: int, b: int, pts, wrap: bool = False, auto: bool = False) -> None:
    if b in lay.neighbors[a]:
        return
    lay.neighbors[a].add(b)
    lay.neighbors[b].add(a)
    lay.straits.append({"a": a, "b": b, "from": list(pts[0]), "to": list(pts[1]), "wrap": wrap, "auto": auto})


def curated_straits(lay: Layout, pairs: list[tuple[str, str]], wraps: list[tuple[str, str]] = ()) -> None:
    by_name = {s.name: i for i, s in enumerate(lay.seeds)}
    edges = edge_points(lay.labels, len(lay.seeds))
    for na, nb in pairs:
        a, b = by_name[na], by_name[nb]
        if b in lay.neighbors[a]:
            lay.notes.append(f"strait {na}-{nb} skipped: already neighbours by land")
            continue
        _, pa, pb = closest_points(edges[a], edges[b])
        add_strait(lay, a, b, (pa, pb))
    for na, nb in wraps:
        a, b = by_name[na], by_name[nb]
        add_strait(lay, a, b, (lay.centers[a], lay.centers[b]), wrap=True)


def auto_connect(lay: Layout) -> None:
    """Join passable components that are cut off (islands, sealed coasts) with the shortest strait."""
    edges = edge_points(lay.labels, len(lay.seeds))
    while True:
        comps = passable_components(lay)
        if len(comps) <= 1:
            return
        main, rest = comps[0], set().union(*comps[1:])
        best = (np.inf, None, None, None)
        for a in rest:
            for b in main:
                ca, cb = lay.centers[a], lay.centers[b]
                if (ca[0] - cb[0]) ** 2 + (ca[1] - cb[1]) ** 2 > (best[0] + 400) ** 2:
                    continue
                d, pa, pb = closest_points(edges[a], edges[b])
                if d < best[0]:
                    best = (d, a, b, (pa, pb))
        d, a, b, pts = best
        if a is None:
            lay.notes.append("auto_connect: could not join a component")
            return
        lay.notes.append(f"auto strait {lay.seeds[a].name} - {lay.seeds[b].name} ({d:.0f}px)")
        add_strait(lay, a, b, pts, auto=True)


def assign_start_territories(
    lay: Layout, allowed=None, order: list[str] | None = None, races: dict[str, str] | None = None
) -> None:
    """Round-robin claims outward from each capital until every nation holds START_SIZE provinces.

    allowed(slot, province) -> bool can restrict claims (Skyshards keeps each nation on its own shard).
    order lists the nations by slot; by default slots follow the capitals' seed order.
    races gives each nation (by name) its race, one of RACES (validate() checks every nation has one).
    """
    n = len(lay.seeds)
    caps = [(i, s.nation) for i, s in enumerate(lay.seeds) if s.nation]
    if order is not None:
        caps.sort(key=lambda c: order.index(c[1]))
    lay.owner = [None] * n
    lay.nations = []
    for slot, (i, name) in enumerate(caps):
        lay.owner[i] = slot
        race = (races or {}).get(name)
        lay.nations.append({"slot": slot + 1, "name": name, "capital": i, "colorIndex": slot + 1, "race": race})
    # hop distance from every capital
    hops = []
    for i, _ in caps:
        dist = [10**9] * n
        dist[i] = 0
        q = deque([i])
        while q:
            a = q.popleft()
            for b in lay.neighbors[a]:
                if dist[b] > dist[a] + 1 and lay.passable(b):
                    dist[b] = dist[a] + 1
                    q.append(b)
        hops.append(dist)
    counts = [1] * len(caps)
    progress = True
    while progress:
        progress = False
        for slot, (cap, _) in enumerate(caps):
            if counts[slot] >= START_SIZE:
                continue
            frontier = set()
            for p in range(n):
                if lay.owner[p] == slot:
                    frontier |= {
                        q
                        for q in lay.neighbors[p]
                        if lay.owner[q] is None and lay.passable(q) and (allowed is None or allowed(slot, q))
                    }
            if not frontier:
                continue
            cx, cy = lay.centers[cap]

            def score(q: int) -> tuple[int, float]:
                qx, qy = lay.centers[q]
                return hops[slot][q], (qx - cx) ** 2 + (qy - cy) ** 2

            pick = min(frontier, key=score)
            lay.owner[pick] = slot
            counts[slot] += 1
            progress = True
    short = [lay.nations[s]["name"] for s, c in enumerate(counts) if c < START_SIZE]
    if short:
        lay.notes.append(f"start territory smaller than {START_SIZE} for: {', '.join(short)}")


DEV_BY_BIOME = {
    # earth
    "grassland": 3, "steppe": 2, "savanna": 2, "desert": 1, "tundra": 1, "forest": 2, "taiga": 1,
    "jungle": 2, "hills": 2, "drylands": 1, "mountains": 1, "ice": 1,
    # fantasy
    "meadow": 3, "frostfields": 1, "dunes": 1, "wildwood": 2, "highlands": 2, "ashlands": 1, "peaks": 1,
    # sky
    "skymeadow": 2, "heartruins": 4, "crystalgrove": 2, "crags": 2, "stormspire": 1,
}


START_DEV = 17  # total development every nation starts with, on every map


def base_dev(s: Seed) -> int:
    dev = s.dev if s.dev is not None else DEV_BY_BIOME.get(s.biome, 2)
    if s.nation:
        dev = max(dev, 3)
    return int(min(max(dev, 1), 5))


def balance_start_development(lay: Layout, target: int = START_DEV) -> None:
    """Nudge development inside each start territory so every nation starts equally rich.

    Neutral land is untouched, so maps keep their character (rich Crownlands, poor deserts).
    """
    for slot in range(len(lay.nations)):
        owned = [i for i in range(len(lay.seeds)) if lay.owner[i] == slot]
        devs = {i: base_dev(lay.seeds[i]) for i in owned}
        while sum(devs.values()) < target:
            i = min((i for i in owned if devs[i] < 5), key=lambda i: (devs[i], i))
            devs[i] += 1
        while sum(devs.values()) > target:
            i = max((i for i in owned if devs[i] > 1 and not lay.seeds[i].nation), key=lambda i: (devs[i], -i))
            devs[i] -= 1
        for i, d in devs.items():
            lay.seeds[i].dev = d


def finalize(lay: Layout) -> None:
    lay.neighbors = find_neighbors(lay.labels, len(lay.seeds))
    lay.centers, lay.areas = find_centers(lay.labels, lay.seeds)


# ---------------------------------------------------------------- sea zones

GRID_STEP = 2  # layout pixels per pixel of the game's map grid (export_luau.GRID_STEP)
MIN_COAST = 3  # shared edge pixels (layout) before a province counts as a coast of a zone...
MIN_COAST_SHARE = 0.1  # ...and at least this share of the province's whole shore (not a corner grazing a zone)
MIN_ZONE_BORDER = 2  # shared edge pixels (game grid) before two zones count as neighbours


def _shift(a: np.ndarray, dy: int, dx: int, wrap_x: bool, fill: int = -1) -> np.ndarray:
    """a moved by (dy, dx): out[y, x] = a[y - dy, x - dx]. Off-map pixels read `fill`, except across the left and
    right edges of a map that wraps around (Earth: the Pacific)."""
    out = np.roll(np.roll(a, dy, 0), dx, 1)
    if dy > 0:
        out[:dy, :] = fill
    elif dy < 0:
        out[dy:, :] = fill
    if not wrap_x:
        if dx > 0:
            out[:, :dx] = fill
        elif dx < 0:
            out[:, dx:] = fill
    return out


STEPS4 = ((0, 1), (0, -1), (1, 0), (-1, 0))
STEPS8 = STEPS4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def grow_zones(water: np.ndarray, seeds: list[tuple[int, int, int]], wrap_x: bool) -> np.ndarray:
    """Zone index per pixel: every water pixel takes the zone of the nearest seed (x, y, zone) along a path over
    water, so a zone never jumps across land. The front grows one pixel a step, alternating 4- and 8-neighbour
    steps so zones come out round. Water no seed reaches (lakes) keeps -1, and so does land."""
    zones = np.full(water.shape, -1, dtype=np.int32)
    for x, y, z in seeds:
        zones[y, x] = z
    step = 0
    while True:
        free = water & (zones < 0)
        if not free.any():
            break
        new = zones.copy()
        changed = False
        for dy, dx in STEPS4 if step % 2 == 0 else STEPS8:
            src = _shift(zones, dy, dx, wrap_x)
            take = free & (src >= 0) & (new < 0)
            if take.any():
                new[take] = src[take]
                changed = True
        zones = new
        step += 1
        if not changed:
            break
    return zones


def _nearest(mask: np.ndarray, x: float, y: float) -> tuple[int, int]:
    ys, xs = np.nonzero(mask)
    k = int(np.argmin((xs - x) ** 2 + (ys - y) ** 2))
    return int(xs[k]), int(ys[k])


def build_sea_zones(
    lay: Layout,
    zone_seeds: list[ZoneSeed],
    links: list[tuple[str, str]] = (),
    wrap_x: bool = False,
    zone_range: tuple[int, int] = (1, 30),
    assign=None,
) -> None:
    """Split the water (or Skyshards' void) into named sea zones (docs/DESIGN.md "Navies").

    Zones are grown on the game's map grid (every GRID_STEP-th layout pixel, the province grid MapData carries), so
    the zone grid lines up with it exactly, then spread to every layout pixel. `assign(xs, ys)` (layout pixels ->
    zone index per pixel) replaces the growth where geometry should decide (Skyshards' symmetric wedges). Each zone
    gets its neighbours (zones whose water touches, plus `links`: channels too narrow for the map's pixels, like
    Gibraltar), its coasts (land provinces with MIN_COAST pixels and MIN_COAST_SHARE of their shore on it), its
    centre (its first seed point) and its area. Every strait gets the zone it crosses. Water no seed reaches (lakes)
    has no zone.
    """
    lay.zone_range = zone_range
    lay.zone_wrap = wrap_x
    water_full = lay.labels < 0
    water = water_full[::GRID_STEP, ::GRID_STEP]
    if assign is not None:
        gy, gx = np.mgrid[0 : water.shape[0], 0 : water.shape[1]]
        small = np.where(water, assign(gx * GRID_STEP, gy * GRID_STEP), -1).astype(np.int32)
    else:
        starts = []
        for z, zs in enumerate(zone_seeds):
            for px, py in zs.points:
                sx, sy = _nearest(water, px / GRID_STEP, py / GRID_STEP)
                starts.append((sx, sy, z))
        small = grow_zones(water, starts, wrap_x)
    # every layout pixel: the grid pixel's zone, then a few steps of growth over the water pixels the grid skipped
    full = np.repeat(np.repeat(small, GRID_STEP, 0), GRID_STEP, 1)[: lay.height, : lay.width]
    full = np.where(water_full, full, -1)
    for _ in range(4 * GRID_STEP):
        free = water_full & (full < 0)
        if not free.any():
            break
        for dy, dx in STEPS4:
            src = _shift(full, dy, dx, wrap_x)
            take = free & (src >= 0) & (full < 0)
            full[take] = src[take]
    lay.zones = full
    n = len(zone_seeds)
    lay.zone_names = [zs.name for zs in zone_seeds]
    lay.zone_areas = (np.bincount(small[small >= 0].ravel(), minlength=n) * GRID_STEP * GRID_STEP).tolist()
    centers = []
    for z, zs in enumerate(zone_seeds):
        px, py = zs.points[0]
        gx, gy = _nearest(small == z, px / GRID_STEP, py / GRID_STEP)
        centers.append((gx * GRID_STEP, gy * GRID_STEP))
    lay.zone_centers = centers

    # neighbours: zones whose grid pixels touch (across the map edge too on a wrapping map), plus the links
    nb: list[set[int]] = [set() for _ in range(n)]
    pairs = []
    for dy, dx in ((0, 1), (1, 0)):
        other = _shift(small, -dy, -dx, wrap_x)
        m = (small >= 0) & (other >= 0) & (small != other)
        pairs.append(np.minimum(small[m], other[m]).astype(np.int64) * 1000 + np.maximum(small[m], other[m]))
    codes, counts = np.unique(np.concatenate(pairs), return_counts=True)
    for c, k in zip(codes.tolist(), counts.tolist()):
        if k >= MIN_ZONE_BORDER:
            a, b = divmod(c, 1000)
            nb[a].add(b)
            nb[b].add(a)
    by_name = {name: z for z, name in enumerate(lay.zone_names)}
    for a, b in links:
        za, zb = by_name[a], by_name[b]
        nb[za].add(zb)
        nb[zb].add(za)
    lay.zone_neighbors = nb

    # coasts: land pixels with a 4-neighbour of the zone, counted per (province, zone)
    contact: dict[tuple[int, int], int] = {}
    for dy, dx in STEPS4:
        other = _shift(full, dy, dx, wrap_x)
        m = (lay.labels >= 0) & (other >= 0)
        codes, counts = np.unique(lay.labels[m].astype(np.int64) * 1000 + other[m], return_counts=True)
        for c, k in zip(codes.tolist(), counts.tolist()):
            key = divmod(c, 1000)
            contact[key] = contact.get(key, 0) + k
    coasts: list[list[int]] = [[] for _ in range(n)]
    per_province: list[list[tuple[int, int]]] = [[] for _ in range(len(lay.seeds))]
    shore = [0] * len(lay.seeds)
    for (p, _), k in contact.items():
        shore[p] += k
    for (p, z), k in sorted(contact.items()):
        if k >= MIN_COAST and k >= MIN_COAST_SHARE * shore[p] and lay.passable(p):
            coasts[z].append(p)
            per_province[p].append((k, z))
    lay.zone_coasts = coasts
    lay.province_zones = [[z for _, z in sorted(lst, key=lambda t: (-t[0], t[1]))] for lst in per_province]

    # the zone each strait crosses: the zone most of the water along it belongs to, if both shores are its coasts;
    # else the zone both shores touch that lies nearest the strait's middle
    for st in lay.straits:
        a, b = st["a"], st["b"]
        shared = [z for z in lay.province_zones[a] if z in lay.province_zones[b]]
        zone = None
        if not st["wrap"]:
            (x0, y0), (x1, y1) = st["from"], st["to"]
            votes: dict[int, int] = {}
            steps = max(2, int(math.hypot(x1 - x0, y1 - y0)))
            for i in range(steps + 1):
                x = int(round(x0 + (x1 - x0) * i / steps))
                y = int(round(y0 + (y1 - y0) * i / steps))
                ys0, ys1 = max(0, y - 3), min(lay.height, y + 4)
                xs0, xs1 = max(0, x - 3), min(lay.width, x + 4)
                for v in full[ys0:ys1, xs0:xs1].ravel().tolist():
                    if v >= 0:
                        votes[v] = votes.get(v, 0) + 1
            for v, _ in sorted(votes.items(), key=lambda t: (-t[1], t[0])):
                if v in shared:
                    zone = v
                    break
            if zone is None and shared:
                mx, my = (x0 + x1) / 2, (y0 + y1) / 2
                zone = min(shared, key=lambda z: (lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)(_nearest(full == z, mx, my)))
        elif shared:
            zone = shared[0]
        st["zone"] = zone


def validate(lay: Layout) -> list[str]:
    problems = []
    comps = passable_components(lay)
    if len(comps) != 1:
        problems.append(f"{len(comps)} separate passable regions (should be 1)")
    for i, s in enumerate(lay.seeds):
        if lay.areas[i] < 100:
            problems.append(f"province '{s.name}' is tiny ({lay.areas[i]}px)")
        if lay.passable(i) and not any(lay.passable(j) for j in lay.neighbors[i]):
            problems.append(f"province '{s.name}' has no passable neighbour")
    names = [s.name for s in lay.seeds]
    dupes = {x for x in names if names.count(x) > 1}
    if dupes:
        problems.append(f"duplicate names: {sorted(dupes)}")
    if len(lay.seeds) > 150:
        problems.append(f"{len(lay.seeds)} provinces is over the 150 budget")
    for n in lay.nations:
        if n.get("race") not in RACES:
            problems.append(f"nation '{n['name']}' has no race (one of {', '.join(RACES)})")
    missing = [r for r in RACES if r not in {n.get("race") for n in lay.nations}]
    if missing:
        problems.append(f"races missing from the map: {', '.join(missing)}")
    problems += validate_zones(lay)
    return problems


def zone_pieces(mask: np.ndarray, wrap_x: bool, min_share: float = 0.01) -> list[int]:
    """Sizes of the separate pieces of one zone (grid pixels), ignoring slivers under min_share of it (a pixel of
    water cut off in a fjord). Water touching only at a corner counts as touching (zones grow over corners), and so
    does water on both sides of a map that wraps around."""
    m = mask.copy()
    # close corner-only links: where two diagonal pixels are in and their two neighbours out, take one neighbour in
    a, b = m[:-1, :-1], m[1:, 1:]
    c, d = m[:-1, 1:], m[1:, :-1]
    m[:-1, 1:] |= a & b
    m[:-1, :-1] |= c & d
    comp = components(np.where(m, 0, -1))
    count = int(comp.max()) + 1
    if count <= 0:
        return []
    parent = list(range(count))

    def find(i: int) -> int:
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    if wrap_x:
        left, right = comp[:, 0], comp[:, -1]
        for y in np.flatnonzero((left >= 0) & (right >= 0)).tolist():
            ra, rb = find(int(left[y])), find(int(right[y]))
            if ra != rb:
                parent[ra] = rb
    sizes: dict[int, int] = {}
    labels, counts = np.unique(comp[(comp >= 0) & mask], return_counts=True)
    for k, n in zip(labels.tolist(), counts.tolist()):
        r = find(int(k))
        sizes[r] = sizes.get(r, 0) + n
    total = sum(sizes.values())
    return sorted((n for n in sizes.values() if n >= min_share * total), reverse=True)


def validate_zones(lay: Layout) -> list[str]:
    """The sea-zone rules (docs/DESIGN.md "Navies", docs/MAPS.md): the map's zone count, unique names, every zone in
    one piece with a coast, one connected sea, every strait in a zone whose coasts hold both its ends."""
    problems = []
    n = len(lay.zone_names)
    lo, hi = lay.zone_range
    if lay.zones is None or n == 0:
        return ["no sea zones (build_sea_zones)"]
    if not lo <= n <= hi:
        problems.append(f"{n} sea zones (this map wants {lo}-{hi})")
    if not lay.ship:
        problems.append("the map names no ship")
    names = set(s.name for s in lay.seeds)
    if len(set(lay.zone_names)) != n:
        problems.append("duplicate sea zone names")
    grid = lay.zones[::GRID_STEP, ::GRID_STEP]
    for z, name in enumerate(lay.zone_names):
        if name in names:
            problems.append(f"sea zone '{name}' has a province's name")
        if not lay.zone_coasts[z]:
            problems.append(f"sea zone '{name}' touches no province")
        pieces = zone_pieces(grid == z, lay.zone_wrap)
        if len(pieces) > 1:
            problems.append(f"sea zone '{name}' is in {len(pieces)} pieces: {pieces}")
    seen = {0}
    queue = deque([0])
    while queue:
        a = queue.popleft()
        for b in lay.zone_neighbors[a]:
            if b not in seen:
                seen.add(b)
                queue.append(b)
    if len(seen) != n:
        cut = sorted(lay.zone_names[z] for z in range(n) if z not in seen)
        problems.append(f"sea zones cut off from the rest: {', '.join(cut)}")
    for st in lay.straits:
        na, nb = lay.seeds[st["a"]].name, lay.seeds[st["b"]].name
        z = st.get("zone")
        if z is None:
            problems.append(f"strait {na}-{nb} lies in no sea zone")
        elif st["a"] not in lay.zone_coasts[z] or st["b"] not in lay.zone_coasts[z]:
            problems.append(f"strait {na}-{nb}: both ends must be coasts of {lay.zone_names[z]}")
    return problems


def to_json(lay: Layout) -> dict:
    provinces = []
    for i, s in enumerate(lay.seeds):
        dev = base_dev(s)
        provinces.append(
            {
                "id": i + 1,
                "name": s.name,
                "terrain": lay.terrain(i),
                "biome": s.biome,
                "development": dev,
                "center": list(lay.centers[i]),
                "area": int(lay.areas[i]),
                "neighbors": sorted(j + 1 for j in lay.neighbors[i]),
                "startOwner": None if lay.owner[i] is None else lay.owner[i] + 1,
                "isCapital": bool(s.nation),
                **({"garrison": s.garrison} if s.garrison else {}),
                **({"zones": [z + 1 for z in lay.province_zones[i]]} if lay.province_zones and lay.province_zones[i] else {}),
            }
        )
    straits = [
        {
            "a": st["a"] + 1,
            "b": st["b"] + 1,
            "from": st["from"],
            "to": st["to"],
            "wrap": st["wrap"],
            "auto": st["auto"],
            "zone": None if st.get("zone") is None else st["zone"] + 1,
        }
        for st in lay.straits
    ]
    zones = [
        {
            "id": z + 1,
            "name": lay.zone_names[z],
            "center": list(lay.zone_centers[z]),
            "area": int(lay.zone_areas[z]),
            "neighbors": sorted(b + 1 for b in lay.zone_neighbors[z]),
            "coasts": sorted(p + 1 for p in lay.zone_coasts[z]),
        }
        for z in range(len(lay.zone_names))
    ]
    counts = {"provinces": len(provinces)}
    for t in ("Plains", "Forest", "Hills", "Mountain"):
        counts[t] = sum(1 for p in provinces if p["terrain"] == t)
    counts["neutralAtStart"] = sum(1 for p in provinces if p["startOwner"] is None and p["terrain"] != "Mountain")
    counts["seaZones"] = len(zones)
    counts["coastal"] = sum(1 for p in provinces if p.get("zones"))
    return {
        "id": lay.map_id,
        "title": lay.title,
        "theme": lay.theme,
        "imageSize": [lay.width, lay.height],
        "ship": lay.ship,
        "summary": counts,
        "nations": [{**n, "capital": n["capital"] + 1} for n in lay.nations],
        "provinces": provinces,
        "straits": straits,
        "seaZones": zones,
        "notes": lay.notes,
    }


def write_json(lay: Layout, path: str) -> None:
    with open(path, "w") as f:
        json.dump(to_json(lay), f, indent=1)
        f.write("\n")
