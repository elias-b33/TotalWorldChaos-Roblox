"""The painted sample: each FrameArt frame at 1x (magnified, with its 9-slice lines and SliceCenter) and the same
frame assembled at phone sizes (SliceScale 2, drawn at 2x). python3 -I sample_frames.py OUT.png"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402

import frameart as fa  # noqa: E402
from mock import S, Canvas  # noqa: E402

P = fa.P
MAG = 12  # magnification of the 1x art (output px per art px)

items = [
    ("button", fa.style_button(P["gold"]), "button (gold)", [(140, 44), (96, 52)]),
    ("buttonDown", fa.style_button(P["gold"]), "buttonDown (pressed)", [(140, 44)]),
    ("button", fa.style_button(P["emerald"]), "button (emerald)", [(96, 44)]),
    ("plate", "plate", "plate", [(180, 44), (120, 60)]),
    ("window", "window", "window (brass: meta)", [(220, 110)]),
    ("window", "windowIron", "window (iron: in-match sheets)", [(220, 110)]),
    ("window", fa.rarity_window(P["epic"]), "window (Epic card)", [(110, 140)]),
    ("well", "well", "well", [(120, 28), (80, 32)]),
    ("titlePlate", "titlePlate", "titlePlate", [(150, 28)]),
    ("badge", fa.style_button(P["crimson"]), "badge", [(22, 22), (36, 22)]),
    ("medallion", dict(fa.style_button(P["war"]), w=P["slate900"]), "medallion (octagon(20))", [(40, 40)]),
    ("medallionLarge", dict(fa.style_button(P["royal"]), w=0x2B1A4A), "medallionLarge (octagon(32, 3))",
     [(64, 64)]),
    ("ribbon", fa.style_button(P["crimson"]), "ribbon", [(300, 60)]),
]

W, H = 1180, 1488
c = Canvas(W, H, bg=0x26324A)
c.text(20, 22, "FrameArt: pixel frames painted at runtime into EditableImages, shown as 9-slice ImageLabels",
       "body", 16, P["text"], anchor="lm")
c.text(20, 42, "Left: the 1x art (x6 of a phone's GUI px), red lines = SliceCenter. Right: the same image at phone "
       "size, SliceScale 2, ResampleMode Pixelated.", "bodyMedium", 13, P["textDim"], anchor="lm")

x, y = 20, 64
col_w = 580
row_h = 0
for i, (name, style, label, sizes) in enumerate(items):
    frame = fa.FRAMES[name]
    st = style if isinstance(style, dict) else fa.STYLES[style]
    art = fa.paint(frame, st)
    big = art.resize((art.width * MAG, art.height * MAG), Image.NEAREST)
    # checker behind the art so transparency shows
    chk = Image.new("RGBA", big.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(chk)
    for yy in range(0, big.height, 8):
        for xx in range(0, big.width, 8):
            if (xx // 8 + yy // 8) % 2 == 0:
                d.rectangle((xx, yy, xx + 7, yy + 7), fill=(255, 255, 255, 22))
    chk.alpha_composite(big)
    sl = frame["slice"]
    if sl:
        d = ImageDraw.Draw(chk)
        x0, y0, x1, y1 = (v * MAG for v in sl)
        for xx in (x0, x1):
            for yy in range(0, chk.height, 6):
                d.line((xx, yy, xx, yy + 3), fill=(255, 70, 70, 255), width=2)
        for yy in (y0, y1):
            for xx in range(0, chk.width, 6):
                d.line((xx, yy, xx + 3, yy), fill=(255, 70, 70, 255), width=2)
    bw = chk.width / S
    bh = chk.height / S
    if x + col_w > W:
        x = 20
        y += row_h + 24
        row_h = 0
    c.paste(chk, x, y + 18)
    rect = f"Rect.new({sl[0]}, {sl[1]}, {sl[2]}, {sl[3]})" if sl else "no slicing (Stretch at 2x)"
    c.text(x, y + 6, f"{label}: {art.width} x {art.height}, SliceCenter = {rect}", "body", 13, P["brass300"],
           anchor="lm")
    ax = x + bw + 16
    ay = y + 18
    for (sw, sh) in sizes:
        c.frame(name, style, ax, ay, sw, sh)
        c.text(ax, ay + sh + 10, f"{sw} x {sh}", "bodyMedium", 12, P["textDim"], anchor="lm")
        ax += max(sw, 56) + 16
    row_h = max(row_h, bh + 18, 18 + max(sh for _, sh in sizes) + 20)
    x += col_w

# the algorithm, in brief (docs/UI_DIRECTION.md "FrameArt" has the full version)
y += row_h + 30
ui_x = 20
c.frame("plate", "plate", ui_x, y, W - 40, 168)
lines = [
    "paint(frame, style):  rows = frame.rows (strings, one char per art pixel);  buffer = W x H x 4 bytes, zero = clear",
    "    for each (x, y): code = rows[y][x];  if code ~= '.' then colour = style[code]  ->  write RGBA (alpha 255)",
    "style for a button colour = ramp(face):  W glint, H highlight (lighter, hue towards yellow), F face,",
    "    S lower face, B base, D base bottom (darker, hue towards blue), K ink #0b0d1a",
    "show: EditableImage (W x H) <- WritePixelsBuffer;  ImageLabel.ImageContent = Content.fromObject(image)",
    "    ScaleType = Slice, SliceCenter = Rect.new(frame.slice), SliceScale = 2, ResampleMode = Pixelated",
    "one image per (frame, style), painted on first use and shared by every label: about 50 images, under 100 KB",
]
for i, s in enumerate(lines):
    c.text(ui_x + 16, y + 22 + i * 21, s, "bodyMedium", 13, P["text"] if i % 2 == 0 else P["textDim"], anchor="lm")
c.save(sys.argv[1])
