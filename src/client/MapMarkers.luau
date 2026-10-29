--!strict
-- Map markers (docs/NEXT_FEATURES.md 3.3): one pooled set of overlays on MapRenderer's "Markers" layer, over the
-- army badges, the status rows and the crowns. A marker is a medallion with a pixel icon on a stem standing on a map
-- point, with an optional flag beside the medallion and two pulse rings round the point. Map pings use it (UI/Pings);
-- the empire plate, the advisor's arrows and the daily challenge's goals are meant to share it. Markers are placed by
-- scale on the canvas, so they follow every pan and zoom; their sizes stay fixed on screen.
--
-- At most CAPACITY markers show, 6 GUI objects each (stem, two rings, medallion, its icon, the flag): showing one
-- more takes the place of the oldest. A free marker stays in the pool, hidden, for the next one.

local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Client = script.Parent
local Cosmetics = require(Client.Cosmetics)
local Icons = require(Client.UI.Icons)
local MapRenderer = require(Client.MapRenderer)
local Theme = require(Client.UI.Theme)
local Widgets = require(Client.UI.Widgets)

local STEM = 24 -- screen px from the map point up to the medallion's bottom
local STEM_WIDTH = 2
local MEDALLION_DROP = 2 -- the medallion overlaps the stem's top by this much
local FLAG_WIDTH, FLAG_HEIGHT = 24, 18 -- a 16×12 flag, like the capitals'
local FLAG_GAP = 2 -- between the medallion and the flag
local RING_MIN, RING_MAX = 10, 46 -- a pulse ring grows from this diameter to that one, fading out
local RING_EDGE = 3
local PULSE_SECONDS = 1.2 -- one ring's growth; the second runs half a pulse behind
local STILL_RINGS = { 22, 40 } -- with reduced motion: two still rings
local STILL_FADE = 0.35

local MapMarkers = {}

MapMarkers.CAPACITY = 8

-- What a marker shows: a pixel icon in a medallion of a colour style (a Frames style: "crimson", "azure", "gold",
-- "slate"...), pulse rings in a colour (nil: none), and a nation's flag (nil: none).
export type Look = {
	icon: string,
	style: string,
	ring: Color3?,
	flagId: string?,
	colorIndex: number?,
}

type Ring = { frame: Frame, stroke: UIStroke }

type Marker = {
	name: string?, -- nil while free
	root: Frame, -- the stem; the rest hang on it
	medallion: ImageLabel,
	icon: GuiObject,
	rings: { Ring },
	flag: GuiObject?,
	flagKey: string,
	shownAt: number,
}

