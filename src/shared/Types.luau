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

export type MapDef = {
	id: string, -- "earth" | "eldmoor" | "skyshards"
	title: string,
	theme: string, -- texture set: "earth" | "fantasy" | "sky"
	imageSize: Point,
	nations: { NationDef },
	provinces: { ProvinceDef },
	straits: { StraitDef },
}

-- Intents: what a player or bot asks for. CommandRouter checks the shape, Sim/Commands checks the rules.

export type Command =
	{ kind: "Develop", province: ProvinceId }
	| { kind: "Build", province: ProvinceId, building: Building }
	| { kind: "Recruit", province: ProvinceId, regiments: number }

return {}
