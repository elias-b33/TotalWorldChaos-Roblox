--!strict
-- Navies (docs/DESIGN.md "Navies"): the sea zones in the map data, ships and fleets, sailing, embarking and landing,
-- sea battles and retreats, straits blocked by fleets, blockades, war across the sea, upkeep and elimination.
-- Mostly on Skyshards: its space zones are one wedge per home shard, so the cases are easy to set up.
local Army = require("../src/shared/Sim/Army")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Economy = require("../src/shared/Sim/Economy")
local MapGrid = require("../src/shared/MapGrid")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Movement = require("../src/shared/Sim/Movement")
local Navy = require("../src/shared/Sim/Navy")
local Pathing = require("../src/shared/Sim/Pathing")
local Primordial = require("../src/shared/Sim/Primordial")
local Rng = require("../src/shared/Sim/Rng")
local Siege = require("../src/shared/Sim/Siege")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

Config.Battle.RandomSpread = 0 -- deterministic battles in this file

local ZONE_COUNTS = { earth = { 15, 22 }, eldmoor = { 8, 12 }, skyshards = { 8, 12 } }

-- The map data --------------------------------------------------------------------------------------------------

for _, mapId in Maps.ids do
	local map = Maps.get(mapId)
	T.test(mapId .. ": sea zones are named, numbered 1..N and as many as the map should have", function()
		local lo, hi = ZONE_COUNTS[mapId][1], ZONE_COUNTS[mapId][2]
		T.expect(#map.seaZones >= lo and #map.seaZones <= hi, #map.seaZones .. " zones")
		T.expect(#map.ship > 0, "the map names its ship")
		local names: { [string]: boolean } = {}
		for _, p in map.provinces do
			names[p.name] = true
		end
		for i, z in map.seaZones do
			T.equal(z.id, i)
			T.expect(#z.name > 0 and not names[z.name], "zone name " .. z.name)
			names[z.name] = true
		end
	end)

	T.test(mapId .. ": zone neighbours are symmetric and every zone reaches every other", function()
		for _, z in map.seaZones do
			for _, n in z.neighbors do
				T.expect(map.seaZones[n] ~= nil and n ~= z.id, z.name .. " neighbour " .. n)
				T.expect(table.find(map.seaZones[n].neighbors, z.id) ~= nil, z.name .. " -> " .. n .. " is one-way")
			end
		end
		local seen, queue = { [1] = true }, { 1 }
		local count = 1
		while #queue > 0 do
			local cur = table.remove(queue) :: number
			for _, n in map.seaZones[cur].neighbors do
				if not seen[n] then
					seen[n] = true
					count += 1
					table.insert(queue, n)
				end
			end
		end
		T.equal(count, #map.seaZones, "zones reachable from the first")
	end)

	T.test(
		mapId .. ": coasts are passable provinces, and a province lists exactly the zones it is a coast of",
		function()
			for _, z in map.seaZones do
				T.expect(#z.coasts > 0, z.name .. " has a coast")
				for _, p in z.coasts do
					local def = map.provinces[p]
					T.expect(def.terrain ~= "Mountain", z.name .. " coast " .. def.name .. " is a mountain")
					T.expect(def.zones ~= nil and table.find(def.zones, z.id) ~= nil, def.name .. " lists " .. z.name)
				end
			end
			for _, def in map.provinces do
				for _, zone in def.zones or {} do
					T.expect(
						table.find(map.seaZones[zone].coasts, def.id) ~= nil,
						def.name .. " in " .. zone .. "'s coasts"
					)
				end
			end
		end
	)

	T.test(mapId .. ": every strait lies in a zone whose coasts hold both its ends", function()
		T.expect(#map.straits > 0)
		for _, s in map.straits do
			local zone = map.seaZones[s.zone]
			T.expect(zone ~= nil, "strait " .. s.a .. "-" .. s.b .. " has a zone")
			T.expect(
				table.find(zone.coasts, s.a) ~= nil and table.find(zone.coasts, s.b) ~= nil,
				"both ends on " .. zone.name
			)
		end
	end)

	T.test(mapId .. ": the sea grid covers only water, every zone has pixels, each centre lies in its zone", function()
		local land = MapGrid.decode(map)
		local sea = MapGrid.decodeSea(map)
		T.equal(sea.width, land.width)
		T.equal(sea.height, land.height)
		local pixels: { [number]: number } = {}
		local water, zoned = 0, 0
		for i = 0, buffer.len(sea.ids) - 1 do
			local z = buffer.readu8(sea.ids, i)
			local p = buffer.readu8(land.ids, i)
			if z ~= 0 then
				T.expect(p == 0, "a zone pixel on land")
				pixels[z] = (pixels[z] or 0) + 1
				zoned += 1
			end
			if p == 0 then
				water += 1
			end
		end
		T.expect(zoned > water * 0.97, string.format("nearly all water is zoned (%d of %d)", zoned, water))
		for _, z in map.seaZones do
			T.expect((pixels[z.id] or 0) > 0, z.name .. " has pixels")
			T.equal(MapGrid.at(sea, z.center.x / sea.scale, z.center.y / sea.scale), z.id, z.name .. " centre")
		end
	end)
end

T.test("skyshards: the space zones are symmetric, one per home shard", function()
	local map = Maps.get("skyshards")
	T.equal(#map.seaZones, #map.nations)
	for _, z in map.seaZones do
		local own = 0
		for _, p in z.coasts do
			if map.provinces[p].startOwner == z.id then
				own += 1
			end
		end
		T.equal(#z.coasts, 11, z.name .. " coasts")
		T.equal(own, 8, z.name .. " holds its whole home shard")
		T.equal(#z.neighbors, 2, z.name .. " neighbours")
	end
end)

-- Skyshards fixtures ----------------------------------------------------------------------------------------------

local map = Maps.get("skyshards")
local byName: { [string]: number } = {}
for _, p in map.provinces do
	byName[p.name] = p.id
end
local function id(name: string): number
	return assert(byName[name], "no province " .. name)
end

local AURORA, ZEPHYR, NIMBUS, HALO = 1, 2, 3, 5
local VEGA, LYRA, ORION = 1, 2, 3 -- the space zones round Aurora, Zephyr and Nimbus

local function fresh(): (Types.MatchState, Rng.Rng)
	return Match.new(map), Rng.new(1)
end

local function run(state: Types.MatchState, rng: Rng.Rng, ticks: number)
	for _ = 1, ticks do
		Tick.advance(state, rng)
	end
end

local function warPhase(state: Types.MatchState)
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
end

local function clearArmies(state: Types.MatchState, provinces: { number })
	for armyId, a in state.armies do
		if table.find(provinces, a.location) then
			state.armies[armyId] = nil
		end
	end
end

local function fleetsOf(state: Types.MatchState, owner: number): { Types.Fleet }
	local out = {}
	for _, f in state.fleets do
		if f.owner == owner then
			table.insert(out, f)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

local function events(state: Types.MatchState, kind: string): { Types.MatchEvent }
	local out = {}
	for _, e in state.events do
		if e.kind == kind then
			table.insert(out, e)
		end
	end
	return out
end

-- Ships and fleets ------------------------------------------------------------------------------------------------

T.test("ships launch from a coastal province into its port zone and join the idle fleet there", function()
	local state = fresh()
	local landing = id("Aurora Landing")
	T.equal(Navy.port(state, landing), VEGA)
	local gold = state.nations[AURORA].gold
	T.expect((Commands.apply(state, AURORA, { kind = "BuildShips", province = landing, ships = 2 })))
	T.equal(state.nations[AURORA].gold, gold - 2 * Config.Navy.ShipGold)
	local fleets = fleetsOf(state, AURORA)
	T.equal(#fleets, 1)
	T.equal(fleets[1].zone, VEGA)
	T.equal(Navy.ships(fleets[1]), 2)
	T.equal(Navy.capacity(fleets[1]), 2 * Config.Navy.ShipCapacity)
	T.expect((Commands.apply(state, AURORA, { kind = "BuildShips", province = id("Aurora Fields"), ships = 1 })))
	T.equal(#fleetsOf(state, AURORA), 1, "the new ship joins the idle fleet")
	T.equal(Navy.ships(fleets[1]), 3)
end)

T.test("ship orders are checked: a coast of your own, whole ships, gold", function()
	local state = fresh()
	local function refused(command: Types.Command, reason: string)
		local ok, err = Commands.apply(state, AURORA, command)
		T.expect(not ok, reason)
		T.equal(err, reason)
	end
	refused({ kind = "BuildShips", province = id("Zephyr Landing"), ships = 1 }, "NotYourProvince")
	refused({ kind = "BuildShips", province = id("Aurora Landing"), ships = 0 }, "BadAmount")
	refused({ kind = "BuildShips", province = id("Aurora Landing"), ships = 1.5 }, "BadAmount")
	refused(
		{ kind = "BuildShips", province = id("Aurora Landing"), ships = Config.Navy.MaxShipsPerCommand + 1 },
		"BadAmount"
	)
	state.nations[AURORA].gold = Config.Navy.ShipGold - 1
	refused({ kind = "BuildShips", province = id("Aurora Landing"), ships = 1 }, "NotEnoughGold")
	-- the Heartstone's Sanctums touch no zone
	local sanctum = id("Sanctum of Dawn")
	state.provinces[sanctum].owner = AURORA
	state.nations[AURORA].gold = 500
	refused({ kind = "BuildShips", province = sanctum, ships = 1 }, "NoCoast")
end)

T.test("a fleet sails a zone every MoveTicks; sailing where it stands stops it", function()
	local state, rng = fresh()
	local fleet = Navy.spawn(state, AURORA, VEGA, 1)
	T.expect((Commands.apply(state, AURORA, { kind = "Sail", fleet = fleet.id, zone = ORION })))
	T.equal(#fleet.path, 2)
	run(state, rng, Config.Navy.MoveTicks - 1)
	T.equal(fleet.zone, VEGA)
	run(state, rng, 1)
	T.equal(fleet.zone, LYRA)
	T.expect((Commands.apply(state, AURORA, { kind = "Sail", fleet = fleet.id, zone = LYRA })))
	T.equal(#fleet.path, 0)
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(fleet.zone, LYRA)
	local ok, err = Commands.apply(state, ZEPHYR, { kind = "Sail", fleet = fleet.id, zone = VEGA })
	T.expect(not ok)
	T.equal(err, "NotYourFleet")
end)

T.test("a nation's idle fleets in one zone merge, and orders for the merged one reach the stack", function()
	local state, rng = fresh()
	local a = Navy.spawn(state, AURORA, VEGA, 2)
	local b = Navy.spawn(state, AURORA, LYRA, 1)
	Navy.setCargo(b, { Archers = 1000 })
	T.expect((Commands.apply(state, AURORA, { kind = "Sail", fleet = b.id, zone = VEGA })))
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(state.fleets[b.id], nil)
	T.equal(Navy.ships(a), 3)
	T.equal(a.men, 1000)
	T.equal(a.troops.Archers, 1000)
	T.equal(Navy.resolve(state, b.id), a.id)
	T.expect((Commands.apply(state, AURORA, { kind = "Sail", fleet = b.id, zone = LYRA })), "an order to the old id")
	T.equal(a.path[1], LYRA)
end)

-- Embarking and landing -----------------------------------------------------------------------------------------

T.test("an army on the coast boards its fleet: what fits goes aboard, the rest stays", function()
	local state, rng = fresh()
	local landing = id("Aurora Landing")
	local fleet = Navy.spawn(state, AURORA, VEGA, 2)
	local army = Army.spawn(state, AURORA, landing, 2000)
	Army.add(army, { Archers = 1000 })
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = army.id, fleet = fleet.id })))
	run(state, rng, 1)
	T.equal(fleet.men, 2000, "two ships carry two regiments")
	T.equal(state.armies[army.id], army, "the rest stays ashore as the same army")
	T.equal(army.men, 1000)
	T.equal((fleet.troops.Infantry or 0) + (fleet.troops.Archers or 0), 2000)
	T.equal(Navy.room(fleet), 0)
	local ok, err = Commands.apply(state, AURORA, { kind = "Embark", army = army.id, fleet = fleet.id })
	T.expect(not ok)
	T.equal(err, "FleetFull")
	-- another ship: the rest goes aboard too, the army is gone (an Embarked event, not a defeat)
	fleet.hull += Config.Navy.ShipHull
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = army.id, fleet = fleet.id })))
	Tick.advance(state, rng)
	T.equal(state.armies[army.id], nil)
	T.equal(fleet.men, 3000)
	T.equal(#events(state, "Embarked"), 1)
	T.equal(Economy.regiments(state, AURORA), 3, "men aboard still count as the nation's")
end)

T.test("an army walks to a coast of the fleet's zone to board; a new order cancels boarding", function()
	local state, rng = fresh()
	local rock, reach = id("Cinder Rock"), id("Cinder Reach")
	clearArmies(state, { rock, reach })
	state.provinces[rock].owner = AURORA
	state.provinces[reach].owner = AURORA
	local fleet = Navy.spawn(state, AURORA, LYRA, 2) -- Cinder Reach is Aurora's only coast of Lyra Reach
	local army = Army.spawn(state, AURORA, id("Aurora Windward"), 2000)
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = army.id, fleet = fleet.id })))
	T.equal(army.path[#army.path], reach)
	T.equal(army.boardFleet, fleet.id)
	-- an army waiting to board doesn't merge into another standing beside it
	local waiting = Army.spawn(state, AURORA, rock, 1000)
	waiting.boardFleet = 999
	local beside = Army.spawn(state, AURORA, rock, 1000)
	Movement.mergeStacks(state)
	T.expect(state.armies[waiting.id] ~= nil and state.armies[beside.id] ~= nil, "no merge while boarding")
	state.armies[waiting.id], state.armies[beside.id] = nil, nil
	run(state, rng, 30)
	T.equal(state.armies[army.id], nil, "boarded at Cinder Reach")
	T.equal(fleet.men, 2000)
	-- a Move order replaces boarding
	local other = Army.spawn(state, AURORA, id("Aurora Windward"), 1000)
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = other.id, fleet = fleet.id })) == false)
	fleet.hull += Config.Navy.ShipHull
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = other.id, fleet = fleet.id })))
	T.expect((Commands.apply(state, AURORA, { kind = "Move", army = other.id, to = id("Aurora Landing") })))
	T.equal(other.boardFleet, nil)
