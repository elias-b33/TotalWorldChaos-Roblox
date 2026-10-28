--!strict
-- The UI kit (docs/UI_DIRECTION.md "Slate & Brass", docs/DESIGN.md "UI style"): every screen builds from these so
-- they share one look: painted pixel frames (FrameArt, shown by Frames) on slate panels with iron or brass bands,
-- enamel buttons on a thick base that sink when pressed, recessed wells for values, pixel icons (Icons) instead of
-- emoji, ink outlines on display text. Colours, fonts and sizes come from Theme.
--
-- A widget's root object is its API (its class, Name, Text, Icon child, LayoutOrder, Size): screens and the harness
-- find buttons by Name or Text. Widgets.skin adds the painted frame inside the root as a "Face" ImageLabel under
-- everything, and for text roots a "Caption" label that mirrors the root's text (the root's own text is hidden:
-- children draw over their parent). Where EditableImage isn't allowed, skin does nothing and the root keeps the
-- flat look (a fill, a corner, an ink outline and a bevel), so every widget works either way.

local TweenService = game:GetService("TweenService")

local Frames = require(script.Parent.Frames)
local Icons = require(script.Parent.Icons)
local Theme = require(script.Parent.Theme)

local Widgets = {}

Widgets.Theme = Theme
Widgets.Icons = Icons
Widgets.Frames = Frames

-- Colour names the screens already use (kept so older screens keep working), mapped onto the theme's roles.
Widgets.PANEL = Theme.color.slate800
Widgets.BUTTON = Theme.color.azure
Widgets.BUTTON_OFF = Theme.color.slate
Widgets.DANGER = Theme.color.crimson
Widgets.GOOD = Theme.color.emerald
Widgets.GOLD = Theme.color.gold
Widgets.SPECIAL = Theme.color.royal
Widgets.DISABLED = Theme.color.disabled
Widgets.BUTTON_HEIGHT = Theme.size.button

local WHITE = Color3.new(1, 1, 1)
local PRESS_IN = TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_OUT = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local PRESSED_SCALE = 0.97
local PRESS_DROP = 4 -- a pressed button's face sits 2 art px lower: its content follows

-- A button's face is its top part: the caption centres on it, clear of the 12 px base (docs/UI_DIRECTION.md 7.2).
local FACE_TOP = 2
local FACE_BOTTOM = 12

-- The flat look's buttons: full colour down to the bevel line, then a darker band (UIGradient multiplies the
-- background, so the band follows whatever colour a screen gives the button later).
local EDGE = Color3.fromRGB(150, 150, 165)
local BUTTON_GRADIENT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(1 - Theme.bevel - 0.001, WHITE),
	ColorSequenceKeypoint.new(1 - Theme.bevel, EDGE),
	ColorSequenceKeypoint.new(1, EDGE),
})
-- The flat look's panels: a gentle top-to-bottom light, lit from above like the map's mountains.
local PANEL_GRADIENT = ColorSequence.new(WHITE, Color3.fromRGB(214, 216, 228))

-- Skins ------------------------------------------------------------------------------------------------------------

