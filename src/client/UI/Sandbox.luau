--!strict
-- The sandbox panel (docs/DESIGN.md "Sandbox"), shown only in a sandbox world: a small panel at the top left, under
-- the top bar, with
--   the time controls   pause, 1×, 2×, 4× (one tap)
--   Play as             a list of the living nations and Watch: tap one to lead it (two taps)
--   Powers              the usual power picker, free here, opened beside the panel (then a target and Confirm)
--   World               disasters on or off, a new world on any map, back to Play online (two taps)
-- The lists open in the panel's place. The server answers every tap (Intents.sandbox); the panel redraws from the
-- snapshot's controls and from the nation that names you. Built the first time a sandbox snapshot arrives, so a
-- match never pays for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local MapView = require(Client.MapView)
local Palette = require(Client.Palette)
local RaceInfo = require(Client.RaceInfo)
local Powers = require(script.Parent.Powers)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local MARGIN = Theme.space.m -- from the screen's left edge and the top bar
local GAP = Theme.space.xs
local TAB = 46 -- a time tab
local INNER = 4 * TAB + 3 * GAP -- the panel's content width
local PANEL_WIDTH = INNER + 2 * Theme.space.l
local CELL = 150 -- a nation in the Play as list: the longest name ("Ashen Dominion") fits beside its race icon
local COLUMNS = 3
local MAP_BUTTON = 120 -- a new world's map
local SWATCH = 10 -- the nation's colour on its button

local Sandbox = {}

local gui: ScreenGui
local panel: Frame? = nil
local tabs: { [number]: TextButton } = {}
local popup: Frame? = nil -- the Play as list or the World menu, open in the panel's place
local popupKind = ""
local shownNation = -1 -- the nation the panel last saw you hold (0 = watching)
local toast: (string) -> () = function(_text: string) end
local onSwitch: () -> () = function() end

local function isSandbox(): boolean
	local snap = ClientState.snapshot()
	return snap ~= nil and snap.setup.sandbox == true
end

local function top(): number
	return MapView.topBand() + MARGIN
end

local function speedText(speed: number): string
	return string.format("%d×", speed)
end

-- Popups (Play as, World) -------------------------------------------------------------------------------------------

local function closePopup()
	if popup then
		popup:Destroy()
	end
	popup = nil
	popupKind = ""
	if panel then
		panel.Visible = isSandbox()
	end
end

-- A panel in the sandbox panel's place, with a title and ✕.
local function openPopup(kind: string, title: string, icon: string, width: number): Frame
	closePopup()
	if Powers.isOpen() then
		Powers.toggle()
	end
	local f = Widgets.panel(gui, width)
	f.Name = kind
	f.Position = UDim2.fromOffset(MARGIN, top())
	Widgets.list(f, false, Theme.space.s)
	local header = Widgets.header(f, title, icon, closePopup)
	header.LayoutOrder = 0
	popup = f
	popupKind = kind
	if panel then
		panel.Visible = false
	end
	return f
end

-- A row of buttons inside a popup.
local function row(parent: Frame, order: number, columns: number?): Frame
	local r = Instance.new("Frame")
	r.Name = "Row" .. order
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	r.AutomaticSize = if columns then Enum.AutomaticSize.Y else Enum.AutomaticSize.None
	r.LayoutOrder = order
	r.Parent = parent
	if columns then
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(CELL, Widgets.BUTTON_HEIGHT)
		grid.CellPadding = UDim2.fromOffset(Theme.space.s, Theme.space.s)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = r
	else
		Widgets.list(r, true, Theme.space.s)
	end
	return r
end

-- Play as: Watch, then every living nation (yours in gold). A tap takes it over; the server hands your old nation
-- back to a bot.
local function openPlayAs()
	local snap = ClientState.snapshot()
	if snap == nil then
		return
	end
	local f =
		openPopup("PlayAs", "Play as", "crown", COLUMNS * CELL + (COLUMNS - 1) * Theme.space.s + 2 * Theme.space.l)
	local grid = row(f, 1, COLUMNS)
	local me = ClientState.myNation()
	local watch = Widgets.iconTextButton(
		grid,
		"eye",
		"Watch",
		CELL,
		if me == 0 then Widgets.GOLD else Widgets.BUTTON_OFF,
		function()
			Intents.sandbox("Play", 0)
			closePopup()
		end,
		"Watch"
	)
	watch.LayoutOrder = 0
	for _, n in snap.nations do
		if not n.eliminated then
			local id = n.id
			local b = Widgets.iconTextButton(
				grid,
				RaceInfo.icon(n.race),
				n.name,
				CELL,
				if id == me then Widgets.GOLD else Widgets.BUTTON,
				function()
					Intents.sandbox("Play", id)
					closePopup()
				end,
				"Play" .. id
			)
			b.LayoutOrder = id
			b.TextSize = Theme.text.small + 1
			b.TextTruncate = Enum.TextTruncate.AtEnd
			local swatch = Instance.new("Frame")
			swatch.Name = "Swatch"
			swatch.AnchorPoint = Vector2.new(1, 0.5)
			swatch.Position = UDim2.fromScale(1, 0.5)
			swatch.Size = UDim2.fromOffset(SWATCH, SWATCH)
			swatch.BackgroundColor3 = Palette.nation(n.colorIndex)
			swatch.BorderSizePixel = 0
			swatch.ZIndex = 3
			swatch.Parent = b
			Widgets.stroke(swatch, Theme.color.ink, 1)
		end
	end
end

