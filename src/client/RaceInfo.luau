--!strict
-- What the UI says and shows about races and troops (docs/DESIGN.md "Races", "Troops"): each race's name, pixel icon
-- and one-line bonus, its roster of five troops (one per role), each troop's name, icon and trick, and an army's
-- composition and main troop type from its record. Numbers come from Config, so the text follows a balance change
-- (Sim.Races.bonusText, Sim.Troops.trickText, tested under Lune).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Races = require(Shared.Sim.Races)
local Troops = require(Shared.Sim.Troops)
local Types = require(Shared.Types)

local MapBadges = require(script.Parent.MapBadges)

local RaceInfo = {}

local function goldPerRegiment(troop: string): number
	return Troops.stats(troop :: Types.Troop).gold
end

-- What the UI calls a race ("Kingdom", "Crystal folk").
function RaceInfo.name(race: string): string
	return Races.name(race :: Types.Race)
end

-- The pixel icon of a race (src/client/IconArt.luau: "humans", "kingdom"...).
function RaceInfo.icon(race: string): string
	return string.lower(race)
end

-- A race's passive in one short line.
function RaceInfo.bonus(race: string): string
	return Races.bonusText(race :: Types.Race)
end

-- What a troop is called ("Elk riders").
function RaceInfo.troopName(troop: string): string
	return Troops.name(troop :: Types.Troop)
end

-- A troop's pixel icon (Troops.icon).
function RaceInfo.troopIcon(troop: string): string
	return Troops.icon(troop :: Types.Troop)
end

-- A special troop's trick in a few words ("Besieges 2x as fast"); "" for the others.
function RaceInfo.troopTrick(troop: string): string
	return Troops.trickText(troop :: Types.Troop)
end

-- What a nation of this race can recruit, in button order: its line, ranged, fast, elite and special troops.
function RaceInfo.troops(race: string): { Types.Troop }
	return Troops.roster(race :: Types.Race)
end

-- The race's line troop (the tutorial's recruit prompt points at it); Infantry without a race.
function RaceInfo.lineTroop(race: string?): Types.Troop
	return Troops.ofRole(race :: Types.Race?, "line") or Troops.BASE
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
	return if main then RaceInfo.troopIcon(main) else "sword"
end

-- An army record's composition, as { troop, men } in role order (the army sheet's chips).
function RaceInfo.composition(troops: string): { { troop: Types.Troop, men: number } }
	local parts = Troops.decode(troops)
	local out = {}
	for _, troop in Troops.LIST do
		local men = parts[troop]
		if men and men > 0 then
			table.insert(out, { troop = troop, men = men })
		end
	end
	local function rank(troop: Types.Troop): number
		return table.find(Troops.ROLES, Troops.role(troop) or "line") or 0
	end
	table.sort(out, function(a, b)
		if rank(a.troop) ~= rank(b.troop) then
			return rank(a.troop) < rank(b.troop)
		end
		return a.troop < b.troop
	end)
	return out
end

return RaceInfo
