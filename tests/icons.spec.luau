--!strict
-- The UI's pixel icons (src/client/IconArt.luau, docs/DESIGN.md "UI style"): every icon is a clean 16×16 grid in
-- the shared palette, stands out on the navy panels, has an emoji fallback, and the whole set stays small.
local IconArt = require("../src/client/IconArt")
local T = require("./TestKit")

local NAVY = 0x1d2448 -- Theme.color.navy, the panels icons sit on

-- The icons the UI kit promises (docs/DESIGN.md "UI style").
local REQUIRED = {
	"gold",
	"manpower",
	"crown",
	"sword",
	"shield",
	"star",
	"globe",
	"clock",
	"peace",
	"war",
	"skull",
	"flag",
	"castle",
	"scroll",
	"cart",
	"soundOn",
	"soundOff",
	"gear",
	"trophy",
	"medal",
	"fire",
	"charge",
	"sparkles",
	"meteor",
	"plague",
	"rebels",
	"earthquake",
	"blessing",
	"divineShield",
	"close",
	"check",
	"arrow",
}

local function luminance(c: number): number
	local r, g, b = bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
	return 0.299 * r + 0.587 * g + 0.114 * b
end

T.test("every promised icon exists", function()
	for _, name in REQUIRED do
		T.expect(IconArt.rows(name) ~= nil, "missing icon " .. name)
	end
	T.expect(#IconArt.names() >= 30, "about 30 icons or more")
end)

T.test("every icon is a 16×16 grid in the shared palette, with an outline", function()
	for _, name in IconArt.names() do
		local rows = IconArt.rows(name) :: { string }
		T.equal(#rows, IconArt.SIZE, name .. " rows")
		local outline, opaque = 0, 0
		for y, row in rows do
			T.equal(#row, IconArt.SIZE, string.format("%s row %d width", name, y))
			for x = 1, #row do
				local ch = string.sub(row, x, x)
				T.expect(ch == "." or IconArt.PALETTE[ch] ~= nil, string.format("%s has unknown code %q", name, ch))
				if ch ~= "." then
					opaque += 1
				end
				if ch == "K" then
					outline += 1
				end
			end
		end
		T.expect(outline > 0, name .. " has an outline")
		T.expect(opaque >= 30, name .. " is big enough to read")
	end
end)

T.test("every icon stands out on the navy panels", function()
	local navy = luminance(NAVY)
	for _, name in IconArt.names() do
		local bright, opaque = 0, 0
		for _, row in IconArt.rows(name) :: { string } do
			for x = 1, #row do
				local colour = IconArt.PALETTE[string.sub(row, x, x)]
				if colour then
					opaque += 1
					if math.abs(luminance(colour) - navy) >= 60 then
						bright += 1
					end
				end
			end
		end
		T.expect(bright >= opaque * 0.25, string.format("%s: only %d of %d pixels show on navy", name, bright, opaque))
	end
end)

T.test("paint gives 16×16 RGBA, transparent where the grid is empty", function()
	local pixels, w, h = IconArt.paint("gold")
	T.equal(w, 16)
	T.equal(h, 16)
	T.equal(buffer.len(pixels), 16 * 16 * 4)
	T.equal(buffer.readu32(pixels, 0), 0, "the corner is transparent")
	-- the coin's outline at (5, 2) is K = 0x1b1426: bytes R, G, B, A
	local i = (2 * 16 + 5) * 4
	T.equal(buffer.readu8(pixels, i), 0x1b)
	T.equal(buffer.readu8(pixels, i + 1), 0x14)
	T.equal(buffer.readu8(pixels, i + 2), 0x26)
	T.equal(buffer.readu8(pixels, i + 3), 255)
	local blank = IconArt.paint("no-such-icon")
	for k = 0, 16 * 16 - 1 do
		T.equal(buffer.readu32(blank, k * 4), 0, "unknown icons paint nothing")
	end
end)

T.test("variants recolour their base icon", function()
	local flag, rebels = IconArt.rows("flag") :: { string }, IconArt.rows("rebels") :: { string }
	T.equal(#rebels, #flag)
	T.expect(rebels[4] ~= flag[4], "the rebels flag is not red")
	T.equal(string.find(table.concat(rebels), "R") ~= nil, true, "but keeps a red emblem")
end)

T.test("every icon has an emoji fallback and every emoji maps to an icon", function()
	for _, name in IconArt.names() do
		T.expect(IconArt.FALLBACK[name] ~= nil, name .. " has no fallback")
	end
	for emoji, name in IconArt.EMOJI do
		T.expect(IconArt.rows(name) ~= nil, emoji .. " maps to a missing icon " .. name)
	end
end)

T.test("a leading emoji becomes an icon", function()
	local icon, rest = IconArt.split("⚔ Zephyr declared war on you!")
	T.equal(icon, "war")
	T.equal(rest, "Zephyr declared war on you!")
	icon, rest = IconArt.split("🛡️ Aurora is immune for 30 s") -- with the emoji presentation selector
	T.equal(icon, "shield")
	T.equal(rest, "Aurora is immune for 30 s")
	icon, rest = IconArt.split("+💰50")
	T.equal(icon, nil)
	T.equal(rest, "+💰50")
	icon, rest = IconArt.split("Plain text")
	T.equal(icon, nil)
	T.equal(rest, "Plain text")
	icon = IconArt.split("🫠 unknown emoji")
	T.equal(icon, nil, "an emoji without an icon stays text")
end)

T.test("the whole set is small in memory", function()
	-- each icon is its own 16×16 RGBA EditableImage when shown: 1 KB
	T.expect(#IconArt.names() * 16 * 16 * 4 <= 64 * 1024, "under 64 KB even if every icon is on screen")
end)

T.finish()