local pool: { Marker } = {}
local poolLayer: Frame? = nil -- the layer the pool was made on (a new map's canvas has a new one)

local function reducedMotion(): boolean
	local ok, on = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and on == true
end

local function make(layer: Frame): Marker
	local root = Instance.new("Frame")
	root.Name = "Marker"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Size = UDim2.fromOffset(STEM_WIDTH, STEM)
	root.BackgroundColor3 = Theme.color.text
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = layer
	local edge = Instance.new("UIStroke")
	edge.Color = Theme.color.ink
	edge.Thickness = 1
	edge.Parent = root
	local rings: { Ring } = {}
	for i = 1, 2 do
		local ring = Instance.new("Frame")
		ring.Name = "Ring" .. i
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromScale(0.5, 1) -- the map point, at the stem's foot
		ring.BackgroundTransparency = 1
		ring.Parent = root
		Widgets.corner(ring, 999)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = RING_EDGE
		stroke.Parent = ring
		rings[i] = { frame = ring, stroke = stroke }
	end
	local medallion, icon = Widgets.medallion(root, "small", "slate", "eye")
	medallion.AnchorPoint = Vector2.new(0.5, 1)
	medallion.Position = UDim2.new(0.5, 0, 0, MEDALLION_DROP)
	return {
		name = nil,
		root = root,
		medallion = medallion,
		icon = icon,
		rings = rings,
		flag = nil,
		flagKey = "",
		shownAt = 0,
	}
end

-- The pool on the current map's "Markers" layer (nil before the first map). A new canvas drops the old pool: its
-- objects went with the old canvas.
local function currentPool(): { Marker }?
	local layer = MapRenderer.layer("Markers")
	if layer == nil then
		return nil
	end
	if layer ~= poolLayer then
		poolLayer = layer
		pool = {}
	end
	return pool
end

local function find(name: string): Marker?
	for _, m in pool do
		if m.name == name then
			return m
		end
	end
	return nil
end

local function free(m: Marker)
	m.name = nil
	m.root.Name = "Marker"
	m.root.Visible = false
end

-- Show the marker called `name` (it becomes its root's Name) on map point `at` (map pixels), or move and restyle it
-- if it already shows. Past CAPACITY the oldest marker gives way. Returns the name of the marker that gave way, if
-- one did.
function MapMarkers.show(name: string, at: Vector2, look: Look): string?
	local markers = currentPool()
	if markers == nil then
		return nil
	end
	local evicted: string? = nil
	local m = find(name)
	if m == nil then
		for _, candidate in markers do
			if candidate.name == nil then
				m = candidate
				break
			end
		end
	end
	if m == nil and #markers < MapMarkers.CAPACITY then
		local made = make(poolLayer :: Frame)
		table.insert(markers, made)
		m = made
	end
	if m == nil then
		local oldest = markers[1]
		for _, candidate in markers do
			if candidate.shownAt < oldest.shownAt then
				oldest = candidate
			end
		end
		evicted = oldest.name
		m = oldest
	end
	local marker = m :: Marker
	if marker.name ~= name then
		marker.shownAt = os.clock()
	end
	marker.name = name
	marker.root.Name = name
	local size = MapRenderer.mapSize()
	marker.root.Position = UDim2.fromScale(at.X / size.X, at.Y / size.Y)
	Widgets.setMedallion(marker.medallion, look.style)
	Icons.set(marker.icon, look.icon)
	for _, ring in marker.rings do
		ring.frame.Visible = look.ring ~= nil
		if look.ring then
			ring.stroke.Color = look.ring
		end
	end
	local flagKey = if look.flagId and look.colorIndex then look.flagId .. ":" .. look.colorIndex else ""
	if flagKey ~= marker.flagKey then
		if marker.flag then
			marker.flag:Destroy()
			marker.flag = nil
		end
		if look.flagId and look.colorIndex then
			local flag = Cosmetics.flagLabel(
				marker.root,
				look.flagId,
				look.colorIndex,
				UDim2.fromOffset(FLAG_WIDTH, FLAG_HEIGHT)
			)
			flag.Name = "Flag"
			flag.AnchorPoint = Vector2.new(0, 0.5)
			local medallionSize = marker.medallion.Size.Y.Offset
			flag.Position = UDim2.new(0.5, medallionSize / 2 + FLAG_GAP, 0, MEDALLION_DROP - medallionSize / 2)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.color.ink
			stroke.Thickness = 1
			stroke.Parent = flag
			marker.flag = flag
		end
		marker.flagKey = flagKey
	end
	marker.root.Visible = true
	return evicted
end

-- Take the marker called `name` off the map (no-op when it isn't there).
function MapMarkers.hide(name: string)
	local m = find(name)
	if m then
		free(m)
	end
end

-- Take every marker off the map.
function MapMarkers.clear()
	for _, m in pool do
		free(m)
	end
end

-- The rings pulse: each grows and fades over PULSE_SECONDS, the second half a pulse behind. With reduced motion
-- they stand still.
RunService.RenderStepped:Connect(function()
	local still: boolean? = nil
	local now = os.clock()
	for _, m in pool do
		if m.name and m.root.Visible then
			if still == nil then
				still = reducedMotion()
			end
			for i, ring in m.rings do
				local d, fade
				if still then
					d, fade = STILL_RINGS[i], STILL_FADE
				else
					local t = ((now - m.shownAt) / PULSE_SECONDS + (i - 1) / 2) % 1
					d, fade = RING_MIN + (RING_MAX - RING_MIN) * t, t
				end
				local px = math.floor(d / 2 + 0.5) * 2 -- even sizes, on the pixel grid
				ring.frame.Size = UDim2.fromOffset(px, px)
				ring.stroke.Transparency = fade
			end
		end
	end
end)

return MapMarkers
