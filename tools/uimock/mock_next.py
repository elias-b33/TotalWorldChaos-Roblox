"""Mockups for docs/NEXT_FEATURES.md (docs/images/next/), in the Slate & Brass kit of docs/UI_DIRECTION.md.

    python3 -I mock_next.py pings   BACKDROP.png OUT.png             1: the ping wheel and an ally's ping
    python3 -I mock_next.py results BACKDROP.jpg FRAME.jpg OUT.png   2: Results with the replay and the awards
    python3 -I mock_next.py frames  STRIP.jpg OUT.jpg                2b: six moments of the replay (not a phone mockup)
    python3 -I mock_next.py empire  BACKDROP.png OUT.png             3: the empire banner and the empire on the map
    python3 -I mock_next.py menu    BACKDROP.jpg OUT.png             4: the start menu's party panel and invites
    python3 -I mock_next.py draft   BACKDROP.jpg OUT.png             5: the draft with a party seated side by side

The backdrops are real harness renders (map only), made by the planning scripts described in
docs/NEXT_FEATURES.md "Mockups"; the replay frames are PixelArt paintings of a real bot match (Eldmoor, seed 7).
Every player name is made up.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402

import frameart as fa  # noqa: E402
import ui  # noqa: E402
from mock import S, Canvas, font, rgb  # noqa: E402

P = fa.P
# nation colours by colour index (tools/harness/paint.luau): 1 crimson ... 10 charcoal
NATION = {
    1: 0xE6194B, 2: 0x6C89F6, 3: 0xFFE119, 4: 0x911EB4, 5: 0xF58231,
    6: 0x469990, 7: 0xF032E6, 8: 0x3CD74B, 9: 0x9A6324, 10: 0x353535,
}


def lighten(c: int, amount: float = 0.18) -> int:
    """A nation colour made readable as text on slate (dark colours such as charcoal come up to 62% lightness)."""
    l_now = fa.colorsys.rgb_to_hls(*(v / 255 for v in fa.hx(c)))[1]
    return fa.tone(c, max(0.62, min(0.82, l_now + amount)), 0)


def backdrop(path: str) -> Canvas:
    bg = Image.open(path).convert("RGBA")
    bg.paste(bg.crop((0, 700, 120, 740)), (0, 740))  # hide the renderer's "t=..." debug label
    return Canvas(844, 390, bg=bg)


def ring(c: Canvas, cx, cy, r, color: int, width: float = 2, alpha: int = 255, fill: int | None = None,
         fill_alpha: int = 255):
    layer = Image.new("RGBA", c.img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = ((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S)
    d.ellipse(box, fill=rgb(fill, fill_alpha) if fill is not None else None, outline=rgb(color, alpha),
              width=int(width * S))
    c.img.alpha_composite(layer)


def dotted(c: Canvas, x0, y0, x1, y1, color: int, step: float = 6, size: float = 2):
    n = int(max(abs(x1 - x0), abs(y1 - y0)) / step)
    for i in range(n + 1):
        t = i / max(1, n)
        x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        c.rect(x - size / 2 - 1, y - size / 2 - 1, size + 2, size + 2, fa.INK)
        c.rect(x - size / 2, y - size / 2, size, size, color)


def topbar(c: Canvas, nation_color: int, name: str, gold: str, manpower: str, clock: str, phase: str,
           rank: str, level: str, empire: bool = False, name_w: int = 132):
    """The in-match top bar: plates in Roblox's top-bar row (docs/UI_DIRECTION.md 7.9)."""
    c.gradient_rect(0, 0, 844, 78, fa.INK, fa.INK, 150, 0)
    # Roblox's own experience controls (not ours): faint, for placement only
    c.rect(12, 7, 92, 44, 0x000000, 70, radius=12)
    c.rect(24, 17, 24, 24, 0xFFFFFF, 60, radius=4)
    c.rect(58, 21, 16, 16, 0xFFFFFF, 45, radius=8)
    c.rect(80, 21, 14, 16, 0xFFFFFF, 45, radius=3)
    ui.button(c, 112, 6, name_w, 44, "slateBtn")
    ui.flag(c, 122, 14, nation_color, 24, 18)
    if empire:  # the empire mark over the flag (the stand-in for the planned `imperial` sprite)
        c.icon("star", 126, 1, 16)
    c.text(154, 23, name, "fredoka", 18, P["text"], stroke=2, anchor="lm")
    x = 112 + name_w + 22
    ui.capsule(c, x, 7, 80, "gold", gold)
    ui.capsule(c, x + 100, 7, 86, "manpower", manpower)
    cx = x + 214
    c.shadow("well", "well", cx, 7, 80, 32, dy=3, alpha=0.35)
    ui.well(c, cx, 7, 80, 32)
    c.text(cx + 30, 23, clock, "fredoka", 18, P["text"], stroke=2, anchor="lm")
    ui.medallion(c, cx - 18, 3, P[phase], {"peace": "peace", "war": "war", "cataclysm": "meteor"}[phase], size=40)
    rx = cx + 92
    if rx + 58 + 6 + 46 < 696:
        ui.chip(c, rx, 7, "trophy", rank, h=32, font="fredoka", size=17, w=58)
        ui.chip(c, rx + 66, 7, "medal", level, h=32, font="fredoka", size=17, w=46)
    ui.icon_button(c, 696, 6, 44, "slateBtn", "globe")
    ui.icon_button(c, 744, 6, 44, "slateBtn", "cart")
    ui.icon_button(c, 792, 6, 44, "slateBtn", "soundOn")


