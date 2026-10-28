--!strict
-- Pixel art for cosmetics (docs/MONETIZATION.md 3.2): 16×12 flags, 12×12 army tokens, border and shade swatches
-- for the shop. Painted from little character grids in the nation's own colours, so every flag and token keeps
-- the map's WorldBox look and its owner's colour. Pure Luau on buffers (no Roblox APIs): tested under Lune.
-- Pixels are RGBA bytes, ready for EditableImage:WritePixelsBuffer.
--
-- Colour codes: N the nation's colour, D its border colour, L the nation colour lightened, K outline, W white,
-- G gold, "." transparent. The race soldiers (SOLDIERS) add a few fixed colours of their own (SOLDIER_COLOURS).

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
	-- the World Shaker achievement's Legendary token: a crowned titan's helm
	world_shaker = {
		{
			"G.G.G..G.G.G",
			"GGGGGGGGGGGG",
			".KKKKKKKKKK.",
			"KNNNNNNNNNNK",
			"KNKKKNNKKKNK",
			"KNKWKNNKWKNK",
			"KNNNNNNNNNNK",
			"KDNNNKKNNNDK",
			".KDNNNNNNDK.",
			".KNDKNNKDNK.",
			"..KNNNNNNK..",
			"...KKKKKK...",
		},
	},
} :: { [string]: { { string } } }

