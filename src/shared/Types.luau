--!strict
-- Shared types: the contract every module builds against (docs/DESIGN.md "Data model").

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
	owner: NationId?, -- nil = neutral
	development: number, -- 1..5
	building: Building,
	isCapital: boolean,
	-- lastTick: the last tick it progressed (or waited under a shield); kept Config.Siege.GraceTicks after that
	siege: { by: NationId, progress: number, required: number, lastTick: number }?,
	shieldUntil: number?, -- tick when Divine Shield ends
	buffs: { [string]: number }, -- buff name -> tick it ends
}

export type Nation = {
	id: NationId,
	name: string,
	colorIndex: number, -- palette index, so game logic stays Roblox-free and testable
	controller: "Player" | "Bot",
	userId: number?, -- nil for bots
	capital: ProvinceId,
	gold: number,
	manpower: number,
	charges: number,
	allianceId: number?,
	powerImmuneUntil: number, -- 30 s Primordial-power protection
	plagueUntil: number?, -- tick when a Plague ends (nil = none)
	eliminated: boolean,
	battlesWon: number, -- counts towards the score
}

export type Army = {
	id: ArmyId,
	owner: NationId, -- 0 = neutral (garrisons, Rebels)
	location: ProvinceId,
	men: number,
	path: { ProvinceId }, -- remaining route
	moveProgress: number, -- ticks spent toward next province
	inBattle: boolean,
	rebel: boolean?, -- true for the neutral army a Rebels power raised (clients draw it apart from garrisons)
	retreating: boolean?, -- beaten: walking home on its path; takes no orders, doesn't fight, block or besiege
}

export type War = { id: number, attackers: { NationId }, defenders: { NationId }, startedAt: number }
export type Alliance = { id: number, members: { NationId } }
export type Truce = { a: NationId, b: NationId, untilTick: number }
-- chargeTicks: progress towards the next charge (its own clock, started when the Primordial rose)
export type Primordial = { userId: number, charges: number, chargeTicks: number }

-- A fight in one province. It lasts Config.Battle.Rounds rounds, one per tick.
export type Battle = {
	province: ProvinceId,
	round: number, -- rounds fought so far
	attackerRoll: number, -- the random ± modifier each side gets for this battle
	defenderRoll: number,
}

-- An alliance or peace proposal waiting for the other nation to accept.
export type Offer = {
	id: number,
	kind: "Ally" | "Peace",
	from: NationId,
	to: NationId,
	tribute: number, -- gold the proposer pays when peace is accepted
	expiresAt: number, -- tick
}

-- Something worth telling players about (a toast). Cleared after every tick's delta.
-- kinds: WarDeclared(a attacks b), PeaceMade(a, b), AllianceFormed(a, b), Offer(a -> b, province = offer id),
-- ProvinceTaken(a takes province from b), BattleEnded(a won against b at province), Victory(a),
-- Power(a = power index in Sim.Primordial.POWERS, b = nation hit or 0, at province, by = the caster's nation, for a
-- Primordial the nation it last held, so clients show the caster's power-effect cosmetic), Disaster (same fields,
-- no caster), Eliminated(a)
export type MatchEvent = { kind: string, a: number, b: number, province: number, by: number? }

export type MatchResult = {
	kind: "Domination" | "Alliance" | "Score",
	winners: { NationId },
	scores: { { nation: NationId, score: number } }, -- best first
	endedAt: number, -- tick
}

export type Difficulty = "Easy" | "Normal" | "Hard"

-- A private server owner's match settings (docs/MONETIZATION.md 3.4; allowed values in Config.Private). Public
-- servers play the defaults (Sim.Settings.defaults). Flat lists only, so it survives the network.
export type MatchSettings = {
	map: string, -- a map id, or "" = the Lobby's map vote
	theme: string, -- "Vote" = the theme vote (the winning map's voters' theme), "Default" = always the default theme
	minutes: number, -- match length: Results at minutes × 60
	peaceMinutes: number, -- no wars or powers before this
	bots: number, -- most bot nations (0–9); nations nobody plays beyond this are taken off the map (land neutral)
	difficulty: Difficulty, -- every bot's difficulty
	powers: boolean, -- Primordial powers (nations and Primordials)
	disasters: boolean, -- the Cataclysm's disasters
	teams: { { userId: number, team: number } }, -- locked teams: these players start allied; none = off
}

