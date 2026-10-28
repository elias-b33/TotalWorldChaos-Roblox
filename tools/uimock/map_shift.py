"""Render only the map of a kept harness scene, with the canvas panned by (dx, dy) GUI px.

python3 -I map_shift.py REPO SCENE.json OUT.png DX DY
"""
import json
import os
import subprocess
import sys

repo, scene, out, dx, dy = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
s = json.load(open(os.path.join(repo, scene)))
s["gui"] = [g for g in s["gui"] if g.get("name") == "Map"]
canvas = s["gui"][0]["children"][0]["children"][0]
assert canvas["name"] == "Canvas"
canvas["position"][1] += dx
canvas["position"][3] += dy
tmp = os.path.join(repo, scene + ".shift.json")
json.dump(s, open(tmp, "w"))
r = subprocess.run(["python3", "tools/harness/render_scene.py", tmp, out], cwd=repo, capture_output=True, text=True)
print(r.stdout[-300:], r.stderr[-1500:])
os.remove(tmp)
