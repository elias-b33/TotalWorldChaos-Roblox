"""Skyshards: the world after the last god war, shattered into floating islands.

Ten identical home shards circle the Heartstone. Each shard is a ring of 8
provinces around an impassable storm spire, so every nation starts with the
same land, the same terrain and the same number of bridges:

  home Gate      <-> the Heartstone (one bridge each)
  home Windward  <-> drift isle <-> next nation's Leeward

The Heartstone is the prize: 20 rich ruin provinces with strong garrisons
around a central spire. The map is rotationally symmetric, so it is the fair,
competitive map of the three, and the one to balance-test on.

No new rules: islands and bridges are the design doc's "straits".
"""

from __future__ import annotations

import math

import numpy as np

from layout import (
    Layout,
    Seed,
    add_strait,
    assign_start_territories,
    balance_start_development,
    build_regions,
    closest_points,
    edge_points,
    finalize,
)

W, H = 2048, 1536
CX, CY = W / 2, H / 2
RING = 600  # distance of home shards and drift isles from the centre
HOME_R = 105
ISLE_RX, ISLE_RY = 56, 38
HEART_R = 280

NATIONS = ["Aurora", "Zephyr", "Nimbus", "Tempest", "Halo", "Solace", "Ember", "Rime", "Verdance", "Umbra"]
DRIFTS = ["Cinder", "Feather", "Lantern", "Thistle", "Comet", "Willow", "Copper", "Echo", "Ivory", "Storm"]
SANCTUMS = ["Dawn", "Storms", "Stars", "Embers", "Tides", "Echoes", "Crowns", "Thorns", "Mirrors", "Ashes"]

# home shard ring: local angle (0 = away from the Heartstone, 90 = towards the next shard)
HOME_RING = [
    (0, "Landing", "skymeadow"),
    (45, "Meadows", "skymeadow"),
    (90, "Windward", "crags"),
    (135, "Grove", "crystalgrove"),
    (180, "Gate", "crags"),
    (225, "Glade", "crystalgrove"),
    (270, "Leeward", "crags"),
    (315, "Fields", "skymeadow"),
]

TERRAIN = {"skymeadow": "Plains", "heartruins": "Plains", "crystalgrove": "Forest", "crags": "Hills", "stormspire": "Mountain"}


def home_angle(k: int) -> float:
    return math.radians(-90 + 36 * k)


def wobble(phi: np.ndarray, terms: list[tuple[int, float, float]]) -> np.ndarray:
    out = np.ones_like(phi)
    for k, a, p in terms:
        out += a * np.sin(k * phi + p)
    return out


HOME_SHAPE = [(3, 0.035, 1.0), (5, 0.025, 2.1), (7, 0.015, 0.4)]  # same for every shard
ISLE_SHAPE = [(2, 0.04, 0.3), (5, 0.03, 1.7)]


def land_mask() -> np.ndarray:
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    land = np.zeros((H, W), dtype=bool)
    for k in range(10):
        th = home_angle(k)
        for kind, ang, r in (("home", th, HOME_R), ("isle", th + math.radians(18), ISLE_RX)):
            cx, cy = CX + RING * math.cos(ang), CY + RING * math.sin(ang)
            x0, x1 = int(cx - r * 1.3), int(cx + r * 1.3)
            y0, y1 = int(cy - r * 1.3), int(cy + r * 1.3)
            dx, dy = xx[y0:y1, x0:x1] - cx, yy[y0:y1, x0:x1] - cy
            # local frame: u points away from the centre, v along the ring
            u = dx * math.cos(ang) + dy * math.sin(ang)
            v = -dx * math.sin(ang) + dy * math.cos(ang)
            phi = np.arctan2(v, u)
            if kind == "home":
                inside = np.hypot(u, v) < HOME_R * wobble(phi, HOME_SHAPE)
            else:
                inside = np.hypot(u / ISLE_RY, v / ISLE_RX) < wobble(phi, ISLE_SHAPE)
            land[y0:y1, x0:x1] |= inside
    dx, dy = xx - CX, yy - CY
    phi = np.arctan2(dy, dx) - home_angle(0)
    land |= np.hypot(dx, dy) < HEART_R * wobble(phi, [(10, 0.05, 0.0), (20, 0.02, 1.2)])
    return land


