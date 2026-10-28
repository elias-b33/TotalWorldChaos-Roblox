--!strict
-- Rewarded video and experience notifications (docs/MONETIZATION.md 3.7, 7.6, 10 "Ads"). Named AdRewardService so
-- it never clashes with Roblox's AdService.
--
-- Rewarded video, the one placement: the Quests screen's "Watch an ad" button (Lobby only) sends RequestAd. Sim.Ads
-- checks the rules (the map vote with time left, no free reroll left, a daily quest to reroll, under today's cap), then this service
-- wraps the "Quest reroll" developer product with AdService:CreateAdRewardFromDevProductId and plays the video with
-- AdService:ShowRewardedVideoAdAsync. Roblox grants the reward through MarketplaceService.ProcessReceipt with
-- ProductPurchaseChannel.AdReward (never from the ad's result): ShopService hands that receipt here, and
-- PlayerDataService.processReceipt grants it once, saves it, and keeps it out of the Robux purchase history. The
-- client asks AdService:GetAdAvailabilityNowAsync before it shows the button, so players Roblox reports as
-- ineligible (under 13, device, region) never see it.
-- Test mode: while the product id is 0, Studio grants the reward straight away through the same receipt path (no
-- video), and a live server refuses ("Not on sale yet").
--
-- Notifications: inside the match reward, Sim.Ads decides whether this was the player's first finished match (once
-- per profile, never the tutorial); the client then shows Roblox's opt-in prompt back in the Lobby, if
-- ExperienceNotificationService:CanPromptOptInAsync says it may (client-only APIs).
-- Thin wrapper: the rules are in Shared.Sim.Ads and Shared.Sim.Quests.

local AdService = game:GetService("AdService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Ads = require(Shared.Sim.Ads)
local Catalogue = require(Shared.Catalogue)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local LobbyService = require(script.Parent.LobbyService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local QuestService = require(script.Parent.QuestService)
local ShopService = require(script.Parent.ShopService)
local TelemetryService = require(script.Parent.TelemetryService)
local TutorialService = require(script.Parent.TutorialService)

local AdRewardService = {}

local busy: { [Player]: boolean } = {} -- a video is playing for this player
local promptRemote: RemoteEvent

-- A "Quest reroll" receipt (a rewarded video's, or bought with Robux on the store page): one more free reroll today.
local function onReceipt(receipt: any): Enum.ProductPurchaseDecision
	local fromAd = receipt.ProductPurchaseChannel == Enum.ProductPurchaseChannel.AdReward
	local fresh = false
	local decision = PlayerDataService.processReceipt(receipt, Ads.PRODUCT, function(data)
		Ads.grant(data, receipt.PlayerId, ProgressionService.today(), fromAd)
		fresh = true
	end, fromAd)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player and decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		if fresh and not fromAd then
			TelemetryService.purchased(player, Ads.PRODUCT, receipt.CurrencySpent) -- analytics: a Robux purchase
			ShopService.refresh(player) -- the shop's purchase history lists it
		end
		QuestService.sendView(player)
	end
	return decision
end

-- Play the video. True once it played to the end (the reward arrives through ProcessReceipt). May yield a long time.
local function play(player: Player, productId: number): boolean
	if productId == 0 then
		-- test mode (Studio only): no video, the same receipt path with a made-up AdReward receipt
		local receipt = {
			PurchaseId = "studio-ad-" .. HttpService:GenerateGUID(false),
			PlayerId = player.UserId,
			ProductId = 0,
			CurrencySpent = 0,
			ProductPurchaseChannel = Enum.ProductPurchaseChannel.AdReward,
		}
		return onReceipt(receipt) == Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local ok, result = pcall(function()
		local reward = AdService:CreateAdRewardFromDevProductId(productId)
		return AdService:ShowRewardedVideoAdAsync(player, reward)
	end)
	if not ok then
		print("[ads] the rewarded video failed: " .. tostring(result)) -- never warn: ads must not break the game
	end
	return ok and result == Enum.ShowAdResult.ShowCompleted
end

-- A RequestAd from CommandRouter (shape and rate limit already checked). Yields while the video plays.
function AdRewardService.watch(player: Player, placement: string): (boolean, string?)
	if placement ~= Ads.PLACEMENT then
		return false, "BadRequest"
	end
	local data = PlayerDataService.data(player)
	if data == nil then
		return false, "NotLoaded"
	end
	local lobby = LobbyService.state()
	local voteSecondsLeft = if lobby and lobby.phase == "Lobby" then lobby.ticksLeft * Config.TickSeconds else nil
	local ok, reason = Ads.canWatch(data, ShopService.isVip(player), voteSecondsLeft, busy[player] == true)
	if not ok then
		return false, reason
	end
	local productId = Catalogue.productId(Ads.PRODUCT)
	if productId == 0 and not RunService:IsStudio() then
		return false, "NotForSale" -- the owner hasn't created the product yet
	end
	busy[player] = true
	local completed = play(player, productId)
	busy[player] = nil
	TelemetryService.adRewarded(player, Ads.PLACEMENT, if completed then "completed" else "failed")
	QuestService.sendView(player)
	return completed, if completed then nil else "AdFailed"
end

-- Inside the match reward's profile update: the first finished match asks for notifications (once per profile).
local function onReward(
	player: Player,
	data: Types.PlayerProfile,
	_stats: Types.PlayerMatchStats,
	report: Types.RewardReport
)
	if Ads.takeNotificationPrompt(data, report.reward, TutorialService.enabled()) and player.Parent == Players then
		promptRemote:FireClient(player)
	end
end

function AdRewardService.init()
	promptRemote = Remotes.event("NotificationPrompt")
	CommandRouter.onAd(AdRewardService.watch)
	ShopService.onProduct(Ads.PRODUCT, onReceipt)
	ProgressionService.onReward(onReward)
	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
	end)
end

return AdRewardService
