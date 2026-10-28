--!nocheck
-- Paint a map's 2D pixel art with its start owners, straight from the game's PixelArt module, into a raw RGBA file.
--   lune run tools/harness/paint <map> <out.rgba> [theme]   (theme: a map theme, e.g. night; default: classic)
local fs = require("@lune/fs")
local process = require("@lune/process")
local MapGrid = require("../../src/shared/MapGrid")
local Maps = require("../../src/shared/Maps")
local PixelArt = require("../../src/client/PixelArt")

local NATIONS = { 0xe6194b, 0x6c89f6, 0xffe119, 0x911eb4, 0xf58231, 0x469990, 0xf032e6, 0x3cd74b, 0x9a6324, 0x353535 }
local BORDERS = { 0x97233d, 0x517aa8, 0xbeab23, 0x75298a, 0xb76c33, 0x145a4f, 0xb436ab, 0x47b052, 0x7b572a, 0x2d2e2b }

local map = Maps.get(process.args[1])
local t0 = os.clock()
local grid = MapGrid.decode(map)
local art = PixelArt.new(map, grid, nil, process.args[3])
local owners, colors, borders = {}, {}, {}
for _, p in map.provinces do
	owners[p.id] = p.startOwner or 0
end
for _, n in map.nations do
	colors[n.slot] = NATIONS[n.colorIndex]
	borders[n.slot] = BORDERS[n.colorIndex]
end
PixelArt.setOwners(art, owners, colors, borders)
print(string.format("%s %s %dx%d painted in %.2f s", map.id, process.args[3] or "classic", grid.width, grid.height, os.clock() - t0))
fs.writeFile(process.args[2], buffer.tostring(art.pixels))
