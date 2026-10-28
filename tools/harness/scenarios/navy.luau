--!nocheck
-- Navies (docs/DESIGN.md "Navies") on Skyshards, through the real UI: zone names zoomed out, starships built from
-- the capital's sheet, an army boarding them (tap the army, tap the fleet, Board), the fleet sailing to a drift isle
-- and landing it (tap the fleet, tap the coast, Land), sailing home (tap the fleet, tap the sea, Sail), then at war a
-- sea battle in Zephyr's space, the blockade that follows and its toast, and the GUI budget.

local Emulator = require("../Emulator")
local H = require("../H")
local MapGrid = require("../../../src/shared/MapGrid")
local Navy = require("../../../src/shared/Sim/Navy")
local provinceByName = H.provinceByName

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

local function fleetOf(state, owner: number)
	for _, f in state.fleets do
		if f.owner == owner then
			return f
		end
	end
	return nil
end

-- Wait up to `seconds` of game time for a text (a toast comes after the ones queued before it).
local function waitText(client, needle: string, seconds: number): boolean
	local deadline = Emulator.now() + seconds
	while Emulator.findText(client, needle) == nil and Emulator.now() < deadline do
		Emulator.run(0.25)
	end
	return Emulator.findText(client, needle) ~= nil
end

local function waitFor(cond: () -> boolean, seconds: number): boolean
	local deadline = Emulator.now() + seconds
	while not cond() and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	return cond()
end

-- Centre the view on a fleet (a lone one in its zone, so it stands at the zone's anchor) and tap its ship.
local function tapFleet(client, fleet)
	local MapView = H.client(client, "MapView")
	local anchor = H.client(client, "MapRenderer").zoneCenterOf(fleet.zone) - Emulator.roblox.Vector2.new(0, 4)
	MapView.centreOn(anchor, true)
	Emulator.run(1.5)
	local screen = MapView.toScreen(anchor)
	Emulator.tapScreen(client, screen.X, screen.Y)
	Emulator.run(0.3)
end

-- Centre the view on a sea zone and tap open water in it, clear of the fleets at its centre.
local function tapZone(client, zoneId: number)
	local MapView = H.client(client, "MapView")
	local MapRenderer = H.client(client, "MapRenderer")
	local map = H.client(client, "ClientState").map()
	local sea, land = MapGrid.decodeSea(map), MapGrid.decode(map)
	local c = MapRenderer.zoneCenterOf(zoneId)
	MapView.centreOn(c, true)
	Emulator.run(1.5)
	local spot = nil
	for r = 16, 40, 4 do
		for _, d in { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 } } do
			local p = c + Emulator.roblox.Vector2.new(d[1] * r, d[2] * r)
			if spot == nil and MapGrid.at(sea, p.X, p.Y) == zoneId and MapGrid.at(land, p.X, p.Y) == 0 then
				spot = p
			end
		end
	end
	assert(spot, "no open water found in zone " .. zoneId)
	local screen = MapView.toScreen(spot)
	Emulator.tapScreen(client, screen.X, screen.Y)
	Emulator.run(0.3)
