--!strict
-- The UI's painted frames (docs/UI_DIRECTION.md "Slate & Brass", Appendix A): 9-slice pixel-art frames painted
-- from character grids, the way IconArt paints icons. Slate panels with a lit edge, iron and brass bands, enamel
-- buttons on a thick base, recessed wells, ribbons and octagon medallions, all on the map's 2 px pixel grid.
-- Pure Luau on buffers (no Roblox APIs): tested under Lune. Pixels are RGBA bytes, ready for
-- EditableImage:WritePixelsBuffer. src/client/UI/Frames.luau puts them on screen as 9-slice ImageLabels.
--
-- Codes. Buttons, badges, ribbons, medallion rings: W glint, H highlight row, F face, S lower face, B base,
-- D base bottom, K ink. Plates: E lit edge, L lip, P fill, e dark edge. Windows: y Y O o band (highlight, face,
-- shade, deep shade), R r rivet and its shine, L lip, P fill, d bottom shade. Wells: x rim shadow, w fill, z light
-- edge. Medallions: w the well inside the ring. "." is transparent.

local FrameArt = {}

export type Palette = { [string]: number }
export type Frame = { rows: { string }, slice: { number }? }

FrameArt.INK = 0x0b0d1a

-- The palette's named colours (docs/UI_DIRECTION.md 6.3), as 0xRRGGBB.
FrameArt.COLORS = {
	ink = 0x0b0d1a,
	slate950 = 0x0e111c,
	slate900 = 0x141927,
	slate850 = 0x191f30,
	slate800 = 0x1e2538,
	slate700 = 0x283149,
	slate600 = 0x36415f,
	slate500 = 0x4c5878,
	slate400 = 0x6b7799,
	slate300 = 0x98a2c0,
	brass100 = 0xfff1b8,
	brass200 = 0xffe08a,
	brass300 = 0xf6c453,
	brass400 = 0xe0a23a,
	brass500 = 0xb8752a,
	brass600 = 0x7e4a1e,
	iron200 = 0xc9d1e0,
	iron400 = 0x8f9ab3,
	iron500 = 0x5f6a85,
	iron600 = 0x3d4660,
	-- enamel faces: buttons, badges, ribbons, medallion rings
	gold = 0xf4bf45,
	emerald = 0x41b54a,
	crimson = 0xd8453e,
	azure = 0x3a85de,
	royal = 0x8a52da,
	slate = 0x4a5576,
	disabled = 0x3a4157,
	tile = 0x283149, -- slot tiles (slate700)
	peace = 0x55c35a,
	war = 0xe0483f,
	cataclysm = 0x9a5bea,
	common = 0xb9c1d9,
	rare = 0x4fa3ff,
	epic = 0xb36ff2,
	legendary = 0xffa53a,
} :: { [string]: number }

-- Slot tiles swap only their base to say which group they are in (6.4).
FrameArt.TILE_BASES = {
	build = { B = 0x6e4b22, D = 0x4e3416 }, -- bronze
	recruit = { B = 0x2e6e3a, D = 0x1f4e29 }, -- green
	powers = { B = 0x3e269a, D = 0x2f1d70 }, -- royal
} :: { [string]: { B: number, D: number } }

FrameArt.POWER_WELL = 0x2b1a4a -- the power button's medallion is filled with a deep purple

-- HLS colour conversion, ported from Python's colorsys so the ramps match tools/uimock/frameart.py to the byte.

local function split(c: number): (number, number, number)
	return bit32.rshift(c, 16) / 255, bit32.band(bit32.rshift(c, 8), 255) / 255, bit32.band(c, 255) / 255
end

local function join(r: number, g: number, b: number): number
	local function byte(v: number): number
		return math.clamp(math.floor(v * 255 + 0.5), 0, 255)
	end
	return byte(r) * 65536 + byte(g) * 256 + byte(b)
end

local function toHls(r: number, g: number, b: number): (number, number, number)
	local maxc, minc = math.max(r, g, b), math.min(r, g, b)
	local l = (maxc + minc) / 2
	if maxc == minc then
		return 0, l, 0
	end
	local range = maxc - minc
	local s = if l <= 0.5 then range / (maxc + minc) else range / (2 - maxc - minc)
	local rc, gc, bc = (maxc - r) / range, (maxc - g) / range, (maxc - b) / range
	local h
	if r == maxc then
		h = bc - gc
	elseif g == maxc then
		h = 2 + rc - bc
	else
		h = 4 + gc - rc
	end
	return (h / 6) % 1, l, s
