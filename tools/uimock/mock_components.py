"""The component board: every kit component in its states, at real phone size (GUI px), drawn at 2x.

python3 -I mock_components.py OUT.png
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frameart as fa  # noqa: E402
import ui  # noqa: E402
from mock import Canvas  # noqa: E402

P = fa.P
W, H = 1040, 760
c = Canvas(W, H, bg=0x2B3A55)
# a strip of real map behind part of the board, so components are judged on the map too
c.rect(0, 0, W, H, 0x2F6BD0)
c.rect(0, 0, W, H, 0x24314A, 235)


def note(x, y, s, col=0xB8C2DD):
    c.text(x, y, s, "bodyMedium", 12, col, anchor="lm")


def head(x, y, s):
    c.text(x, y, s.upper(), "bodyHeavy", 14, P["brass300"], anchor="lm", tracking=1.2)


# ---- buttons ---------------------------------------------------------------------------------------------------
head(20, 18, "Buttons  ·  44 px tall, face = top 32 px, base 12 px")
x = 20
for col, cap in (("gold", "Play"), ("emerald", "Accept"), ("crimson", "Declare war"), ("azure", "Ally"),
                 ("royal", "Powers"), ("slateBtn", "Cancel")):
    w = c.text_size(cap, "fredoka", 17)[0] + 40
    ui.button(c, x, 34, w, 44, col, cap)
    note(x, 88, {"slateBtn": "secondary"}.get(col, col if col != "gold" else "primary (gold)"))
    x += w + 12
ui.button(c, x, 34, 96, 44, "gold", "Play", pressed=True)
note(x, 88, "pressed")
x += 108
ui.button(c, x, 34, 96, 44, "disabled", "Play")
note(x, 88, "disabled")

# ---- icon buttons, tabs, close ------------------------------------------------------------------------------------
head(20, 112, "Icon buttons 44 × 44 (32 px icon)  ·  Tabs 44 tall  ·  Close")
x = 20
for icon in ("globe", "cart", "soundOn", "back", "arrow"):
    ui.icon_button(c, x, 128, 44, "slateBtn", icon)
    x += 52
ui.icon_button(c, x, 128, 44, "slateBtn", "cart", pressed=True)
note(x, 182, "pressed")
x += 60
ui.close_button(c, x, 128)
note(x, 182, "close")
x += 64
ui.button(c, x, 128, 112, 44, "gold", "Flags", icon="flag", icon_size=16, size=16, align="left")
note(x, 182, "tab: selected")
x += 120
for icon in ("gift", "reroll", "palette"):
    ui.well(c, x, 130, 56, 40)
    c.icon(icon, x + 12, 134, 32)
    x += 60
note(x - 180, 182, "tabs: not selected (wells)")

# ---- tiles, chips, capsules, tags, badges, medallions --------------------------------------------------------------
head(20, 206, "Action tile 126 × 52  ·  Chip 28  ·  Counter 32  ·  Tag  ·  Badge  ·  Phase medallions 40")
tile = fa.style_button(P["slate700"])
tile.update({"B": 0x6E4B22, "D": 0x4E3416})
ui.BTN["build"] = tile
for i, (can, label) in enumerate(((True, "affordable"), (False, "can't afford"))):
    tx = 20 + i * 136
    c.frame("button", ui.BTN["build"] if can else ui.BTN["disabled"], tx, 222, 126, 52)
    c.icon("castle", tx + 7, 226, 32, dim=not can)
    c.text(tx + 45, 235, "Fort", "fredoka", 15, P["text"] if can else 0x8A91AD, stroke=2, anchor="lm")
    c.icon("gold", tx + 45, 244, 16, dim=not can)
    c.text(tx + 62, 253, "60", "fredoka", 14, P["brass300"] if can else P["negative"], stroke=1.5, anchor="lm")
    note(tx, 284, label)
x = 300
x += ui.chip(c, x, 226, "farm", "Plains") + 8
x += ui.chip(c, x, 226, "flag", "Zephyr", color=0x9FB4FF) + 8
ui.capsule(c, x + 12, 224, 80, "gold", "548")
note(x, 284, "counter (top bar)")
x += 106
ui.chip(c, x, 226, "check", "Equipped", color=P["brass300"], h=32)
note(x, 284, "tag")
x += 120
ui.button(c, x, 222, 60, 44, "slateBtn", icon="scroll", icon_size=32)
ui.badge(c, x + 56, 226, "3")
note(x, 284, "count badge")
x += 80
for col, icon, name in ((P["peace"], "peace", "Peace"), (P["war"], "war", "War"),
                        (P["cataclysm"], "meteor", "Cataclysm"), (P["gold"], "flag", "Results")):
    ui.medallion(c, x, 224, col, icon, size=40)
    note(x - 2, 284, name)
    x += 70 if name == "Cataclysm" else 54

# ---- toasts -------------------------------------------------------------------------------------------------------
head(20, 308, "Toasts  ·  plate 44 tall, ≤ 340 wide, medallion in the event colour")
ui.toast(c, 20, 322, 330, P["war"], "war", "Ironholds declared war on you!")
ui.toast(c, 362, 322, 230, P["peace"], "peace", "Peace with Zephyr")
ui.toast(c, 604, 322, 280, P["gold"], "trophy", "Battle won at Cinder Rock")
ui.toast(c, 20, 376, 300, P["azure"], "scroll", "Zephyr sent you an offer")
ui.toast(c, 332, 376, 270, P["slate500"], "flag", "You took Rhineland")

# ---- windows, plates, progress, reward cell -------------------------------------------------------------------------
head(20, 438, "Windows: iron in a match, brass for meta  ·  Plate  ·  Progress  ·  Reward cell")
ui.window(c, 20, 470, 148, 120, title="Nations", icon="globe", iron=True)
note(30, 504, "iron: in-match")
note(30, 520, "sheets, drawer,")
note(30, 536, "powers, offers")
ui.window(c, 178, 470, 148, 120, title="Shop", icon="cart")
ui.close_button(c, 178 + 148 - 34, 470 - 16)
note(188, 504, "brass: shop,")
note(188, 520, "season, quests,")
note(188, 536, "trophies, results")
ui.plate(c, 340, 470, 200, 56)
note(354, 498, "plate (HUD, toasts, popovers)")
c.frame("plate", "plateRaised", 340, 538, 200, 52, tint_gradient=(1.1, 0.95))
note(354, 564, "raised plate (your row, cards)")
ui.progress(c, 560, 474, 200, 0.42, h=16)
note(560, 500, "level bar: gold")
ui.progress(c, 560, 514, 200, 0.7, color=P["emerald"], h=14)
note(560, 538, "quest bar: emerald")
c.shadow("plate", "plateRaised", 780, 470, 150, 56, dy=3, alpha=0.4)
c.frame("plate", "plateRaised", 780, 470, 150, 56, tint_gradient=(1.12, 0.95))
c.icon("star", 788, 474, 48)
c.text(842, 490, "+450", "fredoka", 22, P["brass300"], stroke=2, anchor="lm")
c.text(843, 512, "XP", "body", 14, P["textDim"], anchor="lm")
note(780, 538, "reward cell (48 px icon)")

# ---- banners --------------------------------------------------------------------------------------------------
head(20, 612, "Phase banners  ·  ribbon 60 tall, hero text 30 + 3 px stroke + 3 px drop")
for i, (col, icon, txt) in enumerate(((P["crimson"], "war", "WAR!"), (P["royal"], "meteor", "CATACLYSM!"))):
    bx = 20 + i * 330
    st = fa.style_button(col)
    bw = 300
    c.shadow("ribbon", st, bx, 628, bw, 60, dy=4, alpha=0.5)
    c.frame("ribbon", st, bx, 628, bw, 60)
    tw = c.text_size(txt, "fredoka", 30, stroke=3)[0]
    c.icon(icon, bx + bw / 2 - (tw + 40) / 2, 635, 32)
    c.text(bx + bw / 2 + 20, 650, txt, "fredoka", 30, P["text"], stroke=3, drop=3, anchor="mm")

# ---- map overlays and the fallback --------------------------------------------------------------------------------
head(690, 612, "Map badges (unchanged shape)")
c.rect(690, 628, 290, 74, 0x4E8A3A)
for (bx, by, icon, txt, edge) in ((700, 640, "sword", "3k", 0xE6194B), (770, 640, "hourglass", "70%", P["gold"]),
                                  (856, 640, "battle", "", P["danger"] if "danger" in P else 0xD9434B)):
    tw = c.text_size(txt, "fredoka", 14)[0] if txt else 0
    w = 16 + 8 + (tw + 4 if txt else 0)
    c.rect(bx - 1, by - 1, w + 2, 22, edge, radius=3)
    c.rect(bx, by, w, 20, P["slate900"], radius=2)
    c.icon(icon, bx + 3, by + 2, 16)
    if txt:
        c.text(bx + 21, by + 10, txt, "fredoka", 14, P["text"], stroke=1, anchor="lm")
c.text(760, 684, "Rhineland", "body", 14, P["text"], stroke=1, anchor="mm")
ui.pip_bar(c, 800, 678, 3)

head(20, 712, "Fallback without EditableImage: same widgets, flat look")
c.shadow_rect(20, 728, 120, 24, dy=4, alpha=0.4, radius=6)
c.rect(18, 726, 124, 28, fa.INK, radius=7)
c.gradient_rect(20, 728, 120, 24, 0xF7CA5E, 0xC98E2A)
c.text(80, 740, "Play", "fredoka", 16, P["textDark"], anchor="mm")
c.rect(158, 726, 300, 28, fa.INK, radius=7)
c.rect(160, 728, 296, 24, P["slate800"], radius=6)
c.rect(160, 728, 296, 2, P["brass400"])
note(166, 740, "panel: UIStroke + UIGradient + UIShadow")
c.save(sys.argv[1])
