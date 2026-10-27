"""Render map images from a Layout: terrain overview, political preview, id map, atlas, vote card."""

from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from layout import Layout
from noise import hex_rgb, mix
from tiles import biome_map, detail_of, make_tile

# Nation palette, indexed by Nation.colorIndex (1-based): WorldBox's kingdom colours, the same as the
# client's Palette.luau (docs/MAPS.md "Art direction").
PALETTE = [
    "#e6194b",  # 1 red
    "#6c89f6",  # 2 blue
    "#ffe119",  # 3 yellow
    "#911eb4",  # 4 purple
    "#f58231",  # 5 orange
    "#469990",  # 6 teal
    "#f032e6",  # 7 magenta
    "#3cd74b",  # 8 green
    "#9a6324",  # 9 brown
    "#353535",  # 10 charcoal
]

FONT_PATHS = [
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


def font(size: int) -> ImageFont.ImageFont:
    for p in FONT_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def box_blur(a: np.ndarray, r: int) -> np.ndarray:
    """Separable box blur with edge clamping; three passes approximate a gaussian."""
    if r <= 0:
        return a.astype(np.float64)
    out = a.astype(np.float64)
    for _ in range(3):
        for axis in (0, 1):
            pad = [(0, 0), (0, 0)]
            pad[axis] = (r + 1, r)
            p = np.pad(out, pad, mode="edge")
            c = np.cumsum(p, axis=axis)
            if axis == 0:
                out = (c[2 * r + 1 :, :] - c[: -2 * r - 1, :]) / (2 * r + 1)
            else:
                out = (c[:, 2 * r + 1 :] - c[:, : -2 * r - 1]) / (2 * r + 1)
    return out


def tiled(tile: np.ndarray, w: int, h: int, scale: float) -> np.ndarray:
    size = max(16, int(tile.shape[0] * scale))
    im = Image.fromarray((tile * 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    t = np.asarray(im).astype(np.float64) / 255.0
    reps = (h // size + 1, w // size + 1, 1)
    return np.tile(t, reps)[:h, :w]


def edges_of(labels: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """(province borders between two land provinces, coastline pixels on land)."""
    land = labels >= 0
    border = np.zeros(labels.shape, dtype=bool)
    coast = np.zeros(labels.shape, dtype=bool)
    for dy, dx in ((0, 1), (1, 0)):
        nb = np.roll(np.roll(labels, -dy, 0), -dx, 1)
        diff = labels != nb
        border |= diff & land & (nb >= 0)
        coast |= land & (nb < 0)
        nb2 = np.roll(np.roll(labels, dy, 0), dx, 1)
        coast |= land & (nb2 < 0)
    return border, coast


def dilate(m: np.ndarray, r: int = 1) -> np.ndarray:
    out = m.copy()
    for _ in range(r):
        o = out.copy()
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            o |= np.roll(np.roll(out, dy, 0), dx, 1)
        out = o
    return out


def paint_land(lay: Layout, scale: float, political: bool) -> np.ndarray:
    h, w = lay.labels.shape
    biomes = biome_map(lay.theme)
    out = np.zeros((h, w, 3))
    prov_biome = np.array([s.biome for s in lay.seeds])
    for key in sorted(set(prov_biome.tolist())):
        ids = np.flatnonzero(prov_biome == key)
        m = np.isin(lay.labels, ids)
        if not m.any():
            continue
        tex = tiled(make_tile(lay.theme, key), w, h, scale)
        if political:
            det = tiled(np.repeat(detail_of(make_tile(lay.theme, key))[..., None], 3, -1), w, h, scale)
            owner_col = np.zeros((h, w, 3))
            owned = np.zeros((h, w), dtype=bool)
            for i in ids:
                if lay.owner[i] is None:
                    continue
                pm = lay.labels == i
                owner_col[pm] = hex_rgb(PALETTE[lay.owner[i] % len(PALETTE)])
                owned |= pm
            neutral = mix(tex, np.full_like(tex, 0.86), np.full((h, w), 0.45))
            tex = np.where(owned[..., None], owner_col * det, neutral)
            if biomes[key].terrain == "Mountain":  # never owned: keep the rock look, slightly dimmed
                tex = tiled(make_tile(lay.theme, key), w, h, scale) * 0.85
        out[m] = tex[m]
    return out


def draw_straits(img: Image.Image, lay: Layout, style: str) -> None:
    d = ImageDraw.Draw(img, "RGBA")
    w = lay.width
    for st in lay.straits:
        (x0, y0), (x1, y1) = st["from"], st["to"]
        if st["wrap"]:
            # leaves the map on one edge and comes back on the other (the world is round)
            for (x, y), edge in (((x0, y0), 0 if x0 < w / 2 else w - 1), ((x1, y1), 0 if x1 < w / 2 else w - 1)):
                dashed(d, (x, y), (edge, y), (255, 255, 255, 220), 3, 10, 6)
                ah = 10 if edge > 0 else -10
                d.polygon([(edge, y), (edge - ah, y - 7), (edge - ah, y + 7)], fill=(255, 255, 255, 230))
            continue
        if style == "sky":
            rope_bridge(d, (x0, y0), (x1, y1))
        elif style == "fantasy":
            dashed(d, (x0, y0), (x1, y1), (60, 40, 25, 230), 3, 9, 6)
            for p in ((x0, y0), (x1, y1)):
                d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(60, 40, 25, 230))
        else:
            dashed(d, (x0, y0), (x1, y1), (255, 255, 255, 230), 3, 9, 6)
            for p in ((x0, y0), (x1, y1)):
                d.ellipse([p[0] - 4, p[1] - 4, p[0] + 4, p[1] + 4], fill=(255, 255, 255, 240), outline=(20, 40, 60, 255))


def dashed(d: ImageDraw.ImageDraw, a, b, color, width, dash, gap) -> None:
    (x0, y0), (x1, y1) = a, b
    length = math.hypot(x1 - x0, y1 - y0)
    if length < 1:
        return
    ux, uy = (x1 - x0) / length, (y1 - y0) / length
    t = 0.0
    while t < length:
        e = min(t + dash, length)
        d.line([(x0 + ux * t, y0 + uy * t), (x0 + ux * e, y0 + uy * e)], fill=color, width=width)
        t += dash + gap


def rope_bridge(d: ImageDraw.ImageDraw, a, b) -> None:
    (x0, y0), (x1, y1) = a, b
    length = math.hypot(x1 - x0, y1 - y0)
    if length < 1:
        return
    ux, uy = (x1 - x0) / length, (y1 - y0) / length
    px, py = -uy, ux
    half = 6
    # shadow far below, then deck planks, then ropes
    d.line([(x0 + 10, y0 + 18), (x1 + 10, y1 + 18)], fill=(10, 10, 40, 70), width=12)
    t = 0.0
    while t < length:
        cx, cy = x0 + ux * t, y0 + uy * t
        d.line([(cx + px * half, cy + py * half), (cx - px * half, cy - py * half)], fill=(140, 96, 56, 255), width=3)
        t += 4.5
    for s in (half, -half):
        d.line([(x0 + px * s, y0 + py * s), (x1 + px * s, y1 + py * s)], fill=(70, 46, 24, 255), width=2)


def capital_marker(d: ImageDraw.ImageDraw, x: int, y: int, r: int = 9) -> None:
    pts = []
    for k in range(10):
        ang = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.45
        pts.append((x + rr * math.cos(ang), y + rr * math.sin(ang)))
    d.polygon(pts, fill=(255, 236, 140, 255), outline=(40, 30, 10, 255))


def render(lay: Layout, background: np.ndarray, style: str, scale: float = 0.5, political: bool = False):
    land = lay.labels >= 0
    col = paint_land(lay, scale, political)
    border, coast = edges_of(lay.labels)
    # soft inner shade along borders gives each province a slightly raised "tile" look
    edge_soft = box_blur((border | coast).astype(np.float64), 3)
    col = col * (1.0 - 0.22 * np.clip(edge_soft * 2.0, 0, 1))[..., None]
    out = np.where(land[..., None], col, background)
    ink = {"earth": (0.08, 0.1, 0.12), "fantasy": (0.18, 0.11, 0.06), "sky": (0.12, 0.1, 0.2)}[style]
    b = dilate(border, 1) & land if political else border
    out = mix(out, np.broadcast_to(np.array(ink), out.shape), b.astype(np.float64) * (0.85 if political else 0.6))
    out = mix(out, np.broadcast_to(np.array(ink), out.shape), dilate(coast, 1).astype(np.float64) * 0.85)
    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))
    draw_straits(img, lay, style)
    if political:
        d = ImageDraw.Draw(img, "RGBA")
        for n in lay.nations:
            x, y = lay.centers[n["capital"]]
            capital_marker(d, x, y)
    return img


def id_map(lay: Layout) -> Image.Image:
    """Province id encoded in the red and green channels (id = R + 256*G); 0 means no province."""
    ids = (lay.labels + 1).astype(np.int64)
    rgb = np.zeros(lay.labels.shape + (3,), dtype=np.uint8)
    rgb[..., 0] = ids % 256
    rgb[..., 1] = ids // 256
    return Image.fromarray(rgb)


def atlas(base: Image.Image, lay: Layout) -> Image.Image:
    img = base.copy()
    d = ImageDraw.Draw(img)
    f = font(13)
    for i, (x, y) in enumerate(lay.centers):
        t = str(i + 1)
        d.text((x, y), t, font=f, fill=(255, 255, 255), anchor="mm", stroke_width=3, stroke_fill=(0, 0, 0))
    return img


def vote_card(base: Image.Image, title: str, subtitle: str) -> Image.Image:
    w, h = 1024, 512
    # cover the card with a blurred copy, then fit the whole map on top
    cover = max(w / base.width, h / base.height)
    bg = base.resize((int(base.width * cover) + 1, int(base.height * cover) + 1), Image.LANCZOS)
    bg = bg.crop(((bg.width - w) // 2, (bg.height - h) // 2, (bg.width - w) // 2 + w, (bg.height - h) // 2 + h))
    card = bg.filter(ImageFilter.GaussianBlur(12)).point(lambda v: int(v * 0.6))
    fit = min(w / base.width, h / base.height)
    img = base.resize((int(base.width * fit), int(base.height * fit)), Image.LANCZOS)
    card.paste(img, ((w - img.width) // 2, (h - img.height) // 2))
    shade = Image.new("RGBA", (w, 120), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for yy in range(120):
        sd.line([(0, yy), (w, yy)], fill=(0, 0, 0, int(200 * yy / 120)))
    card.paste(shade, (0, h - 120), shade)
    d = ImageDraw.Draw(card)
    d.text((28, h - 52), title, font=font(48), fill=(255, 255, 255), stroke_width=3, stroke_fill=(0, 0, 0), anchor="ls")
    d.text((30, h - 20), subtitle, font=font(20), fill=(225, 225, 225), anchor="ls")
    return card
