# Total World Chaos — Design Doc

Source of truth for the game design. Mirrors the design doc in Claude (claude.ai). If they disagree, ask the owner which one wins.

## Overview

A 25-minute map PvP match: 10 nations on one map expand, fight and ally, and players who get knocked out rise as Primordials with world-breaking powers. Built for Roblox players aged 13–18+, most of them on phones.

**Design pillars**

1. **Readable at a glance.** Map colour is power; a new player understands the state of the match in 5 seconds.
2. **Two taps per decision.** Every action is reachable in two taps on a phone.
3. **Chaos is fun.** Primordial powers and disasters shake up every match so the leader is never safe.
4. **Short matches, long progression.** A match ends in 25 minutes; account XP and cosmetics carry over.

| Source | Keep | Cut |
| --- | --- | --- |
| EU4 | Provinces, development, armies on a map, sieges, alliances, war and peace, coalitions against the leader | Trade nodes, estates, missions, ideas, religion, rebels, naval combat, war score, most modifiers |
| WorldBox | God powers (here: Primordial powers), disasters, watching borders spread across the map, the pixel-art map look | Individual units, creatures, sandbox world editing |

## Match structure

A match runs 25 minutes in six phases and always ends with a winner: a nation holding 40% of provinces wins on the spot, otherwise the top score at 25:00 wins.

| Setting | Value |
| --- | --- |
| Server size | 12 players max |
| Nations per match | 10 (bots fill empty slots) |
| Map | ~150 provinces, ~15 per nation; three maps to vote on (`docs/MAPS.md`) |
| Match length | 25 min |
| Tick | 1 s = 1 game day |
| Economy payout | every 10 ticks (1 "month") |

**Phases**

1. **Lobby (60 s):** players join and vote on the map.
2. **Pick (30 s):** players pick a start nation in random draft order; bots take the rest.
3. **Peace (0–3 min):** no wars between nations; expand into neutral provinces and build.
4. **Open war (3–20 min):** everything unlocked.
5. **Cataclysm (20–25 min):** Primordial powers recharge twice as fast and a random disaster hits every 60 s.
6. **Results (30 s):** winner, stats and XP; the server votes on the next map.

**Win conditions**

- **Domination:** own 40% of all provinces → instant win.
- **Alliance victory:** an alliance (max 3 nations) jointly holds 55% → all members win.
- **Score:** at 25:00 the highest score wins. Score = provinces × 10 + total development × 5 + battles won × 2.

**Elimination and leavers**

- A nation is eliminated when it has lost its capital and holds fewer than 3 provinces.
- Eliminated players rise as **Primordials**: they stay in the server, see the whole map and use Primordial powers. Nobody sits out a match.
- An eliminated nation's armies disband and its last provinces turn neutral, each with a fresh garrison unless another army stands there. It leaves its wars, alliance (a one-nation alliance dissolves) and offers. A player keeps the nation's unspent charges as a Primordial; an eliminated bot simply ends.
- A player who leaves is replaced by a bot instantly, so the map never has dead nations.

## Core systems

Two resources (gold and manpower), one unit type and one siege rule carry the whole game. Every number below is a starting value for playtests and lives in one `Config` module.

### Map and provinces

- ~150 land provinces, each with terrain, development (1–5) and at most one building.
- Terrain: plains (normal), forest and hills (+25% defence, slower movement), mountains (impassable, used to make chokepoints).
- About 40% of provinces start **neutral** with a small garrison (one regiment, `Config.NeutralGarrison`; a map can set a bigger one per province), so the first minutes are about expansion, not PvP.
- No sea in v1. Islands connect through "straits": extra neighbour links drawn as bridges or sea lanes.
- Three maps: **Earth** (real world), **Eldmoor** (fantasy continent) and **Skyshards** (floating islands). Every nation starts with 8 provinces and 17 total development on every map. Details, art and data pipeline: `docs/MAPS.md`.

### Economy

Income is paid every month (10 s).

| Item | Cost | Effect |
| --- | --- | --- |
| Province income | — | +1 gold and +100 manpower per development level |
| Capital | — | +5 gold per month |
| Regiment (1,000 men) | 10 gold + 1,000 manpower | Upkeep 0.5 gold per month |
| Develop province | 30 gold × current level | +1 development (max 5) |
| Farm | 50 gold | +50% gold from this province |
| Barracks | 40 gold | +50% manpower from this province |
| Fort | 60 gold | +50% defence, siege time ×2 |

