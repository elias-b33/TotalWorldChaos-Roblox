"""FrameArt reference: pixel-art 9-slice frames painted from character grids, exactly like IconArt paints icons.

A frame is { rows, slice } where rows is a list of equal-length strings (one character per art pixel) and
slice = (x0, y0, x1, y1) is the stretchable centre in art pixels (Roblox SliceCenter = Rect.new(x0, y0, x1, y1)).
A style is a palette: character -> 0xRRGGBB. "." is transparent. paint(frame, style) returns RGBA rows.
nine_slice(img, slice, scale, w, h) draws it at any size the way Roblox's ScaleType.Slice does with SliceScale =
scale and ResampleMode = Pixelated: corners keep scale x their size, edges stretch along one axis, the centre
stretches both ways (nearest neighbour).
"""
from __future__ import annotations

import colorsys
import math

from PIL import Image

# ---------------------------------------------------------------------------------------------- palette

INK = 0x0B0D1A


def hx(c: int) -> tuple:
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255)


def to_hex(rgb) -> int:
    # floor(v + 0.5), not Python's round() (which rounds halves to even), so a Luau port gets the same bytes
    r, g, b = (max(0, min(255, int(math.floor(v + 0.5)))) for v in rgb)
    return (r << 16) | (g << 8) | b


def shift(c: int, dl: float, dh: float = 0.0, ds: float = 0.0) -> int:
    """Lighten/darken in HLS with a hue shift (degrees) and saturation change: hue-shifted ramps."""
    r, g, b = (v / 255 for v in hx(c))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    h = (h + dh / 360) % 1
    l = max(0, min(1, l + dl))
    s = max(0, min(1, s + ds))
    return to_hex(tuple(v * 255 for v in colorsys.hls_to_rgb(h, l, s)))


def tone(face: int, light: float, hue: float, sat: float = 0.0) -> int:
    """face with its HLS lightness set to `light` (absolute), hue rotated by `hue` degrees, saturation + sat."""
    r, g, b = (v / 255 for v in hx(face))
    h, _, s = colorsys.rgb_to_hls(r, g, b)
    h = (h + hue / 360) % 1
    s = max(0, min(1, s + sat))
    return to_hex(tuple(v * 255 for v in colorsys.hls_to_rgb(h, max(0, min(1, light)), s)))


def ramp(face: int) -> dict:
    """A button colour's tones from its face colour (docs/UI_DIRECTION.md "Ramps"). Lightness is scaled, not
    shifted, so dark faces (slate) keep a visible base; highlights turn warm (hue towards yellow), shades cool
    (hue towards blue), the way the map's pixel art is shaded. Codes W H F S B D for the button grids."""
    r, g, b = (v / 255 for v in hx(face))
    h, light, _ = colorsys.rgb_to_hls(r, g, b)

    def towards(target: float, amount: float) -> float:
        d = ((target - h * 360 + 540) % 360) - 180
        return max(-amount, min(amount, d))

    warm = towards(60, 10)
    cool = towards(230, 12)
    return {
        "W": tone(face, light + (1 - light) * 0.55, warm, -0.10),  # glint
        "H": tone(face, light + (1 - light) * 0.28, warm, 0.0),  # top highlight row
        "F": face,
        "S": tone(face, light * 0.86, cool * 0.5, -0.02),  # lower face shade
        "B": tone(face, light * 0.64, cool, -0.04),  # base (thickness)
        "D": tone(face, light * 0.47, cool, -0.06),  # base bottom row
        "K": INK,
    }


