--!strict
-- What is drawn on the 2D map (docs/DESIGN.md "Map rendering"): the pixel-art image painted by PixelArt
-- (terrain, owners, the selected province, each race's capitals), straits, province names with their development
-- pips, army tokens (a soldier of its main troop, or its token skin) gliding from province to province with their
-- strength badges (the icon of the troop type an army is mostly made of), each province's status pills (battle,
-- siege, Primordial powers, blockades), the coalition leader's crown and route lines. Everything sits on MapView's
-- canvas, placed in map pixels. The terrain is painted in the match's map theme (Cosmetics.matchTheme).
--
-- Navies (docs/DESIGN.md "Navies"): each fleet is the map's ship (Cosmetics.shipLabel) in its nation's colours at its
-- sea zone's centre, gliding from zone to zone, with a strength badge (its ships and the men aboard); fleets resting
-- in one zone sit side by side. Zoomed out, each zone's name stands under its centre in quiet italics wherever it
-- covers no province name. Taps on the water find a zone in the sea grid (MapGrid.decodeSea).
--
-- The overlays share the UI kit's look (UI/Theme, UI/Icons): names in Builder Sans with an ink outline, pips as a
-- pixel bar, badges and pills as dark plates with a pixel icon and Fredoka One numbers. What they say and where they
-- stack comes from MapBadges. Armies resting in one province stand side by side and their badges stack in a column
-- above them, with the province's status row on top, so nothing covers anything at any zoom.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local CatchUp = require(Shared.Sim.CatchUp)
local Config = require(Shared.Config)
local MapGrid = require(Shared.MapGrid)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local Cosmetics = require(script.Parent.Cosmetics)
local HudLayout = require(script.Parent.UI.HudLayout)
local Icons = require(script.Parent.UI.Icons)
local LabelLayout = require(script.Parent.LabelLayout)
local MapBadges = require(script.Parent.MapBadges)
local MapView = require(script.Parent.MapView)
local Palette = require(script.Parent.Palette)
local PixelArt = require(script.Parent.PixelArt)
local RaceInfo = require(script.Parent.RaceInfo)
local Relations = require(script.Parent.Relations)
local ShopState = require(script.Parent.ShopState)
local Theme = require(script.Parent.UI.Theme)
local Widgets = require(script.Parent.UI.Widgets)

local NAME_MIN_PIXELS = 70 -- a province's name shows once the province is this wide on screen
local NAME_RELAYOUT = 0.04 -- names are laid out again when the zoom changes by this share
local NAME_OFFSET = 6 -- screen pixels between a province's centre and the top of its name
local CAPITAL_FOOT = 3 -- map pixels from a capital's centre down to its building's foot (PixelArt); its name clears it
local NAME_HEIGHT = 18
local PIPS_SCALE = 2 -- screen pixels per pixel of the development pip bar (MapBadges.pips)
local PIPS_GAP = 1 -- screen pixels between a name and its pips
local DETAIL_ZOOM = 0.9 -- garrisons and development pips show from this share of the region zoom inwards
local TEXT_SIZE = Theme.text.small -- the smallest text on the map (docs/DESIGN.md "UI and controls")
local TOKEN_SIZE = 14 -- army token, screen pixels
local TOKEN_SKIN_SIZE = 18 -- a token skin's 12×12 sprite, screen pixels
local TOKEN_PICK = 20 -- a tap this close to a token's centre (screen pixels) picks the army
local TOKEN_LIFT = 4 -- map pixels: armies resting in a province stand this far above its centre (its name is below)
local TOKEN_SLOT = 18 -- screen pixels between armies resting side by side in one province
local TOKEN_SMOOTHING = 6 -- higher = tokens catch up with their target faster
local MORALE_BAR_HEIGHT = 4 -- the morale bar under a token (an ink track with the fill inside), screen pixels
local MORALE_COLORS: { [string]: Color3 } =
	{ good = Theme.color.emerald, low = Theme.color.gold, broken = Theme.color.crimson }
