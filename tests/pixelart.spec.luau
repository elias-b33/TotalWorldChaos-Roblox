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

------------------------------------------------------------------------------------------------- close-up detail

local D = PixelArt.DETAIL
local F = D.factor
local RED, BLUE = 0xe6194b, 0x6c89f6
local RED_BORDER, BLUE_BORDER = 0x97233d, 0x517aa8

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
end

local function mix(a: number, b: number, t: number): number
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	local function round(v: number): number
		return math.clamp(math.floor(v + 0.5), 0, 255)
	end
	return round(r1 + (r2 - r1) * t) * 65536 + round(g1 + (g2 - g1) * t) * 256 + round(b1 + (b2 - b1) * t)
end

local function close(a: number, b: number): boolean
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	return math.abs(r1 - r2) <= 1 and math.abs(g1 - g2) <= 1 and math.abs(b1 - b2) <= 1
end

-- A straight vertical edge between two provinces: map pixels (x, y) | (x + 1, y), each with its own province above
-- and below too, so no corner of either is cut. Searched near a nation's capital.
local function straightEdge(near: number): (number, number, number, number)
	local cx, cy = centre(near)
	for r = 0, 60 do
		for y = cy - r, cy + r do
			for x = cx - r, cx + r do
				local a, b = MapGrid.at(grid, x, y), MapGrid.at(grid, x + 1, y)
				if
					a ~= 0
					and b ~= 0
					and a ~= b
					and MapGrid.at(grid, x - 1, y) == a
					and MapGrid.at(grid, x + 2, y) == b
					and MapGrid.at(grid, x, y - 1) == a
					and MapGrid.at(grid, x, y + 1) == a
					and MapGrid.at(grid, x + 1, y - 1) == b
					and MapGrid.at(grid, x + 1, y + 1) == b
				then
					return x, y, a, b
				end
			end
		end
	end
	error("no straight edge")
end

local ex, ey, provA, provB = straightEdge(map.nations[1].capital)
local close1 = PixelArt.new(map, grid)
PixelArt.setOwners(
	close1,
	{ [provA] = 1, [provB] = 2 },
	{ [1] = RED, [2] = BLUE },
	{ [1] = RED_BORDER, [2] = BLUE_BORDER }
)
local W, H = 320, 192 -- close-up size in sub-pixels (80 × 48 map pixels)
local function closeUpAt(art: PixelArt.Art, x0: number, y0: number): PixelArt.Detail
	local d = PixelArt.newDetail(W, H)
	PixelArt.paintDetail(art, d, x0, y0)
	return d
end
local ox, oy = PixelArt.detailOrigin(close1, PixelArt.newDetail(W, H), ex, ey)
local detail = closeUpAt(close1, ox, oy)
-- the edge's sub-pixel row in the middle of map pixel row ey, and the sub-pixel column of pixel ex's left side
local edgeY = (ey - detail.y0) * F + F // 2
local edgeX = (ex - detail.x0) * F

T.test("a close-up paints the same pixels every time, and overlapping close-ups agree", function()
	local again = closeUpAt(close1, ox, oy)
	T.expect(buffer.tostring(again.pixels) == buffer.tostring(detail.pixels), "the same close-up twice")
	local shifted = closeUpAt(close1, ox + 13, oy + 9)
	T.equal(shifted.x0, ox + 13)
	local dx, dy = 13 * F, 9 * F
	local differ = 0
	for y = dy, H - 1 do
		for x = dx, W - 1 do
			if PixelArt.detailPixel(detail, x, y) ~= PixelArt.detailPixel(shifted, x - dx, y - dy) then
				differ += 1
			end
		end
	end
	T.equal(differ, 0, "pixels that differ where the two overlap")
end)

