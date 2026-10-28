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

local FrameArt = require(script.Parent.Parent.FrameArt)
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

-- Tablets ------------------------------------------------------------------------------------------------------------

-- The UI grows on big screens (Theme.uiScale): each screen's root objects carry a "DeviceScale" UIScale. Their
-- Size and Position stay written in phone px: the scale parts of a Size shrink by the scale (a full-screen window
-- still fills the screen) and the offsets of a Position grow by it (a corner button's margin grows with it).
type Placed = { size: UDim2, position: UDim2, scale: UIScale }
local placed = setmetatable({} :: { [Instance]: Placed }, { __mode = "k" })
local scaleListeners: { () -> () } = {}

local function viewportScale(): number
	local camera = workspace.CurrentCamera
	return Theme.uiScale(if camera then camera.ViewportSize else Vector2.new(844, 390))
end

local currentScale = viewportScale()

-- The UI's scale on this device: 1 on phones, more on tablets.
function Widgets.uiScale(): number
	return currentScale
end

-- Call `fn` whenever the UI's scale changes (a window resized, a device rotated in Studio).
function Widgets.onScale(fn: () -> ())
	table.insert(scaleListeners, fn)
end

local function applyFit(root: GuiObject, p: Placed)
	local k = currentScale
	root.Size = UDim2.new(p.size.X.Scale / k, p.size.X.Offset, p.size.Y.Scale / k, p.size.Y.Offset)
	root.Position = UDim2.new(p.position.X.Scale, p.position.X.Offset * k, p.position.Y.Scale, p.position.Y.Offset * k)
	p.scale.Scale = k
end

-- Scale a screen's root object for the device. `size` and `position` (optional) are its new Size and Position in
-- phone px; without them it keeps the ones it has (the first call) or was last given. Call it again whenever a
-- screen moves or resizes the root.
function Widgets.fit(root: GuiObject, size: UDim2?, position: UDim2?)
	local p = placed[root]
	if p == nil then
		local existing = root:FindFirstChild("DeviceScale")
		local scale: UIScale = if existing and existing:IsA("UIScale") then existing else Instance.new("UIScale")
		scale.Name = "DeviceScale"
		scale.Parent = root
		p = { size = size or root.Size, position = position or root.Position, scale = scale }
		placed[root] = p
	else
		if size then
			p.size = size
		end
		if position then
			p.position = position
		end
	end
	applyFit(root, p :: Placed)
end

-- Fit every root object of a screen (call at the end of its init, once its roots are placed).
function Widgets.fitScreen(gui: ScreenGui)
	for _, child in gui:GetChildren() do
		if child:IsA("GuiObject") then
			Widgets.fit(child)
		end
	end
end

local viewCamera = workspace.CurrentCamera
if viewCamera then
	viewCamera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		local k = viewportScale()
		if k == currentScale then
			return
		end
		currentScale = k
		for root, p in placed do
			if root.Parent then
				applyFit(root :: GuiObject, p)
			end
		end
		for _, fn in scaleListeners do
			task.spawn(fn)
		end
	end)
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

-- Materials (docs/UI_DIRECTION.md 6.1): iron bands on in-match sheets and panels, brass on reward and meta windows,
-- slate plates for popovers and toasts, raised plates for cards, recessed wells for values. Each: its painted frame
-- and style, and the flat look's fill, ink outline, inner band stroke and corner.
type Material = {
	frame: string,
	style: Frames.Style,
	fill: Color3,
	outline: boolean,
	band: Color3?,
	bandThickness: number,
	radius: number,
	light: boolean,
}

