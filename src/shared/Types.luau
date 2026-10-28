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
	retreating: boolean?, -- beaten: walking home on its path; takes no orders, doesn't fight, block or besiege
}

export type War = { id: number, attackers: { NationId }, defenders: { NationId }, startedAt: number }
export type Alliance = { id: number, members: { NationId } }
export type Truce = { a: NationId, b: NationId, untilTick: number }
export type Primordial = { userId: number, charges: number }

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
	joinedAt: number,
	leftAt: number?, -- set when they leave before Results
	lastCommandAt: number,
	longestIdle: number, -- longest run of ticks without a command so far
	provincesTaken: number,
	battlesWon: number,
	powersUsed: number,
}

-- One row of a reward breakdown. kind: Finish, Placement, Provinces, Battles, Primordial, Powers, FirstMatch,
-- Vip, CustomRules, LevelUp, RankUp.
export type RewardLine = { kind: string, xp: number, glory: number }

export type MatchReward = {
	xp: number,
	glory: number,
	lines: { RewardLine },
	placement: number?, -- nil without a nation or after leaving early
	stayed: boolean, -- stayed to Results
	afk: boolean, -- sent no command for Config.Progression.AfkTicks in a row: paid nothing
}

-- The saved profile (ProfileStore data). Version 1.
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
	purchaseHistory: { { product: number, robux: number, at: number } },
	stats: { matches: number, wins: number, provincesTaken: number, battlesWon: number, powersUsed: number },
	settings: { [string]: any },
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

return {}
