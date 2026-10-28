--!strict
-- The singleplayer sandbox (docs/DESIGN.md "Sandbox"): a world that never ends, free powers with no immunity,
-- taking over any nation, the time controls, the disasters switch, no rewards, and what clients and analytics see.
local Army = require("../src/shared/Sim/Army")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Primordial = require("../src/shared/Sim/Primordial")
local Progression = require("../src/shared/Sim/Progression")
local Rng = require("../src/shared/Sim/Rng")
local Sandbox = require("../src/shared/Sim/Sandbox")
local Settings = require("../src/shared/Sim/Settings")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Telemetry = require("../src/shared/Sim/Telemetry")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

local ME, OTHER = 3003, 3004
local A, B = 1, 2

local function world(): Types.MatchState
	return Sandbox.new(Maps.get("skyshards"))
end

local function owned(state: Types.MatchState, nationId: number): { number }
	local out = {}
	for id, p in state.provinces do
		if p.owner == nationId then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

local function mountain(state: Types.MatchState): number?
	for id, p in state.provinces do
		if p.terrain == "Mountain" then
			return id
		end
	end
	return nil
end

-- Setup and clock --------------------------------------------------------------------------------------------------

T.test("a new world: every nation a bot, the clock at 1×, disasters off, Peace first", function()
	local state = world()
	T.expect(state.setup.sandbox == true, "marked as a sandbox")
	T.expect(not state.setup.private, "not a private server")
	local controls = assert(state.sandbox)
	T.equal(controls.speed, Config.Sandbox.StartSpeed)
	T.equal(controls.disasters, false)
	local nations = 0
	for _, n in state.nations do
		nations += 1
		T.equal(n.controller, "Bot")
		T.equal(n.userId, nil)
	end
	T.equal(nations, Config.NationsPerMatch, "all ten nations")
	T.equal(state.phase, "Peace")
	T.expect(not pcall(Sandbox.start, Match.new(Maps.get("skyshards"))), "a match can't be turned into a sandbox")
end)

T.test("the clock: the usual Peace, then War for ever (no Cataclysm, no Results)", function()
	local setup = Sandbox.setup()
	local t = Settings.timing(setup)
	T.equal(t.peaceEnd, Config.Phases.PeaceEndTick)
	T.equal(t.warEnd, math.huge)
	T.equal(t.matchEnd, math.huge)
	T.equal(Match.phaseAt(0, setup), "Peace")
	T.equal(Match.phaseAt(Config.Phases.PeaceEndTick, setup), "War")
	T.equal(Match.phaseAt(Config.Phases.WarEndTick, setup), "War", "no Cataclysm at 20:00")
	T.equal(Match.phaseAt(Config.Phases.MatchEndTick, setup), "War", "no Results at 25:00")
	T.equal(Match.phaseAt(10 * 3600, setup), "War", "still at war after ten hours")
end)

T.test("nothing ends the world: past 25:00, and with one nation holding most of the land", function()
	local state = world()
	local rng = Rng.new(5)
	for _ = 1, Config.Phases.MatchEndTick + Config.Phases.ResultsTicks + 60 do
		Tick.advance(state, rng)
	end
	T.equal(state.result, nil, "no result after 25:00")
	T.equal(state.phase, "War")
	T.expect(not Match.isOver(state), "not over")
	-- domination share and more: still no winner
	for _, p in state.provinces do
		if p.terrain ~= "Mountain" then
			p.owner = A
		end
	end
	Tick.advance(state, rng)
	T.equal(state.result, nil, "no domination victory")
	-- the same land in a match ends it
	local match = Match.new(Maps.get("skyshards"))
	for _, p in match.provinces do
		if p.terrain ~= "Mountain" then
			p.owner = A
		end
	end
	Tick.advance(match, rng)
	T.expect(match.result ~= nil, "a match would have ended")
end)

-- Time controls and disasters --------------------------------------------------------------------------------------

