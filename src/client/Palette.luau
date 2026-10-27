--!strict
-- Nation colours by Nation.colorIndex (docs/MAPS.md "Art direction"), plus colours for unowned land.

local nations: { Color3 } = {
	Color3.fromHex("#d7263d"), -- 1 crimson
	Color3.fromHex("#1e6fd9"), -- 2 royal blue
	Color3.fromHex("#f4c430"), -- 3 gold
	Color3.fromHex("#8e44ad"), -- 4 violet
	Color3.fromHex("#f17c1f"), -- 5 orange
	Color3.fromHex("#17b8b8"), -- 6 teal
	Color3.fromHex("#e84aa6"), -- 7 magenta
	Color3.fromHex("#7ac943"), -- 8 lime
	Color3.fromHex("#8b5a2b"), -- 9 bronze
	Color3.fromHex("#3c3c46"), -- 10 charcoal
}

-- Neutral provinces show their terrain, washed out so nation colours stay the loudest thing on the map.
local neutral: { [string]: Color3 } = {
	Plains = Color3.fromHex("#d9d4bf"),
	Forest = Color3.fromHex("#aebfa0"),
	Hills = Color3.fromHex("#c7b79a"),
	Mountain = Color3.fromHex("#6b6b73"),
}

-- Under the map, by MapDef.theme.
local background: { [string]: Color3 } = {
	earth = Color3.fromHex("#1a4d74"),
	fantasy = Color3.fromHex("#1683ad"),
	sky = Color3.fromHex("#2b3477"),
}

local Palette = {
	nations = nations,
	neutral = neutral,
	background = background,
	link = Color3.fromHex("#f2efe6"),
	strait = Color3.fromHex("#ffffff"),
}

function Palette.nation(colorIndex: number): Color3
	return nations[colorIndex] or neutral.Plains
end

return Palette
