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

A match runs 25 minutes in six phases and always ends with a winner: a nation holding half of the land (50% of the provinces that can be owned) wins on the spot, otherwise the top score at 25:00 wins.

| Setting | Value |
| --- | --- |
| Server size | 12 players max |
| Nations per match | 10 (bots fill empty slots) |
| Map | ~150 provinces, ~15 per nation; three maps to vote on (`docs/MAPS.md`) |
| Match length | 25 min |
| Tick | 1 s = 1 game day |
| Economy payout | every 10 ticks (1 "month") |

**Phases**

1. **Lobby (60 s):** players join and vote on the map with three cards (tap a card, tap it again to vote). Most votes wins; a tie, or no votes, is settled at random. A server locked to one map (Workspace `MapId`, or a private server's map setting) shows only that card and skips the vote. On a private server the owner changes the next match's settings here (`docs/MONETIZATION.md` 3.4): length, Peace, bots, powers, disasters, teams, map and theme.
2. **Pick (up to 30 s):** the chosen map shows every nation's start territory, and players pick a start nation one at a time in a random draft order, by tapping its land (then confirming) or its name in the list. Each turn lasts 30 s ÷ players (3–8 s); a turn that runs out picks a random free nation. Someone who joins during the draft goes to the end of the order. Bots take the rest. The match clock starts at 0:00 when the draft ends.
3. **Peace (0–3 min):** no wars between nations; expand into neutral provinces and build.
4. **Open war (3–20 min):** everything unlocked.
5. **Cataclysm (20–25 min):** Primordial powers recharge twice as fast and a random disaster hits every 60 s.
6. **Results (30 s):** winner, stats and XP. Then the Lobby opens again to vote on the next map; everyone stays in the server.

Joining mid-match takes over a bot's nation. For Studio solo tests (and the harness) the Workspace attribute `SkipLobby` starts every match straight in Peace.

**Win conditions**

- **Domination:** own 50% of the ownable provinces → instant win.
- **Alliance victory:** an alliance (max 3 nations) jointly holds 65% → all members win.
- Shares (domination, alliance victory and the coalition crown) count only provinces that can be owned: mountains never count.
- **Score:** at 25:00 the highest score wins. Score = provinces × 10 + total development × 5 + battles won × 2.

**Elimination and leavers**

- A nation is eliminated when it has lost its capital and holds fewer than 3 provinces.
- Eliminated players rise as **Primordials**: they stay in the server, see the whole map and use Primordial powers. Nobody sits out a match.
- An eliminated nation's armies disband and its last provinces turn neutral, each with a fresh garrison unless another army stands there. It leaves its wars, alliance (a one-nation alliance dissolves) and offers. A player keeps the nation's unspent charges as a Primordial; an eliminated bot simply ends.
- A player who leaves is replaced by a bot instantly, so the map never has dead nations.
- The match remembers which nation each player held. A player who rejoins gets that nation back while a bot still runs it, or rises as its Primordial if it was eliminated meanwhile, so leaving never trades a dying nation for a healthy one. Newcomers take a nation nobody held before; a held nation goes to a newcomer only when no other is free. Someone joining during Results isn't seated (they watch and get a nation in the next match); a bot's order still queued for a nation a player has just taken is dropped.

## Core systems

Two resources (gold and manpower), one unit type and one siege rule carry the whole game. Every number below is a starting value for playtests and lives in one `Config` module.

### Map and provinces

- ~150 land provinces, each with terrain, development (1–5) and at most one building.
- Terrain: plains (normal), forest and hills (+25% defence, slower movement), mountains (impassable, used to make chokepoints).
- About 40% of provinces start **neutral** with a small garrison (one regiment, `Config.NeutralGarrison`; a map can set a bigger one per province), so the first minutes are about expansion, not PvP.
- No sea in v1. Islands connect through "straits": extra neighbour links drawn as bridges or sea lanes.
- Three maps: **Earth** (real world), **Eldmoor** (fantasy continent) and **Skyshards** (floating islands). Every nation starts with 8 provinces and 17 total development on every map. Details, art and data pipeline: `docs/MAPS.md`.

### Economy

Income is paid every month (10 s). A nation starts with 100 gold and 3,000 manpower.

| Item | Cost | Effect |
| --- | --- | --- |
| Province income | — | +1 gold and +100 manpower per development level |
| Capital | — | +5 gold per month |
| Regiment (1,000 men) | 10 gold + 1,000 manpower | Upkeep 1.5 gold per month |
| Develop province | 30 gold × current level | +1 development (max 5) |
| Farm | 50 gold | +50% gold from this province |
| Barracks | 40 gold | +50% manpower from this province |
| Fort | 60 gold | +50% defence, siege time ×2 |

### Armies and combat

- One unit type, the regiment. An army is a stack of regiments shown as one token on the map: a nation's armies that stand still in the same province (not marching, fighting or retreating) merge into one.
- Movement: one province per 5 s on plains, 8 s on forest and hills. Paths follow province neighbours (BFS).
- A battle starts when enemy armies share a province and lasts 3 rounds of 1 s. Each round, each side kills enemy men equal to 15% of its own strength × modifiers.
- Modifiers: defender in forest or hills +25%, fort +50%, underdog +50%, coalition +30%, random ±10% per battle.
- After round 3 the side with fewer men retreats: it walks to its nearest owned province on the shortest path over land it may enter, at normal speed, under a 🏳 flag. On the way it takes no orders and doesn't fight, block a siege or besiege; it is a normal army again when it arrives (or when its way closes). Armies under 500 men are destroyed, and so is a loser with no way home.

### Sieges

- An army alone in an enemy or neutral province starts a siege: 10 s × development, ×2 with a fort, ×3 for a capital.
- One siege per province. Whoever started it keeps it while one of its (or an ally's) armies stands there; another besieger at peace with it waits instead of blocking, and takes over (from zero) once the first one leaves.
- An interrupted siege (a battle there, a defending army, the besieger stepping out) keeps its progress for 10 s, then resets. Peace with the owner, or the province changing hands, ends it at once.
- When the siege completes, the province flips to the attacker immediately. No war score and no haggling over provinces in peace deals.

### Diplomacy

- **War:** declare on any nation you border. Your allies join automatically.
- **Alliance:** request and accept; max 3 nations per alliance.
- **Peace:** white peace, or peace plus a gold tribute. A 3-minute truce follows.
- **Coalition:** a nation holding 20%+ of the ownable provinces gets a crown on the map, and every other nation gets +30% combat strength against it.

### Primordial powers

Living nations earn 1 charge every 4 minutes; Primordials earn 1 charge every 60 s, counted from the moment they rose (each Primordial has its own clock; nations share the match clock because they all start at 0:00). A nation can be hit by a Primordial power at most once per 30 s.

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
- Meteor's limit is checked for the army's owner, who then becomes immune. The province it stands in loses its development level only if that province's owner isn't immune, and that loss doesn't make the owner immune.
- The power picker shows an immune nation as unavailable (with the seconds left) instead of sending a power the server would refuse.
- Rebels besiege the province they rise in; when the siege ends it turns neutral. On the map they are a black 🏴 token that always shows, unlike neutral garrisons.
- A Primordial may target anyone, including the nation that eliminated them.
- Cataclysm disasters are a random harmful power on a random valid nation target (seeded), every 60 s from 21:00.

### Catch-up

- **Overextension:** above 20 provinces, every 5 extra provinces cut gold income by 5%. Only full steps count (21–24 provinces: −0%, 25–29: −5%, 30–34: −10%), and the cut applies to gross gold (provinces + capital) before upkeep, never below zero. Manpower is not cut.
- **Underdog:** the 3 nations with the fewest provinces get +50% defence: +50% combat strength when their side is the defender in a battle (not sieges, not when attacking). Only living nations count. A tie at the cut-off leaves everyone in the tie out, so there are never more than 3 underdogs, nobody is one while every nation is level, and the largest nation never is.
- **Coalition** against the leader (see Diplomacy): every living nation with 20%+ of the ownable provinces wears the crown, and any nation's side fighting a crowned nation gets +30% combat strength, attacking or defending (neutral garrisons and Rebels don't). Two crowned nations fighting each other both get it.
- Combat bonuses add to the other modifiers (terrain, fort, the random roll). Because a side's kills scale with its own size, +50% is worth about 15% more men and +30% about 8% (`docs/BALANCE.md` section 5); the bonuses are sized for that. Rules: `Sim/CatchUp.luau`; numbers and their effect: `docs/BALANCE.md`.

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
      TutorialService.luau     -- the tutorial match on a reserved server (Phase 4)
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
2. Move armies (retreating armies walk home too), then merge a nation's armies standing in the same province.
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
- **Painting:** `PixelArt` paints the whole map into an RGBA buffer at match start, in about half a second, using WorldBox's colours (docs/MAPS.md "Art direction"). Skyshards gets space with a faint grid instead of sea.
  - **Sea:** ocean in three round depth bands, with beaches, a foam line, a shadow under the coast and gentle wave dashes.
  - **Land:** each biome's base colour with its own small tile pattern (WorldBox-style textures, not random specks), raised patches of higher ground with a lit edge and a dark lip, and slopes lit from the north-west.
  - **Mountains:** grey ridges with a few snow caps.
  - **Sprites:** small ones for trees, pines, palms, crystals and towers.
  - **Owners:** an owned province is washed with its nation's colour at 59%, and each nation has a 1-pixel border in its darker colour (WorldBox's kingdom look). Thin darker lines separate provinces.
  - **Capitals:** a castle, or a dome on Skyshards.
  - **Map themes** (shop cosmetics, docs/MONETIZATION.md 3.2): `Night`, `Winter` and `Autumn` repaint the terrain colours of any map before the owners go on top (moonlit land, a navy sea and village lights; snow and frozen shallows; turning leaves). Nation colours, borders, castles and everything drawn over the map stay the same. The match's theme comes from the theme vote (`MatchState.theme`, sent in the snapshot); a player who chose "Always classic" sees the classic look. `tests/themes.spec.luau` checks on all three maps that every nation colour and border stands out from the themed terrain about as well as on the classic look.