T.test("time controls: pause, 1×, 2× and 4× only, and only in a sandbox", function()
	local state = world()
	for _, speed in Config.Sandbox.Speeds do
		local ok = Sandbox.setSpeed(state, speed)
		T.expect(ok, "speed " .. speed)
		T.equal(Sandbox.speed(state), speed)
	end
	T.expect(table.find(Config.Sandbox.Speeds, 0) ~= nil, "0 pauses")
	local ok, reason = Sandbox.setSpeed(state, 3)
	T.expect(not ok and reason == "BadSpeed", "3× is not an option")
	ok, reason = Sandbox.setSpeed(state, -1)
	T.expect(not ok and reason == "BadSpeed", "no negative speed")
	local match = Match.new(Maps.get("skyshards"))
	ok, reason = Sandbox.setSpeed(match, 2)
	T.expect(not ok and reason == "NotSandbox", "a match has no time controls")
	T.equal(Sandbox.speed(match), 1, "a match runs at 1×")
end)

T.test(
	"disasters: off by default, then one every 60 s from the moment they are switched on, until switched off",
	function()
		local state = world()
		local every = Config.Primordial.CataclysmDisasterTicks
		for tick = 1, 3 * every do
			state.tick = tick
			T.expect(not Primordial.disasterDue(state), "off: none at tick " .. tick)
		end
		state.tick = 100
		T.expect(Sandbox.setDisasters(state, true))
		T.expect(not Primordial.disasterDue(state), "not the moment they are switched on")
		state.tick = 100 + every - 1
		T.expect(not Primordial.disasterDue(state), "not before a full interval")
		state.tick = 100 + every
		T.expect(Primordial.disasterDue(state), "one interval later")
		state.tick = 100 + 2 * every
		T.expect(Primordial.disasterDue(state), "and every interval after")
		state.tick = 100 + 2 * every + 1
		T.expect(Sandbox.setDisasters(state, true))
		state.tick = 100 + 3 * every
		T.expect(Primordial.disasterDue(state), "switching on again while on keeps the rhythm")
		T.expect(Sandbox.setDisasters(state, false))
		T.expect(not Primordial.disasterDue(state), "off again")
		-- a disaster really strikes during the tick it is due, in Peace too
		state = world()
		T.expect(Sandbox.setDisasters(state, true))
		local rng = Rng.new(9)
		local struck = false
		for _ = 1, every do
			Tick.advance(state, rng)
			for _, e in state.events do
				struck = struck or e.kind == "Disaster"
			end
			table.clear(state.events)
		end
		T.equal(state.phase, "Peace", "still Peace")
		T.expect(struck, "a disaster struck at 1:00")
		local ok, reason = Sandbox.setDisasters(Match.new(Maps.get("skyshards")), true)
		T.expect(not ok and reason == "NotSandbox", "a match's disasters are its Cataclysm's")
	end
)

-- Taking over nations ----------------------------------------------------------------------------------------------

T.test("take over a nation, switch to another (the first goes back to a bot), then watch", function()
	local state = world()
	T.equal(Sandbox.seat(state, ME), nil, "a player arrives watching")
	T.expect(Sandbox.play(state, ME, A))
	T.equal(Match.nationOf(state, ME), A)
	T.equal(state.nations[A].controller, "Player")
	T.equal(state.seats[ME], A)
	T.equal(Sandbox.seat(state, ME), A, "and keeps it")
	T.expect(Sandbox.play(state, ME, A), "taking the same nation again is fine")
	T.expect(Sandbox.play(state, ME, B))
	T.equal(Match.nationOf(state, ME), B)
	T.equal(state.nations[A].controller, "Bot", "the nation left behind is a bot again")
	T.equal(state.nations[A].userId, nil)
	T.equal(state.seats[ME], B)
	T.expect(Sandbox.play(state, ME, 0), "watch")
	T.equal(Match.nationOf(state, ME), nil)
	T.equal(state.nations[B].controller, "Bot")
	T.equal(state.seats[ME], nil, "a watcher holds no seat")
	T.expect(Sandbox.play(state, ME, 0), "watching while watching is fine")
end)

