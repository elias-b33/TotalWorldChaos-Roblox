--!strict
-- Nation colours by Nation.colorIndex (docs/MAPS.md "Art direction"), and the few fixed colours of the 2D map.

local nations: { Color3 } = {
	Color3.fromHex("#d7263d"), -- 1 crimson
	Color3.fromHex("#26358f"), -- 2 navy (clear of the sea's blues)
	Color3.fromHex("#f4c430"), -- 3 gold
	Color3.fromHex("#8e44ad"), -- 4 violet
	Color3.fromHex("#f17c1f"), -- 5 orange
	Color3.fromHex("#17b8b8"), -- 6 teal
	Color3.fromHex("#e84aa6"), -- 7 magenta
	Color3.fromHex("#7ac943"), -- 8 lime
	Color3.fromHex("#8b5a2b"), -- 9 bronze
	Color3.fromHex("#3c3c46"), -- 10 charcoal
}

-- Around the map, by MapDef.theme: the deep sea, or space for Skyshards (PixelArt paints the same colours).
local background: { [string]: Color3 } = {
	earth = Color3.fromHex("#2a5fc4"),
	fantasy = Color3.fromHex("#2470c8"),
	sky = Color3.fromHex("#070a1c"),
}

local Palette = {
	nations = nations,
	background = background,
	garrison = Color3.fromHex("#9a9aa2"), -- neutral garrison tokens
	strait = Color3.fromHex("#ffffff"), -- sea lanes
	energyLink = Color3.fromHex("#3ff0ff"), -- Skyshards' bridges between platforms
}

function Palette.nation(colorIndex: number): Color3
	return nations[colorIndex] or Palette.garrison
end

return Palette
