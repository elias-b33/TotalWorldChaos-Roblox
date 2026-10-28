--!strict
-- Races and troops (docs/DESIGN.md "Races", "Troops"): recruiting by troop type and race, costs and upkeep, the
-- race passives, battle strength by troop and side, losses split by type, merges, speed, Ironguard sieges, the
-- Meteor, and what the network carries. Numbers come from Config, so a balance change doesn't break these.
local Army = require("../src/shared/Sim/Army")
local Battle = require("../src/shared/Sim/Battle")
local Bot = require("../src/shared/Sim/Bot")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Movement = require("../src/shared/Sim/Movement")
local Primordial = require("../src/shared/Sim/Primordial")
local Progression = require("../src/shared/Sim/Progression")
local Races = require("../src/shared/Sim/Races")
local Rng = require("../src/shared/Sim/Rng")
local Siege = require("../src/shared/Sim/Siege")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Troops = require("../src/shared/Sim/Troops")
local Types = require("../src/shared/Types")

type MatchState = Types.MatchState

Config.Battle.RandomSpread = 0 -- deterministic battles in this file

local map = Maps.get("skyshards")
local byName: { [string]: number } = {}
for _, p in map.provinces do
	byName[p.name] = p.id
end
local function id(name: string): number
	return assert(byName[name], "no province " .. name)
end

local AURORA, ZEPHYR = 1, 2
local PLAINS, FOREST, HILLS = id("Cinder Reach"), id("Aurora Grove"), id("Aurora Windward")
local INF = Config.Troops.Infantry

local function fresh(): MatchState
	return Match.new(map)
end

local function run(state: MatchState, ticks: number)
	local rng = Rng.new(1)
	for _ = 1, ticks do
		Tick.advance(state, rng)
	end
end

local function clear(state: MatchState, provinceId: number)
	for armyId, a in state.armies do
		if a.location == provinceId then
			state.armies[armyId] = nil
		end
	end
end

-- Aurora and Zephyr at war, Zephyr owning the province.
local function war(state: MatchState, provinceId: number)
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.provinces[provinceId].owner = ZEPHYR
	state.wars[1] = { id = 1, attackers = { AURORA }, defenders = { ZEPHYR }, startedAt = state.tick }
	clear(state, provinceId)
end

local function recruit(state: MatchState, nation: number, troop: Types.Troop, regiments: number?): (boolean, string?)
	local command: Types.Command = {
		kind = "Recruit",
		province = state.nations[nation].capital,
		regiments = regiments or 1,
		troop = troop,
	}
	return Commands.apply(state, nation, command)
end

local function sumOf(troops: Types.Composition): number
	local n = 0
	for _, men in troops do
		n += men
	end
	return n
end

-- Recruiting ----------------------------------------------------------------------------------------------

T.test("every nation has a race, and each map mixes all four", function()
	for _, mapId in Maps.ids do
		local state = Match.new(Maps.get(mapId))
		local seen: { [string]: number } = {}
		for _, nation in state.nations do
			T.expect(Races.isRace(nation.race), nation.name .. " has no race")
			seen[nation.race] = (seen[nation.race] or 0) + 1
		end
		for _, race in Races.LIST do
			T.expect((seen[race] or 0) >= 2, mapId .. " has " .. (seen[race] or 0) .. " " .. race)
		end
	end
end)

