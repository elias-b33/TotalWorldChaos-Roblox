--!nocheck
-- Phase 4: the Lobby. Three players vote (majority wins), the draft gives everyone the nation they tapped, a
-- player joining mid-draft gets one when his turn runs out, bots keep the rest, and the match starts in Peace.
-- After Results everyone stays and the next-map vote opens again.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	local Lobby = require("../../../src/shared/Sim/Lobby")
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local LobbyService = H.server("Services.LobbyService")
	H.expect(LobbyService.phase() == "Lobby", "the server opens the Lobby")
	H.expect(Emulator.findText(alice, "Vote for the map") ~= nil, "Alice sees the map vote")
	Emulator.run(2) -- the thumbnails are painted
	H.shot(alice, "vote")

	-- two taps per vote: the first chooses a card, the second votes
	Emulator.press(alice, "Card_eldmoor")
	Emulator.run(0.2)
	H.expect(Emulator.findText(alice, "Tap again") ~= nil, "the first tap only chooses the card")
	Emulator.press(alice, "Card_eldmoor")
	Emulator.press(bob, "Card_eldmoor")
	Emulator.press(bob, "Card_eldmoor")
	Emulator.press(carol, "Card_earth")
	Emulator.press(carol, "Card_earth")
	Emulator.run(1.5)
	local tally = Lobby.tally(LobbyService.state())
	H.expect(tally.eldmoor == 2 and tally.earth == 1, "the server counted Eldmoor 2, Earth 1")
	H.expect(Emulator.findText(alice, "Your vote") ~= nil, "Alice sees her vote")
	H.expect(H.hasText(carol, "Votes", "2"), "everyone sees the tally")
	H.shot(carol, "voted")

	-- the vote ends: the draft runs on Eldmoor
	local deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local state = H.state()
	H.expect(LobbyService.phase() == "Pick" and state.mapId == "eldmoor", "Eldmoor won and the draft starts on it")
	H.expect(state.phase == "Pick" and state.tick == 0, "the match waits in Pick at tick 0")
	Emulator.run(1.5)
	H.expect(Emulator.findText(alice, "Vote for the map") == nil, "the vote screen closed")

	local byUser = {
		[alice.serverPlayer.UserId] = alice,
		[bob.serverPlayer.UserId] = bob,
		[carol.serverPlayer.UserId] = carol,
	}
	local want = { [alice] = 4, [bob] = 6, [carol] = 9 }
	local dave
	for turn = 1, 3 do
		local client = byUser[Lobby.current(LobbyService.state())]
		H.expect(client ~= nil, "turn " .. turn .. " belongs to one of the voters")
		H.expect(Emulator.findText(client, "Your turn") ~= nil, client.name .. " is told it's their turn")
		local nation = state.nations[want[client]]
		if client == bob then
			Emulator.press(client, nation.name) -- straight from the list
		else
			H.tapProvince(client, nation.capital, false) -- on the map, then confirm
			H.expect(Emulator.findText(client, "Pick " .. nation.name) ~= nil, "tapping its land offers " .. nation.name)
			if turn == 1 then
				H.shot(client, "draft")
			end
			Emulator.press(client, "Pick " .. nation.name)
		end
		Emulator.run(1.5)
		H.expect(state.nations[want[client]].userId == client.serverPlayer.UserId, client.name .. " took " .. nation.name)
		if turn == 2 then
			dave = Emulator.addClient("Dave") -- joins mid-draft: last in the order
			Emulator.run(1)
			H.expect(#LobbyService.state().order == 4, "Dave joined the end of the draft order")
		end
	end
	H.shot(dave, "draft_dave")

	-- Dave lets his turn run out: he gets a random free nation, bots keep the rest, the match starts
	deadline = Emulator.now() + 20
	while state.phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(state.phase == "Peace" and state.tick <= 2, "the match started in Peace at tick 0")
	for client, id in want do
		H.expect(H.myNation(client) == id, client.name .. " plays the nation they tapped")
	end
	local daveNation = H.myNation(dave)
	H.expect(daveNation ~= 0 and state.nations[daveNation].userId == dave.serverPlayer.UserId, "Dave got a nation")
	local bots = 0
	for _, n in state.nations do
		if n.controller == "Bot" then
			bots += 1
		end
	end
	H.expect(bots == 6, "bots took the other 6 nations")
	H.expect(Emulator.findText(alice, "Your turn") == nil and Emulator.findText(alice, "is picking") == nil, "draft UI gone")
	H.shot(alice, "match_start")

	-- Results, then the next-map vote with everyone still here
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		if p.owner == 4 then
			given += 1
		end
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= 4 and p.terrain ~= "Mountain" then
			p.owner = 4
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil, "Alice won by domination")
	Emulator.run(31)
	H.expect(LobbyService.phase() == "Lobby", "after Results the next-map vote opens")
	H.expect(#Emulator.server.dm:GetService("Players"):GetPlayers() == 4, "everyone stayed in the server")
	for _, client in { alice, bob, carol, dave } do
		H.expect(Emulator.findText(client, "Vote for the map") ~= nil, client.name .. " sees the next-map vote")
	end
	H.shot(bob, "next_vote")
	for _, client in { alice, bob, carol } do
		Emulator.press(client, "Card_skyshards")
		Emulator.press(client, "Card_skyshards")
	end
	deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(H.state() ~= state and H.state().mapId == "skyshards", "Skyshards won the next vote")
	-- nobody picks this time: every turn runs out and the server picks for them
	deadline = Emulator.now() + 40
	while H.state().phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(H.state().phase == "Peace", "the second match started")
	for _, client in { alice, bob, carol, dave } do
		H.expect(H.myNation(client) ~= 0, client.name .. " was given a nation")
	end
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	run = run,
}
