--!strict
-- Phase 2 rules on Skyshards: paths, movement, battles, retreats, sieges, diplomacy and win conditions.
local Army = require("../src/shared/Sim/Army")
local Battle = require("../src/shared/Sim/Battle")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Movement = require("../src/shared/Sim/Movement")
local Pathing = require("../src/shared/Sim/Pathing")
local Rng = require("../src/shared/Sim/Rng")
local Siege = require("../src/shared/Sim/Siege")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Victory = require("../src/shared/Sim/Victory")

Config.Battle.RandomSpread = 0 -- deterministic battles in this file

local map = Maps.get("skyshards")
local byName: { [string]: number } = {}
for _, p in map.provinces do
	byName[p.name] = p.id
end
local function id(name: string): number
	return assert(byName[name], "no province " .. name)
end

local AURORA, ZEPHYR, NIMBUS, TEMPEST = 1, 2, 3, 4

local function fresh()
	local state = Match.new(map)
	return state, Rng.new(1)
end

local function garrisonAt(state, provinceId: number)
	for _, a in state.armies do
		if a.location == provinceId and a.owner == 0 then
			return a
		end
	end
	return nil
end

local function run(state, rng, ticks: number)
	for _ = 1, ticks do
		Tick.advance(state, rng)
	end
end

local function warPhase(state)
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
end

-- Paths and movement ------------------------------------------------------------------------------

T.test("paths follow neighbours and straits, and never cross mountains", function()
	local state = fresh()
	local path = Pathing.find(state, AURORA, id("Aurora Landing"), id("Cinder Rock"))
	assert(path, "no path")
	T.equal(path[#path], id("Cinder Rock"))
	for _, p in path do
		T.expect(state.provinces[p].terrain ~= "Mountain", "path crosses a mountain")
	end
	T.equal(Pathing.find(state, AURORA, id("Aurora Landing"), id("Aurora Spire")), nil, "mountains are unreachable")
	T.equal(#(Pathing.find(state, AURORA, id("Aurora Landing"), id("Aurora Landing")) :: { number }), 0)
end)

T.test("peaceful foreign land is closed until war", function()
	local state = fresh()
	T.equal(Pathing.find(state, AURORA, id("Aurora Landing"), id("Zephyr Landing")), nil)
	warPhase(state)
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)) == false, "Aurora doesn't border Zephyr yet")
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = AURORA
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)), "war once they border")
	T.expect(Pathing.find(state, AURORA, id("Aurora Landing"), id("Zephyr Landing")) ~= nil)
end)

