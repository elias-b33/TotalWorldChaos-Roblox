"""Before / after: python3 -I before_after.py BEFORE.png AFTER.png OUT.png [label_before] [label_after]"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402

from mock import font  # noqa: E402

before = Image.open(sys.argv[1]).convert("RGB").resize((1688, 780), Image.LANCZOS)
after = Image.open(sys.argv[2]).convert("RGB").resize((1688, 780), Image.LANCZOS)
lb = sys.argv[4] if len(sys.argv) > 4 else "Now"
la = sys.argv[5] if len(sys.argv) > 5 else "Proposed"
pad, bar = 24, 64
out = Image.new("RGB", (1688 + 2 * pad, 2 * (780 + bar) + 3 * pad // 2), (22, 26, 40))
d = ImageDraw.Draw(out)
f = font("body", 15)
y = pad // 2
for label, im in ((lb, before), (la, after)):
    d.text((pad, y + bar / 2), label, font=f, fill=(255, 244, 220), anchor="lm")
    out.paste(im, (pad, y + bar))
    y += bar + 780 + pad // 2
out.save(sys.argv[3], optimize=True)
print(sys.argv[3], out.size)
