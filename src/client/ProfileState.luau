--!strict
-- Your own account progress, as the server tells it: the profile summary (Profile remote: level, XP, Glory, rank)
-- and the reward for the match that just ended (Reward remote). The client never grants anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)

local ProfileState = {}

local summary: Types.ProfileSummary? = nil
local report: Types.RewardReport? = nil
local listeners: { () -> () } = {}

local function emit()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function ProfileState.init()
	Remotes.event("Profile").OnClientEvent:Connect(function(data: Types.ProfileSummary)
		summary = data
		emit()
	end)
	Remotes.event("Reward").OnClientEvent:Connect(function(data: Types.RewardReport)
		report = data
		emit()
	end)
	ClientState.onReset(function() -- a new match: the old reward is spent
		if report then
			report = nil
			emit()
		end
	end)
end

function ProfileState.summary(): Types.ProfileSummary?
	return summary
end

-- The reward for the match that just ended, until the next match starts.
function ProfileState.reward(): Types.RewardReport?
	return report
end

function ProfileState.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

return ProfileState
