--!strict
-- Income, upkeep and costs (docs/DESIGN.md "Economy"). Paid once per month.

local CatchUp = require("./CatchUp")
local Config = require("../Config")
local Primordial = require("./Primordial")
local Types = require("../Types")

type MatchState = Types.MatchState
type Province = Types.Province

export type Income = {
	gold: number, -- gross gold from provinces and capital, after overextension
	manpower: number,
	upkeep: number, -- gold paid for regiments
}

local Economy = {}

function Economy.developCost(level: number): number
	return Config.Economy.DevelopCostPerLevel * level
end

-- nil for "None" (nothing to build).
function Economy.buildingCost(building: Types.Building): number?
	if building == "Farm" then
		return Config.Buildings.Farm.cost
	elseif building == "Barracks" then
		return Config.Buildings.Barracks.cost
	elseif building == "Fort" then
		return Config.Buildings.Fort.cost
	end
	return nil
end

function Economy.recruitCost(regiments: number): (number, number)
	return regiments * Config.Army.RegimentGold, regiments * Config.Army.RegimentManpower
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

function Economy.regiments(state: MatchState, nationId: number): number
	local men = 0
	for _, army in state.armies do
		if army.owner == nationId then
			men += army.men
		end
	end
	return men / Config.Army.MenPerRegiment
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
	manpower *= Primordial.manpowerMultiplier(state, nationId) -- Plague
	local nation = state.nations[nationId]
	local capital = nation and state.provinces[nation.capital]
	if capital and capital.owner == nationId then
		gold += Config.Economy.CapitalGold
	end
	gold *= CatchUp.goldMultiplier(state, nationId) -- overextension
	return {
		gold = gold,
		manpower = manpower,
		upkeep = Economy.regiments(state, nationId) * Config.Army.UpkeepPerRegiment,
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
