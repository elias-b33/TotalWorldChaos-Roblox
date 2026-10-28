--!strict
-- Your achievements and the leaderboards, as the server tells it (the Achievements and Boards remotes,
-- docs/MONETIZATION.md 5.6, 7.3). The client never grants anything: titles are equipped through the shop's
-- RequestEquip.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local TrophyState = {}

local achievements: Types.AchievementView? = nil
local boards: Types.BoardsView? = nil
local listeners: { () -> () } = {}

local function changed()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

function TrophyState.init()
	Remotes.event("Achievements").OnClientEvent:Connect(function(data: Types.AchievementView)
		achievements = data
		changed()
	end)
	Remotes.event("Boards").OnClientEvent:Connect(function(data: Types.BoardsView)
		boards = data
		changed()
	end)
end

function TrophyState.achievements(): Types.AchievementView?
	return achievements
end

function TrophyState.boards(): Types.BoardsView?
	return boards
end

-- Achievements earned so far.
function TrophyState.doneCount(): number
	local n = 0
	for _, a in if achievements then achievements.list else {} do
		n += if a.done then 1 else 0
	end
	return n
end

function TrophyState.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

return TrophyState
