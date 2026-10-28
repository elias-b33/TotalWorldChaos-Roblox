--!strict
-- What the UI says and shows about races and troops (docs/DESIGN.md "Races", "Troops"): each race's name, pixel icon
-- and one-line bonus, each troop's name and icon on the current map (a map can rename the shared roles: Skyshards'
-- troopers, gunners and hover bikes), and an army's composition and main troop type from its record. Numbers come
-- from Config, so the text follows a balance change (Sim.Races.bonusText, tested under Lune).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Races = require(Shared.Sim.Races)
local Troops = require(Shared.Sim.Troops)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local MapBadges = require(script.Parent.MapBadges)

local RaceInfo = {}

local function goldPerRegiment(troop: string): number
	return Troops.stats(troop :: Types.Troop).gold
end

local function mapId(): string?
	local map = ClientState.map()
	return if map then map.id else nil
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

-- What a troop is called on the map being played (Troops.name: Skyshards calls infantry "Troopers").
function RaceInfo.troopName(troop: string): string
	return Troops.name(mapId(), troop :: Types.Troop)
end

-- A troop's pixel icon on the map being played (Troops.icon).
function RaceInfo.troopIcon(troop: string): string
	return Troops.icon(mapId(), troop :: Types.Troop)
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
	return if main then RaceInfo.troopIcon(main) else "sword"
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
