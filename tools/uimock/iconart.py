"""The game's real pixel icons, read straight from src/client/IconArt.luau (PALETTE, ICONS, VARIANTS)."""
from __future__ import annotations

import os
import re

from PIL import Image

_icons: dict = {}
_palette: dict = {}
_variants: dict = {}


def load(repo: str):
    src = open(os.path.join(repo, "src/client/IconArt.luau"), encoding="utf-8").read()
    pal = re.search(r"IconArt\.PALETTE = \{(.*?)\n\}", src, re.S).group(1)
    for code, val in re.findall(r"\b(\w)\s*=\s*0x([0-9a-fA-F]{6})", pal):
        _palette[code] = int(val, 16)
    icons = re.search(r"IconArt\.ICONS = \{(.*?)\n\} ::", src, re.S).group(1)
    for name, body in re.findall(r"\n\t(\w+) = \{[^\n]*\n(.*?)\n\t\},", icons, re.S):
        rows = re.findall(r'"([^"]*)"', body)
        _icons[name] = rows
    var = re.search(r"IconArt\.VARIANTS = \{(.*?)\n\} ::", src, re.S).group(1)
    for name, base, mapping in re.findall(r'(\w+) = \{ "(\w+)", \{([^}]*)\} \}', var):
        m = dict(re.findall(r'(\w) = "(\w)"', mapping))
        _variants[name] = (base, m)


def rows(name: str):
    if name in _icons:
        return _icons[name]
    if name in _variants:
        base, m = _variants[name]
        return ["".join(m.get(ch, ch) for ch in row) for row in _icons[base]]
    raise KeyError(name)


def sprite(name: str) -> Image.Image:
    r = rows(name)
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(r[:16]):
        for x, ch in enumerate(row[:16]):
            c = _palette.get(ch)
            if c is not None:
                px[x, y] = ((c >> 16) & 255, (c >> 8) & 255, c & 255, 255)
    return img


def icon(name: str, size: int) -> Image.Image:
    return sprite(name).resize((size, size), Image.NEAREST)


def names():
    return sorted(list(_icons) + list(_variants))
