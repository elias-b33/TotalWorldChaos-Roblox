--!nocheck
-- The singleplayer sandbox (docs/DESIGN.md "Sandbox"): a Studio sandbox server (Workspace "Sandbox"). Alice arrives
-- watching a world of ten bots, takes over a nation and switches to another (the first goes back to a bot), drops a
-- free Meteor in Peace and a second power on the same nation at once, pauses (powers still land), runs at 4×, goes
-- past 25:00 with no end, switches the disasters on, makes a new world on another map, and earns nothing for it.
-- A second player on a 667×375 phone checks the panel and the lists fit, and can't take Alice's nation.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function guiObjects(client): number
	local n = 0
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("GuiObject") then
			n += 1
		end
	end
	return n
end

local function run()
	local Army = require("../../../src/shared/Sim/Army")
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local userId = alice.serverPlayer.UserId

	-- a world of ten bots; Alice watches
	H.expect(state.setup.sandbox == true and state.sandbox ~= nil, "the server plays a sandbox world")
	H.expect(state.mapId == "earth", "on the map it was given (Earth)")
	local bots = 0
	for _, n in state.nations do
		if n.controller == "Bot" then
			bots += 1
		end
	end
	H.expect(bots == 10, "all ten nations are bots")
	H.expect(H.myNation(alice) == 0, "Alice arrives watching")
	H.expect(H.textOf(alice, "Nation") == "Spectating", "the top bar says so")
	H.expect(H.client(alice, "UI.Sandbox").active(), "the client knows it's a sandbox")
	H.expect(H.client(alice, "Music").state().track == "Peace", "a sandbox world plays Peace")
	H.expect(Emulator.findText(alice, "Play as") ~= nil, "the sandbox panel shows Play as")
	H.expect(H.iconIn(alice, "Pause", "pause"), "and the pause tab with its icon")
	H.expect(Emulator.findText(alice, "Your world is alive") ~= nil, "a welcome toast")
	H.expect(
		not H.shown(alice.localPlayer.PlayerGui.Powers.PowerButton),
		"the round power button gives way to the panel"
	)
	H.expect(H.logged("[sandbox] world 1 on earth"), "the server says which world")
	H.shot(alice, "watching")

	-- take over a nation: Play as, then the nation (two taps)
	Emulator.press(alice, "PlayAs")
	Emulator.run(0.3)
	H.expect(H.within(alice, "PlayAs", "Watch"), "the list starts with Watch")
	H.expect(H.within(alice, "PlayAs", state.nations[3].name), "and lists the nations by name")
	H.shot(alice, "play_as")
	local first = 3
	Emulator.press(alice, "Play" .. first)
	Emulator.run(1)
	H.expect(
		state.nations[first].userId == userId and state.nations[first].controller == "Player",
		"the server seats her"
	)
	H.expect(H.myNation(alice) == first, "Alice leads " .. state.nations[first].name)
	-- (a small phone's top bar hides the name to make room, but it is still set)
	local nationLabel = alice.localPlayer.PlayerGui:FindFirstChild("Nation", true)
	H.expect(nationLabel ~= nil and nationLabel.Text == state.nations[first].name, "her top bar names it")
	H.expect(Emulator.findText(alice, "You lead " .. state.nations[first].name) ~= nil, "a toast says so")
	H.shot(alice, "lead")

	-- switch to another: the first goes back to a bot, which plays it again
	local second = 7
	Emulator.press(alice, "PlayAs")
	Emulator.run(0.3)
	Emulator.press(alice, "Play" .. second)
	Emulator.run(1)
	H.expect(H.myNation(alice) == second, "Alice now leads " .. state.nations[second].name)
	H.expect(
		state.nations[first].controller == "Bot" and state.nations[first].userId == nil,
		"the first is a bot again"
	)
	local AIService = H.server("Services.AIService")
	H.expect(AIService ~= nil, "bots run")
	Emulator.run(4)
	H.expect(state.nations[first].controller == "Bot", "and stays one")

	-- a free Meteor in Peace on a bot's army, from the panel's Powers button (no charges)
	H.expect(state.phase == "Peace", "still Peace")
	local victim = 2
	local capital = state.nations[victim].capital
	local army = Army.spawn(state, victim, capital, 8000)
	state.nations[second].charges = 0
	Emulator.run(1)
	Emulator.press(alice, "Powers")
	Emulator.run(0.3)
	H.expect(
		Emulator.findText(alice, "Meteor") ~= nil and Emulator.findText(alice, "Shield") ~= nil,
		"the picker opens"
	)
	H.expect(not H.iconText(alice, "charge", "2", "Powers"), "with no charge prices")
	H.shot(alice, "powers")
	Emulator.press(alice, "Meteor")
	Emulator.run(0.3)
	H.tapProvince(alice, capital)
	H.expect(Emulator.findText(alice, "Confirm") ~= nil, "a target and Confirm")
	Emulator.press(alice, "Confirm")
	Emulator.run(1.5)
	H.expect(army.men == 4000, "the Meteor killed half the army, in Peace")
	H.expect(state.nations[second].charges == 0, "and cost nothing")
	H.expect(state.primordials[userId] == nil, "Alice is no Primordial")
	-- no 30 s immunity: a Plague on the same nation at once
	Emulator.press(alice, "Powers")
	Emulator.press(alice, "Plague")
	H.tapProvince(alice, capital)
	H.expect(Emulator.findText(alice, "immune") == nil, "nobody is immune")
	Emulator.press(alice, "Confirm")
	Emulator.run(1.5)
	H.expect(state.nations[victim].plagueUntil ~= nil, "the Plague struck right after the Meteor")
	H.shot(alice, "meteor_plague")

	-- pause: the clock stops, the bots wait, a power still lands
	Emulator.press(alice, "Pause")
	Emulator.run(1)
	H.expect(state.sandbox.speed == 0, "paused")
	local tick = state.tick
	local clock = H.textOf(alice, "Clock")
	Emulator.run(4)
	H.expect(state.tick == tick, "no ticks while paused")
	H.expect(H.textOf(alice, "Clock") == clock, "the client's clock stands still (" .. tostring(clock) .. ")")
	local blessed = capital
	Emulator.press(alice, "Powers")
	Emulator.press(alice, "Blessing")
	H.tapProvince(alice, blessed)
	Emulator.press(alice, "Confirm")
	Emulator.run(1)
	H.expect(state.provinces[blessed].buffs.Blessing ~= nil and state.tick == tick, "a Blessing lands while paused")
	H.shot(alice, "paused")

	-- 4×: four ticks a second; the client's clock follows
	Emulator.press(alice, "Speed4")
	Emulator.run(0.5)
	tick = state.tick
	Emulator.run(5)
	local ran = state.tick - tick
	H.expect(ran >= 18 and ran <= 22, string.format("4× runs 4 ticks a second (%d in 5 s)", ran))
	local ClientState = H.client(alice, "ClientState")
	H.expect(math.abs(ClientState.tick() - state.tick) <= 2, "the client's clock keeps up")
	H.expect(ClientState.timeScale() == 4, "and knows the speed")
	H.shot(alice, "fast")

	-- past 25:00: nothing ends
	state.tick = Config.Phases.MatchEndTick - 8
	Emulator.run(5)
	H.expect(state.tick > Config.Phases.MatchEndTick + 8, "past 25:00 (" .. state.tick .. ")")
	H.expect(state.result == nil and state.phase == "War", "no result, still War")
	H.expect(not H.server("Services.MatchService").isOver(), "the world isn't over")
	H.expect(Emulator.findText(alice, "The match is over") == nil, "no end toast")
	H.expect(
		string.find(H.textOf(alice, "Clock") or "", "^25:") ~= nil,
		"the clock counts up: " .. tostring(H.textOf(alice, "Clock"))
	)
	state.tick = 3 * Config.Phases.MatchEndTick
	Emulator.run(2)
	H.expect(state.result == nil and state.phase == "War", "nor at 75:00")
	H.shot(alice, "past_25")

	-- disasters on: one strikes a minute later (15 s at 4×)
	Emulator.press(alice, "World")
	Emulator.run(0.3)
	H.expect(H.within(alice, "World", "Disasters: Off"), "the world menu shows the disasters off")
	H.shot(alice, "world_menu")
	Emulator.press(alice, "Disasters")
	Emulator.run(0.5)
	H.expect(state.sandbox.disasters, "disasters on")
	-- the server's Disaster event counts: the client drops a toast when four are already waiting (a war's
	-- conquest toasts can fill the queue), so the toast alone can't say whether one struck
	local Events = H.shared("Sim.Events")
	local push = Events.push
	local disasters = 0
	Events.push = function(s, kind, ...)
		if kind == "Disaster" then
			disasters += 1
		end
		return push(s, kind, ...)
	end
	local toasted = false
	for _ = 1, 40 do
		Emulator.run(0.5)
		toasted = toasted or Emulator.findText(alice, "Cataclysm!") ~= nil
		if toasted then
			break
		end
	end
	Events.push = push
	H.expect(disasters > 0 or toasted, "a disaster struck within a minute of game time")
	H.shot(alice, "disaster")

	-- one more player on a small phone: the panel and the lists fit, and Alice's nation is taken
	local bea = Emulator.addClient("Bea", Emulator.roblox.Vector2.new(667, 375))
	Emulator.run(2)
	H.expect(H.myNation(bea) == 0, "Bea arrives watching")
	H.shot(bea, "phone_panel")
	Emulator.press(bea, "PlayAs")
	Emulator.run(0.3)
	H.shot(bea, "phone_play_as")
	local reason
	bea.dm:GetService("ReplicatedStorage").Remotes.CommandResult.OnClientEvent:Connect(function(_id, ok, why)
		if not ok then
			reason = why
		end
	end)
	Emulator.press(bea, "Play" .. second)
	Emulator.run(1)
	H.expect(H.myNation(bea) == 0 and H.myNation(alice) == second, "Alice's nation is hers")
	H.expect(reason == "Taken", "Bea is told it's taken (" .. tostring(reason) .. ")")
	Emulator.press(bea, "World")
	Emulator.run(0.3)
	H.shot(bea, "phone_world")
	H.pressIn(bea, "World", "✕") -- the menu closes; the panel is back
	Emulator.run(0.3)
	Emulator.press(bea, "Powers")
	Emulator.run(0.3)
	H.shot(bea, "phone_powers")
	H.expect(guiObjects(bea) <= 2000, string.format("Bea's screen holds %d GUI objects", guiObjects(bea)))
	Emulator.press(bea, "Powers")
	Emulator.removeClient(bea)
	Emulator.run(1)

	-- a new world on Skyshards: everyone watches again, at 1×
	Emulator.press(alice, "World")
	Emulator.run(0.3)
	Emulator.press(alice, "NewWorld_skyshards")
	Emulator.run(1.5)
	local world = H.state()
	H.expect(world ~= state and world.mapId == "skyshards", "a new world on Skyshards")
	H.expect(world.sandbox.speed == Config.Sandbox.StartSpeed and not world.sandbox.disasters, "at 1×, disasters off")
	H.expect(H.myNation(alice) == 0, "Alice watches the new world")
	H.expect(H.logged("[sandbox] world 2 on skyshards"), "the server says so")
	H.shot(alice, "new_world")

	-- the start menu's entry point works here too: a new world on Eldmoor
	H.client(alice, "Intents").enterSandbox("eldmoor")
	Emulator.run(1.5)
	H.expect(H.state().mapId == "eldmoor", "Intents.enterSandbox on a sandbox server makes a new world")

	-- Play online: no teleports in Studio, so a toast
	local told = false
	alice.dm:GetService("ReplicatedStorage").Remotes.Notify.OnClientEvent:Connect(function(_kind, text)
		told = told or string.find(text, "Play online needs a live server", 1, true) ~= nil
	end)
	Emulator.press(alice, "World")
	Emulator.press(alice, "PlayOnline")
	Emulator.run(0.5)
	H.expect(H.logged("[sandbox] no teleports in Studio"), "Studio can't teleport")
	H.expect(told, "Alice is told")

	-- no rewards, and analytics only say sandbox_started
	H.expect(H.logged("sandbox_started") and H.logged(" 1 earth,first"), "sandbox_started for the first world")
	H.expect(H.logged(" 1 skyshards,new_world"), "and for a new world")
	H.expect(not H.logged("[telemetry] Onboarding") and not H.logged("[telemetry] Funnel"), "no funnels")
	H.expect(not H.logged("primordial_power_used"), "no match events")
	Emulator.removeClient(alice)
	Emulator.run(2)
	local saved = H.saved(userId)
	H.expect(saved ~= nil and saved.Data.xp == 0 and saved.Data.glory == 0, "no XP or Glory saved")
	H.expect(saved.Data.stats.matches == 0, "and no match counted")
end

return { run = run, map = "earth", attributes = { Sandbox = true, TelemetryLog = true } }