T.test("a nation recruits infantry, archers, cavalry and its own elite, never another race's", function()
	local state = fresh()
	local nation = state.nations[AURORA]
	for _, race in Races.LIST do
		nation.race = race
		local elite = Troops.elite(race)
		T.expect(elite ~= nil and Troops.stats(elite :: Types.Troop).race == race, race .. " has an elite")
		T.equal(#Troops.available(race), 4)
		for _, troop in Troops.LIST do
			nation.gold, nation.manpower = 10000, 100000
			local ok, err = recruit(state, AURORA, troop)
			local mayRecruit = troop == "Infantry" or troop == "Archers" or troop == "Cavalry" or troop == elite
			T.equal(ok, mayRecruit, race .. " recruiting " .. troop)
			if not mayRecruit then
				T.equal(err, "WrongRace")
				T.equal(nation.gold, 10000, "a refused recruit costs nothing")
			end
		end
	end
	local ok, err = Commands.apply(
		state,
		AURORA,
		{ kind = "Recruit", province = nation.capital, regiments = 1, troop = "Dragons" :: any }
	)
	T.expect(not ok)
	T.equal(err, "BadTroop")
end)

T.test("each troop costs its own gold and manpower, and recruits join the army standing there by type", function()
	local state = fresh()
	local nation = state.nations[AURORA]
	nation.race = "Humans"
	nation.gold, nation.manpower = 1000, 20000
	T.expect((recruit(state, AURORA, "Infantry", 2)))
	T.expect((recruit(state, AURORA, "Archers", 1)))
	T.expect((recruit(state, AURORA, "Knights", 1)))
	local t = Config.Troops
	T.equal(nation.gold, 1000 - 2 * t.Infantry.gold - t.Archers.gold - t.Knights.gold)
	T.equal(nation.manpower, 20000 - 2 * t.Infantry.manpower - t.Archers.manpower - t.Knights.manpower)
	local army = assert(Army.idleAt(state, AURORA, nation.capital))
	T.equal(army.troops.Infantry, 2000)
	T.equal(army.troops.Archers, 1000)
	T.equal(army.troops.Knights, 1000)
	T.equal(army.men, 4000)
	local g, m = Economy.recruitCost(3, "Berserkers")
	T.equal(g, 3 * t.Berserkers.gold)
	T.equal(m, 3 * t.Berserkers.manpower)
	T.expect(t.Berserkers.manpower < t.Infantry.manpower, "berserkers need less manpower")
end)

T.test("upkeep: every troop type at its own price per 1,000 men", function()
	local state = fresh()
	local capital = state.nations[AURORA].capital
	Army.spawn(state, AURORA, capital, 2000, "Archers")
	Army.spawn(state, AURORA, id("Aurora Fields"), 1500, "Cavalry")
	local t = Config.Troops
	T.near(Economy.monthlyIncome(state, AURORA).upkeep, 2 * t.Archers.upkeep + 1.5 * t.Cavalry.upkeep, 1e-9)
	T.near(Troops.upkeep({ Infantry = 2400 }), 2.4 * INF.upkeep, 1e-9)
end)

-- Race passives -----------------------------------------------------------------------------------------

T.test("Humans earn more gold (their bonus), gross and before upkeep", function()
	local state = fresh()
	Army.spawn(state, AURORA, state.nations[AURORA].capital, 3000)
	state.nations[AURORA].race = "Orcs"
	local plain = Economy.monthlyIncome(state, AURORA)
	state.nations[AURORA].race = "Humans"
	local human = Economy.monthlyIncome(state, AURORA)
	T.near(human.gold, plain.gold * (1 + Config.Races.Humans.goldBonus), 1e-9)
	T.equal(human.upkeep, plain.upkeep, "the bonus is on income, not upkeep")
end)

T.test("Orcs earn more manpower (their bonus)", function()
	local state = fresh()
	state.nations[AURORA].race = "Humans"
	local plain = Economy.monthlyIncome(state, AURORA)
	state.nations[AURORA].race = "Orcs"
	local orc = Economy.monthlyIncome(state, AURORA)
	T.near(orc.manpower, plain.manpower * (1 + Config.Races.Orcs.manpowerBonus), 1e-9)
	T.near(orc.gold, plain.gold / (1 + Config.Races.Humans.goldBonus), 1e-9, "and no gold bonus")
end)

T.test("Dwarves build forts for half, everything else at full price", function()
	local state = fresh()
	local nation = state.nations[AURORA]
	nation.race = "Dwarves"
	nation.gold = 500
	local fort = Config.Buildings.Fort.cost * Config.Races.Dwarves.fortCostMultiplier
	T.equal(Economy.buildingCost("Fort", "Dwarves"), fort)
	T.equal(Economy.buildingCost("Fort", "Humans"), Config.Buildings.Fort.cost)
	T.equal(Economy.buildingCost("Farm", "Dwarves"), Config.Buildings.Farm.cost)
	T.expect((Commands.apply(state, AURORA, { kind = "Build", province = nation.capital, building = "Fort" })))
	T.equal(nation.gold, 500 - fort)
end)

local function modifiers(state: MatchState, provinceId: number): (number, number)
	local defender = Army.spawn(state, ZEPHYR, provinceId, 1000)
	local attacker = Army.spawn(state, AURORA, provinceId, 1000)
	local sides = assert(Battle.sides(state, provinceId, { defender, attacker }))
	T.equal(sides.defenderOwner, ZEPHYR)
	return Battle.modifier(state, provinceId, sides, true, 0), Battle.modifier(state, provinceId, sides, false, 0)
end

T.test("Dwarves fight harder defending in hills, not attacking, not elsewhere", function()
	local terrain = Config.Battle.TerrainDefenceBonus
	local bonus = Config.Races.Dwarves.hillsDefenceBonus
	local state = fresh()
	war(state, HILLS)
	state.nations[ZEPHYR].race, state.nations[AURORA].race = "Dwarves", "Dwarves"
	local def, att = modifiers(state, HILLS)
	T.near(def, 1 + terrain + bonus, 1e-9, "defending Dwarves in hills")
	T.near(att, 1, 1e-9, "attacking Dwarves get nothing")
	local state2 = fresh()
	war(state2, PLAINS)
	state2.nations[ZEPHYR].race = "Dwarves"
	local def2 = modifiers(state2, PLAINS)
	T.near(def2, 1, 1e-9, "nothing on plains")
end)

T.test("Elves fight harder in forest provinces, attacking or defending", function()
	local terrain = Config.Battle.TerrainDefenceBonus
	local bonus = Config.Races.Elves.forestBonus
	local state = fresh()
	war(state, FOREST)
	state.nations[ZEPHYR].race, state.nations[AURORA].race = "Elves", "Elves"
	local def, att = modifiers(state, FOREST)
	T.near(def, 1 + terrain + bonus, 1e-9, "defending Elves in forest")
	T.near(att, 1 + bonus, 1e-9, "attacking Elves in forest")
	local state2 = fresh()
	war(state2, HILLS)
	state2.nations[ZEPHYR].race, state2.nations[AURORA].race = "Elves", "Elves"
	local def2, att2 = modifiers(state2, HILLS)
	T.near(def2, 1 + terrain, 1e-9, "no forest, no bonus")
	T.near(att2, 1, 1e-9)
end)

T.test("Elves cross forest at plains speed", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Meadows"), 2000)
	state.nations[AURORA].race = "Humans"
	T.equal(Movement.moveTicks(state, army, FOREST), Config.Army.MoveTicks.Forest)
	state.nations[AURORA].race = "Elves"
	T.equal(Movement.moveTicks(state, army, FOREST), Config.Army.MoveTicks.Plains)
	T.equal(Movement.moveTicks(state, army, HILLS), Config.Army.MoveTicks.Hills, "hills stay slow")
	local riders = Army.spawn(state, AURORA, id("Aurora Fields"), 1000, "Cavalry")
	T.equal(Movement.moveTicks(state, riders, FOREST), Config.Army.FastMoveTicks.Plains, "elven cavalry")
end)

-- Battles -----------------------------------------------------------------------------------------------

T.test("a side's strength is its men × attack (attackers) or × defence (defenders)", function()
	local state = fresh()
	local archers = Army.spawn(state, AURORA, PLAINS, 2000, "Archers")
	local mixed = Army.spawn(state, ZEPHYR, PLAINS, 3000)
	Army.add(mixed, { Knights = 1000 })
	local t = Config.Troops
	T.near(Battle.strength({ archers }, true), 2000 * t.Archers.defence, 1e-9)
	T.near(Battle.strength({ archers }, false), 2000 * t.Archers.attack, 1e-9)
	T.near(Battle.strength({ mixed }, false), 3000 * INF.attack + 1000 * t.Knights.attack, 1e-9)
	T.near(Battle.strength({ archers, mixed }, true), 2000 * t.Archers.defence + 3000 + 1000 * t.Knights.defence, 1e-9)
end)

T.test("a round: knights attacking kill by their attack, archers defending by their defence", function()
	local state = fresh()
	war(state, PLAINS)
	state.nations[AURORA].race, state.nations[ZEPHYR].race = "Humans", "Humans" -- no combat bonus on plains anyway
	local knights = Army.spawn(state, AURORA, PLAINS, 2000, "Knights")
	local archers = Army.spawn(state, ZEPHYR, PLAINS, 2000, "Archers")
	run(state, 1)
	local rate, t = Config.Battle.KillRatePerRound, Config.Troops
	T.expect(state.battles[PLAINS] ~= nil, "the battle started")
	T.equal(archers.men, 2000 - math.floor(rate * 2000 * t.Knights.attack + 0.5))
	T.equal(knights.men, 2000 - math.floor(rate * 2000 * t.Archers.defence + 0.5))
	T.equal(archers.troops.Archers, archers.men)
	-- the same knights as defenders kill by their (lower) defence
	local state2 = fresh()
	war(state2, PLAINS)
	local holders = Army.spawn(state2, ZEPHYR, PLAINS, 2000, "Knights")
	local raiders = Army.spawn(state2, AURORA, PLAINS, 2000, "Archers")
	run(state2, 1)
	T.equal(raiders.men, 2000 - math.floor(rate * 2000 * t.Knights.defence + 0.5))
	T.equal(holders.men, 2000 - math.floor(rate * 2000 * t.Archers.attack + 0.5))
end)

T.test("losses split over the troop types in proportion to their men", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, PLAINS, 3000)
	Army.add(army, { Cavalry = 1000 })
	Army.shrinkTo(army, 3000)
	T.equal(army.troops.Infantry, 2250)
	T.equal(army.troops.Cavalry, 750)
	T.equal(army.men, 3000)
	-- whole men that always add up: leftovers go to the biggest remainders, ties to the earlier type
	local parts = Troops.split({ Infantry = 1, Archers = 1, Cavalry = 1 }, 2)
	T.equal(parts.Infantry, 1)
	T.equal(parts.Archers, 1)
	T.equal(parts.Cavalry or 0, 0)
	local odd = Troops.split({ Infantry = 2333, Archers = 1001, Berserkers = 999 }, 2718)
	T.equal(sumOf(odd), 2718)
	-- in a real battle the mix keeps its shares
	war(state, PLAINS)
	clear(state, PLAINS)
	local mixed = Army.spawn(state, AURORA, PLAINS, 3000)
	Army.add(mixed, { Archers = 1000 })
	Army.spawn(state, ZEPHYR, PLAINS, 4000)
	run(state, 1)
	T.expect(mixed.men < 4000, "took losses")
	T.equal(sumOf(mixed.troops), mixed.men)
	T.near(mixed.troops.Infantry / mixed.men, 0.75, 0.001)
end)

