"""Eldmoor: a fantasy continent built for readable fights.

Ten home regions ring the Crownlands, a rich neutral heartland behind the
Dragonspine mountains. The Dragonspine has three passes, so the centre is
always contested through a few chokepoints. The Corsair Isles and the Isle of
Mists play like Britain and Japan on the Earth map: safe to start, but
slow to expand from.
"""

from __future__ import annotations

import math

import numpy as np

from layout import (
    Layout,
    Seed,
    assign_start_territories,
    auto_connect,
    balance_start_development,
    build_regions,
    components,
    finalize,
)

W, H = 2048, 1024
TARGET = 146  # provinces, mountains included

# (cx, cy, rx, ry, weight) gaussian blobs; CARVE cuts bays and the Moonmere lake
BLOBS = [
    (1010, 500, 560, 330, 1.0),  # heartland
    (900, 190, 330, 130, 0.9),  # Frostmarch
    (560, 250, 200, 140, 0.85),  # Wyrmcoast
    (470, 520, 230, 210, 1.0),  # Greenvale
    (600, 770, 190, 120, 0.8),  # Saltmarsh
    (900, 845, 330, 120, 0.9),  # Sunscorch
    (1340, 800, 240, 140, 0.9),  # Ashen Dominion
    (1500, 520, 260, 230, 1.0),  # Elderwood
    (1360, 250, 240, 150, 0.9),  # Ironholds
]

# islands are kept apart from the mainland by a channel
ISLES = [
    (215, 780, 90, 60, 0.95),  # Corsair Isles
    (330, 905, 95, 52, 0.95),
    (140, 920, 62, 42, 0.9),
    (110, 680, 58, 46, 0.9),
    (1830, 270, 150, 115, 1.0),  # Isle of Mists
    (1760, 150, 60, 42, 0.85),
    (1880, 710, 82, 70, 0.95),  # Sunrise Isle
]

CARVE = [
    (1010, 470, 62, 44, -1.7),  # Moonmere
    (1140, 115, 95, 72, -1.0),
    (1130, 955, 105, 85, -1.0),
    (330, 660, 82, 52, -0.9),
    (720, 85, 85, 62, -0.8),
]

CROWN_CENTER = (1010, 480)
SPINE_RX, SPINE_RY = 300, 215
SPINE_ARCS = [(190, 250), (300, 380), (70, 140)]  # degrees, 0 = east, 90 = south
VOLCANO = ("Mount Cinder", 1365, 790)

# name, centre, biome mix, nation (None = neutral zone)
ZONES = [
    ("Frostmarch", (900, 170), {"frostfields": 0.85, "highlands": 0.15}, "Frostmarch"),
    ("Wyrmcoast", (560, 240), {"highlands": 0.45, "meadow": 0.3, "wildwood": 0.25}, "Wyrmcoast"),
    ("Greenvale", (470, 510), {"meadow": 0.65, "wildwood": 0.2, "highlands": 0.15}, "Greenvale"),
    ("Saltmarsh", (630, 770), {"meadow": 0.6, "wildwood": 0.3, "highlands": 0.1}, "Saltmarsh"),
    ("Corsair Isles", (210, 810), {"meadow": 0.6, "highlands": 0.25, "wildwood": 0.15}, "Corsairs"),
    ("Sunscorch", (900, 850), {"dunes": 0.8, "highlands": 0.2}, "Sunscorch"),
    ("Ashen Dominion", (1340, 800), {"ashlands": 0.75, "dunes": 0.25}, "Ashen Dominion"),
    ("Elderwood", (1500, 520), {"wildwood": 0.75, "meadow": 0.25}, "Elderwood"),
    ("Ironholds", (1360, 250), {"highlands": 0.5, "frostfields": 0.3, "wildwood": 0.2}, "Ironholds"),
    ("Isle of Mists", (1830, 260), {"wildwood": 0.6, "meadow": 0.4}, "Mistborn"),
    ("Crownlands", CROWN_CENTER, {"meadow": 0.8, "highlands": 0.2}, None),
]

