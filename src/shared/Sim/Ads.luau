--!strict
-- Rewarded video and experience notifications (docs/MONETIZATION.md 3.7, 7.6, 10 "Ads").
--
-- Rewarded video: one placement, on the Quests screen in the Lobby: "Watch an ad: +1 free reroll". Only during the
-- map vote with Config.Ads.MinVoteSecondsLeft to go (never during the draft, a match or the Results screen), at
-- most Config.Progression.Quests.VideoRerolls a day, and only offered when the player has no free reroll left and a
-- daily quest to spend it on. Roblox decides who may see an ad at all (13+,
-- device, region): the client asks AdService before it shows the button. The reward is the "Quest reroll"
-- developer product, granted in ProcessReceipt (channel AdReward) as one more free reroll today.
--
-- Experience notifications: after a player's first finished match (not the tutorial), once per profile, the client
-- shows Roblox's opt-in prompt if Roblox says it may. profile.settings.notificationsAsked remembers it.
-- Pure: the services pass in the profile, VIP, the phase and the day.

local Config = require("../Config")
local Quests = require("./Quests")
local Types = require("../Types")

type Profile = Types.PlayerProfile

local Ads = {}

Ads.PLACEMENT = "quest_reroll" -- the one rewarded video placement (analytics)
Ads.PRODUCT = "quest_reroll" -- its reward: the Catalogue.PRODUCT_IDS key of the "Quest reroll" developer product

-- Can a video start now? voteSecondsLeft: seconds left in the Lobby's map vote, nil outside it (draft, match,
-- Results). The video must end before the draft starts.
function Ads.timeOk(voteSecondsLeft: number?): boolean
	return voteSecondsLeft ~= nil and voteSecondsLeft >= Config.Ads.MinVoteSecondsLeft
end

-- May this player start a rewarded video now? voteSecondsLeft: as in Ads.timeOk; busy: one of their videos is
-- already playing. Returns ok, or false and a reason: AdNotNow, AdBusy, NoAdReward (a free reroll is left, no daily
-- quest can be rerolled, or today's videos are used up).
function Ads.canWatch(profile: Profile, vip: boolean, voteSecondsLeft: number?, busy: boolean): (boolean, string?)
	if not Ads.timeOk(voteSecondsLeft) then
		return false, "AdNotNow"
	end
	if busy then
		return false, "AdBusy"
	end
	if Quests.videoRerollsLeft(profile.quests, vip) <= 0 then
		return false, "NoAdReward"
	end
	return true, nil
end

-- A "Quest reroll" receipt: fromAd = the player watched a rewarded video (ProductPurchaseChannel.AdReward), else
-- they bought it with Robux. Brings the quests up to `today` first, then adds one free reroll for today. Returns
-- false if a video's reroll is over today's cap (nothing changes).
function Ads.grant(profile: Profile, userId: number, today: number, fromAd: boolean): boolean
	Quests.refresh(profile.quests, userId, today)
	if fromAd then
		return Quests.grantVideoReroll(profile.quests)
	end
	Quests.grantBoughtReroll(profile.quests)
	return true
end

-- Inside a match reward: should this player be asked to turn on experience notifications? Only after a finished
-- match (stayed to Results, not AFK) that isn't the tutorial, and only once per profile. Marks the profile asked.
function Ads.takeNotificationPrompt(profile: Profile, reward: Types.MatchReward, tutorial: boolean): boolean
	if tutorial or not reward.stayed or reward.afk or profile.settings.notificationsAsked == true then
		return false
	end
	profile.settings.notificationsAsked = true
	return true
end

return Ads
