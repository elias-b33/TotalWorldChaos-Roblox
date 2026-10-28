#!/usr/bin/env python3
"""Draws the docs/images/balance_*.png charts from the CSVs the Lune scripts in tools/balance write.

    lune run tools/balance/battles && lune run tools/balance/expansion && lune run tools/balance/catchup
    python3 tools/balance/charts.py

Uses matplotlib-free Pillow drawing (matplotlib isn't installed in the cloud environment), so the charts are
plain line charts with one y-axis, a legend and light grid lines.
"""

import csv
import os
from collections import defaultdict

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "tools", "balance", "data")
OUT = os.path.join(ROOT, "docs", "images")

W, H = 1200, 720
LEFT, RIGHT, TOP, BOTTOM = 110, 40, 160, 100
SURFACE = (252, 252, 251)
INK = (11, 11, 11)
INK2 = (82, 81, 78)
GRID = (226, 225, 220)
SERIES = [(42, 120, 214), (235, 104, 52), (27, 175, 122), (237, 161, 0)]  # blue, orange, aqua, yellow
MUTED = (150, 149, 144)


def config_number(name):
    """A number from src/shared/Config.luau (e.g. "DominationShare"), so the chart's lines follow Config."""
    import re

    text = open(os.path.join(ROOT, "src", "shared", "Config.luau")).read()
    return float(re.search(r"\b" + name + r"\s*=\s*([0-9.]+)", text).group(1))


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for folder in ("/usr/share/fonts/truetype/dejavu", "/Library/Fonts", "C:/Windows/Fonts"):
        path = os.path.join(folder, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


class Chart:
    def __init__(self, title, subtitle, xlabel, ylabel, xr, yr, xticks, yticks, xfmt=str, yfmt=str):
        self.img = Image.new("RGB", (W, H), SURFACE)
        self.d = ImageDraw.Draw(self.img)
        self.xr, self.yr = xr, yr
        self.legend = []
        d = self.d
        d.text((24, 20), title, font=font(30, True), fill=INK)
        d.text((24, 62), subtitle, font=font(18), fill=INK2)
        for y in yticks:
            py = self.py(y)
            d.line([(LEFT, py), (W - RIGHT, py)], fill=GRID, width=1)
            d.text((LEFT - 12, py), yfmt(y), font=font(17), fill=INK2, anchor="rm")
        for x in xticks:
            px = self.px(x)
            d.line([(px, H - BOTTOM), (px, H - BOTTOM + 6)], fill=INK2, width=1)
            d.text((px, H - BOTTOM + 12), xfmt(x), font=font(17), fill=INK2, anchor="mt")
        d.line([(LEFT, H - BOTTOM), (W - RIGHT, H - BOTTOM)], fill=INK2, width=1)
        d.text(((LEFT + W - RIGHT) / 2, H - 38), xlabel, font=font(18), fill=INK2, anchor="mm")
        d.text((24, TOP - 30), ylabel, font=font(18), fill=INK2)

    def px(self, x):
        return LEFT + (x - self.xr[0]) / (self.xr[1] - self.xr[0]) * (W - LEFT - RIGHT)

    def py(self, y):
        return H - BOTTOM - (y - self.yr[0]) / (self.yr[1] - self.yr[0]) * (H - TOP - BOTTOM)

    def line(self, pts, color, width=3, label=None, dash=False):
        xy = [(self.px(x), self.py(y)) for x, y in pts]
        if dash:
            for i in range(len(xy) - 1):
                if i % 2 == 0:
                    self.d.line([xy[i], xy[i + 1]], fill=color, width=width)
        else:
            self.d.line(xy, fill=color, width=width, joint="curve")
        if label:
            self.legend.append((label, color))

    def hline(self, y, label):
        py = self.py(y)
        for x in range(LEFT, W - RIGHT, 14):
            self.d.line([(x, py), (min(x + 7, W - RIGHT), py)], fill=INK2, width=2)
        self.d.text((W - RIGHT - 4, py - 4), label, font=font(16), fill=INK2, anchor="rb")

    def save(self, name):
        x = 24
        y = 104
        for label, color in self.legend:
            self.d.rounded_rectangle([x, y - 7, x + 22, y + 7], radius=3, fill=color)
            self.d.text((x + 30, y), label, font=font(17), fill=INK, anchor="lm")
            x += 30 + self.d.textlength(label, font=font(17)) + 30
        os.makedirs(OUT, exist_ok=True)
        path = os.path.join(OUT, name)
        self.img.save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT))


