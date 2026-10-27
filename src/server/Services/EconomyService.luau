--!strict
-- Pays income and upkeep once a month (tick order step 5). Thin wrapper around Shared.Sim.Economy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Economy = require(Shared.Sim.Economy)
local Types = require(Shared.Types)

local EconomyService = {}

function EconomyService.onTick(state: Types.MatchState)
	if state.tick % Config.MonthTicks == 0 then
		Economy.payMonth(state)
	end
end

return EconomyService
