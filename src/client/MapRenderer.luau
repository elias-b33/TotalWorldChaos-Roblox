--!strict
-- What is drawn on the 2D map (docs/DESIGN.md "Map rendering"): the pixel-art image painted by PixelArt
-- (terrain, owners, the selected province), straits, province names, army tokens gliding between province
-- centres, battle and siege markers, the coalition leader's crown and route lines. Everything sits on MapView's
-- canvas, placed in map pixels.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local CatchUp = require(Shared.Sim.CatchUp)
local MapGrid = require(Shared.MapGrid)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local MapView = require(script.Parent.MapView)
local Palette = require(script.Parent.Palette)
local PixelArt = require(script.Parent.PixelArt)

local NAME_MIN_PIXELS = 70 -- a province's name shows once the province is this wide on screen
local DETAIL_ZOOM = 0.9 -- garrisons and development pips show from this share of the region zoom inwards
local TEXT_SIZE = 14 -- the smallest text on the map (docs/DESIGN.md "UI and controls")
local TOKEN_SIZE = 14 -- army token, screen pixels
local TOKEN_PICK = 20 -- a tap this close to a token's centre (screen pixels) picks the army
local TOKEN_SPACING = 4 -- map pixels between tokens standing in one province
local TOKEN_SMOOTHING = 6 -- higher = tokens catch up with their target faster
local DOT_SPACING = 4 -- map pixels between the dots of a route or strait
local PIXELATED_FROM = 1.5 -- zoom from which map pixels are drawn hard-edged (smooth below, so thin lines don't flicker)
local PAINT_SLICE = 0.008 -- seconds of painting per frame while a map is painted for the first time

local MapRenderer = {}

type Token = {
	frame: Frame,
	stroke: UIStroke,
	label: TextLabel,
	pos: Vector2,
	target: Vector2,
	neutral: boolean,
	province: number,
}

local grid: MapGrid.Grid? = nil
local art: PixelArt.Art? = nil
local image: EditableImage? = nil
local imageLabel: ImageLabel? = nil
local size = Vector2.new(1024, 512)
local generation = 0 -- bumps with every new map, so a painting finished for an old one is ignored
local grids: { [string]: MapGrid.Grid } = {} -- decoded grids by map id
local arts: { [string]: PixelArt.Art } = {} -- painted maps by map id and resolution, reused across matches
local warned = false
local layers: { [string]: Frame } = {}
local widths: { [number]: number } = {} -- each province's width in map pixels
local labels: { [number]: { frame: Frame, pips: TextLabel } } = {}
local markers: { [number]: TextLabel } = {}
local effects: { [number]: TextLabel } = {}
local crowns: { [number]: TextLabel } = {}
local tokens: { [number]: Token } = {}
local selectedArmy: number? = nil

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

local function layer(name: string, parent: Frame): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Parent = parent
	layers[name] = frame
	return frame
end

local function textLabel(parent: Instance, value: string): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = TEXT_SIZE
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = value
	label.Parent = parent
	return label
end

local function pips(development: number): string
	return string.rep("●", development) .. string.rep("○", 5 - development)
end

local function packed(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local function nationColor(nationId: number): Color3
	local nation = ClientState.nation(nationId)
	return if nation then Palette.nation(nation.colorIndex) else Palette.garrison
end

-- Dots from a to b (map pixels) on a layer: straits and routes.
local function dots(parent: Frame, a: Vector2, b: Vector2, color: Color3, dotSize: number)
	local n = math.max(1, math.floor((b - a).Magnitude / DOT_SPACING))
	for i = 0, n do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = at(a:Lerp(b, i / n))
		dot.Size = UDim2.fromOffset(dotSize, dotSize)
		dot.BackgroundColor3 = color
		dot.BorderSizePixel = 0
		dot.Parent = parent
	end
end

-- Neutral garrisons and development pips show from the region zoom inwards (it depends on the screen size).
local function detailVisible(z: number): boolean
	return z >= MapView.regionZoom() * DETAIL_ZOOM
end

-- Everything that depends on the zoom: names, garrisons, and how the pixels are sampled.
local function onZoom(z: number)
	local detail = detailVisible(z)
	for id, label in labels do
		label.frame.Visible = (widths[id] or 0) * z >= NAME_MIN_PIXELS
		label.pips.Visible = detail
	end
	for _, token in tokens do
		if token.neutral then
			token.frame.Visible = detail
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
	for _, nation in snapshot.nations do
		colors[nation.id] = packed(Palette.nation(nation.colorIndex))
		borders[nation.id] = packed(Palette.border(nation.colorIndex))
	end
	PixelArt.setOwners(a, owners, colors, borders)
end

local function build(map: Types.MapDef)
	generation += 1
	local myGeneration = generation
	labels = {}
	markers = {}
	effects = {}
	crowns = {}
	tokens = {}
	layers = {}
	widths = {}
	selectedArmy = nil

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
		local notice = textLabel(canvas.Parent or canvas, "🗺️ Map art is off: turn on Allow Mesh / Image APIs")
		notice.AnchorPoint = Vector2.new(0.5, 0)
		notice.Position = UDim2.new(0.5, 0, 0, 56)
		notice.Size = UDim2.fromOffset(420, 24)
		if not warned then
			warned = true
			warn("[map] no EditableImage: turn on Game Settings > Security > Allow Mesh / Image APIs (docs/MAPS.md)")
		end
	end

	-- the painted map: reused from an earlier match on this map, or painted now, a few milliseconds per frame
	local key = map.id .. ":" .. g.width
	local cached = arts[key]
	if cached then
		art = cached
		PixelArt.select(cached, nil)
		PixelArt.invalidate(cached)
	else
		art = nil
		task.spawn(function()
			local last = os.clock()
			local painted = PixelArt.new(map, g, function()
				if os.clock() - last > PAINT_SLICE then
					task.wait()
					last = os.clock()
				end
			end)
			arts[key] = painted
			if generation == myGeneration then
				art = painted
				paintOwners()
			end
		end)
	end

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

	local labelLayer = layer("Labels", canvas)
	for _, def in map.provinces do
		widths[def.id] = 2 * math.sqrt(def.area / (g.scale * g.scale) / math.pi)
		if def.terrain ~= "Mountain" then
			local record = ClientState.province(def.id)
			local frame = Instance.new("Frame")
			frame.Name = "P" .. def.id
			frame.AnchorPoint = Vector2.new(0.5, 0)
			frame.Position = at(MapRenderer.centerOf(def.id)) + UDim2.fromOffset(0, 6)
			frame.Size = UDim2.fromOffset(150, 36)
			frame.BackgroundTransparency = 1
			frame.Parent = labelLayer
			local name = textLabel(frame, def.name)
			name.Size = UDim2.new(1, 0, 0, 18)
			local dev = textLabel(frame, pips(if record then record.development else def.development))
			dev.Position = UDim2.fromOffset(0, 18)
			dev.Size = UDim2.new(1, 0, 0, 16)
			labels[def.id] = { frame = frame, pips = dev }
		end
	end
	layer("Tokens", canvas)
	layer("Markers", canvas)
	layer("Crowns", canvas)
	onZoom(MapView.zoom())
end

-- Badges above a province, made on demand: battle and siege (markers), Primordial-power effects (effects,
-- higher up).
local function setBadge(store: { [number]: TextLabel }, provinceId: number, value: string?, lift: number, width: number)
	local marker = store[provinceId]
	if value == nil then
		if marker then
			marker.Visible = false
		end
		return
	end
	if marker == nil then
		if layers.Markers == nil then
			return
		end
		local label = textLabel(layers.Markers, "")
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = at(MapRenderer.centerOf(provinceId)) + UDim2.fromOffset(0, -lift)
		label.Size = UDim2.fromOffset(width, 24)
		label.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
		label.BackgroundTransparency = 0.2
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = label
		store[provinceId] = label
		marker = label
	end
	local m = assert(marker, "marker")
	m.Text = value
	m.Visible = true
end

local function setMarker(provinceId: number, value: string?)
	setBadge(markers, provinceId, value, 12, 70)
end

-- A Primordial-power badge over a province (a strike, a shield, a blessing), above the battle/siege badge.
-- nil hides it.
function MapRenderer.setEffect(provinceId: number, value: string?)
	setBadge(effects, provinceId, value, 38, 90)
end

-- A crown over the capital of every coalition leader (CatchUp.leadersFrom); over its first province if the capital
-- is lost.
local function refreshCrowns()
	local snapshot = ClientState.snapshot()
	if snapshot == nil or layers.Crowns == nil then
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
	for nationId, label in crowns do
		label.Visible = leaders[nationId] == true
	end
	for nationId in leaders do
		local where = if owners[capitals[nationId]] == nationId then capitals[nationId] else firstOwned[nationId]
		local label = crowns[nationId]
		if label == nil then
			label = textLabel(layers.Crowns, "👑")
			label.Name = "Crown" .. nationId
			label.TextSize = 20
			label.AnchorPoint = Vector2.new(0.5, 1)
			label.Size = UDim2.fromOffset(28, 26)
			crowns[nationId] = label
		end
		local l = assert(label, "crown")
		l.Position = at(MapRenderer.centerOf(where)) + UDim2.fromOffset(0, -30)
		l.Visible = true
	end
end

local function refreshProvince(record: Snapshot.ProvinceRecord)
	local label = labels[record.id]
	if label then
		label.pips.Text = pips(record.development)
	end
	if record.battle then
		setMarker(record.id, "💥")
	elseif record.siegeRequired > 0 then -- siegeBy is 0 for Rebels
		setMarker(record.id, string.format("⏳ %d%%", math.floor(100 * record.siegeProgress / record.siegeRequired)))
	else
		setMarker(record.id, nil)
	end
end

local function shortMen(men: number): string
	if men >= 1000 then
		return string.format("%gk", math.floor(men / 100) / 10)
	end
	return tostring(men)
end

-- Where an army's token should be: between two centres while moving, else at its province (side by side).
local function tokenTarget(army: Snapshot.ArmyRecord, slot: number): Vector2
	local pos = ClientState.position(army.id)
	if pos and army.next ~= 0 then
		return MapRenderer.centerOf(pos.from):Lerp(MapRenderer.centerOf(pos.to), pos.progress)
	end
	return MapRenderer.centerOf(army.location) + Vector2.new((slot - 1) * TOKEN_SPACING, -4)
end

local function makeToken(army: Snapshot.ArmyRecord, target: Vector2): Token
	local neutral = army.owner == 0
	local px = if neutral then TOKEN_SIZE - 4 else TOKEN_SIZE
	local frame = Instance.new("Frame")
	frame.Name = "Army" .. army.id
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = at(target)
	frame.Size = UDim2.fromOffset(px, px)
	frame.BackgroundColor3 = nationColor(army.owner)
	frame.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 28)
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = textLabel(frame, "")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -2)
	label.Size = UDim2.fromOffset(76, 18)
	frame.Parent = layers.Tokens
	local token: Token = {
		frame = frame,
		stroke = stroke,
		label = label,
		pos = target,
		target = target,
		neutral = neutral,
		province = army.location,
	}
	frame.Visible = not neutral or detailVisible(MapView.zoom())
	return token
