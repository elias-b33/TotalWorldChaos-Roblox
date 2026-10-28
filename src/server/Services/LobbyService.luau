--!strict
-- Owns the lobby between matches: the map vote, then the nation draft on the new match (docs/DESIGN.md
-- "Match structure"). Thin wrapper: the rules are in Shared.Sim.Lobby; GameLoop drives it once a second.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Lobby = require(Shared.Sim.Lobby)
local Maps = require(Shared.Maps)
local Rng = require(Shared.Sim.Rng)
local Settings = require(Shared.Sim.Settings)
local Types = require(Shared.Types)

local MatchService = require(script.Parent.MatchService)

local LobbyService = {}

local lobby: Types.LobbyState? = nil
local match: Types.MatchState? = nil -- the new match, during the draft
local rng = Rng.new(1)
local settings = Settings.defaults() -- a private server's settings: kept from one lobby to the next

-- Set a "SkipLobby" attribute on Workspace (Studio solo tests, the harness) to start matches straight away.
function LobbyService.skipped(): boolean
	return workspace:GetAttribute("SkipLobby") == true
end

-- Open the map vote. `lockedMap` (Workspace "MapId") skips the vote itself, and so does a private server's map
-- setting. On a private server the owner changes the settings here (Sim.Lobby.setting).
function LobbyService.open(lockedMap: string?)
	local owner = MatchService.privateOwner()
	lobby = Lobby.new(Maps.ids, lockedMap, owner, if owner or MatchService.isPrivate() then settings else nil)
	match = nil
	rng = Rng.new(os.time()) -- the vote's tie-break and the draft order; Sim never calls math.random
end

function LobbyService.active(): boolean
	return lobby ~= nil
end

function LobbyService.state(): Types.LobbyState?
	return lobby
end

-- "Lobby" (voting) or "Pick" (drafting), nil when no lobby is open.
function LobbyService.phase(): string?
	local l = lobby
	return if l then l.phase else nil
end

-- The match being drafted (nil while voting).
function LobbyService.match(): Types.MatchState?
	return match
end

function LobbyService.winner(): string
	return Lobby.winner(assert(lobby, "no lobby"), rng)
end

-- The vote is over: draft the players in the server onto `newMatch`.
function LobbyService.startPick(newMatch: Types.MatchState)
	local userIds = {}
	for _, player in Players:GetPlayers() do
		table.insert(userIds, player.UserId)
	end
	match = newMatch
	Lobby.startPick(assert(lobby, "no lobby"), newMatch, userIds, rng)
end

-- A vote or pick from CommandRouter (shape and rate limit already checked).
function LobbyService.apply(userId: number, intent: Types.LobbyIntent): (boolean, string?)
	local l = lobby
	if l == nil then
		return false, "WrongPhase"
	end
	return Lobby.apply(l, match, userId, intent)
end

-- One second. Returns true when the current phase (vote or draft) is over.
function LobbyService.step(): boolean
	local l = assert(lobby, "no lobby")
	l.owner = MatchService.privateOwner() -- with the Studio switch set to true, the first player in the server
	return Lobby.step(l, match, rng)
end

-- The setup the next match plays: this private server's settings, or a public server's defaults.
function LobbyService.setup(): Types.MatchSetup
	local private = MatchService.isPrivate()
	return Settings.setup(private, if private then settings else nil)
end

-- The draft is over: the match starts and the lobby closes.
function LobbyService.finish()
	if match then
		Lobby.finish(match)
	end
	lobby = nil
	match = nil
end

function LobbyService.join(player: Player)
	if lobby then
		Lobby.join(lobby, match, player.UserId)
	end
end

function LobbyService.leave(player: Player)
	if lobby then
		Lobby.leave(lobby, match, player.UserId)
	end
end

-- What clients are told (the Lobby remote).
function LobbyService.view(): Lobby.LobbyView
	local names: { [number]: string } = {}
	for _, player in Players:GetPlayers() do
		names[player.UserId] = if player.DisplayName ~= "" then player.DisplayName else player.Name
	end
	return Lobby.view(lobby, names, MatchService.isPrivate())
end

return LobbyService
