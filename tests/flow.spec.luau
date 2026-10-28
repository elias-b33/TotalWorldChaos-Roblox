--!strict
-- A whole 25-minute match at the Sim level, following the server's tick order, with a client mirror that only
-- sees the snapshot and deltas. Gate 1 in miniature: one player grows a nation for 25 minutes with no errors.
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Rng = require("../src/shared/Sim/Rng")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Troops = require("../src/shared/Sim/Troops")
local Tick = require("../src/shared/Sim/Tick")

-- What a keen player might tap every few seconds: develop the poorest province, then build, then recruit.
local function greedyIntent(state, nationId: number)
	local best = nil
	for id, p in state.provinces do
		if p.owner == nationId and p.development < Config.Economy.MaxDevelopment then
			if best == nil or p.development < state.provinces[best].development then
				best = id
			end
		end
	end
	if best and state.tick % 3 == 0 then
		return { kind = "Develop", province = best }
	end
	for id, p in state.provinces do
		if p.owner == nationId and p.building == "None" then
			return { kind = "Build", province = id, building = if state.tick % 2 == 0 then "Farm" else "Barracks" }
		end
	end
	-- recruit with the gold left over after saving for the next development (recruiting every spare coin piles up
	-- upkeep until income can never pay for a development again)
	local saving = if best then Economy.developCost(state.provinces[best].development) else 0
	local line = Troops.ofRole(state.nations[nationId].race, "line") or Troops.BASE
	if state.nations[nationId].gold >= saving + Config.Troops[line].gold then
		return { kind = "Recruit", province = state.nations[nationId].capital, regiments = 1, troop = line }
	end
	return { kind = "Develop", province = best or state.nations[nationId].capital }
end

local function sameView(a: Snapshot.SnapshotData, b: Snapshot.SnapshotData): boolean
	return Snapshot.diff(a, b) == nil and #a.armies == #b.armies and a.phase == b.phase
end

for _, mapId in Maps.ids do
	T.test(mapId .. ": a full match runs, the player grows, and the client never drifts", function()
		local state = Match.new(Maps.get(mapId))
		local me = Match.seatPlayer(state, 1234)
		assert(me, "no seat")
		local client = Snapshot.full(state)
		local lastSent = Snapshot.full(state)
		local startIncome = Economy.monthlyIncome(state, me).gold
		local accepted, refused = 0, 0
		local phasesSeen: { [string]: boolean } = {}
		local lostToRebels: { [number]: number } = {}

		local rng = Rng.new(7)
		while not Match.isOver(state) do
			-- 1. apply queued commands (one intent per tick from the player)
			local ok = Commands.apply(state, me, greedyIntent(state, me))
			if ok then
				accepted += 1
			else
				refused += 1
			end
			Tick.advance(state, rng) -- 2-8
			phasesSeen[state.phase] = true
			-- 9. one delta to the client, then the events are spent
			local current = Snapshot.full(state)
			local delta = Snapshot.diff(lastSent, current, state.events)
			if delta then
				Snapshot.apply(client, delta)
			end
			lastSent = current
			for _, e in state.events do
				if e.kind == "ProvinceTaken" and e.a == 0 then
					lostToRebels[e.b] = (lostToRebels[e.b] or 0) + 1
				end
			end
			table.clear(state.events)
		end

		T.expect(phasesSeen.Peace and phasesSeen.War and phasesSeen.Cataclysm and phasesSeen.Results, "missed a phase")
		local development = 0
		for _, p in state.provinces do
			if p.owner == me then
				development += p.development
			end
		end
		T.expect(accepted >= 40, "only " .. accepted .. " intents worked")
		T.expect(development > 17, "development did not grow")
		T.expect(refused > 0, "the player should run out of money sometimes")
		T.expect(Economy.monthlyIncome(state, me).gold > startIncome, "income did not grow")
		T.expect(sameView(client, Snapshot.full(state)), "client mirror drifted from the server")
		T.expect(state.result and state.result.kind == "Score", "the match ended on score")
		T.expect(client.result and client.result.kind == "Score", "the client heard the result")
		-- nobody else did anything, so bots kept their starting land, apart from what Cataclysm Rebels took
		for id in state.nations do
			T.equal(Match.provinceCount(state, id), 8 - (lostToRebels[id] or 0))
		end
	end)
end

T.finish()