end

local function refreshArmies()
	local snapshot = ClientState.snapshot()
	if snapshot == nil or layers.Tokens == nil then
		return
	end
	local alive: { [number]: boolean } = {}
	local perProvince: { [number]: number } = {}
	for _, army in snapshot.armies do
		alive[army.id] = true
		local slot = (perProvince[army.location] or 0) + 1
		perProvince[army.location] = slot
		local target = tokenTarget(army, slot)
		local token = tokens[army.id]
		if token == nil then
			token = makeToken(army, target)
			tokens[army.id] = token
		end
		local t = assert(token, "token")
		local icon = if t.neutral
			then "🛡 "
			elseif army.inBattle then "💥 "
			elseif army.retreating then "🏳 "
			else "⚔ "
		t.label.Text = icon .. shortMen(army.men)
		t.target = target
		t.province = army.location
	end
	for id, token in tokens do
		if not alive[id] then
			token.frame:Destroy()
			tokens[id] = nil
		end
	end
end

-- What is under a screen point: an army token (they sit on top) or a province.
function MapRenderer.pick(screenPos: Vector2): ("Army" | "Province" | nil, number?)
	local best: number? = nil
	local bestDistance = TOKEN_PICK
	for id, token in tokens do
		if token.frame.Visible then
			local d = (MapView.toScreen(token.pos) - screenPos).Magnitude
			if d < bestDistance then
				best, bestDistance = id, d
			end
		end
	end
	if best then
		return "Army", best
	end
	local g = grid
	if g then
		local p = MapView.toMap(screenPos)
		local id = MapGrid.at(g, p.X, p.Y)
		if id ~= 0 then
			return "Province", id
		end
	end
	return nil, nil