- **On screen:** the buffer goes into one `EditableImage`, shown by an `ImageLabel` with pixelated resampling on a canvas that `MapView` pans and zooms (from the whole map down to 10 screen pixels per map pixel). An ownership change repaints only the provinces involved and their neighbours, and the image is uploaded at most once a frame.
- **Close-up detail:** zoomed in past about 4 screen pixels per map pixel (more on big screens, so the view always fits), `MapRenderer` lays a second `EditableImage` over the map: just the part in view (with room to pan), painted by `PixelArt.paintDetail` at 4 × 4 sub-pixels per map pixel (docs/MAPS.md "Art direction"): the biome patterns at full resolution, smooth coasts and province edges, beaches and surf, dense shaded trees and other decorations, lit mountain faces, a lighter kingdom wash (48%) with a stronger band inside each nation's border, the border line, the selection's white outline and a detailed castle. It repaints when the view settles somewhere it doesn't cover (a few milliseconds per frame, the old one staying up meanwhile), catches up with ownership, cosmetic and selection changes by repainting only those provinces, and follows the map theme. Zoomed out again, its image is destroyed so phones get the memory back. It isn't used with the half-size fallback image, or if the device refuses the second image.
- **On top:** GUI objects placed on the canvas, in the UI kit's look ("UI style"); `MapBadges` (pure, tested) decides what they say and where they stack.
  - **Names and pips:** province names in Builder Sans with a solid ink outline (gold while the province is selected), shown once a province is about 70 screen pixels wide; a name that would overlap a bigger province's name waits until there's room. From the region zoom inwards a development bar hangs under the name: one pixel cell per level, gold when reached (one small `EditableImage` per level, shared; text pips without `EditableImage`).
  - **Armies:** tokens glide from province to province a little above the centres (the names are below), and armies resting in one province stand side by side. Each has a strength badge: a dark pill with a pixel icon for its state (sword; burst in battle; white flag retreating; black flag for Rebels; shield for neutral garrisons) and its size in Fredoka One, outlined in its nation's colour (gold while selected). The badges of armies in one province stack in a column above them, so none covers another at any zoom. Sizes show from the region zoom inwards; zoomed out, only on your own armies, Rebels and the selected army. An idle neutral garrison's badge is laid out after the names: it shows only where it covers no name and no other garrison's badge (bigger provinces first), and the others keep their grey token until the player zooms in.
  - **Status row:** on top of the badges, the province's battle (burst, red edge) or siege (hourglass and percent, gold edge), then Primordial-power effects with their seconds left (divine shield, blessing, plague, or a strike's icon; purple edge). Zoomed out, the pills show only their icons unless it is your province or your siege.
  - **Capitals:** each nation's flag on a pole left of its capital while it holds it; the coalition leader's pixel crown sits on top of the pole.
  - Dotted straits and routes (a route preview in gold).
