--!strict
-- Pixel art for cosmetics (docs/MONETIZATION.md 3.2): 16×12 flags, 12×12 army tokens, border and shade swatches
-- for the shop. Painted from little character grids in the nation's own colours, so every flag and token keeps
-- the map's WorldBox look and its owner's colour. Pure Luau on buffers (no Roblox APIs): tested under Lune.
-- Pixels are RGBA bytes, ready for EditableImage:WritePixelsBuffer.
--
-- Colour codes: N the nation's colour, D its border colour, L the nation colour lightened, K outline, W white,
-- G gold, "." transparent.

local PixelArt = require("./PixelArt")

local CosmeticArt = {}

CosmeticArt.FLAG_SIZE = { w = 16, h = 12 }
CosmeticArt.TOKEN_SIZE = { w = 12, h = 12 }
CosmeticArt.SWATCH_SIZE = { w = 24, h = 16 }

local K, W, G = 0x1d1d24, 0xf4f1e8, 0xf2c14e

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
end

local function mixWhite(c: number, t: number): number
	local r, g, b = rgb(c)
	r, g, b = r + (255 - r) * t, g + (255 - g) * t, b + (255 - b) * t
	return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

local function rgba(c: number, alpha: number): number
	local r, g, b = rgb(c)
	return alpha * 16777216 + b * 65536 + g * 256 + r
end

