--!strict
-- The 2D map painter: owners tint their provinces, selection lights one up, repaints are local.
local MapGrid = require("../src/shared/MapGrid")
local Maps = require("../src/shared/Maps")
local PixelArt = require("../src/client/PixelArt")
local T = require("./TestKit")

local map = Maps.get("skyshards")
local grid = MapGrid.decode(map)
local art = PixelArt.new(map, grid)

local function centre(id: number): (number, number)
	local p = map.provinces[id]
	return math.floor(p.center.x / grid.scale), math.floor(p.center.y / grid.scale)
end

-- a pixel inside the province, away from the centre (capitals have a castle there)
local function inside(id: number): (number, number)
	local cx, cy = centre(id)
	for r = 6, 1, -1 do
		for _, d in { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } } do
			if MapGrid.at(grid, cx + d[1], cy + d[2]) == id then
				return cx + d[1], cy + d[2]
			end
		end
	end
	return cx, cy
end

T.test("the image has one RGBA pixel per grid pixel", function()
	T.equal(buffer.len(art.pixels), grid.width * grid.height * 4)
end)

T.test("owning a province tints it in the nation's colour", function()
	local id = map.nations[1].capital
	local x, y = inside(id)
	local before = PixelArt.pixel(art, x, y)
	T.expect(PixelArt.setOwners(art, { [id] = 1 }, { [1] = 0xff0000 }), "something changed")
	local after = PixelArt.pixel(art, x, y)
	T.expect(after ~= before, "the pixel changed")
	local r, g = bit32.rshift(after, 16), bit32.band(bit32.rshift(after, 8), 255)
	T.expect(r > g, "red nation, red province")
	T.expect(not PixelArt.setOwners(art, { [id] = 1 }, { [1] = 0xff0000 }), "same owners repaint nothing")
end)

T.test("selecting a province lights it up and deselecting restores it", function()
	local id = map.nations[2].capital
	local x, y = inside(id)
	local before = PixelArt.pixel(art, x, y)
	PixelArt.select(art, id)
	T.expect(PixelArt.pixel(art, x, y) ~= before, "highlighted")
	PixelArt.select(art, nil)
	T.equal(PixelArt.pixel(art, x, y), before, "restored")
end)

T.test("a repaint leaves provinces far away untouched", function()
	local far = map.nations[6].capital
	local x, y = inside(far)
	local before = PixelArt.pixel(art, x, y)
	PixelArt.setOwners(
		art,
		{ [map.nations[1].capital] = 1, [map.nations[2].capital] = 2 },
		{ [1] = 0xff0000, [2] = 0x0000ff }
	)
	T.equal(PixelArt.pixel(art, x, y), before)
end)

T.test("a repaint reports the rectangle it changed", function()
	PixelArt.takeDirty(art)
	local id = map.nations[3].capital
	PixelArt.setOwners(art, { [id] = 3 }, { [3] = 0x00ff00 })
	local d = PixelArt.takeDirty(art)
	T.expect(d ~= nil, "a dirty rectangle")
	local box = art.boxes[id]
	local r = assert(d, "rect")
	T.expect(r[1] <= box[1] and r[2] <= box[2] and r[3] >= box[3] and r[4] >= box[4], "it covers the province")
	T.expect(PixelArt.takeDirty(art) == nil, "and is cleared once taken")
end)

T.test("capitals keep their castle when a neighbour is repainted", function()
	local id = map.nations[4].capital
	local cx, cy = centre(id)
	local before = PixelArt.pixel(art, cx, cy - 1)
	for _, other in art.touching[id] do
		PixelArt.setOwners(art, { [other] = 5 }, { [5] = 0x123456 })
		PixelArt.setOwners(art, { [other] = 0 }, { [5] = 0x123456 })
	end
	T.equal(PixelArt.pixel(art, cx, cy - 1), before)
end)

T.test("a half-resolution grid keeps nearly every province", function()
	local half = MapGrid.downsample(grid, 2)
	T.equal(half.width, grid.width // 2)
	T.equal(half.scale, grid.scale * 2)
	local seen: { [number]: boolean } = {}
	for i = 0, buffer.len(half.ids) - 1 do
		seen[buffer.readu8(half.ids, i)] = true
	end
	local kept = 0
	for _, p in map.provinces do
		if seen[p.id] then
			kept += 1
		end
	end
	T.expect(kept >= #map.provinces * 0.95, "kept " .. kept .. " of " .. #map.provinces)
end)
