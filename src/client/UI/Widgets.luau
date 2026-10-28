--!strict
-- The UI kit (docs/DESIGN.md "UI style"): every screen builds from these so they share one "pixel kingdom" look:
-- navy panels with a 2 px ink outline and a bevel, gold titles, buttons with a darker bottom edge that press down,
-- pixel icons (Icons) instead of emoji, chips (icon + number), tabs, cards, badges, progress bars, bottom sheets
-- and toasts. Colours, fonts and sizes come from Theme. Kept small in GUI objects: a button is the button plus a
-- corner, an outline and a gradient (the press scale is only made on the first press).

local TweenService = game:GetService("TweenService")

local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local Widgets = {}

Widgets.Theme = Theme
Widgets.Icons = Icons

-- Colour names the screens already use (kept so older screens keep working), mapped onto the theme.
Widgets.PANEL = Theme.color.navy
Widgets.BUTTON = Theme.color.primary
Widgets.BUTTON_OFF = Theme.color.secondary
Widgets.DANGER = Theme.color.danger
Widgets.GOOD = Theme.color.good
Widgets.GOLD = Theme.color.gold
Widgets.SPECIAL = Theme.color.special
Widgets.DISABLED = Theme.color.disabled
Widgets.BUTTON_HEIGHT = Theme.size.button

local WHITE = Color3.new(1, 1, 1)
local PRESS_TWEEN = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESSED_SCALE = 0.94

-- Buttons: full colour down to the bevel line, then a darker band (UIGradient multiplies the background, so the
-- band follows whatever colour a screen gives the button later).
local EDGE = Color3.fromRGB(150, 150, 165)
local BUTTON_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(1 - Theme.bevel - 0.001, WHITE),
	ColorSequenceKeypoint.new(1 - Theme.bevel, EDGE),
	ColorSequenceKeypoint.new(1, EDGE),
})
-- Panels: a gentle top-to-bottom shade, lit from above like the map's mountains.
local PANEL_GRADIENT = ColorSequence.new(WHITE, Color3.fromRGB(196, 198, 214))

function Widgets.corner(parent: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.radius.m)
	c.Parent = parent
	return c
end

function Widgets.padding(parent: GuiObject, px: number, vertical: number?): UIPadding
	local p = Instance.new("UIPadding")
	local v = vertical or px
	p.PaddingTop = UDim.new(0, v)
	p.PaddingBottom = UDim.new(0, v)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

function Widgets.list(parent: GuiObject, horizontal: boolean?, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, gap or Theme.space.s)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

function Widgets.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order or 0
	return gui
end

-- The 2 px ink outline round a panel, button or chip. If something else puts its own stroke on the object later
-- (the tutorial's glow), this one steps aside until that one is gone: Roblox draws one border stroke per object.
function Widgets.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Name = "Outline"
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Color = color or Theme.color.ink
	s.Thickness = thickness or Theme.stroke
	s.Parent = parent
	local function others(): boolean
		for _, child in parent:GetChildren() do
			if child:IsA("UIStroke") and child ~= s then
				return true
			end
		end
		return false
	end
	parent.ChildAdded:Connect(function(child: Instance)
		if child:IsA("UIStroke") and child ~= s then
			s.Enabled = false
		end
	end)
	parent.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("UIStroke") and child ~= s then
			s.Enabled = not others()
		end
	end)
	return s
end

-- The darker bottom edge of a button (or a panel's top-to-bottom shade with `panel`).
function Widgets.bevel(parent: GuiObject, panel: boolean?): UIGradient
	local g = Instance.new("UIGradient")
	g.Name = "Bevel"
	g.Rotation = 90
	g.Color = if panel then PANEL_GRADIENT else BUTTON_GRADIENT
	g.Parent = parent
	return g
end

-- A navy panel that grows to fit its content vertically. Active, so taps and drags on it never reach the map.
function Widgets.panel(parent: Instance, width: number): Frame
	local f = Instance.new("Frame")
	f.Active = true
	f.Size = UDim2.fromOffset(width, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = Widgets.PANEL
	f.BackgroundTransparency = 0
	f.BorderSizePixel = 0
	f.Parent = parent
	Widgets.corner(f, Theme.radius.l)
	Widgets.stroke(f)
	Widgets.bevel(f, true)
	Widgets.padding(f, Theme.space.l, Theme.space.m + 2)
	return f
end

-- A bottom sheet: a panel docked to the bottom centre, as wide as `width` but never wider than the screen.
function Widgets.sheet(parent: Instance, width: number): Frame
	local f = Widgets.panel(parent, width)
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -Theme.space.m)
	f.Size = UDim2.new(1, -2 * Theme.space.l, 0, 0)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, math.huge)
	limit.Parent = f
	return f