end

-- Route dots through province centres (the selected army's way, or a preview before confirming).
function MapRenderer.showRoute(from: number?, path: { number }?, preview: boolean?)
	local routeLayer = layers.Route
	if routeLayer == nil then
		return
	end
	routeLayer:ClearAllChildren()
	if from == nil or path == nil or #path == 0 then
		return
	end
	local color = if preview then Color3.fromRGB(255, 230, 90) else Color3.new(1, 1, 1)
	local prev = MapRenderer.centerOf(from)
	for _, id in path do
		local nextPoint = MapRenderer.centerOf(id)
		dots(routeLayer, prev, nextPoint, color, 5)
		prev = nextPoint
	end
end

function MapRenderer.select(provinceId: number?)
	local a = art
	if a then
		PixelArt.select(a, provinceId)
	end
end

function MapRenderer.selectArmy(armyId: number?)
	if selectedArmy and tokens[selectedArmy] then
		local old = tokens[selectedArmy]
		old.stroke.Color = Color3.fromRGB(20, 20, 28)
		old.stroke.Thickness = 2
	end
	selectedArmy = armyId
	local token = if armyId then tokens[armyId] else nil
	if token then
		token.stroke.Color = Color3.fromRGB(255, 230, 90)
		token.stroke.Thickness = 3
	end
end

-- Send what changed in the pixel art to the image: only the changed rectangle, unless most of it changed.
local function upload(editable: EditableImage, a: PixelArt.Art, d: { number })
	local x0, y0, x1, y1 = d[1], d[2], d[3], d[4]
	local w, h = x1 - x0 + 1, y1 - y0 + 1
	if w * h * 2 >= a.width * a.height then
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(a.width, a.height), a.pixels)
		return
	end
	local rect = buffer.create(w * h * 4)
	for row = 0, h - 1 do
		buffer.copy(rect, row * w * 4, a.pixels, ((y0 + row) * a.width + x0) * 4, w * 4)
	end
	editable:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), rect)
end

function MapRenderer.init()
	MapView.onZoom(onZoom)
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
			refreshCrowns()
		end
	end)
	ClientState.onDelta(function(delta)
		for _, record in delta.provinces do
			refreshProvince(record)
		end
		if #delta.provinces > 0 or #delta.nations > 0 then
			paintOwners()
			refreshCrowns()
		end
		if #delta.armies > 0 or #delta.removedArmies > 0 then
			refreshArmies()
		end
	end)
	ClientState.onPositions(function()
		refreshArmies()
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		-- tokens glide towards their targets
		local a = 1 - math.exp(-TOKEN_SMOOTHING * dt)
		for _, token in tokens do
			if (token.pos - token.target).Magnitude > 0.05 then
				token.pos = token.pos:Lerp(token.target, a)
				token.frame.Position = at(token.pos)
			end
		end
		-- the pixel art goes to the screen at most once a frame
		local editable, painted = image, art
		if editable and painted and imageLabel then
			local d = PixelArt.takeDirty(painted)
			if d then
				upload(editable, painted, d)
			end
		end
	end)
end

return MapRenderer
