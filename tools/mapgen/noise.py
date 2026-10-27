"""Tileable noise and shading helpers (numpy only).

Everything here wraps around at the edges, so a texture built from these
functions tiles seamlessly in Roblox (Texture instances repeat their image).
"""

from __future__ import annotations

import numpy as np


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def normalize(a: np.ndarray, lo_pct: float = 0.0, hi_pct: float = 100.0) -> np.ndarray:
    lo, hi = np.percentile(a, [lo_pct, hi_pct])
    if hi - lo < 1e-9:
        return np.zeros_like(a)
    return np.clip((a - lo) / (hi - lo), 0.0, 1.0)


def spectral(
    size: int | tuple[int, int],
    seed: int,
    beta: float = 2.0,
    fmin: float = 1.0,
    fmax: float | None = None,
    stretch: tuple[float, float] = (1.0, 1.0),
) -> np.ndarray:
    """Periodic 1/f^beta noise in [0, 1] made by filtering white noise in Fourier space.

    fmin/fmax are in cycles per image. stretch > 1 on an axis makes features longer on that axis.
    """
    h, w = (size, size) if isinstance(size, int) else size
    white = rng(seed).standard_normal((h, w))
    fy = np.fft.fftfreq(h) * h / stretch[1]
    fx = np.fft.rfftfreq(w) * w / stretch[0]
    f = np.sqrt(fy[:, None] ** 2 + fx[None, :] ** 2)
    amp = np.zeros_like(f)
    band = f >= fmin
    if fmax is not None:
        band &= f <= fmax
    amp[band] = f[band] ** (-beta / 2.0)
    out = np.fft.irfft2(np.fft.rfft2(white) * amp, s=(h, w))
    return normalize(out)


def ridged(n: np.ndarray) -> np.ndarray:
    """Sharp ridges where the noise crosses its middle value."""
    return normalize(1.0 - np.abs(n * 2.0 - 1.0)) ** 2


def worley(size: int, grid: int, seed: int, jitter: float = 1.0, vectors: bool = False):
    """Tileable cellular noise on a jittered grid.

    Returns (f1, f2, cell_id) where distances are in cell units; with vectors=True
    also (dx, dy), the offset from the nearest point in cell units.
    """
    r = rng(seed)
    pts = 0.5 + (r.random((grid, grid, 2)) - 0.5) * jitter
    c = size / grid
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64) + 0.5
    cx = (xx // c).astype(int)
    cy = (yy // c).astype(int)
    f1 = np.full((size, size), np.inf)
    f2 = np.full((size, size), np.inf)
    ids = np.zeros((size, size), dtype=np.int64)
    vx = np.zeros((size, size))
    vy = np.zeros((size, size))
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            ux = cx + dx
            uy = cy + dy
            wx = ux % grid
            wy = uy % grid
            px = (ux + pts[wy, wx, 0]) * c
            py = (uy + pts[wy, wx, 1]) * c
            d = np.hypot(xx - px, yy - py) / c
            cid = wy * grid + wx
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            ids = np.where(closer, cid, ids)
            if vectors:
                vx = np.where(closer, (xx - px) / c, vx)
                vy = np.where(closer, (yy - py) / c, vy)
            f1 = np.where(closer, d, f1)
    if vectors:
        return f1, f2, ids, vx, vy
    return f1, f2, ids


def wrap_blur(a: np.ndarray, radius: int) -> np.ndarray:
    """Cheap tileable box blur (two passes approximate a gaussian)."""
    out = a.astype(np.float64)
    for _ in range(2):
        acc = np.zeros_like(out)
        for k in range(-radius, radius + 1):
            acc += np.roll(out, k, axis=0)
        out = acc / (2 * radius + 1)
        acc = np.zeros_like(out)
        for k in range(-radius, radius + 1):
            acc += np.roll(out, k, axis=1)
        out = acc / (2 * radius + 1)
    return out


def shade(height: np.ndarray, strength: float, light=(-1.0, -1.0, 1.4), wrap: bool = True) -> np.ndarray:
    """Lambert lighting of a height field, light from the top-left. Returns ~[0, 1.3]."""
    if wrap:
        gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
        gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    else:
        gy, gx = np.gradient(height)
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(height)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    lx, ly, lz = light
    ln = np.sqrt(lx * lx + ly * ly + lz * lz)
    lam = (nx * lx + ny * ly + nz * lz) / (norm * ln)
    flat = lz / ln
    return np.clip(lam / flat, 0.0, 1.6)


def ramp(t: np.ndarray, stops: list[tuple[float, str]]) -> np.ndarray:
    """Map t in [0, 1] through colour stops [(pos, '#rrggbb'), ...] -> float RGB in [0, 1]."""
    pos = np.array([p for p, _ in stops])
    cols = np.array([hex_rgb(c) for _, c in stops])
    out = np.empty(t.shape + (3,))
    for ch in range(3):
        out[..., ch] = np.interp(t, pos, cols[:, ch])
    return out


def hex_rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def mix(a: np.ndarray, b: np.ndarray, t: np.ndarray) -> np.ndarray:
    if t.ndim == a.ndim - 1:
        t = t[..., None]
    return a * (1.0 - t) + b * t


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
