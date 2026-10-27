--!strict
-- A whole 25-minute match at the Sim level, following the server's tick order, with a client mirror that only
-- sees the snapshot and deltas. Gate 1 in miniature: one player grows a nation for 25 minutes with no errors.
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")

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
	return { kind = "Recruit", province = state.nations[nationId].capital, regiments = 1 }
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

		while not Match.isOver(state.tick) do
			-- 1. apply queued commands (one intent per tick from the player)
			local ok = Commands.apply(state, me, greedyIntent(state, me))
			if ok then
				accepted += 1
			else
				refused += 1
			end
			-- advance the clock and phase
			state.tick += 1
			state.phase = Match.phaseAt(state.tick)
			phasesSeen[state.phase] = true
			-- 5. income and upkeep
			if state.tick % Config.MonthTicks == 0 then
				Economy.payMonth(state)
			end
			-- 9. one delta to the client
			local current = Snapshot.full(state)
			local delta = Snapshot.diff(lastSent, current)
			if delta then
				Snapshot.apply(client, delta)
			end
			lastSent = current
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
		-- nobody else did anything, so bots kept their starting land
		for id in state.nations do
			T.equal(Match.provinceCount(state, id), 8)
		end
	end)
end

T.finish()