- **Requirement:** `EditableImage` works in Studio, but fails by default in a published game.
  - **Turning it on:** the owner enables *Allow Mesh / Image APIs*. In Studio it's under Experience Settings → Security; on the Creator Dashboard it's in the game's Configure settings.
  - **Owner verification:** older Roblox guidance also required the owner to be 13+ and ID-verified. Check the current rule before launch. The launch checklist already asks for ID verification.
  - **Memory:** phones give these images a strict memory budget. If the full-size image can't be made, the map uses a half-size one.
  - **No image at all:** the map still shows names, tokens and routes, and a notice in the toast style under the toasts' line tells the player the map art is off.

### Performance budget

| Budget | Target |
| --- | --- |
| Provinces | ≤ 150 |
| Map image | one `EditableImage` per match, ≤ 1024×1024 (Earth 1024×512 = 2 MB); painted in < 1 s |
| Close-up image | at most one more, only while zoomed in, ≤ 1024×1024 (a phone in landscape: 1024×476 = 1.9 MB), one extra `ImageLabel`; one repaint < 150 ms of work, spread over frames |
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
    siege: { by: NationId, progress: number, required: number, lastTick: number }?, -- lastTick: last progress (grace period)
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
    rebel: boolean?,           -- raised by the Rebels power (drawn apart from garrisons)
    retreating: boolean?,      -- beaten and walking home: no orders, no fighting, no sieges
}