def rows(name):
    with open(os.path.join(DATA, name), newline="") as f:
        return list(csv.DictReader(f))


def mmss(t):
    return f"{int(t) // 60}:{int(t) % 60:02d}"


def battles():
    data = defaultdict(list)
    for r in rows("battles.csv"):
        data[r["case"]].append((float(r["ratio"]), float(r["win"])))
    c = Chart(
        "Who wins a battle",
        "Attacker win chance vs. strength ratio, Monte-Carlo through Sim/Battle (tools/balance/battles.luau)",
        "attacker men : defender men",
        "attacker wins",
        (0.75, 1.5),
        (0, 1),
        [0.75, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5],
        [0, 0.25, 0.5, 0.75, 1],
        xfmt=lambda v: f"{v:.2f}".rstrip("0").rstrip("."),
        yfmt=lambda v: f"{int(v * 100)}%",
    )
    for i, case in enumerate(["Plains", "Forest/Hills", "Fort (plains)", "Fort + hills"]):
        pts = [(x, y) for x, y in data[case] if 0.75 <= x <= 1.5]
        c.line(pts, SERIES[i], label=case)
    c.save("balance_battles.png")


def peace_income():
    by = defaultdict(lambda: defaultdict(list))
    for r in rows("expansion_peace.csv"):
        net = float(r["gold_income"]) - float(r["upkeep"])
        by[r["map"]][int(r["tick"])].append(net)
    c = Chart(
        "Income in the Peace phase",
        "Median net gold per month while all 10 nations expand greedily (tools/balance/expansion.luau)",
        "match time",
        "net gold / month",
        (0, 180),
        (15, 40),
        [0, 30, 60, 90, 120, 150, 180],
        [15, 20, 25, 30, 35, 40],
        xfmt=mmss,
    )
    for i, m in enumerate(["earth", "eldmoor", "skyshards"]):
        pts = []
        for t in sorted(by[m]):
            v = sorted(by[m][t])
            pts.append((t, (v[len(v) // 2 - 1] + v[len(v) // 2]) / 2))
        c.line(pts, SERIES[i], label=m.capitalize())
    c.save("balance_peace_income.png")


def domination():
    by = defaultdict(list)
    for r in rows("expansion_war.csv"):
        if r["variant"].startswith("ffa_on"):
            by[(r["map"], r["variant"])].append((int(r["tick"]), float(r["share"])))
    c = Chart(
        "How fast someone dominates",
        "Largest nation's share of the ownable provinces, all 10 nations greedy after Peace, 5 seeds per map",
        "match time",
        "share of provinces",
        (180, 1500),
        (0, 0.55),
        [180, 300, 600, 900, 1200, 1500],
        [0, 0.1, 0.2, 0.3, 0.4, 0.5],
        xfmt=mmss,
        yfmt=lambda v: f"{int(round(v * 100))}%",
    )
    crown, win = config_number("CoalitionThreshold"), config_number("DominationShare")
    c.hline(crown, f"crown ({round(crown * 100)}%)")
    c.hline(win, f"domination ({round(win * 100)}%)")
    maps = ["earth", "eldmoor", "skyshards"]
    seen = set()
    for (m, _), pts in sorted(by.items()):
        i = maps.index(m)
        c.line(sorted(pts), SERIES[i], width=2, label=None if m in seen else m.capitalize())
        seen.add(m)
    c.save("balance_domination.png")


def catchup():
    data = rows("catchup.csv")
    c = Chart(
        "Overextension caps gold income",
        "Gross gold per month vs. provinces held, at the starting average development (tools/balance/catchup.luau)",
        "provinces held",
        "gold / month",
        (8, 80),
        (0, 180),
        [8, 20, 30, 40, 50, 60, 70, 80],
        [0, 30, 60, 90, 120, 150, 180],
    )
    c.line([(int(r["provinces"]), float(r["gold_without"])) for r in data], MUTED, label="without overextension")
    c.line([(int(r["provinces"]), float(r["gold_with"])) for r in data], SERIES[0], label="with overextension")
    c.save("balance_overextension.png")


if __name__ == "__main__":
    battles()
    peace_income()
    domination()
    catchup()
