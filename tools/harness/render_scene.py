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

from PIL import Image, ImageDraw, ImageFont

SCALE = 2  # render at 2x so small phone text stays legible
TEXT_FONTS = [
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]
SYMBOL_FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
EMOJI_FONT = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"

_fonts: dict = {}
_emoji_font = ImageFont.truetype(EMOJI_FONT, 109) if os.path.exists(EMOJI_FONT) else None
_emoji_cache: dict = {}


def font(size: int, symbols: bool = False):
    key = (size, symbols)
    if key not in _fonts:
        path = SYMBOL_FONT if symbols else next(p for p in TEXT_FONTS if os.path.exists(p))
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


def measure_line(line: str, size: int) -> int:
    w = 0
    for kind, s in text_runs(line):
        if kind == "emoji":
            w += int(size * 1.15)
        else:
            w += int(font(size, kind == "symbol").getlength(s))
    return w


def draw_line(img: Image.Image, x: float, y: float, line: str, size: int, color, stroke: bool = False):
    d = ImageDraw.Draw(img)
    for kind, s in text_runs(line):
        if kind == "emoji":
            g = emoji_glyph(s)
            h = int(size * 1.05)
            w = max(1, int(g.width * h / g.height))
            img.alpha_composite(g.resize((w, h), Image.LANCZOS), (int(x), int(y + size * 0.05)))
            x += int(size * 1.15)
        else:
            f = font(size, kind == "symbol")
            kw = {"stroke_width": max(1, size // 8), "stroke_fill": (0, 0, 0, 230)} if stroke else {}
            d.text((x, y), s, font=f, fill=color, **kw)
            x += f.getlength(s)


def draw_text_block(img, rect, text, size, color, align="Center", valign="Center", stroke=False):
    x0, y0, x1, y1 = rect
    lines = text.split("\n")
    line_h = int(size * 1.25)
    total = line_h * len(lines)
    y = y0 + ((y1 - y0) - total) / 2 if valign == "Center" else y0
    for line in lines:
        w = measure_line(line, size)
        if align == "Left":
            x = x0
        elif align == "Right":
            x = x1 - w
        else:
            x = x0 + ((x1 - x0) - w) / 2
        draw_line(img, x, y, line, size, color, stroke)
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


def footprint(part):
    """World-space outline of a part's top surface, plus its top height (for draw order)."""
    cf, (sx, sy, sz) = part["cf"], part["size"]
    if part["shape"] == "Cylinder":
        axis = (cf[3], cf[6], cf[9])  # local X in world space
        top_sign = 1 if axis[1] >= 0 else -1
        r = min(sy, sz) / 2
        pts = [
            local_to_world(cf, (top_sign * sx / 2, r * math.cos(a), r * math.sin(a)))
            for a in (i * math.tau / 40 for i in range(40))
        ]
    else:
        corners = [local_to_world(cf, (dx * sx / 2, dy * sy / 2, dz * sz / 2)) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]
        corners.sort(key=lambda p: -p[1])
        top = corners[:4]
        cx = sum(p[0] for p in top) / 4
        cz = sum(p[2] for p in top) / 4
        pts = sorted(top, key=lambda p: math.atan2(p[2] - cz, p[0] - cx))
    return pts, max(p[1] for p in pts)


def render_world(img, scene, cam):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    items = []
    for part in scene["parts"]:
        pts, top = footprint(part)
        items.append((top, part, pts))
    items.sort(key=lambda t: t[0])
    for _, part, pts in items:
        proj = [cam.project(p) for p in pts]
        if any(p is None for p in proj):
            continue
        color = list(part["color"])
        if part["material"] == "Neon":
            color = [min(1.0, c * 1.3 + 0.1) for c in color]
        d.polygon(proj, fill=rgba(color, 1 - part["transparency"]))
        if part["shape"] == "Cylinder":
            d.line(proj + [proj[0]], fill=(0, 0, 0, 90), width=1)
    for sel in scene["selections"]:
        pts, _ = footprint(sel)
        proj = [cam.project(p) for p in pts]
        if all(p is not None for p in proj):
            d.line(proj + [proj[0]], fill=rgba(sel["color"]), width=3 * SCALE)
    img.alpha_composite(layer)
    for bb in scene["billboards"]:
        if cam.distance(bb["pos"]) > bb["maxDistance"]:
            continue
        p = cam.project(bb["pos"])
        if p is None:
            continue
        w = bb["size"][1] * SCALE
        h = bb["size"][3] * SCALE
        rect = (p[0] - w / 2, p[1] - h / 2, p[0] + w / 2, p[1] + h / 2)
        draw_text_block(img, rect, bb["text"], int(bb["textSize"] * SCALE), rgba(bb["textColor"]), stroke=True)


# ------------------------------------------------------------------------------------------- GUI


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
    else:
        for k in sorted(kids, key=lambda c: c.get("zIndex", 1)):
            kw, kh = udim(k["size"], w, h)
            px, py = udim(k["position"], w, h)
            ax, ay = k["anchor"]
            rect = place(k, x + px - ax * kw, y + py - ay * kh, kw, kh, out, fixed=False, anchor=(ax, ay))
            extent = max(extent, rect[3] - y)
    return extent + (pad["pad"][1] * SCALE if pad else 0) + (pad["pad"][0] * SCALE if pad else 0)


def place(node, x, y, w, h, out, fixed, anchor=(0, 0)):
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


def render_gui(img, scene):
    d = ImageDraw.Draw(img)
    vw, vh = img.size
    for sg in sorted(scene["gui"], key=lambda g: g.get("displayOrder", 0)):
        if not sg.get("enabled", True):
            continue
        out = []
        layout(sg, 0, 0, vw, vh, out)
        for node, rect in out:
            if not node.get("visible", True):
                continue
            x0, y0, x1, y1 = rect
            if x1 - x0 < 1 or y1 - y0 < 1:
                continue
            alpha = 1 - node.get("bgT", 0)
            if alpha > 0.01:
                corner = child_of(node, "UICorner")
                radius = 0
                if corner:
                    radius = min((x1 - x0), (y1 - y0)) * corner["radius"][0] + corner["radius"][1] * SCALE
                    radius = min(radius, min(x1 - x0, y1 - y0) / 2)
                overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
                ImageDraw.Draw(overlay).rounded_rectangle(rect, radius=radius, fill=rgba(node["bg"], alpha))
                img.alpha_composite(overlay)
            if node.get("text"):
                draw_text_block(
                    img,
                    rect,
                    node["text"],
                    int(node["textSize"] * SCALE),
                    rgba(node["textColor"]),
                    align=node.get("textXAlign", "Center"),
                )
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
