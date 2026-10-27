--!strict
-- The map on screen: the land comes from MapSurface (real province shapes, materials, relief, water, borders);
-- this module adds what changes during a match. Provinces are painted in their owner's colour when ownership
-- changes; army tokens glide between province centres from the unreliable position updates; markers show battles
-- and sieges; route lines show where a selected army is going; names appear when zoomed in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local MapSurface = require(script.Parent.MapSurface)
local MapStyle = require(script.Parent.MapStyle)
local Palette = require(script.Parent.Palette)

local STUDS_PER_PIXEL = 0.5 -- docs/MAPS.md "Map data pipeline"
local LABEL_DISTANCE = 120 -- neutral garrison labels show only when zoomed in this close (studs)
local NAME_ZOOM = 4 -- a province's name shows once the camera is within this many province widths
local NAME_MIN, NAME_MAX = 50, 600 -- clamp for that distance (studs)
local TOKEN_HEIGHT = 2.5
local TOKEN_SPACING = 3.2
local TOKEN_SMOOTHING = 6 -- higher = tokens catch up with their target faster
local MARKER_DISTANCE = 5000 -- battle and siege markers show at every zoom

local MapRenderer = {}

local root: Model? = nil
local anchors: { [number]: Part } = {}
local markers: { [number]: { gui: BillboardGui, label: TextLabel } } = {}
local tokens: { [number]: { part: Part, label: TextLabel, target: Vector3 } } = {}
local armyFolder: Folder? = nil
local routeFolder: Folder? = nil
local provinceHighlight: Highlight? = nil
local armyBox: SelectionBox? = nil
local mapSize = Vector2.new(1024, 512)

-- Map pixel -> world position on the ground plane (the map is centred on the origin, north is -Z).
function MapRenderer.toWorld(p: Types.Point): Vector3
	return Vector3.new(p.x * STUDS_PER_PIXEL - mapSize.X / 2, 0, p.y * STUDS_PER_PIXEL - mapSize.Y / 2)
end

function MapRenderer.mapSize(): Vector2
	return mapSize
end

-- A province's centre on its surface.
function MapRenderer.centerOf(provinceId: number): Vector3
	local map = ClientState.map()
	if map == nil then
		return Vector3.zero
	end
	return MapRenderer.toWorld(map.provinces[provinceId].center) + Vector3.new(0, MapSurface.top(provinceId), 0)
end

-- What taps can hit: army tokens first (they sit on top), then provinces.
function MapRenderer.pickables(): { Instance }
	local out = {}
	if root then
		for _, name in { "Armies", "Provinces" } do
			local folder = root:FindFirstChild(name)
			if folder then
				table.insert(out, folder)
			end
		end
	end
	return out
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Parent = parent
	return part
end

-- A billboard on a part. Its texts are placed in pixels inside it, so a text in the bottom half shows just below
-- the part and one in the top half just above, at every zoom (a world-space offset shrinks to nothing from afar).
local function billboard(
	parent: BasePart,
	name: string,
	width: number,
	height: number,
	maxDistance: number
): BillboardGui
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromOffset(width, height)
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.Parent = parent
	return gui
end

local function text(gui: BillboardGui, value: string, size: number, top: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, top)
	label.Size = UDim2.new(1, 0, 0, size + 4)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = value
	label.Parent = gui
	return label
end

local function pips(development: number): string
	return string.rep("●", development) .. string.rep("○", 5 - development)
end

local function nationColor(nationId: number): Color3
	local nation = ClientState.nation(nationId)
	return if nation then Palette.nation(nation.colorIndex) else Palette.neutral.Mountain
end

-- Political view: the owner's colour (a touch of the terrain colour keeps the material readable);
-- neutral land shows its natural terrain colour.
local function provinceColor(def: Types.ProvinceDef, record: Snapshot.ProvinceRecord?): Color3
	local natural = MapStyle.biome(def.biome).color
	local owner = if record then record.owner else 0
	if owner ~= 0 and def.terrain ~= "Mountain" then
		return nationColor(owner):Lerp(natural, MapStyle.ownerBlend)
	end
	return natural
end

local function link(a: Vector3, b: Vector3, width: number, color: Color3, transparency: number, parent: Instance)
	local length = (b - a).Magnitude
	if length < 0.01 then
		return
	end
	local mid = (a + b) / 2 + Vector3.new(0, 0.2, 0)
	local part =
		makePart("Link", Vector3.new(width, 0.2, length), CFrame.lookAt(mid, b + Vector3.new(0, 0.2, 0)), color, parent)
	part.Transparency = transparency
	part.CanQuery = false
end

