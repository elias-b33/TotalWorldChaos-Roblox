--!strict
-- Boots the server and runs the 1-second tick (docs/DESIGN.md "Tick order").
-- Step 1 is CommandRouter, steps 2-8 are Shared.Sim.Tick (via MatchService), step 7 (bots) is AIService, step 9 is
-- Replicator.

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
local MatchService = require(Server.Services.MatchService)
local PlayerDataService = require(Server.Services.PlayerDataService)
local ProgressionService = require(Server.Services.ProgressionService)
local Replicator = require(Server.Replicator)

local PHASE_TOASTS = {
	War = "War! Nations can fight now",
	Cataclysm = "Cataclysm! The Primordials stir",
	Results = "The match is over",
}

local function startMatch()
	local state = MatchService.start(MatchService.chooseMap())
	CommandRouter.clear()
	AIService.reset()
	Replicator.reset(state)
	-- seat everyone who is already here, in join order
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, MatchService.seat(player))
	end
	print(string.format("[server] match started on %s", state.mapId))
end

Replicator.init()
CommandRouter.init(MatchService.nationOf)
PlayerDataService.init()
ProgressionService.init(MatchService.state)
startMatch()

Players.PlayerAdded:Connect(function(player)
	local nationId = MatchService.seat(player)
	Replicator.sendSnapshot(player, MatchService.state(), nationId)
end)

Players.PlayerRemoving:Connect(function(player)
	MatchService.unseat(player)
end)

local function tick()
	local state = MatchService.state()
	CommandRouter.applyQueued(state) -- 1. apply queued commands
	local newPhase = MatchService.advance() -- 2-8. armies, battles, sieges, income, win checks
	-- 7. bots plan. Sim.Tick runs steps 2-8 in one call, so bots plan right after it; their commands wait in the
	-- queue for step 1 of the next tick either way, so nothing changes in between.
	AIService.step(state)
	ProgressionService.afterTick(state) -- match stats from this tick's events; XP and Glory at Results
	if newPhase and PHASE_TOASTS[newPhase] then
		Replicator.notifyAll("Phase", PHASE_TOASTS[newPhase])
	end
	Replicator.broadcast(state) -- 9. one delta (with this tick's events) to every client
end

-- Fixed-rate loop that doesn't drift: each tick is scheduled from the previous target time.
local nextTick = os.clock() + Config.TickSeconds
while true do
	task.wait(math.max(0, nextTick - os.clock()))
	nextTick += Config.TickSeconds
	local ok, err = pcall(tick)
	if not ok then
		warn("[server] tick failed: " .. tostring(err))
	end
	if MatchService.isOver() then
		startMatch()
		nextTick = os.clock() + Config.TickSeconds
	end
end
