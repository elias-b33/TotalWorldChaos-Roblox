--!nocheck
-- Paint a map's 2D pixel art with its start owners, straight from the game's PixelArt module, into a raw RGBA file.
--   lune run tools/harness/paint <map> <out.rgba> [theme]                    the whole map (theme: e.g. night)
--   lune run tools/harness/paint <map> <out.rgba> <theme> <x> <y> <w> <h>    the close-up detail of map pixels
--                                                                             x.. y.. (w × h sub-pixels)
-- Prints how long each painting took.
local fs = require("@lune/fs")
local process = require("@lune/process")
local MapGrid = require("../../src/shared/MapGrid")
local Maps = require("../../src/shared/Maps")
local PixelArt = require("../../src/client/PixelArt")

local NATIONS = { 0xe6194b, 0x6c89f6, 0xffe119, 0x911eb4, 0xf58231, 0x469990, 0xf032e6, 0x3cd74b, 0x9a6324, 0x353535 }
local BORDERS = { 0x97233d, 0x517aa8, 0xbeab23, 0x75298a, 0xb76c33, 0x145a4f, 0xb436ab, 0x47b052, 0x7b572a, 0x2d2e2b }

local map = Maps.get(process.args[1])
local theme = process.args[3]
if theme == "classic" then
	theme = nil
end
local t0 = os.clock()
local grid = MapGrid.decode(map)
local art = PixelArt.new(map, grid, nil, theme)
local owners, colors, borders = {}, {}, {}
for _, p in map.provinces do
	owners[p.id] = p.startOwner or 0
end
for _, n in map.nations do
	colors[n.slot] = NATIONS[n.colorIndex]
	borders[n.slot] = BORDERS[n.colorIndex]
end
PixelArt.setOwners(art, owners, colors, borders)
print(
	string.format(
		"%s %s %dx%d painted in %.2f s",
		map.id,
		process.args[3] or "classic",
		grid.width,
		grid.height,
		os.clock() - t0
	)
)
if process.args[4] then
	local x, y = tonumber(process.args[4]), tonumber(process.args[5])
	local w, h = tonumber(process.args[6]), tonumber(process.args[7])
	local detail = PixelArt.newDetail(w, h)
	local best = math.huge
	for _ = 1, 3 do
		local t1 = os.clock()
		PixelArt.paintDetail(art, detail, x, y)
		best = math.min(best, os.clock() - t1)
	end
	print(string.format("  close-up %dx%d at (%d, %d) painted in %.0f ms", w, h, detail.x0, detail.y0, best * 1000))
	fs.writeFile(process.args[2], buffer.tostring(detail.pixels))
else
	fs.writeFile(process.args[2], buffer.tostring(art.pixels))
end
