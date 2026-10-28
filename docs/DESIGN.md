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
| EU4 | Provinces, development, armies on a map, sieges, alliances, war and peace, coalitions against the leader | Trade nodes, estates, missions, ideas, religion, rebels, ship types and admirals (navies are one ship per map), war score, most modifiers |
| WorldBox | World powers (here: Primordial powers), disasters, the four classic races (and a cast of peoples for every map), watching borders spread across the map, the pixel-art map look | Individual units, creatures, sandbox world editing |

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

1. **Lobby (60 s):** players join and vote on the map with three cards (tap a card, tap it again to vote). Most votes wins; a tie, or no votes, is settled at random. A server locked to one map (Workspace `MapId`, or a private server's map setting) shows only that card and skips the vote. On a private server the owner changes the next match's settings here (`docs/MONETIZATION.md` 3.4): length, Peace, bots, powers, disasters, teams, map and theme. A public server's first match has no vote: the first player to choose Play online picks the map ("Start menu" below).
2. **Pick (up to 30 s):** the chosen map shows every nation's start territory, and players pick a start nation one at a time in a random draft order, by tapping its land (then confirming) or its name in the list. Each turn lasts 30 s ÷ players (3–8 s); a turn that runs out picks a random free nation. Someone who joins during the draft goes to the end of the order. Bots take the rest. The match clock starts at 0:00 when the draft ends.
3. **Peace (0–3 min):** no wars between nations; expand into neutral provinces and build.
4. **Open war (3–20 min):** everything unlocked.
5. **Cataclysm (20–25 min):** Primordial powers recharge twice as fast and a random disaster hits every 60 s.
6. **Results (30 s):** winner, stats and XP. Then the Lobby opens again to vote on the next map; everyone stays in the server.

Joining mid-match takes over a bot's nation. For Studio solo tests (and the harness) the Workspace attribute `SkipLobby` starts every match straight in Peace.

**Start menu**

A player arriving on a public or private server first sees a brass window over the map (or the Lobby) with three big tiles, **Play online** (gold), **Singleplayer** and **How to play**, and under them one line saying what the server is doing: who is picking the map, the vote's clock, the draft, or a match on. New players still go to the tutorial first, as before (`TutorialService`); the menu is for everyone else. Tutorial and sandbox servers have no menu.

- **Play online** (`RequestMenu "Online"` through `CommandRouter`, then `MenuService`, at once): the server closes the menu and the player joins this server's matches: the first pick's line, the vote, the end of the draft, or mid-match a bot's nation straight away (as joining did before). Until then the player only watches: not drafted, not seated, and a bot keeps playing the nation they will get.
- **Singleplayer:** three map cards (Earth, Eldmoor, Skyshards, with their thumbnails): tap one, tap it again, and `Intents.enterSandbox(map)` sends the player to a world of their own ("Sandbox"). Studio can't teleport: the menu's line says so.
- **How to play:** five pages of three steps, each an icon and one short line: Grow (recruit, march, win the siege), War and sieges, Allies, Primordial powers, How to win. A pager turns the pages; ✕ goes back. Its numbers come from `Config`. There is no "Play the tutorial" button: a tutorial match pays like any match, against 5 Easy bots, so replaying it would be an easy Glory farm until a replayed tutorial pays nothing.
- **First pick:** a public server's first Lobby is a first pick instead of a vote. Players who choose Play online get in line, and the first in line picks the map on the vote's three cards (tap, tap again); the pick starts the draft at once, with everyone in line. The clock (`Config.Phases.FirstPickTicks`, 20 s) runs only while someone is in line; when it runs out the map is random. A chooser who leaves passes the pick to the next in line with a full clock. Everyone else in line sees "Alice is picking the map" on the cards (and the menu's line says it too), and everyone hears the result: "Alice picked Eldmoor", or "Time's up: Eldmoor it is". The server keeps the line and refuses anyone else's pick (`NotYourTurn`; `Sim/Lobby`). Later matches vote as before.
- **Private servers and locked maps:** the menu shows, but a private server (the owner's settings and map, the owner's flow) and a server locked to a map (`MapId`) keep the usual Lobby for every match, the first included.
- **Studio:** `SkipLobby` turns the menu off too. The Workspace attribute `Menu` decides it: `true` shows it even with `SkipLobby` (an arrival during a solo match), `false` hides it and the first match votes. The harness boots every scenario with `Menu` = false except `menu`.
- **Analytics:** `menu_shown`, `menu_choice` and `first_pick` (`docs/LAUNCH.md`).
- **UI:** `UI/Menu` above every other screen, the screen dimmed behind it; every decision two taps, text at least 14 px, buttons at least 44 px; it fits 844×390, 667×375 and the tablets (`Widgets.fit`). The first pick reuses the vote screen (`UI/MapVote`).

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

## Sandbox (singleplayer)

A world of your own, WorldBox style: the ten nations of a map play as bots while you watch, lead any people you like, cast every Primordial power for free and set the speed of time. No end and no rewards. It keeps WorldBox's powers and time controls, not its terrain painting or creatures (those stay cut, see the table above).

- **Where:** a sandbox needs a server of its own, so it runs on a reserved server of the same place, like the tutorial. The entry point is `Intents.enterSandbox(mapId?)` on the client (`RequestSandbox "Enter"` → `SandboxService.enter(player, mapId?)`): from any server it teleports the player to a fresh reserved server with teleport data `{ mode = "sandbox", map = mapId }`; on a sandbox server it starts a new world instead. The start menu's Singleplayer button calls it. A reserved server learns what it is for from its first player's teleport data (`ServerMode`); without `mode = "sandbox"` it plays the tutorial as before. The data comes through the client, so a forged one could only swap a tutorial for a sandbox, and neither pays anything. A new player sent to a sandbox is never sent on to the tutorial. **World → Play online** goes back to a public server; a failed teleport is a toast and the button works again. In Studio (no teleports, no reserved servers) the Workspace attribute `Sandbox` (`true`, or a map id) makes the server a sandbox from the start; `MapId` works too.
- **The world:** the map the player was sent with (the default map otherwise), all ten nations as Normal bots (`Config.Sandbox.Difficulty`), no Lobby. A player arrives **watching**. **World → New world** starts over on any of the three maps, at 1× with disasters off, everyone watching again.
- **Play as (take over any nation):** two taps, Play as then a nation, any time. The player leads that nation from then on, with its land, armies, gold, wars and alliances; the nation they leave goes back to a bot at once (the bots plan for it from the next tick). **Watch** gives the nation back and keeps only the powers. Every people of the map is playable this way, one after another. Only a living nation nobody else holds can be taken (another player's is "Taken": only Studio tests have two). A player whose nation falls goes back to watching: no Primordial rises, since their powers are free anyway.
- **Free powers:** all six Primordial powers, with no charges, in every phase (Peace too), whether the player leads a nation or watches. The targeting rules stay: never a mountain, Earthquake only on a province with a building, Rebels, Blessing and Shield on a nation's province, Meteor on an army, Plague on a nation. The immunity and the per-caster cooldown are off for the whole world, and a harmful power may hit the player's own nation (it's their world). Bots still pay with their nations' charges and wait for War, as in a match.
- **Time:** pause, 1×, 2× and 4× (`Config.Sandbox.Speeds`): the server runs that many ticks a second. Its loop wakes every `Config.Sandbox.BeatSeconds` (0.25 s) and runs a tick whenever the speed has gathered a game second; a late beat catches up at most `MaxTicksPerBeat` ticks. Paused, the clock stops and the bots wait, but orders and powers still land within a beat. The controls travel in the snapshot and its deltas (`MatchState.sandbox`), so the client's clock and the armies' glide follow the speed, and stand still when paused.
- **Phases:** the usual Peace (3:00, so the peoples spread over the neutral land first), then War for ever. No Cataclysm, no Results, no win check: domination, alliance victory and 25:00 end nothing. The top bar's clock counts up.
- **Disasters:** off at the start. **World → Disasters** switches them on: a random harmful power on a random valid target (the Cataclysm's rule) every 60 s from that moment, in any phase, until switched off.
- **No rewards:** no XP, Glory, quests, login calendar, achievements, season pass or leaderboard progress (the sandbox never tracks match stats, and `Progression.matchReward` pays 0 for one). Analytics send only `sandbox_started` (`docs/LAUNCH.md`) and the economy events of real purchases; no funnels, onboarding steps or match events. The shop works as during a match (Robux purchases stay closed).
- **Authority:** every sandbox action is a `RequestSandbox` intent through `CommandRouter` (shape and rate limit), then `SandboxService`, which accepts it only on a sandbox server (`NotSandbox` elsewhere; `Enter` works anywhere). These run at once rather than at the next tick, so the time controls work while paused. Powers are ordinary `RequestPower` commands: in a sandbox `Sim.Commands` casts a player's power for free. Bots keep sending the same commands as players. Rules: `Sim/Sandbox.luau`, and the sandbox cases in `Settings.timing`, `Tick`, `Primordial` and `Progression`.
- **UI:** a small panel at the top left, under the top bar (`UI/Sandbox`): the four time tabs (the selected one in gold), **Play as**, ✨ **Powers** (the usual power picker, opened beside the panel, every power free; the round power button stays hidden) and ⚙ **World**. Play as and World open in the panel's place, with ✕ to close. Every decision is two taps; it fits 844×390 and 667×375.

## Core systems

Two resources (gold and manpower), a cast of five races on every map (fifteen in all), three shared troop roles plus one elite per race, and one siege rule carry the whole game. Every number below is a starting value for playtests and lives in one `Config` module.

### Map and provinces

- ~150 land provinces, each with terrain, development (1–5) and at most one building.
- Terrain: plains (normal), forest and hills (+25% defence, slower movement), mountains (impassable, used to make chokepoints).
- About 40% of provinces start **neutral** with a small garrison (one regiment, `Config.NeutralGarrison`; a map can set a bigger one per province), so the first minutes are about expansion, not PvP.
- Islands connect through "straits": extra neighbour links drawn as bridges or sea lanes. The water itself is split into sea zones that fleets sail (see "Navies").
- Three maps: **Earth** (real world), **Eldmoor** (fantasy continent) and **Skyshards** (floating islands). Every nation starts with 8 provinces and 17 total development on every map. Details, art and data pipeline: `docs/MAPS.md`.

### Races

Every map has its own cast of five peoples, two nations each, set per nation in the map data (`docs/MAPS.md`), so picking a nation picks its race: realistic civilisations on Earth, WorldBox's four classic races and the Lizardfolk on Eldmoor, sci-fi peoples on Skyshards. Neutral garrisons and Rebels have none. Each race has one passive and one elite troop (see Troops). Races and troops are data: `Config.Races` (each race's name, passive kind and numbers, elite), `Config.Troops` and `Config.Casts` (each map's five races, and its own names and icons for the shared troop roles).

**Passive kinds.** Every race takes one of seven, with its own numbers in `Config.Races`:

| Kind | Effect |
| --- | --- |
| Gold | +10% gold income (gross: provinces and capital, before upkeep) |
| Manpower | +20% manpower income |
| Forest | Cross forest at plains speed; +10% combat strength in battles in forest provinces |
| Hills | +25% combat strength when defending in hills; forts cost half |
| Upkeep | Armies cost 15% less upkeep |
| Swift | Armies march 20% faster (every step's time × 0.8, rounded, at least 1 s) |
| Attack | +10% combat strength when attacking |

**Earth: realistic.** Human civilisations only, archetypes a history strategy game uses, never a real people or present-day nation; they go to nations by terrain and balance (the nations keep their river names).

| Race | Passive | Elite | Nations |
| --- | --- | --- | --- |
| Kingdom | Gold | Knights | Rhine, Niger |
| Empire | Attack | Legionaries | Zambezi, Amazon |
| Nomads | Swift | Horse archers | Volga, Mississippi |
| Republic | Upkeep | Crossbowmen | Ganges, Mekong |
| Clans | Hills | Pikemen | Tigris, Yangtze |

**Eldmoor: fantasy.**

| Race | Passive | Elite | Nations |
| --- | --- | --- | --- |
| Humans | Gold | Knights | Frostmarch, Corsairs |
| Elves | Forest | Rangers | Mistborn, Elderwood |
| Orcs | Manpower | Berserkers | Greenvale, Ashen Dominion |
| Dwarves | Hills | Ironguard | Ironholds, Wyrmcoast |
| Lizardfolk | Attack | Raptor riders | Saltmarsh, Sunscorch |

**Skyshards: sci-fi in space.** Its shared troops are troopers, gunners and hover bikes (the same roles and numbers as infantry, archers and cavalry).

| Race | Passive | Elite | Nations |
| --- | --- | --- | --- |
| Marines | Gold | Mechs | Aurora, Solace |
| Robots | Upkeep | Drones | Tempest, Verdance |
| Insectoids | Manpower | Hive warriors | Zephyr, Ember |
| Crystal folk | Forest (crystal groves are forest) | Golems | Nimbus, Rime |
| Energy beings | Swift | Storm wisps | Halo, Umbra |

- Combat bonuses add to the battle modifier like the terrain, fort and catch-up bonuses, for the whole side: an ally fighting beside an Elven army in a forest shares the Elves' bonus (as with the underdog bonus). A side counts each passive once.
- Each map's races are fitted to the land where it makes sense (Forest races in forests, Hills races in hills) and spread so every race gets strong and weak start positions; on symmetric Skyshards each race holds two opposite shards.
- The draft card shows each nation's race (icon and name); the nation you tap gets a race card with its one-line bonus. The nations drawer shows every nation's race, and yours with its bonus.
- On the map (see "Map rendering"), in the WorldBox spirit: each race's capital is its own building (a stone castle for Humans, a tree hall for Elves, a castle of cone-roofed towers for the Kingdom, a felt tent for the Nomads, a hive spire for the Insectoids...), and a nation's armies are a little soldier of its race unless it has an army token cosmetic equipped. The province sheet's owner chip shows the owner's race icon (a war, alliance or truce icon wins).
- Rules: `Sim/Races.luau`; numbers: `Config.Races`, `Config.Casts`; balance: `docs/BALANCE.md` sections 18 and 19.

### Economy

Income is paid every month (10 s). A nation starts with 100 gold and 3,000 manpower.

| Item | Cost | Effect |
| --- | --- | --- |
| Province income | — | +1 gold and +100 manpower per development level |
| Capital | — | +5 gold per month |
| Race passive | — | Gold races +10% gold (gross, before upkeep), Manpower races +20% manpower, Upkeep races −15% upkeep |
| Regiment (1,000 men of one troop type) | Infantry 10 gold + 1,000 manpower; the other troops in Troops | Upkeep per month: infantry 1.5 gold, the others in Troops (Upkeep races pay 15% less) |
| Develop province | 30 gold × current level | +1 development (max 5) |
| Farm | 50 gold | +50% gold from this province |
| Barracks | 40 gold | +50% manpower from this province |
| Fort | 60 gold (Hills races 30) | +50% defence, siege time ×2 |
| Ship (the map's one type, see Navies) | 25 gold | Upkeep 1 gold per month; fights at sea and carries one regiment |

### Troops

The regiment (1,000 men) is a troop type now. An army is still one token and one stack, with a composition: how many men of each troop type it holds. `Army.men` stays the total; one helper (`Army.setTroops`) changes it and the composition together, so they always agree.

Three shared roles every nation recruits, on every map; Skyshards calls them troopers, gunners and hover bikes (same numbers, sci-fi icons):

| Troop | Skyshards | Cost | Upkeep | Attack | Defence | Speed |
| --- | --- | --- | --- | --- | --- | --- |
| Infantry (the old regiment) | Troopers | 10 gold + 1,000 manpower | 1.5 | 1.0 | 1.0 | normal |
| Archers | Gunners | 15 gold + 1,000 manpower | 2 | 0.75 | 1.5 | normal |
| Cavalry | Hover bikes | 25 gold + 1,000 manpower | 3 | 1.5 | 1.0 | fast |

One elite per race (Knights are both the Kingdom's and the Humans'):

| Elite | Race (map) | Cost | Upkeep | Attack | Defence | Speed |
| --- | --- | --- | --- | --- | --- | --- |
| Knights | Kingdom (Earth), Humans (Eldmoor) | 35 gold + 1,000 manpower | 4 | 2.0 | 1.25 | fast |
| Legionaries | Empire (Earth) | 25 gold + 1,000 manpower | 2 | 1.5 | 1.75 | normal; an army with Legionaries besieges 1.5× as fast |
| Horse archers | Nomads (Earth) | 25 gold + 1,000 manpower | 2.5 | 1.5 | 1.25 | fast |
| Crossbowmen | Republic (Earth) | 20 gold + 1,000 manpower | 2.5 | 1.5 | 1.5 | normal |
| Pikemen | Clans (Earth) | 15 gold + 1,000 manpower | 1.75 | 1.25 | 2.0 | normal |
| Rangers | Elves (Eldmoor) | 20 gold + 1,000 manpower | 2.5 | 1.25 | 1.75 | normal |
| Berserkers | Orcs (Eldmoor) | 12 gold + 750 manpower | 1.5 | 1.75 | 0.75 | normal |
| Ironguard | Dwarves (Eldmoor) | 25 gold + 1,000 manpower | 2 | 1.5 | 2.0 | normal; an army with Ironguard besieges 1.5× as fast |
| Raptor riders | Lizardfolk (Eldmoor) | 20 gold + 750 manpower | 2.5 | 1.75 | 1.0 | fast |
| Mechs | Marines (Skyshards) | 40 gold + 1,000 manpower | 4 | 2.25 | 2.0 | normal |
| Drones | Robots (Skyshards) | 15 gold + 750 manpower | 2 | 1.25 | 0.75 | fast |
| Hive warriors | Insectoids (Skyshards) | 12 gold + 750 manpower | 1.5 | 1.75 | 0.75 | normal |
| Golems | Crystal folk (Skyshards) | 25 gold + 1,000 manpower | 2 | 1.25 | 2.25 | normal |
| Storm wisps | Energy beings (Skyshards) | 30 gold + 1,000 manpower | 3 | 2.0 | 1.0 | fast |

- Upkeep is gold per regiment (1,000 men) per month. Normal speed: 5 s per plains province, 8 s forest and hills; fast: 3 s and 6 s.
- The first numbers were tuned with bot tournaments (`docs/BALANCE.md` section 18): Berserkers' upkeep 2 → 1.5, Ironguard 30 → 25 gold, upkeep 3 → 2, attack 1.25 → 1.5 and sieges 1.25× → 1.5×, the Elves' forest bonus 25% → 10%. The other casts' first numbers and their first measurements are in section 19.
- Recruit buys whole regiments of one type into the army standing in the province (or a new one). A nation recruits its map's three shared roles and its race's elite; the server refuses any other elite.
- Battles: a side's strength is the sum of its men × each troop's attack (attacking side) or defence (defending side), times the modifiers. Losses split over an army's troop types in proportion to their men. Merging stacks adds the compositions.
- An army moves at its slowest troop's speed (retreating too).
- A Meteor's 50% applies to every troop type. Neutral garrisons and Rebels are infantry. Every rule that counts men (retreats under 500, the bots' army sizes, the HUD) counts the total; quests, achievements, telemetry and the tutorial count every troop as a regiment.
- An army's main troop type is the one with the most men; a tie goes to the dearer troop (gold per regiment), then to the later one in `Troops.LIST` (the shared roles first, then the elites, sorted). Its badge on the map and its chip on the province sheet show that troop's icon as the map draws it, so an archer-heavy army shows a bow (a heavy gun on Skyshards) (`MapBadges.mainTroop`, `Troops.icon`).
- Rules: `Sim/Troops.luau`, `Sim/Army.luau`; numbers: `Config.Troops`; balance: `docs/BALANCE.md` sections 18 and 19.

### Armies and combat

- An army is a stack of regiments of any troop types (its composition, see Troops) shown as one token on the map: a nation's armies that stand still in the same province (not marching, fighting or retreating) merge into one, and their compositions add up.
- Movement: one province per 5 s on plains, 8 s on forest and hills; 3 s and 6 s for fast troops (cavalry, knights, horse archers, raptor riders, drones, storm wisps). An army moves at its slowest troop's speed; a Forest race crosses forest at plains speed and a Swift race marches 20% faster. Paths follow province neighbours (BFS).
- A battle starts when enemy armies share a province and lasts 3 rounds of 1 s. Each round, each side kills enemy men equal to 15% of its own strength × modifiers. Strength = the sum of its men × each troop's attack (attackers) or defence (defenders); losses split over troop types in proportion to their men.
- Modifiers: defender in forest or hills +25%, fort +50%, underdog +50%, coalition +30%, a Forest race in a forest +10%, a Hills race defending in hills +25%, an Attack race attacking +10%, random ±10% per battle.
- After round 3 the side with fewer men retreats: it walks to its nearest owned province on the shortest path over land it may enter, at its own speed (its slowest troop's), under a 🏳 flag. On the way it takes no orders and doesn't fight, block a siege or besiege; it is a normal army again when it arrives (or when its way closes). Armies under 500 men are destroyed, and so is a loser with no way home.

### Sieges

- An army alone in an enemy or neutral province starts a siege: 10 s × development, ×2 with a fort, ×3 for a capital. Army size doesn't matter, but an army with siege troops in it (Ironguard or Legionaries; the holder's or an ally's) besieges 1.5× as fast (a third less time).
- One siege per province. Whoever started it keeps it while one of its (or an ally's) armies stands there; another besieger at peace with it waits instead of blocking, and takes over (from zero) once the first one leaves.
- An interrupted siege (a battle there, a defending army, the besieger stepping out) keeps its progress for 10 s, then resets. Peace with the owner, or the province changing hands, ends it at once.
- A province the besieger's side blockades from the sea (see Navies) falls 1.25× as fast, on top of siege troops.
- When the siege completes, the province flips to the attacker immediately. No war score and no haggling over provinces in peace deals.

### Diplomacy

- **War:** declare on any nation you border, by land or by sea: holding a coast of the same sea zone counts (see Navies). Your allies join automatically.
- **Alliance:** request and accept; max 3 nations per alliance.
- **Peace:** white peace, or peace plus a gold tribute. A 3-minute truce follows.
- **Coalition:** a nation holding 20%+ of the ownable provinces gets a crown on the map, and every other nation gets +30% combat strength against it.

### Navies

Each map's water is split into named **sea zones** (on Skyshards, **space zones** in the void around the shards). Nations build ships in their coastal provinces, carry armies across the water, fight at sea, close straits and blockade coasts. Rules: `Sim/Navy.luau`; numbers: `Config.Navy`; the zones of each map: `docs/MAPS.md` "Sea zones"; how bots use fleets: "Bot AI"; balance, measured with bot tournaments: `docs/BALANCE.md` section 20.

- **Sea zones:** Earth has 22 (the oceans and seas, such as the North Atlantic and the Mediterranean), Eldmoor 10 round its coasts, Skyshards 10 (one wedge of space round each home shard). A zone lists its neighbouring zones and its coasts: the provinces it touches. A province touching several zones is a coast of each; the one it shares the most shore with is its **port**. Every strait lies in one zone. Lakes (the Caspian, Moonmere) have no zone. Zones are tappable: the map data's sea grid gives every water pixel its zone id (`MapGrid.decodeSea`), as the province grid does for land.
- **Ships:** one ship type per map: a sailing **Galleon** on Earth, a **Dragonship** on Eldmoor, a **Starship** on Skyshards, with the same numbers everywhere. A ship costs 25 gold (no manpower) and 1 gold upkeep a month, fights with a hull of 1,000 (like a regiment's 1,000 men, attack and defence 1) and carries one regiment: 1,000 men of any troop type. Ships are built 1–5 at a time in an owned coastal province and launch into its port zone, joining the nation's fleet standing there or forming a new one. A blockaded province can't launch ships.
- **Fleets:** a nation's ships standing still in one zone are one fleet, one token, merging like armies. A fleet sails from zone to zone (8 s a zone, along the fewest zones) with the men aboard. A damaged fleet still counts its hull in whole ships, rounded up: 2,550 hull is 3 ships that carry 3 regiments.
- **Embarking:** order an army onto one of your fleets. It walks to the nearest coast of the fleet's zone (or of the zone the fleet is sailing to) and boards when the fleet is there; as many men as there is room for go aboard (every troop type in proportion), and the rest stay ashore as the same army. The men aboard are no army while at sea: they can't fight, besiege or be hit by a Meteor, and they still cost upkeep.
- **Landing:** order a fleet to a coastal province. It sails to the nearest zone off it and lands everyone aboard there as one army, which fights and besieges as usual. Landing needs land your armies could walk into (yours, an ally's, neutral, or an enemy's at war); if peace closes it before the fleet arrives, the men stay aboard.
- **Sea battles:** fleets of nations at war in the same zone fight with the land rule: 3 rounds of 1 s, each side killing 15% of its hull × modifiers (the random ±10%, the underdog and coalition bonuses; no terrain or forts at sea). Nobody owns the sea, so the zone's first fleet (lowest id) with an enemy there defends. Then the side with less hull retreats: each of its fleets sails, men aboard and all, to the nearest other zone off a friendly coast, taking no orders and fighting nobody on the way. A fleet with nowhere to go, or left under 500 hull, sinks with everyone aboard. Each winner gets +1 battle won.
- **Straits:** an enemy fleet (at war with you, not retreating) in a strait's zone stops your armies crossing that strait; an army already on it stops at its edge. Skyshards' bridges are straits, so a space fleet off a shard cuts it off from the Heartstone and its drift isles.
- **Blockades:** your coastal province is blockaded while an enemy fleet is in one of its zones and no fleet of yours or an ally's is there. It earns 25% less gold, can't launch ships, and sieges of it by the blockader's side run 1.25× as fast. You get a toast when a blockade starts.
- **War reach:** you may declare war on a nation you share a sea zone with (both hold a coast of it), not only on one you border by land, because fleets make wars across water real.
- **Races at sea:** race passives are about armies. At sea there is no Attack, Forest or Hills bonus, every fleet sails at the same speed (Swift is for marching), and an Upkeep race pays less for the men aboard but full price for its ships.
- **Who sees fleets:** everyone sees every fleet for now. One helper decides it (`Navy.visible`), so fog of war can hide fleets later without touching the rules.
- **Controls** (the same flow as moving an army): tap your fleet, then a sea zone (or an enemy fleet in it) to sail there, or a coastal province to land there, see the route and its time, then Sail or Land. To embark, tap an army, then one of your fleets, then Board. Ships are built from an owned coastal province's sheet: the Ships tile opens the choice of 1 to 5 (25 gold each); on a blockaded coast it is greyed with an anchor and "Blockaded". The fleet sheet shows the ships and their zone, the men aboard out of the room (and the main troop types aboard), and where the fleet is going; tapping someone else's fleet shows the same without orders. What the server would refuse is said at once with the same toast (no coast, nobody aboard, the fleet is full).
- **On the map:** each fleet is the map's ship in its nation's colours (a Galleon, a Dragonship with a dragon's head and a row of shields, a steel Starship), 16 × 12 pixels, at its zone's centre, gliding from zone to zone; fleets resting in one zone sit side by side. Its badge is the army badge's plate with a ship icon (a burst in a sea battle, a white flag retreating), its ships and the men aboard ("3 · 2k"). Zoomed out, each zone's name stands under its centre in pale blue italics, wherever it covers no province name. A blockaded coast gets an anchor pill (blue edge) in its status row: from the region zoom inwards on every coast, zoomed out only on yours and where you blockade. Sea battles get spray and crossed swords when they start and a burst when they end, with a skull if a fleet sank.
- **Toasts:** a sea battle won or lost (with the zone's name), a blockade starting (for the blockaded nation and the blockader) and your army landing.
- An eliminated nation's fleets disband with everyone aboard.

### Primordial powers

Living nations earn 1 charge every 4 minutes; Primordials earn 1 charge every 60 s, counted from the moment they rose (each Primordial has its own clock; nations share the match clock because they all start at 0:00). A nation can be hit by a harmful power at most once per 60 s, from anyone, and the same caster can hit the same nation at most once per 2 minutes, so no Primordial can focus one nation (`Config.Primordial.ImmunityTicks`, `TargetCooldownTicks`; owner request).

| Power | Effect | Charges |
| --- | --- | --- |
| Meteor | Kills 50% of one army; −1 development in that province | 2 |
| Plague | −50% manpower income for one nation for 60 s | 2 |
| Rebels | Spawns a 3,000-man neutral army in one province | 2 |
| Earthquake | Destroys the building in one province | 1 |
| Blessing | +100% gold from one province for 60 s | 1 |
| Shield | One province can't be sieged for 30 s | 1 |

- Targets: Meteor an army; Plague a nation; Rebels, Blessing and Shield a nation's province; Earthquake a province with a building. Mountains are never a target.
- Powers work in War and Cataclysm, not in Peace. Charges stop at `Config.Primordial.MaxCharges` (5).
- Both limits apply to the harmful powers (Meteor, Plague, Rebels, Earthquake), which can't target your own nation; Blessing and Shield are gifts and ignore them. A Cataclysm disaster has no caster, so only the immunity applies to it. A caster is a living nation, or a Primordial (a player keeps one cooldown clock per target while a nation and gets a fresh one on rising).
- Meteor's limit is checked for the army's owner, who then becomes immune. The province it stands in loses its development level only if that province's owner isn't immune, and that loss doesn't make the owner immune.
- The power picker shows an immune nation as unavailable (with the seconds left), and a nation you hit less than 2 minutes ago as "You can hit X again in N s", instead of sending a power the server would refuse.
- Rebels besiege the province they rise in; when the siege ends it turns neutral. On the map they are a black 🏴 token that always shows, unlike neutral garrisons.
- A Primordial may target anyone, including the nation that eliminated them.
- Cataclysm disasters are a random harmful power on a random valid nation target (seeded), every 60 s from 21:00.
- A sandbox world ("Sandbox") turns the immunity off, lets its player cast every power for free in any phase, and runs disasters only while its player has them on.

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
    ServerMode.luau            -- what this server is for: matches, the tutorial or a sandbox (reserved servers)
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
      SandboxService.luau      -- the singleplayer sandbox on a reserved server: intents, teleports in and out
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
2. Sail fleets, board armies standing on a coast onto their fleets, land fleets that arrived and merge a nation's fleets standing in one zone; then move armies (retreating armies walk home too) and merge a nation's armies standing in the same province.
3. Resolve battles on land, then at sea; then mark the blockaded provinces.
4. Advance sieges and flip provinces.
5. Every 10th tick: pay income and upkeep.
6. Update Primordial-power charges and timers.
7. Bots plan (staggered: 1–2 bots per tick).
8. Check win conditions and phase changes.
9. Send one delta to every client.

A sandbox server ("Sandbox") runs the same order at the speed its player sets (none paused, up to 4 ticks a second), without the win check and without match stats, rewards or analytics.

### Networking

- **On join:** one full snapshot of provinces, nations, armies and fleets.
- **Every tick:** one batched delta with only what changed (owners, development, blockades, armies, fleets, battle events).
- **Army movement:** an `UnreliableRemoteEvent` with progress between province centres; the client interpolates the token.
- **Fleet movement:** a sailing fleet's progress towards its next zone goes on the same unreliable channel as the moving armies (in a list of its own), so its record is in a delta only when something else changes: a new zone, a battle, its hull, cargo or orders. The client glides the token between zone centres. The snapshot and the positions hold only the fleets `Navy.visible` shows (everyone sees every fleet for now, so one delta and one positions stream go to everyone; fog of war will need one per viewer). A sailing fleet costs about 36 bytes a tick (4 numbers) plus its record once per zone it enters, where it cost a whole record every tick before.
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
  - **Capitals:** each race builds its own, flying its owner's flag (grey while neutral), its roofs and banners in the owner's colour (`docs/MAPS.md` "Capitals and armies by race"). Eldmoor: a stone castle for Humans, a tree hall for Elves (a great pale-barked tree with little halls up in its crown), a spiked war camp for Orcs (a hide tent with bone spikes behind a palisade), a stone hall carved into a snowy mountain for Dwarves and a stepped pyramid of mossy stone for the Lizardfolk. Earth: a castle of cone-roofed towers (Kingdom), a marble palace of columns (Empire), a great felt tent with a horse-tail standard (Nomads), a harbour with a lantern tower (Republic), a tower house on a crag (Clans). Skyshards, of its sci-fi materials: a glowing dome (Marines), a factory with a radar dish (Robots), a hive spire (Insectoids), a cluster of glowing shards (Crystal folk), an orb of light over a pylon (Energy beings). A capital keeps the look of the nation it belongs to (the map data's race), whoever holds it: a conqueror only raises its flag. 5 × 6 pixels on the whole map, a 21 × 22 sub-pixel building in the close-up; tests in `tests/pixelart.spec.luau`, a sheet of every race's art from `lune run tools/harness/race_sheet`.
  - **Map themes** (shop cosmetics, docs/MONETIZATION.md 3.2): `Night`, `Winter` and `Autumn` repaint the terrain colours of any map before the owners go on top (moonlit land, a navy sea and village lights; snow and frozen shallows; turning leaves). Nation colours, borders, capitals and everything drawn over the map stay the same. The match's theme comes from the theme vote (`MatchState.theme`, sent in the snapshot); a player who chose "Always classic" sees the classic look. `tests/themes.spec.luau` checks on all three maps that every nation colour and border stands out from the themed terrain about as well as on the classic look.
- **On screen:** the buffer goes into one `EditableImage`, shown by an `ImageLabel` with pixelated resampling on a canvas that `MapView` pans and zooms (from the whole map down to 10 screen pixels per map pixel). An ownership change repaints only the provinces involved and their neighbours, and the image is uploaded at most once a frame.
- **Close-up detail:** zoomed in past about 4 screen pixels per map pixel (more on big screens, so the view always fits), `MapRenderer` lays a second `EditableImage` over the map: just the part in view (with room to pan), painted by `PixelArt.paintDetail` at 4 × 4 sub-pixels per map pixel (docs/MAPS.md "Art direction"): the biome patterns at full resolution, smooth coasts and province edges, beaches and surf, dense shaded trees and other decorations, lit mountain faces, a lighter kingdom wash (48%) with a stronger band inside each nation's border, the border line, the selection's white outline and each race's detailed capital. It repaints when the view settles somewhere it doesn't cover (a few milliseconds per frame, the old one staying up meanwhile), catches up with ownership, cosmetic and selection changes by repainting only those provinces, and follows the map theme. Zoomed out again, its image is destroyed so phones get the memory back. It isn't used with the half-size fallback image, or if the device refuses the second image.
- **On top:** GUI objects placed on the canvas, in the UI kit's look ("UI style"); `MapBadges` (pure, tested) decides what they say and where they stack.
  - **Names and pips:** province names in Builder Sans with a solid ink outline (gold while the province is selected), shown once a province is about 70 screen pixels wide; a name that would overlap a bigger province's name waits until there's room. A capital's name stands below its building, lower the closer you zoom, so the building stays in sight. From the region zoom inwards a development bar hangs under the name: one pixel cell per level, gold when reached (one small `EditableImage` per level, shared; text pips without `EditableImage`).
  - **Armies:** tokens glide from province to province a little above the centres (the names are below), and armies resting in one province stand side by side. A nation's token is a little soldier of its race in its colours (`CosmeticArt.SOLDIERS`, 12 × 12 like the token skins: on Eldmoor a footman with a kite shield and spear, an elf archer, a green orc warrior with horns, tusks and a cleaver, a red-bearded dwarf with an axe, a crested lizard warrior; on Earth a man-at-arms in a great helm, a legionary with a crested helmet, a horse archer in a fur cap, a crossbowman in a kettle hat, a bearded pikeman; on Skyshards a marine in power armour, a robot, an insect warrior, a crystal being, an energy being), or its equipped token skin; neutral garrisons keep their small grey square and Rebels their black one. Each has a strength badge: a dark pill with a pixel icon (the icon of the troop type the army is mostly made of, see "Troops"; burst in battle; white flag retreating; black flag for Rebels; shield for neutral garrisons) and its size in Fredoka One, outlined in its nation's colour (gold while selected). The badges of armies in one province stack in a column above them, so none covers another at any zoom. Sizes show from the region zoom inwards; zoomed out, only on your own armies, Rebels and the selected army. An idle neutral garrison's badge is laid out after the names: it shows only where it covers no name and no other garrison's badge (bigger provinces first), and the others keep their grey token until the player zooms in.
  - **Status row:** on top of the badges, the province's battle (burst, red edge) or siege (hourglass and percent, gold edge), a blockade (an anchor, blue edge; see "Navies"), then Primordial-power effects with their seconds left (shield, blessing, plague, or a strike's icon; purple edge). Zoomed out, the pills show only their icons unless it is your province or your siege.
  - **Fleets and sea zones:** ships at the zones' centres with their badges, and the zones' names zoomed out (see "Navies").
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
export type FleetId = number
export type ZoneId = number                -- a sea zone (a space zone on Skyshards)

export type Terrain = "Plains" | "Forest" | "Hills" | "Mountain"
export type Building = "None" | "Farm" | "Barracks" | "Fort"
export type Phase = "Lobby" | "Pick" | "Peace" | "War" | "Cataclysm" | "Results"
export type PrimordialPower = "Meteor" | "Plague" | "Rebels" | "Earthquake" | "Blessing" | "Shield"
export type Race = string                 -- a key of Config.Races (each map's cast: Config.Casts)
export type Troop = string                -- a key of Config.Troops (the three shared roles and the elites)
export type Composition = { [Troop]: number } -- men per troop type; adds up to Army.men

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
    shieldUntil: number?,      -- tick when a Shield ends
    buffs: { [string]: number }, -- buff name -> tick it ends
    blockade: NationId?,       -- an enemy fleet off its coast blockades it: the blockading nation
}

export type Nation = {
    id: NationId,
    name: string,
    colorIndex: number,        -- palette index, so game logic stays Roblox-free and testable
    race: Race,                -- from the map data
    controller: "Player" | "Bot",
    userId: number?,           -- nil for bots
    capital: ProvinceId,
    gold: number,
    manpower: number,
    charges: number,
    allianceId: number?,
    powerImmuneUntil: number,  -- 60 s protection from harmful Primordial powers
    eliminated: boolean,
}

export type Army = {
    id: ArmyId,
    owner: NationId,           -- 0 = neutral (garrisons, Rebels)
    location: ProvinceId,
    men: number,               -- the total; changes only through Army.setTroops
    troops: Composition,       -- men per troop type (garrisons and Rebels: infantry)
    path: { ProvinceId },      -- remaining route
    moveProgress: number,      -- ticks spent toward next province
    inBattle: boolean,
    rebel: boolean?,           -- raised by the Rebels power (drawn apart from garrisons)
    retreating: boolean?,      -- beaten and walking home: no orders, no fighting, no sieges
    boardFleet: FleetId?,      -- walking to the coast to board this fleet
}

export type Fleet = {
    id: FleetId,
    owner: NationId,
    zone: ZoneId,
    hull: number,              -- 1,000 per ship; ships = hull ÷ 1,000 rounded up
    troops: Composition,       -- the men aboard, per troop type
    men: number,               -- the total aboard; changes only through Navy.setCargo
    path: { ZoneId },          -- remaining route
    moveProgress: number,
    inBattle: boolean,
    retreating: boolean?,      -- beaten: sailing to a zone off a friendly coast
    landAt: ProvinceId?,       -- land the men aboard here on arrival
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
    zones: { [ZoneId]: SeaZone },  -- from the map: name, neighbouring zones, coasts
    shores: { [ProvinceId]: { ZoneId } }, -- the zones each coastal province touches, its port first
    straits: { [ProvinceId]: { [ProvinceId]: ZoneId } }, -- the zone each strait crosses
    fleets: { [FleetId]: Fleet },
    nextFleetId: FleetId,
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
    zones: { ZoneId }?,        -- the sea zones it is a coast of, its port first; nil inland
}

-- A sea zone: its name and fleets stand at `center`; `coasts` are the provinces it touches.
export type SeaZoneDef = {
    id: ZoneId, name: string, center: { x: number, y: number }, area: number,
    neighbors: { ZoneId }, coasts: { ProvinceId },
}

-- Which province each pixel of the 2D map belongs to (0 = sea or space), run-length encoded (see MapGrid).
export type GridDef = { width: number, height: number, rle: string }

export type MapDef = {
    id: string,                -- "earth" | "eldmoor" | "skyshards"
    title: string,
    theme: string,             -- texture set: "earth" | "fantasy" | "sky"
    imageSize: { x: number, y: number },
    ship: string,              -- the map's ship type: "Galleon" | "Dragonship" | "Starship"
    nations: { { slot: number, name: string, capital: ProvinceId, colorIndex: number, race: Race } },
    provinces: { ProvinceDef },
    -- zone: the sea zone the strait crosses
    straits: { { a: ProvinceId, b: ProvinceId, from: { x: number, y: number }, to: { x: number, y: number }, wrap: boolean, zone: ZoneId } },
    seaZones: { SeaZoneDef },
    grid: GridDef,
    seaGrid: GridDef,          -- which sea zone each pixel of the 2D map belongs to (0 = land or a lake)
}
```

Intents are typed too. `CommandRouter` checks their shape; `Sim/Commands` checks the rules.

```lua
export type Command =
    { kind: "Develop", province: ProvinceId }
    | { kind: "Build", province: ProvinceId, building: Building }
    | { kind: "Recruit", province: ProvinceId, regiments: number, troop: Troop }
    | { kind: "BuildShips", province: ProvinceId, ships: number } -- launched into the province's port zone
    | { kind: "Sail", fleet: FleetId, zone: ZoneId }
    | { kind: "Land", fleet: FleetId, province: ProvinceId }      -- sail to a zone off it, land everyone there
    | { kind: "Embark", army: ArmyId, fleet: FleetId }            -- walk to the fleet's coast and board
```

### Remotes

| Remote | Direction | Payload |
| --- | --- | --- |
| `RequestMove` | client → server | armyId, targetProvince |
| `RequestRecruit` | client → server | provinceId, regiments, troop type (the nation's race must be allowed it) |
| `RequestBuild` | client → server | provinceId, building |
| `RequestDevelop` | client → server | provinceId |
| `RequestDiplomacy` | client → server | action (War, Ally, AcceptAlly, Peace, AcceptPeace), targetNation, gold? |
| `RequestPower` | client → server | power, target province or nation |
| `RequestBuildShips` | client → server | provinceId, ships (1–5) |
| `RequestSail` | client → server | fleetId, zoneId |
| `RequestLand` | client → server | fleetId, provinceId (a coast: sail to a zone off it and land the men aboard) |
| `RequestEmbark` | client → server | armyId, fleetId (walk to the fleet's coast and board) |
| `CommandResult` | server → client | requestId, ok, reason |
| `Snapshot` | server → client | full match state, sent on join (every nation's race, every army's composition, the fleets you see with the men aboard) |
| `Delta` | server → client | changed provinces (with their blockade), nations, armies (with their composition), fleets (with their progress while sailing), events |
| `ArmyPositions` (unreliable) | server → client | tick; moving armies (id, from, to, progress %) and sailing fleets (id, from zone, to zone, progress %), two flat arrays, 16 a message |
| `Notify` | server → client | toast type and text |
| `RequestBuy` | client → server | itemId, "Glory" or "Robux" |
| `RequestEquip` | client → server | itemId |
| `RequestEmote` | client → server | emote itemId |
| `RequestTelemetry` | client → server | a UI-only analytics step (`Loaded`, `ShopOpened`, `ItemViewed`, `OfferOpened`, `NotificationPrompt`), optional short string; no reply, changes nothing |
| `RequestDefaultTheme` | client → server | true = always show the classic map (the map-theme opt-out) |
| `Shop` | server → client | your owned and equipped items, VIP, purchase history, whether Robux purchases are open, the starter-pack offer |
| `RequestAd` | client → server | the rewarded video placement (`quest_reroll`); the reply comes when the video ends |
| `NotificationPrompt` | server → client | after your first finished match: ask to turn on experience notifications (once per profile) |
| `RequestSandbox` | client → server | `Enter` map (from any server: off to a new sandbox world), `Leave`, `Speed` 0/1/2/4, `Play` nation (0 = watch), `Disasters` on, `NewWorld` map; all but `Enter` only on a sandbox server ("Sandbox") |
| `RequestMenu` | client → server | `Online`: the start menu's Play online (join this server's matches) |
| `Menu` | server → client | true = show your start menu, false = close it |

## UI and controls

Phone first: the map fills the screen, the HUD stays on the edges, and every action is a tap on the map followed by a tap in a bottom sheet.

- **Camera:** top-down; one finger pans, pinch zooms between 3 levels (whole map, region, province). Double-tap your capital to recentre.
- **Top bar:** gold, manpower, Primordial-power charges, match timer, your rank, and a mute button (see "Sound and effects").
- **Left drawer:** nation list with colour, province count and relation icon (ally, at war, truce).
- **Bottom sheet (tap a province):** owner, development, building, plus buttons for Develop, Build and Recruit (one button per troop your race recruits, each with its price) and, on a coast, Ships, or Declare war and Ally on foreign provinces.
- **Moving armies:** tap the army, tap the destination, see the path with arrival time (at the army's own speed), tap Confirm. The army sheet shows the composition as chips (troop icon and men). Fleets work the same way (see "Navies").
- **Primordial powers:** a power button opens a radial menu; pick a power, tap a target, confirm.
- **Map modes:** Political (default), Diplomacy (allies green, enemies red), Terrain.
- **Feedback:** toasts for war declared, province lost and battle won; a short screen shake for a meteor.

**Rules for every screen**

- Buttons at least 44 px and text at least 14 px on phone.
- Icons and numbers over words; no paragraphs anywhere in the HUD.
- Every UI change is checked in Studio's phone emulator before it's merged.

**Tutorial:** the first match is against 5 easy bots, with 6 prompts in order: take a neutral province, recruit (the Infantry button), siege, make an ally, declare war, use a Primordial power.

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

Cosmetic rarities (`Theme.rarity`, the outline and rarity line of shop cards and season pass rewards): Common `#c9cde0`, Rare `#5aa8ff`, Epic `#b36ff2`, Legendary `#ff9f3a`.

- **Type:** Fredoka One for titles, buttons and numbers; Builder Sans Bold for labels, Builder Sans Medium for hints. Sizes: hero 28, title 22, heading 18, body 15, small 14 (nothing smaller).
- **Spacing:** 4 / 6 / 8 / 12 / 16 px; corner radius 4 / 6 / 8; outlines 2 px; buttons at least 44 px tall.
- **Icons:** 16×16 sprites in one 24-colour palette with a dark outline (`IconArt.ICONS`, plus recoloured variants), each painted once into its own 1 KB EditableImage on first use and shown with pixelated resampling at 16, 20, 24 or 32 px. Without EditableImage they fall back to emoji. A leading emoji in a toast or older string becomes its icon (`IconArt.EMOJI`). `lune run tools/harness/icon_sheet` paints them all into `tools/harness/out/gui/icons.png`; `tests/icons.spec.luau` checks every icon.
- **Components** (`Widgets`): `panel`, `sheet` (bottom sheet), `card`, `header` (icon, gold title, close cross), `title`, `label`, `hint`, `button` (colours `BUTTON`, `GOOD`, `DANGER`, `BUTTON_OFF`, `GOLD`, `SPECIAL`), `iconTextButton`, `iconButton`, `actionButton` (icon, caption, cost line), `setEnabled`, `tab` / `setTab`, `chip` (icon + value), `badge`, `progress` / `setProgress`, `toast` / `setToast`, `icon`, `leadIcon`, `setIconText`; for the full-screen meta screens (shop, season pass, quests, trophies): `window` (a full-screen panel), `fitButton` (as wide as its icon and text: a price, Claim, Equip), `pager` (arrow buttons and "2/5"), `tag` (a status in a dark well: Owned, Equipped, a lock), `cornerButton` / `cornerRowEnd` (the Lobby's round buttons in the bottom-left corner), `countBadge` / `setCount`. Prices show the Robux glyph (U+E002, drawn by every Roblox font) or the Glory medal icon.
- **GUI objects:** a button is 4 objects (button, corner, outline, bevel); the press scale is made on the first press. Hidden sheets and pickers drop their buttons and rebuild them when they open, the private server sheet is built on first open, and the shop, season pass, quests and trophies screens build their contents when they open and drop them when they close.
- **On the map** (`MapRenderer`, `MapBadges`; "Map rendering"): province names in Builder Sans 14 with a solid ink outline, gold while selected; development as a bar of pixel cells, gold when reached. Army strength badges and province status pills are small `navyDeep` plates (4 px corners, a 1 px edge) with a 16 px icon and Fredoka One numbers: the edge is the army's (or fleet's) nation colour (gold while selected), or the status's colour (`danger` battle, `gold` siege, `azure` blockade, `special` Primordial powers). The coalition leader's crown is a 20 px pixel crown on its flag pole; the "map art is off" notice is a toast.
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
| Shield | a blue dome with a twinkling ring for as long as the shield lasts | `Shield` |
| Power-effect cosmetics | Meteor, Plague and Blessing are drawn in the caster's equipped look (`src/client/PowerFx.luau`): Ice Meteor and Violet Plague recolour; Sun Rays adds beams of light and star sparkles; Comet Strike a glittering tail, a glowing head and a star burst. Same area (`PowerFx.AREA`), timing and sound as the default. The `Power` event names the caster (`by`) | the power's own |
| War, Cataclysm, Results | a screen-wide flash and a short banner | `War`, `Cataclysm`, `Results` |
| Any button | | `Tap` |

- **Phones:** at most 240 pooled particle frames, 8 other nations' effects (14 with powers and your own fights) at once, 6 shield domes. Effects off screen are skipped, and other nations' battles and captures are skipped where the province is under 16 screen pixels wide.
- **Sounds:** stand-ins for now, all listed in `Sounds.luau`: the few files every Roblox client ships in `content/sounds` (the default character sounds: footsteps, jumps, landings, falling, swimming, an explosion, a splash, "oof"), played at different speeds. Before launch the owner swaps in Creator Store or uploaded sounds (`rbxassetid://…`). A missing file is harmless (Roblox logs it and stays silent). You hear your own battles and captures even off screen.
- **Mute:** a speaker button at the right end of the top bar; it mutes every sound and is remembered for the session.

## Bot AI

Each bot checks a short priority list every few seconds and does the first action that applies, using the same commands as players.

**Priority list** (bots are staggered so 1–2 plan per tick)

1. **Defend:** an enemy army borders one of my provinces → send the nearest army if my strength is at least 0.8× theirs, otherwise recruit there: archers (the best defenders) if I can pay for them and they make up at most 30% of my men, else infantry.
2. **Recruit:** total army is below provinces × 800 men and manpower is available. Infantry is the base; at war, my race's elite or cavalry if I can pay for it and still keep 2 months of upkeep, while the two make up at most 30% of my men (the elite first when it costs no more upkeep than cavalry, else whichever I have fewer men of).
3. **Expand:** a neutral neighbour whose garrison I can beat → attack it.
4. **Attack:** an enemy I'm at war with, or my weakest neighbour, if my strength is above the attack ratio and there's no truce. With no neighbour by land to take on, a nation across the sea (we both hold a coast of one sea zone, see "Navies") whose coast there a landing from one of my free stacks would beat the same way, if I can have the ships for it (step 5). An enemy across a sea we share counts as in reach, so a bot at war with one doesn't look for another war.
5. **Sea:** a coast my armies can't walk to (no route by land, because it runs through a nation at peace with me, or a closed one: an enemy fleet in a strait, an enemy army on the way), at most 2 zones from my port: neutral land a landing beats, or enemy land where it is above the attack ratio, reached without meeting a stronger fleet. Ships are built at my coast nearest my free stack, and my spare fleets sail there; once they carry the stack (at most the difficulty's ships for one landing, below), it embarks. One landing at a time. Ships are bought only with gold left over after 2 months of upkeep (theirs included), and their upkeep stays under the difficulty's share of my gold income.
6. **Build:** gold left over after 2 months of upkeep → barracks first, then farms, forts on borders (Hills races pay half), then develop; with everything built, spare gold buys regiments (the Recruit step's troop).
7. **Diplomacy:** ally with a nation that shares my enemy; accept peace after losing 30% of my provinces in a war; join coalitions against the leader.

Two kinds of order ride along with whatever the plan does:

- **Fleet orders** (they spend nothing; at most one per fleet): a fleet whose army has all boarded lands it on the coast it wins (the same choice as step 5), else on my nearest coast; my nearest empty fleet that beats the blockaders by the attack ratio sails against a blockade of my coast; an empty fleet sails off an enemy coast my army besieges, so the siege runs faster; the other empty fleets gather at the port of the landing being prepared, else at my home port (the port nearest my capital), unless they stand off an enemy coast, which they blockade. No fleet sails a route through a fleet it wouldn't beat by the attack ratio, and a bot reckons only with the fleets `Navy.visible` shows it.
- **Primordial power:** with 2 charges, Meteor the biggest army of a nation I'm at war with that isn't immune right now, so charges don't pile up.

| Difficulty | Plans every | Attack ratio | Ships: upkeep within this share of gold income, ships for one landing | Behaviour |
| --- | --- | --- | --- | --- |
| Easy | 6 s | 1.6× | 10%, 3 | Won't declare war on a player, march or land in a player's land or use a power on one in the first 8 min (it still defends, at sea too) |
| Normal | 3 s | 1.3× | 15%, 5 | Default |
| Hard | 2 s | 1.1× | 20%, 5 | Targets the leading player |

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
- [x] No focus-firing: a 60 s immunity after any harmful power, and a 2-minute cooldown per caster per nation (owner request; the power picker shows both)
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
- [x] Shop, season pass, quests, trophies and the Lobby's round buttons restyled on the UI kit
- [x] Results, Tutorial, phase banners and map overlays (names, pip bars, army badges, status pills, crown) restyled on the UI kit
- [x] Races (Humans, Elves, Orcs, Dwarves) and troop types (infantry, archers, cavalry, one elite per race): map data, rules, bots, the recruit buttons, army composition chips, races on the draft and the nations drawer (evidence: `docs/BALANCE.md` section 18)
- [x] Races and troops on the map: each race's capital in the pixel art, a soldier of the nation's race as the default army token, the main troop type's icon on army badges and province sheet chips, the race icon on the owner chip (harness scenario `kingdoms`)
- [x] "Slate & Brass" GUI (`docs/UI_DIRECTION.md` section 8), step 1: painted pixel frames (`FrameArt`, `Frames`, `Widgets.skin`) and enamel buttons everywhere; the harness draws 9-slice frames, shadows and stacked strokes
- [x] "Slate & Brass" GUI step 2: every window, sheet and panel framed (brass for meta and reward screens, iron in the match, plates for popovers and toasts), titles on brass plates on the frame's edge with the corner close gem, hard pixel shadows, dimmed modal windows, the province sheet docked left of the power button on small phones
- [x] "Slate & Brass" GUI step 3: the top bar as plates in Roblox's own top-bar row (`GuiService.TopbarInset`, with a fallback row under it), a scrim, counters with riding icons, the clock in a phase medallion, the `fitBar` order on small phones, one `Hud.contentTop()` for everything under the bar; on tablets the whole UI scales up with the screen's short side (`Theme.uiScale`, phones stay at 1)
- [x] "Slate & Brass" GUI step 4: the province sheet's actions as slot tiles five to a row (`Widgets.slotTile`: build bronze, recruit green, diplomacy in full colour; gold costs, red when short, greyed when not possible), a coast's Ships tile in the build row (six to a row when they fit), the development as the map's pip bar in a well, status chips on the info row when they fit; army and fleet composition as icon + men chips and a route line; the power button as a royal medallion with the picker docked beside it; your row raised in the nations drawer; offers on plates with a counter, under the toasts' line
- [x] A cast of five peoples for every map, data-driven (`Config.Races`, `Config.Casts`): human civilisations on Earth, the fantasy peoples and the Lizardfolk on Eldmoor, sci-fi peoples on Skyshards with troopers, gunners and hover bikes; seven passive kinds; an elite, a soldier, a capital and icons for each (evidence: `docs/BALANCE.md` section 19)

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
- [x] Singleplayer sandbox ("Sandbox"): a reserved server of your own, all ten nations as bots, Play as any nation, free powers, pause to 4×, no end and no rewards (harness scenario `sandbox`)
- [x] Start menu ("Match structure"): Play online, Singleplayer (three map cards, then the sandbox) and How to play (five pages); a server's first match on the first player's map pick, with no vote; later matches vote (harness scenario `menu`)
- [ ] Soft-launch gates met (`docs/LAUNCH.md`) before Season 1
- [x] Navies, stage 1: sea and space zones in the map data (generator, validator, `MapData`), the rules for ships and fleets, embarking and landing, sea battles, straits blocked by fleets, blockades and war across the sea (`Sim/Navy.luau`, tests in `tests/navy.spec.luau`)
- [x] Navies, stage 2: the orders through `CommandRouter`, fleets in the snapshot, the ship art for each map, fleet tokens and sea zones on the map, the fleet sheet, toasts, a harness scenario (`tools/harness/scenarios/navy.luau`), a `docs/STUDIO.md` recipe
- [x] Navies, stage 3: bots at sea (`Sim/Bot.luau`: the Sea step and fleet orders, tests in `tests/botsea.spec.luau`), navy numbers in the bot tournament, balance (`docs/BALANCE.md` section 20, Earth's Americas), fleets in the soak, a landing in the bots scenario

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
