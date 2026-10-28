--!strict
-- Quests, the login calendar and the play streak (docs/MONETIZATION.md 5.4–5.6): refreshes each player's quests
-- for the UTC day, counts the match for them at Results (or when a player leaves), moves the calendar and the streak
-- on the day's first finished match (its Glory joins the Results breakdown), and answers claims and rerolls.
-- Thin wrapper: the rules are in Shared.Sim.Quests and Shared.Sim.Login, saving is PlayerDataService's, the match
-- stats are ProgressionService's.
--
-- Rewarded video (Phase 5): the one ad placement, on the Quests screen, calls Quests.grantVideoReroll on the
-- player's book after a finished video, through PlayerDataService.update, then sendView. Nothing calls it yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Login = require(Shared.Sim.Login)
local Progression = require(Shared.Sim.Progression)
local Quests = require(Shared.Sim.Quests)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local ShopService = require(script.Parent.ShopService)

local DAY_CHECK_SECONDS = 5 -- how often to look for a new UTC day (midnight, or DevDay in Studio)

local QuestService = {}

local questsRemote: RemoteEvent
local gains: { [Player]: { [string]: number } } = {} -- what the last match added to each quest (Results)
local refreshedFor = -1 -- the day every loaded player's quests were last refreshed for

local function today(): number
	return ProgressionService.today()
end

function QuestService.sendView(player: Player)
	local data = PlayerDataService.data(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	questsRemote:FireClient(player, Quests.view(data, today(), ShopService.isVip(player), gains[player]))
end

-- Bring a player's quests up to today (a new day or week) and show them.
local function refresh(player: Player)
	local data = PlayerDataService.data(player)
	if data == nil then
		return
	end
	local day = today()
	if data.quests.day ~= day or data.quests.week ~= Quests.weekOf(day) then
		PlayerDataService.update(player, function(profile)
			Quests.refresh(profile.quests, player.UserId, day)
		end)
	end
	QuestService.sendView(player)
end

-- Inside the match reward's profile update (Results, or leaving early): the quests count the match, and the day's
-- first finished match moves the calendar (its Glory goes on the breakdown) and the streak.
local function onReward(
	player: Player,
	data: Types.PlayerProfile,
	stats: Types.PlayerMatchStats,
	report: Types.RewardReport
)
	local day = today()
	local reward = report.reward
	Quests.refresh(data.quests, player.UserId, day)
	local gained = Quests.applyMatch(data.quests, stats, reward)
	if reward.stayed then
		gains[player] = gained -- for the Results screen (a leaver has none to see)
	end
	if reward.stayed and not reward.afk and stats.seated then
		local glory = Login.recordPlay(data.login, day)
		if glory > 0 then
			Progression.addLine(reward, "Calendar", 0, glory)
			data.glory += glory
		end
	end
	if player.Parent == Players then
		task.defer(QuestService.sendView, player) -- after the update has saved
	end
end

-- A claim or reroll from CommandRouter (shape already checked). May yield (saves).
function QuestService.apply(player: Player, intent: Types.QuestIntent): (boolean, string?)
	local vip = ShopService.isVip(player)
	local day = today()
	local result = PlayerDataService.update(player, function(data)
		Quests.refresh(data.quests, player.UserId, day)
		local ok, reason
		if intent.kind == "Claim" then
			ok, reason = Quests.claim(data, intent.key)
		else
			ok, reason = Quests.reroll(data, intent.key, vip, Quests.rerollRng(data.quests, player.UserId))
		end
		return { ok = ok, reason = reason }
	end)
	QuestService.sendView(player)
	if result == nil then
		return false, "NotLoaded"
	end
	return result.ok, result.reason
end

function QuestService.init()
	questsRemote = Remotes.event("Quests")
	PlayerDataService.onLoaded(refresh)
	ProgressionService.onReward(onReward)
	CommandRouter.onQuest(QuestService.apply)
	Players.PlayerRemoving:Connect(function(player)
		gains[player] = nil
	end)
	-- a new UTC day (midnight, or DevDay in Studio): everyone's new quests
	refreshedFor = today()
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_SECONDS)
			if today() ~= refreshedFor then
				refreshedFor = today()
				for _, player in Players:GetPlayers() do
					task.spawn(refresh, player)
				end
			end
		end
	end)
end

return QuestService