type Skin = {
	face: ImageLabel,
	caption: TextLabel?,
	frame: string, -- the frame shown when up (button, well, plate...)
	style: Frames.Style, -- the style shown now
	baseColor: Color3, -- the root's BackgroundColor3 when skinned: it maps back to baseStyle
	baseStyle: Frames.Style,
	seenColor: Color3, -- the last BackgroundColor3 the face followed (signals may arrive after a restyle)
	insetTop: number, -- the root's own vertical padding under a screen's (a button's caption sits on its face)
	insetBottom: number,
	faceTop: number, -- the face's inset from the root's box (an unselected tab's well is 40 of 44 px)
	faceBottom: number,
	pressed: boolean,
}

local skins = setmetatable({} :: { [Instance]: Skin }, { __mode = "k" })

-- Theme colours that are named styles; any other colour (a nation's) gets its own computed ramp.
local NAMED: { [string]: Color3 } = {
	gold = Theme.color.gold,
	emerald = Theme.color.emerald,
	crimson = Theme.color.crimson,
	azure = Theme.color.azure,
	royal = Theme.color.royal,
	slate = Theme.color.slate,
	disabled = Theme.color.disabled,
}

-- The enamel style for a button colour: "gold", "emerald"... or the colour itself (Frames ramps it).
function Widgets.styleOf(color: Color3): Frames.Style
	for name, c in NAMED do
		if c == color then
			return name
		end
	end
	return color
end

local function luminance(c: Color3): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- Make the face cover the root's whole box: children sit inside the root's padding, so undo it.
local function fitFace(obj: GuiObject, skin: Skin)
	local pad = obj:FindFirstChildOfClass("UIPadding")
	local l, r, t, b = 0, 0, 0, 0
	if pad then
		l, r = pad.PaddingLeft.Offset, pad.PaddingRight.Offset
		t, b = pad.PaddingTop.Offset, pad.PaddingBottom.Offset
	end
	skin.face.Position = UDim2.fromOffset(-l, -t + skin.faceTop)
	skin.face.Size = UDim2.new(1, l + r, 1, t + b - skin.faceTop - skin.faceBottom)
end

-- Copy the root's text onto its caption, with an ink outline on light display text (Fredoka One captions,
-- numbers and titles; body text on slate has none, and dark text on gold never does).
local function syncCaption(root: TextLabel | TextButton, caption: TextLabel)
	caption.Text = root.Text
	caption.TextColor3 = root.TextColor3
	caption.TextSize = root.TextSize
	caption.FontFace = root.FontFace
	caption.TextXAlignment = root.TextXAlignment
	caption.TextYAlignment = root.TextYAlignment
	caption.TextWrapped = root.TextWrapped
	caption.TextTruncate = root.TextTruncate
	caption.RichText = root.RichText
	local ink = caption:FindFirstChild("Ink")
	if ink and ink:IsA("UIStroke") then
		local display = root.FontFace.Family == Theme.font.display.Family
		ink.Enabled = display and luminance(root.TextColor3) > 0.35
		ink.Thickness = if root.TextSize >= 16 then 2 else 1.5
	end
end

local MIRRORED = {
	"Text",
	"TextColor3",
	"TextSize",
	"FontFace",
	"TextXAlignment",
	"TextYAlignment",
	"TextWrapped",
	"TextTruncate",
	"RichText",
}

-- An ink outline round a text object's glyphs (2 px, 1.5 under 16 px): display text on slate and over the map.
function Widgets.textStroke(obj: TextLabel | TextButton, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Name = "Ink"
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Color = Theme.color.ink
	s.Thickness = thickness or (if obj.TextSize >= 16 then 2 else 1.5)
	s.Parent = obj
	return s
end

local function paintFace(skin: Skin)
	local frame = skin.frame
	if skin.pressed and frame == "button" then
		frame = "buttonDown"
	end
	Frames.apply(skin.face, frame, skin.style)
end

-- Give a widget its painted frame (docs/UI_DIRECTION.md 7.0): a Face ImageLabel under its content, and for text
-- roots a Caption that mirrors the root's text. `frame` is a FrameArt frame (button, well, plate, titlePlate,
-- badge...), `style` its palette or colour. Returns the face, or nil when frames are unavailable (the root keeps
-- its flat look). Skinning an already skinned widget restyles it.
function Widgets.skin(obj: GuiObject, frame: string, style: Frames.Style): ImageLabel?
	local existing = skins[obj]
	if existing then
		Widgets.restyle(obj, style, frame)
		return existing.face
	end
	if Frames.content(frame, style) == nil then
		return nil
	end
	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.BackgroundTransparency = 1
	face.ZIndex = 0
	local skin: Skin = {
		face = face,
		caption = nil,
		frame = frame,
		style = style,
		baseColor = obj.BackgroundColor3,
		baseStyle = style,
		seenColor = obj.BackgroundColor3,
		insetTop = 0,
		insetBottom = 0,
		faceTop = 0,
		faceBottom = 0,
		pressed = false,
	}
	skins[obj] = skin
	paintFace(skin)
	face.Parent = obj

	-- the face follows the root's padding (leadIcon widens it; a press shifts it). A skinned widget always has a
	-- UIPadding, and Widgets.padding reuses it, so this one is the one to watch.
	local pad = obj:FindFirstChildOfClass("UIPadding")
	if pad == nil then
		local p = Instance.new("UIPadding")
		p.Parent = obj
		pad = p
	end
	for _, prop in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
		(pad :: UIPadding):GetPropertyChangedSignal(prop):Connect(function()
			fitFace(obj, skin)
		end)
	end
	fitFace(obj, skin)

	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		local root = obj :: TextLabel
		local caption = Instance.new("TextLabel")
		caption.Name = "Caption"
		caption.BackgroundTransparency = 1
		caption.Size = UDim2.fromScale(1, 1)
		caption.ZIndex = 2
		Widgets.textStroke(caption)
		syncCaption(root, caption)
		caption.Parent = obj
		skin.caption = caption
		root.TextTransparency = 1
		for _, prop in MIRRORED do
			root:GetPropertyChangedSignal(prop):Connect(function()
				syncCaption(root, caption)
			end)
		end
	end
	-- a screen recolouring the root (setEnabled, a selected tab, a nation colour) recolours the face
	obj:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local c = obj.BackgroundColor3
		if c == skin.seenColor then
			return -- a Widgets call already restyled it
		end
		skin.seenColor = c
		local s = if c == skin.baseColor then skin.baseStyle else Widgets.styleOf(c)
		if s ~= skin.style then
			skin.style = s
			paintFace(skin)
		end
	end)

	obj.BackgroundTransparency = 1
	local outline = obj:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Enabled = false
	end
	local bevel = obj:FindFirstChild("Bevel")
	if bevel and bevel:IsA("UIGradient") then
		bevel.Enabled = false
	end
	return face
end

-- Show a skinned widget in another style (and frame); no-op on a flat one.
function Widgets.restyle(obj: GuiObject, style: Frames.Style, frame: string?)
	local skin = skins[obj]
	if skin == nil then
		return
	end
	if style == skin.style and (frame == nil or frame == skin.frame) then
		return
	end
	skin.style = style
	if frame then
		skin.frame = frame
	end
	paintFace(skin)
end

-- Whether a widget wears a painted frame (false in the flat look).
function Widgets.skinned(obj: GuiObject): boolean
	return skins[obj] ~= nil
end

-- Set the vertical padding a skinned widget keeps under its screen's own (a button's caption sits on its face).
local function setInsets(obj: GuiObject, top: number, bottom: number)
	local skin = skins[obj]
	if skin == nil then
		return
	end
	local pad = obj:FindFirstChildOfClass("UIPadding")
	if pad == nil then
		local p = Instance.new("UIPadding")
		p.Parent = obj
		pad = p
	end
	local padding = pad :: UIPadding
	padding.PaddingTop = UDim.new(0, padding.PaddingTop.Offset - skin.insetTop + top)
	padding.PaddingBottom = UDim.new(0, padding.PaddingBottom.Offset - skin.insetBottom + bottom)
	skin.insetTop, skin.insetBottom = top, bottom
	fitFace(obj, skin)
