"""Compare (and with --fix, replace) the FrameArt grids in docs/UI_DIRECTION.md with frameart.FRAMES.

python3 -I check_appendix.py DOC.md [--fix]
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frameart as fa  # noqa: E402

doc = sys.argv[1]
fix = "--fix" in sys.argv
text = open(doc, encoding="utf-8").read()
appendix_at = text.index("## Appendix A")
head, tail = text[:appendix_at], text[appendix_at:]

names = {"button": "button", "buttonDown": "buttonDown", "plate": "plate", "window": "window", "well": "well",
         "titlePlate": "titlePlate", "badge": "badge", "ribbon": "ribbon"}
bad = 0
for doc_name, frame_name in names.items():
    m = re.search(r"\n`" + re.escape(doc_name) + r"`:[^\n]*\n\n```text\n(.*?)\n```", tail, re.S)
    if not m:
        print("missing block for", doc_name)
        bad += 1
        continue
    rows = m.group(1).split("\n")
    want = fa.FRAMES[frame_name]["rows"]
    sl = fa.FRAMES[frame_name]["slice"]
    header = m.group(0).split("\n")[1]
    if rows != want:
        bad += 1
        print("MISMATCH", doc_name)
        if fix:
            new_block = m.group(0).replace(m.group(1), "\n".join(want))
            tail = tail.replace(m.group(0), new_block)
    if sl and f"Rect.new({sl[0]}, {sl[1]}, {sl[2]}, {sl[3]})" not in header:
        bad += 1
        print("SLICE MISMATCH", doc_name, header, sl)
# the octagon example
m = re.search(r"For example, `octagon\(20, 2\)`:\n\n```text\n(.*?)\n```", tail, re.S)
if m:
    if m.group(1).split("\n") != fa.octagon_rows(20, 2):
        bad += 1
        print("MISMATCH octagon(20, 2)")
        if fix:
            tail = tail.replace(m.group(1), "\n".join(fa.octagon_rows(20, 2)))
else:
    print("missing octagon example")
    bad += 1
if fix:
    open(doc, "w", encoding="utf-8").write(head + tail)
print("problems:", bad)