local BADGE_HEIGHT = 20 -- strength badges and status pills, screen pixels
local BADGE_GAP = 2 -- between a token and its badge, and between stacked badges
local BADGE_ICON = 16 -- the pixel icon in a badge or pill
local BADGE_PAD = 4 -- inside a pill, left of its icon and right of its text
local BADGE_TEXT_GAP = 2 -- between a pill's icon and its text
local GARRISON_PRIORITY = -1e6 -- idle garrisons' badges claim room after every province name (LabelLayout)
local FLEET_WIDTH, FLEET_HEIGHT = 32, 24 -- a fleet's 16×12 ship, screen pixels (2 a sprite pixel: it reads on dark space)
local FLEET_PICK = 26 -- a tap this close to a fleet's centre (screen pixels) picks it
local FLEET_SLOT = 36 -- screen pixels between fleets resting side by side in one zone
local ZONE_NAME_OFFSET = 6 -- screen pixels between a zone's centre and the top of its name (its fleets stand above)
local ZONE_PRIORITY = -1e5 -- zone names claim room after every province name, bigger zones first (LabelLayout)
local ZONE_LABEL_ID = 1e5 -- zone names' ids in the label layout (provinces use their own ids, garrisons negative ones)
local CAPITAL_BOX_ID = -1e6 -- the capitals' flag-and-army corners in the label layout, kept clear of zone names
local STATUS_WIDTH = 240 -- a province's status row (its pills are centred in it)
local CROWN_SIZE = Theme.size.icon -- the coalition leader's crown, on top of its flag pole
local NOTICE_TOP = 60 -- the "map art is off" notice: screen pixels under the top bars, below the toasts' line
local NOTICE_WIDTH = 420
local DOT_SPACING = 4 -- map pixels between the dots of a route or strait
local PIXELATED_FROM = 1.5 -- zoom from which map pixels are drawn hard-edged (smooth below, so thin lines don't flicker)
local PAINT_SLICE = 0.008 -- seconds of painting per frame while a map is painted for the first time
-- The close-up detail (PixelArt.paintDetail): a second image laid over the part of the map in view when zoomed in.
local DETAIL_FROM = 4 -- screen pixels per map pixel from which it shows (more if the screen is too big for it)
local DETAIL_OFF = 0.85 -- it is freed again below this share of that zoom
local DETAIL_WIDTH = 1024 -- its image's width; the height follows the screen's shape (at most 1024)
local DETAIL_COVER = 0.8 -- the view fills at most this share of it, so a short pan stays inside it
local DETAIL_SETTLE = 0.15 -- seconds the view keeps still before the close-up is repainted around it
local DETAIL_SLICE = 0.006 -- seconds of close-up painting per frame
local FLAG_WIDTH, FLAG_HEIGHT = 24, 18 -- a capital's 16×12 flag, screen pixels
local FLAG_RIGHT, FLAG_BOTTOM = -10, 8 -- the flag's pole stands left of the capital's centre: its bottom right corner
local POLE = 3 -- the pole's width plus the gap before the flag
local EMOTE_SIZE = 26 -- capital emote icon, screen pixels
local VICTORY_SIZE = 32 -- victory animation over a winner's capital
local VICTORY_FRAME_SECONDS = 0.4
local _, PIP_BAR_W, PIP_BAR_H = MapBadges.pips(0, Config.Economy.MaxDevelopment) -- the pip bar's size in pixels

local MapRenderer = {}

-- A pill: a dark plate with an outline, a pixel icon and Fredoka One text (or the icon alone), as wide as its content.
type Pill = { label: TextLabel, stroke: UIStroke, pad: UIPadding, icon: GuiObject }

type Token = {
	frame: Frame,
	stroke: UIStroke,
	badge: Pill, -- the army's strength: state icon and size, outlined in its nation's colour
	pos: Vector2,
	target: Vector2,
	neutral: boolean, -- a neutral garrison: hidden below the region zoom
	rebel: boolean, -- Rebels: owner 0 too, but always shown, with the Rebels' flag
	owner: number,
	province: number,
	skinned: boolean, -- drawn with a token skin sprite (no square outline unless selected)
	half: number, -- half the token's size on screen
	resting: boolean, -- standing in its province (not marching between two)
	slotX: number, -- screen pixels left or right of its province's anchor, beside the others resting there
	row: number, -- its badge's row in the province's stack (-1 while hidden)
	text: string, -- what its badge shows now
	icon: string,
	troops: string, -- its composition as last seen (ArmyRecord.troops), and the troop type it is mostly made of
	troop: string?,
	morale: number, -- the morale its bar shows (-1: no bar), and the bar once it has one
	moraleBar: Frame?,
}

-- A province's status row: battle or siege, a blockade, and Primordial-power effects (MapBadges.status).
type Status = { row: Frame, pills: { Pill }, lift: number }

-- What placing a token beside others and stacking its badge needs (armies and fleets alike).
type Badged = { frame: Frame, badge: Pill, pos: Vector2, slotX: number, row: number }

-- A fleet's token: the map's ship in its nation's colours, its badge (state icon, ships and men aboard).
type FleetToken = {
	frame: Frame,
	stroke: UIStroke,
	badge: Pill,
	pos: Vector2,
	target: Vector2,
	owner: number,
	zone: number, -- the zone it is in (or leaving)
	skinned: boolean, -- drawn with the ship sprite (no square outline unless selected)
	resting: boolean, -- standing in its zone (not sailing between two)
	slotX: number,
	row: number,
	text: string,
	icon: string,
}

local grid: MapGrid.Grid? = nil
local art: PixelArt.Art? = nil
local image: EditableImage? = nil
local imageLabel: ImageLabel? = nil
local size = Vector2.new(1024, 512)
local generation = 0 -- bumps with every new map, so a painting finished for an old one is ignored
local grids: { [string]: MapGrid.Grid } = {} -- decoded grids by map id
local arts: { [string]: PixelArt.Art } = {} -- painted maps by map id and resolution (one theme each), reused
local painting: { map: Types.MapDef, grid: MapGrid.Grid }? = nil -- what the current map is painted from
local warned = false
local artOffNotice: TextLabel? = nil -- the "map art is off" notice, kept under the top bar when the bar moves
local closeUp: PixelArt.Detail? = nil -- the close-up, its image and the label showing it (nil when zoomed out)
local detailImage: EditableImage? = nil
local detailLabel: ImageLabel? = nil
local detailAllowed = false -- full resolution only, and not after the device refused the image
local detailJob = 0 -- bumps with every close-up paint; a paint that is no longer the latest stops
local detailBusy = false
local viewKey = "" -- where the view was last frame, and how long it has stayed there
local viewStill = 0
local layers: { [string]: Frame } = {}
local widths: { [number]: number } = {} -- each province's width in map pixels
local capitalAt: { [number]: boolean } = {} -- the capitals' provinces (their names stand below the building)
local namesLaidOut = { zoom = -1, detail = false }
local idleLaidOut: { [number]: boolean } = {} -- the idle garrisons the last layout placed (army ids)
local roomy: { [number]: boolean } = {} -- those of them whose badge had room
-- each province's name (its pips under it) and the name's width on screen
local labels: { [number]: { name: TextLabel, pips: GuiObject, width: number, development: number } } = {}
local pipImages: { [number]: EditableImage | false } = {} -- the pip bar for each development level (false: no image)
local provinceStates: {
	[number]: { battle: boolean, siege: number?, siegeBy: number, owner: number, blockade: number },
} =
	{}
local effectTexts: { [number]: string } = {} -- Primordial-power badges from Powers (MapRenderer.setEffect)
local statuses: { [number]: Status } = {}
local crowns: { [number]: GuiObject } = {}
local tokens: { [number]: Token } = {}
local groups: { [number]: { number } } = {} -- each province's badge stack: armies resting there, then leaving it
local stackShown: { [number]: number } = {} -- strength badges shown in each province's stack
local stackHalf: { [number]: number } = {} -- half the biggest token in each province's stack
local detailShown = false -- garrisons, pips and every army's size show (the region zoom inwards)
local flags: { [number]: { frame: Frame, key: string } } = {}
local victories: { { label: TextLabel, frames: { string } } } = {}
local victoryClock = 0
local selectedArmy: number? = nil
local selectedProvince: number? = nil
-- navies
local seaGrid: MapGrid.Grid? = nil -- which sea zone each pixel of the current map is in, at the province grid's size
local seaGrids: { [string]: MapGrid.Grid } = {} -- decoded sea grids by map id (full resolution)
local wraps = false -- the map runs on across its left and right edges (Earth's Pacific)
local zoneLabels: { [number]: { label: TextLabel, width: number, area: number } } = {}
local fleetTokens: { [number]: FleetToken } = {}
local fleetGroups: { [number]: { number } } = {} -- each zone's badge stack: fleets resting there, then leaving it
local selectedFleet: number? = nil

local function at(p: Vector2): UDim2
	return UDim2.fromScale(p.X / size.X, p.Y / size.Y)
end

-- A province's centre in map pixels.
function MapRenderer.centerOf(provinceId: number): Vector2
	local map = ClientState.map()
	local g = grid
	if map == nil or g == nil then
		return Vector2.zero
	end
	local c = map.provinces[provinceId].center
	return Vector2.new(c.x, c.y) / g.scale
end

-- A sea zone's centre in map pixels (where its name and fleets stand).
function MapRenderer.zoneCenterOf(zoneId: number): Vector2
	local def = Relations.zone(zoneId)
	local g = grid
	if def == nil or g == nil then
		return Vector2.zero
	end
	return Vector2.new(def.center.x, def.center.y) / g.scale
end

-- A province's rough radius in map pixels (from its area).
function MapRenderer.radiusOf(provinceId: number): number
	local map = ClientState.map()
	local g = grid
	if map == nil or g == nil then
		return 0
	end
	return math.sqrt(map.provinces[provinceId].area / (g.scale * g.scale) / math.pi)
end

local function layer(name: string, parent: Frame): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	layers[name] = frame
	return frame
end

-- Map text: Builder Sans in warm white with a solid ink outline, so it reads on every terrain and on the close-up.
local function textLabel(parent: Instance, value: string): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = Theme.font.body
	label.TextSize = TEXT_SIZE
	label.TextColor3 = Theme.color.text
	label.TextStrokeColor3 = Theme.color.ink
	label.TextStrokeTransparency = 0
	label.Text = value
	label.Parent = parent
	return label
end

local function newPill(parent: Instance, name: string, icon: string, edge: Color3): Pill
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromOffset(0, BADGE_HEIGHT)
	label.AutomaticSize = Enum.AutomaticSize.X
	label.BackgroundColor3 = Theme.color.navyDeep
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.FontFace = Theme.font.display
	label.TextSize = TEXT_SIZE
	label.TextColor3 = Theme.color.text
	label.Text = ""
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Theme.radius.s)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = edge
	stroke.Thickness = 1
	stroke.Parent = label
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, BADGE_PAD + BADGE_ICON)
	pad.PaddingRight = UDim.new(0, BADGE_PAD)
	pad.Parent = label
	local iconLabel = Icons.label(label, icon, BADGE_ICON)
	iconLabel.AnchorPoint = Vector2.new(0, 0.5)
	iconLabel.Position = UDim2.new(0, -BADGE_ICON, 0.5, 0)
	label.Parent = parent
	return { label = label, stroke = stroke, pad = pad, icon = iconLabel }
end

-- Change what a pill shows (only what differs).
local function setPill(pill: Pill, icon: string, text: string, edge: Color3?)
	if pill.label.Text ~= text then
		pill.label.Text = text
		local gap = if text == "" then 0 else BADGE_TEXT_GAP
		pill.pad.PaddingLeft = UDim.new(0, BADGE_PAD + BADGE_ICON + gap)
		pill.icon.Position = UDim2.new(0, -(BADGE_ICON + gap), 0.5, 0)
	end
	Icons.set(pill.icon, icon)
	if edge and pill.stroke.Color ~= edge then
		pill.stroke.Color = edge
	end
end

