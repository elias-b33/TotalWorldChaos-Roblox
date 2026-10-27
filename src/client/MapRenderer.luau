--!strict
-- What is drawn on the 2D map (docs/DESIGN.md "Map rendering"): the pixel-art image painted by PixelArt
-- (terrain, owners, the selected province), straits, province names, army tokens gliding between province
-- centres, battle and siege markers and route lines. Everything sits on MapView's canvas, placed in map pixels.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local MapGrid = require(Shared.MapGrid)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local MapView = require(script.Parent.MapView)
local Palette = require(script.Parent.Palette)
local PixelArt = require(script.Parent.PixelArt)

local NAME_MIN_PIXELS = 70 -- a province's name shows once the province is this wide on screen
local GARRISON_MIN_ZOOM = 3 -- neutral garrisons show from this zoom (screen pixels per map pixel)
local TOKEN_SIZE = 14 -- army token, screen pixels
local TOKEN_PICK = 20 -- a tap this close to a token's centre (screen pixels) picks the army
local TOKEN_SPACING = 4 -- map pixels between tokens standing in one province
local TOKEN_SMOOTHING = 6 -- higher = tokens catch up with their target faster
local DOT_SPACING = 4 -- map pixels between the dots of a route or strait

local MapRenderer = {}

type Token = { frame: Frame, stroke: UIStroke, label: TextLabel, pos: Vector2, target: Vector2, neutral: boolean }

local grid: MapGrid.Grid? = nil
local art: PixelArt.Art? = nil
local image: EditableImage? = nil
local dirty = false
local size = Vector2.new(1024, 512)
local layers: { [string]: Frame } = {}
local labels: { [number]: { frame: Frame, pips: TextLabel, width: number } } = {}
local markers: { [number]: TextLabel } = {}
local effects: { [number]: TextLabel } = {}
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

local function textLabel(parent: Instance, value: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
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

local function showLabels(z: number)
	for _, label in labels do
		label.frame.Visible = label.width * z >= NAME_MIN_PIXELS
	end
	for _, token in tokens do
		if token.neutral then
			token.frame.Visible = z >= GARRISON_MIN_ZOOM
		end
	end
end

local function build(map: Types.MapDef)
	labels = {}
	markers = {}
	effects = {}
	tokens = {}
	layers = {}
	selectedArmy = nil
	local g = MapGrid.decode(map)
	grid = g
	size = Vector2.new(g.width, g.height)
	art = PixelArt.new(map, g)
	local canvas = MapView.create(size, Palette.background[map.theme] or Palette.background.earth)

	local imageLayer = layer("Image", canvas)
	local ok, result = pcall(function()
		return AssetService:CreateEditableImage({ Size = size })
	end)
	if ok and result then
		image = result
		local label = Instance.new("ImageLabel")
		label.Name = "Pixels"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.ResampleMode = Enum.ResamplerMode.Pixelated
		label.ImageContent = Content.fromObject(result)
		label.Parent = imageLayer
		dirty = true
	else
		image = nil
		warn("[map] no EditableImage (enable it in Game Settings, see docs/MAPS.md):", result)
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
		if def.terrain ~= "Mountain" then
			local record = ClientState.province(def.id)
			local frame = Instance.new("Frame")
			frame.Name = "P" .. def.id
			frame.AnchorPoint = Vector2.new(0.5, 0)
			frame.Position = at(MapRenderer.centerOf(def.id)) + UDim2.fromOffset(0, 6)
			frame.Size = UDim2.fromOffset(140, 30)
			frame.BackgroundTransparency = 1
			frame.Parent = labelLayer
			local name = textLabel(frame, def.name, 13)
			name.Size = UDim2.new(1, 0, 0, 16)
			local dev = textLabel(frame, pips(if record then record.development else def.development), 9)
			dev.Position = UDim2.fromOffset(0, 16)
			dev.Size = UDim2.new(1, 0, 0, 12)
			local areaPixels = def.area / (g.scale * g.scale)
			labels[def.id] = { frame = frame, pips = dev, width = 2 * math.sqrt(areaPixels / math.pi) }
		end
	end
	layer("Tokens", canvas)
	layer("Markers", canvas)
	showLabels(MapView.zoom())
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
	for _, nation in snapshot.nations do
		colors[nation.id] = packed(Palette.nation(nation.colorIndex))
	end
	if PixelArt.setOwners(a, owners, colors) then
		dirty = true
	end
end

-- Badges above a province, made on demand: battle and siege (markers), Primordial-power effects (effects, higher up).
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
		local label = textLabel(layers.Markers, "", 13)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = at(MapRenderer.centerOf(provinceId)) + UDim2.fromOffset(0, -lift)
		label.Size = UDim2.fromOffset(width, 22)
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
	setBadge(markers, provinceId, value, 10, 64)
end

-- A Primordial-power badge over a province (a strike, a shield, a blessing), above the battle/siege badge.
-- nil hides it.
function MapRenderer.setEffect(provinceId: number, value: string?)
	setBadge(effects, provinceId, value, 34, 84)
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
	frame.Visible = not neutral or MapView.zoom() >= GARRISON_MIN_ZOOM
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 28)
	stroke.Thickness = 2
	stroke.Parent = frame
	local label = textLabel(frame, "", if neutral then 10 else 12)
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0, -2)
	label.Size = UDim2.fromOffset(70, 16)
	frame.Parent = layers.Tokens
	return { frame = frame, stroke = stroke, label = label, pos = target, target = target, neutral = neutral }
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
		t.label.Text = (if t.neutral then "🛡 " elseif army.inBattle then "💥 " else "⚔ ") .. shortMen(army.men)
		t.target = target
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
	local best, bestDistance = nil, TOKEN_PICK
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
	if a and PixelArt.select(a, provinceId) then
		dirty = true
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

function MapRenderer.init()
	MapView.onZoom(showLabels)
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
		end
	end)
	ClientState.onDelta(function(delta)
		for _, record in delta.provinces do
			refreshProvince(record)
		end
		if #delta.provinces > 0 or #delta.nations > 0 then
			paintOwners()
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
		local editable = image
		local pixels = art
		if dirty and editable and pixels then
			dirty = false
			editable:WritePixelsBuffer(Vector2.zero, size, pixels.pixels)
		end
	end)
end

return MapRenderer
