"""Render a scene dumped by tools/harness/Scene.luau into a PNG: what a player's screen would roughly show.

    python3 tools/harness/render_scene.py scene.json out.png

Parts are projected with the client's real camera (perspective, field of view, viewport). GUI layout covers
what this game uses: UDim2 size/position/anchor, UIListLayout, UIGridLayout, UIPadding, UICorner,
UISizeConstraint and AutomaticSize. It is a debugging view, not a pixel-perfect Roblox.
"""

from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SCALE = 2  # render at 2x so small phone text stays legible
TEXT_FONTS = [
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
SYMBOL_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
EMOJI_FONT = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"

HERE = os.path.dirname(os.path.abspath(__file__))
# Stand-ins for Roblox font families (FontFace.Family): Fredoka One ships next to this script (OFL), Builder Sans
# and Gotham are drawn with Inter, the closest font installed here.
FACE_FONTS = {
    "FredokaOne": os.path.join(HERE, "fonts", "FredokaOne-Regular.ttf"),
    "Medium": "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
    "Regular": "/usr/share/fonts/opentype/inter/Inter-Regular.otf",
    "ExtraBold": "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
}

_fonts: dict = {}
_emoji_font = ImageFont.truetype(EMOJI_FONT, 109) if os.path.exists(EMOJI_FONT) else None
_emoji_cache: dict = {}


def face_key(face) -> str:
    """The FACE_FONTS key for a dumped FontFace ({family, weight}), or "" for the default bold font."""
    if not face:
        return ""
    family = face.get("family", "")
    if "FredokaOne" in family:
        return "FredokaOne"
    weight = face.get("weight", "Bold")
    if weight in ("Medium", "Regular", "Light", "ExtraLight", "Thin"):
        return "Medium" if weight == "Medium" else "Regular"
    if weight in ("ExtraBold", "Heavy"):
        return "ExtraBold"
    return ""


def font(size: int, symbols: bool = False, face: str = ""):
    key = (size, symbols, face)
    if key not in _fonts:
        if symbols:
            path = SYMBOL_FONT
        elif face and os.path.exists(FACE_FONTS.get(face, "")):
            path = FACE_FONTS[face]
        else:
            path = next(p for p in TEXT_FONTS if os.path.exists(p))
        _fonts[key] = ImageFont.truetype(path, size)
    return _fonts[key]


def emoji_glyph(ch: str):
    """RGBA image of a colour emoji, or None if the emoji font lacks it."""
    if _emoji_font is None:
        return None
    if ch not in _emoji_cache:
        img = Image.new("RGBA", (160, 140), (0, 0, 0, 0))
        ImageDraw.Draw(img).text((0, 0), ch, font=_emoji_font, embedded_color=True)
        bbox = img.getbbox()
        _emoji_cache[ch] = img.crop(bbox) if bbox else None
    return _emoji_cache[ch]


def is_emojiish(ch: str) -> bool:
    cp = ord(ch)
    return cp >= 0x1F000 or 0x2300 <= cp <= 0x23FF or 0x2600 <= cp <= 0x27BF or 0x2B00 <= cp <= 0x2BFF


def text_runs(text: str):
    """Split into (kind, string) runs: 'emoji' for glyphs the emoji font has, 'symbol'/'text' otherwise."""
    runs = []
    for ch in text:
        if ch in "️‍":
            continue
        if is_emojiish(ch) and emoji_glyph(ch) is not None:
            kind = "emoji"
        elif ord(ch) > 0x2000:
            kind = "symbol"
        else:
            kind = "text"
        if runs and runs[-1][0] == kind and kind != "emoji":
            runs[-1] = (kind, runs[-1][1] + ch)
        else:
            runs.append((kind, ch))
    return runs


def measure_line(line: str, size: int, face: str = "") -> int:
    w = 0
    for kind, s in text_runs(line):
        if kind == "emoji":
            w += int(size * 1.15)
        else:
            w += int(font(size, kind == "symbol", face).getlength(s))
    return w


def draw_line(img: Image.Image, x: float, y: float, line: str, size: int, color, stroke=None, face: str = ""):
    """stroke: None, or (rgba, width in px) for an outline round the glyphs."""
    d = ImageDraw.Draw(img)
    for kind, s in text_runs(line):
        if kind == "emoji":
            g = emoji_glyph(s)
            h = int(size * 1.05)
            w = max(1, int(g.width * h / g.height))
            img.alpha_composite(g.resize((w, h), Image.LANCZOS), (int(x), int(y + size * 0.05)))
            x += int(size * 1.15)
        else:
            f = font(size, kind == "symbol", face)
            kw = {"stroke_width": stroke[1], "stroke_fill": stroke[0]} if stroke else {}
            d.text((x, y), s, font=f, fill=color, **kw)
            x += f.getlength(s)


def wrap_lines(text: str, size: int, width: float, face: str):
    """Greedy word wrap, like Roblox's TextWrapped."""
    out = []
    for para in text.split("\n"):
        line = ""
        for word in para.split(" "):
            trial = word if not line else line + " " + word
            if line and measure_line(trial, size, face) > width:
                out.append(line)
                line = word
            else:
                line = trial
        out.append(line)
    return out


def truncate_line(line: str, size: int, width: float, face: str) -> str:
    if measure_line(line, size, face) <= width:
        return line
    while line and measure_line(line + "…", size, face) > width:
        line = line[:-1]
    return line + "…"


def draw_text_block(img, rect, text, size, color, align="Center", valign="Center", stroke=None, face="",
                    wrapped=False, truncate=False):
    x0, y0, x1, y1 = rect
    text = text.replace("\ue002", "R$")  # Roblox fonts draw U+E002 as the Robux icon; our fonts don't have it
    lines = wrap_lines(text, size, x1 - x0 + 1, face) if wrapped else text.split("\n")
    if truncate and not wrapped:
        lines = [truncate_line(line, size, x1 - x0, face) for line in lines]
    line_h = int(size * 1.2)
    total = line_h * len(lines)
    if valign == "Top":
        y = y0
    elif valign == "Bottom":
        y = y1 - total
    else:
        y = y0 + ((y1 - y0) - total) / 2
    for line in lines:
        w = measure_line(line, size, face)
        if align == "Left":
            x = x0
        elif align == "Right":
            x = x1 - w
        else:
            x = x0 + ((x1 - x0) - w) / 2
        draw_line(img, x, y - size * 0.06, line, size, color, stroke, face)
        y += line_h


def rgba(c, alpha=1.0):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(255 * max(0.0, min(1.0, alpha))))


