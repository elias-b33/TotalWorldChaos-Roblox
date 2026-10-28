--!strict
-- What the map's badges say and where they stand (docs/DESIGN.md "Map rendering"), worked out without Roblox so it
-- runs under Lune: the pixel icon for an army's state or its main troop type, the short form of its size, a
-- province's status pills (its battle or siege, then Primordial-power effects with their seconds left), where armies
-- resting in one province stand and how their strength badges stack above them, and the development pips painted as
-- a small segmented bar; a fleet's badge (its state or the ship, its ships and the men aboard) and the blockade
-- marker on a coast (docs/DESIGN.md "Navies"). src/client/MapRenderer.luau puts all of it on screen.

local IconArt = require("./IconArt")

local MapBadges = {}

-- One pill in a province's status row: a pixel icon (IconArt) and a short text ("" for an icon alone).
export type Pill = { icon: string, text: string }

MapBadges.PIP_CELL = 3 -- a development pip's inside, in pixels (each cell has a 1-pixel outline shared with the next)

-- The troop type an army is mostly made of (docs/DESIGN.md "Troops"): the one with the most men. A tie goes to the
-- dearer troop (`cost`: gold per regiment), then to the later one in `order` (Troops.LIST, where the elites come
-- last). nil for an empty composition. `troops` is men per troop type (Types.Composition).
function MapBadges.mainTroop(troops: { [string]: number }, order: { string }, cost: (string) -> number): string?
	local best: string? = nil
	local bestMen, bestCost = 0, -math.huge
	for _, troop in order do
		local men = troops[troop] or 0
		if men > 0 then
			local c = cost(troop)
			if men > bestMen or (men == bestMen and c >= bestCost) then
				best, bestMen, bestCost = troop, men, c
			end
		end
	end
	return best
end

-- The icon on an army's strength badge: Rebels, a garrison, a battle or a retreat first, else `troopIcon`, the icon
-- of the troop type it is mostly made of (MapBadges.mainTroop, as the map draws it: Sim.Troops.icon), or a sword
-- without one.
function MapBadges.armyIcon(
	rebel: boolean,
	neutral: boolean,
	inBattle: boolean,
	retreating: boolean,
	troopIcon: string?
): string
	if rebel then
		return "rebels"
	elseif neutral then
		return "shield"
	elseif inBattle then
		return "battle"
	elseif retreating then
		return "retreat"
	elseif troopIcon then
		return troopIcon
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

-- The icon on a fleet's strength badge: a burst in a sea battle, the white flag while it retreats, else the ship.
function MapBadges.fleetIcon(inBattle: boolean, retreating: boolean): string
	if inBattle then
		return "battle"
	elseif retreating then
		return "retreat"
	end
	return "ship"
end

-- A fleet's badge text: its ships, then the men aboard when it carries any ("3", "3 · 2k").
function MapBadges.fleetText(ships: number, men: number): string
	if men > 0 then
		return ships .. " · " .. MapBadges.shortMen(men)
	end
	return tostring(ships)
end

-- A power's shield is the glowing power shield; the plain shield marks neutral garrisons.
local EFFECT_ICONS: { [string]: string } = { shield = "powerShield" }

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

-- A province's status pills, left to right: the battle, or the siege's progress in percent, an anchor while an
-- enemy fleet blockades it, then the power effects. `brief` keeps only the icons (zoomed out, on provinces that
-- aren't yours).
function MapBadges.status(
	battle: boolean,
	siegePercent: number?,
	effects: string?,
	brief: boolean,
	blockaded: boolean?
): { Pill }
	local out: { Pill } = {}
	if battle then
		table.insert(out, { icon = "battle", text = "" })
	elseif siegePercent then
		table.insert(out, { icon = "hourglass", text = siegePercent .. "%" })
	end
	if blockaded then
		table.insert(out, { icon = "anchor", text = "" })
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
