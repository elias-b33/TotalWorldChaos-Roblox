--!strict
-- Boots the server and runs the 1-second tick (docs/DESIGN.md "Tick order").
-- Step 1 is CommandRouter, steps 2-8 are Shared.Sim.Tick (via MatchService), step 7 (bots) is AIService, step 9 is
-- Replicator. Between matches the Lobby runs instead (map vote, then nation draft; LobbyService), unless Workspace
-- has SkipLobby set, which starts every match straight away. A tutorial server (TutorialService) skips the Lobby too
-- and plays the tutorial match. A sandbox server (SandboxService) plays one never-ending world in its own loop, at
-- the speed its player sets. A reserved server first waits for its player to learn which of the two it is
-- (ServerMode).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Sandbox = require(Shared.Sim.Sandbox)
local Types = require(Shared.Types)

Remotes.create()
Players.CharacterAutoLoads = false -- the game is the map; nobody needs an avatar walking around

local Server = script.Parent
local AIService = require(Server.Services.AIService)
local CommandRouter = require(Server.CommandRouter)
local DevService = require(Server.Services.DevService)
local LobbyService = require(Server.Services.LobbyService)
local MatchService = require(Server.Services.MatchService)
local PlayerDataService = require(Server.Services.PlayerDataService)
local ProgressionService = require(Server.Services.ProgressionService)
local Replicator = require(Server.Replicator)
local SandboxService = require(Server.Services.SandboxService)
local ServerMode = require(Server.ServerMode)
local TutorialService = require(Server.Services.TutorialService)
local ShopService = require(Server.Services.ShopService)
local QuestService = require(Server.Services.QuestService)
local SeasonService = require(Server.Services.SeasonService)
local TelemetryService = require(Server.Services.TelemetryService)
local AdRewardService = require(Server.Services.AdRewardService)
local AchievementService = require(Server.Services.AchievementService)
local LeaderboardService = require(Server.Services.LeaderboardService)

local PHASE_TOASTS = {
	War = "War! Nations can fight now",
	Cataclysm = "Cataclysm! The Primordials stir",
	Results = "The match is over",
}

-- A tutorial match seats its player in the tutorial nation; a sandbox player arrives watching.
local function seat(player: Player): number?
	if SandboxService.enabled() then
		return SandboxService.seat(player)
	elseif TutorialService.active() then
		return TutorialService.seat(player)
	end
	return MatchService.seat(player)
end

-- Seat everyone who is already here (in join order), apply a private server's bot count and teams, then send
-- each their snapshot.
local function seatAll(state: Types.MatchState, prepare: boolean)
	local seats: { [Player]: number? } = {}
	for _, player in Players:GetPlayers() do
		seats[player] = seat(player)
	end
	if prepare then
		MatchService.prepare()
	end
	Replicator.reset(state)
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, seats[player])
	end
end

local function startMatch()
	local tutorial = TutorialService.enabled()
	local setup = if tutorial then nil else LobbyService.setup()
	local state = MatchService.start(if tutorial then Config.Tutorial.Map else MatchService.chooseMap(setup), setup)
	if not tutorial then
		state.theme = MatchService.forcedTheme(setup) -- no vote without the Lobby: the server's theme, or classic
	end
	CommandRouter.clear()
	AIService.reset(if tutorial then Config.Tutorial.Difficulty else state.setup.settings.difficulty)
	if tutorial then
		TutorialService.start(state)
	else
		TutorialService.stop() -- Studio: the Tutorial attribute was removed; seat players in the new match
	end
	seatAll(state, not tutorial)
	ShopService.onPhase("Peace")
	print(string.format("[server] match started on %s", state.mapId))
end

-- Lobby, part 1: the map vote (also after Results, for the next map). Everyone stays in the server.
local function openLobby()
	TutorialService.stop()
	LobbyService.open(MatchService.lockedMap())
	CommandRouter.clear()
	Replicator.sendLobby(LobbyService.view())
	ShopService.onPhase("Lobby")
	TelemetryService.lobbyOpened() -- analytics: a new MatchFlow session for everyone here
	print("[server] lobby open: vote on the map")
end

