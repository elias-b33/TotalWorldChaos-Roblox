--!strict
-- The singleplayer sandbox (docs/DESIGN.md "Sandbox"): a world of the player's own on a reserved server of this
-- place, WorldBox style. Thin wrapper: the rules are in Shared.Sim.Sandbox. This service answers the sandbox intents
-- (CommandRouter.onSandbox), runs the teleports in and out, and tells GameLoop how fast the world runs and when to
-- start a new one; GameLoop runs the sandbox's own loop.
--
-- The entry point is SandboxService.enter(player, mapId?), which the client reaches through
-- Intents.enterSandbox(mapId?) (the start menu's Singleplayer button): from any server it teleports the player to a
-- fresh reserved server that plays a sandbox world on that map; on a sandbox server it starts a new world instead.
-- In Studio teleports can't run: set the Workspace attribute "Sandbox" (true, or a map id) and the server plays a
-- sandbox from the start (ServerMode).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Sandbox = require(Shared.Sim.Sandbox)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local MatchService = require(script.Parent.MatchService)
local Replicator = require(Server.Replicator)
local ServerMode = require(Server.ServerMode)
local TelemetryService = require(script.Parent.TelemetryService)

local SandboxService = {}

local nextWorld: string? = nil -- the map of a new world a player asked for (GameLoop starts it at its next beat)
local changed = false -- a player changed the controls or took a nation over since GameLoop last looked
local worlds = 0 -- worlds started on this server
local flying: { [Player]: boolean } = {} -- a teleport is on its way (until it fails)
local welcomed: { [Player]: number } = {} -- the last world each player was welcomed to

-- Is this a sandbox server?
function SandboxService.enabled(): boolean
	return ServerMode.get() == "Sandbox"
end

-- The first world's map: Studio's "Sandbox" attribute when it names one, else the map the player was sent with,
-- else the server's locked map (Workspace "MapId") or the default.
function SandboxService.firstMap(): string
	local fallback = MatchService.lockedMap() or Config.DefaultMap
	local attribute = workspace:GetAttribute("Sandbox")
	local wanted = if type(attribute) == "string" then attribute else ServerMode.data("map")
	local map = Sandbox.mapFor(if type(wanted) == "string" then wanted else "", Maps.ids, fallback)
	return map or fallback
end

-- A new world (GameLoop made it with Sim.Sandbox.setup()): its controls. GameLoop then seats everyone here.
function SandboxService.start(state: Types.MatchState)
	Sandbox.start(state)
	nextWorld = nil
	changed = false
	worlds += 1
	print(string.format("[sandbox] world %d on %s", worlds, state.mapId))
end

-- A player arriving (or here when a new world starts) watches, or keeps the nation they still hold. Once per world
-- and player: a welcome toast and sandbox_started.
function SandboxService.seat(player: Player): number?
	local state = MatchService.state()
	if welcomed[player] ~= worlds then
		welcomed[player] = worlds
		TelemetryService.sandboxStarted(player, state.mapId, if worlds == 1 then "first" else "new_world")
		Replicator.notify(player, "Sandbox", "🌍 Your world is alive! Tap Play as to lead a people")
	end
	return Sandbox.seat(state, player.UserId)
end

-- Game ticks per real second (0 = paused).
function SandboxService.speed(): number
	local state = MatchService.current()
	return if state then Sandbox.speed(state) else Config.Sandbox.StartSpeed
end

-- The map of the new world a player asked for, once (GameLoop starts it), or nil.
function SandboxService.takeNewWorld(): string?
	local map = nextWorld
	nextWorld = nil
	return map
end

-- Did a player change the controls or the seats since the last call? GameLoop then sends a delta straight away.
function SandboxService.takeChanged(): boolean
	local was = changed
	changed = false
	return was
end

-- Teleports ----------------------------------------------------------------------------------------------------------

-- To a fresh reserved server playing a sandbox world on `mapId` ("" = the default), or back to a public server.
-- A failure is a toast: the button can simply be pressed again.
local function teleport(player: Player, toSandbox: boolean, mapId: string)
	if RunService:IsStudio() then
		print(string.format("[sandbox] no teleports in Studio: %s stays here", player.Name))
		Replicator.notify(
			player,
			"Sandbox",
			if toSandbox
				then "🌍 Singleplayer needs a live server. In Studio, set Workspace Sandbox"
				else "🌍 Play online needs a live server"
		)
		return
	end
	if flying[player] then
		return
	end
	flying[player] = true
	task.spawn(function()
		local ok, err = pcall(function()
			local options = Instance.new("TeleportOptions")
			options.ShouldReserveServer = toSandbox
			options:SetTeleportData(if toSandbox then { mode = "sandbox", map = mapId } else {})
			TeleportService:TeleportAsync(game.PlaceId, { player }, options)
		end)
		if not ok then
			flying[player] = nil
			warn("[sandbox] teleport failed: " .. tostring(err))
			Replicator.notify(player, "Sandbox", "🌍 Teleport failed. Try again")
		end
	end)
end

-- THE ENTRY POINT: send a player to a sandbox world of their own on `mapId` (nil or "" = the default map). On a
-- sandbox server it starts a new world here instead.
function SandboxService.enter(player: Player, mapId: string?)
	local map = mapId or ""
	if SandboxService.enabled() then
		local state = MatchService.current()
		nextWorld = Sandbox.mapFor(map, Maps.ids, if state then state.mapId else SandboxService.firstMap())
		return
	end
	print(
		string.format("[sandbox] %s is off to a sandbox world (%s)", player.Name, if map == "" then "default" else map)
	)
	teleport(player, true, map)
end

-- Intents --------------------------------------------------------------------------------------------------------------

-- A sandbox intent (CommandRouter checked its shape and the rate limit). Enter works on every server; the rest only
-- on a sandbox server.
function SandboxService.apply(player: Player, intent: Types.SandboxIntent): (boolean, string?)
	if intent.kind == "Enter" then
		local _, reason = Sandbox.mapFor(intent.map, Maps.ids, Config.DefaultMap)
		if reason then
			return false, reason
		end
		SandboxService.enter(player, intent.map)
		return true, nil
	end
	local state = MatchService.current()
	if not SandboxService.enabled() or state == nil or state.sandbox == nil then
		return false, "NotSandbox"
	end
	if intent.kind == "Leave" then
		print(string.format("[sandbox] %s leaves for a public server", player.Name))
		teleport(player, false, "")
		return true, nil
	elseif intent.kind == "NewWorld" then
		local map, reason = Sandbox.mapFor(intent.map, Maps.ids, state.mapId)
		if map == nil then
			return false, reason
		end
		nextWorld = map
		return true, nil
	end
	local ok, reason = Sandbox.apply(state, player.UserId, intent)
	if ok then
		changed = true
	end
	return ok, reason
end

function SandboxService.init()
	CommandRouter.onSandbox(SandboxService.apply)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		if flying[player] then
			flying[player] = nil
			print(string.format("[sandbox] teleport for %s failed: %s %s", player.Name, tostring(result), message))
			Replicator.notify(player, "Sandbox", "🌍 Teleport failed. Try again")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		flying[player] = nil
		welcomed[player] = nil
	end)
end

return SandboxService
