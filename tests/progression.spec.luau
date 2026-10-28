--!strict
local Config = require("../src/shared/Config")
local Events = require("../src/shared/Sim/Events")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Progression = require("../src/shared/Sim/Progression")
local T = require("./TestKit")
local Types = require("../src/shared/Types")

local P = Config.Progression
local STANDARD = { vip = false, firstMatchToday = false, standardRules = true }
local END = Config.Phases.MatchEndTick

-- A finished match: user 101 plays nation 1, user 102 nation 2; scores and winners as given.
local function finished(winners: { number }, scores: { { nation: number, score: number } }): Types.MatchState
	local state = Match.new(Maps.get("skyshards"))
	Match.seatPlayer(state, 101)
	Match.seatPlayer(state, 102)
	state.tick = END
	state.phase = "Results"
	state.result = { kind = "Score", winners = winners, scores = scores, endedAt = END }
	return state
end

local function scoresFor(list: { number }): { { nation: number, score: number } }
	local out = {}
	for i, score in list do
		table.insert(out, { nation = i, score = score })
	end
	table.sort(out, function(a, b)
		return a.score > b.score
	end)
	return out
end

-- Stats for a whole match with a command every 100 ticks (never AFK).
local function busy(userId: number, joinedAt: number?, untilTick: number?): Types.PlayerMatchStats
	local from = joinedAt or 0
	local stats = Progression.newStats(userId, from)
	for t = from, untilTick or END, 100 do
		Progression.recordCommand(stats, t, { kind = "Develop", province = 1 }, true)
	end
	return stats
end

local function line(reward: Types.MatchReward, kind: string): Types.RewardLine?
	for _, l in reward.lines do
		if l.kind == kind then
			return l
		end
	end
	return nil
end

-- Level curve and ranks -----------------------------------------------------------------------------------

T.test("the level curve is 300 + 60 x (level - 1) and level 100 needs 320,760 XP", function()
	T.equal(Progression.xpToNext(1), 300)
	T.equal(Progression.xpToNext(2), 360)
	T.equal(Progression.xpToNext(99), 6180)
	T.equal(Progression.xpToNext(100), 0, "no next level at the cap")
	T.equal(Progression.totalXpFor(1), 0)
	T.equal(Progression.totalXpFor(2), 300)
	T.equal(Progression.totalXpFor(26), 25500)
	T.equal(Progression.totalXpFor(51), 88500)
	T.equal(Progression.totalXpFor(76), 189000)
	T.equal(Progression.totalXpFor(100), 320760)
end)

T.test("levels come from total XP and stop at 100", function()
	T.equal(Progression.levelFor(0), 1)
	T.equal(Progression.levelFor(299), 1)
	T.equal(Progression.levelFor(300), 2)
	T.equal(Progression.levelFor(659), 2)
	T.equal(Progression.levelFor(660), 3)
	T.equal(Progression.levelFor(320759), 99)
	T.equal(Progression.levelFor(320760), 100)
	T.equal(Progression.levelFor(10 ^ 9), 100)
end)