### Armies and combat

- One unit type, the regiment. An army is a stack of regiments shown as one token on the map.
- Movement: one province per 5 s on plains, 8 s on forest and hills. Paths follow province neighbours (BFS).
- A battle starts when enemy armies share a province and lasts 3 rounds of 1 s. Each round, each side kills enemy men equal to 15% of its own strength × modifiers.
- Modifiers: defender in forest or hills +25%, fort +50%, underdog +20%, coalition +10%, random ±10% per battle.
- After round 3 the side with fewer men retreats to its nearest owned province. Armies under 500 men are destroyed.

### Sieges

- An army alone in an enemy or neutral province starts a siege: 10 s × development, ×2 with a fort, ×3 for a capital.
- When the siege completes, the province flips to the attacker immediately. No war score and no haggling over provinces in peace deals.

### Diplomacy

- **War:** declare on any nation you border. Your allies join automatically.
- **Alliance:** request and accept; max 3 nations per alliance.
- **Peace:** white peace, or peace plus a gold tribute. A 3-minute truce follows.
- **Coalition:** a nation holding 25%+ of provinces gets a crown on the map, and every other nation gets +10% combat strength against it.

### Primordial powers

Living nations earn 1 charge every 4 minutes; Primordials earn 1 charge every 60 s. A nation can be hit by a Primordial power at most once per 30 s.

| Power | Effect | Charges |
| --- | --- | --- |
| Meteor | Kills 50% of one army; −1 development in that province | 2 |
| Plague | −50% manpower income for one nation for 60 s | 2 |
| Rebels | Spawns a 3,000-man neutral army in one province | 2 |
| Earthquake | Destroys the building in one province | 1 |
| Blessing | +100% gold from one province for 60 s | 1 |
| Divine shield | One province can't be sieged for 30 s | 1 |

- Targets: Meteor an army; Plague a nation; Rebels, Blessing and Divine shield a nation's province; Earthquake a province with a building. Mountains are never a target.
- Powers work in War and Cataclysm, not in Peace. Charges stop at `Config.Primordial.MaxCharges` (5).
- The 30 s limit applies to the harmful powers (Meteor, Plague, Rebels, Earthquake), which can't target your own nation; Blessing and Divine shield are gifts and ignore it.
- Rebels besiege the province they rise in; when the siege ends it turns neutral.
- A Primordial may target anyone, including the nation that eliminated them.
- Cataclysm disasters are a random harmful power on a random valid nation target (seeded), every 60 s from 21:00.

### Catch-up

- **Overextension:** above 20 provinces, every 5 extra provinces cut gold income by 5%.
- **Underdog:** the 3 nations with the fewest provinces get +20% defence.
- **Coalition** against the leader (see Diplomacy).

## Technical architecture

The server owns all game state and runs one 1-second tick. Clients only send intents and draw what the server tells them, and bots send the same intents players do.

Flow: client `Input + UI` → `Request…` remotes → `CommandRouter` (validates owner, cost, neighbours, cooldown, phase, rate limit) → services change `MatchState` → `Replicator` sends a snapshot on join and a delta every tick → client `MapRenderer + HUD`. `AIService` (bots) sends intents into the same `CommandRouter`. `GameLoop` drives the services every tick.

### Tooling

- **Rojo + Git/GitHub.** Code lives in files and Studio syncs from them.
- **Luau `--!strict`** in every module, with shared types in one `Types.luau`.
- **StyLua** (formatting) and **Selene** (linting) before each commit.
- **Lune** runs the pure game-logic tests outside Roblox.
- **ProfileStore** for player saves (XP, cosmetics), added in Phase 4. Match state is never saved.
- **Studio** for building the final map and UI layouts, and for playtests.

### Folder structure

