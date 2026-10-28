--!strict
-- Headless bot-only tournament through the real Sim (no Roblox): the evidence for Gate 3, "no single bot wins
-- most matches". Each match follows the server's tick order: apply queued commands, Tick.advance, bots plan.
--
--   lune run tools/harness/tournament                 # 20 seeds × every map, Normal bots
--   lune run tools/harness/tournament 5 skyshards     # 5 seeds on one map
--   lune run tools/harness/tournament 20 all Hard     # another difficulty
--   lune run tools/harness/tournament 20 all Hard/Normal   # mixed: half the nations on each, swapped every seed
--   lune run tools/harness/tournament 20 all Easy/Player   # Easy bots against Normal-bot stand-ins for players
--   SET="Siege.TicksPerDevelopment=20" lune run tools/harness/tournament   # what-if: override Config values first

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
local difficultyArg = process.args[3] or "Normal"
local groupA, groupB = string.match(difficultyArg, "^(%a+)/(%a+)$")
local mixed = groupA ~= nil
local difficulty = (if mixed then groupA else difficultyArg) :: Bot.Difficulty
local STAND_IN_PLAN_TICKS = Config.Bots.Normal.planTicks -- "Player" stand-ins plan like Normal bots
local mapIds = if mapArg == "all" then Maps.ids else { mapArg }