T.test("one rank per 10 levels, Primordial at 100", function()
	local function name(level: number): string
		local _, n = Progression.rankFor(level)
		return n
	end
	T.equal(name(1), "Settler")
	T.equal(name(9), "Settler")
	T.equal(name(10), "Chieftain")
	T.equal(name(59), "Prince")
	T.equal(name(99), "World Shaker")
	T.equal(name(100), "Primordial")
	T.equal((Progression.rankFor(100)), #P.Ranks)
end)

-- Placement -----------------------------------------------------------------------------------------------

T.test("winners are 1st, the rest follow by score, ties share a place", function()
	-- a tie for first: both win
	local tie = { kind = "Score", winners = { 1, 2 }, scores = scoresFor({ 100, 100, 50 }), endedAt = END }
	T.equal(Progression.placement(tie :: any, 1), 1)
	T.equal(Progression.placement(tie :: any, 2), 1)
	T.equal(Progression.placement(tie :: any, 3), 3)
	-- a tie further down
	local r = { kind = "Domination", winners = { 4 }, scores = scoresFor({ 50, 50, 20, 90 }), endedAt = 600 }
	T.equal(Progression.placement(r :: any, 4), 1)
	T.equal(Progression.placement(r :: any, 1), 2)
	T.equal(Progression.placement(r :: any, 2), 2)
	T.equal(Progression.placement(r :: any, 3), 4)
end)

T.test("an alliance victory makes every member 1st, even with a lower score", function()
	local r = { kind = "Alliance", winners = { 1, 2 }, scores = scoresFor({ 300, 100, 200 }), endedAt = 900 }
	T.equal(Progression.placement(r :: any, 2), 1)
	T.equal(Progression.placement(r :: any, 3), 3)
end)

-- Rewards -------------------------------------------------------------------------------------------------

T.test("a winner who played the whole match", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = busy(101)
	stats.provincesTaken, stats.battlesWon = 3, 2
	local r = Progression.matchReward(state, stats, STANDARD)
	T.equal(r.placement, 1)
	T.expect(r.stayed and not r.afk)
	T.equal(r.xp, 100 + 150 + 15 + 10)
	T.equal(r.glory, 20 + 40 + 3 + 2)
	T.equal((line(r, "Placement") :: Types.RewardLine).xp, 150)
	T.equal(line(r, "Primordial"), nil)
end)

T.test("the average match pays about 245 XP and 49 Glory", function()
	local xp, glory = 0, 0
	for place = 1, 10 do
		-- finishing order: nations 2..10 with nation 1 slotted in at `place`
		local order = { 2, 3, 4, 5, 6, 7, 8, 9, 10 }
		table.insert(order, place, 1)
		local scores = {}
		for i, n in order do
			scores[n] = 1000 - i
		end
		local state = finished({ order[1] }, scoresFor(scores))
		T.equal(Progression.placement(state.result :: any, 1), place, "setup")
		local stats = busy(101)
		stats.provincesTaken, stats.battlesWon = 8, 5
		if place % 2 == 0 then
			state.primordials[101] = { userId = 101, charges = 0, chargeTicks = 0 } -- rose as a Primordial in half the matches
		end
		local r = Progression.matchReward(state, stats, STANDARD)
		xp += r.xp
		stats.provincesTaken, stats.battlesWon = 4, 4 -- the doc's average activity Glory is 8
		glory += Progression.matchReward(state, stats, STANDARD).glory
	end
	T.equal(xp / 10, 245)
	T.near(glory / 10, 49, 2)
end)

T.test("caps hold for provinces, battles, powers and activity Glory", function()
	local state = finished({ 2 }, scoresFor({ 100, 300 }))
	local stats = busy(101)
	stats.provincesTaken, stats.battlesWon, stats.powersUsed = 40, 30, 9
	local r = Progression.matchReward(state, stats, STANDARD)
	local provinces = line(r, "Provinces") :: Types.RewardLine
	local battles = line(r, "Battles") :: Types.RewardLine
	T.equal(provinces.xp, P.MaxProvinceXp)
	T.equal(battles.xp, P.MaxBattleXp)
	T.equal((line(r, "Powers") :: Types.RewardLine).xp, P.MaxPowerXp)
	T.equal(provinces.glory + battles.glory, P.MaxActivityGlory)
end)

T.test("leaving early prorates the finish reward and pays no placement or Primordial bonus", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	state.primordials[101] = { userId = 101, charges = 0, chargeTicks = 0 }
	local stats = busy(101, 0, 700)
	stats.provincesTaken = 2
	Progression.leave(stats, 720)
	local r = Progression.matchReward(state, stats, { vip = false, firstMatchToday = true, standardRules = true })
	T.expect(not r.stayed and not r.afk)
	T.equal(r.placement, nil)
	T.equal((line(r, "Finish") :: Types.RewardLine).xp, math.floor(100 * 720 / (END - 60) + 0.5))
	T.equal(line(r, "Placement"), nil)
	T.equal(line(r, "Primordial"), nil)
	T.equal(line(r, "FirstMatch"), nil, "the first-match bonus needs a finished match")
	T.equal((line(r, "Provinces") :: Types.RewardLine).xp, 10, "what they did still counts")
end)

T.test("a player who joined late gets the share of the match they played", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local late = busy(101, 1200)
	local r = Progression.matchReward(state, late, STANDARD)
	local share = 300 / (END - P.LateJoinGraceTicks)
	T.equal((line(r, "Finish") :: Types.RewardLine).xp, math.floor(100 * share + 0.5))
	T.equal((line(r, "Placement") :: Types.RewardLine).xp, math.floor(150 * share + 0.5))
	-- joining in the first minute counts as the whole match
	local early = Progression.matchReward(state, busy(101, 50), STANDARD)
	T.equal((line(early, "Finish") :: Types.RewardLine).xp, 100)
	T.equal((line(early, "Placement") :: Types.RewardLine).xp, 150)
end)

T.test("a short match (early domination) pays in full", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	state.tick = 200
	(state.result :: Types.MatchResult).endedAt = 200
	local r = Progression.matchReward(state, busy(101, 2, 200), STANDARD)
	T.equal(r.xp, 250)
end)

T.test("AFK for 5 minutes in a row pays nothing", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = Progression.newStats(101, 0)
	Progression.recordCommand(stats, 100, { kind = "Develop", province = 1 }, true)
	Progression.recordCommand(stats, 100 + P.AfkTicks, { kind = "Develop", province = 1 }, true)
	for t = 500, END, 100 do
		Progression.recordCommand(stats, t, { kind = "Develop", province = 1 }, false)
	end
	local r = Progression.matchReward(state, stats, { vip = true, firstMatchToday = true, standardRules = true })
	T.expect(r.afk)
	T.equal(r.xp, 0)
	T.equal(r.glory, 0)
	-- one tick short of the window still pays
	local ok = Progression.newStats(101, 0)
	for t = P.AfkTicks - 1, END, P.AfkTicks - 1 do
		Progression.recordCommand(ok, t, { kind = "Develop", province = 1 }, true)
	end
	T.expect(not Progression.matchReward(state, ok, STANDARD).afk)
end)

T.test("going quiet before the end counts as AFK too", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = busy(101, 0, END - P.AfkTicks - 10)
	T.expect(Progression.matchReward(state, stats, STANDARD).afk)
end)

T.test("an eliminated player who rose as a Primordial", function()
	local state = finished({ 1 }, scoresFor({ 300, 0, 100, 90, 80, 70, 60, 50, 40, 30 }))
	state.nations[2].eliminated = true
	state.primordials[102] = { userId = 102, charges = 1, chargeTicks = 0 }
	local stats = busy(102)
	stats.powersUsed = 2
	local r = Progression.matchReward(state, stats, STANDARD)
	T.equal(r.placement, 10, "placed by the eliminated nation's score")
	T.equal((line(r, "Primordial") :: Types.RewardLine).xp, P.PrimordialXp)
	T.equal((line(r, "Primordial") :: Types.RewardLine).glory, P.PrimordialGlory)
	T.equal((line(r, "Powers") :: Types.RewardLine).xp, 20)
	T.equal(r.xp, 100 + 25 + 50 + 20)
end)

T.test("a spectator who never had a nation earns nothing for finishing", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local r = Progression.matchReward(state, busy(999), { vip = false, firstMatchToday = true, standardRules = true })
	T.equal(r.placement, nil)
	T.equal(r.xp, 0, "no finish or first-match XP")
	T.equal(r.glory, 0)
end)

T.test("a player who had a nation earlier in the match still gets the finish reward", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = busy(103)
	local result = state.result
	state.result = nil -- during the match (nobody new is seated once it's over)
	Match.seatPlayer(state, 103) -- seated during the match...
	Progression.observe(state, { [103] = stats })
	Match.unseatPlayer(state, 103) -- ...and no longer at the end
	state.result = result
	T.expect(stats.seated, "observe noted the seat")
	T.equal((line(Progression.matchReward(state, stats, STANDARD), "Finish") :: Types.RewardLine).xp, P.FinishXp)
end)

T.test("VIP adds 25% of the match reward, not of the first-match bonus; custom rules pay half", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local vip = Progression.matchReward(state, busy(101), { vip = true, firstMatchToday = true, standardRules = true })
	T.equal((line(vip, "Vip") :: Types.RewardLine).xp, 63) -- 25% of 250, rounded
	T.equal((line(vip, "Vip") :: Types.RewardLine).glory, 15)
	T.equal(vip.xp, 250 + 63 + P.FirstMatchXp)
	T.equal(vip.glory, 60 + 15 + P.FirstMatchGlory)
	local custom =
		Progression.matchReward(state, busy(101), { vip = false, firstMatchToday = false, standardRules = false })
	T.equal(custom.xp, 125)
	T.equal(custom.glory, 30)
end)

-- Stats ---------------------------------------------------------------------------------------------------

T.test("captures and battle wins count for the player whose nation made them", function()
	local state = Match.new(Maps.get("skyshards"))
	Match.seatPlayer(state, 101)
	local stats = { [101] = Progression.newStats(101, 0) }
	Events.push(state, "ProvinceTaken", 1, 0, 5)
	Events.push(state, "BattleEnded", 1, 2, 5)
	Events.push(state, "BattleEnded", 2, 1, 6) -- a bot's win
	Events.push(state, "ProvinceTaken", 0, 1, 7) -- rebels
	Progression.observe(state, stats)
	T.equal(stats[101].provincesTaken, 1)
	T.equal(stats[101].battlesWon, 1)
end)

T.test("only successful powers count as used", function()
	local stats = Progression.newStats(101, 0)
	Progression.recordCommand(stats, 10, { kind = "Power", power = "Meteor", target = 1 }, false)
	Progression.recordCommand(stats, 20, { kind = "Power", power = "Meteor", target = 1 }, true)
	T.equal(stats.powersUsed, 1)
	T.equal(stats.lastCommandAt, 20)
	T.equal(stats.longestIdle, 10)
end)

-- Profiles ------------------------------------------------------------------------------------------------

T.test("granting a reward levels up and pays 50 Glory per level", function()
	local profile = Progression.newProfile()
	T.expect(Progression.isFirstMatchToday(profile, 19000))
	local stats = busy(101)
	stats.provincesTaken, stats.battlesWon = 1, 1
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local reward = Progression.matchReward(state, stats, { vip = false, firstMatchToday = true, standardRules = true })
	T.equal(reward.xp, 460)
	local report = Progression.grant(profile, stats, reward, 19000)
	T.equal(profile.xp, 460)
	T.equal(profile.level, 2)
	T.equal(profile.glory, 20 + 40 + 1 + 1 + 50 + 50)
	T.equal(report.reward.glory, profile.glory, "the report's total includes the level-up Glory")
	T.equal((line(report.reward, "LevelUp") :: Types.RewardLine).glory, 50)
	T.equal(line(report.reward, "RankUp"), nil)
	T.equal(#reward.lines, 5, "the match reward itself is not changed")
	T.equal(report.before.level, 1)
	T.equal(report.after.level, 2)
	T.equal(report.after.xpIntoLevel, 160)
	T.equal(report.after.xpForLevel, 360)
	T.equal(profile.lastMatchDay, 19000)
	T.expect(not Progression.isFirstMatchToday(profile, 19000))
	T.expect(Progression.isFirstMatchToday(profile, 19001))
	T.equal(profile.stats.matches, 1)
	T.equal(profile.stats.wins, 1)
	T.equal(profile.stats.provincesTaken, 1)
end)

T.test("crossing level 10 is a rank-up worth 500 Glory", function()
	local profile = Progression.newProfile()
	profile.xp = Progression.totalXpFor(10) - 1
	profile.level = 9
	local reward: Types.MatchReward =
		{ xp = 600, glory = 0, lines = { { kind = "Finish", xp = 600, glory = 0 } }, stayed = true, afk = false }
	local report = Progression.grant(profile, Progression.newStats(1, 0), reward, 1)
	T.equal(profile.level, 10)
	T.equal(report.after.rankName, "Chieftain")
	T.equal(report.before.rankName, "Settler")
	T.equal(profile.glory, 50 + 500)
	T.equal((line(report.reward, "RankUp") :: Types.RewardLine).glory, 500)
end)

T.test("an AFK or leaver reward doesn't use up the first-match bonus or count as a match", function()
	local profile = Progression.newProfile()
	local afk: Types.MatchReward = { xp = 0, glory = 0, lines = {}, stayed = true, afk = true }
	Progression.grant(profile, Progression.newStats(1, 0), afk, 5)
	local left: Types.MatchReward = { xp = 10, glory = 2, lines = {}, stayed = false, afk = false }
	Progression.grant(profile, Progression.newStats(1, 0), left, 5)
	T.expect(Progression.isFirstMatchToday(profile, 5))
	T.equal(profile.stats.matches, 0, "an AFK match isn't a match played (it doesn't move the starter-pack offer)")
	T.equal(profile.xp, 10)
end)

T.test("a leave and then Results add the match's captures, battles and powers to the lifetime stats once", function()
	local profile = Progression.newProfile()
	local stats = Progression.newStats(1, 0)
	stats.provincesTaken, stats.battlesWon, stats.powersUsed = 3, 2, 1
	local left: Types.MatchReward = { xp = 10, glory = 2, lines = {}, stayed = false, afk = false }
	Progression.grant(profile, stats, left, 5)
	T.equal(profile.stats.provincesTaken, 3)
	stats.provincesTaken, stats.battlesWon = 5, 2 -- rejoined, took 2 more
	local results: Types.MatchReward = { xp = 10, glory = 2, lines = {}, stayed = true, afk = false }
	Progression.grant(profile, stats, results, 5)
	T.equal(profile.stats.provincesTaken, 5, "3 then 2 more, not 3 + 5")
	T.equal(profile.stats.battlesWon, 2)
	T.equal(profile.stats.powersUsed, 1)
	T.equal(profile.stats.matches, 1)
end)

T.test("migrate keeps a v1 profile and recomputes the level from XP", function()
	local profile = Progression.newProfile()
	profile.xp = 700
	profile.level = 1
	Progression.migrate(profile)
	T.equal(profile.version, Progression.PROFILE_VERSION)
	T.equal(profile.level, 3)
end)

-- Leaving and rejoining ------------------------------------------------------------------------------------

local function command(stats: Types.PlayerMatchStats, from: number, to: number)
	for t = from, to, 100 do
		Progression.recordCommand(stats, t, { kind = "Develop", province = 1 }, true)
	end
end

T.test("leaving and rejoining pays the caps once: the same play pays the same as one session", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	-- one session: 40 captures and 20 battles won
	local whole = busy(101)
	whole.provincesTaken, whole.battlesWon = 40, 20
	local single = Progression.newProfile()
	Progression.grant(single, whole, Progression.matchReward(state, whole, STANDARD), 1)

	-- the same play with three leaves (each paid at once) and a rejoin 10 s after each
	local split = Progression.newProfile()
	local stats = Progression.newStats(101, 0)
	for _, cut in { 300, 600, 900 } do
		command(stats, stats.joinedAt, cut)
		stats.provincesTaken += 10
		stats.battlesWon += 5
		Progression.leave(stats, cut)
		Progression.grant(split, stats, Progression.matchReward(state, stats, STANDARD), 1)
		Progression.rejoin(stats, cut + 10)
	end
	command(stats, stats.joinedAt, END)
	stats.provincesTaken += 10
	stats.battlesWon += 5
	local final = Progression.matchReward(state, stats, STANDARD)
	T.expect(line(final, "PaidEarlier") ~= nil, "Results takes off what the leaves paid")
	Progression.grant(split, stats, final, 1)
	T.equal(split.xp, single.xp, "same XP")
	T.equal(split.glory, single.glory, "same Glory")
end)

T.test("a rejoin carries on the finish share instead of starting a new one", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = Progression.newStats(101, 0)
	command(stats, 0, 400)
	Progression.leave(stats, 400)
	Progression.rejoin(stats, 700)
	command(stats, 700, 1000)
	Progression.leave(stats, 1000)
	-- played 400 + 300 ticks
	local share = 700 / (END - P.LateJoinGraceTicks)
	local r = Progression.matchReward(state, stats, STANDARD)
	T.equal((line(r, "Finish") :: Types.RewardLine).xp, math.floor(P.FinishXp * share + 0.5))
end)

T.test("time away isn't idle: rejoining after 10 minutes isn't AFK", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = Progression.newStats(101, 0)
	command(stats, 0, 300)
	Progression.leave(stats, 300)
	Progression.rejoin(stats, 900)
	command(stats, 900, END)
	T.expect(not Progression.matchReward(state, stats, STANDARD).afk)
end)

T.test("what was paid earlier never makes a reward negative", function()
	local state = finished({ 1 }, scoresFor({ 300, 200 }))
	local stats = busy(101)
	stats.paidXp, stats.paidGlory = 10000, 10000
	local r = Progression.matchReward(state, stats, STANDARD)
	T.equal(r.xp, 0)
	T.equal(r.glory, 0)
end)

T.finish()