# The UI's palette (docs/UI_DIRECTION.md "Palette"). Slate panels, brass trim, enamel buttons.
P = {
    "ink": INK,
    "slate950": 0x0E111C,  # full-screen dims, the deepest wells
    "slate900": 0x141927,  # wells (chips, counters, tracks)
    "slate850": 0x191F30,
    "slate800": 0x1E2538,  # panel fill
    "slate700": 0x283149,  # raised cards, slot faces
    "slate600": 0x36415F,  # lit edges, dividers
    "slate500": 0x4C5878,  # bevel highlight, secondary button face
    "slate400": 0x6B7799,
    "slate300": 0x98A2C0,  # dim text on slate
    "brass100": 0xFFF1B8,
    "brass200": 0xFFE08A,
    "brass300": 0xF6C453,  # gold text, brass face
    "brass400": 0xE0A23A,
    "brass500": 0xB8752A,
    "brass600": 0x7E4A1E,  # brass shadow
    "text": 0xFFF6E0,
    "textDim": 0xAEB6D0,
    "textDark": 0x2A1A08,
    "emerald": 0x41B54A,
    "crimson": 0xD8453E,
    "azure": 0x3A85DE,
    "royal": 0x8A52DA,
    "gold": 0xF4BF45,
    "slateBtn": 0x4A5576,
    "peace": 0x55C35A,
    "war": 0xE0483F,
    "cataclysm": 0x9A5BEA,
    "common": 0xB9C1D9,
    "rare": 0x4FA3FF,
    "epic": 0xB36FF2,
    "legendary": 0xFFA53A,
    "negative": 0xFF6B5E,
    "positive": 0x8BEA7C,
}

# ---------------------------------------------------------------------------------------------- frames
# Codes: K ink outline. Buttons: W glint, H highlight row, F face, S lower face, B base, D base bottom.
# Panels: E lit edge, P fill, L inner lip (just under the top edge), e dark edge. Brass: y highlight, Y face,
# O shade, o deep shade, R rivet, r rivet shine. Wells: x inner shadow, w fill, z inner light.

FRAMES: dict = {}

# An enamel button, raised: 2-px stepped corners, a highlight row with a glint, the face, a shaded last face row
# and a 3-px base. Up: 12 x 14. Borders: left/right 4, top 4, bottom 6.
FRAMES["button"] = {
    "rows": [
        "..KKKKKKKK..",
        ".KWHHHHHHHK.",
        "KHHFFFFFFHHK",
        "KHFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KSSSSSSSSSSK",
        "KBBBBBBBBBBK",
        "KBBBBBBBBBBK",
        "KDDDDDDDDDDK",
        ".KDDDDDDDDK.",
        "..KKKKKKKK..",
    ],
    "slice": (4, 4, 8, 8),
}
# Pressed: the face sits 2 px lower on a 1-px base (same size, so swapping images doesn't move the layout).
FRAMES["buttonDown"] = {
    "rows": [
        "............",
        "............",
        "..KKKKKKKK..",
        ".KSHHHHHHSK.",
        "KSFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KFFFFFFFFFSK",
        "KSSSSSSSSSSK",
        "KDDDDDDDDDDK",
        ".KDDDDDDDDK.",
        "..KKKKKKKK..",
    ],
    "slice": (4, 4, 8, 8),
}

# A slate slab (HUD plates, toasts, popovers): ink outline, a lit top/left edge, a dark bottom/right edge,
# an inner lip under the top edge. 10 x 10, borders 3.
FRAMES["plate"] = {
    "rows": [
        "..KKKKKK..",
        ".KEEEEEEK.",
        "KEELLLLLeK",
        "KELPPPPPeK",
        "KEPPPPPPeK",
        "KEPPPPPPeK",
        "KEPPPPPPeK",
        "KePPPPPPeK",
        ".KeeeeeeK.",
        "..KKKKKK..",
    ],
    "slice": (3, 3, 7, 7),
}

