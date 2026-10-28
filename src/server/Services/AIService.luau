--!strict
-- Bots (tick order step 7). Thin wrapper: Shared.Sim.Bot picks which bots plan this tick and what they want;
-- their commands go into CommandRouter exactly like a player's, and are applied at the start of the next tick.
-- Every nation without a player is a bot (Match seats bots in every slot). A player who leaves turns their nation
-- back into a bot (Match.unseatPlayer), and the schedule hands it to the AI on the very next tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Bot = require(Shared.Sim.Bot)
local Config = require(Shared.Config)
local Rng = require(Shared.Sim.Rng)
local Types = require(Shared.Types)

local CommandRouter = require(script.Parent.Parent.CommandRouter)

local AIService = {}

local schedule = Bot.newSchedule()
local rng = Rng.new(1)
local difficulty = Config.Bots.Difficulty :: Bot.Difficulty

-- A new match: forget every bot's schedule and memory. `level` overrides Config.Bots.Difficulty for this match
-- (the tutorial plays Easy).
function AIService.reset(level: string?)
	schedule = Bot.newSchedule()
	rng = Rng.new(os.time() + 1) -- the planner's own random choices; Sim never calls math.random
	difficulty = (level or Config.Bots.Difficulty) :: Bot.Difficulty
end

-- The bots due this tick plan and submit their commands.
function AIService.step(state: Types.MatchState)
	for _, order in Bot.step(schedule, state, rng, difficulty) do
		CommandRouter.submitForBot(order.nation, order.command)
	end
end

return AIService
