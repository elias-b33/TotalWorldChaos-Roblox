--!strict
-- Headless bot-only tournament through the real Sim (no Roblox): the evidence for Gate 3, "no single bot wins
-- most matches". Each match follows the server's tick order: apply queued commands, Tick.advance, bots plan.
--
--   lune run tools/harness/tournament                 # 20 seeds × every map, Normal bots
--   lune run tools/harness/tournament 5 skyshards     # 5 seeds on one map
--   lune run tools/harness/tournament 20 all Hard     # another difficulty

local process = require("@lune/process")

local Bot = require("../../src/shared/Sim/Bot")
local Commands = require("../../src/shared/Sim/Commands")
local Config = require("../../src/shared/Config")
local Maps = require("../../src/shared/Maps")
local Match = require("../../src/shared/Sim/Match")
local Rng = require("../../src/shared/Sim/Rng")
local Tick = require("../../src/shared/Sim/Tick")
local Types = require("../../src/shared/Types")

local seeds = tonumber(process.args[1]) or 20
local mapArg = process.args[2] or "all"
local difficulty = (process.args[3] or "Normal") :: Bot.Difficulty
local mapIds = if mapArg == "all" then Maps.ids else { mapArg }

local MINUTES = Config.Phases.MatchEndTick // 60

type MatchStats = {
	result: Types.MatchResult,
	leaderByMinute: { number }, -- provinces held by the leader at the end of each minute
	finalProvinces: { [number]: number },
	commands: number,
	rejected: number,
	rejectReasons: { [string]: number },
	wars: number,
}

local function runMatch(mapId: string, seed: number): MatchStats
	local state = Match.new(Maps.get(mapId))
	local battleRng = Rng.new(seed)
	local botRng = Rng.new(seed * 7919 + 13)
	local schedule = Bot.newSchedule()
	local queue: { Bot.Order } = {}
	local stats = {
		leaderByMinute = {},
		finalProvinces = {},
		commands = 0,
		rejected = 0,
		rejectReasons = {},
		wars = 0,
	}
	while state.result == nil do
		for _, order in queue do -- 1. apply queued commands
			stats.commands += 1
			local ok, reason = Commands.apply(state, order.nation, order.command)
			if not ok then
				stats.rejected += 1
				local key = order.command.kind .. ":" .. tostring(reason)
				stats.rejectReasons[key] = (stats.rejectReasons[key] or 0) + 1
			end
		end
		Tick.advance(state, battleRng) -- 2-8
		queue = Bot.step(schedule, state, botRng, difficulty) -- 7
		for _, e in state.events do
			if e.kind == "WarDeclared" then
				stats.wars += 1
			end
		end
		table.clear(state.events)
		if state.tick % 60 == 0 or state.result then
			local best = 0
			for id in state.nations do
				best = math.max(best, Match.provinceCount(state, id))
			end
			stats.leaderByMinute[math.ceil(state.tick / 60)] = best
		end
	end
	for id in state.nations do
		stats.finalProvinces[id] = Match.provinceCount(state, id)
	end
	-- a match that ended early: the leader keeps what it held
	local last = 0
	for m = 1, MINUTES do
		last = stats.leaderByMinute[m] or last
		stats.leaderByMinute[m] = last
	end
	return {
		result = state.result :: Types.MatchResult,
		leaderByMinute = stats.leaderByMinute,
		finalProvinces = stats.finalProvinces,
		commands = stats.commands,
		rejected = stats.rejected,
		rejectReasons = stats.rejectReasons,
		wars = stats.wars,
	}
end

local function median(list: { number }): number
	local sorted = table.clone(list)
	table.sort(sorted)
	local n = #sorted
	if n == 0 then
		return 0
	end
	if n % 2 == 1 then
		return sorted[(n + 1) // 2]
	end
	return (sorted[n // 2] + sorted[n // 2 + 1]) / 2
end

local function clock(ticks: number): string
	return string.format("%d:%02d", ticks // 60, math.floor(ticks % 60))
end

local started = os.clock()
local grandRejected, grandCommands = 0, 0
print(string.format("Bot tournament: %d seeds × %d maps, %s bots", seeds, #mapIds, difficulty))
for _, mapId in mapIds do
	local map = Maps.get(mapId)
	local mapStart = os.clock()
	local wins: { [number]: number } = {}
	local provincesSum: { [number]: number } = {}
	local kinds: { [string]: number } = {}
	local lengths = {}
	local perMinute: { { number } } = {}
	local rejected, commands, wars = 0, 0, 0
	local reasons: { [string]: number } = {}
	for m = 1, MINUTES do
		perMinute[m] = {}
	end
	for seed = 1, seeds do
		local s = runMatch(mapId, seed)
		for _, w in s.result.winners do
			wins[w] = (wins[w] or 0) + 1
		end
		for id, n in s.finalProvinces do
			provincesSum[id] = (provincesSum[id] or 0) + n
		end
		kinds[s.result.kind] = (kinds[s.result.kind] or 0) + 1
		table.insert(lengths, s.result.endedAt)
		for m = 1, MINUTES do
			table.insert(perMinute[m], s.leaderByMinute[m])
		end
		rejected += s.rejected
		commands += s.commands
		wars += s.wars
		for k, v in s.rejectReasons do
			reasons[k] = (reasons[k] or 0) + v
		end
	end
	grandRejected += rejected
	grandCommands += commands

	local total = #map.provinces
	print(string.format("\n== %s (%d provinces, domination at %d) ==", map.title, total, math.ceil(0.4 * total)))
	print("slot  nation        start position (capital)      wins  avg final provinces")
	local mostWins = 0
	for _, def in map.nations do
		local capitalName = ""
		for _, p in map.provinces do
			if p.id == def.capital then
				capitalName = p.name
			end
		end
		local w = wins[def.slot] or 0
		mostWins = math.max(mostWins, w)
		print(
			string.format(
				"%4d  %-12s  %-28s  %4d  %6.1f",
				def.slot,
				def.name,
				capitalName,
				w,
				(provincesSum[def.slot] or 0) / seeds
			)
		)
	end
	local sumLength = 0
	for _, l in lengths do
		sumLength += l
	end
	print(
		string.format(
			"results: %d domination, %d alliance, %d score  |  domination rate %.0f%%  |  most wins by one slot: %d of %d",
			kinds.Domination or 0,
			kinds.Alliance or 0,
			kinds.Score or 0,
			100 * (kinds.Domination or 0) / seeds,
			mostWins,
			seeds
		)
	)
	print(
		string.format(
			"average match length %s (median %s)  |  wars declared per match %.1f",
			clock(sumLength / seeds),
			clock(median(lengths)),
			wars / seeds
		)
	)
	local row = {}
	for m = 1, MINUTES do
		table.insert(row, string.format("%d:%s", m, tostring(median(perMinute[m]))))
	end
	print("median leader provinces by minute: " .. table.concat(row, " "))
	print(string.format("bot commands %d, rejected %d", commands, rejected))
	for k, v in reasons do
		print(string.format("  rejected %s × %d", k, v))
	end
	print(string.format("(%.1f s)", os.clock() - mapStart))
end
print(
	string.format(
		"\nall maps: %d commands, %d rejected, %.1f s in total",
		grandCommands,
		grandRejected,
		os.clock() - started
	)
)
