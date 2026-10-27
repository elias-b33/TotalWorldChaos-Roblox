--!strict
-- The 2D pixel-art map, painted pixel by pixel from the province grid in WorldBox's own colours (tile colours,
-- tree icons, water depths, mountain bands and kingdom overlay taken from WorldBox's game data; see
-- docs/MAPS.md "The 2D pixel-art map"). Owned provinces get their nation's colour as a translucent wash with a
-- 1-pixel border in the nation's darker colour, like kingdoms in WorldBox.
-- Pure Luau on buffers (no Roblox APIs), so the same code paints the map in the game and in Lune tests.
-- Colours are packed 0xRRGGBB integers; `pixels` is RGBA bytes, ready for EditableImage:WritePixelsBuffer.

local PixelArt = {}

export type Grid = { width: number, height: number, ids: buffer, scale: number }

type Style = {
	base: number,
	light: number,
	dark: number,
	high: number?, -- patches of the tile's darker "high" variant, like WorldBox's elevation tiles
	deco: string,
	sprite: { [string]: number }?, -- colours of the decoration sprites
}

export type Art = {
	width: number,
	height: number,
	ids: buffer,
	theme: string,
	terrain: buffer, -- 0xRRGGBB per pixel (u32)
	pixels: buffer, -- RGBA per pixel
	boxes: { [number]: { number } }, -- province id -> { x0, y0, x1, y1 }, inclusive
	touching: { [number]: { number } }, -- provinces sharing a pixel edge
	owner: { [number]: number }, -- province id -> nation slot (0 = neutral)
	color: { [number]: number }, -- nation slot -> colour
	border: { [number]: number }, -- nation slot -> border colour
	capitals: { [number]: { x: number, y: number } },
	selected: number,
	near: buffer, -- per pixel: which border checks it needs (NEAR_* bits), worked out once per map
	dirty: { number }?, -- x0, y0, x1, y1 of what changed since the last takeDirty
}

-- Called now and then while painting a whole map, so a client can spread the work over several frames.
export type Yield = () -> ()

local function style(
	base: number,
	light: number,
	dark: number,
	deco: string,
	high: number?,
	sprite: { [string]: number }?
): Style
	return { base = base, light = light, dark = dark, deco = deco, high = high, sprite = sprite }
end

local FOREST_TREE = { L = 0x86bc4e, M = 0x65a13f, D = 0x3f6b3f, S = 0x304e32 }

