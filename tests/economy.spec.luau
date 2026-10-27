--!strict
local Army = require("../src/shared/Sim/Army")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local T = require("./TestKit")

local function fresh()
	return Match.new(Maps.get("skyshards"))
end

T.test("a starting nation earns 17 development + capital per month", function()
	local state = fresh()
	local income = Economy.monthlyIncome(state, 1)
	T.equal(income.gold, 17 * Config.Economy.GoldPerDevelopment + Config.Economy.CapitalGold)
	T.equal(income.manpower, 17 * Config.Economy.ManpowerPerDevelopment)
	T.equal(income.upkeep, 0)
end)

T.test("a farm adds 50% gold and barracks 50% manpower in that province", function()
	local state = fresh()
	local p = state.provinces[state.nations[1].capital]
	local g0, m0 = Economy.provinceYield(p)
	p.building = "Farm"
	local g1, m1 = Economy.provinceYield(p)
	T.equal(g1, g0 * 1.5)
	T.equal(m1, m0)
	p.building = "Barracks"
	local g2, m2 = Economy.provinceYield(p)
	T.equal(g2, g0)
	T.equal(m2, m0 * 1.5)
end)

T.test("losing the capital loses the capital bonus", function()
	local state = fresh()
	local before = Economy.monthlyIncome(state, 1).gold
	local capital = state.provinces[state.nations[1].capital]
	capital.owner = 2
	local after = Economy.monthlyIncome(state, 1).gold
	T.equal(before - after, capital.development + Config.Economy.CapitalGold)
end)

T.test("regiments cost upkeep", function()
	local state = fresh()
	Army.spawn(state, 1, state.nations[1].capital, 4000)
	T.equal(Economy.monthlyIncome(state, 1).upkeep, 4 * Config.Army.UpkeepPerRegiment)
	T.equal(Economy.monthlyIncome(state, 2).upkeep, 0)
end)

T.test("payMonth pays every living nation and skips the eliminated", function()
	local state = fresh()
	state.nations[3].eliminated = true
	Economy.payMonth(state)
	T.equal(state.nations[1].gold, Config.StartGold + 17 + Config.Economy.CapitalGold)
	T.equal(state.nations[1].manpower, Config.StartManpower + 1700)
	T.equal(state.nations[3].gold, Config.StartGold)
end)

T.test("costs follow the design doc", function()
	T.equal(Economy.developCost(1), 30)
	T.equal(Economy.developCost(4), 120)
	T.equal(Economy.buildingCost("Farm"), 50)
	T.equal(Economy.buildingCost("Barracks"), 40)
	T.equal(Economy.buildingCost("Fort"), 60)
	T.equal(Economy.buildingCost("None"), nil)
	local g, m = Economy.recruitCost(3)
	T.equal(g, 30)
	T.equal(m, 3000)
end)

T.finish()
