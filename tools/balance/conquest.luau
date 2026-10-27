--!strict
-- Time and cost to take one neutral province, measured through the real Sim (Commands + Tick).
--   lune run tools/balance/conquest
--
-- Setup on Skyshards: a neutral province (terrain, development and garrison set per row) next to a province of
-- nation 1, every other army removed. Nation 1 recruits R regiments next door and orders them in at tick 0.
-- Each row is the average of SEEDS runs (only the ±10% battle rolls differ).

local Army = require("../../src/shared/Sim/Army")
local Commands = require("../../src/shared/Sim/Commands")
local Config = require("../../src/shared/Config")
local Maps = require("../../src/shared/Maps")
local Match = require("../../src/shared/Sim/Match")
local Rng = require("../../src/shared/Sim/Rng")
local Tick = require("../../src/shared/Sim/Tick")
local Types = require("../../src/shared/Types")

local SEEDS = 40
local map = Maps.get("skyshards")

-- a neutral land province with a land neighbour, both away from start territories
local function pickPair(state: Types.MatchState): (number, number)
	local ids = {}
	for id in state.provinces do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local p = state.provinces[id]
		if p.owner == nil and p.terrain ~= "Mountain" then
			for _, n in p.neighbors do
				local q = state.provinces[n]
				if q.owner == nil and q.terrain ~= "Mountain" then
					return id, n
				end
			end
		end
	end
	error("no pair")
end

type Outcome = { won: number, ticks: number, lost: number }

local function attempt(terrain: Types.Terrain, dev: number, garrison: number, regiments: number, seed: number): Outcome
	local state = Match.new(map)
	local target, home = pickPair(state)
	state.armies = {}
	local p = state.provinces[target]
	p.terrain = terrain
	p.development = dev
	state.provinces[home].owner = 1
	Army.spawn(state, 0, target, garrison)
	state.nations[1].gold = 1000
	state.nations[1].manpower = 100000
	assert(Commands.apply(state, 1, { kind = "Recruit", province = home, regiments = regiments }))
	local army = assert(Army.idleAt(state, 1, home))
	assert(Commands.apply(state, 1, { kind = "Move", army = army.id, to = target }))
	local rng = Rng.new(seed)
	local start = regiments * Config.Army.MenPerRegiment
	for t = 1, 400 do
		Tick.advance(state, rng)
		local a = state.armies[army.id]
		if p.owner == 1 then
			return { won = 1, ticks = t, lost = start - (if a then a.men else 0) }
		end
		if a == nil or a.location ~= target and #a.path == 0 then
			return { won = 0, ticks = t, lost = start - (if a then a.men else 0) }
		end
	end
	error("no result")
end

local function average(terrain: Types.Terrain, dev: number, garrison: number, regiments: number): Outcome
	local won, ticks, lost = 0, 0, 0
	for seed = 1, SEEDS do
		local o = attempt(terrain, dev, garrison, regiments, seed)
		won += o.won
		ticks += o.ticks * o.won
		lost += o.lost
	end
	return { won = won / SEEDS, ticks = if won > 0 then ticks / won else 0, lost = lost / SEEDS }
end

print("Time from the order (army next door) to the province flipping, and men lost, averaged over the battle rolls.")
print("Value of a province per month: development × (1 gold + 100 manpower). Cost of losses: 10 gold + 1000 manpower")
print("per 1000 men. Payback counts 100 manpower as 1 gold (the regiment price ratio).\n")
print(
	"| Terrain | Dev | Garrison | Regiments sent | Win | Time to flip (s) | Men lost | Loss cost (gold + manpower) | Payback (months) |"
)
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for _, terrain in { "Plains", "Forest" } :: { Types.Terrain } do
	for _, garrison in { 1000, 2000, 3000 } do
		for _, dev in { 1, 2, 3, 4, 5 } do
			-- the smallest force that always wins, and one regiment more
			local first: number? = nil
			for regiments = 1, 8 do
				local o = average(terrain, dev, garrison, regiments)
				if first == nil and o.won >= 1 then
					first = regiments
				end
				if first and regiments <= first + 1 and (dev == 2 or regiments == first) then
					local gold = o.lost / Config.Army.MenPerRegiment * Config.Army.RegimentGold
					local manpower = o.lost / Config.Army.MenPerRegiment * Config.Army.RegimentManpower
					local value = dev
						* (Config.Economy.GoldPerDevelopment + Config.Economy.ManpowerPerDevelopment / 100)
					print(
						string.format(
							"| %s | %d | %d | %d | %.0f%% | %.1f | %.0f | %.1f + %.0f | %.1f |",
							if terrain == "Forest" then "Forest/Hills" else terrain,
							dev,
							garrison,
							regiments,
							100 * o.won,
							o.ticks,
							o.lost,
							gold,
							manpower,
							(gold + manpower / 100) / value
						)
					)
				end
				if first and regiments >= first + 1 then
					break
				end
			end
		end
	end
end