-- The pip bar for a development level: one small EditableImage per level, shared by every province (nil when the
-- device can't make one; the pips are text then).
local function pipImage(level: number): EditableImage?
	local cached = pipImages[level]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local pixels, w, h = MapBadges.pips(level, Config.Economy.MaxDevelopment)
	local ok, result = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or result == nil then
		pipImages[level] = false
		return nil
	end
	local editable = result :: EditableImage
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
	pipImages[level] = editable
	return editable
end

local function pipText(development: number): string
	return string.rep("●", development) .. string.rep("○", Config.Economy.MaxDevelopment - development)
end

-- A province's development under its name: the pixel pip bar, or text pips without EditableImage.
local function pipsLabel(parent: Instance, development: number): GuiObject
	local bar = pipImage(development)
	local obj: GuiObject
	if bar then
		local l = Instance.new("ImageLabel")
		l.BackgroundTransparency = 1
		l.ResampleMode = Enum.ResamplerMode.Pixelated
		l.ImageContent = Content.fromObject(bar)
		l.Size = UDim2.fromOffset(PIP_BAR_W * PIPS_SCALE, PIP_BAR_H * PIPS_SCALE)
		obj = l
	else
		local l = textLabel(parent, pipText(development))
		l.TextColor3 = Theme.color.gold
		l.Size = UDim2.fromOffset(100, 16)
		obj = l
	end
	obj.Name = "Pips"
	obj.AnchorPoint = Vector2.new(0.5, 0)
	obj.Position = UDim2.new(0.5, 0, 1, PIPS_GAP)
	obj.Parent = parent
	return obj
end

local function setPips(obj: GuiObject, development: number)
	if obj:IsA("ImageLabel") then
		local bar = pipImage(development)
		if bar then
			obj.ImageContent = Content.fromObject(bar)
		end
	elseif obj:IsA("TextLabel") then
		obj.Text = pipText(development)
	end
end

-- The pip bar for a development level (the province sheet shows it in a well), and its size in pixels; nil
-- without EditableImage.
function MapRenderer.pipBar(level: number): (Content?, Vector2)
	local bar = pipImage(level)
	return if bar then Content.fromObject(bar) else nil, Vector2.new(PIP_BAR_W, PIP_BAR_H)
end

-- The height the pips take under a name (the layout keeps names and pips clear of each other).
local PIPS_HEIGHT = PIPS_GAP + PIP_BAR_H * PIPS_SCALE

local function packed(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local function nationColor(nationId: number): Color3
	local nation = ClientState.nation(nationId)
	return if nation then Palette.nation(nation.colorIndex) else Palette.garrison
end

-- Dots from a to b (map pixels) on a layer: straits and routes. `clip` leaves out the dots off the map's sides.
local function dots(parent: Frame, a: Vector2, b: Vector2, color: Color3, dotSize: number, clip: boolean?)
	local n = math.max(1, math.floor((b - a).Magnitude / DOT_SPACING))
	for i = 0, n do
		local p = a:Lerp(b, i / n)
		if not clip or (p.X >= 0 and p.X <= size.X) then
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = at(p)
			dot.Size = UDim2.fromOffset(dotSize, dotSize)
			dot.BackgroundColor3 = color
			dot.BorderSizePixel = 0
			dot.Parent = parent
		end
	end
end

-- On a map that runs on across its sides, two points more than half the map apart are joined the short way round,
-- over the edge.
local function acrossEdge(a: Vector2, b: Vector2): number
	if wraps and math.abs(b.X - a.X) > size.X / 2 then
		return if b.X > a.X then -size.X else size.X
	end
	return 0
end

-- Dots between two zone centres, over the map's edge when that is the short way.
local function seaDots(parent: Frame, a: Vector2, b: Vector2, color: Color3, dotSize: number)
	local shift = acrossEdge(a, b)
	if shift == 0 then
		dots(parent, a, b, color, dotSize)
	else
		dots(parent, a, b + Vector2.new(shift, 0), color, dotSize, true)
		dots(parent, a - Vector2.new(shift, 0), b, color, dotSize, true)
	end
end

-- The point `t` of the way from one zone centre to the next (over the map's edge when that is the short way).
local function seaLerp(a: Vector2, b: Vector2, t: number): Vector2
	local shift = acrossEdge(a, b)
	if shift == 0 then
		return a:Lerp(b, t)
	end
	local p = a:Lerp(b + Vector2.new(shift, 0), t)
	return Vector2.new(p.X % size.X, p.Y)
end

-- Neutral garrisons and development pips show from the region zoom inwards (it depends on the screen size).
local function detailVisible(z: number): boolean
	return z >= MapView.regionZoom() * DETAIL_ZOOM
end

-- Where armies resting in a province stand (map pixels): a little above its centre, clear of its name.
local function anchorOf(provinceId: number): Vector2
	return MapRenderer.centerOf(provinceId) - Vector2.new(0, TOKEN_LIFT)
end

-- Where fleets resting in a zone stand (map pixels): a little above its centre, clear of its name.
local function fleetAnchorOf(zoneId: number): Vector2
	return MapRenderer.zoneCenterOf(zoneId) - Vector2.new(0, TOKEN_LIFT)
end

-- A neutral garrison alone in its province and not fighting: its badge shows only where it has room.
local function idleGarrison(token: Token): boolean
	local group = groups[token.province]
	return token.neutral and token.resting and token.icon ~= "battle" and group ~= nil and #group == 1
end

-- Whether the idle garrisons are no longer the ones the last layout placed.
local function garrisonsChanged(): boolean
	local n = 0
	for id, token in tokens do
		if idleGarrison(token) then
			if not idleLaidOut[id] then
				return true
			end
			n += 1
		end
	end
	for _ in idleLaidOut do
		n -= 1
	end
	return n ~= 0
end

-- How far below its province's centre a name stands, in screen pixels: a capital's name stands clear of its
-- building (each race's own, painted round the centre), which grows with the zoom.
local function nameOffset(provinceId: number, z: number): number
	if capitalAt[provinceId] then
		return math.max(NAME_OFFSET, math.ceil(CAPITAL_FOOT * z) + 2)
	end
	return NAME_OFFSET
end

-- Names of provinces wide enough on screen, minus any that would overlap a bigger province's name; then, from the
-- region zoom inwards, each idle garrison's badge wherever it covers no name and no garrison badge placed before it
-- (bigger provinces first; the others keep their grey token until there's room). True when it laid them out again.
local function layoutNames(z: number, detail: boolean, force: boolean?): boolean
	local last = namesLaidOut
	if not force and last.detail == detail and last.zoom > 0 and math.abs(z / last.zoom - 1) < NAME_RELAYOUT then
		return false
	end
	namesLaidOut = { zoom = z, detail = detail }
	for id in capitalAt do
		local label = labels[id]
		if label then
			label.name.Position = at(MapRenderer.centerOf(id)) + UDim2.fromOffset(0, nameOffset(id, z))
		end
	end
	local boxes: { LabelLayout.Box } = {}
	for id, label in labels do
		local width = widths[id] or 0
		if width * z >= NAME_MIN_PIXELS then
			local c = MapRenderer.centerOf(id) * z
			table.insert(boxes, {
				id = id,
				x = c.X - label.width / 2,
				y = c.Y + nameOffset(id, z),
				w = label.width,
				h = if detail then NAME_HEIGHT + PIPS_HEIGHT else NAME_HEIGHT,
				priority = width,
			})
		end
	end
	-- zoomed out, the sea zones' names, wherever they cover no province name, no capital's flag and no army standing
	-- at a capital (those corners are placed after every province name, so they never hide one)
	if not detail then
		for id in capitalAt do
			local c = MapRenderer.centerOf(id) * z
			local top = c.Y - TOKEN_LIFT * z - TOKEN_SKIN_SIZE
			table.insert(boxes, {
				id = CAPITAL_BOX_ID - id,
				x = c.X + FLAG_RIGHT - FLAG_WIDTH - POLE,
				y = top,
				w = FLAG_WIDTH + POLE - FLAG_RIGHT + TOKEN_SKIN_SIZE / 2,
				h = c.Y + FLAG_BOTTOM - top,
				priority = -1,
			})
		end
		for id, zone in zoneLabels do
			local c = MapRenderer.zoneCenterOf(id) * z
			table.insert(boxes, {
				id = ZONE_LABEL_ID + id,
				x = c.X - zone.width / 2,
				y = c.Y + ZONE_NAME_OFFSET,
				w = zone.width,
				h = NAME_HEIGHT,
				priority = ZONE_PRIORITY + zone.area,
			})
		end
	end
	idleLaidOut = {}
	if detail then
		for id, token in tokens do
			if idleGarrison(token) then
				idleLaidOut[id] = true
				-- its badge, centred over its token: as wide as its padding, icon and text
				local a = anchorOf(token.province) * z
				local w = BADGE_PAD * 2 + BADGE_ICON + BADGE_TEXT_GAP + LabelLayout.textWidth(token.text, TEXT_SIZE)
				table.insert(boxes, {
					id = -id, -- (names use province ids)
					x = a.X - w / 2,
					y = a.Y - token.half - BADGE_GAP - BADGE_HEIGHT,
					w = w,
					h = BADGE_HEIGHT,
					priority = GARRISON_PRIORITY + (widths[token.province] or 0),
				})
			end
		end
	end
	local shown = LabelLayout.place(boxes)
	for id, label in labels do
		label.name.Visible = shown[id] == true
		label.pips.Visible = detail
	end
	for id, zone in zoneLabels do
		zone.label.Visible = shown[ZONE_LABEL_ID + id] == true
	end
	roomy = {}
	for id in idleLaidOut do
		roomy[id] = shown[-id] == true
	end
	return true
end

-- An army's strength badge shows from the region zoom inwards (an idle garrison's only where it has room, see
-- layoutNames); zoomed out, only on your own armies, Rebels and the selected army, so a busy map isn't a pile of
-- numbers.
local function badgeShown(id: number, token: Token): boolean
	if id == selectedArmy then
		return true
	elseif idleGarrison(token) then
		return detailShown and roomy[id] == true
	end
	local me = ClientState.myNation()
	return detailShown or token.rebel or (me ~= 0 and token.owner == me)
end

-- A badge's place: `row` rows above its token, centred over the armies (or fleets) resting beside it.
local function placeBadge(token: Badged, row: number)
	local label = token.badge.label
	local visible = row >= 0
	if label.Visible ~= visible then
		label.Visible = visible
	end
	if visible and token.row ~= row then
		label.Position = UDim2.new(0.5, -token.slotX, 0, -BADGE_GAP - row * (BADGE_HEIGHT + BADGE_GAP))
	end
	token.row = if visible then row else -1
end

local function placeStatus(provinceId: number, status: Status)
	local lift = MapBadges.statusLift(
		stackHalf[provinceId] or 0,
		BADGE_GAP,
		stackShown[provinceId] or 0,
		BADGE_HEIGHT + BADGE_GAP
	)
	if status.lift ~= lift then
		status.lift = lift
		status.row.Position = at(anchorOf(provinceId)) + UDim2.fromOffset(0, -lift)
	end
end

-- Stack the strength badges of the armies in each province in a column above them (the first shown lowest) and
-- stand each province's status row on top. Run when armies come, go or start marching, when the zoom detail flips
-- and when the selection changes.
local function stackBadges()
	stackShown, stackHalf = {}, {}
	for provinceId, ids in groups do
		local shown, half = 0, 0
		for _, id in ids do
			local token = tokens[id]
			if token then
				half = math.max(half, token.half)
				if token.frame.Visible and badgeShown(id, token) then
					placeBadge(token, shown)
					shown += 1
				else
					placeBadge(token, -1)
				end
			end
		end
		stackShown[provinceId], stackHalf[provinceId] = shown, half
	end
	for provinceId, status in statuses do
		placeStatus(provinceId, status)
	end
end

-- A fleet's strength badge shows like an army's: from the region zoom inwards, and zoomed out on your own fleets, the
-- selected one and fleets in a sea battle.
local function fleetBadgeShown(id: number, token: FleetToken): boolean
	local me = ClientState.myNation()
	return id == selectedFleet or detailShown or (me ~= 0 and token.owner == me) or token.icon == "battle"
end

-- Stack the badges of the fleets in each zone in a column above them (the first shown lowest).
local function stackFleets()
	for _, ids in fleetGroups do
		local shown = 0
		for _, id in ids do
			local token = fleetTokens[id]
			if token then
				if fleetBadgeShown(id, token) then
					placeBadge(token, shown)
					shown += 1
				else
					placeBadge(token, -1)
				end
			end
		end
	end
end

-- Is this province's status yours to follow closely (your land, or your siege)?
local function involvesMe(provinceId: number): boolean
	local me = ClientState.myNation()
	local state = provinceStates[provinceId]
	return me ~= 0 and state ~= nil and (state.owner == me or state.siegeBy == me)
end

local function statusEdge(icon: string): Color3
	if icon == "battle" then
		return Theme.color.danger
	elseif icon == "hourglass" then
		return Theme.color.gold
	elseif icon == "anchor" then
		return Theme.color.azure -- a blockade
	end
	return Theme.color.special -- Primordial powers
end

-- A province's status row: its battle or siege, then Primordial-power effects, each a pill. Zoomed out, only the
-- icons show unless it is your province or your siege. Made on demand and destroyed once empty, so the provinces
-- that once had a battle or a siege don't keep hidden objects for the rest of the match.
-- A blockade's anchor shows from the region zoom inwards, and zoomed out on your own coast or where you blockade, so a
-- war at sea doesn't sprinkle anchors over every coast of the whole map.
local function blockadeShown(provinceId: number): boolean
	local state = provinceStates[provinceId]
	if state == nil or state.blockade == 0 then
		return false
	end
	local me = ClientState.myNation()
	return detailShown or involvesMe(provinceId) or (me ~= 0 and state.blockade == me)
end

local function renderStatus(provinceId: number)
	local state = provinceStates[provinceId]
	local brief = not detailShown and not involvesMe(provinceId)
	local pills = MapBadges.status(
		state ~= nil and state.battle,
		if state then state.siege else nil,
		effectTexts[provinceId],
		brief,
		blockadeShown(provinceId)
	)
	local status = statuses[provinceId]
	if #pills == 0 then
		if status then
			status.row:Destroy()
			statuses[provinceId] = nil
		end
		return
	end
	if status == nil then
		local parent = layers.Markers
		if parent == nil then
			return
		end
		local row = Instance.new("Frame")
		row.Name = "Status" .. provinceId
		row.AnchorPoint = Vector2.new(0.5, 1)
		row.Size = UDim2.fromOffset(STATUS_WIDTH, BADGE_HEIGHT)
		row.BackgroundTransparency = 1
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Center
		list.Padding = UDim.new(0, BADGE_GAP + 1)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = row
		row.Parent = parent
		local made: Status = { row = row, pills = {}, lift = -1 }
		statuses[provinceId] = made
		status = made
	end
	local s = status :: Status
	for i, p in pills do
		local pill = s.pills[i]
		if pill == nil then
			pill = newPill(s.row, "Pill", p.icon, statusEdge(p.icon))
			pill.label.LayoutOrder = i
			s.pills[i] = pill
		end
		setPill(pill, p.icon, p.text, statusEdge(p.icon))
	end
	for i = #s.pills, #pills + 1, -1 do
		s.pills[i].label:Destroy()
		s.pills[i] = nil
	end
	s.row.Visible = true
	placeStatus(provinceId, s)
end

-- Everything that depends on the zoom: names, garrisons, badges, how much the status pills say, and how the pixels
-- are sampled.
local function onZoom(z: number)
	local detail = detailVisible(z)
	local relaid = layoutNames(z, detail)
	if relaid and detail == detailShown and detail then
		stackBadges() -- garrison badges that found room, or lost it
	end
	if detail ~= detailShown then
		detailShown = detail
		for _, token in tokens do
			if token.neutral then
				token.frame.Visible = detail
			end
		end
		stackBadges()
		stackFleets()
		for provinceId in statuses do
			renderStatus(provinceId)
		end
		for provinceId, state in provinceStates do
			if state.blockade ~= 0 and statuses[provinceId] == nil then
				renderStatus(provinceId) -- other nations' blockades show from the region zoom
			end
		end
	end
	local label = imageLabel
	if label then
		local mode = if z >= PIXELATED_FROM then Enum.ResamplerMode.Pixelated else Enum.ResamplerMode.Default
		if label.ResampleMode ~= mode then
			label.ResampleMode = mode
		end
	end
end

-- An EditableImage of this size: the current one if it fits, else a new one (the old one is destroyed, freeing
-- its memory right away). nil when the device or the game settings don't allow it.
local function imageFor(w: number, h: number): EditableImage?
	local current = image
	if current and current.Size.X == w and current.Size.Y == h then
		return current
	end
	if current then
		current:Destroy()
		image = nil
	end
	local ok, result = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if ok and result then
		image = result
		return result
	end
	return nil
end

-- Send part of a painting to its image: only the changed rectangle (x0, y0, x1, y1), unless most of it changed.
local function upload(editable: EditableImage, pixels: buffer, width: number, height: number, d: { number })
	local x0, y0, x1, y1 = d[1], d[2], d[3], d[4]
	local w, h = x1 - x0 + 1, y1 - y0 + 1
	if w * h * 2 >= width * height then
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)
		return
	end
	local rect = buffer.create(w * h * 4)
	for row = 0, h - 1 do
		buffer.copy(rect, row * w * 4, pixels, ((y0 + row) * width + x0) * 4, w * 4)
	end
	editable:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), rect)
end

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(800, 600)
end

-- The close-up's image size for this screen, and the zoom it shows from (where the screen fits well inside it).
local function detailSize(vp: Vector2): (number, number)
	local f = PixelArt.DETAIL.factor
	local h = math.ceil(DETAIL_WIDTH * vp.Y / math.max(vp.X, 1) / f) * f
	return DETAIL_WIDTH, math.clamp(h, 16 * f, 1024)
end

local function detailZoom(vp: Vector2): number
	local w, h = detailSize(vp)
	local f = PixelArt.DETAIL.factor
	return math.max(DETAIL_FROM, vp.X / (w / f * DETAIL_COVER), vp.Y / (h / f * DETAIL_COVER))
end

-- Free the close-up and its image (zoomed out, a new map), so phones get the memory back right away.
local function freeDetail()
	detailJob += 1
	detailBusy = false
	closeUp = nil
	if detailLabel then
		detailLabel:Destroy()
		detailLabel = nil
	end
	if detailImage then
		detailImage:Destroy()
		detailImage = nil
	end
end

-- Paint the close-up around a map point, a few milliseconds per frame (the old one stays up meanwhile), then show it.
local function startDetail(a: PixelArt.Art, vp: Vector2, centre: Vector2)
	local w, h = detailSize(vp)
	local d = closeUp
	if d == nil or d.width ~= w or d.height ~= h then
		freeDetail()
		local ok, result = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		end)
		local imageLayer = layers.Image
		if not ok or result == nil or imageLayer == nil then
			detailAllowed = false -- the device can't spare it: the map stays as it is
			return
		end
		detailImage = result
		local label = Instance.new("ImageLabel")
		label.Name = "Detail"
		label.BackgroundTransparency = 1
		label.ResampleMode = Enum.ResamplerMode.Pixelated
		label.ZIndex = 2
		label.Visible = false
		label.ImageContent = Content.fromObject(result)
		label.Parent = imageLayer
		detailLabel = label
		d = PixelArt.newDetail(w, h)
		closeUp = d
	end
	local target = d :: PixelArt.Detail
	local x0, y0 = PixelArt.detailOrigin(a, target, centre.X, centre.Y)
	detailJob += 1
	local job = detailJob
	detailBusy = true
	task.spawn(function()
		local last = os.clock()
		local ok = pcall(PixelArt.paintDetail, a, target, x0, y0, function()
			if detailJob ~= job then
				error("a newer close-up replaced this one")
			end
			if os.clock() - last > DETAIL_SLICE then
				task.wait()
				last = os.clock()
			end
		end)
		if detailJob ~= job then
			return
		end
		detailBusy = false
		local editable, label = detailImage, detailLabel
		if not ok or art ~= a or closeUp ~= target or editable == nil or label == nil then
			return
		end
		PixelArt.takeDetailDirty(target)
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(target.width, target.height), target.pixels)
		label.Position = UDim2.fromScale(target.x0 / size.X, target.y0 / size.Y)
		label.Size = UDim2.fromScale(target.cols / size.X, target.rows / size.Y)
		label.Visible = true
	end)