end

-- The basics ---------------------------------------------------------------------------------------------------------

function Widgets.corner(parent: GuiObject, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or Theme.radius.m)
	c.Parent = parent
	return c
end

-- Padding round an object's content (`vertical` defaults to `px`). Reuses the object's UIPadding when it has one,
-- and keeps a skinned widget's own insets (a button's caption stays on its face).
function Widgets.padding(parent: GuiObject, px: number, vertical: number?): UIPadding
	local v = vertical or px
	local existing = parent:FindFirstChildOfClass("UIPadding")
	local p = existing or Instance.new("UIPadding")
	local skin = skins[parent]
	local top = if skin then skin.insetTop else 0
	local bottom = if skin then skin.insetBottom else 0
	p.PaddingTop = UDim.new(0, v + top)
	p.PaddingBottom = UDim.new(0, v + bottom)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	if skin then
		fitFace(parent, skin)
	end
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

-- A ScreenGui for a screen. Children draw over their parent (Sibling): a widget's face sits under its caption.
function Widgets.screen(name: string, order: number?): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order or 0
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	return gui
end

-- The 2 px ink outline round a panel, button or chip (the flat look). Several strokes may share an object (the
-- tutorial's glow sits outside it, at a higher ZIndex).
function Widgets.stroke(parent: GuiObject, color: Color3?, thickness: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Name = "Outline"
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Color = color or Theme.color.ink
	s.Thickness = thickness or Theme.stroke
	s.Parent = parent
	return s
end

-- The darker bottom edge of a flat button (or a flat panel's top-to-bottom light with `panel`).
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

-- An icon `size` px square (see Icons.label): 16 beside text, 32 on buttons and tiles, 48 in reward cells.
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
	local skin = skins[obj]
	if skin then
		fitFace(obj, skin)
	end
	local icon = Icons.label(obj, name, s)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, -(s + g), 0.5, 0)
	icon.ZIndex = 2
	return icon
end

-- Buttons ------------------------------------------------------------------------------------------------------------

-- Press feedback: a skinned button swaps to its pressed frame and its content sinks 4 px; a flat one's bevel sinks.
-- Both squash a little while held.
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
			TweenService:Create(scale, if pressed then PRESS_IN else PRESS_OUT, {
				Scale = if pressed then PRESSED_SCALE else 1,
			}):Play()
		end
		local skin = skins[b]
		if skin then
			if skin.frame == "button" then
				skin.pressed = pressed
				paintFace(skin)
				local pad = b:FindFirstChildOfClass("UIPadding")
				if pad then
					local shift = if pressed then PRESS_DROP else -PRESS_DROP
					pad.PaddingTop = UDim.new(0, pad.PaddingTop.Offset + shift)
					pad.PaddingBottom = UDim.new(0, pad.PaddingBottom.Offset - shift)
					fitFace(b, skin)
				end
			end
		elseif gradient then
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

-- Paint a button: the enamel frame in its colour's style, its caption on the face.
local function skinButton(b: GuiObject, color: Color3)
	if Widgets.skin(b, "button", Widgets.styleOf(color)) then
		setInsets(b, FACE_TOP, FACE_BOTTOM)
	end
end

-- A button at least 44 px tall: an enamel face in its role's colour (Widgets.GOLD for the screen's one primary
-- action, GOOD to confirm or buy, DANGER for war and close, BUTTON for diplomacy and info, SPECIAL for Primordial
-- and season, BUTTON_OFF for secondary) on a thick base, with an outlined Fredoka One caption. Gold gets dark text.
function Widgets.button(parent: Instance, text: string, width: number, color: Color3?, onPress: () -> ()): TextButton
	local c = color or Widgets.BUTTON
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, Widgets.BUTTON_HEIGHT)
	b.BackgroundColor3 = c
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.FontFace = Theme.font.display
	b.TextSize = 16
	b.TextWrapped = true
	b.TextColor3 = if c == Widgets.GOLD then Theme.color.textDark else Theme.color.text
	b.Text = text
	b.Parent = parent
	Widgets.corner(b, Theme.radius.s)
	Widgets.stroke(b)
	local bevel = Widgets.bevel(b)
	skinButton(b, c)
	pressable(b, bevel)
	b.Activated:Connect(onPress)
	return b