T.test("only a living nation nobody else holds can be taken over", function()
	local state = world()
	local ok, reason = Sandbox.play(state, ME, 99)
	T.expect(not ok and reason == "UnknownNation", "unknown nation")
	state.nations[B].eliminated = true
	ok, reason = Sandbox.play(state, ME, B)
	T.expect(not ok and reason == "Eliminated", "an eliminated nation")
	T.expect(Sandbox.play(state, OTHER, A))
	ok, reason = Sandbox.play(state, ME, A)
	T.expect(not ok and reason == "Taken", "another player's nation")
	T.expect(Match.nationOf(state, OTHER) == A, "who keeps it")
	ok, reason = Sandbox.play(Match.new(Maps.get("skyshards")), ME, A)
	T.expect(not ok and reason == "NotSandbox", "never in a match")
end)

T.test("a taken-over nation obeys its player; a bot order still queued for it is refused", function()
	local state = world()
	T.expect(Sandbox.play(state, ME, A))
	local province = owned(state, A)[1]
	local ok, reason = Commands.applyFor(state, nil, A, { kind = "Develop", province = province })
	T.expect(not ok and reason == "NoNation", "a stale bot order")
	state.nations[A].gold = 1000
	T.expect(Commands.applyFor(state, ME, A, { kind = "Develop", province = province }), "the player's own order")
	T.expect(Sandbox.play(state, ME, B))
	T.expect(Commands.applyFor(state, nil, A, { kind = "Develop", province = province }), "the bot runs it again")
end)

T.test("a sandbox player whose nation falls goes back to watching: no Primordial", function()
	local state = world()
	T.expect(Sandbox.play(state, ME, B))
	state.tick = Config.Phases.PeaceEndTick + 5
	state.phase = "War"
	for _, id in owned(state, B) do
		state.provinces[id].owner = A
	end
	Primordial.step(state, Rng.new(1))
	T.expect(state.nations[B].eliminated, "eliminated")
	T.equal(Match.nationOf(state, ME), nil, "watching")
	T.equal(state.seats[ME], nil)
	T.equal(state.primordials[ME], nil, "no Primordial")
	T.expect(Sandbox.play(state, ME, A), "and free to take over a living nation")
	local ok, reason = Sandbox.play(state, ME, B)
	T.expect(not ok and reason == "Eliminated", "but not the fallen one")
end)

-- Free powers --------------------------------------------------------------------------------------------------------

T.test("free powers: a watcher casts in Peace with no charges, and pays none", function()
	local state = world()
	T.equal(state.phase, "Peace")
	local capital = state.nations[A].capital
	local army = Army.spawn(state, A, capital, 4000)
	local ok, reason = Commands.applyFor(state, ME, nil, { kind = "Power", power = "Meteor", target = army.id })
	T.expect(ok, "Meteor from a watcher in Peace: " .. tostring(reason))
	T.equal(army.men, 2000, "half the army")
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Blessing", target = capital }), "Blessing")
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Plague", target = B }), "Plague")
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Shield", target = capital }), "Shield")
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Rebels", target = owned(state, B)[2] }))
	T.equal(state.primordials[ME], nil, "the player never became a Primordial")
	local power = state.events[1]
	T.equal(power.kind, "Power")
	T.equal(power.by, nil, "a watcher's power carries no nation's look")
end)

