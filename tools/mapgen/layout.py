"""Turn a land mask plus province seed points into a playable province graph.

Steps: nearest-seed regions clipped to land, contiguity clean-up, neighbours,
straits (curated plus automatic fixes), start territories, validation.
The result is written as layout.json, the draft that MapData is built from.
"""

from __future__ import annotations

import json
from collections import deque
from dataclasses import dataclass, field

import numpy as np

START_SIZE = 8  # provinces each nation owns at the start (~40% of land stays neutral)
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


def assign_start_territories(lay: Layout, allowed=None) -> None:
    """Round-robin claims outward from each capital until every nation holds START_SIZE provinces.

    allowed(slot, province) -> bool can restrict claims (Skyshards keeps each nation on its own shard).
    """
    n = len(lay.seeds)
    caps = [(i, s.nation) for i, s in enumerate(lay.seeds) if s.nation]
    lay.owner = [None] * n
    lay.nations = []
    for slot, (i, name) in enumerate(caps):
        lay.owner[i] = slot
        lay.nations.append({"slot": slot + 1, "name": name, "capital": i, "colorIndex": slot + 1})
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
            }
        )
    straits = [
        {"a": st["a"] + 1, "b": st["b"] + 1, "from": st["from"], "to": st["to"], "wrap": st["wrap"], "auto": st["auto"]}
        for st in lay.straits
    ]
    counts = {"provinces": len(provinces)}
    for t in ("Plains", "Forest", "Hills", "Mountain"):
        counts[t] = sum(1 for p in provinces if p["terrain"] == t)
    counts["neutralAtStart"] = sum(1 for p in provinces if p["startOwner"] is None and p["terrain"] != "Mountain")
    return {
        "id": lay.map_id,
        "title": lay.title,
        "theme": lay.theme,
        "imageSize": [lay.width, lay.height],
        "summary": counts,
        "nations": [{**n, "capital": n["capital"] + 1} for n in lay.nations],
        "provinces": provinces,
        "straits": straits,
        "notes": lay.notes,
    }


def write_json(lay: Layout, path: str) -> None:
    with open(path, "w") as f:
        json.dump(to_json(lay), f, indent=1)
        f.write("\n")
