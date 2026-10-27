"""Seamless 512x512 terrain tiles for every biome of the three map themes.

Each biome has a mechanical terrain (Plains, Forest, Hills, Mountain) from the
design doc and a look. The look is cosmetic only, so a desert and a meadow
both play as Plains.

Every tile also gets a greyscale "detail" version: in the Political map mode
the client tints it with the owner's nation colour (Texture.Color3), so map
colour stays the loudest signal while terrain is still visible underneath.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import numpy as np

from noise import hex_rgb, mix, normalize, ramp, ridged, rng, shade, smoothstep, spectral, worley, wrap_blur

N = 512


# ---------------------------------------------------------------- building blocks


def grain(seed: int, fmin: float = 90.0, beta: float = 0.8) -> np.ndarray:
    return spectral(N, seed, beta=beta, fmin=fmin)


def patches(seed: int, fmin: float = 2.0, fmax: float = 24.0, beta: float = 2.2, stretch=(1.0, 1.0)) -> np.ndarray:
    return spectral(N, seed, beta=beta, fmin=fmin, fmax=fmax, stretch=stretch)


def blobs(grid: int, seed: int, rmin: float, rmax: float, keep: float = 1.0, profile: str = "dome"):
    """Round shapes on a jittered grid: tree crowns, shrubs, boulders.

    Returns (height in [0,1], inside mask, per-blob random tone in [0,1]).
    """
    f1, _, ids = worley(N, grid, seed)
    r = rng(seed + 7)
    n = grid * grid
    radius = r.uniform(rmin, rmax, n)[ids]
    present = (r.random(n) < keep)[ids]
    tone = r.random(n)[ids]
    d = f1 / radius
    inside = (d < 1.0) & present
    if profile == "cone":
        h = np.clip(1.0 - d, 0.0, 1.0)
    else:
        h = np.sqrt(np.clip(1.0 - d * d, 0.0, 1.0))
    h = np.where(inside, h, 0.0)
    return h, inside, tone


def pyramids(grid: int, seed: int, rmin: float, rmax: float) -> np.ndarray:
    """Peaks with 4-6 flat faces, so lighting splits them into clear lit and shadowed sides."""
    _, _, ids, vx, vy = worley(N, grid, seed, vectors=True)
    r = rng(seed + 3)
    n = grid * grid
    sides = r.integers(4, 7, n)[ids]
    rot = r.uniform(0, 2 * np.pi, n)[ids]
    radius = r.uniform(rmin, rmax, n)[ids]
    d = np.full((N, N), -np.inf)
    for k in range(6):
        ang = rot + 2 * np.pi * k / sides
        face = vx * np.cos(ang) + vy * np.sin(ang)
        d = np.where(k < sides, np.maximum(d, face), d)
    return np.clip(1.0 - d / (radius * np.cos(np.pi / sides)), 0.0, 1.0)


def drop_shadow(mask: np.ndarray, dx: int, dy: int, soft: int = 1) -> np.ndarray:
    s = np.roll(np.roll(mask.astype(np.float64), dy, axis=0), dx, axis=1)
    if soft:
        s = wrap_blur(s, soft)
    return np.clip(s, 0, 1)


def specks(seed: int, density: float, size: int = 1) -> np.ndarray:
    """Sparse single-pixel (or small) dots, tileable."""
    m = rng(seed).random((N, N)) < density
    if size > 1:
        acc = np.zeros((N, N), dtype=bool)
        for oy in range(size):
            for ox in range(size):
                acc |= np.roll(np.roll(m, oy, 0), ox, 1)
        m = acc
    return m


def stable(s: str) -> int:
    """Deterministic small hash (Python's hash() changes between runs)."""
    return sum(ord(c) * (i + 3) for i, c in enumerate(s)) % 997


def paint(base: np.ndarray, mask: np.ndarray, color: str, alpha: float = 1.0) -> np.ndarray:
    c = np.array(hex_rgb(color))
    return mix(base, np.broadcast_to(c, base.shape), mask.astype(np.float64) * alpha)


# ---------------------------------------------------------------- recipes


def r_grass(seed: int, p: dict) -> np.ndarray:
    t = 0.65 * patches(seed) + 0.35 * grain(seed + 1)
    col = ramp(t, p["ramp"])
    # mown/field stripes for farmland-like looks
    if p.get("fields"):
        f1, f2, ids = worley(N, 5, seed + 2, jitter=0.8)
        tone = rng(seed + 3).random(25)[ids]
        field = ramp(tone, p["fields"])
        edge = smoothstep(0.0, 0.06, f2 - f1)
        col = mix(col, field, 0.45 * edge)
    if p.get("shrubs"):
        h, inside, tone = blobs(16, seed + 4, 0.16, 0.32, keep=p.get("shrub_keep", 0.35))
        col = mix(col, col * 0.75, drop_shadow(inside, 2, 2, soft=2) * (~inside))
        shrub = ramp(tone * 0.5 + h * 0.5, p["shrubs"]) * (0.75 + 0.25 * shade(h * 8.0, 1.0))[..., None]
        col = np.where(inside[..., None], shrub, col)
    for color, density in p.get("flowers", []):
        col = paint(col, specks(seed + stable(color), density, 2), color, 0.9)
    return col


def r_steppe(seed: int, p: dict) -> np.ndarray:
    streak = spectral(N, seed, beta=1.6, fmin=4.0, stretch=(6.0, 1.0))
    t = 0.45 * patches(seed + 1) + 0.35 * streak + 0.2 * grain(seed + 2)
    col = ramp(t, p["ramp"])
    if p.get("shrubs"):
        h, inside, tone = blobs(16, seed + 3, 0.14, 0.28, keep=p.get("shrub_keep", 0.25))
        col = mix(col, col * 0.78, drop_shadow(inside, 2, 2, soft=2) * (~inside))
        shrub = ramp(tone * 0.5 + h * 0.5, p["shrubs"]) * (0.75 + 0.25 * shade(h * 8.0, 1.0))[..., None]
        col = np.where(inside[..., None], shrub, col)
    return col


def r_canopy(seed: int, p: dict) -> np.ndarray:
    ground = ramp(0.6 * patches(seed) + 0.4 * grain(seed + 1), p["ground"])
    height = np.zeros((N, N))
    inside = np.zeros((N, N), dtype=bool)
    tone = np.zeros((N, N))
    for i, (grid, rmin, rmax, keep) in enumerate(p["layers"]):
        h, m, t = blobs(grid, seed + 10 * i + 3, rmin, rmax, keep=keep, profile=p.get("profile", "dome"))
        h = h * (0.75 + 0.25 * t)  # vary crown height so overlaps look natural
        take = h > height
        height = np.where(take, h, height)
        tone = np.where(take, t, tone)
        inside |= m
    cell_px = N / p["layers"][0][0]
    light = shade(height * cell_px * 0.35, 1.0)
    crown = ramp(np.clip(tone * 0.55 + height * 0.45, 0, 1), p["crown"]) * light[..., None]
    shadow = drop_shadow(inside, 3, 3, soft=2) * (~inside)
    ground = mix(ground, ground * 0.45, shadow)
    col = np.where(inside[..., None], crown, ground)
    if p.get("snow"):
        snow = (height > 0.55) & (spectral(N, seed + 50, beta=0.5, fmin=60) > 0.62)
        col = paint(col, snow, p["snow"], 0.75)
    for color, density in p.get("glow", []):
        dots = specks(seed + 99 + stable(color), density, 2)
        halo = wrap_blur(dots.astype(np.float64), 2) * 3.0
        col = col + np.clip(halo, 0, 1)[..., None] * (np.array(hex_rgb(color)) - col) * 0.6
        col = paint(col, dots, color, 1.0)
    return col


def r_dunes(seed: int, p: dict) -> np.ndarray:
    yy, xx = np.mgrid[0:N, 0:N] / N
    warp = patches(seed, fmin=1.0, fmax=6.0) * 2.0 + patches(seed + 1, fmin=2, fmax=10) * 0.6
    k = p.get("waves", 7)
    phase = (xx * 2 + yy * k + warp) % 1.0
    # asymmetric dune profile: long gentle windward slope, short steep lee slope
    h = np.where(phase < 0.75, phase / 0.75, (1.0 - phase) / 0.25)
    h = h * (0.7 + 0.3 * patches(seed + 2))
    light = shade(h * 26.0, 1.0)
    t = 0.55 * h + 0.25 * patches(seed + 3) + 0.2 * grain(seed + 4)
    col = ramp(normalize(t), p["ramp"]) * (0.55 + 0.45 * light)[..., None]
    return col


def r_hills(seed: int, p: dict) -> np.ndarray:
    h = 0.7 * patches(seed, fmin=2, fmax=10, beta=2.6) + 0.3 * patches(seed + 1, fmin=8, fmax=40)
    light = shade(h * 70.0, 1.0)
    t = 0.6 * h + 0.25 * patches(seed + 2, fmin=6) + 0.15 * grain(seed + 3)
    col = ramp(normalize(t), p["ramp"])
    if p.get("terrace"):
        steps = p["terrace"]
        hq = np.floor(h * steps) / steps
        edge = smoothstep(0.0, 0.02, h - hq)
        light = shade(hq * 120.0 + h * 20.0, 1.0)
        col = mix(col * 0.5, col * 1.1, edge)
    col = col * (0.45 + 0.55 * light)[..., None]
    if p.get("shrubs"):
        hh, inside, tone = blobs(16, seed + 5, 0.14, 0.28, keep=p.get("shrub_keep", 0.3))
        col = mix(col, col * 0.78, drop_shadow(inside, 2, 2, soft=2) * (~inside))
        shrub = ramp(tone * 0.5 + hh * 0.5, p["shrubs"]) * (0.75 + 0.25 * shade(hh * 8.0, 1.0))[..., None]
        col = np.where(inside[..., None], shrub, col)
    for color, density in p.get("flowers", []):
        col = paint(col, specks(seed + stable(color), density, 2), color, 0.85)
    return col


def r_mountains(seed: int, p: dict) -> np.ndarray:
    """Faceted peaks: overlapping cones read as mountains at a glance, even when small."""
    height = np.zeros((N, N))
    for i, (grid, rmin, rmax) in enumerate(((4, 0.85, 1.1), (7, 0.7, 0.95))):
        height = np.maximum(height, pyramids(grid, seed + 13 * i, rmin, rmax) * (1.0 - 0.25 * i))
    ridges = spectral(N, seed + 5, beta=2.0, fmin=6, fmax=24)
    h = normalize(height * (0.95 + 0.05 * ridges))
    light = shade(h * 55.0, 1.0)
    rock = ramp(normalize(h * 0.7 + 0.3 * grain(seed + 3)), p["ramp"])
    col = rock * (0.45 + 0.6 * light)[..., None]
    if p.get("snow"):
        line = p.get("snowline", 0.62)
        snow = smoothstep(line, line + 0.02, h + 0.05 * (spectral(N, seed + 4, fmin=16, fmax=48) - 0.5))
        snow_col = np.array(hex_rgb(p["snow"])) * np.clip(0.35 + 0.65 * light, 0, 1.05)[..., None]
        col = mix(col, snow_col, snow)
    for color, width in p.get("veins", []):
        f1, f2, _ = worley(N, 5, seed + 8)
        v = 1.0 - smoothstep(0.0, width, f2 - f1)
        v *= smoothstep(0.45, 0.6, spectral(N, seed + 9, fmin=2, fmax=8))
        glow = wrap_blur(v, 3)
        c = np.array(hex_rgb(color))
        col = col + glow[..., None] * c * 0.7
        col = mix(col, np.broadcast_to(c, col.shape), v * 0.9)
    return col


def r_ice(seed: int, p: dict) -> np.ndarray:
    h = patches(seed, fmin=2, fmax=20)
    light = shade(h * 40.0, 1.0)
    col = ramp(normalize(0.7 * h + 0.3 * grain(seed + 1)), p["ramp"]) * (0.75 + 0.25 * light)[..., None]
    f1, f2, _ = worley(N, 7, seed + 2)
    crack = 1.0 - smoothstep(0.0, 0.035, f2 - f1)
    crack *= spectral(N, seed + 3, fmin=3, fmax=12) > 0.45
    col = mix(col, np.broadcast_to(np.array(hex_rgb(p["crack"])), col.shape), crack * 0.7)
    return col


def r_ash(seed: int, p: dict) -> np.ndarray:
    h = 0.6 * patches(seed, fmin=2, fmax=16) + 0.4 * ridged(patches(seed + 1, fmin=6, fmax=30))
    light = shade(h * 60.0, 1.0)
    col = ramp(normalize(h + 0.2 * grain(seed + 2)), p["ramp"]) * (0.5 + 0.5 * light)[..., None]
    f1, f2, _ = worley(N, 5, seed + 3)
    crack = 1.0 - smoothstep(0.0, 0.05, f2 - f1)
    crack *= spectral(N, seed + 4, fmin=2, fmax=8) > 0.4
    glow = wrap_blur(crack, 4) * 2.5
    lava = np.array(hex_rgb(p["lava"]))
    hot = np.array(hex_rgb(p["hot"]))
    col = col + np.clip(glow, 0, 1)[..., None] * lava * 0.55
    col = mix(col, np.broadcast_to(hot, col.shape), crack)
    return col


def r_crystal(seed: int, p: dict) -> np.ndarray:
    col = r_canopy(seed, p)
    f1, f2, ids = worley(N, 9, seed + 40)
    r = rng(seed + 41)
    keep = (r.random(81) < p.get("crystal_keep", 0.35))[ids]
    size = r.uniform(0.22, 0.34, 81)[ids]
    facet = (f1 < size) & keep
    gem = np.where(facet, 1.0 - f1 / size, 0.0)
    light = shade(gem * 40.0, 1.0)
    tone = np.clip(0.25 + 0.5 * r.random(81)[ids] + 0.35 * (light - 1.0), 0, 1)
    cry = ramp(tone, p["crystal"]) * (0.7 + 0.3 * light)[..., None]
    col = mix(col, col * 0.5, drop_shadow(facet, 3, 3) * (~facet))
    col = np.where(facet[..., None], cry, col)
    return col


def r_ruins(seed: int, p: dict) -> np.ndarray:
    col = r_grass(seed, p)
    yy, xx = np.mgrid[0:N, 0:N]
    cell = 16
    gx, gy = xx % cell, yy % cell
    gap = (gx < 2) | (gy < 2)
    tile_id = (yy // cell) * (N // cell) + (xx // cell)
    r = rng(seed + 9)
    keep_tile = (r.random((N // cell) ** 2) < 0.7)[tile_id]
    region = spectral(N, seed + 10, fmin=3, fmax=10) > 0.56
    stone = keep_tile & region & ~gap
    tone = r.random((N // cell) ** 2)[tile_id]
    stone_col = ramp(0.6 * tone + 0.4 * grain(seed + 11), p["stone"])
    stone_col = stone_col * (0.85 + 0.15 * shade(patches(seed + 12, fmin=8) * 30, 1.0))[..., None]
    col = mix(col, col * 0.6, drop_shadow(stone, 2, 2) * (~stone))
    col = np.where(stone[..., None], stone_col, col)
    return col


def r_water(seed: int, p: dict) -> np.ndarray:
    t = 0.6 * patches(seed, fmin=1, fmax=8) + 0.4 * spectral(N, seed + 1, beta=1.4, fmin=8, stretch=(4.0, 1.0))
    col = ramp(normalize(t), p["ramp"])
    crest = spectral(N, seed + 2, beta=1.2, fmin=12, fmax=60, stretch=(5.0, 1.0))
    crest = smoothstep(0.78, 0.9, crest)
    col = mix(col, np.broadcast_to(np.array(hex_rgb(p["crest"])), col.shape), crest * p.get("crest_alpha", 0.35))
    return col


def r_clouds(seed: int, p: dict) -> np.ndarray:
    a = spectral(N, seed, beta=2.4, fmin=1, fmax=24)
    b = spectral(N, seed + 1, beta=1.8, fmin=6, fmax=60)
    t = normalize(0.75 * a + 0.25 * b)
    col = ramp(t, p["ramp"])
    puff = smoothstep(0.62, 0.85, t)
    light = shade(t * 50.0, 1.0)
    cloud = np.array(hex_rgb(p["cloud"])) * (0.75 + 0.25 * light)[..., None]
    return mix(col, cloud, puff * 0.85)


def r_planks(seed: int, p: dict) -> np.ndarray:
    """Bridge deck: planks run across the bridge (tile repeats along the bridge length)."""
    yy, xx = np.mgrid[0:N, 0:N]
    plank_h = N // 8
    pid = yy // plank_h
    r = rng(seed)
    tone = r.random(8)[pid]
    wood = spectral(N, seed + 1, beta=1.2, fmin=6, stretch=(10.0, 1.0))
    col = ramp(normalize(0.5 * tone + 0.5 * wood), p["ramp"])
    seam = (yy % plank_h) < 4
    col = np.where(seam[..., None], col * 0.35, col)
    nails = ((yy % plank_h) == plank_h // 2) & (((xx + 20) % (N // 2)) < 6)
    col = paint(col, nails, "#2b2620", 0.9)
    return col


RECIPES: dict[str, Callable[[int, dict], np.ndarray]] = {
    "grass": r_grass,
    "steppe": r_steppe,
    "canopy": r_canopy,
    "dunes": r_dunes,
    "hills": r_hills,
    "mountains": r_mountains,
    "ice": r_ice,
    "ash": r_ash,
    "crystal": r_crystal,
    "ruins": r_ruins,
    "water": r_water,
    "clouds": r_clouds,
    "planks": r_planks,
}


@dataclass(frozen=True)
class Biome:
    key: str
    terrain: str  # Plains | Forest | Hills | Mountain | Water | Bridge
    recipe: str
    params: dict
    label: str


def B(key, terrain, recipe, label, **params) -> Biome:
    return Biome(key, terrain, recipe, params, label)


# ---------------------------------------------------------------- themes

EARTH = [
    B("grassland", "Plains", "grass", "Grassland",
      ramp=[(0, "#4d7a2e"), (0.5, "#6f9a3c"), (1, "#9bb85a")],
      fields=[(0, "#7fa043"), (0.5, "#a8a956"), (1, "#c2b46a")], shrubs=[(0, "#2f5a22"), (1, "#4b7a2c")], shrub_keep=0.18),
    B("steppe", "Plains", "steppe", "Steppe",
      ramp=[(0, "#8f8a4a"), (0.5, "#b3a862"), (1, "#d2c486")], shrubs=[(0, "#5f6a35"), (1, "#7d8240")]),
    B("savanna", "Plains", "grass", "Savanna",
      ramp=[(0, "#a78a3e"), (0.5, "#c9a952"), (1, "#dcc27a")], shrubs=[(0, "#47612a"), (1, "#6a7f34")], shrub_keep=0.12),
    B("desert", "Plains", "dunes", "Desert",
      ramp=[(0, "#b98a4e"), (0.5, "#dcb377"), (1, "#f1d9a3")]),
    B("tundra", "Plains", "steppe", "Tundra",
      ramp=[(0, "#6f6f5c"), (0.45, "#8d8a72"), (0.75, "#b3b29e"), (1, "#e8ecef")], shrubs=[(0, "#5b5a44"), (1, "#7a6c4a")]),
    B("forest", "Forest", "canopy", "Forest",
      ground=[(0, "#22351a"), (1, "#36502a")], crown=[(0, "#2c5a24"), (0.5, "#3f7a2e"), (1, "#6e9e42")],
      layers=[(16, 0.55, 0.8, 0.95), (24, 0.4, 0.6, 0.8)]),
    B("taiga", "Forest", "canopy", "Taiga",
      ground=[(0, "#4a4f45"), (1, "#7a8077")], crown=[(0, "#1d4a35"), (0.5, "#2e6646"), (1, "#56886a")],
      layers=[(22, 0.5, 0.68, 0.9), (30, 0.4, 0.55, 0.75)], profile="cone", snow="#e9eef2"),
    B("jungle", "Forest", "canopy", "Jungle",
      ground=[(0, "#143018"), (1, "#24472a")], crown=[(0, "#1f6a2a"), (0.5, "#2f8c34"), (1, "#7cc04a")],
      layers=[(10, 0.6, 0.85, 1.0), (18, 0.5, 0.75, 0.95), (28, 0.4, 0.6, 0.8)]),
    B("hills", "Hills", "hills", "Hills",
      ramp=[(0, "#4c6a2e"), (0.5, "#7b8a46"), (1, "#a9a46a")], shrubs=[(0, "#2d4a1f"), (1, "#476b2a")], shrub_keep=0.25),
    B("drylands", "Hills", "hills", "Dry hills",
      ramp=[(0, "#7e5d3a"), (0.5, "#a88457"), (1, "#cdb084")], shrubs=[(0, "#5d5a33"), (1, "#7b7641")], shrub_keep=0.15),
    B("mountains", "Mountain", "mountains", "Mountains",
      ramp=[(0, "#4a4642"), (0.5, "#76716a"), (1, "#a39d94")], snow="#f4f6f8", snowline=0.7),
    B("ice", "Hills", "ice", "Ice sheet",
      ramp=[(0, "#b9cfdc"), (0.6, "#dde9f0"), (1, "#f7fbfd")], crack="#7fa3bd"),
    B("sea", "Water", "water", "Ocean",
      ramp=[(0, "#123a5c"), (0.5, "#1a4d74"), (1, "#25618c")], crest="#6f9fc4"),
]

FANTASY = [
    B("meadow", "Plains", "grass", "Meadow",
      ramp=[(0, "#4f9a34"), (0.5, "#74bd45"), (1, "#a6d85f")],
      shrubs=[(0, "#2f6e2a"), (1, "#4f9437")], shrub_keep=0.2,
      flowers=[("#ffe066", 0.0015), ("#ffffff", 0.0012), ("#ff7eb6", 0.0008)]),
    B("frostfields", "Plains", "steppe", "Frostfields",
      ramp=[(0, "#9fb4c8"), (0.4, "#c9d8e6"), (1, "#f4f8fc")], shrubs=[(0, "#8fb0bf"), (1, "#c3dbe6")], shrub_keep=0.2),
    B("dunes", "Plains", "dunes", "Sunscorch dunes",
      ramp=[(0, "#c46a2c"), (0.5, "#e89a45"), (1, "#ffd27a")], waves=6),
    B("wildwood", "Forest", "canopy", "Wildwood",
      ground=[(0, "#0f2a2a"), (1, "#1d4040")], crown=[(0, "#11594a"), (0.5, "#1f8a63"), (1, "#5cd08a")],
      layers=[(12, 0.6, 0.85, 1.0), (20, 0.45, 0.7, 0.85)], glow=[("#b8fff0", 0.0009), ("#ffe58a", 0.0006)]),
    B("highlands", "Hills", "hills", "Heather highlands",
      ramp=[(0, "#4d6b45"), (0.5, "#7c9a5e"), (1, "#b6c48a")], shrubs=[(0, "#7a4a9a"), (1, "#b07ad0")], shrub_keep=0.55),
    B("ashlands", "Hills", "ash", "Ashlands",
      ramp=[(0, "#1f1b1d"), (0.5, "#3a3236"), (1, "#5c5054")], lava="#ff5a1f", hot="#ffc24a"),
    B("peaks", "Mountain", "mountains", "Dragonspine peaks",
      ramp=[(0, "#3b4256"), (0.5, "#646d86"), (1, "#97a0b8")], snow="#ffffff", snowline=0.66),
    B("sea", "Water", "water", "Sea",
      ramp=[(0, "#0f5f8a"), (0.5, "#1683ad"), (1, "#2aa6c9")], crest="#bfeffa", crest_alpha=0.45),
]

SKY = [
    B("skymeadow", "Plains", "grass", "Sky meadow",
      ramp=[(0, "#5cb44a"), (0.5, "#86d35a"), (1, "#c2ec7e")], shrubs=[(0, "#3c8f48"), (1, "#61b660")], shrub_keep=0.15,
      flowers=[("#ffffff", 0.002), ("#c9b8ff", 0.001)]),
    B("heartruins", "Plains", "ruins", "Heartstone ruins",
      ramp=[(0, "#a99a3c"), (0.5, "#cdbb55"), (1, "#eadb85")], stone=[(0, "#cfc6b4"), (0.5, "#e6dfcf"), (1, "#fffaf0")]),
    B("crystalgrove", "Forest", "crystal", "Crystal grove",
      ground=[(0, "#2d1f45"), (1, "#45306a")], crown=[(0, "#6a3592"), (0.5, "#9a52b4"), (1, "#e08fd8")],
      layers=[(14, 0.55, 0.8, 0.95), (22, 0.4, 0.6, 0.7)], crystal_keep=0.18, crystal=[(0, "#3fb6d8"), (0.5, "#8ff0ff"), (1, "#ffffff")]),
    B("crags", "Hills", "hills", "Floating crags",
      ramp=[(0, "#5d5873"), (0.5, "#8a84a0"), (1, "#bdb7cf")], terrace=6, shrubs=[(0, "#3e8a5a"), (1, "#6cbf7a")], shrub_keep=0.2),
    B("stormspire", "Mountain", "mountains", "Storm spire",
      ramp=[(0, "#1d2033"), (0.5, "#33384f"), (1, "#525a78")], veins=[("#6fe6ff", 0.04)]),
    B("void", "Water", "clouds", "Sky void",
      ramp=[(0, "#2a2f6b"), (0.5, "#3d4a8f"), (1, "#5d6fb3")], cloud="#e9e6ff"),
    B("bridge", "Bridge", "planks", "Rope bridge",
      ramp=[(0, "#5a3b22"), (0.5, "#7d5532"), (1, "#a6774a")]),
]

THEMES = {"earth": EARTH, "fantasy": FANTASY, "sky": SKY}


def biome_map(theme: str) -> dict[str, Biome]:
    return {b.key: b for b in THEMES[theme]}


_CACHE: dict[tuple[str, str], np.ndarray] = {}


def make_tile(theme: str, key: str) -> np.ndarray:
    """Float RGB tile in [0, 1], cached."""
    ck = (theme, key)
    if ck not in _CACHE:
        b = biome_map(theme)[key]
        seed = sum(ord(c) * (i + 1) for i, c in enumerate(theme + key)) % 100000
        _CACHE[ck] = np.clip(RECIPES[b.recipe](seed, b.params), 0.0, 1.0)
    return _CACHE[ck]


def detail_of(tile: np.ndarray) -> np.ndarray:
    """High-key greyscale for tinting with a nation colour (multiply)."""
    lum = tile @ np.array([0.299, 0.587, 0.114])
    t = normalize(lum, 1, 99)
    return 0.6 + 0.4 * t