T.test("merging stacks adds their compositions", function()
	local state = fresh()
	local where = id("Aurora Fields")
	local a = Army.spawn(state, AURORA, where, 2000)
	local b = Army.spawn(state, AURORA, where, 1000, "Archers")
	Army.add(b, { Cavalry = 1000 })
	Movement.mergeStacks(state)
	T.equal(state.armies[b.id], nil, "one stack left")
	T.equal(a.troops.Infantry, 2000)
	T.equal(a.troops.Archers, 1000)
	T.equal(a.troops.Cavalry, 1000)
	T.equal(a.men, 4000)
end)

-- Movement ----------------------------------------------------------------------------------------------

T.test("an army marches at its slowest troop's speed", function()
	local state = fresh()
	state.nations[AURORA].race = "Humans"
	local fast = Config.Army.FastMoveTicks
	local riders = Army.spawn(state, AURORA, id("Aurora Meadows"), 1000, "Cavalry")
	T.equal(Movement.moveTicks(state, riders, id("Aurora Landing")), fast.Plains)
	T.equal(Movement.moveTicks(state, riders, HILLS), fast.Hills)
	assert(Movement.order(state, AURORA, riders.id, id("Aurora Landing")))
	run(state, fast.Plains - 1)
	T.equal(riders.location, id("Aurora Meadows"))
	run(state, 1)
	T.equal(riders.location, id("Aurora Landing"), "cavalry arrives after " .. fast.Plains .. " ticks")
	local column = Army.spawn(state, AURORA, id("Aurora Fields"), 1000, "Knights")
	T.equal(Movement.moveTicks(state, column, id("Aurora Landing")), fast.Plains, "knights are fast too")
	Army.add(column, { Infantry = 1000 })
	T.equal(Movement.moveTicks(state, column, id("Aurora Landing")), Config.Army.MoveTicks.Plains, "infantry slows it")
end)

