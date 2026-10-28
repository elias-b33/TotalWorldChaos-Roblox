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
--   SET="Features.Diplomacy=false" lune run tools/harness/tournament 200 earth   # a match feature off (true/false)
--   SET="Features.Events=false" lune run tools/harness/tournament 200 earth      # no event cards (the EU4 pack, stage 2)
--   lune run tools/harness/tournament 200 eldmoor     # start-position balance (docs/BALANCE.md section 16)
--   RACES=shuffle lune run tools/harness/tournament 100   # races dealt out at random each match (the map's mix):
--                                                         # race strength without the start positions in it
--   FIRST_SEED=101 lune run tools/harness/tournament 100 earth   # seeds 101-200: split a long run over processes
--
-- "share" is a slot's wins over the fair share (all wins / 10). Win counts are noisy: at 200 seeds one slot's count
-- moves by about ±5 (±0.2× share) from seed to seed, so judge start positions on 200 seeds per map, not 20.
-- Races (docs/DESIGN.md "Races"): each map also prints the wins by race (its own cast of five) against the race's
-- fair share (all wins × its nations / 10) and the regiments bots recruited of each troop type the map has (the
-- shared roles under the map's names, and its races' elites).

local process = require("@lune/process")

local Bot = require("../../src/shared/Sim/Bot")
local Commands = require("../../src/shared/Sim/Commands")
local Config = require("../../src/shared/Config")
local Diplomacy = require("../../src/shared/Sim/Diplomacy")
local EventCards = require("../../src/shared/Sim/EventCards")
local Maps = require("../../src/shared/Maps")
local Match = require("../../src/shared/Sim/Match")
local Races = require("../../src/shared/Sim/Races")
local Rng = require("../../src/shared/Sim/Rng")
local Tick = require("../../src/shared/Sim/Tick")
local Troops = require("../../src/shared/Sim/Troops")
local Types = require("../../src/shared/Types")

local seeds = tonumber(process.args[1]) or 20
local firstSeed = tonumber(process.env.FIRST_SEED) or 1 -- plays seeds firstSeed .. firstSeed + seeds - 1
local mapArg = process.args[2] or "all"
local difficultyArg = process.args[3] or "Normal"
local groupA, groupB = string.match(difficultyArg, "^(%a+)/(%a+)$")
local mixed = groupA ~= nil
local difficulty = (if mixed then groupA else difficultyArg) :: Bot.Difficulty
local STAND_IN_PLAN_TICKS = Config.Bots.Normal.planTicks -- "Player" stand-ins plan like Normal bots
local mapIds = if mapArg == "all" then Maps.ids else { mapArg }
local shuffleRaces = process.env.RACES == "shuffle"
if shuffleRaces then
	print("races: dealt out at random every match (each map keeps its mix)")
end

