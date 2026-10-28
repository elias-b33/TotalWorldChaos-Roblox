"""Mockup 1: the in-match top bar and the province sheet (Rhineland, the Rhine's capital, as in the smoke test).

python3 -I mock_hud_province.py BACKDROP.png OUT.png
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
bg.paste(bg.crop((0, 700, 120, 740)), (0, 740))  # hide the renderer's "t=4s" debug label
c = Canvas(844, 390, bg=bg)

RHINE = 0xE8173C

# ---- the top bar: plates in the Roblox top-bar row (GuiService.TopbarInset), no full-width band ---------------
c.gradient_rect(0, 0, 844, 78, fa.INK, fa.INK, 150, 0)  # scrim so plates read over snow and sea
# Roblox's own experience controls live here (not ours): drawn faint for placement only
c.rect(12, 7, 92, 44, 0x000000, 70, radius=12)
c.rect(24, 17, 24, 24, 0xFFFFFF, 60, radius=4)
c.rect(58, 21, 16, 16, 0xFFFFFF, 45, radius=8)
c.rect(80, 21, 14, 16, 0xFFFFFF, 45, radius=3)

# your nation (the Capital button): flag + name on a slate enamel plate. Everything in the row centres on the
# buttons' face line (y 23), not on their boxes: the 12 px base under a button is its thickness.
ui.button(c, 112, 6, 132, 44, "slateBtn")
ui.flag(c, 122, 14, RHINE, 24, 18)
c.text(154, 23, "Rhine", "fredoka", 18, P["text"], stroke=2, anchor="lm")

ui.capsule(c, 266, 7, 80, "gold", "74", color=P["text"])
ui.capsule(c, 366, 7, 86, "manpower", "3000")
# the clock: a phase medallion (green ring = Peace) riding over the time capsule
c.shadow("well", "well", 480, 7, 80, 32, dy=3, alpha=0.35)
ui.well(c, 480, 7, 80, 32)
c.text(510, 23, "24:56", "fredoka", 18, P["text"], stroke=2, anchor="lm")
ui.medallion(c, 462, 3, P["peace"], "peace", size=40)
ui.chip(c, 572, 7, "trophy", "#1", h=32, font="fredoka", size=17, w=58)
ui.chip(c, 638, 7, "medal", "1", h=32, font="fredoka", size=17, w=46)
ui.icon_button(c, 696, 6, 44, "slateBtn", "globe")
ui.icon_button(c, 744, 6, 44, "slateBtn", "cart")
ui.icon_button(c, 792, 6, 44, "slateBtn", "soundOn")

# ---- the province sheet: a brass-framed window docked bottom centre --------------------------------------------
SX, SW, SY, SH = 142, 560, 202, 180
# UIMOCK_BAND=brass draws the brass band instead (docs/images/ui/material_ab.png compares the two)
ui.window(c, SX, SY, SW, SH, title="Rhineland", icon="crown", iron=os.environ.get("UIMOCK_BAND", "iron") == "iron")
ui.close_button(c, SX + SW - 34, SY - 16)
# info chips: terrain, owner, development (the map's pip bar), building
x = SX + 16
y = SY + 22
x += ui.chip(c, x, y, "farm", "Plains") + 6
x += ui.chip(c, x, y, "flag", "Rhine", color=0xFF8A9A) + 6
ui.well(c, x, y, 62, 28)
ui.pip_bar(c, x + 10, y + 9, 3)
x += 62 + 6
ui.chip(c, x, y, "castle", "No building", color=P["textDim"])

# action tiles: the build row on bronze-based slate tiles, the recruit row on green-based ones
build = fa.style_button(P["slate700"])
build.update({"B": 0x6E4B22, "D": 0x4E3416})
recruit = fa.style_button(P["slate700"])
recruit.update({"B": 0x2E6E3A, "D": 0x1F4E29})
ui.BTN["build"], ui.BTN["recruit"] = build, recruit
TW, TH, GAP = 126, 52, 8
gold = 74
rows = [
    [("up", "Develop", [("gold", "90")]), ("farm", "Farm", [("gold", "50")]),
     ("sword", "Barracks", [("gold", "40")]), ("castle", "Fort", [("gold", "60")])],
    [("infantry", "Infantry", [("gold", "10"), ("manpower", "1k")]),
     ("archers", "Archers", [("gold", "15"), ("manpower", "1k")]),
     ("cavalry", "Cavalry", [("gold", "25"), ("manpower", "1k")]),
     ("berserkers", "Berserkers", [("gold", "12"), ("manpower", "750")])],
]
for r, row in enumerate(rows):
    for i, (icon, cap, costs) in enumerate(row):
        tx = SX + 16 + i * (TW + GAP)
        ty = SY + 58 + r * (TH + GAP)
        can = int(costs[0][1]) <= gold
        style = ("build" if r == 0 else "recruit") if can else "disabled"
        c.frame("button", ui.BTN[style], tx, ty, TW, TH)
        c.icon(icon, tx + 7, ty + 4, 32, dim=not can)
        tc = P["text"] if can else 0x8A91AD
        c.text(tx + 45, ty + 13, cap, "fredoka", 15, tc, stroke=2, anchor="lm")
        cx = tx + 45
        for ci, (ci_icon, ci_txt) in enumerate(costs):
            col = (P["brass300"] if ci_icon == "gold" else P["text"]) if can else P["negative"]
            if not can and ci_icon != "gold":
                col = 0x8A91AD
            c.icon(ci_icon, cx, ty + 22, 16, dim=not can)
            c.text(cx + 17, ty + 31, ci_txt, "fredoka", 14, col, stroke=1.5, anchor="lm")
            cx += 17 + c.text_size(ci_txt, "fredoka", 14)[0] + 6

# ---- the Primordial power button: a royal medallion with its charges ---------------------------------------------
st = dict(fa.style_button(P["royal"]))
st["w"] = 0x2B1A4A
c.shadow("medallionLarge", st, 768, 300, 64, 64, dy=4, alpha=0.45)
c.frame("medallionLarge", st, 768, 300, 64, 64)
c.icon("sparkles", 784, 314, 32)
ui.chip(c, 776, 356, "charge", "0", h=28, font="fredoka", size=16, w=48)

c.save(sys.argv[2])
