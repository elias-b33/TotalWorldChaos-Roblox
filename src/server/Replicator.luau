--!strict
-- Sends a full snapshot to a player when they join (or a new match starts), then one delta per tick to everyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local Replicator = {}

local snapshotRemote: RemoteEvent
local deltaRemote: RemoteEvent
local notifyRemote: RemoteEvent
local lastSent: Snapshot.SnapshotData? = nil

function Replicator.init()
	snapshotRemote = Remotes.event("Snapshot")
	deltaRemote = Remotes.event("Delta")
	notifyRemote = Remotes.event("Notify")
end

-- Snapshot(data, yourNationId or 0)
function Replicator.sendSnapshot(player: Player, state: Types.MatchState, nationId: number?)
	snapshotRemote:FireClient(player, Snapshot.full(state), nationId or 0)
end

-- A new match: forget the old baseline so the next delta is computed against the new state.
function Replicator.reset(state: Types.MatchState)
	lastSent = Snapshot.full(state)
end

-- Tick order step 9: one delta with only what changed since the last tick.
function Replicator.broadcast(state: Types.MatchState)
	local current = Snapshot.full(state)
	if lastSent then
		local delta = Snapshot.diff(lastSent, current)
		if delta then
			deltaRemote:FireAllClients(delta)
		end
	end
	lastSent = current
end

-- Toast on every client: Notify(kind, text).
function Replicator.notifyAll(kind: string, text: string)
	notifyRemote:FireAllClients(kind, text)
end

return Replicator