# A window (sheets, the shop, results): ink outline with 3-px stepped corners, a 3-px brass band lit from the top
# left (y highlight, Y face, O shade, o deep shade) with a rivet in each corner (R knob, r shine, O its shadow),
# an inner ink line, then the slate fill with a lit lip under the top edge and a shadowed row above the bottom.
# 18 x 18, borders 7 (14 GUI px at SliceScale 2); content padding starts at 14 px.
FRAMES["window"] = {
    "rows": [
        "...KKKKKKKKKKKK...",
        "..KyyyyyyyyyyyyK..",
        ".KyrRYYYYYYYYrROK.",
        "KyYROYYYYYYYYROOoK",
        "KyYYKKKKKKKKKKOOoK",
        "KyYYKLLLLLLLLKOOoK",
        "KyYYKLPPPPPPPKOOoK",
        "KyYYKPPPPPPPPKOOoK",
        "KyYYKPPPPPPPPKOOoK",
        "KyYYKPPPPPPPPKOOoK",
        "KyYYKPPPPPPPPKOOoK",
        "KyYYKPPPPPPPPKOOoK",
        "KyYYKddddddddKOOoK",
        "KyYYKKKKKKKKKKOOoK",
        "KyOrROOOOOOOOrROoK",
        ".KoROooooooooROoK.",
        "..KooooooooooooK..",
        "...KKKKKKKKKKKK...",
    ],
    "slice": (6, 7, 13, 12),
}


def _ribbon_rows() -> list:
    """A ribbon 40 x 30 (60 GUI px tall at SliceScale 2). The body (cols 9-30, rows 0-23) is in front; on each
    side a tail (cols 0-11, rows 8-29) hangs lower behind it, with a V notch cut into its outer end and a dark
    fold where it turns behind the body. Codes: K ink, H highlight, F face, S shade, B tail, D fold."""
    W, H = 40, 30
    g = [["." for _ in range(W)] for _ in range(H)]
    BODY_L, BODY_R, BODY_B = 9, 30, 23
    TAIL_T, TAIL_B, TAIL_W = 8, 29, 12

    def put(x, y, ch, mirror):
        xx = W - 1 - x if mirror else x
        g[y][xx] = ch

    for mirror in (False, True):
        mid = (TAIL_T + TAIL_B) / 2
        for y in range(TAIL_T, TAIL_B + 1):
            notch = max(0, 4 - int(abs(y - mid))) if abs(y - mid) < 4 else 0  # the V cut into the outer end
            for x in range(notch, TAIL_W):
                edge = x == notch or y in (TAIL_T, TAIL_B)
                if edge:
                    put(x, y, "K", mirror)
                elif y == TAIL_T + 1:
                    put(x, y, "S", mirror)
                elif y >= TAIL_B - 2:
                    put(x, y, "D", mirror)
                else:
                    put(x, y, "B", mirror)
        # the fold: below the body, where the tail turns behind it (a dark step)
        for y in range(BODY_B + 1, TAIL_B):
            for x in range(BODY_L, BODY_L + 3):
                put(x, y, "D" if x < BODY_L + 2 else "K", mirror)
    for y in range(0, BODY_B + 1):
        for x in range(BODY_L, BODY_R + 1):
            edge = x in (BODY_L, BODY_R) or y in (0, BODY_B)
            if edge:
                g[y][x] = "K"
            elif y == 1:
                g[y][x] = "H"
            elif y == 2 and x in (BODY_L + 1, BODY_L + 2):
                g[y][x] = "W"
            elif y >= BODY_B - 2:
                g[y][x] = "S"
            else:
                g[y][x] = "F"
    for (x, y) in ((BODY_L, 0), (BODY_R, 0)):
        g[y][x] = "."
    g[1][BODY_L], g[1][BODY_R] = "K", "K"
    return ["".join(r) for r in g]


FRAMES["ribbon"] = {"rows": _ribbon_rows(), "slice": (13, 3, 27, 20)}