end

local function channel(m1: number, m2: number, hue: number): number
	hue = hue % 1
	if hue < 1 / 6 then
		return m1 + (m2 - m1) * hue * 6
	elseif hue < 0.5 then
		return m2
	elseif hue < 2 / 3 then
		return m1 + (m2 - m1) * (2 / 3 - hue) * 6
	end
	return m1
end

local function fromHls(h: number, l: number, s: number): (number, number, number)
	if s == 0 then
		return l, l, l
	end
	local m2 = if l <= 0.5 then l * (1 + s) else l + s - l * s
	local m1 = 2 * l - m2
	return channel(m1, m2, h + 1 / 3), channel(m1, m2, h), channel(m1, m2, h - 1 / 3)
end

-- `face` with its lightness set to `light`, its hue turned by `hue` degrees and `sat` added to its saturation.
local function tone(face: number, light: number, hue: number, sat: number): number
	local h, _, s = toHls(split(face))
	h = (h + hue / 360) % 1
	s = math.clamp(s + sat, 0, 1)
	return join(fromHls(h, math.clamp(light, 0, 1), s))
end

-- A button colour's six tones from its face (6.4): lightness is scaled, not shifted, so dark faces keep a visible
-- base; highlights turn warm (hue towards yellow, at most 10°), shades cool (towards blue, at most 12°).
function FrameArt.ramp(face: number): Palette
	local h, light = toHls(split(face))
	local function towards(target: number, amount: number): number
		local d = ((target - h * 360 + 540) % 360) - 180
		return math.clamp(d, -amount, amount)
	end
	local warm = towards(60, 10)
	local cool = towards(230, 12)
	return {
		W = tone(face, light + (1 - light) * 0.55, warm, -0.10),
		H = tone(face, light + (1 - light) * 0.28, warm, 0),
		F = face,
		S = tone(face, light * 0.86, cool * 0.5, -0.02),
		B = tone(face, light * 0.64, cool, -0.04),
		D = tone(face, light * 0.47, cool, -0.06),
		K = FrameArt.INK,
	}
end

-- The window grid with its brass band recoloured in a rarity's ramp (shop cards, season-pass reward cells).
function FrameArt.rarityWindow(face: number): Palette
	local r = FrameArt.ramp(face)
	local c = FrameArt.COLORS
	return {
		K = FrameArt.INK,
		y = r.H,
		Y = r.F,
		O = r.S,
		o = r.B,
		R = r.H,
		r = r.W,
		L = c.slate700,
		P = c.slate800,
		d = c.slate850,
	}
end

-- A medallion: an octagon n × n art px (drawn unsliced at 2×), an ink outline, a `ring`-px ring lit from the top
-- left (H F on the lit half, B S on the other), an inner ink line and a well (w) for the icon. Appendix A.
function FrameArt.octagon(n: number, ring: number): { string }
	local c = math.floor(n * 0.3 + 0.5)
	local function inside(x: number, y: number, inset: number): boolean
		local lo, hi = inset, n - 1 - inset
		if x < lo or y < lo or x > hi or y > hi then
			return false
		end
		local cc = c + inset
		return x + y >= cc and (n - 1 - x) + y >= cc and x + (n - 1 - y) >= cc and (n - 1 - x) + (n - 1 - y) >= cc
	end
	local rows = {}
	for y = 0, n - 1 do
		local row = table.create(n)
		for x = 0, n - 1 do
			local ch
			if not inside(x, y, 0) then
				ch = "."
			elseif inside(x, y, 1) and not inside(x, y, 1 + ring) then -- the ring
				local lit = x + y < n - 1
				local outer = not inside(x, y, 2)
				ch = if lit then (if outer then "H" else "F") else (if outer then "B" else "S")
			elseif inside(x, y, 2 + ring) then
				ch = "w"
			else -- the outline, or the ink line inside the ring
				ch = "K"
			end
			row[x + 1] = ch
		end
		table.insert(rows, table.concat(row))
	end
	return rows
end