def power_button(c: Canvas, charges: str):
    pst = dict(fa.style_button(P["royal"]))
    pst["w"] = 0x2B1A4A
    c.shadow("medallionLarge", pst, 768, 300, 64, 64, dy=4, alpha=0.45)
    c.frame("medallionLarge", pst, 768, 300, 64, 64)
    c.icon("sparkles", 784, 314, 32)
    ui.chip(c, 776, 356, "charge", charges, h=28, font="fredoka", size=16, w=48)


def ribbon(c: Canvas, cx, y, w, color: int, icon: str | None, text: str, size: float = 30, flag: int | None = None):
    st = fa.style_button(color)
    x = cx - w / 2
    c.shadow("ribbon", st, x, y, w, 60, dy=4, alpha=0.5)
    c.frame("ribbon", st, x, y, w, 60)
    tw = c.text_size(text, "fredoka", size, stroke=3)[0]
    gx = cx - (tw + 40) / 2
    if flag is not None:
        ui.flag(c, gx, y + 13, flag, 28, 21)
    elif icon:
        c.icon(icon, gx, y + 7, 32)
    c.text(gx + 40 + tw / 2, y + 22, text, "fredoka", size, P["text"], stroke=3, drop=3, anchor="mm")


# ---------------------------------------------------------------------------------------------------------------
# 1. Pings: you are Volga, allied with Niger, at war with Tigris. Niger's "Attack" ping sits on Tigris's capital;
#    you long-press your own land and the four-ping wheel opens under your finger.
# ---------------------------------------------------------------------------------------------------------------
PINGS = [  # (label, icon, enamel colour)
    ("Attack", "war", "crimson"),
    ("Defend", "powerShield", "azure"),
    ("Help", "fire", "gold"),
    ("Look", "eye", "slateBtn"),
]


def ping_marker(c: Canvas, x, y, pinger: int, icon: str, color: int, age: float = 0.4):
    """A ping on the map (MapRenderer "Pings" layer): two pulse rings in the pinger's colour round the spot, a
    32 px medallion on a stem above it, and the pinger's flag beside the medallion."""
    for r, a in ((14, 255), (22 + 8 * age, int(200 * (1 - age))), (30 + 8 * age, int(110 * (1 - age)))):
        ring(c, x, y, r + 1, fa.INK, 4, a)
        ring(c, x, y, r, pinger, 2, a)
    c.rect(x - 2, y - 30, 4, 28, fa.INK)
    c.rect(x - 1, y - 29, 2, 27, P["text"])
    ui.medallion(c, x - 16, y - 62, color, icon, size=32)
    ui.flag(c, x + 14, y - 58, pinger, 20, 15)


