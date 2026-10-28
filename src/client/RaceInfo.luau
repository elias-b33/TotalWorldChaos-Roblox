--!strict
-- What the UI says and shows about races and troops (docs/DESIGN.md "Races", "Troops"): each race's pixel icon and
-- one-line bonus, each troop's icon, and an army's composition from its record. Numbers come from Config, so the text
-- follows a balance change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Troops = require(Shared.Sim.Troops)
local Types = require(Shared.Types)

local RaceInfo = {}

local function pct(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- The pixel icon of a race or a troop type (src/client/IconArt.luau: "humans", "archers"...).
function RaceInfo.icon(raceOrTroop: string): string
	return string.lower(raceOrTroop)
end

-- A race's passive in one short line.
function RaceInfo.bonus(race: string): string
	local r = Config.Races
	if race == "Humans" then
		return "+" .. pct(r.Humans.goldBonus) .. " gold"
	elseif race == "Elves" then
		return "Fast in forests, +" .. pct(r.Elves.forestBonus) .. " in forest battles"
	elseif race == "Orcs" then
		return "+" .. pct(r.Orcs.manpowerBonus) .. " manpower"
	elseif race == "Dwarves" then
		return "+"
			.. pct(r.Dwarves.hillsDefenceBonus)
			.. " defending hills, forts -"
			.. pct(1 - r.Dwarves.fortCostMultiplier)
	end
	return ""
end

-- What a nation of this race can recruit, in button order: infantry, archers, cavalry, its elite.
function RaceInfo.troops(race: string): { Types.Troop }
	return Troops.available(race :: Types.Race)
end

-- An army record's composition, as { troop, men } in LIST order (the army sheet's chips).
function RaceInfo.composition(troops: string): { { troop: Types.Troop, men: number } }
	local parts = Troops.decode(troops)
	local out = {}
	for _, troop in Troops.LIST do
		local men = parts[troop]
		if men and men > 0 then
			table.insert(out, { troop = troop, men = men })
		end
	end
	return out
end

return RaceInfo