-- Race soldiers (docs/DESIGN.md "Races", "Map rendering"): with the default token equipped (Catalogue.DEFAULTS.Token),
-- a nation's armies are a little soldier of its race in its colours, so the map shows at a glance whose army is
-- whose and what people they are: Eldmoor's fantasy peoples, Earth's civilisations, Skyshards' sci-fi peoples. An
-- equipped token skin still wins. 12×12 like the tokens.
CosmeticArt.SOLDIERS = {
	Humans = { -- a footman: steel helm, kite shield with a white cross, spear
		"....KKK...K.",
		"...KWSSK.KSK",
		"..KSSSSSKKSK",
		"..KTKSKTKKbK",
		"..KTTTTTKKbK",
		"KKKKKNNNNKbK",
		"KNWNKNNNNTbK",
		"KWWWKNNNNKbK",
		"KNWNKNNNNKbK",
		".KNKKDDDDKbK",
		"..K.KNKKNKbK",
		"....KK..KKbK",
	},
	Elves = { -- an archer: fair hair, a pointed ear, a drawn bow
		"....KKKKK...",
		".BWKYYYYYK..",
		"B.WKYYYYYKK.",
		"B.WKTTTTTKT.",
		"B.WKTKTKTTK.",
		"B.WKYTTTYK..",
		"B.TKNNNNNK..",
		"B.WKNNNNNK..",
		"B.WKNNNNNK..",
		".BWKDDDDDK..",
		"...KNNKNNK..",
		"...KKK.KKK..",
	},
	Orcs = { -- a warrior: green skin, red eyes, tusks, a horned iron cap, a cleaver
		".K........K.",
		"KWK.KKKK.KWK",
		"KWWKssssKWWK",
		".KKVVVVVVKSS",
		"..KVRVVRVKSS",
		"..KVVVVVVKsS",
		"..KWVKKVWKbK",
		"KKKKVVVVKKbK",
		"KVNNNNNNNVbK",
		"KVKNNNNNKKbK",
		".KKDDDDDDKbK",
		"..KNNKKNNKbK",
	},
	Dwarves = { -- a stout dwarf: steel helm, a big red beard, an axe
		"........KKK.",
		"...KKKKKSSSK",
		"..KWSSSSKSSK",
		"..KsssssKKbK",
		"..KTKTKTKKbK",
		".KHTTTTTHKbK",
		"KNHHHHHHHTbK",
		"KNNHHhHHNKbK",
		"KNNKHHHKNKbK",
		"KDDDKHKDDKbK",
		"KNNNNKNNNKbK",
		".KKKK.KKKKKK",
	},
	Kingdom = { -- a man-at-arms: a great helm, a heater shield with a gold charge, a raised sword
		"..KKKKK...K.",
		".KSSSSSK.KWK",
		".KSKKKSK.KWK",
		".KSSSSSK.KWK",
		"..KsssK..KWK",
		"KKKKNNNKKGGG",
		"KNNNKNNNNTK.",
		"KNGNKNNNNK..",
		"KNNNKNNNNK..",
		".KNKKDDDDK..",
		"..K.KNKKNK..",
		"....KK..KK..",
	},
	Empire = { -- a legionary: a red-crested helmet, a tall curved shield with a gold boss, a short sword
		"..KRRRRRK...",
		"...KSSSK....",
		"..KSSSSSK...",
		"..KSTTTSK...",
		"..KSKTKSK...",
		"KKKKKTTTKK..",
		"KNNNKNNNNTK.",
		"KNGNKNNNNKSK",
		"KGGGKNNNNKSK",
		"KNGNKDDDDKK.",
		"KKKKKNKKNK..",
		"....KK..KK..",
	},
	Nomads = { -- a horse archer: a fur-trimmed cap, a recurve bow
		"...KKKK..K..",
		"..KRRRRK.KB.",
		".KMMMMMMKW.B",
		".KMTTTTMKW.B",
		".KTKTTKTKW.B",
		"..KTTTTKKT.B",
		".KNNNNNNKW.B",
		".KNGNNGNKW.B",
		".KNNNNNNKW.B",
		".KDDDDDDKKB.",
		"..KNNKNNK.K.",
		"..KKK.KKK...",
	},
	Republic = { -- a crossbowman: a broad steel kettle hat, a crossbow held across
		"...KKKKK....",
		"..KSSSSSK...",
		"KKSSSSSSSKK.",
		"KsssssssssK.",
		".KKTKTTKTK..",
		"..KTTTTTTK..",
		".KKNNNNNNKK.",
		"KBBBBbBBBBBK",
		"KTKNNNNNNKTK",
		".KKNNNNNNKK.",
		"..KDDDDDDK..",
		"..KNNKKNNK..",
	},
	Clans = { -- a pikeman: a steel cap, a brown beard, a long pike
		"..........K.",
		"...KKKKK.KWK",
		"..KSSSSSKKWK",
		".KKKKKKKKKbK",
		"..KTKTTKTKbK",
		"..KbTTTTbKbK",
		"..KbbbbbbKbK",
		".KNKbbbbKTbK",
		"KNNNKbbKNTbK",
		"KNNNNKKNNKbK",
		".KDDDDDDDKbK",
		"..KNNKKNNKbK",
	},
	Lizardfolk = { -- a lizard warrior: an orange crest, yellow eyes, green scales, a spear
		"...KFKFK..K.",
		"..KZFZFZKKWK",
		".KZZZZZZZKWK",
		".KZYKZZYKZbK",
		".KZZZZZZZZbK",
		"..KzWzWzZKbK",
		"...KZZZZKKbK",
		"..KNNNNNNZbK",
		".KZNNNNNNKbK",
		"KZzKDDDDDKbK",
		"KzK.KNKKNKbK",
		".KK.KK..KKbK",
	},
	Marines = { -- a marine in power armour: a helmet with a cyan visor, a rifle
		"...KKKKK....",
		"..KSSSSSK...",
		".KSKKKKKSK..",
		".KSKCCcKSK..",
		".KSSSSSSSK..",
		"KKSKKKKKSKK.",
		"KSSNNNNNSSKK",
		"KSKNNNNNKKCK",
		"KsKNGNNNKSSK",
		".KKDDDDDKXXK",
		"..KSSKSSK.K.",
		"..KKK.KKK...",
	},
	Robots = { -- a robot: an antenna light, a red eye strip, a plated chest
		".....KK.....",
		".....KAK....",
		"..KKKKKKKK..",
		"..KSSSSSSK..",
		"..KSRRRRSK..",
		"..KSSSSSSK..",
		".KKKKKKKKKK.",
		"KSKNNNNNNKSK",
		"KsKNNCCNNKsK",
		"KSKDDDDDDKSK",
		"..KNNKKNNK..",
		"..KKK..KKK..",
	},
	Insectoids = { -- an insect warrior: antennae, red compound eyes, mandibles, four arms
		".K......K...",
		"..K....K....",
		"...KKKKK....",
		"..KPRPPRPK..",
		"..KRRPPRRK..",
		"..KPPPPPPK..",
		"..KAKPPKAK..",
		"KKKPNNNNPKKK",
		"KPKNNNNNNKPK",
		"KPKNDDDDNKPK",
		"...KNNNNK...",
		"..KPK..KPK..",
	},
	Crystals = { -- a crystal being: a faceted glowing head, a body of shards
		".....KK.....",
		"....KCWK....",
		"...KCWWCK...",
		"..KCCWCcCK..",
		"..KCKCCKcK..",
		"...KCCcCK...",
		".KK.KCcK.KK.",
		"KLNKKNNKKNLK",
		"KNNNNNNNNNNK",
		".KNDDNNDDNK.",
		"..KNNKKNNK..",
		"..KKK..KKK..",
	},
	Energy = { -- an energy being: a crackling orb of light with a tail
		"K...KKKK...K",
		".K.KEEEEK.K.",
		"..KEWWWWEK..",
		".KEWKWWKWEK.",
		"KEWWWWWWWWEK",
		"KEWWWEEWWWEK",
		".KNEWWWWENK.",
		"KNNKEEEEKNNK",
		"KNNNKLLKNNNK",
		".KNNNNNNNNK.",
		".KDDKNNKDDK.",
		"..KK.KK.KK..",
	},
} :: { [string]: { string } }

