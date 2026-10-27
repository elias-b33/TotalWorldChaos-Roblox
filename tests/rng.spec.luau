--!strict
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")

T.test("same seed gives the same sequence", function()
	local a, b = Rng.new(42), Rng.new(42)
	for _ = 1, 100 do
		T.equal(Rng.next(a), Rng.next(b))
	end
end)

T.test("different seeds differ", function()
	T.expect(Rng.next(Rng.new(1)) ~= Rng.next(Rng.new(2)))
end)

T.test("next stays in [0, 1)", function()
	local r = Rng.new(7)
	for _ = 1, 10000 do
		local v = Rng.next(r)
		T.expect(v >= 0 and v < 1, "out of range: " .. v)
	end
end)

T.test("int covers both ends and nothing else", function()
	local r = Rng.new(99)
	local seen = {}
	for _ = 1, 2000 do
		local v = Rng.int(r, 1, 6)
		T.expect(v >= 1 and v <= 6 and v == math.floor(v), "bad roll " .. v)
		seen[v] = true
	end
	for face = 1, 6 do
		T.expect(seen[face], "never rolled " .. face)
	end
end)

T.test("seed 0 and negative seeds still work", function()
	T.expect(Rng.next(Rng.new(0)) >= 0)
	T.expect(Rng.next(Rng.new(-5)) >= 0)
end)

T.finish()
