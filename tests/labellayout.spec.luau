--!strict
-- Province names that would overlap are hidden, bigger provinces first (src/client/LabelLayout.luau).

local LabelLayout = require("../src/client/LabelLayout")
local T = require("./TestKit")

local function box(id: number, x: number, y: number, priority: number): LabelLayout.Box
	return { id = id, x = x, y = y, w = 100, h = 18, priority = priority }
end

T.test("names that don't touch all show", function()
	local shown = LabelLayout.place({ box(1, 0, 0, 5), box(2, 200, 0, 1), box(3, 0, 100, 3) })
	T.expect(shown[1] and shown[2] and shown[3], "all three show")
end)

T.test("the bigger province keeps its name when two overlap", function()
	local shown = LabelLayout.place({ box(1, 0, 0, 1), box(2, 50, 5, 9) })
	T.expect(shown[2] == true, "the bigger one shows")
	T.expect(shown[1] == nil, "the smaller one is hidden")
end)

T.test("a hidden name doesn't block another", function()
	-- 2 is hidden by 1; 3 overlaps only 2, so it still shows
	local shown = LabelLayout.place({ box(1, 0, 0, 9), box(2, 90, 0, 5), box(3, 180, 0, 1) })
	T.expect(shown[1] and shown[3], "1 and 3 show")
	T.expect(shown[2] == nil, "2 is hidden")
end)

T.test("ties go to the lower id, the same way every time", function()
	local a = LabelLayout.place({ box(7, 0, 0, 4), box(3, 10, 0, 4) })
	local b = LabelLayout.place({ box(3, 10, 0, 4), box(7, 0, 0, 4) })
	T.expect(a[3] and not a[7], "id 3 wins")
	T.expect(b[3] and not b[7], "whatever the input order")
end)

T.test("names a hair apart still count as overlapping", function()
	local shown = LabelLayout.place({ box(1, 0, 0, 2), box(2, 101, 0, 1) })
	T.expect(shown[2] == nil, "the 2-pixel gap is kept")
end)

T.test("text width grows with length and size", function()
	T.expect(LabelLayout.textWidth("Nile Delta", 14) > LabelLayout.textWidth("Nubia", 14), "longer is wider")
	T.expect(LabelLayout.textWidth("Nubia", 20) > LabelLayout.textWidth("Nubia", 14), "bigger is wider")
end)

T.finish()
