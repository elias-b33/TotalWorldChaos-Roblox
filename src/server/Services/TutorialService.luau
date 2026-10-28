--!strict
-- The tutorial match (docs/DESIGN.md "Tutorial"). A public server holds up to 12 players in one shared match, so a
-- new player's tutorial runs on a reserved server of the same place: a player whose profile hasn't finished the
-- tutorial is teleported to a fresh reserved server, which plays the tutorial match (the player and Easy bots, the
-- Lobby skipped) and sends them back to a public server when it ends or when they skip it.
-- In Studio (and the harness) teleports can't run: set a "Tutorial" attribute on Workspace to start the tutorial
-- match straight away instead.
-- Thin wrapper: the rules are in Shared.Sim.Tutorial; the teleports are the two small functions at the top.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Match = require(Shared.Sim.Match)
local Remotes = require(Shared.Remotes)
local Tutorial = require(Shared.Sim.Tutorial)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TelemetryService = require(script.Parent.TelemetryService)

local TutorialService = {}

local state: Types.MatchState? = nil
local tut: Types.TutorialState? = nil
local remote: RemoteEvent
local sent: { [Player]: string } = {} -- the last view each player was sent, to send only changes
local counts = { started = 0, finished = 0, skipped = 0 } -- printed for Studio tests; analytics go through TelemetryService
local seatedAt = 0 -- os.clock() when the tutorial player sat down (match ticks jump when Peace ends early)

-- Teleports -------------------------------------------------------------------------------------------------

local function canTeleport(): boolean
	return not RunService:IsStudio() -- Studio and the harness can't teleport
end

-- Send players to a fresh reserved server of this place (the tutorial), or back to a public one.
local function teleport(players: { Player }, toTutorial: boolean)
	if #players == 0 then
		return
	end
	if not canTeleport() then
		print(string.format("[tutorial] no teleports in Studio: %d player(s) stay here", #players))
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			local options = Instance.new("TeleportOptions")
			options.ShouldReserveServer = toTutorial
			options:SetTeleportData({ tutorial = toTutorial })
			TeleportService:TeleportAsync(game.PlaceId, players, options)
		end)
		if not ok then
			warn("[tutorial] teleport failed: " .. tostring(err))
		end
	end)
end

-- Is this a tutorial server? Workspace "Tutorial" in Studio; online, a reserved server (no private-server owner):
-- reserved servers are only ever made for the tutorial.
function TutorialService.enabled(): boolean
	if workspace:GetAttribute("Tutorial") == true then
		return true
	end
	local ok, reserved = pcall(function()
		return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	end)
	return ok and reserved == true
end

-- The match ---------------------------------------------------------------------------------------------------

-- True while a tutorial match is running.
function TutorialService.active(): boolean
	return tut ~= nil
end

-- The tutorial's progress in this match (nil outside a tutorial match).
function TutorialService.current(): Types.TutorialState?
	return tut
end

-- A new tutorial match: setup before the first snapshot goes out.
function TutorialService.start(newState: Types.MatchState)
	state = newState
	tut = Tutorial.setup(newState, Config.Tutorial.PlayerSlot)
	table.clear(sent)
	print(string.format("[tutorial] tutorial match on %s", newState.mapId))
end

function TutorialService.seat(player: Player): number?
	local s, t = state, tut
	if s == nil or t == nil then
		return nil
	end
	local nationId = Tutorial.seat(s, t, player.UserId)
	if nationId == t.slot then
		seatedAt = os.clock()
		counts.started += 1
		print(string.format("[tutorial] %s started (%d started on this server)", player.Name, counts.started))
	end
	return nationId
end

local function tutorialPlayer(): Player?
	local s, t = state, tut
	if s == nil or t == nil then
		return nil
	end
	local userId = s.nations[t.slot] and s.nations[t.slot].userId
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function markDone(player: Player)
	PlayerDataService.update(player, function(data)
		data.tutorialDone = true
	end)
end

local function sendView(player: Player, view: Types.TutorialView?)
	local key = if view
		then string.format("%d:%d:%d:%d:%s", view.step, view.total, view.province, view.nation, tostring(view.canLeave))
		else "none"
	if sent[player] ~= key then
		sent[player] = key
		remote:FireClient(player, view)
	end
end

-- After every tick: the next prompt once this one is done, the bots' part, and the player's view.
function TutorialService.afterTick(s: Types.MatchState)
	local t = tut
	if t == nil or s ~= state then
		return
	end
	local step = Tutorial.update(s, t)
	local player = tutorialPlayer()
	if step and player then
		TelemetryService.tutorialPrompt(player, step - 1) -- analytics: onboarding steps 5-10
		if Tutorial.finished(t) then
			counts.finished += 1
			print(
				string.format(
					"[tutorial] %s finished in %d s (%d of %d finished on this server)",
					player.Name,
					math.floor(os.clock() - seatedAt),
					counts.finished,
					counts.started
				)
			)
			markDone(player)
		else
			print(string.format("[tutorial] %s: prompt %d (%s)", player.Name, step, Tutorial.stepName(t) or "?"))
		end
	end
	for _, order in Tutorial.botOrders(s, t) do
		CommandRouter.submitForBot(order.nation, order.command)
	end
	if player then
		local view = Tutorial.view(s, t)
		view.canLeave = TutorialService.enabled() and canTeleport()
		sendView(player, view)
	end
end

-- The tutorial match is over: back to a public server (in Studio, the next tutorial match starts here).
function TutorialService.matchOver()
	if tut then
		teleport(Players:GetPlayers(), false)
	end
end

local function onRequest(player: Player, action: string)
	local s, t = state, tut
	if s == nil or t == nil or Match.nationOf(s, player.UserId) ~= t.slot then
		return
	end
	if action == "Skip" and not t.skipped and not Tutorial.finished(t) then
		Tutorial.skip(t)
		TelemetryService.tutorialSkipped(player, t.step) -- analytics
		counts.skipped += 1
		print(
			string.format(
				"[tutorial] %s skipped at prompt %d (%d skipped on this server)",
				player.Name,
				t.step,
				counts.skipped
			)
		)
		markDone(player)
		sendView(player, Tutorial.view(s, t))
		teleport({ player }, false)
	elseif action == "Leave" and (t.skipped or Tutorial.finished(t)) then
		teleport({ player }, false)
	end
end

function TutorialService.init()
	remote = Remotes.event("Tutorial")
	CommandRouter.onTutorial(onRequest)
	CommandRouter.observe(function(player: Player, command: Types.Command, ok: boolean)
		local s, t = state, tut
		if s and t and Match.nationOf(s, player.UserId) == t.slot then
			Tutorial.recordCommand(t, command, ok)
		end
	end)
	-- a public server sends players who haven't played the tutorial to one
	PlayerDataService.onLoaded(function(player, data)
		if not data.tutorialDone and not TutorialService.enabled() then
			print(string.format("[tutorial] %s is new: off to the tutorial", player.Name))
			teleport({ player }, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
	end)
end

return TutorialService