local MATERIALS: { [string]: Material } = {
	iron = {
		frame = "window",
		style = "windowIron",
		fill = Theme.color.slate800,
		outline = true,
		band = Theme.color.iron400,
		bandThickness = 2,
		radius = Theme.radius.m,
		light = true,
	},
	brass = {
		frame = "window",
		style = "window",
		fill = Theme.color.slate800,
		outline = true,
		band = Theme.color.brass400,
		bandThickness = 2,
		radius = Theme.radius.m,
		light = true,
	},
	plate = {
		frame = "plate",
		style = "plate",
		fill = Theme.color.slate800,
		outline = true,
		band = nil,
		bandThickness = 2,
		radius = Theme.radius.s,
		light = true,
	},
	raised = {
		frame = "plate",
		style = "plateRaised",
		fill = Theme.color.slate700,
		outline = true,
		band = nil,
		bandThickness = 2,
		radius = Theme.radius.s,
		light = false,
	},
	well = {
		frame = "well",
		style = "well",
		fill = Theme.color.slate900,
		outline = false,
		band = Theme.color.slate850,
		bandThickness = 1,
		radius = Theme.radius.s,
		light = false,
	},
}

-- A rarity's frame: the window grid with its band in the rarity's colour (shop cards, season reward cells).
local function rarityMaterial(color: Color3): Material
	return {
		frame = "window",
		style = color,
		fill = Theme.color.slate800,
		outline = true,
		band = color,
		bandThickness = 2,
		radius = Theme.radius.m,
		light = true,
	}
end

type Dress = { corner: UICorner, outline: UIStroke, band: UIStroke, light: UIGradient }
local dressed = setmetatable({} :: { [Instance]: Dress }, { __mode = "k" })

-- Dress a container in a material ("iron", "brass", "plate", "raised", "well", or a rarity colour): an ImageLabel
-- shows its painted frame as its own image, under its content; anything else, or a device without
-- EditableImage, gets the flat look (a fill, a corner, an ink outline, an inner band stroke and a gentle light).
-- Dressing it again changes its material.
function Widgets.material(obj: GuiObject, material: string | Color3)
	local m = if typeof(material) == "Color3" then rarityMaterial(material) else MATERIALS[material] or MATERIALS.iron
	local parts = dressed[obj]
	if parts == nil then
		local corner = obj:FindFirstChildOfClass("UICorner") or Widgets.corner(obj, m.radius)
		local outline = Widgets.stroke(obj)
		outline.ZIndex = 1
		local band = Instance.new("UIStroke")
		band.Name = "Band"
		band.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		band.BorderStrokePosition = Enum.BorderStrokePosition.Inner
		band.ZIndex = 2
		band.Parent = obj
		local light = Widgets.bevel(obj, true)
		parts = { corner = corner, outline = outline, band = band, light = light }
		dressed[obj] = parts
	end
	local d = parts :: Dress
	d.corner.CornerRadius = UDim.new(0, m.radius)
	obj.BackgroundColor3 = m.fill
	d.band.Color = m.band or m.fill
	d.band.Thickness = m.bandThickness
	local painted = obj:IsA("ImageLabel") and Frames.apply(obj :: any, m.frame, m.style)
	obj.BackgroundTransparency = if painted then 1 else 0
	d.outline.Enabled = not painted and m.outline
	d.band.Enabled = not painted and m.band ~= nil
	d.light.Enabled = not painted and m.light
end

-- A drop shadow (docs/UI_DIRECTION.md 6.6): "window" under windows and sheets, "plate" under plates over the map,
-- "button" under buttons over the map. Hard pixel shadows in ink, following the object's corner.
function Widgets.shadow(obj: GuiObject, kind: string?): UIShadow
	local spec = (Theme.shadow :: any)[kind or "window"] or Theme.shadow.window
	local existing = obj:FindFirstChild("Shadow")
	local s: UIShadow = if existing and existing:IsA("UIShadow") then existing else Instance.new("UIShadow")
	s.Name = "Shadow"
	s.Color = Theme.color.ink
	s.BlurRadius = UDim.new(0, 0)
	s.Offset = UDim2.fromOffset(0, spec.y)
	s.Transparency = spec.transparency
	s.Parent = obj
	return s
end

