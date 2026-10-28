--!strict
-- What the map's badges say and where they stand (docs/DESIGN.md "Map rendering"), worked out without Roblox so it
-- runs under Lune: the pixel icon for an army's state, the short form of its size, a province's status pills (its
-- battle or siege, then Primordial-power effects with their seconds left), where armies resting in one province
-- stand and how their strength badges stack above them, and the development pips painted as a small segmented bar.
-- src/client/MapRenderer.luau puts all of it on screen.

local IconArt = require("./IconArt")

local MapBadges = {}

-- One pill in a province's status row: a pixel icon (IconArt) and a short text ("" for an icon alone).
export type Pill = { icon: string, text: string }

MapBadges.PIP_CELL = 3 -- a development pip's inside, in pixels (each cell has a 1-pixel outline shared with the next)

-- The icon on an army's strength badge, the same ones the province sheet's chips use.
function MapBadges.armyIcon(rebel: boolean, neutral: boolean, inBattle: boolean, retreating: boolean): string
	if rebel then
		return "rebels"
	elseif neutral then
		return "shield"
	elseif inBattle then
		return "battle"
	elseif retreating then
		return "retreat"
	end
	return "sword"
end

-- An army's size as the badge shows it: "800", "3k", "3.7k", "12.3k".
function MapBadges.shortMen(men: number): string
	if men >= 1000 then
		return string.format("%gk", math.floor(men / 100) / 10)
	end
	return tostring(men)
end

-- A power's shield is the divine shield; the plain shield marks neutral garrisons.
local EFFECT_ICONS: { [string]: string } = { shield = "divineShield" }

-- The badge text Powers hands to MapRenderer.setEffect, as pills: each word is a power's emoji with the seconds it has
-- left ("🛡️25 🌟30"), or a strike's emoji alone ("☄️"). Words without a known emoji are left out.
function MapBadges.effects(text: string): { Pill }
	local out: { Pill } = {}
	for word in string.gmatch(text, "%S+") do
		local icon, rest = IconArt.split(word)
		if icon then
			table.insert(out, { icon = EFFECT_ICONS[icon] or icon, text = rest })
		end
	end
	return out
end

-- A province's status pills, left to right: the battle, or the siege's progress in percent, then the power effects.
-- `brief` keeps only the icons (zoomed out, on provinces that aren't yours).
function MapBadges.status(battle: boolean, siegePercent: number?, effects: string?, brief: boolean): { Pill }
	local out: { Pill } = {}
	if battle then
		table.insert(out, { icon = "battle", text = "" })
	elseif siegePercent then
		table.insert(out, { icon = "hourglass", text = siegePercent .. "%" })
	end
	for _, pill in MapBadges.effects(effects or "") do
		table.insert(out, pill)
	end
	if brief then
		for _, pill in out do
			pill.text = ""
		end
	end
	return out
end

-- Armies resting in one province stand side by side, `spacing` screen pixels apart and centred on the province:
-- the screen x offset of the one in `slot` (1 to `count`).
function MapBadges.slotOffset(slot: number, count: number, spacing: number): number
	return (slot - (count + 1) / 2) * spacing
end

-- How far above the province's anchor the status row stands, in screen pixels: over the token, a gap, and the
-- strength badges shown in that province (each `row` pixels tall with its gap).
function MapBadges.statusLift(tokenHalf: number, gap: number, badgesShown: number, row: number): number
	return tokenHalf + gap + badgesShown * row
end

local function rgba(c: number): number
	local r, g, b = bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255)
	return 255 * 16777216 + b * 65536 + g * 256 + r
end

-- Development pips as a segmented bar in the icons' palette: `filled` gold cells out of `total`, the rest dark, all in
-- one dark outline. Returns (RGBA buffer, width, height), ready for EditableImage:WritePixelsBuffer.
function MapBadges.pips(filled: number, total: number): (buffer, number, number)
	local inside = MapBadges.PIP_CELL
	local cell = inside + 1
	local w, h = cell * total + 1, inside + 2
	local p = IconArt.PALETTE
	local outline, gold, light, deep, empty = rgba(p.K), rgba(p.Y), rgba(p.y), rgba(p.O), rgba(p.d)
	local out = buffer.create(w * h * 4)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local cx = x % cell -- 0 on the outline between cells, 1..inside within a cell
			local colour = outline
			if cx ~= 0 and y ~= 0 and y ~= h - 1 then
				if x // cell < filled then
					-- a gold cell, lit from the top left like the icons
					colour = if cx == 1 and y == 1 then light elseif cx == inside or y == inside then deep else gold
				else
					colour = empty
				end
			end
			buffer.writeu32(out, (y * w + x) * 4, colour)
		end
	end
	return out, w, h
end

return MapBadges
