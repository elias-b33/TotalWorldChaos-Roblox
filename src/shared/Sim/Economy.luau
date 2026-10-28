--!strict
-- Income, upkeep and costs (docs/DESIGN.md "Economy"). Paid once per month. Race passives change a few numbers
-- (Sim.Races, Config.Races): Gold races earn more gold (gross), Manpower races more manpower, Upkeep races pay less
-- upkeep, Hills races less for a fort; every troop type has its own price and upkeep (Sim.Troops).

local CatchUp = require("./CatchUp")
local Config = require("../Config")
local Primordial = require("./Primordial")
local Races = require("./Races")
local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState
type Province = Types.Province

export type Income = {
	gold: number, -- gross gold from provinces and capital, after overextension and the race bonus
	manpower: number,
	upkeep: number, -- gold paid for the armies in the field
}

local Economy = {}

function Economy.developCost(level: number): number
	return Config.Economy.DevelopCostPerLevel * level
end

-- nil for "None" (nothing to build). `race` (optional): the builder's race (a Hills race pays less for a fort).
function Economy.buildingCost(building: Types.Building, race: Types.Race?): number?
	local cost: number? = nil
	if building == "Farm" then
		cost = Config.Buildings.Farm.cost
	elseif building == "Barracks" then
		cost = Config.Buildings.Barracks.cost
	elseif building == "Fort" then
		cost = Config.Buildings.Fort.cost
	end
	return if cost then Races.buildingCost(race, building, cost) else nil
end

-- Gold and manpower for `regiments` regiments of a troop (infantry when none is given).
function Economy.recruitCost(regiments: number, troop: Types.Troop?): (number, number)
	return Troops.cost(troop or Troops.BASE, regiments)
end

-- What one province yields per month, before nation-wide modifiers.
function Economy.provinceYield(province: Province): (number, number)
	local gold = province.development * Config.Economy.GoldPerDevelopment
	local manpower = province.development * Config.Economy.ManpowerPerDevelopment
	if province.building == "Farm" then
		gold *= 1 + Config.Buildings.Farm.goldBonus
	elseif province.building == "Barracks" then
		manpower *= 1 + Config.Buildings.Barracks.manpowerBonus
	end
	return gold, manpower
end

-- A nation's men in the field, in regiments (1,000 men of any troop type).
function Economy.regiments(state: MatchState, nationId: number): number
	local men = 0
	for _, army in state.armies do
		if army.owner == nationId then
			men += army.men
		end
	end
	return men / Config.Army.MenPerRegiment
end

-- Gold per month a nation pays for its armies: every troop type at its own upkeep, less for an Upkeep race.
function Economy.upkeep(state: MatchState, nationId: number): number
	local gold = 0
	for _, army in state.armies do
		if army.owner == nationId then
			gold += Troops.upkeep(army.troops)
		end
	end
	return gold * Races.upkeepMultiplier(Races.of(state, nationId))
end

function Economy.monthlyIncome(state: MatchState, nationId: number): Income
	local gold, manpower = 0, 0
	for _, province in state.provinces do
		if province.owner == nationId then
			local g, m = Economy.provinceYield(province)
			gold += g * Primordial.goldMultiplier(state, province) -- Blessing
			manpower += m
		end
	end
	local race = Races.of(state, nationId)
	manpower *= Primordial.manpowerMultiplier(state, nationId) * Races.manpowerMultiplier(race) -- Plague, Manpower
	local nation = state.nations[nationId]
	local capital = nation and state.provinces[nation.capital]
	if capital and capital.owner == nationId then
		gold += Config.Economy.CapitalGold
	end
	gold *= CatchUp.goldMultiplier(state, nationId) * Races.goldMultiplier(race) -- overextension, Gold
	return {
		gold = gold,
		manpower = manpower,
		upkeep = Economy.upkeep(state, nationId),
	}
end

-- Pay every living nation. Gold may go below zero (debt): nothing can be bought until it is positive again.
function Economy.payMonth(state: MatchState)
	for id, nation in state.nations do
		if not nation.eliminated then
			local income = Economy.monthlyIncome(state, id)
			nation.gold += income.gold - income.upkeep
			nation.manpower += income.manpower
		end
	end
end

return Economy
