--!strict
-- The client's copy of the lobby (map vote and nation draft), filled by the Lobby remote once a second while a
-- lobby is open, and "None" once the match starts. The UI reads it and subscribes to changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Lobby = require(Shared.Sim.Lobby)
local Remotes = require(Shared.Remotes)

type Listener = (Lobby.LobbyView) -> ()

local LobbyState = {}

local view: Lobby.LobbyView? = nil
local receivedAt = os.clock()
local listeners: { Listener } = {}

function LobbyState.init()
	Remotes.event("Lobby").OnClientEvent:Connect(function(data: Lobby.LobbyView)
		view = data
		receivedAt = os.clock()
		for _, fn in listeners do
			task.spawn(fn, data)
		end
	end)
end

function LobbyState.onChange(fn: Listener)
	table.insert(listeners, fn)
end

-- "Lobby" (voting), "Pick" (drafting) or "None".
function LobbyState.phase(): string
	local v = view
	return if v then v.phase else "None"
end

function LobbyState.view(): Lobby.LobbyView?
	return view
end

local function since(): number
	return math.floor(os.clock() - receivedAt)
end

-- Seconds until this lobby phase ends, counted down locally between updates.
function LobbyState.secondsLeft(): number
	local v = view
	return if v then math.max(0, v.ticksLeft - since()) else 0
end

-- Seconds left in the current draft turn.
function LobbyState.turnSecondsLeft(): number
	local v = view
	return if v then math.max(0, v.turnTicksLeft - since()) else 0
end

-- The map this player voted for, if any.
function LobbyState.myVote(): string?
	local v = view
	if v then
		for _, vote in v.votes do
			if vote.userId == Players.LocalPlayer.UserId then
				return vote.map
			end
		end
	end
	return nil
end

-- Whose turn it is in the draft (nil when nobody's).
function LobbyState.picker(): { userId: number, name: string, nation: number }?
	local v = view
	if v and v.phase == "Pick" then
		return v.order[v.turn]
	end
	return nil
end

function LobbyState.myTurn(): boolean
	local p = LobbyState.picker()
	return p ~= nil and p.userId == Players.LocalPlayer.UserId
end

return LobbyState
