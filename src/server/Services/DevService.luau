--!strict
-- Studio-only test switches (docs/STUDIO.md): Workspace attributes the owner sets in the Properties window during
-- a test run (on the server's view). Each is applied once at the start of the next tick and then removed. Ignored
-- on live servers, so no player can reach them; it's the one place outside CommandRouter that changes the match.
--   DevTick     number  sets the match clock (179: War next second, 1199: the Cataclysm, 1499: the end)
--   DevCharges  number  every nation and Primordial gets this many power charges
--   DevGold     number  every nation with a player gets this much gold

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
ReplicatedStorage:WaitForChild("Shared")
local Types = require(ReplicatedStorage.Shared.Types)

local DevService = {}

local function take(name: string): number?
	local value = Workspace:GetAttribute(name)
	if value == nil then
		return nil
	end
	Workspace:SetAttribute(name, nil)
	if type(value) ~= "number" or value ~= value then
		warn(string.format("[dev] %s needs a number", name))
		return nil
	end
	return math.max(0, math.floor(value))
end

function DevService.step(state: Types.MatchState)
	if not RunService:IsStudio() then
		return
	end
	local tick = take("DevTick")
	if tick then
		state.tick = tick
		print(string.format("[dev] match clock set to tick %d", tick))
	end
	local charges = take("DevCharges")
	if charges then
		for _, nation in state.nations do
			nation.charges = charges
		end
		for _, primordial in state.primordials do
			primordial.charges = charges
		end
		print(string.format("[dev] every nation and Primordial has %d charges", charges))
	end
	local gold = take("DevGold")
	if gold then
		for _, nation in state.nations do
			if nation.controller == "Player" then
				nation.gold = gold
			end
		end
		print(string.format("[dev] every player nation has %d gold", gold))
	end
end

return DevService
