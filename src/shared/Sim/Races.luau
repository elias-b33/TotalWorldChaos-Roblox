--!strict
-- Races (docs/DESIGN.md "Races"): the peoples nations belong to. Data-driven: every race is an entry of Config.Races
-- and every map has its own cast of five (Config.Casts: realistic civilisations on Earth, fantasy peoples on Eldmoor,
-- sci-fi peoples on Skyshards), set per nation in the map data, so picking a nation picks its race. Neutral garrisons
-- and Rebels have none. Each race recruits a roster of five troops, one per role (Config.Races[race].roster,
-- Sim.Troops), and has one passive, one of a few kinds (PASSIVES, numbers in Config.Races):
--   Gold      more gold income (gross: provinces and capital, before upkeep)
--   Manpower  more manpower income
--   Forest    cross forest at plains speed; more combat strength in battles in forest provinces
--   Hills     more combat strength when defending in hills; cheaper forts
--   Upkeep    armies cost less upkeep
--   Swift     armies march faster
--   Attack    more combat strength when attacking
-- Combat bonuses add to the battle modifier like the terrain, fort and catch-up bonuses, for the whole side: an ally
-- fighting beside an Elven army in a forest shares the bonus (as with the underdog bonus).

local Config = require("../Config")
local Types = require("../Types")

type MatchState = Types.MatchState
type Race = Types.Race

export type Passive = "Gold" | "Manpower" | "Forest" | "Hills" | "Upkeep" | "Swift" | "Attack"

-- One race's entry in Config.Races: its passive's numbers are only the ones its kind uses.
export type RaceDef = {
	name: string,
	passive: Passive,
	roster: { [string]: string }, -- role -> troop: line, ranged, fast, elite, special (Sim.Troops.ROLES)
	goldBonus: number?,
	manpowerBonus: number?,
	forestBonus: number?,
	hillsDefenceBonus: number?,
	fortCostMultiplier: number?,
	upkeepMultiplier: number?,
	moveMultiplier: number?,
	attackBonus: number?,
}

-- A map's cast in Config.Casts: its five races.
export type Cast = { races: { Race } }

local DEFS = Config.Races :: { [string]: RaceDef }
local CASTS = Config.Casts :: { [string]: Cast }

local Races = {}

-- The passive kinds, in a fixed order (docs, tests).
Races.PASSIVES = { "Gold", "Manpower", "Forest", "Hills", "Upkeep", "Swift", "Attack" } :: { Passive }

-- Every race, map by map in Config.Casts' order (earth, eldmoor, skyshards), each map's races in its cast's order.
Races.LIST = {} :: { Race }
for _, mapId in { "earth", "eldmoor", "skyshards" } do
	for _, race in CASTS[mapId].races do
		if table.find(Races.LIST, race) == nil then
			table.insert(Races.LIST, race)
		end
	end
end
local uncast: { Race } = {} -- any race no cast lists (sorted, so the order never depends on the table)
for race in DEFS do
	if table.find(Races.LIST, race) == nil then
		table.insert(uncast, race)
	end
end
table.sort(uncast)
for _, race in uncast do
	table.insert(Races.LIST, race)
end

function Races.isRace(value: unknown): boolean
	return type(value) == "string" and DEFS[value :: string] ~= nil
end

-- A race's entry (nil for an unknown id or no race).
function Races.def(race: Race?): RaceDef?
	return if race then DEFS[race] else nil
end

-- What the UI calls a race ("" without one).
function Races.name(race: Race?): string
	local def = Races.def(race)
	return if def then def.name else ""
end

-- A race's passive kind (nil without a race).
function Races.passive(race: Race?): Passive?
	local def = Races.def(race)
	return if def then def.passive else nil
end

-- A map's cast: its five races in order (empty for an unknown map).
function Races.forMap(mapId: string): { Race }
	local cast = CASTS[mapId]
	return if cast then table.clone(cast.races) else {}
end

-- The map whose cast a race belongs to (nil if none).
function Races.mapOf(race: Race): string?
	for mapId, cast in CASTS do
		if table.find(cast.races, race) then
			return mapId
		end
	end
	return nil
end

