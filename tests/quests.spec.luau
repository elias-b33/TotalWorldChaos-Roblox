--!strict
local Config = require("../src/shared/Config")
local Login = require("../src/shared/Sim/Login")
local Progression = require("../src/shared/Sim/Progression")
local Quests = require("../src/shared/Sim/Quests")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")
local Types = require("../src/shared/Types")

local Q = Config.Progression.Quests
local L = Config.Progression.Login
local DAY = 20000 -- a Thursday (UTC day number)
local USER = 4242

local function ids(list: { Types.QuestState }): string
	local out = {}
	for _, q in list do
		table.insert(out, q.id)
	end
	return table.concat(out, ",")
end

local function tierOf(q: Types.QuestState): string
	return (Quests.def(q.id) :: Types.QuestDef).tier
end

local function profileOn(day: number): Types.PlayerProfile
	local p = Progression.newProfile()
	Quests.refresh(p.quests, USER, day)
	return p
end

-- A finished match: stayed to Results, with a nation, this placement.
local function reward(placement: number?, afk: boolean?): Types.MatchReward
	return { xp = 0, glory = 0, lines = {}, placement = placement, stayed = true, afk = afk == true }
end

local function stats(): Types.PlayerMatchStats
	local s = Progression.newStats(USER, 0)
	s.seated = true
	return s
end

-- Make the book's first daily quest be `id` (for tests that need a particular quest).
local function force(p: Types.PlayerProfile, id: string): Types.QuestState
	local q = p.quests.daily[1]
	q.id = id
	q.key = "d" .. q.day .. "-" .. id
	q.progress = 0
	return q
end

-- The pool ----------------------------------------------------------------------------------------------

T.test("the pool: every tier has a few quests, rewards as in MONETIZATION 5.4-5.5, no losing or buying", function()
	local count: { [string]: number } = {}
	for _, def in Q.Pool do
		count[def.tier] = (count[def.tier] or 0) + 1
		T.expect(Quests.def(def.id) ~= nil, def.id)
		T.expect(def.target >= 1, def.id .. " has a target")
		local s = string.lower(def.stat)
		T.expect(not string.find(s, "lose") and not string.find(s, "buy") and not string.find(s, "betray"), def.id)
		T.expect(def.stat ~= "PrimordialPowers", "no quest needs being a Primordial (that needs losing your nation)")
	end
	T.expect(count.Easy >= 3 and count.Medium >= 3 and count.Hard >= 3, "at least 3 a tier, so rerolls have a choice")
	T.expect(count.Weekly >= Q.WeeklyCount + 1, "weekly pool")
	T.equal(Q.Rewards.Easy.glory, 30)
	T.equal(Q.Rewards.Medium.xp, 150)
	T.equal(Q.Rewards.Hard.glory, 50)
	T.equal(Q.Rewards.Weekly.xp, 1000)
	T.equal(Q.Rewards.Weekly.glory, 150)
	-- every stat a quest uses is counted by the tally
	local tally = Quests.tally(stats(), reward(1))
	for _, def in Q.Pool do
		T.expect(tally[def.stat] ~= nil, def.stat .. " is tallied")
	end
end)

-- Generation --------------------------------------------------------------------------------------------

T.test("the same user and day always give the same quests", function()
	local a = Quests.dailyFor(USER, DAY, Quests.rngFor(USER, DAY, 1))
	local b = Quests.dailyFor(USER, DAY, Quests.rngFor(USER, DAY, 1))
	T.equal(ids(a), ids(b))
	T.equal(ids(profileOn(DAY).quests.daily), ids(profileOn(DAY).quests.daily), "refresh too")
	T.equal(ids(profileOn(DAY).quests.weekly), ids(profileOn(DAY).quests.weekly), "and the weekly quests")
end)

