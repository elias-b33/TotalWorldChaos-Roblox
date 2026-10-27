"""Paint every map's in-game pixel art (PixelArt.luau, start owners) into docs/images/pixel_<map>.png.

    python3 tools/harness/paint_maps.py
"""

from __future__ import annotations

import os
import subprocess
import tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZES = {"earth": (1024, 512), "eldmoor": (1024, 512), "skyshards": (1024, 768)}


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        for name, (w, h) in SIZES.items():
            raw = os.path.join(tmp, name + ".rgba")
            subprocess.run(["lune", "run", "tools/harness/paint", name, raw], cwd=ROOT, check=True)
            with open(raw, "rb") as f:
                img = Image.frombytes("RGBA", (w, h), f.read()).convert("RGB")
            out = os.path.join(ROOT, "docs", "images", f"pixel_{name}.png")
            img.save(out, optimize=True)
            print("wrote", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
