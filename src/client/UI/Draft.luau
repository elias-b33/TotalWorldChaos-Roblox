--!strict
-- The nation draft (Pick phase): the chosen map shows every nation's start territory; players pick a start
-- nation one at a time in a random order. On your turn tap a nation in the list to take it, or tap its land on
-- the map and confirm. A banner says whose turn it is and how long is left. Bots keep the rest.
-- The theme vote's winner is credited at the top of the panel ("🌙 Night Earth, brought by Alice").
-- Picking a nation picks its race (docs/DESIGN.md "Races"): every nation's card shows its race (icon and name), and
-- the nation you tap gets a race card above the Pick button with its one-line bonus.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Maps = require(Shared.Maps)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local MapRenderer = require(Client.MapRenderer)
local Palette = require(Client.Palette)
local RaceInfo = require(Client.RaceInfo)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local BANNER_HEIGHT = 48 -- covers the HUD's top bar (44 px) while drafting
local CELL = Vector2.new(120, 44)
local PANEL_WIDTH = 2 * CELL.X + 6 + 2 * Widgets.PANEL_PAD -- two columns of nations inside the frame
local CONFIRM_WIDTH = 280 -- the Pick button at most
local RACE_CARD_WIDTH = 480 -- the race card at most (one line on an 844 px phone)
local DRAFT_CORNER_BUTTONS = 2 -- corner buttons that stay during the draft: the shop's cart and the quests' scroll
local TAKEN_FADE = 0.75 -- background transparency of a nation someone already picked

local Draft = {}

local gui: ScreenGui
local banner: Frame
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
		-- one button per nation, made once per map (rebuilding them every second could swallow a tap)
		builtFor = snap
		Widgets.clear(grid)
		buttons = {}
		stars = {}
		for _, nation in snap.nations do
			local id = nation.id
			local button = Widgets.button(grid, "", CELL.X, nil, function()
				local n = ClientState.nation(id)
				selected = id
				MapRenderer.select(if n then n.capital else nil)
				Intents.pick(id)
			end)
			button.Name = "Nation" .. id
			button.TextSize = Theme.text.small + 1
			button.TextStrokeTransparency = 0.2
			button.TextStrokeColor3 = Theme.color.ink
			button.LayoutOrder = id
			buttons[id] = button
			local star = Widgets.icon(button, "star", 16)
			star.Position = UDim2.fromOffset(4, 4)
			star.Visible = false
			stars[id] = star
			local race = Widgets.icon(button, RaceInfo.icon(nation.race), 16) -- the race this nation plays
			race.Name = "Race"
			race.AnchorPoint = Vector2.new(1, 1)
			race.Position = UDim2.new(1, -4, 1, -6)
		end
	end
	for _, nation in snap.nations do
		local button = buttons[nation.id]
		if button then
			local taken = nation.userId ~= 0
			if taken and nation.userId ~= me then
				button.Text = nation.name .. "\n" .. nameOf(nation.userId)
			else
				button.Text = nation.name .. "\n" .. nation.race
			end
			stars[nation.id].Visible = nation.userId == me -- your nation wears a star
			-- taken nations fade into the panel (a grey nation colour must still read as free)
			button.BackgroundColor3 = Palette.nation(nation.colorIndex)
			button.BackgroundTransparency = if taken then TAKEN_FADE else 0
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
		raceCard.Text = string.format("%s: %s · %s", shown.name, shown.race, RaceInfo.bonus(shown.race))
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

function Draft.init()
	gui = Widgets.screen("Draft", 5)
	gui.Enabled = false

	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Active = true
	banner.Size = UDim2.new(1, 0, 0, BANNER_HEIGHT)
	banner.BackgroundColor3 = Theme.color.navy
	banner.BorderSizePixel = 0
	banner.Parent = gui
	Widgets.stroke(banner)
	Widgets.bevel(banner, true)
	bannerText = Widgets.title(banner, "", Theme.text.title, BANNER_HEIGHT)
	bannerText.Position = UDim2.fromOffset(16, 0)
	bannerText.Size = UDim2.new(1, -170, 1, 0)
	bannerIcon = Widgets.leadIcon(bannerText, "star", Theme.icon.small)
	timer = Widgets.chip(banner, "hourglass", "", 96, 34)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(1, 0.5)
	timer.Position = UDim2.new(1, -16, 0.5, 0)
	timer.TextSize = Theme.text.title - 2

	panel = Widgets.panel(gui, PANEL_WIDTH)
	panel.Name = "Nations"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -8, 0, BANNER_HEIGHT + 8)
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
	layout.CellPadding = UDim2.fromOffset(6, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	confirm = Widgets.iconTextButton(gui, "check", "", 280, Widgets.GOOD, function()
		if selected then
			Intents.pick(selected)
		end
	end)
	confirm.Name = "Confirm"
	-- between the Lobby's corner buttons (the cart and the scroll stay during the draft) and the panel, as wide as
	-- there is room for (up to CONFIRM_WIDTH): on a 667 px phone it never sits under the corner buttons
	local left = Widgets.cornerRowEnd(DRAFT_CORNER_BUTTONS) + Theme.space.m
	local right = PANEL_WIDTH + 8 + Theme.space.m
	confirm.AnchorPoint = Vector2.new(0.5, 1)
	confirm.Position = UDim2.new(0.5, (left - right) // 2, 1, -12)
	confirm.Size = UDim2.new(1, -(left + right), 0, 48)
	local confirmCap = Instance.new("UISizeConstraint")
	confirmCap.MaxSize = Vector2.new(CONFIRM_WIDTH, 48)
	confirmCap.Parent = confirm
	confirm.TextSize = 18
	confirm.TextWrapped = false
	confirm.TextTruncate = Enum.TextTruncate.AtEnd
	confirm.Visible = false

	-- the race card, just above the Pick button
	raceCard = Widgets.chip(gui, "humans", "", nil, 34)
	raceCard.Name = "RaceCard"
	-- over the free map left of the panel (above the corner buttons): one line on a big phone, two on a small one
	raceCard.AnchorPoint = Vector2.new(0.5, 1)
	raceCard.Position = UDim2.new(0.5, (8 - right) // 2, 1, -12 - 48 - Theme.space.m)
	raceCard.Size = UDim2.new(1, -(8 + right), 0, 34)
	raceCard.AutomaticSize = Enum.AutomaticSize.Y
	raceCard.TextWrapped = true
	raceCard.TextTruncate = Enum.TextTruncate.None
	local raceCap = Instance.new("UISizeConstraint")
	raceCap.MaxSize = Vector2.new(RACE_CARD_WIDTH, math.huge)
	raceCap.Parent = raceCard
	raceCard.BackgroundColor3 = Theme.color.navy
	raceCard.BackgroundTransparency = 0
	Widgets.stroke(raceCard)
	raceCard.Visible = false

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
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