NAME_PARTS = {
    "frostfields": (["Frost", "Rime", "Winter", "Snow", "Hoar", "Ice", "Cold", "Pale"], ["hold", "march", "fell", "reach", "gard", "mere", "haven", "watch"]),
    "meadow": (["Green", "Bright", "Oak", "Barley", "Honey", "Mill", "Amber", "Rose", "Clover", "Fair"], ["vale", "ford", "field", "wick", "dale", "stead", "shire", "brook", "meadow", "bury"]),
    "wildwood": (["Elder", "Moon", "Silver", "Thorn", "Willow", "Fae", "Glimmer", "Mist", "Briar", "Dusk"], ["wood", "glade", "grove", "hollow", "bough", "shade", "thicket", "root"]),
    "highlands": (["Stone", "Crag", "Iron", "Grey", "High", "Wolf", "Storm", "Raven", "Heather"], ["moor", "tor", "crest", "ridge", "heath", "barrow", "cairn", "fell"]),
    "ashlands": (["Ash", "Cinder", "Ember", "Soot", "Char", "Brimstone", "Smoke", "Slag"], ["waste", "reach", "maw", "scar", "pit", "rift", "gate", "forge"]),
    "dunes": (["Sun", "Gold", "Dust", "Sand", "Mirage", "Scorch", "Dune", "Amber"], ["sea", "rest", "well", "reach", "spire", "haven", "drift", "oasis"]),
    "peaks": (["Dragon", "Wyrm", "Titan", "Skull", "Thunder", "Giant", "Grim", "Eagle"], ["fang", "horn", "peak", "spire", "tooth", "crown", "spine", "talon"]),
}

TERRAIN = {
    "meadow": "Plains", "frostfields": "Plains", "dunes": "Plains",
    "wildwood": "Forest",
    "highlands": "Hills", "ashlands": "Hills",
    "peaks": "Mountain",
}


def land_mask() -> np.ndarray:
    from noise import spectral
    from render import box_blur

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    noise = (spectral((H, W), 404, beta=2.0, fmin=3, fmax=90) - 0.5) * 0.42
    margin = np.clip(np.minimum.reduce([xx, W - 1 - xx, yy, H - 1 - yy]) / 40.0, 0, 1)

    def field(blobs):
        f = np.zeros((H, W))
        for cx, cy, rx, ry, w in blobs:
            f += w * np.exp(-(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2))
        return f

    carve = field(CARVE)
    main = (field(BLOBS) + carve + noise) * margin > 0.5
    isles = (field(ISLES) + carve + noise) * margin > 0.5
    channel = box_blur(main.astype(np.float64), 14) > 0.02
    land = main | (isles & ~channel)
    # drop specks too small to hold a province
    comp = components(np.where(land, 0, -1))
    sizes = np.bincount(comp[comp >= 0])
    return land & (comp >= 0) & (sizes[np.maximum(comp, 0)] >= 2500)


def spine_points(step: float) -> list[tuple[float, float]]:
    pts = []
    for a0, a1 in SPINE_ARCS:
        # walk the arc at roughly even pixel spacing
        a = float(a0)
        while a <= a1 + 1e-6:
            r = math.radians(a)
            pts.append((CROWN_CENTER[0] + SPINE_RX * math.cos(r), CROWN_CENTER[1] + SPINE_RY * math.sin(r)))
            dx, dy = -SPINE_RX * math.sin(r), SPINE_RY * math.cos(r)
            a += math.degrees(step / math.hypot(dx, dy))
    return pts


def poisson(land: np.ndarray, r: float, fixed: list[tuple[float, float]], seed: int) -> list[tuple[float, float]]:
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(land)
    order = rng.permutation(len(xs))[:60000]
    pts = list(fixed)
    arr = np.array(pts) if pts else np.zeros((0, 2))
    out = []
    for k in order:
        x, y = float(xs[k]), float(ys[k])
        if len(arr) and ((arr[:, 0] - x) ** 2 + (arr[:, 1] - y) ** 2).min() < r * r:
            continue
        out.append((x, y))
        arr = np.vstack([arr, [x, y]])
    return out


def zone_of(x: float, y: float) -> int:
    cx, cy = CROWN_CENTER
    if ((x - cx) / (SPINE_RX * 0.95)) ** 2 + ((y - cy) / (SPINE_RY * 0.95)) ** 2 < 1:
        return len(ZONES) - 1
    best, bi = 1e18, 0
    for i, (_, (zx, zy), _, _) in enumerate(ZONES[:-1]):
        d = (x - zx) ** 2 + (y - zy) ** 2
        if d < best:
            best, bi = d, i
    return bi


