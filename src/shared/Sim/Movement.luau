--!strict
-- Army orders and movement (tick order step 2): one province per 5 s on plains, 8 s on forest and hills.

local Diplomacy = require("./Diplomacy")
local Pathing = require("./Pathing")
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
	local army = state.armies[armyId]
	if army == nil then
		return false, "UnknownArmy"
	end
	if army.owner ~= nationId then
		return false, "NotYourArmy"
	end
	if army.inBattle then
		return false, "InBattle"
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
	return true, nil
end

-- Ticks this army still needs to reach the next province (0 if it is not moving).
function Movement.ticksToNext(state: MatchState, army: Types.Army): number
	local nextId = army.path[1]
	if nextId == nil then
		return 0
	end
	return Pathing.moveTicks(state.provinces[nextId].terrain) - army.moveProgress
end

function Movement.step(state: MatchState)
	for _, id in sortedIds(state.armies) do
		local army = state.armies[id]
		local nextId = army.path[1]
		if nextId and not army.inBattle and army.owner ~= 0 then
			if not Diplomacy.canEnter(state, army.owner, nextId) then
				-- the way closed (peace was made, an ally left): stop here
				army.path = {}
				army.moveProgress = 0
			else
				army.moveProgress += 1
				if army.moveProgress >= Pathing.moveTicks(state.provinces[nextId].terrain) then
					army.location = nextId
					table.remove(army.path, 1)
					army.moveProgress = 0
				end
			end
		end
	end
end

return Movement
