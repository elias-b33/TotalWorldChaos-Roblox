--!strict
-- Sends intents to the server and reports refusals. The server answers every request with
-- CommandResult(requestId, ok, reason); the visible state change arrives separately in the next delta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

-- Short, icon-first messages for every reason code (Sim.Commands and CommandRouter).
local REASONS: { [string]: string } = {
	NotEnoughGold = "💰 Not enough gold",
	NotEnoughManpower = "👥 Not enough manpower",
	MaxDevelopment = "⬆ Already at max development",
	AlreadyBuilt = "🏗 This province already has a building",
	NotYourProvince = "🚫 Not your province",
	UnknownProvince = "🚫 Unknown province",
	WrongPhase = "⏳ Not now",
	NoNation = "👀 You're spectating",
	TooFast = "⏱ Too fast, slow down",
	BadAmount = "🚫 Bad amount",
	BadBuilding = "🚫 Unknown building",
	BadRequest = "🚫 Bad request",
}

local Intents = {}

local nextId = 0
local onRefused: ((string) -> ())? = nil

function Intents.init(showMessage: (string) -> ())
	onRefused = showMessage
	Remotes.event("CommandResult").OnClientEvent:Connect(function(_requestId: number, ok: boolean, reason: string?)
		if not ok and onRefused then
			onRefused(REASONS[reason or ""] or ("🚫 " .. tostring(reason)))
		end
	end)
end

local function send(remoteName: string, ...: any)
	nextId += 1
	Remotes.event(remoteName):FireServer(nextId, ...)
end

function Intents.develop(provinceId: number)
	send("RequestDevelop", provinceId)
end

function Intents.build(provinceId: number, building: string)
	send("RequestBuild", provinceId, building)
end

function Intents.recruit(provinceId: number, regiments: number)
	send("RequestRecruit", provinceId, regiments)
end

return Intents
