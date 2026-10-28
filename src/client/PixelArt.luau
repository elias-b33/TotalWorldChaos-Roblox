--!strict
--!native
-- The 2D pixel-art map, painted pixel by pixel from the province grid in WorldBox's own colours (tile colours,
-- tree icons, water depths, mountain bands and kingdom overlay taken from WorldBox's game data; see
-- docs/MAPS.md "Art direction"). Owned provinces get their nation's colour as a translucent wash with a
-- 1-pixel border in the nation's darker colour, like kingdoms in WorldBox, and each race's capital is a building of
-- its own (a stone castle, a tree hall, a spiked war camp, a stone hall in a mountain) flying its owner's flag.
-- Two paintings: the whole map at one pixel per map pixel (PixelArt.new; what the zoomed-out map shows), and a
-- close-up detail of just the part in view at DETAIL_FACTOR × DETAIL_FACTOR sub-pixels per map pixel
-- (PixelArt.paintDetail; laid over the map when zoomed in), with WorldBox-style tile patterns, smooth coasts and
-- borders, shaded trees and a lighter kingdom wash.
-- Pure Luau on buffers (no Roblox APIs), so the same code paints the map in the game and in Lune tests.
-- Colours are packed 0xRRGGBB integers; `pixels` is RGBA bytes, ready for EditableImage:WritePixelsBuffer.

local PixelArt = {}

export type Grid = { width: number, height: number, ids: buffer, scale: number }

export type Style = {
	base: number,
	light: number,
	dark: number,
	high: number?, -- patches of the tile's darker "high" variant, like WorldBox's elevation tiles
	deco: string,
	sprite: { [string]: number }?, -- colours of the decoration sprites
	family: string, -- its ground pattern (STAMPS, or "rows" / "panels")
}

export type Art = {
	width: number,
	height: number,
	ids: buffer,
	theme: string, -- the map's texture set (MapDef.theme): "earth" | "fantasy" | "sky"
	look: string, -- the map theme it is painted in (PixelArt.THEMES; "" = the classic look)
	terrain: buffer, -- 0xRRGGBB per pixel (u32)
	pixels: buffer, -- RGBA per pixel
	boxes: { [number]: { number } }, -- province id -> { x0, y0, x1, y1 }, inclusive
	touching: { [number]: { number } }, -- provinces sharing a pixel edge
	owner: { [number]: number }, -- province id -> nation slot (0 = neutral)
	color: { [number]: number }, -- nation slot -> colour
	border: { [number]: number }, -- nation slot -> border colour
	capitals: { [number]: { x: number, y: number, kind: string } }, -- kind: whose capital it is (capitalKind)
	styles: { [number]: NationStyle }, -- nation slot -> its border style and shade set (cosmetics); missing = default
	selected: number,
	near: buffer, -- per pixel: which border checks it needs (NEAR_* bits), worked out once per map
	dirty: { number }?, -- x0, y0, x1, y1 of what changed since the last takeDirty
	biomes: { [number]: Style }, -- province id -> its biome's style
	elevation: buffer, -- per pixel: ground elevation 0–255 (0 at sea); high ground starts at HIGH_AT
	ridge: buffer, -- per pixel: mountain ridge height 0–255 (0 off the mountains)
	level: buffer, -- per pixel: mountain rock band 1–4 (ROCK), 0 off the mountains
	sea: buffer, -- per pixel: water's distance from land in SEA_UNITs (0 on land, at most 255)
	changed: { [number]: boolean }, -- provinces repainted since the close-up detail last caught up
}

-- Called now and then while painting, so a client can spread the work over several frames.
export type Yield = () -> ()

-- A nation's map cosmetics: the border pattern and the shade set of its wash (CosmeticArt art names, e.g.
-- "dashes", "dawn"). Both only ever use shades of the nation's own colours.
export type NationStyle = { border: string, shades: string }

local function style(
	base: number,
	light: number,
	dark: number,
	deco: string,
	high: number?,
	sprite: { [string]: number }?
): Style
	return { base = base, light = light, dark = dark, deco = deco, high = high, sprite = sprite, family = "grass" }
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
	heartruins = style(
		0x9ea6a3,
		0xd5e2ea,
		0x858886,
		"panels",
		nil,
		{ R = 0x8a918e, C = 0xf55858, E = 0x7cfbef, P = 0xa9b1ae, Q = 0x949c99 }
	),
	crystalgrove = style(0x7f5da2, 0xb573da, 0x564180, "crystals", nil, { C = 0x7cfbef, M = 0x64f1e2, D = 0x56c9bd }),
	crags = style(0x5d6191, 0x686da3, 0x4f537c, "plates"), -- grey_goo
	stormspire = style(0x3a485e, 0x597d94, 0x2e363e, "towers", nil, { C = 0x7cfbef, G = 0x8fa3b3, B = 0x2e363e }),
}
local FALLBACK = BIOMES.grassland

-- Each biome's ground pattern, WorldBox-style: a small hand-made tile (STAMPS) instead of random specks.
local FAMILY: { [string]: string } = {
	grassland = "grass",
	steppe = "dry",
	savanna = "dry",
	tundra = "snow",
	desert = "sand",
	drylands = "dry",
	forest = "grass",
	jungle = "jungle",
	taiga = "snow",
	hills = "grass",
	mountains = "rock",
	ice = "snow",
	meadow = "grass",
	frostfields = "snow",
	dunes = "sand",
	wildwood = "grass",
	highlands = "grass",
	ashlands = "ash",
	peaks = "rock",
	skymeadow = "rows",
	heartruins = "panels",
	crystalgrove = "crystal",
	crags = "goo",
	stormspire = "metal",
}
for name, s in BIOMES do
	s.family = FAMILY[name] or "grass"
end

local FLOWERS = { 0xc96b90, 0xd08651, 0xab81c0, 0xc7d8b4, 0xddb847, 0x7f9da9 }

-- WorldBox's ocean: shallow, close and deep water, each flat, with darker lips where it gets deeper and a shadow
-- line on water just south of land. Light comes from the top, so lips and shadows always fall on the south side.
-- A light foam line runs along the other shores, and gentle wave dashes cross the open water.
local SEA = {
	shallow = 0x55aef0,
	medium = 0x4084e2,
	deep = 0x3370cc,
	shallowLip = 0x3f90ea,
	mediumLip = 0x3c7cd1,
	shallowWave = 0x63bcf1,
	mediumWave = 0x488fe5,
	deepWave = 0x3e7fd8,
	shadow = 0x2d61af,
	foam = 0x86cdf6,
	surf = 0xd4f0fc, -- the close-up's foam right at the shore
	beach = 0xf7e898,
	wetSand = 0xe6d18c,
	beachLip = 0xd8c08c,
}
local SHALLOW_TO = 2 -- water up to this many pixels from land is shallow
local MEDIUM_TO = 6 -- then close ocean up to here, then deep ocean
local SEA_UNIT = 3 -- Art.sea counts in thirds of a pixel (a chamfer distance: 3 per straight step, 4 per diagonal)

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

-- Ground elevation (smooth noise, 0–255): high ground (a biome's "high" variant, with a dark lip on its south side
-- and a lit north edge) from HIGH_AT up; and a gentle light from the north-west on every slope.
local HIGH_AT = 153
local SHADE_SLOPE = 14 -- elevation change across two diagonal pixels that counts as a lit or shaded slope
local SHADE = { 1.07, 1, 0.93 } -- lit, flat, shaded

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

