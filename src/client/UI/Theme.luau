--!strict
-- The UI's design tokens (docs/DESIGN.md "UI style"): the "pixel kingdom" look that sits on WorldBox's map.
-- Chunky navy panels with a 2 px ink outline and a bevel, warm gold accents, buttons with a darker bottom edge
-- that press down, Fredoka One for titles and numbers, Builder Sans for everything else. Every screen takes its
-- colours, fonts, sizes and spacing from here (through Widgets), never its own.

local Theme = {}

local hex = Color3.fromHex

Theme.color = {
	ink = hex("#0b0d1a"), -- outlines around panels, buttons and chips
	navy = hex("#1d2448"), -- panels and sheets
	navyDeep = hex("#12172f"), -- the top bar, wells, chips and full-screen backdrops
	navyRaised = hex("#2a3366"), -- cards inside a panel
	gold = hex("#f5c242"), -- titles, highlights, the selected tab
	goldDeep = hex("#b67f24"),
	goldPale = hex("#ffe9a6"),
	text = hex("#fff7e3"), -- warm white body text
	textDim = hex("#b6bcdc"), -- hints and secondary lines
	textDark = hex("#2b1d0c"), -- text on gold
	primary = hex("#3d7ce0"), -- the main button colour (blue)
	good = hex("#3aa856"), -- confirm, accept, go (green)
	danger = hex("#d9434b"), -- war, leave, destructive (red)
	secondary = hex("#4a5385"), -- cancel and neutral options (slate)
	disabled = hex("#353a57"), -- can't be pressed now
	textDisabled = hex("#8a8fb0"),
	special = hex("#8a4fd8"), -- Primordial powers (purple)
	warn = hex("#ff7a6e"), -- negative numbers
}

Theme.font = {
	display = Font.fromEnum(Enum.Font.FredokaOne), -- titles, buttons, numbers
	body = Font.fromEnum(Enum.Font.BuilderSansBold), -- labels and lines
	bodyLight = Font.fromEnum(Enum.Font.BuilderSansMedium), -- hints
}

-- Type scale in px: nothing under 14 on a phone (docs/DESIGN.md "Rules for every screen").
Theme.text = {
	hero = 28, -- full-screen titles (map vote, results)
	title = 22, -- panel titles
	heading = 18, -- sheet titles, big numbers
	body = 15,
	small = 14,
}

Theme.space = { xs = 4, s = 6, m = 8, l = 12, xl = 16 }
Theme.radius = { s = 4, m = 6, l = 8 }
Theme.stroke = 2 -- every outline is 2 px
Theme.bevel = 0.16 -- the darker bottom edge of buttons, as a share of their height

Theme.size = {
	button = 44, -- the smallest touch target
	buttonLarge = 48,
	icon = 20, -- icons beside text
	iconButton = 24, -- icons inside buttons
	iconLarge = 32,
	chip = 30,
	bar = 44, -- the HUD's top bar
}

return Theme