```text
src/
  server/
    GameLoop.server.luau       -- match phases + 1 s tick
    CommandRouter.luau         -- validates every intent from players and bots
    Replicator.luau            -- snapshot on join, deltas each tick
    Services/                  -- thin Roblox wrappers around shared/Sim
      MapService.luau          -- provinces, ownership, neighbours, pathfinding
      EconomyService.luau      -- income, upkeep, buildings, development
      ArmyService.luau         -- movement, battles, sieges
      DiplomacyService.luau    -- war, alliances, peace, truces
      PrimordialService.luau   -- charges, powers, cooldowns
      AIService.luau           -- bot nations
      MatchService.luau        -- phases, win checks, scoring
      PlayerDataService.luau   -- XP, cosmetics (ProfileStore wrapper, Phase 4)
  client/
    MapView.luau               -- the 2D map GUI: pan, pinch zoom, taps
    PixelArt.luau              -- paints the pixel-art map (terrain, owners, borders) into an image buffer
    MapRenderer.luau           -- what is drawn on the map: the pixel art, names, armies, markers, routes
    UI/                        -- HUD, province sheet, diplomacy, powers
  shared/
    Types.luau
    Config.luau                -- every balance number
    MapData/                   -- Earth, Eldmoor, Skyshards (generated from assets/maps)
    MapGrid.luau               -- decodes a map's province grid (which province each map pixel belongs to)
    Sim/                       -- pure game rules, no Roblox APIs (tested with Lune)
tests/                         -- Lune test files for shared/Sim
assets/
  maps/<map>/                  -- layout.json, province_ids.png, previews, vote card
  textures/<theme>/            -- 512 px seamless terrain tiles (+ detail/ for tinting)
tools/mapgen/                  -- Python generator for everything in assets/
```

### Tick order

1. Apply queued commands.
2. Move armies.
3. Resolve battles.
4. Advance sieges and flip provinces.
5. Every 10th tick: pay income and upkeep.
6. Update Primordial-power charges and timers.
7. Bots plan (staggered: 1–2 bots per tick).
8. Check win conditions and phase changes.
9. Send one delta to every client.

### Networking

- **On join:** one full snapshot of provinces, nations and armies.
- **Every tick:** one batched delta with only what changed (owners, development, armies, battle events).
- **Army movement:** an `UnreliableRemoteEvent` with progress between province centres; the client interpolates the token.
- **Intents:** the client fires `Request…` remotes; the server answers with `CommandResult` (ok or reason).

### Security

- `CommandRouter` checks ownership, neighbours, cost, cooldown and match phase on every intent. The client is never trusted.
- Max 10 intents per second per player.
- Bots go through `CommandRouter` too, so an AI bug can't make illegal moves.

### Map rendering

The map is 2D pixel art in the style of WorldBox, drawn in a full-screen GUI. There are no 3D map parts.

- **Province grid:** `MapData` carries each map's province grid (`grid`): which province every map pixel belongs to, at 1 pixel = 1 stud (Earth and Eldmoor 1024×512, Skyshards 1024×768), run-length encoded. `MapGrid` decodes it once per match, and a tap looks up the province under the finger in it.
- **Painting:** `PixelArt` paints the whole map into an RGBA buffer at match start (about half a second). It draws water with shallows and foam (space with a faint grid on Skyshards), each biome's base colour with specks, and small sprites: trees, pines, peaks, hills, dunes, crystals and towers. Owned provinces take their nation's colour, shaded by the terrain underneath, inside a two-pixel nation border; province borders are dotted. Capitals get a castle (a dome on Skyshards).
- **On screen:** the buffer goes into one `EditableImage`, shown by an `ImageLabel` with pixelated resampling on a canvas that `MapView` pans and zooms (from the whole map down to 10 screen pixels per map pixel). An ownership change repaints only the provinces involved and their neighbours, and the image is uploaded at most once a frame.
- **On top:** province names and development pips (shown once a province is about 70 screen pixels wide), army tokens gliding between province centres, battle and siege badges, and dotted straits and routes. All of them are GUI objects placed on the canvas.
- **Requirement:** `EditableImage` works in Studio. In a published game Roblox only allows it when the owner is 13+ and ID-verified. Without it the map still shows names, tokens and routes, but no image, and warns once.

### Performance budget

| Budget | Target |
| --- | --- |
| Provinces | ≤ 150 |
| Map image | one `EditableImage` per match, ≤ 1024×1024 (Earth 1024×512 = 2 MB) |
| Map GUI objects (names, tokens, dots) | ≤ 2,000 |
| Armies on the map | ≤ 60 |
| Server work per tick | < 5 ms |
| Network per client | < 10 KB/s |

## Data model

All match state is a handful of tables keyed by id inside one `MatchState`. This is the contract every module builds against.