end

-- Once a frame: show the close-up when zoomed in far enough, repaint it when the view has settled somewhere it
-- doesn't cover, catch it up with ownership and selection changes, and free it when zoomed out.
local function stepDetail(dt: number)
	local a = art
	if a == nil or not detailAllowed or imageLabel == nil then
		if detailImage then
			freeDetail()
		end
		return
	end
	local vp = viewportSize()
	local z = MapView.zoom()
	if z < detailZoom(vp) * (if detailImage then DETAIL_OFF else 1) then
		if detailImage then
			freeDetail()
		end
		return
	end
	local p0, p1 = MapView.toMap(Vector2.zero), MapView.toMap(vp)
	local key = string.format("%d,%d,%d", math.floor(p0.X), math.floor(p0.Y), math.floor(z * 50))
	if key ~= viewKey then
		viewKey, viewStill = key, 0
	else
		viewStill += dt
	end
	local d, label, editable = closeUp, detailLabel, detailImage
	if d and label and editable and not detailBusy then
		if d.painted ~= a then
			label.Visible = false -- painted from an older painting (another theme)
		elseif
			math.max(p0.X, 0) >= d.x0
			and math.max(p0.Y, 0) >= d.y0
			and math.min(p1.X, a.width) <= d.x0 + d.cols
			and math.min(p1.Y, a.height) <= d.y0 + d.rows
		then
			if PixelArt.syncDetail(a, d) then
				local rect = PixelArt.takeDetailDirty(d)
				if rect then
					upload(editable, d.pixels, d.width, d.height, rect)
				end
			end
			return
		end
	end
	if not detailBusy and viewStill >= DETAIL_SETTLE then
		startDetail(a, vp, (p0 + p1) / 2)
	end
