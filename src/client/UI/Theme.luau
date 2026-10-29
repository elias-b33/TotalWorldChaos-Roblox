--!strict
-- The UI's design tokens (docs/UI_DIRECTION.md "Slate & Brass", docs/DESIGN.md "UI style"): slate panels with a lit
-- edge, iron bands on in-match sheets and brass on reward and meta screens, enamel buttons on a thick base,
-- recessed wells, all painted on the map's 2 px pixel grid (FrameArt). Colour encodes role: gold for the one
-- primary action, emerald for confirm and buy, crimson for war and close, azure for diplomacy and info, royal for
-- Primordial and season content, slate for everything secondary. Fredoka One for titles, numbers and captions
-- (outlined in ink), Builder Sans for body text. Every screen takes its colours, fonts, sizes and spacing from here
-- (through Widgets), never its own.

local Theme = {}

local hex = Color3.fromHex

Theme.color = {
	ink = hex("#0b0d1a"), -- every outline, text strokes, shadows
	slate950 = hex("#0e111c"), -- full-screen dims (at 40% transparency)
	slate900 = hex("#141927"), -- well fill
	slate850 = hex("#191f30"), -- well light edge, panel bottom shade
	slate800 = hex("#1e2538"), -- panel fill
	slate700 = hex("#283149"), -- raised cards, slot tile faces, panel lip
	slate600 = hex("#36415f"), -- lit plate edges, dividers
	slate500 = hex("#4c5878"), -- raised plate edges
	slate400 = hex("#6b7799"), -- muted icons on slate
	slate300 = hex("#98a2c0"), -- section labels, minor numbers
	brass100 = hex("#fff1b8"),
	brass200 = hex("#ffe08a"),
	brass300 = hex("#f6c453"),
	brass400 = hex("#e0a23a"),
	brass500 = hex("#b8752a"),
	brass600 = hex("#7e4a1e"),
	iron200 = hex("#c9d1e0"),
	iron400 = hex("#8f9ab3"),
	iron500 = hex("#5f6a85"),
	iron600 = hex("#3d4660"),
	text = hex("#fff6e0"), -- body and captions (warm white)
	textDim = hex("#aeb6d0"), -- hints, secondary lines
	textDark = hex("#2a1a08"), -- text on gold
	textDisabled = hex("#8a91ad"), -- disabled captions
	gold = hex("#f4bf45"), -- the primary button, gold text and highlights, selection
	emerald = hex("#41b54a"), -- confirm, accept, go, Robux prices, claim, equip
	crimson = hex("#d8453e"), -- war, close, leave, danger
	azure = hex("#3a85de"), -- diplomacy (ally), info, the trophies button
	royal = hex("#8a52da"), -- Primordial powers, season pass
	slate = hex("#4a5576"), -- secondary buttons: cancel, not now, pager, top-bar icon buttons
	disabled = hex("#3a4157"), -- can't be pressed now
	peace = hex("#55c35a"), -- phase medallions
	war = hex("#e0483f"),
	cataclysm = hex("#9a5bea"),
	negative = hex("#ff6b5e"), -- negative gold, unaffordable costs
	positive = hex("#8bea7c"), -- gains
	-- the "pixel kingdom" names, kept as aliases while screens migrate
	navy = hex("#1e2538"), -- slate800
	navyDeep = hex("#141927"), -- slate900
	navyRaised = hex("#283149"), -- slate700
	goldDeep = hex("#b8752a"), -- brass500
	goldPale = hex("#ffe08a"), -- brass200
	primary = hex("#3a85de"), -- azure
	good = hex("#41b54a"), -- emerald
	danger = hex("#d8453e"), -- crimson
	secondary = hex("#4a5576"), -- slate
	special = hex("#8a52da"), -- royal
	warn = hex("#ff6b5e"), -- negative
}

Theme.font = {
	display = Font.fromEnum(Enum.Font.FredokaOne), -- titles, buttons, numbers
	body = Font.fromEnum(Enum.Font.BuilderSansBold), -- labels and lines
	bodyLight = Font.fromEnum(Enum.Font.BuilderSansMedium), -- hints
	label = Font.fromEnum(Enum.Font.BuilderSansExtraBold), -- section labels, rarity tags (uppercase)
}