T.test("a close-up washes owned land lighter than the whole map, terrain showing through", function()
	T.expect(D.alpha < 0.587, "a lighter wash than the whole map's")
	-- a map pixel deep inside province A
	local found = false
	for y = detail.y0 + 2, detail.y0 + detail.rows - 3 do
		for x = detail.x0 + 2, detail.x0 + detail.cols - 3 do
			local inner = true
			for _, d in
				{ { 0, 0 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }
			do
				if MapGrid.at(grid, x + d[1], y + d[2]) ~= provA then
					inner = false
				end
			end
			if inner and not found then
				found = true
				local sx, sy = (x - detail.x0) * F + 1, (y - detail.y0) * F + 1
				local t = PixelArt.detailTerrain(detail, sx, sy)
				T.expect(close(PixelArt.detailPixel(detail, sx, sy), mix(t, RED, D.alpha)), "the nation's wash")
			end
		end
	end
	T.expect(found, "a pixel deep inside the province")
end)

T.test("a close-up draws each nation's border and rim exactly", function()
	for k = 0, F - 1 do
		local x = edgeX + k -- province A's side of the edge, left to right
		local t = PixelArt.detailTerrain(detail, x, edgeY)
		local want = if k >= F - D.border
			then mix(t, RED_BORDER, D.borderAlpha)
			elseif k >= F - D.border - D.rim then mix(t, RED, D.rimAlpha)
			else nil
		if want then
			T.expect(close(PixelArt.detailPixel(detail, x, edgeY), want), "red border or rim at sub-pixel " .. k)
		end
		T.equal(PixelArt.detailProvince(detail, x, edgeY), provA, "province A's sub-pixel")
	end
	for k = 0, D.border - 1 do
		local x = edgeX + F + k -- province B's side
		local t = PixelArt.detailTerrain(detail, x, edgeY)
		T.expect(close(PixelArt.detailPixel(detail, x, edgeY), mix(t, BLUE_BORDER, D.borderAlpha)), "blue border")
	end
	local inside = edgeX + F + D.border + D.rim
	local t = PixelArt.detailTerrain(detail, inside, edgeY)
	T.expect(not close(PixelArt.detailPixel(detail, inside, edgeY), mix(t, BLUE_BORDER, D.borderAlpha)), "border ends")
end)

T.test("selecting a province shows in the close-up, and deselecting restores it", function()
	local before = buffer.tostring(detail.pixels)
	PixelArt.select(close1, provA)
	T.expect(PixelArt.syncDetail(close1, detail), "the close-up caught up")
	T.equal(PixelArt.detailPixel(detail, edgeX + F - 1, edgeY), 0xffffff, "a white outline")
	T.expect(buffer.tostring(detail.pixels) ~= before, "highlighted")
	PixelArt.select(close1, nil)
	PixelArt.syncDetail(close1, detail)
	T.expect(buffer.tostring(detail.pixels) == before, "restored exactly")
	T.expect(not PixelArt.syncDetail(close1, detail), "nothing left to catch up")
end)

T.test("an ownership change repaints only its part of the close-up, the same as a fresh painting", function()
	PixelArt.takeDetailDirty(detail)
	local before = buffer.tostring(detail.pixels)
	PixelArt.setOwners(close1, { [provA] = 1, [provB] = 1 }, { [1] = RED, [2] = BLUE }, { [1] = RED_BORDER })
	T.expect(PixelArt.syncDetail(close1, detail), "something changed")
	T.expect(buffer.tostring(detail.pixels) ~= before, "pixels changed")
	local fresh = closeUpAt(close1, ox, oy)
	T.expect(buffer.tostring(fresh.pixels) == buffer.tostring(detail.pixels), "the repaint matches a fresh painting")
	local rect = assert(PixelArt.takeDetailDirty(detail), "a dirty rectangle")
	local box = close1.boxes[provB]
	T.expect(
		rect[1] <= math.max((box[1] - detail.x0) * F, 0)
			and rect[3] >= math.min((box[3] - detail.x0 + 1) * F - 1, W - 1),
		"it covers province B"
	)
	T.expect(rect[3] - rect[1] < W - 1 or rect[4] - rect[2] < H - 1, "and not the whole close-up")
end)

T.test("capitals keep their castle on top in the close-up", function()
	local id = map.nations[1].capital
	local art = PixelArt.new(map, grid)
	PixelArt.setOwners(art, { [id] = 1 }, { [1] = RED })
	local cx, cy = centre(id)
	local d = closeUpAt(art, cx - 40, cy - 24)
	-- the flag at the top of the keep (the dome on Skyshards), in the owner's colour
	local x0 = (cx - d.x0) * F + F // 2 - 10
	local y0 = (cy + 3 - d.y0) * F - 22
	T.equal(PixelArt.detailPixel(d, x0 + 11, y0 + 1), RED, "the owner's flag")
	for _, other in art.touching[id] do
		PixelArt.setOwners(art, { [id] = 1, [other] = 2 }, { [1] = RED, [2] = BLUE })
	end
	PixelArt.syncDetail(art, d)
	T.equal(PixelArt.detailPixel(d, x0 + 11, y0 + 1), RED, "still there after the neighbours are repainted")
end)

T.test("a theme recolours the close-up's terrain, never the nation's wash", function()
	local night = PixelArt.new(map, grid, nil, "night")
	PixelArt.setOwners(night, { [provA] = 1 }, { [1] = RED })
	local d = closeUpAt(night, ox, oy)
	local x, y = edgeX - 2 * F, edgeY
	T.expect(PixelArt.detailTerrain(d, x, y) ~= PixelArt.detailTerrain(detail, x, y), "night terrain")
	local t = PixelArt.detailTerrain(d, x, y)
	T.expect(close(PixelArt.detailPixel(d, x, y), mix(t, RED, D.alpha)), "the same wash on the themed terrain")
end)

T.test("Earth's close-up has beaches, surf and trees", function()
	local earth = Maps.get("earth")
	local egrid = MapGrid.decode(earth)
	local art = PixelArt.new(earth, egrid)
	local d = PixelArt.newDetail(1024, 420)
	local t0 = os.clock()
	PixelArt.paintDetail(art, d, 480, 150)
	local ms = (os.clock() - t0) * 1000
	print(string.format("       (a 1024×420 close-up of Earth painted in %.0f ms)", ms))
	local seen: { [number]: number } = {}
	for y = 0, d.height - 1, 2 do
		for x = 0, d.width - 1, 2 do
			local c = PixelArt.detailPixel(d, x, y)
			seen[c] = (seen[c] or 0) + 1
		end
	end
	T.expect((seen[0xf7e898] or 0) > 50, "beach sand")
	T.expect((seen[0xd4f0fc] or 0) > 50, "white surf")
	T.expect((seen[0x86bc4e] or 0) + (seen[0x65a13f] or 0) > 50, "tree canopies")
	T.expect(ms < 1000, "painted in well under a second")
end)

T.finish()
