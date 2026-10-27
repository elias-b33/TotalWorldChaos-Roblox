"""The custom texture pack: one Roblox MaterialVariant per map material, 1024 px and seamless.

    python3 tools/mapgen/generate.py --only materials

Each material gets assets/textures/hd/<Name>/<Name>_color.png (greyscale, so the part colour tints it: nation
colours in the political view, biome colours on neutral land), <Name>_normal.png (tangent space, OpenGL / +Y up,
as Roblox expects) and <Name>_roughness.png. File names are unique so a Studio bulk import keeps them apart. A lit preview sheet goes to docs/images/materials.jpg.

Everything is built from tileable noise (noise.py), so the textures repeat without seams.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Callable

import numpy as np
from PIL import Image, ImageDraw

from noise import hex_rgb, smoothstep, spectral, worley, wrap_blur

N = 1024

# A field is (albedo, height, roughness), all N x N in [0, 1].
Field = tuple[np.ndarray, np.ndarray, np.ndarray]


@dataclass(frozen=True)
class Material:
    name: str  # MaterialVariant name, "TWC_" + this
    base: str  # Enum.Material it replaces (MapStyle uses the same one)
    studs: int  # StudsPerTile
    bump: float  # normal map strength
    tint: str  # preview colour (a biome colour from MapStyle)
    recipe: Callable[[int], Field]


def unit(a: np.ndarray) -> np.ndarray:
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / (hi - lo) if hi > lo else np.zeros_like(a)


def lift(albedo: np.ndarray, mean: float = 0.8) -> np.ndarray:
    """Scale the albedo so its mean is `mean`: tinting by the part colour then keeps nation colours bright."""
    return np.clip(albedo * (mean / max(float(albedo.mean()), 1e-6)), 0.0, 1.0)


def cell_values(ids: np.ndarray, seed: int, lo: float = 0.0, hi: float = 1.0) -> np.ndarray:
    """A random value per Worley cell."""
    vals = np.random.default_rng(seed).uniform(lo, hi, int(ids.max()) + 1)
    return vals[ids]


def domes(grid: int, seed: int, rmin: float, rmax: float, keep: float = 1.0, jitter: float = 0.9) -> np.ndarray:
    """Round bumps (tree crowns, pebbles) on a jittered grid; radius in cell units."""
    f1, _, ids = worley(N, grid, seed, jitter=jitter)
    r = cell_values(ids, seed + 1, rmin, rmax)
    alive = cell_values(ids, seed + 2) < keep
    return np.where(alive, np.sqrt(np.clip(1.0 - (f1 / r) ** 2, 0.0, 1.0)), 0.0)


def cells(cols: int, rows: int, seed: int, jitter: float = 0.8, hex_rows: bool = False):
    """Tileable Worley noise on a cols x rows grid of (possibly long) cells; distances in cell units.

    hex_rows shifts every other row by half a cell, which with rows ~ 1.15 x cols gives near-hexagonal cells
    (rows must then be even). Returns f1, f2, ids, vx, vy (offset from the nearest point, in cell units).
    """
    r = np.random.default_rng(seed)
    pts = 0.5 + (r.random((rows, cols, 2)) - 0.5) * jitter
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64) + 0.5
    gx = xx / N * cols
    gy = yy / N * rows
    cy = np.floor(gy).astype(int)
    f1 = np.full((N, N), np.inf)
    f2 = np.full((N, N), np.inf)
    ids = np.zeros((N, N), dtype=np.int64)
    vx = np.zeros((N, N))
    vy = np.zeros((N, N))
    for dy in (-1, 0, 1):
        uy = cy + dy
        wy = uy % rows
        shift = 0.5 * (wy % 2) if hex_rows else 0.0
        cx = np.floor(gx - shift).astype(int)
        for dx in (-1, 0, 1):
            ux = cx + dx
            wx = ux % cols
            px = ux + shift + pts[wy, wx, 0]
            py = uy + pts[wy, wx, 1]
            ox, oy = gx - px, gy - py
            d = np.hypot(ox, oy)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ids = np.where(closer, wy * cols + wx, ids)
            vx = np.where(closer, ox, vx)
            vy = np.where(closer, oy, vy)
            f1 = np.where(closer, d, f1)
    return f1, f2, ids, vx, vy


def strokes(seed: int, length: int = 9, fine: float = 160.0) -> np.ndarray:
    """Grass-like strokes: fine noise smeared along a slowly turning direction field (line integral convolution)."""
    base = spectral(N, seed, beta=0.2, fmin=fine)
    angle = spectral(N, seed + 1, beta=3.0, fmin=1, fmax=6) * 2.4 + 0.4
    dx, dy = np.cos(angle), np.sin(angle)
    yy, xx = np.mgrid[0:N, 0:N]
    acc = np.zeros((N, N))
    for k in range(-length, length + 1):
        sx = (xx + np.rint(dx * k)).astype(int) % N
        sy = (yy + np.rint(dy * k)).astype(int) % N
        acc += base[sy, sx]
    return unit(acc)


def edges(f1: np.ndarray, f2: np.ndarray, width: float) -> np.ndarray:
    """0 on Worley cell borders, 1 inside cells."""
    return smoothstep(0.0, width, f2 - f1)


# ------------------------------------------------------------------------------------------------- recipes


def grass(seed: int) -> Field:
    blades = strokes(seed, length=7) ** 1.4
    patch = spectral(N, seed + 2, beta=2.4, fmin=2, fmax=20)
    flowers = (domes(90, seed + 3, 0.2, 0.32, keep=0.06) > 0.3).astype(float)
    h = 0.75 * blades + 0.25 * patch
    albedo = (0.55 + 0.45 * blades) * (0.9 + 0.15 * (patch - 0.5)) + 0.25 * flowers
    rough = 0.8 + 0.15 * (1 - blades)
    return lift(albedo), unit(h), rough


def forest(seed: int) -> Field:
    big = domes(18, seed, 0.5, 0.8)
    small = domes(29, seed + 30, 0.4, 0.7, keep=0.85)
    crowns = np.maximum(big, small * 0.85)
    leaves = spectral(N, seed + 40, beta=0.9, fmin=90)
    cover = crowns > 0.02
    h = crowns + 0.12 * leaves * cover
    albedo = np.where(cover, 0.42 + 0.45 * crowns**0.7 + 0.18 * (leaves - 0.5), 0.18)
    rough = np.where(cover, 0.78, 0.95)
    return lift(albedo, 0.72), unit(h), rough


def sand(seed: int) -> Field:
    yy, xx = np.mgrid[0:N, 0:N] / N
    warp = spectral(N, seed, beta=3.0, fmin=1, fmax=8)
    phase = 2 * np.pi * (36 * xx + 11 * yy) + 7.0 * warp
    ripple = (0.5 + 0.5 * np.sin(phase)) ** 1.6
    dunes = spectral(N, seed + 5, beta=3.2, fmin=1, fmax=6)
    grains = spectral(N, seed + 6, beta=0.3, fmin=200)
    h = 0.55 * dunes + 0.3 * ripple + 0.15 * grains
    albedo = 0.8 + 0.1 * (ripple - 0.5) + 0.08 * (dunes - 0.5) + 0.08 * (grains - 0.5)
    return lift(albedo, 0.85), unit(h), 0.93 + 0.05 * grains


def ground(seed: int) -> Field:
    soil = spectral(N, seed, beta=1.6, fmin=4, fmax=160)
    f1, f2, ids, _, _ = cells(36, 36, seed + 10, jitter=0.9)
    keep = cell_values(ids, seed + 11) < 0.2
    lumpy = f1 + 0.25 * (spectral(N, seed + 13, beta=2.0, fmin=30, fmax=120) - 0.5)
    stone = np.where(keep, smoothstep(0.38, 0.22, lumpy), 0.0)  # irregular flat pebbles
    tone = cell_values(ids, seed + 12, 0.7, 1.0)
    grassy = smoothstep(0.45, 0.65, spectral(N, seed + 20, beta=2.2, fmin=2, fmax=16))
    blades = strokes(seed + 30, length=5)
    h = 0.45 * soil + 0.2 * stone + 0.35 * grassy * blades
    albedo = (0.5 + 0.3 * soil) * (1 - stone) + stone * tone * 0.95
    albedo = albedo * (1 - 0.25 * grassy) + grassy * 0.3 * blades
    rough = 0.92 - 0.3 * stone
    return lift(albedo, 0.72), unit(h), rough


def sandstone(seed: int) -> Field:
    yy, _ = np.mgrid[0:N, 0:N] / N
    warp = spectral(N, seed, beta=2.8, fmin=1, fmax=10)
    strata = 0.5 + 0.5 * np.sin(2 * np.pi * (9 * yy) + 5.0 * warp)
    f1, f2, ids = worley(N, 12, seed + 3, jitter=0.8)
    plate = cell_values(ids, seed + 4, 0.0, 1.0)
    crack = edges(f1, f2, 0.05)
    terrace = np.floor((0.6 * warp + 0.4 * plate) * 5) / 5
    h = (0.5 * terrace + 0.3 * strata + 0.2 * plate) * (0.4 + 0.6 * crack)
    albedo = (0.62 + 0.22 * strata + 0.1 * plate) * (0.7 + 0.3 * crack)
    return lift(albedo, 0.78), unit(h), 0.8 + 0.15 * (1 - crack)


def rock(seed: int) -> Field:
    # stylised low-poly rock: every cell is a tilted facet, with dark cracks between them
    f1, f2, ids, vx, vy = worley(N, 7, seed, jitter=0.9, vectors=True)
    a = cell_values(ids, seed + 1, -0.9, 0.9)
    b = cell_values(ids, seed + 2, -0.9, 0.9)
    c = cell_values(ids, seed + 3, 0.2, 0.8)
    facet = c + a * vx + b * vy
    crack = edges(f1, f2, 0.05)
    grit = spectral(N, seed + 4, beta=1.0, fmin=60)
    h = (0.8 * facet + 0.2 * grit) * (0.3 + 0.7 * crack)
    tone = cell_values(ids, seed + 5, 0.55, 1.0)
    albedo = tone * (0.6 + 0.25 * grit) * (0.3 + 0.7 * crack) * (0.75 + 0.35 * facet)
    return lift(albedo, 0.7), unit(h), 0.72 + 0.2 * (1 - crack)


def snow(seed: int) -> Field:
    drifts = spectral(N, seed, beta=3.2, fmin=1, fmax=12, stretch=(2.5, 1.0))
    fine = spectral(N, seed + 1, beta=1.2, fmin=50)
    sparkle = (np.random.default_rng(seed + 2).random((N, N)) > 0.997).astype(float)
    sparkle = np.maximum(sparkle, wrap_blur(sparkle, 1) * 2)
    h = 0.8 * drifts + 0.2 * fine
    albedo = 0.9 + 0.06 * (h - 0.5) + 0.1 * np.clip(sparkle, 0, 1)
    rough = 0.55 - 0.35 * np.clip(sparkle, 0, 1)
    return np.clip(albedo, 0, 1), unit(h), rough


def ash(seed: int) -> Field:
    f1, f2, ids = worley(N, 8, seed, jitter=0.85)
    crack = edges(f1, f2, 0.09)
    plate = cell_values(ids, seed + 1, 0.0, 1.0)
    grit = spectral(N, seed + 2, beta=1.1, fmin=40)
    h = (0.5 + 0.3 * plate + 0.2 * grit) * crack * (1 - 0.3 * f1)
    albedo = (0.55 + 0.25 * grit + 0.1 * plate) * (0.15 + 0.85 * crack)
    return lift(albedo, 0.6), unit(h), 0.85 - 0.3 * (1 - crack)


def marble(seed: int) -> Field:
    # paving: running-bond flagstones with worn bevels and faint veins
    rows, cols = 6, 4
    yy, xx = np.mgrid[0:N, 0:N] / N
    row = np.floor(yy * rows)
    u = xx * cols + 0.5 * (row % 2)
    col = np.floor(u) % cols
    du = np.minimum(u - np.floor(u), np.ceil(u) - u) / cols * N
    dv = np.minimum(yy * rows - row, row + 1 - yy * rows) / rows * N
    bevel = smoothstep(2.0, 14.0, np.minimum(du, dv))
    stone = (row * cols + col).astype(int)
    tone = np.random.default_rng(seed).uniform(0.82, 1.0, rows * cols)[stone]
    warp = spectral(N, seed + 1, beta=2.6, fmin=1, fmax=10)
    vein = np.abs(np.sin(2 * np.pi * (3 * xx + 2 * yy) + 9.0 * warp))
    veins = 1 - 0.18 * (1 - smoothstep(0.0, 0.06, vein))
    wear = spectral(N, seed + 2, beta=1.6, fmin=8)
    h = bevel * (0.85 + 0.15 * wear)
    albedo = tone * veins * (0.35 + 0.65 * bevel) * (0.92 + 0.08 * wear)
    rough = 0.35 + 0.5 * (1 - bevel) + 0.1 * wear
    return lift(albedo, 0.82), unit(h), rough


def slate(seed: int) -> Field:
    # overlapping flat plates, longer than wide, each rising towards its lower edge like shingles
    f1, f2, ids, vx, vy = cells(7, 18, seed, jitter=0.7)
    lip = edges(f1, f2, 0.12)
    tilt = cell_values(ids, seed + 1, 0.3, 0.8)
    base = cell_values(ids, seed + 2, 0.0, 0.5)
    grit = spectral(N, seed + 3, beta=1.0, fmin=70)
    h = (base + tilt * (vy + 0.5)) * (0.3 + 0.7 * lip) + 0.05 * grit
    tone = cell_values(ids, seed + 4, 0.7, 1.0)
    albedo = tone * (0.6 + 0.25 * grit) * (0.35 + 0.65 * lip)
    return lift(albedo, 0.72), unit(h), 0.65 + 0.25 * grit


def basalt(seed: int) -> Field:
    # columns: near-hexagonal cells with flat tops at different heights
    f1, f2, ids, _, _ = cells(14, 16, seed, jitter=0.15, hex_rows=True)
    top = cell_values(ids, seed + 1, 0.3, 1.0)
    rim = edges(f1, f2, 0.1)
    grit = spectral(N, seed + 2, beta=1.0, fmin=60)
    h = top * (0.35 + 0.65 * rim) + 0.05 * grit
    albedo = (0.55 + 0.25 * top + 0.15 * grit) * (0.25 + 0.75 * rim)
    return lift(albedo, 0.62), unit(h), 0.6 + 0.3 * (1 - rim)


MATERIALS = [
    Material("Grass", "Grass", 64, 5.0, "#6f9a3c", grass),
    Material("Forest", "LeafyGrass", 40, 9.0, "#3f7a2e", forest),
    Material("Sand", "Sand", 64, 4.0, "#dcb377", sand),
    Material("Ground", "Ground", 48, 6.0, "#7b8a46", ground),
    Material("Sandstone", "Sandstone", 64, 7.0, "#b08d5c", sandstone),
    Material("Rock", "Rock", 48, 9.0, "#7a756d", rock),
    Material("Snow", "Snow", 64, 3.0, "#e8f0f5", snow),
    Material("Ash", "CrackedLava", 48, 7.0, "#5a4a50", ash),
    Material("Marble", "Marble", 48, 6.0, "#e6dfcf", marble),
    Material("Slate", "Slate", 48, 8.0, "#8a84a0", slate),
    Material("Basalt", "Basalt", 40, 8.0, "#4a5070", basalt),
]


# ------------------------------------------------------------------------------------------------- output


def normal_map(h: np.ndarray, strength: float) -> np.ndarray:
    """Tangent-space normals from a height field, OpenGL convention (green = up in the image)."""
    s = strength * N / 256.0
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    grow = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5  # down the image
    n = np.stack([-gx * s, grow * s, np.ones_like(h)], axis=-1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def lit(albedo: np.ndarray, normals: np.ndarray, tint: str) -> np.ndarray:
    """Preview: tinted albedo lit by a sun from the top-left."""
    sun = np.array([-0.45, 0.5, 0.74])
    sun /= np.linalg.norm(sun)
    lam = np.clip(normals @ sun, 0.0, 1.0)
    light = 0.35 + 0.75 * lam
    return np.clip(albedo[..., None] * np.array(hex_rgb(tint)) * light[..., None] * 1.25, 0, 1)


def build(out_dir: str, sheet_path: str, font) -> None:
    cell = 256
    cols = 4
    rows = (len(MATERIALS) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 26)), (18, 18, 22))
    d = ImageDraw.Draw(sheet)
    for i, m in enumerate(MATERIALS):
        albedo, height, rough = m.recipe(1000 + i * 97)
        normals = normal_map(height, m.bump)
        folder = os.path.join(out_dir, m.name)
        os.makedirs(folder, exist_ok=True)
        Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8), "L").save(
            os.path.join(folder, f"{m.name}_color.png"), optimize=True
        )
        Image.fromarray(((normals * 0.5 + 0.5) * 255).astype(np.uint8), "RGB").save(
            os.path.join(folder, f"{m.name}_normal.png"), optimize=True
        )
        Image.fromarray((np.clip(rough, 0, 1) * 255).astype(np.uint8), "L").save(
            os.path.join(folder, f"{m.name}_roughness.png"), optimize=True
        )
        preview = lit(np.tile(albedo, (2, 2)), np.tile(normals, (2, 2, 1)), m.tint)
        img = Image.fromarray((preview * 255).astype(np.uint8), "RGB").resize((cell, cell), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 26)
        sheet.paste(img, (x, y + 26))
        d.text((x + 6, y + 4), f"TWC_{m.name} · {m.base}", font=font, fill=(235, 235, 235))
        print(f"material: TWC_{m.name}", flush=True)
    os.makedirs(os.path.dirname(sheet_path), exist_ok=True)
    sheet.save(sheet_path, quality=90, optimize=True)