-- WorldBox tile colours (base, light and dark sprite shades, high variant) for each of our biomes.
local BIOMES: { [string]: Style } = {
	-- Earth
	grassland = style(0x7eaf46, 0x81b647, 0x709940, "flowers", 0x5f833c), -- grass_low
	steppe = style(0xaca979, 0xb2b07d, 0x9d9b72, "", 0x8c8e65), -- garlic_low
	savanna = style(0xf0b121, 0xffbd29, 0xd99e0c, "savanna", 0xcf931b, { L = 0xb78727, M = 0x757b33, D = 0x4b3927 }),
	tundra = style(0xbad5d3, 0xc5dfd4, 0x9abfbb, "", 0xd3e4e3), -- frozen_low
	desert = style(0xe8c76e, 0xf7e898, 0xc9a36d, "palms", 0xe1ba5a, { L = 0x75b163, M = 0x699963, T = 0xb1a575 }),
	drylands = style(0xe2934b, 0xe1ba5a, 0xc07e43, "", 0xb66f3a), -- soil_low
	forest = style(0x5f833c, 0x86bc4e, 0x3f6b3f, "trees", nil, FOREST_TREE), -- grass_high + trees
	jungle = style(0x46a052, 0x44b055, 0x2a682f, "jungle", 0x1f7020, { L = 0x4b8139, M = 0x3f693f, D = 0x274b2d }),
	taiga = style(0x99bcdb, 0xb4cfe5, 0x84b2dc, "pines", nil, { L = 0x45816f, M = 0x4b696f, D = 0x3f575d }), -- permafrost
	hills = style(0x849371, 0x91a07d, 0x727f62, "hills", 0x6c7759, { L = 0x91a07d, M = 0x849371, P = 0x5e684d }),
	mountains = style(0x5b5e5c, 0x5f5f5f, 0x414545, "rock"),
	ice = style(0xe2edec, 0xfcfdfd, 0xc9dedd, "", 0xd3e4e3), -- snow_hills
	-- Eldmoor
	meadow = style(0x54cc3a, 0x8cdc6a, 0x39a334, "flowers", 0x39a334), -- flower_low
	frostfields = style(0x99bcdb, 0xbdd6e8, 0x84b2dc, "", 0xb4cfe5), -- permafrost_low
	dunes = style(0xe1ba5a, 0xe8c76e, 0xbf8f54, "", 0xe8c76e), -- desert_high
	wildwood = style(0x76b153, 0x8cdc6a, 0x5f833c, "trees", nil, { L = 0xed93c9, M = 0xdb81b7, D = 0xb15d93 }), -- enchanted
	highlands = style(0x5f833c, 0x7eaf46, 0x4b762f, "hills", nil, { L = 0x7eaf46, M = 0x5f833c, P = 0x3f6129 }),
	ashlands = style(0x68372d, 0xe9290e, 0x592f29, "", 0x9c3626), -- infernal_high; the light specks are lava glints
	peaks = style(0x414545, 0x5b5e5c, 0x333333, "rock"),
	-- Skyshards: sci-fi platforms (WorldBox's flower fields, cyber tile, celestial crystals, grey goo, iron walls)
	skymeadow = style(0x54cc3a, 0x8cdc6a, 0x39a334, "rows", nil, { R = 0xa8663a }),
	heartruins = style(0x9ea6a3, 0xd5e2ea, 0x858886, "panels", nil, { R = 0x5b5b5b, C = 0xf55858, E = 0x7cfbef }),
	crystalgrove = style(0x7f5da2, 0xb573da, 0x564180, "crystals", nil, { C = 0x7cfbef, M = 0x64f1e2, D = 0x56c9bd }),
	crags = style(0x5d6191, 0x686da3, 0x4f537c, "plates"), -- grey_goo
	stormspire = style(0x3a485e, 0x597d94, 0x2e363e, "towers", nil, { C = 0xf55858, G = 0xd5e2ea, B = 0xbd8137 }),
}
local FALLBACK = BIOMES.grassland

local FLOWERS = { 0xc96b90, 0xd08651, 0xab81c0, 0xc7d8b4, 0xddb847, 0x7f9da9 }

-- WorldBox's ocean: shallow, close and deep water, each flat, with darker lips where it gets deeper and a shadow
-- line on water just south of land. Light comes from the top, so lips and shadows always fall on the south side.
local SEA = {
	shallow = 0x55aef0,
	medium = 0x4084e2,
	deep = 0x3370cc,
	shallowLip = 0x3f90ea,
	mediumLip = 0x3c7cd1,
	shallowWave = 0x63bcf1,
	mediumWave = 0x488fe5,
	shadow = 0x2d61af,
	beach = 0xf7e898,
	beachLip = 0xd8c08c,
}
local SHALLOW_TO = 2 -- water up to this many pixels from land is shallow
local MEDIUM_TO = 6 -- then close ocean up to here, then deep ocean

-- Mountains, in WorldBox's rock tiles: hills rock with winding ridges of mountain rock, summit crests on the
-- ridges and a few snow caps on the highest points. Each band has a dark lip on its south side; ridges are lit
-- from the west (a) and shaded on the east (b).
local ROCK = {
	{ base = 0x5b5e5c, a = 0x575757, b = 0x525252, lip = 0x313333 },
	{ base = 0x414545, a = 0x474747, b = 0x313131, lip = 0x2c3032 },
	{ base = 0x333333, a = 0x3f3f3f, b = 0x2b2b2b, lip = 0x212121 },
	{ base = 0xfcfdfd, a = 0xfcfdfd, b = 0xcbdfde, lip = 0x3d3d3d },
}
local RIDGE_FROM = { 0, 0.5, 0.74, 0.88 } -- ridge height (0 to 1) where each rock band starts
local SNOW_PATCHES = 0.62 -- snow caps only where patch noise is above this, so most crests stay bare rock
local RIDGE_FADE = 6 -- ridges rise over this many pixels from a mountain province's edge
local RIDGE_SLOPE = 12 -- height change (of 255) across a pixel that counts as a lit or shaded slope

-- Skyshards floats in space (WorldBox's night sky), on platforms with crystal-glow rims and iron hulls.
local SPACE = { top = 0x05003f, bottom = 0x0e165b, star = 0xddfcff, grid = 0x152770, rim = 0x7cfbef, hull = 0x494949 }
local HULL = 6 -- pixels of platform hull drawn below Skyshards land

-- Kingdoms like WorldBox's: the nation colour over the terrain at this opacity, and a 1-pixel border in the
-- nation's darker colour at BORDER_ALPHA.
local NATION_ALPHA = 0.587
local BORDER_ALPHA = 0.88
local PROVINCE_LINE = 0.86 -- 1-pixel lines between provinces darken the terrain to this share

-- Sprites: rows of characters, "." is transparent; colours come from the biome's sprite table (or its light,
-- base and dark shades for L, M and D), or are fixed (W white, G light grey).
local SPRITES: { [string]: { string } } = {
	trees = { "LM", "MD" }, -- WorldBox's zoomed-out tree icon: lit top left, shaded bottom right
	jungle = { "LM", "MD" },
	pines = { ".L", "LM", "MD" },
	savanna = { "LLM", ".D." },
	palms = { "LM", ".T" },
	hills = { ".LL.", "LMML", "PPPP" },
	crystals = { ".C.", "CWC", ".D." },
	towers = { ".C.", ".G.", "BGB", "GGG" },
	plates = { "LLD", "LMD", "DDD" },
	castle = { "F....", "FF...", "M.M.M", "MMMMM", "MDWDM", "MDDDM" },
	dome = { "F....", "FF...", ".CCC.", "CWWWC", "MMMMM", "MDCDM" },
}
-- Drawn in this order (later ones on top), with each decoration's grid spacing and jitter.
local DECORATIONS = { "hills", "palms", "savanna", "pines", "trees", "jungle", "plates", "crystals", "towers" }
local SPACING: { [string]: { number } } = {
	trees = { 3, 1 },
	jungle = { 2, 1 },
	pines = { 3, 1 },
	savanna = { 9, 3 },
	palms = { 10, 3 },
	hills = { 7, 2 },
	crystals = { 5, 1 },
	towers = { 6, 1 },
	plates = { 6, 1 },
}

------------------------------------------------------------------------------------------------- colour maths

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
end

local function pack(r: number, g: number, b: number): number
	r = math.clamp(math.floor(r + 0.5), 0, 255)
	g = math.clamp(math.floor(g + 0.5), 0, 255)
	b = math.clamp(math.floor(b + 0.5), 0, 255)
	return r * 65536 + g * 256 + b
end

local function scale(c: number, k: number): number
	local r, g, b = rgb(c)
	return pack(r * k, g * k, b * k)
end

local function mix(a: number, b: number, t: number): number
	local r1, g1, b1 = rgb(a)
	local r2, g2, b2 = rgb(b)
	return pack(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

-- 32-bit multiply without losing precision in doubles.
local function mul32(a: number, b: number): number
	local hi = bit32.rshift(a, 16)
	local lo = bit32.band(a, 0xffff)
	return bit32.band(bit32.lshift(bit32.band(hi * b, 0xffff), 16) + lo * b, 0xffffffff)
end

-- Deterministic noise in [0, 1) for a pixel.
local function noise(x: number, y: number, salt: number): number
	local h = bit32.bxor(mul32(x, 0x27d4eb2d), mul32(y, 0x165667b1), mul32(salt, 0x9e3779b1))
	h = mul32(bit32.bxor(h, bit32.rshift(h, 15)), 0x85ebca6b)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	return h / 4294967296
end

-- Smooth noise in [0, 1): random values on a lattice every `cell` pixels, blended smoothly in between.
local function smoothNoise(w: number, h: number, cell: number, salt: number): (number, number) -> number
	local cols = w // cell + 2
	local rows = h // cell + 2
	local lattice = buffer.create(cols * rows * 4)
	for gy = 0, rows - 1 do
		for gx = 0, cols - 1 do
			buffer.writef32(lattice, (gy * cols + gx) * 4, noise(gx, gy, salt))
		end
	end
	return function(x: number, y: number): number
		local gx, gy = x // cell, y // cell
		local fx, fy = (x % cell) / cell, (y % cell) / cell
		fx = fx * fx * (3 - 2 * fx)
		fy = fy * fy * (3 - 2 * fy)
		local i = (gy * cols + gx) * 4
		local a = buffer.readf32(lattice, i)
		local b = buffer.readf32(lattice, i + 4)
		local c = buffer.readf32(lattice, i + cols * 4)
		local d = buffer.readf32(lattice, i + cols * 4 + 4)
		return (a + (b - a) * fx) * (1 - fy) + (c + (d - c) * fx) * fy
	end
end

------------------------------------------------------------------------------------------------- terrain

local function styleOf(art: Art, biomeOf: { [number]: Style }, x: number, y: number): Style?
	if x < 0 or y < 0 or x >= art.width or y >= art.height then
		return nil
	end
	return biomeOf[buffer.readu8(art.ids, y * art.width + x)]
end

local function setTerrain(art: Art, x: number, y: number, c: number)
	buffer.writeu32(art.terrain, (y * art.width + x) * 4, c)
end

-- Stamp a decoration on a jittered grid wherever the whole sprite fits inside land of the same biome.
local function decorate(art: Art, biomeOf: { [number]: Style }, deco: string, salt: number, yield: Yield?)
	local sprite = SPRITES[deco]
	local spacing, jitter = SPACING[deco][1], SPACING[deco][2]
	local h, w = #sprite, #sprite[1]
	for gy = 0, art.height - h - 1, spacing do
		if yield and gy % 64 < spacing then
			yield()
		end
		for gx = 0, art.width - w - 1, spacing do
			local x = gx + math.floor(noise(gx, gy, salt) * (2 * jitter + 1)) - jitter
			local y = gy + math.floor(noise(gx, gy, salt + 1) * (2 * jitter + 1)) - jitter
			local s = styleOf(art, biomeOf, x, y)
			if s == nil or s.deco ~= deco then
				continue
			end
			local fits = true
			for j = 0, h - 1 do
				for i = 0, w - 1 do
					if styleOf(art, biomeOf, x + i, y + j) ~= s then
						fits = false
						break
					end
				end
				if not fits then
					break
				end
			end
			if not fits then
				continue
			end
			local colours = s.sprite or {}
			local palette: { [string]: number } = {
				L = colours.L or s.light,
				M = colours.M or s.base,
				D = colours.D or s.dark,
				T = colours.T or 0x613e28,
				P = colours.P or scale(s.dark, 0.8),
				C = colours.C or 0x7cfbef,
				G = colours.G or 0xd8dee6,
				B = colours.B or 0xbd8137,
				W = 0xffffff,
			}
			for j = 1, h do
				local row = sprite[j]
				for i = 1, w do
					local ch = string.sub(row, i, i)
					if ch ~= "." then
						setTerrain(art, x + i - 1, y + j - 1, palette[ch])
					end
				end
			end
		end
	end
end

-- Distance (in pixels, capped at RIDGE_FADE) from the edge of the province, for mountains' ridges.
local function edgeDistance(art: Art, biomeOf: { [number]: Style }, yield: Yield?): buffer
	local w, h = art.width, art.height
	local ids = art.ids
	local dist = buffer.create(w * h)
	buffer.fill(dist, 0, 255)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			local pid = buffer.readu8(ids, i)
			local edge = pid == 0
				or biomeOf[pid].deco ~= "rock"
				or x == 0
				or y == 0
				or x == w - 1
				or y == h - 1
				or buffer.readu8(ids, i - 1) ~= pid
				or buffer.readu8(ids, i + 1) ~= pid
				or buffer.readu8(ids, i - w) ~= pid
				or buffer.readu8(ids, i + w) ~= pid
			if edge then
				buffer.writeu8(dist, i, 0)
			end
		end
	end
	for d = 1, RIDGE_FADE do
		if yield then
			yield()
		end
		for y = 1, h - 2 do
			for x = 1, w - 2 do
				local i = y * w + x
				if buffer.readu8(dist, i) == 255 then
					local prev = d - 1
					if
						buffer.readu8(dist, i - 1) == prev
						or buffer.readu8(dist, i + 1) == prev
						or buffer.readu8(dist, i - w) == prev
						or buffer.readu8(dist, i + w) == prev
					then
						buffer.writeu8(dist, i, d)
					end
				end
			end
		end
	end
	return dist
end

local function paintTerrain(art: Art, biomeOf: { [number]: Style }, yield: Yield?)
	local w, h = art.width, art.height
	local ids = art.ids
	local sky = art.theme == "sky"

	-- distance from land over water, for the ocean's depth bands
	local dist = buffer.create(w * h)
	for i = 0, w * h - 1 do
		buffer.writeu8(dist, i, if buffer.readu8(ids, i) == 0 then 255 else 0)
	end
	for d = 1, if sky then 0 else MEDIUM_TO + 1 do
		if yield then
			yield()
		end
		for y = 0, h - 1 do
			for x = 0, w - 1 do
				local i = y * w + x
				if buffer.readu8(dist, i) == 255 then
					local prev = d - 1
					if
						(x > 0 and buffer.readu8(dist, i - 1) == prev)
						or (x < w - 1 and buffer.readu8(dist, i + 1) == prev)
						or (y > 0 and buffer.readu8(dist, i - w) == prev)
						or (y < h - 1 and buffer.readu8(dist, i + w) == prev)
					then
						buffer.writeu8(dist, i, d)
					end
				end
			end
		end
	end
	local function depth(i: number): number -- 1 shallow, 2 close ocean, 3 deep
		local d = buffer.readu8(dist, i)
		return if d <= SHALLOW_TO then 1 elseif d <= MEDIUM_TO then 2 else 3
	end
	local patches = smoothNoise(w, h, 12, 5)
	local detail = smoothNoise(w, h, 5, 6)

	-- mountains: ridge height (0 to 255) where smooth noise crosses its middle, low along the province's edge
	local rock = edgeDistance(art, biomeOf, yield)
	local ridges = smoothNoise(w, h, 11, 11)
	local ridgeDetail = smoothNoise(w, h, 4, 12)
	local snowPatches = smoothNoise(w, h, 9, 13)
	local heights = buffer.create(w * h)
	local levels = buffer.create(w * h) -- index into ROCK, 0 off the mountains
	for i = 0, w * h - 1 do
		local pid = buffer.readu8(ids, i)
		if pid ~= 0 and biomeOf[pid].deco == "rock" then
			local x, y = i % w, i // w
			local n = ridges(x, y) * 0.8 + ridgeDetail(x, y) * 0.2
			local height = (1 - math.abs(n - 0.5) * 2) * math.min(buffer.readu8(rock, i) / RIDGE_FADE, 1)
			local level = 1
			for band = #RIDGE_FROM, 2, -1 do
				if height >= RIDGE_FROM[band] and (band < #RIDGE_FROM or snowPatches(x, y) > SNOW_PATCHES) then
					level = band
					break
				end
			end
			buffer.writeu8(heights, i, math.floor(height * 255))
			buffer.writeu8(levels, i, level)
		end
	end

	for y = 0, h - 1 do
		if yield and y % 64 == 63 then
			yield()
		end
		for x = 0, w - 1 do
			local i = y * w + x
			local pid = buffer.readu8(ids, i)
			local n = noise(x, y, 1)
			local c: number
			if pid ~= 0 then
				local s = biomeOf[pid]
				if s.deco == "rock" then
					local level = buffer.readu8(levels, i)
					local band = ROCK[level]
					if level == 1 then
						c = if n < 0.06 then band.a elseif n > 0.94 then band.b else band.base
					else
						local slope = if x > 0 and x < w - 1
							then buffer.readu8(heights, i + 1) - buffer.readu8(heights, i - 1)
							else 0
						c = if slope > RIDGE_SLOPE then band.a elseif slope < -RIDGE_SLOPE then band.b else band.base
					end
					-- the south side of each band gets a dark lip
					if y == h - 1 or buffer.readu8(ids, i + w) ~= pid or buffer.readu8(levels, i + w) < level then
						c = band.lip
					end
				else
					local high = s.high
					local ground = if high and patches(x, y) * 0.7 + detail(x, y) * 0.3 > 0.6 then high else s.base
					c = if n > 0.95 then s.light elseif n < 0.05 then s.dark else ground
					if s.deco == "flowers" and noise(x, y, 7) > (if s == BIOMES.meadow then 0.985 else 0.994) then
						c = FLOWERS[1 + math.floor(noise(x, y, 8) * #FLOWERS)]
					elseif s.deco == "rows" and y % 3 == 0 then
						c = (s.sprite :: { [string]: number }).R -- crop rows
					elseif s.deco == "panels" and (x % 8 == 0 or y % 8 == 0) then
						local panel = s.sprite :: { [string]: number }
						local lit = noise(x // 8, y // 8, 9)
						c = if lit < 0.04 then panel.C elseif lit < 0.08 then panel.E else panel.R -- steel panels
					end
				end
			elseif sky then
				c = mix(SPACE.top, SPACE.bottom, y / h)
				if n > 0.997 then
					c = SPACE.star
				elseif x % 32 == 0 or y % 32 == 0 then
					c = mix(c, SPACE.grid, 0.6)
				end
				-- the hull of a platform hangs below its land, with a glowing rim at the bottom
				for k = 1, HULL do
					if y - k >= 0 and buffer.readu8(ids, i - k * w) ~= 0 then
						c = if k == HULL or noise(x, y, 3) < 0.04 then SPACE.rim else scale(SPACE.hull, 1 - k * 0.09)
						break
					end
				end
			else
				local band = depth(i)
				c = if band == 1 then SEA.shallow elseif band == 2 then SEA.medium else SEA.deep
				if band == 1 and n > 0.97 then
					c = SEA.shallowWave
				elseif band == 2 and n > 0.985 then
					c = SEA.mediumWave
				end
				if y > 0 and buffer.readu8(ids, i - w) ~= 0 then
					c = SEA.shadow -- just south of land
				elseif y < h - 1 and buffer.readu8(ids, i + w) == 0 and depth(i + w) > band then
					c = if band == 1 then SEA.shallowLip else SEA.mediumLip -- deeper water below
				end
			end
			setTerrain(art, x, y, c)
		end
	end

	-- coasts: beaches by the sea (with a lip on their south side), crystal-glow rims on space platforms
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			local pid = buffer.readu8(ids, i)
			if pid ~= 0 then
				local south = y < h - 1 and buffer.readu8(ids, i + w) == 0
				local coast = south
					or (x > 0 and buffer.readu8(ids, i - 1) == 0)
					or (x < w - 1 and buffer.readu8(ids, i + 1) == 0)
					or (y > 0 and buffer.readu8(ids, i - w) == 0)
				local deco = biomeOf[pid].deco
				if coast then
					if sky then
						setTerrain(art, x, y, SPACE.rim)
					elseif deco ~= "rock" and biomeOf[pid] ~= BIOMES.ice and biomeOf[pid] ~= BIOMES.frostfields then
						setTerrain(art, x, y, if south then SEA.beachLip else SEA.beach)
					end
				end
			end
		end
	end

	for k, deco in DECORATIONS do
		decorate(art, biomeOf, deco, 10 + 7 * k, yield)
	end
end

------------------------------------------------------------------------------------------------- political layer

local NEAR1 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
-- Art.near bits. A pixel with none set is inside its province, and its colour depends only on its terrain.
local NEAR_EDGE = 1 -- a 4-neighbour is another province, sea or off the map (nation border candidate)
local NEAR_LINE = 2 -- the pixel to the right or below is another province (a 1-pixel province line)

local function idAt(art: Art, x: number, y: number): number
	if x < 0 or y < 0 or x >= art.width or y >= art.height then
		return 0
	end
	return buffer.readu8(art.ids, y * art.width + x)
end

local function ownerAt(art: Art, x: number, y: number): number
	local pid = idAt(art, x, y)
	return if pid == 0 then 0 else art.owner[pid] or 0
end

-- 0xRRGGBB -> the RGBA bytes EditableImage expects (buffers are little-endian).
local function rgba(c: number): number
	local r, g, b = rgb(c)
	return 0xff000000 + b * 65536 + g * 256 + r
end

local function markDirty(art: Art, x0: number, y0: number, x1: number, y1: number)
	local d = art.dirty
	if d == nil then
		art.dirty = { x0, y0, x1, y1 }
	else
		d[1] = math.min(d[1], x0)
		d[2] = math.min(d[2], y0)
		d[3] = math.max(d[3], x1)
		d[4] = math.max(d[4], y1)
	end
end

local function paintProvince(art: Art, pid: number)
	local box = art.boxes[pid]
	if box == nil then
		return
	end
	local o = art.owner[pid] or 0
	local nation = if o ~= 0 then art.color[o] or 0x808080 else 0
	local border = if o ~= 0 then art.border[o] or scale(nation, 0.75) else 0
	local selected = art.selected == pid
	local w = art.width
	local ids, terrain, near, pixels = art.ids, art.terrain, art.near, art.pixels

	-- most pixels' colours depend only on their terrain colour: work each one out once per repaint
	local washed: { [number]: number } = {}
	local function wash(c: number): number
		local t = washed[c]
		if t == nil then
			t = if o ~= 0 then mix(c, nation, NATION_ALPHA) else c
			washed[c] = t
		end
		return t
	end
	local inside: { [number]: number } = {}

	for y = box[2], box[4] do
		local row = y * w
		for x = box[1], box[3] do
			local i = row + x
			if buffer.readu8(ids, i) ~= pid then
				continue
			end
			local c = buffer.readu32(terrain, i * 4)
			local flags = buffer.readu8(near, i)
			if flags == 0 then
				local f = inside[c]
				if f == nil then
					f = rgba(if selected then mix(wash(c), 0xffffff, 0.3) else wash(c))
					inside[c] = f
				end
				buffer.writeu32(pixels, i * 4, f)
				continue
			end
			local v = wash(c)
			local edge = false
			if o ~= 0 and bit32.btest(flags, NEAR_EDGE) then
				for _, d in NEAR1 do
					if ownerAt(art, x + d[1], y + d[2]) ~= o then
						edge = true
						break
					end
				end
			end
			if edge then
				v = mix(c, border, BORDER_ALPHA) -- the nation border
			elseif bit32.btest(flags, NEAR_LINE) then
				v = scale(v, PROVINCE_LINE)
			end
			if selected then
				v = if bit32.btest(flags, NEAR_EDGE) then 0xffffff else mix(v, 0xffffff, 0.3)
			end
			buffer.writeu32(pixels, i * 4, rgba(v))
		end
	end
	markDirty(art, box[1], box[2], box[3], box[4])
end

-- Castles (domes on Skyshards) go on top of everything, after any repaint, since they overlap neighbours.
local function drawCapitals(art: Art)
	local sprite = SPRITES[if art.theme == "sky" then "dome" else "castle"]
	local h, w = #sprite, #sprite[1]
	for pid, capital in art.capitals do
		local o = art.owner[pid] or 0
		local palette: { [string]: number } = {
			F = if o ~= 0 then art.color[o] or 0x808080 else 0xb0b0b0,
			M = 0xe4ded2,
			D = 0x5b544a,
			W = 0xffe9a0,
			C = 0x7cfbef,
		}
		local x0, y0 = capital.x - 2, capital.y - 3
		for j = 1, h do
			for i = 1, w do
				local ch = string.sub(sprite[j], i, i)
				local x, y = x0 + i - 1, y0 + j - 1
				if ch ~= "." and x >= 0 and y >= 0 and x < art.width and y < art.height then
					buffer.writeu32(art.pixels, (y * art.width + x) * 4, rgba(palette[ch]))
				end
			end
		end
		markDirty(art, x0, y0, x0 + w - 1, y0 + h - 1)
	end
end

------------------------------------------------------------------------------------------------- public API

type MapLike = {
	theme: string,
	provinces: { { id: number, biome: string, isCapital: boolean, center: { x: number, y: number } } },
}

-- Paint the terrain and a neutral political layer. Owners come later through setOwners. Pass `yield` to have it
-- called every few dozen rows (a client spreads the work over frames this way); tests leave it out.
function PixelArt.new(map: MapLike, grid: Grid, yield: Yield?): Art
	local w, h = grid.width, grid.height
	local art: Art = {
		width = w,
		height = h,
		ids = grid.ids,
		theme = map.theme,
		terrain = buffer.create(w * h * 4),
		pixels = buffer.create(w * h * 4),
		boxes = {},
		touching = {},
		owner = {},
		color = {},
		border = {},
		capitals = {},
		selected = 0,
		near = buffer.create(w * h),
		dirty = nil,
	}
	local biomeOf: { [number]: Style } = {}
	for _, p in map.provinces do
		biomeOf[p.id] = BIOMES[p.biome] or FALLBACK
		if p.isCapital then
			art.capitals[p.id] = { x = math.floor(p.center.x / grid.scale), y = math.floor(p.center.y / grid.scale) }
		end
	end

	-- bounding boxes, which provinces touch, and each pixel's border checks
	local touch: { [number]: { [number]: boolean } } = {}
	for y = 0, h - 1 do
		if yield and y % 64 == 63 then
			yield()
		end
		for x = 0, w - 1 do
			local i = y * w + x
			local pid = buffer.readu8(grid.ids, i)
			if pid == 0 then
				continue
			end
			local box = art.boxes[pid]
			if box == nil then
				art.boxes[pid] = { x, y, x, y }
			else
				box[1] = math.min(box[1], x)
				box[3] = math.max(box[3], x)
				box[4] = y
			end
			local flags = 0
			for k, d in NEAR1 do
				local other = idAt(art, x + d[1], y + d[2])
				if other ~= pid then
					flags = bit32.bor(flags, NEAR_EDGE)
					if other ~= 0 then
						if k == 1 or k == 3 then -- right or below
							flags = bit32.bor(flags, NEAR_LINE)
						end
						touch[pid] = touch[pid] or {}
						touch[other] = touch[other] or {}
						touch[pid][other] = true
						touch[other][pid] = true
					end
				end
			end
			buffer.writeu8(art.near, i, flags)
		end
	end
	for pid, set in touch do
		local list = {}
		for other in set do
			table.insert(list, other)
		end
		art.touching[pid] = list
	end

	paintTerrain(art, biomeOf, yield)
	for i = 0, w * h - 1 do
		buffer.writeu32(art.pixels, i * 4, rgba(buffer.readu32(art.terrain, i * 4)))
	end
	local painted = 0
	for pid in art.boxes do
		paintProvince(art, pid)
		painted += 1
		if yield and painted % 16 == 0 then
			yield()
		end
	end
	drawCapitals(art)
	art.dirty = { 0, 0, w - 1, h - 1 }
	return art
end

-- Apply owners (province id -> nation slot, 0 = neutral), nation colours (slot -> 0xRRGGBB) and, optionally,
-- border colours (slot -> 0xRRGGBB; default: the colour at 75% brightness). Repaints only the provinces whose
-- owner or colours changed, and their neighbours (borders). Returns true if anything changed.
function PixelArt.setOwners(
	art: Art,
	owners: { [number]: number },
	colors: { [number]: number },
	borders: { [number]: number }?
): boolean
	local dirty: { [number]: boolean } = {}
	for slot, c in colors do
		local b = if borders and borders[slot] then borders[slot] else scale(c, 0.75)
		if art.color[slot] ~= c or art.border[slot] ~= b then
			art.color[slot] = c
			art.border[slot] = b
			for pid, o in art.owner do
				if o == slot then
					dirty[pid] = true
				end
			end
		end
	end
	for pid in art.boxes do
		local o = owners[pid] or 0
		if (art.owner[pid] or 0) ~= o then
			art.owner[pid] = o
			dirty[pid] = true
		end
	end
	local repaint: { [number]: boolean } = {}
	for pid in dirty do
		repaint[pid] = true
		for _, other in art.touching[pid] or {} do
			repaint[other] = true
		end
	end
	local any = false
	for pid in repaint do
		paintProvince(art, pid)
		any = true
	end
	if any then
		drawCapitals(art)
	end
	return any
end

-- Highlight one province (0 or nil = none). Returns true if anything changed.
function PixelArt.select(art: Art, pid: number?): boolean
	local new = pid or 0
	local old = art.selected
	if new == old then
		return false
	end
	art.selected = new
	if old ~= 0 then
		paintProvince(art, old)
	end
	if new ~= 0 then
		paintProvince(art, new)
	end
	drawCapitals(art)
	return true
end

-- Mark the whole image as changed (e.g. a cached painting shown through a new EditableImage).
function PixelArt.invalidate(art: Art)
	art.dirty = { 0, 0, art.width - 1, art.height - 1 }
end

-- The rectangle (x0, y0, x1, y1, inclusive, inside the image) changed since the last call, or nil.
function PixelArt.takeDirty(art: Art): { number }?
	local d = art.dirty
	art.dirty = nil
	if d == nil then
		return nil
	end
	local x0, y0 = math.max(d[1], 0), math.max(d[2], 0)
	local x1, y1 = math.min(d[3], art.width - 1), math.min(d[4], art.height - 1)
	if x1 < x0 or y1 < y0 then
		return nil
	end
	return { x0, y0, x1, y1 }
end

-- The colour of one pixel, 0xRRGGBB (for tests and debugging).
function PixelArt.pixel(art: Art, x: number, y: number): number
	local v = buffer.readu32(art.pixels, (y * art.width + x) * 4)
	return bit32.band(v, 255) * 65536 + bit32.band(bit32.rshift(v, 8), 255) * 256 + bit32.band(bit32.rshift(v, 16), 255)
end

return PixelArt