def pings(bg_path: str, out: str):
    c = backdrop(bg_path)
    volga, niger = NATION[2], NATION[7]
    topbar(c, volga, "Volga", "212", "9.4k", "06:05", "war", "#2", "7")

    # Niger's ping on Tigris's capital (Mesopotamia): every ally sees it for 8 s, with a toast
    ping_marker(c, 590, 332, niger, "war", P["crimson"])
    ui.toast(c, 300, 62, 300, P["crimson"], "war", "Niger: Attack · Mesopotamia")

    # your own long-press on your land east of the Volga: the wheel opens around your finger
    cx, cy = 694, 214
    ring(c, cx, cy, 88, fa.INK, 2, 140, fill=fa.INK, fill_alpha=90)
    ring(c, cx, cy, 11, fa.INK, 4, 255)
    ring(c, cx, cy, 10, P["text"], 2, 255)
    spots = [(0, -58), (58, 0), (0, 58), (-58, 0)]
    for (label, icon, color), (dx, dy) in zip(PINGS, spots):
        bx, by = cx + dx - 22, cy + dy - 30
        c.shadow("button", ui.BTN[color], bx, by, 44, 44, dy=3, alpha=0.5)
        ui.icon_button(c, bx, by, 44, color, icon)
        c.text(cx + dx, by + 51, label, "fredoka", 14, P["text"], stroke=2, anchor="mm")
    # who sees it: allies only
    ui.plate(c, cx - 64, cy - 132, 128, 30, dy=3)
    c.icon("teams", cx - 54, cy - 125, 16)
    c.text(cx - 32, cy - 117, "Allies only", "body", 15, P["text"], anchor="lm")
    power_button(c, "1")
    c.save(out)


# ---------------------------------------------------------------------------------------------------------------
# 2. Results: the Match tab. The replay plays the whole match's borders in 10 s on the left; every player who held
#    a nation gets an award on the right, in placement order. The standings and the XP breakdown are the second tab.
# ---------------------------------------------------------------------------------------------------------------
AWARDS = [  # placement, nation (Eldmoor colour index), player, award, icon, ring colour, reason, mine
    (1, "Greenvale", 5, "Mia", "Conqueror", "flag", "war", "Took 21 provinces", False),
    (2, "Corsairs", 10, "Sam", "Diplomat", "handshake", "azure", "3 alliances, 1 peace", False),
    (5, "Ironholds", 3, "Leo", "Battle Master", "war", "crimson", "66 battles won", False),
    (7, "Saltmarsh", 2, "You", "Primordial Fury", "meteor", "royal", "9 powers cast", True),
]