local overrides = process.env.SET
if overrides and overrides ~= "" then
	for _, pair in string.split(overrides, ",") do
		local path, value = string.match(pair, "^%s*([%w%.]+)%s*=%s*([%w%.]+)%s*$")
		assert(path and value, "bad SET entry: " .. pair)
		local parsed: any = if value == "true" then true elseif value == "false" then false else tonumber(value)
		assert(parsed ~= nil, "bad SET value: " .. pair)
		local node: any = Config
		local keys = string.split(path, ".")
		for i = 1, #keys - 1 do
			node = node[keys[i]]
		end
		assert(node[keys[#keys]] ~= nil, "unknown Config value: " .. path)
		node[keys[#keys]] = parsed
		print(string.format("what-if: Config.%s = %s", path, value))
	end
end

local MINUTES = Config.Phases.MatchEndTick // 60

-- The troop types a map's nations can recruit: each race's roster in role order (line, ranged, fast, elite,
-- special), the map's races in cast order, every troop once (Earth's cultures share four).
local function mapTroops(mapId: string): { string }
	local out = {}
	for _, race in Races.forMap(mapId) do
		for _, troop in Troops.roster(race) do
			if table.find(out, troop) == nil then
				table.insert(out, troop)
			end
		end
	end
	return out
end

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
	insults: number, -- the EU4 pack: insults and insults back bots sent, wars declared on a nation the declarer holds a
	insultsBack: number, -- grudge against (it insulted them)
	grudgeWars: number,
	cards: number, -- the EU4 pack's event cards closed (stage 2), and how many of them ran out of time
	cardsTimedOut: number,
	granted: { [string]: number }, -- what the closed cards gave, by effect (gold, manpower, development, regiments...)
	leaderChanges: number, -- minutes (from 3:00) that ended with a different nation holding the most provinces
	armyStats: { [number]: ArmyStats }, -- at the end of minutes 15 and 25 (or the end of the match)
	group: { [number]: string }, -- mixed mode: nation -> "A" or "B"
	earlyWars: { [string]: number }, -- mixed mode: "AB" = wars A declared on B before Easy's no-player-war time
	earlyTaken: { [string]: number }, -- mixed mode: "AB" = provinces A took from B before that time
	taken: { [string]: number }, -- mixed mode: "AB" = provinces A took from B in the whole match
	races: { [number]: string }, -- nation -> its race this match
	recruits: { [string]: number }, -- troop type -> regiments bots recruited
}

-- Nations' armies at one moment: how many, how many men, the biggest nation's men, standing armies that share
-- a province with another standing army of the same owner (overlapping tokens), the gold living nations hold
-- (median) and the share of all men in each troop type.
type ArmyStats = {
	armies: number,
	men: number,
	maxMen: number,
	stacked: number,
	gold: number,
	manpower: number,
	troops: { [string]: number },
}

local function armyStats(state: Types.MatchState): ArmyStats
	local out =
		{ armies = 0, men = 0, maxMen = 0, stacked = 0, gold = 0, manpower = 0, troops = {} :: { [string]: number } }
	local golds, manpowers = {}, {}
	for _, nation in state.nations do
		if not nation.eliminated then
			table.insert(golds, nation.gold)
			table.insert(manpowers, nation.manpower)
		end
	end
	table.sort(golds)
	table.sort(manpowers)
	out.gold = golds[(#golds + 1) // 2] or 0
	out.manpower = manpowers[(#manpowers + 1) // 2] or 0
	local perNation: { [number]: number } = {}
	local standing: { [string]: number } = {}
	for _, a in state.armies do
		if a.owner ~= 0 then
			out.armies += 1
			out.men += a.men
			for troop, n in a.troops do
				out.troops[troop] = (out.troops[troop] or 0) + n
			end
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
	if shuffleRaces then
		local deck = {}
		for id = 1, #state.nations do
			table.insert(deck, state.nations[id].race)
		end
		local raceRng = Rng.new(seed * 104729 + 7)
		for i = #deck, 2, -1 do
			local j = Rng.int(raceRng, 1, i)
			deck[i], deck[j] = deck[j], deck[i]
		end
		for id = 1, #state.nations do
			state.nations[id].race = deck[id]
		end
	end
	local races: { [number]: string } = {}
	for id, nation in state.nations do
		races[id] = nation.race
	end
	local recruits: { [string]: number } = {}
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
		insults = 0,
		insultsBack = 0,
		grudgeWars = 0,
		cards = 0,
		cardsTimedOut = 0,
		granted = {},
		leaderChanges = 0,
		armyStats = {},
	}
	local lastCard: { [number]: number } = {} -- nation -> the last event card counted
	while state.result == nil do
		for _, order in queue do -- 1. apply queued commands
			stats.commands += 1
			local ok, reason = Commands.apply(state, order.nation, order.command)
			if ok and order.command.kind == "Power" then
				stats.powers += 1
			end
			local command = order.command
			if ok and command.kind == "Recruit" then
				recruits[command.troop] = (recruits[command.troop] or 0) + command.regiments
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
			if e.kind == "Insult" then
				stats.insults += 1
			elseif e.kind == "InsultBack" then
				stats.insultsBack += 1
			end
			if e.kind == "WarDeclared" then
				stats.wars += 1
				if Diplomacy.grudge(state, e.a, e.b) then
					stats.grudgeWars += 1
				end
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
		for id, c in state.chronicles do
			local last = c.last
			if last and lastCard[id] ~= last.card then
				lastCard[id] = last.card
				stats.cards += 1
				if last.auto then
					stats.cardsTimedOut += 1
				end
				local def = EventCards.def(last.event)
				for effect, amount in (if def then def.choices[last.choice] else {}) :: { [string]: number } do
					stats.granted[effect] = (stats.granted[effect] or 0) + amount
				end
			end
		end
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
		insults = stats.insults,
		insultsBack = stats.insultsBack,
		grudgeWars = stats.grudgeWars,
		cards = stats.cards,
		cardsTimedOut = stats.cardsTimedOut,
		granted = stats.granted,
		leaderChanges = stats.leaderChanges,
		armyStats = stats.armyStats,
		group = group,
		earlyWars = earlyWars,
		earlyTaken = earlyTaken,
		taken = taken,
		races = races,
		recruits = recruits,
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
if firstSeed ~= 1 then
	print(string.format("seeds %d to %d", firstSeed, firstSeed + seeds - 1))
end
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
-- every map together: wins and nations by race, regiments by troop type
local allRaceWins: { [string]: number } = {}
local allRaceNations: { [string]: number } = {}
local allWins = 0
local allRecruits: { [string]: number } = {}
for _, mapId in mapIds do
	local map = Maps.get(mapId)
	local mapStart = os.clock()
	local wins: { [number]: number } = {}
	local provincesSum: { [number]: number } = {}
	local kinds: { [string]: number } = {}
	local lengths = {}
	local perMinute: { { number } } = {}
	local rejected, commands, wars, conquests, leaderChanges, powers = 0, 0, 0, 0, 0, 0
	local insults, insultsBack, grudgeWars, cards, cardsTimedOut = 0, 0, 0, 0, 0
	local granted: { [string]: number } = {}
	local atMinute: { [number]: { [string]: { number } } } = {}
	for _, m in { 15, 25 } do
		atMinute[m] = { armies = {}, men = {}, maxMen = {}, stacked = {}, gold = {}, manpower = {} }
	end
	local reasons: { [string]: number } = {}
	for m = 1, MINUTES do
		perMinute[m] = {}
	end
	local troopMenAt: { [number]: { [string]: number } } = { [15] = {}, [25] = {} }
	local raceWins: { [string]: number } = {}
	local raceNations: { [string]: number } = {}
	local raceProvinces: { [string]: number } = {}
	local recruits: { [string]: number } = {}
	for seed = firstSeed, firstSeed + seeds - 1 do
		local s = runMatch(mapId, seed)
		for _, w in s.result.winners do
			wins[w] = (wins[w] or 0) + 1
			raceWins[s.races[w]] = (raceWins[s.races[w]] or 0) + 1
		end
		for id, race in s.races do
			raceNations[race] = (raceNations[race] or 0) + 1
			raceProvinces[race] = (raceProvinces[race] or 0) + (s.finalProvinces[id] or 0)
		end
		for troop, n in s.recruits do
			recruits[troop] = (recruits[troop] or 0) + n
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
				table.insert(lists.gold, a.gold)
				table.insert(lists.manpower, a.manpower)
				for troop, n in a.troops do
					troopMenAt[m][troop] = (troopMenAt[m][troop] or 0) + n
				end
				troopMenAt[m].all = (troopMenAt[m].all or 0) + a.men
			end
		end
		rejected += s.rejected
		commands += s.commands
		wars += s.wars
		conquests += s.conquests
		powers += s.powers
		insults += s.insults
		insultsBack += s.insultsBack
		grudgeWars += s.grudgeWars
		cards += s.cards
		cardsTimedOut += s.cardsTimedOut
		for effect, amount in s.granted do
			granted[effect] = (granted[effect] or 0) + amount
		end
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
	-- share: wins over the fair share (all wins, alliance co-winners included, split evenly over the slots)
	local totalWins = 0
	for _, w in wins do
		totalWins += w
	end
	local fair = math.max(totalWins, 1) / #map.nations
	print("slot  nation        start position (capital)      wins  share  avg final provinces")
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
				"%4d  %-12s  %-28s  %4d  %4.2fx  %6.1f",
				def.slot,
				def.name,
				capitalName,
				w,
				w / fair,
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
			"insults per match %.1f, insults back %.1f  |  wars declared on an insulter per match %.1f",
			insults / seeds,
			insultsBack / seeds,
			grudgeWars / seeds
		)
	)
	print(
		string.format(
			"event cards per match %.1f (%.1f per nation), timed out %.1f",
			cards / seeds,
			cards / seeds / 10,
			cardsTimedOut / seeds
		)
	)
	local gave = {}
	for _, effect in { "gold", "manpower", "development", "regiments", "ships", "boost" } do
		if granted[effect] then
			table.insert(gave, string.format("%s %.2f", effect, granted[effect] / seeds / 10))
		end
	end
	if #gave > 0 then
		print("  event cards gave per nation per match (boost: summed bonus): " .. table.concat(gave, ", "))
	end
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
				"armies at %d:00 (median): %d armies, %dk men in all, biggest nation %dk men, %d stacked tokens, %d gold and %dk manpower banked per nation",
				m,
				median(lists.armies),
				median(lists.men) // 1000,
				median(lists.maxMen) // 1000,
				median(lists.stacked),
				median(lists.gold),
				median(lists.manpower) // 1000
			)
		)
		local mix = {}
		for _, troop in mapTroops(mapId) do
			local share = (troopMenAt[m][troop] or 0) / math.max(troopMenAt[m].all or 0, 1)
			table.insert(mix, string.format("%s %d%%", Troops.name(troop), math.floor(100 * share + 0.5)))
		end
		print(string.format("  men by troop at %d:00: %s", m, table.concat(mix, ", ")))
	end
	-- races: wins against each race's fair share (all wins × its share of the nations)
	local nationsTotal = 0
	for _, n in raceNations do
		nationsTotal += n
	end
	print("race          nations/match  wins  share  avg final provinces")
	for _, race in Races.forMap(mapId) do
		local n = raceNations[race] or 0
		local fairRace = math.max(totalWins, 1) * n / math.max(nationsTotal, 1)
		print(
			string.format(
				"%-12s  %13.1f  %4d  %4.2fx  %6.1f",
				race,
				n / seeds,
				raceWins[race] or 0,
				(raceWins[race] or 0) / math.max(fairRace, 1e-9),
				(raceProvinces[race] or 0) / math.max(n, 1)
			)
		)
		allRaceWins[race] = (allRaceWins[race] or 0) + (raceWins[race] or 0)
		allRaceNations[race] = (allRaceNations[race] or 0) + n
	end
	allWins += totalWins
	local troopLine, troopTotal = {}, 0
	for _, n in recruits do
		troopTotal += n
	end
	for _, troop in mapTroops(mapId) do
		local n = recruits[troop] or 0
		allRecruits[troop] = (allRecruits[troop] or 0) + n
		table.insert(
			troopLine,
			string.format(
				"%s %.1f (%d%%)",
				Troops.name(troop),
				n / seeds,
				math.floor(100 * n / math.max(troopTotal, 1) + 0.5)
			)
		)
	end
	print("regiments recruited per match: " .. table.concat(troopLine, ", "))
	local roleLine = {}
	for _, role in Troops.ROLES do
		local n = 0
		for troop, r in recruits do
			n += if Troops.role(troop) == role then r else 0
		end
		table.insert(roleLine, string.format("%s %d%%", role, math.floor(100 * n / math.max(troopTotal, 1) + 0.5)))
	end
	print("  by role: " .. table.concat(roleLine, ", "))
	print(string.format("bot commands %d, rejected %d", commands, rejected))
	for k, v in reasons do
		print(string.format("  rejected %s × %d", k, v))
	end
	print(string.format("(%.1f s)", os.clock() - mapStart))
end
if #mapIds > 1 then
	local nationsTotal = 0
	for _, n in allRaceNations do
		nationsTotal += n
	end
	print("\n== every map: wins by race ==")
	for _, race in Races.LIST do
		local fairRace = math.max(allWins, 1) * (allRaceNations[race] or 0) / math.max(nationsTotal, 1)
		print(
			string.format(
				"%-12s  wins %4d  share %4.2fx",
				race,
				allRaceWins[race] or 0,
				(allRaceWins[race] or 0) / math.max(fairRace, 1e-9)
			)
		)
	end
	local parts = {}
	for _, troop in Troops.LIST do
		if allRecruits[troop] then
			table.insert(parts, string.format("%s %d", troop, allRecruits[troop]))
		end
	end
	print("regiments recruited in all: " .. table.concat(parts, ", "))
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
