--!strict
-- The nation draft (Pick phase): the chosen map shows every nation's start territory; players pick a start
-- nation one at a time in a random order. On your turn tap a nation in the list to take it, or tap its land on
-- the map and confirm. A banner says whose turn it is and how long is left. Bots keep the rest.
-- The theme vote's winner is credited at the top of the panel ("🌙 Night Earth, brought by Alice").
-- Picking a nation picks its race (docs/DESIGN.md "Races"): every nation's card shows its race (icon and name), and
-- the nation you tap gets a race card above the Pick button with its one-line bonus.
-- The kit (docs/UI_DIRECTION.md 7.10): whose turn it is on a plate at the top left with the time in a counter
-- under it, the nations as raised slate tiles in an iron panel (the flag, the name in the nation's colour, the race
-- icon; a taken nation dimmed with its player's name; the one you tapped outlined in gold), and "Pick <nation>" as
-- the screen's one gold button. The screen covers Roblox's top-bar row (Widgets.coverScreen): the panel has the
-- whole height, and the turn plate hangs just under the row, clear of Roblox's buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Maps = require(Shared.Maps)

local Client = script.Parent.Parent
local TextWidth = require(Client.TextWidth)
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local MapRenderer = require(Client.MapRenderer)
local Palette = require(Client.Palette)
local RaceInfo = require(Client.RaceInfo)
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local MARGIN = Theme.space.m
local CELL = Vector2.new(144, 44) -- a nation: its flag, two lines ("Ashen Dominion", "Orcs") and its race icon
local CELL_GAP = 6
local PANEL_WIDTH = 2 * CELL.X + CELL_GAP + 2 * Widgets.PANEL_PAD -- two columns of nations inside the frame
local FLAG = Vector2.new(20, 15)
local TILE_TEXT_LEFT = 32 -- the name starts right of the flag
local TILE_TEXT_RIGHT = Theme.space.s -- the race icon sits under the name's end, beside the short second line
local TIMER_WIDTH = 92

-- A nation's name in its colour, lightened to read on slate (a dark colour more, so it never looks taken).
local function nameColor(colorIndex: number): Color3
	local c = Palette.nation(colorIndex)
	local luminance = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return c:Lerp(Color3.new(1, 1, 1), math.max(0.35, 0.75 - luminance))
end
local CONFIRM_WIDTH = 280 -- the Pick button at most
local RACE_CARD_WIDTH = 480 -- the race card at most (one line on an 844 px phone)
local RACE_CARD_LINE = 34 -- its height for one line of text; two lines take RACE_CARD_TWO
local RACE_CARD_TWO = 54
local RACE_TEXT_INSET = 42 -- its icon and padding
local RACE_ROOM = 8 + 2 * CELL.X + CELL_GAP + 2 * Widgets.PANEL_PAD + MARGIN + Theme.space.m -- left of the panel
local DRAFT_CORNER_BUTTONS = 2 -- corner buttons that stay during the draft: the shop's cart and the quests' scroll

local Draft = {}

local gui: ScreenGui
local bannerText: TextLabel
local bannerIcon: GuiObject
local timer: TextLabel
local panel: Frame
local orderLabel: TextLabel
local themeLabel: TextLabel
local grid: Frame
local confirm: TextButton
local raceCard: TextLabel
local buttons: { [number]: TextButton } = {} -- nation id -> its button in the list
local stars: { [number]: GuiObject } = {} -- nation id -> the star on your own nation's button
local flags: { [number]: GuiObject } = {} -- nation id -> its flag on its button
local builtFor: any = nil -- the snapshot the buttons were made for
local selected: number? = nil -- nation chosen by a map tap, waiting for the confirm button

-- True while the draft runs on the map this client shows.
function Draft.active(): boolean
	local snap = ClientState.snapshot()
	return LobbyState.phase() == "Pick" and snap ~= nil and snap.phase == "Pick"
end

local function nameOf(userId: number): string
	local view = LobbyState.view()
	if view then
		for _, entry in view.order do
			if entry.userId == userId then
				return entry.name
			end
		end
	end
	return "?"
end

local function render()
	local snap = ClientState.snapshot()
	local view = LobbyState.view()
	if not Draft.active() or snap == nil or view == nil then
		gui.Enabled = false
		selected = nil
		return
	end
	gui.Enabled = true
	local me = Players.LocalPlayer.UserId
	local picker = LobbyState.picker()
	if picker and picker.userId == me then
		bannerText.Text = "Your turn! Pick a nation"
		Icons.set(bannerIcon, "star")
	elseif picker then
		bannerText.Text = picker.name .. " is picking"
		Icons.set(bannerIcon, "hourglass")
	else
		bannerText.Text = "Draft done"
		Icons.set(bannerIcon, "check")
	end
	-- the pick order: → whose turn it is, ✓ who has picked
	local parts = {}
	for i, entry in view.order do
		local mark = if i == view.turn then "→ " elseif entry.nation ~= 0 then "✓ " else ""
		table.insert(parts, mark .. (if entry.userId == me then "You" else entry.name))
	end
	orderLabel.Text = if #parts > 0 then table.concat(parts, "  ·  ") else "Bots only"
	-- the theme vote's winner and who brought it
	local theme = Catalogue.item(view.theme)
	local look = Cosmetics.themeLook(view.theme)
	themeLabel.Visible = theme ~= nil and look ~= ""
	if theme and look ~= "" then
		local text = string.format("%s %s", theme.name, Maps.get(snap.mapId).title)
		if #view.themeBy > 0 then
			text ..= ", brought by " .. table.concat(view.themeBy, ", ")
		end
		if Cosmetics.classicOnly() then
			text ..= " (you see Classic)"
		end
		themeLabel.Text = text
	end

	if builtFor ~= snap then
		-- one tile per nation, made once per map (rebuilding them every second could swallow a tap)
		builtFor = snap
		Widgets.clear(grid)
		buttons = {}
		stars = {}
		flags = {}
		for _, nation in snap.nations do
			local id = nation.id
			local button = Widgets.plateButton(grid, "", CELL, function()
				local n = ClientState.nation(id)
				selected = id
				MapRenderer.select(if n then n.capital else nil)
				Intents.pick(id)
				render()
			end)
			button.Name = "Nation" .. id
			button.TextSize = Theme.text.small
			button.TextXAlignment = Enum.TextXAlignment.Left
			button.TextWrapped = false -- two lines, each cut with … rather than wrapped
			button.TextTruncate = Enum.TextTruncate.AtEnd
			button.LayoutOrder = id
			local pad = button:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingLeft = UDim.new(0, TILE_TEXT_LEFT)
				pad.PaddingRight = UDim.new(0, TILE_TEXT_RIGHT)
			end
			buttons[id] = button
			-- the nation's flag (its cosmetic) at the left, the race icon at the bottom right, a star on yours
			local flag =
				Cosmetics.flagLabel(button, Cosmetics.of(id).flag, nation.colorIndex, UDim2.fromOffset(FLAG.X, FLAG.Y))
			flag.Position = UDim2.fromOffset(Theme.space.s - TILE_TEXT_LEFT, (CELL.Y - FLAG.Y) // 2)
			flag.ZIndex = 2
			flags[id] = flag
			local star = Widgets.icon(button, "star", 16) -- on the flag's corner, like a badge
			star.Position = UDim2.fromOffset(2 - TILE_TEXT_LEFT, 2)
			star.ZIndex = 3
			star.Visible = false
			stars[id] = star
			local race = Widgets.icon(button, RaceInfo.icon(nation.race), 16) -- the race this nation plays
			race.Name = "Race"
			race.Position = UDim2.new(1, TILE_TEXT_RIGHT - 16 - 4, 1, -20)
			race.ZIndex = 2
		end
	end
	for _, nation in snap.nations do
		local button = buttons[nation.id]
		if button then
			local taken = nation.userId ~= 0
			if taken and nation.userId ~= me then
				button.Text = nation.name .. "\n" .. nameOf(nation.userId)
			else
				button.Text = nation.name .. "\n" .. RaceInfo.name(nation.race)
			end
			stars[nation.id].Visible = nation.userId == me -- your nation wears a star
			-- a nation someone else took is dimmed (its player's name says who); the one you tapped is outlined
			local gone = taken and nation.userId ~= me
			Widgets.setDimmed(button, gone)
			button.TextColor3 = if gone then Theme.color.textDisabled else nameColor(nation.colorIndex)
			local flag = flags[nation.id]
			if flag and flag:IsA("ImageLabel") then
				flag.ImageTransparency = if gone then 0.55 else 0
			end
			Widgets.setChosen(button, selected == nation.id and not gone)
		end
	end

	local choice = if selected then ClientState.nation(selected) else nil
	if choice and choice.userId == 0 and LobbyState.myTurn() then
		confirm.Text = "Pick " .. choice.name
		confirm.Visible = true
	else
		confirm.Visible = false
	end
	-- the tapped nation's race and its bonus (else your own nation's, once you have one)
	local shown = choice
	if shown == nil then
		for _, nation in snap.nations do
			if nation.userId == me then
				shown = nation
			end
		end
	end
	raceCard.Visible = shown ~= nil
	if shown then
		Icons.set(raceCard:FindFirstChild("Icon") :: GuiObject, RaceInfo.icon(shown.race))
		raceCard.Text = string.format("%s: %s · %s", shown.name, RaceInfo.name(shown.race), RaceInfo.bonus(shown.race))
		-- one line on a big phone, two on a small one: the plate grows upwards to hold them (worked out from the
		-- text's width, as the harness has no text layout)
		local screen = Widgets.screenSize(gui) / Widgets.uiScale()
		local room = math.min(screen.X - RACE_ROOM, RACE_CARD_WIDTH) - RACE_TEXT_INSET
		local lines = if TextWidth.measure(raceCard.Text, raceCard.TextSize) <= room then 1 else 2
		Widgets.fit(raceCard, UDim2.new(1, -RACE_ROOM, 0, if lines == 1 then RACE_CARD_LINE else RACE_CARD_TWO))
	end
end

-- A tap on the map while drafting: choose the nation whose land it is (confirm with the button).
function Draft.tap(kind: "Army" | "Province" | nil, id: number?)
	local provinceId = id
	if kind == "Army" and id then
		local army = ClientState.army(id)
		provinceId = if army then army.location else nil
	end
	local province = if provinceId then ClientState.province(provinceId) else nil
	if province and province.owner ~= 0 then
		selected = province.owner
		MapRenderer.select(provinceId)
	else
		selected = nil
		MapRenderer.select(nil)
	end
	render()
end

local function updateTimer()
	if gui.Enabled then
		local s = if LobbyState.picker() then LobbyState.turnSecondsLeft() else LobbyState.secondsLeft()
		timer.Text = string.format("%d:%02d", s // 60, s % 60)
	end
end

-- Whose turn it is, and the time under it: at the top left, under Roblox's top-bar row (a plate beside Roblox's
-- buttons would run into the nations panel on a 667 px phone).
local function placeBanner()
	local top = math.max(MARGIN, math.ceil((Widgets.topbarBottom(gui) + Theme.space.xs) / 2) * 2)
	Widgets.fit(bannerText, nil, UDim2.fromOffset(MARGIN, top))
	Widgets.fit(timer, nil, UDim2.fromOffset(MARGIN + 10, top + Widgets.BUTTON_HEIGHT + Theme.space.m))
end

function Draft.init()
	gui = Widgets.screen("Draft", 5)
	gui.Enabled = false
	Widgets.coverScreen(gui)

	-- whose turn it is: a plate at the top left, the time in a counter under it
	bannerText = Instance.new("TextLabel")
	bannerText.Name = "Banner"
	bannerText.Active = true
	bannerText.Position = UDim2.fromOffset(MARGIN, MARGIN)
	bannerText.Size = UDim2.fromOffset(0, Widgets.BUTTON_HEIGHT)
	bannerText.AutomaticSize = Enum.AutomaticSize.X
	bannerText.BackgroundColor3 = Theme.color.slate800
	bannerText.BorderSizePixel = 0
	bannerText.FontFace = Theme.font.display
	bannerText.TextSize = Theme.text.title
	bannerText.TextColor3 = Theme.color.text
	bannerText.TextWrapped = false
	bannerText.Parent = gui
	Widgets.corner(bannerText, Theme.radius.s)
	Widgets.stroke(bannerText)
	local bannerPad = Widgets.padding(bannerText, Theme.space.l, 0)
	bannerIcon = Widgets.leadIcon(bannerText, "star", Theme.size.icon)
	bannerPad.PaddingBottom = UDim.new(0, 2)
	if not Widgets.skin(bannerText, "plate", "plate") then
		Widgets.textStroke(bannerText)
	end
	Widgets.shadow(bannerText, "plate")
	timer = Widgets.counter(gui, "hourglass", "", TIMER_WIDTH)
	timer.Name = "Timer"
	timer.Position = UDim2.fromOffset(MARGIN + 10, MARGIN + Widgets.BUTTON_HEIGHT + Theme.space.m)

	panel = Widgets.panel(gui, PANEL_WIDTH)
	panel.Name = "Nations"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -MARGIN, 0, MARGIN)
	Widgets.list(panel, false, 6)
	themeLabel = Widgets.label(panel, "", Theme.text.small, 36)
	themeLabel.Name = "ThemeCredit"
	themeLabel.TextColor3 = Theme.color.gold
	themeLabel.TextWrapped = true
	themeLabel.LayoutOrder = 0
	themeLabel.Visible = false
	Widgets.leadIcon(themeLabel, "palette", Theme.size.icon)
	orderLabel = Widgets.label(panel, "", Theme.text.small, 40)
	orderLabel.LayoutOrder = 1
	grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	layout.CellPadding = UDim2.fromOffset(CELL_GAP, CELL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	confirm = Widgets.iconTextButton(gui, "check", "", 280, Widgets.GOLD, function()
		if selected then
			Intents.pick(selected)
		end
	end)
	confirm.Name = "Confirm"
	-- between the Lobby's corner buttons (the cart and the scroll stay during the draft) and the panel, as wide as
	-- there is room for (up to CONFIRM_WIDTH): on a 667 px phone it never sits under the corner buttons
	local left = Widgets.cornerRowEnd(DRAFT_CORNER_BUTTONS) + Theme.space.m
	local right = PANEL_WIDTH + MARGIN + Theme.space.m
	confirm.AnchorPoint = Vector2.new(0.5, 1)
	confirm.Position = UDim2.new(0.5, (left - right) // 2, 1, -12)
	confirm.Size = UDim2.new(1, -(left + right), 0, 48)
	local confirmCap = Instance.new("UISizeConstraint")
	confirmCap.MaxSize = Vector2.new(CONFIRM_WIDTH, 48)
	confirmCap.Parent = confirm
	confirm.TextSize = Theme.text.button - 1
	confirm.TextWrapped = false
	confirm.TextTruncate = Enum.TextTruncate.AtEnd
	confirm.Visible = false

	-- the race card, just above the Pick button
	raceCard = Widgets.chip(gui, "humans", "", nil, 34)
	raceCard.Name = "RaceCard"
	-- over the free map left of the panel (above the corner buttons): one line on a big phone, two on a small one
	raceCard.AnchorPoint = Vector2.new(0.5, 1)
	raceCard.Position = UDim2.new(0.5, (8 - right) // 2, 1, -12 - 48 - Theme.space.m)
	raceCard.Size = UDim2.new(1, -RACE_ROOM, 0, RACE_CARD_LINE)
	raceCard.AutomaticSize = Enum.AutomaticSize.None
	raceCard.TextWrapped = true
	raceCard.TextTruncate = Enum.TextTruncate.None
	local raceCap = Instance.new("UISizeConstraint")
	raceCap.MaxSize = Vector2.new(RACE_CARD_WIDTH, math.huge)
	raceCap.Parent = raceCard
	-- a popover plate over the map, not a well
	if Widgets.skinned(raceCard) then
		Widgets.restyle(raceCard, "plate", "plate")
	else
		Widgets.material(raceCard, "plate")
	end
	Widgets.shadow(raceCard, "plate")
	raceCard.Visible = false

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	placeBanner()
	HudLayout.onChange(placeBanner) -- Roblox's row changed, or the screen did
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	LobbyState.onChange(render)
	ClientState.onReset(function()
		selected = nil
		render()
	end)
	ClientState.onDelta(function(delta)
		if #delta.nations > 0 or delta.phase ~= "Pick" then
			render()
		end
	end)
	RunService.Heartbeat:Connect(updateTimer)
end

return Draft
