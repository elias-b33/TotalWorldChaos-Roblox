"""Mockup canvas: everything is placed in GUI px (844 x 390 phone) and drawn at 2x.

Primitives mirror what the builder implements in Roblox:
  frame()   - an ImageLabel with ScaleType.Slice, SliceScale 2, Pixelated (FrameArt)
  shadow()  - a UIShadow (BlurRadius 0 = hard pixel shadow) following a frame's shape
  text()    - a TextLabel; stroke = UIStroke Contextual (outline), drop = a second ink label offset down
  icon()    - Icons.label at 16 / 32 / 48 px (integer scales of the 16 x 16 sprites)
"""
from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import frameart as fa
import iconart

S = 2  # output px per GUI px
ART = 2  # GUI px per art px (SliceScale)
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

FONTS = {
    # Fredoka One ships with the harness (OFL); Builder Sans is stood in for by Inter, as the harness renderer does
    "fredoka": os.path.join(REPO, "tools/harness/fonts/FredokaOne-Regular.ttf"),
    "body": "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "bodyMedium": "/usr/share/fonts/opentype/inter/Inter-Medium.otf",
    "bodyHeavy": "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
}

iconart.load(REPO)
_font_cache: dict = {}


def font(key: str, size: float):
    k = (key, size)
    if k not in _font_cache:
        _font_cache[k] = ImageFont.truetype(FONTS[key], int(round(size * S)))
    return _font_cache[k]


def rgb(c: int, a: int = 255):
    return ((c >> 16) & 255, (c >> 8) & 255, c & 255, a)


