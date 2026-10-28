--!strict
-- Your season pass, as the server tells it (Season remote, docs/MONETIZATION.md 6): the season, your tier and season
-- XP, the pass, what you have claimed and how many rewards wait. The client never grants anything: it only asks to
-- claim (Intents.claimSeason) or to buy the pass through the shop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local SeasonState = {}

local view: Types.SeasonView? = nil
local claimedSet: { [string]: boolean } = {}
local listeners: { () -> () } = {}

function SeasonState.init()
	Remotes.event("Season").OnClientEvent:Connect(function(data: Types.SeasonView)
		view = data
		claimedSet = {}
		for _, key in data.claimed do
			claimedSet[key] = true
		end
		for _, fn in listeners do
			task.spawn(fn)
		end
	end)
end

function SeasonState.view(): Types.SeasonView?
	return view
end

-- Is a season running (and loaded)?
function SeasonState.active(): boolean
	return view ~= nil and view.id ~= ""
end

-- Have I claimed this reward key ("F3", "P3")?
function SeasonState.claimed(key: string): boolean
	return claimedSet[key] == true
end

-- Rewards waiting to be claimed.
function SeasonState.readyCount(): number
	return if view then view.ready else 0
end

function SeasonState.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

return SeasonState
