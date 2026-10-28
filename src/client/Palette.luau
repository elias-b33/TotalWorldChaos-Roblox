--!strict
-- Nation colours by Nation.colorIndex (docs/MAPS.md "Art direction"), and the few fixed colours of the 2D map.

-- WorldBox's kingdom colours: each nation's main colour and the darker border colour WorldBox pairs with it.
-- Blues and cyans close to the sea are left out.
local nations: { Color3 } = {
	Color3.fromHex("#e6194b"), -- 1 red
	Color3.fromHex("#6c89f6"), -- 2 blue
	Color3.fromHex("#ffe119"), -- 3 yellow
	Color3.fromHex("#911eb4"), -- 4 purple
	Color3.fromHex("#f58231"), -- 5 orange
	Color3.fromHex("#469990"), -- 6 teal
	Color3.fromHex("#f032e6"), -- 7 magenta
	Color3.fromHex("#3cd74b"), -- 8 green
	Color3.fromHex("#9a6324"), -- 9 brown
	Color3.fromHex("#353535"), -- 10 charcoal
}

local borders: { Color3 } = {
	Color3.fromHex("#97233d"),
	Color3.fromHex("#517aa8"),
	Color3.fromHex("#beab23"),
	Color3.fromHex("#75298a"),
	Color3.fromHex("#b76c33"),
	Color3.fromHex("#145a4f"),
	Color3.fromHex("#b436ab"),
	Color3.fromHex("#47b052"),
	Color3.fromHex("#7b572a"),
	Color3.fromHex("#2d2e2b"),
}

-- Around the map, by MapDef.theme: WorldBox's deep ocean, or space for Skyshards (PixelArt paints the same).
local background: { [string]: Color3 } = {
	earth = Color3.fromHex("#3370cc"),
	fantasy = Color3.fromHex("#3370cc"),
	sky = Color3.fromHex("#05003f"),
}

local Palette = {
	nations = nations,
	background = background,
	garrison = Color3.fromHex("#9a9aa2"), -- neutral garrison tokens
	rebel = Color3.fromHex("#1c1c1c"), -- Rebels' tokens: a black flag...
	rebelEdge = Color3.fromHex("#ff3b30"), -- ...with a red edge, so they never pass for the charcoal nation
	strait = Color3.fromHex("#ffffff"), -- sea lanes
	energyLink = Color3.fromHex("#7cfbef"), -- Skyshards' bridges between platforms
	zoneName = Color3.fromHex("#a9cdf5"), -- sea and space zone names: a soft sea blue, quieter than province names
	-- Effects' pixel particles (src/client/Effects.luau): WorldBox-like dust, fire, plague, gold and shield colours
	fx = {
		white = Color3.fromHex("#ffffff"),
		dust = Color3.fromHex("#c8b48a"),
		dustGrey = Color3.fromHex("#9a9aa2"),
		steel = Color3.fromHex("#e8e8f0"),
		hilt = Color3.fromHex("#9a6324"),
		bone = Color3.fromHex("#f4f1e6"),
		ink = Color3.fromHex("#151515"),
		fireYellow = Color3.fromHex("#ffe119"),
		fireOrange = Color3.fromHex("#f58231"),
		fireRed = Color3.fromHex("#e6194b"),
		smoke = Color3.fromHex("#5b5e5c"),
		crater = Color3.fromHex("#333333"),
		earth = Color3.fromHex("#7b572a"),
		crack = Color3.fromHex("#2a1d14"),
		plague = Color3.fromHex("#8bd14a"),
		plagueDark = Color3.fromHex("#5a8f2e"),
		plagueLight = Color3.fromHex("#c6f07a"),
		pole = Color3.fromHex("#5b4a3a"),
		gold = Color3.fromHex("#ffe119"),
		paleGold = Color3.fromHex("#fff6a8"),
		shield = Color3.fromHex("#7cc4ff"),
		shieldDeep = Color3.fromHex("#3f8fe0"),
	},
}

function Palette.nation(colorIndex: number): Color3
	return nations[colorIndex] or Palette.garrison
end

-- The nation's border colour on the map.
function Palette.border(colorIndex: number): Color3
	return borders[colorIndex] or Palette.garrison
end

return Palette
