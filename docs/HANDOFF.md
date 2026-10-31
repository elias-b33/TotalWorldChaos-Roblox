# Build hand-off (for a new chat)

The coordinator's notes: where every stage stands, the order of the remaining work and the owner's preferences. Plans for the next features are in `docs/NEXT_FEATURES.md` (9.10–9.14 are the newest). Paths under `/tmp/claude-0/…` and `.claude/worktrees/` existed only in the first cloud session.

# Builds (paused 29 October about 07:30 UTC; resumed about 08:10 UTC)

Wrapped up for the day (29 October ~13:00 UTC, owner's request). Main (pushed) is 76989cd: pings, Slate & Brass step 7, smarter PvP and navies stage 3 are all merged. Missions + fog: WIP 97612d5 (merged with navy; steps left in its commit body). Tomorrow: a fresh xhigh builder continues missions + fog from 97612d5, then the order in the notes below. trial26 (at main) is free.

Main (pushed): `b5485bb`. It holds:
- the sandbox;
- navies 1–2 and the fleet positions;
- the Primordial anti-focus cooldown;
- the start menu;
- five troops per race;
- Slate & Brass steps 4–6;
- EU4 stages 1–2 (insults, gifts, access, event cards);
- music;
- docs: monetization plan section 13, RIVALS.md, NEXT_FEATURES 9.9.

Unfinished stages, all committed on their worktree branches:

| Stage | Branch | Commit | State | Next step |
| --- | --- | --- | --- | --- |
| EU4 missions + fog of war | `worktree-agent-a9df32e16041059c3` | `97612d5` (WIP after merging navy 63caefd in 377e945) | Merged with everything; fog consistent (no extra code needed); quick checks pass (43 spec files); smoke, fog, missions, private (also 667) pass. Missions/Fog switches on a new third private-sheet tab "More" (builder's decision, tell the owner) | Fresh xhigh builder: the steps in 97612d5's commit body (all scenarios with fog on, soaks with ten-viewer numbers, tournaments missions/fog on/off, BALANCE 24-25, final commits, merge main) |

Queue after these:
- bot strategy (after navy);
- generals (after PvP);
- Slate & Brass step 8;
- replay and awards;
- play with friends;
- game modes;
- the combined balance pass (event-card and mission pace, Earth's Clans starts);
- the final review;
- optional: empire, monetization stages.

Verification scripts are in `scratchpad/tools/`:
- `fullrun.sh <dir> <prefix> [667 scenarios]`;
- `resume_run.sh` for detached runs past the 2-hour limit;
- `watch_once.sh`.

## Owner's preferences (keep them)

**Usage and agents:**
- Be careful with usage: the weekly limit was hit on 29 October with five builders.
- The plan after the pause:
  - I finish pings and Slate & Brass step 7 myself (run the checks, review, merge);
  - then **one builder at a time**, at effort **high**;
  - **xhigh** only for bot strategy, finishing missions and fog, and the combined balance pass.
  - **Medium** where it's viable, but quality must stay the same (owner, 29 October ~08:10 UTC, when building resumed). Use it only for well-specified work with strong automated checks.
- No second machine or session.
- Never more than 5 agents.
- Fresh agents per stage. Hand off at large contexts (over about 500k tokens).
- Agents end their turn while checks run; no polling.
- Don't wake agents needlessly.

**Interruptions:**
- A user interrupt (the stop button) cancels every builder for good. The harness then only allows new agents if the owner explicitly asks. Save WIP commits first.
- A container restart kills background runs. Resumed agents (SendMessage) must re-run them.

**The verification workflow:**
1. Make a scratch worktree from main and merge the stage with `--no-ff`.
2. Run `tools/fullrun.sh` (`NO_SHOTS`, all scenarios, three soaks, the no-image runs, the 667×375 runs).
3. Fast-forward main and push `claude/zen-pascal-446t9e`.
4. Background runs die after 2 hours: run long ones detached (`setsid nohup … &`) with a waiter.

**Other:**
- Commit trailers:
  - `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01CmaemW8ruDu6NfTovd2rhB`
- Never use the banned words listed in CLAUDE.md's golden rules anywhere.
- Flags and banners need a big art pass later. Not now.
- Monetization: no strength for sale at launch; the other options stay open (docs/MONETIZATION.md 13.7).
- The owner's brainstorm is saved for later (NEXT_FEATURES 9.9): a grand strategy mode for PC and tablets, Earth's eras and nukes, a WorldBox-level sandbox with player-made worlds.
- Final messages to the owner follow CLAUDE.md: What changed, How to test in Studio, Decisions.

## Notes for later stages (from the PvP builder, 29 October)
- Bot strategy (xhigh): Hard bots beat Normal only ~41% head to head (BALANCE.md section 22; section 16's 56% doesn't reproduce even on main). Hard must clearly beat Normal.
- Slate & Brass step 8: the event card overlaps part of the province sheet on a phone; the client drops a toast when 4 are queued, so a disaster toast can vanish behind conquest toasts (sandbox).
- Combined balance pass (xhigh): with counters and morale, Skyshards' Crystal folk (+1.8 provinces) and Marines (+1.7) rose, Energy beings (-1.4) and Robots (-1.1) fell; Eldmoor's start slots spread more (best/worst land 2.8 vs 2.26); armies at 25:00 are smaller (Earth 201k -> 162k men).

## Notes from the navy builder (29 October)
- Gameplay bug (already on main): a tired or broken army that boards a ship lands with full morale, so ships refresh morale. Fix by keeping morale aboard the fleet (Types change, Navy board/land, Bot landingParty, tests). Bundle it with the generals stage (generals must also survive boarding).
- Bot strategy: Hard vs Normal fell to 35% with navies (41% without). Balance pass: Earth's Volga wins 54/200 with navies (2.14x fair share), Eldmoor's Frostmarch 54; Skyshards blockades +29% blockaded time.
- Next order: missions + fog -> generals + morale-aboard fix (high) -> bot strategy (xhigh) -> combat feel (9.14, high) -> Primordials stage 1 (NEXT_FEATURES 9.11, xhigh) -> bigger Earth A+B (NEXT_FEATURES 9.10, high) -> GUI step 8 + tap help (9.10 C) -> replay + awards -> play with friends -> modes + Classic + map rotation and matchmaking (9.13) -> balance pass (xhigh) -> final review.
