--!nocheck
-- Paints every map's cast at the sizes the game shows it, so new art can be checked by eye (docs/DESIGN.md
-- "Races"): per race, a row with its icon and its elite's icon (16, 20, 24 and 32 px on the UI's navy), its line
-- troop's soldier token (18 px as on the map, and 36 px) in two nation colours, its capital on the whole map (5 × 6 at
-- 1, 3.5 and 8 screen pixels per map pixel) and close up (21 × 22 at 1 and 2.5 screen pixels per sub-pixel), on its
-- map's ground. Every troop of every roster: tools/harness/troop_sheet.luau.
--
--   lune run tools/harness/race_sheet        # -> tools/harness/out/gui/races.png

local fs = require("@lune/fs")
local process = require("@lune/process")

local CosmeticArt = require("../../src/client/CosmeticArt")
local IconArt = require("../../src/client/IconArt")
local Maps = require("../../src/shared/Maps")
local PixelArt = require("../../src/client/PixelArt")
local Races = require("../../src/shared/Sim/Races")
local Troops = require("../../src/shared/Sim/Troops")

local OUT = "tools/harness/out/gui"
local ROW = 96
local W = 1180
local NAVY = 0x1d2448
local GROUND = { earth = 0x81b647, fantasy = 0x8cdc6a, sky = 0x54cc3a }
local NATIONS = { { 0xe6194b, 0x97233d }, { 0x6c89f6, 0x517aa8 } }

local maps = {}
for _, id in Maps.ids do
	table.insert(maps, Maps.get(id))
end
local rows = 0
for _, map in maps do
	rows += #Races.forMap(map.id)
end
local H = rows * ROW + 8
local sheet = buffer.create(W * H * 4)

local function rgba(c: number): number
	local r, g, b = bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
	return 255 * 16777216 + b * 65536 + g * 256 + r
end

local function fill(x0: number, y0: number, w: number, h: number, c: number)
	for y = y0, y0 + h - 1 do
		for x = x0, x0 + w - 1 do
			if x >= 0 and y >= 0 and x < W and y < H then
				buffer.writeu32(sheet, (y * W + x) * 4, rgba(c))
			end
		end
	end
end

-- Blit an RGBA buffer of size (w, h) scaled by `scale` (nearest neighbour: what pixelated resampling shows).
local function blit(pixels: buffer, w: number, h: number, x0: number, y0: number, scale: number)
	local tw, th = math.floor(w * scale + 0.5), math.floor(h * scale + 0.5)
	for ty = 0, th - 1 do
		for tx = 0, tw - 1 do
			local sx, sy = math.min(w - 1, math.floor(tx / scale)), math.min(h - 1, math.floor(ty / scale))
			local v = buffer.readu32(pixels, (sy * w + sx) * 4)
			local x, y = x0 + tx, y0 + ty
			if bit32.rshift(v, 24) > 0 and x >= 0 and y >= 0 and x < W and y < H then
				buffer.writeu32(sheet, (y * W + x) * 4, v)
			end
		end
	end
end

local labels = {}
local function label(x: number, y: number, text: string)
	table.insert(labels, string.format("%d\t%d\t%s", x, y, text))
end

fill(0, 0, W, H, 0x202028)
local row = 0
for _, map in maps do
	for _, race in Races.forMap(map.id) do
		local y0 = row * ROW + 4
		fill(0, y0, 300, ROW - 4, NAVY)
		local elite = Troops.ofRole(race, "elite")
		local x = 6
		for _, name in { string.lower(race), Troops.icon(elite) } do
			local pixels = IconArt.paint(name)
			for _, size in { 16, 20, 24, 32 } do
				blit(pixels, 16, 16, x, y0 + 6 + (32 - size), size / 16)
				x += size + 4
			end
			x += 6
		end
		label(6, y0 + 44, string.format("%s (%s) · %s", Races.name(race), map.title, Troops.name(elite)))
		label(6, y0 + 60, Races.bonusText(race))
		-- its line troop's soldiers on the map's ground
		fill(300, y0, 200, ROW - 4, GROUND[map.theme])
		for i, colours in NATIONS do
			local pixels = CosmeticArt.soldier(Troops.ofRole(race, "line"), colours[1], colours[2])
			blit(pixels, 12, 12, 300 + 8 + (i - 1) * 90, y0 + 30, 1.5)
			blit(pixels, 12, 12, 300 + 36 + (i - 1) * 90, y0 + 12, 3)
		end
		-- the capital: whole map, then close up
		fill(500, y0, 680, ROW - 4, GROUND[map.theme])
		for i, colours in NATIONS do
			local whole, ww, wh, close, cw, ch = PixelArt.capitalArt(map.theme, race, colours[1])
			local cx = 500 + (i - 1) * 340
			blit(whole, ww, wh, cx + 8, y0 + 40, 1)
			blit(whole, ww, wh, cx + 20, y0 + 30, 3.5)
			blit(whole, ww, wh, cx + 46, y0 + 20, 8)
			blit(close, cw, ch, cx + 96, y0 + 34, 1)
			blit(close, cw, ch, cx + 124, y0 + 18, 2.5)
			blit(close, cw, ch, cx + 186, y0 + 4, 4)
		end
		row += 1
	end
end

fs.writeDir(OUT)
fs.writeFile(OUT .. "/races.rgba", buffer.tostring(sheet))
fs.writeFile(OUT .. "/races.txt", table.concat(labels, "\n"))
local script = string.format(
	[[
from PIL import Image, ImageDraw
img = Image.frombytes("RGBA", (%d, %d), open("%s/races.rgba", "rb").read())
d = ImageDraw.Draw(img)
for line in open("%s/races.txt").read().split("\n"):
    x, y, text = line.split("\t", 2)
    d.text((int(x), int(y)), text, fill=(255, 255, 255))
img.save("%s/races.png")
]],
	W,
	H,
	OUT,
	OUT,
	OUT
)
local r = process.exec("python3", { "-c", script })
fs.removeFile(OUT .. "/races.rgba")
fs.removeFile(OUT .. "/races.txt")
if not r.ok then
	error(r.stderr)
end
print("wrote " .. OUT .. "/races.png")