# A recessed well (chips, counters, empty slots, progress tracks): the rim casts a shadow on the top and left,
# light catches the bottom and right. 8 x 8, borders 2.
FRAMES["well"] = {
    "rows": [
        ".KKKKKK.",
        "KxxxxxxK",
        "KxwwwwwK",
        "KxwwwwzK",
        "KxwwwwzK",
        "KxwwwwzK",
        "KwzzzzzK",
        ".KKKKKK.",
    ],
    "slice": (2, 2, 6, 6),
}

# A brass title plate with notched ends (window titles, the results ribbon's crest). Fixed height 14 art px
# (28 GUI px at scale 2); the middle stretches sideways. 12 x 14, borders 5 left/right, 0 top/bottom.
FRAMES["titlePlate"] = {
    "rows": [
        "..KKKKKKKK..",
        ".KyyyyyyyyK.",
        "KyyYYYYYYyyK",
        "KyYYYYYYYYOK",
        "KyYYYYYYYYOK",
        "KyYYYYYYYYOK",
        "KyYYYYYYYYOK",
        "KyYYYYYYYYOK",
        "KyYYYYYYYYOK",
        "KyYYYYYYYYOK",
        "KOOOOOOOOOOK",
        "KooooooooooK",
        ".KooooooooK.",
        "..KKKKKKKK..",
    ],
    "slice": (5, 2, 7, 11),
}

# A round notification badge (counts, NEW): 10 x 10, borders 4 (stays round as it widens).
FRAMES["badge"] = {
    "rows": [
        "...KKKK...",
        ".KKHHHHKK.",
        ".KHFFFFHK.",
        "KHFFFFFFSK",
        "KFFFFFFFSK",
        "KFFFFFFFSK",
        "KSFFFFFSSK",
        ".KSSSSSSK.",
        ".KKSSSSKK.",
        "...KKKK...",
    ],
    "slice": (4, 4, 6, 6),
}

def octagon_rows(n: int, ring: int = 2) -> list:
    """A medallion n x n art px (drawn unsliced at 2x: n = 16 -> 32 GUI px, 20 -> 40, 32 -> 64): an octagon with an
    ink outline, a `ring`-px ring lit from the top left (H F on the top-left half, S B on the bottom-right), an inner
    ink line and a slate well (w) for a 16 or 32 px icon.
    inside(x, y): the four corners are cut by the lines x + y >= c and its mirrors, c = round(n * 0.3)."""
    c = round(n * 0.3)

    def inside(x, y, inset=0):
        lo, hi = inset, n - 1 - inset
        if x < lo or y < lo or x > hi or y > hi:
            return False
        cc = c + inset  # one step in along a 45-degree edge is one step of x + y
        return (x + y >= cc and (n - 1 - x) + y >= cc and x + (n - 1 - y) >= cc
                and (n - 1 - x) + (n - 1 - y) >= cc)

    rows = []
    for y in range(n):
        row = ""
        for x in range(n):
            if not inside(x, y):
                row += "."
            elif not inside(x, y, 1):
                row += "K"
            elif not inside(x, y, 1 + ring):
                light = x + y < n - 1  # the top-left half catches the light
                outer = not inside(x, y, 2)
                row += ("H" if outer else "F") if light else ("B" if outer else "S")
            elif not inside(x, y, 2 + ring):
                row += "K"
            else:
                row += "w"
        rows.append(row)
    return rows


FRAMES["medallionSmall"] = {"rows": octagon_rows(16), "slice": None}  # toasts: 32 GUI px
FRAMES["medallion"] = {"rows": octagon_rows(20), "slice": None}  # the clock: 40 GUI px
FRAMES["medallionLarge"] = {"rows": octagon_rows(32, 3), "slice": None}  # the power button: 64 GUI px

# ---------------------------------------------------------------------------------------------- styles


def style_button(face: int) -> dict:
    return ramp(face)