local function build(map: Types.MapDef)
	if root then
		root:Destroy()
	end
	anchors = {}
	markers = {}
	tokens = {}
	mapSize = Vector2.new(map.imageSize.x, map.imageSize.y) * STUDS_PER_PIXEL

	local model = Instance.new("Model")
	model.Name = "Map"
	MapSurface.build(map, mapSize, model, function(x: number, y: number): Vector3
		return MapRenderer.toWorld({ x = x, y = y })
	end)
	local armies = Instance.new("Folder")
	armies.Name = "Armies"
	armies.Parent = model
	armyFolder = armies
	local routes = Instance.new("Folder")
	routes.Name = "Routes"
	routes.Parent = model
	routeFolder = routes
	local straits = Instance.new("Folder")
	straits.Name = "Straits"
	straits.Parent = model
	for _, st in map.straits do
		if not st.wrap then
			local y = Vector3.new(0, math.max(MapSurface.top(st.a), MapSurface.top(st.b)) + 0.1, 0)
			link(MapRenderer.toWorld(st.from) + y, MapRenderer.toWorld(st.to) + y, 1, Palette.strait, 0.2, straits)
		end
	end

	-- an invisible anchor at each province's centre carries its name label and battle/siege marker
	local anchorFolder = Instance.new("Folder")
	anchorFolder.Name = "Anchors"
	anchorFolder.Parent = model
	for _, def in map.provinces do
		local top = MapSurface.top(def.id)
		local anchor = makePart(
			"A" .. def.id,
			Vector3.new(1, 1, 1),
			CFrame.new(MapRenderer.toWorld(def.center) + Vector3.new(0, top, 0)),
			Color3.new(1, 1, 1),
			anchorFolder
		)
		anchor.Transparency = 1
		anchor.CanQuery = false
		if def.terrain ~= "Mountain" then
			-- big provinces name themselves from far away, small ones only up close, so labels rarely pile up
			local width = 2 * math.sqrt(def.area / math.pi) * STUDS_PER_PIXEL
			local distance = math.clamp(width * NAME_ZOOM, NAME_MIN, NAME_MAX)
			local record = ClientState.province(def.id)
			local development = if record then record.development else def.development
			local gui = billboard(anchor, "Label", 140, 64, distance) -- name and pips just below the centre
			text(gui, def.name, 13, 34).Name = "Name"
			text(gui, pips(development), 9, 50).Name = "Pips"
		end
		anchors[def.id] = anchor
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ProvinceSelection"
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.75
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.Enabled = false
	highlight.Parent = model
	provinceHighlight = highlight
	local abox = Instance.new("SelectionBox")
	abox.Name = "ArmySelection"
	abox.LineThickness = 0.3
	abox.Color3 = Color3.fromRGB(255, 230, 90)
	abox.SurfaceTransparency = 1
	abox.Visible = false
	abox.Parent = model
	armyBox = abox

	model.Parent = workspace
	root = model
end

-- Battle and siege markers: one small always-visible label per province, made on demand.
local function setMarker(provinceId: number, value: string?)
	local existing = markers[provinceId]
	if value == nil then
		if existing then
			existing.gui.Enabled = false
		end
		return
	end
	if existing == nil then
		local anchor = anchors[provinceId]
		if anchor == nil then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "Marker"
		gui.Size = UDim2.fromOffset(70, 24)
		gui.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
		gui.MaxDistance = MARKER_DISTANCE
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
		label.BackgroundTransparency = 0.25
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = label
		gui.Parent = anchor
		existing = { gui = gui, label = label }
		markers[provinceId] = existing
	end
	local marker = assert(existing, "marker")
	marker.label.Text = value
	marker.gui.Enabled = true
end

local function ownerOf(id: number): number
	local record = ClientState.province(id)
	return if record then record.owner else 0
end

local function refreshProvince(record: Snapshot.ProvinceRecord)
	local map = ClientState.map()
	local anchor = anchors[record.id]
	if map == nil or anchor == nil then
		return
	end
	local def = map.provinces[record.id]
	MapSurface.paint(record.id, provinceColor(def, record))
	local gui = anchor:FindFirstChild("Label")
	local label = gui and gui:FindFirstChild("Pips")
	if label and label:IsA("TextLabel") then
		label.Text = pips(record.development)
	end
	if record.battle then
		setMarker(record.id, "💥")
	elseif record.siegeBy ~= 0 and record.siegeRequired > 0 then
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
local function tokenTarget(army: Snapshot.ArmyRecord, slot: number): Vector3
	local up = Vector3.new(0, TOKEN_HEIGHT - 1, 0)
	local pos = ClientState.position(army.id)
	if pos and army.next ~= 0 then
		return MapRenderer.centerOf(pos.from):Lerp(MapRenderer.centerOf(pos.to), pos.progress) + up
	end
	return MapRenderer.centerOf(army.location) + up + Vector3.new((slot - 1) * TOKEN_SPACING, 0, 0)
