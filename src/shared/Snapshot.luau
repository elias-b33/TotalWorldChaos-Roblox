--!strict
-- What the server sends clients: a full snapshot on join, then a delta of changed records every tick.
-- Records are flat arrays of plain values because RemoteEvents mangle sparse or mixed tables.
-- Neutral owner and "no player" are sent as 0 instead of nil for the same reason. Pure Luau (tested with Lune).

local Types = require("./Types")

type MatchState = Types.MatchState

export type ProvinceRecord = {
	id: number,
	owner: number, -- 0 = neutral
	development: number,
	building: Types.Building,
}

export type NationRecord = {
	id: number,
	name: string,
	colorIndex: number,
	controller: string,
	userId: number, -- 0 = bot
	capital: number,
	gold: number,
	manpower: number,
	charges: number,
	eliminated: boolean,
}

export type ArmyRecord = {
	id: number,
	owner: number,
	location: number,
	men: number,
}

export type SnapshotData = {
	mapId: string,
	tick: number,
	phase: Types.Phase,
	provinces: { ProvinceRecord },
	nations: { NationRecord },
	armies: { ArmyRecord },
}

export type DeltaData = {
	tick: number,
	phase: Types.Phase,
	provinces: { ProvinceRecord },
	nations: { NationRecord },
	armies: { ArmyRecord },
	removedArmies: { number },
}

local Snapshot = {}

local function sortedKeys(t: { [number]: any }): { number }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

function Snapshot.full(state: MatchState): SnapshotData
	local provinces = {}
	for _, id in sortedKeys(state.provinces) do
		local p = state.provinces[id]
		table.insert(provinces, {
			id = p.id,
			owner = p.owner or 0,
			development = p.development,
			building = p.building,
		})
	end
	local nations = {}
	for _, id in sortedKeys(state.nations) do
		local n = state.nations[id]
		table.insert(nations, {
			id = n.id,
			name = n.name,
			colorIndex = n.colorIndex,
			controller = n.controller,
			userId = n.userId or 0,
			capital = n.capital,
			gold = n.gold,
			manpower = n.manpower,
			charges = n.charges,
			eliminated = n.eliminated,
		})
	end
	local armies = {}
	for _, id in sortedKeys(state.armies) do
		local a = state.armies[id]
		table.insert(armies, { id = a.id, owner = a.owner, location = a.location, men = a.men })
	end
	return {
		mapId = state.mapId,
		tick = state.tick,
		phase = state.phase,
		provinces = provinces,
		nations = nations,
		armies = armies,
	}
end

local function sameRecord(a: { [string]: any }, b: { [string]: any }): boolean
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function changed<T>(before: { T }, after: { T }): { T }
	local old: { [number]: T } = {}
	for _, r in before do
		old[(r :: any).id] = r
	end
	local out = {}
	for _, r in after do
		local prev = old[(r :: any).id]
		if prev == nil or not sameRecord(prev :: any, r :: any) then
			table.insert(out, r)
		end
	end
	return out
end

-- Records that differ between two snapshots. Returns nil when nothing changed but the tick.
function Snapshot.diff(before: SnapshotData, after: SnapshotData): DeltaData?
	local removed = {}
	local alive: { [number]: boolean } = {}
	for _, a in after.armies do
		alive[a.id] = true
	end
	for _, a in before.armies do
		if not alive[a.id] then
			table.insert(removed, a.id)
		end
	end
	local delta: DeltaData = {
		tick = after.tick,
		phase = after.phase,
		provinces = changed(before.provinces, after.provinces),
		nations = changed(before.nations, after.nations),
		armies = changed(before.armies, after.armies),
		removedArmies = removed,
	}
	if
		#delta.provinces == 0
		and #delta.nations == 0
		and #delta.armies == 0
		and #removed == 0
		and before.phase == after.phase
	then
		return nil
	end
	return delta
end

local function merge<T>(list: { T }, updates: { T }): { T }
	local index: { [number]: number } = {}
	for i, r in list do
		index[(r :: any).id] = i
	end
	for _, r in updates do
		local i = index[(r :: any).id]
		if i then
			list[i] = r
		else
			table.insert(list, r)
			index[(r :: any).id] = #list
		end
	end
	return list
end

-- Client side: bring a snapshot up to date with a delta (changes it in place and returns it).
function Snapshot.apply(snapshot: SnapshotData, delta: DeltaData): SnapshotData
	snapshot.tick = delta.tick
	snapshot.phase = delta.phase
	merge(snapshot.provinces, delta.provinces)
	merge(snapshot.nations, delta.nations)
	merge(snapshot.armies, delta.armies)
	if #delta.removedArmies > 0 then
		local gone: { [number]: boolean } = {}
		for _, id in delta.removedArmies do
			gone[id] = true
		end
		local kept = {}
		for _, a in snapshot.armies do
			if not gone[a.id] then
				table.insert(kept, a)
			end
		end
		snapshot.armies = kept
	end
	return snapshot
end

return Snapshot
