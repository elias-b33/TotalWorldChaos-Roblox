--!strict
-- The map's badges (src/client/MapBadges.luau, docs/DESIGN.md "Map rendering"): army icons and sizes, status pills
-- from battles, sieges and Primordial powers, where resting armies and their badges stand, and the pip bar.
local IconArt = require("../src/client/IconArt")
local MapBadges = require("../src/client/MapBadges")
local T = require("./TestKit")
local Troops = require("../src/shared/Sim/Troops")

T.test("an army's badge icon follows its state, Rebels and garrisons first", function()
	T.equal(MapBadges.armyIcon(false, false, false, false), "sword")
	T.equal(MapBadges.armyIcon(false, false, true, false), "battle")
	T.equal(MapBadges.armyIcon(false, false, false, true), "retreat")
	T.equal(MapBadges.armyIcon(true, false, true, false), "rebels", "Rebels in a battle are still Rebels")
	T.equal(MapBadges.armyIcon(false, true, true, false), "shield", "a garrison in a battle is still a garrison")
	for _, icon in { "sword", "battle", "retreat", "rebels", "shield" } do
		T.expect(IconArt.rows(icon) ~= nil, icon .. " is a painted icon")
	end
end)

-- MapBadges.mainTroop with the game's own troop order and prices (Config.Troops), as RaceInfo calls it.
local function gold(troop: string): number
	return Troops.stats(troop :: any).gold
end
local function main(troops: { [string]: number }): string?
	return MapBadges.mainTroop(troops, Troops.LIST :: any, gold)
end

T.test("an army's main troop type is the one with the most men", function()
	T.equal(main({ Infantry = 3000 }), "Infantry")
	T.equal(main({ Infantry = 1000, Archers = 3000, Cavalry = 2000 }), "Archers", "archer-heavy")
	T.equal(main({ Infantry = 4000, Knights = 3000 }), "Infantry", "men count, not price")
	T.equal(main({ Berserkers = 2500, Infantry = 2499 }), "Berserkers")
	T.equal(main({}), nil, "an empty composition has none")
	T.equal(main({ Archers = 0 }), nil, "types with no men left don't count")
end)

T.test("a tie goes to the dearer troop, then to the later one in Troops.LIST (the elites)", function()
	T.expect(gold("Knights") > gold("Infantry"), "knights cost more than infantry")
	T.equal(main({ Infantry = 2000, Knights = 2000 }), "Knights")
	T.equal(main({ Knights = 2000, Infantry = 2000 }), "Knights", "whatever order the table is in")
	T.equal(main({ Infantry = 1000, Archers = 1000 }), "Archers")
	T.equal(main({ Infantry = 1000, Berserkers = 1000 }), "Berserkers", "12 gold beats 10")
	T.equal(gold("Cavalry"), gold("Ironguard"), "cavalry and ironguard cost the same")
	T.equal(main({ Cavalry = 1000, Ironguard = 1000 }), "Ironguard", "an equal price: the elite, later in the list")
	T.equal(main({ Infantry = 1000, Archers = 1000, Cavalry = 1000, Ironguard = 1000 }), "Ironguard")
end)

T.test(
	"the badge shows the main troop's icon, unless the army is fighting, retreating, Rebels or a garrison",
	function()
		T.equal(MapBadges.armyIcon(false, false, false, false, "archers"), "archers")
		T.equal(MapBadges.armyIcon(false, false, true, false, "archers"), "battle", "a battle's burst first")
		T.equal(MapBadges.armyIcon(false, false, false, true, "archers"), "retreat", "then the retreat flag")
		T.equal(MapBadges.armyIcon(true, false, false, false, "infantry"), "rebels", "Rebels keep their flag")
		T.equal(MapBadges.armyIcon(false, true, false, false, "infantry"), "shield", "garrisons keep their shield")
		-- every troop's icon as each map draws it (Skyshards' troopers, gunners and hover bikes) is a painted icon
		local Maps = require("../src/shared/Maps")
		for _, mapId in Maps.ids do
			for _, troop in Troops.LIST do
				local icon = MapBadges.armyIcon(false, false, false, false, Troops.icon(mapId, troop))
				T.expect(IconArt.rows(icon) ~= nil, mapId .. ": " .. troop .. "'s badge icon " .. icon .. " is painted")
			end
		end
		T.equal(Troops.icon("skyshards", "Infantry"), "troopers", "Skyshards draws its infantry as troopers")
		T.equal(Troops.icon("earth", "Infantry"), "infantry")
		T.equal(Troops.icon("earth", "HorseArchers"), "horsearchers", "an elite's icon is its id in lower case")
	end
)

