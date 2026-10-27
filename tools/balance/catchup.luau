--!strict
-- What the catch-up rules (Sim/CatchUp) do to a growing nation, and the battle break-even ratios they move.
--   lune run tools/balance/catchup     # prints markdown, writes tools/balance/data/catchup.csv
--
-- Income model for the size table: every province at the starting average of 17/8 development, capital owned,
-- no buildings, no upkeep. Break-even ratios use the exact round-by-round battle model from docs/BALANCE.md
-- (no ±10% roll, no rounding): each round A -= k·md·D and D -= k·ma·A at once, k = KillRatePerRound.

local fs = require("@lune/fs")

local CatchUp = require("../../src/shared/Sim/CatchUp")
local Config = require("../../src/shared/Config")
local Maps = require("../../src/shared/Maps")

local AVG_DEV = 17 / 8
local k = Config.Battle.KillRatePerRound

-- Attacker men per defender man that leave both sides equal after Config.Battle.Rounds rounds.
local function breakEven(md: number, ma: number): number
	-- attacker and defender men after the rounds, as linear functions of the start (a0, d0)
	local aA, aD, dA, dD = 1, 0, 0, 1 -- a = aA·a0 + aD·d0, d = dA·a0 + dD·d0
	for _ = 1, Config.Battle.Rounds do
		aA, aD, dA, dD = aA - k * md * dA, aD - k * md * dD, dA - k * ma * aA, dD - k * ma * aD
	end
	-- aA·r + aD = dA·r + dD
	return (dD - aD) / (aA - dA)
end

local function grossGold(provinces: number): number
	return provinces * AVG_DEV * Config.Economy.GoldPerDevelopment + Config.Economy.CapitalGold
end

print("### Overextension\n")
print("| Provinces | Gold multiplier | Gross gold / month (no catch-up) | With overextension | Gold lost / month |")
print("| --- | --- | --- | --- | --- |")
local csv = { "provinces,multiplier,gold_without,gold_with" }
for n = 8, 80 do
	local m = CatchUp.overextension(n)
	local g = grossGold(n)
	table.insert(csv, string.format("%d,%.4f,%.2f,%.2f", n, m, g, g * m))
	if n == 8 or n == 20 or n == 24 or n % 5 == 0 and n >= 25 then
		print(string.format("| %d | %.2f | %.1f | %.1f | %.1f |", n, m, g, g * m, g - g * m))
	end
end

print("\n### Where the thresholds sit on each map\n")
print("| Map | Crown at (25%) | Gold multiplier at the crown | Domination at (40%) | Gold multiplier at 40% |")
print("| --- | --- | --- | --- | --- |")
for _, id in Maps.ids do
	local total = #Maps.get(id).provinces
	local crown = math.ceil(Config.Diplomacy.CoalitionThreshold * total)
	local win = math.ceil(Config.Win.DominationShare * total)
	print(
		string.format(
			"| %s | %d | %.2f | %d | %.2f |",
			id,
			crown,
			CatchUp.overextension(crown),
			win,
			CatchUp.overextension(win)
		)
	)
end

print("\n### Break-even ratios (attacker men needed per defender man to win half the time)\n")
print("| Situation | Defender modifier | Attacker modifier | Break-even |")
print("| --- | --- | --- | --- |")
local function row(name: string, md: number, ma: number)
	print(string.format("| %s | %.2f | %.2f | %.3f |", name, md, ma, breakEven(md, ma)))
end
local t, f = Config.Battle.TerrainDefenceBonus, Config.Buildings.Fort.defenceBonus
local u, c = Config.Battle.UnderdogBonus, Config.Battle.CoalitionBonus
row("Plains", 1, 1)
row("Plains, underdog defends", 1 + u, 1)
row("Plains, coalition attacks the leader", 1, 1 + c)
row("Plains, the leader attacks the coalition", 1 + c, 1)
row("Forest/hills", 1 + t, 1)
row("Forest/hills, underdog defends", 1 + t + u, 1)
row("Fort", 1 + f, 1)
row("Fort + hills", 1 + t + f, 1)
row("Fort + hills, underdog defends against the leader", 1 + t + f + u + c, 1)

fs.writeDir("tools/balance/data")
fs.writeFile("tools/balance/data/catchup.csv", table.concat(csv, "\n") .. "\n")
print("\nwrote tools/balance/data/catchup.csv")
