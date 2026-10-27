--!strict
-- Snapshot/delta encoding and the intent rate limit.
local Army = require("../src/shared/Sim/Army")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local RateLimit = require("../src/shared/RateLimit")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")

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
	T.equal(client.armies[1].men, 2000)

	-- the army disappears
	local before = Snapshot.full(state)
	state.armies[army.id] = nil
	local delta2 = Snapshot.diff(before, Snapshot.full(state))
	assert(delta2, "expected a delta")
	T.equal(delta2.removedArmies[1], army.id)
	Snapshot.apply(client, delta2)
	T.equal(#client.armies, 0)
end)

T.test("a phase change alone is a delta", function()
	local state = Match.new(Maps.get("skyshards"))
	local a = Snapshot.full(state)
	state.phase = "War"
	local delta = Snapshot.diff(a, Snapshot.full(state))
	assert(delta, "expected a delta")
	T.equal(delta.phase, "War")
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
