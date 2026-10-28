--!strict
-- The nation draft (Pick phase): the chosen map shows every nation's start territory; players pick a start
-- nation one at a time in a random order. On your turn tap a nation in the list to take it, or tap its land on
-- the map and confirm. A banner says whose turn it is and how long is left. Bots keep the rest.
-- The theme vote's winner is credited at the top of the panel ("🌙 Night Earth, brought by Alice").

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
local Widgets = require(script.Parent.Widgets)

local BANNER_HEIGHT = 48 -- covers the HUD's top bar (44 px) while drafting
local PANEL_WIDTH = 272
local CELL = Vector2.new(120, 44)
local TAKEN_FADE = 0.75 -- background transparency of a nation someone already picked

local Draft = {}

local gui: ScreenGui
local banner: Frame
local bannerText: TextLabel
local timer: TextLabel
local panel: Frame
local orderLabel: TextLabel
local themeLabel: TextLabel
local grid: Frame
local confirm: TextButton
local buttons: { [number]: TextButton } = {} -- nation id -> its button in the list
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
		bannerText.Text = "🎯 Your turn! Pick a nation"
	elseif picker then
		bannerText.Text = "⏳ " .. picker.name .. " is picking"
	else
		bannerText.Text = "✅ Draft done"
	end
	local parts = {}
	for i, entry in view.order do
		local mark = if i == view.turn then "👉" elseif entry.nation ~= 0 then "✔" else "·"
		table.insert(parts, mark .. " " .. (if entry.userId == me then "You" else entry.name))
	end
	orderLabel.Text = if #parts > 0 then table.concat(parts, "   ") else "🤖 Bots only"
	-- the theme vote's winner and who brought it
	local theme = Catalogue.item(view.theme)
	local look = Cosmetics.themeLook(view.theme)
	themeLabel.Visible = theme ~= nil and look ~= ""
	if theme and look ~= "" then
		local text =
			string.format("%s %s %s", Cosmetics.THEME_ICONS[look] or "🎨", theme.name, Maps.get(snap.mapId).title)
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
		for _, nation in snap.nations do
			local id = nation.id
			local button = Widgets.button(grid, "", CELL.X, nil, function()
				local n = ClientState.nation(id)
				selected = id
				MapRenderer.select(if n then n.capital else nil)
				Intents.pick(id)
			end)
			button.Name = "Nation" .. id
			button.TextSize = 14
			button.TextStrokeTransparency = 0.3
			button.LayoutOrder = id
			buttons[id] = button
		end
	end
	for _, nation in snap.nations do
		local button = buttons[nation.id]
		if button then
			local taken = nation.userId ~= 0
			if nation.userId == me then
				button.Text = "⭐ " .. nation.name
			elseif taken then
				button.Text = nation.name .. "\n👤 " .. nameOf(nation.userId)
			else
				button.Text = nation.name
			end
			-- taken nations fade into the panel (a grey nation colour must still read as free)
			button.BackgroundColor3 = Palette.nation(nation.colorIndex)
			button.BackgroundTransparency = if taken then TAKEN_FADE else 0
		end
	end

	local choice = if selected then ClientState.nation(selected) else nil
	if choice and choice.userId == 0 and LobbyState.myTurn() then
		confirm.Text = "✔ Pick " .. choice.name
		confirm.Visible = true
	else
		confirm.Visible = false
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
		timer.Text = string.format("⏳ %d:%02d", s // 60, s % 60)
	end
end

function Draft.init()
	gui = Widgets.screen("Draft", 5)
	gui.Enabled = false

	banner = Instance.new("Frame")
	banner.Name = "Banner"
	banner.Active = true
	banner.Size = UDim2.new(1, 0, 0, BANNER_HEIGHT)
	banner.BackgroundColor3 = Widgets.PANEL
	banner.BorderSizePixel = 0
	banner.Parent = gui
	bannerText = Widgets.label(banner, "", 20, BANNER_HEIGHT)
	bannerText.Position = UDim2.fromOffset(16, 0)
	bannerText.Size = UDim2.new(1, -170, 1, 0)
	timer = Widgets.label(banner, "", 20, BANNER_HEIGHT)
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, -16, 0, 0)
	timer.Size = UDim2.new(0, 140, 1, 0)
	timer.TextXAlignment = Enum.TextXAlignment.Right

	panel = Widgets.panel(gui, PANEL_WIDTH)
	panel.Name = "Nations"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -8, 0, BANNER_HEIGHT + 8)
	Widgets.list(panel, false, 6)
	themeLabel = Widgets.label(panel, "", 14, 36)
	themeLabel.Name = "ThemeCredit"
	themeLabel.TextColor3 = Color3.fromRGB(242, 193, 78)
	themeLabel.TextWrapped = true
	themeLabel.LayoutOrder = 0
	themeLabel.Visible = false
	orderLabel = Widgets.label(panel, "", 14, 40)
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

	confirm = Widgets.button(gui, "", 220, Widgets.GOOD, function()
		if selected then
			Intents.pick(selected)
		end
	end)
	confirm.Name = "Confirm"
	confirm.AnchorPoint = Vector2.new(0.5, 1)
	confirm.Position = UDim2.new(0.5, -PANEL_WIDTH // 2, 1, -12)
	confirm.Size = UDim2.fromOffset(220, 48)
	confirm.TextSize = 18
	confirm.Visible = false

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
