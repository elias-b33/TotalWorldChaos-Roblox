--!strict
-- Breadth-first paths along province neighbours (docs/DESIGN.md "Armies and combat").

local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Types = require("../Types")

type MatchState = Types.MatchState

local Pathing = {}

-- Generic BFS: the route from `from` to `to` (excluding `from`), {} if they are the same, nil if unreachable.
-- The client uses this too, with its own neighbour and access functions, to preview paths.
function Pathing.search(
	neighborsOf: (number) -> { number },
	canEnter: (number) -> boolean,
	from: number,
	to: number
): { number }?
	if from == to then
		return {}
	end
	if not canEnter(to) then
		return nil
	end
	local cameFrom: { [number]: number } = { [from] = from }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, n in neighborsOf(cur) do
			if cameFrom[n] == nil and canEnter(n) then
				cameFrom[n] = cur
				if n == to then
					local path = { n }
					local step = cur
					while step ~= from do
						table.insert(path, 1, step)
						step = cameFrom[step]
					end
					return path
				end
				table.insert(queue, n)
			end
		end
	end
	return nil
end

function Pathing.find(state: MatchState, nationId: number, from: number, to: number): { number }?
	return Pathing.search(function(id)
		return state.provinces[id].neighbors
	end, function(id)
		return Diplomacy.canEnter(state, nationId, id)
	end, from, to)
end

-- The route to the nearest province `owner` holds, other than `from`, over land its armies may enter (fewest
-- steps; ties go to the lower province id). nil if there is none. Used for retreats.
function Pathing.retreatPath(state: MatchState, owner: number, from: number): { number }?
	local cameFrom: { [number]: number } = { [from] = from }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local next = table.clone(state.provinces[cur].neighbors)
		table.sort(next)
		for _, n in next do
			if cameFrom[n] == nil and Diplomacy.canEnter(state, owner, n) then
				cameFrom[n] = cur
				if state.provinces[n].owner == owner then
					local path = { n }
					local step = cur
					while step ~= from do
						table.insert(path, 1, step)
						step = cameFrom[step]
					end
					return path
				end
				table.insert(queue, n)
			end
		end
	end
	return nil
end

-- Ticks to step into a province of this terrain.
function Pathing.moveTicks(terrain: Types.Terrain): number
	if terrain == "Forest" then
		return Config.Army.MoveTicks.Forest
	elseif terrain == "Hills" then
		return Config.Army.MoveTicks.Hills
	end
	return Config.Army.MoveTicks.Plains
end

return Pathing
