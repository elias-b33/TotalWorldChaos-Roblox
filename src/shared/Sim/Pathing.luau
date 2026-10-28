--!strict
-- Breadth-first paths along province neighbours (docs/DESIGN.md "Armies and combat"). A strait whose sea zone holds
-- a fleet at war with the army's owner is closed to it (docs/DESIGN.md "Navies", Diplomacy.crossable).

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

-- A province's neighbours an army may step to: all of them, minus straits in `blocked` sea zones
-- (Diplomacy.blockedZones). The neighbour list itself when nothing is blocked.
function Pathing.open(state: MatchState, blocked: { [number]: boolean }, id: number): { number }
	local neighbors = state.provinces[id].neighbors
	if next(blocked) == nil then
		return neighbors
	end
	local out = {}
	for _, n in neighbors do
		if Diplomacy.crossable(state, blocked, id, n) then
			table.insert(out, n)
		end
	end
	return out
end

function Pathing.find(state: MatchState, nationId: number, from: number, to: number): { number }?
	local blocked = Diplomacy.blockedZones(state, nationId)
	return Pathing.search(function(id)
		return Pathing.open(state, blocked, id)
	end, function(id)
		return Diplomacy.canEnter(state, nationId, id)
	end, from, to)
end

-- Generic BFS to the nearest province `want` accepts (fewest steps; ties go to the lower province id): {} if `from`
-- itself is wanted, nil if none is reachable. The client previews embarking with it, with its own neighbour and access
-- functions.
function Pathing.searchNearest(
	neighborsOf: (number) -> { number },
	canEnter: (number) -> boolean,
	from: number,
	want: (number) -> boolean
): { number }?
	if want(from) then
		return {}
	end
	local cameFrom: { [number]: number } = { [from] = from }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local nexts = table.clone(neighborsOf(cur))
		table.sort(nexts)
		for _, n in nexts do
			if cameFrom[n] == nil and canEnter(n) then
				cameFrom[n] = cur
				if want(n) then
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

-- The route to the nearest province `want` accepts, over land this nation's armies may enter (Pathing.searchNearest).
-- Embarking uses it to find a coast of the fleet's zone.
function Pathing.nearest(state: MatchState, nationId: number, from: number, want: (number) -> boolean): { number }?
	local blocked = Diplomacy.blockedZones(state, nationId)
	return Pathing.searchNearest(function(id)
		return Pathing.open(state, blocked, id)
	end, function(id)
		return Diplomacy.canEnter(state, nationId, id)
	end, from, want)
end

-- The route to the nearest province `owner` holds, other than `from`, over land its armies may enter (fewest
-- steps; ties go to the lower province id). nil if there is none. Used for retreats, and to walk home from a land
-- whose military access just ended: `through` (that land's owner) counts as land the army may cross. Straits closed
-- by enemy fleets stay closed either way.
function Pathing.retreatPath(state: MatchState, owner: number, from: number, through: number?): { number }?
	local blocked = Diplomacy.blockedZones(state, owner)
	local cameFrom: { [number]: number } = { [from] = from }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local next = table.clone(Pathing.open(state, blocked, cur))
		table.sort(next)
		for _, n in next do
			local p = state.provinces[n]
			local crossable = through ~= nil and p.owner == through and p.terrain ~= "Mountain"
			if cameFrom[n] == nil and (crossable or Diplomacy.canEnter(state, owner, n)) then
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
