--!strict
-- Whole matches through the real Sim (Commands + Tick) with the greedy Planner, to measure expansion speed.
--   lune run tools/balance/expansion             # all maps; prints markdown, writes tools/balance/data/expansion_*.csv
--   MAP=skyshards lune run tools/balance/expansion
--
-- Part 1, Peace (0:00-3:00): all 10 nations run the greedy planner and race for neutral land.
-- Part 2, after Peace: from that 3:00 state, one nation (each of the 10 in turn) keeps playing greedily and
-- declares war on every neighbour; the other nine freeze (no commands; their armies stay where they stood).
--   static      frozen opponents keep their armies, catch-up rules on (the real rules)
--   nocatchup   the same, with overextension, underdog and coalition switched off
--   empty       frozen opponents' armies removed: the fastest conquest the movement and siege rules allow
-- Part 3, free-for-all: from the same 3:00 state all 10 nations keep playing greedily and attack every neighbour.
--
-- What-if runs: SET="Siege.TicksPerDevelopment=20,Battle.UnderdogBonus=0.5" overrides Config values first
-- (CSV names get a _whatif suffix so the committed data stays the real rules).

local fs = require("@lune/fs")
local process = require("@lune/process")

local Battle = require("../../src/shared/Sim/Battle")
local CatchUp = require("../../src/shared/Sim/CatchUp")
local Config = require("../../src/shared/Config")
local Economy = require("../../src/shared/Sim/Economy")
local Maps = require("../../src/shared/Maps")
local Match = require("../../src/shared/Sim/Match")
local Planner = require("./Planner")
local Rng = require("../../src/shared/Sim/Rng")
local Tick = require("../../src/shared/Sim/Tick")
local Types = require("../../src/shared/Types")

type MatchState = Types.MatchState

local function deepCopy<T>(v: T): T
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v :: any do
		out[k] = deepCopy(x)
	end
	return out :: any
end

local function nationIds(state: MatchState): { number }
	local ids = {}
	for id in state.nations do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Shares (crown, domination) count ownable provinces only, as the rules do.
local function totalProvinces(state: MatchState): number
	return CatchUp.ownableCount(state.provinces)
end