-- Sieges ------------------------------------------------------------------------------------------------

T.test("an army with Ironguard besieges faster (Ironguard siegeSpeed)", function()
	local function siegeTicks(troops: Types.Composition): number
		local state = fresh()
		local rock = id("Cinder Rock")
		clear(state, rock)
		local army = Army.spawn(state, AURORA, rock, 1)
		Army.setTroops(army, troops)
		local required = Siege.required(state.provinces[rock])
		local ticks = 0
		while state.provinces[rock].owner ~= AURORA and ticks < 2 * required do
			run(state, 1)
			ticks += 1
		end
		return ticks
	end
	local required = Config.Siege.TicksPerDevelopment * map.provinces[id("Cinder Rock")].development
	local speed = Config.Troops.Ironguard.siegeSpeed :: number
	T.equal(siegeTicks({ Infantry = 3000 }), required)
	T.equal(siegeTicks({ Ironguard = 1000 }), math.ceil(required / speed))
	T.equal(
		siegeTicks({ Infantry = 5000, Ironguard = 1000 }),
		math.ceil(required / speed),
		"any Ironguard sets the pace"
	)
end)

-- Powers, garrisons, network, quests --------------------------------------------------------------------

T.test("a Meteor kills half of every troop type", function()
	local state = fresh()
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.nations[ZEPHYR].charges = 2
	local army = Army.spawn(state, AURORA, id("Aurora Fields"), 3000)
	Army.add(army, { Archers = 1000 })
	T.expect((Primordial.use(state, { nation = ZEPHYR }, "Meteor", army.id)))
	T.equal(army.troops.Infantry, 1500)
	T.equal(army.troops.Archers, 500)
	T.equal(army.men, 2000)
end)