-- A nation's race; nil for neutral armies (owner 0) and nations not in the match.
function Races.of(state: MatchState, nationId: number): Race?
	local nation = state.nations[nationId]
	return if nation then nation.race else nil
end

-- Multiplier on a nation's gross gold income (Gold).
function Races.goldMultiplier(race: Race?): number
	local def = Races.def(race)
	return if def and def.passive == "Gold" then 1 + (def.goldBonus or 0) else 1
end

-- Multiplier on a nation's manpower income (Manpower).
function Races.manpowerMultiplier(race: Race?): number
	local def = Races.def(race)
	return if def and def.passive == "Manpower" then 1 + (def.manpowerBonus or 0) else 1
end

-- Multiplier on what a nation's armies cost a month (Upkeep).
function Races.upkeepMultiplier(race: Race?): number
	local def = Races.def(race)
	return if def and def.passive == "Upkeep" then def.upkeepMultiplier or 1 else 1
end

-- What a building costs this race (Hills: forts for less).
function Races.buildingCost(race: Race?, building: Types.Building, cost: number): number
	local def = Races.def(race)
	if def and def.passive == "Hills" and building == "Fort" then
		return cost * (def.fortCostMultiplier or 1)
	end
	return cost
end

-- The terrain an army of this race marches over as (Forest: forest at plains speed).
function Races.moveTerrain(race: Race?, terrain: Types.Terrain): Types.Terrain
	if terrain == "Forest" and Races.passive(race) == "Forest" then
		return "Plains"
	end
	return terrain
end

-- Ticks an army of this race takes to step into a province of this terrain (Swift: fewer, at least 1), from the
-- ticks its troops need there (Sim.Troops.moveTicks on Races.moveTerrain's terrain).
function Races.moveTicks(race: Race?, ticks: number): number
	local def = Races.def(race)
	if def and def.passive == "Swift" then
		return math.max(1, math.floor(ticks * (def.moveMultiplier or 1) + 0.5))
	end
	return ticks
end

local function pct(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- A race's passive in one short line for the UI ("+10% gold", "+25% defending hills, forts -50%"), from its numbers
-- in Config.Races, so the text follows a balance change. "" without a race.
function Races.bonusText(race: Race?): string
	local def = Races.def(race)
	if def == nil then
		return ""
	end
	local kind = def.passive
	if kind == "Gold" then
		return "+" .. pct(def.goldBonus or 0) .. " gold"
	elseif kind == "Manpower" then
		return "+" .. pct(def.manpowerBonus or 0) .. " manpower"
	elseif kind == "Forest" then
		return "Fast in forests, +" .. pct(def.forestBonus or 0) .. " in forest battles"
	elseif kind == "Hills" then
		return "+"
			.. pct(def.hillsDefenceBonus or 0)
			.. " defending hills, forts -"
			.. pct(1 - (def.fortCostMultiplier or 1))
	elseif kind == "Upkeep" then
		return "Armies cost " .. pct(1 - (def.upkeepMultiplier or 1)) .. " less upkeep"
	elseif kind == "Swift" then
		return "Armies march " .. pct(1 - (def.moveMultiplier or 1)) .. " faster"
	elseif kind == "Attack" then
		return "+" .. pct(def.attackBonus or 0) .. " attacking"
	end
	return ""
end

-- Extra combat strength for one side of a battle in this province. `owners` are the nations fighting on that side.
-- Each passive counts once for the side, however many of its nations have it (the largest number wins).
function Races.battleBonus(state: MatchState, province: Types.Province, owners: { number }, defending: boolean): number
	local forest, hills, attack = 0, 0, 0
	for _, id in owners do
		local def = Races.def(Races.of(state, id))
		if def then
			if def.passive == "Forest" then
				forest = math.max(forest, def.forestBonus or 0)
			elseif def.passive == "Hills" then
				hills = math.max(hills, def.hillsDefenceBonus or 0)
			elseif def.passive == "Attack" then
				attack = math.max(attack, def.attackBonus or 0)
			end
		end
	end
	local bonus = 0
	if province.terrain == "Forest" then
		bonus += forest
	end
	if defending and province.terrain == "Hills" then
		bonus += hills
	end
	if not defending then
		bonus += attack
	end
	return bonus
end

return Races