T.test("free powers: no 30 s immunity, so the same nation can be hit again at once", function()
	local state = world()
	local capital = state.nations[A].capital
	local first = Army.spawn(state, A, capital, 4000)
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Meteor", target = first.id }))
	T.equal(state.nations[A].powerImmuneUntil, 0, "no immunity starts")
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Plague", target = A }), "a second strike")
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Meteor", target = first.id }), "a third")
	T.equal(first.men, 1000)
	-- a match keeps its immunity
	local match = Match.new(Maps.get("skyshards"))
	match.tick = Config.Phases.PeaceEndTick + 10
	match.phase = "War"
	local army = Army.spawn(match, A, match.nations[A].capital, 4000)
	match.nations[B].charges = 5
	T.expect(Commands.applyFor(match, nil, B, { kind = "Power", power = "Meteor", target = army.id }))
	local ok, reason = Commands.applyFor(match, nil, B, { kind = "Power", power = "Plague", target = A })
	T.expect(not ok and reason == "Immune", "a match's 30 s immunity")
end)

T.test("free powers keep the targeting rules: no mountains, Earthquake needs a building", function()
	local state = world()
	local peak = mountain(state)
	if peak then
		local ok, reason = Commands.applyFor(state, ME, nil, { kind = "Power", power = "Rebels", target = peak })
		T.expect(not ok and reason == "BadTarget", "no Rebels on a mountain")
		ok, reason = Commands.applyFor(state, ME, nil, { kind = "Power", power = "Earthquake", target = peak })
		T.expect(not ok and reason == "BadTarget", "no Earthquake on a mountain")
	end
	local province = owned(state, A)[1]
	local ok, reason = Commands.applyFor(state, ME, nil, { kind = "Power", power = "Earthquake", target = province })
	T.expect(not ok and reason == "NoBuilding", "Earthquake only on a building")
	state.provinces[province].building = "Fort"
	T.expect(Commands.applyFor(state, ME, nil, { kind = "Power", power = "Earthquake", target = province }))
	T.equal(state.provinces[province].building, "None")
end)

