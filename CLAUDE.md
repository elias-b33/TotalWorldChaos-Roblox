# CLAUDE.md

Total World Chaos: a Roblox map PvP strategy game (EU4 + WorldBox, simplified) for players aged 13–18+, mostly on phones.
The full spec is `docs/DESIGN.md`; the three maps, textures and map data pipeline are in `docs/MAPS.md`. Read the sections your task touches before writing code.

## Golden rules

- `docs/DESIGN.md` is the spec. Don't add features it doesn't list. If something is missing or contradictory, pick the simplest option, write it under "Decisions" in your final message, and keep going.
- The server is authoritative. Every state change goes through `CommandRouter` and then the services. Never trust the client.
- Bots send the same commands as players, through the same `CommandRouter`.
- Every balance number lives in `src/shared/Config.luau`. No magic numbers anywhere else.
- Game rules live in `src/shared/Sim/` as pure Luau. Sim code must not touch `game`, `workspace`, `Instance`, `Color3`, `Vector3`, `task`, `RemoteEvent` or any other Roblox global, so it runs under Lune. Sim functions take `MatchState` plus inputs and change state or return results.
- Randomness in Sim comes from a seeded RNG module (`src/shared/Sim/Rng.luau`) passed in as an argument, so tests are deterministic. Never use `math.random` or `Random.new` inside Sim.
- `src/server/Services/` are thin Roblox wrappers: they call Sim, handle remotes and timing, and nothing else.
- `--!strict` at the top of every Luau file. Types come from `src/shared/Types.luau`. If you need to change a type, say so in your final message.
- Map data and textures are generated. Never hand-edit `assets/maps/*/layout.json`, `assets/textures/` or `src/shared/MapData/`: change `tools/mapgen/` and rerun it, then check the validator printed no `PROBLEM` lines.
- Never use the words "god", "gods", "godlike", "divine" or "holy" anywhere: player-facing text, names, docs, comments or identifiers. Eliminated players are Primordials and their abilities are Primordial powers; the shield power is "Shield".
- Inside `src/shared/`, use string requires (`require("./Rng")`) so the same files load in Roblox and Lune. If a require pattern fails in either runtime, fix it consistently and note it under "Decisions".

## Commands

| What | Command |
| --- | --- |
| Build the place file | `mkdir -p build && rojo build -o build/game.rbxlx` |
| Format | `stylua src tests` |
| Check formatting | `stylua --check src tests` |
| Lint | `RUST_MIN_STACK=67108864 selene src` (the cloud's debug-built Selene needs the bigger stack) |
| Run Sim tests | `lune run tests/run` |
| Install missing tools | `bash scripts/cloud-setup.sh` |
| Regenerate maps and textures | `python3 tools/mapgen/generate.py` (or `--only earth`, `--only tiles`, …) |
| Play the game headlessly | `lune run tools/harness/play all` after `rojo build` (or `play <scenario>`; screenshots in `tools/harness/out/`; `MAP=earth` for another map; `NO_SHOTS=1` skips the PNGs for faster check runs) |
| Play a whole match with bots | `lune run tools/harness/soak` after `rojo build` (25 minutes in about 20 s; errors, GUI budget, armies per minute) |
| Repaint the docs' map pictures | `python3 tools/harness/paint_maps.py` |

The cloud environment's setup script normally installs the tools. If one is missing when a session starts, the SessionStart hook is already installing it in the background: wait until `/tmp/cloud-setup.log` says `cloud-setup: done` instead of starting a second install.

The first task creates `tests/run.luau` (a small runner that executes every `tests/*.spec.luau` and exits non-zero on failure). Lune supports string requires such as `require("../src/shared/Sim/Economy")` from a test file.

`roblox.yml` is the Roblox API list Selene lints against. It is committed on purpose because Selene can't download it through the cloud proxy. Don't delete or regenerate it in a cloud session; the owner refreshes it on their own computer with `selene generate-roblox-std` if a newer Roblox API is flagged as unknown.

## Definition of done (every task)

1. `stylua --check`, `selene`, the Lune tests and `rojo build` all pass. Fix failures before you stop.
2. Every new Sim rule has a Lune test.
3. Tick the matching checkbox in the roadmap in `docs/DESIGN.md`.
4. Commit with a clear message and push the branch.
5. Your final message has three parts: **What changed**, **How to test in Studio** (exact steps the owner can follow, for example "Test tab → Clients and Servers → 2 players, tap a province, press Recruit"), and **Decisions** (anything you chose that the spec didn't say).

## Limits of this environment

- Roblox Studio can't run here. Code that needs the Roblox runtime (rendering, remotes, input, camera, UI) can only be built, not run. Keep that code simple, reuse the same patterns across files, and give precise manual test steps.
- No third-party Roblox packages in Phases 1–3. ProfileStore arrives in Phase 4.
- Work on one roadmap phase (or part of one) per session. Small, finished and tested beats big and half-done.

## Layout

```text
default.project.json   Rojo project: shared → ReplicatedStorage.Shared, server → ServerScriptService.Server, client → StarterPlayerScripts.Client
src/shared/            Types, Config, MapData, MapGrid, Sim (pure rules)
src/server/            GameLoop, CommandRouter, Replicator, Services
src/client/            MapView (2D map GUI), PixelArt (pixel-art painter), MapRenderer, UI
tests/                 Lune tests for src/shared/Sim (and the pure client painter, PixelArt)
docs/DESIGN.md         The spec and the roadmap checkboxes
docs/MAPS.md           The three maps, art direction, the pixel-art map, map data pipeline
docs/MONETIZATION.md   Shop, prices, Glory, progression, season pass, live ops, revenue model, Phase 4–5 task cards
docs/LAUNCH.md         Soft-launch gates, store page, ads, creators, analytics events
docs/STUDIO.md         Testing in Roblox Studio: settings, Workspace test switches, a recipe per feature
docs/BALANCE.md        Balance analysis: economy, battles, sieges, catch-up, match length
docs/UI_DIRECTION.md   The "Slate & Brass" GUI: palette, painted frames, component specs, the build plan
docs/NEXT_FEATURES.md  Plans and task cards for the next features (pings, replay and awards, music, empires, friends, …)
docs/RIVALS.md         The top 10 rival games (and the sandbox side) and how we take our share
docs/COMPETITOR_VIDEOS.md  What YouTube shows about the rivals (formats, creators, views) and what we do about it
assets/maps/           Generated per-map data (layout.json, province_ids.png) and previews
assets/textures/       Generated seamless terrain tiles per theme
tools/mapgen/          Python (numpy + Pillow) generator for everything in assets/
tools/harness/         Lune emulator that runs the built place's real scripts, plays scenarios and renders screenshots
                       (one file per scenario in tools/harness/scenarios/, shared helpers in H.luau)
roblox.yml             Roblox API list for Selene (committed; see Commands)
scripts/cloud-setup.sh Installs rojo, stylua, selene, lune
scripts/session-start.sh  SessionStart hook: installs missing tools in the background (cloud only)
.claude/settings.json  Registers the SessionStart hook
```
