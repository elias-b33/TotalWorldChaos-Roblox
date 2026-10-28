--!strict
-- Boots the server and runs the 1-second tick (docs/DESIGN.md "Tick order").
-- Step 1 is CommandRouter, steps 2-8 are Shared.Sim.Tick (via MatchService), step 7 (bots) is AIService, step 9 is
-- Replicator. Between matches the Lobby runs instead (map vote, then nation draft; LobbyService), unless Workspace
-- has SkipLobby set, which starts every match straight away. A tutorial server (TutorialService) skips the Lobby too
-- and plays the tutorial match.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

Remotes.create()
Players.CharacterAutoLoads = false -- the game is the map; nobody needs an avatar walking around

local Server = script.Parent
local AIService = require(Server.Services.AIService)
local CommandRouter = require(Server.CommandRouter)
local LobbyService = require(Server.Services.LobbyService)
local MatchService = require(Server.Services.MatchService)
local PlayerDataService = require(Server.Services.PlayerDataService)
local ProgressionService = require(Server.Services.ProgressionService)
local Replicator = require(Server.Replicator)
local TutorialService = require(Server.Services.TutorialService)

local PHASE_TOASTS = {
	War = "War! Nations can fight now",
	Cataclysm = "Cataclysm! The Primordials stir",
	Results = "The match is over",
}

-- A tutorial match seats its player in the tutorial nation.
local function seat(player: Player): number?
	if TutorialService.active() then
		return TutorialService.seat(player)
	end
	return MatchService.seat(player)
end

local function startMatch()
	local tutorial = TutorialService.enabled()
	local state = MatchService.start(if tutorial then Config.Tutorial.Map else MatchService.chooseMap())
	CommandRouter.clear()
	AIService.reset(if tutorial then Config.Tutorial.Difficulty else nil)
	if tutorial then
		TutorialService.start(state)
	end
	Replicator.reset(state)
	-- seat everyone who is already here, in join order
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, seat(player))
	end
	print(string.format("[server] match started on %s", state.mapId))
end

-- Lobby, part 1: the map vote (also after Results, for the next map). Everyone stays in the server.
local function openLobby()
	LobbyService.open(MatchService.lockedMap())
	CommandRouter.clear()
	Replicator.sendLobby(LobbyService.view())
	print("[server] lobby open: vote on the map")
end

-- Lobby, part 2: the vote is over; the draft runs on a fresh match of the winning map, shown to everyone.
local function startPick()
	local state = MatchService.start(LobbyService.winner())
	CommandRouter.clear()
	AIService.reset()
	LobbyService.startPick(state)
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
	Replicator.reset(state)
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, MatchService.seat(player))
	end
	Replicator.sendLobby(LobbyService.view()) -- "None": the lobby screens close
	Replicator.notifyAll("Phase", "🕊 The match begins! Expand and build")
	print(string.format("[server] match started on %s", state.mapId))
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
nextMatch()

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
	CommandRouter.applyQueued(state) -- 1. apply queued commands
	local newPhase = MatchService.advance() -- 2-8. armies, battles, sieges, income, win checks
	-- 7. bots plan. Sim.Tick runs steps 2-8 in one call, so bots plan right after it; their commands wait in the
	-- queue for step 1 of the next tick either way, so nothing changes in between.
	AIService.step(state)
	TutorialService.afterTick(state) -- the tutorial's prompts and the bots' part in it
	ProgressionService.afterTick(state) -- match stats from this tick's events; XP and Glory at Results
	if newPhase and PHASE_TOASTS[newPhase] then
		Replicator.notifyAll("Phase", PHASE_TOASTS[newPhase])
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
