--!strict
-- Troop matchups (docs/BALANCE.md section 18) through the real Sim/Battle code, the random roll off: how many men an
-- attacking stack of one troop type needs per defending man of another type to win on plains (the break-even
-- ratio, below 1 = the attacker's troop is the better fighter), and what each troop costs to keep per regiment.
--   lune run tools/balance/troops
--
-- Arena as in tools/balance/battles.luau: nation 1 attacks nation 2's plains province, Battle.bonus off.

local Army = require("../../src/shared/Sim/Army")
local Battle = require("../../src/shared/Sim/Battle")
local Config = require("../../src/shared/Config")
local Rng = require("../../src/shared/Sim/Rng")
local Troops = require("../../src/shared/Sim/Troops")
local Types = require("../../src/shared/Types")

Config.Battle.RandomSpread = 0
Battle.bonus = function(): number
	return 0
end

local DEFENDER_MEN = 3000

local function province(id: number, owner: number, neighbors: { number }): Types.Province
	return {
		id = id,
		name = "P" .. id,
		terrain = "Plains",
		neighbors = neighbors,
		owner = owner,
		development = 2,
		building = "None",
		isCapital = false,
		siege = nil,
		shieldUntil = nil,
		buffs = {},
	}
end

local function nation(id: number): Types.Nation
	return {
		id = id,
		name = "N" .. id,
		colorIndex = id,
		race = "Humans", -- no race bonus on plains
		controller = "Bot",
		userId = nil,
		capital = id + 1,
		gold = 0,
		manpower = 0,
		charges = 0,
		allianceId = nil,
		powerImmuneUntil = 0,
		eliminated = false,
		battlesWon = 0,
	}
end

-- Does `attMen` men of troop `att` beat 3,000 men of troop `def` defending (more men standing after 3 rounds)?
local function attackerWins(att: Types.Troop, attMen: number, def: Types.Troop): boolean
	local state: Types.MatchState = {
		mapId = "arena",
		setup = { private = false, settings = {} :: any },
		tick = 0,
		phase = "War",
		provinces = { [1] = province(1, 2, { 2, 3 }), [2] = province(2, 1, { 1 }), [3] = province(3, 2, { 1 }) },
		nations = { [1] = nation(1), [2] = nation(2) },
		armies = {},
		wars = { [1] = { id = 1, attackers = { 1 }, defenders = { 2 }, startedAt = 0 } },
		alliances = {},
		truces = {},
		primordials = {},
		seats = {},
		nextArmyId = 1,
		mergedInto = {},
		battles = {},
		zones = {}, -- no sea in the arena
		shores = {},
		straits = {},
		fleets = {},
		nextFleetId = 1,
		fleetMergedInto = {},
		seaBattles = {},
		offers = {},
		events = {},
		result = nil,
	}
	Army.spawn(state, 2, 1, DEFENDER_MEN, def)
	local attacker = Army.spawn(state, 1, 1, attMen, att)
	local rng = Rng.new(1)
	for _ = 1, Config.Battle.Rounds do
		Battle.step(state, rng)
	end
	return state.armies[attacker.id] ~= nil and not attacker.retreating
end

-- The fewest attacking men (in steps of 10) that win, as a ratio to the defenders.
local function breakEven(att: Types.Troop, def: Types.Troop): number
	local lo, hi = 0, 10 * DEFENDER_MEN
	while hi - lo > 10 do
		local mid = (lo + hi) // 2
		if attackerWins(att, mid, def) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi / DEFENDER_MEN
end

print("### Break-even attacker : defender on plains (rows attack, columns defend)\n")
local header = { "| Attacker \\ defender" }
local rule = { "| ---" }
for _, def in Troops.LIST do
	table.insert(header, def)
	table.insert(rule, "---")
end
print(table.concat(header, " | ") .. " |")
print(table.concat(rule, " | ") .. " |")
for _, att in Troops.LIST do
	local row = { "| " .. att }
	for _, def in Troops.LIST do
		table.insert(row, string.format("%.2f", breakEven(att, def)))
	end
	print(table.concat(row, " | ") .. " |")
end

print("\n### What a regiment costs and gives\n")
print(
	"| Troop | Gold | Manpower | Upkeep | Attack | Defence | Attack per upkeep | Defence per upkeep | vs infantry: attack men per upkeep | defence men per upkeep |"
)
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
local inf = Troops.stats("Infantry")
for _, troop in Troops.LIST do
	local t = Troops.stats(troop)
	-- the men of infantry a regiment of this troop is worth (break-even against infantry), per gold of upkeep,
	-- relative to infantry's
	local attackWorth = 1 / breakEven(troop, "Infantry")
	local defenceWorth = breakEven("Infantry", troop)
	print(
		string.format(
			"| %s | %d | %d | %.1f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |",
			troop,
			t.gold,
			t.manpower,
			t.upkeep,
			t.attack,
			t.defence,
			t.attack / t.upkeep,
			t.defence / t.upkeep,
			attackWorth / t.upkeep * inf.upkeep,
			defenceWorth / t.upkeep * inf.upkeep
		)
	)
end
