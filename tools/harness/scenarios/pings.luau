--!nocheck
-- Map pings (docs/NEXT_FEATURES.md 4) on Earth, through the real UI. Alice and Bob ally (the sheet's Ally, the offer's
-- Accept). Alice long-presses one of Carol's provinces: the four-ping wheel opens; she presses Attack. Bob's map shows
-- the marker (medallion, flag, rings) and a toast; Carol's shows nothing and her client is never even sent it. A
-- second ping at once is refused with the wait toast, and the marker fades after its 8 s. Then the province sheet's
-- ping gem (Defend on Alice's own land), a third live ping taking the oldest off Bob's map (PingGone), Carol (no
-- allies) told to make an ally, and the GUI budget.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")
local MapGrid = require("../../../src/shared/MapGrid")

local GUI_BUDGET = 2000

local function guiObjects(client): number
	local n = 0
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("GuiObject") then
			n += 1
		end
	end
	return n
end

-- Wait up to `seconds` of game time for a text (a toast comes after the ones queued before it).
local function waitText(client, needle: string, seconds: number): boolean
	local deadline = Emulator.now() + seconds
	while Emulator.findText(client, needle) == nil and Emulator.now() < deadline do
		Emulator.run(0.25)
	end
	return Emulator.findText(client, needle) ~= nil
end

-- Centre a client's view on a province (the region zoom) and return a point of it on screen, a little below its
-- centre (as H.tapProvince picks it).
local function spotOf(client, provinceId: number)
	local MapView = H.client(client, "MapView")
	MapView.centreOn(H.provinceMap(client, provinceId), true)
	Emulator.run(1.5)
	local grid = MapGrid.decode(H.client(client, "ClientState").map())
	local c = H.provinceMap(client, provinceId)
	local spot = c
	for r = 12, 3, -1 do
		local p = c + Emulator.roblox.Vector2.new(0, r)
		if MapGrid.at(grid, p.X, p.Y) == provinceId then
			spot = p
			break
		end
	end
	return MapView.toScreen(spot)
end

local function longPressOn(client, provinceId: number)
	local s = spotOf(client, provinceId)
	Emulator.longPress(client, s.X, s.Y, Config.Pings.LongPressSeconds + 0.05)
end

-- The icon in the medallion of the visible toast whose text contains `needle` (nil: no such toast).
local function toastIcon(client, needle: string): string?
	for _, d in client.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "Toast" and H.shown(d) and string.find(d.Text, needle, 1, true) then
			local medallion = d:FindFirstChild("Medallion")
			local icon = medallion and medallion:FindFirstChild("Icon")
			return icon and icon:GetAttribute("Icon")
		end
	end
	return nil
end

local function markerIcon(client, name: string): string?
	local marker = H.mapObject(client, name)
	local medallion = marker and marker:FindFirstChild("Medallion")
	local icon = medallion and medallion:FindFirstChild("Icon")
	return icon and icon:GetAttribute("Icon")
end

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local state = H.state()
	local A, B, C = H.myNation(alice), H.myNation(bob), H.myNation(carol)
	H.expect(A ~= 0 and B ~= 0 and C ~= 0 and A ~= B and B ~= C and A ~= C, "Alice, Bob and Carol hold three nations")

	-- what each client is sent on the Ping remote
	local received = {}
	for _, c in { alice, bob, carol } do
		received[c] = 0
		c.dm:GetService("ReplicatedStorage").Remotes.Ping.OnClientEvent:Connect(function()
			received[c] += 1
		end)
	end

	-- 1. Alice and Bob ally through the UI
	H.tapProvince(alice, state.nations[B].capital)
	Emulator.press(alice, "🤝 Ally")
	Emulator.run(1.5)
	Emulator.press(bob, "Accept")
	Emulator.run(1.5)
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	H.expect(Diplomacy.allied(state, A, B), "Alice and Bob are allies")
	H.expect(not Diplomacy.allied(state, A, C) and not Diplomacy.allied(state, B, C), "Carol is in no alliance")
	Emulator.press(alice, "✕")
	Emulator.run(4) -- the alliance's toasts go by

	-- a province of Carol's (not her capital)
	local target
	for id, p in state.provinces do
		if p.owner == C and id ~= state.nations[C].capital and p.terrain ~= "Mountain" then
			target = id
			break
		end
	end
	H.expect(target ~= nil, "Carol has a province besides her capital")
	H.client(bob, "MapView").centreOn(H.provinceMap(bob, target), true)
	H.client(carol, "MapView").centreOn(H.provinceMap(carol, target), true)

	-- 2. Alice long-presses it: the wheel opens under her finger
	local spot = spotOf(alice, target)
	Emulator.longPress(alice, spot.X, spot.Y, Config.Pings.LongPressSeconds + 0.05)
	H.expect(H.button(alice, "Ping_Attack") ~= nil, "a long press opens the ping wheel")
	for _, kind in Config.Pings.Kinds do
		H.expect(H.button(alice, "Ping_" .. kind) ~= nil, "the wheel has " .. kind)
	end
	H.expect(Emulator.findText(alice, "Allies only") ~= nil, "the wheel says who sees it")
	H.expect(H.button(alice, "Ping_Attack").Size.X.Offset >= 44, "the gems are 44 px touch targets")
	H.expect(guiObjects(alice) <= GUI_BUDGET, string.format("GUI objects with the wheel open: %d", guiObjects(alice)))
	H.shot(alice, "wheel")

	-- 3. Attack. 4. And at once a second ping: too soon
	Emulator.press(alice, "Ping_Attack")
	Emulator.run(0.1)
	H.expect(H.button(alice, "Ping_Attack") == nil, "the wheel closes after a ping")
	Emulator.longPress(alice, spot.X, spot.Y, Config.Pings.LongPressSeconds + 0.05)
	Emulator.press(alice, "Ping_Help")
	Emulator.run(1.2)
	H.expect(#state.pings == 1 and state.pings[1].kind == "Attack", "the server holds one ping: Attack")
	H.expect(H.mapObject(bob, "Ping1") ~= nil, "Bob's map shows the ping")
	H.expect(markerIcon(bob, "Ping1") == "war", "with the crossed swords")
	local marker = H.mapObject(bob, "Ping1")
	H.expect(marker:FindFirstChild("Flag") ~= nil, "and Alice's flag")
	H.expect(H.mapObject(alice, "Ping1") ~= nil, "Alice sees her own ping")
	H.expect(H.mapObject(carol, "Ping1") == nil, "Carol's map shows nothing")
	H.expect(received[carol] == 0, "Carol's client was never sent the ping")
	H.expect(received[bob] == 1 and received[alice] == 1, "Alice and Bob were sent it once")
	H.expect(waitText(bob, ": Attack · ", 4), "Bob gets a toast naming the ping")
	H.expect(toastIcon(bob, ": Attack · ") == "war", "the toast's medallion shows the ping's icon")
	H.expect(waitText(alice, "Wait a moment to ping again", 4), "the second ping was refused: wait")
	H.expect(Emulator.findText(carol, ": Attack · ") == nil, "Carol gets no toast")
	H.shot(bob, "ally_sees")

	-- the ping fades after its 8 s
	Emulator.run(Config.Pings.LifeTicks)
	H.expect(H.mapObject(bob, "Ping1") == nil, "after 8 s the ping is gone from Bob's map")
	H.expect(H.mapObject(alice, "Ping1") == nil, "and from Alice's")
	H.expect(#state.pings == 0, "and from the server")

	-- the province sheet's ping gem: Defend on Alice's own capital
	H.tapProvince(alice, state.nations[A].capital)
	H.expect(H.button(alice, "PingButton") ~= nil, "the province sheet has a ping gem (Alice has an ally)")
	H.shot(alice, "sheet_gem")
	Emulator.press(alice, "PingButton")
	Emulator.run(0.5)
	H.expect(H.button(alice, "Ping_Defend") ~= nil, "the gem opens the wheel")
	Emulator.press(alice, "Ping_Defend")
	Emulator.run(1.5)
	H.expect(markerIcon(bob, "Ping2") == "powerShield", "Bob sees Defend's shield on Alice's capital")
	H.expect(waitText(bob, ": Defend · ", 4), "with its toast")
	H.expect(toastIcon(bob, ": Defend · ") == "shield", "a shield in the toast's medallion")

	-- a third live ping takes the oldest off the map at once
	local alicesOther
	for id, p in state.provinces do
		if p.owner == A and id ~= state.nations[A].capital and p.terrain ~= "Mountain" then
			alicesOther = id
			break
		end
	end
	Emulator.run(Config.Pings.CooldownTicks - 1)
	H.client(alice, "Intents").ping("Look", alicesOther)
	Emulator.run(Config.Pings.CooldownTicks)
	H.client(alice, "Intents").ping("Help", target)
	Emulator.run(1.5)
	H.expect(H.mapObject(bob, "Ping2") == nil, "Alice's third ping took her oldest off Bob's map")
	H.expect(H.mapObject(bob, "Ping3") ~= nil and H.mapObject(bob, "Ping4") ~= nil, "her two newest show")
	H.expect(markerIcon(bob, "Ping4") == "fire", "Help is the fire")
	H.expect(guiObjects(bob) <= GUI_BUDGET, string.format("Bob's GUI objects with pings up: %d", guiObjects(bob)))

	-- Carol has no ally: a long press tells her so, and opens nothing
	longPressOn(carol, state.nations[C].capital)
	H.expect(H.button(carol, "Ping_Attack") == nil, "no wheel without an ally")
	H.expect(waitText(carol, "make an ally first", 4), "Carol is told to make an ally")
	H.tapProvince(carol, state.nations[C].capital)
	H.expect(Emulator.findText(carol, "Develop") ~= nil, "a tap still opens her sheet")
	H.expect(H.button(carol, "PingButton") == nil, "and her sheet has no ping gem")
	H.expect(received[carol] == 0, "Carol was sent no ping all match")
end

return { run = run, map = "earth" }