def build() -> Layout:
    land = land_mask()
    name_rng = np.random.default_rng(7)  # names and biomes draw from separate streams,
    biome_rng = np.random.default_rng(8)  # so renaming never reshuffles terrain
    # mountain seeds along the Dragonspine arcs, plus Mount Cinder
    lo, hi = 40.0, 90.0
    for _ in range(18):  # binary search the spacing that gives TARGET provinces
        r = (lo + hi) / 2
        mountains = spine_points(r * 0.95) + [VOLCANO[1:]]
        others = poisson(land, r, mountains, seed=11)
        if len(mountains) + len(others) > TARGET:
            lo = r
        else:
            hi = r
    r = hi
    mountains = spine_points(r * 0.95) + [VOLCANO[1:]]
    others = poisson(land, r, mountains, seed=11)

    used: set[str] = {z[0] for z in ZONES} | {z[3] for z in ZONES if z[3]}  # keep nation and region names unique

    def name_for(biome: str) -> str:
        pre, suf = NAME_PARTS[biome]
        for _ in range(200):
            n = pre[name_rng.integers(len(pre))] + suf[name_rng.integers(len(suf))]
            if n not in used:
                used.add(n)
                return n
        raise RuntimeError("ran out of names")

    seeds: list[Seed] = []
    for i, (x, y) in enumerate(mountains):
        if i == len(mountains) - 1:
            seeds.append(Seed(VOLCANO[0], x, y, "peaks"))
            used.add(VOLCANO[0])
        else:
            seeds.append(Seed(name_for("peaks"), x, y, "peaks"))
    for x, y in others:
        z = ZONES[zone_of(x, y)]
        mix = z[2]
        biome = biome_rng.choice(list(mix.keys()), p=list(mix.values()))
        s = Seed(name_for(str(biome)), x, y, str(biome))
        if z[3] is None:  # Crownlands: rich and well defended
            s.dev = 4 if biome == "meadow" else 3
            s.garrison = 3000
        seeds.append(s)
    # capitals: the passable seed nearest each zone's centre
    for zname, (zx, zy), _, nation in ZONES:
        if nation is None:
            continue
        cands = [s for s in seeds if s.biome != "peaks" and zone_of(s.x, s.y) == ZONES.index(next(z for z in ZONES if z[0] == zname))]
        cap = min(cands, key=lambda s: (s.x - zx) ** 2 + (s.y - zy) ** 2)
        cap.nation = nation
        if cap.biome in ("dunes", "frostfields", "ashlands"):
            cap.dev = 3
    notes: list[str] = [f"province spacing {r:.1f}px"]
    labels, seeds = build_regions(land, seeds, notes)
    lay = Layout("eldmoor", "Eldmoor", "fantasy", W, H, labels, land, seeds, TERRAIN, notes=notes)
    finalize(lay)
    auto_connect(lay)
    extra_straits(lay)
    assign_start_territories(lay)
    balance_start_development(lay)
    return lay


def extra_straits(lay: Layout) -> None:
    """Second crossings for the island nations, so a single blockade can't seal them in."""
    from layout import add_strait, closest_points, edge_points

    edges = edge_points(lay.labels, len(lay.seeds))
    land_comp = components(np.where(lay.land, 0, -1))
    comp_of = [int(land_comp[s.y, s.x]) for s in lay.seeds]
    main = max(set(comp_of), key=comp_of.count)
    for c in sorted(set(comp_of) - {main}):
        members = [i for i in range(len(lay.seeds)) if comp_of[i] == c and lay.passable(i)]
        links = [st for st in lay.straits if comp_of[st["a"]] == c or comp_of[st["b"]] == c]
        if len(links) >= 2 or not members:
            continue
        linked = {st["a"] for st in links} | {st["b"] for st in links}
        best = (np.inf, None, None, None)
        for a in members:
            for b in range(len(lay.seeds)):
                if comp_of[b] == c or not lay.passable(b) or b in linked:
                    continue
                d, pa, pb = closest_points(edges[a], edges[b])
                if d < best[0]:
                    best = (d, a, b, (pa, pb))
        if best[1] is not None and best[0] < 260:
            add_strait(lay, best[1], best[2], best[3], auto=True)
            lay.notes.append(f"second strait {lay.seeds[best[1]].name} - {lay.seeds[best[2]].name} ({best[0]:.0f}px)")


def background(lay: Layout) -> np.ndarray:
    from noise import mix, ramp, spectral
    from render import box_blur

    sea = ramp(
        0.6 * spectral((H, W), 21, beta=2.2, fmin=2, fmax=50) + 0.4 * spectral((H, W), 22, beta=1.2, fmin=40, stretch=(4, 1)),
        [(0, "#0f5f8a"), (0.5, "#1683ad"), (1, "#2aa6c9")],
    )
    land = lay.land.astype(np.float64)
    near = np.clip(box_blur(land, 8) * 2.5, 0, 1)
    sea = mix(sea, np.broadcast_to(np.array([0.36, 0.78, 0.84]), sea.shape), near * 0.65)
    # classic fantasy-map ripple lines following the coast
    far = box_blur(land, 16)
    lines = np.zeros_like(far)
    for t in (0.18, 0.07, 0.025):
        lines = np.maximum(lines, np.clip(1.0 - np.abs(far - t) / (t * 0.12), 0, 1))
    sea = mix(sea, np.ones_like(sea) * 0.92, lines * (1 - land) * 0.5)
    return sea