def results(strip_path: str, frame_path: str, out: str):
    # behind the window: the map at the end of the match (the strip's last tile), dimmed
    bg = Image.open(strip_path).convert("RGBA").crop((1024, 256, 1536, 512))
    w, h = bg.size
    scale = max(844 * S / w, 390 * S / h)
    bg = bg.resize((int(w * scale), int(h * scale)), Image.NEAREST)
    c = Canvas(844, 390, bg=bg.crop((0, 0, 844 * S, 390 * S)))
    c.dim(0.62)
    WX, WY, WW, WH = 82, 42, 680, 340
    ui.window(c, WX, WY, WW, WH)
    ribbon(c, 422, 6, 380, P["gold"], None, "GREENVALE WON", size=28, flag=NATION[5])

    # tabs on the window's top edge, right of the ribbon: Match (selected, gold) and Rewards (a well; the badge is
    # the XP the match paid)
    ui.button(c, 628, 22, 90, 44, "gold", "Match", icon="globe", icon_size=16, size=16)
    c.shadow("well", "well", 722, 24, 44, 40, dy=3, alpha=0.4)
    ui.well(c, 722, 24, 44, 40)
    c.icon("star", 728, 28, 32)
    ui.badge(c, 762, 24, "+190", "gold")

    # ---- left: the replay ------------------------------------------------------------------------------------
    LX, LW = 100, 316
    ui.well(c, LX, 76, LW, 164)
    fr = Image.open(frame_path).convert("RGBA").resize(((LW - 6) * S, 155 * S), Image.LANCZOS)
    c.paste(fr, LX + 3, 79)
    # the replay clock rides on the frame
    ui.plate(c, LX + 8, 84, 92, 30, dy=3)
    ui.medallion(c, LX + 4, 79, P["war"], "war", size=40)
    c.text(LX + 48, 99, "15:00", "fredoka", 17, P["text"], stroke=2, anchor="lm")
    # the scrubber: Peace, War, Cataclysm segments, filled to 15:00; the replay button restarts it
    ui.icon_button(c, LX, 246, 44, "slateBtn", "reroll")
    tx, tw = LX + 52, LW - 52
    ui.well(c, tx, 256, tw, 16)
    inner = tw - 6
    segs = [(0, 3, P["peace"]), (3, 20, P["war"]), (20, 25, P["cataclysm"])]
    for a, b, col in segs:
        x0, x1 = tx + 3 + inner * a / 25, tx + 3 + inner * min(b, 15) / 25
        if x1 > x0:
            r = fa.ramp(col)
            c.rect(x0, 259, x1 - x0, 10, r["F"])
            c.rect(x0, 259, x1 - x0, 2, r["H"])
        x2 = tx + 3 + inner * b / 25
        c.rect(x2 - 1, 257, 2, 14, fa.INK)
    knob = tx + 3 + inner * 15 / 25
    c.rect(knob - 5, 252, 10, 24, fa.INK)
    c.rect(knob - 3, 254, 6, 20, P["text"])
    c.text(tx + 3, 285, "0:00", "bodyMedium", 14, P["textDim"], anchor="lm")
    c.text(tx + 3 + inner, 285, "25:00", "bodyMedium", 14, P["textDim"], anchor="rm")
    c.icon("crown", LX, 300, 16)
    c.text(LX + 22, 308, "Score at 25:00 · Greenvale 1,305", "body", 15, P["brass300"], anchor="lm")

    # ---- right: one award per player, in placement order -----------------------------------------------------
    RX, RW = 440, 306
    ui.label_caps(c, RX, 92, "Awards")
    c.text(RX + RW, 92, "4 players", "bodyMedium", 14, P["textDim"], anchor="rm")
    y = 104
    for place, nation, idx, player, award, icon, ring_col, reason, mine in AWARDS:
        if mine:
            c.shadow("plate", "plateRaised", RX - 2, y - 2, RW + 4, 48, dx=0, dy=0, color=P["gold"], alpha=0.45,
                     blur=5)
        c.frame("plate", "plateRaised", RX, y, RW, 44, tint_gradient=(1.1, 0.95))
        if mine:
            c.rect(RX + 2, y + 6, 3, 32, P["brass300"])
        ui.medallion(c, RX + 8, y + 6, P[ring_col], icon, size=32)
        c.text(RX + 48, y + 14, award, "fredoka", 16, P["brass300"], stroke=1.5, anchor="lm")
        c.text(RX + 48, y + 33, reason, "bodyMedium", 14, P["textDim"], anchor="lm")
        c.text(RX + RW - 10, y + 14, player, "fredoka", 16, P["brass300"] if mine else P["text"], stroke=1.5,
               anchor="rm")
        where = f"#{place} {nation}"
        ww = c.text_size(where, "body", 14)[0]
        ui.flag(c, RX + RW - 10 - ww - 22, y + 27, NATION[idx], 16, 12)
        c.text(RX + RW - 10, y + 33, where, "body", 14, lighten(NATION[idx]), anchor="rm")
        y += 52

    # ---- footer ------------------------------------------------------------------------------------------------
    ui.button(c, LX, 326, 196, 44, "gold", "Quests · 1 to claim", icon="scroll", icon_size=32, size=16,
              align="left")
    ui.icon_button(c, LX + 204, 326, 44, "azure", "trophy")
    ui.chip(c, RX, 333, "star", "+190 XP", h=30, font="fredoka", size=16)
    ui.chip(c, RX + 100, 333, "medal", "+34", h=30, font="fredoka", size=16)
    c.icon("hourglass", RX + 176, 340, 16)
    c.text(RX + 196, 348, "Next match: 14 s", "bodyMedium", 14, P["textDim"], anchor="lm")
    c.save(out)