local RIBBON = {
	"..........KKKKKKKKKKKKKKKKKKKK..........",
	".........KHHHHHHHHHHHHHHHHHHHHK.........",
	".........KWWFFFFFFFFFFFFFFFFFFK.........",
	".........KFFFFFFFFFFFFFFFFFFFFK.........",
	".........KFFFFFFFFFFFFFFFFFFFFK.........",
	".........KFFFFFFFFFFFFFFFFFFFFK.........",
	".........KFFFFFFFFFFFFFFFFFFFFK.........",
	".........KFFFFFFFFFFFFFFFFFFFFK.........",
	"KKKKKKKKKKFFFFFFFFFFFFFFFFFFFFKKKKKKKKKK",
	"KSSSSSSSSKFFFFFFFFFFFFFFFFFFFFKSSSSSSSSK",
	"KBBBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBBBK",
	"KBBBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBBBK",
	"KBBBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBBBK",
	"KBBBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBBBK",
	"KBBBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBBBK",
	".KBBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBBK.",
	"..KBBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBBK..",
	"...KBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBK...",
	"....KBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBK....",
	"....KBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBK....",
	"...KBBBBBKFFFFFFFFFFFFFFFFFFFFKBBBBBK...",
	"..KBBBBBBKSSSSSSSSSSSSSSSSSSSSKBBBBBBK..",
	".KBBBBBBBKSSSSSSSSSSSSSSSSSSSSKBBBBBBBK.",
	"KBBBBBBBBKKKKKKKKKKKKKKKKKKKKKKBBBBBBBBK",
	"KBBBBBBBBDDK................KDDBBBBBBBBK",
	"KBBBBBBBBDDK................KDDBBBBBBBBK",
	"KBBBBBBBBDDK................KDDBBBBBBBBK",
	"KDDDDDDDDDDK................KDDDDDDDDDDK",
	"KDDDDDDDDDDK................KDDDDDDDDDDK",
	"KKKKKKKKKKKK................KKKKKKKKKKKK",
}

-- The ribbon behind phase banners and the Results headline: 40 × 30, always drawn exactly 60 GUI px tall.
function FrameArt.ribbon(): { string }
	return RIBBON
end

-- The frames. `slice` is SliceCenter in art pixels (x0, y0 inclusive, x1, y1 exclusive, as Rect.new takes them);
-- nil for medallions, which are drawn unsliced at exactly 2×.
FrameArt.FRAMES = {
	button = {
		rows = {
			"..KKKKKKKK..",
			".KWHHHHHHHK.",
			"KHHFFFFFFHHK",
			"KHFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KSSSSSSSSSSK",
			"KBBBBBBBBBBK",
			"KBBBBBBBBBBK",
			"KDDDDDDDDDDK",
			".KDDDDDDDDK.",
			"..KKKKKKKK..",
		},
		slice = { 4, 4, 8, 8 },
	},
	-- pressed: the face sits lower on a thin base, the same size so swapping images never moves the layout
	buttonDown = {
		rows = {
			"............",
			"............",
			"..KKKKKKKK..",
			".KSHHHHHHSK.",
			"KSFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KFFFFFFFFFSK",
			"KSSSSSSSSSSK",
			"KDDDDDDDDDDK",
			".KDDDDDDDDK.",
			"..KKKKKKKK..",
		},
		slice = { 4, 4, 8, 8 },
	},
	plate = {
		rows = {
			"..KKKKKK..",
			".KEEEEEEK.",
			"KEELLLLLeK",
			"KELPPPPPeK",
			"KEPPPPPPeK",
			"KEPPPPPPeK",
			"KEPPPPPPeK",
			"KePPPPPPeK",
			".KeeeeeeK.",
			"..KKKKKK..",
		},
		slice = { 3, 3, 7, 7 },
	},
	window = {
		rows = {
			"...KKKKKKKKKKKK...",
			"..KyyyyyyyyyyyyK..",
			".KyrRYYYYYYYYrROK.",
			"KyYROYYYYYYYYROOoK",
			"KyYYKKKKKKKKKKOOoK",
			"KyYYKLLLLLLLLKOOoK",
			"KyYYKLPPPPPPPKOOoK",
			"KyYYKPPPPPPPPKOOoK",
			"KyYYKPPPPPPPPKOOoK",
			"KyYYKPPPPPPPPKOOoK",
			"KyYYKPPPPPPPPKOOoK",
			"KyYYKPPPPPPPPKOOoK",
			"KyYYKddddddddKOOoK",
			"KyYYKKKKKKKKKKOOoK",
			"KyOrROOOOOOOOrROoK",
			".KoROooooooooROoK.",
			"..KooooooooooooK..",
			"...KKKKKKKKKKKK...",
		},
		slice = { 6, 7, 13, 12 },
	},
	well = {
		rows = {
			".KKKKKK.",
			"KxxxxxxK",
			"KxwwwwwK",
			"KxwwwwzK",
			"KxwwwwzK",
			"KxwwwwzK",
			"KwzzzzzK",
			".KKKKKK.",
		},
		slice = { 2, 2, 6, 6 },
	},
	-- always drawn exactly 28 GUI px tall
	titlePlate = {
		rows = {
			"..KKKKKKKK..",
			".KyyyyyyyyK.",
			"KyyYYYYYYyyK",
			"KyYYYYYYYYOK",
			"KyYYYYYYYYOK",
			"KyYYYYYYYYOK",
			"KyYYYYYYYYOK",
			"KyYYYYYYYYOK",
			"KyYYYYYYYYOK",
			"KyYYYYYYYYOK",
			"KOOOOOOOOOOK",
			"KooooooooooK",
			".KooooooooK.",
			"..KKKKKKKK..",
		},
		slice = { 5, 2, 7, 11 },
	},
	badge = {
		rows = {
			"...KKKK...",
			".KKHHHHKK.",
			".KHFFFFHK.",
			"KHFFFFFFSK",
			"KFFFFFFFSK",
			"KFFFFFFFSK",
			"KSFFFFFSSK",
			".KSSSSSSK.",
			".KKSSSSKK.",
			"...KKKK...",
		},
		slice = { 4, 4, 6, 6 },
	},
	ribbon = { rows = RIBBON, slice = { 13, 3, 27, 20 } },
	medallionSmall = { rows = FrameArt.octagon(16, 2) }, -- 32 GUI px: toasts
	medallion = { rows = FrameArt.octagon(20, 2) }, -- 40 GUI px: the clock
	medallionLarge = { rows = FrameArt.octagon(32, 3) }, -- 64 GUI px: the power button
} :: { [string]: Frame }

