"""Mockup 2: the shop, Flags tab, page 1 (the same five cards as the real screen).

python3 -I mock_shop.py BACKDROP.png OUT.png
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image  # noqa: E402

import frameart as fa  # noqa: E402
import ui  # noqa: E402
from mock import Canvas  # noqa: E402

P = fa.P
bg = Image.open(sys.argv[1]).convert("RGBA")
bg.paste(bg.crop((0, 700, 120, 740)), (0, 740))  # hide the renderer's "t=..." debug label
c = Canvas(844, 390, bg=bg)
c.dim(0.6)

RED = 0xE8173C
WX, WY, WW, WH = 8, 16, 828, 366
ui.window(c, WX, WY, WW, WH, title="Shop", icon="cart", title_x=18, title_size=20)
ui.close_button(c, WX + WW - 36, WY - 16)

# header row inside the frame: Glory, the Studio note, the pager
ui.capsule(c, 44, 34, 92, "medal", "3,000")
c.text(156, 42, "Studio test mode:", "bodyMedium", 14, P["textDim"], anchor="lm")
c.text(156, 58, "purchases are free", "bodyMedium", 14, P["textDim"], anchor="lm")
ui.icon_button(c, 652, 30, 44, "slateBtn", "back")
c.text(722, 47, "1/2", "fredoka", 17, P["text"], stroke=2, anchor="mm")
ui.icon_button(c, 748, 30, 44, "slateBtn", "arrow")

# the tab row: the chosen tab is a gold enamel tab with its icon and name, the others recessed wells
tabs = ["gift", "reroll", "flag", "border", "palette", "sword", "smile", "trophy", "frame", "meteor", "map",
        "scroll"]
inner_x, inner_w = 24, 796
unit = (inner_w - 11 * 4) / 13
x = inner_x
for i, icon in enumerate(tabs):
    if icon == "flag":
        w = unit * 2
        ui.button(c, x, 84, w, 44, "gold", "Flags", icon="flag", icon_size=16, size=16, align="left")
    else:
        w = unit
        ui.well(c, x, 84, w, 40)
        c.icon(icon, x + (w - 32) / 2, 88, 32)
    x += w + 4

# five cards: rarity frames, a lit display well, the name, the prices side by side
cards = [
    ("Banner", "Free", None, "equipped"),
    ("Tricolour", "Common", P["common"], ("49", "500")),
    ("Northern Cross", "Common", P["common"], ("49", "500")),
    ("Rising Sun", "Rare", P["rare"], ("99", "1,200")),
    ("Crown", "Rare", P["rare"], "nottoday"),
]
CW, CH, CG = 152, 206, 9
for i, (name, rarity, rcol, state) in enumerate(cards):
    cx = inner_x + i * (CW + CG)
    cy = 140
    if rcol is None:
        ui.plate(c, cx, cy, CW, CH, raised=False)
        glow = P["slate500"]
    else:
        if rarity != "Common":  # a rarity glow: a second UIShadow, blurred, in the rarity colour
            c.shadow("window", fa.rarity_window(rcol), cx, cy, CW, CH, dy=0, color=rcol, alpha=0.55, blur=7)
        ui.window(c, cx, cy, CW, CH, rarity=rcol, shadow=True)
        glow = rcol
    # rarity tag on the top edge
    tag = rarity.upper()
    tw = c.text_size(tag, "bodyHeavy", 14)[0] + 18
    tag_style = fa.style_button(rcol if rcol else P["slate500"])
    c.frame("button", tag_style, cx + (CW - tw) / 2, cy - 10, tw, 26)
    c.text(cx + CW / 2, cy + 0, tag, "bodyHeavy", 14, P["textDark"] if rcol == P["common"] else P["text"],
           anchor="mm")
    # display well with a glow in the rarity colour
    wx, wy, ww, wh = cx + 12, cy + 22, CW - 24, 78
    ui.well(c, wx, wy, ww, wh)
    c.gradient_rect(wx + 3, wy + 3, ww - 6, wh - 6, glow, glow, 110, 0)
    fx, fy, fw, fh = cx + CW / 2 - 32, wy + 15, 64, 48
    c.rect(fx - 2, fy - 2, fw + 4, fh + 4, fa.INK)
    if name == "Banner":
        c.rect(fx, fy, fw, fh, RED)
        c.rect(fx + 26, fy + 18, 12, 12, 0xFFFFFF)
    elif name == "Tricolour":
        c.rect(fx, fy, 21, fh, RED)
        c.rect(fx + 21, fy, 22, fh, 0xF4EEE0)
        c.rect(fx + 43, fy, 21, fh, 0x9A1830)
    elif name == "Northern Cross":
        c.rect(fx, fy, fw, fh, RED)
        c.rect(fx + 18, fy, 10, fh, 0xFFFFFF)
        c.rect(fx, fy + 19, fw, 10, 0xFFFFFF)
    elif name == "Rising Sun":
        c.rect(fx, fy, fw, fh, RED)
        c.rect(fx + 22, fy + 14, 20, 20, 0xFFD447)
        for dx, dy in ((-10, 0), (10, 0), (0, -10), (0, 10)):
            c.rect(fx + 28 + dx * 1.6, fy + 20 + dy * 1.2, 8, 8, 0xFFD447)
    else:
        c.rect(fx, fy, fw, fh, RED)
        c.icon("crown", fx + 16, fy + 8, 32)
    c.text(cx + CW / 2, cy + 116, name, "fredoka", 16, P["text"], stroke=2, anchor="mm")
    # the state at the bottom
    by = cy + CH - 58
    if state == "equipped":
        ui.chip(c, cx + 14, by + 6, "check", "Equipped", color=P["brass300"], h=36, w=CW - 28)
    elif state == "nottoday":
        ui.chip(c, cx + 14, by - 16, "reroll", "Not today", h=32, w=CW - 28)
        c.text(cx + CW / 2, by + 26, "Back within", "bodyMedium", 14, P["textDim"], anchor="mm")
        c.text(cx + CW / 2, by + 42, "60 days", "bodyMedium", 14, P["textDim"], anchor="mm")
    else:
        # side by side when both fit the card (fit widths), else the Glory price goes under the Robux one
        robux, glory = state
        rt = "R$ " + robux
        rw = c.text_size(rt, "fredoka", 14)[0] + 18
        gw = c.text_size(glory, "fredoka", 14)[0] + 16 + 4 + 16
        gap = 4
        total = rw + gap + gw
        sx = cx + (CW - total) / 2
        ui.button(c, sx, by, rw, 44, "emerald", rt, size=14)
        ui.button(c, sx + rw + gap, by, gw, 44, "gold", glory, icon="medal", icon_size=16, size=14,
                  align="left")
c.text(28, 362, "No random items: you always see what you get. Glory is earned by playing, never sold.",
       "bodyMedium", 14, P["textDim"], anchor="lm")
c.save(sys.argv[2])