# ------------------------------------------------------------------------------------------- 3D


class Camera:
    def __init__(self, cam, viewport):
        c = cam["cf"]
        self.pos = (c[0], c[1], c[2])
        r = c[3:]
        self.right = (r[0], r[3], r[6])
        self.up = (r[1], r[4], r[7])
        self.look = (-r[2], -r[5], -r[8])
        self.tan = math.tan(math.radians(cam["fov"]) / 2)
        self.w, self.h = viewport[0] * SCALE, viewport[1] * SCALE

    def project(self, p):
        rel = (p[0] - self.pos[0], p[1] - self.pos[1], p[2] - self.pos[2])
        z = sum(a * b for a, b in zip(rel, self.look))
        if z <= 0.01:
            return None
        aspect = self.w / self.h
        nx = sum(a * b for a, b in zip(rel, self.right)) / (z * self.tan * aspect)
        ny = sum(a * b for a, b in zip(rel, self.up)) / (z * self.tan)
        return ((nx + 1) / 2 * self.w, (1 - ny) / 2 * self.h)

    def distance(self, p):
        return math.dist(p, self.pos)


def local_to_world(cf, v):
    x, y, z = cf[0:3]
    r = cf[3:]
    return (
        x + r[0] * v[0] + r[1] * v[1] + r[2] * v[2],
        y + r[3] * v[0] + r[4] * v[1] + r[5] * v[2],
        z + r[6] * v[0] + r[7] * v[1] + r[8] * v[2],
    )


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX = os.path.join(ROOT, "assets", "textures")
# Stand-ins for Roblox's built-in materials: our own tiles' luminance, tinted by the part colour.
MATERIAL_TEXTURES = {
    "Grass": "earth/grassland",
    "LeafyGrass": "earth/forest",
    "Sand": "earth/desert",
    "Snow": "earth/ice",
    "Rock": "earth/mountains",
    "Ground": "earth/hills",
    "Sandstone": "earth/drylands",
    "CrackedLava": "fantasy/ashlands",
    "Marble": "sky/heartruins",
    "Slate": "sky/crags",
    "Basalt": "sky/stormspire",
    "Water": "earth/sea",
}
TEXTURE_PERIOD = 18.0  # studs per texture repeat
SUN = np.array([-0.35, 1.0, 0.45]) / np.linalg.norm([-0.35, 1.0, 0.45])
AMBIENT = 0.58
_details: dict = {}


def mips(a):
    chain = [a]
    while chain[-1].shape[0] > 4:
        x = chain[-1]
        chain.append((x[0::2, 0::2] + x[1::2, 0::2] + x[0::2, 1::2] + x[1::2, 1::2]) / 4)
    return chain