CosmeticArt.FLAGS = {
	banner = {
		"DDDDDDDDDDDDDDDD",
		"DNNNNNNNNNNNNNND",
		"DNNNNNNNNNNNNNND",
		"DNNNNNNNNNNNNNND",
		"DNNNNNNLLNNNNNND",
		"DNNNNNLWWLNNNNND",
		"DNNNNNLWWLNNNNND",
		"DNNNNNNLLNNNNNND",
		"DNNNNNNNNNNNNNND",
		"DNNNNNNNNNNNNNND",
		"DNNNNNNNNNNNNNND",
		"DDDDDDDDDDDDDDDD",
	},
	tricolour = table.create(12, "NNNNNWWWWWWDDDDD"),
	cross = {
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"WWWWWWWWWWWWWWWW",
		"WWWWWWWWWWWWWWWW",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
		"NNNNWWNNNNNNNNNN",
	},
	sun = {
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNGGNNNNNNN",
		"NNNGNNNGGNNNGNNN",
		"NNNNGNGGGGNGNNNN",
		"NNNNNGGGGGGNNNNN",
		"NGGNGGGGGGGGNGGN",
		"NGGNGGGGGGGGNGGN",
		"NNNNNGGGGGGNNNNN",
		"NNNNGNGGGGNGNNNN",
		"NNNGNNNGGNNNGNNN",
		"NNNNNNNGGNNNNNNN",
		"DDDDDDDDDDDDDDDD",
	},
	crown = {
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNNNNNNNNNN",
		"NNNGNNNGGNNNGNNN",
		"NNNGGNGGGGNGGNNN",
		"NNNGGGGGGGGGGNNN",
		"NNNGGWGGGGWGGNNN",
		"NNNGGGGGGGGGGNNN",
		"NNNGGGGGGGGGGNNN",
		"NNNDDDDDDDDDDNNN",
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNNNNNNNNNN",
	},
	vanguard = {
		"WNNNNNNNNNNNNNNN",
		"WWNNNNNNNNNNNNNN",
		"DWWNNNNNNNNNNNNN",
		"DDWWNNNNNNNNNNNN",
		"DDDWWNNNNNNNNNNN",
		"DDDDWWNNNNNNNNNN",
		"DDDDWWNNNNNNNNNN",
		"DDDWWNNNNNNNNNNN",
		"DDWWNNNNNNNNNNNN",
		"DWWNNNNNNNNNNNNN",
		"WWNNNNNNNNNNNNNN",
		"WNNNNNNNNNNNNNNN",
	},
	comet = {
		"NNNNNNNNNNNNNNNN",
		"NKKKKKKKKKKKKKKN",
		"NKKWKKKKKKKKWKKN",
		"NKKKKKKKKKLLKKKN",
		"NKKKKKKKLLLWWKKN",
		"NKKKKKLLLLWWWKKN",
		"NKKKLLLLKKWWKKKN",
		"NKLLLKKKKKKKKKKN",
		"NKKKKKKKWKKKKKKN",
		"NKKWKKKKKKKKKKKN",
		"NKKKKKKKKKKKKWKN",
		"NNNNNNNNNNNNNNNN",
	},
	vip = {
		"GGGGGGGGGGGGGGGG",
		"GNNNNNNNNNNNNNNG",
		"GNNNNNNWWNNNNNNG",
		"GNNNNNNWWNNNNNNG",
		"GNNWWWWWWWWWWNNG",
		"GNNNWWWWWWWWNNNG",
		"GNNNNWWWWWWNNNNG",
		"GNNNNWWNNWWNNNNG",
		"GNNNWWNNNNWWNNNG",
		"GNNNNNNNNNNNNNNG",
		"GNNNNNNNNNNNNNNG",
		"GGGGGGGGGGGGGGGG",
	},
	-- Season 1 "Rise of the Primordials" (season-pass rewards)
	ember_sigil = {
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNGNNNNNNNN",
		"NNNNNNGGNNNNNNNN",
		"NNNNNGGGNGNNNNNN",
		"NNNNNGGGGGNNNNNN",
		"NNNNGGWGGGGNNNNN",
		"NNNNGGWWGGGNNNNN",
		"NNNNGWWWWGGNNNNN",
		"NNNNNGWWWGNNNNNN",
		"NNNNNNGGGNNNNNNN",
		"NNNNNNNNNNNNNNNN",
		"DDDDDDDDDDDDDDDD",
	},
	ember_banner = {
		"KKKKKKKKKKKKKKKK",
		"KNNNNNNNNNNNNNNK",
		"KNNNNNNNNNNNNNNK",
		"KGGGGGGGGGGGGGGK",
		"KNNNNNNGNNNNNNNK",
		"KNNNNNGGGNNNNNNK",
		"KNNNNGGWGGNNNNNK",
		"KNNNNNGGGNNNNNNK",
		"KGGGGGGGGGGGGGGK",
		"KNNNNNNNNNNNNNNK",
		"KNNNNNK..KNNNNNK",
		"KKKKKK....KKKKKK",
	},
	titan_eye = {
		"NNNNNNNNNNNNNNNN",
		"NNNNNNNNNNNNNNNN",
		"NNNNNKKKKKKNNNNN",
		"NNNKKWWWWWWKKNNN",
		"NNKWWWDDDDWWWKNN",
		"NKWWWDDKKDDWWWKN",
		"NKWWWDDKKDDWWWKN",
		"NNKWWWDDDDWWWKNN",
		"NNNKKWWWWWWKKNNN",
		"NNNNNKKKKKKNNNNN",
		"NNNNNNNNNNNNNNNN",
		"GGGGGGGGGGGGGGGG",
	},
	storm_banner = {
		"DDDDDDDDDDDDDDDD",
		"NNNNNNNNNWWNNNNN",
		"NNNNNNNNWWNNNNNN",
		"NNNNNNNWWNNNNNNN",
		"NNNNNNWWNNNNNNNN",
		"NNNNNWWWWWWNNNNN",
		"NNNNNNNNNWWNNNNN",
		"NNNNNNNNWWNNNNNN",
		"NNNNNNNWWNNNNNNN",
		"NNNNNNWWNNNNNNNN",
		"NNNNNWNNNNNNNNNN",
		"DDDDDDDDDDDDDDDD",
	},
	cracked_crown = {
		"KKKKKKKKKKKKKKKK",
		"KNNNNNNNNNNNNNNK",
		"KNNGNNNGGNNNGNNK",
		"KNNGGNGGKGNGGNNK",
		"KNNGGGGKGGGGGNNK",
		"KNNGGWGGKGGWGNNK",
		"KNNGGGGKGGGGGNNK",
		"KNNGGGGGKGGGGNNK",
		"KNNDDDDDDDDDDNNK",
		"KNNNNNNNNNNNNNNK",
		"KNNNNNNNNNNNNNNK",
		"KKKKKKKKKKKKKKKK",
	},
	storm_titan = {
		"NNNNNNNNNNNNNNNN",
		"NNNNNNKKKKNNNNNN",
		"NNNNNKWKKWKNNNNN",
		"NNNNNKKKKKKNNNNN",
		"NNNKKKKKKKKKKNNN",
		"NNKKNKKKKKKNKKNN",
		"NWNKNKKKKKKNKNGN",
		"WNNKNKKKKKKNKNNG",
		"NWNNNKKNNKKNNNGN",
		"NNNNNKKNNKKNNNNN",
		"NNNNKKKNNKKKNNNN",
		"DDDDDDDDDDDDDDDD",
	},
	obsidian_crown = {
		"KKKKKKKKKKKKKKKK",
		"KKKKKKKKKKKKKKKK",
		"KKKGKKKGGKKKGKKK",
		"KKKNNKNNNNKNNKKK",
		"KKKNNNNNNNNNNKKK",
		"KKKNNWNNNNWNNKKK",
		"KKKNNNNNNNNNNKKK",
		"KKKNNNNLLNNNNKKK",
		"KKKGGGGGGGGGGKKK",
		"KKKKKKKKKKKKKKKK",
		"KNKNKNKNKNKNKNKN",
		"NKNKNKNKNKNKNKNK",
	},
} :: { [string]: { string } }

