--!strict
-- Boots the server and runs the 1-second tick (docs/DESIGN.md "Tick order").
-- Phase 1 runs steps 1, 5, 8 and 9; armies, battles, sieges, gods and bots plug in here as they arrive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

Remotes.create()
Players.CharacterAutoLoads = false -- the game is the map; nobody needs an avatar walking around

local Server = script.Parent
local CommandRouter = require(Server.CommandRouter)
local EconomyService = require(Server.Services.EconomyService)
local MatchService = require(Server.Services.MatchService)
local Replicator = require(Server.Replicator)

local PHASE_TOASTS = {
	War = "War! Nations can fight now",
	Cataclysm = "Cataclysm! The gods are restless",
	Results = "The match is over",
}

local function startMatch()
	local state = MatchService.start(MatchService.chooseMap())
	CommandRouter.clear()
	Replicator.reset(state)
	-- seat everyone who is already here, in join order
	for _, player in Players:GetPlayers() do
		Replicator.sendSnapshot(player, state, MatchService.seat(player))
	end
	print(string.format("[server] match started on %s", state.mapId))
end

Replicator.init()
CommandRouter.init(MatchService.nationOf)
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
	local newPhase = MatchService.advance()
	-- 2-4. move armies, resolve battles, advance sieges (Phase 2)
	EconomyService.onTick(state) -- 5. income and upkeep every month
	-- 6-7. god-power charges, bots plan (Phase 3)
	if newPhase and PHASE_TOASTS[newPhase] then -- 8. phase changes (win checks arrive in Phase 2)
		Replicator.notifyAll("Phase", PHASE_TOASTS[newPhase])
	end
	Replicator.broadcast(state) -- 9. one delta to every client
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