-- How a match was set up, read by Sim from MatchState (never from globals).
export type MatchSetup = {
	private: boolean, -- a private server: rewards depend on the rules and the number of players (Sim.Settings)
	settings: MatchSettings,
}

export type MatchState = {
	mapId: string,
	setup: MatchSetup, -- the private server's settings (the defaults on a public server)
	tick: number,
	phase: Phase,
	provinces: { [ProvinceId]: Province },
	nations: { [NationId]: Nation },
	armies: { [ArmyId]: Army },
	wars: { [number]: War },
	alliances: { [number]: Alliance },
	truces: { Truce },
	primordials: { [number]: Primordial }, -- keyed by userId
	seats: { [number]: NationId }, -- userId -> the nation that player last held (a rejoining player gets it back)
	nextArmyId: ArmyId, -- army ids are never reused (clients and queued commands refer to armies by id)
	mergedInto: { [ArmyId]: ArmyId }, -- an army merged into another stack -> the army that took its men (Army.resolve)
	battles: { [ProvinceId]: Battle },
	offers: { Offer },
	events: { MatchEvent },
	result: MatchResult?, -- set when someone has won; the phase is then Results
	theme: string?, -- the map theme everyone sees (a Theme catalogue item id, from the theme vote); nil = classic.
	-- Cosmetic only: no rule reads it.
}

