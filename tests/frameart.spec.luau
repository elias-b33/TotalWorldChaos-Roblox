--!strict
-- The UI's painted frames (src/client/FrameArt.luau, docs/UI_DIRECTION.md Appendix A): clean grids, palettes
-- that cover every code, sane 9-slice rects, ramps that match the doc's table to the byte, symmetric medallions.
local FrameArt = require("../src/client/FrameArt")
local T = require("./TestKit")

local function luminance(c: number): number
	local r, g, b = bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
	return 0.299 * r + 0.587 * g + 0.114 * b
end

local function hex(c: number): string
	return string.format("#%06x", c)
end

-- Every frame with the palettes it is painted in on screen.
local USES: { [string]: { string | number } } = {
	button = {
		"gold",
		"emerald",
		"crimson",
		"azure",
		"royal",
		"slate",
		"disabled",
		"tile:build",
		"tile:recruit",
		0xd23c50,
	},
	buttonDown = { "gold", "slate", "tile:powers" },
	plate = { "plate", "plateRaised" },
	window = { "window", "windowIron", "common", "rare", "epic", "legendary" },
	well = { "well" },
	titlePlate = { "titlePlate", "common", "rare", "epic", "legendary", "slate", "gold" },
	badge = { "crimson", "gold" },
	ribbon = { "war", "cataclysm", "gold" },
	medallionSmall = { "war", "peace", "gold", "slate", "azure", "royal" },
	medallion = { "peace", "war", "cataclysm", "gold" },
	medallionLarge = { "power" },
}