end

-- Owners and nation colours from the snapshot into the pixel art.
local function paintOwners()
	local a = art
	local snapshot = ClientState.snapshot()
	if a == nil or snapshot == nil then
		return
	end
	local owners: { [number]: number } = {}
	for _, record in snapshot.provinces do
		owners[record.id] = record.owner
	end
	local colors: { [number]: number } = {}
	local borders: { [number]: number } = {}
	local styles: { [number]: PixelArt.NationStyle } = {}
	for _, nation in snapshot.nations do
		colors[nation.id] = packed(Palette.nation(nation.colorIndex))
		borders[nation.id] = packed(Palette.border(nation.colorIndex))
		-- border style and shade set (cosmetics): always shades of the nation's own colours
		local c = Cosmetics.of(nation.id)
		local border, shades = Cosmetics.art(c.border), Cosmetics.art(c.shades)
		if border ~= "solid" or shades ~= "default" then
			styles[nation.id] = { border = border, shades = shades }
		end
	end
	PixelArt.setStyles(a, styles)
	PixelArt.setOwners(a, owners, colors, borders)
end

-- Each nation's flag (its equipped cosmetic) on a little pole left of its capital (armies stand at the centre),
-- while it holds the capital.
local function refreshFlags()
	local snapshot = ClientState.snapshot()
	local flagLayer = layers.Flags
	if snapshot == nil or flagLayer == nil then
		return
	end
	local owners: { [number]: number } = {}
	for _, record in snapshot.provinces do
		owners[record.id] = record.owner
	end
	local alive: { [number]: boolean } = {}
	for _, nation in snapshot.nations do
		local show = not nation.eliminated and owners[nation.capital] == nation.id
		local flagId = Cosmetics.of(nation.id).flag
		local key = flagId .. ":" .. nation.colorIndex
		local entry = flags[nation.id]
		if entry and (not show or entry.key ~= key) then
			entry.frame:Destroy()
			flags[nation.id] = nil
			entry = nil
		end
		if show and entry == nil then
			local holder = Instance.new("Frame")
			holder.Name = "Flag" .. nation.id
			holder.AnchorPoint = Vector2.new(1, 1)
			holder.Position = at(MapRenderer.centerOf(nation.capital)) + UDim2.fromOffset(FLAG_RIGHT, FLAG_BOTTOM)
			holder.Size = UDim2.fromOffset(FLAG_WIDTH + POLE, FLAG_HEIGHT + 8)
			holder.BackgroundTransparency = 1
			holder.Parent = flagLayer
			local pole = Instance.new("Frame")
			pole.Name = "Pole"
			pole.Size = UDim2.new(0, POLE - 1, 1, 0)
			pole.BackgroundColor3 = Theme.color.ink
			pole.BorderSizePixel = 0
			pole.Parent = holder
			local flag =
				Cosmetics.flagLabel(holder, flagId, nation.colorIndex, UDim2.fromOffset(FLAG_WIDTH, FLAG_HEIGHT))
			flag.Position = UDim2.fromOffset(POLE, 0)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.color.ink
			stroke.Thickness = 1
			stroke.Parent = flag
			flags[nation.id] = { frame = holder, key = key }
		end
		alive[nation.id] = true
	end
	for id, entry in flags do
		if not alive[id] then
			entry.frame:Destroy()
			flags[id] = nil
		end
	end
end

-- A capital emote (MatchEvent "Emote": a = nation, b = emote index, province = capital) for a few seconds.
local function showEmote(e: Types.MatchEvent)
	local item = Catalogue.ofSlot("Emote")[e.b]
	local emoteLayer = layers.Emotes
	if item == nil or emoteLayer == nil or e.province == 0 then
		return
	end
	local label = textLabel(emoteLayer, item.art)
	label.Name = "Emote" .. e.a
	label.TextSize = EMOTE_SIZE
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = at(MapRenderer.centerOf(e.province)) + UDim2.fromOffset(0, -58)
	label.Size = UDim2.fromOffset(EMOTE_SIZE + 12, EMOTE_SIZE + 8)
	label.BackgroundColor3 = Theme.color.navyDeep
	label.BackgroundTransparency = 0.15
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.color.ink
	stroke.Thickness = Theme.stroke
	stroke.Parent = label
	local myGeneration = generation
	task.delay(Config.Shop.EmoteShowSeconds, function()
		if generation == myGeneration then
			label:Destroy()
		end
	end)
end

-- The winners' victory animations over their capitals while Results shows (frames of the item's art, cycled).
local function refreshVictory()
	local snapshot = ClientState.snapshot()
	local victoryLayer = layers.Emotes
	for _, v in victories do
		v.label:Destroy()
	end
	victories = {}
	local result = if snapshot then snapshot.result else nil
	if result == nil or victoryLayer == nil then
		return
	end
	for _, nationId in result.winners do
		local nation = ClientState.nation(nationId)
		if nation then
			local frames = string.split(Cosmetics.art(Cosmetics.of(nationId).victory), " ")
			local label = textLabel(victoryLayer, frames[1] or "🏆")
			label.Name = "Victory" .. nationId
			label.TextSize = VICTORY_SIZE
			label.AnchorPoint = Vector2.new(0.5, 1)
			label.Position = at(MapRenderer.centerOf(nation.capital)) + UDim2.fromOffset(0, -32)
			label.Size = UDim2.fromOffset(VICTORY_SIZE + 16, VICTORY_SIZE + 8)
			table.insert(victories, { label = label, frames = frames })
		end
	end
end

-- The painted map in the match's theme: reused from an earlier match on this map if it has that theme, or painted
-- now, a few milliseconds per frame (the old painting stays up meanwhile). Only one theme per map is kept.
local function paintMap()
	local job = painting
	if job == nil then
		return
	end
	local map, g = job.map, job.grid
	local look = Cosmetics.matchTheme()
	local background = Palette.background[map.theme] or Palette.background.earth
	local canvas = MapView.canvas()
	local back = if canvas then canvas.Parent else nil
	if back and back:IsA("Frame") then
		local themed = PixelArt.themeColor(look, packed(background), false, map.theme == "sky")
		back.BackgroundColor3 =
			Color3.fromRGB(bit32.rshift(themed, 16), bit32.band(bit32.rshift(themed, 8), 255), bit32.band(themed, 255))
	end
	local key = map.id .. ":" .. g.width
	local cached = arts[key]
	if cached and cached.look == look then
		art = cached
		PixelArt.select(cached, nil)
		PixelArt.invalidate(cached)
		return
	end
	local myGeneration = generation
	task.spawn(function()
		local last = os.clock()
		local painted = PixelArt.new(map, g, function()
			if os.clock() - last > PAINT_SLICE then
				task.wait()
				last = os.clock()
			end
		end, look)
		arts[key] = painted
		if generation == myGeneration and Cosmetics.matchTheme() == look then
			local old = art
			art = painted
			if old then
				PixelArt.select(painted, old.selected)
			end
			paintOwners()
			PixelArt.invalidate(painted)
		end
	end)
end

