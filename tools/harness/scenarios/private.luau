--!nocheck
-- Phase 4: private server settings. Olivia owns the server (Workspace "PrivateServerOwner"): in the Lobby she sets
-- a 15-minute match with 5 Hard bots, powers off, Eldmoor, and puts herself and Pete in one team. Pete can't change
-- anything. The match plays those settings and ends at 15:00, paying half (custom rules, 2 players).

local Emulator = require("../Emulator")
local H = require("../H")
local PRIVATE_OWNER = H.PRIVATE_OWNER

local function run()
	Emulator.run(1)
	local olivia = Emulator.addClient("Olivia", nil, PRIVATE_OWNER)
	local pete = Emulator.addClient("Pete")
	Emulator.run(2)
	local LobbyService = H.server("Services.LobbyService")
	H.expect(LobbyService.phase() == "Lobby", "the private server opens the Lobby")
	H.expect(LobbyService.state().owner == PRIVATE_OWNER, "the server knows its owner")
	H.expect(Emulator.findText(olivia, "Settings") ~= nil, "Olivia, the owner, sees ⚙ Settings")
	H.expect(Emulator.findText(pete, "Settings") == nil, "Pete doesn't")
	H.expect(Emulator.findText(pete, "Private server") ~= nil, "everyone sees the settings summary")
	H.expect(not H.logged("off to the tutorial"), "a private server sends nobody to the tutorial (friends stay)")
	Emulator.run(2)
	H.shot(pete, "vote_summary")

	-- Pete tries anyway: the server refuses
	H.client(pete, "Intents").setting("minutes", 15)
	Emulator.run(1.5)
	H.expect(LobbyService.state().settings.minutes == 25, "Pete can't change the match length")
	H.expect(Emulator.findText(pete, "Only the server's owner") ~= nil, "Pete is told why")

	Emulator.press(olivia, "SettingsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(olivia, "Private server settings") ~= nil, "the settings sheet opens")
	H.expect(Emulator.findText(olivia, "full XP and Glory") == nil, "two players: the sheet says the rewards are half")
	H.shot(olivia, "settings_default")
	local presses = { "Setting_minutes_15", "Setting_difficulty_Hard", "Setting_powers_false", "Setting_map_eldmoor" }
	table.insert(presses, "Setting_events_false") -- the EU4 pack's event cards, beside Insults on one row
	for _, name in presses do
		Emulator.press(olivia, name)
	end
	for _ = 1, 4 do
		Emulator.press(olivia, "BotsLess")
		Emulator.run(1.1) -- each step counts down from the last view
	end
	Emulator.press(olivia, "Team_" .. PRIVATE_OWNER)
	Emulator.press(olivia, "Team_" .. pete.serverPlayer.UserId)
	Emulator.run(1.5)
	local s = LobbyService.state().settings
	H.expect(s.minutes == 15 and s.difficulty == "Hard" and s.powers == false, "15 minutes, Hard bots, powers off")
	H.expect(s.bots == 5 and s.map == "eldmoor", "5 bots, on Eldmoor")
	H.expect(s.events == false and s.diplomacy == true, "no event cards; insults still on")
	H.expect(#s.teams == 2 and s.teams[1].team == 1 and s.teams[2].team == 1, "Olivia and Pete are team 1")
	H.expect(LobbyService.state().locked == "eldmoor", "the map setting locks the vote to Eldmoor")
	H.expect(Emulator.findText(olivia, "custom rules") ~= nil, "the sheet says custom rules pay half")
	H.shot(olivia, "settings_custom")
	Emulator.press(olivia, "SettingsDone")
	Emulator.run(0.5)
	H.expect(
		Emulator.findText(pete, "15 min") ~= nil and Emulator.findText(pete, "5 Hard bots") ~= nil,
		"Pete sees them"
	)
	H.expect(Emulator.findText(pete, "powers off") ~= nil, "including powers off")
	H.expect(Emulator.findText(pete, "no events") ~= nil, "and no events")
	H.shot(pete, "vote_locked")

	-- the vote runs out, nobody picks: the draft gives everyone a nation, then the match plays the settings
	local deadline = Emulator.now() + 120
	while (LobbyService.active() or H.state().phase == "Pick") and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	local state = H.state()
	H.expect(state.mapId == "eldmoor" and state.phase == "Peace", "the match started on Eldmoor in Peace")
	H.expect(state.setup.private and state.setup.settings.minutes == 15, "the match setup carries the settings")
	local nations, bots = 0, 0
	for _, n in state.nations do
		nations += 1
		bots += if n.controller == "Bot" then 1 else 0
	end
	H.expect(nations == 7 and bots == 5, "2 players + 5 bots: the other 3 nations left the map")
	H.expect(H.server("Services.AIService").difficulty() == "Hard", "the bots play Hard")
	local O, P = H.myNation(olivia), H.myNation(pete)
	H.expect(O ~= 0 and P ~= 0 and state.nations[O].allianceId ~= nil, "both players have a nation")
	H.expect(state.nations[O].allianceId == state.nations[P].allianceId, "Olivia and Pete start allied (team 1)")
	H.expect(
		string.find(H.textOf(olivia, "Clock") or "", "^14:5") ~= nil and H.iconShown(olivia, "peace"),
		"the clock counts down from 15:00"
	)
	H.expect(H.textOf(olivia, "Charges") == nil, "no power button with powers off")
	H.shot(olivia, "match_start")

	-- powers are refused, and so is a new alliance (teams are locked)
	local workspace = Emulator.server.dm:GetService("Workspace")
	workspace:SetAttribute("DevTick", 179)
	Emulator.run(1.5)
	-- toasts queue up one after another: wait until this one shows
	local function toastShows(text: string): boolean
		local until_ = Emulator.now() + 12
		while Emulator.findText(olivia, text) == nil and Emulator.now() < until_ do
			Emulator.run(0.5)
		end
		return Emulator.findText(olivia, text) ~= nil
	end
	H.client(olivia, "Intents").power("Blessing", state.nations[O].capital)
	H.expect(toastShows("Powers are off"), "a power is refused: powers are off")
	local other = nil
	for id, n in state.nations do
		if id ~= O and id ~= P and n.controller == "Bot" then
			other = id
		end
	end
	H.client(olivia, "Intents").diplomacy("Ally", other)
	H.expect(toastShows("Teams are set"), "no new alliances: teams are locked")

	-- the Cataclysm at 10:00, the end at 15:00. The clock jumps less than the AFK time (5 min) at a time, and
	-- Olivia gives an order after each jump, so the match still pays her.
	local function jump(tick: number)
		workspace:SetAttribute("DevTick", tick)
		Emulator.run(1.5)
		H.client(olivia, "Intents").develop(state.nations[O].capital)
		Emulator.run(1)
	end
	jump(400)
	jump(599)
	H.expect(state.phase == "Cataclysm", "the Cataclysm starts at 10:00 (the last 5 minutes)")
	jump(850)
	workspace:SetAttribute("DevTick", 897)
	Emulator.run(4)
	H.expect(state.result ~= nil and state.result.endedAt == 15 * 60, "the match ended at 15:00")
	Emulator.run(1)
	local report = H.client(olivia, "ProfileState").reward()
	local half = false
	for _, line in report.reward.lines do
		half = half or line.kind == "CustomRules"
	end
	H.expect(half, "custom rules pay half")
	H.expect(Emulator.findText(olivia, "Private server: half") ~= nil, "the Results screen says so")
	H.shot(olivia, "results")
	Emulator.run(31)
	H.expect(LobbyService.phase() == "Lobby", "the next Lobby opens")
	H.expect(LobbyService.state().settings.minutes == 15, "and keeps the settings")
	H.expect(LobbyService.state().locked == "eldmoor", "including the map")
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	attributes = { PrivateServerOwner = H.PRIVATE_OWNER }, -- the server's owner
	run = run,
}
