--!strict
-- The client's copy of the match: filled by the Snapshot remote, kept current by Delta.
-- Other client modules read from here and subscribe to changes. The client never changes the match itself.

local Players = game:GetService("Players")
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
local positionListeners: { Listener<{ [number]: Snapshot.ArmyPosition }> } = {}

-- Latest unreliable position per moving army (cleared when an army stops; see Snapshot.ArmyRecord.next).
local positions: { [number]: Snapshot.ArmyPosition } = {}

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
		positions = {}
		emit(resetListeners, data)
	end)
	Remotes.unreliableEvent("ArmyPositions").OnClientEvent:Connect(function(_tick: number, flat: { number })
		-- flat: id, from, to, progress% repeated
		local changed: { [number]: Snapshot.ArmyPosition } = {}
		for i = 1, #flat - 3, 4 do
			local p = { id = flat[i], from = flat[i + 1], to = flat[i + 2], progress = flat[i + 3] / 100 }
			positions[p.id] = p
			changed[p.id] = p
		end
		emit(positionListeners, changed)
	end)
	Remotes.event("Delta").OnClientEvent:Connect(function(delta: Snapshot.DeltaData)
		local current = snapshot
		if current == nil then
			return -- the snapshot is on its way
		end
		Snapshot.apply(current, delta)
		tickReceivedAt = os.clock()
		if current.setup.sandbox and #delta.nations > 0 then
			-- a sandbox player takes nations over and lets them go: the nation that names us is ours (0 = watching).
			-- Set before the listeners run, so every screen redraws for the new nation.
			myNationId = 0
			for _, n in current.nations do
				if n.userId == Players.LocalPlayer.UserId then
					myNationId = n.id
				end
			end
		end
		for _, a in delta.armies do
			if a.next == 0 then
				positions[a.id] = nil
			end
		end
		for _, id in delta.removedArmies do
			positions[id] = nil
		end
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

-- Called with the positions that just arrived for moving armies.
function ClientState.onPositions(fn: Listener<{ [number]: Snapshot.ArmyPosition }>)
	table.insert(positionListeners, fn)
end

function ClientState.position(armyId: number): Snapshot.ArmyPosition?
	return positions[armyId]
end

function ClientState.army(armyId: number): Snapshot.ArmyRecord?
	if snapshot then
		for _, a in snapshot.armies do
			if a.id == armyId then
				return a
			end
		end
	end
	return nil
end

-- A fleet you can see (Snapshot.fleets), or nil.
function ClientState.fleet(fleetId: number): Snapshot.FleetRecord?
	if snapshot then
		for _, f in snapshot.fleets do
			if f.id == fleetId then
				return f
			end
		end
	end
	return nil
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

-- This player's Primordial, once their nation has been eliminated.
function ClientState.myPrimordial(): Snapshot.PrimordialRecord?
	if snapshot then
		for _, p in snapshot.primordials do
			if p.userId == Players.LocalPlayer.UserId then
				return p
			end
		end
	end
	return nil
end

-- Primordial-power charges this player can spend: their Primordial's, else their living nation's (nil = none).
function ClientState.myCharges(): number?
	local primordial = ClientState.myPrimordial()
	if primordial then
		return primordial.charges
	end
	local nation = ClientState.nation(myNationId)
	if nation and not nation.eliminated then
		return nation.charges
	end
	return nil
end

-- A sandbox world's controls (time, disasters), or nil in a match.
function ClientState.sandbox(): Types.SandboxState?
	return if snapshot then snapshot.sandbox else nil
end

-- How fast the world's clock runs: 1 in a match; a sandbox's speed (0 while paused).
function ClientState.timeScale(): number
	local controls = ClientState.sandbox()
	return if controls then controls.speed else 1
end

-- Match tick, counted forward locally between deltas (deltas only arrive when something changed), at the world's
-- speed.
function ClientState.tick(): number
	if snapshot == nil then
		return 0
	end
	return snapshot.tick + math.floor((os.clock() - tickReceivedAt) * ClientState.timeScale())
end

return ClientState