-- Type scale in px: nothing under 14 on a phone (docs/DESIGN.md "Rules for every screen").
Theme.text = {
	ribbon = 30, -- hero text on ribbons: the phase banners and the Results headline
	hero = 28, -- full-screen titles (map vote)
	title = 20, -- title plates
	heading = 18, -- sheet titles, big numbers
	button = 17, -- button captions (16 or 15 when dense)
	body = 15,
	small = 14,
}

Theme.space = { xs = 4, s = 6, m = 8, l = 12, xl = 16 }
Theme.radius = { s = 4, m = 6, l = 8 }
Theme.stroke = 2 -- every outline is 2 px
Theme.bevel = 0.16 -- the flat look's darker bottom edge on buttons, as a share of their height
Theme.art = 2 -- GUI px per art pixel: frames are drawn at SliceScale 2, so sizes and positions are even

-- Icons only at 1x, 2x and 3x of the 16×16 sprites: 16 beside text, 32 on buttons, tabs, tiles and counters, 48
-- in reward cells and heroes.
Theme.icon = { small = 16, medium = 32, large = 48 }

Theme.size = {
	button = 44, -- the smallest touch target
	buttonLarge = 52, -- slot tiles and large actions
	icon = 16, -- icons beside text
	iconButton = 32, -- icons alone on a button
	iconLarge = 48, -- reward cells and heroes
	chip = 28,
	counter = 32,
	bar = 44, -- the HUD's plates
	titlePlate = 28,
}

-- Window frames: the painted border's thickness and the content padding inside it (docs/UI_DIRECTION.md 7.1).
Theme.frame = {
	border = { left = 12, right = 10, top = 14, bottom = 12 },
	pad = { side = 16, top = 22, topBare = 18, bottom = 14 },
}

-- Depth (docs/UI_DIRECTION.md 6.6): hard pixel shadows under plates and windows, glows under rare things.
Theme.shadow = {
	plate = { y = 4, transparency = 0.55 }, -- plates over the map: top-bar items, toasts, Lobby buttons
	button = { y = 3, transparency = 0.6 }, -- buttons over the map
	window = { y = 6, transparency = 0.5 }, -- windows and sheets
	title = { y = 3, transparency = 0.5 }, -- title plates on a window's edge
	counter = { y = 3, transparency = 0.65 }, -- the top bar's counters and chips
	glow = { blur = 12, transparency = 0.45 }, -- rare shop cards, claimable rewards
}

-- The Results window (docs/UI_DIRECTION.md 7.13) hangs from a line near the top of the screen with its gold ribbon
-- centred on it; Effects' MATCH OVER banner pops on the same line, as wide, and leaves the ribbon under it.
Theme.results = { ribbonY = 36, ribbonWidth = 340 }

-- Tablets (docs/STUDIO.md "UI kit"): the whole UI grows with the screen's short side, so a sheet or the top bar is
-- as big in the hand on an iPad as on a phone. Phones (short side under `phone`) stay at exactly 1; bigger screens
-- get short side / `base`, at most `max` (an iPad Air in landscape, 820 px: 1.26; an iPad Pro, 1024 px: 1.4).
Theme.tablet = { phone = 600, base = 650, max = 1.4 }

-- The UI's scale on a screen of this size (GUI px).
function Theme.uiScale(screen: Vector2): number
	local short = math.min(screen.X, screen.Y)
	if short < Theme.tablet.phone then
		return 1
	end
	return math.clamp(short / Theme.tablet.base, 1, Theme.tablet.max)
end

-- Cosmetic rarities (shop cards, season pass reward cells): the frame band, the tag and the glow.
Theme.rarity = {
	Common = hex("#b9c1d9"),
	Rare = hex("#4fa3ff"),
	Epic = hex("#b36ff2"),
	Legendary = hex("#ffa53a"),
} :: { [string]: Color3 }

return Theme