local function build(map: Types.MapDef)
	generation += 1
	freeDetail()
	labels = {}
	provinceStates = {}
	effectTexts = {}
	statuses = {}
	crowns = {}
	tokens = {}
	groups = {}
	stackShown, stackHalf = {}, {}
	flags = {}
	victories = {}
	layers = {}
	widths = {}
	capitalAt = {}
	namesLaidOut = { zoom = -1, detail = false }
	idleLaidOut, roomy = {}, {}
	detailShown = false
	selectedArmy = nil
	selectedProvince = nil
	zoneLabels = {}
	fleetTokens = {}
	fleetGroups = {}
	selectedFleet = nil

	-- full resolution if the device allows it, else half
	local full = grids[map.id] or MapGrid.decode(map)
	grids[map.id] = full
	local g = full
	local editable = imageFor(g.width, g.height)
	if editable == nil then
		g = MapGrid.downsample(full, 2)
		editable = imageFor(g.width, g.height)
	end
	grid = g
	detailAllowed = g == full -- no close-up on a device that needs the half-size map
	-- the sea grid at the same size, so a tap on the water finds its zone
	local sea = seaGrids[map.id] or MapGrid.decodeSea(map)
	seaGrids[map.id] = sea
	seaGrid = if g == full then sea else MapGrid.downsample(sea, full.width // g.width)
	wraps = false
	for _, st in map.straits do
		wraps = wraps or st.wrap
	end
	size = Vector2.new(g.width, g.height)
	local canvas = MapView.create(size, Palette.background[map.theme] or Palette.background.earth)

	local imageLayer = layer("Image", canvas)
	imageLabel = nil
	if editable then
		local label = Instance.new("ImageLabel")
		label.Name = "Pixels"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.ImageContent = Content.fromObject(editable)
		label.Parent = imageLayer
		imageLabel = label
	else
		-- the kit's toast look, standing for good under the line where toasts come and go (a full-screen GUI)
		local notice = Widgets.toast(canvas.Parent or canvas, MapView.topBand() + NOTICE_TOP, NOTICE_WIDTH)
		notice.Name = "MapArtOff"
		artOffNotice = notice
		Widgets.setIconText(notice, "🗺 Map art is off: turn on Allow Mesh / Image APIs", "map")
		notice.Visible = true
		if not warned then
			warned = true
			warn("[map] no EditableImage: turn on Game Settings > Security > Allow Mesh / Image APIs (docs/MAPS.md)")
		end
	end

	painting = { map = map, grid = g }
	art = nil
	paintMap()

	local straits = layer("Straits", canvas)
	local linkColor = if map.theme == "sky" then Palette.energyLink else Palette.strait
	for _, st in map.straits do
		if not st.wrap then
			dots(
				straits,
				Vector2.new(st.from.x, st.from.y) / g.scale,
				Vector2.new(st.to.x, st.to.y) / g.scale,
				linkColor,
				3
			)
		end
	end
	layer("Route", canvas)

	-- each sea zone's name under its centre (its fleets stand above): quiet italics in a pale sea blue
	local zoneLayer = layer("Zones", canvas)
	for _, def in map.seaZones do
		local width = LabelLayout.textWidth(def.name, TEXT_SIZE)
		local label = textLabel(zoneLayer, def.name)
		label.Name = "Z" .. def.id
		label.FontFace = Font.new(Theme.font.body.Family, Enum.FontWeight.SemiBold, Enum.FontStyle.Italic)
		label.TextColor3 = Palette.zoneName
		label.TextTransparency = 0.15
		label.TextStrokeTransparency = 0.45
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = at(Vector2.new(def.center.x, def.center.y) / g.scale) + UDim2.fromOffset(0, ZONE_NAME_OFFSET)
		label.Size = UDim2.fromOffset(width, NAME_HEIGHT)
		label.Visible = false -- layoutNames shows the ones with room
		zoneLabels[def.id] = { label = label, width = width, area = def.area / (g.scale * g.scale) }
	end

	-- each province's name, its development pips hanging under it (two GUI objects a province)
	local labelLayer = layer("Labels", canvas)
	for _, def in map.provinces do
		widths[def.id] = 2 * math.sqrt(def.area / (g.scale * g.scale) / math.pi)
		if def.isCapital then
			capitalAt[def.id] = true
		end
		if def.terrain ~= "Mountain" then
			local record = ClientState.province(def.id)
			local development = if record then record.development else def.development
			local width = math.max(LabelLayout.textWidth(def.name, TEXT_SIZE), PIP_BAR_W * PIPS_SCALE)
			local name = textLabel(labelLayer, def.name)
			name.Name = "P" .. def.id
			name.AnchorPoint = Vector2.new(0.5, 0)
			name.Position = at(MapRenderer.centerOf(def.id)) + UDim2.fromOffset(0, nameOffset(def.id, MapView.zoom()))
			name.Size = UDim2.fromOffset(width, NAME_HEIGHT)
			local pips = pipsLabel(name, development)
			labels[def.id] = { name = name, pips = pips, width = width, development = development }
		end
	end
	layer("Flags", canvas)
	layer("Tokens", canvas)
	layer("Fleets", canvas)
	layer("Markers", canvas)
	layer("Crowns", canvas)
	layer("Emotes", canvas)
	layer("Effects", canvas).ZIndex = 2 -- Effects' particles, over everything else
	onZoom(MapView.zoom())
end

-- A layer of the current map's canvas by name (nil before the first map), the map's size in map pixels, and a
-- province's rough width in map pixels: for Effects, which draws on the "Effects" layer.
function MapRenderer.layer(name: string): Frame?
	return layers[name]
end

function MapRenderer.mapSize(): Vector2
	return size
end

function MapRenderer.provinceWidth(provinceId: number): number
	return widths[provinceId] or 0
end

-- How far above a province's centre its overlays reach on screen (its armies' badges and its status row), so the
-- tutorial's arrow can stand clear of what it points at.
function MapRenderer.overlayTop(provinceId: number): number
	local lift = MapBadges.statusLift(
		stackHalf[provinceId] or 0,
		BADGE_GAP,
		stackShown[provinceId] or 0,
		BADGE_HEIGHT + BADGE_GAP
	)
	local status = statuses[provinceId]
	if status and status.row.Visible then
		lift += BADGE_HEIGHT
	end
	return TOKEN_LIFT * MapView.zoom() + lift
end

-- A Primordial-power badge over a province (a strike, a shield, a blessing, a plague: Powers' emoji and seconds left,
-- e.g. "🛡️25 🌟30"), shown as pills in the province's status row after its battle or siege. nil clears it.
function MapRenderer.setEffect(provinceId: number, value: string?)
	effectTexts[provinceId] = value
	renderStatus(provinceId)
end

-- A pixel crown on top of the flag pole of every coalition leader's capital (CatchUp.leadersFrom); where the pole
-- would stand at its first province if the capital is lost.
local function refreshCrowns()
	local snapshot = ClientState.snapshot()
	local crownLayer = layers.Crowns
	if snapshot == nil or crownLayer == nil then
		return
	end
	local counts: { [number]: number } = {}
	local capitals: { [number]: number } = {}
	for _, nation in snapshot.nations do
		if not nation.eliminated then
			counts[nation.id] = 0
			capitals[nation.id] = nation.capital
		end
	end
	local owners: { [number]: number } = {}
	local firstOwned: { [number]: number } = {}
	for _, record in snapshot.provinces do
		owners[record.id] = record.owner
		if counts[record.owner] then
			counts[record.owner] += 1
			firstOwned[record.owner] = math.min(firstOwned[record.owner] or math.huge, record.id)
		end
	end
	local map = ClientState.map()
	if map == nil then
		return
	end
	local leaders = CatchUp.leadersFrom(counts, CatchUp.ownableCount(map.provinces))
	for nationId, crown in crowns do
		crown.Visible = leaders[nationId] == true
	end
	local poleX = FLAG_RIGHT - FLAG_WIDTH - POLE + (POLE - 1) / 2 -- the middle of the flag's pole
	local poleTop = FLAG_BOTTOM - FLAG_HEIGHT - 8
	for nationId in leaders do
		local where = if owners[capitals[nationId]] == nationId then capitals[nationId] else firstOwned[nationId]
		local crown = crowns[nationId]
		if crown == nil then
			local made = Icons.label(crownLayer, "crown", CROWN_SIZE)
			made.Name = "Crown" .. nationId
			made.AnchorPoint = Vector2.new(0.5, 1)
			crowns[nationId] = made
			crown = made
		end
		local c = crown :: GuiObject
		c.Position = at(MapRenderer.centerOf(where)) + UDim2.fromOffset(poleX, poleTop)
		c.Visible = true
	end
end

local function refreshProvince(record: Snapshot.ProvinceRecord)
	local label = labels[record.id]
	if label and label.development ~= record.development then
		label.development = record.development
		setPips(label.pips, record.development)
	end
	-- siegeBy is 0 for Rebels: a siege is on whenever it needs progress
	local siege = if record.siegeRequired > 0
		then math.floor(100 * record.siegeProgress / record.siegeRequired)
		else nil
	local blockade = record.blockade or 0 -- (0 from a server older than navies)
	local old = provinceStates[record.id]
	if
		old
		and old.battle == record.battle
		and old.siege == siege
		and old.siegeBy == record.siegeBy
		and old.owner == record.owner
		and old.blockade == blockade
	then
		return
	end
	provinceStates[record.id] = {
		battle = record.battle,
		siege = siege,
		siegeBy = record.siegeBy,
		owner = record.owner,
		blockade = blockade,
	}
	if record.battle or siege or blockade ~= 0 or statuses[record.id] then
		renderStatus(record.id)
	end
end

-- An army's badge outline: its nation's colour (Rebels red, garrisons grey), gold while selected.
local function edgeOf(token: Token): Color3
	if token.rebel then
		return Palette.rebelEdge
	elseif token.neutral then
		return Palette.garrison
	end
	return nationColor(token.owner)
end

-- A nation's army whose main troop changed (it recruited or lost men): its soldier follows (an equipped token skin
-- stays as it is).
local function resoldier(token: Token)
	local sprite = token.frame:FindFirstChild("TokenSkin")
	local troop = token.troop
	local nation = ClientState.nation(token.owner)
	if sprite == nil or troop == nil or nation == nil then
		return
	end
	local soldier = sprite:GetAttribute("Soldier")
	if soldier == nil or soldier == troop then
		return
	end
	if Cosmetics.armyLabel(token.frame, token.owner, troop, nation.colorIndex, UDim2.fromScale(1, 1)) then
		sprite:Destroy()
	end
end