end

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A == 1 and B == 2, "Alice is Aurora, Bob is Zephyr")
	state.nations[A].gold, state.nations[A].manpower = 1000, 20000
	state.nations[B].gold = 300
	local vega, lyra = 1, 2 -- Aurora's and Zephyr's space zones
	H.expect(state.zones[vega].name == "Vega Drift" and state.zones[lyra].name == "Lyra Reach", "the shards' zones")

	-- zoomed out, the zones' names show
	H.client(alice, "MapView").showWholeMap()
	Emulator.run(1.5)
	local zoneNames = 0
	for id in state.zones do
		zoneNames += if H.mapObject(alice, "Z" .. id) then 1 else 0
	end
	H.expect(zoneNames >= 3, "zoomed out, the zones' names show where they have room (" .. zoneNames .. " of 10)")
	H.shot(alice, "zones")

	-- build 3 starships at the capital: the Ships tile, then the 1-5 choice
	local gold = state.nations[A].gold
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	Emulator.press(alice, "Ships")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "5 ships") ~= nil, "the ships tile opens the 1-5 choice")
	H.shot(alice, "ship_picker")
	Emulator.press(alice, "Ships_3")
	Emulator.run(1.5)
	local fleet = fleetOf(state, A)
	H.expect(fleet ~= nil and Navy.ships(fleet) == 3 and fleet.zone == vega, "3 starships launch into Vega Drift")
	H.expect(state.nations[A].gold == gold - 75, "for 25 gold each")
	H.expect(H.mapObject(alice, "Fleet" .. fleet.id) ~= nil, "a fleet token is on Alice's map")
	H.expect(H.client(bob, "ClientState").fleet(fleet.id) ~= nil, "Bob sees the fleet too")

	-- recruit 3 regiments, pick the army up from the sheet, tap the fleet, Board
	for _ = 1, 3 do
		Emulator.press(alice, "Regiment")
		Emulator.run(1.2)
	end
	local army
	for _, a in state.armies do
		if a.owner == A then
			army = a
		end
	end
	H.expect(army ~= nil and army.men == 3000, "a 3k army stands at the capital")
	Emulator.press(alice, "Move")
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "or a fleet to board") ~= nil, "the army sheet says armies board fleets")
	tapFleet(alice, fleet)
	H.expect(Emulator.findText(alice, "Board in Vega Drift") ~= nil, "tapping the fleet previews boarding")
	H.shot(alice, "board_preview")
	Emulator.press(alice, "Board")
	H.expect(
		waitFor(function()
			return state.armies[army.id] == nil
		end, 10),
		"the army went aboard"
	)
	H.expect(fleet.men == 3000, "3k men are aboard")
	Emulator.run(1)
	local badge = H.mapObject(alice, "Fleet" .. fleet.id):FindFirstChild("Strength")
	H.expect(badge and badge.Text == "3 · 3k", "the fleet's badge shows its ships and the men aboard")
	H.shot(alice, "aboard")

	-- tap the fleet, tap Cinder Reach (a drift isle off Zephyr's space), Land
	local reach = provinceByName("Cinder Reach")
	tapFleet(alice, fleet)
	H.expect(
		Emulator.findText(alice, "Tap a sea to sail, or a coast to land") ~= nil,
		"the fleet sheet asks for an order"
	)
	H.expect(Emulator.findText(alice, "3k / 3k aboard") ~= nil, "it shows the men aboard out of the room")
	H.tapProvince(alice, reach)
	H.expect(Emulator.findText(alice, "Land at Cinder Reach") ~= nil, "tapping a coast previews the landing")
	H.shot(alice, "landing_preview")
	Emulator.press(alice, "Land")
	Emulator.run(4)
	H.expect(#fleet.path == 1 and fleet.path[1] == lyra and fleet.landAt == reach, "the fleet sails for Lyra Reach")
	H.shot(alice, "sailing")
	H.expect(waitText(alice, "Landed at Cinder Reach", 20), "Alice gets a toast when her army lands")
	local landed = false
	for _, a in state.armies do
		landed = landed or (a.owner == A and a.location == reach)
	end
	H.expect(landed and fleet.men == 0, "the army is ashore at Cinder Reach and the fleet is empty")
	Emulator.run(1)
	H.shot(alice, "landed")

	-- sail home: tap the fleet, tap Vega Drift's open space, Sail
	tapFleet(alice, fleet)
	tapZone(alice, vega)
	H.expect(
		Emulator.findText(alice, "Vega Drift") ~= nil and Emulator.findText(alice, "s sail") ~= nil,
		"sail preview"
	)
	Emulator.press(alice, "Sail")
	H.expect(
		waitFor(function()
			return fleet.zone == vega and #fleet.path == 0
		end, 15),
		"the fleet sailed home to Vega Drift"
	)

	-- Bob launches 2 starships from Zephyr Landing; Aurora holds Cinder Reach (a coast of Lyra Reach) and declares war
	local zephyrLanding = provinceByName("Zephyr Landing")
	H.tapProvince(bob, zephyrLanding)
	Emulator.press(bob, "Ships")
	Emulator.run(0.3)
	Emulator.press(bob, "Ships_2")
	Emulator.run(1.5)
	local bobFleet = fleetOf(state, B)
	H.expect(
		bobFleet ~= nil and bobFleet.zone == lyra and Navy.ships(bobFleet) == 2,
		"Zephyr's 2 starships in Lyra Reach"
	)
	state.provinces[reach].owner = A
	state.tick = 179
	Emulator.run(2)
	H.tapProvince(alice, zephyrLanding)
	Emulator.press(alice, "Declare")
	Emulator.run(1.5)
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	H.expect(Diplomacy.atWar(state, A, B), "Aurora and Zephyr are at war")

	-- Alice sails into Lyra Reach: a sea battle
	tapFleet(alice, fleet)
	tapZone(alice, lyra)
	Emulator.press(alice, "Sail")
	H.expect(
		waitFor(function()
			return fleet.inBattle or state.fleets[bobFleet.id] == nil
		end, 20),
		"the fleets meet in Lyra Reach"
	)
	Emulator.run(0.6)
	H.shot(alice, "sea_battle")
	H.expect(waitText(alice, "Sea battle won in Lyra Reach", 15), "Alice: sea battle won")
	H.expect(waitText(bob, "Sea battle lost in Lyra Reach", 10), "Bob: sea battle lost")
	H.expect(state.fleets[bobFleet.id] == nil, "Zephyr's beaten fleet had nowhere friendly to go and sank")
	H.expect(state.nations[A].battlesWon >= 1, "the win counts")

	-- the blockade: Zephyr's coasts in Lyra Reach, a toast for Bob, anchors on his map, no ships from his sheet
	Emulator.run(1.5)
	H.expect(state.provinces[zephyrLanding].blockade == A, "Aurora blockades Zephyr Landing")
	H.expect(waitText(bob, "Aurora blockades", 15), "Bob gets a toast when the blockade starts")
	H.tapProvince(bob, zephyrLanding)
	H.expect(Emulator.findText(bob, "Blockade: Aurora") ~= nil, "Zephyr Landing's sheet says who blockades it")
	H.expect(Emulator.findText(bob, "Blockaded") ~= nil, "its Ships tile is greyed: blockaded")
	H.expect(H.iconIn(bob, "Status" .. zephyrLanding, "anchor"), "an anchor marks the blockaded coast on Bob's map")
	H.shot(bob, "blockaded")
	Emulator.press(bob, "Ships")
	H.expect(waitText(bob, "Blockaded: no ships can launch", 10), "the server refuses ships from a blockaded coast")

	for name, client in { Alice = alice, Bob = bob } do
		local n = guiObjects(client)
		H.expect(n <= GUI_BUDGET, string.format("%s's screen holds %d GUI objects (budget %d)", name, n, GUI_BUDGET))
	end
end

return { run = run, map = "skyshards" }
