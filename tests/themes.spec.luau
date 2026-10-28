--!strict
-- Map themes (docs/MONETIZATION.md 3.2, rule 5): a theme re-skins the terrain only. Every nation colour and border
-- stays readable on every theme, on all three maps, and no theme changes a nation's colour.
-- THEME_REPORT=1 lune run tests/themes.spec.luau prints each theme's shares per nation colour, for tuning.
local process = require("@lune/process")

local Catalogue = require("../src/shared/Catalogue")
local MapGrid = require("../src/shared/MapGrid")
local Maps = require("../src/shared/Maps")
local PixelArt = require("../src/client/PixelArt")
local T = require("./TestKit")

-- WorldBox's kingdom colours (src/client/Palette.luau): fill and border per nation colour index.
local FILLS = { 0xe6194b, 0x6c89f6, 0xffe119, 0x911eb4, 0xf58231, 0x469990, 0xf032e6, 0x3cd74b, 0x9a6324, 0x353535 }
local BORDERS = { 0x97233d, 0x517aa8, 0xbeab23, 0x75298a, 0xb76c33, 0x145a4f, 0xb436ab, 0x47b052, 0x7b572a, 0x2d2e2b }
local NATION_ALPHA = 0.587 -- PixelArt's kingdom wash
local BORDER_ALPHA = 0.88
local READABLE = 60 -- a washed pixel this far (redmean distance) from the bare terrain reads as owned
local BORDER_READABLE = 80 -- a border pixel this far from the bare terrain next to it reads as a border
local SHARE_DROP = 0.1 -- a theme may make a nation stand out on at most this much less land than the classic look
local SHARE_FLOOR = 0.7 -- (a theme where the nation stands out on this much land always passes)
local STRIDE = 3 -- sample every 3rd pixel each way

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
end

local function mix(a: number, b: number, t: number): (number, number, number)
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t
end

