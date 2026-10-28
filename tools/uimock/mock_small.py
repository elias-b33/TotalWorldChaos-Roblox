"""Mockup 6: the smallest phone (667 x 375): the top bar drops Level, Rank and the nation's name (the Capital button
keeps its flag), the province sheet docks left so it never sits under the power button.

python3 -I mock_small.py BACKDROP_844x390_2x.png OUT.png
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image  # noqa: E402

import frameart as fa  # noqa: E402
import ui  # noqa: E402
from mock import S, Canvas  # noqa: E402

P = fa.P
src = Image.open(sys.argv[1]).convert("RGBA")
bg = src.crop((60 * S, 0, (60 + 667) * S, 375 * S))
c = Canvas(667, 375, bg=bg)
RHINE = 0xE8173C

c.gradient_rect(0, 0, 667, 78, fa.INK, fa.INK, 150, 0)
c.rect(12, 7, 92, 44, 0x000000, 70, radius=12)
c.rect(24, 17, 24, 24, 0xFFFFFF, 60, radius=4)
c.rect(58, 21, 16, 16, 0xFFFFFF, 45, radius=8)
c.rect(80, 21, 14, 16, 0xFFFFFF, 45, radius=3)
# Capital button shrinks to its flag; Level and Rank step aside
ui.button(c, 112, 6, 48, 44, "slateBtn")
ui.flag(c, 124, 14, RHINE, 24, 18)
ui.capsule(c, 182, 7, 72, "gold", "74")
ui.capsule(c, 276, 7, 80, "manpower", "3000")
c.shadow("well", "well", 386, 7, 76, 32, dy=3, alpha=0.35)
ui.well(c, 386, 7, 76, 32)
c.text(414, 23, "24:56", "fredoka", 18, P["text"], stroke=2, anchor="lm")
ui.medallion(c, 368, 3, P["peace"], "peace", size=40)
ui.icon_button(c, 515, 6, 44, "slateBtn", "globe")
ui.icon_button(c, 563, 6, 44, "slateBtn", "cart")
ui.icon_button(c, 611, 6, 44, "slateBtn", "soundOn")

SX, SW, SY, SH = 8, 560, 187, 180
ui.window(c, SX, SY, SW, SH, title="Rhineland", icon="crown", iron=True)
ui.close_button(c, SX + SW - 34, SY - 16)
x = SX + 16
y = SY + 22
x += ui.chip(c, x, y, "farm", "Plains") + 6
x += ui.chip(c, x, y, "flag", "Rhine", color=0xFF8A9A) + 6
ui.well(c, x, y, 62, 28)
ui.pip_bar(c, x + 10, y + 9, 3)
x += 68
ui.chip(c, x, y, "castle", "No building", color=P["textDim"])
build = fa.style_button(P["slate700"])
build.update({"B": 0x6E4B22, "D": 0x4E3416})
recruit = fa.style_button(P["slate700"])
recruit.update({"B": 0x2E6E3A, "D": 0x1F4E29})
rows = [
    [("up", "Develop", ["90"]), ("farm", "Farm", ["50"]), ("sword", "Barracks", ["40"]), ("castle", "Fort", ["60"])],
    [("infantry", "Infantry", ["10", "1k"]), ("archers", "Archers", ["15", "1k"]),
     ("cavalry", "Cavalry", ["25", "1k"]), ("berserkers", "Berserkers", ["12", "750"])],
]
for r, row in enumerate(rows):
    for i, (icon, cap, costs) in enumerate(row):
        tx = SX + 16 + i * 134
        ty = SY + 58 + r * 60
        can = int(costs[0]) <= 74
        st = (build if r == 0 else recruit) if can else ui.BTN["disabled"]
        c.frame("button", st, tx, ty, 126, 52)
        c.icon(icon, tx + 7, ty + 4, 32, dim=not can)
        c.text(tx + 45, ty + 13, cap, "fredoka", 15, P["text"] if can else 0x8A91AD, stroke=2, anchor="lm")
        cx = tx + 45
        for ci, txt in enumerate(costs):
            ic = "gold" if ci == 0 else "manpower"
            col = (P["brass300"] if ci == 0 else P["text"]) if can else (P["negative"] if ci == 0 else 0x8A91AD)
            c.icon(ic, cx, ty + 22, 16, dim=not can)
            c.text(cx + 17, ty + 31, txt, "fredoka", 14, col, stroke=1.5, anchor="lm")
            cx += 17 + c.text_size(txt, "fredoka", 14)[0] + 6
pst = dict(fa.style_button(P["royal"]))
pst["w"] = 0x2B1A4A
c.shadow("medallionLarge", pst, 591, 285, 64, 64, dy=4, alpha=0.45)
c.frame("medallionLarge", pst, 591, 285, 64, 64)
c.icon("sparkles", 607, 299, 32)
ui.chip(c, 599, 341, "charge", "0", h=28, font="fredoka", size=16, w=48)
c.save(sys.argv[2])
