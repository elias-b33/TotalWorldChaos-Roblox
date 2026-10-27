--!strict
-- Owns the one MatchState: starts matches, advances the clock and phases, seats players.
-- Thin wrapper: the rules are in Shared.Sim.Match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Match = require(Shared.Sim.Match)
local Rng = require(Shared.Sim.Rng)
local Tick = require(Shared.Sim.Tick)
local Types = require(Shared.Types)

local MatchService = {}

local state: Types.MatchState? = nil
local rng = Rng.new(1)

-- A map the server is locked to: set a "MapId" attribute on Workspace in Studio to test another map. It also
-- skips the Lobby's map vote. (Later: private-server settings.)
function MatchService.lockedMap(): string?
	local override = workspace:GetAttribute("MapId")
	if type(override) == "string" and table.find(Maps.ids, override) then
		return override
	end
	return nil
end

-- Map for a match that skips the Lobby (Workspace "SkipLobby").
function MatchService.chooseMap(): string
	return MatchService.lockedMap() or Config.DefaultMap
end

function MatchService.start(mapId: string): Types.MatchState
	local newState = Match.new(Maps.get(mapId))
	state = newState
	rng = Rng.new(os.time()) -- battles get their random rolls from here; Sim never calls math.random
	return newState
end

function MatchService.state(): Types.MatchState
	assert(state, "no match running")
	return state
end

-- The current match, or nil before the first one (the first Lobby).
function MatchService.current(): Types.MatchState?
	return state
end

-- Tick order steps 2-8 (movement, battles, sieges, income, win checks). Returns the new phase if it changed.
function MatchService.advance(): Types.Phase?
	return Tick.advance(MatchService.state(), rng)
end

function MatchService.isOver(): boolean
	return Match.isOver(MatchService.state())
end

function MatchService.seat(player: Player): number?
	return Match.seatPlayer(MatchService.state(), player.UserId)
end

function MatchService.unseat(player: Player)
	Match.unseatPlayer(MatchService.state(), player.UserId)
end

function MatchService.nationOf(player: Player): number?
	return Match.nationOf(MatchService.state(), player.UserId)
end

return MatchService