local overrides = process.env.SET
if overrides and overrides ~= "" then
	for _, pair in string.split(overrides, ",") do
		local path, value = string.match(pair, "^%s*([%w%.]+)%s*=%s*([%d%.]+)%s*$")
		assert(path and value, "bad SET entry: " .. pair)
		local node: any = Config
		local keys = string.split(path, ".")
		for i = 1, #keys - 1 do
			node = node[keys[i]]
		end
		assert(node[keys[#keys]] ~= nil, "unknown Config value: " .. path)
		node[keys[#keys]] = tonumber(value)
		print(string.format("what-if: Config.%s = %s", path, value))
	end
end

local MINUTES = Config.Phases.MatchEndTick // 60

type MatchStats = {
	result: Types.MatchResult,
	leaderByMinute: { number }, -- provinces held by the leader at the end of each minute
	finalProvinces: { [number]: number },
	commands: number,
	rejected: number,
	rejectReasons: { [string]: number },
	wars: number,
	conquests: number, -- provinces taken from another nation (not neutral land)
	powers: number, -- Primordial powers bots used
	leaderChanges: number, -- minutes (from 3:00) that ended with a different nation holding the most provinces
	armyStats: { [number]: ArmyStats }, -- at the end of minutes 15 and 25 (or the end of the match)
	group: { [number]: string }, -- mixed mode: nation -> "A" or "B"
	earlyWars: { [string]: number }, -- mixed mode: "AB" = wars A declared on B before Easy's no-player-war time
	earlyTaken: { [string]: number }, -- mixed mode: "AB" = provinces A took from B before that time
	taken: { [string]: number }, -- mixed mode: "AB" = provinces A took from B in the whole match
}

-- Nations' armies at one moment: how many, how many men, the biggest nation's men, and standing armies that share
-- a province with another standing army of the same owner (overlapping tokens).
type ArmyStats = { armies: number, men: number, maxMen: number, stacked: number }

local function armyStats(state: Types.MatchState): ArmyStats
	local out = { armies = 0, men = 0, maxMen = 0, stacked = 0 }
	local perNation: { [number]: number } = {}
	local standing: { [string]: number } = {}
	for _, a in state.armies do
		if a.owner ~= 0 then
			out.armies += 1
			out.men += a.men
			perNation[a.owner] = (perNation[a.owner] or 0) + a.men
			if #a.path == 0 and not a.inBattle then
				local key = a.owner .. ":" .. a.location
				standing[key] = (standing[key] or 0) + 1
			end
		end
	end
	for _, n in perNation do
		out.maxMen = math.max(out.maxMen, n)
	end
	for _, n in standing do
		if n > 1 then
			out.stacked += n
		end
	end
	return out
end

local function runMatch(mapId: string, seed: number): MatchStats
	local state = Match.new(Maps.get(mapId))
	local battleRng = Rng.new(seed)
	local botRng = Rng.new(seed * 7919 + 13)
	local schedule = Bot.newSchedule()
	local queue: { Bot.Order } = {}
	-- mixed mode: alternate slots between the two groups, swapped on every other seed so each slot plays both
	local group: { [number]: string } = {}
	local levels: { [number]: Bot.Difficulty } = {}
	local standIns: { [number]: Bot.Memory } = {}
	if mixed then
		for id in state.nations do
			local g = if (id + seed) % 2 == 0 then "A" else "B"
			group[id] = g
			local level = if g == "A" then groupA else groupB
			if level == "Player" then
				state.nations[id].controller = "Player"
				state.nations[id].userId = 100000 + id
				standIns[id] = Bot.newMemory()
			else
				levels[id] = level :: Bot.Difficulty
			end
		end
	end
	local earlyWars: { [string]: number } = {}
	local earlyTaken: { [string]: number } = {}
	local taken: { [string]: number } = {}
	local lastLeader = 0
	local stats = {
		leaderByMinute = {},
		finalProvinces = {},
		commands = 0,
		rejected = 0,
		rejectReasons = {},
		wars = 0,
		conquests = 0,
		powers = 0,
		leaderChanges = 0,
		armyStats = {},
	}
	while state.result == nil do
		for _, order in queue do -- 1. apply queued commands
			stats.commands += 1
			local ok, reason = Commands.apply(state, order.nation, order.command)
			if ok and order.command.kind == "Power" then
				stats.powers += 1
			end
			if not ok then
				stats.rejected += 1
				local key = order.command.kind .. ":" .. tostring(reason)
				stats.rejectReasons[key] = (stats.rejectReasons[key] or 0) + 1
			end
		end
		Tick.advance(state, battleRng) -- 2-8
		queue = Bot.step(schedule, state, botRng, difficulty, levels) -- 7
		for id, memory in standIns do
			local nation = state.nations[id]
			if not nation.eliminated and (state.tick + id) % STAND_IN_PLAN_TICKS == 0 then
				for _, command in Bot.plan(state, id, botRng, "Normal", memory) do
					table.insert(queue, { nation = id, command = command })
				end
			end
		end
		local early = state.tick < Config.Bots.Easy.noPlayerWarTicks
		for _, e in state.events do
			if e.kind == "WarDeclared" then
				stats.wars += 1
				if mixed and early then
					local key = group[e.a] .. group[e.b]
					earlyWars[key] = (earlyWars[key] or 0) + 1
				end
			elseif e.kind == "ProvinceTaken" and e.a ~= 0 and e.b ~= 0 then
				stats.conquests += 1
				if mixed and group[e.a] and group[e.b] then
					local key = group[e.a] .. group[e.b]
					taken[key] = (taken[key] or 0) + 1
					if early then
						earlyTaken[key] = (earlyTaken[key] or 0) + 1
					end
				end
			end
		end
		table.clear(state.events)
		if state.tick % 60 == 0 or state.result then
			local best, leader = 0, 0
			for id = 1, #state.nations do
				local n = Match.provinceCount(state, id)
				if n > best then
					best, leader = n, id
				end
			end
			stats.leaderByMinute[math.ceil(state.tick / 60)] = best
			if state.tick > Config.Phases.PeaceEndTick and leader ~= lastLeader then
				stats.leaderChanges += 1
			end
			lastLeader = leader
		end
		if state.tick == 15 * 60 or state.result then
			stats.armyStats[if state.tick <= 15 * 60 then 15 else 25] = armyStats(state)
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
		conquests = stats.conquests,
		powers = stats.powers,
		leaderChanges = stats.leaderChanges,
		armyStats = stats.armyStats,
		group = group,
		earlyWars = earlyWars,
		earlyTaken = earlyTaken,
		taken = taken,
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
print(string.format("Bot tournament: %d seeds × %d maps, %s bots", seeds, #mapIds, difficultyArg))
-- mixed mode, every map together: wins and final provinces by group
local mixedTotals = {
	wins = { A = 0, B = 0 },
	matches = 0,
	provinces = { A = 0, B = 0 },
	nations = { A = 0, B = 0 },
	eliminated = { A = 0, B = 0 },
	earlyWars = {} :: { [string]: number },
	earlyTaken = {} :: { [string]: number },
	taken = {} :: { [string]: number },
}
for _, mapId in mapIds do
	local map = Maps.get(mapId)
	local mapStart = os.clock()
	local wins: { [number]: number } = {}
	local provincesSum: { [number]: number } = {}
	local kinds: { [string]: number } = {}
	local lengths = {}
	local perMinute: { { number } } = {}
	local rejected, commands, wars, conquests, leaderChanges, powers = 0, 0, 0, 0, 0, 0
	local atMinute: { [number]: { [string]: { number } } } = {}
	for _, m in { 15, 25 } do
		atMinute[m] = { armies = {}, men = {}, maxMen = {}, stacked = {} }
	end
	local reasons: { [string]: number } = {}
	for m = 1, MINUTES do
		perMinute[m] = {}
	end
	for seed = 1, seeds do
		local s = runMatch(mapId, seed)
		for _, w in s.result.winners do
			wins[w] = (wins[w] or 0) + 1
		end
		if mixed then
			mixedTotals.matches += 1
			for _, w in s.result.winners do
				mixedTotals.wins[s.group[w]] += 1 / #s.result.winners
			end
			for id, n in s.finalProvinces do
				local g = s.group[id]
				mixedTotals.provinces[g] += n
				mixedTotals.nations[g] += 1
				if n == 0 then
					mixedTotals.eliminated[g] += 1
				end
			end
			for _, pair in { { s.earlyWars, mixedTotals.earlyWars }, { s.earlyTaken, mixedTotals.earlyTaken } } do
				for k, v in pair[1] do
					pair[2][k] = (pair[2][k] or 0) + v
				end
			end
			for k, v in s.taken do
				mixedTotals.taken[k] = (mixedTotals.taken[k] or 0) + v
			end
		end
		for id, n in s.finalProvinces do
			provincesSum[id] = (provincesSum[id] or 0) + n
		end
		kinds[s.result.kind] = (kinds[s.result.kind] or 0) + 1
		table.insert(lengths, s.result.endedAt)
		for m = 1, MINUTES do
			table.insert(perMinute[m], s.leaderByMinute[m])
		end
		for m, lists in atMinute do
			local a = s.armyStats[m] or s.armyStats[15] or s.armyStats[25]
			if a then
				table.insert(lists.armies, a.armies)
				table.insert(lists.men, a.men)
				table.insert(lists.maxMen, a.maxMen)
				table.insert(lists.stacked, a.stacked)
			end
		end
		rejected += s.rejected
		commands += s.commands
		wars += s.wars
		conquests += s.conquests
		powers += s.powers
		leaderChanges += s.leaderChanges
		for k, v in s.rejectReasons do
			reasons[k] = (reasons[k] or 0) + v
		end
	end
	grandRejected += rejected
	grandCommands += commands

	local total = #map.provinces
	local ownable = 0
	for _, p in map.provinces do
		if p.terrain ~= "Mountain" then
			ownable += 1
		end
	end
	print(
		string.format(
			"\n== %s (%d provinces, %d ownable, domination at %d) ==",
			map.title,
			total,
			ownable,
			math.ceil(Config.Win.DominationShare * ownable)
		)
	)
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
	local sortedLengths = table.clone(lengths)
	table.sort(sortedLengths)
	local ends = {}
	for _, l in sortedLengths do
		table.insert(ends, clock(l))
	end
	print("match ends: " .. table.concat(ends, " "))
	print(
		string.format(
			"provinces taken from nations per match %.1f  |  leader changes per match (minute checks after 3:00) %.1f  |  powers used by bots per match %.1f",
			conquests / seeds,
			leaderChanges / seeds,
			powers / seeds
		)
	)
	local row = {}
	for m = 1, MINUTES do
		table.insert(row, string.format("%d:%s", m, tostring(median(perMinute[m]))))
	end
	print("median leader provinces by minute: " .. table.concat(row, " "))
	for _, m in { 15, 25 } do
		local lists = atMinute[m]
		print(
			string.format(
				"armies at %d:00 (median): %d armies, %dk men in all, biggest nation %dk men, %d stacked tokens",
				m,
				median(lists.armies),
				median(lists.men) // 1000,
				median(lists.maxMen) // 1000,
				median(lists.stacked)
			)
		)
	end
	print(string.format("bot commands %d, rejected %d", commands, rejected))
	for k, v in reasons do
		print(string.format("  rejected %s × %d", k, v))
	end
	print(string.format("(%.1f s)", os.clock() - mapStart))
end
if mixed then
	local m = mixedTotals
	print(string.format("\n== mixed: A = %s, B = %s (%d matches, every map) ==", groupA, groupB, m.matches))
	for _, g in { "A", "B" } do
		print(
			string.format(
				"%s %-7s wins %5.1f (%3.0f%%)  avg final provinces %5.1f  ended with no land %d of %d",
				g,
				if g == "A" then groupA else groupB,
				m.wins[g],
				100 * m.wins[g] / math.max(1, m.matches),
				m.provinces[g] / math.max(1, m.nations[g]),
				m.eliminated[g],
				m.nations[g]
			)
		)
	end
	local minutes = Config.Bots.Easy.noPlayerWarTicks // 60
	for _, key in { "AB", "BA", "AA", "BB" } do
		print(
			string.format(
				"%s on %s: wars before %d:00 %d, provinces taken before %d:00 %d, in the whole match %d",
				key:sub(1, 1),
				key:sub(2, 2),
				minutes,
				m.earlyWars[key] or 0,
				minutes,
				m.earlyTaken[key] or 0,
				m.taken[key] or 0
			)
		)
	end
end
print(
	string.format(
		"\nall maps: %d commands, %d rejected, %.1f s in total",
		grandCommands,
		grandRejected,
		os.clock() - started
	)
)
