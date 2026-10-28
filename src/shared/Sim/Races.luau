--!strict
-- Races (docs/DESIGN.md "Races"): WorldBox's four classic races. Every nation has one, set per nation in the map
-- data, so picking a nation picks its race; neutral garrisons and Rebels have none. One passive each (numbers in
-- Config.Races), plus one elite troop each (Config.Troops, Sim.Troops):
--   Humans   more gold income (gross: provinces and capital, before upkeep)
--   Elves    cross forest at plains speed; more combat strength in battles in forest provinces
--   Orcs     more manpower income
--   Dwarves  more combat strength when defending in hills; cheaper forts
-- Combat bonuses add to the battle modifier like the terrain, fort and catch-up bonuses, for the whole side: an ally
-- fighting beside an Elven army in a forest shares the bonus (as with the underdog bonus).

local Config = require("../Config")
local Types = require("../Types")

type MatchState = Types.MatchState
type Race = Types.Race

local Races = {}

-- Every race, in a fixed order (docs, the tournament's tables).
Races.LIST = { "Humans", "Elves", "Orcs", "Dwarves" } :: { Race }

function Races.isRace(value: unknown): boolean
	return type(value) == "string" and table.find(Races.LIST, value :: any) ~= nil
end

-- A nation's race; nil for neutral armies (owner 0) and nations not in the match.
function Races.of(state: MatchState, nationId: number): Race?
	local nation = state.nations[nationId]
	return if nation then nation.race else nil
end

-- Multiplier on a nation's gross gold income.
function Races.goldMultiplier(race: Race?): number
	return if race == "Humans" then 1 + Config.Races.Humans.goldBonus else 1
end

-- Multiplier on a nation's manpower income.
function Races.manpowerMultiplier(race: Race?): number
	return if race == "Orcs" then 1 + Config.Races.Orcs.manpowerBonus else 1
end

-- What a building costs this race (Dwarves build forts for less).
function Races.buildingCost(race: Race?, building: Types.Building, cost: number): number
	if race == "Dwarves" and building == "Fort" then
		return cost * Config.Races.Dwarves.fortCostMultiplier
	end
	return cost
end

-- The terrain an army of this race marches over as: Elves cross forest at plains speed.
function Races.moveTerrain(race: Race?, terrain: Types.Terrain): Types.Terrain
	if race == "Elves" and terrain == "Forest" then
		return "Plains"
	end
	return terrain
end

-- Extra combat strength for one side of a battle in this province. `owners` are the nations fighting on that side.
function Races.battleBonus(state: MatchState, province: Types.Province, owners: { number }, defending: boolean): number
	local elves, dwarves = false, false
	for _, id in owners do
		local race = Races.of(state, id)
		elves = elves or race == "Elves"
		dwarves = dwarves or race == "Dwarves"
	end
	local bonus = 0
	if elves and province.terrain == "Forest" then
		bonus += Config.Races.Elves.forestBonus
	end
	if dwarves and defending and province.terrain == "Hills" then
		bonus += Config.Races.Dwarves.hillsDefenceBonus
	end
	return bonus
end

return Races