T.test("different users and days get different quests", function()
	local seen: { [string]: boolean } = {}
	local distinct = 0
	for d = 0, 29 do
		local key = ids(profileOn(DAY + d).quests.daily)
		if not seen[key] then
			seen[key] = true
			distinct += 1
		end
	end
	T.expect(distinct >= 10, "30 days give at least 10 different sets, got " .. distinct)
	local users: { [string]: boolean } = {}
	local distinctUsers = 0
	for u = 1, 30 do
		local p = Progression.newProfile()
		Quests.refresh(p.quests, u, DAY)
		local key = ids(p.quests.daily)
		if not users[key] then
			users[key] = true
			distinctUsers += 1
		end
	end
	T.expect(distinctUsers >= 10, "neighbouring user ids get unrelated quests, got " .. distinctUsers)
end)

T.test("dailies are 1 easy, 1 medium, 1 hard; weeklies are 3 different weekly quests", function()
	for d = 0, 20 do
		local p = profileOn(DAY + d * 3)
		local daily = p.quests.daily
		T.equal(#daily, 3)
		T.equal(tierOf(daily[1]), "Easy")
		T.equal(tierOf(daily[2]), "Medium")
		T.equal(tierOf(daily[3]), "Hard")
		local weekly = p.quests.weekly
		T.equal(#weekly, Q.WeeklyCount)
		T.expect(weekly[1].id ~= weekly[2].id and weekly[2].id ~= weekly[3].id and weekly[1].id ~= weekly[3].id)
		for _, q in weekly do
			T.equal(tierOf(q), "Weekly")
		end
	end
end)

T.test("weeks start on Monday", function()
	-- day 4 = Monday 5 January 1970; day 3 the Sunday before
	T.equal(Quests.weekOf(3), 0)
	T.equal(Quests.weekOf(4), 1)
	T.equal(Quests.weekOf(10), 1)
	T.equal(Quests.weekOf(11), 2)
end)

-- Progress ----------------------------------------------------------------------------------------------

T.test("a match's stats move the quests; progress caps at the target", function()
	local p = profileOn(DAY)
	local q = force(p, "recruit5")
	local s = stats()
	for _ = 1, 3 do
		Progression.recordCommand(s, 10, { kind = "Recruit", province = 1, regiments = 3, troop = "Archers" }, true)
	end
	Progression.recordCommand(s, 11, { kind = "Recruit", province = 1, regiments = 3, troop = "Infantry" }, false) -- refused
	T.equal(s.regiments, 9)
	local gains = Quests.applyMatch(p.quests, s, reward(4))
	T.equal(q.progress, 5, "capped at 5")
	T.equal(gains[q.key], 5)
	T.expect(Quests.isDone(q))
	-- the weekly "play 10 matches" moved by one
	for _, w in p.quests.weekly do
		if w.id == "w_matches10" then
			T.equal(w.progress, 1)
		end
	end
end)

T.test("max quests count the best single match; sums add up over matches", function()
	local p = profileOn(DAY)
	local hold = force(p, "hold25")
	local s = stats()
	s.mostProvinces = 18
	Quests.applyMatch(p.quests, s, reward(5))
	T.equal(hold.progress, 18)
	local s2 = stats()
	s2.mostProvinces = 12
	Quests.applyMatch(p.quests, s2, reward(5))
	T.equal(hold.progress, 18, "a worse match doesn't add")
	local battles = force(p, "battles3")
	local s3 = stats()
	s3.battlesWon = 2
	Quests.applyMatch(p.quests, s3, reward(5))
	local s4 = stats()
	s4.battlesWon = 2
	Quests.applyMatch(p.quests, s4, reward(5))
	T.equal(battles.progress, 3, "2 + 2, capped at 3")
end)

T.test("AFK counts nothing; leaving and rejoining counts the match once", function()
	local p = profileOn(DAY)
	local q = force(p, "capture10")
	local s = stats()
	s.provincesTaken = 4
	T.expect(next(Quests.applyMatch(p.quests, s, reward(2, true))) == nil, "AFK: no progress")
	T.equal(q.progress, 0)
	-- left with 4 captures, came back and finished with 6
	Quests.applyMatch(p.quests, s, { xp = 0, glory = 0, lines = {}, placement = nil, stayed = false, afk = false })
	T.equal(q.progress, 4)
	s.provincesTaken = 6
	Quests.applyMatch(p.quests, s, reward(2))
	T.equal(q.progress, 6, "4 then 2 more, not 4 + 6")
end)

T.test("placement quests: top 5, top 3 and a win need a nation at Results", function()
	local tally = Quests.tally(stats(), reward(3))
	T.equal(tally.Top5, 1)
	T.equal(tally.Top3, 1)
	T.equal(tally.Wins, 0)
	T.equal(Quests.tally(stats(), reward(1)).Wins, 1)
	local left = Quests.tally(stats(), { xp = 0, glory = 0, lines = {}, placement = 1, stayed = false, afk = false })
	T.equal(left.Wins, 0, "leaving early never counts a place")
	T.equal(left.Matches, 0, "nor a finished match")
	local spectator = Progression.newStats(USER, 0)
	T.equal(Quests.tally(spectator, reward(nil)).Matches, 0, "a spectator didn't play")
end)

T.test("match stats for quests: captures, capitals, alliances, buildings, development, provinces held", function()
	local Maps = require("../src/shared/Maps")
	local Match = require("../src/shared/Sim/Match")
	local state = Match.new(Maps.get("skyshards"))
	Match.seatPlayer(state, USER)
	local me = Match.nationOf(state, USER) :: number
	local s = Progression.newStats(USER, 0)
	local byUser = { [USER] = s }
	local neutral, capital
	for id, p in state.provinces do
		if p.owner == nil and neutral == nil then
			neutral = id
		elseif p.isCapital and p.owner ~= me and capital == nil then
			capital = id
		end
	end
	state.events = {
		{ kind = "ProvinceTaken", a = me, b = 0, province = neutral },
		{ kind = "ProvinceTaken", a = me, b = state.provinces[capital].owner :: number, province = capital },
		{ kind = "AllianceFormed", a = 3, b = me, province = 0 },
	}
	Progression.observe(state, byUser)
	T.equal(s.provincesTaken, 2)
	T.equal(s.neutralTaken, 1)
	T.equal(s.capitalsTaken, 1)
	T.equal(s.alliances, 1, "an alliance counts for both sides")
	T.expect(s.mostProvinces >= 1, "provinces held")
	local home = state.nations[me].capital
	state.provinces[home].development = 4
	Progression.recordCommand(s, 5, { kind = "Develop", province = home }, true, state)
	Progression.recordCommand(s, 6, { kind = "Build", province = home, building = "Farm" }, true, state)
	T.equal(s.developed, 1)
	T.equal(s.bestDevelopment, 4)
	T.equal(s.buildings, 1)
end)

-- Claiming ----------------------------------------------------------------------------------------------

T.test("claiming a finished quest pays its XP and Glory once", function()
	local p = profileOn(DAY)
	local q = force(p, "play1")
	T.equal(select(2, Quests.claim(p, q.key)), "NotDone")
	Quests.applyMatch(p.quests, stats(), reward(6))
	local ok = Quests.claim(p, q.key)
	T.expect(ok)
	T.equal(p.xp, Q.Rewards.Easy.xp)
	T.equal(p.glory, Q.Rewards.Easy.glory)
	T.equal(select(2, Quests.claim(p, q.key)), "Claimed")
	T.equal(p.glory, Q.Rewards.Easy.glory, "paid once")
	T.equal(select(2, Quests.claim(p, "nope")), "Unknown")
end)

T.test("a weekly quest's XP can level the player up (with the level-up Glory)", function()
	local p = profileOn(DAY)
	local w = p.quests.weekly[1]
	w.progress = (Quests.def(w.id) :: Types.QuestDef).target
	T.expect(Quests.claim(p, w.key))
	T.equal(p.xp, 1000)
	T.equal(p.level, Progression.levelFor(1000))
	T.equal(p.glory, 150 + (p.level - 1) * Config.Progression.LevelUpGlory)
end)

-- Expiry ------------------------------------------------------------------------------------------------

T.test("unfinished dailies stay for 2 days, 6 at most; finished ones stay until claimed", function()
	local p = profileOn(DAY)
	local first = table.clone(p.quests.daily)
	first[1].progress = (Quests.def(first[1].id) :: Types.QuestDef).target -- finished, not claimed
	Quests.refresh(p.quests, USER, DAY + 1)
	T.equal(#p.quests.daily, 6, "yesterday's 3 wait next to today's 3")
	Quests.refresh(p.quests, USER, DAY + 2)
	-- day 1's unfinished ones went; its finished one stays; day 2's and day 3's are here
	T.equal(#p.quests.daily, 7)
	T.expect(table.find(p.quests.daily, first[1]) ~= nil, "the finished quest waits to be claimed")
	T.expect(table.find(p.quests.daily, first[2]) == nil, "an unfinished one from 2 days ago is gone")
	T.expect(Quests.claim(p, first[1].key))
	Quests.refresh(p.quests, USER, DAY + 3)
	T.equal(#p.quests.daily, 6, "claimed ones go at the next day")
	-- a long break: only today's
	Quests.refresh(p.quests, USER, DAY + 10)
	T.equal(#p.quests.daily, 3)
end)

T.test("a new week replaces the weekly quests (a finished, unclaimed one stays)", function()
	local p = profileOn(DAY)
	local w = p.quests.weekly
	w[2].progress = (Quests.def(w[2].id) :: Types.QuestDef).target
	local done = w[2]
	Quests.refresh(p.quests, USER, DAY + 1) -- Friday: same week
	T.equal(#p.quests.weekly, 3)
	Quests.refresh(p.quests, USER, DAY + 4) -- Monday
	T.equal(#p.quests.weekly, 4)
	T.expect(table.find(p.quests.weekly, done) ~= nil)
end)

-- Rerolls -----------------------------------------------------------------------------------------------

T.test("reroll: one free a day (+1 VIP), then 100 Glory; same tier, not a quest already in the list", function()
	local p = profileOn(DAY)
	local hard = p.quests.daily[3]
	T.equal(Quests.freeRerolls(p.quests, false), 1)
	T.equal(Quests.freeRerolls(p.quests, true), 1 + Config.Shop.VipQuestRerolls)
	T.expect(Quests.reroll(p, hard.key, false, Quests.rerollRng(p.quests, USER)))
	local new = p.quests.daily[3]
	T.expect(new.id ~= hard.id, "a different quest")
	T.equal(tierOf(new), "Hard")
	T.equal(new.progress, 0)
	T.equal(Quests.freeRerolls(p.quests, false), 0)
	T.equal(select(2, Quests.reroll(p, new.key, false, Rng.new(1))), "NotEnoughGlory")
	p.glory = 150
	T.expect(Quests.reroll(p, new.key, false, Quests.rerollRng(p.quests, USER)))
	T.equal(p.glory, 50, "the second reroll cost 100 Glory")
	-- VIP has one more free one today
	local vipProfile = profileOn(DAY)
	T.expect(Quests.reroll(vipProfile, vipProfile.quests.daily[1].key, true, Rng.new(7)))
	T.expect(Quests.reroll(vipProfile, vipProfile.quests.daily[1].key, true, Rng.new(8)))
	T.equal(vipProfile.glory, 0, "both free with VIP")
	-- a new day resets them
	Quests.refresh(vipProfile.quests, USER, DAY + 1)
	T.equal(Quests.freeRerolls(vipProfile.quests, true), 2)
end)

T.test("reroll refuses finished, claimed and weekly quests; the video hook adds free rerolls", function()
	local p = profileOn(DAY)
	local q = force(p, "play1")
	q.progress = 1
	T.equal(select(2, Quests.reroll(p, q.key, false, Rng.new(1))), "Done")
	T.equal(select(2, Quests.reroll(p, p.quests.weekly[1].key, false, Rng.new(1))), "NotDaily")
	T.equal(p.quests.rerollsUsed, 0, "nothing used")
	T.expect(Quests.grantVideoReroll(p.quests))
	T.expect(Quests.grantVideoReroll(p.quests))
	T.expect(not Quests.grantVideoReroll(p.quests), "2 a day from the video")
	T.equal(Quests.freeRerolls(p.quests, false), 3)
end)

T.test("the view lists the quests with their rewards, rerolls and the calendar", function()
	local p = profileOn(DAY)
	Login.recordPlay(p.login, DAY)
	local view = Quests.view(p, DAY, false, { [p.quests.daily[1].key] = 1 })
	T.equal(#view.daily, 3)
	T.equal(view.daily[1].xp, Q.Rewards.Easy.xp)
	T.equal(view.daily[1].daysLeft, 1)
	T.equal(view.freeRerolls, 1)
	T.equal(view.rerollGlory, Q.RerollGlory)
	T.equal(view.calendar.step, 1)
	T.expect(view.calendar.playedToday)
	T.equal(view.streak, 1)
	T.equal(view.gains[p.quests.daily[1].key], 1)
end)

-- Login calendar and streak -----------------------------------------------------------------------------

T.test("the calendar moves one step per play day and pays 25/25/50/50/75/75/200", function()
	local login = Progression.newProfile().login
	local paid = {}
	for d = 0, 6 do
		table.insert(paid, Login.recordPlay(login, DAY + d))
		T.equal(Login.recordPlay(login, DAY + d), 0, "a second match the same day pays nothing")
	end
	T.equal(table.concat(paid, ","), "25,25,50,50,75,75,200")
	local total = 0
	for _, g in L.CalendarGlory do
		total += g
	end
	T.equal(total, 500, "500 Glory a cycle")
	T.equal(Login.recordPlay(login, DAY + 7), 25, "then a new cycle")
	T.equal(login.step, 1)
end)

T.test("a missed day pauses the calendar, never resets it", function()
	local login = Progression.newProfile().login
	Login.recordPlay(login, DAY)
	Login.recordPlay(login, DAY + 1)
	T.equal(login.step, 2)
	T.equal(Login.recordPlay(login, DAY + 9), 50, "8 days later: step 3")
	T.equal(login.step, 3)
end)

T.test("streak: consecutive play days, one missed day a week covered, a broken streak keeps its flames", function()
	local login = Progression.newProfile().login
	local monday = 20003 -- (20003 + 3) % 7 == 0
	T.equal(Quests.weekOf(monday), Quests.weekOf(monday + 6))
	T.expect(Quests.weekOf(monday - 1) ~= Quests.weekOf(monday), "a Monday")
	Login.recordPlay(login, monday)
	Login.recordPlay(login, monday + 1)
	Login.recordPlay(login, monday + 2)
	T.equal(login.streak, 3)
	T.equal(Login.flameTier(login), 1, "a flame at 3 days")
	-- Thursday missed: covered
	T.equal(Login.currentStreak(login, monday + 4), 3, "still alive on Friday")
	Login.recordPlay(login, monday + 4)
	T.equal(login.streak, 4)
	-- Saturday missed too: the week's cover is used, so Sunday starts over
	T.equal(Login.currentStreak(login, monday + 6), 0, "lapsed")
	Login.recordPlay(login, monday + 6)
	T.equal(login.streak, 1)
	T.equal(login.best, 4)
	T.equal(Login.flameTier(login), 1, "the flame stays earned")
	-- next week a missed day is covered again
	Login.recordPlay(login, monday + 8)
	T.equal(login.streak, 2)
end)

T.test("streak rewards at 3, 7, 14 and 30 days", function()
	T.equal(Login.tierFor(2), 0)
	T.equal(Login.tierFor(3), 1)
	T.equal(Login.tierFor(7), 2)
	T.equal(Login.tierFor(14), 3)
	T.equal(Login.tierFor(30), 4)
	local login = Progression.newProfile().login
	for d = 0, 29 do
		Login.recordPlay(login, DAY + d)
	end
	T.equal(login.streak, 30)
	T.equal(Login.flameTier(login), 4)
end)

T.test("profile migration 2 -> 3 sets up the quest book and calendar", function()
	local p = Progression.newProfile()
	p.version = 2
	p.quests = { day = 0, week = 0, rerollsUsed = 0, daily = {}, weekly = {} } :: any
	p.login = { step = 0, lastPlayDay = 0, streak = 0 } :: any
	Progression.migrate(p)
	T.equal(p.version, Progression.PROFILE_VERSION)
	T.equal(p.login.lastPlayDay, -1)
	T.equal(p.login.best, 0)
	T.equal(p.quests.videoRerolls, 0)
	Quests.refresh(p.quests, USER, DAY)
	T.equal(#p.quests.daily, 3)
end)

T.finish()
