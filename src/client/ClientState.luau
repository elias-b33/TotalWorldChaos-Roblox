--!strict
-- The client's copy of the match: filled by the Snapshot remote, kept current by Delta.
-- Other client modules read from here and subscribe to changes. The client never changes the match itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Maps = require(Shared.Maps)
local Remotes = require(Shared.Remotes)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

type Listener<T> = (T) -> ()

local ClientState = {}

local snapshot: Snapshot.SnapshotData? = nil
local map: Types.MapDef? = nil
local myNationId = 0
local tickReceivedAt = os.clock()

local resetListeners: { Listener<Snapshot.SnapshotData> } = {}
local deltaListeners: { Listener<Snapshot.DeltaData> } = {}

local function emit<T>(listeners: { Listener<T> }, value: T)
	for _, fn in listeners do
		task.spawn(fn, value)
	end
end

function ClientState.init()
	Remotes.event("Snapshot").OnClientEvent:Connect(function(data: Snapshot.SnapshotData, nationId: number)
		snapshot = data
		map = Maps.get(data.mapId)
		myNationId = nationId
		tickReceivedAt = os.clock()
		emit(resetListeners, data)
	end)
	Remotes.event("Delta").OnClientEvent:Connect(function(delta: Snapshot.DeltaData)
		local current = snapshot
		if current == nil then
			return -- the snapshot is on its way
		end
		Snapshot.apply(current, delta)
		tickReceivedAt = os.clock()
		emit(deltaListeners, delta)
	end)
end

-- Called with the full snapshot whenever a match (re)starts or we join.
function ClientState.onReset(fn: Listener<Snapshot.SnapshotData>)
	table.insert(resetListeners, fn)
	if snapshot then
		task.spawn(fn, snapshot)
	end
end

function ClientState.onDelta(fn: Listener<Snapshot.DeltaData>)
	table.insert(deltaListeners, fn)
end

function ClientState.map(): Types.MapDef?
	return map
end

function ClientState.snapshot(): Snapshot.SnapshotData?
	return snapshot
end

-- 0 while spectating (all seats taken).
function ClientState.myNation(): number
	return myNationId
end

function ClientState.province(id: number): Snapshot.ProvinceRecord?
	return if snapshot then snapshot.provinces[id] else nil
end

function ClientState.nation(id: number): Snapshot.NationRecord?
	if snapshot == nil then
		return nil
	end
	for _, n in snapshot.nations do
		if n.id == id then
			return n
		end
	end
	return nil
end

-- Match tick, counted forward locally between deltas (deltas only arrive when something changed).
function ClientState.tick(): number
	if snapshot == nil then
		return 0
	end
	return snapshot.tick + math.floor(os.clock() - tickReceivedAt)
end

return ClientState