local function makeToken(army: Snapshot.ArmyRecord, target: Vector2): Token
	local rebel = army.rebel
	local neutral = army.owner == 0 and not rebel
	local px = if neutral then TOKEN_SIZE - 4 else TOKEN_SIZE
	local frame = Instance.new("Frame")
	frame.Name = "Army" .. army.id
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = at(target)
	frame.Size = UDim2.fromOffset(px, px)
	frame.BackgroundColor3 = if rebel then Palette.rebel else nationColor(army.owner)
	frame.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = if rebel then Palette.rebelEdge else Theme.color.ink
	stroke.Thickness = Theme.stroke
	stroke.Parent = frame
	-- a nation's sprite instead of the plain square: its token skin (cosmetic), or with the default token a soldier of
	-- the troop it is mostly made of (garrisons and Rebels keep their squares)
	local nation = if neutral then nil else ClientState.nation(army.owner)
	local troop = RaceInfo.mainTroop(army.troops) or RaceInfo.lineTroop(if nation then nation.race else nil)
	local sprite = if nation
		then Cosmetics.armyLabel(frame, army.owner, troop, nation.colorIndex, UDim2.fromScale(1, 1))
		else nil
	local skinned = sprite ~= nil
	if skinned then
		px = TOKEN_SKIN_SIZE
		frame.Size = UDim2.fromOffset(px, px)
		frame.BackgroundTransparency = 1
		stroke.Enabled = false
	end
	local token: Token = {
		frame = frame,
		stroke = stroke,
		badge = newPill(frame, "Strength", "sword", Palette.garrison),
		pos = target,
		target = target,
		neutral = neutral,
		rebel = rebel,
		owner = army.owner,
		province = army.location,
		skinned = skinned,
		half = px / 2,
		resting = true,
		slotX = 0,
		row = -1,
		text = "",
		icon = "",
		troops = "",
		troop = nil,
		morale = -1,
		moraleBar = nil,
	}
	token.badge.stroke.Color = edgeOf(token)
	token.badge.label.AnchorPoint = Vector2.new(0.5, 1)
	token.badge.label.Visible = false -- stackBadges places and shows it
	frame.Visible = not neutral or detailShown
	frame.Parent = layers.Tokens
	return token
end

-- An army's morale bar under its token (docs/DESIGN.md "Armies and combat"): while it fights, and while it is below
-- full (MapBadges.showMorale); its fill in the tone's colour. `morale` -1 hides it. Two objects, made on first use.
local function setMorale(token: Token, morale: number)
	local bar = token.moraleBar
	if morale < 0 then
		if bar then
			bar.Visible = false
		end
		return
	end
	if bar == nil then
		local track = Instance.new("Frame")
		track.Name = "Morale"
		track.AnchorPoint = Vector2.new(0.5, 0)
		track.Position = UDim2.new(0.5, 0, 1, 2)
		track.Size = UDim2.fromOffset(TOKEN_SKIN_SIZE, MORALE_BAR_HEIGHT)
		track.BackgroundColor3 = Theme.color.ink
		track.BorderSizePixel = 0
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Position = UDim2.fromOffset(1, 1)
		fill.BorderSizePixel = 0
		fill.Parent = track
		track.Parent = token.frame
		token.moraleBar = track
		bar = track
	end
	local track = bar :: Frame
	local fraction, tone = MapBadges.morale(morale, Config.Battle.MoraleMax)
	local fill = track:FindFirstChild("Fill") :: Frame
	fill.Size = UDim2.new(fraction, -2 * fraction, 1, -2)
	fill.BackgroundColor3 = MORALE_COLORS[tone]
	fill.Visible = fraction > 0
	track:SetAttribute("Morale", morale)
	track.Visible = true
end

-- Beside the other armies resting in its province, or fleets in its zone (screen pixels from the anchor).
local function setSlot(token: Badged, x: number)
	if token.slotX ~= x then
		token.slotX = x
		token.row = -2 -- its badge has to move back over the group
		token.frame.Position = at(token.pos) + UDim2.fromOffset(x, 0)
	end
end