def texture_of(key: str):
    """Colour detail (mean ~1) and optional normal-map mip chains for a material, or None."""
    if key in _details:
        return _details[key]
    tex = None
    if key in MATERIAL_TEXTURES:
        path = os.path.join(TEX, MATERIAL_TEXTURES[key] + ".png")
        if os.path.exists(path):
            lum = np.asarray(Image.open(path).convert("L"), dtype=np.float64)
            lum = np.clip(1 + (lum / max(lum.mean(), 1) - 1) * 0.9, 0.45, 1.6)
            tex = {"color": mips(lum), "normal": None, "studs": TEXTURE_PERIOD}
    _details[key] = tex
    return tex


def part_faces(part):
    """World-space faces [(points, normal)] of a part, by shape."""
    cf, (sx, sy, sz) = part["cf"], part["size"]
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    shape = part["shape"]

    def w(v):
        return np.array(local_to_world(cf, v))

    if shape == "Wedge":
        # cross-section in local Y/Z: front-bottom, back-bottom, back-top (the front-top corner is cut away)
        cross = [(-hy, -hz), (-hy, hz), (hy, hz)]
        left = [w((-hx, y, z)) for y, z in cross]
        right = [w((hx, y, z)) for y, z in cross]
        faces = [left[::-1], right]
        for i in range(3):
            j = (i + 1) % 3
            faces.append([left[i], left[j], right[j], right[i]])
    elif shape == "Cylinder":
        axis_top = 1 if cf[6] >= 0 else -1
        r = min(hy, hz)
        faces = [[w((axis_top * hx, r * math.cos(a), r * math.sin(a))) for a in (i * math.tau / 32 for i in range(32))]]
    else:
        c = [w((dx * hx, dy * hy, dz * hz)) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]
        idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        faces = [[c[i] for i in q] for q in idx]
    centre = w((0, 0, 0))
    out = []
    for f in faces:
        n = np.cross(f[1] - f[0], f[2] - f[0])
        if np.linalg.norm(n) < 1e-9 and len(f) > 3:
            n = np.cross(f[2] - f[0], f[3] - f[0])
        norm = np.linalg.norm(n)
        if norm < 1e-9:
            continue
        n = n / norm
        fc = sum(f) / len(f)
        if np.dot(n, fc - centre) < 0:
            n = -n  # outward
        out.append((f, n, local_axis(cf, n)))
    return out


def local_axis(cf, n):
    """The part-local axis (0 = X, 1 = Y, 2 = Z) closest to a world-space face normal."""
    r = cf[3:]
    cols = [np.array([r[a], r[3 + a], r[6 + a]]) for a in range(3)]
    return int(np.argmax([abs(float(np.dot(c, n))) for c in cols]))


NEAR = 0.5


def project_face(cam, face):
    """Screen points (x, y, depth) of a world-space polygon, clipped against the near plane; None if all behind."""
    pos = np.asarray(cam.pos)
    pts = []
    for p in face:
        rel = np.asarray(p) - pos
        pts.append((float(np.dot(rel, cam.right)), float(np.dot(rel, cam.up)), float(np.dot(rel, cam.look))))
    clipped = []
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        if a[2] >= NEAR:
            clipped.append(a)
        if (a[2] >= NEAR) != (b[2] >= NEAR):
            t = (NEAR - a[2]) / (b[2] - a[2])
            clipped.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(3)))
    if len(clipped) < 3:
        return None
    aspect = cam.w / cam.h
    return [
        ((x / (z * cam.tan * aspect) + 1) / 2 * cam.w, (1 - y / (z * cam.tan)) / 2 * cam.h, z) for x, y, z in clipped
    ]


