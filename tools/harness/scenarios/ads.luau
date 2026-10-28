--!nocheck
-- Phase 5: the rewarded-video quest reroll and the experience notification prompt. Studio test mode first (the
-- product id is 0: no video, the reward straight away), then a "live" product id where the emulated AdService
-- answers (Emulator.adAvailability, Emulator.adResult) and the reward arrives through ProcessReceipt with channel
-- AdReward. The button only shows in the map vote, after the free reroll, while an ad is available, at most 2 a day.
-- Then Alice's first finished match: back in the Lobby she is asked once to turn on notifications.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local shown = H.shown

local function run()
	local LobbyService = H.server("Services.LobbyService")
	local Data = H.server("Services.PlayerDataService")
	local log = Emulator.analytics
	local function customs(name: string, userId: number): { string }
		local out = {}
		local keys = Emulator.roblox.Enum.AnalyticsCustomFieldKeys
		for _, r in log do
			if r.method == "LogCustomEvent" and r.userId == userId and r.args[1] == name then
				local f = r.args[#r.args] or {}
				table.insert(out, table.concat({ f[keys.CustomField01.Name] or "", f[keys.CustomField02.Name] or "" }, ","))
			end
		end
		return out
	end
	local pressIn = H.pressIn
	local function adShown(client): boolean
		return Emulator.findText(client, "Watch an ad") ~= nil
	end
	local function reopen(client)
		Emulator.press(client, "✕")
		Emulator.run(0.3)
		Emulator.press(client, "QuestsButton")
		Emulator.run(0.5)
	end
	local function setProductId(client, id: number)
		local serverShared = Emulator.server.dm:GetService("ReplicatedStorage").Shared
		Emulator.server.modules[serverShared.Catalogue].PRODUCT_IDS.quest_reroll = id
		local clientShared = client.dm:GetService("ReplicatedStorage").Shared
		client.modules[clientShared.Catalogue].PRODUCT_IDS.quest_reroll = id
	end
	-- run a yielding emulator call (ProcessReceipt) in its own thread while the game runs
	local function await(fn, ...)
		local args = table.pack(...)
		local result
		Emulator.task.spawn(function()
			result = table.pack(fn(table.unpack(args, 1, args.n)))
		end)
		local deadline = Emulator.now() + 10
		while result == nil and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		assert(result, "timed out")
		return table.unpack(result, 1, result.n)
	end
	-- a daily quest that can still be rerolled
	local function openDaily(d)
		for _, q in d.quests.daily do
			if not q.claimed and q.progress == 0 then
				return q.id
			end
		end
		error("no daily quest left to reroll")
	end

	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(3)
	local player = alice.serverPlayer
	local uid = player.UserId
	local data = Data.data(player)
	local QuestState = H.client(alice, "QuestState")
	H.expect(LobbyService.active(), "the Lobby is open")

	-- a free reroll is left: no ad
	Emulator.press(alice, "QuestsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "1 free reroll today") ~= nil, "the Quests screen opens with a free reroll")
	H.expect(not adShown(alice), "no ad while the free reroll is left")
	H.shot(alice, "free_reroll_first")

	-- Studio test mode (product id 0): after the free reroll the button shows, without asking AdService
	pressIn(alice, "Quest_" .. openDaily(data), "Free", "reroll")
	Emulator.run(1)
	H.expect(QuestState.view().videoRerolls == 2, "2 ad rerolls on offer today")
	H.expect(adShown(alice) and Emulator.findText(alice, "(test)") ~= nil, "the ad button shows (Studio test mode)")
	H.expect(Emulator.findText(alice, "2 left today") ~= nil, "with today's count")
	H.expect(Emulator.adCallCount("GetAdAvailabilityNowAsync") == 0, "test mode never calls AdService")
	H.shot(alice, "ad_button_test_mode")
	Emulator.press(alice, "Watch an ad")
	Emulator.run(1)
	H.expect(data.quests.videoRerolls == 1 and QuestState.view().freeRerolls == 1, "the ad gave one free reroll")
	H.expect(not adShown(alice), "no second ad before it is spent")
	H.expect(#data.purchaseHistory == 0, "an ad reward isn't a Robux purchase: not in the purchase history")
	H.expect(table.concat(customs("ad_rewarded", uid), "|") == "quest_reroll,completed", "ad_rewarded: completed")
	H.shot(alice, "ad_reward_test_mode")
	pressIn(alice, "Quest_" .. openDaily(data), "Free", "reroll")
	Emulator.run(1)
	H.expect(table.find(customs("quest_rerolled", uid), "ad,") ~= nil, "quest_rerolled: source ad")
	H.expect(table.find(customs("quest_rerolled", uid), "free,") ~= nil, "quest_rerolled: source free")
	H.expect(adShown(alice) and Emulator.findText(alice, "1 left today") ~= nil, "the second ad of the day is on offer")

	-- a live product id: AdService decides. Under 13 (PlayerIneligible) or no fill: no button
	setProductId(alice, 777)
	Emulator.adAvailability = "PlayerIneligible"
	reopen(alice)
	H.expect(Emulator.adCallCount("GetAdAvailabilityNowAsync", uid) == 1, "opening the screen asks AdService")
	H.expect(not adShown(alice), "an ineligible player (under 13) never sees the button")
	H.shot(alice, "ineligible_no_button")
	Emulator.adAvailability = "NoFill"
	reopen(alice)
	H.expect(not adShown(alice), "no ad to fill: no button")

	-- an ad is available: the button shows and is registered for ad opportunity tracking
	Emulator.adAvailability = "IsAvailable"
	reopen(alice)
	H.expect(adShown(alice) and Emulator.findText(alice, "(test)") == nil, "an available ad shows the button")
	H.expect(Emulator.adCallCount("RegisterAdOpportunityAsync", uid) == 1, "the button is registered as an ad opportunity")
	H.shot(alice, "ad_button_live")

	-- closed early: no reward
	Emulator.adResult = "ShowInterrupted"
	Emulator.press(alice, "Watch an ad")
	Emulator.run(0.2)
	H.expect(not adShown(alice), "the button hides while the ad plays (one answer, one ad)")
	Emulator.run(1.5)
	H.expect(Emulator.adCallCount("ShowRewardedVideoAdAsync") == 1, "the server played the video")
	H.expect(data.quests.videoRerolls == 1 and QuestState.view().freeRerolls == 0, "an interrupted ad gives nothing")
	H.expect(table.find(customs("ad_rewarded", uid), "quest_reroll,failed") ~= nil, "ad_rewarded: failed")
	H.expect(Emulator.findText(alice, "didn't play to the end") ~= nil, "the player is told")
	H.expect(adShown(alice), "Roblox is asked again and the button comes back")
	H.shot(alice, "ad_interrupted")

	-- watched to the end: the reward arrives through ProcessReceipt (channel AdReward)
	Emulator.adResult = "ShowCompleted"
	Emulator.press(alice, "Watch an ad")
	Emulator.run(2)
	H.expect(data.quests.videoRerolls == 2 and QuestState.view().freeRerolls == 1, "the ad's receipt gave a free reroll")
	H.expect(#data.purchaseHistory == 0, "still nothing in the purchase history")
	pressIn(alice, "Quest_" .. openDaily(data), "Free", "reroll")
	Emulator.run(1)
	H.expect(QuestState.view().videoRerolls == 0 and not adShown(alice), "2 ads a day: the button is gone")
	H.expect(Emulator.findText(alice, "Rerolls: 100") ~= nil, "the next reroll costs Glory")
	H.shot(alice, "ads_used_up")

	-- a forged request is refused by the server
	local shows = Emulator.adCallCount("ShowRewardedVideoAdAsync")
	H.client(alice, "Intents").watchAd("quest_reroll")
	Emulator.run(1)
	H.expect(Emulator.adCallCount("ShowRewardedVideoAdAsync") == shows, "a third ad today is refused")
	H.expect(Emulator.findText(alice, "No ad reroll to earn") ~= nil, "with a reason")

	-- the same product bought with Robux on the experience's store page: one more free reroll, in the history
	local decision = await(Emulator.processReceipt, {
		PurchaseId = "store-1",
		PlayerId = uid,
		ProductId = 777,
		CurrencySpent = 10,
		ProductPurchaseChannel = Emulator.roblox.Enum.ProductPurchaseChannel.ExperienceDetailsPage,
	})
	Emulator.run(0.5)
	H.expect(decision == Emulator.roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "a Robux receipt is granted")
	H.expect(QuestState.view().freeRerolls == 1 and data.quests.videoRerolls == 2, "a bought reroll is free and outside the cap")
	H.expect(#data.purchaseHistory == 1 and data.purchaseHistory[1].robux == 10, "and listed in the purchase history")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)
	H.client(alice, "UI.Shop").open("History") -- the receipt resent the shop view: the history is up to date
	Emulator.run(0.5)
	H.expect(
		Emulator.findText(alice, "Quest reroll") ~= nil and Emulator.findText(alice, "quest_reroll") == nil,
		"the shop's purchase history names it, not its product id"
	)
	H.client(alice, "UI.Shop").close()
	Emulator.run(0.3)

	-- the match: no ad button there, and the server refuses a request
	Emulator.canPromptOptIn = true
	local deadline = Emulator.now() + 200
	while (LobbyService.active() or H.state().phase ~= "Peace" or H.myNation(alice) == 0) and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(H.state().phase == "Peace" and H.myNation(alice) ~= 0, "the match started with Alice in it")
	Emulator.server.dm:GetService("Workspace"):SetAttribute("DevDay", 1) -- a new day: a free reroll and 2 ads again
	Emulator.run(7)
	H.expect(QuestState.view().freeRerolls == 1, "a new day")
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.3)
	Emulator.press(alice, "📜 Quests")
	Emulator.run(0.5)
	pressIn(alice, "Quest_" .. openDaily(data), "Free", "reroll")
	Emulator.run(1)
	H.expect(QuestState.view().videoRerolls == 2, "the rules would offer an ad")
	H.expect(not adShown(alice), "but never during a match")
	H.client(alice, "Intents").watchAd("quest_reroll")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "Ads only play early in the map vote") ~= nil, "and the server refuses one")
	H.expect(Emulator.adCallCount("ShowRewardedVideoAdAsync") == shows, "no video played")
	H.shot(alice, "match_no_ad")
	Emulator.press(alice, "✕")
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.3)

	-- Alice's first finished match: hand her half the land, Results
	local state = H.state()
	local A = H.myNation(alice)
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" and not p.isCapital then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(3)
	H.expect(state.result ~= nil and H.client(alice, "ProfileState").reward() ~= nil, "Alice finished her first match")
	H.expect(data.settings.notificationsAsked == true, "the server marks her asked")
	H.expect(Emulator.adCallCount("PromptOptIn") == 0, "no prompt over the Results screen")
	Emulator.press(alice, "Quests")
	Emulator.run(0.5)
	H.expect(not adShown(alice), "no ad on the Results screen either")
	H.shot(alice, "results_no_ad_no_prompt")
	Emulator.press(alice, "✕")

	-- back in the Lobby: Roblox is asked whether she may be prompted, then its opt-in prompt opens, once
	deadline = Emulator.now() + 60
	while not LobbyService.active() and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(LobbyService.active(), "the next Lobby opens")
	Emulator.run(Config.Ads.NotificationPromptDelaySeconds + 1)
	H.expect(Emulator.adCallCount("CanPromptOptInAsync", uid) == 1, "CanPromptOptInAsync first")
	H.expect(Emulator.adCallCount("PromptOptIn", uid) == 1, "then Roblox's opt-in prompt")
	H.expect(table.concat(customs("notification_opt_in", uid), "|") == "shown,", "notification_opt_in: shown")
	-- the Lobby again: the ads are back (a free reroll was spent in the match, an ad is available)
	Emulator.press(alice, "QuestsButton")
	Emulator.run(0.5)
	H.expect(adShown(alice) and Emulator.findText(alice, "2 left today") ~= nil, "back in the Lobby the ad is on offer again")
	H.shot(alice, "lobby_again")
	local saved = H.saved(uid).Data
	H.expect(saved.settings.notificationsAsked == true, "asked once per profile: saved")
end

return {
	lobby = true, -- the rewarded video only plays in the Lobby
	run = run,
}
