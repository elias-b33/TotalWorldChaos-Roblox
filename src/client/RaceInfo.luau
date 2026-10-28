--!strict
-- What the UI says and shows about races and troops (docs/DESIGN.md "Races", "Troops"): each race's pixel icon and
-- one-line bonus, each troop's icon, and an army's composition and main troop type from its record. Numbers come
-- from Config, so the text follows a balance change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Troops = require(Shared.Sim.Troops)
local Types = require(Shared.Types)

local MapBadges = require(script.Parent.MapBadges)

local RaceInfo = {}

local function goldPerRegiment(troop: string): number
	return Troops.stats(troop :: Types.Troop).gold
end

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

-- The troop type an army record is mostly made of: the most men, a tie to the dearer troop (MapBadges.mainTroop).
-- nil for an empty composition.
function RaceInfo.mainTroop(troops: string): Types.Troop?
	local main = MapBadges.mainTroop(Troops.decode(troops) :: any, Troops.LIST :: any, goldPerRegiment)
	return main :: Types.Troop?
end

-- The icon for an army record in the province sheet's chips: its main troop type's, or a sword.
function RaceInfo.mainTroopIcon(troops: string): string
	local main = RaceInfo.mainTroop(troops)
	return if main then RaceInfo.icon(main) else "sword"
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
