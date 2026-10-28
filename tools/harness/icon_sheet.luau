--!nocheck
-- Paints every UI pixel icon (src/client/IconArt.luau) into one sheet, at 1× and 4×, on the UI's navy and on
-- white, so they can be checked by eye:
--
--   lune run tools/harness/icon_sheet        # -> tools/harness/out/gui/icons.png

local fs = require("@lune/fs")
local process = require("@lune/process")

local IconArt = require("../../src/client/IconArt")

local OUT = "tools/harness/out/gui"
local names = IconArt.names()
local COLS = 10
local SCALE = 4
local CELL = 16 * SCALE + 8
local LABEL = 14
local rows = math.ceil(#names / COLS)
local w = COLS * CELL * 2 + 16
local h = rows * (CELL + LABEL) + 8
local sheet = buffer.create(w * h * 4)

local function put(x: number, y: number, rgba: number)
	if x >= 0 and y >= 0 and x < w and y < h then
		buffer.writeu32(sheet, (y * w + x) * 4, rgba)
	end
end

local NAVY = 0xff462b1c -- RGBA bytes of #1c2b46... little-endian ABGR
local WHITE = 0xffffffff
for y = 0, h - 1 do
	for x = 0, w - 1 do
		put(x, y, if x < w / 2 then 0xff46231c else WHITE)
	end
end

for i, name in names do
	local pixels = IconArt.paint(name)
	local col, row = (i - 1) % COLS, (i - 1) // COLS
	for half = 0, 1 do
		local ox = half * (COLS * CELL + 16) + col * CELL + 4
		local oy = row * (CELL + LABEL) + 4
		for py = 0, 15 do
			for px = 0, 15 do
				local v = buffer.readu32(pixels, (py * 16 + px) * 4)
				if bit32.rshift(v, 24) > 0 then
					for sy = 0, SCALE - 1 do
						for sx = 0, SCALE - 1 do
							put(ox + px * SCALE + sx, oy + py * SCALE + sy, v)
						end
					end
				end
			end
		end
	end
end
local _ = NAVY

fs.writeDir(OUT)
fs.writeFile(OUT .. "/icons.rgba", buffer.tostring(sheet))
fs.writeFile(OUT .. "/icons.txt", table.concat(names, "\n"))
local script = string.format(
	[[
from PIL import Image, ImageDraw
img = Image.frombytes("RGBA", (%d, %d), open("%s/icons.rgba", "rb").read())
d = ImageDraw.Draw(img)
names = open("%s/icons.txt").read().split("\n")
for i, n in enumerate(names):
    col, row = i %% %d, i // %d
    for half in (0, 1):
        x = half * (%d * %d + 16) + col * %d + 4
        y = row * (%d + %d) + 4 + %d + 2
        d.text((x, y - 6), n, fill=(255, 255, 255) if half == 0 else (0, 0, 0))
img.save("%s/icons.png")
]],
	w,
	h,
	OUT,
	OUT,
	COLS,
	COLS,
	COLS,
	CELL,
	CELL,
	CELL,
	LABEL,
	16 * SCALE,
	OUT
)
local r = process.exec("python3", { "-c", script })
fs.removeFile(OUT .. "/icons.rgba")
fs.removeFile(OUT .. "/icons.txt")
if not r.ok then
	error(r.stderr)
end
print("wrote " .. OUT .. "/icons.png (" .. #names .. " icons)")