end

local function refreshArmies()
	local folder = armyFolder
	local snapshot = ClientState.snapshot()
	if folder == nil or snapshot == nil then
		return
	end
	local alive: { [number]: boolean } = {}
	local perProvince: { [number]: number } = {}
	for _, army in snapshot.armies do
		alive[army.id] = true
		local slot = (perProvince[army.location] or 0) + 1
		perProvince[army.location] = slot
		local token = tokens[army.id]
		local neutral = army.owner == 0
		if token == nil then
			local size = if neutral then Vector3.new(1.6, 1, 1.6) else Vector3.new(2.4, 1.6, 2.4)
			local part =
				makePart("Army" .. army.id, size, CFrame.new(tokenTarget(army, slot)), nationColor(army.owner), folder)
			part.Material = if neutral then Enum.Material.SmoothPlastic else Enum.Material.Neon
			part:SetAttribute("ArmyId", army.id)
			-- the men count just above the token
			local gui = billboard(part, "Label", 90, 44, if neutral then LABEL_DISTANCE else LABEL_DISTANCE * 3)
			local label = text(gui, "", if neutral then 11 else 13, 2)
			token = { part = part, label = label, target = part.CFrame.Position }
			tokens[army.id] = token
		end
		token = assert(token, "token")
		token.label.Text = (if neutral then "🛡 " elseif army.inBattle then "💥 " else "⚔ ") .. shortMen(army.men)
		token.target = tokenTarget(army, slot)
	end
	for id, token in tokens do
		if not alive[id] then
			token.part:Destroy()
			tokens[id] = nil
		end
	end
end

-- Route line through province centres (the selected army's way, or a preview before confirming).
function MapRenderer.showRoute(from: number?, path: { number }?, preview: boolean?)
	local folder = routeFolder
	if folder == nil then
		return
	end
	folder:ClearAllChildren()
	if from == nil or path == nil or #path == 0 then
		return
	end
	local color = if preview then Color3.fromRGB(255, 230, 90) else Color3.new(1, 1, 1)
	local prev = MapRenderer.centerOf(from) + Vector3.new(0, 0.6, 0)
	for _, id in path do
		local nextPoint = MapRenderer.centerOf(id) + Vector3.new(0, 0.6, 0)
		local length = (nextPoint - prev).Magnitude
		if length > 0.01 then
			local seg = makePart(
				"Route",
				Vector3.new(0.9, 0.3, length),
				CFrame.lookAt((prev + nextPoint) / 2, nextPoint),
				color,
				folder
			)
			seg.Material = Enum.Material.Neon
			seg.CanQuery = false
		end
		prev = nextPoint
	end
end

function MapRenderer.select(provinceId: number?)
	local highlight = provinceHighlight
	if highlight then
		-- disable instead of clearing Adornee, so the same code also runs in the headless harness
		local province = if provinceId then MapSurface.province(provinceId) else nil
		if province then
			highlight.Adornee = province.model
		end
		highlight.Enabled = province ~= nil
	end
end

function MapRenderer.selectArmy(armyId: number?)
	local box = armyBox
	if box then
		local token = if armyId then tokens[armyId] else nil
		if token then
			box.Adornee = token.part
		end
		box.Visible = token ~= nil
	end
end

function MapRenderer.init()
	ClientState.onReset(function()
		local map = ClientState.map()
		if map then
			build(map)
			local snapshot = ClientState.snapshot()
			if snapshot then
				for _, record in snapshot.provinces do
					refreshProvince(record)
				end
			end
			MapSurface.updateBorders(ownerOf)
			refreshArmies()
		end
	end)
	ClientState.onDelta(function(delta)
		local ownersChanged = false
		for _, record in delta.provinces do
			refreshProvince(record)
			ownersChanged = true
		end
		if ownersChanged then
			MapSurface.updateBorders(ownerOf)
		end
		if #delta.armies > 0 or #delta.removedArmies > 0 then
			refreshArmies()
		end
	end)
	ClientState.onPositions(function()
		refreshArmies()
	end)
	-- glide tokens towards their targets every frame
	RunService.RenderStepped:Connect(function(dt: number)
		local a = 1 - math.exp(-TOKEN_SMOOTHING * dt)
		for _, token in tokens do
			local current = token.part.CFrame.Position
			if (current - token.target).Magnitude > 0.05 then
				token.part.CFrame = CFrame.new(current:Lerp(token.target, a))
			end
		end
	end)
end

return MapRenderer