-- Ships (docs/DESIGN.md "Navies", "Map rendering"): each map's one ship type (MapDef.ship) as its fleets' token,
-- in the nation's colours, 16×12 (a ship is longer than it is tall), bow to the right. It draws with the soldiers'
-- colours (SOLDIER_COLOURS).
CosmeticArt.SHIP_SIZE = { w = 16, h = 12 }
CosmeticArt.SHIPS = {
	Galleon = { -- Earth: a two-masted sailing ship, white sails with a stripe and pennants in the nation's colour
		"....bNN....bNN..",
		"..KKKKKK.KKKKKK.",
		"..KWWWWK.KWWWWK.",
		"..KNNNNK.KNNNNK.",
		"..KWWWWK.KWWWWK.",
		"..KKbKKK.KKbKKK.",
		"....b......b....",
		"KKKKKKKKKKKKKKKK",
		"KBBBBBBBBBBBBBBK",
		".KBDBBDBBDBBDBK.",
		"..KBBBBBBBBBBK..",
		"...KKKKKKKKKK...",
	},
	Dragonship = { -- Eldmoor: a longship with a dragon's head on the prow, a striped sail and a row of shields
		".......b........",
		"....KKKbKKKK....",
		"....KNWNWNWK....",
		"....KNWNWNWK....",
		"....KNWNWNWK....",
		"....KKKbKKKK..KK",
		".K.....b.....KZK",
		"KbK....b....KZRK",
		"KBKKKKKKKKKKKZK.",
		".KNDNDNDNDNDNK..",
		"..KBBBBBBBBBK...",
		"...KbKbKbKbK....",
	},
	Starship = { -- Skyshards: a steel starship with a stripe in the nation's colour, a cyan canopy and engine glow
		"................",
		".....KKK........",
		"....KNNK........",
		"...KNNNKKKKK....",
		"KK.KSSSSSSSSKK..",
		"CEKSSSSSCCSSSSK.",
		"CEKNNNNNNNNNNNNK",
		"KK.KSSSSSSSSSKK.",
		"...KDDDKKKKKK...",
		"....KDDK........",
		".....KKK........",
		"................",
	},
} :: { [string]: { string } }

-- The soldiers' own colours: T skin, V an orc's skin, R red (an orc's eyes, a crest, a light), S s steel and its
-- shade, B b wood and dark wood, H h a beard and its shade, Y fair hair, Z z scales and their shade, F an orange
-- crest, A amber light, C c cyan glow and its shade, P a purple carapace, E energy light, M fur, X gunmetal.
CosmeticArt.SOLDIER_COLOURS = {
	T = 0xf0c08a,
	V = 0x8cb43c,
	R = 0xff4a3a,
	S = 0xd2d8e2,
	s = 0x858da0,
	B = 0xa0672f,
	b = 0x63401f,
	H = 0xb8582a,
	h = 0x7a3518,
	Y = 0xffe28a,
	Z = 0x46b48c,
	z = 0x2c7a60,
	F = 0xff9a3c,
	A = 0xffb02e,
	C = 0x7cfbef,
	c = 0x3fb3aa,
	P = 0x9a66d6,
	E = 0xfff07a,
	M = 0xc9b08a,
	X = 0x3a4250,
} :: { [string]: number }

-- Nameplate frames: the outline colour around a name (none = no outline). Centurion and Warlord are earned
-- (an achievement, last week's top 100).
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
	centurion = 0xb36bff,
	warlord = 0xe0483c,
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
	return CosmeticArt.SOLDIER_COLOURS[ch] or K
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

-- A race soldier's pixels (CosmeticArt.SOLDIERS) in a nation's colours. Unknown races paint the square token.
function CosmeticArt.soldier(race: string, nation: number, border: number): (buffer, number, number)
	local rows = CosmeticArt.SOLDIERS[race] or CosmeticArt.TOKENS.square[1]
	return paint(rows, nation, border, nil)
end

-- A ship's pixels (CosmeticArt.SHIPS, by the map's ship name) in a nation's colours. Unknown ships paint the Galleon.
function CosmeticArt.ship(name: string, nation: number, border: number): (buffer, number, number)
	return paint(CosmeticArt.SHIPS[name] or CosmeticArt.SHIPS.Galleon, nation, border, nil)
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