-- The lobby before a match (Sim.Lobby): the map vote ("Lobby"), then the nation draft ("Pick"). It lives outside
-- MatchState because the vote happens before there is a map; the draft seats players in the new match.
export type LobbyState = {
	phase: "Lobby" | "Pick",
	ticksLeft: number, -- until this phase ends
	maps: { string }, -- the map ids on the vote cards
	pool: { string }, -- every map the server can play (the cards when no map is locked)
	locked: string?, -- a map the server set (Workspace "MapId", a private server's map setting): no vote
	votes: { [number]: string }, -- userId -> map id (kept per voter, so a theme vote can look at the winners' voters)
	mapId: string?, -- the chosen map, once the vote is over
	order: { number }, -- draft order (userIds)
	turn: number, -- index in order of who picks now (> #order when the draft is done)
	turnTicks: number, -- length of one turn
	turnTicksLeft: number,
	picks: { [number]: NationId }, -- userId -> nation
	owner: number?, -- a private server's owner (userId): only they change the settings; nil = public server
	settings: MatchSettings, -- the next match's settings (changed only during the vote)
	theme: string?, -- the theme vote's result for the chosen map (Sim.Lobby.chooseTheme), once the vote is over
	themeBy: { number }?, -- the voters whose equipped theme won (credited on the draft screen)
}

-- Lobby intents: CommandRouter checks the shape, Sim/Lobby (and Sim/Settings) the rules. A Setting names a
-- MatchSettings key; "team" sets player `value`'s team to `extra`.
export type LobbyIntent =
	{ kind: "Vote", map: string }
	| { kind: "Pick", nation: NationId }
	| { kind: "Setting", key: string, value: string | number | boolean, extra: number }

-- The tutorial match (Sim.Tutorial): which prompt the new player is on. Lives outside MatchState, like the lobby.
export type TutorialState = {
	slot: NationId, -- the player's nation
	step: number, -- index in Sim.Tutorial.STEPS; #STEPS + 1 = finished
	startProvinces: { [ProvinceId]: boolean }, -- what the player owned at the start
	actions: { [string]: boolean }, -- command kinds the player has carried out (Recruit, Power...)
	friend: NationId?, -- the bot the ally prompt points at
	rival: NationId?, -- the bot the war prompt points at
	skipped: boolean,
	startedAt: number, -- tick the player was seated
	finishedAt: number?, -- tick
}

-- What the tutorial player's client is told (the Tutorial remote).
export type TutorialView = {
	step: number, -- 1..total; total + 1 = finished; 0 = skipped (nothing to show)
	total: number,
	province: ProvinceId, -- where the arrow points (0 = nowhere)
	nation: NationId, -- the nation the prompt names (0 = none)
	canLeave: boolean, -- a teleport to a public server works here (not in Studio)
}

-- Static map definitions (src/shared/MapData, generated from assets/maps/*/layout.json).

export type Point = { x: number, y: number }

export type ProvinceDef = {
	id: ProvinceId,
	name: string,
	terrain: Terrain,
	biome: string, -- cosmetic: picks the texture, never a rule
	development: number,
	neighbors: { ProvinceId }, -- includes straits
	center: Point, -- map pixels; 1 px = 0.5 stud
	area: number, -- map pixels
	startOwner: number?, -- start slot 1..10, nil = neutral
	isCapital: boolean,
	garrison: number?, -- neutral garrison override, men
}

export type NationDef = { slot: number, name: string, capital: ProvinceId, colorIndex: number }

export type StraitDef = { a: ProvinceId, b: ProvinceId, from: Point, to: Point, wrap: boolean }

-- Which province each pixel of the 2D map belongs to (0 = sea or sky), 1 pixel = 1 stud: run-length encoded
-- (id: u8, length: u16 little-endian) triples in base64, decoded by MapGrid.
export type GridDef = { width: number, height: number, rle: string }

export type MapDef = {
	id: string, -- "earth" | "eldmoor" | "skyshards"
	title: string,
	theme: string, -- texture set: "earth" | "fantasy" | "sky"
	imageSize: Point,
	nations: { NationDef },
	provinces: { ProvinceDef },
	straits: { StraitDef },
	grid: GridDef,
}

-- Intents: what a player or bot asks for. CommandRouter checks the shape, Sim/Commands checks the rules.

export type DiplomacyAction = "War" | "Ally" | "AcceptAlly" | "Peace" | "AcceptPeace"

export type Command =
	{ kind: "Develop", province: ProvinceId }
	| { kind: "Build", province: ProvinceId, building: Building }
	| { kind: "Recruit", province: ProvinceId, regiments: number }
	| { kind: "Move", army: ArmyId, to: ProvinceId }
	| { kind: "Diplomacy", action: DiplomacyAction, target: NationId, gold: number }
	-- target is an army, nation or province id, depending on the power (Sim.Primordial.TARGETS)
	| { kind: "Power", power: PrimordialPower, target: number }

-- Progression and saves (docs/MONETIZATION.md 4–5). Profiles are saved; MatchState never is.

-- What one player did in the current match (kept by the server, never sent by the client). Ticks are match ticks.
export type PlayerMatchStats = {
	userId: number,
	joinedAt: number, -- start of the current stretch in the server
	leftAt: number?, -- set when they leave before Results (cleared if they rejoin)
	playedTicks: number, -- ticks played in earlier stretches, before leaving and rejoining
	seated: boolean, -- had a nation or a Primordial at some point in the match
	lastCommandAt: number,
	longestIdle: number, -- longest run of ticks without a command so far
	provincesTaken: number,
	battlesWon: number,
	powersUsed: number,
	paidXp: number, -- already paid this match, when they left earlier
	paidGlory: number,
	-- what earlier payments this match already added to the lifetime stats (a leave, then Results)
	paidProvinces: number,
	paidBattles: number,
	paidPowers: number,
	-- for quests (Sim.Quests): what the player's nation did this match
	neutralTaken: number, -- provinces captured from neutral land
	capitalsTaken: number, -- enemy capitals captured
	regiments: number, -- regiments recruited
	buildings: number, -- buildings built
	developed: number, -- Develop orders carried out
	bestDevelopment: number, -- highest level a province reached by the player's Develop order
	alliances: number, -- alliances formed
	mostProvinces: number, -- most provinces held at once
	questCounted: { [string]: number }, -- quest stat -> what quests already counted (a leave, then Results)
}

-- One row of a reward breakdown. kind: Finish, Placement, Provinces, Battles, Primordial, Powers, FirstMatch,
-- Vip, CustomRules, PaidEarlier (what an earlier leave already paid, negative), LevelUp, RankUp, Calendar (the
-- login calendar step the day's first finished match pays).
export type RewardLine = { kind: string, xp: number, glory: number }

export type MatchReward = {
	xp: number,
	glory: number,
	lines: { RewardLine },
	placement: number?, -- nil without a nation or after leaving early
	stayed: boolean, -- stayed to Results
	afk: boolean, -- sent no command for Config.Progression.AfkTicks in a row: paid nothing
}

-- Quests, login calendar and play streak (docs/MONETIZATION.md 5.4–5.6). The pool is Config.Progression.Quests,
-- the rules Sim.Quests and Sim.Login. Days are UTC day numbers, weeks start on Monday (Sim.Quests.weekOf).

export type QuestTier = "Easy" | "Medium" | "Hard" | "Weekly"

-- One quest in the pool. stat: what counts (Sim.Quests.tally); max: progress is the best single match, not a sum.
export type QuestDef = { id: string, tier: QuestTier, stat: string, target: number, max: boolean? }

-- One quest a player has. day: the UTC day it was given (a weekly quest: its week).
export type QuestState = { key: string, id: string, day: number, progress: number, claimed: boolean }

-- profile.quests. day/week: the last day and week the quests were refreshed for.
export type QuestBook = {
	day: number,
	week: number,
	rerollsUsed: number, -- today
	videoRerolls: number, -- rerolls a rewarded video gave today (Sim.Quests.grantVideoReroll)
	daily: { QuestState },
	weekly: { QuestState },
}

-- profile.login. step: steps of the 7-step calendar done in this cycle (0..7); lastPlayDay: the last UTC day with
-- a finished match (-1 = never); streak: consecutive play days; best: the longest streak (its flames stay earned);
-- coveredWeek: the week whose one covered missed day is used (-1 = none).
export type LoginState = { step: number, lastPlayDay: number, streak: number, best: number, coveredWeek: number }

-- Quest requests: CommandRouter checks the shape, Sim.Quests the rules.
export type QuestIntent = { kind: "Claim", key: string } | { kind: "Reroll", key: string }

-- One quest as the player's client sees it.
export type QuestEntry = {
	key: string,
	id: string,
	tier: QuestTier,
	stat: string,
	target: number,
	progress: number,
	claimed: boolean,
	xp: number,
	glory: number,
	daysLeft: number, -- days it stays after today (0 = goes at the end of today; weekly: 0)
}

-- What a player sees of their quests (the Quests remote, after every change).
export type QuestView = {
	daily: { QuestEntry },
	weekly: { QuestEntry },
	freeRerolls: number, -- free rerolls left today
	rerollGlory: number, -- the price of a reroll once the free ones are used
	videoRerolls: number, -- rewarded videos the Quests screen may offer now (0: none; Sim.Quests.videoRerollsLeft)
	calendar: { glory: { number }, step: number, playedToday: boolean },
	streak: number, -- current play streak (0 when it has lapsed)
	best: number,
	flame: number, -- streak reward tier earned so far (0 = none; Config.Progression.Login.StreakFlames)
	gains: { [string]: number }, -- quest key -> progress the last match added (the Results screen)
}

-- The saved profile (ProfileStore data). Version 3.
export type PlayerProfile = {
	version: number,
	xp: number, -- total account XP
	level: number,
	glory: number,
	lastMatchDay: number, -- UTC day of the last paid match (first-match-of-the-day bonus)
	owned: { [string]: boolean }, -- item id -> true
	equipped: { [string]: string }, -- slot -> item id
	quests: QuestBook, -- version 3
	login: LoginState, -- version 3
	achievements: { [string]: number }, -- id -> progress
	season: SeasonState, -- the season pass (Sim.Season)
	receipts: { [string]: number }, -- purchase id -> os.time() it was granted (the last 200)
	purchaseHistory: { PurchaseRecord },
	stats: { matches: number, wins: number, provincesTaken: number, battlesWon: number, powersUsed: number },
	settings: { [string]: any },
	tutorialDone: boolean, -- finished or skipped the tutorial match (version 2)
}

-- What a player sees of their own profile (the Profile remote, the HUD badge, the Results level bar).
export type ProfileSummary = {
	level: number,
	xp: number, -- total
	xpIntoLevel: number, -- progress inside the current level
	xpForLevel: number, -- XP from this level to the next (0 at the cap)
	glory: number,
	rank: number, -- 1..#Config.Progression.Ranks
	rankName: string,
}

-- Sent to a player at Results: the reward (with level-up and rank-up lines) and their profile before and after.
export type RewardReport = { reward: MatchReward, before: ProfileSummary, after: ProfileSummary }

-- Shop and cosmetics (docs/MONETIZATION.md 3, 10). Item data is in Shared.Catalogue, the rules in Sim.Shop.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type CosmeticSlot = "Flag" | "Border" | "Shades" | "Token" | "Frame" | "Victory" | "Emote" | "PowerFx" | "Theme"

export type CatalogueItem = {
	id: string,
	slot: CosmeticSlot,
	rarity: Rarity,
	name: string,
	art: string, -- the design the client draws (CosmeticArt, PowerFx, PixelArt themes), or an emote's or animation's icon
	glory: number?, -- Glory price; nil = not sold for Glory
	robux: number?, -- list price in Robux (the shop shows MarketplaceService's live price); nil = not sold for Robux
	free: boolean?, -- everyone owns it: the defaults
	vipOnly: boolean?, -- comes with the VIP pass, never sold alone
	power: PrimordialPower?, -- PowerFx: the power it re-skins
	animated: boolean?,
	season: string?, -- a season-pass reward of this season id: never sold (MONETIZATION 6)
}

-- A pass or developer product that grants several items: VIP, the starter pack, nation skin sets.
export type ShopOffer = {
	id: string,
	kind: "Pass" | "Product",
	name: string,
	icon: string,
	items: { string },
	robux: number, -- list price
	oncePerAccount: boolean,
	weekly: boolean?, -- a bundle that rotates through the weekly shop slot (Sim.ShopRotation); else always offered
}

-- One Robux purchase in the receipt ledger (newest last). item: the catalogue item or offer id.
export type PurchaseRecord = { product: number, robux: number, at: number, item: string? }

-- One nation's equipped cosmetics, replicated next to MatchState (Snapshot.cosmetics). Item ids; bots and nations
-- without a player get the defaults. powerFx: power name -> PowerFx item id (missing = the default look).
export type NationCosmetics = {
	nation: NationId,
	flag: string,
	border: string,
	shades: string,
	token: string,
	frame: string,
	victory: string,
	powerFx: { [string]: string },
	vip: boolean,
	flame: number?, -- play-streak flame on the nameplate (Sim.Login.flameTier; nil or 0 = none)
}

-- Shop requests: CommandRouter checks the shape, Sim.Shop the rules. Equipping an item puts it in its slot.
export type ShopIntent =
	{ kind: "Buy", item: string, currency: "Glory" | "Robux" }
	| { kind: "Equip", item: string }
	| { kind: "Emote", item: string }
	| { kind: "DefaultTheme", on: boolean } -- the opt-out: always see the classic map

-- What a player sees of their own shop state (the Shop remote, after every change).
export type ShopView = {
	owned: { string }, -- item and offer ids
	equipped: { [string]: string }, -- equip key -> item id
	vip: boolean,
	history: { PurchaseRecord }, -- newest first
	robuxOpen: boolean, -- Robux purchases are open now (never during a match)
	starterOffer: boolean, -- show the starter-pack offer now (at most once per session)
	testMode: boolean, -- some product ids are still 0: Studio grants those purchases free
	defaultTheme: boolean, -- the player always sees the classic map, whatever theme won the vote
	rotation: RotationView?, -- today's rotating shop (Sim.ShopRotation; ShopService adds it)
}

-- The rotating shop (docs/MONETIZATION.md 3.8, Sim.ShopRotation): the same for every player and server on a day.
-- daily: item ids (2 Common, 1 Rare, 1 Epic); weekly: a Legendary item id and a bundle offer id. *Left: seconds
-- until the next refresh when the server sent it (00:00 UTC; weekly: Monday 00:00 UTC).
export type RotationView = { day: number, daily: { string }, weekly: { string }, dailyLeft: number, weeklyLeft: number }

-- Season pass (docs/MONETIZATION.md 6). Seasons and their rewards are Config.Season, the rules Sim.Season.
export type SeasonTrack = "Free" | "Premium"

-- One reward on a tier: a catalogue item, Glory, a title or a season badge (titles and badges are earned, never sold).
export type SeasonReward = { item: string?, glory: number?, title: string?, badge: string? }

-- One tier of a season's reward list (an empty track = nothing on that tier).
export type SeasonTier = { free: { SeasonReward }, premium: { SeasonReward } }

-- A season: id ("S1"), name, its UTC days [startDay, endDay) and its 50 tiers.
export type SeasonDef = { id: string, name: string, startDay: number, endDay: number, tiers: { SeasonTier } }

-- profile.season. xp: account XP earned this season (Sim.Progression.addXp counts it); premium: bought the pass;
-- bundle: bought the pass bundle (+Config.Season.BundleTiers tiers, once); claimed: "F12" / "P12" -> true;
-- bonus: bonus rewards past the last tier already paid.
export type SeasonState = {
	id: string,
	xp: number,
	premium: boolean,
	bundle: boolean,
	claimed: { [string]: boolean },
	bonus: number,
}

-- Season requests: CommandRouter checks the shape, Sim.Season the rules. "Viewed": the season screen opened
-- (analytics only). The pass itself is bought through the shop (RequestBuy "season_pass" / "season_bundle").
export type SeasonIntent =
	{ kind: "Claim", tier: number, track: SeasonTrack }
	| { kind: "ClaimAll" }
	| { kind: "Viewed" }

-- What a player sees of the season pass (the Season remote). id = "" when no season is running.
export type SeasonView = {
	id: string,
	name: string,
	daysLeft: number, -- days after today until the season ends
	xp: number, -- season XP, with the bundle's tiers
	tier: number, -- 1..maxTier (0 without a season)
	maxTier: number,
	xpIntoTier: number, -- progress to the next tier (or to the next bonus reward at the last tier)
	xpForTier: number,
	premium: boolean,
	bundle: boolean,
	claimed: { string }, -- "F3", "P3"
	ready: number, -- rewards claimable now (bonus rewards included)
	bonusReady: number, -- bonus rewards past the last tier waiting to be claimed
	nextStartDay: number?, -- without a season: when the next one starts (nil = none planned)
}

-- Analytics (docs/LAUNCH.md 7): Sim.Telemetry builds these, Services/TelemetryService sends them to
-- AnalyticsService. No personal data: userId only says which Player the call is made for (nil = a match-wide event,
-- sent for any player in the server).
export type TelemetryEvent = {
	kind: "Custom" | "Funnel" | "Onboarding" | "Economy" | "Progression",
	userId: number?,
	name: string, -- custom event name, funnel name, currency or progression path ("Onboarding" for onboarding)
	value: number, -- custom value; funnel or onboarding step number; economy amount; progression level
	step: string?, -- funnel or onboarding step name; economy itemSku; progression level name
	session: string?, -- funnel session id
	flow: string?, -- economy "Source" | "Sink"; progression "Start" | "Complete"
	transaction: string?, -- economy transaction type (Enum.AnalyticsEconomyTransactionType names)
	balance: number?, -- economy ending balance
	fields: { string }, -- custom fields 1-3
}

return {}
