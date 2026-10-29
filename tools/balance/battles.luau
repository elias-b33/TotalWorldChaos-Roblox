--!strict
-- Monte-Carlo battles through the real Sim/Battle code: win probability and losses against strength ratio.
--   lune run tools/balance/battles            # prints the markdown tables, writes tools/balance/data/battles.csv
--   TRIALS=5000 lune run tools/balance/battles
--
-- Arena: three provinces in a row (attacker home - battlefield - defender home), nation 1 attacks nation 2 in
-- nation 2's province. Battle.bonus is replaced by a fixed bonus per case, so catch-up effects are measured
-- on purpose and never by accident.

local fs = require("@lune/fs")
local process = require("@lune/process")

local Battle = require("../../src/shared/Sim/Battle")
local Config = require("../../src/shared/Config")
local Rng = require("../../src/shared/Sim/Rng")
local Types = require("../../src/shared/Types")

local TRIALS = tonumber(process.env.TRIALS) or 2000
local DEFENDER_MEN = 3000

type Case = {
	name: string,
	terrain: Types.Terrain,
	building: Types.Building,
	neutral: boolean, -- defender is a neutral garrison (no fort bonus, never retreats)
	attackerBonus: number, -- catch-up bonus for the attacker
	defenderBonus: number,
	defenderMen: number,
}

local CASES: { Case } = {
	{
		name = "Plains",
		terrain = "Plains",
		building = "None",
		neutral = false,
		attackerBonus = 0,
		defenderBonus = 0,
		defenderMen = DEFENDER_MEN,
	},
	{
		name = "Forest/Hills",
		terrain = "Forest",
		building = "None",
		neutral = false,
		attackerBonus = 0,
		defenderBonus = 0,
		defenderMen = DEFENDER_MEN,
	},
	{
		name = "Fort (plains)",
		terrain = "Plains",
		building = "Fort",
		neutral = false,
		attackerBonus = 0,
		defenderBonus = 0,
		defenderMen = DEFENDER_MEN,
	},
	{
		name = "Fort + hills",
		terrain = "Hills",
		building = "Fort",
		neutral = false,
		attackerBonus = 0,
		defenderBonus = 0,
		defenderMen = DEFENDER_MEN,
	},
	{
		name = "Underdog defends (plains)",
		terrain = "Plains",
		building = "None",
		neutral = false,
		attackerBonus = 0,
		defenderBonus = Config.Battle.UnderdogBonus,
		defenderMen = DEFENDER_MEN,
	},
	{
		name = "Coalition attacks leader (plains)",
		terrain = "Plains",
		building = "None",
		neutral = false,
		attackerBonus = Config.Battle.CoalitionBonus,
		defenderBonus = 0,
		defenderMen = DEFENDER_MEN,
	},
	{
		name = "Neutral garrison 1000 (plains)",
		terrain = "Plains",
		building = "None",
		neutral = true,
		attackerBonus = 0,
		defenderBonus = 0,
		defenderMen = 1000,
	},
	{
		name = "Neutral garrison 1000 (forest/hills)",
		terrain = "Forest",
		building = "None",
		neutral = true,
		attackerBonus = 0,
		defenderBonus = 0,
		defenderMen = 1000,
	},
}

local RATIOS = { 0.5, 0.75, 0.9, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.4, 1.5, 1.75, 2.0, 2.5, 3.0 }