-- A soft glow in a colour under rare shop cards and claimable rewards (`color` nil removes it).
function Widgets.glow(obj: GuiObject, color: Color3?)
	local existing = obj:FindFirstChild("Glow")
	if color == nil then
		if existing then
			existing:Destroy()
		end
		return
	end
	local g: UIShadow = if existing and existing:IsA("UIShadow") then existing else Instance.new("UIShadow")
	g.Name = "Glow"
	g.Color = color
	g.BlurRadius = UDim.new(0, Theme.shadow.glow.blur)
	g.Offset = UDim2.new()
	g.Transparency = Theme.shadow.glow.transparency
	g.Parent = obj
end

-- A container: an ImageLabel (so its frame is its own image, under whatever layout a screen puts in it), typed as a
-- Frame for the screens. Active, so taps and drags on it never reach the map.
local function container(parent: Instance, material: string | Color3): Frame
	local f = Instance.new("ImageLabel")
	f.Active = true
	f.BorderSizePixel = 0
	f.Parent = parent
	Widgets.material(f, material)
	return (f :: any) :: Frame
end

Widgets.PANEL_PAD = Theme.frame.pad.side -- a framed panel's padding left and right

-- The padding inside a material's frame: window frames 16 at the sides, 18 at the top (22 under a title plate), 14
-- at the bottom; plates 10 and 8.
local function framePadding(f: GuiObject, material: string | Color3)
	local pad = f:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	local plate = material == "plate" or material == "raised" or material == "well"
	local side = if plate then 10 else Theme.frame.pad.side
	pad.PaddingLeft = UDim.new(0, side)
	pad.PaddingRight = UDim.new(0, side)
	pad.PaddingTop = UDim.new(0, if plate then 8 else Theme.frame.pad.topBare)
	pad.PaddingBottom = UDim.new(0, if plate then 8 else Theme.frame.pad.bottom)
	pad.Parent = f
end

-- A framed panel that grows to fit its content vertically: iron by default (in-match drawers and sheets), "brass"
-- for reward and meta screens, "plate" for popovers. It drops a hard shadow.
function Widgets.panel(parent: Instance, width: number, material: (string | Color3)?): Frame
	local m = material or "iron"
	local f = container(parent, m)
	f.Size = UDim2.fromOffset(width, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	framePadding(f, m)
	Widgets.shadow(f, if m == "plate" then "plate" else "window")
	return f
end

-- The screen a widget is on, in GUI px (not divided by the device scale): its ScreenGui's size once laid out,
-- else the camera's viewport.
function Widgets.screenSize(obj: Instance?): Vector2
	local gui = if obj then obj:FindFirstAncestorWhichIsA("LayerCollector") else nil
	if gui and gui:IsA("ScreenGui") then
		local ok, size = pcall(function()
			return gui.AbsoluteSize
		end)
		if ok and size.X > 0 then
			return size
		end
	end
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(844, 390)
end

Widgets.POWER_ROOM = 84 -- the power button and its margin at the bottom right: sheets stay clear of it

-- Dock a sheet at the bottom: centred when it fits beside the power button, else at the left (a small phone),
-- never wider than the screen allows (docs/UI_DIRECTION.md 7.1).
local function dock(f: GuiObject, width: number)
	local screen = Widgets.screenSize(f) / currentScale -- in phone px: the sheet grows by the device scale
	local room = screen.X - 2 * Theme.space.m - (if screen.X < 744 then Widgets.POWER_ROOM else 0)
	local w = math.min(width, room)
	w -= w % 2
	if (screen.X + w) / 2 <= screen.X - Widgets.POWER_ROOM then
		f.AnchorPoint = Vector2.new(0.5, 1)
		Widgets.fit(f, UDim2.fromOffset(w, 0), UDim2.new(0.5, 0, 1, -Theme.space.m))
	else
		f.AnchorPoint = Vector2.new(0, 1)
		Widgets.fit(f, UDim2.fromOffset(w, 0), UDim2.new(0, Theme.space.m, 1, -Theme.space.m))
	end
end

-- A bottom sheet: an iron panel docked to the bottom, `width` wide when the screen has room. Centred beside the
-- power button, or docked left on a small phone.
function Widgets.sheet(parent: Instance, width: number): Frame
	local f = Widgets.panel(parent, width)
	dock(f, width)
	local gui = f:FindFirstAncestorWhichIsA("LayerCollector")
	if gui then
		gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			dock(f, width)
		end)
	end
	Widgets.onScale(function()
		dock(f, width)
	end)
	return f
