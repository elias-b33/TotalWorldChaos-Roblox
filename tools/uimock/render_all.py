"""Redraw every mockup in docs/images/ui/ (docs/UI_DIRECTION.md) from the backdrops in tools/uimock/backdrops/.

    python3 tools/uimock/render_all.py

Needs Python 3 with Pillow, Fredoka One (tools/harness/fonts) and Inter (/usr/share/fonts/opentype/inter, the
harness renderer's stand-in for Builder Sans). The backdrops are harness renders with only the map kept: run a scenario
with KEEP_SCENE=1, then map_only.py (or map_shift.py to pan the map) on the scene it saved. now_capital.png is the
current build's own render, for the before/after. font_test.png is not redrawn here (it needs Luckiest Guy, which
the repo does not ship).
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(REPO, "docs", "images", "ui")
BACK = os.path.join(HERE, "backdrops")


def run(script, *args, env=None):
    cmd = [sys.executable, "-I", os.path.join(HERE, script), *args]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    print((r.stdout + r.stderr).strip())
    if r.returncode != 0:
        sys.exit(f"{script} failed")


os.makedirs(OUT, exist_ok=True)
run("mock_hud_province.py", os.path.join(BACK, "capital_earth.png"), os.path.join(OUT, "01_hud_province.png"))
run("mock_shop.py", os.path.join(BACK, "shop_earth.png"), os.path.join(OUT, "02_shop.png"))
run("mock_results.py", os.path.join(BACK, "results_earth.jpg"), os.path.join(OUT, "03_results.png"))
run("mock_war.py", os.path.join(BACK, "war_skyshards.png"), os.path.join(OUT, "04_war.png"))
run("mock_components.py", os.path.join(OUT, "05_components.png"))
run("mock_small.py", os.path.join(BACK, "capital_earth.png"), os.path.join(OUT, "06_small_phone.png"))
run("sample_frames.py", os.path.join(OUT, "frameart_sample.png"))
run("before_after.py", os.path.join(BACK, "now_capital.png"), os.path.join(OUT, "01_hud_province.png"),
    os.path.join(OUT, "00_before_after.png"), "Now (harness render of the current build)",
    "Proposed (gold 74 here to show a disabled tile)")
with tempfile.TemporaryDirectory() as tmp:
    brass = os.path.join(tmp, "brass.png")
    run("mock_hud_province.py", os.path.join(BACK, "capital_earth.png"), brass,
        env=dict(os.environ, UIMOCK_BAND="brass"))
    run("before_after.py", brass, os.path.join(OUT, "01_hud_province.png"), os.path.join(OUT, "material_ab.png"),
        "A: brass band", "B: iron band, brass title plate (chosen for in-match sheets)")
