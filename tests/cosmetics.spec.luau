--!strict
-- Cosmetics on the map never change a nation's colour (docs/MONETIZATION.md rule 5): border styles and shade sets
-- stay within ±8° of the nation's hue; flags and tokens are painted in the nation's own colours.
local Catalogue = require("../src/shared/Catalogue")
local CosmeticArt = require("../src/client/CosmeticArt")
local MapGrid = require("../src/shared/MapGrid")
local Maps = require("../src/shared/Maps")
local PixelArt = require("../src/client/PixelArt")
local T = require("./TestKit")

-- WorldBox's kingdom colours (src/client/Palette.luau): fill and border per nation colour index.
local FILLS = { 0xe6194b, 0x6c89f6, 0xffe119, 0x911eb4, 0xf58231, 0x469990, 0xf032e6, 0x3cd74b, 0x9a6324, 0x353535 }
local BORDERS = { 0x97233d, 0x517aa8, 0xbeab23, 0x75298a, 0xb76c33, 0x145a4f, 0xb436ab, 0x47b052, 0x7b572a, 0x2d2e2b }

-- Hue in degrees and saturation 0..1 of a 0xRRGGBB colour.
local function hue(c: number): (number, number)
	local r = bit32.rshift(c, 16) / 255
	local g = bit32.band(bit32.rshift(c, 8), 255) / 255
	local b = bit32.band(c, 255) / 255
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	if d == 0 then
		return 0, 0
	end
	local h
	if mx == r then
		h = ((g - b) / d) % 6
	elseif mx == g then
		h = (b - r) / d + 2
	else
		h = (r - g) / d + 4
	end
	return h * 60, d / mx
end

local function hueDistance(a: number, b: number): number
	local d = math.abs(a - b) % 360
	return math.min(d, 360 - d)
end

local function artOf(slot: string): { string }
	local out = {}
	for _, item in Catalogue.ofSlot(slot) do
		table.insert(out, item.art)
	end
	return out
end

T.test("border styles stay within ±8° of the nation's border hue", function()
	for i, border in BORDERS do
		local h0, s0 = hue(border)
		for _, style in artOf("Border") do
			for y = 0, 20 do
				for x = 0, 20 do
					local c = PixelArt.borderShade(style, border, x, y)
					local h, s = hue(c)
					if s0 > 0.1 and s > 0.05 then
						T.expect(
							hueDistance(h, h0) <= 8,
							string.format("%s on colour %d: hue %.1f vs %.1f", style, i, h, h0)
						)
					end
				end
			end
		end
	end
end)

T.test("shade sets stay within ±8° of the nation's colour", function()
	for i, fill in FILLS do
		local h0, s0 = hue(fill)
		for _, set in artOf("Shades") do
			for _, bright in { 30, 120, 200 } do
				local h, s = hue(PixelArt.shadeColor(set, fill, bright))
				if s0 > 0.1 then
					T.expect(s > 0.05, set .. " keeps a colour")
					T.expect(hueDistance(h, h0) <= 8, string.format("%s on colour %d: hue %.1f vs %.1f", set, i, h, h0))
				end
			end
		end
	end
end)

T.test("a shade set uses three different shades", function()
	for _, set in { "dawn", "dusk", "royal" } do
		local light = PixelArt.shadeColor(set, 0xe6194b, 200)
		local mid = PixelArt.shadeColor(set, 0xe6194b, 120)
		local dark = PixelArt.shadeColor(set, 0xe6194b, 30)
		T.expect(light ~= mid and mid ~= dark and light ~= dark, set)
	end
	T.equal(PixelArt.shadeColor("default", 0xe6194b, 200), 0xe6194b)
end)