def rasterize(polys, w, h):
    """Z-buffer: polys are lists of (x, y, z) screen points. Returns (id buffer, depth buffer); id 0 = nothing."""
    zbuf = np.full((h, w), np.inf)
    ids = np.zeros((h, w), dtype=np.int32)
    for k, poly in enumerate(polys, start=1):
        for i in range(1, len(poly) - 1):
            (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = poly[0], poly[i], poly[i + 1]
            area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
            if abs(area) < 1e-6:
                continue
            bx0 = max(int(math.floor(min(x0, x1, x2))), 0)
            bx1 = min(int(math.ceil(max(x0, x1, x2))), w - 1)
            by0 = max(int(math.floor(min(y0, y1, y2))), 0)
            by1 = min(int(math.ceil(max(y0, y1, y2))), h - 1)
            if bx0 > bx1 or by0 > by1:
                continue
            py, px = np.mgrid[by0 : by1 + 1, bx0 : bx1 + 1].astype(np.float64)
            px += 0.5
            py += 0.5
            b0 = ((x1 - px) * (y2 - py) - (x2 - px) * (y1 - py)) / area
            b1 = ((x2 - px) * (y0 - py) - (x0 - px) * (y2 - py)) / area
            b2 = 1 - b0 - b1
            eps = -0.02
            inside = (b0 >= eps) & (b1 >= eps) & (b2 >= eps)
            if not inside.any():
                continue
            z = 1 / (b0 / z0 + b1 / z1 + b2 / z2)  # perspective-correct depth
            zb = zbuf[by0 : by1 + 1, bx0 : bx1 + 1]
            win = inside & (z < zb)
            zb[win] = z[win]
            ids[by0 : by1 + 1, bx0 : bx1 + 1][win] = k
    return ids, zbuf


def render_world(img, scene, cam):
    w, h = img.size
    campos = np.array(cam.pos)
    parts = list(scene["parts"])
    for wblock in scene.get("water", []):
        parts.append({"shape": "Block", "cf": wblock["cf"], "size": wblock["size"], "color": wblock["color"],
                      "transparency": 0, "material": "Water"})
    opaque, translucent = [], []  # (screen poly, colour, shade, material, alpha)
    for part in parts:
        if part["transparency"] >= 0.95:
            continue
        for f, n, axis in part_faces(part):
            fc = sum(f) / len(f)
            if np.dot(n, campos - fc) <= 0:
                continue  # facing away
            proj = project_face(cam, f)
            if proj is None:
                continue
            shade = AMBIENT + (1 - AMBIENT) * max(0.0, float(np.dot(n, SUN)))
            if part["material"] == "Neon":
                shade = 1.25
            texture = part.get("variant") or part["material"]
            item = (proj, part["color"], shade, texture, 1 - part["transparency"], part["cf"], axis, n)
            (opaque if part["transparency"] < 0.001 else translucent).append(item)

    ids, zbuf = rasterize([it[0] for it in opaque], w, h)
    colors = np.array([[0.04, 0.04, 0.06]] + [list(it[1]) for it in opaque])
    shades = np.array([1.0] + [it[2] for it in opaque])
    out = colors[ids] * shades[ids][..., None]

    # world position under every pixel, from its depth
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    nx = (2 * (xs + 0.5) / w - 1) * cam.tan * (w / h)
    ny = (1 - 2 * (ys + 0.5) / h) * cam.tan
    right, up, look = (np.array(v) for v in (cam.right, cam.up, cam.look))
    depth = np.where(np.isfinite(zbuf), zbuf, 0)
    world = [campos[i] + (right[i] * nx + up[i] * ny + look[i]) * depth for i in range(3)]

    # materials: Roblox maps a material's texture in each part's own space (it turns with the part), so do the same
    rots = np.array([[0.0] * 9] + [it[5][3:] for it in opaque])
    poss = np.array([[0.0] * 3] + [it[5][:3] for it in opaque])
    axes = np.array([0] + [it[6] for it in opaque])
    normals = np.array([[0.0, 1.0, 0.0]] + [list(it[7]) for it in opaque])
    keys = [""] + [it[3] for it in opaque]
    for key in set(keys):
        tex = texture_of(key)
        if tex is None:
            continue
        mask = np.isin(ids, [i for i, k in enumerate(keys) if k == key])
        if not mask.any():
            continue
        k = ids[mask]
        rel = [world[i][mask] - poss[k, i] for i in range(3)]
        rot = rots[k]
        local = [rot[:, a] * rel[0] + rot[:, 3 + a] * rel[1] + rot[:, 6 + a] * rel[2] for a in range(3)]
        ua = np.where(axes[k] == 0, 1, 0)  # the two axes across the face
        va = np.where(axes[k] == 2, 1, 2)
        local = np.stack(local, axis=-1)
        lu = np.take_along_axis(local, ua[:, None], axis=1)[:, 0]
        lv = np.take_along_axis(local, va[:, None], axis=1)[:, 0]
        period = tex["studs"]
        # pick the mip level whose texels match the pixel's footprint, like a GPU would
        footprint = depth[mask] * 2 * cam.tan / h * tex["color"][0].shape[0] / period
        level = np.clip(np.floor(np.log2(np.maximum(footprint, 1e-6))), 0, len(tex["color"]) - 1).astype(int)
        albedo = np.ones(level.shape)
        bump = np.zeros(level.shape + (3,))
        bump[:, 2] = 1
        for lv_i in range(len(tex["color"])):
            sel = level == lv_i
            if not sel.any():
                continue
            tn = tex["color"][lv_i].shape[0]
            u = ((lu[sel] / period) % 1.0 * tn).astype(int) % tn
            v = ((lv[sel] / period) % 1.0 * tn).astype(int) % tn
            albedo[sel] = tex["color"][lv_i][v, u]
            if tex["normal"] is not None:
                bump[sel] = tex["normal"][lv_i][v, u]
        if tex["normal"] is not None:
            # tangent space -> world: u along the part's ua axis, image-up along -va, out along the face normal
            tu = np.stack([rot[np.arange(len(k)), ua + 3 * j] for j in range(3)], axis=-1)
            tv = -np.stack([rot[np.arange(len(k)), va + 3 * j] for j in range(3)], axis=-1)
            nw = tu * bump[:, :1] + tv * bump[:, 1:2] + normals[k] * bump[:, 2:3]
            nw /= np.linalg.norm(nw, axis=-1, keepdims=True)
            lam = np.clip(nw @ SUN, 0, 1)
            flat = np.clip(normals[k] @ SUN, 0, 1)
            out[mask] *= ((AMBIENT + (1 - AMBIENT) * lam) / (AMBIENT + (1 - AMBIENT) * flat))[:, None]
        out[mask] *= albedo[:, None]
    rgb = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8), "RGB").convert("RGBA")
    img.alpha_composite(rgb)

    # translucent faces (inner borders) and highlights on top, only where they are in front of the solid world
    layer = np.zeros((h, w, 4))
    for proj, color, shade, _, alpha, *_ in translucent:
        lid, lz = rasterize([proj], w, h)
        m = (lid > 0) & (lz <= zbuf + 0.05)
        c = np.clip(np.array(color) * shade, 0, 1)
        layer[m, :3] = layer[m, :3] * (1 - alpha) + c * alpha
        layer[m, 3] = layer[m, 3] * (1 - alpha) + alpha
    for hl in scene.get("highlights", []):
        for f, n, _ in part_faces({**hl, "transparency": 0}):
            if n[1] > 0.5:
                proj = project_face(cam, f)
                if proj is not None:
                    lid, lz = rasterize([proj], w, h)
                    m = (lid > 0) & (lz <= zbuf + 0.05)
                    a = hl["alpha"]
                    layer[m, :3] = layer[m, :3] * (1 - a) + np.array(hl["color"]) * a
                    layer[m, 3] = layer[m, 3] * (1 - a) + a
    if layer[..., 3].any():
        over = np.zeros((h, w, 4), dtype=np.uint8)
        alpha = layer[..., 3:4]
        over[..., :3] = (np.clip(np.divide(layer[..., :3], alpha, out=np.zeros_like(layer[..., :3]),
                                           where=alpha > 0), 0, 1) * 255).astype(np.uint8)
        over[..., 3] = (np.clip(layer[..., 3], 0, 1) * 255).astype(np.uint8)
        img.alpha_composite(Image.fromarray(over, "RGBA"))

    sel_layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(sel_layer)
    for sel in scene["selections"]:
        for f, n, _ in part_faces({**sel, "transparency": 0}):
            if n[1] > 0.5:
                proj = [cam.project(tuple(p)) for p in f]
                if all(p is not None for p in proj):
                    sd.line(proj + [proj[0]], fill=rgba(sel["color"]), width=2 * SCALE)
    img.alpha_composite(sel_layer)

    for bb in scene["billboards"]:
        if cam.distance(bb["pos"]) > bb["maxDistance"]:
            continue
        p = cam.project(bb["pos"])
        if p is None:
            continue
        bw = bb["size"][1] * SCALE
        bh = bb["size"][3] * SCALE
        out = []
        layout(bb["gui"], p[0] - bw / 2, p[1] - bh / 2, bw, bh, out)
        draw_nodes(img, out)