-- Lobby, part 2: the vote is over; the draft runs on a fresh match of the winning map, shown to everyone.
local function startPick()
	local mapId = LobbyService.winner()
	local setup = LobbyService.setup()
	-- the theme vote: the theme most of the map's voters have equipped (or the server's setting)
	LobbyService.chooseTheme(mapId, ShopService.themesByUser(), MatchService.forcedTheme(setup))
	local state = MatchService.start(mapId, setup)
	TelemetryService.voteOver(assert(LobbyService.state())) -- analytics: map_vote for every voter
	CommandRouter.clear()
	AIService.reset(state.setup.settings.difficulty)
	LobbyService.startPick(state) -- also paints the match in the chosen theme
	Replicator.reset(state)
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, nil)
	end
	print(string.format("[server] draft on %s", state.mapId))
end

-- The draft is over: the match starts in Peace at tick 0. Anyone who didn't get a turn takes a bot's nation.
local function startDraftedMatch()
	LobbyService.finish()
	local state = MatchService.state()
	seatAll(state, true)
	Replicator.sendLobby(LobbyService.view()) -- "None": the lobby screens close
	Replicator.notifyAll("Phase", "🕊 The match begins! Expand and build")
	ShopService.onPhase("Peace") -- Robux purchases close for the match
	print(string.format("[server] match started on %s", state.mapId))
end

-- The sandbox ----------------------------------------------------------------------------------------------------

-- A new sandbox world on a map: every nation a bot, everyone here watching, no Lobby (docs/DESIGN.md "Sandbox").
local function startSandbox(mapId: string)
	TutorialService.stop()
	local state = MatchService.start(mapId, Sandbox.setup())
	state.theme = MatchService.forcedTheme(nil) -- the server's theme (Workspace "Theme"), or classic
	SandboxService.start(state)
	CommandRouter.clear()
	AIService.reset(Config.Sandbox.Difficulty)
	Replicator.reset(state)
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, SandboxService.seat(player))
	end
	ShopService.onPhase(state.phase)
end

-- One sandbox tick: the match's tick order without its end (Sim.Sandbox) and without match stats, rewards or
-- analytics (a sandbox pays nothing and logs only sandbox_started).
local function sandboxTick(state: Types.MatchState)
	DevService.step(state) -- Studio-only test switches
	CommandRouter.applyQueued(state) -- 1. apply queued commands
	local newPhase = MatchService.advance() -- 2-8. armies, battles, sieges, income, powers (no win check)
	AIService.step(state) -- 7. bots plan
	if newPhase and PHASE_TOASTS[newPhase] then
		Replicator.notifyAll("Phase", PHASE_TOASTS[newPhase])
	end
	Replicator.broadcast(state) -- 9. one delta to every client
end

-- The sandbox's loop: a beat every Config.Sandbox.BeatSeconds runs a tick whenever the world's speed has gathered a
-- game second (4× ticks at every beat, 1× at every fourth). Paused, the clock stops and the bots wait, but orders and
-- powers still land at each beat. The controls and a take-over are sent at the next beat whether or not it ticked.
local function runSandbox()
	local owed = 0 -- game seconds the clock owes
	local last = os.clock()
	while true do
		task.wait(Config.Sandbox.BeatSeconds)
		local now = os.clock()
		local ok, err = pcall(function()
			local newWorld = SandboxService.takeNewWorld()
			if newWorld then
				startSandbox(newWorld)
				owed = 0
				return
			end
			local state = MatchService.state()
			local speed = SandboxService.speed()
			local changed = SandboxService.takeChanged()
			CommandRouter.applyLobbyQueued(nil) -- votes and picks mean nothing here
			local ran = 0
			owed += (now - last) * speed
			while owed >= Config.TickSeconds and ran < Config.Sandbox.MaxTicksPerBeat do
				owed -= Config.TickSeconds
				ran += 1
				sandboxTick(state)
			end
			owed = math.min(owed, Config.TickSeconds) -- a long stall is skipped, not replayed
			if ran == 0 and speed == 0 then
				CommandRouter.applyQueued(state) -- paused: orders and powers land, the clock stays
			end
			if ran == 0 and (speed == 0 or changed) then
				Replicator.broadcast(state)
			end
		end)
		last = now
		if not ok then
			warn("[server] sandbox beat failed: " .. tostring(err))
		end
	end
end

-- The next match: the Lobby, or straight into Peace with SkipLobby.
local function nextMatch()
	if LobbyService.skipped() or TutorialService.enabled() then
		startMatch()
	else
		openLobby()
	end
