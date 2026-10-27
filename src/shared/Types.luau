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
	siege: { by: NationId, progress: number, required: number }?,
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
-- ProvinceTaken(a takes province from b), BattleEnded(a won against b at province), Victory(a)
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
	tris: { number }, -- the province's shape: triangles as flat x0, y0, x1, y1, x2, y2, ... in map pixels
}

export type NationDef = { slot: number, name: string, capital: ProvinceId, colorIndex: number }

export type StraitDef = { a: ProvinceId, b: ProvinceId, from: Point, to: Point, wrap: boolean }

-- The simplified border line between two neighbouring provinces: flat x0, y0, x1, y1, ... in map pixels.
export type BorderDef = { a: ProvinceId, b: ProvinceId, points: { number } }

export type MapDef = {
	id: string, -- "earth" | "eldmoor" | "skyshards"
	title: string,
	theme: string, -- texture set: "earth" | "fantasy" | "sky"
	imageSize: Point,
	nations: { NationDef },
	provinces: { ProvinceDef },
	straits: { StraitDef },
	borders: { BorderDef },
}

-- Intents: what a player or bot asks for. CommandRouter checks the shape, Sim/Commands checks the rules.

export type DiplomacyAction = "War" | "Ally" | "AcceptAlly" | "Peace" | "AcceptPeace"

export type Command =
	{ kind: "Develop", province: ProvinceId }
	| { kind: "Build", province: ProvinceId, building: Building }
	| { kind: "Recruit", province: ProvinceId, regiments: number }
	| { kind: "Move", army: ArmyId, to: ProvinceId }
	| { kind: "Diplomacy", action: DiplomacyAction, target: NationId, gold: number }

return {}
