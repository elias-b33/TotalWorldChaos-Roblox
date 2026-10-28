--!nocheck
-- Paints every race's five troops at the sizes the game shows them, so the rosters can be checked by eye
-- (docs/DESIGN.md "Troops"): per race, a row with its icon, name and bonus, then one cell per troop in role order
-- (line, ranged, fast, elite, special): its icon at 16 and 32 px on the UI's navy, its soldier token at 18 px (as on
-- the map) and 36 px on its map's ground in a nation's colours, its name, role, price and numbers, and a special's
-- trick.
--
--   lune run tools/harness/troop_sheet        # -> tools/harness/out/gui/troops.png

local fs = require("@lune/fs")
local process = require("@lune/process")

local CosmeticArt = require("../../src/client/CosmeticArt")
local IconArt = require("../../src/client/IconArt")
local Maps = require("../../src/shared/Maps")
local Races = require("../../src/shared/Sim/Races")
local Troops = require("../../src/shared/Sim/Troops")

local OUT = "tools/harness/out/gui"
local ROW = 112
local HEAD = 150 -- the race's column
local CELL = 240 -- one troop
local W = HEAD + 5 * CELL + 6
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
	for r, race in Races.forMap(map.id) do
		local y0 = row * ROW + 4
		-- the race
		fill(0, y0, HEAD - 4, ROW - 4, NAVY)
		local icon = IconArt.paint(string.lower(race))
		blit(icon, 16, 16, 6, y0 + 6, 2)
		label(44, y0 + 8, Races.name(race))
		label(44, y0 + 22, map.title)
		label(6, y0 + 44, Races.passive(race) or "")
		label(6, y0 + 58, Races.bonusText(race))
		-- its five troops
		for i, troop in Troops.roster(race) do
			local t = Troops.stats(troop)
			local x0 = HEAD + (i - 1) * CELL
			fill(x0, y0, CELL - 4, 46, NAVY)
			local pixels = IconArt.paint(Troops.icon(troop))
			blit(pixels, 16, 16, x0 + 6, y0 + 7, 2)
			blit(pixels, 16, 16, x0 + 44, y0 + 23, 1)
			fill(x0, y0 + 46, CELL - 4, ROW - 50, GROUND[map.theme])
			local colours = NATIONS[(r % 2) + 1]
			local soldier = CosmeticArt.soldier(troop, colours[1], colours[2])
			blit(soldier, 12, 12, x0 + 6, y0 + 52, 3)
			blit(soldier, 12, 12, x0 + 48, y0 + 70, 1.5)
			label(x0 + 66, y0 + 4, t.name)
			label(x0 + 66, y0 + 18, t.role .. if t.fast then " · fast" else "")
			label(
				x0 + 76,
				y0 + 50,
				string.format(
					"%dg %s mp up %s",
					t.gold,
					if t.manpower % 1000 == 0 then (t.manpower // 1000) .. "k" else tostring(t.manpower),
					tostring(t.upkeep)
				)
			)
			label(x0 + 76, y0 + 64, string.format("att %s  def %s", tostring(t.attack), tostring(t.defence)))
			local trick = Troops.trickText(troop)
			if trick ~= "" then
				label(x0 + 76, y0 + 80, trick)
			end
		end
		row += 1
	end
end

fs.writeDir(OUT)
fs.writeFile(OUT .. "/troops.rgba", buffer.tostring(sheet))
fs.writeFile(OUT .. "/troops.txt", table.concat(labels, "\n"))
local script = string.format(
	[[
from PIL import Image, ImageDraw
img = Image.frombytes("RGBA", (%d, %d), open("%s/troops.rgba", "rb").read())
d = ImageDraw.Draw(img)
for line in open("%s/troops.txt").read().split("\n"):
    x, y, text = line.split("\t", 2)
    d.text((int(x), int(y)), text, fill=(255, 255, 255))
img.save("%s/troops.png")
]],
	W,
	H,
	OUT,
	OUT,
	OUT
)
local r = process.exec("python3", { "-c", script })
fs.removeFile(OUT .. "/troops.rgba")
fs.removeFile(OUT .. "/troops.txt")
if not r.ok then
	error(r.stderr)
end
print("wrote " .. OUT .. "/troops.png")
