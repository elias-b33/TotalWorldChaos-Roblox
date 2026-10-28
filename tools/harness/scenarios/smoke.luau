--!nocheck
-- Phase 1: join, look around, develop, build, recruit, earn income.

local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	H.shot(alice, "joined")
	local me = H.myNation(alice)
	H.expect(me == 1, "Alice is seated as nation 1")
	H.expect(H.logged("Alice is new: off to the tutorial"), "a public server sends a new player to the tutorial")
	local state = H.state()
	local nation = state.nations[me]
	nation.gold = 500 -- enough to try everything

	Emulator.press(alice, "Capital")
	Emulator.run(1)
	H.shot(alice, "capital")
	local capital = state.provinces[nation.capital]
	local dev0 = capital.development
	Emulator.press(alice, "Develop")
	Emulator.run(1.5)
	H.expect(capital.development == dev0 + 1, "Develop raised the capital's development")
	Emulator.press(alice, "Farm")
	Emulator.run(1.5)
	H.expect(capital.building == "Farm", "Farm was built")
	Emulator.press(alice, H.lineButton(alice))
	Emulator.run(1.5)
	local armies = 0
	for _, a in state.armies do
		if a.owner == me then
			armies += 1
		end
	end
	H.expect(armies == 1, "Recruit created an army")
	H.shot(alice, "built")

	-- tap a foreign province on the 2D map
	local foreign
	for id, p in state.provinces do
		if p.owner ~= nil and p.owner ~= me then
			foreign = id
			break
		end
	end
	Emulator.press(alice, "✕")
	Emulator.run(0.5)
	local ClientState = H.client(alice, "ClientState")
	H.tapProvince(alice, foreign)
	local owner = ClientState.nation(state.provinces[foreign].owner)
	H.expect(Emulator.findText(alice, owner.name) ~= nil, "Tapping a foreign province shows its owner")
	H.shot(alice, "foreign")

	local gold0 = nation.gold
	Emulator.run(30)
	H.expect(nation.gold > gold0, "Income arrives every month")
	H.expect(ClientState.nation(me).gold == nation.gold, "The client's gold matches the server")

	-- Studio test switches (docs/STUDIO.md): set on Workspace, applied once on the next tick, then removed
	local workspace = Emulator.server.dm:GetService("Workspace")
	workspace:SetAttribute("DevTick", 179)
	workspace:SetAttribute("DevCharges", 3)
	workspace:SetAttribute("DevGold", 500)
	Emulator.run(2.5)
	H.expect(state.phase == "War", "DevTick 179 jumps to War")
	H.expect(nation.charges == 3 and nation.gold >= 500, "DevCharges and DevGold apply")
	H.expect(workspace:GetAttribute("DevTick") == nil, "the switches clear themselves")
end

return { run = run }