local function median(xs: { number }): number
	local s = table.clone(xs)
	table.sort(s)
	if #s == 0 then
		return 0
	end
	if #s % 2 == 1 then
		return s[(#s + 1) // 2]
	end
	return (s[#s // 2] + s[#s // 2 + 1]) / 2
end

local function fmtTime(ticks: number?): string
	if ticks == nil then
		return "never"
	end
	return string.format("%d:%02d", ticks // 60, ticks % 60)
end

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

local maps = if process.env.MAP then { process.env.MAP :: string } else Maps.ids
local peaceCsv = { "map,tick,nation,provinces,gold_income,manpower_income,upkeep,regiments,gold,manpower" }
local warCsv = { "map,variant,aggressor,tick,provinces,share,gold_income,manpower_income,overextension,regiments" }
local savedBonus = Battle.bonus
local savedStart = Config.CatchUp.OverextensionStart

for _, mapId in maps do
	local map = Maps.get(mapId)
	print(string.format("\n## %s\n", mapId))

	-- Part 1: Peace --------------------------------------------------------------------------------
	local state = Match.new(map)
	local rng = Rng.new(1)
	local ids = nationIds(state)
	local monthRows: { { tick: number, provinces: { number }, gold: { number }, mp: { number } } } = {}
	local function recordPeace()
		local row = { tick = state.tick, provinces = {}, gold = {}, mp = {} }
		for _, id in ids do
			local income = Economy.monthlyIncome(state, id)
			local n = Match.provinceCount(state, id)
			table.insert(row.provinces, n)
			table.insert(row.gold, income.gold - income.upkeep)
			table.insert(row.mp, income.manpower)
			table.insert(
				peaceCsv,
				string.format(
					"%s,%d,%d,%d,%.2f,%d,%.2f,%.2f,%.1f,%d",
					mapId,
					state.tick,
					id,
					n,
					income.gold,
					income.manpower,
					income.upkeep,
					Economy.regiments(state, id),
					state.nations[id].gold,
					state.nations[id].manpower
				)
			)
		end
		table.insert(monthRows, row)
	end
	recordPeace()
	while state.tick < Config.Phases.PeaceEndTick do
		for _, id in ids do
			Planner.step(state, id, { war = false })
		end
		Tick.advance(state, rng)
		if state.tick % 30 == 0 then
			recordPeace()
		end
	end
	print("Peace, all 10 nations greedy (net gold = income - upkeep, per month):\n")
	print("| Time | Provinces min / median / max | Net gold min / median / max | Manpower median |")
	print("| --- | --- | --- | --- |")
	for _, row in monthRows do
		local p, g = table.clone(row.provinces), table.clone(row.gold)
		table.sort(p)
		table.sort(g)
		print(
			string.format(
				"| %s | %d / %g / %d | %.1f / %.1f / %.1f | %d |",
				fmtTime(row.tick),
				p[1],
				median(p),
				p[#p],
				g[1],
				median(g),
				g[#g],
				median(row.mp)
			)
		)
	end
	local neutralLeft = 0
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			neutralLeft += 1
		end
	end
	print(string.format("\nNeutral provinces left at 3:00: %d\n", neutralLeft))

	-- Part 2: after Peace ----------------------------------------------------------------------------
	local total = totalProvinces(state)
	print("After Peace, one greedy nation against nine frozen ones (each nation tried as the aggressor):\n")
	print(
		"| Variant | Crown ("
			.. math.floor(Config.Diplomacy.CoalitionThreshold * 100 + 0.5)
			.. "%) median / best | "
			.. math.floor(Config.Win.DominationShare * 100 + 0.5)
			.. "% domination median / best | Wins before 25:00 | Provinces at 4:00 (median) | Net gold/month at 4:00 (median) | Regiments at 4:00 (median) |"
	)
	print("| --- | --- | --- | --- | --- | --- | --- |")
	for _, variant in { "static", "nocatchup", "empty" } do
		if variant == "nocatchup" then
			Battle.bonus = function(): number
				return 0
			end
			Config.CatchUp.OverextensionStart = math.huge
		else
			Battle.bonus = savedBonus
			Config.CatchUp.OverextensionStart = savedStart
		end
		local crowns, wins, at4, gold4, regs4 = {}, {}, {}, {}, {}
		local crownBest, winBest = math.huge, math.huge
		for _, aggressor in ids do
			local s = deepCopy(state)
			local r = Rng.new(aggressor)
			if variant == "empty" then
				for armyId, a in s.armies do
					if a.owner ~= aggressor and a.owner ~= 0 then
						s.armies[armyId] = nil
					end
				end
			end
			local crownAt: number? = nil
			while s.result == nil and s.tick < Config.Phases.MatchEndTick do
				Planner.step(s, aggressor, { war = true })
				Tick.advance(s, r)
				local n = Match.provinceCount(s, aggressor)
				if crownAt == nil and n >= Config.Diplomacy.CoalitionThreshold * total then
					crownAt = s.tick
				end
				if s.tick % 30 == 0 or s.result then
					local income = Economy.monthlyIncome(s, aggressor)
					table.insert(
						warCsv,
						string.format(
							"%s,%s,%d,%d,%d,%.4f,%.2f,%d,%.2f,%.2f",
							mapId,
							variant,
							aggressor,
							s.tick,
							n,
							n / total,
							income.gold - income.upkeep,
							income.manpower,
							CatchUp.overextension(n),
							Economy.regiments(s, aggressor)
						)
					)
					if s.tick == 240 then
						table.insert(at4, n)
						table.insert(gold4, income.gold - income.upkeep)
						table.insert(regs4, Economy.regiments(s, aggressor))
					end
				end
			end
			local result = s.result
			local wonAt = if result
					and result.kind == "Domination"
					and result.winners[1] == aggressor
				then result.endedAt
				else nil
			table.insert(crowns, crownAt or math.huge)
			table.insert(wins, wonAt or math.huge)
			crownBest = math.min(crownBest, crownAt or math.huge)
			winBest = math.min(winBest, wonAt or math.huge)
		end
		local winCount = 0
		for _, w in wins do
			if w < math.huge then
				winCount += 1
			end
		end
		local function t(x: number): string
			return if x == math.huge then "never" else fmtTime(x)
		end
		print(
			string.format(
				"| %s | %s / %s | %s / %s | %d of %d | %g | %.1f | %.1f |",
				variant,
				t(median(crowns)),
				t(crownBest),
				t(median(wins)),
				t(winBest),
				winCount,
				#ids,
				median(at4),
				median(gold4),
				median(regs4)
			)
		)
	end
	Battle.bonus = savedBonus
	Config.CatchUp.OverextensionStart = savedStart

	-- Part 3: free-for-all ---------------------------------------------------------------------------
	print("\nAfter Peace, all 10 nations greedy and at war with every neighbour (5 seeds, catch-up on and off):\n")
	print("| Catch-up | Seed | Result | Largest share at 6:00 / 10:00 / 15:00 / 20:00 | Crown worn |")
	print("| --- | --- | --- | --- | --- |")
	for _, catchup in { true, false } do
		if catchup then
			Battle.bonus = savedBonus
			Config.CatchUp.OverextensionStart = savedStart
		else
			Battle.bonus = function(): number
				return 0
			end
			Config.CatchUp.OverextensionStart = math.huge
		end
		for seed = 1, 5 do
			local s = deepCopy(state)
			local r = Rng.new(100 + seed)
			local shares: { [number]: number } = {}
			local crowned = false
			while s.result == nil and s.tick < Config.Phases.MatchEndTick do
				for _, id in ids do
					Planner.step(s, id, { war = true })
				end
				Tick.advance(s, r)
				local best = 0
				for _, id in ids do
					best = math.max(best, Match.provinceCount(s, id))
				end
				crowned = crowned or best >= Config.Diplomacy.CoalitionThreshold * total
				shares[s.tick] = best / total
				if s.tick % 30 == 0 or s.result ~= nil then
					table.insert(
						warCsv,
						string.format(
							"%s,ffa_%s_%d,0,%d,%d,%.4f,0,0,%.2f,0",
							mapId,
							if catchup then "on" else "off",
							seed,
							s.tick,
							best,
							best / total,
							CatchUp.overextension(best)
						)
					)
				end
			end
			local result = s.result
			local text = if result
				then string.format("%s by nation %d at %s", result.kind, result.winners[1], fmtTime(result.endedAt))
				else "none"
			local function share(t: number): string
				local v = shares[t]
				return if v then string.format("%.0f%%", 100 * v) else "-"
			end
			print(
				string.format(
					"| %s | %d | %s | %s / %s / %s / %s | %s |",
					if catchup then "on" else "off",
					seed,
					text,
					share(360),
					share(600),
					share(900),
					share(1200),
					if crowned then "yes" else "no"
				)
			)
		end
	end
	Battle.bonus = savedBonus
	Config.CatchUp.OverextensionStart = savedStart
end

fs.writeDir("tools/balance/data")
local suffix = (if process.env.MAP then "_" .. (process.env.MAP :: string) else "")
	.. (if overrides and overrides ~= "" then "_whatif" else "")
fs.writeFile("tools/balance/data/expansion_peace" .. suffix .. ".csv", table.concat(peaceCsv, "\n") .. "\n")
fs.writeFile("tools/balance/data/expansion_war" .. suffix .. ".csv", table.concat(warCsv, "\n") .. "\n")
print("\nwrote tools/balance/data/expansion_peace" .. suffix .. ".csv and expansion_war" .. suffix .. ".csv")
