--!nocheck
-- Phase 4: the tutorial match. A new player on a tutorial server (Workspace "Tutorial") meets 5 Easy bots on an
-- otherwise neutral map and follows the six prompts with the normal UI: take a neutral province, recruit, siege,
-- make an ally, declare war, use a Primordial power. The profile remembers it; the next match's prompts can be
-- skipped with two taps.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local tapProvince = H.tapProvince

local function run()
	local Config = require("../../../src/shared/Config")
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	local Tutorial = require("../../../src/shared/Sim/Tutorial")
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local A = H.myNation(alice)
	local TutorialService = H.server("Services.TutorialService")
	local tut = TutorialService.current()
	H.expect(state.mapId == Config.Tutorial.Map and A == Config.Tutorial.PlayerSlot, "Alice plays the tutorial nation")
	local nations = 0
	for _, n in state.nations do
		nations += 1
	end
	H.expect(nations == 6, "Alice and 5 bots; the other nations are gone")
	H.expect(state.phase == "Peace" and state.tick <= 3, "the Lobby was skipped")
	H.expect(Emulator.findText(alice, "1/6") ~= nil, "the first prompt shows")
	local capital = state.nations[A].capital
	-- the card's hint says what to tap next: the icon of the button to press, or the map arrow ("point")
	local function hintIs(icon: string, text: string): boolean
		local gui = alice.localPlayer.PlayerGui:FindFirstChild("Tutorial")
		local label = gui and gui:FindFirstChild("Hint", true)
		local mark = label and label:FindFirstChild("Icon")
		if mark == nil or not string.find(label.Text, text, 1, true) or Emulator.findText(alice, label.Text) == nil then
			return false
		end
		return (if mark:GetAttribute("Points") then "point" else mark:GetAttribute("Icon")) == icon
	end

	-- 1. take a neutral province: the arrow is on the army; tap it, Move, the grey province, Go
	H.expect(hintIs("point", "Tap your army"), "it asks for the army, where the map arrow points")
	H.shot(alice, "prompt1_army")
	tapProvince(alice, capital)
	H.expect(hintIs("arrow", "Tap Move"), "then for Move (its arrow icon)")
	H.shot(alice, "prompt1_move")
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	H.expect(hintIs("point", "Tap grey land"), "then for the grey province")
	local target = Tutorial.neutralTarget(state, A)
	H.shot(alice, "prompt1_target")
	tapProvince(alice, target)
	H.expect(hintIs("check", "Tap Go"), "then for Go (its check icon)")
	H.shot(alice, "prompt1_go")
	Emulator.press(alice, "Go")
	Emulator.run(8)
	H.expect(hintIs("hourglass", ""), "then it says to wait (an hourglass)")
	H.shot(alice, "prompt1_wait")
	local deadline = Emulator.now() + 120
	while tut.step == 1 and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[target].owner == A and tut.step == 2, "taking the province finished prompt 1")
	Emulator.run(1)

	-- 2. recruit
	H.expect(Emulator.findText(alice, "2/6") ~= nil and Emulator.findText(alice, "Tap your land") ~= nil, "prompt 2")
	H.shot(alice, "prompt2_recruit")
	tapProvince(alice, capital)
	H.expect(hintIs("infantry", "Tap Infantry"), "it points at the line troop's Recruit button (Ganges: Infantry)")
	H.shot(alice, "prompt2_button")
	Emulator.press(alice, "Recruit_Infantry")
	Emulator.run(2)
	H.expect(tut.step == 3, "recruiting finished prompt 2")
	Emulator.press(alice, "✕")
	Emulator.run(0.5)

	-- 3. siege: the army again, the next grey province, Go, and the siege starts
	H.expect(Emulator.findText(alice, "3/6") ~= nil, "prompt 3")
	H.shot(alice, "prompt3_siege")
	local second = Tutorial.neutralTarget(state, A)
	tapProvince(alice, target)
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	tapProvince(alice, second)
	Emulator.press(alice, "Go")
	deadline = Emulator.now() + 120
	while tut.step == 3 and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(tut.step == 4 and state.provinces[second].siege ~= nil, "the siege finished prompt 3")
	Emulator.run(1)

	-- 4. make an ally: tap the friend's land, Ally; the bot accepts
	local friend = tut.friend
	H.expect(Emulator.findText(alice, "Ally with " .. state.nations[friend].name) ~= nil, "prompt 4 names the friend")
	H.shot(alice, "prompt4_ally")
	tapProvince(alice, Tutorial.view(state, tut).province)
	H.expect(hintIs("handshake", "Tap Ally"), "it points at the Ally button")
	H.shot(alice, "prompt4_button")
	Emulator.press(alice, "🤝 Ally")
	Emulator.run(3)
	H.expect(Diplomacy.allied(state, A, friend), "the friend accepted")
	H.expect(tut.step == 5, "the alliance finished prompt 4")
	Emulator.press(alice, "✕")
	Emulator.run(2)

	-- 5. declare war: Peace ended early
	local rival = tut.rival
	H.expect(state.phase == "War", "War came early for the tutorial")
	H.expect(Emulator.findText(alice, "War on " .. state.nations[rival].name) ~= nil, "prompt 5 names the rival")
	H.shot(alice, "prompt5_war")
	tapProvince(alice, Tutorial.view(state, tut).province)
	H.expect(hintIs("war", "Tap Declare war"), "it points at Declare war")
	H.shot(alice, "prompt5_button")
	Emulator.press(alice, "Declare")
	Emulator.run(2)
	H.expect(Diplomacy.atWar(state, A, rival), "Alice is at war with the rival")
	H.expect(tut.step == 6, "the war finished prompt 5")
	Emulator.press(alice, "✕")
	Emulator.run(1)

	-- 6. a power: the button, Blessing, her own land, Confirm
	H.expect(state.nations[A].charges >= 1, "Alice has a charge")
	H.expect(hintIs("sparkles", "Tap the power button"), "prompt 6 points at the power button")
	H.shot(alice, "prompt6_power")
	Emulator.press(alice, "PowerButton")
	Emulator.run(0.5)
	H.expect(hintIs("blessing", "Pick Blessing"), "then at Blessing")
	H.shot(alice, "prompt6_blessing")
	Emulator.press(alice, "Blessing")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Tap your land") ~= nil, "then at her land")
	tapProvince(alice, capital)
	H.expect(hintIs("check", "Tap Confirm"), "then at Confirm")
	H.shot(alice, "prompt6_confirm")
	Emulator.press(alice, "Confirm")
	Emulator.run(2)
	H.expect(Tutorial.finished(tut), "the power finished the tutorial")
	H.expect(Emulator.findText(alice, "Tutorial done!") ~= nil, "Alice sees the end card")
	H.expect(Emulator.findText(alice, "1/6") == nil and Emulator.findText(alice, "6/6") == nil, "the prompt card is gone")
	local data = H.server("Services.PlayerDataService").data(alice.serverPlayer)
	H.expect(data and data.tutorialDone == true, "the profile remembers the tutorial is done")
	H.shot(alice, "done")
	Emulator.press(alice, "Keep playing")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Tutorial done!") == nil, "the end card closes")

	-- the match ends; in Studio the next tutorial match starts here, and its prompts can be skipped (two taps).
	-- Playing the tutorial match to its end counts as done, finished or not (nobody loops back to it on every join).
	H.server("Services.PlayerDataService").update(alice.serverPlayer, function(d)
		d.tutorialDone = false
	end)
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
	Emulator.run(34)
	H.expect(data.tutorialDone == true, "the end of the tutorial match marked the tutorial done")
	H.expect(H.state() ~= state and TutorialService.current() ~= tut, "a new tutorial match started")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "1/6") ~= nil, "its first prompt shows")
	Emulator.press(alice, "Skip")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "Sure?") ~= nil, "the first tap asks to confirm")
	H.shot(alice, "skip_confirm")
	Emulator.press(alice, "Sure?")
	Emulator.run(1.5)
	H.expect(TutorialService.current().skipped, "the server skipped the tutorial")
	H.expect(Emulator.findText(alice, "1/6") == nil, "the prompts are gone")
	H.expect(Emulator.findText(alice, "Play online") == nil, "no way out in Studio (no teleports)")
	-- online (canLeave) a skipped player keeps a small 🌍 Play online button: it asks the server to leave
	local remotes = Emulator.server.dm:GetService("ReplicatedStorage").Remotes
	remotes.Tutorial:FireClient(alice.serverPlayer, { step = 0, total = 6, province = 0, nation = 0, canLeave = true })
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Play online") ~= nil, "after Skip, 🌍 Play online stays on screen")
	H.shot(alice, "skipped_play_online")
	Emulator.press(alice, "Play online")
	Emulator.run(0.5)
	H.expect(H.logged("no teleports in Studio: 1 player(s) stay here"), "and the server tries the teleport back")

	-- Studio: the Tutorial attribute is removed; when this match ends the next one is a normal match with a nation
	Emulator.server.dm:GetService("Workspace"):SetAttribute("Tutorial", nil)
	local second = H.state()
	local owned, needed = 0, 0
	for _, p in second.provinces do
		needed += 1
		owned += if p.owner == A then 1 else 0
	end
	needed = math.ceil(Config.Win.DominationShare * needed)
	for _, p in second.provinces do
		if owned < needed and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			owned += 1
		end
	end
	Emulator.run(36)
	H.expect(H.state() ~= second and not TutorialService.active(), "the next match isn't a tutorial")
	local nationId = H.myNation(alice)
	H.expect(nationId ~= nil and nationId ~= 0 and H.state().nations[nationId].userId == alice.serverPlayer.UserId, "and Alice has a nation the server knows")

	-- analytics: the six prompts were onboarding steps 5-10, and the skip was logged with its prompt
	local onboarded, skips = {}, {}
	for _, r in Emulator.analytics do
		if r.userId == alice.serverPlayer.UserId and r.method == "LogOnboardingFunnelStepEvent" then
			table.insert(onboarded, r.args[1] .. ":" .. r.args[2])
		elseif r.method == "LogCustomEvent" and r.args[1] == "tutorial_skipped" then
			table.insert(skips, r)
		end
	end
	local prompts = "5:first_neutral_captured,6:first_recruit,7:first_siege_done,8:first_ally,9:first_war,10:first_power_used"
	H.expect(string.find(table.concat(onboarded, ","), prompts, 1, true) ~= nil, "onboarding steps 5-10 follow the prompts")
	H.expect(#skips == 1 and skips[1].args[2] == 1, "tutorial_skipped at prompt 1")
end

return {
	tutorial = true, -- it boots a tutorial server (Workspace "Tutorial")
	run = run,
}
