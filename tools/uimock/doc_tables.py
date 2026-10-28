"""Print the doc's generated tables: contrast ratios, button ramps, styles and the FrameArt grids (markdown)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frameart as fa  # noqa: E402

P = fa.P


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = fa.hx(c)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def h(c):
    return f"#{c:06x}"


print("## contrast")
pairs = [
    ("text", "slate800"), ("text", "slate900"), ("textDim", "slate800"), ("textDim", "slate900"),
    ("textDim", "slate700"), ("brass300", "slate800"), ("slate300", "slate800"), ("negative", "slate800"),
    ("negative", "slate700"), ("positive", "slate800"), ("textDark", "gold"), ("text", "emerald"),
    ("text", "crimson"), ("text", "azure"), ("text", "royal"), ("text", "slateBtn"),
]
for fg, bg in pairs:
    print(f"| `{fg}` {h(P[fg])} on `{bg}` {h(P[bg])} | {contrast(P[fg], P[bg]):.1f} : 1 |")
print(f"| disabled text #8a91ad on #3a4157 | {contrast(0x8A91AD, 0x3A4157):.1f} : 1 |")

print("\n## ramps")
print("| Button | W glint | H highlight | F face | S lower face | B base | D base bottom |")
print("| --- | --- | --- | --- | --- | --- | --- |")
for name in ("gold", "emerald", "crimson", "azure", "royal", "slateBtn"):
    r = fa.ramp(P[name])
    print(f"| `{name}` | " + " | ".join(f"`{h(r[k])}`" for k in "WHFSBD") + " |")
r = fa.ramp(0x3A4157)
print("| `disabled` | " + " | ".join(f"`{h(r[k])}`" for k in "WHFSBD") + " |")
r = fa.ramp(P["slate700"])
print("| `tile` (slate700 face) | " + " | ".join(f"`{h(r[k])}`" for k in "WHFSBD") + " |")
for name in ("peace", "war", "cataclysm"):
    r = fa.ramp(P[name])
    print(f"| `{name}` (medallion ring) | " + " | ".join(f"`{h(r[k])}`" for k in "WHFSBD") + " |")
for name in ("common", "rare", "epic", "legendary"):
    r = fa.ramp(P[name])
    print(f"| `{name}` (card band) | " + " | ".join(f"`{h(r[k])}`" for k in "WHFSBD") + " |")

print("\n## styles")
for name, st in fa.STYLES.items():
    print(f"- `{name}`: " + ", ".join(f"{k} `{h(v)}`" for k, v in st.items()))

print("\n## grids")
for name, fr in fa.FRAMES.items():
    rows = fr["rows"]
    sl = fr["slice"]
    rect = f"Rect.new({sl[0]}, {sl[1]}, {sl[2]}, {sl[3]})" if sl else "none (drawn unsliced at 2x)"
    print(f"\n`{name}`: {len(rows[0])} x {len(rows)}, SliceCenter {rect}\n")
    print("```text")
    for row in rows:
        print(row)
    print("```")
