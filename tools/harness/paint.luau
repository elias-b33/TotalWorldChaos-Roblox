--!nocheck
-- Paint a map's 2D pixel art with its start owners, straight from the game's PixelArt module, into a raw RGBA file.
--   lune run tools/harness/paint <map> <out.rgba>      (then render_scene.py's helpers turn it into a PNG)
local fs = require("@lune/fs")
local process = require("@lune/process")
local MapGrid = require("../../src/shared/MapGrid")
local Maps = require("../../src/shared/Maps")
local PixelArt = require("../../src/client/PixelArt")

local NATIONS = { 0xd7263d, 0x26358f, 0xf4c430, 0x8e44ad, 0xf17c1f, 0x17b8b8, 0xe84aa6, 0x7ac943, 0x8b5a2b, 0x3c3c46 }

local map = Maps.get(process.args[1])
local t0 = os.clock()
local grid = MapGrid.decode(map)
local art = PixelArt.new(map, grid)
local owners, colors = {}, {}
for _, p in map.provinces do
	owners[p.id] = p.startOwner or 0
end
for _, n in map.nations do
	colors[n.slot] = NATIONS[n.colorIndex]
end
PixelArt.setOwners(art, owners, colors)
print(string.format("%s %dx%d painted in %.2f s", map.id, grid.width, grid.height, os.clock() - t0))
fs.writeFile(process.args[2], buffer.tostring(art.pixels))
