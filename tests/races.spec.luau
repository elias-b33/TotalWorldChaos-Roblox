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

T.test("every map has its own cast of five races, two nations each, set in the map data", function()
	local everyRace: { [string]: boolean } = {}
	for _, mapId in Maps.ids do
		local cast = Races.forMap(mapId)
		T.equal(#cast, 5, mapId .. " has five races")
		local state = Match.new(Maps.get(mapId))
		local seen: { [string]: number } = {}
		for _, nation in state.nations do
			T.expect(Races.isRace(nation.race), nation.name .. " has no race")
			T.expect(table.find(cast, nation.race) ~= nil, nation.name .. "'s " .. nation.race .. " isn't of " .. mapId)
			seen[nation.race] = (seen[nation.race] or 0) + 1
		end
		for _, race in cast do
			T.equal(seen[race] or 0, 2, mapId .. ": nations of the " .. race)
			T.equal(Races.mapOf(race), mapId)
			T.expect(not everyRace[race], race .. " lives on one map only")
			everyRace[race] = true
		end
	end
	for _, race in Races.LIST do
		T.expect(everyRace[race], race .. " is in a map's cast")
	end
	T.equal(#Races.LIST, 15, "fifteen races in all")
end)

T.test("Earth is human civilisations, Eldmoor the fantasy peoples, Skyshards the sci-fi peoples", function()
	local earth, eldmoor, sky = Races.forMap("earth"), Races.forMap("eldmoor"), Races.forMap("skyshards")
	for _, race in { "Kingdom", "Empire", "Nomads", "Republic", "Clans" } do
		T.expect(table.find(earth, race) ~= nil, "Earth has the " .. race)
	end
	for _, race in { "Humans", "Elves", "Orcs", "Dwarves", "Lizardfolk" } do
		T.expect(table.find(eldmoor, race) ~= nil, "Eldmoor has the " .. race)
	end
	for _, race in { "Marines", "Robots", "Insectoids", "Crystals", "Energy" } do
		T.expect(table.find(sky, race) ~= nil, "Skyshards has the " .. race)
	end
	T.equal(Races.name("Crystals"), "Crystal folk", "a race's name for the UI")
	T.equal(Races.name(nil), "")
end)

T.test("each race has one passive of the known kinds and a roster of five, one troop per role", function()
	local kinds: { [string]: number } = {}
	for _, race in Races.LIST do
		local def = assert(Races.def(race), race)
		T.expect(table.find(Races.PASSIVES, def.passive) ~= nil, race .. "'s passive " .. def.passive)
		kinds[def.passive] = (kinds[def.passive] or 0) + 1
		T.expect(Races.bonusText(race) ~= "", race .. " describes its passive")
		local roster = Troops.roster(race)
		T.equal(#roster, 5, race .. " recruits five troops")
		for i, role in Troops.ROLES do
			T.equal(Troops.role(roster[i]), role, race .. "'s troop " .. i)
			T.equal(Troops.ofRole(race, role), roster[i])
		end
	end
	for _, kind in Races.PASSIVES do
		T.expect((kinds[kind] or 0) >= 1, "some race has the " .. kind .. " passive")
	end
	T.equal(#Troops.roster(nil), 0, "no race, no roster")
	T.equal(Troops.ofRole(nil, "line"), nil)
	-- every troop in Config.Troops is in some race's roster
	for _, troop in Troops.LIST do
		local owners = 0
		for _, race in Races.LIST do
			owners += if table.find(Troops.roster(race), troop) then 1 else 0
		end
		T.expect(owners >= 1, troop .. " is some race's")
	end
end)

T.test(
	"Earth's cultures share four human troops and each adds its own elite; elsewhere every race's five are its own",
	function()
		local earth = Races.forMap("earth")
		local elites: { [string]: boolean } = {}
		for _, race in earth do
			for _, role in { "line", "ranged", "fast", "special" } :: { Types.TroopRole } do
				T.equal(
					Troops.ofRole(race, role),
					Troops.ofRole(earth[1], role),
					race .. " shares Earth's " .. role .. " troop"
				)
			end
			local elite = assert(Troops.ofRole(race, "elite"))
			T.expect(not elites[elite], race .. "'s elite is its own")
			elites[elite] = true
		end
		T.equal(Troops.ofRole("Kingdom", "line"), Troops.BASE, "Earth's line troop is the garrisons' Infantry")
		T.equal(Troops.ofRole("Clans", "special"), "Catapults")
		for _, mapId in { "eldmoor", "skyshards" } do
			local seen: { [string]: string } = {}
			for _, race in Races.forMap(mapId) do
				for _, troop in Troops.roster(race) do
					T.expect(
						seen[troop] == nil,
						mapId .. ": " .. troop .. " is both " .. tostring(seen[troop]) .. "'s and " .. race .. "'s"
					)
					seen[troop] = race
				end
			end
		end
	end
)

T.test(
	"every troop has its own name and job: fast troops march fast, each special has one trick, the rest none",
	function()
		local names: { [string]: string } = {}
		local tricks = { "siegeSpeed", "terrain", "pathfinder", "vsNeutral" }
		for _, troop in Troops.LIST do
			local t = Troops.stats(troop)
			T.expect(names[t.name] == nil, troop .. " and " .. tostring(names[t.name]) .. " share the name " .. t.name)
			names[t.name] = troop
			T.expect(string.match(troop, "^%a+$") ~= nil, troop .. ": ids are letters only (the network encoding)")
			T.expect(t.gold > 0 and t.manpower > 0 and t.upkeep > 0, troop .. " costs something")
			T.expect(t.attack > 0 and t.defence > 0, troop .. " fights")
			if t.role == "fast" then
				T.expect(t.fast == true, troop .. " is a fast troop")
			elseif t.role ~= "elite" then
				T.expect(not t.fast, troop .. " marches at the normal pace")
			end
			local count = 0
			for _, trick in tricks do
				count += if (t :: any)[trick] ~= nil then 1 else 0
			end
			T.equal(count, if t.role == "special" then 1 else 0, troop .. "'s tricks")
			T.equal(Troops.trickText(troop) ~= "", t.role == "special", troop .. "'s trick text")
			if t.terrain then
				T.expect((t.terrainBonus or 0) > 0, troop .. " has a terrain bonus")
			end
		end
		T.equal(
			Troops.trickText("Catapults"),
			string.format("Besieges %gx as fast", Config.Troops.Catapults.siegeSpeed)
		)
		T.equal(
			Troops.trickText("Treants"),
			string.format("+%d%% in forest battles", math.floor(Config.Troops.Treants.terrainBonus * 100 + 0.5))
		)
		T.equal(Troops.trickText("SwampStalkers"), "Forest and hills at plains speed")
		T.equal(
			Troops.trickText("Battlemages"),
			string.format(
				"+%d%% against garrisons and Rebels",
				math.floor(Config.Troops.Battlemages.vsNeutral * 100 + 0.5)
			)
		)
		T.equal(Troops.trickText("Dragons"), "")
		T.equal(Troops.name("ElkRiders"), "Elk riders")
		T.equal(Troops.name("Dragons"), "Dragons")
		T.equal(Troops.icon("HorseArchers"), "horsearchers", "a troop's icon is its id in lower case")
		-- a fixed order: sorted by id
		for i = 1, #Troops.LIST - 1 do
			T.expect(Troops.LIST[i] < Troops.LIST[i + 1], "LIST is sorted")
		end
	end
)

T.test("a nation recruits its race's five troops and nothing else: the server refuses any other", function()
	local state = fresh()
	local nation = state.nations[AURORA]
	for _, race in Races.LIST do
		nation.race = race
		local roster = Troops.roster(race)
		T.equal(#roster, 5)
		for _, troop in Troops.LIST do
			nation.gold, nation.manpower = 10000, 100000
			local ok, err = recruit(state, AURORA, troop)
			local mayRecruit = table.find(roster, troop) ~= nil
			T.equal(ok, mayRecruit, race .. " recruiting " .. troop)
			T.equal(Troops.canRecruit(race, troop), mayRecruit)
			if not mayRecruit then
				T.equal(err, "WrongRace")
				T.equal(nation.gold, 10000, "a refused recruit costs nothing")
			end
		end
	end
	T.expect(not Troops.canRecruit(nil, "Infantry"), "no race recruits nothing")
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
	T.expect((recruit(state, AURORA, "Footmen", 2)))
	T.expect((recruit(state, AURORA, "Longbowmen", 1)))
	T.expect((recruit(state, AURORA, "Knights", 1)))
	local t = Config.Troops
	T.equal(nation.gold, 1000 - 2 * t.Footmen.gold - t.Longbowmen.gold - t.Knights.gold)
	T.equal(nation.manpower, 20000 - 2 * t.Footmen.manpower - t.Longbowmen.manpower - t.Knights.manpower)
	local army = assert(Army.idleAt(state, AURORA, nation.capital))
	T.equal(army.troops.Footmen, 2000)
	T.equal(army.troops.Longbowmen, 1000)
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

T.test("passives go by kind: every Forest race and every Hills race gets the same rules", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Meadows"), 2000)
	state.nations[AURORA].race = "Crystals" -- Skyshards' Forest race glides through crystal groves
	T.equal(Movement.moveTicks(state, army, FOREST), Config.Army.MoveTicks.Plains)
	local battle = fresh()
	war(battle, FOREST)
	battle.nations[ZEPHYR].race, battle.nations[AURORA].race = "Crystals", "Marines"
	local def = modifiers(battle, FOREST)
	T.near(def, 1 + Config.Battle.TerrainDefenceBonus + Config.Races.Crystals.forestBonus, 1e-9, "Crystals in forest")
	local hills = fresh()
	war(hills, HILLS)
	hills.nations[ZEPHYR].race, hills.nations[AURORA].race = "Clans", "Marines" -- Earth's Hills race
	local hdef = modifiers(hills, HILLS)
	T.near(hdef, 1 + Config.Battle.TerrainDefenceBonus + Config.Races.Clans.hillsDefenceBonus, 1e-9, "Clans in hills")
	T.equal(
		Economy.buildingCost("Fort", "Clans"),
		Config.Buildings.Fort.cost * Config.Races.Clans.fortCostMultiplier,
		"Clans build cheap forts"
	)
	T.equal(Economy.buildingCost("Fort", "Kingdom"), Config.Buildings.Fort.cost)
end)

T.test("an Upkeep race pays less upkeep for every troop type, and bots count it", function()
	local state = fresh()
	Army.spawn(state, AURORA, state.nations[AURORA].capital, 3000)
	Army.spawn(state, AURORA, id("Aurora Fields"), 1000, "Drones")
	state.nations[AURORA].race = "Marines"
	local full = Economy.monthlyIncome(state, AURORA).upkeep
	state.nations[AURORA].race = "Robots"
	local cheap = Economy.monthlyIncome(state, AURORA).upkeep
	T.near(cheap, full * Config.Races.Robots.upkeepMultiplier, 1e-9)
	T.expect(cheap < full, "machines need no pay")
	T.near(Races.upkeepMultiplier("Republic"), Config.Races.Republic.upkeepMultiplier, 1e-9)
	T.equal(Races.upkeepMultiplier("Humans"), 1, "other races pay in full")
end)

T.test("a Swift race marches faster: every step takes fewer ticks, at least one", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Meadows"), 2000)
	local riders = Army.spawn(state, AURORA, id("Aurora Fields"), 1000, "StormWisps")
	state.nations[AURORA].race = "Marines"
	local plain, hill = Movement.moveTicks(state, army, id("Aurora Landing")), Movement.moveTicks(state, army, HILLS)
	state.nations[AURORA].race = "Energy"
	local m = Config.Races.Energy.moveMultiplier
	T.equal(Movement.moveTicks(state, army, id("Aurora Landing")), math.floor(plain * m + 0.5))
	T.equal(Movement.moveTicks(state, army, HILLS), math.floor(hill * m + 0.5))
	T.expect(Movement.moveTicks(state, army, HILLS) < hill, "faster in hills too")
	local fast = Movement.moveTicks(state, riders, id("Aurora Landing"))
	T.equal(fast, math.max(1, math.floor(Config.Army.FastMoveTicks.Plains * m + 0.5)), "storm wisps are fast too")
	T.expect(fast >= 1, "never instant")
	T.equal(Races.moveTicks("Nomads", 1), 1, "at least one tick")
	-- a whole march: the order arrives sooner
	assert(Movement.order(state, AURORA, army.id, id("Aurora Landing")))
	run(state, math.floor(plain * m + 0.5))
	T.equal(army.location, id("Aurora Landing"), "the Energy beings arrive early")
end)

T.test("an Attack race fights harder when attacking, anywhere, never defending", function()
	local state = fresh()
	war(state, PLAINS)
	state.nations[ZEPHYR].race, state.nations[AURORA].race = "Lizardfolk", "Empire"
	local def, att = modifiers(state, PLAINS)
	T.near(att, 1 + Config.Races.Empire.attackBonus, 1e-9, "the Empire attacking on plains")
	T.near(def, 1, 1e-9, "the Lizardfolk defending get nothing")
	local hills = fresh()
	war(hills, HILLS)
	hills.nations[ZEPHYR].race, hills.nations[AURORA].race = "Marines", "Lizardfolk"
	local _, att2 = modifiers(hills, HILLS)
	T.near(att2, 1 + Config.Races.Lizardfolk.attackBonus, 1e-9, "and in hills")
end)

T.test("each passive's one line for the UI follows Config", function()
	local function pct(x: number): string
		return math.floor(x * 100 + 0.5) .. "%"
	end
	T.equal(Races.bonusText("Kingdom"), "+" .. pct(Config.Races.Kingdom.goldBonus) .. " gold")
	T.equal(Races.bonusText("Orcs"), "+" .. pct(Config.Races.Orcs.manpowerBonus) .. " manpower")
	T.equal(
		Races.bonusText("Dwarves"),
		string.format(
			"+%s defending hills, forts -%s",
			pct(Config.Races.Dwarves.hillsDefenceBonus),
			pct(1 - Config.Races.Dwarves.fortCostMultiplier)
		)
	)
	T.equal(
		Races.bonusText("Robots"),
		"Armies cost " .. pct(1 - Config.Races.Robots.upkeepMultiplier) .. " less upkeep"
	)
	T.equal(Races.bonusText("Nomads"), "Armies march " .. pct(1 - Config.Races.Nomads.moveMultiplier) .. " faster")
	T.equal(Races.bonusText("Lizardfolk"), "+" .. pct(Config.Races.Lizardfolk.attackBonus) .. " attacking")
	T.equal(Races.bonusText(nil), "")
end)

T.test("one race per match: a nation's race comes from the map data and recruiting never changes it", function()
	local state = Match.new(Maps.get("earth"))
	for _, nation in state.nations do
		T.expect(table.find(Races.forMap("earth"), nation.race) ~= nil, nation.name .. " is one of Earth's cultures")
		T.equal(Troops.ofRole(nation.race, "line"), "Infantry", "everyone on Earth is human")
	end
	local nation = state.nations[1]
	local race = nation.race
	nation.gold, nation.manpower = 5000, 50000
	for _, troop in Troops.roster(race) do
		T.expect(
			(Commands.apply(state, 1, { kind = "Recruit", province = nation.capital, regiments = 1, troop = troop }))
		)
	end
	T.equal(nation.race, race)
end)

-- Battles -----------------------------------------------------------------------------------------------

T.test("a side's strength is its men × attack (attackers) or × defence (defenders)", function()
	local state = fresh()
	local archers = Army.spawn(state, AURORA, PLAINS, 2000, "Archers")
	local mixed = Army.spawn(state, ZEPHYR, PLAINS, 3000, "Infantry")
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
	local army = Army.spawn(state, AURORA, PLAINS, 3000, "Infantry")
	Army.add(army, { Cavalry = 1000 })
	Army.shrinkTo(army, 3000)
	T.equal(army.troops.Infantry, 2250)
	T.equal(army.troops.Cavalry, 750)
	T.equal(army.men, 3000)
	-- whole men that always add up: leftovers go to the biggest remainders, ties to the earlier type in LIST (by id)
	local parts = Troops.split({ Infantry = 1, Archers = 1, Cavalry = 1 }, 2)
	T.equal(parts.Archers, 1)
	T.equal(parts.Cavalry, 1)
	T.equal(parts.Infantry or 0, 0)
	local odd = Troops.split({ Infantry = 2333, Archers = 1001, Berserkers = 999 }, 2718)
	T.equal(sumOf(odd), 2718)
	-- in a real battle the mix keeps its shares
	war(state, PLAINS)
	clear(state, PLAINS)
	local mixed = Army.spawn(state, AURORA, PLAINS, 3000, "Infantry")
	Army.add(mixed, { Archers = 1000 })
	Army.spawn(state, ZEPHYR, PLAINS, 4000, "Infantry")
	run(state, 1)
	T.expect(mixed.men < 4000, "took losses")
	T.equal(sumOf(mixed.troops), mixed.men)
	T.near(mixed.troops.Infantry / mixed.men, 0.75, 0.001)
end)

T.test("merging stacks adds their compositions", function()
	local state = fresh()
	local where = id("Aurora Fields")
	local a = Army.spawn(state, AURORA, where, 2000, "Infantry")
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

T.test("an army with a siege troop besieges faster (Catapults, Sappers, Artillery: siegeSpeed)", function()
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
	local speed = Config.Troops.Artillery.siegeSpeed :: number
	T.equal(siegeTicks({ Troopers = 3000 }), required)
	T.equal(siegeTicks({ Artillery = 1000 }), math.ceil(required / speed))
	T.equal(
		siegeTicks({ Troopers = 5000, Artillery = 1000 }),
		math.ceil(required / speed),
		"any Artillery sets the pace"
	)
	local catapults = Config.Troops.Catapults.siegeSpeed :: number
	T.equal(siegeTicks({ Infantry = 2000, Catapults = 1000 }), math.ceil(required / catapults), "Catapults")
	T.equal(Troops.siegeSpeed({ Sappers = 1000 }), Config.Troops.Sappers.siegeSpeed)
	T.equal(Troops.siegeSpeed({ Ironguard = 3000, Pikemen = 3000 }), 1, "the elites besiege at the normal pace")
end)

-- Specials' tricks ---------------------------------------------------------------------------------------

T.test("a terrain special fights harder in its terrain only (Treants in forest, Trolls in hills)", function()
	local t = Config.Troops
	local treants = { Treants = 2000, Wardens = 1000 }
	T.near(Troops.strength(treants, true), 2000 * t.Treants.defence + 1000 * t.Wardens.defence, 1e-9)
	T.near(
		Troops.strength(treants, true, "Forest"),
		2000 * t.Treants.defence * (1 + (t.Treants.terrainBonus :: number)) + 1000 * t.Wardens.defence,
		1e-9,
		"only the Treants' men get it"
	)
	T.near(Troops.strength(treants, false, "Hills"), 2000 * t.Treants.attack + 1000 * t.Wardens.attack, 1e-9)
	T.near(
		Troops.strength({ Trolls = 1000 }, false, "Hills"),
		1000 * t.Trolls.attack * (1 + (t.Trolls.terrainBonus :: number)),
		1e-9,
		"attacking too"
	)
	-- in a real battle: Treants holding a forest kill more than the same Treants on plains
	local function kills(where: number): number
		local state = fresh()
		war(state, where)
		state.nations[AURORA].race, state.nations[ZEPHYR].race = "Marines", "Marines" -- no passive in play
		Army.spawn(state, ZEPHYR, where, 2000, "Treants")
		local raiders = Army.spawn(state, AURORA, where, 4000, "Troopers")
		run(state, 1)
		return 4000 - raiders.men
	end
	local terrain = Config.Battle.TerrainDefenceBonus
	local inForest, onPlains = kills(FOREST), kills(PLAINS)
	local rate = Config.Battle.KillRatePerRound
	T.equal(onPlains, math.floor(rate * 2000 * t.Treants.defence + 0.5))
	T.equal(
		inForest,
		math.floor(rate * 2000 * t.Treants.defence * (1 + (t.Treants.terrainBonus :: number)) * (1 + terrain) + 0.5)
	)
end)

T.test(
	"a pathfinder special marches through forest and hills at plains speed; slower troops still set the pace",
	function()
		local state = fresh()
		state.nations[AURORA].race = "Lizardfolk"
		local plains = Config.Army.MoveTicks.Plains
		local stalkers = Army.spawn(state, AURORA, id("Aurora Meadows"), 1000, "SwampStalkers")
		T.equal(Movement.moveTicks(state, stalkers, FOREST), plains)
		T.equal(Movement.moveTicks(state, stalkers, HILLS), plains)
		T.equal(Movement.moveTicks(state, stalkers, id("Aurora Landing")), plains)
		Army.add(stalkers, { Scaleguards = 1000 })
		T.equal(
			Movement.moveTicks(state, stalkers, HILLS),
			Config.Army.MoveTicks.Hills,
			"the line troop slows it in hills"
		)
		local burrowers = Army.spawn(state, AURORA, id("Aurora Fields"), 1000, "Burrowers")
		Army.add(burrowers, { Wasps = 1000 })
		T.equal(
			Movement.moveTicks(state, burrowers, FOREST),
			math.max(plains, Config.Army.FastMoveTicks.Forest),
			"with fast troops: the slower of the two"
		)
	end
)

T.test("an anti-garrison special fights harder against neutral garrisons and Rebels, not against nations", function()
	local t = Config.Troops
	local mages = { Battlemages = 1000, Footmen = 1000 }
	T.near(
		Troops.strength(mages, false, nil, true),
		1000 * t.Battlemages.attack * (1 + (t.Battlemages.vsNeutral :: number)) + 1000 * t.Footmen.attack,
		1e-9
	)
	T.near(Troops.strength(mages, false, nil, false), 1000 * t.Battlemages.attack + 1000 * t.Footmen.attack, 1e-9)
	-- in a real battle: the same mages kill more of a garrison than of a nation's army
	local function kills(neutral: boolean): number
		local state = fresh()
		local where = PLAINS
		if neutral then
			clear(state, where)
		else
			war(state, where)
		end
		state.nations[AURORA].race = "Marines"
		state.nations[ZEPHYR].race = "Marines"
		local holders = Army.spawn(state, if neutral then 0 else ZEPHYR, where, 4000)
		Army.spawn(state, AURORA, where, 1000, "Battlemages")
		run(state, 1)
		return 4000 - holders.men
	end
	local rate = Config.Battle.KillRatePerRound
	local function lost(losses: number): number -- the holders' men round as Battle rounds them
		return 4000 - math.floor(4000 - losses + 0.5)
	end
	T.equal(kills(false), lost(rate * 1000 * t.Battlemages.attack))
	T.equal(kills(true), lost(rate * 1000 * t.Battlemages.attack * (1 + (t.Battlemages.vsNeutral :: number))))
end)

-- Powers, garrisons, network, quests --------------------------------------------------------------------

T.test("a Meteor kills half of every troop type", function()
	local state = fresh()
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	state.nations[ZEPHYR].charges = 2
	local army = Army.spawn(state, AURORA, id("Aurora Fields"), 3000, "Infantry")
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
	-- a nation's new army with no troop type given is its race's line troop
	local mine = Army.spawn(state, AURORA, id("Aurora Fields"), 2000)
	T.equal(mine.troops[Troops.ofRole(state.nations[AURORA].race, "line") :: Types.Troop], 2000)
	T.equal(Army.spawn(state, 0, id("Aurora Fields"), 1000).troops.Infantry, 1000)
end)

T.test("the network carries every nation's race and every army's composition", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Fields"), 2000, "Infantry")
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
	T.equal(record.troops, "Archers:1000,Infantry:2000", "LIST order: by id")
	local back = Troops.decode(record.troops)
	T.equal(back.Infantry, 2000)
	T.equal(back.Archers, 1000)
	-- a change of composition alone is a delta
	local before = Snapshot.full(state)
	Army.setTroops(army, { Infantry = 1000, Archers = 2000 })
	local delta = assert(Snapshot.diff(before, Snapshot.full(state)))
	T.equal(#delta.armies, 1)
	T.equal(delta.armies[1].troops, "Archers:2000,Infantry:1000")
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

T.test("bots: a threatened province raises the race's ranged troop", function()
	local state = borderWar(1000, 3000)
	local c = recruitOf(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	assert(c and c.kind == "Recruit", "the bot recruits")
	T.equal(c.province, id("Cinder Rock"))
	T.equal(c.troop, Troops.ofRole(state.nations[AURORA].race, "ranged"))
	T.equal(c.troop, "Gunners", "the Marines' ranged troop")
end)

T.test(
	"bots: the line troop in peace; at war the special, the elite and the fast troop when they can afford them",
	function()
		local state = fresh()
		local race = state.nations[AURORA].race
		local c = recruitOf(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
		assert(c and c.kind == "Recruit", "the bot recruits")
		T.equal(c.troop, Troops.ofRole(race, "line"))
		-- at war with Zephyr far away (no threat), rich: the special first (under SpecialShare)
		local rich = borderWar(0, 1000)
		clear(rich, id("Cinder Reach"))
		rich.nations[AURORA].gold = 2000
		local capital = rich.nations[AURORA].capital
		Army.spawn(rich, AURORA, capital, 3000, Troops.ofRole(race, "line"))
		local d = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
		assert(d and d.kind == "Recruit", "the bot recruits")
		T.equal(d.troop, Troops.ofRole(race, "special"))
		-- with its special's share filled: the elite and the fast troop, the one furthest below its share first
		-- (EliteShare, FastShare; none of either yet: the elite)
		Army.add(assert(Army.idleAt(rich, AURORA, capital)), { [Troops.ofRole(race, "special") :: Types.Troop] = 1000 })
		local f = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
		assert(f and f.kind == "Recruit", "the bot recruits")
		T.equal(f.troop, Troops.ofRole(race, "elite"))
		Army.add(assert(Army.idleAt(rich, AURORA, capital)), { [Troops.ofRole(race, "elite") :: Types.Troop] = 1000 })
		local g = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
		assert(g and g.kind == "Recruit", "the bot recruits")
		T.equal(g.troop, Troops.ofRole(race, "fast"))
		-- poor at war: the line troop
		local line = Troops.ofRole(race, "line") :: Types.Troop
		rich.nations[AURORA].gold = Config.Troops[line].gold
		local e = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
		assert(e and e.kind == "Recruit", "the bot recruits")
		T.equal(e.troop, line)
	end
)

T.test("bots: the line troop stays the base (the other roles stop at their share of the army)", function()
	local state = borderWar(1000, 3000)
	local race = state.nations[AURORA].race
	for _, a in state.armies do
		if a.owner == AURORA then
			Army.setTroops(a, { [Troops.ofRole(race, "ranged") :: Types.Troop] = a.men }) -- well past RangedShare
		end
	end
	local c = recruitOf(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	assert(c and c.kind == "Recruit", "the bot recruits")
	T.equal(c.province, id("Cinder Rock"))
	T.equal(c.troop, Troops.ofRole(race, "line"))
	local rich = borderWar(0, 1000)
	clear(rich, id("Cinder Reach"))
	rich.nations[AURORA].gold = 2000
	local army = Army.spawn(rich, AURORA, rich.nations[AURORA].capital, 1000, Troops.ofRole(race, "special"))
	Army.add(army, { [Troops.ofRole(race, "fast") :: Types.Troop] = 1000 })
	Army.add(army, { [Troops.ofRole(race, "elite") :: Types.Troop] = 1000 }) -- past every share
	local d = recruitOf(Bot.plan(rich, AURORA, Rng.new(1), "Normal"))
	assert(d and d.kind == "Recruit", "the bot recruits")
	T.equal(d.troop, Troops.ofRole(race, "line"))
end)

T.test("bots only ever ask for their own race's troops", function()
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
