--!nocheck
-- Phase 2: march on a garrison, win the battle, siege and take the province; war, peace and results.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local provinceByName = H.provinceByName
local tapProvince = H.tapProvince

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A == 1 and B == 2, "Alice is Aurora, Bob is Zephyr")
	state.nations[A].gold, state.nations[A].manpower = 400, 20000

	-- recruit 3 regiments at the capital
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for _ = 1, 3 do
		Emulator.press(alice, H.lineButton(alice))
		Emulator.run(1.2)
	end
	local army
	for _, a in state.armies do
		if a.owner == A then
			army = a
		end
	end
	H.expect(army ~= nil and army.men == 3000, "a 3k army stands at the capital")

	-- pick it up from the sheet, tap the neutral drift isle, Go
	Emulator.press(alice, "Move")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "Tap where to go") ~= nil, "the army sheet asks for a destination")
	local rock = provinceByName("Cinder Rock")
	tapProvince(alice, rock)
	H.expect(Emulator.findText(alice, "Cinder Rock") ~= nil, "route preview names the destination")
	H.shot(alice, "route_preview")
	Emulator.press(alice, "Go")
	Emulator.run(1)
	H.expect(#army.path > 0, "the army is marching")
	Emulator.run(6)
	H.shot(alice, "marching")

	-- arrive, fight the garrison, besiege, take it
	local deadline = Emulator.now() + 60
	while army.location ~= rock and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(army.location == rock, "the army reached Cinder Rock")
	Emulator.run(1.5)
	H.shot(alice, "battle")
	Emulator.run(4)
	local garrisonLeft = false
	for _, a in state.armies do
		garrisonLeft = garrisonLeft or (a.owner == 0 and a.location == rock)
	end
	H.expect(not garrisonLeft, "the garrison was beaten")
	Emulator.run(8)
	H.shot(alice, "siege")
	deadline = Emulator.now() + 120
	while state.provinces[rock].owner ~= A and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[rock].owner == A, "Cinder Rock was captured")
	Emulator.run(0.5)
	H.shot(alice, "captured")

	-- jump to the war phase, take the other drift province so Aurora borders Zephyr, declare war
	state.tick = 179
	state.provinces[provinceByName("Cinder Reach")].owner = A
	Emulator.run(2)
	local zephyrLeeward = provinceByName("Zephyr Leeward")
	tapProvince(alice, zephyrLeeward)
	H.shot(alice, "foreign_sheet")
	Emulator.press(alice, "Declare")
	Emulator.run(1.5)
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	H.expect(Diplomacy.atWar(state, A, B), "Aurora and Zephyr are at war")
	H.shot(bob, "war_declared_on_bob")

	-- Bob offers peace with 50 gold; Alice accepts from the offer card
	state.nations[B].gold = 300
	Emulator.run(1)
	tapProvince(bob, provinceByName("Cinder Reach"))
	Emulator.press(bob, "Peace_50")
	Emulator.run(2)
	H.expect(Emulator.findText(alice, "offers peace") ~= nil, "Alice sees Bob's peace offer")
	H.shot(alice, "peace_offer")
	local aliceGold = state.nations[A].gold
	Emulator.press(alice, "Accept")
	Emulator.run(1.5)
	H.expect(not Diplomacy.atWar(state, A, B), "peace was made")
	H.expect(state.nations[A].gold >= aliceGold + 50, "Alice got the tribute")

	-- the nations drawer
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Zephyr") ~= nil, "the drawer lists the nations")
	H.shot(alice, "nations")
	Emulator.press(alice, "NationsButton")

	-- give Aurora 30% of the world: the coalition crown, then the domination share and the results screen
	local given = 0
	for _, p in state.provinces do
		if p.owner == A then
			given += 1
		end
	end
	local need = math.ceil(0.3 * 131)
	for _, p in state.provinces do
		if given < need and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(1.5)
	local crown = H.mapObject(alice, "Crown" .. A)
	H.expect(crown ~= nil and crown:GetAttribute("Icon") == "crown", "the coalition leader wears a crown")
	H.shot(alice, "crown")
	need = math.ceil(Config.Win.DominationShare * 131)
	for _, p in state.provinces do
		if given < need and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil and state.result.kind == "Domination", "Aurora won by domination")
	H.expect(Emulator.findText(alice, "You win") ~= nil, "Alice sees the victory screen")
	H.shot(alice, "results")
	Emulator.run(32)
	H.expect(state ~= H.state(), "a new match started after Results")
	H.expect(H.state().phase == "Peace", "the new match is in Peace")
end

return { run = run }