def child_of(node, cls):
    return next((c for c in node["children"] if c["class"] == cls), None)


def gui_children(node):
    return [c for c in node["children"] if "size" in c and c.get("visible", True)]


def udim(u, parent_w, parent_h):
    return u[0] * parent_w + u[1] * SCALE, u[2] * parent_h + u[3] * SCALE


def layout(node, x, y, w, h, out):
    """Lay out node's GUI children inside the content box (x, y, w, h); append (node, rect) to out in draw order."""
    pad = child_of(node, "UIPadding")
    if pad:
        t, b, l, r = (v * SCALE for v in pad["pad"])
        x, y, w, h = x + l, y + t, w - l - r, h - t - b
    kids = sorted(gui_children(node), key=lambda c: c["layoutOrder"])
    lst = child_of(node, "UIListLayout")
    grid = child_of(node, "UIGridLayout")
    extent = 0.0
    if grid:
        cw, ch = udim(grid["cell"], w, h)
        px, py = udim(grid["cellPadding"], w, h)
        per_row = max(1, int((w + px) // (cw + px)))
        for i, k in enumerate(kids):
            cx = x + (i % per_row) * (cw + px)
            cy = y + (i // per_row) * (ch + py)
            place(k, cx, cy, cw, ch, out, fixed=True)
            extent = max(extent, cy + ch - y)
    elif lst:
        gap = lst["padding"][0] * (w if lst["fill"] == "Horizontal" else h) + lst["padding"][1] * SCALE
        cursor = 0.0
        first = len(out)
        for k in kids:
            kw, kh = udim(k["size"], w, h)
            if lst["fill"] == "Horizontal":
                ky = y + ((h - kh) / 2 if lst["valign"] == "Center" else 0)
                rect = place(k, x + cursor, ky, kw, kh, out, fixed=True)
                cursor += (rect[2] - rect[0]) + gap
                extent = max(extent, rect[3] - y)
            else:
                rect = place(k, x, y + cursor, kw, kh, out, fixed=True)
                cursor += (rect[3] - rect[1]) + gap
                extent = max(extent, cursor - gap)
        # a horizontal list centred or right-aligned: move the row (and everything inside it) over
        if lst["fill"] == "Horizontal" and lst.get("halign") in ("Center", "Right") and kids:
            spare = w - (cursor - gap)
            shift = spare / 2 if lst["halign"] == "Center" else spare
            for item in out[first:]:
                a, b, c, d = item[1]
                item[1] = (a + shift, b, c + shift, d)
    else:
        for k in sorted(kids, key=lambda c: c.get("zIndex", 1)):
            kw, kh = constrain(k, *udim(k["size"], w, h))
            px, py = udim(k["position"], w, h)
            ax, ay = k["anchor"]
            rect = place(k, x + px - ax * kw, y + py - ay * kh, kw, kh, out, fixed=False, anchor=(ax, ay))
            extent = max(extent, rect[3] - y)
    return extent + (pad["pad"][1] * SCALE if pad else 0) + (pad["pad"][0] * SCALE if pad else 0)


def constrain(node, w, h):
    """A UISizeConstraint's limits, applied before the anchor point places the object (as Roblox does)."""
    cons = child_of(node, "UISizeConstraint")
    if cons:
        mx, my = cons["maxSize"]  # null = math.huge
        if mx is not None:
            w = min(w, mx * SCALE)
        if my is not None:
            h = min(h, my * SCALE)
    return w, h


def text_width(node) -> float:
    """Width a text object needs for its text plus padding (AutomaticSize X), in render pixels."""
    size = int(node["textSize"] * SCALE)
    face = face_key(node.get("font"))
    w = max((measure_line(line, size, face) for line in node["text"].split("\n")), default=0)
    pad = child_of(node, "UIPadding")
    if pad:
        w += (pad["pad"][2] + pad["pad"][3]) * SCALE
    return w + 2


def place(node, x, y, w, h, out, fixed, anchor=(0, 0)):
    if node.get("autoSize") in ("X", "XY") and node.get("text") is not None:
        grown = max(w, text_width(node))
        x -= (grown - w) * anchor[0]
        w = grown
    cons = child_of(node, "UISizeConstraint")
    if cons:
        mx, my = cons["maxSize"]  # null = math.huge
        if mx is not None:
            w = min(w, mx * SCALE)
        if my is not None:
            h = min(h, my * SCALE)
    index = len(out)
    out.append([node, (x, y, x + w, y + h)])
    content_h = layout(node, x, y, w, h, out)
    if node.get("autoSize") in ("Y", "XY") and content_h > h:
        grow = content_h - h
        # anchored at the bottom: grow upwards, and move everything already laid out inside
        shift = -grow * anchor[1] if not fixed else 0
        x0, y0, x1, y1 = out[index][1]
        out[index][1] = (x0, y0 + shift, x1, y1 + shift + grow)
        if shift:
            for item in out[index + 1 :]:
                a, b, c, d = item[1]
                item[1] = (a, b + shift, c, d + shift)
    return out[index][1]


_images: dict = {}


def draw_image(img, rect, info, images, rotation=0):
    """An EditableImage shown by an ImageLabel: crop to the screen first (a zoomed map can be huge), then scale."""
    path = images[info["index"] - 1]
    if path not in _images:
        with open(path, "rb") as f:
            _images[path] = Image.frombytes("RGBA", (info["width"], info["height"]), f.read())
    src = _images[path]
    x0, y0, x1, y1 = rect
    if info.get("fit") and x1 > x0 and y1 > y0:
        # ScaleType.Fit: the largest box with the image's shape, centred in the label
        scale = min((x1 - x0) / src.width, (y1 - y0) / src.height)
        w, h = src.width * scale, src.height * scale
        x0, y0 = x0 + ((x1 - x0) - w) / 2, y0 + ((y1 - y0) - h) / 2
        x1, y1 = x0 + w, y0 + h
    vx0, vy0, vx1, vy1 = max(x0, 0), max(y0, 0), min(x1, img.width), min(y1, img.height)
    if vx1 - vx0 < 1 or vy1 - vy0 < 1:
        return
    sx, sy = src.width / (x1 - x0), src.height / (y1 - y0)
    box = ((vx0 - x0) * sx, (vy0 - y0) * sy, (vx1 - x0) * sx, (vy1 - y0) * sy)
    resample = Image.NEAREST if info.get("pixelated") else Image.BILINEAR
    part = src.resize((int(vx1 - vx0), int(vy1 - vy0)), resample, box=box)
    tint, fade = info.get("color", [1, 1, 1]), info.get("transparency", 0)
    if tint != [1, 1, 1] or fade > 0:
        a = np.asarray(part, dtype=np.float64).copy()
        a[..., :3] *= np.array(tint)
        a[..., 3] *= 1 - fade
        part = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")
    if rotation and (vx0, vy0, vx1, vy1) == (x0, y0, x1, y1):
        # GuiObject.Rotation turns clockwise round the centre (whole images only, e.g. an icon turned to point down)
        part = part.rotate(-rotation, resample=Image.NEAREST if info.get("pixelated") else Image.BICUBIC)
    img.alpha_composite(part, (int(vx0), int(vy0)))


def sample(keys, t):
    """A ColorSequence / NumberSequence ([[time, *values]]) at times t (numpy array) -> array of values."""
    times = [k[0] for k in keys]
    cols = [np.interp(t, times, [k[i] for k in keys]) for i in range(1, len(keys[0]))]
    return np.stack(cols, axis=-1)


def gradient_fill(img, rect, color, alpha, radius, grad):
    """A background with a UIGradient: its colours multiply the background, its transparency fades it."""
    x0, y0, x1, y1 = rect
    cx0, cy0 = max(int(x0), 0), max(int(y0), 0)
    cx1, cy1 = min(int(math.ceil(x1)), img.width), min(int(math.ceil(y1)), img.height)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    ys, xs = np.mgrid[cy0:cy1, cx0:cx1].astype(np.float64)
    u = (xs + 0.5 - x0) / max(x1 - x0, 1) - 0.5 - grad["offset"][0]
    v = (ys + 0.5 - y0) / max(y1 - y0, 1) - 0.5 - grad["offset"][1]
    a = math.radians(grad["rotation"])
    t = np.clip(u * math.cos(a) + v * math.sin(a) + 0.5, 0, 1)
    mult = sample(grad["colors"], t)
    fade = sample(grad["transparency"], t)[..., 0]
    rgb = np.clip(np.array(color)[None, None, :] * mult, 0, 1)
    mask = Image.new("L", (cx1 - cx0, cy1 - cy0), 0)
    ImageDraw.Draw(mask).rounded_rectangle((x0 - cx0, y0 - cy0, x1 - cx0, y1 - cy0), radius=radius, fill=255)
    al = np.asarray(mask, dtype=np.float64) / 255 * alpha * (1 - fade)
    layer = np.dstack([rgb * 255, al * 255]).astype(np.uint8)
    img.alpha_composite(Image.fromarray(layer, "RGBA"), (cx0, cy0))


def outline(img, rect, color, alpha, thickness, radius):
    """A UIStroke round the border: outside the box, following its rounded corners."""
    x0, y0, x1, y1 = rect
    t = thickness
    pad = int(t) + 2
    ox, oy = int(x0) - pad, int(y0) - pad
    w, h = int(math.ceil(x1)) - ox + pad, int(math.ceil(y1)) - oy + pad
    if w <= 0 or h <= 0:
        return
    ring = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(ring)
    d.rounded_rectangle((x0 - t - ox, y0 - t - oy, x1 + t - ox, y1 + t - oy), radius=radius + t if radius > 0 else 0,
                        fill=255)
    d.rounded_rectangle((x0 - ox, y0 - oy, x1 - ox, y1 - oy), radius=radius, fill=0)
    layer = Image.new("RGBA", (w, h), rgba(color, alpha))
    layer.putalpha(Image.fromarray((np.asarray(ring, dtype=np.float64) * alpha).astype(np.uint8)))
    left, top = max(0, -ox), max(0, -oy)
    img.alpha_composite(layer.crop((left, top, w, h)), (ox + left, oy + top))


def fill(img, rect, color, alpha, radius):
    x0, y0, x1, y1 = rect
    if x1 <= 0 or y1 <= 0 or x0 >= img.width or y0 >= img.height:
        return
    if alpha >= 0.999 and radius <= 0:
        ImageDraw.Draw(img).rectangle(rect, fill=rgba(color))
        return
    cx0, cy0 = max(int(x0), 0), max(int(y0), 0)
    cx1, cy1 = min(int(math.ceil(x1)), img.width), min(int(math.ceil(y1)), img.height)
    overlay = Image.new("RGBA", (cx1 - cx0, cy1 - cy0), (0, 0, 0, 0))
    ImageDraw.Draw(overlay).rounded_rectangle(
        (x0 - cx0, y0 - cy0, x1 - cx0, y1 - cy0), radius=radius, fill=rgba(color, alpha)
    )
    img.alpha_composite(overlay, (cx0, cy0))


def draw_nodes(img, out, images=()):
    """Draw laid-out GUI nodes: backgrounds, images, strokes and text."""
    for node, rect in out:
        if not node.get("visible", True):
            continue
        x0, y0, x1, y1 = rect
        if x1 - x0 < 1 or y1 - y0 < 1:
            continue
        if x1 < 0 or y1 < 0 or x0 > img.width or y0 > img.height:
            continue
        alpha = 1 - node.get("bgT", 0)
        corner = child_of(node, "UICorner")
        radius = 0
        if corner:
            radius = min((x1 - x0), (y1 - y0)) * corner["radius"][0] + corner["radius"][1] * SCALE
            radius = min(radius, min(x1 - x0, y1 - y0) / 2)
        if alpha > 0.01:
            if node.get("gradient"):
                gradient_fill(img, rect, node["bg"], alpha, radius, node["gradient"])
            else:
                fill(img, rect, node["bg"], alpha, radius)
        if node.get("image") and images:
            draw_image(img, rect, node["image"], images, node.get("rotation", 0))
        stroke = node.get("uiStroke")
        if stroke and not stroke.get("text") and stroke.get("transparency", 0) < 0.99:
            outline(img, rect, stroke["color"], 1 - stroke.get("transparency", 0), stroke["thickness"] * SCALE, radius)
        if node.get("text") and node.get("textT", 0) < 0.99:
            text_stroke = None
            if stroke and stroke.get("text"):
                text_stroke = (rgba(stroke["color"], 1 - stroke.get("transparency", 0)),
                               max(1, int(stroke["thickness"] * SCALE)))
            elif node.get("stroke"):
                text_stroke = (rgba(node.get("strokeColor", [0, 0, 0]), 1 - node.get("strokeT", 0)), SCALE)
            pad = child_of(node, "UIPadding")
            box = rect
            if pad:
                t, b, l, r = (v * SCALE for v in pad["pad"])
                box = (x0 + l, y0 + t, x1 - r, y1 - b)
            draw_text_block(
                img,
                box,
                node["text"],
                int(node["textSize"] * SCALE),
                rgba(node["textColor"], 1 - node.get("textT", 0)),
                align=node.get("textXAlign", "Center"),
                valign=node.get("textYAlign", "Center"),
                stroke=text_stroke,
                face=face_key(node.get("font")),
                wrapped=node.get("textWrapped", False),
                truncate=node.get("truncate", False),
            )


def render_gui(img, scene):
    d = ImageDraw.Draw(img)
    vw, vh = img.size
    for sg in sorted(scene["gui"], key=lambda g: g.get("displayOrder", 0)):
        if not sg.get("enabled", True):
            continue
        out = []
        layout(sg, 0, 0, vw, vh, out)
        draw_nodes(img, out, scene.get("images", []))
    return d


def render(scene_path: str, out_path: str):
    with open(scene_path) as f:
        scene = json.load(f)
    vw, vh = scene["viewport"]
    img = Image.new("RGBA", (vw * SCALE, vh * SCALE), (10, 10, 14, 255))
    cam = Camera(scene["camera"], scene["viewport"])
    render_world(img, scene, cam)
    render_gui(img, scene)
    t = scene.get("time", 0)
    draw_line(img, 8, img.height - 30, f"t={t:.0f}s", 20, (255, 255, 255, 160))
    img.convert("RGB").save(out_path)


if __name__ == "__main__":
    render(sys.argv[1], sys.argv[2])