end

-- A button with a pixel icon (16 px) before its text. `name` (optional) is the button's Name, e.g. its old emoji
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
	Widgets.padding(b, Theme.space.m + 2, 0)
	Widgets.leadIcon(b, icon, Theme.size.icon)
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
	local skinned = skins[b] ~= nil
	local pad = Widgets.padding(b, Theme.space.s, 0)
	if #costs > 0 then
		-- caption at the top of the face, the costs at its bottom (clear of the base, or of the flat bevel)
		pad.PaddingTop = UDim.new(0, if skinned then 5 else 7)
		pad.PaddingBottom = UDim.new(0, if skinned then 14 else 9)
	end
	Widgets.leadIcon(b, icon, Theme.size.iconButton, Theme.space.s)
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
			row.ZIndex = 2
			row.Parent = b
			Widgets.list(row, true, Theme.space.xs)
			line = row
		end
		for i, cost in costs do
			local l = Widgets.label(line, cost[2], Theme.text.small, 16)
			l.Name = "Cost"
			l.FontFace = Theme.font.display
			l.TextColor3 = if cost[1] == "gold" then Theme.color.gold else Theme.color.text
			l.Size = UDim2.fromOffset(0, 16)
			l.AutomaticSize = Enum.AutomaticSize.X
			l.TextWrapped = false
			l.LayoutOrder = i
			l.ZIndex = 2
			Widgets.textStroke(l, 1.5)
			if line == b then
				l.AnchorPoint = Vector2.new(0, 1)
				l.Position = UDim2.fromScale(0, 1)
			end
			Widgets.leadIcon(l, cost[1], Theme.size.icon, 2)
		end
	end
	if name then
		b.Name = name
	end
	return b
end