export type War = { id: number, attackers: { NationId }, defenders: { NationId }, startedAt: number }
export type Alliance = { id: number, members: { NationId } }
export type Truce = { a: NationId, b: NationId, untilTick: number }
export type Primordial = { userId: number, charges: number, chargeTicks: number } -- chargeTicks: its own clock

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
    seats: { [number]: NationId }, -- userId -> the nation that player last held (rejoins)
    nextArmyId: ArmyId,        -- army ids count up and are never reused
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
| `RequestBuy` | client → server | itemId, "Glory" or "Robux" |
| `RequestEquip` | client → server | itemId |
| `RequestEmote` | client → server | emote itemId |
| `RequestTelemetry` | client → server | a UI-only analytics step (`Loaded`, `ShopOpened`, `ItemViewed`, `OfferOpened`, `NotificationPrompt`), optional short string; no reply, changes nothing |
| `RequestDefaultTheme` | client → server | true = always show the classic map (the map-theme opt-out) |
| `Shop` | server → client | your owned and equipped items, VIP, purchase history, whether Robux purchases are open, the starter-pack offer |
| `RequestAd` | client → server | the rewarded video placement (`quest_reroll`); the reply comes when the video ends |
| `NotificationPrompt` | server → client | after your first finished match: ask to turn on experience notifications (once per profile) |

## UI and controls

Phone first: the map fills the screen, the HUD stays on the edges, and every action is a tap on the map followed by a tap in a bottom sheet.

- **Camera:** top-down; one finger pans, pinch zooms between 3 levels (whole map, region, province). Double-tap your capital to recentre.
- **Top bar:** gold, manpower, Primordial-power charges, match timer, your rank, and a mute button (see "Sound and effects").
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

- **Where:** a public server's match is shared by up to 12 players, so the tutorial runs on a reserved server of the same place. A player whose profile hasn't finished the tutorial (`tutorialDone`) and hasn't played a match is teleported to a fresh reserved server; every reserved server plays the tutorial. Private (VIP) servers never send anyone, so friends who join one stay together. When its match ends, or the player skips, they go back to a public server; a failed teleport is tried again a few times (`Config.Tutorial`), the player is never seated in the next tutorial match, and a small "🌍 Play online" button stays on screen after Skip or "Stay". In Studio the Workspace attribute `Tutorial` starts the tutorial match directly (teleports can't run there).
- **The match:** Earth, the player as Ganges (`Config.Tutorial`), the 5 nations nearest to them as Easy bots, and the other 4 nations gone (their land neutral, with garrisons). No Lobby. The player starts with a 3-regiment army so the first prompt can start at once.
- **Prompts:** a card under the top bar (step counter, one short line, one hint, Skip), an arrow and ring on the province to tap, and a glowing outline on the button to press. The player does every step with the normal UI. Each prompt ends when the match shows it done: owns a province it didn't start with, recruited, is besieging, is in an alliance, is at war, used a power. A step done early counts when its prompt comes up.
- **Bots help:** every bot accepts the player's alliance offer; the ally prompt points at the nearest bot, the war prompt at the weakest bot on the player's border. When the war prompt starts, Peace ends at once (the clock jumps to 3:00); the power prompt tops the player up to 1 charge (a Blessing on their own land).
- **Skip and done:** Skip takes two taps. Finishing, skipping or the end of the tutorial match (finished or not) saves `tutorialDone`; players who had already played a match count as done. Each prompt done is an onboarding funnel step and a skip is a `tutorial_skipped` event (`docs/LAUNCH.md` "Analytics events"); the server also prints started, finished and skipped in the Output.

