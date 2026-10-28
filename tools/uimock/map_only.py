"""Render only the map (and optionally other named ScreenGuis) of a kept harness scene.

python3 -I map_only.py REPO SCENE.json OUT.png [Gui1,Gui2]
Runs REPO/tools/harness/render_scene.py on a filtered copy of the scene (cwd = REPO, so image paths resolve).
"""
import json
import os
import subprocess
import sys

repo, scene, out = sys.argv[1], sys.argv[2], sys.argv[3]
keep = set((sys.argv[4] if len(sys.argv) > 4 else "Map").split(","))
s = json.load(open(os.path.join(repo, scene)))
s["gui"] = [g for g in s["gui"] if g.get("name") in keep]
tmp = os.path.join(repo, scene + ".maponly.json")
json.dump(s, open(tmp, "w"))
r = subprocess.run(["python3", "tools/harness/render_scene.py", tmp, out], cwd=repo, capture_output=True, text=True)
print(r.stdout[-500:], r.stderr[-2000:])
os.remove(tmp)