class Canvas:
    def __init__(self, w: int = 844, h: int = 390, bg=None):
        self.w, self.h = w, h
        if isinstance(bg, Image.Image):
            self.img = bg.convert("RGBA").resize((w * S, h * S), Image.LANCZOS)
        else:
            self.img = Image.new("RGBA", (w * S, h * S), rgb(bg if bg is not None else fa.P["slate950"]))

    # -- primitives -------------------------------------------------------------------------------------------

    def rect(self, x, y, w, h, color: int, alpha: int = 255, radius: float = 0):
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        box = (x * S, y * S, (x + w) * S - 1, (y + h) * S - 1)
        if radius:
            d.rounded_rectangle(box, radius=radius * S, fill=rgb(color, alpha))
        else:
            d.rectangle(box, fill=rgb(color, alpha))
        self.img.alpha_composite(layer)

    def gradient_rect(self, x, y, w, h, top: int, bottom: int, top_a: int = 255, bottom_a: int = 255):
        """A Frame with a vertical UIGradient (colour and transparency)."""
        g = Image.new("RGBA", (1, max(1, h * S)))
        for i in range(h * S):
            t = i / max(1, h * S - 1)
            c0, c1 = rgb(top, top_a), rgb(bottom, bottom_a)
            g.putpixel((0, i), tuple(round(c0[k] + (c1[k] - c0[k]) * t) for k in range(4)))
        g = g.resize((w * S, h * S), Image.NEAREST)
        self.img.alpha_composite(g, (int(x * S), int(y * S)))

    def frame(self, name: str, style, x, y, w, h, tint_gradient: tuple | None = None, alpha: float = 1.0):
        """A FrameArt ImageLabel: 9-slice at SliceScale ART, pixelated. tint_gradient = (top, bottom) multipliers
        (a UIGradient on the image: top lighter, bottom darker)."""
        im = fa.frame_image(name, style, int(w * S), int(h * S), ART * S)
        if tint_gradient:
            t0, t1 = tint_gradient
            px = im.load()
            H = im.height
            for yy in range(H):
                m = t0 + (t1 - t0) * yy / max(1, H - 1)
                for xx in range(im.width):
                    r, g, b, a = px[xx, yy]
                    if a:
                        px[xx, yy] = (min(255, int(r * m)), min(255, int(g * m)), min(255, int(b * m)), a)
        if alpha < 1:
            a = im.getchannel("A").point(lambda v: int(v * alpha))
            im.putalpha(a)
        self.img.alpha_composite(im, (int(x * S), int(y * S)))
        return im

    def shadow(self, name: str, style, x, y, w, h, dx=0, dy=4, color: int = fa.INK, alpha: float = 0.45,
               blur: float = 0):
        """UIShadow: the frame's own shape, offset, in ink. blur > 0 adds a soft second shadow."""
        im = fa.frame_image(name, style, int(w * S), int(h * S), ART * S)
        mask = im.getchannel("A")
        if blur:
            pad = int(blur * S * 2)
            big = Image.new("L", (mask.width + 2 * pad, mask.height + 2 * pad), 0)
            big.paste(mask, (pad, pad))
            mask = big.filter(ImageFilter.GaussianBlur(blur * S))
            ox, oy = int((x + dx) * S) - pad, int((y + dy) * S) - pad
        else:
            ox, oy = int((x + dx) * S), int((y + dy) * S)
        layer = Image.new("RGBA", mask.size, rgb(color))
        layer.putalpha(mask.point(lambda v: int(v * alpha)))
        self.img.alpha_composite(layer, (ox, oy))

    def shadow_rect(self, x, y, w, h, dx=0, dy=4, alpha=0.45, radius=0, color=fa.INK):
        self.rect(x + dx, y + dy, w, h, color, int(255 * alpha), radius)

    def icon(self, name: str, x, y, size: int = 32, dim: bool = False, shadow: bool = False):
        im = iconart.icon(name, size * S)
        if shadow:
            sh = Image.new("RGBA", im.size, rgb(fa.INK))
            sh.putalpha(im.getchannel("A").point(lambda v: int(v * 0.5)))
            self.img.alpha_composite(sh, (int(x * S), int((y + size / 16) * S)))
        if dim:
            a = im.getchannel("A").point(lambda v: int(v * 0.45))
            im.putalpha(a)
        self.img.alpha_composite(im, (int(x * S), int(y * S)))

    def text_size(self, s: str, fkey: str, size: float, stroke: float = 0):
        f = font(fkey, size)
        bb = f.getbbox(s, stroke_width=int(stroke * S))
        return (bb[2] - bb[0]) / S, (bb[3] - bb[1]) / S

    def text(self, x, y, s: str, fkey: str, size: float, color: int = fa.P["text"], stroke: float = 0,
             stroke_color: int = fa.INK, drop: float = 0, anchor: str = "lm", alpha: int = 255,
             tracking: float = 0):
        """Text at (x, y) with a PIL anchor (l/m/r + t/m/b/s). stroke = UIStroke thickness in GUI px."""
        f = font(fkey, size)
        X, Y = x * S, y * S
        sw = int(round(stroke * S))
        d = ImageDraw.Draw(self.img)
        if tracking:
            # manual letter spacing (Roblox has none; used only to preview small caps labels)
            total = sum(f.getlength(ch) for ch in s) + tracking * S * (len(s) - 1)
            if anchor[0] == "m":
                X -= total / 2
            elif anchor[0] == "r":
                X -= total
            a2 = "l" + anchor[1]
            for ch in s:
                if drop:
                    d.text((X, Y + drop * S), ch, font=f, fill=rgb(stroke_color, alpha), anchor=a2,
                           stroke_width=sw, stroke_fill=rgb(stroke_color, alpha))
                d.text((X, Y), ch, font=f, fill=rgb(color, alpha), anchor=a2, stroke_width=sw,
                       stroke_fill=rgb(stroke_color, alpha))
                X += f.getlength(ch) + tracking * S
            return
        if drop:
            d.text((X, Y + drop * S), s, font=f, fill=rgb(stroke_color, alpha), anchor=anchor, stroke_width=sw,
                   stroke_fill=rgb(stroke_color, alpha))
        d.text((X, Y), s, font=f, fill=rgb(color, alpha), anchor=anchor, stroke_width=sw,
               stroke_fill=rgb(stroke_color, alpha))

    def line(self, x0, y0, x1, y1, color, width=1, alpha=255):
        d = ImageDraw.Draw(self.img)
        d.line((x0 * S, y0 * S, x1 * S, y1 * S), fill=rgb(color, alpha), width=int(width * S))

    def paste(self, im: Image.Image, x, y):
        self.img.alpha_composite(im, (int(x * S), int(y * S)))

    def dim(self, alpha: float = 0.45, color: int = fa.P["slate950"]):
        self.rect(0, 0, self.w, self.h, color, int(255 * alpha))

    def save(self, path: str):
        self.img.convert("RGB").save(path, optimize=True)
        print(path, self.img.size)