### UI style: "pixel kingdom"

One look for every screen, made to sit on WorldBox's pixel map and read at a glance on a phone. Tokens live in `src/client/UI/Theme.luau`, components in `src/client/UI/Widgets.luau`, icons in `src/client/IconArt.luau` (painted) and `src/client/UI/Icons.luau` (on screen). Screens never pick their own colours, fonts or sizes.

- **Look:** chunky navy panels with a 2 px ink outline and a gentle top-to-bottom bevel; warm gold for titles, highlights and the selected tab; buttons with a darker bottom edge that squash (94%) and sink while pressed; pixel icons, never emoji.
- **Palette:**

| Token | Colour | Use |
| --- | --- | --- |
| `ink` | `#0b0d1a` | every outline |
| `navy` | `#1d2448` | panels, sheets, the top bar |
| `navyDeep` | `#12172f` | chips, wells, unselected tabs, full-screen backdrops |
| `navyRaised` | `#2a3366` | cards inside panels |
| `gold` / `goldDeep` / `goldPale` | `#f5c242` / `#b67f24` / `#ffe9a6` | titles, selection, prices |
| `text` / `textDim` / `textDark` | `#fff7e3` / `#b6bcdc` / `#2b1d0c` | body, hints, text on gold |
| `primary` / `good` / `danger` / `secondary` / `special` | `#3d7ce0` / `#3aa856` / `#d9434b` / `#4a5385` / `#8a4fd8` | buttons: main, confirm, war, cancel, Primordial |
| `disabled` | `#353a57` (text `#8a8fb0`) | can't be pressed now |

- **Type:** Fredoka One for titles, buttons and numbers; Builder Sans Bold for labels, Builder Sans Medium for hints. Sizes: hero 28, title 22, heading 18, body 15, small 14 (nothing smaller).
- **Spacing:** 4 / 6 / 8 / 12 / 16 px; corner radius 4 / 6 / 8; outlines 2 px; buttons at least 44 px tall.
- **Icons:** 16×16 sprites in one 24-colour palette with a dark outline (`IconArt.ICONS`, plus recoloured variants), each painted once into its own 1 KB EditableImage on first use and shown with pixelated resampling at 16, 20, 24 or 32 px. Without EditableImage they fall back to emoji. A leading emoji in a toast or older string becomes its icon (`IconArt.EMOJI`). `lune run tools/harness/icon_sheet` paints them all into `tools/harness/out/gui/icons.png`; `tests/icons.spec.luau` checks every icon.
- **Components** (`Widgets`): `panel`, `sheet` (bottom sheet), `card`, `header` (icon, gold title, close cross), `title`, `label`, `hint`, `button` (colours `BUTTON`, `GOOD`, `DANGER`, `BUTTON_OFF`, `GOLD`, `SPECIAL`), `iconTextButton`, `iconButton`, `actionButton` (icon, caption, cost line), `setEnabled`, `tab` / `setTab`, `chip` (icon + value), `badge`, `progress` / `setProgress`, `toast` / `setToast`, `icon`, `leadIcon`, `setIconText`.
- **GUI objects:** a button is 4 objects (button, corner, outline, bevel); the press scale is made on the first press. Hidden sheets and pickers drop their buttons and rebuild them when they open, and the private server sheet is built on first open.
- **On the map** (`MapRenderer`, `MapBadges`; "Map rendering"): province names in Builder Sans 14 with a solid ink outline, gold while selected; development as a bar of pixel cells, gold when reached. Army strength badges and province status pills are small `navyDeep` plates (4 px corners, a 1 px edge) with a 16 px icon and Fredoka One numbers: the edge is the army's nation colour (gold while selected), or the status's colour (`danger` battle, `gold` siege, `special` Primordial powers). The coalition leader's crown is a 20 px pixel crown on its flag pole; the "map art is off" notice is a toast.
- **Phase banners** (`Effects`): War, Cataclysm and Results pop in (a 0.6 to 1 scale) as a plate in `danger`, `special` or `gold` with the ink outline and the darker bottom edge, a 32 px icon (crossed swords, meteor, flag) and hero-size Fredoka One, then fade.
- **Results:** a panel with two columns, the match (title with a trophy or flag, how it was won, the top 5 with flags, a crown on the winners and your row on a raised card, the quests the match moved and the achievements it unlocked) and your reward (XP and Glory chips, the breakdown under a star and a medal for its two columns, your level line and bar, your Glory), over a footer row: Quests (gold), the season pass (purple, while a season runs), achievements (trophy) and "Next match starts soon". It fits 667×375; only an unusually long breakdown makes it shrink to fit.
- **Tutorial:** the prompt card is a panel with a gold outline under the top bar: a gold step pill ("2/6"), the prompt's icon and title, and a gold hint whose icon is the button to press, or the map arrow when the tap goes on the map. The map arrow and the arrow over the glowing button are the kit's arrow turned to point down, in gold, at 48 px; the ring round the province is a gold line on an ink edge; the button to press gets a pulsing gold outline. Skip takes two taps; "Play online" and the end card's buttons are kit buttons.

