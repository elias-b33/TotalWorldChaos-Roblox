# mapgen

Generates the three maps (Earth, Eldmoor, Skyshards) and every terrain texture in `assets/`. The design behind them is in `docs/MAPS.md`.

```bash
pip install -r tools/mapgen/requirements.txt   # numpy + Pillow
python3 tools/mapgen/generate.py               # everything, about 1–2 minutes
python3 tools/mapgen/generate.py --only tiles  # or: earth | eldmoor | skyshards
```

The output is deterministic. The run prints notes (straits it added, seeds it moved) and a `PROBLEM` line for any broken rule: disconnected land, tiny provinces, duplicate names, or more than 150 provinces.

| File | Job |
| --- | --- |
| `noise.py` | Tileable noise, cellular noise, lighting, colour ramps |
| `tiles.py` | Biome recipes and the three texture themes (`EARTH`, `FANTASY`, `SKY`) |
| `layout.py` | Land mask + seed points → provinces, neighbours, straits, start territories, balance, validation, `layout.json` |
| `export_luau.py` | `layout.json` → `src/shared/MapData/<Map>.luau` (also run by `generate.py`; run it alone to re-export without regenerating) |
| `render.py` | Terrain and political views, province id map, atlas, vote card, nation palette |
| `maps/earth.py` | Natural Earth coastlines, 150 named regions, curated sea lanes |
| `maps/fantasy.py` | Eldmoor: continent shape, zones, Dragonspine, name lists |
| `maps/sky.py` | Skyshards: symmetric shards, bridges, sky background |
| `data/land-50m.json` | Natural Earth 1:50m land (public domain) via the `world-atlas` npm package (ISC licence) |

Common edits:

- **Rename provinces or nations:** Earth `REGIONS`; Eldmoor `ZONES` and `NAME_PARTS`; Skyshards `NATIONS`, `DRIFTS`, `SANCTUMS`.
- **Move a province:** change its seed (lat/lon on Earth, pixels elsewhere) and regenerate. Borders follow automatically.
- **Change a texture:** edit the biome's parameters in `tiles.py` (colour ramps, density, sizes). `generate.py --only tiles` is quick.
- **Starting balance:** `START_SIZE` and `START_DEV` in `layout.py`.
