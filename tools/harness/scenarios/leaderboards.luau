--!nocheck
-- Phase 5: leaderboards and achievements. Four players (Alice and Bob are friends; Alice has a friend, Zed, who
-- isn't here) play a public match through the Lobby. Alice wore last week's Warlord frame in, wins by Domination:
-- the weekly board (an OrderedDataStore per week) gets everyone's points in one batch, the friends view shows only
-- Alice's friends, and Domination pays 300 Glory and the title "the Dominant", which she wears into the next match.
-- Then a new week: fresh boards, and last week's top wear the Warlord frame.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local shown = H.shown

local function run()
	local Login = require("../../../src/shared/Sim/Login")
	local LobbyService = H.server("Services.LobbyService")
	local Data = H.server("Services.PlayerDataService")
	local workspace = Emulator.server.dm:GetService("Workspace")
	local function waitForMatch(client)
		local deadline = Emulator.now() + 240
		while (LobbyService.active() or H.state().phase ~= "Peace" or H.myNation(client) == 0) and Emulator.now() < deadline do
			Emulator.run(1)
		end
		Emulator.run(1)
		H.expect(H.state().phase == "Peace" and H.myNation(client) ~= 0, "a match started with " .. client.name .. " in it")
	end
	local function row(rows, name)
		for _, r in rows do
			if r.name == name then
				return r
			end
		end
		return nil
	end

	Emulator.run(1)
	local week = Login.weekOf(H.server("Services.ProgressionService").today())
	local ALICE, BOB, CAROL, DAVE, ZED, STRANGER = 7001, 7002, 7003, 7004, 9001, 9002
	-- last week: Alice made the top 100; this week, before the match: Zed (Alice's friend) and a stranger have points
	local Boards = H.server("Services.LeaderboardService")
	local CONQUEST, LEVEL = Boards.CONQUEST_STORE, Boards.LEVEL_STORE
	Emulator.orderedStores[CONQUEST .. "/W" .. (week - 1)] = { [tostring(ALICE)] = 25 }
	Emulator.orderedStores[CONQUEST .. "/W" .. week] = { [tostring(ZED)] = 12, [tostring(STRANGER)] = 30 }
	Emulator.displayNames[ZED] = "Zed"
	Emulator.displayNames[STRANGER] = "Stranger"
	Emulator.friends[ALICE] = { BOB, ZED }
	Emulator.friends[BOB] = { ALICE }
	local alice = Emulator.addClient("Alice", nil, ALICE)
	local bob = Emulator.addClient("Bob", nil, BOB)
	local carol = Emulator.addClient("Carol", nil, CAROL)
	local dave = Emulator.addClient("Dave", nil, DAVE)
	Emulator.run(3)
	-- Studio keeps its own boards, like its saves: a test session never opens the live ones
	for id in Emulator.orderedStores do
		H.expect(string.find(id, "^Conquest/") == nil and string.find(id, "^Level/") == nil, "Studio never touches the live boards (" .. id .. ")")
	end
	local trophies = H.client(alice, "TrophyState")
	H.expect(trophies.achievements() ~= nil and #trophies.achievements().list == 30, "Alice sees her 30 achievements")
	local boards = trophies.boards()
	H.expect(boards ~= nil and boards.week == week, "and this week's boards")
	H.expect(boards.warlord and H.client(alice, "ShopState").owns("frame_warlord"), "last week's top 100: Alice wears the Warlord frame")
	H.expect(not H.client(bob, "ShopState").owns("frame_warlord"), "Bob wasn't in it")
	for _, id in Emulator.friendCalls do
		H.expect(id == ALICE or id == BOB or id == CAROL or id == DAVE, "the friends list is read only for a player's own friends")
	end

	-- the Lobby's trophy button, next to the cart and the scroll, opens the Trophies screen
	Emulator.run(2)
	H.shot(alice, "lobby_button")
	Emulator.press(alice, "TrophiesButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "0 of 30 earned") ~= nil, "the Trophies screen opens from the Lobby")
	H.shot(alice, "lobby_trophies")
	Emulator.press(alice, "Tab" .. "Weekly")
	Emulator.run(0.3)
	-- the board was read when the server started (empty then); the points added since show at the next read
	H.expect(Emulator.findText(alice, "No points yet this week") ~= nil, "the weekly board, as the server last read it")
	Emulator.press(alice, "✕")

	-- the match: Alice equips the Warlord frame, then wins by Domination
	H.client(alice, "Intents").equip("frame_warlord")
	waitForMatch(alice)
	H.expect(Data.data(alice.serverPlayer).equipped.Frame == "frame_warlord", "Alice wears the Warlord frame in the match")
	local state = H.state()
	local humans = 0
	for _ in state.seats do
		humans += 1
	end
	H.expect(humans == 4 and not state.setup.private, "a public match with 4 players: it counts")
	local glory0 = Data.data(alice.serverPlayer).glory
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
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Alice won by Domination")

	-- achievements: Domination pays 300 Glory and its title, shown on the Results screen
	local data = Data.data(alice.serverPlayer)
	H.expect(data.achievements.domination == 1 and data.owned.title_dominant == true, "Domination is earned, with its title")
	local report = H.client(alice, "ProfileState").reward()
	local achievementGlory = 0
	for _, line in report.reward.lines do
		if line.kind == "Achievement" then
			achievementGlory += line.glory
		end
	end
	H.expect(achievementGlory >= 300, "the Results breakdown pays it (" .. achievementGlory .. " Glory from achievements)")
	H.expect(data.glory >= glory0 + 300, "into Alice's Glory")
	H.expect(table.find(trophies.achievements().recent, "domination") ~= nil, "Alice's view lists it as just unlocked")
	H.expect(Emulator.findText(alice, "Unlocked: ") ~= nil and Emulator.findText(alice, "Domination") ~= nil, "the Results screen says so")
	H.expect(H.iconText(alice, "trophy", "Achievements", "Results"), "with an achievement line in the breakdown")
	H.shot(alice, "results")

	-- the weekly board: one batch of writes at Results, then a fresh read
	Emulator.run(2)
	local scores = Emulator.orderedStores[CONQUEST .. "/W" .. week]
	H.expect(scores[tostring(ALICE)] == 10, "Alice won: 10 conquest points on this week's board")
	for _, client in { bob, carol, dave } do
		H.expect((scores[tostring(client.serverPlayer.UserId)] or 0) >= 1, client.name .. " got points for their place")
	end
	H.expect(Emulator.orderedCalls.IncrementAsync == 4, "one write per player (" .. tostring(Emulator.orderedCalls.IncrementAsync) .. ")")
	H.expect(Emulator.orderedStores[LEVEL .. "/global"][tostring(ALICE)] == data.xp, "the level board has Alice's XP")
	boards = trophies.boards()
	H.expect(boards.myPoints == 10 and boards.myRank == 3, "Alice: 10 points, 3rd behind the stranger (30) and Zed (12)")
	H.expect(row(boards.weekly, "Alice") ~= nil and row(boards.weekly, "Carol") ~= nil, "everyone is on the weekly board")
	local friendNames = {}
	for _, r in boards.friends do
		table.insert(friendNames, r.name)
	end
	H.expect(#boards.friends == 3 and row(boards.friends, "Zed") and row(boards.friends, "Bob") and row(boards.friends, "Alice"),
		"Alice's friends view: Alice, Bob and Zed (" .. table.concat(friendNames, ", ") .. ")")
	H.expect(row(boards.friends, "Carol") == nil and row(boards.friends, "Stranger") == nil, "nobody else")
	H.expect(#H.client(bob, "TrophyState").boards().friends == 2, "Bob's friends view: Bob and Alice")
	H.expect(row(boards.level, "Alice").level == data.level, "the global level board shows Alice's level")

	-- the Trophies screen from the Results screen: achievements, weekly, friends and level boards
	Emulator.press(alice, "TrophiesButton")
	Emulator.run(0.5)
	H.expect(
		H.within(alice, "Achievement_domination", "Domination") and H.iconIn(alice, "Achievement_domination", "check"),
		"the Trophies screen opens from Results, Domination done"
	)
	H.shot(alice, "achievements")
	Emulator.press(alice, "TitleButton")
	Emulator.run(1)
	H.expect(data.equipped.Title == "title_dominant", "Alice wears the title the Dominant")
	H.expect(Emulator.findText(alice, "the Dominant") ~= nil, "the title button shows it")
	Emulator.press(alice, "Tab" .. "Weekly")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "You: 10 pts") ~= nil, "the weekly board says where Alice stands")
	H.shot(alice, "weekly")
	Emulator.press(alice, "Tab" .. "Friends")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "Zed") ~= nil and Emulator.findText(alice, "Carol") == nil, "the friends board shows only friends")
	H.shot(alice, "friends")
	Emulator.press(alice, "Tab" .. "Level")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "Lv " .. data.level) ~= nil, "the level board")
	H.shot(alice, "level")
	Emulator.press(alice, "✕")

	-- the next match: the title under Alice's name, the Warlord frame round it
	waitForMatch(alice)
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "the Dominant") ~= nil, "the nations list shows Alice's title")
	H.shot(alice, "nations_title")
	Emulator.press(alice, "NationsButton")
	-- the shop's frames: Warlord worn, Centurion earned only (never sold)
	Emulator.press(alice, "ShopButton")
	Emulator.run(0.5)
	Emulator.press(alice, "Tab_Frame")
	Emulator.run(0.5)
	H.expect(
		H.within(alice, "Card_frame_centurion", "Trophy") and H.iconIn(alice, "Card_frame_centurion", "trophy"),
		"the shop shows the Centurion frame: earned, not for sale"
	)
	H.shot(alice, "shop_frames")
	Emulator.press(alice, "NextPage")
	Emulator.run(0.5)
	H.expect(H.within(alice, "Card_frame_warlord", "Equipped"), "and the Warlord frame Alice wears")
	H.shot(alice, "shop_warlord")
	Emulator.press(alice, "✕")

	-- a new week (DevDay): fresh boards; last week's top 100 (all four of them) wear the Warlord frame
	workspace:SetAttribute("DevDay", 7)
	Emulator.run(Config.Leaderboards.RefreshSeconds + 5)
	boards = trophies.boards()
	H.expect(boards.week == week + 1 and boards.myPoints == 0, "a new week: Alice starts at 0 points")
	H.expect(H.client(bob, "ShopState").owns("frame_warlord") and H.client(bob, "TrophyState").boards().warlord, "Bob made last week's top 100: the Warlord frame")
	H.expect(H.client(alice, "ShopState").owns("frame_warlord"), "Alice keeps it for another week")
	local reads = Emulator.orderedCalls.GetSortedAsync or 0
	H.expect(reads <= 20, "sorted reads stay within budget (" .. reads .. " in " .. math.floor(Emulator.now()) .. " s)")
end

return {
	lobby = true, -- the 🏆 button is in the Lobby
	run = run,
}