-- Capitals (docs/MAPS.md "Capitals and armies by race"): each race builds its own, flying its owner's flag F (grey
-- while neutral) and with roofs and banners R in the owner's colour. A capital keeps the look of the nation it is the
-- capital of; its flag follows whoever holds it. On the whole map they are 5 × 6 pixels round the capital's centre;
-- the close-up has detailed ones (DETAIL_CAPITALS). Skyshards' peoples build of its sci-fi materials (SCI_FI:
-- SKY_CAPITAL_COLOURS), and so would any other race standing on Skyshards (the Humans' castle as a glowing dome).
-- Colours: M D stone and its shade, W lit windows, C glow, G g e leaves, T t bark, H h hide, X wood, B bone,
-- K a dark doorway, Q q k rock, S snow, O fire; a building's own colours are in KIND_COLOURS.
local CAPITALS: { [string]: { string } } = {
	-- Eldmoor's fantasy peoples
	Humans = { "F....", "FF...", "M.M.M", "MMMMM", "MDWDM", "MDDDM" }, -- a stone castle
	Elves = { "F.GG.", "FFGGG", "GGGge", "egeee", ".tTt.", ".TWT." }, -- a tree hall
	Orcs = { "F.X.X", "FFXHX", ".HHh.", "BHHhB", "XHKhX", "XHOhX" }, -- a spiked war camp
	Dwarves = { "F.S..", "FFSq.", ".QQqk", "QQqqk", "QMKMk", "QMOMk" }, -- a stone hall in a mountain
	Lizardfolk = { "F.R..", "FFq..", ".qCq.", ".gqq.", "gqqqk", "qqqqk" }, -- a stepped pyramid with a glowing door
	-- Earth's civilisations
	Kingdom = { "F.R.R", "FFRMR", "M.MMM", "MMMMM", "MWMWM", "MMDMM" }, -- a castle of towers under tall cones
	Empire = { "F.R..", "FRRR.", "RMMMR", "MDMDM", "MDMDM", "MMMMM" }, -- a marble palace of columns
	Nomads = { "F....", "FF.Vx", ".VVVx", "VVVVx", "RRRRx", "VVOVx" }, -- a great felt tent and a horse-tail standard
	Republic = { "F.O..", "FFM..", "RRMRR", "MWMWM", "MKMKM", "AAAAA" }, -- a harbour: a lantern tower, a hall
	Clans = { "F.M..", "FFMM.", ".MKM.", "XqQqX", "QQqqk", "QqQqk" }, -- a tower house on a crag
	-- Skyshards' sci-fi peoples (the Marines build the dome)
	dome = { "F....", "FF...", ".CCC.", "CWWWC", "MMMMM", "MDCDM" }, -- a glowing dome on a steel base
	Robots = { "F...O", "FF..x", "MMM.x", "MRRMx", "MWKMx", "MMKMx" }, -- a factory and its mast
	Insectoids = { "F.P..", "FFp..", ".pAp.", ".RRR.", "PpAnn", "PpKnn" }, -- a hive spire with glowing cells
	Crystals = { "F.C..", "FFC..", "VCCV.", "VCCVC", "MRRRM", "MMMMM" }, -- a cluster of glowing shards
	Energy = { "F.Y..", "FYWY.", ".YEY.", "C.X.C", ".MRM.", "MMMMM" }, -- an orb of light over a pylon
}
-- Races whose capital is another kind's building.
local CAPITAL_OF: { [string]: string } = { Marines = "dome" }
-- Buildings made of Skyshards' materials wherever they stand.
local SCI_FI: { [string]: boolean } = { Robots = true, Insectoids = true, Crystals = true, Energy = true }
-- A building's own colours, looked up before the shared ones.
local KIND_COLOURS: { [string]: { [string]: number } } = {
	Lizardfolk = { q = 0x8e9690, g = 0x5f9a3a, k = 0x5d6160 }, -- mossy stone
	Nomads = { V = 0xf2e9d3, x = 0x5a3a20 }, -- felt, the standard's pole
	Republic = { A = 0x4084e2 }, -- the harbour's water
	Clans = { X = 0x5e3e22 },
	Robots = { x = 0x3a4250 },
	Insectoids = { P = 0xa47be0, p = 0x7650b8, n = 0x4a2e80, A = 0xffb02e, K = 0x2b1a40 }, -- chitin, amber light
	Crystals = { V = 0xb38cff, C = 0x7cfbef },
	Energy = { Y = 0xffc83d, E = 0xfff07a, W = 0xffffff, C = 0x7cfbef, X = 0x3a4250 },
}
local CAPITAL_COLOURS: { [string]: number } = {
	M = 0xe4ded2,
	D = 0x5b544a,
	W = 0xffe9a0,
	C = 0x7cfbef,
	G = 0xa3d35a,
	g = 0x5f9a3a,
	e = 0x3b6e33,
	T = 0xe6dcc4,
	t = 0x9a8a6c,
	H = 0xb88c58,
	h = 0x7a5434,
	X = 0x5e3e22,
	B = 0xf2ead8,
	K = 0x2b231c,
	Q = 0xa9adab,
	q = 0x7a7d7e,
	k = 0x4d5152,
	S = 0xf4f8fb,
	O = 0xff8a26,
}
-- Skyshards' materials, for every capital but the dome: steel, plating, crystal leaves, cyan and red light.
local SKY_CAPITAL_COLOURS: { [string]: number } = {
	M = 0xd8dee6,
	D = 0x4b5560,
	W = 0x7cfbef,
	G = 0xc8fff8,
	g = 0x64f1e2,
	e = 0x3fb3aa,
	T = 0xd8dee6,
	t = 0x8fa3b3,
	H = 0x8f97a8,
	h = 0x5a6272,
	X = 0x3a4250,
	B = 0xe8edf3,
	K = 0x10152a,
	Q = 0x8fa3b3,
	q = 0x597d94,
	k = 0x2e363e,
	S = 0x7cfbef,
	O = 0xf55858,
}

-- The capital a race builds on a map of this texture set (MapDef.theme): its own, the castle without a race.
local function capitalKind(theme: string, race: string?): string
	local kind = if race then CAPITAL_OF[race] or (if CAPITALS[race] then race else nil) else nil
	local built = kind or "Humans"
	return if built == "Humans" and theme == "sky" then "dome" else built
end

-- Is this capital drawn in Skyshards' materials (a sci-fi building, or any but the dome on a sky map)?
local function sciFi(theme: string, kind: string): boolean
	return SCI_FI[kind] == true or (theme == "sky" and kind ~= "dome")
end

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

-- A deterministic 32-bit hash of a pixel (or any two integers) and a salt.
local function hash32(x: number, y: number, salt: number): number
	local h = bit32.bxor(mul32(bit32.band(x, 0xffffffff), 0x27d4eb2d), mul32(bit32.band(y, 0xffffffff), 0x165667b1))
	h = bit32.bxor(h, mul32(salt, 0x9e3779b1))
	h = mul32(bit32.bxor(h, bit32.rshift(h, 15)), 0x85ebca6b)
	return bit32.bxor(h, bit32.rshift(h, 13))
end

-- Deterministic noise in [0, 1) for a pixel.
local function noise(x: number, y: number, salt: number): number
	return hash32(x, y, salt) / 4294967296
end

-- The deep-space backdrop behind the shards: the soft glow of a nebula, bright stars with a cross of light, and a few
-- distant planets in the empty corners, a ringed giant among them. Positions are shares of the map's size, so a vote
-- card's small painting shows them too. x, y: the centre; r: the radius as a share of the width; ring: a tilted ring.
local NEBULA = { violet = 0x5a2a9a, teal = 0x1f6a8a, strength = 0.32 }
local BRIGHT_STAR_CELL = 26 -- one candidate bright star per cell of this many map pixels
local PLANETS: { { x: number, y: number, r: number, body: number, shade: number, light: number, band: number?, ring: number? } } =
	{
		{
			x = 0.1,
			y = 0.15,
			r = 0.034,
			body = 0xd98c4a,
			shade = 0x7a3a24,
			light = 0xffd09a,
			band = 0xb86a3a,
			ring = 0xd8c39a,
		},
		{ x = 0.915, y = 0.865, r = 0.017, body = 0x6f9cd0, shade = 0x2c4a80, light = 0xd4ecff },
		{ x = 0.925, y = 0.12, r = 0.008, body = 0xc8586a, shade = 0x6a2236, light = 0xffb4c0 },
	}

-- The nebula's strength (0 to 1) and colour at a point (u, v in shares of the map), smooth and deterministic.
local function nebulaAt(u: number, v: number): (number, number)
	local a = math.sin(u * 7.1 + 1.3) * math.cos(v * 5.3 - 0.4)
	local b = math.sin((u + v) * 4.7 + 2.1) * 0.6 + math.cos((u - v * 1.3) * 9.2) * 0.4
	local t = math.clamp((a * 0.55 + b * 0.45 - 0.18) * 1.6, 0, 1)
	local hue = (math.sin(u * 3.1 - v * 2.3 + 0.7) + 1) / 2
	return t * t * NEBULA.strength, mix(NEBULA.violet, NEBULA.teal, hue)
end

-- A distant planet's colour at map point (x, y) of a map w × h, or nil where no planet is. Lit from the north-west,
-- with bands on the giant and its ring passing in front of its lower half.
local function planetAt(x: number, y: number, w: number, h: number): number?
	for _, p in PLANETS do
		local r = p.r * w
		local dx, dy = (x - p.x * w) / r, (y - p.y * h) / r
		local ring = p.ring
		if ring then
			-- a thin tilted ellipse round the planet: in front of it below its middle, behind it above
			local rx, ry = dx * 0.92 + dy * 0.39, -dx * 0.39 + dy * 0.92
			local e = (rx / 2.1) ^ 2 + (ry / 0.5) ^ 2
			if e >= 0.62 and e <= 1 and (ry > 0 or dx * dx + dy * dy > 1) then
				return if e > 0.86 then mix(ring, 0x000000, 0.25) else ring
			end
		end
		local d2 = dx * dx + dy * dy
		if d2 <= 1 then
			local lit = -(dx * 0.62 + dy * 0.78) + (1 - d2) * 0.35
			local band = p.band
			if band and math.floor((dy + 1) * 4.5) % 2 == 1 and lit > -0.25 then
				return if lit > 0.45 then mix(band, p.light, 0.35) else band
			end
			return if lit > 0.5 then p.light elseif lit < -0.3 then p.shade else p.body
		end
	end
	return nil
end

-- A bright star's light at map pixel (x, y): 1 at its centre, 0.55 on the arms of its cross, else 0.
local function brightStarAt(x: number, y: number): number
	local cx, cy = x // BRIGHT_STAR_CELL, y // BRIGHT_STAR_CELL
	local hsh = hash32(cx, cy, 515)
	if bit32.band(hsh, 7) ~= 0 then -- one cell in eight has one
		return 0
	end
	local sx = cx * BRIGHT_STAR_CELL + 2 + bit32.band(bit32.rshift(hsh, 8), 15)
	local sy = cy * BRIGHT_STAR_CELL + 2 + bit32.band(bit32.rshift(hsh, 16), 15)
	local d = math.abs(x - sx) + math.abs(y - sy)
	return if d == 0 then 1 elseif d == 1 and (x == sx or y == sy) then 0.55 else 0
end

-- The backdrop's colour at map point (x, y) of a map w × h (fractions for the close-up): a planet, or the sky's
-- gradient with the nebula's glow. Stars and grid lines go on top elsewhere.
local function spaceAt(x: number, y: number, w: number, h: number): (number, boolean)
	local planet = planetAt(x, y, w, h)
	if planet then
		return planet, true
	end
	local c = mix(SPACE.top, SPACE.bottom, math.clamp(y / h, 0, 1))
	local t, glow = nebulaAt(x / w, y / h)
	return if t > 0 then mix(c, glow, t) else c, false
end

------------------------------------------------------------------------------------------------- cosmetics

-- Border styles (docs/MONETIZATION.md 3.2): the colour of one border pixel, from the nation's border colour.
-- Every variant is that colour mixed with white or darkened, so its hue never changes (map colour is power).
function PixelArt.borderShade(pattern: string, border: number, x: number, y: number): number
	if pattern == "dashes" then
		return if ((x + y) // 3) % 2 == 0 then border else mix(border, 0xffffff, 0.45)
	elseif pattern == "runes" then
		local k = (x * 3 + y * 5) % 7
		return if k == 0 then mix(border, 0xffffff, 0.6) elseif k == 3 then scale(border, 0.6) else border
	elseif pattern == "embers" then
		local n = noise(x, y, 77)
		return if n > 0.72 then mix(border, 0xffffff, 0.55) elseif n < 0.3 then scale(border, 0.7) else border
	elseif pattern == "laurel" then
		return if (x + 2 * y) % 4 < 2 then mix(border, 0xffffff, 0.3) else scale(border, 0.8)
	end
	return border
end

-- Shade sets: the wash colour over a terrain pixel of this brightness (0–255), from the nation's colour. Three
-- shades of the same hue: for light, middle and dark terrain.
function PixelArt.shadeColor(set: string, nation: number, brightness: number): number
	local band = if brightness > 150 then 1 elseif brightness > 95 then 2 else 3
	if set == "dawn" then
		return if band == 1 then mix(nation, 0xffffff, 0.35) elseif band == 2 then mix(nation, 0xffffff, 0.2) else nation
	elseif set == "dusk" then
		return if band == 1 then nation elseif band == 2 then scale(nation, 0.85) else scale(nation, 0.7)
	elseif set == "royal" then
		return if band == 1 then mix(nation, 0xffffff, 0.3) elseif band == 2 then nation else scale(nation, 0.65)
	end
	return nation
end

local function brightness(c: number): number
	local r, g, b = rgb(c)
	return (r * 299 + g * 587 + b * 114) / 1000
end

------------------------------------------------------------------------------------------------- map themes

-- Map themes (docs/MONETIZATION.md 3.2): a re-skin of the terrain, painted the same pixel way. A theme only
-- recolours terrain pixels (land, sea, space), before the kingdom overlay goes on top, so nation colours, borders,
-- capitals and everything drawn over the map (armies, names, effects) are untouched. Since the overlay is a fixed
-- mix of terrain and nation colour, two nations always differ by the same amount on any theme; only how a nation
-- stands out from its terrain can change, and tests/themes.spec.luau checks that on all three maps.
PixelArt.THEMES = { "night", "winter", "autumn" } :: { string }

-- Glowing things keep their colour at night: crystal rims, crystals, lava glints, lit panel seams.
local GLOW: { [number]: boolean } = { [0x7cfbef] = true, [0x64f1e2] = true, [0xe9290e] = true, [0xf55858] = true }
local NIGHT_LIGHT = 0xffd27a -- village lights scattered over night land
local NIGHT_LIGHTS = 0.9965 -- a land pixel is a light where its noise is above this
local SNOW = 0xeef3f8
local ICE = 0xdcebf4
local WINTER_FLAKES = 0.985 -- fresh snow sparkles on winter land
-- Autumn foliage by brightness: maroon shadows, scarlet, amber and gold leaves (no mid browns, so the brown
-- nation still stands out).
local AUTUMN_GREEN = 20 -- a pixel turns if its green beats red and blue by more than this
local AUTUMN_RAMP: { { number } } = {
	{ 0, 0x3c1420 },
	{ 0.3, 0x8c2a2a },
	{ 0.42, 0xc8502e },
	{ 0.52, 0xe0a050 },
	{ 0.6, 0xf0c86e },
	{ 1, 0xfaeac0 },
}

local function ramp(stops: { { number } }, t: number): number
	for i = 2, #stops do
		local a, b = stops[i - 1], stops[i]
		if t <= b[1] then
			return mix(a[2], b[2], (t - a[1]) / (b[1] - a[1]))
		end
	end
	return stops[#stops][2]
end

-- One terrain colour under a theme ("" or "classic" = unchanged). `land`: a land pixel; else sea or space.
function PixelArt.themeColor(theme: string, c: number, land: boolean, space: boolean?): number
	local r, g, b = rgb(c)
	local l = brightness(c)
	if theme == "night" then
		if GLOW[c] or c == SPACE.star then
			return c
		end
		if space then
			return scale(c, 0.7)
		end
		if not land then
			return pack(r * 0.22 + 6, g * 0.28 + 10, b * 0.42 + 24)
		end
		-- moonlight: mostly grey, a little of the old hue, cool and dim
		r, g, b = r + (l - r) * 0.7, g + (l - g) * 0.7, b + (l - b) * 0.7
		return pack(r * 0.55 + 32, g * 0.52 + 30, b * 0.48 + 40)
	elseif theme == "winter" then
		if space then
			return c
		end
		if not land then
			return mix(c, 0xaacde6, 0.35)
		end
		-- snow everywhere; dark pixels (trees, rock shadows) only frosted, so forests still show
		return mix(c, SNOW, if l < 100 then 0.28 else 0.72)
	elseif theme == "autumn" then
		if space or not land then
			return c
		end
		if g - math.max(r, b) > AUTUMN_GREEN then
			return mix(ramp(AUTUMN_RAMP, l / 255), c, 0.12) -- leaves and grass turn; pines, rock and snow don't
		end
		return pack(r + 6, g, b - 6) -- everything else just a little warmer
	end
	return c
end

-- A terrain colour under a theme, with the rule both paintings share: in winter the shallows (and their foam) freeze.
local function themed(theme: string, c: number, kind: number): number -- kind: 1 land, 2 sea, 3 space
	if theme == "winter" and kind == 2 and (c == SEA.shallow or c == SEA.shallowWave or c == SEA.foam) then
		return ICE
	end
	return PixelArt.themeColor(theme, c, kind == 1, kind == 3)
end

-- Recolour the painted terrain for a theme, plus a few per-pixel touches: village lights at night, snow
-- sparkles and frozen shallows in winter.
local function applyTheme(art: Art, theme: string, yield: Yield?)
	if theme == "" or theme == "classic" then
		return
	end
	local w, h = art.width, art.height
	local sky = art.theme == "sky"
	local cache: { { [number]: number } } = { {}, {}, {} } -- land, sea, space
	for y = 0, h - 1 do
		if yield and y % 64 == 63 then
			yield()
		end
		for x = 0, w - 1 do
			local i = y * w + x
			local c = buffer.readu32(art.terrain, i * 4)
			local land = buffer.readu8(art.ids, i) ~= 0
			local kind = if land then 1 elseif sky then 3 else 2
			local t = cache[kind][c]
			if t == nil then
				t = themed(theme, c, kind)
				cache[kind][c] = t
			end
			if land and theme == "night" and noise(x, y, 91) > NIGHT_LIGHTS then
				t = NIGHT_LIGHT
			elseif land and theme == "winter" and noise(x, y, 93) > WINTER_FLAKES then
				t = 0xffffff
			end
			buffer.writeu32(art.terrain, i * 4, t)
		end
	end
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

------------------------------------------------------------------------------------------------- ground patterns

-- WorldBox paints every tile with a small hand-made texture instead of noise. Ours: 8×8 stamps per pattern family
-- (grass tufts, dry strokes, sand ripples, snow drifts, rock facets...), several variants each plus their mirror
-- images, picked per 8×8 block by a hash so nothing visibly repeats. The whole map uses them at one pixel per map
-- pixel; the close-up at one pixel per sub-pixel, so they come out 4× finer there.
-- "." base, "l" light, "d" dark, "h" highlight, "s" shadow (palette indices 1–5).
local STAMP_ROWS: { [string]: { { string } } } = {
	grass = {
		{ "........", ".l.l....", "..d.....", "......l.", ".....d..", "..h.....", "..d..l.l", "......d." },
		{ "........", "....l...", "...d.l..", "........", "l.l.....", ".d......", ".....h..", ".....d.." },
		{ "......l.", ".h...d..", ".d......", "....l.l.", ".....d..", "l.......", "d...h...", "....d..." },
		{ "........", "..l.....", ".d.l....", "........", "......l.", ".....d.l", ".l......", ".d......" },
	},
	dry = {
		{ "........", ".ll.....", "...d....", "......l.", ".....ld.", "........", "..d..ll.", "........" },
		{ "....ll..", "......d.", "........", ".l......", ".dl.....", "........", "....d.ll", "........" },
		{ "........", "...h....", "..ld....", "........", "......ll", ".d......", "........", "..ll...." },
	},
	sand = {
		{ "........", "..lll...", ".l...dd.", "........", "........", "......ll", "........", "........" },
		{ "........", "........", "....lll.", "...l...d", "........", ".ll.....", "...d....", "........" },
		{ "..ll....", "....d...", "........", "........", ".....lll", "....l...", "........", "........" },
		{ "........", "........", "........", ".lll....", "l...dd..", "........", "........", "......h." },
	},
	snow = {
		{ "........", "........", "..hhh...", ".l...l..", "........", "........", "......h.", "........" },
		{ "........", "......l.", "........", "........", ".lhhl...", "........", "........", "........" },
		{ "........", "........", "........", "....hh..", "...l..l.", "........", ".h......", "........" },
		{ "........", "........", "........", "........", "........", "........", "........", "........" },
		{ "........", "........", "........", "........", "........", ".....h..", "........", "........" },
	},
	rock = {
		{ "........", ".l......", "..d...l.", "......d.", "...l....", "....d...", ".l....l.", "..d....d" },
		{ "....l...", "...ld...", "......d.", ".l......", ".d...l..", ".....d..", "........", ".d......" },
	},
	jungle = {
		{ ".d..l..d", "..l..d..", "d...d..l", ".l.....d", "...dl...", "d......l", "..l.d...", ".d...l.d" },
		{ "..d...l.", "l...d...", ".d.l...d", "....d.l.", "d.l.....", "...d..d.", ".l...l..", "d...d..." },
	},
	ash = {
		{ "....d...", "...d....", "..d..l..", "...dd...", "......d.", ".l...d..", "....d...", "...d...." },
		{ "........", ".d......", "..dd....", "....d.l.", ".....d..", "..l...d.", "......d.", "........" },
		{ "......d.", ".....d..", "..dd.d..", ".d....l.", "........", "...l....", "........", "d......." },
	},
	crystal = {
		{ "........", ".h......", "..h.....", "..dh....", "...d....", "......h.", ".....hd.", "....hd.." },
		{ "......h.", ".....hd.", "....hd..", "........", ".h......", "..h.....", "..dh....", "...d...." },
	},
	goo = {
		{ "........", ".hl.....", ".ld..hl.", "..d..ld.", "......d.", "..hl....", "..ld....", "...d...." },
		{ "....hl..", "....ld..", ".....d..", "hl......", "ld...hl.", ".d...ld.", "......d.", "........" },
	},
	metal = {
		{ "dddddddd", "d.......", "d..l....", "d.......", "d.......", "d.....l.", "d.......", "d......." },
		{ "dddddddd", "d.......", "d.......", "d...h...", "d.......", "d.......", "d.l.....", "d......." },
	},
}
local STAMP_CODE: { [string]: number } = { ["."] = 1, l = 2, d = 3, h = 4, s = 5 }

-- Each family's variants as 64 palette indices, mirrored copies included.
local STAMPS: { [string]: { { number } } } = {}
for family, variants in STAMP_ROWS do
	local list: { { number } } = {}
	for _, rows in variants do
		local plain, mirrored = table.create(64, 1), table.create(64, 1)
		for y = 0, 7 do
			for x = 0, 7 do
				local code = STAMP_CODE[string.sub(rows[y + 1], x + 1, x + 1)] or 1
				plain[y * 8 + x + 1] = code
				mirrored[y * 8 + (7 - x) + 1] = code
			end
		end
		table.insert(list, plain)
		table.insert(list, mirrored)
	end
	STAMPS[family] = list
end

-- The stamp variant of the 8×8 block holding pixel (x, y) of a pattern grid.
local function stampOf(stamps: { { number } }, x: number, y: number): { number }
	return stamps[hash32(x // 8, y // 8, 31) % #stamps + 1]
end

-- A biome's ground palette (base, light, dark, highlight, shadow) on low or high ground, lit (1), flat (2) or
-- shaded (3) by the light from the north-west. Glowing colours (lava glints) never darken. `soft`: the whole map's
-- version, its marks closer to the base colour, since at one pixel per map pixel strong marks read as specks.
local palettes: { [Style]: { [number]: { number } } } = {}
local function paletteOf(s: Style, high: boolean, shade: number, soft: boolean?): { number }
	local set = palettes[s]
	if set == nil then
		set = {}
		palettes[s] = set
	end
	local key = (if high then 3 else 0) + shade + (if soft then 6 else 0)
	local pal = set[key]
	if pal == nil then
		local hi = s.high
		local b = if high and hi then hi else s.base
		local l = if high and hi then mix(hi, s.light, 0.5) else s.light
		local d = if high and hi then scale(hi, 0.85) else s.dark
		local k = SHADE[shade]
		local list = if soft
			then {
				b,
				if GLOW[l] then l else mix(b, l, 0.45),
				mix(b, d, 0.45),
				mix(b, l, 0.85),
				mix(b, scale(d, 0.9), 0.85),
			}
			else { b, l, d, mix(l, 0xffffff, 0.2), scale(d, 0.8) }
		pal = {}
		for i, c in list do
			pal[i] = if GLOW[c] or k == 1 then c else scale(c, k)
		end
		set[key] = pal
	end
	return pal
end

-- Pattern families of made surfaces (Skyshards' plating, crop rows, metal): no slopes, no shading.
local FLAT: { [string]: boolean } = { panels = true, rows = true, metal = true }

-- Light from the north-west: lit (1) where the ground rises towards the south-east, shaded (3) where it falls.
local function shadeAt(art: Art, x: number, y: number): number
	local w, h = art.width, art.height
	if FLAT[(art.biomes[buffer.readu8(art.ids, y * w + x)] or FALLBACK).family] then
		return 2
	end
	local elev = art.elevation
	local here = buffer.readu8(elev, y * w + x)
	local ax, ay = math.max(x - 1, 0), math.max(y - 1, 0)
	local bx, by = math.min(x + 1, w - 1), math.min(y + 1, h - 1)
	local a = buffer.readu8(elev, ay * w + ax)
	local b = buffer.readu8(elev, by * w + bx)
	if a == 0 then
		a = here
	end
	if b == 0 then
		b = here
	end
	local g = b - a
	return if g > SHADE_SLOPE then 1 elseif g < -SHADE_SLOPE then 3 else 2
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

-- Gentle waves on open water: short light dashes on every few rows, staggered, in random runs. `x`, `y` and
-- `period` are in the painting's own pixels (the close-up passes sub-pixels and a longer period).
local function waveAt(x: number, y: number, period: number, deep: boolean): boolean
	if y % period ~= 0 then
		return false
	end
	local row = y // period
	local sx = x + row * (period + 1)
	local length = period * 2 + 3
	if sx % length >= (period + 1) // 2 + 1 then
		return false
	end
	return hash32(sx // length, row, 61) % (if deep then 5 else 3) == 0
end

-- A two-pass chamfer distance transform in place: every non-zero pixel gets its distance to the nearest zero pixel,
-- in SEA_UNITs (SEA_UNIT per straight step, one more per diagonal step, so distances come out nearly round), capped
-- at 255.
local function chamfer(field: buffer, w: number, h: number)
	local straight, diagonal = SEA_UNIT, SEA_UNIT + 1
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local i = y * w + x
			local v = buffer.readu8(field, i)
			if v ~= 0 then
				if x > 0 then
					v = math.min(v, buffer.readu8(field, i - 1) + straight)
				end
				if y > 0 then
					v = math.min(v, buffer.readu8(field, i - w) + straight)
					if x > 0 then
						v = math.min(v, buffer.readu8(field, i - w - 1) + diagonal)
					end
					if x < w - 1 then
						v = math.min(v, buffer.readu8(field, i - w + 1) + diagonal)
					end
				end
				buffer.writeu8(field, i, math.min(v, 255))
			end
		end
	end
	for y = h - 1, 0, -1 do
		for x = w - 1, 0, -1 do
			local i = y * w + x
			local v = buffer.readu8(field, i)
			if v ~= 0 then
				if x < w - 1 then
					v = math.min(v, buffer.readu8(field, i + 1) + straight)
				end
				if y < h - 1 then
					v = math.min(v, buffer.readu8(field, i + w) + straight)
					if x < w - 1 then
						v = math.min(v, buffer.readu8(field, i + w + 1) + diagonal)
					end
					if x > 0 then
						v = math.min(v, buffer.readu8(field, i + w - 1) + diagonal)
					end
				end
				buffer.writeu8(field, i, math.min(v, 255))
			end
		end
	end
end

local function paintTerrain(art: Art, biomeOf: { [number]: Style }, yield: Yield?)
	local w, h = art.width, art.height
	local ids = art.ids
	local sky = art.theme == "sky"

	-- distance from land over water, for the ocean's depth bands (round, thanks to the chamfer transform)
	local dist = art.sea
	for i = 0, w * h - 1 do
		buffer.writeu8(dist, i, if buffer.readu8(ids, i) ~= 0 then 0 else 255)
	end
	chamfer(dist, w, h)
	local function depth(i: number): number -- 1 shallow, 2 close ocean, 3 deep
		local d = buffer.readu8(dist, i)
		return if d <= SHALLOW_TO * SEA_UNIT then 1 elseif d <= MEDIUM_TO * SEA_UNIT then 2 else 3
	end
	local patches = smoothNoise(w, h, 12, 5)
	local detail = smoothNoise(w, h, 5, 6)
	local calm = smoothNoise(w, h, 16, 14) -- waves only show in patches of rougher water

	-- mountains: ridge height (0 to 255) where smooth noise crosses its middle, low along the province's edge
	local rock = edgeDistance(art, biomeOf, yield)
	local ridges = smoothNoise(w, h, 11, 11)
	local ridgeDetail = smoothNoise(w, h, 4, 12)
	local snowPatches = smoothNoise(w, h, 9, 13)
	local elev, heights, levels = art.elevation, art.ridge, art.level
	for i = 0, w * h - 1 do
		local pid = buffer.readu8(ids, i)
		if pid ~= 0 then
			local x, y = i % w, i // w
			buffer.writeu8(elev, i, math.clamp(math.floor((patches(x, y) * 0.7 + detail(x, y) * 0.3) * 255), 1, 255))
			if biomeOf[pid].deco == "rock" then
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
						local k = stampOf(STAMPS.rock, x, y)[(y % 8) * 8 + x % 8 + 1]
						c = if k == 2 or k == 4 then band.a elseif k == 3 or k == 5 then band.b else band.base
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
					local e = buffer.readu8(elev, i)
					local high = s.high ~= nil and e > HIGH_AT
					local pal = paletteOf(s, high, shadeAt(art, x, y), true)
					local stamps = STAMPS[s.family]
					local k = if stamps then stampOf(stamps, x, y)[(y % 8) * 8 + x % 8 + 1] else 1
					if high then
						-- high ground: a dark lip on its south side, a lit edge on its north side
						if y < h - 1 and buffer.readu8(elev, i + w) <= HIGH_AT then
							k = 5
						elseif y > 0 and buffer.readu8(elev, i - w) <= HIGH_AT then
							k = 4
						end
					end
					c = pal[k]
					if s.deco == "flowers" and noise(x, y, 7) > (if s == BIOMES.meadow then 0.985 else 0.994) then
						c = FLOWERS[1 + math.floor(noise(x, y, 8) * #FLOWERS)]
					elseif s.deco == "rows" and y % 3 == 0 then
						c = (s.sprite :: { [string]: number }).R -- crop rows
					elseif s.deco == "panels" then
						-- hull plating: 8-pixel panels in three shades, faint seams, a few lit seams
						local panel = s.sprite :: { [string]: number }
						if x % 8 == 0 or y % 8 == 0 then
							local lit = noise(x // 8, y // 8, 9)
							c = if lit < 0.04 then panel.C elseif lit < 0.08 then panel.E else panel.R
						else
							local shade = noise(x // 8, y // 8, 10)
							c = if shade < 0.2 then panel.P elseif shade > 0.8 then panel.Q else c
						end
					end
				end
			elseif sky then
				local planet
				c, planet = spaceAt(x + 0.5, y + 0.5, w, h) -- the nebula's glow, or a distant planet
				if not planet then
					local bright = brightStarAt(x, y)
					if bright > 0 then
						c = mix(c, SPACE.star, bright)
					elseif n > 0.997 then
						c = SPACE.star
					elseif x % 32 == 0 or y % 32 == 0 then
						c = mix(c, SPACE.grid, 0.6)
					end
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
				if calm(x, y) > 0.45 and waveAt(x, y, 4, band == 3) then
					c = if band == 1 then SEA.shallowWave elseif band == 2 then SEA.mediumWave else SEA.deepWave
				end
				if y > 0 and buffer.readu8(ids, i - w) ~= 0 then
					c = SEA.shadow -- just south of land
				elseif buffer.readu8(dist, i) == SEA_UNIT then
					c = SEA.foam -- along the other shores
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

local function unrgba(v: number): number
	return bit32.band(v, 255) * 65536 + bit32.band(bit32.rshift(v, 8), 255) * 256 + bit32.band(bit32.rshift(v, 16), 255)
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
	art.changed[pid] = true
	local o = art.owner[pid] or 0
	local nation = if o ~= 0 then art.color[o] or 0x808080 else 0
	local border = if o ~= 0 then art.border[o] or scale(nation, 0.75) else 0
	local selected = art.selected == pid
	local w = art.width
	local ids, terrain, near, pixels = art.ids, art.terrain, art.near, art.pixels
	local look = if o ~= 0 then art.styles[o] else nil
	local borderStyle = if look then look.border else "solid"
	local shades = if look then look.shades else "default"

	-- most pixels' colours depend only on their terrain colour: work each one out once per repaint
	local washed: { [number]: number } = {}
	local function wash(c: number): number
		local t = washed[c]
		if t == nil then
			local tint = if shades == "default" then nation else PixelArt.shadeColor(shades, nation, brightness(c))
			t = if o ~= 0 then mix(c, tint, NATION_ALPHA) else c
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
				-- the nation border, in its style's pattern
				local b = if borderStyle == "solid" then border else PixelArt.borderShade(borderStyle, border, x, y)
				v = mix(c, b, BORDER_ALPHA)
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

-- The colour of one pixel of a capital on the whole map: the owner's flag and roofs (F R), the building's own
-- colours, then Skyshards' materials or the classic ones.
local function capitalColour(kind: string, sky: boolean, ch: string, flag: number): number
	if ch == "F" or ch == "R" then
		return flag
	end
	local own = KIND_COLOURS[kind]
	return (own and own[ch]) or (if sky then SKY_CAPITAL_COLOURS[ch] else nil) or CAPITAL_COLOURS[ch]
end

-- Capitals (each race's own, CAPITALS) go on top of everything, after any repaint, since they overlap neighbours.
local function drawCapitals(art: Art)
	for pid, capital in art.capitals do
		local sprite = CAPITALS[capital.kind]
		local h, w = #sprite, #sprite[1]
		local sky = sciFi(art.theme, capital.kind)
		local o = art.owner[pid] or 0
		local flag = if o ~= 0 then art.color[o] or 0x808080 else 0xb0b0b0
		local x0, y0 = capital.x - 2, capital.y - 3
		for j = 1, h do
			for i = 1, w do
				local ch = string.sub(sprite[j], i, i)
				local x, y = x0 + i - 1, y0 + j - 1
				if ch ~= "." and x >= 0 and y >= 0 and x < art.width and y < art.height then
					local c = capitalColour(capital.kind, sky, ch, flag)
					buffer.writeu32(art.pixels, (y * art.width + x) * 4, rgba(c))
				end
			end
		end
		markDirty(art, x0, y0, x0 + w - 1, y0 + h - 1)
	end
end

------------------------------------------------------------------------------------------------- close-up detail

-- When the camera is zoomed in, MapRenderer lays a second image over the map: just the part in view, painted at
-- DETAIL_FACTOR × DETAIL_FACTOR sub-pixels per map pixel from the same painting (Art), so zooming in shows more
-- detail instead of bigger blocks, the way WorldBox draws every tile as a little 8×8 sprite:
--   * the biome's ground pattern (STAMPS) at full sub-pixel resolution, lit from the north-west;
--   * coasts and province edges smoothed: each map pixel's corners are cut where both neighbours on that side agree
--     (the Scale2x rule), so staircases become diagonals; the same for high ground, water depths and mountain bands,
--     which are blended between pixel centres;
--   * beaches with wet sand, white surf and foam, a shadow under the south shores, wave dashes;
--   * dense shaded trees, bushes, rocks, flowers, cacti, crystals and towers (DETAIL_DECOS), each one deterministic
--     per map pixel so two overlapping close-ups always agree;
--   * a lighter kingdom wash (DETAIL_ALPHA) so the terrain shows through, with a stronger band just inside the
--     nation's border and a crisp border line, a thin line between provinces, and a white outline on the selection;
--   * each race's detailed capital on top (DETAIL_CAPITALS).
-- Ownership changes repaint only the provinces involved (syncDetail), like the whole-map painting.

local DETAIL_FACTOR = 4
local DETAIL_MARGIN = 2 -- map pixels worked out around the close-up (border checks, sprites reaching in)
local DETAIL_TOP = DETAIL_MARGIN + HULL + 1 -- (more above: Skyshards' hulls hang below their platforms)
local DETAIL_ALPHA = 0.48 -- the kingdom wash in the close-up: lighter, so the terrain shows through
local DETAIL_RIM_ALPHA = 0.7 -- a stronger band just inside a nation's border
local DETAIL_BORDER = 2 -- sub-pixels of nation border
local DETAIL_RIM = 2 -- sub-pixels of stronger wash inside it
local DETAIL_SELECT = 2 -- sub-pixels of white outline round the selected province
local DETAIL_LINE = 0.8 -- the 1-sub-pixel line between provinces darkens to this share
local DETAIL_ROCK_SLOPE = 3 -- ridge height change across half a map pixel that counts as a lit or shaded slope
local DETAIL_WAVES = 10 -- sub-pixel rows between wave dashes
local SHORE = 1 -- detail flag: beach, surf or rim (no sprites on it)

export type Detail = {
	factor: number, -- sub-pixels per map pixel
	width: number, -- image size in sub-pixels
	height: number,
	cols: number, -- map pixels covered
	rows: number,
	x0: number, -- the map pixel at the top-left (-1 before the first paint)
	y0: number,
	pixels: buffer, -- RGBA, width × height
	ew: number, -- the working area: the close-up plus margins, in sub-pixels
	eh: number,
	ids: buffer, -- per working sub-pixel: its province (0 = sea or space), corners cut
	terrain: buffer, -- per working sub-pixel: 0xRRGGBB before the kingdom wash
	flags: buffer, -- per working sub-pixel: SHORE
	painted: Art?, -- the painting it was last painted from
	dirty: { number }?, -- x0, y0, x1, y1 (sub-pixels) changed since the last takeDetailDirty
}

PixelArt.DETAIL = {
	factor = DETAIL_FACTOR,
	alpha = DETAIL_ALPHA,
	rimAlpha = DETAIL_RIM_ALPHA,
	border = DETAIL_BORDER,
	rim = DETAIL_RIM,
	borderAlpha = BORDER_ALPHA,
	select = DETAIL_SELECT,
}

-- Close-up sprites, in sub-pixels, drawn with their bottom row's middle on a jittered spot in their map pixel.
-- L M D: the biome's sprite (or light, base, dark) colours; h highlight; S deep shade; T t trunk; k a shadow cast on
-- the ground (south-east, away from the light); r R q rock greys; x X cactus; W snow; F a flower; C c crystal glow;
-- G B tower metal; P hill foot; Y y lamp light.
local DETAIL_SPRITES: { [string]: { string } } = {
	tree = {
		"..hLL..",
		".hLLLLM",
		"hLLLLMM",
		"LLLMMMD",
		"LMMMMDD",
		".MMDDDS",
		"..DTDkk",
		"...Tkk.",
	},
	round = { ".hLL..", "hLLLM.", "LLLMMD", "LMMMDD", ".MDDSk", "..Tkk." },
	jungle = {
		"...hLL...",
		".hLLLLMM.",
		"hLLLLMMMD",
		"LLLMMMMDD",
		"LMMMMMDDD",
		".MMMDDDDS",
		"...DTDkk.",
		"....Tkk..",
	},
	pine = { "...W...", "..LLM..", "..LMM..", ".WLLMD.", ".LLMMD.", "LLLMMDD", "LLMMMDS", "..kTkk.", "...Tk.." },
	palm = { "hL...L.", ".LL.LM.", "..LLM..", "LM.TMDM", "L..T..D", "...T...", "..T....", "..Tkk.." },
	acacia = { ".hLLLLM..", "hLLLMMMMD", ".DDMDDDDS", "....T....", "....Tt...", "....Tkk.." },
	bush = { ".hL.", "LMMD", ".DSk" },
	rock = { ".rR.", "rRRq", "Rqqk" },
	boulder = { ".rrR.", "rRRRq", "RRqqq", ".qqkk" },
	cactus = { "..x..", "x.x..", "xxx.x", "..xxX", "..x..", "..xkk" },
	flowers = { "F...", "D.F.", "..D." },
	mound = { "....hLL.....", "..hLLLLMM...", ".hLLLMMMMD..", "hLLMMMMMDDD.", "PPPPPPPPPPPk", "..kkkkkkkk.." },
	crystal = { "..C..", ".CWC.", ".CCc.", "CWCcc", "CCccD", ".DDD.", "..kk." },
	tower = { "..C..", "..G..", ".GGB.", ".GCB.", ".GGB.", "GGGBB", "GGGGB", "BBBBB", ".kkkk" },
	plate = { ".hLL..", "hLLMMD", "LMMMDD", ".DDDk." },
	light = { ".y.", "yYy", ".y." },
}

-- Which close-up decorations grow in each biome, and how often (chance per map pixel; one at most per pixel).
local DETAIL_DECO_TABLE: { [string]: { { any } } } = {
	grassland = { { "tree", 0.015 }, { "bush", 0.05 }, { "flowers", 0.05 }, { "rock", 0.01 } },
	steppe = { { "bush", 0.035 }, { "rock", 0.015 } },
	savanna = { { "acacia", 0.03 }, { "bush", 0.04 } },
	tundra = { { "rock", 0.02 }, { "bush", 0.015 } },
	desert = { { "cactus", 0.02 }, { "rock", 0.015 }, { "palm", 0.006 } },
	drylands = { { "rock", 0.03 }, { "bush", 0.02 } },
	forest = { { "tree", 0.42 }, { "round", 0.2 }, { "bush", 0.08 } },
	jungle = { { "jungle", 0.55 }, { "round", 0.15 }, { "bush", 0.1 } },
	taiga = { { "pine", 0.36 }, { "rock", 0.02 } },
	hills = { { "mound", 0.05 }, { "rock", 0.03 }, { "bush", 0.03 } },
	mountains = { { "boulder", 0.012 } },
	ice = { { "rock", 0.005 } },
	meadow = { { "flowers", 0.14 }, { "bush", 0.04 }, { "tree", 0.012 } },
	frostfields = { { "rock", 0.012 }, { "bush", 0.01 } },
	dunes = { { "rock", 0.01 }, { "cactus", 0.008 } },
	wildwood = { { "tree", 0.4 }, { "round", 0.2 }, { "flowers", 0.06 } },
	highlands = { { "mound", 0.05 }, { "bush", 0.04 }, { "rock", 0.02 } },
	ashlands = { { "rock", 0.03 } },
	peaks = { { "boulder", 0.012 } },
	crystalgrove = { { "crystal", 0.16 } },
	crags = { { "plate", 0.07 } },
	stormspire = { { "tower", 0.09 } },
}

type Pixel = { dx: number, dy: number, ch: string }
type DecoChoice = { upTo: number, pixels: { Pixel } }

-- Sprites as pixel lists, relative to their foot (bottom row, middle).
local function compile(rows: { string }): { Pixel }
	local list: { Pixel } = {}
	local h, w = #rows, #rows[1]
	for j = 1, h do
		for i = 1, w do
			local ch = string.sub(rows[j], i, i)
			if ch ~= "." then
				table.insert(list, { dx = i - 1 - w // 2, dy = j - h, ch = ch })
			end
		end
	end
	-- shadows first, so a sprite's own pixels cover them
	table.sort(list, function(a, b)
		local ka, kb = if a.ch == "k" then 0 else 1, if b.ch == "k" then 0 else 1
		if ka ~= kb then
			return ka < kb
		end
		return if a.dy ~= b.dy then a.dy < b.dy else a.dx < b.dx
	end)
	return list
end
local DETAIL_PIXELS: { [string]: { Pixel } } = {}
for name, rows in DETAIL_SPRITES do
	DETAIL_PIXELS[name] = compile(rows)
end
local DETAIL_DECOS: { [Style]: { DecoChoice } } = {}
for name, list in DETAIL_DECO_TABLE do
	local choices: { DecoChoice } = {}
	local total = 0
	for _, entry in list do
		total += entry[2] :: number
		table.insert(choices, { upTo = total, pixels = DETAIL_PIXELS[entry[1] :: string] })
	end
	DETAIL_DECOS[BIOMES[name]] = choices
end

-- Capitals in the close-up: CAPITAL_W × CAPITAL_H sub-pixels, built from rectangles and shapes, one per race (and
-- the dome for the Humans on Skyshards), each flying the owner's flag on a pole at x = 10. Colours: F f the owner's
-- flag, R r roofs and banners in the owner's colour, p the flagpole, M m D lit, middle and shaded stone, W lit
-- windows, C c the dome's glow, G g e lit, middle and shaded leaves, T t u lit, middle and shaded bark, H h hide,
-- X x wood, B bone, K a dark doorway, Q q k lit, middle and shaded rock, S snow, O fire.
local CAPITAL_W, CAPITAL_H = 21, 22

type Sprite = {
	put: (x: number, y: number, ch: string) -> (),
	rect: (x0: number, y0: number, x1: number, y1: number, ch: string) -> (),
	rows: () -> { string },
}

local function newSprite(): Sprite
	local grid: { { string } } = {}
	for y = 1, CAPITAL_H do
		grid[y] = table.create(CAPITAL_W, ".")
	end
	local function put(x: number, y: number, ch: string)
		if x >= 0 and y >= 0 and x < CAPITAL_W and y < CAPITAL_H then
			grid[y + 1][x + 1] = ch
		end
	end
	return {
		put = put,
		rect = function(x0: number, y0: number, x1: number, y1: number, ch: string)
			for y = y0, y1 do
				for x = x0, x1 do
					put(x, y, ch)
				end
			end
		end,
		rows = function(): { string }
			local rows: { string } = {}
			for y = 1, CAPITAL_H do
				rows[y] = table.concat(grid[y])
			end
			return rows
		end,
	}
end

-- The owner's flag at the top of its pole (x = 10, rows 0 to `foot`).
local function flagOn(s: Sprite, foot: number)
	s.rect(10, 0, 10, foot, "p")
	s.rect(11, 0, 13, 0, "F")
	s.rect(11, 1, 12, 1, "F")
	s.put(14, 0, "f")
end

-- The Humans' stone castle: side towers with roofs in the owner's colour, curtain walls, the keep and its gate.
local function buildCastle(): { string }
	local s = newSprite()
	local rect, put = s.rect, s.put
	for _, x0 in { 0, 16 } do
		rect(x0, 7, x0 + 4, 21, "m")
		rect(x0, 7, x0, 21, "M")
		rect(x0 + 4, 7, x0 + 4, 21, "D")
		put(x0 + 2, 3, "R")
		rect(x0 + 1, 4, x0 + 3, 4, "R")
		rect(x0, 5, x0 + 4, 6, "R")
		rect(x0 + 3, 4, x0 + 3, 4, "r")
		rect(x0 + 3, 5, x0 + 4, 6, "r")
		rect(x0 + 2, 10, x0 + 2, 11, "W")
	end
	rect(5, 12, 15, 21, "m")
	put(5, 11, "M")
	put(15, 11, "D")
	rect(7, 5, 13, 21, "m")
	rect(7, 5, 7, 21, "M")
	rect(13, 5, 13, 21, "D")
	for x = 7, 13, 2 do
		put(x, 4, if x == 13 then "D" else "M")
	end
	rect(10, 8, 10, 9, "W")
	rect(9, 17, 11, 21, "D")
	put(10, 16, "D")
	rect(0, 21, 20, 21, "D")
	flagOn(s, 3)
	return s.rows()
end

-- The Humans' capital on Skyshards: a glowing dome on a steel base.
local function buildDome(): { string }
	local s = newSprite()
	local rect, put = s.rect, s.put
	rect(2, 15, 18, 20, "m")
	rect(2, 15, 2, 20, "M")
	rect(18, 15, 18, 20, "D")
	rect(2, 21, 18, 21, "D")
	for y = 7, 14 do
		for x = 3, 17 do
			local dx, dy = x - 10, (y - 15) * 1.2
			if dx * dx + dy * dy <= 52 then
				put(x, y, if dx + dy < -6 then "W" elseif dx > 3 then "c" else "C")
			end
		end
	end
	rect(10, 0, 10, 7, "p")
	rect(11, 1, 13, 1, "F")
	rect(11, 2, 12, 2, "F")
	put(14, 1, "f")
	rect(6, 17, 7, 18, "W")
	rect(13, 17, 14, 18, "W")
	return s.rows()
end

-- The Elves' tree hall: a great pale-barked tree, its crown lit from the north-west, little halls with roofs in the
-- owner's colour up in the leaves, lanterns, and a glowing door between the roots.
local function buildTreeHall(): { string }
	local s = newSprite()
	local rect, put = s.rect, s.put
	rect(8, 11, 12, 20, "t")
	rect(8, 11, 8, 20, "T")
	rect(12, 11, 12, 20, "u")
	rect(7, 18, 13, 20, "t")
	put(7, 18, "T")
	put(13, 18, "u")
	rect(6, 20, 14, 20, "t")
	put(6, 20, "T")
	put(14, 20, "u")
	rect(5, 21, 15, 21, "u")
	local crowns = { { 10, 7.5, 7.6, 5.4 }, { 4.8, 10, 4.6, 3.6 }, { 15.2, 10, 4.6, 3.6 } } -- centre, radii
	local function leafy(x: number, y: number): boolean
		for _, k in crowns do
			local dx, dy = (x - k[1]) / k[3], (y - k[2]) / k[4]
			if dx * dx + dy * dy <= 1 then
				return true
			end
		end
		return false
	end
	for y = 0, CAPITAL_H - 1 do
		for x = 0, CAPITAL_W - 1 do
			if leafy(x, y) then
				local light = (x - 10) * 0.7 + (y - 8)
				local clump = (x * 3 + y * 5) % 7 -- leaf clumps: a few lit and shaded leaves in the middle tone
				put(
					x,
					y,
					if not leafy(x, y + 1) or light > 3.5
						then "e"
						elseif light < -4.5 or (light < 1 and clump == 0) then "G"
						elseif clump == 3 then "e"
						else "g"
				)
			end
		end
	end
	for _, x0 in { 3, 15 } do
		put(x0 + 1, 8, "R")
		rect(x0, 9, x0 + 1, 9, "R")
		put(x0 + 2, 9, "r")
		put(x0, 10, "T")
		put(x0 + 1, 10, "W")
		put(x0 + 2, 10, "u")
		put(x0, 11, "T")
		put(x0 + 1, 11, "t")
		put(x0 + 2, 11, "u")
	end
	put(7, 5, "W")
	put(13, 6, "W")
	put(10, 12, "W")
	rect(9, 14, 9, 15, "W")
	rect(11, 14, 11, 15, "W")
	rect(9, 18, 11, 21, "W")
	put(10, 17, "W")
	flagOn(s, 3)
	return s.rows()
end

-- The Orcs' war camp: a great hide tent on crossed poles with a band in the owner's colour, a fire in its door, and a
-- palisade of stakes with bone spikes in front.
local function buildWarCamp(): { string }
	local s = newSprite()
	local rect, put = s.rect, s.put
	local function half(y: number): number -- the tent's half width on row y
		return (y - 4) * 0.62 + 0.5
	end
	for y = 4, 20 do
		local w = math.floor(half(y))
		for x = 10 - w, 10 + w do
			local d = x - 10
			local seam = d ~= 0 and math.abs(math.abs(d) - (y - 4) * 0.3) < 0.5 -- where two hides are sewn
			local edge = math.abs(d) == w and w > 0 -- a dark edge, so the tent stands out on any land
			put(x, y, if edge or (d > 0 and seam) then "x" elseif d < 0 then (if seam then "h" else "H") else "h")
		end
	end
	for y = 10, 11 do
		local w = math.floor(half(y))
		rect(10 - w, y, 10, y, "R")
		rect(11, y, 10 + w, y, "r")
	end
	for y = 13, 20 do
		local w = math.floor((y - 13) * 0.5)
		rect(10 - w, y, 10 + w, y, "K")
	end
	rect(9, 20, 11, 20, "O")
	put(10, 19, "O")
	for _, p in { { 9, 3 }, { 8, 2 }, { 11, 3 }, { 12, 2 } } do
		put(p[1], p[2], "X") -- the tent poles, crossed over the top
	end
	for _, y in { 8, 14 } do -- bone spikes out of the hides
		local w = math.floor(half(y))
		put(9 - w, y, "B")
		put(8 - w, y - 1, "B")
		put(11 + w, y, "B")
		put(12 + w, y - 1, "B")
	end
	for _, x in { 0, 2, 18, 20 } do -- the palisade, its stakes sharpened
		rect(x, 16, x, 21, if x < 10 then "X" else "x")
		put(x, 15, "B")
	end
	rect(0, 18, 3, 18, "x")
	rect(17, 18, 20, 18, "x")
	flagOn(s, 3)
	return s.rows()
end

-- The Dwarves' stone hall: a mountain lit on its western face with snow on its peak, and carved into it a hall
-- front of pillars and a lintel under a gable in the owner's colour, banners, and a gate glowing with a forge.
local function buildStoneHall(): { string }
	local s = newSprite()
	local rect, put = s.rect, s.put
	for y = 3, CAPITAL_H - 1 do
		local half = (y - 3) * 0.58 + 0.5
		local ridge = (y - 3) * 0.2 -- the ridge leans east as it falls
		for x = 0, CAPITAL_W - 1 do
			local d = x - 10
			if math.abs(d) <= half then
				local ch = if d < ridge - 1 then "Q" elseif d <= ridge then "q" else "k"
				if y - 3 <= 3 - math.abs(d) * 0.8 then
					ch = "S"
				elseif (ch == "Q" and (x + 2 * y) % 7 == 0) or (ch == "k" and (x + y) % 5 == 0) then
					ch = "q" -- cracks in the rock
				end
				put(x, y, ch)
			end
		end
	end
	rect(9, 9, 10, 9, "R")
	put(11, 9, "r")
	rect(7, 10, 10, 10, "R")
	rect(11, 10, 13, 10, "r")
	rect(5, 11, 15, 11, "M")
	rect(5, 12, 15, 12, "m")
	put(15, 12, "D")
	rect(5, 13, 5, 21, "M")
	rect(6, 13, 6, 21, "m")
	rect(14, 13, 14, 21, "m")
	rect(15, 13, 15, 21, "D")
	rect(7, 13, 7, 16, "R")
	rect(13, 13, 13, 16, "r")
	rect(8, 15, 12, 21, "K")
	rect(9, 14, 11, 14, "K")
	rect(9, 19, 11, 21, "O")
	put(10, 18, "O")
	put(3, 16, "W")
	put(17, 16, "W")
	rect(7, 7, 7, 8, "W")
	rect(13, 7, 13, 8, "W")
	flagOn(s, 3)
	return s.rows()
end

local DETAIL_CAPITALS: { [string]: { string } } = {
	Humans = buildCastle(),
	dome = buildDome(),
	Elves = buildTreeHall(),
	Orcs = buildWarCamp(),
	Dwarves = buildStoneHall(),
	-- The other peoples' buildings, drawn straight as rows (CAPITAL_W × CAPITAL_H; the same codes, the flag on its
	-- pole at x = 10, and DETAIL_KIND_COLOURS for each one's own colours).
	-- a castle: round towers under tall cones in the owner's colour, a keep with a pointed roof, a gate
	Kingdom = {
		"..........pFFFf......",
		"..........pFF........",
		"..R.......p.......R..",
		".RRr......p......RRr.",
		".RRr.....RRr.....RRr.",
		"RRRrr...RRRrr...RRRrr",
		"RRRrr..RRRRrrr..RRRrr",
		"RRRrr..MmmmmmD..RRRrr",
		"DDDDD..MmmmmmD..DDDDD",
		"MmmmD..MmWmWmD..MmmmD",
		"MmmmD..MmWmWmD..MmmmD",
		"MmWmD..MmmmmmD..MmWmD",
		"MmWmD..MmmmmmD..MmWmD",
		"MmmmDM.MmmmmmD.DMmmmD",
		"MmmmDmmMmmmmmDmmMmmmD",
		"MmmmDmmMmmmmmDmmMmmmD",
		"MmmmDmmMmmKmmDmmMmmmD",
		"MmmmDmmMmKKKmDmmMmmmD",
		"MmmmDmmMmKKKmDmmMmmmD",
		"MmmmDmmMmKKKmDmmMmmmD",
		"MmmmDmmMmKKKmDmmMmmmD",
		"DDDDDDDDDDDDDDDDDDDDD",
	},
	-- a marble palace: steps, columns before a shaded portico, a pediment roofed in the owner's colour
	Empire = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p..........",
		"..........p..........",
		"..........R..........",
		".........Rrr.........",
		".......RRMMMrr.......",
		".....RRMMYYYMMrr.....",
		"...RRMMMMMYMMMMMrr...",
		"..MMMMMMMMMMMMMMMMM..",
		"..mmmmmmmmmmmmmmmmm..",
		"...DDDDDDDDDDDDDDD...",
		"...MmDDMmDDDMmDDMm...",
		"...MmDDMmYYYMmDDMm...",
		"...MmDDMmKKKMmDDMm...",
		"...MmDDMmKKKMmDDMm...",
		"...MmDDMmKKKMmDDMm...",
		"...MmDDMmKKKMmDDMm...",
		"..DDDDDDDDDDDDDDDDD..",
		".MMMMMMMMMMMMMMMMMMM.",
		"mmmmmmmmmmmmmmmmmmmmm",
		"DDDDDDDDDDDDDDDDDDDDD",
	},
	-- a great felt tent with a band in the owner's colour and a painted door, a horse-tail standard
	Nomads = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p..........",
		"..........p..........",
		"..........p..........",
		"..........p..........",
		"..........p........H.",
		"..........p.......hhh",
		".........VVV......hhh",
		"........VvVwV.....hhh",
		".......VvVVVwv....hxh",
		".....VVvVVVVVwvv...x.",
		"....VVvVVVVVVvwvv..x.",
		"..vvvvvvvvvvvvvvvvvx.",
		"..VVVVVVVVVVVVvvvvvx.",
		"..VVVVVVVVVVVVvvvvvx.",
		"..RRRRRRRRRRRRrrrrrx.",
		"..RRRRRRRRRRRRrrrrrx.",
		"..VVVVVVVXXXVVvvvvvx.",
		"..VVVVVVVXOXVVvvvvvx.",
		"..VVVVVVVXOXVVvvvvvx.",
		"..wwwwwwwwwwwwwwwwwx.",
	},
	-- a harbour: a lantern tower, a merchants' hall roofed in the owner's colour, a boat, the water
	Republic = {
		"..R.......pFFFf......",
		"RRRrr.....pFF........",
		".OOO......p..........",
		".OWO......p..........",
		".OOO......p..........",
		"MmmmD.....p..........",
		"MmmmD.....p..........",
		"MmmmD.....p..........",
		"MmWmD.RRRRRrrrrr.....",
		"MmWmDRRRRRRrrrrrr....",
		"MmmmDRRRRRRrrrrrr....",
		"MmmmDMmmmmmmmmmmD....",
		"MmWmDMmWWmWWmWWmD.x..",
		"MmWmDMmWWmWWmWWmD.xrR",
		"MmmmDMmmmmmmmmmmD.xrR",
		"MmmmDMmKKmKKmKKmD.xrR",
		"MmmmDMmKKmKKmKKmD.xrR",
		"MmmmDMmKKmKKmKKmD.x..",
		"MmmmDDDDDDDDDDDDXXXXX",
		"wwwwwwwwwwwwwwwwwxxxw",
		"aAAAaAAAaAAAaAAAaAAAa",
		"AAaAAAaAAAaAAAaAAAaAA",
	},
	-- a tower house with the owner's banner on a crag, a palisade of stakes round it
	Clans = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p..........",
		".......M.MpM.D.......",
		".......MmmmmmD.......",
		".......MmmmmmD.......",
		".......MmWmWmD.......",
		".......MmWmWmD.......",
		".......MRmmmrD.......",
		".......MRmmmrD.......",
		".......MRmKmrD.......",
		".......MRKKKrD.......",
		".......MmKKKmD.......",
		".......MmKKKmD.......",
		"..B.B.BMmKKKmDB.B.B..",
		"..X.XQXQkqqqqqxkx.x..",
		"..X.XQXQqqkqqqxkx.x..",
		"..xxxxxqqqqqkqxxxxx..",
		"..XkXQXQQqqqqqxkxkx..",
		"..XQXkXQqqqqqqxkxkx..",
		".QQQQQQkqqqqqqkkkkkk.",
		"QQQQQQQQQkqqqqqkkkkkk",
	},
	-- a stepped pyramid of mossy stone, a stair, a shrine with a glowing door and a crest
	Lizardfolk = {
		"..........pFFFf......",
		"..........pFF........",
		".......RRRprrr.......",
		"........Qqqqk........",
		"........QqCqk........",
		"........QqCqk........",
		".......ggqqqgg.......",
		".......eQQQQek.......",
		".......QQqqqkk.......",
		".......QQQQQkk.......",
		".....ggggqqqgggg.....",
		".....eQqqQQQqqke.....",
		".....QQqqqqqqqkk.....",
		".....QQqqQQQqqkk.....",
		"...ggggggqqqgggggg...",
		"...eQqqqeQQQqeqqkk...",
		"g..QQqqqqqqqqqqqkk..g",
		"e..QQqqqqQQQqqqqkk..e",
		"eggggggggqqqgggggggge",
		"egQqqqeqqQQQqqqqeqkke",
		"eQQqqqqqqqqqqqqqqqkke",
		"eQQqqqqqqQQQqqqqqqkke",
	},
	-- a factory block with cyan windows and a red-lit bay, a radar dish, a mast with red lights
	Robots = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p......O...",
		"..........p.....Xxx..",
		".......O..p.....Xxx..",
		"....MMM...p.....DDD..",
		"...MMMMM..p.....Xxx..",
		"...mmmmm..p.....Xxx..",
		"....mmm...p.....Xxx..",
		".....D....p.....DDD..",
		".DDDDDDDDDDDDDDDXxx..",
		".MmmmmmmmmmmmmmDXxx..",
		".MmmmmmmmmmmmmmDXxx..",
		".RRRRRRRRRRrrrrrDDD..",
		".MmmmmmmmmmmmmmDXxx..",
		".MmWWmWWKKKmWWmDXxx..",
		".MmWWmWWKOKmWWmDXxx..",
		".MmmmmmmKOKmmmmDDDD..",
		".MmmmmmmKKKmmmmDXxx..",
		".MmmmmmmKKKmmmmDXxx..",
		".MmmmmmmKKKmmmmDXxx..",
		"DDDDDDDDDDDDDDDDDDDDD",
	},
	-- a ridged hive spire of chitin with glowing amber cells and spikes
	Insectoids = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p..........",
		"..........p..........",
		".........Ppn.........",
		"........PPppn........",
		"........PPpnn........",
		"........Pappn........",
		".......PPAppnn.......",
		".......PPpppnn.......",
		"......PPPppapnn......",
		"......PPPppAnnn......",
		"....B.PPappppnn.B....",
		".....PPPAppppnnn.....",
		".....PPPppppannn.....",
		"...PPPPPppppApnnnn...",
		"....RRRRRRRrrrrrr....",
		"...PPPPAppapppnnnn...",
		"...PPPPPppAppannnn...",
		"..BPPPaPpKKKpAannnB..",
		".PPPPPAppKKKppAnnnnn.",
		".PPPPPPppKKKpppnnnnn.",
	},
	-- a cluster of glowing cyan and violet shards on a steel platform
	Crystals = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p..........",
		"..........p..........",
		"..........W..........",
		".........WCc.........",
		"........WWCcc........",
		"........WWCcc........",
		"........WWCcc..U.....",
		".....U..WWCcc.UVv....",
		"....UVv.WWCccUUVvv...",
		"...UUVvvWWCccUUVvv...",
		"...UUVvvWWCccWUVvv...",
		"...UUVvWWWCcWCcVvv...",
		"...WUVWCcWCcWCcVvU...",
		"..WCcVWCcWCcWCcVUVv..",
		"..WCcVWCcWCcWCcVUVv..",
		"..WCcVWCcWCcWCcVUVv..",
		"..WCcVWCcWCcWCcVUVv..",
		"..MmmmmmmmmmmmmmmmD..",
		"..RRRRRRRRRrrrrrrrr..",
		"..MmmmmmmmmmmmmmmmD..",
	},
	-- a floating orb of light over a lattice pylon, a ring and arcs
	Energy = {
		"..........pFFFf......",
		"..........pFF........",
		"..........p..........",
		"..........Y..........",
		"....C...YEEEY........",
		".....C.YEEWEEY..C....",
		"....C..YEWWWEY.C.....",
		".......YEEWEEY..C....",
		"........YEEEY........",
		"..........Y..........",
		".....cCCCCCCCCCc.....",
		".........M.D.........",
		"......C.XXXXX........",
		"........M...D.C......",
		"........XXXXX........",
		"........M...D........",
		".......XXXXXXX.......",
		".......M.....D.......",
		"....MmmmmmmmmmmmD....",
		"....RRRRRRRrrrrrr....",
		"....MmmmmmmmmmmmD....",
		"....MmmmmmmmmmmmD....",
	},
}
-- A close-up building's own colours, looked up before the shared ones.
local DETAIL_KIND_COLOURS: { [string]: { [string]: number } } = {
	Empire = { Y = 0xf2c14e }, -- gold
	Nomads = { V = 0xf2e9d3, v = 0xc9b994, w = 0x9c8c6a }, -- felt, its shade, the seams
	Republic = { A = 0x4084e2, a = 0x3370cc, w = 0xd4f0fc }, -- the harbour's water and foam
	Insectoids = { P = 0xa47be0, p = 0x7650b8, n = 0x4a2e80, A = 0xffb02e, a = 0xc97a1e, B = 0xe8edf3 },
	Crystals = { V = 0xb38cff, v = 0x7a55d0, U = 0xe2d4ff, c = 0x3fb3aa, C = 0x7cfbef, W = 0xe6fffc },
	Energy = { E = 0xfff07a, Y = 0xffc83d, W = 0xffffff, C = 0x7cfbef, c = 0x3fb3aa },
}
local DETAIL_CAPITAL_COLOURS: { [string]: number } = {
	M = 0xf2ede4,
	m = 0xd9d1c3,
	D = 0x6e6558,
	W = 0xffe9a0,
	p = 0x3b3128,
	C = 0x7cfbef,
	c = 0x4fc9c0,
	G = 0xa6d65a,
	g = 0x6aa83c,
	e = 0x3e7a35,
	T = 0xece4cf,
	t = 0xc4b79a,
	u = 0x8a7d63,
	H = 0xc4955c,
	h = 0x8e6339,
	X = 0x8a5a32,
	x = 0x5a3a20,
	B = 0xf3ead6,
	K = 0x2b231c,
	Q = 0xb4b8b6,
	q = 0x8a8e8c,
	k = 0x5d6160,
	S = 0xf4f8fb,
	O = 0xff8a26,
}
-- Skyshards' materials (every capital but the dome): steel and plating, crystal leaves, cyan and red light.
local DETAIL_SKY_COLOURS: { [string]: number } = {
	M = 0xe6ebf2,
	m = 0xb7c0cc,
	D = 0x4b5560,
	W = 0x7cfbef,
	p = 0x2e363e,
	G = 0xc8fff8,
	g = 0x64f1e2,
	e = 0x3fb3aa,
	T = 0xd8dee6,
	t = 0xa9b2bd,
	u = 0x5d6878,
	H = 0x9aa2b2,
	h = 0x5f6878,
	X = 0x4b5560,
	x = 0x2e363e,
	B = 0xe8edf3,
	K = 0x10152a,
	Q = 0x8fa3b3,
	q = 0x597d94,
	k = 0x2e363e,
	S = 0x7cfbef,
	O = 0xf55858,
}

-- A new, empty close-up of width × height sub-pixels (factor: sub-pixels per map pixel, 1, 2, 4 or 8).
function PixelArt.newDetail(width: number, height: number, factor: number?): Detail
	local f = factor or DETAIL_FACTOR
	assert(8 % f == 0, "the detail factor divides 8")
	local cols, rows = width // f, height // f
	local ew = (cols + 2 * DETAIL_MARGIN) * f
	local eh = (rows + DETAIL_TOP + DETAIL_MARGIN) * f
	return {
		factor = f,
		width = cols * f,
		height = rows * f,
		cols = cols,
		rows = rows,
		x0 = -1,
		y0 = -1,
		pixels = buffer.create(cols * f * rows * f * 4),
		ew = ew,
		eh = eh,
		ids = buffer.create(ew * eh),
		terrain = buffer.create(ew * eh * 4),
		flags = buffer.create(ew * eh),
		painted = nil,
		dirty = nil,
	}
end

type Ctx = {
	art: Art,
	d: Detail,
	f: number,
	bx: number, -- map pixel at the working area's top-left
	by: number,
	theme: { [number]: { [number]: number } }, -- themed colours by kind (1 land, 2 sea, 3 space)
	palettes: { [Style]: { [number]: { number } } }, -- themed ground palettes
	sprites: { [Style]: { [string]: number } }, -- themed sprite colours
}

local function tc(ctx: Ctx, c: number, kind: number): number
	local cache = ctx.theme[kind]
	local t = cache[c]
	if t == nil then
		t = themed(ctx.art.look, c, kind)
		cache[c] = t
	end
	return t
end

local function groundPalette(ctx: Ctx, s: Style, high: boolean, shade: number): { number }
	local set = ctx.palettes[s]
	if set == nil then
		set = {}
		ctx.palettes[s] = set
	end
	local key = (if high then 3 else 0) + shade
	local pal = set[key]
	if pal == nil then
		pal = {}
		for i, c in paletteOf(s, high, shade) do
			pal[i] = tc(ctx, c, 1)
		end
		set[key] = pal
	end
	return pal
end

local function spriteColours(ctx: Ctx, s: Style): { [string]: number }
	local p = ctx.sprites[s]
	if p then
		return p
	end
	local sp = s.sprite or {}
	local L, M, D = sp.L or s.light, sp.M or s.base, sp.D or s.dark
	local T = sp.T or 0x6b4430
	local raw: { [string]: number } = {
		L = L,
		M = M,
		D = D,
		h = mix(L, 0xffffff, 0.35),
		S = scale(D, 0.72),
		T = T,
		t = scale(T, 0.7),
		r = 0xb9bcb9,
		R = 0x8a8d8a,
		q = 0x5d605d,
		x = 0x5d9a3c,
		X = 0x3f6e2a,
		W = 0xf4f8fb,
		C = sp.C or 0x7cfbef,
		c = sp.M or 0x64f1e2,
		G = sp.G or 0xd8dee6,
		B = sp.B or 0x2e363e,
		P = sp.P or scale(s.dark, 0.8),
	}
	if s.deco == "crystals" then
		raw.D = sp.D or s.dark
	end
	p = {}
	for ch, c in raw do
		p[ch] = tc(ctx, c, 1)
	end
	ctx.sprites[s] = p
	return p
end

local SEA_CAP = (MEDIUM_TO + 2) * SEA_UNIT

-- The depth band (1 shallow, 2 close, 3 deep) of water this far from land, in SEA_UNITs.
local function seaBand(d: number): number
	return if d <= (SHALLOW_TO + 0.5) * SEA_UNIT then 1 elseif d <= (MEDIUM_TO + 0.5) * SEA_UNIT then 2 else 3
end

local SEA_BANDS = { SEA.shallow, SEA.medium, SEA.deep }
local SEA_WAVES = { SEA.shallowWave, SEA.mediumWave, SEA.deepWave }
local SEA_LIPS = { SEA.shallowLip, SEA.mediumLip, SEA.deep }

-- A map pixel of the close-up being painted, and the 3×3 neighbourhoods of the fields its sub-pixels blend between
-- (read once per map pixel, when first needed).
type Cell = {
	cx: number,
	cy: number,
	sea: { number },
	elev: { number },
	ridge: { number },
	shore: { number }, -- land (1) and water (-1), blurred: its zero line is a smooth coast
	hasSea: boolean,
	hasElev: boolean,
	hasRidge: boolean,
	snow: boolean, -- a snow cap in the neighbourhood (only then can the ridge's top band be snow)
}

local function window(art: Art, field: buffer, cx: number, cy: number, cap: number, out: { number })
	local w, h = art.width, art.height
	for j = -1, 1 do
		local row = math.clamp(cy + j, 0, h - 1) * w
		for i = -1, 1 do
			out[(j + 1) * 3 + i + 2] = math.min(buffer.readu8(field, row + math.clamp(cx + i, 0, w - 1)), cap)
		end
	end
end

-- A 3×3 window blended at (fx, fy) from its centre pixel's centre (each from -1 to 1): exactly the field blended
-- between the four nearest pixel centres.
local function sample(win: { number }, fx: number, fy: number): number
	local c, tx = 1, fx
	if fx < 0 then
		c, tx = 0, fx + 1
	end
	local r, ty = 1, fy
	if fy < 0 then
		r, ty = 0, fy + 1
	end
	local i = r * 3 + c + 1
	local a = win[i]
	local top = a + (win[i + 1] - a) * tx
	return top + (win[i + 3] + (win[i + 4] - win[i + 3]) * tx - top) * ty
end

local function seaWindow(ctx: Ctx, cell: Cell): { number }
	if not cell.hasSea then
		window(ctx.art, ctx.art.sea, cell.cx, cell.cy, SEA_CAP, cell.sea)
		cell.hasSea = true
	end
	return cell.sea
end

local function elevWindow(ctx: Ctx, cell: Cell): { number }
	if not cell.hasElev then
		window(ctx.art, ctx.art.elevation, cell.cx, cell.cy, 255, cell.elev)
		cell.hasElev = true
	end
	return cell.elev
end

local function ridgeWindow(ctx: Ctx, cell: Cell): { number }
	if not cell.hasRidge then
		local art = ctx.art
		window(art, art.ridge, cell.cx, cell.cy, 255, cell.ridge)
		local w, h = art.width, art.height
		local snow = false
		for j = -1, 1 do
			local row = math.clamp(cell.cy + j, 0, h - 1) * w
			for i = -1, 1 do
				if buffer.readu8(art.level, row + math.clamp(cell.cx + i, 0, w - 1)) == #ROCK then
					snow = true
				end
			end
		end
		cell.snow = snow
		cell.hasRidge = true
	end
	return cell.ridge
end

-- Land (1) and water (-1) round a map pixel, blurred with a 1-2-1 kernel: blended between pixel centres, its zero
-- line is a smooth coastline that rounds off the grid's steps.
local BLUR = { 1, 2, 1 }
local function shoreWindow(ctx: Ctx, cell: Cell): { number }
	local art = ctx.art
	local w, h = art.width, art.height
	local land = table.create(25, 0)
	for j = -2, 2 do
		local row = math.clamp(cell.cy + j, 0, h - 1) * w
		for i = -2, 2 do
			land[(j + 2) * 5 + i + 3] = if buffer.readu8(art.ids, row + math.clamp(cell.cx + i, 0, w - 1)) ~= 0
				then 1
				else -1
		end
	end
	local out = cell.shore
	for j = 0, 2 do
		for i = 0, 2 do
			local sum = 0
			for dj = 0, 2 do
				for di = 0, 2 do
					sum += BLUR[dj + 1] * BLUR[di + 1] * land[(j + dj) * 5 + i + di + 1]
				end
			end
			out[j * 3 + i + 1] = sum
		end
	end
	return out
end

local function rockLevel(height: number, snow: boolean): number
	for band = #RIDGE_FROM, 2, -1 do
		if height >= RIDGE_FROM[band] * 255 and (band < #RIDGE_FROM or snow) then
			return band
		end
	end
	return 1
end

-- The close-up's rock bands, with faces lit from the north-west lighter and the others darker than WorldBox's flat
-- tiles, so ridges stand out: base, lit, shaded, lip, light speck, dark speck.
local DETAIL_ROCK: { { number } } = {}
for i, band in ROCK do
	DETAIL_ROCK[i] = if i == #ROCK
		then { band.base, 0xffffff, band.b, band.lip, band.a, band.b }
		else { band.base, mix(band.base, 0xffffff, 0.16), scale(band.base, 0.74), band.lip, band.a, band.b }
end

-- Mountain rock at sub-pixel (sx, sy) of a map pixel: bands by ridge height with a dark lip on their south side,
-- faces lit from the north-west, specks on the flat parts.
local function rockColour(ctx: Ctx, cell: Cell, sx: number, sy: number): number
	local f = ctx.f
	local win = ridgeWindow(ctx, cell)
	local snow = cell.snow
	local step = 1 / f
	local fx, fy = (sx + 0.5) * step - 0.5, (sy + 0.5) * step - 0.5
	local here = sample(win, fx, fy)
	local level = rockLevel(here, snow)
	local band = DETAIL_ROCK[level]
	local below = sample(win, fx, fy + step)
	if rockLevel(below, snow) < level or rockLevel(sample(win, fx, fy + 2 * step), snow) < level then
		return tc(ctx, band[4], 1)
	end
	local slope = sample(win, fx + step, fy) - sample(win, fx - step, fy) + below - here
	local c = band[1]
	if slope > DETAIL_ROCK_SLOPE then
		c = band[2]
	elseif slope < -DETAIL_ROCK_SLOPE then
		c = band[3]
	else
		local gx, gy = cell.cx * f + sx, cell.cy * f + sy
		local k = stampOf(STAMPS.rock, gx, gy)[(gy % 8) * 8 + gx % 8 + 1]
		c = if k == 2 or k == 4 then band[5] elseif k == 3 or k == 5 then band[6] else band[1]
	end
	return tc(ctx, c, 1)
end

-- Skyshards' hull plating at sub-pixel (gx, gy): 8-pixel panels in three shades (`shadeN` of the panel) with bevelled
-- edges and rivets, and seams, a few of them lit (`litN`).
local function panelColour(ctx: Ctx, sp: { [string]: number }, plain: number, gx: number, gy: number): number
	local f = ctx.f
	local size = 8 * f
	local px, py = gx % size, gy % size
	local panelX, panelY = gx // size, gy // size
	if px == 0 or py == 0 then
		local lit = noise(panelX, panelY, 9)
		return tc(ctx, if lit < 0.04 then sp.C elseif lit < 0.08 then sp.E else scale(sp.R, 0.9), 1)
	end
	local shade = noise(panelX, panelY, 10)
	local c = if shade < 0.2 then sp.P elseif shade > 0.8 then sp.Q else plain
	if (px == 3 or px == size - 3) and (py == 3 or py == size - 3) then
		c = mix(c, 0xffffff, 0.45) -- rivets
	elseif px == 1 or py == 1 then
		c = mix(c, 0xffffff, 0.18) -- lit edge
	elseif px == size - 1 or py == size - 1 then
		c = scale(c, 0.86) -- shaded edge
	end
	return tc(ctx, c, 1)
end

-- The colour of sub-pixel (sx, sy) of a map pixel when it belongs to `q` (0 = water or space; with corners cut, it
-- can be a neighbour's), its ground lit by `shade`.
local function subColour(ctx: Ctx, cell: Cell, q: number, shade: number, sx: number, sy: number): number
	local art, f = ctx.art, ctx.f
	local gx, gy = cell.cx * f + sx, cell.cy * f + sy
	local step = 1 / f
	local fx, fy = (sx + 0.5) * step - 0.5, (sy + 0.5) * step - 0.5
	if q == 0 then
		if art.theme == "sky" then
			local c, planet = spaceAt((gx + 0.5) / f, (gy + 0.5) / f, art.width, art.height)
			if not planet and (gx % (32 * f) == 0 or gy % (32 * f) == 0) then
				c = mix(c, SPACE.grid, 0.6)
			end
			return tc(ctx, c, 3)
		end
		local win = seaWindow(ctx, cell)
		local band = seaBand(sample(win, fx, fy))
		if band < 3 and seaBand(sample(win, fx, fy + step)) > band then
			return tc(ctx, SEA_LIPS[band], 2)
		end
		if waveAt(gx, gy, DETAIL_WAVES, band == 3) then
			return tc(ctx, SEA_WAVES[band], 2)
		end
		return tc(ctx, SEA_BANDS[band], 2)
	end
	local s = art.biomes[q] or FALLBACK
	if s.deco == "rock" then
		return rockColour(ctx, cell, sx, sy)
	end
	local high = false
	local k = 1
	if s.high then
		local win = elevWindow(ctx, cell)
		high = sample(win, fx, fy) > HIGH_AT
		if high then
			if sample(win, fx, fy + step) <= HIGH_AT then
				k = 5
			elseif sample(win, fx, fy - step) <= HIGH_AT then
				k = 4
			end
		end
	end
	local pal = groundPalette(ctx, s, high, shade)
	if k == 1 then
		local family = s.family
		local stamps = STAMPS[family]
		if stamps then
			k = stampOf(stamps, gx, gy)[(gy % 8) * 8 + gx % 8 + 1]
		elseif family == "rows" then
			-- crop rows every 3 map pixels (like the whole map), with plants standing between them
			local r = gy % (3 * f)
			local sp = s.sprite :: { [string]: number }
			if r < f then
				return tc(ctx, if r == f - 1 then scale(sp.R, 0.82) else sp.R, 1)
			end
			k = if (gx + (gy // (3 * f)) * 2) % 3 == 0
				then (if r == f then 4 elseif r < 2 * f then 2 else 3)
				else (if r == 3 * f - 1 then 3 else 1)
		elseif family == "panels" then
			return panelColour(ctx, s.sprite :: { [string]: number }, paletteOf(s, false, 2)[1], gx, gy)
		end
	end
	return pal[k]
end

-- The working area's ground: every sub-pixel's province (corners cut) and terrain colour.
local function detailGround(ctx: Ctx, yield: Yield?)
	local art, d, f = ctx.art, ctx.d, ctx.f
	local half = f // 2
	local W, H = art.width, art.height
	local ids = art.ids
	local ew = d.ew
	local sub, terr = d.ids, d.terrain
	local bx, by = ctx.bx, ctx.by
	local ecols, erows = ew // f, d.eh // f
	local sky = art.theme == "sky"
	local biomes = art.biomes
	local cell: Cell = {
		cx = 0,
		cy = 0,
		sea = table.create(9, 0),
		elev = table.create(9, 0),
		ridge = table.create(9, 0),
		shore = table.create(9, 0),
		hasSea = false,
		hasElev = false,
		hasRidge = false,
		snow = false,
	}
	local function id(cx: number, cy: number): number
		if cx < 0 or cy < 0 or cx >= W or cy >= H then
			return 0
		end
		return buffer.readu8(ids, cy * W + cx)
	end
	for ey = 0, erows - 1 do
		if yield then
			yield()
		end
		local cy = by + ey
		for ex = 0, ecols - 1 do
			local cx = bx + ex
			cell.cx, cell.cy = cx, cy
			cell.hasSea, cell.hasElev, cell.hasRidge = false, false, false
			local E = id(cx, cy)
			local B, D, R, U = id(cx, cy - 1), id(cx - 1, cy), id(cx + 1, cy), id(cx, cy + 1)
			local tl = if D == B and B ~= E and B ~= R and D ~= U then B else -1
			local tr = if B == R and R ~= E and B ~= D and R ~= U then R else -1
			local bl = if D == U and D ~= E and D ~= B and U ~= R then D else -1
			local br = if R == U and R ~= E and R ~= B and U ~= D then R else -1
			-- where land meets water, the coast follows the shore field instead (corners are only cut between provinces)
			local land = E ~= 0
			local coastal = (B ~= 0) ~= land
				or (D ~= 0) ~= land
				or (R ~= 0) ~= land
				or (U ~= 0) ~= land
				or (id(cx - 1, cy - 1) ~= 0) ~= land
				or (id(cx + 1, cy - 1) ~= 0) ~= land
				or (id(cx - 1, cy + 1) ~= 0) ~= land
				or (id(cx + 1, cy + 1) ~= 0) ~= land
			local shoreWin: { number }? = nil
			if coastal then
				shoreWin = shoreWindow(ctx, cell)
				if not land or tl == 0 then
					tl = -1
				end
				if not land or tr == 0 then
					tr = -1
				end
				if not land or bl == 0 then
					bl = -1
				end
				if not land or br == 0 then
					br = -1
				end
			end
			local base = ey * f * ew + ex * f
			local gx0, gy0 = cx * f, cy * f
			local s = if E ~= 0 then biomes[E] or FALLBACK else FALLBACK
			local shade = if E ~= 0 then shadeAt(art, cx, cy) else 2
			if tl < 0 and tr < 0 and bl < 0 and br < 0 and not coastal then
				-- fast paths: a whole map pixel of plain ground, rock, plating, open water or space
				if E ~= 0 then
					local stamps = STAMPS[s.family]
					if s.deco == "rock" then
						for sy = 0, f - 1 do
							local o = base + sy * ew
							for sx = 0, f - 1 do
								buffer.writeu8(sub, o + sx, E)
								buffer.writeu32(terr, (o + sx) * 4, rockColour(ctx, cell, sx, sy))
							end
						end
						continue
					elseif s.family == "panels" then
						local sp = s.sprite :: { [string]: number }
						local plain = paletteOf(s, false, 2)[1]
						for sy = 0, f - 1 do
							local o = base + sy * ew
							for sx = 0, f - 1 do
								buffer.writeu8(sub, o + sx, E)
								buffer.writeu32(terr, (o + sx) * 4, panelColour(ctx, sp, plain, gx0 + sx, gy0 + sy))
							end
						end
						continue
					elseif stamps then
						local uniform = true
						local high = false
						if s.high then
							local win = elevWindow(ctx, cell)
							high = win[5] > HIGH_AT
							for i = 1, 9 do
								if (win[i] > HIGH_AT) ~= high then
									uniform = false
								end
							end
						end
						if uniform then
							local pal = groundPalette(ctx, s, high, shade)
							local stamp = stampOf(stamps, gx0, gy0)
							for sy = 0, f - 1 do
								local o = base + sy * ew
								local row = ((gy0 + sy) % 8) * 8 + 1
								for sx = 0, f - 1 do
									buffer.writeu8(sub, o + sx, E)
									buffer.writeu32(terr, (o + sx) * 4, pal[stamp[row + (gx0 + sx) % 8]])
								end
							end
							continue
						end
					end
				elseif sky then
					if
						planetAt(cx + 0.5, cy + 0.5, W, H)
						or planetAt(cx, cy, W, H)
						or planetAt(cx + 1, cy + 1, W, H)
					then
						-- a planet's edge runs through this map pixel: every sub-pixel on its own
						for sy = 0, f - 1 do
							local o = base + sy * ew
							for sx = 0, f - 1 do
								buffer.writeu8(sub, o + sx, 0)
								buffer.writeu32(terr, (o + sx) * 4, subColour(ctx, cell, 0, shade, sx, sy))
							end
						end
						continue
					end
					-- the nebula changes slowly: one glow for the whole map pixel, the sky's gradient row by row
					local t, glow = nebulaAt((cx + 0.5) / W, (cy + 0.5) / H)
					local spaceH = H * f
					for sy = 0, f - 1 do
						local o = base + sy * ew
						local gy = gy0 + sy
						local c = mix(SPACE.top, SPACE.bottom, math.clamp(gy / spaceH, 0, 1))
						if t > 0 then
							c = mix(c, glow, t)
						end
						local onGrid = gy % (32 * f) == 0
						local flat = tc(ctx, if onGrid then mix(c, SPACE.grid, 0.6) else c, 3)
						local line = tc(ctx, mix(c, SPACE.grid, 0.6), 3)
						for sx = 0, f - 1 do
							buffer.writeu8(sub, o + sx, 0)
							buffer.writeu32(terr, (o + sx) * 4, if (gx0 + sx) % (32 * f) == 0 then line else flat)
						end
					end
					continue
				else
					local win = seaWindow(ctx, cell)
					local lo, hi = SEA_CAP, 0
					for i = 1, 9 do
						lo, hi = math.min(lo, win[i]), math.max(hi, win[i])
					end
					local band = seaBand(lo)
					if band == seaBand(hi) and lo > 0 then
						local flat, wave = tc(ctx, SEA_BANDS[band], 2), tc(ctx, SEA_WAVES[band], 2)
						for sy = 0, f - 1 do
							local o = base + sy * ew
							for sx = 0, f - 1 do
								buffer.writeu8(sub, o + sx, 0)
								buffer.writeu32(
									terr,
									(o + sx) * 4,
									if waveAt(gx0 + sx, gy0 + sy, DETAIL_WAVES, band == 3) then wave else flat
								)
							end
						end
						continue
					end
				end
			end
			for sy = 0, f - 1 do
				for sx = 0, f - 1 do
					local q, scx, scy = E, cx, cy
					if sy < half then
						if sx < half then
							if tl >= 0 and sx + sy < half then
								q, scy = tl, cy - 1
							end
						elseif tr >= 0 and (f - 1 - sx) + sy < half then
							q, scx = tr, cx + 1
						end
					else
						if sx < half then
							if bl >= 0 and sx + (f - 1 - sy) < half then
								q, scx = bl, cx - 1
							end
						elseif br >= 0 and (f - 1 - sx) + (f - 1 - sy) < half then
							q, scy = br, cy + 1
						end
					end
					if shoreWin then
						-- (a map pixel the blur would wipe out keeps its middle, so 1-pixel islands and straits stay)
						local fx, fy = (sx + 0.5) / f - 0.5, (sy + 0.5) / f - 0.5
						local middle = math.abs(fx) <= 0.25 and math.abs(fy) <= 0.25 and (shoreWin[5] > 0) ~= land
						if if middle then not land else sample(shoreWin, fx, fy) <= 0 then
							q = 0
						elseif q == 0 then
							-- water turned land: the land beside it, straight across first, then diagonally
							local hx = if sx < half then cx - 1 else cx + 1
							local vy = if sy < half then cy - 1 else cy + 1
							local first, second = id(hx, cy), id(cx, vy)
							if math.abs(fx) < math.abs(fy) then
								first, second = second, first
							end
							if first ~= 0 then
								q = first
							elseif second ~= 0 then
								q = second
							else
								q = id(hx, vy)
							end
							scx, scy = cx, cy
							if q ~= 0 then
								if q == id(hx, cy) then
									scx = hx
								elseif q == id(cx, vy) then
									scy = vy
								else
									scx, scy = hx, vy
								end
							end
						end
					end
					local o = base + sy * ew + sx
					buffer.writeu8(sub, o, q)
					local lit = if q == E then shade elseif q ~= 0 then shadeAt(art, scx, scy) else 2
					buffer.writeu32(terr, o * 4, subColour(ctx, cell, q, lit, sx, sy))
				end
			end
		end
	end
end

-- Shores: beaches with wet sand and a lip on their south side, surf and foam on the water, a shadow under south
-- shores; on Skyshards, glowing rims round the platforms and hulls hanging below them.
local function detailShores(ctx: Ctx, yield: Yield?)
	local art, d, f = ctx.art, ctx.d, ctx.f
	local ew, eh = d.ew, d.eh
	local sub, terr, flags = d.ids, d.terrain, d.flags
	local sky = art.theme == "sky"
	local ecols, erows = ew // f, eh // f
	local reach = f -- sub-pixels checked each way
	local beach, wet, lip = tc(ctx, SEA.beach, 1), tc(ctx, SEA.wetSand, 1), tc(ctx, SEA.beachLip, 1)
	local surf, foam, shadow = tc(ctx, SEA.surf, 2), tc(ctx, SEA.foam, 2), tc(ctx, SEA.shadow, 2)
	local rim = tc(ctx, SPACE.rim, 1)
	local biomes = art.biomes
	local function land(o: number): boolean
		return buffer.readu8(sub, o) ~= 0
	end
	for ey = 1, erows - 2 do
		if yield and ey % 8 == 0 then
			yield()
		end
		for ex = 1, ecols - 2 do
			local base = ey * f * ew + ex * f
			-- only map pixels where land meets water somewhere near
			local first = land(base)
			local mixed = false
			for j = -1, 1 do
				for i = -1, 1 do
					local o = base + j * f * ew + i * f
					if land(o) ~= first or land(o + f - 1) ~= first or land(o + (f - 1) * ew) ~= first then
						mixed = true
					end
				end
			end
			if not mixed then
				continue
			end
			for sy = 0, f - 1 do
				for sx = 0, f - 1 do
					local o = base + sy * ew + sx
					local q = buffer.readu8(sub, o)
					-- the nearest sub-pixel of the other kind straight up, down, left or right
					local near, below, above = reach + 1, false, false
					for k = 1, reach do
						local hit = false
						if land(o - k) ~= (q ~= 0) or land(o + k) ~= (q ~= 0) then
							hit = true
						end
						if land(o + k * ew) ~= (q ~= 0) then
							hit, below = true, true
						end
						if land(o - k * ew) ~= (q ~= 0) then
							hit, above = true, true
						end
						if hit then
							near = k
							break
						end
					end
					if near > reach then
						continue
					end
					if q ~= 0 then
						if sky then
							if near == 1 then
								buffer.writeu32(terr, o * 4, rim)
								buffer.writeu8(flags, o, SHORE)
							elseif near == 2 then
								buffer.writeu32(terr, o * 4, mix(rim, buffer.readu32(terr, o * 4), 0.55))
								buffer.writeu8(flags, o, SHORE)
							end
						else
							local s = biomes[q] or FALLBACK
							if s.deco ~= "rock" and s ~= BIOMES.ice and s ~= BIOMES.frostfields and near <= f - 1 then
								buffer.writeu32(
									terr,
									o * 4,
									if below and near <= 2 then lip elseif near == 1 then wet else beach
								)
								buffer.writeu8(flags, o, SHORE)
							end
						end
					elseif not sky then
						if above then
							buffer.writeu32(terr, o * 4, shadow)
						elseif near == 1 then
							buffer.writeu32(terr, o * 4, surf)
						elseif near == 2 then
							buffer.writeu32(terr, o * 4, foam)
						end
					end
				end
			end
		end
	end
	if not sky then
		return
	end
	-- hulls: each column of space below a platform, top down
	local hullDepth = HULL * f
	local bx, by = ctx.bx * f, ctx.by * f
	for x = 0, ew - 1 do
		local run = hullDepth + 1
		for y = 0, eh - 1 do
			local o = y * ew + x
			if buffer.readu8(sub, o) ~= 0 then
				run = 0
			else
				run += 1
				if run <= hullDepth then
					local gx, gy = bx + x, by + y
					local c: number
					if run > hullDepth - 2 then
						c = SPACE.rim
					else
						c = scale(SPACE.hull, 1 - (run / f) * 0.09)
						if gy % (2 * f) == 0 or gx % (3 * f) == 0 then
							c = scale(c, 0.78) -- plate seams
						elseif gx % (3 * f) == 1 then
							c = mix(c, 0xffffff, 0.12)
						end
						if
							hash32(gx // (3 * f), gy // (2 * f), 3) % 23 == 0
							and gx % (3 * f) == 6
							and gy % (2 * f) == 4
						then
							c = SPACE.rim -- a lit porthole
						end
					end
					buffer.writeu32(terr, o * 4, tc(ctx, c, 3))
					buffer.writeu8(flags, o, SHORE)
				end
			end
		end
	end
end

-- Stars, and the close-up decorations: trees, bushes, rocks, flowers... (one at most per map pixel, chosen by a
-- hash of the map pixel so every close-up agrees), and village lights or snow sparkles on themed maps.
local function detailSprites(ctx: Ctx, yield: Yield?)
	local art, d, f = ctx.art, ctx.d, ctx.f
	local ew, eh = d.ew, d.eh
	local sub, terr, flags = d.ids, d.terrain, d.flags
	local W, H = art.width, art.height
	local ids = art.ids
	local ecols, erows = ew // f, eh // f
	local look = art.look
	local sky = art.theme == "sky"
	local shadows: { [number]: number } = {}
	local star = tc(ctx, SPACE.star, 3)
	local lamp, glow = NIGHT_LIGHT, mix(NIGHT_LIGHT, 0x3a3550, 0.45)
	local function id(cx: number, cy: number): number
		if cx < 0 or cy < 0 or cx >= W or cy >= H then
			return 0
		end
		return buffer.readu8(ids, cy * W + cx)
	end
	for ey = 0, erows - 1 do
		if yield and ey % 8 == 0 then
			yield()
		end
		local cy = ctx.by + ey
		for ex = 0, ecols - 1 do
			local cx = ctx.bx + ex
			local pid = id(cx, cy)
			local h = hash32(cx, cy, 401)
			local ax = ex * f + bit32.band(bit32.rshift(h, 16), f - 1)
			local ay = ey * f + bit32.band(bit32.rshift(h, 20), f - 1)
			if pid == 0 then
				if sky and bit32.band(h, 0xff) < 2 and not planetAt(cx + 0.5, cy + 0.5, W, H) then
					local o = ay * ew + ax
					if buffer.readu8(sub, o) == 0 and buffer.readu8(flags, o) == 0 then
						buffer.writeu32(terr, o * 4, star)
					end
				end
				continue
			end
			if look == "night" and noise(cx, cy, 91) > NIGHT_LIGHTS then
				for _, p in DETAIL_PIXELS.light do
					local x, y = ax + p.dx, ay + p.dy
					if x >= 0 and y >= 0 and x < ew and y < eh then
						buffer.writeu32(terr, (y * ew + x) * 4, if p.ch == "Y" then lamp else glow)
					end
				end
				continue
			elseif look == "winter" and noise(cx, cy, 93) > WINTER_FLAKES then
				buffer.writeu32(terr, (ay * ew + ax) * 4, 0xffffff)
				continue
			end
			local s = art.biomes[pid] or FALLBACK
			local choices = DETAIL_DECOS[s]
			if choices == nil then
				continue
			end
			-- not right by the shore
			if id(cx - 1, cy) == 0 or id(cx + 1, cy) == 0 or id(cx, cy - 1) == 0 or id(cx, cy + 1) == 0 then
				continue
			end
			local r = bit32.band(h, 0xffff) / 65536
			local pixels: { Pixel }? = nil
			for _, choice in choices do
				if r < choice.upTo then
					pixels = choice.pixels
					break
				end
			end
			if pixels == nil then
				continue
			end
			local colours = spriteColours(ctx, s)
			local flower = tc(ctx, FLOWERS[1 + bit32.rshift(h, 24) % #FLOWERS], 1)
			for _, p in pixels do
				local x, y = ax + p.dx, ay + p.dy
				if x < 0 or y < 0 or x >= ew or y >= eh then
					continue
				end
				local o = y * ew + x
				if buffer.readu8(sub, o) ~= pid or buffer.readu8(flags, o) ~= 0 then
					continue
				end
				if p.ch == "k" then
					local c = buffer.readu32(terr, o * 4)
					local t = shadows[c]
					if t == nil then
						t = scale(c, 0.76)
						shadows[c] = t
					end
					buffer.writeu32(terr, o * 4, t)
				else
					buffer.writeu32(terr, o * 4, if p.ch == "F" then flower else colours[p.ch])
				end
			end
		end
	end
end

type Washes = { inner: { [number]: number }, wash: { [number]: number }, rim: { [number]: number } }

-- The kingdom layer over map pixels cx0..cx1, cy0..cy1 (inside the close-up), into its RGBA pixels: a lighter
-- wash, a stronger rim, the border line, lines between provinces and the selection. `only`: just this province's
-- sub-pixels (a repaint).
local function detailPolitics(ctx: Ctx, cx0: number, cy0: number, cx1: number, cy1: number, only: number?)
	local art, d, f = ctx.art, ctx.d, ctx.f
	local ew = d.ew
	local sub, terr, out = d.ids, d.terrain, d.pixels
	local W = art.width
	local near = art.near
	local owner = art.owner
	local selected = art.selected
	local reach = math.max(DETAIL_BORDER + DETAIL_RIM, DETAIL_SELECT)
	local washes: { [number]: Washes } = {}
	local function washesOf(o: number): Washes
		local t = washes[o]
		if t == nil then
			t = { inner = {}, wash = {}, rim = {} }
			washes[o] = t
		end
		return t
	end
	local function tintOf(o: number, c: number): number
		local nation = art.color[o] or 0x808080
		local look = art.styles[o]
		return if look and look.shades ~= "default"
			then PixelArt.shadeColor(look.shades, nation, brightness(c))
			else nation
	end
	local function ownerOf(q: number): number
		return if q == 0 then 0 else owner[q] or 0
	end
	local function innerCell(cx: number, cy: number): boolean
		if cx < 1 or cy < 1 or cx >= W - 1 or cy >= art.height - 1 then
			return false
		end
		local i = cy * W + cx
		return buffer.readu8(near, i) == 0
			and buffer.readu8(near, i - 1) == 0
			and buffer.readu8(near, i + 1) == 0
			and buffer.readu8(near, i - W) == 0
			and buffer.readu8(near, i + W) == 0
	end
	local dw = d.width
	for cy = cy0, cy1 do
		local ey = cy - ctx.by
		local py = cy - d.y0
		for cx = cx0, cx1 do
			local ex = cx - ctx.bx
			local px = cx - d.x0
			local base = ey * f * ew + ex * f
			local pbase = py * f * dw + px * f
			local E = buffer.readu8(sub, base)
			if E ~= 0 and innerCell(cx, cy) then
				if only and E ~= only then
					continue
				end
				-- inside a province: only the wash (and the selection's tint)
				local o = ownerOf(E)
				local cache = if E == selected then nil else washesOf(o).inner
				for sy = 0, f - 1 do
					local o1, p1 = base + sy * ew, pbase + sy * dw
					for sx = 0, f - 1 do
						local c = buffer.readu32(terr, (o1 + sx) * 4)
						local v = if cache then cache[c] else nil
						if v == nil then
							local t = if o ~= 0 then mix(c, tintOf(o, c), DETAIL_ALPHA) else c
							if E == selected then
								t = mix(t, 0xffffff, 0.3)
							end
							v = rgba(t)
							if cache then
								cache[c] = v
							end
						end
						buffer.writeu32(out, (p1 + sx) * 4, v)
					end
				end
				continue
			end
			for sy = 0, f - 1 do
				for sx = 0, f - 1 do
					local o1 = base + sy * ew + sx
					local q = buffer.readu8(sub, o1)
					if only and q ~= only then
						continue
					end
					local c = buffer.readu32(terr, o1 * 4)
					local v = c
					if q ~= 0 then
						local o = ownerOf(q)
						local dOwn, dId = 99, 99
						if o ~= 0 or q == selected then
							for k = 1, reach do
								local a = buffer.readu8(sub, o1 - k)
								local b = buffer.readu8(sub, o1 + k)
								local c1 = buffer.readu8(sub, o1 - k * ew)
								local c2 = buffer.readu8(sub, o1 + k * ew)
								if a ~= q or b ~= q or c1 ~= q or c2 ~= q then
									dId = math.min(dId, k)
									if
										o ~= 0
										and (
											(a ~= q and ownerOf(a) ~= o)
											or (b ~= q and ownerOf(b) ~= o)
											or (c1 ~= q and ownerOf(c1) ~= o)
											or (c2 ~= q and ownerOf(c2) ~= o)
										)
									then
										dOwn = k
										break
									end
								end
							end
						end
						if o ~= 0 then
							if dOwn <= DETAIL_BORDER then
								local look = art.styles[o]
								local border = art.border[o] or scale(art.color[o] or 0x808080, 0.75)
								local b = if look and look.border ~= "solid"
									then PixelArt.borderShade(
										look.border,
										border,
										(cx * f + sx) // 2,
										(cy * f + sy) // 2
									)
									else border
								v = mix(c, b, BORDER_ALPHA)
							elseif dOwn <= DETAIL_BORDER + DETAIL_RIM then
								local cache = washesOf(o).rim
								v = cache[c]
								if v == nil then
									v = mix(c, tintOf(o, c), DETAIL_RIM_ALPHA)
									cache[c] = v
								end
							else
								local cache = washesOf(o).wash
								v = cache[c]
								if v == nil then
									v = mix(c, tintOf(o, c), DETAIL_ALPHA)
									cache[c] = v
								end
							end
						end
						if dOwn > DETAIL_BORDER then
							local right, down = buffer.readu8(sub, o1 + 1), buffer.readu8(sub, o1 + ew)
							if (right ~= q and right ~= 0) or (down ~= q and down ~= 0) then
								v = scale(v, DETAIL_LINE)
							end
						end
						if q == selected then
							v = if dId <= DETAIL_SELECT then 0xffffff else mix(v, 0xffffff, 0.3)
						end
					end
					buffer.writeu32(out, (pbase + sy * dw + sx) * 4, rgba(v))
				end
			end
		end
	end
end

-- The owner's colours on a close-up capital: its flag (F f) and its roofs and banners (R r).
local function ownerColours(flag: number): { [string]: number }
	return { F = flag, f = scale(flag, 0.75), R = flag, r = scale(flag, 0.72) }
end

-- The colour of one sub-pixel of a close-up capital: the owner's, the building's own, then Skyshards' materials or
-- the classic ones.
local function detailCapitalColour(kind: string, sky: boolean, ch: string, owner: { [string]: number }): number
	local own = DETAIL_KIND_COLOURS[kind]
	return owner[ch] or (own and own[ch]) or (if sky then DETAIL_SKY_COLOURS[ch] else nil) or DETAIL_CAPITAL_COLOURS[ch]
end

-- Capitals (each race's own, DETAIL_CAPITALS) in the close-up, on top of everything. Returns the sub-pixel rectangles
-- drawn.
local function detailCapitals(ctx: Ctx, within: { number }?)
	local art, d, f = ctx.art, ctx.d, ctx.f
	local h, w = CAPITAL_H, CAPITAL_W
	for pid, capital in art.capitals do
		local x0 = (capital.x - d.x0) * f + f // 2 - w // 2
		local y0 = (capital.y + 3 - d.y0) * f - h
		local x1, y1 = x0 + w - 1, y0 + h - 1
		if x1 < 0 or y1 < 0 or x0 >= d.width or y0 >= d.height then
			continue
		end
		if within and (x1 < within[1] or y1 < within[2] or x0 > within[3] or y0 > within[4]) then
			continue
		end
		local sprite = DETAIL_CAPITALS[capital.kind]
		local sky = sciFi(art.theme, capital.kind)
		local o = art.owner[pid] or 0
		local flag = if o ~= 0 then art.color[o] or 0x808080 else 0xb0b0b0
		local owner = ownerColours(flag)
		for j = 1, h do
			local row = sprite[j]
			for i = 1, w do
				local ch = string.sub(row, i, i)
				local x, y = x0 + i - 1, y0 + j - 1
				if ch ~= "." and x >= 0 and y >= 0 and x < d.width and y < d.height then
					local c = detailCapitalColour(capital.kind, sky, ch, owner)
					buffer.writeu32(d.pixels, (y * d.width + x) * 4, rgba(c))
				end
			end
		end
		local dirty = d.dirty
		if dirty == nil then
			d.dirty = { math.max(x0, 0), math.max(y0, 0), math.min(x1, d.width - 1), math.min(y1, d.height - 1) }
		else
			dirty[1] = math.max(math.min(dirty[1], x0), 0)
			dirty[2] = math.max(math.min(dirty[2], y0), 0)
			dirty[3] = math.min(math.max(dirty[3], x1), d.width - 1)
			dirty[4] = math.min(math.max(dirty[4], y1), d.height - 1)
		end
	end
end

local function contextOf(art: Art, d: Detail): Ctx
	return {
		art = art,
		d = d,
		f = d.factor,
		bx = d.x0 - DETAIL_MARGIN,
		by = d.y0 - DETAIL_TOP,
		theme = { {}, {}, {} },
		palettes = {},
		sprites = {},
	}
end

-- The map pixel a close-up of this size would start at to be centred on map point (x, y), kept inside the map.
function PixelArt.detailOrigin(art: Art, d: Detail, x: number, y: number): (number, number)
	local x0 = math.clamp(math.floor(x - d.cols / 2), 0, math.max(art.width - d.cols, 0))
	local y0 = math.clamp(math.floor(y - d.rows / 2), 0, math.max(art.height - d.rows, 0))
	return x0, y0
end

-- Paint the close-up of map pixels x0.. (d.cols wide), y0.. (d.rows tall) from a painting, kingdoms included.
-- Pass `yield` to have it called every so often (a client spreads the work over frames).
function PixelArt.paintDetail(art: Art, d: Detail, x0: number, y0: number, yield: Yield?)
	d.x0 = math.clamp(math.floor(x0), 0, math.max(art.width - d.cols, 0))
	d.y0 = math.clamp(math.floor(y0), 0, math.max(art.height - d.rows, 0))
	d.painted = art
	table.clear(art.changed) -- what changes from here on is caught up by syncDetail
	buffer.fill(d.flags, 0, 0)
	local ctx = contextOf(art, d)
	detailGround(ctx, yield)
	detailShores(ctx, yield)
	detailSprites(ctx, yield)
	local cols, rows = math.min(d.cols, art.width - d.x0), math.min(d.rows, art.height - d.y0)
	for cy = d.y0, d.y0 + rows - 1, 8 do
		if yield then
			yield()
		end
		detailPolitics(ctx, d.x0, cy, d.x0 + cols - 1, math.min(cy + 7, d.y0 + rows - 1), nil)
	end
	d.dirty = nil
	detailCapitals(ctx, nil)
	d.dirty = { 0, 0, d.width - 1, d.height - 1 }
end

-- Catch the close-up up with the painting: repaint the kingdom layer of the provinces whose owner, colours, style
-- or selection changed since (only those, and their capitals). Returns true if anything in the close-up changed.
function PixelArt.syncDetail(art: Art, d: Detail): boolean
	if d.painted ~= art or next(art.changed) == nil then
		return false
	end
	local ctx = contextOf(art, d)
	local f = d.factor
	local any = false
	local cx1, cy1 = math.min(d.x0 + d.cols, art.width) - 1, math.min(d.y0 + d.rows, art.height) - 1
	for pid in art.changed do
		local box = art.boxes[pid]
		if box == nil then
			continue
		end
		local x0, y0 = math.max(box[1] - 1, d.x0), math.max(box[2] - 1, d.y0)
		local x1, y1 = math.min(box[3] + 1, cx1), math.min(box[4] + 1, cy1)
		if x1 < x0 or y1 < y0 then
			continue
		end
		detailPolitics(ctx, x0, y0, x1, y1, pid)
		local rect = { (x0 - d.x0) * f, (y0 - d.y0) * f, (x1 - d.x0 + 1) * f - 1, (y1 - d.y0 + 1) * f - 1 }
		local dirty = d.dirty
		if dirty == nil then
			d.dirty = { rect[1], rect[2], rect[3], rect[4] }
		else
			dirty[1] = math.min(dirty[1], rect[1])
			dirty[2] = math.min(dirty[2], rect[2])
			dirty[3] = math.max(dirty[3], rect[3])
			dirty[4] = math.max(dirty[4], rect[4])
		end
		detailCapitals(ctx, rect)
		any = true
	end
	table.clear(art.changed)
	return any
end

-- The sub-pixel rectangle (x0, y0, x1, y1, inclusive) of the close-up changed since the last call, or nil.
function PixelArt.takeDetailDirty(d: Detail): { number }?
	local r = d.dirty
	d.dirty = nil
	return r
end

-- The colour of one close-up pixel, and the terrain under it before the kingdom wash, 0xRRGGBB; and its province
-- (for tests and debugging).
function PixelArt.detailPixel(d: Detail, x: number, y: number): number
	return unrgba(buffer.readu32(d.pixels, (y * d.width + x) * 4))
end

function PixelArt.detailTerrain(d: Detail, x: number, y: number): number
	local o = (y + DETAIL_TOP * d.factor) * d.ew + x + DETAIL_MARGIN * d.factor
	return buffer.readu32(d.terrain, o * 4)
end

function PixelArt.detailProvince(d: Detail, x: number, y: number): number
	local o = (y + DETAIL_TOP * d.factor) * d.ew + x + DETAIL_MARGIN * d.factor
	return buffer.readu8(d.ids, o)
end

------------------------------------------------------------------------------------------------- public API

type MapLike = {
	theme: string,
	provinces: { { id: number, biome: string, isCapital: boolean, center: { x: number, y: number } } },
	-- { capital: number, race: string } each: whose capital is whose, since each race builds its own (MapDef.nations)
	nations: { any }?,
}

-- Paint the terrain and a neutral political layer. Owners come later through setOwners. Pass `yield` to have it
-- called every few dozen rows (a client spreads the work over frames this way); tests leave it out. `look`: a map
-- theme from PixelArt.THEMES (nil or "" = the classic look).
function PixelArt.new(map: MapLike, grid: Grid, yield: Yield?, look: string?): Art
	local w, h = grid.width, grid.height
	local art: Art = {
		width = w,
		height = h,
		ids = grid.ids,
		theme = map.theme,
		look = look or "",
		terrain = buffer.create(w * h * 4),
		pixels = buffer.create(w * h * 4),
		boxes = {},
		touching = {},
		owner = {},
		color = {},
		border = {},
		capitals = {},
		styles = {},
		selected = 0,
		near = buffer.create(w * h),
		dirty = nil,
		biomes = {},
		elevation = buffer.create(w * h),
		ridge = buffer.create(w * h),
		level = buffer.create(w * h),
		sea = buffer.create(w * h),
		changed = {},
	}
	local biomeOf = art.biomes
	local raceAt: { [number]: string } = {} -- capital province -> the race of the nation it is the capital of
	for _, n in map.nations or {} do
		if n.race then
			raceAt[n.capital] = n.race
		end
	end
	for _, p in map.provinces do
		biomeOf[p.id] = BIOMES[p.biome] or FALLBACK
		if p.isCapital then
			art.capitals[p.id] = {
				x = math.floor(p.center.x / grid.scale),
				y = math.floor(p.center.y / grid.scale),
				kind = capitalKind(map.theme, raceAt[p.id]),
			}
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
	applyTheme(art, art.look, yield)
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

-- Apply nations' border styles and shade sets (nation slot -> style; missing = default). Repaints only the
-- provinces of nations whose style changed (and their neighbours). Returns true if anything changed.
function PixelArt.setStyles(art: Art, styles: { [number]: NationStyle }): boolean
	local changed: { [number]: boolean } = {}
	for slot, s in styles do
		local old = art.styles[slot]
		if old == nil or old.border ~= s.border or old.shades ~= s.shades then
			art.styles[slot] = { border = s.border, shades = s.shades }
			changed[slot] = true
		end
	end
	for slot in art.styles do
		if styles[slot] == nil then
			art.styles[slot] = nil
			changed[slot] = true
		end
	end
	if next(changed) == nil then
		return false
	end
	local repaint: { [number]: boolean } = {}
	for pid, o in art.owner do
		if changed[o] then
			repaint[pid] = true
			for _, other in art.touching[pid] or {} do
				repaint[other] = true
			end
		end
	end
	for pid in repaint do
		paintProvince(art, pid)
	end
	if next(repaint) then
		drawCapitals(art)
	end
	return true
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
	return unrgba(buffer.readu32(art.pixels, (y * art.width + x) * 4))
end

-- A race's capital as a map of this texture set (MapDef.theme) draws it, flying `flag` (0xRRGGBB): the whole map's
-- 5 × 6 sprite and the close-up's 21 × 22 building, as RGBA buffers (transparent round the building), each with its
-- width and height. For art previews and tests (tools/harness/race_sheet.luau, tests/pixelart.spec.luau).
function PixelArt.capitalArt(
	theme: string,
	race: string?,
	flag: number
): (buffer, number, number, buffer, number, number)
	local kind = capitalKind(theme, race)
	local sky = sciFi(theme, kind)
	local whole = CAPITALS[kind]
	local ww, wh = #whole[1], #whole
	local wholePixels = buffer.create(ww * wh * 4)
	for j = 1, wh do
		for i = 1, ww do
			local ch = string.sub(whole[j], i, i)
			if ch ~= "." then
				buffer.writeu32(wholePixels, ((j - 1) * ww + i - 1) * 4, rgba(capitalColour(kind, sky, ch, flag)))
			end
		end
	end
	local close = DETAIL_CAPITALS[kind]
	local closePixels = buffer.create(CAPITAL_W * CAPITAL_H * 4)
	local owner = ownerColours(flag)
	for j = 1, CAPITAL_H do
		for i = 1, CAPITAL_W do
			local ch = string.sub(close[j], i, i)
			if ch ~= "." then
				local c = detailCapitalColour(kind, sky, ch, owner)
				buffer.writeu32(closePixels, ((j - 1) * CAPITAL_W + i - 1) * 4, rgba(c))
			end
		end
	end
	return wholePixels, ww, wh, closePixels, CAPITAL_W, CAPITAL_H
end

-- The kind of capital a race builds on a map of this texture set (its own; the Marines' dome; the castle, or the
-- dome on Skyshards, without a race), for tests.
function PixelArt.capitalKind(theme: string, race: string?): string
	return capitalKind(theme, race)
end

return PixelArt