T.test("a border style changes the map's border pixels and nothing outside the nation", function()
	local map = Maps.get("skyshards")
	local grid = MapGrid.decode(map)
	local art = PixelArt.new(map, grid)
	local owners: { [number]: number } = {}
	for _, p in map.provinces do
		if p.startOwner == 1 then
			owners[p.id] = 1
		end
	end
	PixelArt.setOwners(art, owners, { [1] = FILLS[1] }, { [1] = BORDERS[1] })
	local before = buffer.tostring(art.pixels)
	PixelArt.takeDirty(art)
	T.expect(PixelArt.setStyles(art, { [1] = { border = "dashes", shades = "default" } }), "repainted")
	T.equal(PixelArt.setStyles(art, { [1] = { border = "dashes", shades = "default" } }), false, "no change")
	local after = buffer.tostring(art.pixels)
	T.expect(before ~= after, "some border pixels changed")
	-- every changed pixel belongs to nation 1's provinces (or a castle drawn over them)
	local changed = 0
	for i = 0, art.width * art.height - 1 do
		if string.sub(before, i * 4 + 1, i * 4 + 4) ~= string.sub(after, i * 4 + 1, i * 4 + 4) then
			changed += 1
			local pid = buffer.readu8(art.ids, i)
			T.expect(owners[pid] == 1, "pixel " .. i .. " of province " .. pid .. " changed")
		end
	end
	T.expect(changed > 0, "changed pixels")
	T.expect(PixelArt.setStyles(art, {}), "back to the default")
	T.equal(buffer.tostring(art.pixels), before, "the default looks exactly as before")
end)

