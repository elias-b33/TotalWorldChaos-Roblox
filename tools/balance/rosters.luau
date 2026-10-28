--!strict
-- The five-troop rosters at a glance (docs/BALANCE.md section 19): every race's troops with their price, upkeep and
-- strength per gold of upkeep (what limits a bot's army: income / upkeep), relative to Earth's Infantry; then each
-- race's army as bots raise it (the role mix of the last tournament, Config.Bots' shares) and its strength per gold
-- of upkeep attacking and defending, with the Upkeep passive in it (the other passives are situational).
--   lune run tools/balance/rosters
--   lune run tools/balance/rosters md     # docs/DESIGN.md "Troops": one Markdown roster table per race, from Config
--   lune run tools/balance/rosters passives   # every race's passive with its numbers (docs/DESIGN.md "Races")

local process = require("@lune/process")

local Config = require("../../src/shared/Config")
local Races = require("../../src/shared/Sim/Races")
local Troops = require("../../src/shared/Sim/Troops")

if process.args[1] == "passives" then
	-- every race's passive and its numbers, one line each ("Kingdom\tGold: +10% gold"): docs/DESIGN.md "Races"
	for _, race in Races.LIST do
		print(string.format("%s\t%s: %s", Races.name(race), Races.passive(race) or "", Races.bonusText(race)))
	end
	return
end

if process.args[1] == "md" then
	local function num(x: number): string
		return (string.gsub(string.format("%.2f", x), "%.?0+$", ""))
	end
	local function men(x: number): string
		return if x >= 1000 then string.format("%d,%03d", x // 1000, x % 1000) else tostring(x)
	end
	local function row(role: string, troop: string)
		local t = Troops.stats(troop)
		local trick = Troops.trickText(troop)
		print(
			string.format(
				"| %s | %s | %d gold + %s manpower | %s | %s | %s | %s%s |",
				role,
				t.name,
				t.gold,
				men(t.manpower),
				num(t.upkeep),
				num(t.attack),
				num(t.defence),
				if t.fast then "fast" else "normal",
				if trick ~= "" then "; " .. string.lower(string.sub(trick, 1, 1)) .. string.sub(trick, 2) else ""
			)
		)
	end
	local function header(title: string)
		print(title .. "\n")
		print("| Role | Troop | Cost | Upkeep | Attack | Defence | Speed and trick |")
		print("| --- | --- | --- | --- | --- | --- | --- |")
	end
	-- Earth: one table, the four human troops every culture shares and each culture's elite
	local earth = Races.forMap("earth")
	header("**Earth: every culture**")
	for _, role in Troops.ROLES do
		if role == "elite" then
			for _, race in earth do
				row("elite (" .. Races.name(race) .. ")", Troops.ofRole(race, "elite") :: string)
			end
		else
			row(role, Troops.ofRole(earth[1], role) :: string)
		end
	end
	print("")
	for _, mapId in { "eldmoor", "skyshards" } do
		for _, race in Races.forMap(mapId) do
			header(string.format("**%s** (%s)", Races.name(race), Races.bonusText(race)))
			for _, troop in Troops.roster(race) do
				row(Troops.stats(troop).role, troop)
			end
			print("")
		end
	end
	return
end

-- regiments bots recruit by role (tournament, 200 seeds per map: docs/BALANCE.md section 19)
local MIX = { line = 0.57, ranged = 0.25, fast = 0.06, elite = 0.05, special = 0.07 }

local inf = Troops.stats("Infantry")
local infAtt, infDef = inf.attack / inf.upkeep, inf.defence / inf.upkeep

local function f2(x: number): string
	return string.format("%.2f", x)
end

for _, mapId in { "earth", "eldmoor", "skyshards" } do
	print(string.format("\n== %s ==", mapId))
	for _, race in Races.forMap(mapId) do
		local upkeepMul = Races.upkeepMultiplier(race)
		local att, def, gold, manpower = 0, 0, 0, 0
		local rows = {}
		for _, troop in Troops.roster(race) do
			local t = Troops.stats(troop)
			local up = t.upkeep * upkeepMul
			local share = MIX[t.role]
			att += share * t.attack / up
			def += share * t.defence / up
			gold += share * t.gold
			manpower += share * t.manpower
			local trick = Troops.trickText(troop)
			table.insert(
				rows,
				string.format(
					"  %-8s %-16s %3dg %4dmp up %-4s att %-4s def %-4s  per upkeep: att %s def %s%s",
					t.role,
					t.name,
					t.gold,
					t.manpower,
					tostring(t.upkeep),
					tostring(t.attack),
					tostring(t.defence),
					f2(t.attack / up / infAtt),
					f2(t.defence / up / infDef),
					if trick ~= "" then "  (" .. trick .. ")" else ""
				)
			)
		end
		print(
			string.format(
				"%-12s %-8s  army per upkeep: att %s def %s  avg regiment %.1fg %dmp  %s",
				Races.name(race),
				Races.passive(race) or "",
				f2(att / infAtt),
				f2(def / infDef),
				gold,
				math.floor(manpower),
				Races.bonusText(race)
			)
		)
		for _, row in rows do
			print(row)
		end
	end
end
print(
	string.format(
		"\n(Bots: RangedShare %s, SpecialShare %s, EliteShare %s, FastShare %s)",
		tostring(Config.Bots.RangedShare),
		tostring(Config.Bots.SpecialShare),
		tostring(Config.Bots.EliteShare),
		tostring(Config.Bots.FastShare)
	)
)
