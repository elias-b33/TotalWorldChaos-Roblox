--!strict
-- The 2D pixel-art map (WorldBox style), painted pixel by pixel from the province grid: water or space, terrain
-- with little trees, peaks and dunes, then each owned province tinted in its nation's colour with a bold border.
-- Pure Luau on buffers (no Roblox APIs), so the same code paints the map in the game and in Lune tests.
-- Colours are packed 0xRRGGBB integers; `pixels` is RGBA bytes, ready for EditableImage:WritePixelsBuffer.

local PixelArt = {}

export type Grid = { width: number, height: number, ids: buffer, scale: number }

type Style = { base: number, light: number, dark: number, deco: string }

export type Art = {
	width: number,
	height: number,
	ids: buffer,
	theme: string,
	terrain: buffer, -- 0xRRGGBB per pixel (u32)
	pixels: buffer, -- RGBA per pixel
	boxes: { [number]: { number } }, -- province id -> { x0, y0, x1, y1 }, inclusive
	touching: { [number]: { number } }, -- provinces sharing a pixel edge
	baseLum: { [number]: number }, -- luminance of each province's biome colour
	owner: { [number]: number }, -- province id -> nation slot (0 = neutral)
	color: { [number]: number }, -- nation slot -> colour
	capitals: { [number]: { x: number, y: number } },
	selected: number,
	near: buffer, -- per pixel: which border checks it needs (NEAR_* bits), worked out once per map
	dirty: { number }?, -- x0, y0, x1, y1 of what changed since the last takeDirty
}

-- Called now and then while painting a whole map, so a client can spread the work over several frames.
export type Yield = () -> ()

-- Biome looks: base colour, light and dark specks, decoration.
local function style(base: number, light: number, dark: number, deco: string): Style
	return { base = base, light = light, dark = dark, deco = deco }
end

local BIOMES: { [string]: Style } = {
	-- Earth
	grassland = style(0x4fb03c, 0x6acb52, 0x3f9630, "grass"),
	steppe = style(0xa8c454, 0xbfd76a, 0x8faa44, "grass"),
	savanna = style(0xd2c057, 0xe2d272, 0xb8a646, "savanna"),
	tundra = style(0xa3b39a, 0xb9c8b0, 0x8a9a82, "grass"),
	desert = style(0xf0d48a, 0xf8e3a8, 0xdcbd6c, "dunes"),
	drylands = style(0xd4a865, 0xe2bd80, 0xb98d50, "dunes"),
	forest = style(0x2f8f37, 0x4cb34b, 0x23712a, "trees"),
	jungle = style(0x1f9c3d, 0x3cbd52, 0x16792e, "trees"),
	taiga = style(0x2d6e47, 0x438c5d, 0x205536, "pines"),
	hills = style(0x86b24a, 0xa0cb5e, 0x6c923b, "hills"),
	mountains = style(0x8d8a86, 0xb3b0ab, 0x6b6864, "peaks"),
	ice = style(0xeef6fb, 0xffffff, 0xcfe0ec, "snow"),
	-- Eldmoor
	meadow = style(0x52b83e, 0x70d257, 0x40a031, "grass"),
	frostfields = style(0xe4eff8, 0xf8fbfe, 0xc6d8e8, "snow"),
	dunes = style(0xf2b765, 0xf9cd8a, 0xdc9c4c, "dunes"),
	wildwood = style(0x1c8c5e, 0x33ad7a, 0x136b47, "trees"),
	highlands = style(0x7fae5e, 0x99c977, 0x668e4b, "hills"),
	ashlands = style(0x544850, 0x6a5c65, 0x40363c, "ash"),
	peaks = style(0x7d86a4, 0xa0a8c2, 0x5f6782, "peaks"),
	-- Skyshards (sci-fi: platforms in space)
	skymeadow = style(0x3fae6a, 0x62d18a, 0x2d8a52, "rows"),
	heartruins = style(0xc3cddb, 0xe4ebf3, 0x98a3b4, "panels"),
	crystalgrove = style(0x3a2a6a, 0x5a41a0, 0x261b48, "crystals"),
	crags = style(0x6b7390, 0x8b93b0, 0x4f5670, "plates"),
	stormspire = style(0x232946, 0x3a4268, 0x161a30, "towers"),
}
local FALLBACK = BIOMES.grassland

