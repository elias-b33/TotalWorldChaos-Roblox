# Maps and art plan

Total World Chaos ships with three maps. All three play by the same rules in `DESIGN.md`; only the geography changes, so every system (economy, armies, sieges, Primordials, bots) works on every map without special cases.

| | Earth | Eldmoor | Skyshards |
| --- | --- | --- | --- |
| Picture | ![Earth](images/map_earth.jpg) | ![Eldmoor](images/map_eldmoor.jpg) | ![Skyshards](images/map_skyshards.jpg) |
| Idea | The real world, 1:1 coastlines | Fantasy continent around a rich heartland | A shattered world of floating islands |
| Provinces | 150 (11 mountains) | 146 (15 mountains) | 131 (11 mountains) |
| Straits | 26 sea lanes (1 wraps around the map) | 8 sea lanes | 30 rope bridges |
| Neutral at start | 59 | 51 | 40 |
| Fairness | Asymmetric geography, equal start | Semi-balanced | Perfectly symmetric |
| Feel | Familiar, epic, great for clips | Chokepoint fights over the centre | Fast and aggressive, competitive |

The pictures above show each map at the start of a match (political view: nation colours, stars on capitals, grey neutral land).

## Rules every map follows

These are checked by the generator (`tools/mapgen/layout.py`), so a map that breaks one doesn't get built.

- **10 start nations.** Each starts with **8 provinces and 17 total development**, capital at least development 3. Geography differs between maps and start spots; starting wealth never does.
- **About 40% of passable land starts neutral**, as the design doc asks.
- **One connected world.** Every passable province can reach every other one by land or strait. Mountains are impassable and never owned; they only shape the routes.
- **≤ 150 provinces** (the performance budget).
- **Straits** are extra neighbour links across water or void, exactly as in the design doc. Each map draws them in its own style: dashed sea lanes on Earth, ink sea lanes on Eldmoor, rope bridges on Skyshards.
- **Neutral garrisons** default to one regiment (1,000 men, `Config.NeutralGarrison`). A map can give a province a bigger garrison; only the two map centres do (the Crownlands and the Heartstone).

## Earth

The real world on a Miller projection, centred on 11°E so the Americas sit on the left, Asia on the right, and the Bering Strait wraps across the map edge. Coastlines come from Natural Earth (public domain).

