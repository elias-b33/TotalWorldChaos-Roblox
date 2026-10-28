--!strict
-- Snapshot/delta encoding and the intent rate limit.
local Army = require("../src/shared/Sim/Army")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Navy = require("../src/shared/Sim/Navy")
local RateLimit = require("../src/shared/RateLimit")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Troops = require("../src/shared/Sim/Troops")

T.test("snapshots are flat arrays with 0 for neutral", function()
	local state = Match.new(Maps.get("eldmoor"))
	local snap = Snapshot.full(state)
	T.equal(#snap.provinces, #Maps.get("eldmoor").provinces)
	T.equal(#snap.nations, 10)
	local neutral = 0
	for i, p in snap.provinces do
		T.equal(p.id, i)
		if p.owner == 0 then
			neutral += 1
		end
	end
	T.expect(neutral > 0)
end)

T.test("no change, no delta", function()
	local state = Match.new(Maps.get("skyshards"))
	local a = Snapshot.full(state)
	state.tick += 1
	T.equal(Snapshot.diff(a, Snapshot.full(state)), nil)
end)

T.test("a delta carries only changed records, and applying it catches the client up", function()
	local state = Match.new(Maps.get("skyshards"))
	local server = Snapshot.full(state)
	local client = Snapshot.full(state)
	state.tick = 5
	state.nations[2].gold += 7
	state.provinces[3].owner = 2
	state.provinces[3].development = 4
	local army = Army.spawn(state, 2, 3, 2000)
	local delta = Snapshot.diff(server, Snapshot.full(state))
	assert(delta, "expected a delta")
	T.equal(#delta.nations, 1)
	T.equal(#delta.provinces, 1)
	T.equal(#delta.armies, 1)
	Snapshot.apply(client, delta)
	T.equal(client.tick, 5)
	T.equal(client.provinces[3].owner, 2)
	T.equal(client.provinces[3].development, 4)
	T.equal(client.nations[2].gold, state.nations[2].gold)
	local mirrored
	for _, a in client.armies do
		if a.id == army.id then
			mirrored = a
		end
	end
	T.equal(mirrored and mirrored.men, 2000)

	-- the army disappears
	local before = Snapshot.full(state)
	state.armies[army.id] = nil
	local delta2 = Snapshot.diff(before, Snapshot.full(state))
	assert(delta2, "expected a delta")
	T.equal(delta2.removedArmies[1], army.id)
	Snapshot.apply(client, delta2)
	for _, a in client.armies do
		T.expect(a.id ~= army.id, "the removed army is gone on the client")
	end
end)

T.test("a phase change alone is a delta", function()
	local state = Match.new(Maps.get("skyshards"))
	local a = Snapshot.full(state)
	state.phase = "War"
	local delta = Snapshot.diff(a, Snapshot.full(state))
	assert(delta, "expected a delta")
	T.equal(delta.phase, "War")
end)

T.test("fleets travel in the snapshot and in deltas: ships, men aboard, route, progress, blockades", function()
	local state = Match.new(Maps.get("skyshards"))
	local client = Snapshot.full(state)
	T.equal(#client.fleets, 0)
	T.equal(client.provinces[2].blockade, 0, "no blockade is 0")

	-- three ships, one of them damaged, with men aboard, sailing two zones
	local before = Snapshot.full(state)
	local fleet = Navy.spawn(state, 1, 1, 3)
	fleet.hull = 2550
	Navy.setCargo(fleet, { Infantry = 2000, Archers = 500 })
	fleet.path = { 2, 3 }
	fleet.moveProgress = 2
	fleet.landAt = 94
	local delta = Snapshot.diff(before, Snapshot.full(state))
	assert(delta, "expected a delta")
	T.equal(#delta.fleets, 1)
	local r = delta.fleets[1]
	T.equal(r.id, fleet.id)
	T.equal(r.owner, 1)
	T.equal(r.zone, 1)
	T.equal(r.ships, 3, "2,550 hull is 3 ships")
	T.equal(r.hull, 2550)
	T.equal(r.men, 2500)
	T.equal(Troops.decode(r.troops).Archers, 500)
	T.equal(r.next, 2)
	T.equal(r.dest, 3)
	T.equal(r.progress, 25, "2 of 8 ticks into the next zone")
	T.equal(r.landAt, 94)
	T.equal(r.inBattle, false)
	T.equal(r.retreating, false)
	Snapshot.apply(client, delta)
	T.equal(#client.fleets, 1)

	-- a moving fleet is a new record every tick; a standing one only when it changes
	before = Snapshot.full(state)
	fleet.moveProgress = 3
	local moved = Snapshot.diff(before, Snapshot.full(state))
	T.equal(moved and #moved.fleets, 1)
	fleet.path, fleet.moveProgress = {}, 0
	before = Snapshot.full(state)
	state.tick += 1
	T.equal(Snapshot.diff(before, Snapshot.full(state)), nil)
	local still = Snapshot.full(state).fleets[1]
	T.equal(still.next, 0)
	T.equal(still.dest, 1, "standing still, it is heading where it is")

	-- a blockade is on the province record
	before = Snapshot.full(state)
	state.provinces[11].blockade = 1
	local blockaded = Snapshot.diff(before, Snapshot.full(state))
	assert(blockaded, "expected a delta")
	T.equal(blockaded.provinces[1].blockade, 1)

	-- the fleet sinks: removed on the client
	before = Snapshot.full(state)
	state.fleets[fleet.id] = nil
	local sunk = Snapshot.diff(before, Snapshot.full(state))
	assert(sunk, "expected a delta")
	T.equal(sunk.removedFleets[1], fleet.id)
	Snapshot.apply(client, sunk)
	T.equal(#client.fleets, 0)
end)

T.test("the snapshot holds only the fleets Navy.visible shows the viewer", function()
	local state = Match.new(Maps.get("skyshards"))
	Navy.spawn(state, 1, 1, 1)
	Navy.spawn(state, 2, 2, 1)
	-- everyone sees every fleet for now (the fog-of-war hook returns true)
	T.equal(#Snapshot.full(state, nil, 1).fleets, 2)
	T.equal(#Snapshot.full(state).fleets, 2)
	local visible = Navy.visible
	Navy.visible = function(_state, viewer, fleet)
		return fleet.owner == viewer
	end
	local ok, err = pcall(function()
		T.equal(#Snapshot.full(state, nil, 1).fleets, 1)
		T.equal(Snapshot.fleets(state, 2)[1].owner, 2)
	end)
	Navy.visible = visible
	assert(ok, err)
end)

T.test("rate limit allows 10 intents per second per player", function()
	local limit = RateLimit.new(10)
	for i = 1, 10 do
		T.expect(RateLimit.allow(limit, 1, 100 + i * 0.01), "intent " .. i)
	end
	T.expect(not RateLimit.allow(limit, 1, 100.5), "11th intent in the same second")
	T.expect(RateLimit.allow(limit, 2, 100.5), "other players are separate")
	T.expect(RateLimit.allow(limit, 1, 101.2), "the window slides")
end)

T.finish()
