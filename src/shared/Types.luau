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
-- Power(a = power index in Sim.Primordial.POWERS, b = nation hit or 0, at province), Disaster (same fields),
-- Eliminated(a)
export type MatchEvent = { kind: string, a: number, b: number, province: number }

export type MatchResult = {
	kind: "Domination" | "Alliance" | "Score",
	winners: { NationId },
	scores: { { nation: NationId, score: number } }, -- best first
	endedAt: number, -- tick
}

export type MatchState = {
	mapId: string,
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
	battles: { [ProvinceId]: Battle },
	offers: { Offer },
	events: { MatchEvent },
	result: MatchResult?, -- set when someone has won; the phase is then Results
}

-- The lobby before a match (Sim.Lobby): the map vote ("Lobby"), then the nation draft ("Pick"). It lives outside
-- MatchState because the vote happens before there is a map; the draft seats players in the new match.
export type LobbyState = {
	phase: "Lobby" | "Pick",
	ticksLeft: number, -- until this phase ends
	maps: { string }, -- the map ids on the vote cards
	locked: string?, -- a map the server set (Workspace "MapId", later private servers): no vote
	votes: { [number]: string }, -- userId -> map id (kept per voter, so a theme vote can look at the winners' voters)
	mapId: string?, -- the chosen map, once the vote is over
	order: { number }, -- draft order (userIds)
	turn: number, -- index in order of who picks now (> #order when the draft is done)
	turnTicks: number, -- length of one turn
	turnTicksLeft: number,
	picks: { [number]: NationId }, -- userId -> nation
}

-- Lobby intents: CommandRouter checks the shape, Sim/Lobby checks the rules.
export type LobbyIntent = { kind: "Vote", map: string } | { kind: "Pick", nation: NationId }

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
}

-- One row of a reward breakdown. kind: Finish, Placement, Provinces, Battles, Primordial, Powers, FirstMatch,
-- Vip, CustomRules, PaidEarlier (what an earlier leave already paid, negative), LevelUp, RankUp.
export type RewardLine = { kind: string, xp: number, glory: number }

export type MatchReward = {
	xp: number,
	glory: number,
	lines: { RewardLine },
	placement: number?, -- nil without a nation or after leaving early
	stayed: boolean, -- stayed to Results
	afk: boolean, -- sent no command for Config.Progression.AfkTicks in a row: paid nothing
}

-- The saved profile (ProfileStore data). Version 2.
export type PlayerProfile = {
	version: number,
	xp: number, -- total account XP
	level: number,
	glory: number,
	lastMatchDay: number, -- UTC day of the last paid match (first-match-of-the-day bonus)
	owned: { [string]: boolean }, -- item id -> true
	equipped: { [string]: string }, -- slot -> item id
	quests: { day: number, week: number, rerollsUsed: number, daily: { any }, weekly: { any } }, -- placeholders
	login: { step: number, lastPlayDay: number, streak: number }, -- placeholders
	achievements: { [string]: number }, -- id -> progress
	season: { id: string, xp: number, premium: boolean, claimed: { [string]: boolean } },
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
export type CosmeticSlot = "Flag" | "Border" | "Shades" | "Token" | "Frame" | "Victory" | "Emote" | "PowerFx"

export type CatalogueItem = {
	id: string,
	slot: CosmeticSlot,
	rarity: Rarity,
	name: string,
	art: string, -- the design the client draws (CosmeticArt), or the icon of an emote, effect or animation
	glory: number?, -- Glory price; nil = not sold for Glory
	robux: number?, -- list price in Robux (the shop shows MarketplaceService's live price); nil = not sold for Robux
	free: boolean?, -- everyone owns it: the defaults
	vipOnly: boolean?, -- comes with the VIP pass, never sold alone
	power: PrimordialPower?, -- PowerFx: the power it re-skins
	animated: boolean?,
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
}

-- Shop requests: CommandRouter checks the shape, Sim.Shop the rules. Equipping an item puts it in its slot.
export type ShopIntent =
	{ kind: "Buy", item: string, currency: "Glory" | "Robux" }
	| { kind: "Equip", item: string }
	| { kind: "Emote", item: string }

-- What a player sees of their own shop state (the Shop remote, after every change).
export type ShopView = {
	owned: { string }, -- item and offer ids
	equipped: { [string]: string }, -- equip key -> item id
	vip: boolean,
	history: { PurchaseRecord }, -- newest first
	robuxOpen: boolean, -- Robux purchases are open now (never during a match)
	starterOffer: boolean, -- show the starter-pack offer now (at most once per session)
	testMode: boolean, -- some product ids are still 0: Studio grants those purchases free
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
