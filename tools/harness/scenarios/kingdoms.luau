--!nocheck
-- Races on the map (docs/DESIGN.md "Map rendering"): every nation's army is a little soldier of the troop it is mostly
-- made of, its badge shows that troop's icon, and each of the map's five races builds its own capital, at the
-- whole-map, region and close-up zooms; the province sheet's recruit buttons are the five troops of the player's race,
-- and the soldier follows when recruits change an army's main troop. Runs on any map: MAP=earth lune run
-- tools/harness/play kingdoms (Skyshards by default). The bots hold still, so every army keeps its place and make-up
-- for the pictures.

local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local Army = require("../../../src/shared/Sim/Army")
	local Races = require("../../../src/shared/Sim/Races")
	local Troops = require("../../../src/shared/Sim/Troops")
	H.server("Services.AIService").step = function() end
	Emulator.run(1.1) -- (orders the bots gave before go through)
	local state = H.state()
	local mapId = state.mapId
	local cast = Races.forMap(mapId)
	H.expect(#cast == 5, mapId .. " has its own cast of five races: " .. table.concat(cast, ", "))
	for id, a in state.armies do
		if a.owner ~= 0 then
			state.armies[id] = nil
		end
	end
	-- one army per nation at its capital: two regiments of its race's elite and one of its line troop; the second
	-- nation of the first race with two nations here raises its ranged troop instead, so a ranged troop shows too
	local main, armies, byRace = {}, {}, {}
	local ids = {} -- (a match with fewer players than nations keeps nine bots: one nation may be gone)
	local count: { [string]: number } = {}
	for id, n in state.nations do
		table.insert(ids, id)
		count[n.race] = (count[n.race] or 0) + 1
	end
	table.sort(ids)
	local archerRace
	for _, race in cast do
		if archerRace == nil and (count[race] or 0) >= 2 then
			archerRace = race
		end
	end
	for _, id in ids do
		local n = state.nations[id]
		main[id] = Troops.ofRole(n.race, "elite")
		if byRace[n.race] ~= nil and n.race == archerRace then
			main[id] = Troops.ofRole(n.race, "ranged")
		end
		local army = Army.spawn(state, id, n.capital, 2000, main[id])
		Army.add(army, { [Troops.ofRole(n.race, "line")] = 1000 })
		armies[id] = army
		byRace[n.race] = byRace[n.race] or id
	end
	local MapView = H.client(alice, "MapView")
	MapView.showWholeMap()
	Emulator.run(1.5)
	local wrong = {}
	for id, n in state.nations do
		local token = H.mapObject(alice, "Army" .. armies[id].id)
		local sprite = token and token:FindFirstChild("TokenSkin")
		if sprite == nil or sprite:GetAttribute("Soldier") ~= main[id] then
			table.insert(wrong, n.name)
		end
	end
	H.expect(
		#wrong == 0,
		if #wrong == 0
			then "every nation's army is a soldier of its main troop"
			else "not a soldier of its main troop: " .. table.concat(wrong, ", ")
	)
	local me = H.myNation(alice)
	local myMain = Troops.icon(main[me])
	H.expect(
		select(2, H.badge(alice, armies[me].id)) == myMain,
		"zoomed out, Alice's badge shows her main troop: " .. myMain
	)
	H.shot(alice, "whole_map")
	-- each race's capital and army, at the region zoom and close up; every badge shows its army's main troop
	for _, race in cast do
		local id = byRace[race]
		H.expect(id ~= nil, "a nation of the " .. race)
		local capital = state.nations[id].capital
		MapView.showWholeMap()
		MapView.centreOn(H.provinceMap(alice, capital), true) -- the region zoom
		Emulator.run(2)
		local _, icon = H.badge(alice, armies[id].id)
		local wanted = Troops.icon(main[id])
		H.expect(icon == wanted, state.nations[id].name .. "'s badge shows " .. wanted .. " (" .. tostring(icon) .. ")")
		H.shot(alice, string.lower(race) .. "_region")
		Emulator.pinch(alice, 3)
		MapView.centreOn(H.provinceMap(alice, capital), false) -- (a pinch zooms round the screen's middle)
		Emulator.run(2)
		-- the building reaches 3 map pixels below the capital's centre (PixelArt): its name stands below that
		local name = H.mapObject(alice, "P" .. capital)
		H.expect(
			name ~= nil and name.Position.Y.Offset >= 3 * MapView.zoom(),
			state.nations[id].name .. "'s capital name stands below its building, close up"
		)
		H.shot(alice, string.lower(race) .. "_close")
	end
	-- the second nation of the first race: its ranged troop
	local archers
	for _, id in ids do
		if main[id] == Troops.ofRole(state.nations[id].race, "ranged") then
			archers = id
		end
	end
	H.expect(
		archers ~= nil and select(2, H.badge(alice, armies[archers].id)) ~= nil,
		"an army of ranged troops on the map"
	)
	MapView.centreOn(H.provinceMap(alice, state.nations[archers].capital), true)
	Emulator.run(2)
	H.expect(
		select(2, H.badge(alice, armies[archers].id)) == Troops.icon(main[archers]),
		"its badge shows its ranged troop: " .. Troops.icon(main[archers])
	)
	-- the province sheet of another race's capital: the owner chip shows its race (no war, ally or truce to show),
	-- the army chip its elite
	local other
	for _, race in cast do
		if other == nil and byRace[race] and state.nations[byRace[race]].race ~= state.nations[me].race then
			other = byRace[race]
		end
	end
	local otherRace = state.nations[other].race
	H.tapProvince(alice, state.nations[other].capital)
	H.expect(
		H.iconIn(alice, "Owner", string.lower(otherRace)),
		"the owner chip of a " .. otherRace .. " capital shows its race"
	)
	H.expect(
		H.iconIn(alice, "ArmyChip" .. armies[other].id, Troops.icon(main[other])),
		"and its army's chip its elite: " .. main[other]
	)
	H.shot(alice, string.lower(otherRace) .. "_capital_sheet")
	-- Alice's own capital: one recruit button per troop of her race's roster, under its own name
	Emulator.press(alice, "✕")
	local myRace = state.nations[me].race
	state.nations[me].gold, state.nations[me].manpower = 1000, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for _, troop in Troops.roster(myRace) do
		H.expect(H.button(alice, "Recruit_" .. troop) ~= nil, "a recruit button for " .. troop)
		H.expect(Emulator.findText(alice, Troops.name(troop)) ~= nil, "it says " .. Troops.name(troop))
	end
	if mapId ~= "earth" then
		for _, label in { "Infantry", "Archers", "Cavalry", "Catapults" } do
			H.expect(Emulator.findText(alice, label) == nil, "no Earth troop here: " .. label)
		end
	end
	-- three regiments of her ranged troop outnumber her elite: the army's soldier and badge follow
	local ranged = Troops.ofRole(myRace, "ranged")
	for _ = 1, 3 do
		Emulator.press(alice, "Recruit_" .. ranged)
	end
	Emulator.run(1.5)
	H.expect(armies[me].troops[ranged] == 3000, "three regiments of " .. ranged .. " joined Alice's army")
	local sprite = H.mapObject(alice, "Army" .. armies[me].id):FindFirstChild("TokenSkin")
	H.expect(sprite ~= nil and sprite:GetAttribute("Soldier") == ranged, "its soldier is now one of her " .. ranged)
	H.expect(select(2, H.badge(alice, armies[me].id)) == Troops.icon(ranged), "and so is its badge")
	H.shot(alice, "recruit_buttons")
end

return { run = run }