local function province(id: number, terrain: Types.Terrain, owner: number?, neighbors: { number }): Types.Province
	return {
		id = id,
		name = "P" .. id,
		terrain = terrain,
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
		race = "Humans", -- no combat bonus: battles here measure the bare rules
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

local function arena(case: Case, attackerMen: number, defenderMen: number): Types.MatchState
	local field = province(1, case.terrain, if case.neutral then nil else 2, { 2, 3 })
	field.building = case.building
	local state: Types.MatchState = {
		mapId = "arena",
		tick = 0,
		phase = "War",
		provinces = { [1] = field, [2] = province(2, "Plains", 1, { 1 }), [3] = province(3, "Plains", 2, { 1 }) },
		nations = { [1] = nation(1), [2] = nation(2) },
		armies = {
			[1] = {
				id = 1,
				owner = if case.neutral then 0 else 2,
				location = 1,
				men = defenderMen,
				troops = { Infantry = defenderMen },
				path = {},
				moveProgress = 0,
				inBattle = false,
				morale = Config.Battle.MoraleMax,
			},
			[2] = {
				id = 2,
				owner = 1,
				location = 1,
				men = attackerMen,
				troops = { Infantry = attackerMen },
				path = {},
				moveProgress = 0,
				inBattle = false,
				morale = Config.Battle.MoraleMax,
			},
		},
		wars = { [1] = { id = 1, attackers = { 1 }, defenders = { 2 }, startedAt = 0 } },
		alliances = {},
		truces = {},
		primordials = {},
		battles = {},
		offers = {},
		events = {},
		result = nil,
	}
	return state
end

export type Row = {
	case: string,
	ratio: number,
	win: number, -- attacker win probability
	attLoss: number, -- mean share of the attacker's men lost (dead, not counting a destroyed remnant)
	defLoss: number,
	attDestroyed: number, -- probability the attacker's army is gone afterwards
	defDestroyed: number,
}

local function run(case: Case, ratio: number, rng: Rng.Rng): Row
	Battle.bonus = function(_state, _owners, _enemies, defending: boolean): number
		return if defending then case.defenderBonus else case.attackerBonus
	end
	local defMen = case.defenderMen
	local attMen = math.floor(defMen * ratio + 0.5)
	local wins, attLoss, defLoss, attGone, defGone = 0, 0, 0, 0, 0
	for _ = 1, TRIALS do
		local state = arena(case, attMen, defMen)
		for _ = 1, Config.Battle.Rounds do
			Battle.step(state, rng)
		end
		local att, def = state.armies[2], state.armies[1]
		-- the attacker won if it still stands on the battlefield (a beaten army walks off: Army.retreating)
		if att and not att.retreating then
			wins += 1
		end
		attGone += if att then 0 else 1
		defGone += if def then 0 else 1
		-- losses from the battle itself: read the dead from the last round (destroyed armies count all their men)
		attLoss += (attMen - (if att then att.men else 0)) / attMen
		defLoss += (defMen - (if def then def.men else 0)) / defMen
	end
	return {
		case = case.name,
		ratio = ratio,
		win = wins / TRIALS,
		attLoss = attLoss / TRIALS,
		defLoss = defLoss / TRIALS,
		attDestroyed = attGone / TRIALS,
		defDestroyed = defGone / TRIALS,
	}
end

local rng = Rng.new(20261027)
local rows: { Row } = {}
local csv = { "case,ratio,win,att_loss,def_loss,att_destroyed,def_destroyed" }
for _, case in CASES do
	print(string.format("\n### %s (defender %d men, %d trials per row)\n", case.name, case.defenderMen, TRIALS))
	print(
		"| Attacker : defender | Attacker wins | Attacker loses (incl. destroyed) | Defender loses | Attacker army destroyed | Defender army destroyed |"
	)
	print("| --- | --- | --- | --- | --- | --- |")
	for _, ratio in RATIOS do
		local r = run(case, ratio, rng)
		table.insert(rows, r)
		print(
			string.format(
				"| %.2f | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% |",
				ratio,
				100 * r.win,
				100 * r.attLoss,
				100 * r.defLoss,
				100 * r.attDestroyed,
				100 * r.defDestroyed
			)
		)
		table.insert(
			csv,
			string.format(
				"%s,%.2f,%.4f,%.4f,%.4f,%.4f,%.4f",
				case.name,
				ratio,
				r.win,
				r.attLoss,
				r.defLoss,
				r.attDestroyed,
				r.defDestroyed
			)
		)
	end
end

-- the ratio where the attacker starts winning half the time, per case
print("\n### Break-even ratio (attacker wins 50%)\n")
print("| Case | Break-even attacker : defender |")
print("| --- | --- |")
for _, case in CASES do
	Battle.bonus = function(_state, _owners, _enemies, defending: boolean): number
		return if defending then case.defenderBonus else case.attackerBonus
	end
	local lo, hi = 0.5, 3.0
	for _ = 1, 20 do
		local mid = (lo + hi) / 2
		local r = run(case, mid, Rng.new(7))
		if r.win < 0.5 then
			lo = mid
		else
			hi = mid
		end
	end
	print(string.format("| %s | %.3f |", case.name, (lo + hi) / 2))
end

fs.writeDir("tools/balance/data")
fs.writeFile("tools/balance/data/battles.csv", table.concat(csv, "\n") .. "\n")
print("\nwrote tools/balance/data/battles.csv")