end

Replicator.init()
CommandRouter.init(MatchService.nationOf)
PlayerDataService.init()
ProgressionService.init(MatchService.current)
TutorialService.init()
ShopService.init(function(): string
	if LobbyService.active() then
		return LobbyService.phase()
	end
	local state = MatchService.current()
	return if state then state.phase else "Lobby"
end, MatchService.current, MatchService.nationOf)
QuestService.init()
AdRewardService.init() -- after QuestService: the quest reroll ad and the notification prompt
SeasonService.init()
AchievementService.init() -- after QuestService: its reward hook runs after the quests'
LeaderboardService.init()
Replicator.setCosmetics(ShopService.cosmetics)
TelemetryService.init()
SandboxService.init()
ServerMode.await() -- a reserved server learns from its first player whether it plays the tutorial or a sandbox
if SandboxService.enabled() then
	startSandbox(SandboxService.firstMap())
else
	nextMatch()
end

Players.PlayerAdded:Connect(function(player)
	if LobbyService.active() then
		-- joining the vote or the draft: the lobby, and the drafted map if there is one
		LobbyService.join(player)
		local drafted = LobbyService.match()
		if drafted then
			Replicator.sendSnapshot(player, drafted, nil)
		end
		Replicator.sendLobby(LobbyService.view(), player)
		return
	end
	local nationId = seat(player)
	Replicator.sendSnapshot(player, MatchService.state(), nationId)
end)

Players.PlayerRemoving:Connect(function(player)
	if LobbyService.active() then
		LobbyService.leave(player)
	else
		MatchService.unseat(player)
	end
end)

local function tick()
	local state = MatchService.state()
	DevService.step(state) -- Studio-only test switches (Workspace attributes; docs/STUDIO.md)
	CommandRouter.applyQueued(state) -- 1. apply queued commands
	local newPhase = MatchService.advance() -- 2-8. armies, battles, sieges, income, win checks
	-- 7. bots plan. Sim.Tick runs steps 2-8 in one call, so bots plan right after it; their commands wait in the
	-- queue for step 1 of the next tick either way, so nothing changes in between.
	AIService.step(state)
	TutorialService.afterTick(state) -- the tutorial's prompts and the bots' part in it
	ProgressionService.afterTick(state) -- match stats from this tick's events; XP and Glory at Results
	TelemetryService.afterTick(state) -- analytics: MatchFlow, match and player events (after the rewards)
	if newPhase and PHASE_TOASTS[newPhase] then
		Replicator.notifyAll("Phase", PHASE_TOASTS[newPhase])
	end
	if newPhase then
		ShopService.onPhase(newPhase) -- after the rewards: the starter-pack offer counts finished matches
	end
	Replicator.broadcast(state) -- 9. one delta (with this tick's events) to every client
end

-- A Lobby second: votes and picks, the clocks, then what changed to every client.
local function lobbyTick()
	CommandRouter.refuseQueued("WrongPhase") -- no orders before the match starts
	CommandRouter.applyLobbyQueued(LobbyService.apply)
	if LobbyService.step() then
		if LobbyService.phase() == "Lobby" then
			startPick()
		else
			startDraftedMatch()
			return
		end
	end
	Replicator.sendLobby(LobbyService.view())
	local drafted = LobbyService.match()
	if drafted then
		Replicator.broadcast(drafted) -- the picks, as nation changes
	end
end

if SandboxService.enabled() then
	runSandbox() -- never returns: a sandbox world never ends
end

-- Fixed-rate loop that doesn't drift: each tick is scheduled from the previous target time.
local nextTick = os.clock() + Config.TickSeconds
while true do
	task.wait(math.max(0, nextTick - os.clock()))
	nextTick += Config.TickSeconds
	if LobbyService.active() then
		local ok, err = pcall(lobbyTick)
		if not ok then
			warn("[server] lobby tick failed: " .. tostring(err))
		end
	else
		CommandRouter.applyLobbyQueued(nil) -- votes and picks mean nothing during a match
		local ok, err = pcall(tick)
		if not ok then
			warn("[server] tick failed: " .. tostring(err))
		end
		if MatchService.isOver() then
			TutorialService.matchOver()
			nextMatch()
			nextTick = os.clock() + Config.TickSeconds
		end
	end
end