-- Frames painted in a fixed palette (not a colour ramp).
FrameArt.STYLES = {
	plate = {
		K = FrameArt.INK,
		E = FrameArt.COLORS.slate600,
		L = FrameArt.COLORS.slate700,
		P = FrameArt.COLORS.slate800,
		e = FrameArt.COLORS.slate900,
	},
	plateRaised = { -- cards inside a window, your row in a table
		K = FrameArt.INK,
		E = FrameArt.COLORS.slate500,
		L = FrameArt.COLORS.slate600,
		P = FrameArt.COLORS.slate700,
		e = FrameArt.COLORS.slate850,
	},
	window = { -- brass: meta and reward windows
		K = FrameArt.INK,
		y = FrameArt.COLORS.brass200,
		Y = FrameArt.COLORS.brass400,
		O = FrameArt.COLORS.brass500,
		o = FrameArt.COLORS.brass600,
		R = FrameArt.COLORS.brass200,
		r = FrameArt.COLORS.brass100,
		L = FrameArt.COLORS.slate700,
		P = FrameArt.COLORS.slate800,
		d = FrameArt.COLORS.slate850,
	},
	windowIron = { -- iron: in-match sheets and panels
		K = FrameArt.INK,
		y = FrameArt.COLORS.iron200,
		Y = FrameArt.COLORS.iron400,
		O = FrameArt.COLORS.iron500,
		o = FrameArt.COLORS.iron600,
		R = 0xe6ebf3,
		r = 0xffffff,
		L = FrameArt.COLORS.slate700,
		P = FrameArt.COLORS.slate800,
		d = FrameArt.COLORS.slate850,
	},
	well = { K = FrameArt.INK, x = 0x0a0d17, w = FrameArt.COLORS.slate900, z = FrameArt.COLORS.slate850 },
	titlePlate = {
		K = FrameArt.INK,
		y = FrameArt.COLORS.brass200,
		Y = FrameArt.COLORS.brass300,
		O = FrameArt.COLORS.brass500,
		o = FrameArt.COLORS.brass600,
	},
} :: { [string]: Palette }

local MEDALLIONS = { medallionSmall = true, medallion = true, medallionLarge = true }
local WINDOWS = { window = true }

