--!strict
-- Rewarded video quest reroll and the notification opt-in (Sim.Ads, Sim.Quests' ad rules).
local Ads = require("../src/shared/Sim/Ads")
local Catalogue = require("../src/shared/Catalogue")
local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Sim/Progression")
local Quests = require("../src/shared/Sim/Quests")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")
local Types = require("../src/shared/Types")

local Q = Config.Progression.Quests
local DAY = 20000
local USER = 4242

local function profileOn(day: number): Types.PlayerProfile
	local p = Progression.newProfile()
	Quests.refresh(p.quests, USER, day)
	return p
end

-- Use up the free reroll(s) on the first daily quest.
local function spendFree(p: Types.PlayerProfile, vip: boolean)
	local n = 0
	while Quests.freeRerolls(p.quests, vip) > 0 do
		n += 1
		T.expect(Quests.reroll(p, p.quests.daily[1].key, vip, Rng.new(n)), "free reroll")
	end
end

local function reward(stayed: boolean, afk: boolean): Types.MatchReward
	return { xp = 0, glory = 0, lines = {}, placement = if stayed then 3 else nil, stayed = stayed, afk = afk }
end

T.test("the reroll product has a catalogue id slot and a price Roblox allows for an ad reward", function()
	T.expect(Catalogue.PRODUCT_IDS[Ads.PRODUCT] ~= nil, "quest_reroll is in PRODUCT_IDS")
	T.equal(Catalogue.productId(Ads.PRODUCT), 0, "0 until the owner creates it (Studio test mode)")
	T.expect(Config.Ads.QuestRerollRobux >= 3 and Config.Ads.QuestRerollRobux <= 10, "worth 3 to 10 Robux")
	T.equal(Catalogue.item(Ads.PRODUCT), nil, "not a shop item")
	T.equal(Catalogue.offer(Ads.PRODUCT), nil, "not a shop offer")
end)

T.test("no video while a free reroll is left", function()
	local p = profileOn(DAY)
	T.equal(Quests.videoRerollsLeft(p.quests, false), 0)
	T.equal(select(2, Ads.canWatch(p, false, 60, false)), "NoAdReward")
	spendFree(p, false)
	T.equal(Quests.videoRerollsLeft(p.quests, false), Q.VideoRerolls)
	T.expect(Ads.canWatch(p, false, 60, false))
	-- VIP has one more free reroll first
	local vip = profileOn(DAY)
	T.expect(Quests.reroll(vip, vip.quests.daily[1].key, true, Rng.new(1)))
	T.equal(Quests.videoRerollsLeft(vip.quests, true), 0, "VIP's second free reroll is still there")
	spendFree(vip, true)
	T.equal(Quests.videoRerollsLeft(vip.quests, true), Q.VideoRerolls)
end)

T.test("only early in the map vote, one at a time", function()
	local p = profileOn(DAY)
	spendFree(p, false)
	T.equal(select(2, Ads.canWatch(p, false, nil, false)), "AdNotNow", "never in the draft, a match or on Results")
	local late = Config.Ads.MinVoteSecondsLeft - 1
	T.equal(select(2, Ads.canWatch(p, false, late, false)), "AdNotNow", "not when it would run into the draft")
	T.expect(Ads.canWatch(p, false, Config.Ads.MinVoteSecondsLeft, false))
	T.expect(Config.Ads.MinVoteSecondsLeft > 30 and Config.Ads.MinVoteSecondsLeft <= Config.Phases.LobbyTicks)
	T.equal(select(2, Ads.canWatch(p, false, 60, true)), "AdBusy")
end)

T.test("no video without a daily quest to reroll", function()
	local p = profileOn(DAY)
	spendFree(p, false)
	for _, q in p.quests.daily do
		q.progress = (Quests.def(q.id) :: Types.QuestDef).target
	end
	T.equal(Quests.videoRerollsLeft(p.quests, false), 0, "every daily quest is finished")
	T.equal(select(2, Ads.canWatch(p, false, 60, false)), "NoAdReward")
end)

T.test("a watched video gives one free reroll, at most VideoRerolls a day", function()
	local p = profileOn(DAY)
	spendFree(p, false)
	for i = 1, Q.VideoRerolls do
		T.expect(Ads.canWatch(p, false, 60, false), "video " .. i .. " offered")
		T.expect(Ads.grant(p, USER, DAY, true), "video " .. i .. " granted")
		T.equal(Quests.freeRerolls(p.quests, false), 1, "one free reroll to spend")
		T.equal(Quests.videoRerollsLeft(p.quests, false), 0, "no second video before it is spent")
		T.equal(Quests.rerollSource(p.quests, false), "ad")
		local glory = p.glory
		T.expect(Quests.reroll(p, p.quests.daily[1].key, false, Rng.new(100 + i)))
		T.equal(p.glory, glory, "the ad's reroll is free")
	end
	T.equal(Quests.videoRerollsLeft(p.quests, false), 0, "today's videos are used up")
	T.equal(select(2, Ads.canWatch(p, false, 60, false)), "NoAdReward")
	T.expect(not Ads.grant(p, USER, DAY, true), "a late reward over the cap gives nothing")
	T.equal(Quests.freeRerolls(p.quests, false), 0)
	T.equal(Quests.rerollSource(p.quests, false), "glory")
	-- the next day: a new free reroll first, then the videos again
	T.expect(Ads.grant(p, USER, DAY + 1, true), "a receipt on a new day refreshes the quests first")
	T.equal(p.quests.day, DAY + 1)
	T.equal(p.quests.videoRerolls, 1)
	T.equal(Quests.freeRerolls(p.quests, false), 2)
end)

T.test("a bought reroll (Robux, store page) is one more free reroll outside the video cap", function()
	local p = profileOn(DAY)
	spendFree(p, false)
	T.expect(Ads.grant(p, USER, DAY, false))
	T.equal(Quests.freeRerolls(p.quests, false), 1)
	T.equal(p.quests.videoRerolls, 0, "doesn't use up a video")
	T.equal(Quests.rerollSource(p.quests, false), "free")
	T.expect(Quests.reroll(p, p.quests.daily[2].key, false, Rng.new(9)))
	T.equal(Quests.videoRerollsLeft(p.quests, false), Q.VideoRerolls)
end)

T.test("reroll sources in order: free, vip, ad, glory", function()
	local p = profileOn(DAY)
	T.equal(Quests.rerollSource(p.quests, true), "free")
	T.expect(Quests.reroll(p, p.quests.daily[1].key, true, Rng.new(1)))
	T.equal(Quests.rerollSource(p.quests, true), "vip")
	T.expect(Quests.reroll(p, p.quests.daily[1].key, true, Rng.new(2)))
	T.equal(Quests.rerollSource(p.quests, true), "glory")
	T.expect(Quests.grantVideoReroll(p.quests))
	T.equal(Quests.rerollSource(p.quests, true), "ad")
end)

T.test("the quest view carries the videos on offer", function()
	local p = profileOn(DAY)
	T.equal(Quests.view(p, DAY, false).videoRerolls, 0)
	spendFree(p, false)
	T.equal(Quests.view(p, DAY, false).videoRerolls, Q.VideoRerolls)
end)

T.test("the notification prompt comes once, after the first finished match that isn't the tutorial", function()
	local p = Progression.newProfile()
	T.expect(not Ads.takeNotificationPrompt(p, reward(true, false), true), "not after the tutorial match")
	T.expect(not Ads.takeNotificationPrompt(p, reward(false, false), false), "not after leaving early")
	T.expect(not Ads.takeNotificationPrompt(p, reward(true, true), false), "not after an AFK match")
	T.equal(p.settings.notificationsAsked, nil, "still not asked")
	T.expect(Ads.takeNotificationPrompt(p, reward(true, false), false), "after the first finished match")
	T.equal(p.settings.notificationsAsked, true, "remembered in the profile")
	T.expect(not Ads.takeNotificationPrompt(p, reward(true, false), false), "never again")
end)

T.finish()