**Names avoid modern countries.** Provinces use geographic and historic regions (Castile, Anatolia, Levant, Bengal, Formosa, Patagonia), and the ten nations are named after great rivers. That keeps the map clear of touchy borders and flags (the concern in the design doc's open questions) while staying instantly recognisable.

| Colour | Nation | Capital | Start region |
| --- | --- | --- | --- |
| 1 crimson | Rhine | Rhineland | Western Europe |
| 2 blue | Volga | Muscovy | Russia |
| 3 gold | Tigris | Mesopotamia | Middle East |
| 4 violet | Ganges | Ganges Plain | India |
| 5 orange | Yangtze | Yangtze Valley | China |
| 6 teal | Mekong | Mekong | Southeast Asia |
| 7 magenta | Niger | Niger Bend | West Africa |
| 8 lime | Zambezi | Zambezi | Southern Africa |
| 9 bronze | Mississippi | Mississippi | North America |
| 10 charcoal | Amazon | Amazonia | South America |

**How it plays**

- **Crowded Old World.** Rhine, Volga and Tigris start only a province or two apart, so Europe and the Middle East turn violent first. The Alps, Caucasus and Zagros funnel those wars.
- **The Roof of the World.** Tibet, Himalaya, Karakoram, Pamir and Hindu Kush form one impassable wall, so India and China can only reach each other through Southeast Asia or Central Asia.
- **Lonely Americas.** Mississippi and Amazon get lots of quiet expansion room but only three ways out: Greenland–Iceland in the north, the Dakar–Natal lane across the Atlantic, and the Bering Strait wrap.
- **Big empty wilds.** Siberia, Canada, the Sahara and Australia are a few huge, poor provinces. They're cheap to take and add province count (which counts towards the 40% domination win) but little development.

Sea lanes: Iceland–Scotland, Iceland–Greenland, Greenland–Laurentia, England–Seine, Latium–Numidia (Sicily), Hellas–Anatolia, Yemen–Horn, Najd–Persis (Hormuz), Lanka–Dravida, Malaya–Sumatra, Sumatra–Java, Java–Borneo, Borneo–Luzon, Luzon–Formosa, Formosa–Lingnan, Korea–Yamato, Yamato–Ezo, Ezo–Amur (Sakhalin), Java–Top End, New Guinea–Queensland, Murray–Aotearoa, Madagascar–Sofala, Antilles–Appalachia, Antilles–Yucatan, Senegambia–Sertao (Dakar–Natal), and Chukotka–Alaska (Bering, wraps). Gibraltar, the Bosporus and the Øresund are narrow enough to count as land borders.

**Balance watch (Phase 5):** win rate by start position matters most here. Volga and Yangtze (room to grow) will likely be strong and Rhine (surrounded) risky. Fix it with development and garrisons on neutral land, never with special rules.

## Eldmoor

A fantasy continent built for chokepoint fights. Ten kingdoms ring the **Crownlands**, a rich neutral heartland around Moonmere lake. The **Dragonspine** mountains wall the Crownlands off, with three passes. Crownlands provinces have development 3–4 and 3,000-man garrisons, so taking the centre is a mid-game commitment, not an opening move.

| Colour | Nation | Region | Terrain |
| --- | --- | --- | --- |
| 1 crimson | Mistborn | Isle of Mists (east island) | Wildwood, meadows |
| 2 blue | Saltmarsh | Southwest coast | Meadows, woods |
| 3 gold | Ironholds | Northeast | Highlands, frost |
| 4 violet | Frostmarch | Frozen north | Frostfields |
| 5 orange | Greenvale | Western breadbasket | Meadows |
| 6 teal | Elderwood | Great eastern forest | Wildwood |
| 7 magenta | Wyrmcoast | Northwest | Highlands, meadows |
| 8 lime | Sunscorch | Southern desert | Dunes |
| 9 bronze | Ashen Dominion | Southeast volcano | Ashlands, dunes |
| 10 charcoal | Corsairs | Corsair Isles (southwest archipelago) | Meadows, highlands |

**How it plays**

- **The Crownlands are the prize.** About 13 rich provinces sit behind three passes, so whoever holds a pass controls the centre's economy.
- **Island nations** (Mistborn, Corsairs) start safe but have to cross sea lanes to grow, like Britain and Japan on Earth. Each island group has at least two crossings, so no single army can seal one in.
- **Mount Cinder** sits inside Ashen territory as a natural fortress wall.
- **Terrain flavour is cosmetic.** Frostfields, dunes and meadows all play as Plains; ashlands and highlands play as Hills.

Province names are generated from per-region word lists (Hoarreach, Silvershade, Dunehaven). Rename anything by editing `NAME_PARTS` or the zone list in `tools/mapgen/maps/fantasy.py`. Names and terrain use separate random streams, so renaming never moves terrain.

## Skyshards (new map)

**The story:** the last war of the Primordials shattered the world. What's left floats above the clouds: ten home shards circling the **Heartstone**, the glowing core that still holds the old world's riches. Knocked-out players rise as Primordials in every match, so this is the world they broke.

**The layout:** perfectly symmetric (10-fold rotation), so every nation has exactly the same land, terrain and routes.

```text
            Heartstone (20 ruin provinces + central spire)
                 ▲  one long bridge per nation
   ┌─────────────┴─────────────┐
   │  Gate                     │
   │  Glade  ▲ Spire ▲  Grove  │   home shard: 8 provinces around
   │  Leeward          Windward│   an impassable storm spire
   │  Fields          Meadows  │
   │        Landing (capital)  │
   └───────────────────────────┘
 Leeward ◄─ drift isle ─► Windward of the next shard (2 provinces each)
```

- **Home shards:** 8 provinces around an impassable storm spire. The capital (Landing) is on the far side from the Heartstone, and the Gate faces it.
- **Drift isles:** 10 two-province islets between neighbouring shards. These are the first contested land.
- **The Heartstone:** 10 Approaches (development 3, 2,000-man garrisons) and 10 Sanctums (development 4, 3,000-man garrisons) around the Heartstone Spire. That's almost two-thirds of the map's neutral development in one place.

**How it plays:** every nation owns its whole shard at the start, so the Peace phase is a race for drift isles and Heartstone Approaches. It's the fastest and most aggressive map, and the one to run playtests on, because symmetry means any imbalance is the rules' fault, not the map's.

Skyshards uses no new rules: shards are islands and bridges are straits, both already in the design doc.

## Art direction

- **Map colour is power.** In the Political view each owned province shows its nation colour multiplied by a greyscale "detail" version of its terrain texture, so colour is the loudest signal but terrain still shows through. Neutral land shows washed-out terrain. Mountains always show bare rock.
- **Stylised low-poly.** Faceted peaks, round tree crowns, sculpted dunes. Every tile is lit from the top-left so the whole map shares one light.
- **One palette for nations** (`Nation.colorIndex`, 1–10). These colours stay clear of every terrain colour:

| Index | Colour | Hex |
| --- | --- | --- |
| 1 | Crimson | `#d7263d` |
| 2 | Royal blue | `#1e6fd9` |
| 3 | Gold | `#f4c430` |
| 4 | Violet | `#8e44ad` |
| 5 | Orange | `#f17c1f` |
| 6 | Teal | `#17b8b8` |
| 7 | Magenta | `#e84aa6` |
| 8 | Lime | `#7ac943` |
| 9 | Bronze | `#8b5a2b` |
| 10 | Charcoal | `#3c3c46` |

### Terrain textures

Every tile is 512×512 and seamless. `detail/` holds the greyscale version for tinting. Each look maps to one of the four terrains in the rules:

| Theme | Plains | Forest | Hills | Mountain | Background |
| --- | --- | --- | --- | --- | --- |
| Earth | grassland, steppe, savanna, desert, tundra | forest, taiga, jungle | hills, drylands, ice | mountains | sea |
| Eldmoor (`fantasy`) | meadow, frostfields, dunes | wildwood | highlands, ashlands | peaks | sea |
| Skyshards (`sky`) | skymeadow, heartruins | crystalgrove | crags | stormspire | void, bridge |

![Earth tiles](images/tiles_earth.jpg)
![Fantasy tiles](images/tiles_fantasy.jpg)
![Sky tiles](images/tiles_sky.jpg)

### Using the textures in Roblox

1. Upload `assets/textures/<theme>/*.png` and `detail/*.png` with Studio's Asset Manager (Bulk Import). Tiles are 512×512, under Roblox's 1024×1024 image limit.
2. Put the asset ids in one client module, `src/client/MapArt.luau` (biome key → colour id, detail id).
3. On each province's top face, add a `Texture` with `StudsPerTileU = StudsPerTileV = 128`, so every province shares one grid and textures line up across borders.
   - **Terrain view:** colour tile, `Color3` white.
   - **Political view:** detail tile, `Color3` = the owner's palette colour. Neutral: colour tile at `Transparency 0.45` over a light grey part.
4. Water and void: one large part under the map with the `sea` or `void` tile. Bridges: a thin part per strait with the `bridge` tile.
5. Lobby: upload `assets/maps/<map>/vote_card.jpg` (1024×512) for the three map-vote buttons.

## Map data pipeline

Everything here comes from `python3 tools/mapgen/generate.py` (about 1–2 minutes; needs Python 3 with numpy and Pillow). Output is deterministic.

| File | What it is | Used by |
| --- | --- | --- |
| `assets/maps/<map>/layout.json` | Provinces, neighbours, straits, nations, start owners, development, garrisons | Converted into `src/shared/MapData/<Map>.luau` |
| `assets/maps/<map>/province_ids.png` | Every pixel's province id (`R + 256·G`, 0 = none) | Province mesh export (Phase 4) |
| `assets/maps/<map>/terrain.jpg`, `political.jpg` | Full-size previews | Reviews and Studio reference |
| `assets/maps/<map>/atlas.jpg` | Terrain view with province ids printed | Debugging, bug reports ("army stuck in 57") |
| `assets/maps/<map>/vote_card.jpg` | 1024×512 lobby card | Map vote |
| `assets/textures/<theme>/…` | Terrain tiles | `MapArt` |

**Scale:** 1 image pixel = 0.5 stud, so Earth and Eldmoor are 1024×512 studs and Skyshards is 1024×768. `center` in `layout.json` is where the province label and garrison token sit.

**Never hand-edit `layout.json`.** Change the generator (`tools/mapgen/maps/*.py`) and regenerate. The validator then re-checks every rule above.

### Province shapes: generated, not hand-made

This answers the open question "keep the hex grid or switch to hand-made provinces?": **neither**. Hand-tracing 3 × 150 provinces in Studio would take weeks and drift from the data. Instead `tools/mapgen/shapes.py` traces every province outline from the province id grid:

1. Walk the pixel edges between each pair of provinces (and between land and sea) into border chains.
2. Simplify each chain once (Douglas–Peucker: 1.2 px for borders, 2.5 px for coasts), so two neighbours share exactly the same points and never leave gaps.
3. Join each province's chains into rings, bridge any holes (lakes, enclaves) into the outer ring, and triangulate by ear clipping.

The triangles go into `layout.json` and `MapData` as `tris`, and the shared chains as `borders`. The client builds each triangle from two `WedgePart`s at match start (`MapSurface`), so there is no import step: regenerate the map and the game draws the new shapes. Islands smaller than 150 px are dropped from the drawing (never from the rules). The validator checks every province got a shape.

## Roadmap changes

| Phase | Before | Now |
| --- | --- | --- |
| 1 | Generated hex map | **Skyshards `MapData`** converted from `layout.json`, drawn as simple flat discs at province centres with lines for neighbours. Real data from day one, and symmetric, so early tests are fair. |
| 2–3 | (one map) | Build and test on Skyshards. Add Eldmoor once war works (Gate 2). |
| 4 | Hand-made final map | **Province shapes for all three maps** (done early, built from `MapData`), a **custom texture pack**, plus the **map vote** with the three cards. |
| 5 | A second map | **Per-map balance** from win rate by start position. Earth needs it most. |

## Task cards

Paste one per Claude Code session, in order. Each follows the design doc's task template.

```text
## Task: MapData from layout.json (done)
Phase: 1   Service: MapData
Goal: the game loads Skyshards (and the other maps) from generated Luau data.
Read first: docs/MAPS.md, src/shared/Types.luau, assets/maps/skyshards/layout.json
Do:
- Add tools/mapgen/export_luau.py: layout.json -> src/shared/MapData/<Map>.luau (generated header, --!strict, a MapDef table)
- Add MapDef and ProvinceDef types to Types.luau as in DESIGN.md "Map data"
- Lune test: ids are 1..N, neighbours are symmetric, every passable province is reachable, each nation starts with 8 provinces and 17 development
Don't: hand-edit the generated modules; change Province or MatchState
Done when: lune run tests/run passes for all three maps; rojo build passes
```

```text
## Task: Province shapes (done, without meshes)
Phase: 4   Service: tools/mapgen + MapSurface
Goal: every map has real province shapes.
Done: tools/mapgen/shapes.py traces and triangulates provinces into MapData (tris, borders); MapSurface builds
them from wedges with biome materials, relief, Terrain water and border lines. No OBJ import is needed.
```

```text
## Task: Map vote
Phase: 4   Service: MatchService + UI
Goal: in the Lobby, players vote between Earth, Eldmoor and Skyshards using the vote cards.
Do: three 2-tap cards, majority wins, ties random, private servers can lock a map
Done when: 3 test clients vote and the chosen map loads
```

## Decisions to confirm

- **Third map:** Skyshards, the floating-island map described above.
- **Earth naming:** geographic regions instead of countries, and river nations.
- **Equal start on every map:** 8 provinces and 17 development per nation.
- **Neutral garrison:** 1,000 men by default (`Config.NeutralGarrison`). Maps may override per province.
- **Scale:** 1 px = 0.5 stud, and texture tiles every 128 studs.
- **Earth straits:** the Bering Strait wraps around the map edge, and the Dakar–Natal lane links the Americas to Africa.
- **`biome`** is a cosmetic field in map data only. `MatchState` is unchanged.
