--!nocheck
-- Phase 4: daily and weekly quests, the login calendar and the play streak. The 📜 button in the Lobby, a quest
-- finished in a match (recruit 5 regiments) and shown on Results, claimed, a daily quest rerolled; then DevDay moves
-- the server's day on: new quests, and the calendar and streak move on the next finished match (a missed day is
-- covered), up to the streak flame in the nations list.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	-- press a button inside one quest row (several rows show "Claim" or a reroll)
	local pressIn = H.pressIn
	local LobbyService = H.server("Services.LobbyService")
	local Data = H.server("Services.PlayerDataService")
	local workspace = Emulator.server.dm:GetService("Workspace")
	-- wait out the vote and the draft: the match starts in Peace with Alice seated
	local function waitForMatch(client)
		local deadline = Emulator.now() + 200
		while (LobbyService.active() or H.state().phase ~= "Peace" or H.myNation(client) == 0) and Emulator.now() < deadline do
			Emulator.run(1)
		end
		Emulator.run(1)
		H.expect(H.state().phase == "Peace" and H.myNation(client) ~= 0, "a match started with Alice in it")
	end
	-- hand Alice's nation half the land: domination, Results, the reward
	local function win(client)
		local state = H.state()
		local A = H.myNation(client)
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
		Emulator.run(2.5)
		H.expect(state.result ~= nil and H.client(client, "ProfileState").reward() ~= nil, "Alice won and got her reward")
	end
	local function calendarLine(report)
		for _, line in report.reward.lines do
			if line.kind == "Calendar" then
				return line
			end
		end
		return nil
	end

	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local player = alice.serverPlayer
	local QuestState = H.client(alice, "QuestState")
	local view = QuestState.view()
	H.expect(view ~= nil and #view.daily == 3 and #view.weekly == 3, "Alice has 3 daily and 3 weekly quests")
	H.expect(view.daily[1].tier == "Easy" and view.daily[2].tier == "Medium" and view.daily[3].tier == "Hard", "one easy, one medium, one hard")
	local data = Data.data(player)
	local firstIds = {}
	for _, q in data.quests.daily do
		table.insert(firstIds, q.id)
	end

	-- the Lobby's scroll button opens the Quests screen
	Emulator.run(2)
	H.shot(alice, "lobby_button")
	Emulator.press(alice, "QuestsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Daily quests") ~= nil, "the Quests screen opens from the Lobby")
	H.expect(Emulator.findText(alice, "1 free reroll today") ~= nil, "with today's free reroll")
	H.shot(alice, "lobby_quests")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the easy quest is "Recruit 5 regiments" for this test
	local recruitKey
	Data.update(player, function(d)
		local q = d.quests.daily[1]
		q.id = "recruit5"
		q.key = "d" .. q.day .. "-recruit5"
		recruitKey = q.key
	end)
	H.server("Services.QuestService").sendView(player)
	waitForMatch(alice)

	-- in the match, the quests open from the 🌍 nations drawer (the top bar has no room for another button)
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.3)
	Emulator.press(alice, "📜 Quests")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Recruit 5 regiments") ~= nil, "the Quests screen opens from the nations drawer")
	H.shot(alice, "match_quests")
	Emulator.press(alice, "✕")
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.3)

	-- recruit 5 regiments at the capital, then win
	local state = H.state()
	local nation = state.nations[H.myNation(alice)]
	nation.gold, nation.manpower = 400, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for _ = 1, 5 do
		Emulator.press(alice, "Regiment")
		Emulator.run(1.2)
	end
	win(alice)
	Emulator.run(1)
	local report = H.client(alice, "ProfileState").reward()
	local cal = calendarLine(report)
	H.expect(cal ~= nil and cal.glory == 25, "the day's first finished match pays the calendar's first step (25 Glory)")
	H.expect(Emulator.findText(alice, "Play calendar 1/7") ~= nil, "on the Results breakdown")
	H.expect(Emulator.findText(alice, "Recruit 5 regiments: done!") ~= nil, "the Results screen shows the quest finished")
	H.expect(Emulator.findText(alice, "to claim") ~= nil, "and a Quests button with quests to claim")
	H.shot(alice, "results_quests")

	-- claim it from the Results screen's Quests button
	local xp0, glory0 = data.xp, data.glory
	Emulator.press(alice, "to claim")
	Emulator.run(0.5)
	H.shot(alice, "quest_done")
	pressIn(alice, "Quest_recruit5", "Claim")
	Emulator.run(1)
	local claimed
	for _, q in data.quests.daily do
		if q.key == recruitKey then
			claimed = q.claimed
		end
	end
	H.expect(claimed == true, "the quest is claimed")
	H.expect(data.xp == xp0 + 100 and data.glory >= glory0 + 30, "it paid 100 XP and 30 Glory")
	H.expect(
		H.within(alice, "Quest_recruit5", "Recruit 5 regiments") and H.iconIn(alice, "Quest_recruit5", "check"),
		"the row shows it claimed"
	)
	H.client(alice, "Intents").claimQuest(recruitKey) -- the row has no Claim button any more: ask the server anyway
	Emulator.run(0.5)
	H.expect(data.xp == xp0 + 100, "a second claim pays nothing")

	-- reroll the hard quest (the free one)
	local hard = data.quests.daily[3]
	local hardId = hard.id
	pressIn(alice, "Quest_" .. hardId, "Free", "reroll")
	Emulator.run(1)
	H.expect(data.quests.daily[3].id ~= hardId and data.quests.rerollsUsed == 1, "the hard quest was rerolled for another")
	H.expect((Emulator.findText(alice, "Rerolls: 100") ~= nil), "the next reroll costs 100 Glory")
	H.shot(alice, "rerolled")
	Emulator.press(alice, "✕")

	-- the next day (DevDay): new daily quests next to yesterday's unfinished ones; the calendar waits for a match
	workspace:SetAttribute("DevDay", 1)
	Emulator.run(7)
	view = QuestState.view()
	H.expect(#view.daily == 5, "yesterday's 2 unfinished quests stay next to today's 3 (the claimed one went)")
	H.expect(view.calendar.step == 1 and not view.calendar.playedToday, "the calendar waits on step 1 until Alice plays")
	H.expect(view.freeRerolls == 1, "a new free reroll")
	waitForMatch(alice)
	win(alice)
	report = H.client(alice, "ProfileState").reward()
	cal = calendarLine(report)
	H.expect(cal ~= nil and cal.glory == 25 and data.login.step == 2, "day 2: the calendar's second step (25 Glory)")
	H.expect(data.login.streak == 2, "a 2-day play streak")

	-- a day off, then a third play day: the missed day is covered, the streak reaches 3 (a flame)
	workspace:SetAttribute("DevDay", 2)
	Emulator.run(7)
	H.expect(QuestState.view().streak == 2, "after one missed day the streak still stands")
	waitForMatch(alice)
	win(alice)
	report = H.client(alice, "ProfileState").reward()
	cal = calendarLine(report)
	H.expect(cal ~= nil and cal.glory == 50 and data.login.step == 3, "the calendar paused over the missed day: step 3 (50 Glory)")
	H.expect(data.login.streak == 3 and data.login.best == 3, "the streak is 3 days")
	Emulator.run(1)
	Emulator.press(alice, "Quests")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "3-day play streak") ~= nil, "the Quests screen shows the streak")
	H.expect(Emulator.findText(alice, "Flame") ~= nil, "and the flame it earned")
	H.shot(alice, "calendar_streak")
	Emulator.press(alice, "✕")
	alice.localPlayer.PlayerGui.Results.Enabled = false -- the nations list under the Results panel
	if Emulator.findText(alice, "Not now") then
		Emulator.press(alice, "Not now") -- the starter-pack offer (after the 2nd match) is the shop's
	end
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.5)
	H.expect(H.iconShown(alice, "fire"), "Alice's nation shows the streak flame in the nations list")
	H.shot(alice, "nations_flame")
	local saved = H.saved(player.UserId).Data
	H.expect(saved.login.step == 3 and saved.login.streak == 3, "the calendar and streak are saved")
	H.expect(#firstIds == 3, "the first day's quests: " .. table.concat(firstIds, ", "))
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	run = run,
}