end

-- A raised card inside a panel (a shop item, a quest, a map in the vote).
function Widgets.card(parent: Instance, width: number?, height: number?): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(if width then 0 else 1, width or 0, 0, height or 0)
	f.AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
	f.BackgroundColor3 = Theme.color.navyRaised
	f.BorderSizePixel = 0
	f.Parent = parent
	Widgets.corner(f, Theme.radius.m)
	Widgets.stroke(f)
	Widgets.padding(f, Theme.space.m)
	return f
end

-- Body text: Builder Sans, warm white, left aligned, wrapping.
function Widgets.label(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height or 22)
	l.FontFace = Theme.font.body
	l.TextSize = size or Theme.text.body
	l.TextColor3 = Theme.color.text
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Text = text
	l.Parent = parent
	return l
end

-- A hint line: lighter and dimmer than body text.
function Widgets.hint(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local l = Widgets.label(parent, text, size or Theme.text.small, height)
	l.FontFace = Theme.font.bodyLight
	l.TextColor3 = Theme.color.textDim
	return l
end

-- A title: Fredoka One in gold.
function Widgets.title(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local l = Widgets.label(parent, text, size or Theme.text.heading, height or 28)
	l.FontFace = Theme.font.display
	l.TextColor3 = Theme.color.gold
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	return l
end

-- An icon `size` px square (see Icons.label).
function Widgets.icon(parent: Instance, name: string, size: number?): GuiObject
	return Icons.label(parent, name, size or Theme.size.icon)
end

-- Put an icon at the left of a text label or button, inside its left padding (the text moves right to make room).
-- Returns the icon; Icons.set changes it later.
function Widgets.leadIcon(obj: GuiObject, name: string, size: number?, gap: number?): GuiObject
	local s = size or Theme.size.icon
	local g = gap or Theme.space.s
	local pad = obj:FindFirstChildOfClass("UIPadding")
	if pad == nil then
		pad = Widgets.padding(obj, 0, 0)
	end
	local padding = pad :: UIPadding
	local left = padding.PaddingLeft.Offset
	padding.PaddingLeft = UDim.new(0, left + s + g)
	local icon = Icons.label(obj, name, s)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, -(s + g), 0.5, 0)
	return icon
end

-- Press feedback: the button squashes a little and its bevel sinks while held.
local function pressable(b: GuiButton, gradient: UIGradient?)
	local scale: UIScale? = nil
	local down = false
	local function set(pressed: boolean)
		if pressed == down then
			return
		end
		down = pressed
		if pressed and scale == nil then
			local s = Instance.new("UIScale")
			s.Parent = b
			scale = s
		end
		if scale then
			TweenService:Create(scale, PRESS_TWEEN, { Scale = if pressed then PRESSED_SCALE else 1 }):Play()
		end
		if gradient then
			gradient.Offset = if pressed then Vector2.new(0, Theme.bevel) else Vector2.zero
		end
	end
	b.MouseButton1Down:Connect(function()
		set(true)
	end)
	b.MouseButton1Up:Connect(function()
		set(false)
	end)
	b.MouseLeave:Connect(function()
		set(false)
	end)
	b.Activated:Connect(function()
		set(false)
	end)
end

-- A button at least 44 px tall: colour (Widgets.BUTTON, GOOD, DANGER, BUTTON_OFF, GOLD, SPECIAL...), an outline,
-- a darker bottom edge and Fredoka One text. Gold buttons get dark text.
function Widgets.button(parent: Instance, text: string, width: number, color: Color3?, onPress: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, Widgets.BUTTON_HEIGHT)
	b.BackgroundColor3 = color or Widgets.BUTTON
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.FontFace = Theme.font.display
	b.TextSize = 16
	b.TextWrapped = true
	b.TextColor3 = if color == Widgets.GOLD then Theme.color.textDark else Theme.color.text
	b.Text = text
	b.Parent = parent
	Widgets.corner(b, Theme.radius.m)
	Widgets.stroke(b)
	pressable(b, Widgets.bevel(b))
	b.Activated:Connect(onPress)
	return b
end

-- A button with a pixel icon before its text. `name` (optional) is the button's Name, e.g. its old emoji
-- caption, so the tutorial and the harness still find it.
function Widgets.iconTextButton(
	parent: Instance,
	icon: string,
	text: string,
	width: number,
	color: Color3?,
	onPress: () -> (),
	name: string?
): TextButton
	local b = Widgets.button(parent, text, width, color, onPress)
	b.TextXAlignment = Enum.TextXAlignment.Left
	Widgets.padding(b, Theme.space.m, 0)
	Widgets.leadIcon(b, icon, Theme.size.iconButton)
	if name then
		b.Name = name
	end
	return b
end

-- A big action button: a pixel icon at the left, a caption and under it the cost as icon + number pairs
-- (`costs` = { { "gold", "40" }, { "manpower", "1k" } }). `name` (optional) is the button's Name.
function Widgets.actionButton(
	parent: Instance,
	icon: string,
	caption: string,
	costs: { { string } },
	size: Vector2,
	color: Color3?,
	onPress: () -> (),
	name: string?
): TextButton
	local b = Widgets.button(parent, caption, size.X, color, onPress)
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.TextSize = Theme.text.small + 1
	b.TextWrapped = false
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextYAlignment = if #costs > 0 then Enum.TextYAlignment.Top else Enum.TextYAlignment.Center
	local pad = Widgets.padding(b, Theme.space.s, 0)
	pad.PaddingTop = UDim.new(0, if #costs > 0 then 7 else 0)
	pad.PaddingBottom = UDim.new(0, if #costs > 0 then 9 else 4) -- clear of the darker bottom edge
	Widgets.leadIcon(b, icon, Theme.size.iconButton)
	if #costs > 0 then
		-- one cost sits straight in the button; several share a row (two fewer objects for the usual case)
		local line: GuiObject = b
		if #costs > 1 then
			local row = Instance.new("Frame")
			row.Name = "Cost"
			row.BackgroundTransparency = 1
			row.AnchorPoint = Vector2.new(0, 1)
			row.Position = UDim2.fromScale(0, 1)
			row.Size = UDim2.new(1, 0, 0, 16)
			row.Parent = b
			Widgets.list(row, true, Theme.space.xs)
			line = row
		end
		for i, cost in costs do
			local l = Widgets.label(line, cost[2], Theme.text.small, 16)
			l.Name = "Cost"
			l.FontFace = Theme.font.display
			l.TextColor3 = Theme.color.goldPale
			l.Size = UDim2.fromOffset(0, 16)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.TextWrapped = false
			l.LayoutOrder = i
			if line == b then
				l.AnchorPoint = Vector2.new(0, 1)
				l.Position = UDim2.fromScale(0, 1)
			end
			Widgets.leadIcon(l, cost[1], 14)
		end
	end
	if name then
		b.Name = name
	end
	return b
end

-- A square button showing just an icon. `name` is the button's Name (what the harness and tutorial look for).
-- Without a colour it is a plain icon with no plate (top bar buttons, close crosses).
function Widgets.iconButton(
	parent: Instance,
	icon: string,
	name: string,
	size: number?,
	color: Color3?,
	onPress: () -> ()
): TextButton
	local s = size or Widgets.BUTTON_HEIGHT
	local b: TextButton
	if color then
		b = Widgets.button(parent, "", s, color, onPress)
		b.Size = UDim2.fromOffset(s, s)
	else
		b = Instance.new("TextButton")
		b.Size = UDim2.fromOffset(s, s)
		b.BackgroundTransparency = 1
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = parent
		pressable(b, nil)
		b.Activated:Connect(onPress)
	end
	b.Name = name
	local iconSize = if s >= 56 then Theme.size.iconLarge else Theme.size.iconButton
	local i = Icons.label(b, icon, iconSize)
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Position = UDim2.fromScale(0.5, 0.5)
	return b
end

-- Grey a button out (it still gets taps: screens explain why in a toast) or give it its colour back.
function Widgets.setEnabled(b: GuiButton, enabled: boolean, color: Color3?)
	b.BackgroundColor3 = if enabled then color or Widgets.BUTTON else Widgets.DISABLED
	if b:IsA("TextButton") then
		b.TextColor3 = if not enabled
			then Theme.color.textDisabled
			elseif color == Widgets.GOLD then Theme.color.textDark
			else Theme.color.text
	end
	for _, child in b:GetChildren() do
		if child.Name == "Icon" and child:IsA("GuiObject") then
			Icons.dim(child, not enabled)
		end
	end
end

-- A tab: gold with dark text when selected, a dark well otherwise.
function Widgets.tab(parent: Instance, text: string, width: number, selected: boolean, onPress: () -> ()): TextButton
	local b = Widgets.button(parent, text, width, nil, onPress)
	b.TextSize = Theme.text.small + 1
	Widgets.setTab(b, selected)
	return b
end

function Widgets.setTab(b: TextButton, selected: boolean)
	b.BackgroundColor3 = if selected then Theme.color.gold else Theme.color.navyDeep
	b.TextColor3 = if selected then Theme.color.textDark else Theme.color.textDim
end

-- A chip: an icon and a value in a dark well ("💰 120" as a pixel coin and a number). Fixed `width`, or as wide
-- as its text without one. Returns the chip (set its Text); its icon is the child "Icon" (Icons.set).
function Widgets.chip(parent: Instance, icon: string, text: string, width: number?, height: number?): TextLabel
	local h = height or Theme.size.chip
	local c = Instance.new("TextLabel")
	c.Name = "Chip"
	c.Size = UDim2.fromOffset(width or 0, h)
	c.AutomaticSize = if width then Enum.AutomaticSize.None else Enum.AutomaticSize.X
	c.BackgroundColor3 = Theme.color.navyDeep
	c.BackgroundTransparency = 0.15
	c.BorderSizePixel = 0
	c.FontFace = Theme.font.display
	c.TextSize = if h >= 30 then 17 else Theme.text.small + 1
	c.TextColor3 = Theme.color.text
	c.TextXAlignment = Enum.TextXAlignment.Left
	c.TextTruncate = Enum.TextTruncate.AtEnd
	c.Text = text
	c.Parent = parent
	Widgets.corner(c, Theme.radius.m)
	Widgets.padding(c, Theme.space.s, 0)
	Widgets.leadIcon(c, icon, if h >= 30 then Theme.size.icon else 16, Theme.space.xs)
	return c
end

-- A small round badge (a count on a button, "NEW"): Fredoka on red (or `color`), outlined.
function Widgets.badge(parent: Instance, text: string, color: Color3?): TextLabel
	local b = Instance.new("TextLabel")
	b.Name = "Badge"
	b.Size = UDim2.fromOffset(22, 22)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BackgroundColor3 = color or Theme.color.danger
	b.BorderSizePixel = 0
	b.FontFace = Theme.font.display
	b.TextSize = Theme.text.small
	b.TextColor3 = Theme.color.text
	b.Text = text
	b.Parent = parent
	Widgets.corner(b, 11)
	Widgets.stroke(b)
	Widgets.padding(b, Theme.space.s, 0)
	return b
end

-- A progress bar (quest progress, XP): a dark track with a coloured fill. Widgets.setProgress moves it.
function Widgets.progress(parent: Instance, width: number?, height: number?, color: Color3?): Frame
	local track = Instance.new("Frame")
	track.Name = "Progress"
	track.Size = UDim2.new(if width then 0 else 1, width or 0, 0, height or 12)
	track.BackgroundColor3 = Theme.color.navyDeep
	track.BorderSizePixel = 0
	track.Parent = parent
	Widgets.corner(track, Theme.radius.s)
	Widgets.stroke(track)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color or Theme.color.gold
	fill.BorderSizePixel = 0
	fill.Parent = track
	Widgets.corner(fill, Theme.radius.s)
	return track
end

function Widgets.setProgress(track: Frame, fraction: number)
	local fill = track:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		fill.Visible = fraction > 0
	end
end

-- A panel header row: optional icon, a gold title, and a close cross at the right (Name "✕", what the harness
-- presses) when `onClose` is given. Returns the row and its title label.
function Widgets.header(parent: Instance, text: string, icon: string?, onClose: (() -> ())?): (Frame, TextLabel)
	local row = Instance.new("Frame")
	row.Name = "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	row.Parent = parent
	local title = Widgets.title(row, text, Theme.text.title, Widgets.BUTTON_HEIGHT)
	title.Size = UDim2.new(1, if onClose then -Widgets.BUTTON_HEIGHT else 0, 1, 0)
	if icon then
		Widgets.leadIcon(title, icon, Theme.size.iconButton)
	end
	if onClose then
		local close = Widgets.iconButton(row, "close", "✕", Widgets.BUTTON_HEIGHT, nil, onClose)
		close.AnchorPoint = Vector2.new(1, 0)
		close.Position = UDim2.fromScale(1, 0)
	end
	return row, title
end

-- A toast: a line (two at most) under the top bar with an icon. Widgets.setToast shows a text (a leading emoji becomes the
-- icon). Starts hidden.
function Widgets.toast(parent: Instance, top: number, width: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "Toast"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, top)
	t.Size = UDim2.fromOffset(width, Widgets.BUTTON_HEIGHT)
	t.BackgroundColor3 = Theme.color.navy
	t.BackgroundTransparency = 0
	t.BorderSizePixel = 0
	t.FontFace = Theme.font.body
	t.TextSize = Theme.text.body
	t.TextColor3 = Theme.color.text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true -- a long one takes two lines
	t.Visible = false
	t.Parent = parent
	Widgets.corner(t, Theme.radius.l)
	Widgets.stroke(t, Theme.color.gold)
	Widgets.padding(t, Theme.space.l, 0)
	Widgets.leadIcon(t, "sparkles", Theme.size.iconButton)
	return t
end

function Widgets.setToast(t: TextLabel, text: string)
	Widgets.setIconText(t, text, "sparkles")
end

-- Set the text of a label that has a lead icon (Widgets.leadIcon): a leading emoji in `text` becomes the icon
-- (else `fallback`), so strings from the server and older screens ("⚔ War!") show as pixel icon + "War!".
function Widgets.setIconText(label: TextLabel | TextButton, text: string, fallback: string)
	local icon, rest = Icons.split(text)
	local iconObj = label:FindFirstChild("Icon")
	if iconObj and iconObj:IsA("GuiObject") then
		Icons.set(iconObj, icon or fallback)
	end
	label.Text = rest
end

function Widgets.clear(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- The meta screens (shop, season pass, quests, trophies) --------------------------------------------------------

-- A full-screen panel (the shop, the season pass...): the panel look, a margin round it, hidden until opened.
-- Screens build its contents when it opens and drop them when it closes (Widgets.clear), to save GUI objects.
function Widgets.window(parent: Instance, name: string): Frame
	local f = Widgets.panel(parent, 0)
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.new(1, -2 * Theme.space.m, 1, -2 * Theme.space.m)
	f.AutomaticSize = Enum.AutomaticSize.None
	f.Visible = false
	local pad = f:FindFirstChildOfClass("UIPadding")
	if pad then -- a phone in landscape is 375 px tall at least: keep the vertical margin small
		pad.PaddingTop = UDim.new(0, Theme.space.m)
		pad.PaddingBottom = UDim.new(0, Theme.space.m)
	end
	return f
end

-- A button 44 px tall and as wide as its (optional) pixel icon and text: a price ("R$ 149", or the Glory medal and
-- "1,200"), Claim, Equip. Centre it with AnchorPoint and Position. `name` (optional) is the button's Name.
function Widgets.fitButton(
	parent: Instance,
	icon: string?,
	text: string,
	color: Color3?,
	onPress: () -> (),
	name: string?
): TextButton
	local b = Widgets.button(parent, text, 0, color, onPress)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.TextWrapped = false
	Widgets.padding(b, Theme.space.m, 0)
	if icon then
		Widgets.leadIcon(b, icon, Theme.size.icon, Theme.space.xs)
	end
	if name then
		b.Name = name
	end
	return b
end

local PAGE_LABEL = 44 -- room for "12/12" between a pager's arrows

-- A pager: a "previous" arrow, the page ("2/5") and a "next" arrow, the arrows 44 px icon buttons named `prevName`
-- and `nextName` (PrevPage and NextPage by default). Returns the row (sized to fit) and the page label.
function Widgets.pager(
	parent: Instance,
	onPrev: () -> (),
	onNext: () -> (),
	prevName: string?,
	nextName: string?
): (Frame, TextLabel)
	local s = Widgets.BUTTON_HEIGHT
	local row = Instance.new("Frame")
	row.Name = "Pager"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(2 * s + PAGE_LABEL, s)
	row.Parent = parent
	Widgets.iconButton(row, "back", prevName or "PrevPage", s, Theme.color.secondary, onPrev)
	local label = Widgets.label(row, "1/1", Theme.text.body, s)
	label.Name = "Page"
	label.FontFace = Theme.font.display
	label.Position = UDim2.fromOffset(s, 0)
	label.Size = UDim2.fromOffset(PAGE_LABEL, s)
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	local nextButton = Widgets.iconButton(row, "arrow", nextName or "NextPage", s, Theme.color.secondary, onNext)
	nextButton.Position = UDim2.fromOffset(s + PAGE_LABEL, 0)
	return row, label
end

Widgets.CORNER_BUTTON = 52 -- the Lobby's round buttons

-- A round icon button in the Lobby's bottom-left row (the shop, quests, trophies, the season pass), `slot` 0, 1,
-- 2... from the left. Widgets.cornerRowEnd(n) is where a row of n of them ends, for anything placed beside the row.
function Widgets.cornerButton(
	parent: Instance,
	slot: number,
	icon: string,
	name: string,
	color: Color3,
	onPress: () -> ()
): TextButton
	local s = Widgets.CORNER_BUTTON
	local b = Widgets.iconButton(parent, icon, name, s, color, onPress)
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(0, Theme.space.l + slot * (s + Theme.space.m), 1, -Theme.space.l)
	local round = b:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0.5, 0)
	end
	local i = b:FindFirstChild("Icon")
	if i and i:IsA("GuiObject") then
		i.Size = UDim2.fromOffset(Theme.size.iconLarge, Theme.size.iconLarge)
	end
	return b
end

function Widgets.cornerRowEnd(count: number): number
	return Theme.space.l + count * Widgets.CORNER_BUTTON + (count - 1) * Theme.space.m
end

-- A count badge at the top-right corner of a button (quests or season rewards waiting): hidden at 0.
function Widgets.countBadge(button: GuiObject): TextLabel
	local b = Widgets.badge(button, "")
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, Theme.space.xs, 0, -Theme.space.xs)
	b.Visible = false
	return b
end

function Widgets.setCount(badge: TextLabel, count: number)
	badge.Visible = count > 0
	badge.Text = tostring(count)
end

-- A status tag in a dark well (Owned, Equipped, Not today, a lock): an icon and an optional short text, sized to
-- fit. Not a button: it says why there is nothing to press.
function Widgets.tag(parent: Instance, icon: string, text: string?, height: number?): TextLabel
	local t = Widgets.chip(parent, icon, text or "", nil, height or 36)
	t.Name = "Tag"
	t.TextSize = Theme.text.small
	t.BackgroundTransparency = 0
	if text == nil or text == "" then -- just the icon, centred
		local pad = t:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingRight = UDim.new(0, Theme.space.s - Theme.space.xs)
		end
	end
	return t
end

return Widgets