T.test("every frame has rows of equal length", function()
	for name, frame in FrameArt.FRAMES do
		local w = #frame.rows[1]
		T.expect(w > 0, name .. " is empty")
		for i, row in frame.rows do
			T.equal(#row, w, name .. " row " .. i)
		end
	end
end)

T.test("every frame is painted somewhere, and every code it uses is in each palette", function()
	for name in FrameArt.FRAMES do
		T.expect(USES[name] ~= nil, name .. " has no palette in the test")
	end
	for name, styles in USES do
		local frame = FrameArt.FRAMES[name]
		T.expect(frame ~= nil, "no frame " .. name)
		for _, style in styles do
			local palette = FrameArt.palette(name, style)
			for y, row in frame.rows do
				for x = 1, #row do
					local code = string.sub(row, x, x)
					if code ~= "." then
						T.expect(
							palette[code] ~= nil,
							string.format("%s in %s: code %s at %d,%d has no colour", name, tostring(style), code, x, y)
						)
					end
				end
			end
		end
	end
end)

T.test("slice rects sit inside their images and their centres are opaque", function()
	for name, frame in FrameArt.FRAMES do
		local slice = frame.slice
		if slice then
			local w, h = FrameArt.size(name)
			local x0, y0, x1, y1 = slice[1], slice[2], slice[3], slice[4]
			T.expect(x0 >= 1 and y0 >= 1 and x1 < w and y1 < h, name .. "'s slice leaves a border on every side")
			T.expect(x0 < x1 and y0 < y1, name .. "'s slice has a centre")
			for y = y0 + 1, y1 do
				local row = FrameArt.FRAMES[name].rows[y]
				for x = x0 + 1, x1 do
					T.expect(
						string.sub(row, x, x) ~= ".",
						string.format("%s's centre is transparent at %d,%d", name, x, y)
					)
				end
			end
		end
	end
end)

T.test("paint makes w × h RGBA pixels with transparent corners", function()
	for name in FrameArt.FRAMES do
		local styles = USES[name]
		local pixels, w, h = FrameArt.paint(name, FrameArt.palette(name, styles[1]))
		local fw, fh = FrameArt.size(name)
		T.equal(w, fw, name .. " width")
		T.equal(h, fh, name .. " height")
		T.equal(buffer.len(pixels), w * h * 4, name .. " buffer")
		-- the ribbon's tails reach its bottom corners; the gap between them is transparent instead
		local corners = if name == "ribbon"
			then { { 0, 0 }, { w - 1, 0 }, { w // 2, h - 1 } }
			else { { 0, 0 }, { w - 1, 0 }, { 0, h - 1 }, { w - 1, h - 1 } }
		for _, corner in corners do
			local alpha = buffer.readu8(pixels, (corner[2] * w + corner[1]) * 4 + 3)
			T.equal(alpha, 0, string.format("%s corner %d,%d", name, corner[1], corner[2]))
		end
		-- the middle is painted, opaque
		local mid = buffer.readu8(pixels, ((h // 2) * w + w // 2) * 4 + 3)
		T.equal(mid, 255, name .. " middle")
	end
	-- the bytes are R, G, B, A (what WritePixelsBuffer takes)
	local pixels, w = FrameArt.paint("well", FrameArt.STYLES.well)
	local at = (3 * w + 3) * 4
	T.equal(buffer.readu8(pixels, at), 0x14)
	T.equal(buffer.readu8(pixels, at + 1), 0x19)
	T.equal(buffer.readu8(pixels, at + 2), 0x27)
end)

T.test("ramp returns six tones in falling luminance", function()
	for name, face in FrameArt.COLORS do
		if
			string.match(name, "^slate%d") == nil
			and string.match(name, "^brass") == nil
			and string.match(name, "^iron") == nil
			and name ~= "ink"
		then
			local r = FrameArt.ramp(face)
			local order = { r.W, r.H, r.F, r.S, r.B, r.D }
			for i = 2, #order do
				T.expect(
					luminance(order[i]) < luminance(order[i - 1]),
					string.format(
						"%s: tone %d (%s) is not darker than tone %d (%s)",
						name,
						i,
						hex(order[i]),
						i - 1,
						hex(order[i - 1])
					)
				)
			end
			T.equal(r.F, face, name .. "'s face")
			T.equal(r.K, FrameArt.INK, name .. "'s outline")
		end
	end
end)

T.test("ramps match the doc's table to the byte (docs/UI_DIRECTION.md 6.4)", function()
	local TABLE: { [string]: { number } } = {
		gold = { 0xf6ecb0, 0xf7e679, 0xf4bf45, 0xef9b1e, 0xb9640f, 0x86490d },
		emerald = { 0xb1daae, 0x7bcd73, 0x41b54a, 0x3a9a4b, 0x2d7140, 0x22522f },
		crimson = { 0xe8baad, 0xe38c74, 0xd8453e, 0xc42b33, 0x902133, 0x691a26 },
		azure = { 0xacd3eb, 0x71bbe7, 0x3a85de, 0x2561cc, 0x1d3c96, 0x172d6d },
		royal = { 0xd4b6ea, 0xbb82e4, 0x8a52da, 0x6332d0, 0x3e269a, 0x2f1d70 },
		slate = { 0xaeb6c1, 0x7288a7, 0x4a5576, 0x414864, 0x323649, 0x252835 },
		disabled = { 0xa5abb5, 0x637794, 0x3a4157, 0x33384a, 0x272936, 0x1d1f27 },
		tile = { 0x95a4b7, 0x4f6c91, 0x283149, 0x23293e, 0x1b1e2d, 0x141621 },
		peace = { 0xbcdfb8, 0x8ed485, 0x55c35a, 0x41b051, 0x328146, 0x265d34 },
		war = { 0xecbcae, 0xe98f75, 0xe0483f, 0xd2252c, 0x9a1d2f, 0x701724 },
		cataclysm = { 0xdbb9f1, 0xc789f0, 0x9a5bea, 0x7035e3, 0x401cb4, 0x301683 },
		common = { 0xe2e6eb, 0xcdd6e4, 0xb9c1d9, 0x96a0c4, 0x606ba1, 0x485075 },
		rare = { 0xb4e2fb, 0x80d2ff, 0x4fa3ff, 0x2275fd, 0x043dd1, 0x052e98 },
		epic = { 0xe5c2f6, 0xd897f6, 0xb36ff2, 0x8a44ec, 0x5017cb, 0x3c1393 },
		legendary = { 0xfbe3ab, 0xffd671, 0xffa53a, 0xfd7911, 0xc44604, 0x8f3404 },
	}
	local CODES = { "W", "H", "F", "S", "B", "D" }
	for name, want in TABLE do
		local r = FrameArt.ramp(FrameArt.COLORS[name])
		for i, code in CODES do
			T.equal(hex(r[code]), hex(want[i]), name .. " " .. code)
		end
	end
end)

T.test("slot tiles swap only their base; the power medallion has a purple well", function()
	local tile = FrameArt.ramp(FrameArt.COLORS.tile)
	local build = FrameArt.palette("button", "tile:build")
	T.equal(build.F, tile.F)
	T.equal(build.H, tile.H)
	T.equal(build.B, 0x6e4b22)
	T.equal(build.D, 0x4e3416)
	T.equal(FrameArt.palette("medallionLarge", "power").w, FrameArt.POWER_WELL)
	T.equal(FrameArt.palette("medallion", "peace").w, FrameArt.COLORS.slate900)
	-- a colour on a window is a rarity band
	T.equal(FrameArt.palette("window", "rare").Y, FrameArt.COLORS.rare)
	-- and on a title plate, a rarity tag: the plate's grid in the colour's ramp (face, lit top, shaded base)
	local epic = FrameArt.ramp(FrameArt.COLORS.epic)
	local tag = FrameArt.palette("titlePlate", "epic")
	T.equal(tag.Y, epic.F)
	T.equal(tag.y, epic.H)
	T.equal(tag.O, epic.S)
	T.equal(tag.o, epic.B)
	T.equal(FrameArt.palette("titlePlate", "titlePlate").Y, FrameArt.COLORS.brass300)
end)

T.test("octagons are mirror-symmetric and match the doc's example", function()
	for _, spec in { { 16, 2 }, { 20, 2 }, { 32, 3 } } do
		local rows = FrameArt.octagon(spec[1], spec[2])
		T.equal(#rows, spec[1])
		local n = spec[1]
		for y = 1, n do
			for x = 1, n do
				local a = string.sub(rows[y], x, x)
				local mirrorX = string.sub(rows[y], n + 1 - x, n + 1 - x)
				local mirrorY = string.sub(rows[n + 1 - y], x, x)
				T.equal(
					a == ".",
					mirrorX == ".",
					string.format("octagon %d: shape at %d,%d vs its left-right mirror", n, x, y)
				)
				T.equal(
					a == ".",
					mirrorY == ".",
					string.format("octagon %d: shape at %d,%d vs its top-bottom mirror", n, x, y)
				)
				T.equal(a == "K", mirrorX == "K", string.format("octagon %d: outline at %d,%d", n, x, y))
			end
		end
	end
	local EXAMPLE = {
		"......KKKKKKKK......",
		".....KHHHHHHHHK.....",
		"....KHFFFFFFFFHK....",
		"...KHFKKKKKKKKFHK...",
		"..KHFKwwwwwwwwKSBK..",
		".KHFKwwwwwwwwwwKSBK.",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		"KHFKwwwwwwwwwwwwKSBK",
		".KHFKwwwwwwwwwwKSBK.",
		"..KHSKwwwwwwwwKSBK..",
		"...KBSKKKKKKKKSBK...",
		"....KBSSSSSSSSBK....",
		".....KBBBBBBBBK.....",
		"......KKKKKKKK......",
	}
	local rows = FrameArt.octagon(20, 2)
	for i, row in EXAMPLE do
		T.equal(rows[i], row, "octagon(20, 2) row " .. i)
	end
end)

T.test("fixed-height frames: the title plate is 14 art px (28 on screen), the ribbon 30 (60)", function()
	local _, plateH = FrameArt.size("titlePlate")
	local ribbonW, ribbonH = FrameArt.size("ribbon")
	T.equal(plateH, 14)
	T.equal(ribbonW, 40)
	T.equal(ribbonH, 30)
	T.equal(#FrameArt.ribbon(), 30)
end)

T.test("the Results sunburst: 16 rays in alternate sectors, fading out in steps, nothing past its circle", function()
	local n = 64
	local pixels, w, h = FrameArt.sunburst(n, 16, 0xfff1b8)
	T.equal(w, n)
	T.equal(h, n)
	T.equal(buffer.len(pixels), n * n * 4)
	local function alpha(x: number, y: number): number
		return buffer.readu8(pixels, (y * n + x) * 4 + 3)
	end
	-- corners lie outside the circle
	T.equal(alpha(0, 0), 0)
	T.equal(alpha(n - 1, n - 1), 0)
	-- walking round a ring crosses 16 lit sectors (32 lit/dark changes)
	local changes, last = 0, alpha(n // 2 + 20, n // 2) > 0
	local steps = 720
	for i = 1, steps do
		local a = i / steps * 2 * math.pi
		local x = math.floor(n / 2 - 0.5 + 20 * math.cos(a) + 0.5)
		local y = math.floor(n / 2 - 0.5 + 20 * math.sin(a) + 0.5)
		local lit = alpha(x, y) > 0
		if lit ~= last then
			changes += 1
		end
		last = lit
	end
	T.expect(changes >= 30 and changes <= 34, "about 32 sector edges round the ring, got " .. changes)
	-- alpha only takes the stepped values, and fades outwards along a lit ray
	local seen = {}
	for i = 0, n * n - 1 do
		seen[buffer.readu8(pixels, i * 4 + 3)] = true
	end
	for a in seen do
		local ok = a == 0
		for s = 1, FrameArt.SUNBURST_STEPS do
			ok = ok or a == math.floor(s / FrameArt.SUNBURST_STEPS * 255 + 0.5)
		end
		T.expect(ok, "stepped alpha, got " .. a)
	end
	-- no rays in the middle; full alpha just outside the hole, a quarter near the edge, in the colour asked for
	T.equal(alpha(n // 2, n // 2), 0)
	local strongest, faintest = 0, 255
	for i = 0, n * n - 1 do
		local a = buffer.readu8(pixels, i * 4 + 3)
		if a > 0 then
			strongest, faintest = math.max(strongest, a), math.min(faintest, a)
			T.equal(buffer.readu8(pixels, i * 4), 0xff)
		end
	end
	T.equal(strongest, 255)
	T.equal(faintest, math.floor(255 / FrameArt.SUNBURST_STEPS + 0.5))
end)

T.test("text widths come from the font's advances: wider text, wider estimate; size scales it", function()
	local TextWidth = require("../src/client/TextWidth")
	T.equal(TextWidth.measure("", 17), 0)
	T.expect(TextWidth.measure("WWW", 17) > TextWidth.measure("iii", 17), "W is wider than i")
	T.expect(
		math.abs(TextWidth.measure("Go", 34) - 2 * TextWidth.measure("Go", 17)) < 1e-6,
		"twice the size, twice as wide"
	)
	-- Fredoka One 30 "YOU WIN!" measures about 140 px in its font file
	local w = TextWidth.measure("YOU WIN!", 30)
	T.expect(w > 130 and w < 150, "YOU WIN! at 30 px: " .. w)
	T.expect(TextWidth.measure("Peace with Zephyr", 15, "body") > 100, "body text has its own widths")
	-- kerning: "CATACLYSM!" measures about 182 px at 30 in the font file (AT, TA, LY pull letters together)
	local kerned = TextWidth.measure("CATACLYSM!", 30)
	T.expect(kerned > 178 and kerned < 186, "CATACLYSM! at 30 px, kerned: " .. kerned)
end)

T.finish()