local WATER = {
	earth = { deep = 0x2a5fc4, shallow = 0x4a92ea, foam = 0xb4e0ff, wave = 0x6fa6f0, beach = 0xf2e2a4 },
	fantasy = { deep = 0x2470c8, shallow = 0x45a5ee, foam = 0xb4e0ff, wave = 0x6fb4f2, beach = 0xf2e2a4 },
}
local SPACE = { top = 0x070a1c, bottom = 0x111842, star = 0xc9d2ff, grid = 0x18225a, rim = 0x3ff0ff, hull = 0x2a3148 }
local SHALLOWS = 6 -- pixels of lighter water along coasts
local HULL = 6 -- pixels of platform underside drawn below Skyshards land

-- Sprites: rows of characters, "." is transparent; colours come from the biome (L light, M base, D dark,
-- S shadow) or are fixed (W white, G light grey, C glow, F flag).
local SPRITES: { [string]: { string } } = {
	trees = { ".LL..", "LLMD.", "LMMDS", ".DDS.", "..S.." },
	pines = { ".L.", ".M.", "LMD", "MMD", ".S." },
	peaks = { "...W...", "..WWG..", ".LLMGD.", "LLMMDDD", "LMMDDDD" },
	hills = { ".LLL.", "LMMMD", "MDDDD" },
	dunes = { "LLM", "MDD" },
	grass = { "L.L", ".M." },
	savanna = { ".LL..", "LLMD.", "LMMDS", ".DDS.", "..S.." },
	crystals = { ".C.", "CWC", "CMD", ".D." },
	towers = { "..C..", "..G..", ".LMD.", ".LMD.", "LLMDD" },
	plates = { "LLLD", "LMMD", "DDDD" },
	castle = { "F....", "FF...", "M.M.M", "MMMMM", "MDWDM", "MDDDM" },
	dome = { "F....", "FF...", ".CCC.", "CWWWC", "MMMMM", "MDCDM" },
}
-- Drawn in this order (later ones on top).
local DECORATIONS = { "grass", "dunes", "hills", "savanna", "trees", "pines", "plates", "crystals", "towers", "peaks" }
local SPACING: { [string]: { number } } = { -- grid spacing and jitter for each decoration
	trees = { 4, 1 },
	pines = { 4, 1 },
	peaks = { 6, 1 },
	hills = { 7, 2 },
	dunes = { 6, 2 },
	grass = { 5, 2 },
	savanna = { 11, 4 },
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

local function lum(c: number): number
	local r, g, b = rgb(c)
	return 0.299 * r + 0.587 * g + 0.114 * b
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
			local glow = if noise(gx, gy, salt + 2) < 0.5 then 0x3ff0ff else 0xff5ad8
			local leaf = if deco == "savanna" then BIOMES.forest else s -- lone green trees on the savanna
			local palette: { [string]: number } = {
				L = scale(leaf.light, 1.05),
				M = scale(leaf.base, 0.95),
				D = scale(leaf.dark, 0.85),
				S = scale(leaf.dark, 0.6),
				W = 0xffffff,
				G = 0xd8dee6,
				C = glow,
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

local function paintTerrain(art: Art, biomeOf: { [number]: Style }, yield: Yield?)
	local w, h = art.width, art.height
	local ids = art.ids
	local sky = art.theme == "sky"
	local water = WATER[art.theme] or WATER.earth

	-- distance from land over water, for shallows
	local dist = buffer.create(w * h)
	for i = 0, w * h - 1 do
		buffer.writeu8(dist, i, if buffer.readu8(ids, i) == 0 then 255 else 0)
	end
	for d = 1, if sky then 0 else SHALLOWS do
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
				c = if n > 0.88 then s.light elseif n < 0.1 then s.dark else s.base
				if s.deco == "rows" and y % 3 == 0 then
					c = s.dark -- crop rows
				elseif s.deco == "panels" and (x % 8 == 0 or y % 8 == 0) then
					c = if noise(x // 8, y // 8, 9) < 0.08 then 0x3ff0ff else s.dark -- steel panels, a few lit
				end
			elseif sky then
				c = mix(SPACE.top, SPACE.bottom, y / h)
				if n > 0.997 then
					c = SPACE.star
				elseif x % 32 == 0 or y % 32 == 0 then
					c = mix(c, SPACE.grid, 0.6)
				end
				-- the underside of a platform hangs below its land
				for k = 1, HULL do
					if y - k >= 0 and buffer.readu8(ids, i - k * w) ~= 0 then
						c = if k == HULL or noise(x, y, 3) < 0.04 then SPACE.rim else scale(SPACE.hull, 1 - k * 0.08)
						break
					end
				end
			else
				local d = buffer.readu8(dist, i)
				local t = math.clamp((d - 1) / (SHALLOWS - 1), 0, 1)
				c = mix(water.shallow, water.deep, t)
				if d == 1 then
					c = water.foam
				elseif n > 0.985 then
					c = mix(c, water.wave, 0.5)
				end
			end
			setTerrain(art, x, y, c)
		end
	end

	-- coasts: beaches by the sea, neon rims on space platforms
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			local pid = buffer.readu8(ids, i)
			if pid ~= 0 then
				local coast = (x > 0 and buffer.readu8(ids, i - 1) == 0)
					or (x < w - 1 and buffer.readu8(ids, i + 1) == 0)
					or (y > 0 and buffer.readu8(ids, i - w) == 0)
					or (y < h - 1 and buffer.readu8(ids, i + w) == 0)
				local deco = biomeOf[pid].deco
				if coast then
					if sky then
						setTerrain(art, x, y, SPACE.rim)
					elseif deco ~= "snow" and deco ~= "peaks" then
						setTerrain(art, x, y, water.beach)
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
local NEAR2 = { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
-- Art.near bits. A pixel with none set is inside its province, and its colour depends only on its terrain.
local NEAR_EDGE = 1 -- a 4-neighbour is another province, sea or off the map (nation border candidate)
local NEAR_RING = 2 -- a pixel two steps away is another province, sea or off the map (inner line candidate)
local NEAR_PROVINCE = 4 -- a 4-neighbour is another province (dotted province border)

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
	local selected = art.selected == pid
	local base = art.baseLum[pid]
	local w = art.width
	local ids, terrain, near, pixels = art.ids, art.terrain, art.near, art.pixels

	-- most pixels' colours depend only on their terrain colour: work each one out once per repaint
	local tinted: { [number]: number } = {}
	local function tint(c: number): number
		local t = tinted[c]
		if t == nil then
			t = c
			if o ~= 0 then
				-- the nation's colour, shaded by the terrain underneath so trees and peaks still show
				t = mix(c, scale(nation, math.clamp(lum(c) / base, 0.55, 1.5)), 0.7)
			end
			tinted[c] = t
		end
		return t
	end
	local inside: { [number]: number } = {}
	local edgeColor = if selected then 0xffffff else scale(nation, 0.55)
	local innerColor = mix(nation, 0xffffff, 0.25)

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
					f = rgba(if selected then mix(tint(c), 0xffffff, 0.35) else tint(c))
					inside[c] = f
				end
				buffer.writeu32(pixels, i * 4, f)
				continue
			end
			local v = tint(c)
			local edge = false
			if o ~= 0 and bit32.btest(flags, NEAR_EDGE) then
				for _, d in NEAR1 do
					if ownerAt(art, x + d[1], y + d[2]) ~= o then
						edge = true
						break
					end
				end
			end
			local provinceEdge = bit32.btest(flags, NEAR_PROVINCE)
			if edge then
				v = edgeColor
			else
				if o ~= 0 and bit32.btest(flags, NEAR_RING) then
					for _, d in NEAR2 do
						if ownerAt(art, x + d[1], y + d[2]) ~= o then
							v = innerColor -- a light inner line along the nation border
							break
						end
					end
				end
				if provinceEdge and (x + y) % 2 == 0 then
					v = scale(v, 0.7)
				end
				if selected then
					v = if provinceEdge then 0xffffff else mix(v, 0xffffff, 0.35)
				end
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
			C = 0x3ff0ff,
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
		baseLum = {},
		owner = {},
		color = {},
		capitals = {},
		selected = 0,
		near = buffer.create(w * h),
		dirty = nil,
	}
	local biomeOf: { [number]: Style } = {}
	for _, p in map.provinces do
		local s = BIOMES[p.biome] or FALLBACK
		biomeOf[p.id] = s
		art.baseLum[p.id] = math.max(lum(s.base), 1)
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
			for _, d in NEAR1 do
				local other = idAt(art, x + d[1], y + d[2])
				if other ~= pid then
					flags = bit32.bor(flags, NEAR_EDGE)
					if other ~= 0 then
						flags = bit32.bor(flags, NEAR_PROVINCE)
						touch[pid] = touch[pid] or {}
						touch[other] = touch[other] or {}
						touch[pid][other] = true
						touch[other][pid] = true
					end
				end
			end
			for _, d in NEAR2 do
				if idAt(art, x + d[1], y + d[2]) ~= pid then
					flags = bit32.bor(flags, NEAR_RING)
					break
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

-- Apply owners (province id -> nation slot, 0 = neutral) and nation colours (slot -> 0xRRGGBB). Repaints only
-- the provinces whose owner or colour changed, and their neighbours (borders). Returns true if anything changed.
function PixelArt.setOwners(art: Art, owners: { [number]: number }, colors: { [number]: number }): boolean
	local dirty: { [number]: boolean } = {}
	for slot, c in colors do
		if art.color[slot] ~= c then
			art.color[slot] = c
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
