"""Generate every texture and map image in assets/.

    python3 tools/mapgen/generate.py                 # everything (about 2 minutes)
    python3 tools/mapgen/generate.py --only tiles    # just the terrain tiles
    python3 tools/mapgen/generate.py --only materials  # the 1024 px texture pack (material variants)
    python3 tools/mapgen/generate.py --only earth    # one map: earth | eldmoor | skyshards

Output is deterministic: the same code always produces the same files.
"""

from __future__ import annotations

import argparse
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import export_luau  # noqa: E402
import materials  # noqa: E402
import render  # noqa: E402
import shapes  # noqa: E402
from layout import to_json, validate, write_json  # noqa: E402
from maps import earth, fantasy, sky  # noqa: E402
from tiles import THEMES, detail_of, make_tile  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ASSETS = os.path.join(ROOT, "assets")
SHEETS = os.path.join(ROOT, "docs", "images")

MAPS = {
    "earth": (earth, "earth", "Earth", "The real world · 150 provinces · 10 river nations"),
    "eldmoor": (fantasy, "fantasy", "Eldmoor", "Fantasy continent · 146 provinces · hold the Crownlands"),
    "skyshards": (sky, "sky", "Skyshards", "Floating islands · 131 provinces · perfectly fair"),
}


def save(img: Image.Image, *parts: str) -> str:
    """PNG for anything read by code or uploaded as a texture, JPEG for preview pictures."""
    path = os.path.join(*parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if path.endswith(".jpg"):
        img.convert("RGB").save(path, quality=90, optimize=True)
    else:
        img.save(path, optimize=True)
    return path


def to_img(a: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def make_tiles() -> None:
    for theme, biomes in THEMES.items():
        cell, cols = 256, 5
        rows = (len(biomes) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 26)), (18, 18, 22))
        d = ImageDraw.Draw(sheet)
        for i, b in enumerate(biomes):
            tile = make_tile(theme, b.key)
            save(to_img(tile), ASSETS, "textures", theme, f"{b.key}.png")
            if b.terrain not in ("Water", "Bridge"):
                save(to_img(detail_of(tile)), ASSETS, "textures", theme, "detail", f"{b.key}.png")
            x, y = (i % cols) * cell, (i // cols) * (cell + 26)
            sheet.paste(to_img(np.tile(tile, (2, 2, 1))).resize((cell, cell), Image.LANCZOS), (x, y + 26))
            d.text((x + 6, y + 4), f"{b.label} · {b.terrain}", font=render.font(15), fill=(235, 235, 235))
        save(sheet, SHEETS, f"tiles_{theme}.jpg")
        print(f"tiles: {theme} ({len(biomes)})", flush=True)


def make_map(key: str) -> None:
    mod, style, title, subtitle = MAPS[key]
    t0 = time.time()
    lay = mod.build()
    lay.shapes, lay.borders = shapes.province_shapes(lay.labels, len(lay.seeds))
    problems = validate(lay)
    for i, sh in enumerate(lay.shapes):
        if not sh["tris"]:
            problems.append(f"province '{lay.seeds[i].name}' has no shape")
    out = os.path.join(ASSETS, "maps", key)
    os.makedirs(out, exist_ok=True)
    write_json(lay, os.path.join(out, "layout.json"))
    export_luau.write(to_json(lay))
    bg = mod.background(lay)
    terrain = render.render(lay, bg, style)
    political = render.render(lay, bg, style, political=True)
    save(terrain, out, "terrain.jpg")
    save(political, out, "political.jpg")
    save(render.atlas(terrain, lay), out, "atlas.jpg")
    save(render.id_map(lay), out, "province_ids.png")
    save(render.vote_card(political, title, subtitle), out, "vote_card.jpg")
    small = political.resize((1024, int(1024 * political.height / political.width)), Image.LANCZOS)
    save(small, SHEETS, f"map_{key}.jpg")
    print(f"map: {key} ({len(lay.seeds)} provinces, {time.time() - t0:.0f}s)", flush=True)
    for n in lay.notes:
        print(f"  note: {n}")
    for p in problems:
        print(f"  PROBLEM: {p}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", choices=["tiles", "materials", *MAPS.keys()])
    args = ap.parse_args()
    if args.only in (None, "tiles"):
        make_tiles()
    if args.only in (None, "materials"):
        materials.build(os.path.join(ASSETS, "textures", "hd"), os.path.join(SHEETS, "materials.jpg"), render.font(15))
    for key in MAPS:
        if args.only in (None, key):
            make_map(key)


if __name__ == "__main__":
    main()
