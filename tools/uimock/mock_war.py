"""Mockup 4: the start of the War phase on Skyshards: the WAR! ribbon, a toast, the top bar's red medallion and
the army sheet with its route preview (the same army and route as the war test's first screenshot).

python3 -I mock_war.py BACKDROP.png OUT.png
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
bg.paste(bg.crop((0, 700, 120, 740)), (0, 740))
c = Canvas(844, 390, bg=bg)
AURORA = 0xE6194B

# ---- top bar, War phase ----------------------------------------------------------------------------------------
c.gradient_rect(0, 0, 844, 78, fa.INK, fa.INK, 150, 0)
c.rect(12, 7, 92, 44, 0x000000, 70, radius=12)
c.rect(24, 17, 24, 24, 0xFFFFFF, 60, radius=4)
c.rect(58, 21, 16, 16, 0xFFFFFF, 45, radius=8)
c.rect(80, 21, 14, 16, 0xFFFFFF, 45, radius=3)
ui.button(c, 112, 6, 132, 44, "slateBtn")
ui.flag(c, 122, 14, AURORA, 24, 18)
c.text(154, 23, "Aurora", "fredoka", 18, P["text"], stroke=2, anchor="lm")
ui.capsule(c, 266, 7, 80, "gold", "370")
ui.capsule(c, 366, 7, 86, "manpower", "17.0k")
c.shadow("well", "well", 480, 7, 80, 32, dy=3, alpha=0.35)
ui.well(c, 480, 7, 80, 32)
c.text(510, 23, "21:58", "fredoka", 18, P["text"], stroke=2, anchor="lm")
ui.medallion(c, 462, 3, P["war"], "war", size=40)
ui.chip(c, 572, 7, "trophy", "#1", h=32, font="fredoka", size=17, w=58)
ui.chip(c, 638, 7, "medal", "1", h=32, font="fredoka", size=17, w=46)
ui.icon_button(c, 696, 6, 44, "slateBtn", "globe")
ui.icon_button(c, 744, 6, 44, "slateBtn", "cart")
ui.icon_button(c, 792, 6, 44, "slateBtn", "soundOn")

# ---- the toast, under the top bar ------------------------------------------------------------------------------
ui.toast(c, 452, 62, 300, P["war"], "war", "Zephyr declared war on you!")

# ---- the WAR! banner: a crimson ribbon popping in (0.6 -> 1.08 -> 1), a shine band sweeping across --------------
st = fa.style_button(P["crimson"])
BW, BY = 300, 128
bx = 422 - BW / 2
c.shadow("ribbon", st, bx, BY, BW, 60, dy=4, alpha=0.5)
c.frame("ribbon", st, bx, BY, BW, 60)
# the shine sweep (a UIGradient band on the ribbon, offset tweened from -1 to 1)
for i in range(14):
    xx = bx + 150 + i - 30
    c.line(xx, BY + 3, xx + 22, BY + 43, 0xFFFFFF, width=1, alpha=int(60 * (1 - abs(i - 7) / 7)))
c.icon("war", 422 - 74, BY + 7, 32)
c.text(442, BY + 22, "WAR!", "fredoka", 30, P["text"], stroke=3, drop=3, anchor="mm")

# ---- the army sheet ------------------------------------------------------------------------------------------------
SX, SW, SY, SH = 200, 444, 236, 146
ui.window(c, SX, SY, SW, SH, title="3k at Aurora Landing", icon="sword", iron=True)
ui.close_button(c, SX + SW - 34, SY - 16)
ui.chip(c, SX + 16, SY + 22, "infantry", "3k Infantry")
c.icon("clock", SX + 16, SY + 62, 16)
c.text(SX + 38, SY + 70, "Cinder Rock", "body", 15, P["text"], anchor="lm")
c.text(SX + 132, SY + 70, "·  18 s march", "body", 15, P["textDim"], anchor="lm")
ui.button(c, SX + 16, SY + 86, 200, 44, "emerald", "Go", icon="check", icon_size=16, size=17)
ui.button(c, SX + 228, SY + 86, 200, 44, "slateBtn", "Cancel", icon="close", icon_size=16, size=17)

# ---- the power button --------------------------------------------------------------------------------------------
pst = dict(fa.style_button(P["royal"]))
pst["w"] = 0x2B1A4A
c.shadow("medallionLarge", pst, 768, 300, 64, 64, dy=4, alpha=0.45)
c.frame("medallionLarge", pst, 768, 300, 64, 64)
c.icon("sparkles", 784, 314, 32)
ui.chip(c, 776, 356, "charge", "0", h=28, font="fredoka", size=16, w=48)
c.save(sys.argv[2])
