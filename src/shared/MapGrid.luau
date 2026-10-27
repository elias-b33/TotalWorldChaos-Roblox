--!strict
-- The 2D map's province grid: which province every pixel of the pixel-art map belongs to (0 = sea or sky).
-- MapData stores it run-length encoded (Types.GridDef); decode it once per match. Pure Luau, so it loads in
-- Roblox and Lune alike.

local Types = require("./Types")

local MapGrid = {}

export type Grid = {
	width: number,
	height: number,
	ids: buffer, -- width * height bytes, row by row from the top-left
	scale: number, -- map pixels (Types.Point, ProvinceDef.center) per grid pixel
}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local VALUE: { [number]: number } = {}
for i = 1, #ALPHABET do
	VALUE[string.byte(ALPHABET, i)] = i - 1
end

local function fromBase64(s: string): buffer
	local padding = if string.sub(s, -2) == "==" then 2 elseif string.sub(s, -1) == "=" then 1 else 0
	local size = #s // 4 * 3 - padding
	local out = buffer.create(size)
	local o = 0
	for i = 1, #s, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local n = VALUE[a] * 262144 + VALUE[b] * 4096 + (VALUE[c] or 0) * 64 + (VALUE[d] or 0)
		for shift = 16, 0, -8 do
			if o < size then
				buffer.writeu8(out, o, bit32.band(bit32.rshift(n, shift), 255))
				o += 1
			end
		end
	end
	return out
end

function MapGrid.decode(map: Types.MapDef): Grid
	local def = map.grid
	local runs = fromBase64(def.rle)
	local ids = buffer.create(def.width * def.height)
	local o = 0
	for i = 0, buffer.len(runs) - 3, 3 do
		local n = buffer.readu16(runs, i + 1)
		buffer.fill(ids, o, buffer.readu8(runs, i), n)
		o += n
	end
	assert(o == def.width * def.height, "province grid has the wrong size")
	return { width = def.width, height = def.height, ids = ids, scale = map.imageSize.x / def.width }
end

-- The province at grid pixel (x, y), 0-based; 0 for sea, sky or outside the map.
function MapGrid.at(grid: Grid, x: number, y: number): number
	x, y = math.floor(x), math.floor(y)
	if x < 0 or y < 0 or x >= grid.width or y >= grid.height then
		return 0
	end
	return buffer.readu8(grid.ids, y * grid.width + x)
end

return MapGrid