local function refreshArmies()
	local snapshot = ClientState.snapshot()
	if snapshot == nil or layers.Tokens == nil then
		return
	end
	local alive: { [number]: boolean } = {}
	local resting: { [number]: { number } } = {}
	for _, army in snapshot.armies do
		alive[army.id] = true
		-- at its province's anchor, or between two anchors while marching (the same height above the province
		-- centres, so a badge stacked over the armies it leaves stays clear of theirs)
		local pos = ClientState.position(army.id)
		local marching = pos ~= nil and army.next ~= 0
		local target = if pos and marching
			then anchorOf(pos.from):Lerp(anchorOf(pos.to), pos.progress)
			else anchorOf(army.location)
		local token = tokens[army.id]
		if token == nil then
			token = makeToken(army, target)
			tokens[army.id] = token
		end
		local t = token :: Token
		t.target = target
		t.province = army.location
		t.resting = not marching
		if t.resting then
			local list = resting[army.location] or {}
			table.insert(list, army.id)
			resting[army.location] = list
		end
		if t.troops ~= army.troops then
			t.troops = army.troops
			t.troop = RaceInfo.mainTroop(army.troops) -- its badge shows this troop's icon, its token its soldier
			resoldier(t)
		end
		local troopIcon = if t.troop then RaceInfo.troopIcon(t.troop) else nil
		local icon = MapBadges.armyIcon(t.rebel, t.neutral, army.inBattle, army.retreating, troopIcon)
		local text = MapBadges.shortMen(army.men)
		if t.icon ~= icon or t.text ~= text then
			t.icon, t.text = icon, text
			setPill(t.badge, icon, text)
		end
		local morale = if MapBadges.showMorale(army.morale, Config.Battle.MoraleMax, army.inBattle)
			then army.morale
			else -1
		if t.morale ~= morale then
			t.morale = morale
			setMorale(t, morale)
		end
	end
	for id, token in tokens do
		if not alive[id] then
			token.frame:Destroy()
			tokens[id] = nil
		end
	end
	-- armies resting together stand side by side, always in the same order
	for _, ids in resting do
		table.sort(ids)
		for slot, id in ids do
			setSlot(tokens[id], MapBadges.slotOffset(slot, #ids, TOKEN_SLOT))
		end
	end
	-- each province's badge stack: the armies resting there, then those marching out of it (their badges ride
	-- with them a row up, clear of the ones staying behind, until they reach the next province)
	local stacks: { [number]: { number } } = {}
	for location, ids in resting do
		stacks[location] = table.clone(ids)
	end
	local leaving: { number } = {}
	for id, token in tokens do
		if not token.resting then
			setSlot(token, 0)
			table.insert(leaving, id)
		end
	end
	table.sort(leaving)
	for _, id in leaving do
		local location = tokens[id].province
		local list = stacks[location] or {}
		table.insert(list, id)
		stacks[location] = list
	end
	groups = stacks
	-- a garrison came, went, or began or stopped fighting: lay the names and garrison badges out again
	if detailShown and garrisonsChanged() then
		layoutNames(MapView.zoom(), true, true)
	end
	stackBadges()
end

local function makeFleet(fleet: Snapshot.FleetRecord, target: Vector2): FleetToken
	local frame = Instance.new("Frame")
	frame.Name = "Fleet" .. fleet.id
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = at(target)
	frame.Size = UDim2.fromOffset(TOKEN_SIZE, TOKEN_SIZE)
	frame.BackgroundColor3 = nationColor(fleet.owner)
	frame.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.color.ink
	stroke.Thickness = Theme.stroke
	stroke.Parent = frame
	-- the map's ship in the nation's colours (a plain square where the device can't paint it)
	local nation = ClientState.nation(fleet.owner)
	local map = ClientState.map()
	local sprite = if nation and map
		then Cosmetics.shipLabel(frame, map.ship, nation.colorIndex, UDim2.fromScale(1, 1))
		else nil
	local skinned = sprite ~= nil
	if skinned then
		frame.Size = UDim2.fromOffset(FLEET_WIDTH, FLEET_HEIGHT)
		frame.BackgroundTransparency = 1
		stroke.Enabled = false
	end
	local token: FleetToken = {
		frame = frame,
		stroke = stroke,
		badge = newPill(frame, "Strength", "ship", nationColor(fleet.owner)),
		pos = target,
		target = target,
		owner = fleet.owner,
		zone = fleet.zone,
		skinned = skinned,
		resting = true,
		slotX = 0,
		row = -1,
		text = "",
		icon = "",
	}
	token.badge.label.AnchorPoint = Vector2.new(0.5, 1)
	token.badge.label.Visible = false -- stackFleets places and shows it
	frame.Parent = layers.Fleets
	return token
end

-- Fleet tokens from the snapshot: at their zone's anchor, or between two zone centres while sailing (its latest
-- position, ClientState.fleetPosition); fleets resting in one zone side by side, their badges stacked above them.
local function refreshFleets()
	local snapshot = ClientState.snapshot()
	if snapshot == nil or layers.Fleets == nil then
		return
	end
	local alive: { [number]: boolean } = {}
	local resting: { [number]: { number } } = {}
	local leaving: { number } = {}
	for _, fleet in snapshot.fleets do
		alive[fleet.id] = true
		local sailing = fleet.next ~= 0
		local pos = ClientState.fleetPosition(fleet.id)
		local target = if sailing and pos
			then seaLerp(fleetAnchorOf(pos.from), fleetAnchorOf(pos.to), pos.progress)
			else fleetAnchorOf(fleet.zone)
		local token = fleetTokens[fleet.id]
		if token == nil then
			token = makeFleet(fleet, target)
			fleetTokens[fleet.id] = token
		end
		local t = token :: FleetToken
		if math.abs(target.X - t.pos.X) > size.X / 2 then
			t.pos = target -- over the map's edge: jump rather than glide across the whole map
		end
		t.target = target
		t.zone = fleet.zone
		t.resting = not sailing
		if sailing then
			table.insert(leaving, fleet.id)
		else
			local list = resting[fleet.zone] or {}
			table.insert(list, fleet.id)
			resting[fleet.zone] = list
		end
		local icon = MapBadges.fleetIcon(fleet.inBattle, fleet.retreating)
		local text = MapBadges.fleetText(fleet.ships, fleet.men)
		if t.icon ~= icon or t.text ~= text then
			t.icon, t.text = icon, text
			setPill(t.badge, icon, text)
		end
	end
	for id, token in fleetTokens do
		if not alive[id] then
			token.frame:Destroy()
			fleetTokens[id] = nil
		end
	end
	-- fleets resting in one zone side by side (always in the same order), then each zone's badge stack: those resting
	-- there, then those sailing out of it (their badges ride with them a row up)
	local stacks: { [number]: { number } } = {}
	for zone, ids in resting do
		table.sort(ids)
		for slot, id in ids do
			setSlot(fleetTokens[id], MapBadges.slotOffset(slot, #ids, FLEET_SLOT))
		end
		stacks[zone] = table.clone(ids)
	end
	table.sort(leaving)
	for _, id in leaving do
		local token = fleetTokens[id]
		setSlot(token, 0)
		local list = stacks[token.zone] or {}
		table.insert(list, id)
		stacks[token.zone] = list
	end
	fleetGroups = stacks
	stackFleets()
end

export type Pick = "Army" | "Fleet" | "Province" | "Zone"

-- What is under a screen point: an army or fleet token (they sit on top), a province, or a sea zone.
function MapRenderer.pick(screenPos: Vector2): (Pick?, number?)
	local best: number? = nil
	local bestKind: Pick? = nil
	local bestDistance = math.huge
	for id, token in tokens do
		if token.frame.Visible then
			local d = (MapView.toScreen(token.pos) + Vector2.new(token.slotX, 0) - screenPos).Magnitude
			if d < TOKEN_PICK and d < bestDistance then
				best, bestKind, bestDistance = id, "Army", d
			end
		end
	end
	for id, token in fleetTokens do
		local d = (MapView.toScreen(token.pos) + Vector2.new(token.slotX, 0) - screenPos).Magnitude
		if d < FLEET_PICK and d < bestDistance then
			best, bestKind, bestDistance = id, "Fleet", d
		end
	end
	if best then
		return bestKind, best
	end
	local g = grid
	if g then
		local p = MapView.toMap(screenPos)
		local id = MapGrid.at(g, p.X, p.Y)
		if id ~= 0 then
			return "Province", id
		end
		local sea = seaGrid
		local zone = if sea then MapGrid.at(sea, p.X, p.Y) else 0
		if zone ~= 0 then
			return "Zone", zone
		end
	end
	return nil, nil
end

-- A fleet's route through zone centres (white for the selected fleet's way, a gold preview before confirming), and
-- the last step ashore when it sails to land on a coast.
function MapRenderer.showSeaRoute(from: number?, path: { number }?, preview: boolean?, landAt: number?)
	local routeLayer = layers.Route
	if routeLayer == nil then
		return
	end
	routeLayer:ClearAllChildren()
	if from == nil or path == nil then
		return
	end
	local color = if preview then Theme.color.gold else Theme.color.text
	local prev = MapRenderer.zoneCenterOf(from)
	for _, zone in path do
		local nextPoint = MapRenderer.zoneCenterOf(zone)
		seaDots(routeLayer, prev, nextPoint, color, 5)
		prev = nextPoint
	end
	if landAt then
		dots(routeLayer, prev, MapRenderer.centerOf(landAt), color, 5)
	end
end

-- The selected fleet: a gold outline round its ship and its badge, and the badge shows at any zoom.
function MapRenderer.selectFleet(fleetId: number?)
	local previous = selectedFleet
	local old = if previous then fleetTokens[previous] else nil
	if old then
		old.stroke.Color = Theme.color.ink
		old.stroke.Thickness = Theme.stroke
		old.stroke.Enabled = not old.skinned
		old.badge.stroke.Color = nationColor(old.owner)
		old.badge.stroke.Thickness = 1
	end
	selectedFleet = fleetId
	local token = if fleetId then fleetTokens[fleetId] else nil
	if token then
		token.stroke.Color = Theme.color.gold
		token.stroke.Thickness = 3
		token.stroke.Enabled = true
		token.badge.stroke.Color = Theme.color.gold
		token.badge.stroke.Thickness = Theme.stroke
	end
	stackFleets()
end

-- Route dots through province centres (the selected army's way in white, or a gold preview before confirming).
function MapRenderer.showRoute(from: number?, path: { number }?, preview: boolean?)
	local routeLayer = layers.Route
	if routeLayer == nil then
		return
	end
	routeLayer:ClearAllChildren()
	if from == nil or path == nil or #path == 0 then
		return
	end
	local color = if preview then Theme.color.gold else Theme.color.text
	local prev = MapRenderer.centerOf(from)
	for _, id in path do
		local nextPoint = MapRenderer.centerOf(id)
		dots(routeLayer, prev, nextPoint, color, 5)
		prev = nextPoint
	end
end

-- The selected province: PixelArt outlines it in white, and its name turns gold.
function MapRenderer.select(provinceId: number?)
	local a = art
	if a then
		PixelArt.select(a, provinceId)
	end
	local old = if selectedProvince then labels[selectedProvince] else nil
	if old then
		old.name.TextColor3 = Theme.color.text
	end
	selectedProvince = provinceId
	local new = if provinceId then labels[provinceId] else nil
	if new then
		new.name.TextColor3 = Theme.color.gold
	end
end

-- The selected army: a gold outline round its token and its badge, and the badge shows at any zoom.
function MapRenderer.selectArmy(armyId: number?)
	local previous = selectedArmy
	local old = if previous then tokens[previous] else nil
	if old then
		old.stroke.Color = if old.rebel then Palette.rebelEdge else Theme.color.ink
		old.stroke.Thickness = Theme.stroke
		old.stroke.Enabled = not old.skinned
		old.badge.stroke.Color = edgeOf(old)
		old.badge.stroke.Thickness = 1
	end
	selectedArmy = armyId
	local token = if armyId then tokens[armyId] else nil
	if token then
		token.stroke.Color = Theme.color.gold
		token.stroke.Thickness = 3
		token.stroke.Enabled = true
		token.badge.stroke.Color = Theme.color.gold
		token.badge.stroke.Thickness = Theme.stroke
	end
	stackBadges()
end

function MapRenderer.init()
	MapView.onZoom(onZoom)
	HudLayout.onChange(function()
		local notice = artOffNotice
		if notice and notice.Parent then
			notice.Position = UDim2.new(0.5, 0, 0, MapView.topBand() + NOTICE_TOP)
		end
	end)
	ClientState.onReset(function()
		local map = ClientState.map()
		if map then
			build(map)
			paintOwners()
			local snapshot = ClientState.snapshot()
			if snapshot then
				for _, record in snapshot.provinces do
					refreshProvince(record)
				end
			end
			refreshArmies()
			refreshFleets()
			refreshCrowns()
			refreshFlags()
			refreshVictory()
		end
	end)
	ClientState.onDelta(function(delta)
		for _, record in delta.provinces do
			refreshProvince(record)
		end
		if #delta.provinces > 0 or #delta.nations > 0 then
			paintOwners()
			refreshCrowns()
			refreshFlags()
		end
		if #delta.armies > 0 or #delta.removedArmies > 0 then
			refreshArmies()
		end
		if #delta.fleets > 0 or #delta.removedFleets > 0 then
			local selected = selectedFleet
			refreshFleets()
			if selected and fleetTokens[selected] then
				MapRenderer.selectFleet(selected) -- (a token made again keeps its gold outline)
			end
		end
		if delta.result then
			refreshVictory()
		end
		for _, e in delta.events do
			if e.kind == "Emote" then
				showEmote(e)
			end
		end
	end)
	-- the opt-out ("always show the classic map") was switched: repaint the terrain
	ShopState.onChange(function()
		local a = art
		if painting and a and a.look ~= Cosmetics.matchTheme() then
			paintMap()
		end
	end)
	-- someone equipped something: flags, borders, shades and tokens follow
	Cosmetics.onChange(function()
		if layers.Tokens == nil then
			return
		end
		paintOwners()
		refreshFlags()
		for id, token in tokens do
			token.frame:Destroy()
			tokens[id] = nil
		end
		local selected = selectedArmy
		selectedArmy = nil
		refreshArmies()
		MapRenderer.selectArmy(selected)
	end)
	ClientState.onPositions(function(moved)
		if next(moved.armies) then
			refreshArmies()
		end
		if next(moved.fleets) then
			refreshFleets()
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		-- tokens glide towards their targets (faster in a sandbox running at 2× or 4×, where positions come faster)
		local a = 1 - math.exp(-TOKEN_SMOOTHING * dt * math.max(1, ClientState.timeScale()))
		for _, token in tokens do
			if (token.pos - token.target).Magnitude > 0.05 then
				token.pos = token.pos:Lerp(token.target, a)
				token.frame.Position = at(token.pos) + UDim2.fromOffset(token.slotX, 0)
			end
		end
		for _, token in fleetTokens do
			if (token.pos - token.target).Magnitude > 0.05 then
				token.pos = token.pos:Lerp(token.target, a)
				token.frame.Position = at(token.pos) + UDim2.fromOffset(token.slotX, 0)
			end
		end
		-- victory animations cycle through their frames
		victoryClock += dt
		if victoryClock >= VICTORY_FRAME_SECONDS and #victories > 0 then
			victoryClock = 0
			for _, v in victories do
				local i = (table.find(v.frames, v.label.Text) or 0) % #v.frames + 1
				v.label.Text = v.frames[i]
			end
		end
		-- the pixel art goes to the screen at most once a frame
		local editable, painted = image, art
		if editable and painted and imageLabel then
			local d = PixelArt.takeDirty(painted)
			if d then
				upload(editable, painted.pixels, painted.width, painted.height, d)
			end
		end
		stepDetail(dt)
	end)
end

return MapRenderer