```lua
--!strict
export type ProvinceId = number
export type NationId = number
export type ArmyId = number

export type Terrain = "Plains" | "Forest" | "Hills" | "Mountain"
export type Building = "None" | "Farm" | "Barracks" | "Fort"
export type Phase = "Lobby" | "Pick" | "Peace" | "War" | "Cataclysm" | "Results"
export type PrimordialPower = "Meteor" | "Plague" | "Rebels" | "Earthquake" | "Blessing" | "Shield"

export type Province = {
    id: ProvinceId,
    name: string,
    terrain: Terrain,
    neighbors: { ProvinceId },
    owner: NationId?,          -- nil = neutral
    development: number,       -- 1..5
    building: Building,
    isCapital: boolean,
    siege: { by: NationId, progress: number, required: number }?,
    shieldUntil: number?,      -- tick when Divine Shield ends
    buffs: { [string]: number }, -- buff name -> tick it ends
}

export type Nation = {
    id: NationId,
    name: string,
    colorIndex: number,        -- palette index, so game logic stays Roblox-free and testable
    controller: "Player" | "Bot",
    userId: number?,           -- nil for bots
    capital: ProvinceId,
    gold: number,
    manpower: number,
    charges: number,
    allianceId: number?,
    powerImmuneUntil: number,  -- 30 s Primordial-power protection
    eliminated: boolean,
}

export type Army = {
    id: ArmyId,
    owner: NationId,           -- 0 = neutral (garrisons, Rebels)
    location: ProvinceId,
    men: number,
    path: { ProvinceId },      -- remaining route
    moveProgress: number,      -- ticks spent toward next province
    inBattle: boolean,
}

export type War = { id: number, attackers: { NationId }, defenders: { NationId }, startedAt: number }
export type Alliance = { id: number, members: { NationId } }
export type Truce = { a: NationId, b: NationId, untilTick: number }
export type Primordial = { userId: number, charges: number }

export type MatchState = {
    mapId: string,             -- which MapDef this match is played on
    tick: number,
    phase: Phase,
    provinces: { [ProvinceId]: Province },
    nations: { [NationId]: Nation },
    armies: { [ArmyId]: Army },
    wars: { [number]: War },
    alliances: { [number]: Alliance },
    truces: { Truce },
    primordials: { [number]: Primordial }, -- keyed by userId
}
```

### Map data

Static map definitions live in `src/shared/MapData/<Map>.luau`, generated from `assets/maps/<map>/layout.json` (never hand-edited). At match start they fill `MatchState.provinces` and `nations`.

```lua
export type ProvinceDef = {
    id: ProvinceId,
    name: string,
    terrain: Terrain,
    biome: string,             -- cosmetic: picks the texture, never a rule
    development: number,
    neighbors: { ProvinceId }, -- includes straits
    center: { x: number, y: number }, -- layout pixels (imageSize); the 2D map grid is half that resolution
    area: number,              -- layout pixels (sizes the label distance)
    startOwner: number?,       -- start slot 1..10, nil = neutral
    isCapital: boolean,
    garrison: number?,         -- neutral garrison override, men
}

-- Which province each pixel of the 2D map belongs to (0 = sea or space), run-length encoded (see MapGrid).
export type GridDef = { width: number, height: number, rle: string }

export type MapDef = {
    id: string,                -- "earth" | "eldmoor" | "skyshards"
    title: string,
    theme: string,             -- texture set: "earth" | "fantasy" | "sky"
    imageSize: { x: number, y: number },
    nations: { { slot: number, name: string, capital: ProvinceId, colorIndex: number } },
    provinces: { ProvinceDef },
    straits: { { a: ProvinceId, b: ProvinceId, from: { x: number, y: number }, to: { x: number, y: number }, wrap: boolean } },
    grid: GridDef,
}
```

Intents are typed too. `CommandRouter` checks their shape; `Sim/Commands` checks the rules.

```lua
export type Command =
    { kind: "Develop", province: ProvinceId }
    | { kind: "Build", province: ProvinceId, building: Building }
    | { kind: "Recruit", province: ProvinceId, regiments: number }
```

### Remotes

