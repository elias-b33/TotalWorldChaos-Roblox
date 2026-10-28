"""Mockup 3: Results after a Domination win (the same content as the real Results screenshot).

python3 -I mock_results.py BACKDROP.png OUT.png
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402

import frameart as fa  # noqa: E402
import ui  # noqa: E402
from mock import S, Canvas  # noqa: E402

P = fa.P
bg = Image.open(sys.argv[1]).convert("RGBA")
bg.paste(bg.crop((0, 700, 120, 740)), (0, 740))  # hide the renderer's "t=..." debug label
c = Canvas(844, 390, bg=bg)
c.dim(0.62)


def sunburst(cx, cy, r, rays=16, color=0xFFD447, alpha=70):
    """RaysArt: a 64 x 64 pixel sunburst painted once, shown at 4x, turning slowly behind the ribbon."""
    n = 64
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = im.load()
    for y in range(n):
        for x in range(n):
            dx, dy = x - n / 2 + 0.5, y - n / 2 + 0.5
            d = math.hypot(dx, dy) / (n / 2)
            if d > 1:
                continue
            a = (math.atan2(dy, dx) / (2 * math.pi) * rays) % 1
            if a < 0.5:
                fade = (1 - d) ** 0.8
                px[x, y] = ((color >> 16) & 255, (color >> 8) & 255, color & 255, int(alpha * fade))
    big = im.resize((int(2 * r * S), int(2 * r * S)), Image.NEAREST)
    c.img.alpha_composite(big, (int((cx - r) * S), int((cy - r) * S)))


WX, WY, WW, WH = 82, 42, 680, 340
sunburst(422, 36, 230, alpha=120)
ui.window(c, WX, WY, WW, WH)

# the ribbon: gold, over the window's top edge, with the headline
RW = 340
rib = fa.style_button(P["gold"])
c.shadow("ribbon", rib, 422 - RW / 2, 6, RW, 60, dy=4, alpha=0.5)
c.frame("ribbon", rib, 422 - RW / 2, 6, RW, 60)
c.icon("trophy", 422 - 98, 13, 32)
c.text(442, 28, "YOU WIN!", "fredoka", 30, P["text"], stroke=3, drop=3, anchor="mm")

# ---- left column: how it was won, the standings, the quests ------------------------------------------------------
LX, LW = WX + 18, 316
c.icon("crown", LX, 82, 16)
c.text(LX + 22, 90, "Domination: 50% of the world", "body", 15, P["brass300"], anchor="lm")
rows = [
    (1, "Saltmarsh", 0x6C89F6, 1545, True, True),
    (2, "Mistborn", 0xE6194B, 145, False, False),
    (3, "Frostmarch", 0x911EB4, 125, False, False),
    (4, "Elderwood", 0x469990, 125, False, False),
    (5, "Wyrmcoast", 0xF032E6, 105, False, False),
]
y = 104
for rank, name, col, score, mine, winner in rows:
    if mine:
        c.frame("plate", "plateRaised", LX - 6, y - 1, LW + 6, 28, tint_gradient=(1.1, 0.95))
        c.rect(LX - 4, y + 3, 3, 20, P["brass300"])
    rc = P["brass300"] if rank == 1 else P["slate300"]
    c.text(LX + 12, y + 13, str(rank), "fredoka", 16, rc, stroke=1.5, anchor="mm")
    ui.flag(c, LX + 28, y + 6, col, 20, 15)
    lite = fa.tone(col, min(0.8, fa.colorsys.rgb_to_hls(*(v / 255 for v in fa.hx(col)))[1] + 0.18), 0)
    c.text(LX + 58, y + 13, name, "body", 16, lite, anchor="lm")
    if winner:
        c.icon("crown", LX + LW - 76, y + 5, 16)
    c.text(LX + LW - 8, y + 13, str(score), "fredoka", 16, P["text"], stroke=1.5, anchor="rm")
    y += 28
y += 4
for icon, text, col in (
    ("check", "Finish in the top 3: done!", P["brass300"]),
    ("check", "Win a match: done!", P["brass300"]),
    ("trophy", "Unlocked: Domination, Victor, Empire…", P["brass300"]),
):
    c.icon(icon, LX, y, 16)
    c.text(LX + 22, y + 8, text, "body", 14, col, anchor="lm")
    y += 20

# ---- right column: the reward cells, the breakdown, the level ----------------------------------------------------
RX, RWD = 440, 306
for i, (icon, amount, unit) in enumerate((("star", "+450", "XP"), ("medal", "+835", "Glory"))):
    cx = RX + i * (RWD / 2 + 4)
    cw = RWD / 2 - 4
    c.shadow("plate", "plateRaised", cx, 78, cw, 56, dy=3, alpha=0.4)
    c.frame("plate", "plateRaised", cx, 78, cw, 56, tint_gradient=(1.12, 0.95))
    c.icon(icon, cx + 8, 82, 48)
    c.text(cx + 62, 98, amount, "fredoka", 22, P["brass300"], stroke=2, anchor="lm")
    c.text(cx + 63, 120, unit, "body", 14, P["textDim"], anchor="lm")
ui.well(c, RX, 142, RWD, 132)
c.icon("star", RX + RWD - 98, 148, 16)
c.icon("medal", RX + RWD - 38, 148, 16)
lines = [
    ("flag", "Finished", "+100", "+20", None),
    ("trophy", "Place #1", "+150", "+40", None),
    ("blessing", "First match today", "+200", "+50", None),
    ("up", "Level up", "", "+50", P["brass300"]),
    ("check", "Play calendar 1/7", "", "+25", None),
    ("trophy", "Achievements", "", "+650", None),
]
ly = 168
for icon, label, xp, glory, col in lines:
    c.icon(icon, RX + 10, ly, 16)
    c.text(RX + 32, ly + 8, label, "body", 14, col or P["text"], anchor="lm")
    if xp:
        c.text(RX + RWD - 72, ly + 8, xp, "fredoka", 14, col or P["text"], stroke=1.2, anchor="rm")
    c.text(RX + RWD - 12, ly + 8, glory, "fredoka", 14, col or P["text"], stroke=1.2, anchor="rm")
    ly += 17
c.icon("up", RX, 282, 16)
c.text(RX + 22, 290, "Level 2! · Settler", "fredoka", 17, P["brass300"], stroke=2, anchor="lm")
ui.progress(c, RX, 304, RWD - 104, 150 / 360, h=16)
c.text(RX + RWD, 312, "150 / 360 XP", "body", 14, P["text"], anchor="rm")

# ---- footer ------------------------------------------------------------------------------------------------------
ui.button(c, LX, 326, 214, 44, "gold", "Quests · 2 to claim", icon="scroll", icon_size=32, size=16, align="left")
ui.icon_button(c, LX + 222, 326, 44, "azure", "trophy")
c.icon("hourglass", LX + 282, 334, 16)
c.text(LX + 304, 342, "Next match starts soon", "bodyMedium", 14, P["textDim"], anchor="lm")
c.icon("medal", RX + 166, 334, 16)
c.text(RX + 188, 342, "835 Glory", "body", 14, P["textDim"], anchor="lm")
c.save(sys.argv[2])