-- A square button showing just an icon (32 px on a 44 px gem). `name` is the button's Name (what the harness and
-- tutorial look for). Without a colour it is a plain icon with no plate.
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
	-- 32 px on a gem; a close cross keeps its 16 px (docs/UI_DIRECTION.md 7.1)
	local iconSize = if icon ~= "close" and (color or s >= 40) then Theme.size.iconButton else Theme.size.icon
	local i = Icons.label(b, icon, iconSize)
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Position = UDim2.fromScale(0.5, 0.5)
	i.ZIndex = 2
	return b
end

-- Grey a button out (it still gets taps: screens explain why in a toast) or give it its colour back (`color`, or
-- the one it was made with).
function Widgets.setEnabled(b: GuiButton, enabled: boolean, color: Color3?)
	local skin = skins[b]
	local base = if skin then skin.baseColor else Widgets.BUTTON
	local c = if enabled then color or base else Widgets.DISABLED
	if skin then
		skin.seenColor = c
		Widgets.restyle(b, if c == skin.baseColor then skin.baseStyle else Widgets.styleOf(c))
	end
	b.BackgroundColor3 = c
	if b:IsA("TextButton") then
		b.TextColor3 = if not enabled
			then Theme.color.textDisabled
			elseif c == Widgets.GOLD then Theme.color.textDark
			else Theme.color.text
	end
	for _, child in b:GetChildren() do
		if child.Name == "Icon" and child:IsA("GuiObject") then
			Icons.dim(child, not enabled)
		end
	end
end

-- A tab: a gold button with dark text when selected, a recessed well otherwise.
function Widgets.tab(parent: Instance, text: string, width: number, selected: boolean, onPress: () -> ()): TextButton
	local b = Widgets.button(parent, text, width, nil, onPress)
	b.TextSize = Theme.text.small + 1
	Widgets.setTab(b, selected)
	return b
end

function Widgets.setTab(b: TextButton, selected: boolean)
	local skin = skins[b]
	local c = if selected then Theme.color.gold else Theme.color.slate900
	if skin then
		skin.seenColor = c
	end
	b.BackgroundColor3 = c
	b.TextColor3 = if selected then Theme.color.textDark else Theme.color.textDim
	if skin then
		-- the well is 40 tall inside the 44 px tab; a press goes straight to selected (no pressed image)
		skin.faceTop = if selected then 0 else 2
		skin.faceBottom = if selected then 0 else 2
		Widgets.restyle(b, if selected then "gold" else "well", if selected then "button" else "well")
		fitFace(b, skin)
	end
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
	Widgets.leadIcon(c, icon, Theme.size.icon, Theme.space.xs)
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
	b.ZIndex = 3
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
		Widgets.leadIcon(title, icon, Theme.size.icon)
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
	Widgets.leadIcon(t, "sparkles", Theme.size.icon)
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

-- Drop every GUI object inside `parent` (a hidden screen keeps none), but not a skinned widget's own face and
-- caption.
function Widgets.clear(parent: Instance)
	local skin = skins[parent]
	for _, child in parent:GetChildren() do
		if child:IsA("GuiObject") and not (skin and (child == skin.face or child == skin.caption)) then
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

-- A pager: a "previous" arrow, the page ("2/5") and a "next" arrow, the arrows 44 px slate icon buttons named
-- `prevName` and `nextName` (PrevPage and NextPage by default). Returns the row (sized to fit) and the page label.
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
	Widgets.iconButton(row, "back", prevName or "PrevPage", s, Theme.color.slate, onPrev)
	local label = Widgets.label(row, "1/1", Theme.text.button, s)
	label.Name = "Page"
	label.FontFace = Theme.font.display
	label.Position = UDim2.fromOffset(s, 0)
	label.Size = UDim2.fromOffset(PAGE_LABEL, s)
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Center
	Widgets.textStroke(label)
	local nextButton = Widgets.iconButton(row, "arrow", nextName or "NextPage", s, Theme.color.slate, onNext)
	nextButton.Position = UDim2.fromOffset(s + PAGE_LABEL, 0)
	return row, label
end

Widgets.CORNER_BUTTON = 52 -- the Lobby's gem buttons

-- A gem icon button in the Lobby's bottom-left row (the shop, quests, trophies, the season pass), `slot` 0, 1,
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
	if not Widgets.skinned(b) then
		local round = b:FindFirstChildOfClass("UICorner")
		if round then -- the flat look: a disc
			round.CornerRadius = UDim.new(0.5, 0)
		end
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
