--!nocheck
-- Balance pass: a beaten army walks home (no teleport) under a 🏳 flag and takes no orders on the way.

local Emulator = require("../Emulator")
local H = require("../H")
local provinceByName = H.provinceByName

local Troops = require("../../../src/shared/Sim/Troops")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	local Army = require("../../../src/shared/Sim/Army")
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	local rock, reach = provinceByName("Cinder Rock"), provinceByName("Cinder Reach")
	state.tick = 179
	state.provinces[rock].owner = A
	state.provinces[reach].owner = B
	for id, a in state.armies do
		if a.location == rock or a.location == reach then
			state.armies[id] = nil
		end
	end
	Emulator.run(2)
	H.expect((Diplomacy.declareWar(state, A, B)), "Aurora and Zephyr are at war")
	local beaten = Army.spawn(state, A, reach, 3000)
	Army.spawn(state, B, reach, 5000)
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, reach), true)
	Emulator.run(1.5)
	H.shot(alice, "battle")
	local deadline = Emulator.now() + 10
	while not beaten.retreating and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	H.expect(beaten.retreating == true and beaten.location == reach, "the beaten army is still on the field, retreating")
	Emulator.run(2)
	H.expect(select(2, H.badge(alice, beaten.id)) == "retreat", "its token flies the retreat flag")
	H.client(alice, "UI.ArmySheet").show(beaten.id)
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Retreating to Cinder Rock") ~= nil, "the army sheet says where it is going")
	H.shot(alice, "retreating")
	H.client(alice, "UI.ArmySheet").show(nil)
	deadline = Emulator.now() + 20
	while beaten.location ~= rock and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	Emulator.run(1)
	H.expect(beaten.location == rock and beaten.retreating == nil, "it walked home and is a normal army again")
	H.expect(
		state.armies[beaten.id] ~= nil
			and select(2, H.badge(alice, beaten.id)) == Troops.icon(Troops.ofRole(state.nations[A].race, "line"))
			and not H.iconText(alice, "retreat", "", "Map"),
		"no flag once home: its badge shows its troops (its race's line troop) again"
	)
	H.shot(alice, "home")
end

return { run = run }