def frames(strip_path: str, out: str):
    """Six moments of the replay, from the strip of PixelArt paintings (3 x 2 tiles of 512 x 256)."""
    strip = Image.open(strip_path).convert("RGBA")
    band = 44
    img = Image.new("RGBA", (strip.width, strip.height + band), rgb(P["slate900"]))
    img.alpha_composite(strip, (0, band))
    d = ImageDraw.Draw(img)
    title = font("fredoka", 12)
    d.text((14, band / 2), "Results replay: six moments of one bot match (Eldmoor, seed 7), painted by PixelArt",
           font=title, fill=rgb(P["text"]), anchor="lm", stroke_width=2, stroke_fill=rgb(fa.INK))
    labels = ["0:00 Peace", "5:00 War", "10:00", "15:00", "20:00 Cataclysm", "25:00 Greenvale wins"]
    lab = font("fredoka", 12)
    for i, text in enumerate(labels):
        x, y = (i % 3) * 512 + 12, band + (i // 3) * 256 + 12
        d.text((x, y), text, font=lab, fill=rgb(P["text"]), anchor="lt", stroke_width=3, stroke_fill=rgb(fa.INK))
    img.convert("RGB").save(out, quality=88, optimize=True)
    print(out, img.size)


# ---------------------------------------------------------------------------------------------------------------
# 3. Empire: Frostmarch holds 11 of the Crownlands' 14 provinces and becomes the Crown Empire. Everyone sees the
#    ribbon; the former also gets the reward plate. On the map the empire's name lies on a plate over its land and
#    the gold empire mark tops the capital's flag pole.
# ---------------------------------------------------------------------------------------------------------------
def empire(bg_path: str, out: str):
    c = backdrop(bg_path)
    frost = NATION[4]
    topbar(c, frost, "Crown Empire", "481", "14.2k", "08:14", "war", "#1", "12", empire=True, name_w=172)

    # the empire's name over its land: one slate plate at the region's centre (the province names under it step
    # aside, as names already do for each other), its text in the nation's colour, flanked by the empire mark (`star`
    # stands in for the planned `imperial` sprite; the crown stays the coalition leader's)
    label = "CROWN EMPIRE"
    tw = c.text_size(label, "fredoka", 24, stroke=3)[0] + 3 * (len(label) - 1)
    lx, ly = 470, 318
    pw = tw + 76
    ui.plate(c, lx - pw / 2, ly - 20, pw, 40, dy=4)
    c.rect(lx - pw / 2 + 4, ly - 16, 4, 32, frost)
    c.rect(lx + pw / 2 - 8, ly - 16, 4, 32, frost)
    c.text(lx, ly - 1, label, "fredoka", 24, lighten(frost, 0.32), stroke=3, anchor="mm", tracking=3)
    c.icon("star", lx - tw / 2 - 26, ly - 9, 16)
    c.icon("star", lx + tw / 2 + 10, ly - 9, 16)
    # the capital's flag pole gets the gold empire mark on top (Hoarreach)
    c.icon("star", 375, 82, 16)

    # the banner everyone sees (2.6 s), then the former's reward plate
    ribbon(c, 422, 128, 380, P["gold"], "star", "EMPIRE FORMED!")
    PW = 384
    px = 422 - PW / 2
    ui.plate(c, px, 196, PW, 76, dy=4)
    c.text(422, 214, "Frostmarch is now the Crown Empire", "body", 15, P["text"], anchor="mm")
    cw1 = c.text_size("+10% gold", "body", 15)[0] + 34
    cw2 = c.text_size("+1 charge", "body", 15)[0] + 34
    cx0 = 422 - (cw1 + 8 + cw2) / 2
    ui.chip(c, cx0, 232, "gold", "+10% gold", color=P["brass300"])
    ui.chip(c, cx0 + cw1 + 8, 232, "charge", "+1 charge", color=P["brass300"])
    power_button(c, "2")
    c.save(out)


# ---------------------------------------------------------------------------------------------------------------
# 4. Start menu with a party: Mia came in your Roblox party, Leo got an invite. "Play online" takes everyone in
#    the party to one server.
# ---------------------------------------------------------------------------------------------------------------
def avatar(c: Canvas, x, y, letter: str, color: int, s: int = 36):
    ui.well(c, x, y, s, s)
    c.rect(x + 4, y + 4, s - 8, s - 8, color)
    c.text(x + s / 2, y + s / 2, letter, "fredoka", 18, P["text"], stroke=2, anchor="mm")


def menu(bg_path: str, out: str):
    c = backdrop(bg_path)
    c.dim(0.62)
    c.text(40, 64, "TOTAL WORLD CHAOS", "fredoka", 30, P["brass300"], stroke=3, drop=3, anchor="lm")
    c.text(42, 96, "10 nations · 25 minutes", "body", 15, P["textDim"], anchor="lm")
    ui.button(c, 40, 118, 300, 56, "gold", "Play online", icon="globe", icon_size=32, size=19)
    c.text(190, 192, "with your party of 3", "body", 14, P["brass300"], anchor="mm")
    ui.button(c, 40, 206, 300, 52, "slateBtn", "Singleplayer", icon="bot", icon_size=32, size=18)
    ui.button(c, 40, 266, 300, 52, "slateBtn", "How to play", icon="scroll", icon_size=32, size=18)

    # the party panel
    WX, WY, WW, WH = 452, 96, 360, 236
    ui.window(c, WX, WY, WW, WH, title="Party", icon="teams")
    rows = [
        ("Y", P["azure"], "You", "check", "Ready", P["positive"]),
        ("M", P["royal"], "Mia", "teams", "In your Roblox party", P["text"]),
        ("L", P["emerald"], "Leo", "hourglass", "Invite sent", P["textDim"]),
    ]
    y = WY + 24
    for letter, col, name, icon, status, scol in rows:
        c.frame("plate", "plateRaised", WX + 16, y, WW - 32, 44, tint_gradient=(1.1, 0.95))
        avatar(c, WX + 20, y + 4, letter, col)
        c.text(WX + 66, y + 22, name, "fredoka", 17, P["text"], stroke=1.5, anchor="lm")
        c.icon(icon, WX + 150, y + 14, 16)
        c.text(WX + 172, y + 22, status, "body", 14, scol, anchor="lm")
        y += 50
    ui.button(c, WX + 16, y + 4, WW - 32, 48, "emerald", "Invite friends", icon="plus", icon_size=16, size=17)
    ui.toast(c, 452, 30, 250, P["peace"], "teams", "Mia joined your party")
    c.save(out)


# ---------------------------------------------------------------------------------------------------------------
# 5. The draft with a party: party members pick one after another; Mia took Niger, so the two free nations nearest
#    to it are tagged "Next to Mia". You tapped Zambezi.
# ---------------------------------------------------------------------------------------------------------------
NATIONS_EARTH = [  # name, colour index, race icon, race, tag, taken by
    ("Zambezi", 8, "empire", "Empire", "Next to Mia", None),
    ("Tigris", 3, "clans", "Clans", "Next to Mia", None),
    ("Rhine", 1, "kingdom", "Kingdom", None, None),
    ("Niger", 7, "kingdom", "Kingdom", None, "Mia"),
    ("Volga", 2, "nomads", "Nomads", None, "Alex"),
]


def draft(bg_path: str, out: str):
    c = backdrop(bg_path)
    c.dim(0.25)
    # Mia's nation on the map: a name tag on its flag; a dotted gold line to your choice, 3 provinces away
    dotted(c, 380, 238, 446, 296, P["brass300"])
    ui.plate(c, 344, 186, 72, 28, dy=3)
    c.icon("teams", 350, 192, 16)
    c.text(370, 200, "Mia", "fredoka", 15, P["text"], stroke=1.5, anchor="lm")
    # your choice (Zambezi): a gold ring round its capital
    ring(c, 446, 296, 20, fa.INK, 5)
    ring(c, 446, 296, 19, P["gold"], 3)

    # the draft panel
    WX, WY, WW, WH = 8, 66, 312, 316
    ui.window(c, WX, WY, WW, WH, title="Pick your nation", icon="flag", iron=True)
    y = WY + 22
    # your turn, and the party's order: party members pick one after another
    ui.chip(c, WX + 16, y, "hourglass", "0:06", h=30, font="fredoka", size=16)
    c.text(WX + 96, y + 15, "Your turn", "fredoka", 17, P["brass300"], stroke=1.5, anchor="lm")
    y += 38
    x = WX + 16
    for icon, text, col in (("check", "Mia", P["positive"]), ("arrow", "You", P["brass300"]), ("hourglass", "Leo",
                                                                                              P["textDim"])):
        x += ui.chip(c, x, y, icon, text, color=col) + 6
    y += 36
    for name, idx, race_icon, race, tag, taken in NATIONS_EARTH:
        selected = name == "Zambezi"
        if selected:
            c.shadow("plate", "plateRaised", WX + 14, y - 2, WW - 28, 40, dy=0, color=P["gold"], alpha=0.5, blur=4)
        c.frame("plate", "plateRaised", WX + 16, y, WW - 32, 36, tint_gradient=(1.1, 0.95), alpha=0.6 if taken else 1)
        ui.flag(c, WX + 24, y + 9, NATION[idx], 24, 18)
        c.text(WX + 56, y + 18, name, "body", 15, lighten(NATION[idx]) if not taken else P["textDim"], anchor="lm")
        c.icon(race_icon, WX + 132, y + 10, 16, dim=bool(taken))
        if tag:
            c.icon("teams", WX + 156, y + 10, 16)
            c.text(WX + 176, y + 18, tag, "body", 14, P["brass300"], anchor="lm")
        elif taken:
            c.text(WX + WW - 26, y + 18, taken, "body", 14, P["textDim"], anchor="rm")
        y += 40

    # the race card and the confirm button for the nation you tapped
    ui.plate(c, 470, 300, 286, 36, dy=3)
    c.icon("empire", 478, 310, 16)
    c.text(500, 318, "Zambezi · Empire · +10% attack", "body", 15, P["text"], anchor="lm")
    ui.button(c, 520, 342, 186, 44, "emerald", "Pick Zambezi", icon="check", icon_size=16, size=17)
    c.save(out)


if __name__ == "__main__":
    which = sys.argv[1]
    if which == "pings":
        pings(sys.argv[2], sys.argv[3])
    elif which == "results":
        results(sys.argv[2], sys.argv[3], sys.argv[4])
    elif which == "frames":
        frames(sys.argv[2], sys.argv[3])
    elif which == "empire":
        empire(sys.argv[2], sys.argv[3])
    elif which == "menu":
        menu(sys.argv[2], sys.argv[3])
    elif which == "draft":
        draft(sys.argv[2], sys.argv[3])
    else:
        sys.exit("unknown mockup " + which)