-- "Redmean" colour distance: a cheap, decent approximation of how different two colours look.
local function distance(r1: number, g1: number, b1: number, c: number): number
	local r2, g2, b2 = rgb(c)
	local rm = (r1 + r2) / 2
	local dr, dg, db = r1 - r2, g1 - g2, b1 - b2
	return math.sqrt((2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db)
end

type Shares = { fill: { number }, border: { number } }

-- For each nation colour: the share of the map's land where its wash (and its border) stands out from the bare
-- themed terrain.
local function shares(mapId: string, theme: string): Shares
	local map = Maps.get(mapId)
	local grid = MapGrid.decode(map)
	local art = PixelArt.new(map, grid, nil, theme)
	local fill, border = table.create(#FILLS, 0), table.create(#FILLS, 0)
	local samples = 0
	for y = 0, art.height - 1, STRIDE do
		for x = 0, art.width - 1, STRIDE do
			local i = y * art.width + x
			if buffer.readu8(art.ids, i) ~= 0 then
				samples += 1
				local t = buffer.readu32(art.terrain, i * 4)
				for k = 1, #FILLS do
					local r, g, b = mix(t, FILLS[k], NATION_ALPHA)
					if distance(r, g, b, t) >= READABLE then
						fill[k] += 1
					end
					r, g, b = mix(t, BORDERS[k], BORDER_ALPHA)
					if distance(r, g, b, t) >= BORDER_READABLE then
						border[k] += 1
					end
				end
			end
		end
	end
	for k = 1, #FILLS do
		fill[k] /= samples
		border[k] /= samples
	end
	return { fill = fill, border = border }
end

local MAPS = { "earth", "eldmoor", "skyshards" }
local results: { [string]: { [string]: Shares } } = {}
for _, mapId in MAPS do
	results[mapId] = { classic = shares(mapId, "") }
	for _, theme in PixelArt.THEMES do
		results[mapId][theme] = shares(mapId, theme)
	end
end

if process.env.THEME_REPORT then
	for _, mapId in MAPS do
		for _, theme in { "classic", table.unpack(PixelArt.THEMES) } do
			local s = results[mapId][theme]
			local f, b = {}, {}
			for k = 1, #FILLS do
				table.insert(f, string.format("%3d", math.floor(s.fill[k] * 100)))
				table.insert(b, string.format("%3d", math.floor(s.border[k] * 100)))
			end
			print(string.format("%-9s %-7s fill %s | border %s", mapId, theme, table.concat(f), table.concat(b)))
		end
	end
end

T.test("every catalogue theme has a look PixelArt paints", function()
	local themes = Catalogue.ofSlot("Theme")
	T.expect(#themes >= 4, "the classic look and at least three themes")
	for _, item in themes do
		T.expect(item.art == "classic" or table.find(PixelArt.THEMES, item.art) ~= nil, item.id .. " has a look")
	end
	T.expect(table.find(PixelArt.THEMES, "night") ~= nil, "there is a Night theme")
end)

T.test("every nation stands out from the terrain on every theme and map", function()
	for _, mapId in MAPS do
		local classic = results[mapId].classic
		for _, theme in PixelArt.THEMES do
			local s = results[mapId][theme]
			for k = 1, #FILLS do
				T.expect(
					s.fill[k] >= SHARE_FLOOR or s.fill[k] >= classic.fill[k] - SHARE_DROP,
					string.format(
						"%s %s: nation colour %d stands out on %.0f%% of land",
						mapId,
						theme,
						k,
						s.fill[k] * 100
					)
				)
			end
		end
	end
end)

T.test("every nation's border stands out on every theme and map", function()
	for _, mapId in MAPS do
		local classic = results[mapId].classic
		for _, theme in PixelArt.THEMES do
			local s = results[mapId][theme]
			for k = 1, #FILLS do
				T.expect(
					s.border[k] >= classic.border[k] - SHARE_DROP or s.border[k] >= SHARE_FLOOR,
					string.format("%s %s: border %d stands out on %.0f%% of land", mapId, theme, k, s.border[k] * 100)
				)
			end
		end
	end
end)

T.test("a theme recolours the terrain but never a nation's colour", function()
	local map = Maps.get("earth")
	local grid = MapGrid.decode(map)
	local id = map.nations[1].capital
	local p = map.provinces[id]
	local plain = PixelArt.new(map, grid)
	-- a pixel inside the province, away from its castle, borders and province lines
	local x, y = math.floor(p.center.x / grid.scale), math.floor(p.center.y / grid.scale) + 4
	while MapGrid.at(grid, x, y) ~= id or buffer.readu8(plain.near, y * plain.width + x) ~= 0 do
		x += 1
	end
	for _, theme in PixelArt.THEMES do
		local art = PixelArt.new(map, grid, nil, theme)
		T.expect(PixelArt.pixel(art, x, y) ~= PixelArt.pixel(plain, x, y), theme .. " changes the terrain")
		PixelArt.setOwners(art, { [id] = 1 }, { [1] = FILLS[3] })
		-- the owned pixel is still exactly the wash of the nation's own colour over the themed terrain
		local t = buffer.readu32(art.terrain, (y * art.width + x) * 4)
		local r, g, b = mix(t, FILLS[3], NATION_ALPHA)
		local pr, pg, pb = rgb(PixelArt.pixel(art, x, y))
		T.expect(
			math.abs(pr - r) <= 1 and math.abs(pg - g) <= 1 and math.abs(pb - b) <= 1,
			theme .. " keeps the nation's wash"
		)
	end
end)

T.test("the classic look is the default painting", function()
	local map = Maps.get("eldmoor")
	local grid = MapGrid.decode(map)
	local a, b = PixelArt.new(map, grid), PixelArt.new(map, grid, nil, "classic")
	T.expect(buffer.tostring(a.pixels) == buffer.tostring(b.pixels), "classic paints exactly the default")
end)

T.finish()