T.test("a player holding a nation casts for free too, even on their own land; bots still pay", function()
	local state = world()
	T.expect(Sandbox.play(state, ME, A))
	state.nations[A].charges = 0
	local army = Army.spawn(state, A, state.nations[A].capital, 4000)
	local ok, reason = Commands.applyFor(state, ME, A, { kind = "Power", power = "Meteor", target = army.id })
	T.expect(ok, "own army, no charges: " .. tostring(reason))
	T.equal(state.nations[A].charges, 0, "no charges paid")
	T.equal(state.events[#state.events].by, A, "the power carries the held nation's look")
	-- a bot in the same world pays and needs War
	state.nations[B].charges = 5
	ok, reason = Commands.applyFor(state, nil, B, { kind = "Power", power = "Plague", target = A })
	T.expect(not ok and reason == "NoPowersYet", "a bot waits for War")
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	T.expect(Commands.applyFor(state, nil, B, { kind = "Power", power = "Plague", target = A }), "then casts")
	T.equal(state.nations[B].charges, 5 - Config.Primordial.Powers.Plague.charges, "and pays")
end)

T.test("a free cast is only for a sandbox player", function()
	local match = Match.new(Maps.get("skyshards"))
	match.tick = Config.Phases.PeaceEndTick + 10
	match.phase = "War"
	local ok, reason = Primordial.use(match, { userId = ME, free = true }, "Plague", A)
	T.expect(not ok and reason == "NotSandbox", "not in a match")
	local ok2, reason2 = Primordial.use(world(), { nation = A, free = true }, "Plague", B)
	T.expect(not ok2 and reason2 == "NotSandbox", "not for a nation")
	local ok3, reason3 = Commands.applyFor(match, ME, nil, { kind = "Power", power = "Plague", target = A })
	T.expect(not ok3 and reason3 == "NoNation", "a match spectator has no powers")
end)

-- Intents -------------------------------------------------------------------------------------------------------------

T.test("Sandbox.apply runs Speed, Play and Disasters, and nothing else", function()
	local state = world()
	T.expect(Sandbox.apply(state, ME, { kind = "Speed", speed = 4 }))
	T.equal(Sandbox.speed(state), 4)
	T.expect(Sandbox.apply(state, ME, { kind = "Play", nation = A }))
	T.equal(Match.nationOf(state, ME), A)
	T.expect(Sandbox.apply(state, ME, { kind = "Disasters", on = true }))
	T.expect(assert(state.sandbox).disasters)
	local ok, reason = Sandbox.apply(state, ME, { kind = "Leave" })
	T.expect(not ok and reason == "BadRequest", "teleports are the service's")
	ok, reason = Sandbox.apply(Match.new(Maps.get("skyshards")), ME, { kind = "Speed", speed = 2 })
	T.expect(not ok and reason == "NotSandbox")
end)

T.test("a new world's map: a map the server has, or the fallback for none", function()
	T.equal(Sandbox.mapFor("", Maps.ids, "skyshards"), "skyshards")
	T.equal(Sandbox.mapFor("earth", Maps.ids, "skyshards"), "earth")
	local map, reason = Sandbox.mapFor("atlantis", Maps.ids, "skyshards")
	T.expect(map == nil and reason == "UnknownMap")
end)

-- No rewards, what clients and analytics see -------------------------------------------------------------------------

T.test("a sandbox pays no XP and no Glory", function()
	local state = world()
	T.expect(Sandbox.play(state, ME, A))
	local stats = Progression.newStats(ME, 0)
	stats.provincesTaken = 10
	stats.battlesWon = 10
	stats.powersUsed = 5
	stats.seated = true
	state.tick = 600
	stats.lastCommandAt = 590
	stats.leftAt = 600
	local reward = Progression.matchReward(state, stats, { vip = true, firstMatchToday = true, standardRules = true })
	T.equal(reward.xp, 0)
	T.equal(reward.glory, 0)
	T.equal(#reward.lines, 0)
end)

T.test("clients get the controls in the snapshot, and a delta when they change", function()
	local state = world()
	local before = Snapshot.full(state)
	local controls = assert(before.sandbox)
	T.equal(controls.speed, 1)
	T.expect(before.setup.sandbox == true, "the snapshot says it's a sandbox")
	T.equal(Snapshot.diff(before, Snapshot.full(state)), nil, "nothing changed")
	T.expect(Sandbox.setSpeed(state, 0))
	local after = Snapshot.full(state)
	T.equal(controls.speed, 1, "the baseline is a copy")
	local delta = assert(Snapshot.diff(before, after), "a pause is a change")
	T.equal(assert(delta.sandbox).speed, 0)
	Snapshot.apply(before, delta)
	T.equal(assert(before.sandbox).speed, 0, "the client's copy follows")
	T.equal(Snapshot.full(Match.new(Maps.get("skyshards"))).sandbox, nil, "a match has none")
end)

T.test("analytics: sandbox_started, and a sandbox sends nothing else but the economy", function()
	local e = Telemetry.sandboxStarted("earth", "first", ME)
	T.equal(e.kind, "Custom")
	T.equal(e.name, "sandbox_started")
	T.equal(e.value, 1)
	T.equal(e.fields[1], "earth")
	T.equal(e.fields[2], "first")
	T.equal(e.userId, ME)
	T.expect(Telemetry.sandboxAllows(e), "sandbox_started")
	T.expect(not Telemetry.sandboxAllows(Telemetry.onboarding("joined", ME)), "no onboarding steps")
	T.expect(not Telemetry.sandboxAllows(Telemetry.funnel("MatchFlow", "m-1", "pick", ME)), "no funnels")
	T.expect(not Telemetry.sandboxAllows(Telemetry.custom("map_vote", 1, { "earth" }, ME)), "no match events")
	local spend = Telemetry.robuxPurchase("starter", 99, {}, ME)
	T.expect(Telemetry.sandboxAllows(spend), "real purchases are still recorded")
end)

T.finish()