### Sound and effects

Cosmetic and client-only (`src/client/Effects.luau`, `src/client/Sounds.luau`): they read the delta's events and records, never change the match. WorldBox pixel style: square particles in whole map pixels, colours from `Palette.fx`, moved with TweenService.

| Moment | Effect | Sound |
| --- | --- | --- |
| Battle starts | dust puff and pixel crossed swords | `BattleStart` |
| Battle ends | burst in the winner's colour; bigger, with a white flash and a pixel skull, if an army was destroyed | `BattleEnd` / `ArmyDestroyed` |
| Province changes hands | flash and rings in the new owner's colour | `Capture` (`Lost` if it was yours) |
| Meteor | falling fireball with a trail, impact flash, ring of fire, crater dust, a crater, screen shake | `MeteorFall`, `MeteorImpact` |
| Plague | sickly green pulses over the nation's provinces | `Plague` |
| Rebels | black flags popping up | `Rebels` |
| Earthquake | map shake and crack lines over the province | `Earthquake` |
| Blessing | golden sparkles | `Blessing` |
| Divine shield | a blue dome with a twinkling ring for as long as the shield lasts | `Shield` |
| Power-effect cosmetics | Meteor, Plague and Blessing are drawn in the caster's equipped look (`src/client/PowerFx.luau`): Ice Meteor and Violet Plague recolour; Sun Rays adds beams of light and star sparkles; Comet Strike a glittering tail, a glowing head and a star burst. Same area (`PowerFx.AREA`), timing and sound as the default. The `Power` event names the caster (`by`) | the power's own |
| War, Cataclysm, Results | a screen-wide flash and a short banner | `War`, `Cataclysm`, `Results` |
| Any button | | `Tap` |

- **Phones:** at most 240 pooled particle frames, 8 other nations' effects (14 with powers and your own fights) at once, 6 shield domes. Effects off screen are skipped, and other nations' battles and captures are skipped where the province is under 16 screen pixels wide.
- **Sounds:** stand-ins for now, all listed in `Sounds.luau`: the few files every Roblox client ships in `content/sounds` (the default character sounds: footsteps, jumps, landings, falling, swimming, an explosion, a splash, "oof"), played at different speeds. Before launch the owner swaps in Creator Store or uploaded sounds (`rbxassetid://…`). A missing file is harmless (Roblox logs it and stays silent). You hear your own battles and captures even off screen.
- **Mute:** a speaker button at the right end of the top bar; it mutes every sound and is remembered for the session.

## Bot AI

Each bot checks a short priority list every few seconds and does the first action that applies, using the same commands as players.

**Priority list** (bots are staggered so 1–2 plan per tick)

