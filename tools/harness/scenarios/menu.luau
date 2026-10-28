--!nocheck
-- The start menu (docs/DESIGN.md "Match structure"). A fresh public server: Alice arrives at the menu (Play online,
-- Singleplayer, How to play) over the first pick; she chooses Play online and so picks the map alone, no vote. Bob
-- arrives on a 667×375 phone while she picks: his menu says Alice is picking, Singleplayer shows three map cards,
-- How to play has five pages; after Play online he waits on "Alice is picking the map" and the server refuses his
-- pick. Alice's pick starts the draft on her map with both of them, and everyone hears it. Mid-match Carol arrives
-- on a big tablet: the menu doesn't seat her, Singleplayer's second tap calls the sandbox entry (Studio can't
-- teleport: the menu says so), and Play online takes over a bot's nation at once. Analytics: menu_shown,
-- menu_choice and first_pick.

local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	local Lobby = require("../../../src/shared/Sim/Lobby")
	local log = Emulator.analytics
	local function customs(name: string, userId: number?)
		local out = {}
		for _, r in log do
			if r.method == "LogCustomEvent" and r.args[1] == name and (userId == nil or r.userId == userId) then
				table.insert(out, r)
			end
		end
		return out
	end
	local function fields(r): string
		local f = r.args[#r.args] or {}
		local keys = Emulator.roblox.Enum.AnalyticsCustomFieldKeys
		return table.concat({ f[keys.CustomField01.Name] or "", f[keys.CustomField02.Name] or "" }, ",")
	end
	local function choices(userId: number): string
		local out = {}
		for _, r in customs("menu_choice", userId) do
			table.insert(out, fields(r))
		end
		return table.concat(out, " ")
	end
	local function heard(client, needle: string)
		local box = { told = false }
		client.dm:GetService("ReplicatedStorage").Remotes.Notify.OnClientEvent:Connect(function(_kind, text)
			box.told = box.told or string.find(text, needle, 1, true) ~= nil
		end)
		return box
	end

	local LobbyService = H.server("Services.LobbyService")
	Emulator.run(1)
	H.expect(LobbyService.phase() == "Lobby" and LobbyService.state().first, "a fresh server opens a first pick")
	H.expect(H.logged("the first to choose Play online picks the map"), "the server says so")

	-- Alice arrives: the menu, over the first pick
	local alice = Emulator.addClient("Alice")
	Emulator.run(2.5) -- the vote cards' thumbnails behind it get painted
	local aliceMenu = H.client(alice, "UI.Menu")
	H.expect(aliceMenu.isOpen(), "Alice arrives at the start menu")
	for _, text in { "Play online", "Singleplayer", "How to play" } do
		H.expect(H.within(alice, "Menu", text), "it offers " .. text)
	end
	H.expect(H.within(alice, "Menu", "The first to tap Play online picks the map"), "and says what Play online does")
	H.expect(#LobbyService.state().queue == 0, "nobody is in line until someone chooses Play online")
	H.shot(alice, "menu")

	-- Play online: Alice is first in line, so she picks the map
	Emulator.press(alice, "Play online")
	Emulator.run(1)
	H.expect(not aliceMenu.isOpen(), "the server closes her menu")
	H.expect(Lobby.chooser(LobbyService.state()) == alice.serverPlayer.UserId, "the server makes Alice the chooser")
	H.expect(Emulator.findText(alice, "Pick the map") ~= nil, "she is asked to pick the map")
	H.expect(Emulator.findText(alice, "Vote for the map") == nil, "no vote")
	H.shot(alice, "pick_map")

	-- Bob arrives on a small phone while she picks
	local bob = Emulator.addClient("Bob", Emulator.roblox.Vector2.new(667, 375))
	Emulator.run(1.5)
	local bobMenu = H.client(bob, "UI.Menu")
	H.expect(bobMenu.isOpen(), "Bob arrives at the menu too")
	H.expect(H.within(bob, "Menu", "Alice is picking the map"), "it says Alice is picking the map")
	H.expect(H.server("Services.MenuService").isOnline(bob.serverPlayer) == false, "he hasn't joined yet")
	H.shot(bob, "menu_phone")

	-- Singleplayer: three map cards (Bob looks, then goes back)
	Emulator.press(bob, "Singleplayer")
	Emulator.run(1)
	for _, id in { "earth", "eldmoor", "skyshards" } do
		H.expect(H.within(bob, "World_" .. id, ""), "Singleplayer shows a card for " .. id)
	end
	Emulator.press(bob, "World_eldmoor")
	Emulator.run(0.3)
	H.expect(H.within(bob, "Menu", "Play Eldmoor"), "the first tap only chooses the map")
	H.shot(bob, "singleplayer_phone")
	H.pressIn(bob, "Menu", "✕")
	Emulator.run(0.3)

	-- How to play: five pages, round and round
	Emulator.press(bob, "How to play")
	Emulator.run(0.3)
	H.expect(H.textOf(bob, "Page") == "1/5", "How to play opens on page 1 of 5")
	H.shot(bob, "guide_phone")
	local titles = {}
	for _ = 1, 5 do
		table.insert(titles, H.textOf(bob, "GuideTitle") or "?")
		Emulator.press(bob, "NextPage")
		Emulator.run(0.2)
	end
	H.expect(
		table.concat(titles, ",") == "Grow,War and sieges,Allies,Primordial powers,How to win",
		"five pages: grow, war, allies, powers, how to win"
	)
	H.expect(H.textOf(bob, "Page") == "1/5", "and back to the first")
	Emulator.press(bob, "PrevPage")
	Emulator.run(0.3)
	H.expect(H.within(bob, "Menu", "Hold 50% of the land"), "the last page says how to win")
	H.shot(bob, "guide_win_phone")
	H.pressIn(bob, "Menu", "✕")
	Emulator.run(0.3)
	H.expect(H.within(bob, "Menu", "Play online"), "✕ goes back to the three choices")

	-- Bob chooses Play online: he waits in line and sees who is picking
	Emulator.press(bob, "Play online")
	Emulator.run(1)
	H.expect(not bobMenu.isOpen(), "Bob's menu closes")
	H.expect(LobbyService.state().queue[2] == bob.serverPlayer.UserId, "he is second in line")
	H.expect(Emulator.findText(bob, "Alice is picking the map") ~= nil, "he sees who is picking")
	H.shot(bob, "waiting_phone")
	H.client(bob, "Intents").vote("earth") -- a forged pick
	Emulator.run(1.2)
	H.expect(next(LobbyService.state().votes) == nil, "the server refuses Bob's pick")

	-- Alice picks Eldmoor with two taps: the draft starts at once on it, with both of them
	local bobHeard = heard(bob, "Alice picked Eldmoor")
	Emulator.press(alice, "Card_eldmoor")
	Emulator.run(0.2)
	H.expect(Emulator.findText(alice, "Tap again") ~= nil, "the first tap only chooses the card")
	Emulator.press(alice, "Card_eldmoor")
	Emulator.run(1.5)
	local state = H.state()
	H.expect(LobbyService.phase() == "Pick" and state.mapId == "eldmoor", "her pick starts the draft on Eldmoor")
	H.expect(#LobbyService.state().order == 2, "Alice and Bob are in the draft")
	H.expect(H.logged("[server] first pick: Alice picked eldmoor"), "the server says who picked what")
	H.expect(bobHeard.told, "Bob hears it")
	H.shot(bob, "result_phone")

	local deadline = Emulator.now() + 40
	while state.phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(state.phase == "Peace", "the match starts in Peace")
	H.expect(H.myNation(alice) ~= 0 and H.myNation(bob) ~= 0, "both have a nation")

	-- Carol arrives mid-match on a big tablet: the menu, and no nation behind it
	local carol = Emulator.addClient("Carol", Emulator.roblox.Vector2.new(1366, 1024))
	Emulator.run(2)
	local carolId = carol.serverPlayer.UserId
	H.expect(H.client(carol, "UI.Menu").isOpen(), "Carol arrives at the menu")
	H.expect(H.myNation(carol) == 0 and state.seats[carolId] == nil, "she isn't seated behind it")
	H.expect(H.within(carol, "Menu", "A match is on"), "the menu says a match is on")
	H.shot(carol, "menu_tablet")

	-- Singleplayer: the second tap on a map calls the sandbox entry
	local carolHeard = heard(carol, "Singleplayer needs a live server")
	Emulator.press(carol, "Singleplayer")
	Emulator.run(1)
	Emulator.press(carol, "World_skyshards")
	Emulator.press(carol, "World_skyshards")
	Emulator.run(1)
	H.expect(H.logged("[sandbox] Carol is off to a sandbox world (skyshards)"), "it calls the sandbox entry")
	H.expect(H.logged("[sandbox] no teleports in Studio: Carol stays here"), "Studio can't teleport")
	H.expect(carolHeard.told and H.within(carol, "Menu", "Singleplayer needs a live server"), "the menu says why")
	H.shot(carol, "singleplayer_tablet")

	-- back, then Play online: a bot's nation at once
	H.pressIn(carol, "Menu", "✕")
	Emulator.run(0.2)
	Emulator.press(carol, "Play online")
	Emulator.run(0.5)
	local nation = H.myNation(carol)
	H.expect(nation ~= 0 and state.nations[nation].userId == carolId, "Play online takes over a bot's nation at once")
	H.expect(not H.client(carol, "UI.Menu").isOpen(), "and closes the menu")
	H.shot(carol, "playing_tablet")

	-- analytics: the menu shown on every arrival, each choice, and the first pick
	local a, b = alice.serverPlayer.UserId, bob.serverPlayer.UserId
	H.expect(#customs("menu_shown") == 3, "menu_shown for each arrival")
	H.expect(fields(customs("menu_shown", a)[1]) == "first,public", "Alice's during the first pick")
	H.expect(fields(customs("menu_shown", carolId)[1]) == "match,public", "Carol's mid-match")
	H.expect(choices(a) == "online,first", "Alice chose Play online")
	H.expect(choices(b) == "singleplayer,first guide,first online,first", "Bob looked around, then Play online")
	H.expect(choices(carolId) == "singleplayer,match online,match", "Carol tried Singleplayer, then Play online")
	local picks = customs("first_pick")
	H.expect(#picks == 1 and picks[1].userId == a and fields(picks[1]) == "eldmoor,picked", "first_pick: Alice's")
	H.expect(#customs("map_vote") == 0, "no map_vote: there was no vote")
end

return {
	lobby = true, -- the first pick is a Lobby
	attributes = { Menu = true },
	run = run,
}