T.test("an army steps into plains in 5 ticks and into hills in 8", function()
	local state, rng = fresh()
	local windward = id("Aurora Windward") -- hills
	local army = Army.spawn(state, AURORA, id("Aurora Meadows"), 3000)
	T.expect((Commands.apply(state, AURORA, { kind = "Move", army = army.id, to = windward })))
	T.equal(Pathing.moveTicks(state.provinces[windward].terrain), Config.Army.MoveTicks.Hills)
	run(state, rng, Config.Army.MoveTicks.Hills - 1)
	T.equal(army.location, id("Aurora Meadows"))
	run(state, rng, 1)
	T.equal(army.location, windward)
	T.equal(#army.path, 0)
end)

T.test("orders: only your own armies, not mid-battle, and ordering it home stops it", function()
	local state = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Landing"), 3000)
	local ok, err = Commands.apply(state, ZEPHYR, { kind = "Move", army = army.id, to = id("Aurora Fields") })
	T.expect(not ok)
	T.equal(err, "NotYourArmy")
	T.expect((Commands.apply(state, AURORA, { kind = "Move", army = army.id, to = id("Aurora Fields") })))
	T.expect(#army.path > 0)
	T.expect((Commands.apply(state, AURORA, { kind = "Move", army = army.id, to = id("Aurora Landing") })))
	T.equal(#army.path, 0)
	army.inBattle = true
	local ok2, err2 = Commands.apply(state, AURORA, { kind = "Move", army = army.id, to = id("Aurora Fields") })
	T.expect(not ok2)
	T.equal(err2, "InBattle")
end)

-- Battles -----------------------------------------------------------------------------------------

T.test("an army beats a garrison in three rounds and the garrison is gone", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock")
	local garrison = assert(garrisonAt(state, rock))
	T.equal(garrison.men, Config.NeutralGarrison)
	local army = Army.spawn(state, AURORA, rock, 4000)
	run(state, rng, 1)
	T.expect(army.inBattle and state.battles[rock] ~= nil, "battle started")
	run(state, rng, Config.Battle.Rounds - 1)
	T.equal(state.armies[garrison.id], nil, "garrison destroyed (nowhere to retreat)")
	T.expect(state.armies[army.id] ~= nil and army.men < 4000, "attacker took losses but survived")
	T.equal(state.nations[AURORA].battlesWon, 1)
	T.equal(state.battles[rock], nil)
end)

T.test("a round kills 15% of the enemy's strength, more for a defender in hills", function()
	local state = fresh()
	local hills = id("Aurora Windward")
	state.provinces[hills].owner = nil
	local g = Army.spawn(state, 0, hills, 2000)
	local a = Army.spawn(state, AURORA, hills, 2000)
	local sides = assert(Battle.sides(state, hills, { g, a }))
	T.equal(sides.defenderOwner, 0)
	T.near(Battle.modifier(state, hills, sides, true, 0), 1 + Config.Battle.TerrainDefenceBonus, 1e-9)
	T.near(Battle.modifier(state, hills, sides, false, 0), 1, 1e-9)
	state.provinces[hills].building = "Fort"
	state.provinces[hills].owner = AURORA
	local sides2 = assert(Battle.sides(state, hills, { a, g }))
	T.equal(sides2.defenderOwner, AURORA, "the owner's army defends its province")
	T.near(
		Battle.modifier(state, hills, sides2, true, 0),
		1 + Config.Battle.TerrainDefenceBonus + Config.Buildings.Fort.defenceBonus,
		1e-9
	)
end)

T.test("the loser retreats to its nearest province; tiny armies are destroyed", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local field = id("Cinder Reach")
	local strong = Army.spawn(state, ZEPHYR, field, 6000)
	local weak = Army.spawn(state, AURORA, field, 3000)
	run(state, rng, Config.Battle.Rounds)
	T.expect(state.armies[strong.id] ~= nil, "winner stays")
	T.expect(state.armies[weak.id] ~= nil, "loser survives the retreat")
	T.equal(weak.location, id("Cinder Rock"), "loser fell back to its nearest owned province")
	T.equal(state.nations[ZEPHYR].battlesWon, 1)

	-- a 400-man army that loses is simply destroyed
	local tiny = Army.spawn(state, AURORA, field, 400)
	run(state, rng, Config.Battle.Rounds)
	T.equal(state.armies[tiny.id], nil)
end)

T.test("allies and nations at peace share provinces without fighting", function()
	local state, rng = fresh()
	local p = id("Aurora Fields")
	Army.spawn(state, AURORA, p, 2000)
	Army.spawn(state, ZEPHYR, p, 2000)
	run(state, rng, 2)
	T.equal(state.battles[p], nil)
end)

-- Sieges ------------------------------------------------------------------------------------------

T.test("after the garrison falls, a siege takes 10 s per development and flips the province", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock")
	local army = Army.spawn(state, AURORA, rock, 5000)
	run(state, rng, Config.Battle.Rounds) -- clear the garrison
	local required = Siege.required(state.provinces[rock])
	T.equal(required, Config.Siege.TicksPerDevelopment * state.provinces[rock].development)
	-- the siege starts the same tick the garrison falls
	local started = assert(state.provinces[rock].siege, "siege started").progress
	run(state, rng, required - started - 1)
	T.equal(state.provinces[rock].owner, nil)
	T.expect(state.provinces[rock].siege ~= nil, "siege in progress")
	run(state, rng, 1)
	T.equal(state.provinces[rock].owner, AURORA)
	T.equal(state.provinces[rock].siege, nil)
	T.expect(state.armies[army.id] ~= nil)
	local taken = false
	for _, e in state.events do
		taken = taken or (e.kind == "ProvinceTaken" and e.province == rock and e.a == AURORA)
	end
	T.expect(taken, "ProvinceTaken event")
end)

T.test("forts double and capitals triple siege time", function()
	local state = fresh()
	local p = state.provinces[id("Zephyr Landing")]
	local base = Config.Siege.TicksPerDevelopment * p.development
	T.equal(Siege.required(p), base * Config.Siege.CapitalMultiplier)
	p.building = "Fort"
	T.equal(Siege.required(p), base * Config.Siege.CapitalMultiplier * Config.Buildings.Fort.siegeMultiplier)
end)

T.test("defenders at home stop a siege, and leaving resets it", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock")
	state.armies[assert(garrisonAt(state, rock)).id] = nil
	local army = Army.spawn(state, AURORA, rock, 3000)
	run(state, rng, 3)
	T.expect(state.provinces[rock].siege ~= nil)
	assert(Movement.order(state, AURORA, army.id, id("Aurora Windward")))
	run(state, rng, Config.Army.MoveTicks.Hills)
	T.equal(state.provinces[rock].siege, nil, "siege reset when the army left")
end)

-- Diplomacy ---------------------------------------------------------------------------------------

T.test("no wars in the Peace phase", function()
	local state = fresh()
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	local ok, err = Commands.apply(state, AURORA, { kind = "Diplomacy", action = "War", target = ZEPHYR, gold = 0 })
	T.expect(not ok)
	T.equal(err, "PeaceTime")
end)

T.test("alliances: offer, accept, at most three, and allies join wars", function()
	local state, rng = fresh()
	T.expect((Diplomacy.propose(state, "Ally", AURORA, NIMBUS, 0)))
	T.expect((Diplomacy.accept(state, "Ally", NIMBUS, AURORA)))
	T.expect(Diplomacy.allied(state, AURORA, NIMBUS))
	T.expect((Diplomacy.propose(state, "Ally", TEMPEST, AURORA, 0)))
	T.expect((Diplomacy.accept(state, "Ally", AURORA, TEMPEST)))
	T.equal(#state.alliances[state.nations[AURORA].allianceId :: number].members, 3)
	T.expect((Diplomacy.propose(state, "Ally", 5, AURORA, 0)))
	local ok, err = Diplomacy.accept(state, "Ally", AURORA, 5)
	T.expect(not ok)
	T.equal(err, "AllianceFull")

	warPhase(state)
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	T.expect((Diplomacy.declareWar(state, ZEPHYR, AURORA)))
	T.expect(Diplomacy.atWar(state, ZEPHYR, NIMBUS), "Aurora's ally joined the defence")
	T.expect(Diplomacy.atWar(state, ZEPHYR, TEMPEST))
	run(state, rng, 1)
end)

T.test("peace with tribute pays gold, ends the war and starts a truce", function()
	local state = fresh()
	warPhase(state)
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	state.nations[AURORA].gold = 200
	state.nations[ZEPHYR].gold = 0
	local ok, err = Commands.apply(state, AURORA, { kind = "Diplomacy", action = "Peace", target = ZEPHYR, gold = 50 })
	T.expect(ok, err)
	T.expect((Commands.apply(state, ZEPHYR, { kind = "Diplomacy", action = "AcceptPeace", target = AURORA, gold = 0 })))
	T.expect(not Diplomacy.atWar(state, AURORA, ZEPHYR))
	T.equal(state.nations[AURORA].gold, 150)
	T.equal(state.nations[ZEPHYR].gold, 50)
	T.expect(Diplomacy.hasTruce(state, AURORA, ZEPHYR))
	local ok2, err2 = Diplomacy.declareWar(state, AURORA, ZEPHYR)
	T.expect(not ok2)
	T.equal(err2, "Truce")
	state.tick += Config.Diplomacy.TruceTicks
	T.expect(not Diplomacy.hasTruce(state, AURORA, ZEPHYR), "truces run out")
end)

T.test("offers expire", function()
	local state, rng = fresh()
	T.expect((Diplomacy.propose(state, "Ally", AURORA, ZEPHYR, 0)))
	run(state, rng, Config.Diplomacy.OfferTicks)
	local ok, err = Diplomacy.accept(state, "Ally", ZEPHYR, AURORA)
	T.expect(not ok)
	T.equal(err, "NoOffer")
end)

-- Win conditions ----------------------------------------------------------------------------------

T.test("holding 40% of all provinces wins on the spot", function()
	local state, rng = fresh()
	local need = math.ceil(Config.Win.DominationShare * #map.provinces)
	local given = 0
	for _, p in state.provinces do
		if given < need and p.terrain ~= "Mountain" then
			p.owner = AURORA
			given += 1
		end
	end
	run(state, rng, 1)
	local result = assert(state.result)
	T.equal(result.kind, "Domination")
	T.equal(result.winners[1], AURORA)
	T.equal(state.phase, "Results")
	local tick = state.tick
	run(state, rng, 5)
	T.equal(state.tick, tick + 5)
	T.equal(state.phase, "Results", "the world stands still in Results")
end)

T.test("an alliance holding 55% together wins together", function()
	local state, rng = fresh()
	assert(Diplomacy.propose(state, "Ally", AURORA, ZEPHYR, 0))
	assert(Diplomacy.accept(state, "Ally", ZEPHYR, AURORA))
	local need = math.ceil(Config.Win.AllianceShare * #map.provinces)
	local given = 0
	for _, p in state.provinces do
		if given < need and p.terrain ~= "Mountain" then
			p.owner = if given % 2 == 0 then AURORA else ZEPHYR
			given += 1
		end
	end
	run(state, rng, 1)
	local result = assert(state.result)
	T.equal(result.kind, "Alliance")
	T.equal(#result.winners, 2)
end)

T.test("score = provinces × 10 + development × 5 + battles won × 2, best score wins at the end", function()
	local state, rng = fresh()
	state.nations[ZEPHYR].battlesWon = 3
	T.equal(Victory.score(state, ZEPHYR), 8 * 10 + 17 * 5 + 3 * 2)
	state.tick = Config.Phases.MatchEndTick - 1
	run(state, rng, 1)
	local result = assert(state.result)
	T.equal(result.kind, "Score")
	T.equal(result.winners[1], ZEPHYR)
	T.equal(result.scores[1].nation, ZEPHYR)
end)

-- Network -----------------------------------------------------------------------------------------

T.test("moving armies report progress for the client to interpolate", function()
	local state, rng = fresh()
	local army = Army.spawn(state, AURORA, id("Aurora Meadows"), 2000)
	assert(Movement.order(state, AURORA, army.id, id("Aurora Windward")))
	run(state, rng, 4)
	local positions = Snapshot.positions(state, function(p)
		return Pathing.moveTicks(state.provinces[p].terrain)
	end)
	T.equal(#positions, 1)
	T.equal(positions[1].to, id("Aurora Windward"))
	T.near(positions[1].progress, 4 / Config.Army.MoveTicks.Hills, 1e-9)
end)

T.finish()
