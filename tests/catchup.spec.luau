--!strict
-- Catch-up rules: overextension, underdog and coalition (docs/DESIGN.md "Catch-up").
local Army = require("../src/shared/Sim/Army")
local Battle = require("../src/shared/Sim/Battle")
local CatchUp = require("../src/shared/Sim/CatchUp")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")
local Types = require("../src/shared/Types")

Config.Battle.RandomSpread = 0 -- deterministic battles in this file

local map = Maps.get("skyshards")

-- Land provinces in id order, so tests can hand out exact province counts.
local function landIds(state: Types.MatchState): { number }
	local ids = {}
	for id, p in state.provinces do
		if p.terrain ~= "Mountain" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

-- A match where nation i owns counts[i] provinces (the rest is neutral) and there are no armies.
local function withCounts(counts: { number }): (Types.MatchState, { number })
	local state = Match.new(map)
	state.armies = {}
	local ids = landIds(state)
	for _, p in state.provinces do
		p.owner = nil
	end
	local next = 1
	for nation, n in counts do
		for _ = 1, n do
			state.provinces[ids[next]].owner = nation
			next += 1
		end
	end
	return state, ids
end

-- Shares count ownable provinces only (mountains can't be owned).
local function total(state: Types.MatchState): number
	return CatchUp.ownableCount(state.provinces)
end

local function count(t: { [number]: boolean }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- Overextension ---------------------------------------------------------------------------------

T.test("overextension: -5% gold per full 5 provinces above 20", function()
	T.equal(CatchUp.overextension(0), 1)
	T.equal(CatchUp.overextension(20), 1)
	T.equal(CatchUp.overextension(21), 1, "21-24 provinces are not a full step yet")
	T.equal(CatchUp.overextension(24), 1)
	T.near(CatchUp.overextension(25), 0.95, 1e-9)
	T.near(CatchUp.overextension(29), 0.95, 1e-9)
	T.near(CatchUp.overextension(30), 0.90, 1e-9)
	T.near(CatchUp.overextension(60), 0.60, 1e-9)
	T.equal(CatchUp.overextension(1000), 0, "never below zero")
end)

T.test("overextension cuts gross gold income only, not manpower or upkeep", function()
	local state = withCounts({ 25 })
	state.provinces[state.nations[1].capital].owner = 1
	Army.spawn(state, 1, state.nations[1].capital, 4000)
	local income = Economy.monthlyIncome(state, 1)
	local gold, manpower = Config.Economy.CapitalGold, 0
	for _, p in state.provinces do
		if p.owner == 1 then
			local g, m = Economy.provinceYield(p)
			gold += g
			manpower += m
		end
	end
	local n = Match.provinceCount(state, 1)
	T.expect(n >= 25 and n < 30, "25-29 provinces")
	T.near(income.gold, gold * 0.95, 1e-9)
	T.equal(income.manpower, manpower)
	T.equal(income.upkeep, 4 * Config.Army.UpkeepPerRegiment)
end)

T.test("a starting nation is not overextended", function()
	local state = Match.new(map)
	T.equal(CatchUp.goldMultiplier(state, 1), 1)
end)

-- Underdog --------------------------------------------------------------------------------------

T.test("underdog: nobody while every nation is level", function()
	T.equal(count(CatchUp.underdogs(Match.new(map))), 0)
	T.equal(count(CatchUp.underdogsFrom({ 4, 4, 4, 4 })), 0)
end)

T.test("underdog: the 3 nations with the fewest provinces", function()
	local u = CatchUp.underdogsFrom({ 9, 2, 8, 3, 7, 1, 6, 5, 10, 11 })
	T.equal(count(u), 3)
	T.expect(u[6] and u[2] and u[4], "1, 2 and 3 provinces")
end)

T.test("underdog: a tie at the cut-off leaves everyone in the tie out", function()
	-- 1, 2, then two nations on 3: only 1 and 2 qualify
	local u = CatchUp.underdogsFrom({ 1, 2, 3, 3, 8, 8, 8, 8, 8, 8 })
	T.equal(count(u), 2)
	T.expect(u[1] and u[2], "1 and 2 provinces")
	-- three nations tied at the bottom all qualify
	u = CatchUp.underdogsFrom({ 2, 2, 2, 8, 8, 8, 8, 8, 8, 8 })
	T.equal(count(u), 3)
	-- four tied at the bottom: nobody
	T.equal(count(CatchUp.underdogsFrom({ 2, 2, 2, 2, 8, 8, 8, 8, 8, 8 })), 0)
end)

T.test("underdog: never the largest nation, even with 3 or fewer living", function()
	local u = CatchUp.underdogsFrom({ 5, 10, 20 })
	T.equal(count(u), 2)
	T.expect(u[1] and u[2] and not u[3])
	T.equal(count(CatchUp.underdogsFrom({ 7 })), 0)
end)

T.test("underdog: eliminated nations are neither counted nor underdogs", function()
	local state = withCounts({ 8, 8, 8, 8, 8, 8, 8, 1, 0, 0 })
	state.nations[9].eliminated = true
	state.nations[10].eliminated = true
	local u = CatchUp.underdogs(state)
	T.equal(count(u), 1, "8 and 7 x eight provinces: only the 1-province nation")
	T.expect(u[8])
	-- with 9 and 10 alive (0 provinces) they and the 1-province nation are the three
	state.nations[9].eliminated = false
	state.nations[10].eliminated = false
	u = CatchUp.underdogs(state)
	T.equal(count(u), 3)
	T.expect(u[8] and u[9] and u[10])
end)

T.test("underdog: +20% when defending, nothing when attacking", function()
	local state = withCounts({ 10, 10, 10, 10, 10, 10, 10, 2, 10, 10 })
	T.near(CatchUp.battleBonus(state, { 8 }, { 1 }, true), Config.Battle.UnderdogBonus, 1e-9)
	T.equal(CatchUp.battleBonus(state, { 8 }, { 1 }, false), 0)
	T.equal(CatchUp.battleBonus(state, { 1 }, { 8 }, true), 0)
	-- an ally helping the underdog defend shares the bonus
	T.near(CatchUp.battleBonus(state, { 1, 8 }, { 2 }, true), Config.Battle.UnderdogBonus, 1e-9)
end)

T.test("underdog bonus reaches Battle.modifier and adds to terrain", function()
	local state, ids = withCounts({ 10, 10, 10, 10, 10, 10, 10, 2, 10, 10 })
	local home = ids[71] -- one of nation 8's provinces
	T.equal(state.provinces[home].owner, 8)
	state.provinces[home].terrain = "Forest"
	state.provinces[home].building = "None"
	local def = Army.spawn(state, 8, home, 1000)
	local att = Army.spawn(state, 1, home, 1000)
	local sides = { defenderOwner = 8, defenders = { def }, attackers = { att } }
	T.near(
		Battle.modifier(state, home, sides, true, 0),
		1 + Config.Battle.TerrainDefenceBonus + Config.Battle.UnderdogBonus,
		1e-9
	)
	T.near(Battle.modifier(state, home, sides, false, 0), 1, 1e-9)
end)

-- Coalition -------------------------------------------------------------------------------------

T.test("coalition: the crown needs exactly CoalitionThreshold of the ownable provinces", function()
	local all = total(Match.new(map))
	local need = math.ceil(Config.Diplomacy.CoalitionThreshold * all)
	local below = withCounts({ need - 1, 5 })
	T.equal(count(CatchUp.leaders(below)), 0, "one province short")
	local at = withCounts({ need, 5 })
	local leaders = CatchUp.leaders(at)
	T.equal(count(leaders), 1)
	T.expect(leaders[1])
	local q = math.ceil(Config.Diplomacy.CoalitionThreshold * 100)
	T.equal(count(CatchUp.leadersFrom({ q, q, 50 }, 100)), 3, "everyone at the threshold or above wears a crown")
	T.equal(count(CatchUp.leadersFrom({ q - 1 }, 100)), 0)
	T.equal(count(CatchUp.leadersFrom({}, 0)), 0)
end)

T.test("shares ignore mountains: the crown threshold counts ownable provinces only", function()
	local state = Match.new(map)
	local all, mountains = 0, 0
	for _, p in state.provinces do
		all += 1
		if p.terrain == "Mountain" then
			mountains += 1
		end
	end
	T.expect(mountains > 0, "the test map has mountains")
	local _, counted = CatchUp.counts(state)
	T.equal(counted, all - mountains)
	-- exactly the threshold share of the ownable land wears the crown, although it is less of all provinces
	local need = math.ceil(Config.Diplomacy.CoalitionThreshold * (all - mountains))
	T.expect(need < Config.Diplomacy.CoalitionThreshold * all)
	T.equal(count(CatchUp.leaders((withCounts({ need, 5 })))), 1)
end)

T.test("coalition: +10% for anyone fighting the leader, attacking or defending", function()
	local all = total(Match.new(map))
	local state = withCounts({ math.ceil(Config.Diplomacy.CoalitionThreshold * all), 6, 6, 6, 6, 6, 6, 6, 6, 6 })
	local b = Config.Battle.CoalitionBonus
	T.near(CatchUp.battleBonus(state, { 2 }, { 1 }, false), b, 1e-9)
	T.near(CatchUp.battleBonus(state, { 2 }, { 1 }, true), b, 1e-9)
	T.near(CatchUp.battleBonus(state, { 2, 3 }, { 1, 4 }, false), b, 1e-9, "counted once per side")
	T.equal(CatchUp.battleBonus(state, { 1 }, { 2 }, false), 0, "the leader gets nothing")
	T.equal(CatchUp.battleBonus(state, { 0 }, { 1 }, true), 0, "neutral garrisons are not nations")
end)

T.test("coalition: two crowned nations fighting each other both get it", function()
	local all = total(Match.new(map))
	local q = math.ceil(Config.Diplomacy.CoalitionThreshold * all)
	local state = withCounts({ q, q, 3, 3 })
	local b = Config.Battle.CoalitionBonus
	T.near(CatchUp.battleBonus(state, { 1 }, { 2 }, false), b, 1e-9)
	T.near(CatchUp.battleBonus(state, { 2 }, { 1 }, true), b, 1e-9)
end)

T.test("coalition: eliminated nations never wear the crown", function()
	local all = total(Match.new(map))
	local state = withCounts({ math.ceil(Config.Diplomacy.CoalitionThreshold * all), 5 })
	state.nations[1].eliminated = true
	T.equal(count(CatchUp.leaders(state)), 0)
end)

T.test("a whole battle: the coalition bonus turns an even fight", function()
	local all = total(Match.new(map))
	local state, ids = withCounts({ math.ceil(Config.Diplomacy.CoalitionThreshold * all), 6, 6, 6, 6, 6, 6, 6, 6, 6 })
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.wars[1] = { id = 1, attackers = { 2 }, defenders = { 1 }, startedAt = state.tick }
	T.expect(Diplomacy.atWar(state, 2, 1))
	local field = ids[1] -- one of nation 1's provinces, made plain plains
	state.provinces[field].terrain = "Plains"
	state.provinces[field].building = "None"
	local def = Army.spawn(state, 1, field, 3000)
	local att = Army.spawn(state, 2, field, 3000)
	local rng = Rng.new(1)
	for _ = 1, Config.Battle.Rounds do
		Battle.step(state, rng)
	end
	-- equal men: without the bonus the defender wins ties; with +10% the attacker kills more
	T.expect(state.armies[att.id] ~= nil, "attacker survives")
	T.equal(state.armies[att.id].location, field, "attacker holds the field")
	local d = state.armies[def.id]
	T.expect(d == nil or d.retreating == true, "the leader's army retreats")
end)

T.finish()
