--!strict
-- The tutorial match (docs/DESIGN.md "Tutorial"). A public server holds up to 12 players in one shared match, so a
-- new player's tutorial runs on a reserved server of the same place: a player whose profile hasn't finished the
-- tutorial is teleported to a fresh reserved server, which plays the tutorial match (the player and Easy bots, the
-- Lobby skipped) and sends them back to a public server when it ends or when they skip it.
-- In Studio (and the harness) teleports can't run: set a "Tutorial" attribute on Workspace to start the tutorial
-- match straight away instead. Private servers never send anyone to the tutorial (friends stay together).
-- A teleport back that fails is tried again (Config.Tutorial.TeleportRetries); a player on their way out is never
-- seated in the next tutorial match, and keeps a "🌍 Play online" button to try again.
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
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Replicator = require(Server.Replicator)
local ServerMode = require(Server.ServerMode)
local TelemetryService = require(script.Parent.TelemetryService)

local TutorialService = {}

local state: Types.MatchState? = nil
local tut: Types.TutorialState? = nil
local remote: RemoteEvent
local sent: { [Player]: string } = {} -- the last view each player was sent, to send only changes
local counts = { started = 0, finished = 0, skipped = 0 } -- printed for Studio tests; analytics go through TelemetryService
local seatedAt = 0 -- os.clock() when the tutorial player sat down (match ticks jump when Peace ends early)
local sentAway: { [Player]: number } = {} -- sent back to a public server -> teleport tries in this round
local flying: { [Player]: boolean } = {} -- a teleport back is on its way (until it fails)

-- Teleports -------------------------------------------------------------------------------------------------

local function canTeleport(): boolean
	return not RunService:IsStudio() -- Studio and the harness can't teleport
end

local retry: (Player) -> () -- below

-- Send players to a fresh reserved server of this place (the tutorial), or back to a public one.
local function teleport(players: { Player }, toTutorial: boolean)
	if #players == 0 then
		return
	end
	if not canTeleport() then
		print(string.format("[tutorial] no teleports in Studio: %d player(s) stay here", #players))
		return
	end
	if not toTutorial then
		for _, player in players do
			sentAway[player] = (sentAway[player] or 0) + 1
			flying[player] = true
		end
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
			if not toTutorial then
				for _, player in players do
					retry(player)
				end
			end
		end
	end)
end

-- A teleport back to a public server failed: try again a few times, then leave it to the 🌍 Play online button.
retry = function(player: Player)
	local tries = sentAway[player]
	flying[player] = nil
	if tries == nil or player.Parent ~= Players then
		return
	end
	if tries > Config.Tutorial.TeleportRetries then
		sentAway[player] = 0 -- the button starts a new round of tries
		Replicator.notify(player, "Tutorial", "🌍 No public server yet. Tap 🌍 Play online to try again")
		return
	end
	Replicator.notify(player, "Tutorial", "🌍 Teleport failed, trying again…")
	task.delay(Config.Tutorial.TeleportRetrySeconds, function()
		if sentAway[player] and not flying[player] and player.Parent == Players then
			teleport({ player }, false)
		end
	end)
end

-- Can a player who skipped or finished leave for a public server from here?
local function canLeave(): boolean
	return TutorialService.enabled() and canTeleport()
end

-- Is this a tutorial server? Workspace "Tutorial" in Studio; online, a reserved server whose first player wasn't
-- sent to a sandbox (ServerMode).
function TutorialService.enabled(): boolean
	return ServerMode.get() == "Tutorial"
end

local function markDone(player: Player)
	local data = PlayerDataService.data(player)
	if data and not data.tutorialDone then
		PlayerDataService.update(player, function(profile)
			profile.tutorialDone = true
		end)
	end
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

-- The player's prompt card, with whether they can leave for a public server.
local function viewOf(s: Types.MatchState, t: Types.TutorialState): Types.TutorialView
	local view = Tutorial.view(s, t)
	view.canLeave = canLeave()
	return view
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

-- The next match isn't a tutorial (Studio: the Workspace "Tutorial" attribute was removed): forget the old one.
function TutorialService.stop()
	state = nil
	tut = nil
	table.clear(sent)
end

-- A tutorial match seats its player in the tutorial nation; a player already sent back to a public server sits
-- out (a fresh tutorial would start its prompts again) with only the 🌍 Play online button.
function TutorialService.seat(player: Player): number?
	local s, t = state, tut
	if s == nil or t == nil then
		return nil
	end
	if sentAway[player] then
		sendView(player, { step = 0, total = #Tutorial.STEPS, province = 0, nation = 0, canLeave = canLeave() })
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
		sendView(player, viewOf(s, t))
	end
end

-- The tutorial match is over: it counts as the tutorial done (finished or not, so nobody comes back to it on every
-- join), then back to a public server (in Studio, the next tutorial match starts here).
function TutorialService.matchOver()
	if tut then
		for _, player in Players:GetPlayers() do
			markDone(player)
		end
		teleport(Players:GetPlayers(), false)
	end
end

local function onRequest(player: Player, action: string)
	if action == "Leave" and sentAway[player] then
		if not flying[player] then
			teleport({ player }, false) -- the 🌍 Play online button after a teleport that failed
		end
		return
	end
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
		sendView(player, viewOf(s, t))
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
	-- a public server sends players who haven't played the tutorial (or any match) to one; a private server doesn't,
	-- and neither does a sandbox (the player chose it)
	PlayerDataService.onLoaded(function(player, data)
		if Tutorial.needed(data) and ServerMode.get() == "Match" and not MatchService.isPrivate() then
			print(string.format("[tutorial] %s is new: off to the tutorial", player.Name))
			teleport({ player }, true)
		end
	end)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
		if sentAway[player] then
			warn(string.format("[tutorial] teleport for %s failed: %s %s", player.Name, tostring(result), message))
			retry(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		sent[player] = nil
		sentAway[player] = nil
		flying[player] = nil
	end)
end

return TutorialService