| Remote | Direction | Payload |
| --- | --- | --- |
| `RequestMove` | client → server | armyId, targetProvince |
| `RequestRecruit` | client → server | provinceId, regiments |
| `RequestBuild` | client → server | provinceId, building |
| `RequestDevelop` | client → server | provinceId |
| `RequestDiplomacy` | client → server | action (War, Ally, AcceptAlly, Peace, AcceptPeace), targetNation, gold? |
| `RequestPower` | client → server | power, target province or nation |
| `CommandResult` | server → client | requestId, ok, reason |
| `Snapshot` | server → client | full match state, sent on join |
| `Delta` | server → client | changed provinces, nations, armies, events |
| `ArmyPositions` (unreliable) | server → client | armyId, from, to, progress |
| `Notify` | server → client | toast type and text |

## UI and controls

Phone first: the map fills the screen, the HUD stays on the edges, and every action is a tap on the map followed by a tap in a bottom sheet.

- **Camera:** top-down; one finger pans, pinch zooms between 3 levels (whole map, region, province). Double-tap your capital to recentre.
- **Top bar:** gold, manpower, Primordial-power charges, match timer, your rank.
- **Left drawer:** nation list with colour, province count and relation icon (ally, at war, truce).
- **Bottom sheet (tap a province):** owner, development, building, plus buttons for Develop, Build and Recruit, or Declare war and Ally on foreign provinces.
- **Moving armies:** tap the army, tap the destination, see the path with arrival time, tap Confirm.
- **Primordial powers:** a power button opens a radial menu; pick a power, tap a target, confirm.
- **Map modes:** Political (default), Diplomacy (allies green, enemies red), Terrain.
- **Feedback:** toasts for war declared, province lost and battle won; a short screen shake for a meteor.

**Rules for every screen**

- Buttons at least 44 px and text at least 14 px on phone.
- Icons and numbers over words; no paragraphs anywhere in the HUD.
- Every UI change is checked in Studio's phone emulator before it's merged.

**Tutorial:** the first match is against 5 easy bots, with 6 prompts in order: take a neutral province, recruit, siege, make an ally, declare war, use a Primordial power.

## Bot AI

Each bot checks a short priority list every few seconds and does the first action that applies, using the same commands as players.

**Priority list** (bots are staggered so 1–2 plan per tick)

1. **Defend:** an enemy army borders one of my provinces → send the nearest army if my strength is at least 0.8× theirs, otherwise recruit there.
2. **Recruit:** total army is below provinces × 800 men and manpower is available.
3. **Expand:** a neutral neighbour whose garrison I can beat → attack it.
4. **Attack:** an enemy I'm at war with, or my weakest neighbour, if my strength is above the attack ratio and there's no truce.
5. **Build:** gold left over after 2 months of upkeep → barracks first, then farms, forts on borders, then develop.
6. **Diplomacy:** ally with a nation that shares my enemy; accept peace after losing 30% of my provinces in a war; join coalitions against the leader.
7. **Primordial power:** spend a charge on the biggest enemy army in a war I'm in.

| Difficulty | Plans every | Attack ratio | Behaviour |
| --- | --- | --- | --- |
| Easy | 6 s | 1.6× | Won't declare war on a player in the first 8 min |
| Normal | 3 s | 1.3× | Default |
| Hard | 2 s | 1.1× | Targets the leading player |

No cheating: harder bots think faster and take more risks, but they never get free gold or manpower.

## Monetization and retention

Sell looks, convenience and private play, never strength. Full plan: `docs/MONETIZATION.md`; launch and analytics: `docs/LAUNCH.md`.

| Product | Type | Price (Robux) |
| --- | --- | --- |
| Cosmetics by rarity: Common / Rare / Epic / Legendary | Shop item | 49 / 99 / 149 / 249 (Glory 500 / 1,200 / 2,500 / —) |
| Nation skins: flag, border style, shade set (within your assigned colour), army token; matched sets | Shop item | 49–249; sets 199 / 299 |
| Map themes: re-skins of the maps (e.g. Ember Eldmoor); the winning map uses its voters' most-equipped theme | Shop item | 99 |
| Primordial-power effects: meteor style, plague colour | Shop item | 49–149 |
| Capital emotes | Shop item | 25–49 |
| Victory animations, nameplate frames | Shop item | 49–249 |
| VIP: VIP flag set, gold frame, chat tag, +25% match XP and Glory, +1 quest reroll | Game pass | 249 |
| Private servers: map, theme, length, peace, bots, powers, disasters | Private server | 100 per month |
| Season pass: 8 weeks, 50 tiers, free and premium tracks | Developer product | 299 (499 with 10 tiers) |
| Starter pack (once per account, no timer) | Developer product | 149 |