T.test("neutral garrisons and Rebels are infantry, and have no race", function()
	local state = fresh()
	for _, a in state.armies do
		if a.owner == 0 then
			T.equal(a.troops.Infantry, a.men)
			T.equal(Races.of(state, a.owner), nil)
		end
	end
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.nations[ZEPHYR].charges = 2
	T.expect((Primordial.use(state, { nation = ZEPHYR }, "Rebels", id("Aurora Fields"))))
	local rebels
	for _, a in state.armies do
		if a.rebel then
			rebels = a
		end
	end
	T.expect(rebels ~= nil and rebels.troops.Infantry == Config.Primordial.Powers.Rebels.men, "infantry Rebels")
end)

T.test("the network carries every nation's race and every army's composition", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Fields"), 2000)
	Army.add(army, { Archers = 1000 })
	local snap = Snapshot.full(state)
	for _, n in snap.nations do
		T.equal(n.race, state.nations[n.id].race)
	end
	local record
	for _, a in snap.armies do
		if a.id == army.id then
			record = a
		end
	end
	assert(record, "the army is in the snapshot")
	T.equal(record.troops, "Infantry:2000,Archers:1000")
	local back = Troops.decode(record.troops)
	T.equal(back.Infantry, 2000)
	T.equal(back.Archers, 1000)
	-- a change of composition alone is a delta
	local before = Snapshot.full(state)
	Army.setTroops(army, { Infantry = 1000, Archers = 2000 })
	local delta = assert(Snapshot.diff(before, Snapshot.full(state)))
	T.equal(#delta.armies, 1)
	T.equal(delta.armies[1].troops, "Infantry:1000,Archers:2000")
end)

T.test("quests and achievements count every troop as a regiment", function()
	local stats = Progression.newStats(77, 0)
	Progression.recordCommand(stats, 1, { kind = "Recruit", province = 1, regiments = 2, troop = "Knights" }, true)
	Progression.recordCommand(stats, 2, { kind = "Recruit", province = 1, regiments = 1, troop = "Archers" }, true)
	T.equal(stats.regiments, 3)
end)

-- Bots --------------------------------------------------------------------------------------------------

-- Aurora holds Cinder Rock, Zephyr holds Cinder Reach next to it; they are at war and a Zephyr army waits there.
local function borderWar(auroraMen: number, zephyrMen: number): MatchState
	local state = fresh()
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	for armyId, a in state.armies do
		if a.owner == 0 then
			state.armies[armyId] = nil
		end
	end
	assert(Diplomacy.declareWar(state, ZEPHYR, AURORA))
	Army.spawn(state, ZEPHYR, id("Cinder Reach"), zephyrMen)
	if auroraMen > 0 then
		Army.spawn(state, AURORA, id("Aurora Landing"), auroraMen)
	end
	return state
end

local function recruitOf(commands: { Types.Command }): Types.Command?
	for _, c in commands do
		if c.kind == "Recruit" then
			return c
		end
	end
	return nil
end

T.test("bots: a threatened province raises archers", function()
	local state = borderWar(1000, 3000)
	local c = recruitOf(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	assert(c and c.kind == "Recruit", "the bot recruits")
	T.equal(c.province, id("Cinder Rock"))
	T.equal(c.troop, "Archers")
end)

T.test("bots: infantry in peace; cavalry or their elite at war when they can afford it", function()
	local state = fresh()
	local c = recruitOf(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	assert(c and c.kind == "Recruit", "the bot recruits")
	T.equal(c.troop, "Infantry")
	-- at war with Zephyr far away (no threat), rich: the attack troops
	local rich = borderWar(0, 1000)
	clear(rich, id("Cinder Reach"))
	rich.nations[AURORA].gold = 2000
	local d = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
	assert(d and d.kind == "Recruit", "the bot recruits")
	T.expect(d.troop == "Cavalry" or d.troop == Troops.elite(rich.nations[AURORA].race), "attack troop: " .. d.troop)
	-- poor at war: infantry
	rich.nations[AURORA].gold = Config.Troops.Infantry.gold
	local e = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
	assert(e and e.kind == "Recruit", "the bot recruits")
	T.equal(e.troop, "Infantry")
end)

T.test("bots: infantry stays the base (archers and attack troops stop at their share of the army)", function()
	local state = borderWar(1000, 3000)
	for _, a in state.armies do
		if a.owner == AURORA then
			Army.setTroops(a, { Archers = a.men }) -- all archers already: well past ArcherShare
		end
	end
	local c = recruitOf(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	assert(c and c.kind == "Recruit", "the bot recruits")
	T.equal(c.province, id("Cinder Rock"))
	T.equal(c.troop, "Infantry")
	local rich = borderWar(0, 1000)
	clear(rich, id("Cinder Reach"))
	rich.nations[AURORA].gold = 2000
	Army.spawn(rich, AURORA, rich.nations[AURORA].capital, 2000, "Cavalry") -- past AttackShare
	local d = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
	assert(d and d.kind == "Recruit", "the bot recruits")
	T.equal(d.troop, "Infantry")
end)

T.test("bots never ask for another race's elite", function()
	for _, mapId in Maps.ids do
		local state = Match.new(Maps.get(mapId))
		for nationId, nation in state.nations do
			nation.gold = 5000
			state.tick = Config.Phases.PeaceEndTick
			state.phase = "War"
			for other in state.nations do
				if other ~= nationId and Diplomacy.atWar(state, nationId, other) == false then
					state.wars[#state.wars + 1] =
						{ id = #state.wars + 1, attackers = { nationId }, defenders = { other }, startedAt = 0 }
					break
				end
			end
			local c = recruitOf(Bot.plan(state, nationId, Rng.new(nationId), "Normal"))
			if c and c.kind == "Recruit" then
				T.expect(Troops.canRecruit(nation.race, c.troop), nation.name .. " asked for " .. c.troop)
			end
		end
	end
end)

T.finish()
