--!strict
-- The client side of rewarded video and experience notifications (docs/MONETIZATION.md 3.7, 7.6, 10 "Ads").
--
-- Rewarded video: the Quests screen calls Ads.check when it could offer a video (Lobby, no free reroll left): it
-- asks AdService:GetAdAvailabilityNowAsync (client only), and the "Watch an ad" button shows only while Roblox says
-- IsAvailable, so players it reports as ineligible (under 13, device, region, no fill) never see it. One answer is
-- good for one ad: Ads.watch forgets it. The server (AdRewardService) plays the video and grants the reroll.
-- Studio test mode (the "Quest reroll" product id is still 0): no AdService call, the button shows and the server
-- grants the reroll without a video.
--
-- Notifications: after the first finished match the server sends NotificationPrompt; back in the Lobby (the vote,
-- never the draft), this asks ExperienceNotificationService:CanPromptOptInAsync and, if Roblox allows it, shows its
-- standard opt-in prompt (PromptOptIn). Every Roblox call is wrapped in pcall.

local AdService = game:GetService("AdService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local SimAds = require(Shared.Sim.Ads)

local Client = script.Parent
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)

local Ads = {}

local available = false
local checking = false
local registered: { [Instance]: boolean } = {}
local listeners: { () -> () } = {}
local promptPending = false

local function set(value: boolean)
	if available == value then
		return
	end
	available = value
	for _, fn in listeners do
		task.spawn(fn)
	end
end

-- Studio, and the reward product not created yet: the whole flow runs without a real video.
function Ads.testMode(): boolean
	return RunService:IsStudio() and Catalogue.productId(SimAds.PRODUCT) == 0
end

-- Did Roblox say a rewarded video can play now (or is this Studio test mode)?
function Ads.available(): boolean
	return available
end

function Ads.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

-- Ask Roblox whether a rewarded video can play now. Call it right before the button could show (Roblox asks for
-- that: it keeps ads out of memory and helps the fill rate). The answer arrives through Ads.onChange.
function Ads.check()
	if checking then
		return
	end
	if Ads.testMode() then
		set(true)
		return
	end
	if Catalogue.productId(SimAds.PRODUCT) == 0 then
		set(false) -- a live server without the product: no ads
		return
	end
	checking = true
	task.spawn(function()
		local ok, result = pcall(function()
			return AdService:GetAdAvailabilityNowAsync(Enum.AdFormat.RewardedVideo)
		end)
		checking = false
		set(ok and type(result) == "table" and result.AdAvailabilityResult == Enum.AdAvailabilityResult.IsAvailable)
	end)
end

-- The button was pressed: one availability answer is good for one ad.
function Ads.watch()
	set(false)
	Intents.watchAd(SimAds.PLACEMENT)
end

-- Let Roblox measure how often the button is on screen (ad opportunity tracking). Live only, once per button.
function Ads.register(button: GuiButton)
	if Ads.testMode() or registered[button] then
		return
	end
	registered[button] = true
	task.spawn(function()
		local ok, err = pcall(function()
			AdService:RegisterAdOpportunityAsync(button)
		end)
		if not ok then
			print("[ads] couldn't register the ad button: " .. tostring(err))
		end
	end)
end

-- Notifications -----------------------------------------------------------------------------------------------

local function prompt()
	local ok, can = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	if ok and can == true then
		local shown = pcall(function()
			ExperienceNotificationService:PromptOptIn()
		end)
		Intents.signal("NotificationPrompt", if shown then "shown" else "ineligible")
	else
		Intents.signal("NotificationPrompt", "ineligible")
	end
end

local function tryPrompt()
	if promptPending and LobbyState.phase() == "Lobby" then
		promptPending = false
		task.delay(Config.Ads.NotificationPromptDelaySeconds, prompt)
	end
end

function Ads.init()
	Remotes.event("NotificationPrompt").OnClientEvent:Connect(function()
		promptPending = true
		tryPrompt()
	end)
	LobbyState.onChange(function()
		tryPrompt()
	end)
end

return Ads
