--!strict
-- Troop types (docs/DESIGN.md "Troops"): what a regiment of each type costs, how it fights and how fast it marches.
-- An army is still one token and one stack, with a composition: men per troop type (Army.troops), which always adds
-- up to Army.men (Army.setTroops keeps the two in step). Data-driven: every troop is an entry of Config.Troops with a
-- role (ROLES), and every race recruits a roster of five, one troop per role (Config.Races[race].roster), and nothing
-- else: a player is one race for the whole match. Earth's five cultures share four human troops and add their own
-- elite; on Eldmoor and Skyshards each race's five are its own. Neutral garrisons and Rebels are Infantry (BASE).
-- Each special has one trick, a small hook here: siegeSpeed (Troops.siegeSpeed), terrain and vsNeutral
-- (Troops.strength), pathfinder (Troops.moveTicks).

local Config = require("../Config")
local Races = require("./Races")
local Types = require("../Types")

type Troop = Types.Troop
type TroopRole = Types.TroopRole
type Race = Types.Race
type Composition = Types.Composition

export type Stats = {
	name: string,
	role: TroopRole,
	gold: number,
	manpower: number,
	upkeep: number,
	attack: number,
	defence: number,
	fast: boolean?,
	siegeSpeed: number?, -- an army with this troop in it besieges this many times as fast
	terrain: Types.Terrain?, -- with terrainBonus: these men fight better in battles in this terrain
	terrainBonus: number?,
	pathfinder: boolean?, -- forest and hills at plains speed
	vsNeutral: number?, -- these men fight better against neutral garrisons and Rebels
}

local STATS = Config.Troops :: { [string]: Stats }

local Troops = {}

-- The roles, in the recruit buttons' order. Every race recruits one troop of each.
Troops.ROLES = { "line", "ranged", "fast", "elite", "special" } :: { TroopRole }

-- Every troop type in a fixed order, sorted by id (so it never depends on how Config lists them): the network
-- encoding, splitting losses, rounding ties.
Troops.LIST = {} :: { Troop }
for troop in STATS do
	table.insert(Troops.LIST, troop)
end
table.sort(Troops.LIST)

-- What garrisons, Rebels and the tutorial's ready army are made of: Earth's line infantry.
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
	return type(value) == "string" and STATS[value :: string] ~= nil
end

function Troops.stats(troop: Troop): Stats
	return STATS[troop]
end

-- A troop's role (nil for an unknown troop).
function Troops.role(troop: Troop): TroopRole?
	local t = STATS[troop]
	return if t then t.role else nil
end

-- A race's roster: its troop for each role, in ROLES order (empty without a race).
function Troops.roster(race: Race?): { Troop }
	local def = Races.def(race)
	local out = {}
	if def then
		for _, role in Troops.ROLES do
			local troop = def.roster[role]
			if troop and STATS[troop] then
				table.insert(out, troop)
			end
		end
	end
	return out
end

-- The race's troop for a role (nil without a race).
function Troops.ofRole(race: Race?, role: TroopRole): Troop?
	local def = Races.def(race)
	local troop = if def then def.roster[role] else nil
	return if troop and STATS[troop] then troop else nil
end

-- May a nation of this race recruit this troop? Only the five of its roster.
function Troops.canRecruit(race: Race?, troop: Troop): boolean
	return Troops.isTroop(troop) and table.find(Troops.roster(race), troop) ~= nil
end

-- What a nation of this race recruits, in role order: line, ranged, fast, elite, special.
function Troops.available(race: Race?): { Troop }
	return Troops.roster(race)
end

-- What the UI calls a troop.
function Troops.name(troop: Troop): string
	local stats = STATS[troop]
	return if stats then stats.name else troop
end

-- The troop's pixel icon (src/client/IconArt.luau): its id in lower case ("archers", "horsearchers").
function Troops.icon(troop: Troop): string
	return string.lower(troop)
end

local function pct(x: number): string
	return string.format("%d%%", math.floor(x * 100 + 0.5))
end

-- A special's trick in a few words for the UI ("Besieges 2x as fast"), from its numbers in Config.Troops; "" for a
-- troop without one.
function Troops.trickText(troop: Troop): string
	local t = STATS[troop]
	if t == nil then
		return ""
	elseif t.siegeSpeed then
		return string.format("Besieges %gx as fast", t.siegeSpeed)
	elseif t.terrain then
		return string.format("+%s in %s battles", pct(t.terrainBonus or 0), string.lower(t.terrain))
	elseif t.pathfinder then
		return "Forest and hills at plains speed"
	elseif t.vsNeutral then
		return string.format("+%s against garrisons and Rebels", pct(t.vsNeutral))
	end
	return ""
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

-- Combat strength before modifiers: each troop's men times its defence (on the defending side) or its attack, and
-- the specials' tricks that apply: +terrainBonus in a battle in their terrain, +vsNeutral against neutral garrisons
-- and Rebels (`vsNeutral`: the other side is all neutral armies).
function Troops.strength(troops: Composition, defending: boolean, terrain: Types.Terrain?, vsNeutral: boolean?): number
	local s = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men then
			local t = Troops.stats(troop)
			local bonus = 0
			if terrain ~= nil and t.terrain == terrain then
				bonus += t.terrainBonus or 0
			end
			if vsNeutral then
				bonus += t.vsNeutral or 0
			end
			s += men * (if defending then t.defence else t.attack) * (1 + bonus)
		end
	end
	return s
end

-- Ticks to step into a province of this terrain: an army marches at its slowest troop's speed (a pathfinder crosses
-- forest and hills at plains speed).
function Troops.moveTicks(troops: Composition, terrain: Types.Terrain): number
	local slowest = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men and men > 0 then
			local t = Troops.stats(troop)
			local speeds = if t.fast then Config.Army.FastMoveTicks else Config.Army.MoveTicks
			slowest = math.max(slowest, ticksFor(speeds, if t.pathfinder then "Plains" else terrain))
		end
	end
	return if slowest > 0 then slowest else ticksFor(Config.Army.MoveTicks, terrain)
end

-- Siege progress per tick an army of this composition makes: faster with any siege troop in it (Catapults, Sappers,
-- Artillery: Config.Troops siegeSpeed).
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