1. **Defend:** an enemy army borders one of my provinces → send the nearest army if my strength is at least 0.8× theirs, otherwise recruit there.
2. **Recruit:** total army is below provinces × 800 men and manpower is available.
3. **Expand:** a neutral neighbour whose garrison I can beat → attack it.
4. **Attack:** an enemy I'm at war with, or my weakest neighbour, if my strength is above the attack ratio and there's no truce.
5. **Build:** gold left over after 2 months of upkeep → barracks first, then farms, forts on borders, then develop.
6. **Diplomacy:** ally with a nation that shares my enemy; accept peace after losing 30% of my provinces in a war; join coalitions against the leader.
7. **Primordial power:** with 2 charges, Meteor the biggest army of a nation I'm at war with that isn't immune right now. This rides along with whatever else the plan does, so charges don't pile up.

| Difficulty | Plans every | Attack ratio | Behaviour |
| --- | --- | --- | --- |
| Easy | 6 s | 1.6× | Won't declare war on a player, march into a player's land or use a power on one in the first 8 min (it still defends) |
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

- [x] `AIService` on Normal; bots fill empty slots and replace leavers
- [x] Elimination and the Primordial role
- [x] 6 Primordial powers with charges and cooldowns
- [x] Catch-up rules: overextension, underdog, coalition
- [x] Cataclysm phase

**Gate 3:** 1 player against 9 bots is fun for 25 minutes, and no single bot wins most matches.

### Phase 4: Polish and shop

- [x] 2D pixel-art map for Earth, Eldmoor and Skyshards (WorldBox style, painted at runtime)
- [x] Map textures: biome tile patterns, height shading, foam and waves on the whole map, and a close-up detail layer when zoomed in (smooth coasts and borders, shaded trees, a lighter kingdom wash)
- [x] Map vote in the Lobby with the three vote cards
- [x] Tutorial match
- [x] Progression rules in Sim: match XP and Glory, level curve, ranks
- [x] `PlayerDataService` (ProfileStore): XP, Glory, items, receipts; Results screen rewards
- [x] Daily and weekly quests, login calendar, play streak
- [x] Shop: catalogue, Robux and Glory purchases, VIP pass, starter pack, purchase history
- [x] Cosmetics shown in the match: flags, borders, tokens, emotes, power effects, victory animations, theme vote (also shade sets and nameplate frames; map themes Night, Winter and Autumn; a private server's "Default" theme setting forces the classic look through `MatchService.forcedTheme`)
- [x] Private server settings
- [x] Sound and effects for battles and Primordial powers
- [x] UI kit with a "pixel kingdom" look and runtime pixel icons, on the HUD, sheets, powers, nations, offers, map vote, draft, private settings and emotes ("UI style")
- [ ] Shop and Quests restyled on the UI kit
- [x] Results, Tutorial, phase banners and map overlays (names, pip bars, army badges, status pills, crown) restyled on the UI kit

**Gate 4:** 10 testers who have never played finish the tutorial without help.

### Phase 5: Soft launch

- [x] Analytics events (`docs/LAUNCH.md`): match length, quit time, phase reached, win rate by start position, funnels, economy
- [ ] Weekly balance patch from the data
- [x] Easy and Hard bots (evidence: `docs/BALANCE.md` 16)
- [x] Per-map balance from win rate by start position (bot tournament; `docs/BALANCE.md` section 17)
- [x] Season pass (8 weeks, 50 tiers)
- [x] Rotating shop
- [x] Weekly, friends and global leaderboards; achievements
- [x] Rewarded video quest reroll; experience notifications
- [ ] Soft-launch gates met (`docs/LAUNCH.md`) before Season 1

## Open questions

Answered:

- Working title: **Total World Chaos**.
- Real-world map or fictional continents? **Both**: Earth (region names, never countries), Eldmoor and Skyshards. See `docs/MAPS.md`.
- Hex grid or hand-made provinces for the final map? **Neither**: a province pixel grid generated from the map data, drawn as pixel art. See `docs/MAPS.md`.
- Can a Primordial target the nation that eliminated them? **Yes** (the simplest rule; revisit after playtests).

Still open:

- Art style beyond the maps: historical, fantasy or meme?
- Casual only, or a ranked mode after launch? Proposed: ranked beta in month 5–6 if peak CCU ≥ 1,500 (`docs/MONETIZATION.md` 7.5).
- Provinces flip when a siege ends (current rule) or only through peace deals?
