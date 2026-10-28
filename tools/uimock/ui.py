"""The proposed UI kit drawn in mockups. Every function is one component of docs/UI_DIRECTION.md, in GUI px."""
from __future__ import annotations

import frameart as fa
from mock import Canvas

P = fa.P
BTN = {k: fa.style_button(P[k]) for k in ("gold", "emerald", "crimson", "azure", "royal", "slateBtn")}
BTN["slot"] = fa.style_button(P["slate700"])  # province action tiles: raised slate
BTN["disabled"] = fa.style_button(0x3A4157)
WELL = "well"
DISPLAY = "fredoka"


def text_color_on(color: str) -> tuple:
    """(text colour, stroke) for a caption on a button colour."""
    if color == "gold":
        return P["textDark"], 0
    if color == "disabled":
        return 0x8A91AD, 2
    return P["text"], 2


def button(c: Canvas, x, y, w, h, color: str, caption: str = "", icon: str | None = None, icon_size: int = 16,
           size: float = 17, pressed: bool = False, align: str = "center", sub: list | None = None,
           icon_dim: bool = False):
    """An enamel button (FrameArt button / buttonDown). The face is the top h-12 px; captions centre on it."""
    st = BTN[color]
    c.frame("buttonDown" if pressed else "button", st, x, y, w, h)
    tc, sw = text_color_on(color)
    dy = 4 if pressed else 0
    face_mid = y + 2 + (h - 14) / 2 + dy
    if sub:
        face_mid -= 8
    ix = x + (8 if w < 90 else 10)
    if icon and caption and align == "center" and not sub:
        # centre the icon + caption group on the face
        group = icon_size + 6 + c.text_size(caption, DISPLAY, size, stroke=sw)[0]
        ix = x + (w - group) / 2
    if icon:
        iy = face_mid - icon_size / 2 if not sub else y + 2 + (h - 14 - icon_size) / 2 + dy
        c.icon(icon, ix, iy, icon_size, dim=icon_dim)
        ix += icon_size + (4 if w < 90 else 6)
    if caption:
        if align == "center" and not icon and not sub:
            c.text(x + w / 2, face_mid, caption, DISPLAY, size, tc, stroke=sw, anchor="mm")
        else:
            c.text(ix, face_mid, caption, DISPLAY, size, tc, stroke=sw, anchor="lm")
    if sub:  # cost line under the caption: [(icon, text, colour)]
        sx = ix
        for icn, txt, col in sub:
            c.icon(icn, sx, face_mid + 9, 16, dim=icon_dim)
            c.text(sx + 18, face_mid + 17, txt, DISPLAY, 14, col, stroke=sw, anchor="lm")
            sx += 18 + c.text_size(txt, DISPLAY, 14)[0] + 8


def icon_button(c: Canvas, x, y, s, color: str, icon: str, icon_size: int = 32, pressed: bool = False):
    st = BTN[color]
    c.frame("buttonDown" if pressed else "button", st, x, y, s, s)
    face_h = s - 14
    c.icon(icon, x + (s - icon_size) / 2, y + 1 + (face_h - icon_size) / 2 + (4 if pressed else 0), icon_size)


def well(c: Canvas, x, y, w, h):
    c.frame("well", WELL, x, y, w, h)


def chip(c: Canvas, x, y, icon: str | None, txt: str, color: int = P["text"], h: int = 28, font: str = "body",
         size: float = 15, w: float | None = None) -> float:
    tw = c.text_size(txt, font, size)[0]
    width = w or (tw + (34 if icon else 16))
    well(c, x, y, width, h)
    tx = x + 8
    if icon:
        c.icon(icon, x + 6, y + (h - 16) / 2, 16)
        tx = x + 28
    stroke = 1.5 if font == DISPLAY else 0
    c.text(tx, y + h / 2, txt, font, size, color, stroke=stroke, anchor="lm")
    return width


def capsule(c: Canvas, x, y, w, icon: str, txt: str, color: int = P["text"], h: int = 32):
    """A top-bar counter: a well capsule with a 32 px icon riding over its left end."""
    c.shadow("well", WELL, x, y, w, h, dy=3, alpha=0.35)
    well(c, x, y, w, h)
    c.icon(icon, x - 10, y + (h - 32) / 2, 32)
    c.text(x + 28, y + h / 2, txt, DISPLAY, 18, color, stroke=2, anchor="lm")


def plate(c: Canvas, x, y, w, h, raised: bool = False, shadow: bool = True, dy: int = 4):
    st = "plateRaised" if raised else "plate"
    if shadow:
        c.shadow("plate", st, x, y, w, h, dy=dy, alpha=0.45)
    c.frame("plate", st, x, y, w, h, tint_gradient=(1.06, 0.94))