-- Animated flags wave: each frame shifts the columns up and down a pixel.
CosmeticArt.ANIMATED_FLAGS = { comet = true, cracked_crown = true } :: { [string]: boolean }
CosmeticArt.FLAG_FRAMES = 4

-- Army tokens: one or more frames each (animated tokens flip between them).
CosmeticArt.TOKENS = {
	square = {
		{
			"............",
			".KKKKKKKKKK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KKKKKKKKKK.",
			"............",
		},
	},
	shield = {
		{
			".KKKKKKKKKK.",
			".KNNNNNNNNK.",
			".KNWNNNNNNK.",
			".KNWNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			".KNNNNNNNNK.",
			"..KNNNNNNK..",
			"..KNNNNNNK..",
			"...KNNNNK...",
			"....KNNK....",
			".....KK.....",
		},
	},
	vanguard = {
		{
			".KK.........",
			".KWKKKKKKK..",
			".KWKNNNNNNK.",
			".KWKNNLNNNNK",
			".KWKNLLLNNK.",
			".KWKNNNNNK..",
			".KWKKKKKK...",
			".KWK........",
			".KWK........",
			".KWK........",
			"KKWKK.......",
			"KKKKK.......",
		},
	},
	tower = {
		{
			"KKK.KKKK.KKK",
			"KNKKKNNKKKNK",
			"KNNNNNNNNNNK",
			"KKKKKKKKKKKK",
			".KNNNNNNNNK.",
			".KNNNKKNNNK.",
			".KNNNKKNNNK.",
			".KNNNNNNNNK.",
			".KDDDDDDDDK.",
			".KNNNKKNNNK.",
			".KNNKWWKNNK.",
			".KKKKKKKKKK.",
		},
	},
	dragon = {
		{
			"............",
			".K.......K..",
			"KNK.....KNK.",
			"KNNK...KNNK.",
			"KNNNKKKNNNKK",
			".KNNNNNNNNWK",
			"..KNNNNNNNKK",
			"..KNNNNNNK..",
			".KNNKKKNNK..",
			".KNK...KNK..",
			".KK.....KK..",
			"............",
		},
		{
			"............",
			"............",
			"............",
			"K.........K.",
			"KNKKKKKKKKNK",
			"KNNNNNNNNNWK",
			".KKNNNNNNNKK",
			"..KNNNNNNK..",
			".KNNKKKNNK..",
			".KNK...KNK..",
			".KK.....KK..",
			"............",
		},
	},
	lion = {
		{
			"..GGGGGGGG..",
			".GGNNNNNNGG.",
			"GGNNNNNNNNGG",
			"GNNKNNNNKNNG",
			"GNNNNNNNNNNG",
			"GNNNNKKNNNNG",
			"GGNNKWWKNNGG",
			".GGNNNNNNGG.",
			"..GGGGGGGG..",
			"...G.GG.G...",
			"............",
			"............",
		},
	},
	-- Season 1 "Rise of the Primordials" (season-pass rewards)
	stone_golem = {
		{
			"...KKKKKK...",
			"..KNNNNNNK..",
			"..KNWNNWNK..",
			"..KNNNNNNK..",
			"KKKKNNNNKKKK",
			"KNNKNNNNKNNK",
			"KNNKNNNNKNNK",
			"KKKKNNNNKKKK",
			"...KNNNNK...",
			"..KNNKKNNK..",
			"..KNNK.KNNK.",
			"..KKKK.KKKK.",
		},
	},
	ember_knight = {
		{
			"....GG......",
			"...GGGG.....",
			"....GG......",
			"..KKKKKKKK..",
			".KNNNNNNNNK.",
			".KNKKKKKKNK.",
			".KNWWWWWWNK.",
			".KNKKKKKKNK.",
			".KNNNNNNNNK.",
			".KNNNLLNNNK.",
			"..KNNNNNNK..",
			"...KKKKKK...",
		},
	},
	obsidian = {
		{
			".....KK.....",
			"....KNNK....",
			"....KNNK....",
			"...KNNLNK...",
			"...KNNLNK...",
			"..KNNNLNNK..",
			"..KNNNLNNK..",
			"..KNNNNNNK..",
			".KNNNNNNNNK.",
			".KDDDDDDDDK.",
			"KKKKKKKKKKKK",
			"............",
		},
	},
	phoenix_rider = {
		{
			"............",
			"G....KK....G",
			"GG..KNWK..GG",
			".GG.KNNK.GG.",
			"..GGKNNKGG..",
			"...KNNNNK...",
			"..KNNNNNNK..",
			".KNNKNNKNNK.",
			"KNNK.KK.KNNK",
			"KKK..GG..KKK",
			".....GG.....",
			"......G.....",
		},
	},
	cinder_golem = {
		{
			"...KKKKKK...",
			"..KNNNNNNK..",
			"..KGNNNNGK..",
			"..KNNGGNNK..",
			"KKKKNNNNKKKK",
			"KNGKNGNNKGNK",
			"KNNKNNGNKNNK",
			"KKKKNGNNKKKK",
			"...KNNGNK...",
			"..KNNKKNNK..",
			"..KGNK.KNGK.",
			"..KKKK.KKKK.",
		},
	},
	titan = {
		{
			"....KKKK....",
			"...KWKKWK...",
			"...KKKKKK...",
			".KKKNNNNKKK.",
			"KNNKNNNNKNNK",
			"KNNKNLLNKNNK",
			"KNNKNNNNKNNK",
			".KKKNNNNKKK.",
			"...KNNNNK...",
			"...KNKKNK...",
			"..KNNK.KNNK.",
			"..KKKK.KKKK.",
		},
		{
			"KK..KKKK..KK",
			"KNK.WKKW.KNK",
			"KNNKKKKKKNNK",
			".KNKNNNNKNK.",
			"..KKNNNNKK..",
			"...KNLLNK...",
			"...KNNNNK...",
			"...KNNNNK...",
			"...KNNNNK...",
			"...KNKKNK...",
			"..KNNK.KNNK.",
			"..KKKK.KKKK.",
		},
	},
} :: { [string]: { { string } } }