end)

T.test("an army waits on the coast for a fleet on its way, and gives up on one that stopped elsewhere", function()
	local state, rng = fresh()
	local fleet = Navy.spawn(state, AURORA, ORION, 2)
	T.expect((Commands.apply(state, AURORA, { kind = "Sail", fleet = fleet.id, zone = VEGA })))
	local army = Army.spawn(state, AURORA, id("Aurora Landing"), 1000)
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = army.id, fleet = fleet.id })))
	T.equal(#army.path, 0, "already on a coast of the fleet's destination")
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(army.boardFleet, fleet.id, "still waiting")
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(state.armies[army.id], nil, "boarded when the fleet arrived")
	-- a fleet that stops somewhere the army can't reach from where it stands isn't waited for
	local far = Navy.spawn(state, AURORA, ORION, 1)
	local second = Army.spawn(state, AURORA, id("Aurora Landing"), 1000)
	second.boardFleet = far.id
	Tick.advance(state, rng)
	T.equal(second.boardFleet, nil)
	T.equal(state.armies[second.id], second)
end)

T.test("a fleet sails to a coast and lands everyone there, and the landed army fights and besieges", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock") -- neutral, with a garrison, a coast of Vega Drift
	local fleet = Navy.spawn(state, AURORA, LYRA, 3)
	Navy.setCargo(fleet, { Infantry = 3000 })
	T.expect((Commands.apply(state, AURORA, { kind = "Land", fleet = fleet.id, province = rock })))
	T.equal(fleet.landAt, rock)
	T.equal(fleet.path[#fleet.path], VEGA)
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(fleet.men, 0, "landed on arrival")
	local landed = events(state, "Landed")
	T.equal(#landed, 1)
	local army = state.armies[landed[1].a]
	T.expect(army ~= nil and army.location == rock and army.owner == AURORA)
	T.expect(army.inBattle, "it fights the garrison at once")
	run(state, rng, Config.Battle.Rounds + 2)
	T.expect(state.provinces[rock].siege ~= nil and state.provinces[rock].siege.by == AURORA, "then besieges")
end)

T.test("landing is checked: men aboard, a coast, and land open to you", function()
	local state = fresh()
	local fleet = Navy.spawn(state, AURORA, VEGA, 1)
	local function refused(province: number, reason: string)
		local ok, err = Commands.apply(state, AURORA, { kind = "Land", fleet = fleet.id, province = province })
		T.expect(not ok, reason)
		T.equal(err, reason)
	end
	refused(id("Cinder Rock"), "NoTroops")
	Navy.setCargo(fleet, { Infantry = 1000 })
	refused(id("Sanctum of Dawn"), "NoCoast")
	refused(id("Zephyr Landing"), "NoPath") -- a nation at peace
	T.expect((Commands.apply(state, AURORA, { kind = "Land", fleet = fleet.id, province = id("Aurora Fields") })))
end)

T.test("men stay aboard if peace closes the coast before the fleet arrives", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Reach")].owner = ZEPHYR -- Zephyr borders Aurora now
	state.provinces[id("Cinder Rock")].owner = AURORA
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local fleet = Navy.spawn(state, AURORA, VEGA, 1)
	Navy.setCargo(fleet, { Infantry = 1000 })
	local target = id("Zephyr Landing")
	T.expect((Commands.apply(state, AURORA, { kind = "Land", fleet = fleet.id, province = target })))
	state.wars = {}
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(fleet.men, 1000)
	T.equal(fleet.landAt, nil)
	T.equal(#events(state, "Landed"), 0)
end)

-- Sea battles -------------------------------------------------------------------------------------------------------

T.test("hostile fleets fight three rounds; the loser retreats to the nearest zone off a friendly coast", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Feather Reach")].owner = ZEPHYR -- a Zephyr coast on Orion Span
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local strong = Navy.spawn(state, AURORA, LYRA, 3)
	local weak = Navy.spawn(state, ZEPHYR, LYRA, 2)
	Navy.setCargo(weak, { Infantry = 1000 })
	Tick.advance(state, rng)
	T.expect(strong.inBattle and weak.inBattle and state.seaBattles[LYRA] ~= nil, "a battle at sea")
	local ok, err = Commands.apply(state, AURORA, { kind = "Sail", fleet = strong.id, zone = VEGA })
	T.expect(not ok)
	T.equal(err, "InBattle")
	run(state, rng, Config.Battle.Rounds - 1)
	T.equal(state.seaBattles[LYRA], nil)
	T.expect(strong.hull < 3000 and Navy.ships(strong) == 3, "the winner took damage")
	T.expect(weak.retreating == true, "the loser retreats")
	T.equal(weak.path[#weak.path], ORION, "to the nearest zone off a Zephyr coast")
	T.equal(weak.men, 1000, "with its men aboard")
	T.equal(state.nations[AURORA].battlesWon, 1)
	local battles = events(state, "SeaBattle")
	T.equal(#battles, 1)
	T.equal(battles[1].a, AURORA)
	T.equal(battles[1].zone, LYRA)
	-- a retreating fleet takes no orders and fights nobody on the way
	local ok2, err2 = Commands.apply(state, ZEPHYR, { kind = "Sail", fleet = weak.id, zone = LYRA })
	T.expect(not ok2)
	T.equal(err2, "Retreating")
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(weak.zone, ORION)
	T.equal(weak.retreating, nil)
end)

T.test("an insult's grudge and high spirits count at sea too", function()
	local state = fresh()
	warPhase(state)
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	state.provinces[id("Cinder Rock")].owner = AURORA
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local mine = Navy.spawn(state, AURORA, LYRA, 2)
	local theirs = Navy.spawn(state, ZEPHYR, LYRA, 2)
	local sides = assert(Navy.sides(state, { mine, theirs }))
	T.equal(sides.defenderOwner, AURORA)
	local before = Navy.modifier(state, sides, true, 0)
	local attackBefore = Navy.modifier(state, sides, false, 0)
	local insult = { kind = "Diplomacy", action = "Insult", target = AURORA, gold = 0 } :: Types.Command
	T.expect((Commands.apply(state, ZEPHYR, insult)))
	T.near(Navy.modifier(state, sides, true, 0), before + Config.Diplomacy.GrudgeBonus, 1e-9, "the insulted fleet")
	T.near(Navy.modifier(state, sides, false, 0), attackBefore, 1e-9, "the insulter's gets nothing")
	local laugh = { kind = "Diplomacy", action = "LaughOff", target = ZEPHYR, gold = 0 } :: Types.Command
	T.expect((Commands.apply(state, AURORA, laugh)))
	T.near(Navy.modifier(state, sides, true, 0), before + Config.Diplomacy.LaughBonus, 1e-9, "high spirits")
end)

T.test("a beaten fleet with no friendly coast to reach sinks, and everyone aboard with it", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	state.provinces[id("Cinder Rock")].owner = AURORA
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	-- in Zephyr's own zone the only Zephyr coasts are there, so it has nowhere else to go
	Navy.spawn(state, AURORA, LYRA, 3)
	local weak = Navy.spawn(state, ZEPHYR, LYRA, 2)
	Navy.setCargo(weak, { Infantry = 2000 })
	run(state, rng, Config.Battle.Rounds)
	T.equal(state.fleets[weak.id], nil)
	T.equal(Economy.regiments(state, ZEPHYR), 0)
	-- and a fleet left under MinHull sinks even with a coast to go to
	local tiny = Navy.spawn(state, ZEPHYR, VEGA, 1)
	tiny.hull = Config.Navy.MinHull - 1
	Navy.spawn(state, AURORA, VEGA, 1)
	run(state, rng, Config.Battle.Rounds)
	T.equal(state.fleets[tiny.id], nil)
end)

T.test("fleets of nations at peace share a zone without fighting", function()
	local state, rng = fresh()
	warPhase(state)
	local a = Navy.spawn(state, AURORA, LYRA, 2)
	local z = Navy.spawn(state, ZEPHYR, LYRA, 2)
	run(state, rng, Config.Battle.Rounds)
	T.expect(not a.inBattle and not z.inBattle and a.hull == 2000 and z.hull == 2000)
end)

-- Straits ---------------------------------------------------------------------------------------------------------

T.test("an enemy fleet in a strait's zone closes the strait to your armies", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	state.provinces[id("Cinder Rock")].owner = AURORA
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local gate, approach = id("Aurora Gate"), id("Aurora Approach")
	T.expect(Pathing.find(state, AURORA, gate, approach) ~= nil, "the Gate bridge is open")
	-- an army already on the bridge stops when the enemy fleet arrives
	local army = Army.spawn(state, AURORA, gate, 3000)
	T.expect((Commands.apply(state, AURORA, { kind = "Move", army = army.id, to = approach })))
	run(state, rng, 2)
	local enemy = Navy.spawn(state, ZEPHYR, VEGA, 1)
	run(state, rng, 1)
	T.equal(#army.path, 0, "stopped at the bridge")
	T.equal(army.location, gate)
	T.equal(Pathing.find(state, AURORA, gate, approach), nil, "every Aurora bridge is in Vega Drift: sealed")
	local ok, err = Commands.apply(state, AURORA, { kind = "Move", army = army.id, to = approach })
	T.expect(not ok)
	T.equal(err, "NoPath")
	-- other nations' armies cross: the fleet blocks only its enemies
	T.expect(Diplomacy.crossable(state, Diplomacy.blockedZones(state, NIMBUS), gate, approach))
	-- nor does a retreating fleet block anyone
	enemy.retreating = true
	T.expect(Pathing.find(state, AURORA, gate, approach) ~= nil)
end)

-- Blockades ---------------------------------------------------------------------------------------------------------

T.test("an enemy fleet off your coast blockades it: less gold, no ships, faster sieges for the blockader", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	state.provinces[id("Cinder Rock")].owner = AURORA
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local before = Economy.monthlyIncome(state, AURORA).gold
	local enemy = Navy.spawn(state, ZEPHYR, VEGA, 1)
	Tick.advance(state, rng)
	local landing = id("Aurora Landing")
	T.equal(state.provinces[landing].blockade, ZEPHYR)
	T.equal(state.provinces[id("Zephyr Landing")].blockade, nil, "not its own coast")
	local blockades = events(state, "Blockade")
	T.equal(#blockades, 1, "one event for the whole coast")
	T.equal(blockades[1].a, ZEPHYR)
	T.equal(blockades[1].b, AURORA)
	T.equal(blockades[1].zone, VEGA)
	table.clear(state.events) -- (the server sends a tick's events once, then clears them)
	Tick.advance(state, rng)
	T.equal(#events(state, "Blockade"), 0, "only when it starts")
	local after = Economy.monthlyIncome(state, AURORA).gold
	T.expect(after < before, string.format("blockaded provinces earn less gold (%.1f -> %.1f)", before, after))
	local ok, err = Commands.apply(state, AURORA, { kind = "BuildShips", province = landing, ships = 1 })
	T.expect(not ok)
	T.equal(err, "Blockaded")
	-- a siege by the blockader's side runs faster
	local fields = id("Aurora Fields")
	local besieger = Army.spawn(state, ZEPHYR, fields, 2000)
	Tick.advance(state, rng)
	local siege = state.provinces[fields].siege
	T.expect(siege ~= nil and siege.by == ZEPHYR, "Zephyr besieges")
	T.near((siege :: any).progress, Config.Navy.BlockadeSiegeSpeed, 1e-9, "progress per tick")
	T.expect(besieger.men == 2000)
	-- an Aurora fleet in the zone breaks the blockade (they fight, but the coast is guarded)
	Navy.spawn(state, AURORA, VEGA, 1)
	Tick.advance(state, rng)
	T.equal(state.provinces[landing].blockade, nil)
	T.expect(enemy.inBattle)
	T.equal(
		Siege.required(state.provinces[fields]),
		Config.Siege.TicksPerDevelopment * state.provinces[fields].development
	)
end)

-- War across the sea ------------------------------------------------------------------------------------------------

T.test("nations sharing a sea zone may declare war without a land border", function()
	local earth = Maps.get("earth")
	local state = Match.new(earth)
	warPhase(state)
	local RHINE, MISSISSIPPI = 1, 9
	T.equal(state.nations[RHINE].name, "Rhine")
	T.equal(state.nations[MISSISSIPPI].name, "Mississippi")
	T.expect(not Diplomacy.borders(state, MISSISSIPPI, RHINE), "an ocean apart")
	T.expect(Diplomacy.sharesSea(state, MISSISSIPPI, RHINE), "both hold North Atlantic coasts")
	T.expect((Diplomacy.declareWar(state, MISSISSIPPI, RHINE)))
	-- on Skyshards Aurora and Halo share neither land nor a space zone
	local sky = fresh()
	warPhase(sky)
	local ok, err = Diplomacy.declareWar(sky, AURORA, HALO)
	T.expect(not ok)
	T.equal(err, "NoBorder")
end)

-- Upkeep and elimination --------------------------------------------------------------------------------------------

T.test("ships and the men aboard cost upkeep", function()
	local state = fresh()
	for armyId, a in state.armies do
		if a.owner == AURORA then
			state.armies[armyId] = nil
		end
	end
	T.equal(Economy.upkeep(state, AURORA), 0)
	local fleet = Navy.spawn(state, AURORA, VEGA, 2)
	T.near(Economy.upkeep(state, AURORA), 2 * Config.Navy.ShipUpkeep, 1e-9)
	Navy.setCargo(fleet, { Infantry = 1000 })
	T.near(Economy.upkeep(state, AURORA), 2 * Config.Navy.ShipUpkeep + Config.Troops.Infantry.upkeep, 1e-9)
	-- an Upkeep race pays less for the men aboard, not for the ships
	state.nations[AURORA].race = "Robots"
	T.equal(Config.Races.Robots.passive, "Upkeep")
	local discount = Config.Races.Robots.upkeepMultiplier :: number
	T.near(Economy.upkeep(state, AURORA), 2 * Config.Navy.ShipUpkeep + Config.Troops.Infantry.upkeep * discount, 1e-9)
	-- a damaged fleet pays for what is left of its hull
	fleet.hull = 1500
	T.near(Economy.upkeep(state, AURORA), 1.5 * Config.Navy.ShipUpkeep + Config.Troops.Infantry.upkeep * discount, 1e-9)
end)

T.test("an eliminated nation's fleets go with it", function()
	local state = fresh()
	local fleet = Navy.spawn(state, ZEPHYR, LYRA, 2)
	Navy.setCargo(fleet, { Infantry = 2000 })
	Navy.spawn(state, AURORA, VEGA, 1)
	Primordial.eliminate(state, ZEPHYR)
	T.equal(state.fleets[fleet.id], nil)
	T.equal(#fleetsOf(state, AURORA), 1)
end)

T.test("a whole crossing through the tick loop: build, board, sail, land, take the province", function()
	local state, rng = fresh()
	local rock, reach = id("Cinder Rock"), id("Cinder Reach")
	clearArmies(state, { rock, reach })
	local nation = state.nations[AURORA]
	nation.gold = 500
	local army = Army.spawn(state, AURORA, id("Aurora Windward"), 2000)
	T.expect((Commands.apply(state, AURORA, { kind = "BuildShips", province = id("Aurora Windward"), ships = 2 })))
	local fleet = fleetsOf(state, AURORA)[1]
	T.expect((Commands.apply(state, AURORA, { kind = "Embark", army = army.id, fleet = fleet.id })))
	Tick.advance(state, rng)
	T.equal(fleet.men, 2000)
	T.expect((Commands.apply(state, AURORA, { kind = "Land", fleet = fleet.id, province = reach })))
	run(state, rng, Config.Navy.MoveTicks)
	T.equal(fleet.zone, LYRA)
	T.equal(fleet.men, 0)
	run(state, rng, Siege.required(state.provinces[reach]) + 2)
	T.equal(state.provinces[reach].owner, AURORA, "the landed army took Cinder Reach")
end)

T.finish()