end

-- A raised card inside a panel (a shop item, a quest, a map in the vote): a raised slate plate.
function Widgets.card(parent: Instance, width: number?, height: number?): Frame
	local f = container(parent, "raised")
	f.Active = false
	f.Size = UDim2.new(if width then 0 else 1, width or 0, 0, height or 0)
	f.AutomaticSize = if height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y
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

-- A title: Fredoka One in gold, outlined in ink.
function Widgets.title(parent: Instance, text: string, size: number?, height: number?): TextLabel
	local l = Widgets.label(parent, text, size or Theme.text.heading, height or 28)
	l.FontFace = Theme.font.display
	l.TextColor3 = Theme.color.gold
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	Widgets.textStroke(l)
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
		-- one UIScale per object: a screen's root button squashes its device scale
		local p = placed[b]
		local base = if p then currentScale else 1
		if scale == nil then
			if p then
				scale = p.scale
			elseif pressed then
				local s = Instance.new("UIScale")
				s.Parent = b
				scale = s
			end
		end
		if scale then
			TweenService:Create(scale, if pressed then PRESS_IN else PRESS_OUT, {
				Scale = base * (if pressed then PRESSED_SCALE else 1),
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

-- A recessed well behind a text widget: its painted frame, or the flat look (a dark fill, a light inner edge).
local function well(obj: GuiObject)
	if not Widgets.skin(obj, "well", "well") then
		Widgets.material(obj, "well")
	end
end

-- A chip: an icon and a value in a recessed well ("💰 120" as a pixel coin and a number): the icon 16 px at x 6, the
-- text from x 28. Fixed `width`, or as wide as its text without one. Returns the chip (set its Text); its icon is
-- the child "Icon" (Icons.set).
function Widgets.chip(parent: Instance, icon: string, text: string, width: number?, height: number?): TextLabel
	local h = height or Theme.size.chip
	local c = Instance.new("TextLabel")
	c.Name = "Chip"
	c.Size = UDim2.fromOffset(width or 0, h)
	c.AutomaticSize = if width then Enum.AutomaticSize.None else Enum.AutomaticSize.X
	c.BackgroundColor3 = Theme.color.slate900
	c.BorderSizePixel = 0
	c.FontFace = Theme.font.display
	c.TextSize = if h >= 30 then 17 else Theme.text.body
	c.TextColor3 = Theme.color.text
	c.TextXAlignment = Enum.TextXAlignment.Left
	c.TextTruncate = Enum.TextTruncate.AtEnd
	c.Text = text
	c.Parent = parent
	Widgets.padding(c, Theme.space.s, 0).PaddingRight = UDim.new(0, Theme.space.m)
	Widgets.leadIcon(c, icon, Theme.size.icon, Theme.space.s)
	well(c)
	return c
end

-- A counter (the top bar's gold, manpower and clock, Glory in the shop): a 32 px well `width` wide with a 32 px
-- icon riding over its left end and the number in Fredoka One 18, outlined, from x 28. Leave 10 px free left of it
-- for the icon. Returns the counter (set its Text); its icon is the child "Icon".
function Widgets.counter(parent: Instance, icon: string?, text: string, width: number): TextLabel
	local c = Instance.new("TextLabel")
	c.Name = "Counter"
	c.Size = UDim2.fromOffset(width, Theme.size.counter)
	c.BackgroundColor3 = Theme.color.slate900
	c.BorderSizePixel = 0
	c.FontFace = Theme.font.display
	c.TextSize = Theme.text.heading
	c.TextColor3 = Theme.color.text
	c.TextXAlignment = Enum.TextXAlignment.Left
	c.TextTruncate = Enum.TextTruncate.AtEnd
	c.Text = text
	c.Parent = parent
	local pad = Widgets.padding(c, 0, 0)
	pad.PaddingLeft = UDim.new(0, 28)
	pad.PaddingRight = UDim.new(0, Theme.space.s)
	if icon then
		local i = Icons.label(c, icon, Theme.size.iconButton)
		i.AnchorPoint = Vector2.new(0, 0.5)
		i.Position = UDim2.new(0, -38, 0.5, 0)
		i.ZIndex = 3
	end
	well(c)
	if not Widgets.skinned(c) then
		Widgets.textStroke(c)
	end
	Widgets.shadow(c, "counter")
	return c
end

local MEDALLIONS: { [string]: string } = { small = "medallionSmall", normal = "medallion", large = "medallionLarge" }

-- The colour a frame style stands for (a named colour, or the colour itself).
local function colorOf(style: Frames.Style): Color3
	if typeof(style) == "Color3" then
		return style
	end
	local hex = FrameArt.COLORS[style :: string] or FrameArt.COLORS.slate
	return Color3.fromHex(string.format("%06x", hex))
end

-- Show a medallion in another colour (a phase's): its painted octagon, or the flat look's disc.
function Widgets.setMedallion(m: ImageLabel, style: Frames.Style)
	local frame = (m:GetAttribute("Medallion") :: string?) or "medallion"
	local look = if style == "power" then "royal" else style
	if Frames.apply(m, frame, style) then
		return
	end
	m.BackgroundTransparency = 0
	m.BackgroundColor3 = colorOf(look)
	if m:FindFirstChildOfClass("UICorner") == nil then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = m
		Widgets.stroke(m)
	end
end

-- A medallion (docs/UI_DIRECTION.md 6.7): an octagon ring in a colour round a well, with an icon. `size` is
-- "small" (32 px: toasts), "normal" (40 px: the clock) or "large" (64 px: the power button). Returns the medallion
-- and its icon (Icons.set changes it).
function Widgets.medallion(parent: Instance, size: string, style: Frames.Style, icon: string): (ImageLabel, GuiObject)
	local frame = MEDALLIONS[size] or "medallion"
	local px = Frames.size(frame).X
	local m = Instance.new("ImageLabel")
	m.Name = "Medallion"
	m.Size = UDim2.fromOffset(px, px)
	m.BackgroundTransparency = 1
	m.BorderSizePixel = 0
	m.ZIndex = 3
	m:SetAttribute("Medallion", frame)
	m.Parent = parent
	Widgets.setMedallion(m, style)
	local i = Icons.label(m, icon, if px >= 64 then Theme.size.iconButton else Theme.size.icon)
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Position = UDim2.fromScale(0.5, 0.5)
	i.ZIndex = 4
	return m, i
end

-- A small badge (a count on a button, "NEW"): Fredoka One 14 on a crimson enamel pill (or `color`; gold gets dark
-- text), outlined.
function Widgets.badge(parent: Instance, text: string, color: Color3?): TextLabel
	local c = color or Theme.color.crimson
	local b = Instance.new("TextLabel")
	b.Name = "Badge"
	b.Size = UDim2.fromOffset(22, 22)
	b.AutomaticSize = Enum.AutomaticSize.X
	b.BackgroundColor3 = c
	b.BorderSizePixel = 0
	b.FontFace = Theme.font.display
	b.TextSize = Theme.text.small
	b.TextColor3 = if c == Theme.color.gold then Theme.color.textDark else Theme.color.text
	b.Text = text
	b.ZIndex = 4
	b.Parent = parent
	Widgets.corner(b, 11)
	Widgets.stroke(b)
	Widgets.padding(b, Theme.space.s, 0)
	Widgets.skin(b, "badge", Widgets.styleOf(c))
	return b
end

-- A progress bar (quest progress, XP): a recessed well with a fill inset 3 px, lit from the top in the bar's colour
-- (gold for XP and levels, emerald for quests, royal for the season). Widgets.setProgress moves it.
function Widgets.progress(parent: Instance, width: number?, height: number?, color: Color3?): Frame
	local track = container(parent, "well")
	track.Name = "Progress"
	track.Active = false
	track.Size = UDim2.new(if width then 0 else 1, width or 0, 0, height or 14)
	local face = color or Theme.color.gold
	local tones = FrameArt.ramp(tonumber(face:ToHex(), 16) or 0)
	local function tone(code: string): Color3
		return Color3.fromHex(string.format("%06x", tones[code]))
	end
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Position = UDim2.fromOffset(3, 3)
	fill.Size = UDim2.new(0, 0, 1, -6)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = track
	local light = Instance.new("UIGradient")
	light.Name = "Light"
	light.Rotation = 90
	light.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, tone("H")),
		ColorSequenceKeypoint.new(0.25, tone("F")),
		ColorSequenceKeypoint.new(0.75, tone("F")),
		ColorSequenceKeypoint.new(1, tone("S")),
	})
	light.Parent = fill
	return track
end

function Widgets.setProgress(track: Frame, fraction: number)
	local fill = track:FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		local f = math.clamp(fraction, 0, 1)
		fill.Size = UDim2.new(f, -6 * f, 1, -6) -- inside the well's 3 px rim
		fill.Visible = fraction > 0
	end
end

-- A brass title plate (docs/UI_DIRECTION.md 7.1): 28 px tall, as wide as its title, an optional 16 px icon, white
-- Fredoka One outlined in ink, a hard shadow. Widgets.header puts one on a window's top edge.
function Widgets.titlePlate(parent: Instance, text: string, icon: string?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.Size = UDim2.fromOffset(0, Theme.size.titlePlate)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.BackgroundColor3 = Theme.color.brass400
	t.BorderSizePixel = 0
	t.FontFace = Theme.font.display
	t.TextSize = Theme.text.title
	t.TextColor3 = Theme.color.text
	t.TextWrapped = false
	t.Text = text
	t.ZIndex = 3
	t.Parent = parent
	Widgets.corner(t, Theme.radius.s)
	Widgets.stroke(t)
	local pad = Widgets.padding(t, 10, 0)
	if icon then
		Widgets.leadIcon(t, icon, Theme.size.icon, Theme.space.s)
	end
	if Widgets.skin(t, "titlePlate", "titlePlate") then
		-- the caption sits on the plate's face, above its darker bottom rows
		pad.PaddingBottom = UDim.new(0, 5)
	else
		Widgets.textStroke(t)
	end
	Widgets.shadow(t, "title")
	return t
end

-- The corner close button: a crimson gem with a 16 px cross, named "✕" (what the harness presses).
function Widgets.closeButton(parent: Instance, onClose: () -> ()): TextButton
	local b = Widgets.iconButton(parent, "close", "✕", Widgets.BUTTON_HEIGHT, Widgets.DANGER, onClose)
	b.ZIndex = 3
	return b
end

-- A window's header (docs/UI_DIRECTION.md 7.1): the title plate centred on its top edge, 16 px from its left, and
-- the close gem overhanging its top-right corner when `onClose` is given. The header row itself takes no room:
-- put it first in the window (it is LayoutOrder -1). Returns the row and the title plate (set its Text later).
function Widgets.header(parent: Instance, text: string, icon: string?, onClose: (() -> ())?): (Frame, TextLabel)
	local row = Instance.new("Frame")
	row.Name = "Header"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0)
	row.LayoutOrder = -1
	row.ZIndex = 3
	row.Parent = parent
	local title = Widgets.titlePlate(row, text, icon)
	local close = if onClose then Widgets.closeButton(row, onClose) else nil
	local host = parent :: GuiObject
	local pad = host:FindFirstChildOfClass("UIPadding")
	if pad == nil then
		pad = Widgets.padding(host, Theme.frame.pad.side, 0)
	end
	local padding = pad :: UIPadding
	-- the content starts under the plate: 22 px down, less the gap a list puts after this zero-height row
	local list = host:FindFirstChildOfClass("UIListLayout")
	local gap = if list and list.FillDirection == Enum.FillDirection.Vertical then list.Padding.Offset else 0
	padding.PaddingTop = UDim.new(0, Theme.frame.pad.top - gap)
	local function place()
		local top = padding.PaddingTop.Offset
		title.Position = UDim2.fromOffset(Theme.frame.pad.side - padding.PaddingLeft.Offset, -top - 14)
		if close then
			close.Position = UDim2.new(1, padding.PaddingRight.Offset - 36, 0, -top - 16)
		end
	end
	place()
	for _, prop in { "PaddingTop", "PaddingLeft", "PaddingRight" } do
		padding:GetPropertyChangedSignal(prop):Connect(place)
	end
	return row, title
end

-- A toast: a line (two at most) under the top bar on a slate plate with a hard shadow, an icon at its left.
-- Widgets.setToast shows a text (a leading emoji becomes the icon). Starts hidden.
function Widgets.toast(parent: Instance, top: number, width: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "Toast"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, top)
	t.Size = UDim2.fromOffset(width, Widgets.BUTTON_HEIGHT)
	t.BackgroundColor3 = Theme.color.slate800
	t.BackgroundTransparency = 0
	t.BorderSizePixel = 0
	t.FontFace = Theme.font.body
	t.TextSize = Theme.text.body
	t.TextColor3 = Theme.color.text
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true -- a long one takes two lines
	t.Visible = false
	t.Parent = parent
	Widgets.corner(t, Theme.radius.s)
	Widgets.stroke(t)
	Widgets.padding(t, Theme.space.l, 0)
	Widgets.leadIcon(t, "sparkles", Theme.size.icon)
	Widgets.skin(t, "plate", "plate")
	Widgets.shadow(t, "plate")
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

-- A full-screen window (the shop, the season pass...): a brass frame 8 px from the screen's edges (16 at the top,
-- for its title plate), a hard shadow, and the screen dimmed behind it. Hidden until opened; the dim follows it.
-- Screens build its contents when it opens and drop them when it closes (Widgets.clear), to save GUI objects.
function Widgets.window(parent: Instance, name: string): Frame
	local dim = Instance.new("Frame")
	dim.Name = name .. "Dim"
	dim.Active = true -- taps on the dim never reach the map
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Theme.color.slate950
	dim.BackgroundTransparency = 0.4
	dim.BorderSizePixel = 0
	dim.ZIndex = 0
	dim.Visible = false
	dim.Parent = parent
	local f = Widgets.panel(parent, 0, "brass")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.5, Theme.space.xs)
	f.Size = UDim2.new(1, -2 * Theme.space.m, 1, -3 * Theme.space.m)
	f.AutomaticSize = Enum.AutomaticSize.None
	f.Visible = false
	Widgets.fit(f)
	f:GetPropertyChangedSignal("Visible"):Connect(function()
		dim.Visible = f.Visible
	end)
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
	Widgets.fit(b, nil, UDim2.new(0, Theme.space.l + slot * (s + Theme.space.m), 1, -Theme.space.l))
	Widgets.shadow(b, "plate")
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

-- A status tag in a recessed well (Owned, Equipped, Not today, a lock): an icon and an optional short text in
-- Builder Sans Bold, sized to fit. Not a button: it says why there is nothing to press.
function Widgets.tag(parent: Instance, icon: string, text: string?, height: number?): TextLabel
	local t = Widgets.chip(parent, icon, text or "", nil, height or 36)
	t.Name = "Tag"
	t.FontFace = Theme.font.body
	t.TextSize = Theme.text.body
	if text == nil or text == "" then -- just the icon, centred
		local pad = t:FindFirstChildOfClass("UIPadding")
		if pad then
			pad.PaddingRight = UDim.new(0, Theme.space.s - Theme.space.xs)
		end
	end
	return t
end

return Widgets