-- Nameplate frames: the outline colour around a name (none = no outline).
CosmeticArt.FRAME_COLORS = {
	bronze = 0xb87333,
	silver = 0xc9d1dc,
	gold = 0xf2c14e,
	ashen = 0x9a948c, -- Season 1
	molten = 0xff7a2a,
	lava_seam = 0xe9290e,
	obsidian = 0x6a5a86,
	primordial_eye = 0xb06cff,
	rift = 0x7cfbef,
} :: { [string]: number }

local function colourOf(ch: string, nation: number, border: number): number
	if ch == "N" then
		return nation
	elseif ch == "D" then
		return border
	elseif ch == "L" then
		return mixWhite(nation, 0.5)
	elseif ch == "W" then
		return W
	elseif ch == "G" then
		return G
	end
	return K
end

-- Paint character rows; `shift(x)` moves a column down by that many pixels (waving flags).
local function paint(
	rows: { string },
	nation: number,
	border: number,
	shift: ((number) -> number)?
): (buffer, number, number)
	local h, w = #rows, #rows[1]
	local out = buffer.create(w * h * 4) -- zero = transparent
	for y = 1, h do
		local row = rows[y]
		for x = 1, w do
			local ch = string.sub(row, x, x)
			local ty = y - 1 + (if shift then shift(x - 1) else 0)
			if ch ~= "." and ty >= 0 and ty < h then
				buffer.writeu32(out, (ty * w + x - 1) * 4, rgba(colourOf(ch, nation, border), 255))
			end
		end
	end
	return out, w, h
