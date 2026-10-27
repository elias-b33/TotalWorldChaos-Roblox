--!strict
-- Owns the one MatchState: starts matches, advances the clock and phases, seats players.
-- Thin wrapper: the rules are in Shared.Sim.Match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Match = require(Shared.Sim.Match)
local Types = require(Shared.Types)

local MatchService = {}

local state: Types.MatchState? = nil

-- Map for the next match: set a "MapId" attribute on Workspace in Studio to test another map.
function MatchService.chooseMap(): string
	local override = workspace:GetAttribute("MapId")
	if type(override) == "string" and table.find(Maps.ids, override) then
		return override
	end
	return Config.DefaultMap
end

function MatchService.start(mapId: string): Types.MatchState
	local newState = Match.new(Maps.get(mapId))
	state = newState
	return newState
end

function MatchService.state(): Types.MatchState
	assert(state, "no match running")
	return state
end

-- Moves the clock one tick. Returns the new phase if it changed.
function MatchService.advance(): Types.Phase?
	local s = MatchService.state()
	s.tick += 1
	local phase = Match.phaseAt(s.tick)
	if phase ~= s.phase then
		s.phase = phase
		return phase
	end
	return nil
end

function MatchService.isOver(): boolean
	return Match.isOver(MatchService.state().tick)
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