T.test("every flag and token design is a full grid of known colour codes", function()
	for name, rows in CosmeticArt.FLAGS do
		T.equal(#rows, CosmeticArt.FLAG_SIZE.h, name .. " height")
		for _, row in rows do
			T.equal(#row, CosmeticArt.FLAG_SIZE.w, name .. " width")
			T.expect(string.match(row, "^[NDLKWG.]+$") ~= nil, name .. " codes")
		end
	end
	for name, frames in CosmeticArt.TOKENS do
		for _, rows in frames do
			T.equal(#rows, CosmeticArt.TOKEN_SIZE.h, name .. " height")
			for _, row in rows do
				T.equal(#row, CosmeticArt.TOKEN_SIZE.w, name .. " width")
				T.expect(string.match(row, "^[NDLKWG.]+$") ~= nil, name .. " codes")
			end
		end
	end
	for _, item in Catalogue.ofSlot("Flag") do
		T.expect(CosmeticArt.FLAGS[item.art] ~= nil, "art for " .. item.id)
	end
	for _, item in Catalogue.ofSlot("Token") do
		T.expect(CosmeticArt.TOKENS[item.art] ~= nil, "art for " .. item.id)
	end
end)

T.test("a flag is painted in its nation's colour", function()
	local pixels, w, h = CosmeticArt.flag("banner", 0x3cd74b, 0x47b052)
	T.equal(w, 16)
	T.equal(h, 12)
	local c, a = CosmeticArt.pixel(pixels, w, 2, 2)
	T.equal(c, 0x3cd74b)
	T.equal(a, 255)
	T.equal((CosmeticArt.pixel(pixels, w, 0, 0)), 0x47b052, "the border colour")
	local again = CosmeticArt.flag("banner", 0xe6194b, 0x97233d)
	T.equal((CosmeticArt.pixel(again, w, 2, 2)), 0xe6194b, "another nation, another colour")
	-- every flag shows the nation's colour somewhere
	for name in CosmeticArt.FLAGS do
		local px = CosmeticArt.flag(name, 0x3cd74b, 0x47b052)
		local found = false
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				found = found or CosmeticArt.pixel(px, w, x, y) == 0x3cd74b
			end
		end
		T.expect(found, name .. " shows the nation colour")
	end
end)

T.test("animated flags wave between frames; others stay still", function()
	local a = buffer.tostring((CosmeticArt.flag("comet", 0xe6194b, 0x97233d, 0)))
	local b = buffer.tostring((CosmeticArt.flag("comet", 0xe6194b, 0x97233d, 1)))
	T.expect(a ~= b, "the comet waves")
	local c = buffer.tostring((CosmeticArt.flag("sun", 0xe6194b, 0x97233d, 0)))
	local d = buffer.tostring((CosmeticArt.flag("sun", 0xe6194b, 0x97233d, 1)))
	T.equal(c, d, "the sun doesn't")
end)

T.test("every race has a soldier: a 12×12 grid of known colour codes, outlined, in the nation's colours", function()
	local Races = require("../src/shared/Sim/Races")
	local codes = "NDLKWG."
	for code in CosmeticArt.SOLDIER_COLOURS do
		T.expect(not string.find("NDLKWG.", code, 1, true), code .. " doesn't shadow a token code")
		codes ..= code
	end
	local seen: { [string]: string } = {}
	for _, race in Races.LIST do
		local rows = CosmeticArt.SOLDIERS[race]
		T.expect(rows ~= nil, race .. " has a soldier")
		T.equal(#rows, CosmeticArt.TOKEN_SIZE.h, race .. " height")
		for _, row in rows do
			T.equal(#row, CosmeticArt.TOKEN_SIZE.w, race .. " width")
			T.expect(string.match(row, "^[" .. codes .. "]+$") ~= nil, race .. " codes: " .. row)
		end
		local px, w, h = CosmeticArt.soldier(race, 0x3cd74b, 0x47b052)
		T.equal(w, 12)
		T.equal(h, 12)
		local nation, border, outline, opaque = 0, 0, 0, 0
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local c, a = CosmeticArt.pixel(px, w, x, y)
				if a > 0 then
					opaque += 1
					nation += if c == 0x3cd74b then 1 else 0
					border += if c == 0x47b052 then 1 else 0
					outline += if c == 0x1d1d24 then 1 else 0
				end
			end
		end
		T.expect(nation >= 14, race .. " wears its nation's colour (" .. nation .. " pixels)")
		T.expect(border >= 4, race .. " has a belt in the border colour")
		T.expect(outline >= 25, race .. " is outlined")
		T.expect(opaque < 144, race .. " stands on the map, transparent round it")
		local key = buffer.tostring(px)
		T.expect(seen[key] == nil, race .. " looks different from " .. tostring(seen[key]))
		seen[key] = race
	end
	local unknown = CosmeticArt.soldier("Gnomes", 0x3cd74b, 0x47b052)
	T.expect(
		buffer.tostring(unknown) == buffer.tostring((CosmeticArt.token("square", 0x3cd74b, 0x47b052))),
		"no race: the square"
	)
end)

T.test("every map's ship is a 16×12 grid of known colour codes, outlined, in the nation's colours", function()
	local codes = "NDLKWG."
	for code in CosmeticArt.SOLDIER_COLOURS do
		codes ..= code
	end
	local seen: { [string]: string } = {}
	for _, mapId in Maps.ids do
		local name = Maps.get(mapId).ship
		local rows = CosmeticArt.SHIPS[name]
		T.expect(rows ~= nil, mapId .. " has its ship drawn: " .. name)
		T.equal(#rows, CosmeticArt.SHIP_SIZE.h, name .. " height")
		for _, row in rows do
			T.equal(#row, CosmeticArt.SHIP_SIZE.w, name .. " width")
			T.expect(string.match(row, "^[" .. codes .. "]+$") ~= nil, name .. " codes: " .. row)
		end
		local px, w, h = CosmeticArt.ship(name, 0x3cd74b, 0x47b052)
		T.equal(w, 16)
		T.equal(h, 12)
		local nation, border, outline, opaque = 0, 0, 0, 0
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local c, a = CosmeticArt.pixel(px, w, x, y)
				if a > 0 then
					opaque += 1
					nation += if c == 0x3cd74b then 1 else 0
					border += if c == 0x47b052 then 1 else 0
					outline += if c == 0x1d1d24 then 1 else 0
				end
			end
		end
		T.expect(nation >= 8, name .. " flies its nation's colour (" .. nation .. " pixels)")
		T.expect(border >= 4, name .. " has some of the border colour")
		T.expect(outline >= 20, name .. " is outlined")
		T.expect(opaque < 16 * 12 * 0.8, name .. " sails on the map, transparent round it")
		local key = buffer.tostring(px)
		T.expect(seen[key] == nil, name .. " looks different from " .. tostring(seen[key]))
		seen[key] = name
	end
	T.equal(
		buffer.tostring((CosmeticArt.ship("Raft", 1, 2))),
		buffer.tostring((CosmeticArt.ship("Galleon", 1, 2))),
		"an unknown ship is the Galleon"
	)
end)

T.test("tokens: transparent outside the sprite, animated ones have frames", function()
	local px, w = CosmeticArt.token("shield", 0xe6194b, 0x97233d)
	local _, alpha = CosmeticArt.pixel(px, w, 0, 0)
	T.equal(alpha, 0, "a transparent corner")
	T.equal((CosmeticArt.pixel(px, w, 3, 4)), 0xe6194b)
	T.equal(CosmeticArt.tokenFrames("dragon"), 2)
	T.equal(CosmeticArt.tokenFrames("shield"), 1)
	local f0 = buffer.tostring((CosmeticArt.token("dragon", 0xe6194b, 0x97233d, 0)))
	local f1 = buffer.tostring((CosmeticArt.token("dragon", 0xe6194b, 0x97233d, 1)))
	T.expect(f0 ~= f1, "the dragon flaps")
end)

T.finish()
