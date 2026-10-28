--!strict
-- Your quests, login calendar and play streak, as the server tells it (Quests remote, docs/MONETIZATION.md
-- 5.4–5.6). The client never grants anything: it only asks to claim or reroll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local QuestState = {}

local view: Types.QuestView? = nil
local listeners: { () -> () } = {}

function QuestState.init()
	Remotes.event("Quests").OnClientEvent:Connect(function(data: Types.QuestView)
		view = data
		for _, fn in listeners do
			task.spawn(fn)
		end
	end)
end

function QuestState.view(): Types.QuestView?
	return view
end

-- Finished quests waiting to be claimed.
function QuestState.readyCount(): number
	local v = view
	if v == nil then
		return 0
	end
	local n = 0
	for _, list in { v.daily, v.weekly } do
		for _, q in list do
			if not q.claimed and q.progress >= q.target then
				n += 1
			end
		end
	end
	return n
end

function QuestState.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

return QuestState
