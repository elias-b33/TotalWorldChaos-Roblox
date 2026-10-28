--!nocheck
-- Phase 5: analytics. A new player (Alice) and a returning one (Bob) go through the Lobby, the shop, the starter
-- pack, a whole match and the start of the next one, where Carol joins, Bob is eliminated, rises as a Primordial
-- and leaves, and Carol leaves. The emulator records every AnalyticsService call (Emulator.analytics); each funnel,
-- economy, progression and custom event from docs/LAUNCH.md "Analytics events" is checked against them.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local shown = H.shown

local function run()
	local Telemetry = require("../../../src/shared/Sim/Telemetry")
	local ROBUX = utf8.char(0xE002)
	local log = Emulator.analytics
	-- recorded calls: { method, userId, args }; args follow the player (enums as names)
	local function calls(method: string, userId: number?, first: any?)
		local out = {}
		for _, r in log do
			if r.method == method and (userId == nil or r.userId == userId) and (first == nil or r.args[1] == first) then
				table.insert(out, r)
			end
		end
		return out
	end
	local function customs(name: string, userId: number?)
		return calls("LogCustomEvent", userId, name)
	end
	local function fields(r)
		local f = r.args[#r.args] or {}
		local keys = Emulator.roblox.Enum.AnalyticsCustomFieldKeys
		return table.concat({
			f[keys.CustomField01.Name] or "",
			f[keys.CustomField02.Name] or "",
			f[keys.CustomField03.Name] or "",
		}, ",")
	end
	-- the step names of one funnel for one player, in order (and their sessions)
	local function steps(funnel: string, userId: number)
		local names, sessions = {}, {}
		for _, r in calls("LogFunnelStepEvent", userId, funnel) do
			table.insert(names, r.args[4])
			table.insert(sessions, r.args[2])
		end
		return table.concat(names, ","), sessions
	end
	local function onboarding(userId: number)
		local names = {}
		for _, r in calls("LogOnboardingFunnelStepEvent", userId) do
			table.insert(names, r.args[2])
		end
		return table.concat(names, ",")
	end
	local function has(list: string, item: string): boolean
		return table.find(string.split(list, ","), item) ~= nil
	end
	local function economy(userId: number, sku: string)
		for _, r in calls("LogEconomyEvent", userId) do
			if r.args[6] == sku then
				return r
			end
		end
		return nil
	end
	local pressIn = H.pressIn
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
	local function runUntil(cond, seconds: number)
		local deadline = Emulator.now() + seconds
		while not cond() and Emulator.now() < deadline do
			Emulator.run(1)
		end
	end
	local function dominate(state, nation)
		local total, given = 0, 0
		for _, p in state.provinces do
			total += 1
			given += if p.owner == nation then 1 else 0
		end
		for _, p in state.provinces do
			if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= nation and p.terrain ~= "Mountain" then
				p.owner = nation
				given += 1
			end
		end
	end

	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(3)
	local a, b = alice.serverPlayer.UserId, bob.serverPlayer.UserId
	local Data = H.server("Services.PlayerDataService")
	local ShopService = H.server("Services.ShopService")
	local LobbyService = H.server("Services.LobbyService")

	-- joining: onboarding, MatchFlow's first step, the first account level
	H.expect(onboarding(a) == "joined,lobby_loaded", "Alice's onboarding: joined, lobby_loaded")
	H.expect(steps("MatchFlow", a) == "lobby", "MatchFlow step 1 (lobby) for Alice")
	local start = calls("LogProgressionStartEvent", a, "AccountLevel")
	H.expect(#start == 1 and start[1].args[2] == 1 and start[1].args[3] == "Settler", "AccountLevel 1 (Settler) started")
	-- Bob has played before (two matches): no more onboarding for him from here on
	Data.update(bob.serverPlayer, function(data)
		data.stats.matches = 2
	end)

	-- the shop: opened, a tab, a Glory purchase, a Robux purchase (Studio test mode), a refused one
	Data.update(alice.serverPlayer, function(data)
		data.glory = 3000
	end)
	Emulator.press(alice, "ShopButton")
	Emulator.run(0.5)
	Emulator.press(alice, "Tab_Flag")
	Emulator.run(0.5)
	pressIn(alice, "Card_flag_sun", "1,200", "medal")
	Emulator.run(1)
	local sun = economy(a, "flag_sun")
	H.expect(sun and sun.args[1] == "Sink" and sun.args[2] == "Glory" and sun.args[5] == "Shop", "a Glory Shop sink: flag_sun")
	H.expect(sun.args[3] == 1200 and sun.args[4] == 1800, "1,200 Glory, ending balance 1,800")
	H.expect(fields(sun) == "1-9,false,false", "with level_bucket, is_vip, is_payer")
	Emulator.press(alice, "NextPage")
	Emulator.run(0.3)
	pressIn(alice, "Card_flag_comet", ROBUX .. " 149")
	Emulator.run(1.5)
	local comet = economy(a, "flag_comet")
	H.expect(comet and comet.args[2] == "Robux" and comet.args[5] == "IAP" and comet.args[3] == 149, "a Robux IAP sink: flag_comet, 149")
	local shopSteps, shopSessions = steps("Shop", a)
	H.expect(
		shopSteps == "shop_opened,item_viewed,purchase_prompted,purchase_completed,purchase_completed,purchase_prompted",
		"the Shop funnel: opened, viewed (once), Glory buy prompted + completed, Robux buy completed + prompted"
	)
	H.expect(shopSessions[1] == shopSessions[#shopSessions], "all in one shop session")
	local ok, reason = await(ShopService.apply, alice.serverPlayer, { kind = "Buy", item = "flag_comet", currency = "Robux" })
	H.expect(ok == false and reason == "Owned", "buying the Comet twice is refused")
	local failed = customs("purchase_failed", a)
	H.expect(#failed == 1 and fields(failed[1]) == "flag_comet,Owned,", "purchase_failed: product and reason")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)
	Emulator.press(alice, "ShopButton")
	Emulator.run(0.3)
	local _, sessions = steps("Shop", a)
	H.expect(sessions[#sessions] ~= shopSessions[1], "opening the shop again starts a new Shop session")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the starter pack for Bob: shown, opened (the pop-up), prompted, completed
	ShopService.onPhase("Lobby")
	Emulator.run(1)
	H.expect(Emulator.findText(bob, "Starter Pack") ~= nil, "Bob sees the starter-pack offer")
	Emulator.press(bob, "Buy")
	Emulator.run(1.5)
	local starterSteps, starterSessions = steps("StarterPack", b)
	H.expect(
		starterSteps == "offer_shown,offer_opened,purchase_completed,purchase_prompted",
		"the StarterPack funnel: shown, opened, then the purchase (test mode grants before the prompt step)"
	)
	H.expect(starterSessions[1] == tostring(b), "its session is Bob's userId")
	H.expect(economy(b, "starter") ~= nil, "and a Robux IAP sink for the starter pack")
	H.expect(steps("StarterPack", a) == "", "Alice (no finished match) isn't offered it")

	-- the map vote: Alice votes, Bob doesn't
	Emulator.press(alice, "Card_eldmoor")
	Emulator.press(alice, "Card_eldmoor")
	runUntil(function()
		return LobbyService.phase() ~= "Lobby"
	end, 70)
	local votes = customs("map_vote")
	H.expect(#votes == 1 and votes[1].userId == a and fields(votes[1]) == "eldmoor,lobby,fantasy", "map_vote: eldmoor, lobby, fantasy")
	H.expect(has(onboarding(a), "map_voted"), "Alice's onboarding: map_voted")

	-- the draft runs out: the match starts in Peace
	runUntil(function()
		return H.state().phase == "Peace" and not LobbyService.active()
	end, 40)
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A ~= 0 and B ~= 0, "both have a nation")
	H.expect(steps("MatchFlow", a) == "lobby,pick,peace", "MatchFlow for Alice: lobby, pick, peace")
	H.expect(steps("MatchFlow", b) == "lobby,pick,peace", "and for Bob")
	H.expect(has(onboarding(a), "nation_picked") and not has(onboarding(b), "nation_picked"), "onboarding: Alice picked a nation; Bob is past onboarding")

	-- War: nation_start for all ten nations after the first minute
	local Intents = H.client(alice, "Intents")
	Intents.develop(state.nations[A].capital) -- a command, so the jump to War isn't idle time
	Emulator.run(1.5)
	state.tick = Config.Phases.PeaceEndTick - 1
	Emulator.run(2)
	H.expect(state.phase == "War", "War")
	H.expect(has(steps("MatchFlow", a), "war"), "MatchFlow: war")
	local starts = customs("nation_start")
	H.expect(#starts == Config.NationsPerMatch, "nation_start for every nation")
	local humans = 0
	for _, r in starts do
		humans += if string.find(fields(r), "human", 1, true) then 1 else 0
	end
	H.expect(humans == 2 and fields(starts[A]) == "eldmoor," .. A .. ",human", "two of them human, with map and start nation")
	H.expect(starts[1].userId == a, "match-wide events go out for the lowest userId in the server")

	-- Bob uses a power on his own land
	state.nations[B].charges = 2
	H.client(bob, "Intents").power("Blessing", state.nations[B].capital)
	Emulator.run(1.5)
	local powers = customs("primordial_power_used", b)
	H.expect(#powers == 1 and fields(powers[1]) == "Blessing,eldmoor,living", "primordial_power_used: Blessing, eldmoor, living")

	-- Alice wins: match_end, match_win, player_result, Results, the reward's economy and progression events
	Intents.develop(state.nations[A].capital)
	Emulator.run(1.5)
	dominate(state, A)
	Emulator.run(2)
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Alice won by domination")
	local ended = customs("match_end")
	H.expect(#ended == 1 and fields(ended[1]) == "eldmoor,domination,1-3", "match_end: eldmoor, domination, 1-3 humans")
	H.expect(ended[1].args[2] == Telemetry.minutes(state.result.endedAt), string.format("its value is the match length (%.1f min)", ended[1].args[2]))
	local wins = customs("match_win")
	H.expect(#wins == 1 and fields(wins[1]) == "eldmoor," .. A .. ",domination", "match_win: Alice's start nation")
	local results = customs("player_result")
	H.expect(#results == Config.NationsPerMatch, "player_result for every nation")
	local mine = results[A]
	H.expect(mine.userId == a and mine.args[2] == 1 and fields(mine) == "eldmoor," .. A .. ",human", "Alice placed 1st")
	H.expect(has(steps("MatchFlow", a), "results") and has(steps("MatchFlow", b), "results"), "MatchFlow: results")
	H.expect(has(onboarding(a), "first_match_finished"), "Alice's onboarding: first_match_finished")
	local data = Data.data(alice.serverPlayer)
	local matchReward, levelUp = economy(a, "match_reward"), economy(a, "level_up")
	H.expect(matchReward and matchReward.args[1] == "Source" and matchReward.args[5] == "Gameplay", "a Glory Gameplay source: match_reward")
	H.expect(levelUp and levelUp.args[3] == Config.Progression.LevelUpGlory, "and level_up (50 Glory)")
	-- the win also unlocks achievements (Domination, Victor...): their Glory is its own source, logged last
	local achievement = economy(a, "achievement")
	H.expect(achievement and achievement.args[4] == data.glory, "and achievement, ending on Alice's balance")
	local extra = achievement.args[3]
	H.expect(levelUp.args[4] == data.glory - extra and matchReward.args[4] == data.glory - extra - levelUp.args[3], "with the ending balances")
	H.expect(fields(matchReward) == "1-9,false,true", "Alice is a payer now")
	local done = calls("LogProgressionCompleteEvent", a, "AccountLevel")
	H.expect(#done == 1 and done[1].args[2] == 1, "AccountLevel 1 completed")
	H.expect(#calls("LogProgressionStartEvent", a, "AccountLevel") == 2, "and level 2 started")
	local firstSession = select(2, steps("MatchFlow", a))[1]

	-- the next-map vote: a new MatchFlow session, round "next"
	runUntil(function()
		return LobbyService.phase() == "Lobby"
	end, 40)
	Emulator.run(1)
	local _, flowSessions = steps("MatchFlow", a)
	H.expect(flowSessions[#flowSessions] ~= firstSession, "the next Lobby starts a new MatchFlow session")
	for _, client in { alice, bob } do
		Emulator.press(client, "Card_skyshards")
		Emulator.press(client, "Card_skyshards")
	end
	runUntil(function()
		return LobbyService.phase() ~= "Lobby"
	end, 70)
	votes = customs("map_vote")
	H.expect(#votes == 3 and fields(votes[3]) == "skyshards,next,sky", "map_vote round next")
	runUntil(function()
		return H.state().phase == "Peace" and not LobbyService.active()
	end, 40)
	Emulator.run(2)
	state = H.state()
	local nextStarted = 0
	for _, r in calls("LogFunnelStepEvent", nil, "MatchFlow") do
		if r.args[4] == "next_match_started" and r.args[2] == firstSession then
			nextStarted += 1
		end
	end
	H.expect(nextStarted == 1, "MatchFlow next_match_started on Alice's first-match session")
	local bobNext = 0
	for _, r in calls("LogFunnelStepEvent", b, "MatchFlow") do
		bobNext += if r.args[4] == "next_match_started" then 1 else 0
	end
	H.expect(bobNext == 1, "and on Bob's")
	H.expect(has(onboarding(a), "second_match_started"), "Alice's onboarding: second_match_started")

	-- Carol joins mid-match; Cataclysm; everyone has been idle for 17 minutes
	local carol = Emulator.addClient("Carol")
	Emulator.run(3)
	local c = carol.serverPlayer.UserId
	B = H.myNation(bob)
	state.tick = Config.Phases.WarEndTick - 1
	Emulator.run(2)
	H.expect(state.phase == "Cataclysm", "Cataclysm")
	H.expect(has(steps("MatchFlow", c), "cataclysm"), "MatchFlow: cataclysm (for Carol too, who joined late)")
	local afk = customs("afk_flagged", b)
	H.expect(#afk == 1 and fields(afk[1]) == "skyshards,Cataclysm,", "afk_flagged for Bob, once")

	-- Bob loses everything: player_eliminated, then he rises as a Primordial and uses a power
	for _, p in state.provinces do
		if p.owner == B then
			p.owner = H.myNation(alice)
		end
	end
	Emulator.run(2)
	H.expect(state.nations[B].eliminated and state.primordials[b] ~= nil, "Bob was eliminated and rose as a Primordial")
	local out = customs("player_eliminated", b)
	H.expect(#out == 1 and fields(out[1]) == "skyshards," .. B .. ",Cataclysm", "player_eliminated: map, start nation, phase")
	state.primordials[b].charges = 2
	H.client(bob, "Intents").power("Blessing", state.nations[H.myNation(alice)].capital)
	Emulator.run(1.5)
	powers = customs("primordial_power_used", b)
	H.expect(#powers == 2 and fields(powers[2]) == "Blessing,skyshards,primordial", "primordial_power_used by a Primordial")

	-- Bob and Carol leave
	Emulator.removeClient(bob)
	Emulator.run(1)
	local quits = customs("player_quit", b)
	H.expect(#quits == 1 and fields(quits[1]) == "skyshards,Cataclysm,true", "player_quit: Cataclysm, was a Primordial")
	H.expect(#customs("bot_replaced_leaver", b) == 0, "no bot takes over an eliminated nation")
	Emulator.removeClient(carol)
	Emulator.run(1)
	quits = customs("player_quit", c)
	H.expect(#quits == 1 and fields(quits[1]) == "skyshards,Cataclysm,false", "Carol's player_quit")
	local replaced = customs("bot_replaced_leaver", c)
	H.expect(#replaced == 1 and fields(replaced[1]) == "skyshards,Cataclysm,", "bot_replaced_leaver for Carol's nation")
	H.expect(replaced[1].args[2] == quits[1].args[2] and quits[1].args[2] >= 20, "both at the minute she left")

	-- the limits: known names only, at most 3 fields, no player names anywhere, nothing dropped
	local known = {}
	for _, name in Telemetry.CUSTOM_EVENTS do
		known[name] = true
	end
	local clean = true
	for _, r in log do
		if r.method == "LogCustomEvent" and not known[r.args[1]] then
			clean = false
		end
		for _, arg in r.args do
			local values = if type(arg) == "table" then arg else { arg }
			local count = 0
			for _, v in values do
				count += 1
				if type(v) == "string" and (string.find(v, "Alice") or string.find(v, "Bob") or string.find(v, "Carol")) then
					clean = false
				end
			end
			if type(arg) == "table" and count > 3 then
				clean = false
			end
		end
	end
	H.expect(clean, string.format("all %d events use known names, at most 3 fields and no player names", #log))
	local dropped = false
	for _, line in Emulator.log() do
		dropped = dropped or string.find(line, "over budget", 1, true) ~= nil
	end
	H.expect(not dropped, "nothing was dropped by the per-minute budget")
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	run = run,
}