def seeds() -> list[Seed]:
    out: list[Seed] = []
    for k, nation in enumerate(NATIONS):
        th = home_angle(k)
        cx, cy = CX + RING * math.cos(th), CY + RING * math.sin(th)
        ux, uy = math.cos(th), math.sin(th)
        vx, vy = -math.sin(th), math.cos(th)
        out.append(Seed(f"{nation} Spire", cx, cy, "stormspire"))
        for a, label, biome in HOME_RING:
            al = math.radians(a)
            r = 0.6 * HOME_R
            x = cx + r * (math.cos(al) * ux + math.sin(al) * vx)
            y = cy + r * (math.cos(al) * uy + math.sin(al) * vy)
            out.append(Seed(f"{nation} {label}", x, y, biome, dev=3 if a == 0 else 2, nation=nation if a == 0 else None))
    for k, drift in enumerate(DRIFTS):
        th = home_angle(k) + math.radians(18)
        cx, cy = CX + RING * math.cos(th), CY + RING * math.sin(th)
        vx, vy = -math.sin(th), math.cos(th)
        for side, label in ((-1, "Rock"), (1, "Reach")):
            out.append(Seed(f"{drift} {label}", cx + side * 0.5 * ISLE_RX * vx, cy + side * 0.5 * ISLE_RX * vy, "skymeadow", dev=2))
    out.append(Seed("Heartstone Spire", CX, CY, "stormspire"))
    for k in range(10):
        th = home_angle(k)
        r = 0.78 * HEART_R
        out.append(Seed(f"{NATIONS[k]} Approach", CX + r * math.cos(th), CY + r * math.sin(th), "heartruins", dev=3, garrison=2000))
        th2 = th + math.radians(18)
        r2 = 0.45 * HEART_R
        out.append(Seed(f"Sanctum of {SANCTUMS[k]}", CX + r2 * math.cos(th2), CY + r2 * math.sin(th2), "heartruins", dev=4, garrison=3000))
    return out


def build() -> Layout:
    land = land_mask()
    notes: list[str] = []
    labels, sd = build_regions(land, seeds(), notes)
    lay = Layout("skyshards", "Skyshards", "sky", W, H, labels, land, sd, TERRAIN, notes=notes)
    finalize(lay)
    idx = {s.name: i for i, s in enumerate(lay.seeds)}
    edges = edge_points(lay.labels, len(lay.seeds))

    def bridge(a: str, b: str) -> None:
        ia, ib = idx[a], idx[b]
        _, pa, pb = closest_points(edges[ia], edges[ib])
        add_strait(lay, ia, ib, (pa, pb))

    for k, nation in enumerate(NATIONS):
        bridge(f"{nation} Gate", f"{nation} Approach")
        bridge(f"{nation} Windward", f"{DRIFTS[k]} Rock")
        bridge(f"{DRIFTS[k]} Reach", f"{NATIONS[(k + 1) % 10]} Leeward")
    assign_start_territories(lay, allowed=lambda slot, q: lay.seeds[q].name.startswith(NATIONS[slot] + " "))
    balance_start_development(lay)
    return lay


def background(lay: Layout) -> np.ndarray:
    from noise import hex_rgb, mix, ramp, smoothstep, spectral
    from render import box_blur

    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    rad = np.hypot(xx - CX, (yy - CY) * 1.2) / (W * 0.62)
    sky = ramp(np.clip(1.0 - rad, 0, 1), [(0, "#141838"), (0.45, "#2b3477"), (0.8, "#4b5cae"), (1, "#6d7fcb")])
    # two layers of drifting cloud far below the islands
    for seed, alpha, lo in ((31, 0.45, 0.5), (32, 0.3, 0.58)):
        c = spectral((H, W), seed, beta=2.8, fmin=2, fmax=36)
        sky = mix(sky, np.broadcast_to(np.array(hex_rgb("#c9c4f2")), sky.shape), smoothstep(lo, lo + 0.25, c) * alpha)
    land = lay.land.astype(np.float64)
    # golden glow from the Heartstone
    glow = box_blur((np.hypot(xx - CX, yy - CY) < HEART_R).astype(np.float64), 60)
    sky = sky + glow[..., None] * np.array(hex_rgb("#ffcf6e")) * 0.35
    # soft shadows the islands cast on the clouds below
    shadow = box_blur(np.roll(np.roll(land, 60, 0), 25, 1), 18)
    sky = sky * (1.0 - 0.45 * shadow)[..., None]
    # rocky undersides: the island silhouette pushed down, with strata bands
    depth = np.zeros((H, W))
    for d in range(1, 34):
        depth = np.where((depth == 0) & np.roll(land, d, 0).astype(bool), d, depth)
    cliff = (depth > 0) & ~lay.land
    t = np.clip(depth / 34.0, 0, 1)
    strata = 0.5 + 0.5 * np.sin(yy * 0.9 + spectral((H, W), 33, fmin=20, fmax=120) * 6)
    rock = ramp(np.clip(0.75 - 0.6 * t + 0.15 * strata, 0, 1), [(0, "#1d1a2b"), (0.5, "#4a4260"), (1, "#7d7396")])
    taper = smoothstep(0.75, 1.0, t)  # undersides fade into the haze
    rock = mix(rock, sky, taper)
    return np.where(cliff[..., None], rock, np.clip(sky, 0, 1))
