--!strict
-- Army orders and movement (tick order step 2): one province per 5 s on plains, 8 s on forest and hills, and
-- 3 s / 6 s for fast troops (cavalry, knights). An army marches at its slowest troop's speed, and Elves cross
-- forest at plains speed (Sim.Troops, Sim.Races). After moving, a nation's armies that stand still in the same
-- province merge into one (the lowest id stays, the compositions add up): an army is a stack of regiments shown as
-- one token. Retreating armies walk on and take no orders.

local Army = require("./Army")
local Diplomacy = require("./Diplomacy")
local Events = require("./Events")
local Pathing = require("./Pathing")
local Races = require("./Races")
local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState

local Movement = {}

local function sortedIds(t: { [number]: any }): { number }
	local ids = {}
	for id in t do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Send an army somewhere. Ordering it to where it stands stops it.
function Movement.order(state: MatchState, nationId: number, armyId: number, to: number): (boolean, string?)
	local army = state.armies[Army.resolve(state, armyId)] -- an army that just merged: the stack it joined
	if army == nil then
		return false, "UnknownArmy"
	end
	if army.owner ~= nationId then
		return false, "NotYourArmy"
	end
	if army.inBattle then
		return false, "InBattle"
	end
	if army.retreating then
		return false, "Retreating"
	end
	if state.provinces[to] == nil then
		return false, "UnknownProvince"
	end
	local path = Pathing.find(state, nationId, army.location, to)
	if path == nil then
		return false, "NoPath"
	end
	-- keep progress if the army keeps heading the same way
	if #path == 0 or army.path[1] ~= path[1] then
		army.moveProgress = 0
	end
	army.path = path
	army.boardFleet = nil -- a new order replaces boarding a fleet (Sim.Navy)
	return true, nil
end

-- Ticks this army takes to step into a province: its slowest troop's speed on that terrain (as plains for Elves
-- in a forest).
function Movement.moveTicks(state: MatchState, army: Types.Army, provinceId: number): number
	local terrain = Races.moveTerrain(Races.of(state, army.owner), state.provinces[provinceId].terrain)
	return Troops.moveTicks(army.troops, terrain)
end

-- Ticks this army still needs to reach the next province (0 if it is not moving).
function Movement.ticksToNext(state: MatchState, army: Types.Army): number
	local nextId = army.path[1]
	if nextId == nil then
		return 0
	end
	return Movement.moveTicks(state, army, nextId) - army.moveProgress
end

-- A nation's armies standing still together (no route, not fighting, not retreating, not about to board a fleet)
-- become one army: the lowest id keeps the men of the others (their compositions add up), which are removed. Each
-- merge is remembered (state.mergedInto, so orders for the removed id reach the stack) and sent as a "Merged" event
-- (a = the army that stays, b = the one removed), so clients don't take the removed token for an army destroyed.
function Movement.mergeStacks(state: MatchState)
	local keeper: { [string]: Types.Army } = {}
	for _, id in sortedIds(state.armies) do
		local army = state.armies[id]
		if
			army.owner ~= 0
			and #army.path == 0
			and not army.inBattle
			and not army.retreating
			and not army.boardFleet
		then
			local key = army.owner .. ":" .. army.location
			local first = keeper[key]
			if first == nil then
				keeper[key] = army
			else
				Army.add(first, army.troops)
				state.armies[id] = nil
				state.mergedInto[id] = first.id
				Events.push(state, "Merged", first.id, id, army.location)
			end
		end
	end
end

function Movement.step(state: MatchState)
	local blocked: { [number]: { [number]: boolean } } = {} -- each owner's blocked sea zones, worked out once a tick
	for _, id in sortedIds(state.armies) do
		local army = state.armies[id]
		local nextId = army.path[1]
		if nextId and not army.inBattle and army.owner ~= 0 then
			local zones = blocked[army.owner]
			if zones == nil then
				zones = Diplomacy.blockedZones(state, army.owner)
				blocked[army.owner] = zones
			end
			if
				not Diplomacy.canEnter(state, army.owner, nextId)
				or not Diplomacy.crossable(state, zones, army.location, nextId)
			then
				-- the way closed (peace was made, an ally left, an enemy fleet blocks the strait): stop here
				army.path = {}
				army.moveProgress = 0
			else
				army.moveProgress += 1
				if army.moveProgress >= Movement.moveTicks(state, army, nextId) then
					army.location = nextId
					table.remove(army.path, 1)
					army.moveProgress = 0
				end
			end
		end
		if army.retreating and #army.path == 0 then
			army.retreating = nil -- home (or the way closed): a normal army again
		end
	end
	Movement.mergeStacks(state)
end

return Movement