-- World: disasters on or off, a new world on any map, or back to a public server.
local function openWorld()
	local controls = ClientState.sandbox()
	if controls == nil then
		return
	end
	local width = #Maps.ids * MAP_BUTTON + (#Maps.ids - 1) * Theme.space.s
	local f = openPopup("World", "World", "globe", width + 2 * Theme.space.l)
	local half = (width - Theme.space.s) // 2
	local first = row(f, 1)
	local on = controls.disasters
	Widgets.iconTextButton(
		first,
		"meteor",
		if on then "Disasters: On" else "Disasters: Off",
		half,
		if on then Widgets.DANGER else Widgets.BUTTON_OFF,
		function()
			Intents.sandbox("Disasters", not on)
			toast(if on then "☀ Disasters off" else "☄ Disasters on: one every minute")
			closePopup()
		end,
		"Disasters"
	)
	Widgets.iconTextButton(first, "globe", "Play online", half, Widgets.GOOD, function()
		Intents.sandbox("Leave")
		closePopup()
	end, "PlayOnline")
	local hint = Widgets.hint(f, "New world", Theme.text.small, 20)
	hint.LayoutOrder = 2
	Widgets.leadIcon(hint, "map", Theme.size.icon)
	local maps = row(f, 3)
	for i, id in Maps.ids do
		local b = Widgets.iconTextButton(maps, "map", Maps.get(id).title, MAP_BUTTON, Widgets.BUTTON, function()
			Intents.sandbox("NewWorld", id)
			closePopup()
		end, "NewWorld_" .. id)
		b.LayoutOrder = i
	end
end

-- The panel ----------------------------------------------------------------------------------------------------------

local function refreshTabs()
	local controls = ClientState.sandbox()
	local speed = if controls then controls.speed else -1
	for value, b in tabs do
		Widgets.setTab(b, value == speed)
	end
end

local function build()
	local p = Widgets.panel(gui, PANEL_WIDTH)
	p.Name = "SandboxPanel"
	p.Position = UDim2.fromOffset(MARGIN, top())
	Widgets.list(p, false, Theme.space.s)
	local time = Instance.new("Frame")
	time.Name = "Time"
	time.BackgroundTransparency = 1
	time.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	time.LayoutOrder = 1
	time.Parent = p
	Widgets.list(time, true, GAP)
	for i, speed in Config.Sandbox.Speeds do
		local b = Widgets.tab(time, if speed == 0 then "" else speedText(speed), TAB, false, function()
			Intents.sandbox("Speed", speed)
		end)
		b.Name = if speed == 0 then "Pause" else "Speed" .. speed
		b.LayoutOrder = i
		if speed == 0 then
			local icon = Widgets.icon(b, "pause", Theme.size.iconButton)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			icon.ZIndex = 2
		end
		tabs[speed] = b
	end
	local actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	actions.LayoutOrder = 2
	actions.Parent = p
	Widgets.list(actions, true, GAP)
	local size = Widgets.BUTTON_HEIGHT
	local playAs = Widgets.iconTextButton(
		actions,
		"crown",
		"Play as",
		INNER - 2 * (size + GAP),
		Widgets.GOLD,
		function()
			if popupKind == "PlayAs" then
				closePopup()
			else
				openPlayAs()
			end
		end,
		"PlayAs"
	)
	playAs.LayoutOrder = 1
	playAs.TextSize = Theme.text.small + 1
	local powers = Widgets.iconButton(actions, "sparkles", "Powers", size, Widgets.SPECIAL, function()
		closePopup()
		Powers.placePicker(Vector2.zero, UDim2.fromOffset(MARGIN + PANEL_WIDTH + MARGIN, top()))
		Powers.toggle()
	end)
	powers.LayoutOrder = 2
	local world = Widgets.iconButton(actions, "gear", "World", size, Widgets.BUTTON_OFF, function()
		if popupKind == "World" then
			closePopup()
		else
			openWorld()
		end
	end)
	world.LayoutOrder = 3
	panel = p
end

-- Show the panel in a sandbox (building it the first time), hide it in a match.
local function refresh()
	if not isSandbox() then
		closePopup()
		if panel then
			panel.Visible = false
		end
		return
	end
	if panel == nil then
		build()
	end
	local p = panel :: Frame
	p.Position = UDim2.fromOffset(MARGIN, top())
	p.Visible = popup == nil
	refreshTabs()
	if popupKind == "World" then
		openWorld() -- the disasters button shows the new state
	end
end

-- After a take-over (or a fall): say who you are now, and drop any selection made for the old nation.
local function checkNation()
	if not isSandbox() then
		shownNation = -1
		return
	end
	local me = ClientState.myNation()
	if me == shownNation then
		return
	end
	local first = shownNation == -1
	shownNation = me
	onSwitch()
	if popupKind == "PlayAs" then
		closePopup()
	end
	if first then
		return
	end
	local nation = ClientState.nation(me)
	if nation then
		toast("👑 You lead " .. nation.name)
	else
		toast("👁 You're watching the world")
	end
end

-- showToast: the HUD's toasts; switched: called when you lead another nation or start watching (close the sheets).
function Sandbox.init(showToast: (string) -> (), switched: () -> ())
	toast = showToast
	onSwitch = switched
	gui = Widgets.screen("Sandbox", 3) -- under the nations drawer and the power picker (4)
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	ClientState.onReset(function()
		shownNation = -1
		closePopup()
		refresh()
		checkNation()
	end)
	ClientState.onDelta(function(delta)
		if delta.sandbox then
			refresh()
		end
		if #delta.nations > 0 then
			checkNation()
		end
	end)
end

-- True in a sandbox world (the start menu and other screens can ask).
function Sandbox.active(): boolean
	return isSandbox()
end

return Sandbox
