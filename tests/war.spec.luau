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

T.test("the loser walks back to its nearest province; tiny armies are destroyed", function()
	local state, rng = fresh()
	warPhase(state)
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local field = id("Cinder Reach")
	for _, a in state.armies do
		state.armies[a.id] = nil -- no garrisons in the way
	end
	local strong = Army.spawn(state, ZEPHYR, field, 5000)
	local weak = Army.spawn(state, AURORA, field, 3000)
	run(state, rng, Config.Battle.Rounds)
	T.expect(state.armies[strong.id] ~= nil, "winner stays")
	T.expect(state.armies[weak.id] ~= nil, "loser survives the retreat")
	T.equal(state.nations[ZEPHYR].battlesWon, 1)
	-- no teleport: it is still on the field, walking home, and takes no orders
	T.equal(weak.location, field)
	T.expect(weak.retreating == true, "retreating")
	T.equal(weak.path[#weak.path], id("Cinder Rock"), "heading for its nearest owned province")
	local ok, err = Commands.apply(state, AURORA, { kind = "Move", army = weak.id, to = field })
	T.expect(not ok)
	T.equal(err, "Retreating")
	-- it doesn't fight the winner standing beside it, and arrives at normal speed
	local men = weak.men
	run(state, rng, Movement.ticksToNext(state, weak) - 1)
	T.equal(state.battles[field], nil, "no new battle with a retreating army")
	T.equal(weak.men, men)
	T.equal(weak.location, field)
	run(state, rng, 1)
	T.equal(weak.location, id("Cinder Rock"))
	T.equal(weak.retreating, nil, "home: a normal army again")
	T.expect((Commands.apply(state, AURORA, { kind = "Move", army = weak.id, to = field })), "orders work again")

	-- a 400-man army that loses is simply destroyed
	local tiny = Army.spawn(state, AURORA, field, 400)
	run(state, rng, Config.Battle.Rounds)
	T.equal(state.armies[tiny.id], nil)
end)

T.test("a retreating army walks past enemies and doesn't block a siege of its own province", function()
	local state, rng = fresh()
	warPhase(state)
	local rock, reach = id("Cinder Rock"), id("Cinder Reach")
	state.provinces[rock].owner = AURORA
	state.provinces[reach].owner = ZEPHYR
	T.expect((Diplomacy.declareWar(state, AURORA, ZEPHYR)))
	local g = garrisonAt(state, rock)
	if g then
		state.armies[g.id] = nil
	end
	local besieger = Army.spawn(state, ZEPHYR, rock, 2000)
	local runner = Army.spawn(state, AURORA, rock, 3000)
	runner.retreating = true
	runner.path = { id("Aurora Windward") }
	run(state, rng, 1)
	T.equal(state.battles[rock], nil, "no battle")
	local siege = assert(state.provinces[rock].siege, "the siege goes on")
	T.equal(siege.by, ZEPHYR)
	T.expect(state.armies[besieger.id] ~= nil and state.armies[runner.id] ~= nil)
end)

T.test("a beaten army with no way home is destroyed", function()
	local state, rng = fresh()
	warPhase(state)
	local rock = id("Cinder Rock")
	state.provinces[rock].owner = ZEPHYR
	state.wars[1] = { id = 1, attackers = { AURORA }, defenders = { ZEPHYR }, startedAt = state.tick }
	-- Aurora holds nothing it can walk to
	for _, p in state.provinces do
		if p.owner == AURORA then
			p.owner = NIMBUS
		end
	end
	local g = garrisonAt(state, rock)
	if g then
		state.armies[g.id] = nil
	end
	Army.spawn(state, ZEPHYR, rock, 6000)
	local lost = Army.spawn(state, AURORA, rock, 3000)
	run(state, rng, Config.Battle.Rounds)
	T.equal(state.armies[lost.id], nil)
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

T.test("an interrupted siege keeps its progress for a grace period, then resets", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock")
	state.armies[assert(garrisonAt(state, rock)).id] = nil
	local army = Army.spawn(state, AURORA, rock, 3000)
	run(state, rng, 3)
	local siege = assert(state.provinces[rock].siege)
	T.equal(siege.progress, 3)
	-- step out and back: the progress waits
	assert(Movement.order(state, AURORA, army.id, id("Aurora Windward")))
	run(state, rng, 2)
	assert(Movement.order(state, AURORA, army.id, rock))
	T.equal(state.provinces[rock].siege, siege, "kept while away")
	T.equal(siege.progress, 3, "no progress while away")
	run(state, rng, 1)
	T.equal(siege.progress, 4, "it picks up where it stopped")
	-- gone for longer than the grace period: progress is lost
	assert(Movement.order(state, AURORA, army.id, id("Aurora Windward")))
	run(state, rng, Config.Siege.GraceTicks)
	T.expect(state.provinces[rock].siege ~= nil, "still kept on the last grace tick")
	run(state, rng, 1)
	T.equal(state.provinces[rock].siege, nil, "siege reset after the grace period")
end)

T.test("a defender stops a siege; once it is beaten, the siege resumes where it was", function()
	local state, rng = fresh()
	warPhase(state)
	local rock = id("Cinder Rock")
	state.provinces[rock].owner = ZEPHYR
	state.provinces[rock].development = 3
	state.wars[1] = { id = 1, attackers = { AURORA }, defenders = { ZEPHYR }, startedAt = state.tick }
	local g = garrisonAt(state, rock)
	if g then
		state.armies[g.id] = nil
	end
	Army.spawn(state, AURORA, rock, 3000)
	run(state, rng, 5)
	local siege = assert(state.provinces[rock].siege)
	local before = siege.progress
	local relief = Army.spawn(state, ZEPHYR, rock, 1000)
	run(state, rng, Config.Battle.Rounds - 1)
	T.equal(siege.progress, before, "no progress during the battle")
	run(state, rng, 1) -- the battle ends this tick and the relief army walks away
	local r = state.armies[relief.id]
	T.expect(r == nil or r.retreating == true, "relief beaten")
	T.equal(state.provinces[rock].siege, siege, "progress kept through the battle")
	T.equal(siege.progress, before + 1)
end)

T.test("rival besiegers at peace: the first keeps the siege, the second waits instead of blocking", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock")
	state.armies[assert(garrisonAt(state, rock)).id] = nil
	Army.spawn(state, AURORA, rock, 1000)
	run(state, rng, 2)
	local siege = assert(state.provinces[rock].siege)
	T.equal(siege.by, AURORA)
	-- Zephyr (at peace with Aurora: it's the Peace phase) arrives with a bigger army: no deadlock, no fight
	local rival = Army.spawn(state, ZEPHYR, rock, 5000)
	run(state, rng, siege.required - 2)
	T.equal(state.provinces[rock].owner, AURORA, "the first besieger finished its siege")
	T.expect(state.armies[rival.id] ~= nil)
	T.equal(state.battles[rock], nil)
end)

T.test("rival besiegers: when the first one leaves, the other takes over from zero", function()
	local state, rng = fresh()
	local rock = id("Cinder Rock")
	state.armies[assert(garrisonAt(state, rock)).id] = nil
	local first = Army.spawn(state, AURORA, rock, 1000)
	Army.spawn(state, ZEPHYR, rock, 1000)
	run(state, rng, 3)
	T.equal(assert(state.provinces[rock].siege).by, AURORA, "the lower army id started first")
	assert(Movement.order(state, AURORA, first.id, id("Aurora Windward")))
	run(state, rng, 1)
	local siege = assert(state.provinces[rock].siege)
	T.equal(siege.by, ZEPHYR)
	T.equal(siege.progress, 1)
end)

T.test("a nation's armies standing in the same province merge into one", function()
	local state, rng = fresh()
	local home = id("Aurora Landing")
	local a = Army.spawn(state, AURORA, home, 2000)
	local b = Army.spawn(state, AURORA, home, 3000)
	local walker = Army.spawn(state, AURORA, id("Aurora Meadows"), 1000)
	local guest = Army.spawn(state, ZEPHYR, home, 1000)
	assert(Movement.order(state, AURORA, walker.id, home))
	run(state, rng, 1)
	T.equal(state.armies[b.id], nil, "the higher id joined the lower")
	T.equal(a.men, 5000)
	T.expect(state.armies[walker.id] ~= nil, "a moving army stays apart")
	T.expect(state.armies[guest.id] ~= nil, "other nations' armies stay apart")
	for _ = 1, 60 do
		if state.armies[walker.id] == nil then
			break
		end
		run(state, rng, 1)
	end
	T.equal(state.armies[walker.id], nil, "it merges on arrival")
	T.equal(a.men, 6000)
end)

T.test("an order or a power for an army that just merged reaches the stack it joined", function()
	local state, rng = fresh()
	local home = id("Aurora Landing")
	local a = Army.spawn(state, AURORA, home, 2000)
	local b = Army.spawn(state, AURORA, home, 3000)
	table.clear(state.events)
	Movement.mergeStacks(state)
	T.equal(state.armies[b.id], nil, "b merged into a")
	T.equal(state.mergedInto[b.id], a.id)
	local event = state.events[#state.events]
	T.expect(event.kind == "Merged" and event.a == a.id and event.b == b.id, "a Merged event tells clients")
	T.equal(event.province, home)
	T.equal(Army.resolve(state, b.id), a.id)
	T.equal(Army.resolve(state, 9999), 9999, "an id that never merged stays as it is")
	-- the player's Go for b, sent before they saw the merge, moves the whole stack
	T.expect(Commands.apply(state, AURORA, { kind = "Move", army = b.id, to = id("Aurora Meadows") }), "Go for b")
	T.equal(a.path[#a.path], id("Aurora Meadows"))
	-- a Meteor aimed at b hits a
	state.tick = Config.Phases.PeaceEndTick + 10
	state.phase = "War"
	state.nations[ZEPHYR].charges = 5
	local ok, err = Commands.apply(state, ZEPHYR, { kind = "Power", power = "Meteor", target = b.id })
	T.expect(ok, "Meteor on the merged id: " .. tostring(err))
	T.expect(a.men < 5000, "it hit the stack")
	run(state, rng, 1)
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

local function ownable(): number
	local n = 0
	for _, p in map.provinces do
		if p.terrain ~= "Mountain" then
			n += 1
		end
	end
	return n
end

T.test("holding DominationShare of the ownable provinces wins on the spot", function()
	local state, rng = fresh()
	local need = math.ceil(Config.Win.DominationShare * ownable())
	T.expect(need < Config.Win.DominationShare * #map.provinces, "mountains don't count")
	local short = 0
	for _, p in state.provinces do
		if short < need - 1 and p.terrain ~= "Mountain" then
			p.owner = AURORA
			short += 1
		elseif p.owner == AURORA then
			p.owner = nil
		end
	end
	run(state, rng, 1)
	T.equal(state.result, nil, "one province short")
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

T.test("an alliance holding AllianceShare together wins together", function()
	local state, rng = fresh()
	assert(Diplomacy.propose(state, "Ally", AURORA, ZEPHYR, 0))
	assert(Diplomacy.accept(state, "Ally", ZEPHYR, AURORA))
	local need = math.ceil(Config.Win.AllianceShare * ownable())
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
