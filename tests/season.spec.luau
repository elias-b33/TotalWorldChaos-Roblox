--!strict
-- The season pass (docs/MONETIZATION.md 6, Sim.Season): tier math, claims (never twice), the premium track, buying
-- the pass late, the bundle's tiers (once), bonus rewards past the last tier, season XP from account XP, the end of a
-- season, and Season 1's reward list.
local Catalogue = require("../src/shared/Catalogue")
local Config = require("../src/shared/Config")
local Progression = require("../src/shared/Sim/Progression")
local Season = require("../src/shared/Sim/Season")
local T = require("./TestKit")

local C = Config.Season
local S1 = assert(Season.def("S1"))
local DAY = S1.startDay + 3 -- a day in Season 1

local function profileIn(def): any
	local p = Progression.newProfile()
	Season.sync(p, def)
	return p
end

T.test("8-week seasons of 50 tiers at 1,200 XP each (60,000 XP)", function()
	for _, def in Season.DEFS do
		T.equal(def.endDay - def.startDay, 56, def.id .. " lasts 8 weeks")
		T.equal(#def.tiers, C.Tiers, def.id .. " has 50 tiers")
	end
	T.equal(C.Tiers * C.XpPerTier, 60000)
end)

T.test("the current season is chosen by the day", function()
	T.equal(Season.current(S1.startDay), S1, "its first day")
	T.equal(Season.current(S1.endDay - 1), S1, "its last day")
	T.equal(Season.current(S1.startDay - 1), nil, "the day before")
	T.equal(Season.current(S1.endDay), nil, "the day it ends")
	T.equal(Season.nextAfter(S1.startDay - 10), S1, "the next season")
end)

T.test("tier math: tier 1 at 0 XP, one tier per 1,200 XP, capped at 50", function()
	T.equal(Season.tierFor(0), 1)
	T.equal(Season.tierFor(1199), 1)
	T.equal(Season.tierFor(1200), 2)
	T.equal(Season.tierFor(2 * 1200), 3)
	T.equal(Season.tierFor(49 * 1200), 50)
	T.equal(Season.tierFor(10 ^ 6), 50)
end)

T.test("season XP is the account XP earned during the season", function()
	local p = profileIn(S1)
	Progression.addXp(p, 1300, 0)
	T.equal(p.season.xp, 1300)
	T.equal(Season.tierOf(p.season), 2)
	T.equal(p.xp, 1300, "account XP too")
end)

T.test("claims: free tiers up to your tier, never twice, Glory and items granted", function()
	local p = profileIn(S1)
	p.season.xp = 2 * C.XpPerTier -- tier 3
	local ok, reason, glory = Season.claim(p, S1, 1, "Free")
	T.expect(ok, "tier 1 free")
	T.equal(glory, 0)
	T.equal(p.owned.emote_gg, true, "the GG emote")
	ok, reason = Season.claim(p, S1, 1, "Free")
	T.equal(ok, false)
	T.equal(reason, "Claimed", "never twice")
	local before = p.glory
	ok, _, glory = Season.claim(p, S1, 3, "Free")
	T.expect(ok, "tier 3 free")
	T.equal(glory, 100)
	T.equal(p.glory, before + 100, "100 Glory")
	ok, reason = Season.claim(p, S1, 5, "Free")
	T.equal(reason, "TierLocked", "tier 5 is not reached yet")
	ok, reason = Season.claim(p, S1, 2, "Free")
	T.equal(reason, "Unknown", "nothing on tier 2's free track")
	ok, reason = Season.claim(p, S1, 1, "Premium")
	T.equal(reason, "NeedPass", "the premium track needs the pass")
	ok, reason = Season.claim(p, S1, 99, "Free")
	T.equal(reason, "Unknown")
	ok, reason = Season.claim(p, nil, 1, "Free")
	T.equal(reason, "NoSeason")
end)

T.test("buying the pass late opens every premium reward up to your tier at once", function()
	local p = profileIn(S1)
	p.season.xp = 11 * C.XpPerTier -- tier 12
	T.equal(#Season.claimable(p.season, S1), 5, "without the pass: free tiers 1, 3, 5, 8 and 10")
	T.expect(Season.canBuyPass(p, S1), "the pass is on sale")
	Season.buyPass(p, false)
	local premium = 0
	for _, c in Season.claimable(p.season, S1) do
		if c.track == "Premium" then
			premium += 1
		end
	end
	T.equal(premium, 12, "premium tiers 1-12 are all claimable")
	local ok, reason = Season.canBuyPass(p, S1)
	T.equal(ok, false)
	T.equal(reason, "Owned", "one pass per season: no tier skips to buy")
	local count, glory = Season.claimAll(p, S1)
	T.equal(count, 12 + 5, "claim all: 12 premium and 5 free rewards")
	T.equal(glory, 100 + 100 + 100 + 100 + 100, "premium 2, 6, 11 and free 3, 8")
	T.equal(p.owned.token_ember_knight, true, "the Ember Knight token")
	T.equal(#Season.claimable(p.season, S1), 0, "nothing left")
end)

T.test("the bundle adds 10 tiers, once", function()
	local p = profileIn(S1)
	p.season.xp = 1500 -- tier 2
	Season.buyPass(p, true)
	T.equal(Season.tierOf(p.season), 12, "tier 2 + 10")
	Season.buyPass(p, true) -- a repeated receipt can't stack it
	T.equal(Season.tierOf(p.season), 12, "still 12")
	T.equal(Season.canBuyPass(p, S1), false, "and neither the pass nor the bundle can be bought again")
	local q = profileIn(S1)
	q.season.xp = 49 * C.XpPerTier
	Season.buyPass(q, true)
	T.equal(Season.tierOf(q.season), 50, "never past the last tier")
end)

T.test("past the last tier: 100 Glory per 2,400 XP, repeatable", function()
	local p = profileIn(S1)
	p.season.xp = C.Tiers * C.XpPerTier + 2 * C.BonusXp + 100
	T.equal(Season.bonusEarned(p.season), 2)
	local glory = Season.claimBonus(p)
	T.equal(glory, 2 * C.BonusGlory)
	T.equal(Season.claimBonus(p), 0, "paid once")
	p.season.xp += C.BonusXp
	T.equal(Season.claimBonus(p), C.BonusGlory, "and again for the next 2,400 XP")
	local v = Season.view(p, S1, DAY)
	T.equal(v.tier, 50)
	T.equal(v.xpForTier, C.BonusXp, "the bar counts to the next bonus reward")
	T.equal(v.xpIntoTier, 100)
end)

T.test("the view: tier, progress, days left, ready count", function()
	local p = profileIn(S1)
	p.season.xp = 2 * C.XpPerTier + 300
	local v = Season.view(p, S1, S1.startDay)
	T.equal(v.id, "S1")
	T.equal(v.tier, 3)
	T.equal(v.xpIntoTier, 300)
	T.equal(v.xpForTier, C.XpPerTier)
	T.equal(v.daysLeft, 55)
	T.equal(v.ready, 2, "free tiers 1 and 3")
	Season.claim(p, S1, 1, "Free")
	T.equal(Season.view(p, S1, DAY).claimed[1], "F1")
	local between = Season.view(Progression.newProfile(), nil, S1.startDay - 5)
	T.equal(between.id, "")
	T.equal(between.nextStartDay, S1.startDay, "between seasons: when the next one starts")
end)

T.test("a new season: unclaimed rewards of the last one are granted, then everything starts over", function()
	local p = profileIn(S1)
	p.season.xp = 4 * C.XpPerTier -- tier 5
	Season.buyPass(p, false)
	local changed = Season.sync(p, S1)
	T.equal(changed, false, "same season: nothing changes")
	local glory0 = p.glory
	local moved, count, glory = Season.sync(p, nil)
	T.expect(moved, "the season ended")
	T.equal(count, 3 + 5, "free 1, 3, 5 and premium 1-5 granted")
	T.equal(glory, 100 + 100, "free tier 3 and premium tier 2")
	T.equal(p.glory, glory0 + 200)
	T.equal(p.owned.flag_ember_sigil, true, "the free tier-5 flag")
	T.equal(p.season.id, "")
	T.equal(p.season.xp, 0)
	T.equal(p.season.premium, false, "a pass is for one season")
	T.equal(Season.needsSync(p, nil), false)
	T.equal(Season.needsSync(p, S1), true)
end)

T.test("a pass whose purchase finishes after its season ended, with none running, is the next season's", function()
	-- the prompt opened on Season 1's last day; at midnight the season ended (no next one yet) and the profile moved on
	local p = profileIn(S1)
	p.season.xp = 4 * C.XpPerTier
	Season.sync(p, nil)
	T.equal(p.season.id, "")
	-- then the receipt: SeasonService grants the pass with no season running
	Season.buyPass(p, true)
	local S2 = { id = "S2", name = "Next", startDay = S1.endDay + 7, endDay = S1.endDay + 63, tiers = S1.tiers }
	Season.sync(p, S2)
	T.equal(p.season.id, "S2")
	T.expect(p.season.premium and p.season.bundle, "paid for: the pass and the bundle's tiers are the next season's")
	-- a pass bought during a season stays that season's
	local q = profileIn(S1)
	Season.buyPass(q, false)
	Season.sync(q, nil)
	Season.sync(q, S2)
	T.equal(q.season.premium, false, "a pass is for one season")
end)

T.test("an older save without the new season fields is filled in", function()
	local p = Progression.newProfile()
	p.season = { id = "S1", xp = 1200, premium = true, claimed = {} } :: any
	T.expect(Season.needsSync(p, S1), "needs filling in")
	Season.sync(p, S1)
	T.equal(p.season.bundle, false)
	T.equal(p.season.bonus, 0)
	T.equal(p.season.xp, 1200, "kept its XP")
	T.equal(p.season.premium, true, "and its pass")
end)

T.test("Season 1: 10 free and 40 premium cosmetics, a title on each track, 2,500 and 2,250 Glory", function()
	local counts = { Free = { items = 0, glory = 0, titles = 0 }, Premium = { items = 0, glory = 0, titles = 0 } }
	for tier = 1, C.Tiers do
		for _, track in Season.TRACKS do
			for _, r in Season.rewards(S1, tier, track) do
				local c = (counts :: any)[track]
				if r.item then
					local item = Catalogue.item(r.item)
					T.expect(item ~= nil, r.item .. " is in the catalogue")
					c.items += 1
				end
				c.glory += r.glory or 0
				c.titles += if r.title then 1 else 0
			end
		end
	end
	T.equal(counts.Free.items, 10)
	T.equal(counts.Premium.items, 40)
	T.equal(counts.Free.glory, 2500)
	T.equal(counts.Premium.glory, 2250)
	T.equal(counts.Free.titles, 1)
	T.equal(counts.Premium.titles, 1)
	T.equal(Season.rewards(S1, 1, "Premium")[1].item, "token_ember_knight", "the Ember Knight on tier 1")
end)

T.test("season items are never sold", function()
	for _, item in Catalogue.ITEMS do
		if item.season then
			T.equal(item.robux, nil, item.id .. " has no Robux price")
			T.equal(item.glory, nil, item.id .. " has no Glory price")
		end
	end
	T.expect(Catalogue.PRODUCT_IDS.season_pass ~= nil and Catalogue.PRODUCT_IDS.season_bundle ~= nil, "pass products")
end)

T.test("a season title is also given as a wearable title", function()
	local p = profileIn(S1)
	for _, track in Season.TRACKS do
		for _, r in Season.rewards(S1, C.Tiers, track) do
			if r.title then
				Season.grant(p, r)
				local wearable = Catalogue.titleNamed(r.title)
				T.expect(wearable ~= nil, r.title .. " is a catalogue title")
				T.expect(p.owned[wearable :: string] == true, r.title .. " can be worn")
			end
		end
	end
	T.expect(p.owned.title_s1_veteran and p.owned.title_primordial_herald, "both tier-50 titles")
end)

T.finish()
