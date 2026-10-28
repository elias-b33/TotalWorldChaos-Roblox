--!strict
-- The rotating shop (docs/MONETIZATION.md 3.8, Sim.ShopRotation): 4 daily and 2 weekly slots from a fixed schedule
-- seeded by the day, the same everywhere, with every rotating item back within 60 days.
local Catalogue = require("../src/shared/Catalogue")
local Config = require("../src/shared/Config")
local Login = require("../src/shared/Sim/Login")
local ShopRotation = require("../src/shared/Sim/ShopRotation")
local T = require("./TestKit")

local R = Config.ShopRotation
local FIRST_DAY = 20749 -- any day: Season 1's first

T.test("the core range: 12 items, always on sale, never rotating", function()
	T.equal(#Catalogue.CORE, 12)
	for _, id in Catalogue.CORE do
		local item = assert(Catalogue.item(id), id)
		T.expect(item.robux ~= nil, id .. " is sold")
		T.equal(ShopRotation.rotates(id), false)
		for day = FIRST_DAY, FIRST_DAY + 30 do
			T.expect(ShopRotation.onSale(id, day), id .. " on sale every day")
		end
	end
end)

T.test("what rotates: sold items outside the core range and the weekly bundles", function()
	local pools = ShopRotation.pools()
	T.expect(#pools.Common >= 2 and #pools.Rare >= 1 and #pools.Epic >= 1, "enough to fill the daily slots")
	T.expect(#pools.Legendary >= 1 and #pools.Bundle >= 1, "and the weekly ones")
	for _, item in Catalogue.ITEMS do
		local shouldRotate = item.robux ~= nil and table.find(Catalogue.CORE, item.id) == nil
		T.equal(ShopRotation.rotates(item.id), shouldRotate, item.id)
	end
	T.equal(ShopRotation.rotates("vip"), false, "VIP is always offered")
	T.equal(ShopRotation.rotates("starter"), false, "the starter pack too (no timer)")
	T.equal(ShopRotation.rotates("season_pass"), false)
	T.equal(ShopRotation.rotates("set_royal"), true, "nation skin sets rotate in the weekly slot")
end)

T.test("each day: 2 Common, 1 Rare, 1 Epic; each week: a Legendary item and a bundle; nothing twice", function()
	for day = FIRST_DAY, FIRST_DAY + 364 do
		local r = ShopRotation.rotation(day)
		T.equal(#r.daily, R.Daily.Common + R.Daily.Rare + R.Daily.Epic)
		local rarities = {}
		local seen = {}
		for _, id in r.daily do
			T.expect(not seen[id], string.format("%s twice on day %d", id, day))
			seen[id] = true
			local item = assert(Catalogue.item(id))
			rarities[item.rarity] = (rarities[item.rarity] or 0) + 1
		end
		T.equal(rarities.Common, 2)
		T.equal(rarities.Rare, 1)
		T.equal(rarities.Epic, 1)
		T.equal(#r.weekly, 2)
		T.equal(assert(Catalogue.item(r.weekly[1])).rarity, "Legendary")
		T.expect(Catalogue.offer(r.weekly[2]) ~= nil, "a bundle")
	end
end)

T.test("over 365 days every rotating item appears at least once in every 60-day window", function()
	local pools = ShopRotation.pools()
	local days = 365
	local shown: { [string]: { boolean } } = {}
	for _, pool in pools :: any do
		for _, id in pool :: { string } do
			shown[id] = table.create(days, false)
		end
	end
	for i = 1, days do
		local r = ShopRotation.rotation(FIRST_DAY + i - 1)
		for _, id in r.daily do
			shown[id][i] = true
		end
		for _, id in r.weekly do
			shown[id][i] = true
		end
	end
	for id, list in shown do
		for start = 1, days - R.ReturnDays + 1 do
			local found = false
			for i = start, start + R.ReturnDays - 1 do
				found = found or list[i]
			end
			T.expect(found, string.format("%s is missing from days %d-%d", id, start, start + R.ReturnDays - 1))
		end
	end
end)

T.test("the schedule depends only on the day: every server agrees", function()
	local a = ShopRotation.rotation(FIRST_DAY + 17)
	local b = ShopRotation.rotation(FIRST_DAY + 17)
	T.equal(table.concat(a.daily, ","), table.concat(b.daily, ","))
	T.equal(table.concat(a.weekly, ","), table.concat(b.weekly, ","))
	local changes = 0
	for day = FIRST_DAY, FIRST_DAY + 13 do
		local today = table.concat(ShopRotation.rotation(day).daily, ",")
		local tomorrow = table.concat(ShopRotation.rotation(day + 1).daily, ",")
		changes += if today ~= tomorrow then 1 else 0
		-- the weekly slots change only when a new week starts
		local sameWeek = Login.weekOf(day) == Login.weekOf(day + 1)
		local w1 = table.concat(ShopRotation.rotation(day).weekly, ",")
		local w2 = table.concat(ShopRotation.rotation(day + 1).weekly, ",")
		if sameWeek then
			T.equal(w1, w2, "same week, same weekly slots")
		end
	end
	T.equal(changes, 14, "the daily slots change every day")
end)

T.test("on sale: a rotating item only on its days", function()
	local r = ShopRotation.rotation(FIRST_DAY)
	T.expect(ShopRotation.onSale(r.daily[1], FIRST_DAY), "today's Common")
	T.expect(ShopRotation.onSale(r.weekly[2], FIRST_DAY), "this week's bundle")
	local off = 0
	for _, id in ShopRotation.pools().Rare do
		off += if ShopRotation.onSale(id, FIRST_DAY) then 0 else 1
	end
	T.equal(off, #ShopRotation.pools().Rare - 1, "one Rare a day")
end)

T.test("the view: today's slots and the time to each refresh", function()
	local monday = 20752 -- 2026-10-26, a Monday
	T.equal(Login.weekOf(monday), Login.weekOf(monday - 1) + 1, "a week starts on Monday")
	local v = ShopRotation.view(monday, 3600)
	T.equal(v.day, monday)
	T.equal(v.dailyLeft, 86400 - 3600)
	T.equal(v.weeklyLeft, 7 * 86400 - 3600)
	local sunday = ShopRotation.view(monday + 6, 0)
	T.equal(sunday.weeklyLeft, 86400, "Sunday: one day left")
	T.equal(#v.daily, 4)
	T.equal(#v.weekly, 2)
end)

T.test("pick: k distinct items a period and a cycle of ceil(n / k) periods", function()
	local pool = { "a", "b", "c", "d", "e" }
	T.equal(ShopRotation.cycleLength(5, 2), 3)
	local seen: { [string]: number } = {}
	for period = 0, 2 do
		local got = ShopRotation.pick(pool, 2, period, 9)
		T.equal(#got, 2)
		T.expect(got[1] ~= got[2], "distinct")
		for _, id in got do
			seen[id] = (seen[id] or 0) + 1
		end
	end
	for _, id in pool do
		T.expect(seen[id] ~= nil, id .. " shown in its cycle")
	end
	T.equal(#ShopRotation.pick({}, 2, 0, 1), 0, "an empty pool fills nothing")
end)

T.finish()