end

-- A flag's pixels for a nation (0xRRGGBB colours). Unknown designs paint the default banner. `frame` (0-based)
-- waves animated flags.
function CosmeticArt.flag(design: string, nation: number, border: number, frame: number?): (buffer, number, number)
	local rows = CosmeticArt.FLAGS[design] or CosmeticArt.FLAGS.banner
	local f = frame or 0
	if CosmeticArt.ANIMATED_FLAGS[design] and f > 0 then
		return paint(rows, nation, border, function(x: number): number
			return math.floor(math.sin((x / 16) * 2 * math.pi + f * math.pi / 2) + 0.5)
		end)
	end
	return paint(rows, nation, border, nil)
end

function CosmeticArt.tokenFrames(skin: string): number
	local frames = CosmeticArt.TOKENS[skin]
	return if frames then #frames else 1
end

-- An army token's pixels. Unknown skins paint the square.
function CosmeticArt.token(skin: string, nation: number, border: number, frame: number?): (buffer, number, number)
	local frames = CosmeticArt.TOKENS[skin] or CosmeticArt.TOKENS.square
	local rows = frames[((frame or 0) % #frames) + 1]
	return paint(rows, nation, border, nil)
end

-- A shop preview of a border style and shade set: a little patch of grass washed in the nation's shades, inside
-- a styled border.
function CosmeticArt.swatch(
	borderStyle: string,
	shades: string,
	nation: number,
	border: number
): (buffer, number, number)
	local w, h = CosmeticArt.SWATCH_SIZE.w, CosmeticArt.SWATCH_SIZE.h
	local out = buffer.create(w * h * 4)
	local grass = { 0x81b647, 0x7eaf46, 0x5f833c } -- light, middle and dark WorldBox grass
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local c
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 then
				c = PixelArt.borderShade(borderStyle, border, x, y)
			else
				local terrain = grass[(x + y) % 3 + 1]
				local r, g, b = rgb(terrain)
				-- three bands stand for light, middle and dark terrain, so all three shades show
				local lift = if y < 6 then 60 elseif y < 11 then -20 else -80
				local tint = PixelArt.shadeColor(shades, nation, (r * 299 + g * 587 + b * 114) / 1000 + lift)
				local tr, tg, tb = rgb(tint)
				local t = 0.587
				c = math.floor(r + (tr - r) * t + 0.5) * 65536
					+ math.floor(g + (tg - g) * t + 0.5) * 256
					+ math.floor(b + (tb - b) * t + 0.5)
			end
			buffer.writeu32(out, (y * w + x) * 4, rgba(c, 255))
		end
	end
	return out, w, h
end

-- The colour of one painted pixel as 0xRRGGBB and its alpha (tests).
function CosmeticArt.pixel(pixels: buffer, w: number, x: number, y: number): (number, number)
	local v = buffer.readu32(pixels, (y * w + x) * 4)
	local a = bit32.rshift(v, 24)
	return bit32.band(v, 255) * 65536 + bit32.band(bit32.rshift(v, 8), 255) * 256 + bit32.band(bit32.rshift(v, 16), 255),
		a
end

return CosmeticArt