STYLES = {
    "plate": {
        "K": INK,
        "E": P["slate600"],
        "L": P["slate700"],
        "P": P["slate800"],
        "e": P["slate900"],
    },
    "plateRaised": {  # cards inside a window, slot faces
        "K": INK,
        "E": P["slate500"],
        "L": P["slate600"],
        "P": P["slate700"],
        "e": P["slate850"],
    },
    "window": {
        "K": INK,
        "y": P["brass200"],
        "Y": P["brass400"],
        "O": P["brass500"],
        "o": P["brass600"],
        "R": P["brass200"],
        "r": P["brass100"],
        "L": P["slate700"],
        "P": P["slate800"],
        "d": P["slate850"],
    },
    # in-match sheets (province, army, powers, nations, offers, tutorial): the same grid with an iron band
    "windowIron": {
        "K": INK,
        "y": 0xC9D1E0,
        "Y": 0x8F9AB3,
        "O": 0x5F6A85,
        "o": 0x3D4660,
        "R": 0xE6EBF3,
        "r": 0xFFFFFF,
        "L": P["slate700"],
        "P": P["slate800"],
        "d": P["slate850"],
    },
    "well": {"K": INK, "x": 0x0A0D17, "w": P["slate900"], "z": P["slate850"]},
    "titlePlate": {"K": INK, "y": P["brass200"], "Y": P["brass300"], "O": P["brass500"], "o": P["brass600"]},
}


def rarity_window(c: int) -> dict:
    """A shop card's frame: the window grid with the brass band recoloured in the rarity's ramp."""
    rr = ramp(c)
    return {
        "K": INK,
        "y": rr["H"],
        "Y": rr["F"],
        "O": rr["S"],
        "o": rr["B"],
        "R": rr["H"],
        "r": rr["W"],
        "L": P["slate700"],
        "P": P["slate800"],
        "d": P["slate850"],
    }


# ---------------------------------------------------------------------------------------------- painting


def paint(frame: dict, style: dict) -> Image.Image:
    rows = frame["rows"]
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        assert len(row) == w, (y, row)
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            c = style.get(ch)
            if c is None:
                raise KeyError(f"code {ch!r} missing in style")
            px[x, y] = hx(c) + (255,)
    return img


def nine_slice(img: Image.Image, sl, scale: int, w: int, h: int) -> Image.Image:
    """Roblox ScaleType.Slice + SliceScale + Pixelated, at a target size in output pixels."""
    if sl is None:
        return img.resize((w, h), Image.NEAREST)
    x0, y0, x1, y1 = sl
    iw, ih = img.size
    xs = [0, x0, x1, iw]
    ys = [0, y0, y1, ih]
    left, right = x0 * scale, (iw - x1) * scale
    top, bottom = y0 * scale, (ih - y1) * scale
    cw = max(0, w - left - right)
    ch = max(0, h - top - bottom)
    dxs = [0, left, left + cw, w]
    dys = [0, top, top + ch, h]
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for j in range(3):
        for i in range(3):
            sx0, sx1, sy0, sy1 = xs[i], xs[i + 1], ys[j], ys[j + 1]
            dx0, dx1, dy0, dy1 = dxs[i], dxs[i + 1], dys[j], dys[j + 1]
            if sx1 <= sx0 or sy1 <= sy0 or dx1 <= dx0 or dy1 <= dy0:
                continue
            part = img.crop((sx0, sy0, sx1, sy1)).resize((dx1 - dx0, dy1 - dy0), Image.NEAREST)
            out.alpha_composite(part, (dx0, dy0))
    return out


_cache: dict = {}


def frame_image(name: str, style_key, w: int, h: int, scale: int) -> Image.Image:
    """A frame painted in a style (a STYLES key, or a dict) drawn at w x h output pixels."""
    frame = FRAMES[name]
    if isinstance(style_key, dict):
        style = style_key
        key = (name, tuple(sorted(style.items())))
    else:
        style = STYLES[style_key]
        key = (name, style_key)
    if key not in _cache:
        _cache[key] = paint(frame, style)
    return nine_slice(_cache[key], frame["slice"], scale, w, h)