-- The palette a frame is painted in. `style` is a STYLES name, a named colour (COLORS: "gold", "emerald"...),
-- "tile:<group>" (a slot tile with its group's base: build, recruit, powers), "power" (the power button's
-- medallion) or a colour as 0xRRGGBB. A colour on a window frame is a rarity band; on a medallion, a ring round a
-- slate well; on anything else, an enamel ramp.
function FrameArt.palette(frame: string, style: string | number): Palette
	if type(style) == "string" then
		local fixed = FrameArt.STYLES[style]
		if fixed then
			return fixed
		end
		local group = string.match(style, "^tile:(%w+)$")
		if group then
			local p = table.clone(FrameArt.ramp(FrameArt.COLORS.tile))
			local base = FrameArt.TILE_BASES[group]
			if base then
				p.B, p.D = base.B, base.D
			end
			return p
		end
		if style == "power" then
			local p = table.clone(FrameArt.ramp(FrameArt.COLORS.royal))
			p.w = FrameArt.POWER_WELL
			return p
		end
	end
	local face = if type(style) == "number" then style else FrameArt.COLORS[style] or FrameArt.COLORS.slate
	if WINDOWS[frame] then
		return FrameArt.rarityWindow(face)
	end
	if frame == "titlePlate" then
		-- a small plate in an enamel colour (the shop's rarity tags): its lit top, face, shaded and dark base rows
		local r = FrameArt.ramp(face)
		return { K = FrameArt.INK, y = r.H, Y = r.F, O = r.S, o = r.B }
	end
	local p = FrameArt.ramp(face)
	if MEDALLIONS[frame] then
		p = table.clone(p)
		p.w = FrameArt.COLORS.slate900
	end
	return p
end

local function rgba(c: number): number
	local r, g, b = bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
	return 255 * 16777216 + b * 65536 + g * 256 + r
end

-- Paint a frame (by name) in a palette: an RGBA buffer and its size. Unknown codes stay transparent.
function FrameArt.paint(frame: string, palette: Palette): (buffer, number, number)
	local def = FrameArt.FRAMES[frame]
	local rows = if def then def.rows else {}
	local h = #rows
	local w = if h > 0 then #rows[1] else 0
	local out = buffer.create(w * h * 4) -- zero = transparent
	for y = 1, h do
		local row = rows[y]
		for x = 1, math.min(#row, w) do
			local colour = palette[string.sub(row, x, x)]
			if colour then
				buffer.writeu32(out, ((y - 1) * w + x - 1) * 4, rgba(colour))
			end
		end
	end
	return out, w, h
end

-- The sunburst behind the Results ribbon (docs/UI_DIRECTION.md 7.13): `n` × `n` px of `rays` rays in `colour`
-- from the centre, in alternate angular sectors, starting from a ring (the middle, where the rays would crowd into
-- a jumble, is hidden by the ribbon anyway) and fading out in four steps towards the edge: pixel art, not a blur.
-- RGBA bytes, ready for EditableImage:WritePixelsBuffer.
FrameArt.SUNBURST_STEPS = 4
FrameArt.SUNBURST_HOLE = 0.22 -- of the radius: no rays inside it
local SUNBURST_BANDS = { 0.55, 0.72, 0.86, 1 } -- full, then 3/4, 1/2 and 1/4 alpha out to the edge
function FrameArt.sunburst(n: number, rays: number, colour: number): (buffer, number, number)
	local out = buffer.create(n * n * 4) -- zero = transparent
	local r, g, b = bit32.rshift(colour, 16), bit32.band(bit32.rshift(colour, 8), 255), bit32.band(colour, 255)
	local centre = (n - 1) / 2
	local steps = FrameArt.SUNBURST_STEPS
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local dx, dy = x - centre, y - centre
			local d = math.sqrt(dx * dx + dy * dy) / (n / 2)
			local sector = math.floor((math.atan2(dy, dx) + math.pi) / (2 * math.pi) * rays * 2) % (rays * 2)
			if d >= FrameArt.SUNBURST_HOLE and d < 1 and sector % 2 == 0 then
				local band = 1
				while d >= SUNBURST_BANDS[band] do
					band += 1
				end
				local a = math.floor((steps + 1 - band) / steps * 255 + 0.5)
				buffer.writeu32(out, (y * n + x) * 4, a * 16777216 + b * 65536 + g * 256 + r)
			end
		end
	end
	return out, n, n
end

-- The size of a frame's art in art pixels.
function FrameArt.size(frame: string): (number, number)
	local def = FrameArt.FRAMES[frame]
	if def == nil then
		return 0, 0
	end
	return #def.rows[1], #def.rows
end

return FrameArt