T.test("army sizes are short", function()
	T.equal(MapBadges.shortMen(800), "800")
	T.equal(MapBadges.shortMen(3000), "3k")
	T.equal(MapBadges.shortMen(3750), "3.7k")
	T.equal(MapBadges.shortMen(12345), "12.3k")
end)

T.test("power badges become icon pills, the shield the power one", function()
	local pills = MapBadges.effects("🛡️25 🌟30 🦠12")
	T.equal(#pills, 3)
	T.equal(pills[1].icon, "powerShield", "a power's shield isn't the garrison's shield")
	T.equal(pills[1].text, "25")
	T.equal(pills[2].icon, "blessing")
	T.equal(pills[2].text, "30")
	T.equal(pills[3].icon, "plague")
	local strike = MapBadges.effects("☄️")
	T.equal(#strike, 1)
	T.equal(strike[1].icon, "meteor")
	T.equal(strike[1].text, "", "a strike is an icon alone")
	T.equal(#MapBadges.effects("🏴 🌋"), 2)
	T.equal(#MapBadges.effects(""), 0)
	T.equal(#MapBadges.effects("plain 42"), 0, "words without an emoji are left out")
	for _, pill in MapBadges.effects("☄️ 🦠1 🏴 🌋 🌟1 🛡️1") do
		T.expect(IconArt.rows(pill.icon) ~= nil, pill.icon .. " is a painted icon")
	end
end)

T.test("status pills: battle or siege first, then powers; brief keeps only icons", function()
	local pills = MapBadges.status(false, 45, "🛡️20", false)
	T.equal(#pills, 2)
	T.equal(pills[1].icon, "hourglass")
	T.equal(pills[1].text, "45%")
	T.equal(pills[2].icon, "powerShield")
	local battle = MapBadges.status(true, 45, nil, false)
	T.equal(#battle, 1, "a battle replaces the siege")
	T.equal(battle[1].icon, "battle")
	local brief = MapBadges.status(false, 45, "🛡️20", true)
	T.equal(brief[1].text, "")
	T.equal(brief[2].text, "")
	T.equal(#MapBadges.status(false, nil, nil, false), 0, "nothing going on: no pills")
end)

T.test("resting armies stand side by side, centred on their province", function()
	T.equal(MapBadges.slotOffset(1, 1, 18), 0, "one army stands in the middle")
	T.equal(MapBadges.slotOffset(1, 2, 18), -9)
	T.equal(MapBadges.slotOffset(2, 2, 18), 9)
	T.equal(MapBadges.slotOffset(2, 3, 18), 0)
	T.expect(MapBadges.slotOffset(3, 3, 18) - MapBadges.slotOffset(1, 3, 18) == 36, "evenly spaced")
end)

T.test("the status row stands above the badges shown", function()
	local none = MapBadges.statusLift(7, 3, 0, 23)
	local two = MapBadges.statusLift(7, 3, 2, 23)
	T.equal(none, 10, "just over the token")
	T.equal(two - none, 46, "one row per badge")
end)

T.test("development pips are a segmented bar: gold filled cells, dark empty ones, one outline", function()
	local cell = MapBadges.PIP_CELL
	local pixels, w, h = MapBadges.pips(3, 5)
	T.equal(w, 5 * (cell + 1) + 1)
	T.equal(h, cell + 2)
	T.equal(buffer.len(pixels), w * h * 4)
	local function at(x: number, y: number): number
		local i = (y * w + x) * 4
		return buffer.readu8(pixels, i) * 65536 + buffer.readu8(pixels, i + 1) * 256 + buffer.readu8(pixels, i + 2)
	end
	local p = IconArt.PALETTE
	T.equal(at(0, 0), p.K, "the corner is outline")
	T.equal(at(cell + 1, 2), p.K, "cells share an outline")
	T.equal(at(2, 2), p.Y, "the first cell is gold")
	T.equal(at(1, 1), p.y, "lit at the top left")
	T.equal(at(2 * (cell + 1) + 2, 2), p.Y, "the third cell is gold")
	T.equal(at(3 * (cell + 1) + 2, 2), p.d, "the fourth is empty")
	T.equal(at(4 * (cell + 1) + 2, 2), p.d, "the fifth is empty")
	for i = 0, w * h - 1 do
		T.equal(buffer.readu8(pixels, i * 4 + 3), 255, "the bar is opaque")
	end
	local _, w0 = MapBadges.pips(0, 5)
	T.equal(w0, w, "every level is the same size")
end)

T.finish()
