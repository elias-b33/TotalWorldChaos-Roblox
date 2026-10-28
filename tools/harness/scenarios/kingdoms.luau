--!nocheck
-- Races on the map (docs/DESIGN.md "Map rendering"): every nation's army is a little soldier of its race, its badge
-- shows the troop type it is mostly made of (as this map draws it), and each of the map's five races builds its own
-- capital, at the whole-map, region and close-up zooms; the province sheet's recruit buttons carry the map's names
-- for its troops. Runs on any map: MAP=earth lune run tools/harness/play kingdoms (Skyshards by default). The bots
-- hold still, so every army keeps its place and make-up for the pictures.

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
	-- one army per nation at its capital: two regiments of its race's elite and one of infantry; the second nation of
	-- the first race with two nations here raises archers instead, so a shared role's icon (as this map draws it)
	-- shows too
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
		main[id] = Troops.elite(n.race)
		if byRace[n.race] ~= nil and n.race == archerRace then
			main[id] = "Archers"
		end
		local army = Army.spawn(state, id, n.capital, 2000, main[id])
		Army.add(army, { Infantry = 1000 })
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
		if sprite == nil or sprite:GetAttribute("Soldier") ~= n.race then
			table.insert(wrong, n.name)
		end
	end
	H.expect(
		#wrong == 0,
		if #wrong == 0
			then "every nation's army is a soldier of its race"
			else "not a soldier of its race: " .. table.concat(wrong, ", ")
	)
	local me = H.myNation(alice)
	local myMain = Troops.icon(mapId, main[me])
	H.expect(select(2, H.badge(alice, armies[me].id)) == myMain, "zoomed out, Alice's badge shows her main troop: " .. myMain)
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
		local wanted = Troops.icon(mapId, main[id])
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
	-- the second nation of the first race: archers, under the map's own icon for them
	local archers
	for _, id in ids do
		if main[id] == "Archers" then
			archers = id
		end
	end
	H.expect(archers ~= nil and select(2, H.badge(alice, armies[archers].id)) ~= nil, "an army of archers on the map")
	MapView.centreOn(H.provinceMap(alice, state.nations[archers].capital), true)
	Emulator.run(2)
	H.expect(
		select(2, H.badge(alice, armies[archers].id)) == Troops.icon(mapId, "Archers"),
		"its badge shows the map's archers: " .. Troops.icon(mapId, "Archers")
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
	H.expect(H.iconIn(alice, "Owner", string.lower(otherRace)), "the owner chip of a " .. otherRace .. " capital shows its race")
	H.expect(
		H.iconIn(alice, "ArmyChip" .. armies[other].id, Troops.icon(mapId, main[other])),
		"and its army's chip its elite: " .. main[other]
	)
	H.shot(alice, string.lower(otherRace) .. "_capital_sheet")
	-- Alice's own capital: one recruit button per troop her race raises, under this map's names
	Emulator.press(alice, "✕")
	state.nations[me].gold, state.nations[me].manpower = 1000, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for _, troop in Troops.available(state.nations[me].race) do
		local label = Troops.name(mapId, troop)
		H.expect(Emulator.findText(alice, label) ~= nil, "a recruit button says " .. label)
	end
	if mapId == "skyshards" then
		for _, label in { "Troopers", "Gunners", "Hover bikes" } do
			H.expect(Emulator.findText(alice, label) ~= nil, "Skyshards' shared troops: " .. label)
		end
		H.expect(Emulator.findText(alice, "Infantry") == nil, "no infantry by that name on Skyshards")
	end
	Emulator.press(alice, "Recruit_Archers")
	Emulator.press(alice, "Recruit_Archers")
	Emulator.run(1.5)
	H.expect(armies[me].troops.Archers == 2000, "two regiments of the map's archers joined Alice's army")
	H.shot(alice, "recruit_buttons")
end

return { run = run }
