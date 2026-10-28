--!strict
-- Owns the one MatchState: starts matches, advances the clock and phases, seats players.
-- Thin wrapper: the rules are in Shared.Sim.Match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Match = require(Shared.Sim.Match)
local Rng = require(Shared.Sim.Rng)
local Settings = require(Shared.Sim.Settings)
local Tick = require(Shared.Sim.Tick)
local Types = require(Shared.Types)

local MatchService = {}

local state: Types.MatchState? = nil
local rng = Rng.new(1)

-- A map the server is locked to: set a "MapId" attribute on Workspace in Studio to test another map. It also
-- skips the Lobby's map vote. (A private server's owner can lock the map in the settings too: Sim.Lobby.)
function MatchService.lockedMap(): string?
	local override = workspace:GetAttribute("MapId")
	if type(override) == "string" and table.find(Maps.ids, override) then
		return override
	end
	return nil
end

-- A private (VIP) server's owner, or nil. Online: game.PrivateServerId ~= "" and PrivateServerOwnerId ~= 0 (a
-- reserved server has owner 0: that's the tutorial, TutorialService). Studio and the harness can't make one, so a
-- "PrivateServerOwner" attribute on Workspace simulates it: a userId, or true for the first player in the server.
function MatchService.privateOwner(): number?
	local simulated = workspace:GetAttribute("PrivateServerOwner")
	if type(simulated) == "number" and simulated ~= 0 then
		return simulated
	elseif simulated == true then
		local first = Players:GetPlayers()[1]
		return if first then first.UserId else nil
	end
	local ok, owner = pcall(function()
		return if game.PrivateServerId ~= "" then game.PrivateServerOwnerId else 0
	end)
	return if ok and type(owner) == "number" and owner ~= 0 then owner else nil
end

-- A map theme the server forces on every match, skipping the theme vote, or nil for the vote: a "Theme"
-- attribute on Workspace (a Theme catalogue id such as "theme_night"; "theme_classic" forces the classic look), or
-- a private server whose owner set the theme to "Default".
function MatchService.forcedTheme(setup: Types.MatchSetup?): string?
	local id = workspace:GetAttribute("Theme")
	local item = if type(id) == "string" then Catalogue.item(id) else nil
	if item and item.slot == "Theme" then
		return item.id
	end
	if setup and setup.settings.theme == "Default" then
		return Catalogue.DEFAULTS.Theme
	end
	return nil
end

-- Is this a private server (whether or not its owner is here)?
function MatchService.isPrivate(): boolean
	local simulated = workspace:GetAttribute("PrivateServerOwner")
	return simulated == true or MatchService.privateOwner() ~= nil
end

-- Map for a match that skips the Lobby (Workspace "SkipLobby"): the locked map, the private server's map setting,
-- or the default.
function MatchService.chooseMap(setup: Types.MatchSetup?): string
	local setting = if setup and setup.settings.map ~= "" then setup.settings.map else nil
	return MatchService.lockedMap() or setting or Config.DefaultMap
end

-- A new match on a map. `setup`: the private server's settings for it (nil = the defaults).
function MatchService.start(mapId: string, setup: Types.MatchSetup?): Types.MatchState
	local newState = Match.new(Maps.get(mapId), setup)
	state = newState
	rng = Rng.new(os.time()) -- battles get their random rolls from here; Sim never calls math.random
	return newState
end

-- The players are seated and tick 0 is next: apply the setup's bot count and locked teams.
function MatchService.prepare()
	Settings.prepare(MatchService.state(), rng)
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
