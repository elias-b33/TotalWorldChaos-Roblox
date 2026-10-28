--!strict
-- Analytics payloads (Sim.Telemetry): the event plan stays inside AnalyticsService's limits, and the builders turn
-- matches, votes, rewards and purchases into the events docs/LAUNCH.md lists. Also the per-minute budget.
local Config = require("../src/shared/Config")
local Events = require("../src/shared/Sim/Events")
local Lobby = require("../src/shared/Sim/Lobby")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Progression = require("../src/shared/Sim/Progression")
local T = require("./TestKit")
local Telemetry = require("../src/shared/Sim/Telemetry")
local Tutorial = require("../src/shared/Sim/Tutorial")
local Types = require("../src/shared/Types")

local function named(events: { Types.TelemetryEvent }, name: string): { Types.TelemetryEvent }
	local out = {}
	for _, e in events do
		if e.name == name then
			table.insert(out, e)
		end
	end
	return out
end

-- A match on Skyshards: user 101 plays nation 1, user 102 nation 2.
local function seated(): Types.MatchState
	local state = Match.new(Maps.get("skyshards"))
	Match.seatPlayer(state, 101)
	Match.seatPlayer(state, 102)
	return state
end

-- The plan --------------------------------------------------------------------------------------------------------

T.test("the plan fits AnalyticsService's limits: under 100 event names, 10 funnels, 100 steps", function()
	T.expect(#Telemetry.CUSTOM_EVENTS < 100, "custom event names")
	local seen = {}
	for _, name in Telemetry.CUSTOM_EVENTS do
		T.expect(not seen[name], "duplicate event " .. name)
		seen[name] = true
	end
	local funnels = 0
	for _, steps in Telemetry.FUNNELS do
		funnels += 1
		T.expect(#steps <= 100, "steps per funnel")
	end
	T.expect(funnels + 1 <= 10, "funnels (with onboarding)")
	T.equal(#Telemetry.ONBOARDING, 12)
	T.equal(#Telemetry.ONBOARDING, 6 + #Tutorial.STEPS, "4 steps, the tutorial prompts, 2 steps")
end)

T.test("custom events refuse unknown names and more than 3 fields", function()
	T.expect(not pcall(Telemetry.custom, "made_up", 1, {}), "unknown name")
	T.expect(not pcall(Telemetry.custom, "map_vote", 1, { "a", "b", "c", "d" }), "4 fields")
	local e = Telemetry.custom("map_vote", 1, { "earth", "lobby", "earth" }, 7)
	T.equal(e.kind, "Custom")
	T.equal(e.userId, 7)
	T.equal(#e.fields, 3)
end)

T.test("funnel and onboarding steps are numbered from the plan", function()
	local e = Telemetry.funnel("MatchFlow", "m-1", "war", 5)
	T.equal(e.value, 4)
	T.equal(e.session, "m-1")
	T.equal(e.step, "war")
	T.equal(Telemetry.funnel("Shop", "s", "purchase_completed", 5).value, 4)
	T.equal(Telemetry.funnel("SeasonPass", "s", "pass_viewed", 5).value, 1)
	T.expect(not pcall(Telemetry.funnel, "MatchFlow", "m", "made_up", 5), "unknown step")
	T.expect(not pcall(Telemetry.funnel, "Nope", "m", "lobby", 5), "unknown funnel")
	local o = Telemetry.onboarding("second_match_started", 5)
	T.equal(o.kind, "Onboarding")
	T.equal(o.value, 12)
	T.equal(Telemetry.onboarding("first_neutral_captured", 5).value, 5)
end)

T.test("buckets and minutes", function()
	T.equal(Telemetry.humansBucket(0), "0")
	T.equal(Telemetry.humansBucket(1), "1-3")
	T.equal(Telemetry.humansBucket(3), "1-3")
	T.equal(Telemetry.humansBucket(4), "4-6")
	T.equal(Telemetry.humansBucket(12), "7-12")
	T.equal(Telemetry.levelBucket(1), "1-9")
	T.equal(Telemetry.levelBucket(10), "10-29")
	T.equal(Telemetry.levelBucket(30), "30+")
	T.equal(Telemetry.levelBucket(100), "30+")
	T.equal(Telemetry.minutes(Config.Phases.MatchEndTick), 25)
	T.equal(Telemetry.minutes(90), 1.5)
	T.equal(Telemetry.phaseStep("Cataclysm"), "cataclysm")
	T.equal(Telemetry.phaseStep("Pick"), nil)
end)

-- Match events ------------------------------------------------------------------------------------------------------

T.test("nation_start: every start nation once, human or bot", function()
	local state = seated()
	Match.unseatPlayer(state, 102) -- left: nation 2 started with a human all the same
	local starts = Telemetry.nationStarts(state)
	T.equal(#starts, Config.NationsPerMatch)
	for i, e in starts do
		T.equal(e.name, "nation_start")
		T.equal(e.userId, nil, "match-wide")
		T.equal(e.fields[1], "skyshards")
		T.equal(e.fields[2], tostring(i))
		T.equal(e.fields[3], if i <= 2 then "human" else "bot")
	end
end)

T.test("match end: length, winners and every nation's placement", function()
	local state = seated()
	state.tick = 900
	state.phase = "Results"
	local scores = {}
	for i = 1, 10 do
		table.insert(scores, { nation = i, score = 100 - i })
	end
	state.result = { kind = "Domination", winners = { 2 }, scores = scores, endedAt = 900 }
	local events = Telemetry.matchEnd(state)
	local ended = named(events, "match_end")
	T.equal(#ended, 1)
	T.equal(ended[1].value, 15, "15 minutes")
	T.equal(table.concat(ended[1].fields, ","), "skyshards,domination,1-3")
	local wins = named(events, "match_win")
	T.equal(#wins, 1)
	T.equal(table.concat(wins[1].fields, ","), "skyshards,2,domination")
	local results = named(events, "player_result")
	T.equal(#results, 10)
	T.equal(results[2].value, 1, "the winner is 1st")
	T.equal(results[2].userId, 102)
	T.equal(results[1].value, 2, "nation 1 is next by score")
	T.equal(results[1].fields[3], "human")
	T.equal(results[5].fields[3], "bot")
	T.equal(results[5].userId, nil)
end)

T.test("player_eliminated for a player's nation, not a bot's", function()
	local state = seated()
	state.tick = 600
	state.phase = "War"
	Events.push(state, "Eliminated", 1)
	Events.push(state, "Eliminated", 5)
	local events = Telemetry.eliminations(state)
	T.equal(#events, 1)
	T.equal(events[1].userId, 101)
	T.equal(events[1].value, 10)
	T.equal(table.concat(events[1].fields, ","), "skyshards,1,War")
end)

T.test("quitting: player_quit, and bot_replaced_leaver only for a living nation", function()
	local state = seated()
	state.tick = 300
	state.phase = "War"
	local living = Telemetry.quit(state, 101)
	T.equal(#living, 2)
	T.equal(living[1].name, "player_quit")
	T.equal(living[1].value, 5)
	T.equal(table.concat(living[1].fields, ","), "skyshards,War,false")
	T.equal(living[2].name, "bot_replaced_leaver")
	T.equal(table.concat(living[2].fields, ","), "skyshards,War")

	state.nations[2].eliminated = true
	state.primordials[102] = { userId = 102, charges = 0, chargeTicks = 0 }
	local primordial = Telemetry.quit(state, 102)
	T.equal(#primordial, 1, "a Primordial leaves no nation behind")
	T.equal(primordial[1].fields[3], "true")

	T.equal(#Telemetry.quit(state, 999), 0, "never played")
	state.result = { kind = "Score", winners = { 1 }, scores = {}, endedAt = 300 }
	T.equal(#Telemetry.quit(state, 101), 0, "leaving after Results isn't quitting")
end)

T.test("primordial_power_used says who used it", function()
	local state = seated()
	local e = Telemetry.powerUsed(state, 101, "Blessing")
	T.equal(table.concat(e.fields, ","), "Blessing,skyshards,living")
	state.nations[2].eliminated = true
	T.equal(Telemetry.powerUsed(state, 102, "Meteor").fields[3], "primordial")
end)

T.test("map_vote: one per voter with the round and the theme", function()
	local lobby = Lobby.new(Maps.ids, nil)
	T.expect((Lobby.vote(lobby, 202, "eldmoor")), "vote")
	T.expect((Lobby.vote(lobby, 201, "earth")), "vote")
	local themes = { earth = "earth", eldmoor = "fantasy", skyshards = "sky" }
	local events = Telemetry.mapVotes(lobby, "next", themes)
	T.equal(#events, 2)
	T.equal(events[1].userId, 201)
	T.equal(table.concat(events[1].fields, ","), "earth,next,earth")
	T.equal(table.concat(events[2].fields, ","), "eldmoor,next,fantasy")
end)

-- Economy and progression --------------------------------------------------------------------------------------------

T.test("a reward with a level-up: two Glory sources with their balances, and AccountLevel progress", function()
	local profile = Progression.newProfile()
	local stats = Progression.newStats(101, 0)
	local reward: Types.MatchReward = {
		xp = 700,
		glory = 120,
		lines = { { kind = "Finish", xp = 700, glory = 120 } },
		placement = 1,
		stayed = true,
		afk = false,
	}
	local report = Progression.grant(profile, stats, reward, 1)
	T.equal(report.after.level, 3, "700 XP: level 3")
	local fields = Telemetry.economyFields(profile, true)
	T.equal(table.concat(fields, ","), "1-9,true,false")
	local events = Telemetry.reward(report, fields, 101)
	local sources = named(events, Telemetry.GLORY)
	T.equal(#sources, 2)
	T.equal(sources[1].step, "match_reward")
	T.equal(sources[1].value, 120)
	T.equal(sources[1].balance, 120)
	T.equal(sources[1].flow, "Source")
	T.equal(sources[1].transaction, "Gameplay")
	T.equal(sources[2].step, "level_up")
	T.equal(sources[2].value, 2 * Config.Progression.LevelUpGlory)
	T.equal(sources[2].balance, profile.glory, "the ending balance")
	local levels = named(events, Telemetry.ACCOUNT_LEVEL)
	T.equal(#levels, 3, "completed 1 and 2, started 3")
	T.equal(levels[1].flow, "Complete")
	T.equal(levels[1].value, 1)
	T.equal(levels[1].step, Config.Progression.Ranks[1])
	T.equal(levels[3].flow, "Start")
	T.equal(levels[3].value, 3)
end)

T.test("a reward without Glory or levels sends nothing", function()
	local profile = Progression.newProfile()
	local reward: Types.MatchReward = { xp = 0, glory = 0, lines = {}, placement = nil, stayed = false, afk = true }
	local report = Progression.grant(profile, Progression.newStats(1, 0), reward, 1)
	T.equal(#Telemetry.reward(report, {}, 1), 0)
end)

T.test("purchases: a Glory shop sink and a Robux IAP sink", function()
	local profile = Progression.newProfile()
	table.insert(profile.purchaseHistory, { product = 1, robux = 49, at = 0, item = "flag_cross" })
	profile.level = 12
	local fields = Telemetry.economyFields(profile, false)
	T.equal(table.concat(fields, ","), "10-29,false,true")
	local glory = Telemetry.gloryPurchase("flag_sun", 1200, 1800, fields, 7)
	T.equal(glory.flow, "Sink")
	T.equal(glory.name, "Glory")
	T.equal(glory.transaction, "Shop")
	T.equal(glory.step, "flag_sun")
	T.equal(glory.value, 1200)
	T.equal(glory.balance, 1800)
	local robux = Telemetry.robuxPurchase("vip", 249, fields, 7)
	T.equal(robux.name, "Robux")
	T.equal(robux.transaction, "IAP")
	T.equal(robux.value, 249)
end)

-- Budget ----------------------------------------------------------------------------------------------------------------

T.test("the budget allows 120 + 20 per player each minute and counts what it drops", function()
	local budget = Telemetry.newBudget()
	local limit = Telemetry.limit(2)
	T.equal(limit, Config.Telemetry.BudgetBase + 2 * Config.Telemetry.BudgetPerPlayer)
	for i = 1, limit do
		T.expect((Telemetry.allow(budget, 10 + (i - 1) / 1000, 2)), "event " .. i)
	end
	T.expect(not (Telemetry.allow(budget, 30, 2)), "over the budget")
	T.expect(not (Telemetry.allow(budget, 69, 2)), "still the same minute")
	T.expect((Telemetry.allow(budget, 9 + 60, 2)) == false, "the window started at the first event")
	local ok, dropped = Telemetry.allow(budget, 10 + 60, 2)
	T.expect(ok, "a new minute")
	T.equal(dropped, 3, "the last minute dropped 3")
	local _, again = Telemetry.allow(budget, 71, 2)
	T.equal(again, 0, "reported once")
	T.expect((Telemetry.allow(Telemetry.newBudget(), 0, 0)), "an empty server still sends")
end)

T.finish()
