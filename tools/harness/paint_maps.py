"""Paint every map's in-game pixel art (PixelArt.luau, start owners) into docs/images/pixel_<map>.png.

    python3 tools/harness/paint_maps.py            # the classic look, for the docs
    python3 tools/harness/paint_maps.py --themes   # every map theme on every map, into tools/harness/out/themes/
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZES = {"earth": (1024, 512), "eldmoor": (1024, 512), "skyshards": (1024, 768)}
THEMES = ["night", "winter", "autumn"]  # PixelArt.THEMES


def paint(tmp: str, name: str, size: tuple[int, int], theme: str, out: str) -> None:
    raw = os.path.join(tmp, f"{name}_{theme}.rgba")
    subprocess.run(["lune", "run", "tools/harness/paint", name, raw, theme], cwd=ROOT, check=True)
    with open(raw, "rb") as f:
        img = Image.frombytes("RGBA", size, f.read()).convert("RGB")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print("wrote", os.path.relpath(out, ROOT))


def main() -> None:
    themes = "--themes" in sys.argv
    with tempfile.TemporaryDirectory() as tmp:
        for name, size in SIZES.items():
            if themes:
                for theme in THEMES:
                    out = os.path.join(ROOT, "tools", "harness", "out", "themes", f"pixel_{name}_{theme}.png")
                    paint(tmp, name, size, theme, out)
            else:
                paint(tmp, name, size, "classic", os.path.join(ROOT, "docs", "images", f"pixel_{name}.png"))


if __name__ == "__main__":
    main()
