--!nocheck
-- Phase 3: Bob is eliminated, rises as a Primordial and drops a Meteor on Alice's army through the power UI.

local Emulator = require("../Emulator")
local H = require("../H")
local tapProvince = H.tapProvince

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A == 1 and B == 2, "Alice is Aurora, Bob is Zephyr")
	H.expect(H.textOf(alice, "Charges") == "0", "a living nation sees the power button with its charges")

	-- open war; Aurora takes Zephyr's capital and all but two provinces: Zephyr is eliminated next tick
	state.tick = 10 * 60
	local kept = 0
	for _, p in state.provinces do
		if p.owner == B then
			if p.isCapital or kept >= 2 then
				p.owner = A
			else
				kept += 1
			end
		end
	end
	Emulator.run(2)
	local bobId = bob.serverPlayer.UserId
	H.expect(state.nations[B].eliminated, "Zephyr was eliminated")
	H.expect(state.primordials[bobId] ~= nil, "Bob rose as a Primordial")
	H.expect(Emulator.findText(bob, "You rose as a Primordial") ~= nil, "Bob sees the Primordial banner")
	H.expect(H.textOf(bob, "Nation") == "Primordial", "Bob's top bar says Primordial")
	H.shot(bob, "primordial")
	Emulator.run(2.5) -- after the War toast
	H.expect(Emulator.findText(alice, "Zephyr was eliminated") ~= nil, "Alice hears about it")

	-- Bob has no orders to give, only powers
	tapProvince(bob, state.nations[A].capital)
	H.expect(Emulator.findText(bob, "Declare") == nil and Emulator.findText(bob, "Develop") == nil, "no orders")
	Emulator.press(bob, "✕")

	-- charges and a target: a 4k Aurora army at its capital
	state.primordials[bobId].charges = 3
	local Army = require("../../../src/shared/Sim/Army")
	local capital = state.nations[A].capital
	local army = Army.spawn(state, A, capital, 4000)
	local dev = state.provinces[capital].development
	Emulator.run(1.5)
	H.expect(H.textOf(bob, "Charges") == "3", "the power button shows Bob's 3 charges")

	-- button -> pick Meteor -> tap the army -> Confirm
	Emulator.press(bob, "PowerButton")
	Emulator.run(0.3)
	H.expect(Emulator.findText(bob, "Meteor") ~= nil and Emulator.findText(bob, "Shield") ~= nil, "the picker lists powers")
	H.shot(bob, "picker")
	Emulator.press(bob, "Meteor")
	Emulator.run(0.3)
	H.expect(Emulator.findText(bob, "Tap an army") ~= nil, "Meteor asks for an army")
	local MapView = H.client(bob, "MapView")
	local spot = H.provinceMap(bob, capital) + Emulator.roblox.Vector2.new(0, -4)
	MapView.centreOn(spot, true)
	Emulator.run(1.5)
	local screen = MapView.toScreen(spot)
	Emulator.tapScreen(bob, screen.X, screen.Y)
	Emulator.run(0.3)
	H.expect(Emulator.findText(bob, "Aurora's army (4k)") ~= nil, "the target is Aurora's 4k army")
	H.shot(bob, "target")
	Emulator.press(bob, "Confirm")
	Emulator.run(1.5)
	H.expect(army.men == 2000, "the Meteor killed half the army")
	H.expect(state.provinces[capital].development == math.max(1, dev - 1), "and cost the capital a development level")
	H.expect(state.primordials[bobId].charges == 1, "Bob paid 2 charges")
	H.expect(Emulator.findText(alice, "Meteor struck your army") ~= nil, "Alice gets the toast")
	H.expect(H.textOf(bob, "Charges") == "1", "Bob's button shows 1 charge left")
	H.shot(alice, "meteor_alice")
	H.shot(bob, "meteor_bob")

	-- the 60 s immunity: the picker shows Aurora as unavailable instead of sending a power the server refuses
	state.primordials[bobId].charges = 3
	Emulator.run(1.5)
	Emulator.press(bob, "PowerButton")
	Emulator.press(bob, "Plague")
	tapProvince(bob, capital)
	H.expect(Emulator.findText(bob, "Aurora is immune for") ~= nil, "the target step says Aurora is immune")
	H.expect(Emulator.findText(bob, "Confirm") == nil, "and offers no Confirm")
	H.shot(bob, "immune_target")
	Emulator.press(bob, "Cancel")
	H.expect(state.nations[A].plagueUntil == nil, "Aurora is not plagued")

	-- Rebels: a black 🏴 token that shows even zoomed out, unlike the neutral garrisons
	local rebelTarget
	for id, p in state.provinces do
		if p.owner == 4 and not p.isCapital and p.terrain ~= "Mountain" and (rebelTarget == nil or id < rebelTarget) then
			rebelTarget = id
		end
	end
	Emulator.press(bob, "PowerButton")
	Emulator.press(bob, "Rebels")
	tapProvince(bob, rebelTarget)
	Emulator.press(bob, "Confirm")
	Emulator.run(1.5)
	local rebels
	for _, a in state.armies do
		if a.rebel then
			rebels = a
		end
	end
	H.expect(rebels ~= nil and rebels.location == rebelTarget, "Rebels rose in " .. state.provinces[rebelTarget].name)
	H.client(alice, "MapView").showWholeMap()
	Emulator.run(1.5)
	H.expect(H.badge(alice, rebels.id) == "3k" and select(2, H.badge(alice, rebels.id)) == "rebels", "Alice sees the Rebels token (flag, 3k) zoomed out")
	H.expect(not H.iconText(alice, "shield", "", "Map"), "while garrisons stay hidden at that zoom")
	H.shot(alice, "rebels")
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, rebelTarget), true)
	Emulator.run(1.5)
	H.shot(alice, "rebels_close")

	-- rejoining: Bob leaves and comes back as himself, still the Primordial of Zephyr
	Emulator.removeClient(bob)
	Emulator.run(2)
	bob = Emulator.addClient("Bob", nil, bobId)
	Emulator.run(2)
	H.expect(H.myNation(bob) == B, "Bob rejoins on Zephyr")
	H.expect(H.textOf(bob, "Nation") == "Primordial", "still a Primordial")

	-- Carol takes a nation, leaves, and it is eliminated while a bot runs it: she rejoins as its Primordial
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local carolId = carol.serverPlayer.UserId
	local C = H.myNation(carol)
	H.expect(C == 3, "Carol takes the lowest free nation, " .. state.nations[3].name)
	Emulator.removeClient(carol)
	Emulator.run(2)
	H.expect(state.nations[C].controller == "Bot", "a bot runs it after she leaves")
	local dave = Emulator.addClient("Dave")
	Emulator.run(2)
	H.expect(H.myNation(dave) ~= C, "a newcomer doesn't take the nation Carol held")
	for _, p in state.provinces do
		if p.owner == C then
			p.owner = A
		end
	end
	Emulator.run(2)
	H.expect(state.nations[C].eliminated, state.nations[C].name .. " was eliminated under the bot")
	carol = Emulator.addClient("Carol", nil, carolId)
	Emulator.run(2)
	H.expect(H.myNation(carol) == C, "Carol rejoins on her eliminated nation, not a healthy one")
	H.expect(state.primordials[carolId] ~= nil, "and is its Primordial")
	H.expect(H.textOf(carol, "Nation") == "Primordial", "her top bar says Primordial")
	H.shot(carol, "rejoined_primordial")
end

return { run = run }
