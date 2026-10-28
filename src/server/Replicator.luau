--!strict
-- Sends a full snapshot to a player when they join (or a new match starts), then one delta per tick to everyone.
-- Records carry what clients need: every nation's race, every army's composition, the fleets with the men aboard,
-- each coast's blockade (Shared.Snapshot). Moving armies and sailing fleets report their progress on the unreliable
-- channel instead, so their records don't change every tick. Everyone sees every fleet for now (Sim.Navy.visible), so
-- one delta and one positions stream go to all; fog of war will need one per viewer (Snapshot.full's viewer).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Lobby = require(Shared.Sim.Lobby)
local Movement = require(Shared.Sim.Movement)
local Remotes = require(Shared.Remotes)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

-- UnreliableRemoteEvent payloads must stay under ~900 bytes, so positions go out as flat number arrays in chunks.
local POSITIONS_PER_MESSAGE = 16

local Replicator = {}

local snapshotRemote: RemoteEvent
local deltaRemote: RemoteEvent
local notifyRemote: RemoteEvent
local positionsRemote: UnreliableRemoteEvent
local lobbyRemote: RemoteEvent
local lastSent: Snapshot.SnapshotData? = nil

function Replicator.init()
	snapshotRemote = Remotes.event("Snapshot")
	deltaRemote = Remotes.event("Delta")
	notifyRemote = Remotes.event("Notify")
	positionsRemote = Remotes.unreliableEvent("ArmyPositions")
	lobbyRemote = Remotes.event("Lobby")
end

-- Every nation's equipped cosmetics travel next to the match state (ShopService sets this).
local cosmeticsOf: ((Types.MatchState) -> { Types.NationCosmetics })? = nil

function Replicator.setCosmetics(fn: (Types.MatchState) -> { Types.NationCosmetics })
	cosmeticsOf = fn
end

local function full(state: Types.MatchState): Snapshot.SnapshotData
	return Snapshot.full(state, if cosmeticsOf then cosmeticsOf(state) else nil)
end

-- Snapshot(data, yourNationId or 0)
function Replicator.sendSnapshot(player: Player, state: Types.MatchState, nationId: number?)
	snapshotRemote:FireClient(player, full(state), nationId or 0)
end

-- A new match: forget the old baseline so the next delta is computed against the new state.
function Replicator.reset(state: Types.MatchState)
	lastSent = full(state)
end

-- Tick order step 9: one delta with only what changed since the last tick, plus this tick's events.
-- Then moving armies' and sailing fleets' positions on the unreliable channel. Events are spent once sent.
function Replicator.broadcast(state: Types.MatchState)
	local current = full(state)
	if lastSent then
		local delta = Snapshot.diff(lastSent, current, state.events)
		if delta then
			deltaRemote:FireAllClients(delta)
		end
	end
	lastSent = current
	table.clear(state.events)

	local positions = Snapshot.positions(state, function(provinceId, army)
		return Movement.moveTicks(state, army, provinceId) -- its slowest troop's speed (Elves: forest as plains)
	end)
	-- ArmyPositions(tick, armies, fleets): id, from, to, progress in percent, armies and fleets in separate arrays
	local armies, fleets = {}, {}
	for i, p in positions do
		local flat = if p.fleet then fleets else armies
		table.insert(flat, p.id)
		table.insert(flat, p.from)
		table.insert(flat, p.to)
		table.insert(flat, math.floor(p.progress * 100 + 0.5))
		if i % POSITIONS_PER_MESSAGE == 0 or i == #positions then
			positionsRemote:FireAllClients(state.tick, armies, fleets)
			armies, fleets = {}, {}
		end
	end
end

-- The lobby (map vote, draft, or "None" once the match starts) to one player, or to everyone.
function Replicator.sendLobby(view: Lobby.LobbyView, player: Player?)
	if player then
		lobbyRemote:FireClient(player, view)
	else
		lobbyRemote:FireAllClients(view)
	end
end

-- Toast on every client: Notify(kind, text).
function Replicator.notifyAll(kind: string, text: string)
	notifyRemote:FireAllClients(kind, text)
end

-- Toast on one client.
function Replicator.notify(player: Player, kind: string, text: string)
	notifyRemote:FireClient(player, kind, text)
end

return Replicator