def window(c: Canvas, x, y, w, h, title: str | None = None, icon: str | None = None, rarity: int | None = None,
           shadow: bool = True, title_x: float = 16, title_size: float = 19, iron: bool = False):
    """A window: brass band for meta and reward screens, iron band (iron=True) for in-match sheets, a rarity band
    for shop cards."""
    style = fa.rarity_window(rarity) if rarity is not None else ("windowIron" if iron else "window")
    if shadow:
        c.shadow("window", style, x, y, w, h, dy=6, alpha=0.5)
    c.frame("window", style, x, y, w, h, tint_gradient=(1.08, 0.9))
    if title:
        title_plate(c, x + title_x, y - 14, title, icon, size=title_size)


def title_plate(c: Canvas, x, y, title: str, icon: str | None = None, size: float = 19, h: int = 28):
    tw = c.text_size(title, DISPLAY, size, stroke=2)[0]
    w = tw + (44 if icon else 28)
    c.shadow("titlePlate", "titlePlate", x, y, w, h, dy=3, alpha=0.5)
    c.frame("titlePlate", "titlePlate", x, y, w, h)
    tx = x + 14
    if icon:
        c.icon(icon, x + 10, y + (h - 16) / 2 - 1, 16)
        tx = x + 30
    c.text(tx, y + h / 2 - 1, title, DISPLAY, size, P["text"], stroke=2, anchor="lm")
    return w


def close_button(c: Canvas, x, y, s: int = 44):
    icon_button(c, x, y, s, "crimson", "close", icon_size=16)


MEDALLIONS = {32: "medallionSmall", 40: "medallion", 64: "medallionLarge"}


def medallion(c: Canvas, x, y, phase_color: int, icon: str, size: int = 40, icon_size: int = 16,
              well: int = P["slate900"]):
    """An octagon medallion (FrameArt.octagon) at exactly 2x its art: 32, 40 or 64 GUI px."""
    name = MEDALLIONS[size]
    st = dict(fa.style_button(phase_color))
    st["w"] = well
    c.shadow(name, st, x, y, size, size, dy=3, alpha=0.4)
    c.frame(name, st, x, y, size, size)
    c.icon(icon, x + (size - icon_size) / 2, y + (size - icon_size) / 2, icon_size)


def badge(c: Canvas, x, y, txt: str, color: str = "crimson"):
    tw = c.text_size(txt, DISPLAY, 14)[0]
    w = max(22, tw + 12)
    c.frame("badge", BTN[color], x - w / 2, y - 11, w, 22)
    c.text(x, y - 1, txt, DISPLAY, 14, P["text"], stroke=1.5, anchor="mm")


def progress(c: Canvas, x, y, w, frac: float, color: int = P["gold"], h: int = 14):
    well(c, x, y, w, h)
    fw = max(0, (w - 6) * frac)
    if fw > 0:
        r = fa.ramp(color)
        c.rect(x + 3, y + 3, fw, h - 6, r["F"])
        c.rect(x + 3, y + 3, fw, 2, r["H"])
        c.rect(x + 3, y + h - 5, fw, 2, r["S"])


def toast(c: Canvas, x, y, w, color: int, icon: str, txt: str):
    plate(c, x, y, w, 44, dy=4)
    medallion(c, x + 6, y + 5, color, icon, size=32)
    c.text(x + 46, y + 21, txt, "body", 15, P["text"], anchor="lm")


def label_caps(c: Canvas, x, y, txt: str, color: int = P["slate300"], size: float = 12, anchor: str = "lm"):
    """Small caps section label (Builder Sans ExtraBold, tracked). Only 14 px+ in the game: preview here at 14."""
    c.text(x, y, txt.upper(), "bodyHeavy", 14, color, anchor=anchor, tracking=1.2)


def flag(c: Canvas, x, y, color: int, w: int = 24, h: int = 18):
    """A nation's flag as on the map (the Banner cosmetic): its colour with a white diamond."""
    c.rect(x - 1, y - 1, w + 2, h + 2, fa.INK)
    c.rect(x, y, w, h, color)
    c.rect(x, y, w, 2, fa.tone(color, min(1, fa.colorsys.rgb_to_hls(*(v / 255 for v in fa.hx(color)))[1] + 0.15), 0))
    cx, cy = x + w / 2, y + h / 2
    c.rect(cx - 2, cy - 4, 4, 8, 0xFFFFFF)
    c.rect(cx - 4, cy - 2, 8, 4, 0xFFFFFF)


def pip_bar(c: Canvas, x, y, filled: int, total: int = 5, scale: int = 2):
    """The map's development pip bar (MapBadges.pips), drawn at 2 GUI px per pixel."""
    inside, cell = 3, 4
    w, h = cell * total + 1, inside + 2
    for py in range(h):
        for px in range(w):
            cx = px % cell
            colour = fa.INK
            if cx != 0 and py not in (0, h - 1):
                if px // cell < filled:
                    colour = 0xFFF3B0 if (cx == 1 and py == 1) else (0xE39B22 if (cx == inside or py == inside)
                                                                       else 0xFFD447)
                else:
                    colour = 0x565B72
            c.rect(x + px * scale, y + py * scale, scale, scale, colour)
    return w * scale