**Glory** is the only soft currency. It is earned by playing (about 49 per match plus quests) and is never sold.

**Never sell:** gold, regiments, manpower, Primordial-power charges, combat bonuses, start positions, titles, Glory or anything else that changes a match. No paid random items (loot boxes), no countdown offers, no prompts during a match, no single tier skips.

**Retention:** account XP (300 + 60 × (level − 1) per level, cap 100) and ten ranks; 3 daily and 3 weekly quests; a login calendar that pauses instead of resetting; achievements; the server votes on the next map after Results; weekly, friends and global leaderboards; parties of up to 3 start next to each other; clans and a ranked mode after launch.

## Build roadmap

Five phases, each ending in a playtest gate the owner runs in Studio.

### Phase 1: Foundation

- [x] Rojo project, StyLua, Selene, strict mode, Lune test runner
- [x] `Types.luau` and `Config.luau` from this doc
- [x] `MapData` generated from `assets/maps/*/layout.json`; Skyshards is the test map
- [x] `MapRenderer` colours provinces by owner; camera pan and zoom on phone
- [x] `GameLoop` with a 1 s tick; economy pays income
- [x] Recruit, develop and build through `CommandRouter`

**Gate 1:** one player can grow a nation for 25 minutes on a phone with no errors.

### Phase 2: War

- [x] Army movement with BFS paths and client interpolation
- [x] Battles, retreats, sieges, provinces flipping
- [x] War, alliance, peace and truce
- [x] Neutral provinces with garrisons
- [x] Win conditions and the Results screen

**Gate 2:** 4 friends play 3 matches and ask for a 4th.

### Phase 3: Bots and Primordials

- [ ] `AIService` on Normal; bots fill empty slots and replace leavers
- [x] Elimination and the Primordial role
- [x] 6 Primordial powers with charges and cooldowns
- [ ] Catch-up rules: overextension, underdog, coalition
- [x] Cataclysm phase

**Gate 3:** 1 player against 9 bots is fun for 25 minutes, and no single bot wins most matches.

### Phase 4: Polish and shop

- [x] 2D pixel-art map for Earth, Eldmoor and Skyshards (WorldBox style, painted at runtime)
- [ ] Map vote in the Lobby with the three vote cards
- [ ] Tutorial match
- [ ] Progression rules in Sim: match XP and Glory, level curve, ranks
- [ ] `PlayerDataService` (ProfileStore): XP, Glory, items, receipts; Results screen rewards
- [ ] Daily and weekly quests, login calendar, play streak
- [ ] Shop: catalogue, Robux and Glory purchases, VIP pass, starter pack, purchase history
- [ ] Cosmetics shown in the match: flags, borders, tokens, emotes, power effects, victory animations, theme vote
- [ ] Private server settings
- [ ] Sound and effects for battles and Primordial powers

**Gate 4:** 10 testers who have never played finish the tutorial without help.

### Phase 5: Soft launch

- [ ] Analytics events (`docs/LAUNCH.md`): match length, quit time, phase reached, win rate by start position, funnels, economy
- [ ] Weekly balance patch from the data
- [ ] Easy and Hard bots
- [ ] Per-map balance from win rate by start position
- [ ] Season pass (8 weeks, 50 tiers)
- [ ] Rotating shop
- [ ] Weekly, friends and global leaderboards; achievements
- [ ] Rewarded video quest reroll; experience notifications
- [ ] Soft-launch gates met (`docs/LAUNCH.md`) before Season 1

## Open questions

Answered:

- Working title: **Total World Chaos**.
- Real-world map or fictional continents? **Both**: Earth (region names, never countries), Eldmoor and Skyshards. See `docs/MAPS.md`.
- Hex grid or hand-made provinces for the final map? **Neither**: province meshes generated from the map data. See `docs/MAPS.md`.

- Can a Primordial target the nation that eliminated them? **Yes** (the simplest rule; revisit after playtests).

Still open:

- Art style beyond the maps: historical, fantasy or meme?
- Casual only, or a ranked mode after launch? Proposed: ranked beta in month 5–6 if peak CCU ≥ 1,500 (`docs/MONETIZATION.md` 7.5).
- Provinces flip when a siege ends (current rule) or only through peace deals?
