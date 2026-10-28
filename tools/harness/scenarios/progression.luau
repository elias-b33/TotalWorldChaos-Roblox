--!nocheck
-- Phase 4: Alice wins a battle, takes a province and the match, sees her XP and Glory on the Results screen, and
-- the profile is saved; she leaves (releasing the session lock) and rejoins, and her XP and Glory are still there.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local provinceByName = H.provinceByName
local tapProvince = H.tapProvince

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local userId = alice.serverPlayer.UserId
	local Data = H.server("Services.PlayerDataService")
	local summary = H.client(alice, "ProfileState").summary()
	H.expect(Data.data(alice.serverPlayer) ~= nil, "Alice's profile loaded with a session lock")
	H.expect(summary and summary.level == 1 and summary.xp == 0 and summary.glory == 0, "a new player: level 1, no XP")
	H.expect(H.textOf(alice, "Level") == "1", "the HUD shows level 1")

	-- recruit 3 regiments, march on the neutral Cinder Rock, beat its garrison and take it
	local state = H.state()
	local A = H.myNation(alice)
	state.nations[A].gold, state.nations[A].manpower = 400, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for _ = 1, 3 do
		Emulator.press(alice, H.lineButton(alice))
		Emulator.run(1.2)
	end
	Emulator.press(alice, "Move")
	Emulator.run(0.3)
	local rock = provinceByName("Cinder Rock")
	tapProvince(alice, rock)
	Emulator.press(alice, "Go")
	local deadline = Emulator.now() + 180
	while state.provinces[rock].owner ~= A and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[rock].owner == A, "Alice won the battle and captured Cinder Rock")

	-- the domination share of the world for Aurora: domination and Results
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Aurora won by domination")
	local report = H.client(alice, "ProfileState").reward()
	-- finish 100 + 1st place 150 + 1 province 5 + 1 battle 5 + first match today 200 = 460 XP (level 2);
	-- Glory 20 + 40 + 1 + 1 + 50, and 50 for the level-up, 25 for the first step of the play calendar = 187
	-- plus the achievements the win unlocked (First Blood, Domination, Victor, Podium...): one line of their own
	local achievementGlory = 0
	for _, line in report.reward.lines do
		achievementGlory += if line.kind == "Achievement" then line.glory else 0
	end
	H.expect(achievementGlory >= 500, "achievements the match unlocked pay " .. achievementGlory .. " Glory")
	local glory = 187 + achievementGlory
	H.expect(report ~= nil and report.reward.xp == 460 and report.reward.glory == glory, "the reward: 460 XP, 187 Glory + achievements")
	H.expect(report.reward.placement == 1 and report.after.level == 2, "1st place, and Alice reached level 2")
	H.expect(Emulator.findText(alice, "+460 XP") ~= nil, "the Results screen shows the XP and Glory")
	H.expect(Emulator.findText(alice, "First match today") ~= nil, "with the breakdown")
	H.expect(Emulator.findText(alice, "Level 2!") ~= nil, "and the level-up")
	H.expect(Emulator.findText(alice, "160 / 360 XP") ~= nil, "and the level bar")
	H.expect(H.textOf(alice, "Level") == "2", "the HUD shows level 2")
	H.shot(alice, "results_reward")

	Emulator.run(1)
	local saved = H.saved(userId)
	H.expect(saved.Data.xp == 460 and saved.Data.glory == glory, "the reward was saved to the DataStore")
	H.expect(saved.MetaData.ActiveSession ~= nil, "Alice's server holds the session lock")
	H.expect(Emulator.dataStores.PlayerData == nil, "Studio saves go to their own store, never the live one")

	-- leave, rejoin
	Emulator.removeClient(alice)
	Emulator.run(3)
	saved = H.saved(userId)
	H.expect(saved.MetaData.ActiveSession == nil, "leaving saved the profile and released the session lock")
	H.expect(saved.Data.xp == 460 and saved.Data.stats.wins == 1, "the save has the XP and the win")
	local again = Emulator.addClient("Alice", nil, userId)
	Emulator.run(3)
	local data = Data.data(again.serverPlayer)
	H.expect(data and data.xp == 460 and data.glory == glory and data.level == 2, "after rejoining: 460 XP, the Glory, level 2")
	H.expect(H.client(again, "ProfileState").summary().level == 2, "and Alice's client knows it")
	Emulator.run(30) -- the next match
	H.expect(H.state().result == nil, "a new match started")
	H.expect(H.textOf(again, "Level") == "2", "the HUD shows level 2 after rejoining")
	H.shot(again, "rejoined")

	-- the server shuts down a minute into the match, before Alice leaves: she gets what leaving pays (4 XP of
	-- the finish reward), and no wrong kick message (a kick counts as a warning and fails the scenario)
	Emulator.run(60)
	Emulator.shutdown()
	saved = H.saved(userId)
	H.expect(saved.Data.xp > 460, string.format("the shutdown paid the match so far (%d XP)", saved.Data.xp))
	H.expect(saved.MetaData.ActiveSession == nil, "and released the session lock")
end

return { run = run }
