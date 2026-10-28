--!strict
-- Troop types (docs/DESIGN.md "Troops"): what a regiment of each type costs, how it fights and how fast it marches.
-- An army is still one token and one stack, now with a composition: men per troop type (Army.troops), which always
-- adds up to Army.men (Army.setTroops keeps the two in step). Infantry, archers and cavalry are for every race, plus
-- one elite per race. Neutral garrisons and Rebels are infantry. The numbers are Config.Troops.

local Config = require("../Config")
local Types = require("../Types")

type Troop = Types.Troop
type Race = Types.Race
type Composition = Types.Composition

export type Stats = {
	gold: number,
	manpower: number,
	upkeep: number,
	attack: number,
	defence: number,
	fast: boolean?,
	race: string?,
	siegeSpeed: number?,
}

local Troops = {}

-- Every troop type in a fixed order: the network encoding, the recruit buttons and chips, rounding ties.
Troops.LIST = { "Infantry", "Archers", "Cavalry", "Knights", "Rangers", "Berserkers", "Ironguard" } :: { Troop }

-- What garrisons, Rebels and the tutorial's ready army are made of.
Troops.BASE = "Infantry" :: Troop

local function ticksFor(speeds: { Plains: number, Forest: number, Hills: number }, terrain: Types.Terrain): number
	if terrain == "Forest" then
		return speeds.Forest
	elseif terrain == "Hills" then
		return speeds.Hills
	end
	return speeds.Plains
end

function Troops.isTroop(value: unknown): boolean
	return type(value) == "string" and table.find(Troops.LIST, value :: any) ~= nil
end

function Troops.stats(troop: Troop): Stats
	return (Config.Troops :: any)[troop]
end

-- The elite only this race recruits (nil without a race).
function Troops.elite(race: Race?): Troop?
	if race == nil then
		return nil
	end
	for _, troop in Troops.LIST do
		if Troops.stats(troop).race == race then
			return troop
		end
	end
	return nil
end

-- May a nation of this race recruit this troop? The shared troops yes, an elite only its own race.
function Troops.canRecruit(race: Race?, troop: Troop): boolean
	local only = Troops.stats(troop).race
	return only == nil or only == race
end

-- What a nation of this race recruits, in LIST order: infantry, archers, cavalry and its elite.
function Troops.available(race: Race?): { Troop }
	local out = {}
	for _, troop in Troops.LIST do
		if Troops.canRecruit(race, troop) then
			table.insert(out, troop)
		end
	end
	return out
end

-- Gold and manpower for `regiments` regiments of a troop.
function Troops.cost(troop: Troop, regiments: number): (number, number)
	local t = Troops.stats(troop)
	return regiments * t.gold, regiments * t.manpower
end

-- Gold per month to keep a composition in the field (fractional: 2,400 infantry cost 3.6).
function Troops.upkeep(troops: Composition): number
	local gold = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men then
			gold += men / Config.Army.MenPerRegiment * Troops.stats(troop).upkeep
		end
	end
	return gold
end

-- Combat strength before modifiers: each troop's men × its defence (on the defending side) or its attack.
function Troops.strength(troops: Composition, defending: boolean): number
	local s = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men then
			local t = Troops.stats(troop)
			s += men * (if defending then t.defence else t.attack)
		end
	end
	return s
end

-- Ticks to step into a province of this terrain: an army marches at its slowest troop's speed.
function Troops.moveTicks(troops: Composition, terrain: Types.Terrain): number
	local slowest = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men and men > 0 then
			local speeds = if Troops.stats(troop).fast then Config.Army.FastMoveTicks else Config.Army.MoveTicks
			slowest = math.max(slowest, ticksFor(speeds, terrain))
		end
	end
	return if slowest > 0 then slowest else ticksFor(Config.Army.MoveTicks, terrain)
end

-- Siege progress per tick an army of this composition makes: faster with any Ironguard in it.
function Troops.siegeSpeed(troops: Composition): number
	local speed = 1
	for _, troop in Troops.LIST do
		local men = troops[troop]
		local t = Troops.stats(troop)
		if men and men > 0 and t.siegeSpeed then
			speed = math.max(speed, t.siegeSpeed)
		end
	end
	return speed
end

-- `total` men split over a composition's types in proportion to their men: whole numbers that add up to `total`
-- (largest remainders get the leftover men; ties go to the earlier type in LIST). Losses and a Meteor use it.
function Troops.split(troops: Composition, total: number): Composition
	local men = 0
	for _, troop in Troops.LIST do
		men += troops[troop] or 0
	end
	local out: Composition = {}
	if men <= 0 or total <= 0 then
		return out
	end
	type Part = { troop: Troop, rest: number, order: number }
	local parts: { Part } = {}
	local given = 0
	for i, troop in Troops.LIST do
		local m = troops[troop]
		if m and m > 0 then
			local exact = m * total / men
			local whole = math.floor(exact)
			out[troop] = whole
			given += whole
			table.insert(parts, { troop = troop, rest = exact - whole, order = i })
		end
	end
	table.sort(parts, function(a: Part, b: Part): boolean
		if a.rest ~= b.rest then
			return a.rest > b.rest
		end
		return a.order < b.order
	end)
	local i = 1
	while given < total and i <= #parts do
		local troop = parts[i].troop
		out[troop] = (out[troop] or 0) + 1
		given += 1
		i += 1
	end
	return out
end

-- The composition as text for the network ("Infantry:3000,Archers:1000": LIST order, only the types it has), so an
-- army record stays a flat table of plain values that Snapshot.diff compares by value.
function Troops.encode(troops: Composition): string
	local parts = {}
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men and men > 0 then
			table.insert(parts, troop .. ":" .. men)
		end
	end
	return table.concat(parts, ",")
end

-- Back from Troops.encode (unknown types are skipped).
function Troops.decode(text: string): Composition
	local out: Composition = {}
	for _, part in string.split(text, ",") do
		local name, men = string.match(part, "^(%a+):(%d+)$")
		if name and men and Troops.isTroop(name) then
			out[name :: Troop] = tonumber(men) :: number
		end
	end
	return out
end

return Troops
