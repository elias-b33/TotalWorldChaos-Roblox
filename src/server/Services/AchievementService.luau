--!strict
-- Achievements (docs/MONETIZATION.md 5.6): checks every match reward (Results, or leaving early) against the 30
-- achievements, pays the ones it earns (Glory on the Results breakdown, titles and cosmetics into the profile) and
-- sends each player their progress. Titles are equipped like any cosmetic (RequestEquip, ShopService).
-- Thin wrapper: the rules are in Shared.Sim.Achievements, saving is PlayerDataService's, the match stats are
-- ProgressionService's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Achievements = require(Shared.Sim.Achievements)
local Catalogue = require(Shared.Catalogue)
local Progression = require(Shared.Sim.Progression)
local Remotes = require(Shared.Remotes)
local Settings = require(Shared.Sim.Settings)
local Shop = require(Shared.Sim.Shop)
local Types = require(Shared.Types)

local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local ShopService = require(script.Parent.ShopService)

local AchievementService = {}

local remote: RemoteEvent
local recent: { [Player]: { string } } = {} -- what the last match earned (the Results screen)

function AchievementService.sendView(player: Player)
	local data = PlayerDataService.data(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	local title = Shop.equippedIn(data, "Title", ShopService.isVip(player)) or Catalogue.DEFAULTS.Title
	remote:FireClient(player, Achievements.view(data, title, recent[player]))
end

-- Inside the match reward's profile update: count the match, pay what it earned (each achievement's Glory is a
-- line on the Results breakdown, so analytics logs it as the "achievement" Glory source).
local function onReward(
	player: Player,
	data: Types.PlayerProfile,
	stats: Types.PlayerMatchStats,
	report: Types.RewardReport,
	state: Types.MatchState
)
	local reward = report.reward
	local earned, glory = Achievements.check(state, data, stats, reward, Settings.fullRewards(state))
	Progression.addLine(reward, "Achievement", 0, glory) -- one line for them all; already in data.glory
	for _, id in earned do
		local def = Achievements.def(id)
		print(string.format("[achievements] %s earned %s", player.Name, if def then def.name else id))
	end
	if reward.stayed then
		recent[player] = earned
	end
	if player.Parent == Players then
		task.defer(function() -- after the update has saved
			AchievementService.sendView(player)
			if #earned > 0 then
				ShopService.refresh(player) -- a new title or cosmetic to equip
			end
		end)
	end
end

function AchievementService.init()
	remote = Remotes.event("Achievements")
	PlayerDataService.onLoaded(AchievementService.sendView)
	ProgressionService.onReward(onReward)
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
	end)
end

return AchievementService
