--!strict
-- Prototype map (docs/DESIGN.md "Map rendering"): one flat disc per province at its centre, sized by its area,
-- with links between neighbours. Colours change only when ownership changes. Army tokens glide between province
-- centres from the unreliable position updates; markers show battles and sieges; route lines show where a
-- selected army is going. Phase 4 swaps the discs for generated province meshes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local Palette = require(script.Parent.Palette)

local STUDS_PER_PIXEL = 0.5 -- docs/MAPS.md "Map data pipeline"
local DISC_HEIGHT = 1
local MOUNTAIN_HEIGHT = 3
local DISC_FILL = 0.85 -- disc diameter as a share of the province's own size, so neighbours don't overlap
local LABEL_DISTANCE = 120 -- province names show only when zoomed in this close (studs)
local TOKEN_HEIGHT = 2.5
local TOKEN_SPACING = 3.2
local TOKEN_SMOOTHING = 6 -- higher = tokens catch up with their target faster
local MARKER_DISTANCE = 5000 -- battle and siege markers show at every zoom

local MapRenderer = {}

local root: Model? = nil
local discs: { [number]: Part } = {}
local markers: { [number]: { gui: BillboardGui, label: TextLabel } } = {}
local tokens: { [number]: { part: Part, label: TextLabel, target: Vector3 } } = {}
local armyFolder: Folder? = nil
local routeFolder: Folder? = nil
local provinceBox: SelectionBox? = nil
local armyBox: SelectionBox? = nil
local mapSize = Vector2.new(1024, 512)

-- Map pixel -> world position on the ground plane (the map is centred on the origin, north is -Z).
function MapRenderer.toWorld(p: Types.Point): Vector3
	return Vector3.new(p.x * STUDS_PER_PIXEL - mapSize.X / 2, 0, p.y * STUDS_PER_PIXEL - mapSize.Y / 2)
end

function MapRenderer.mapSize(): Vector2
	return mapSize
end

function MapRenderer.centerOf(provinceId: number): Vector3
	local map = ClientState.map()
	return if map then MapRenderer.toWorld(map.provinces[provinceId].center) else Vector3.zero
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

local function makeLabel(parent: BasePart, text: string, height: number, maxDistance: number, size: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(130, 30)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function pips(development: number): string
	return string.rep("●", development) .. string.rep("○", 5 - development)
end

local function nationColor(nationId: number): Color3
	local nation = ClientState.nation(nationId)
	return if nation then Palette.nation(nation.colorIndex) else Palette.neutral.Mountain
end

local function provinceColor(def: Types.ProvinceDef, record: Snapshot.ProvinceRecord?): Color3
	if def.terrain == "Mountain" then
		return Palette.neutral.Mountain
	end
	local owner = if record then record.owner else 0
	if owner ~= 0 then
		return nationColor(owner)
	end
	return Palette.neutral[def.terrain]
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
	discs = {}
	markers = {}
	tokens = {}
	mapSize = Vector2.new(map.imageSize.x, map.imageSize.y) * STUDS_PER_PIXEL

	local model = Instance.new("Model")
	model.Name = "Map"
	local provinces = Instance.new("Folder")
	provinces.Name = "Provinces"
	provinces.Parent = model
	local links = Instance.new("Folder")
	links.Name = "Links"
	links.Parent = model
	local armies = Instance.new("Folder")
	armies.Name = "Armies"
	armies.Parent = model
	armyFolder = armies
	local routes = Instance.new("Folder")
	routes.Name = "Routes"
	routes.Parent = model
	routeFolder = routes

	-- backdrop: sea (or sky) under the whole map
	local backdrop = makePart(
		"Backdrop",
		Vector3.new(mapSize.X * 1.6, 1, mapSize.Y * 1.6),
		CFrame.new(0, -2, 0),
		Palette.background[map.theme] or Palette.background.earth,
		model
	)
	backdrop.CanQuery = false

	-- land links between neighbours; straits are drawn on their own, wider and brighter
	local isStrait: { [string]: boolean } = {}
	for _, s in map.straits do
		isStrait[math.min(s.a, s.b) .. "-" .. math.max(s.a, s.b)] = true
		if not s.wrap then
			link(MapRenderer.toWorld(s.from), MapRenderer.toWorld(s.to), 1.2, Palette.strait, 0.15, links)
		end
	end
	for _, def in map.provinces do
		for _, n in def.neighbors do
			if n > def.id and not isStrait[def.id .. "-" .. n] then
				local other = map.provinces[n]
				link(MapRenderer.toWorld(def.center), MapRenderer.toWorld(other.center), 0.6, Palette.link, 0.55, links)
			end
		end
	end

	for _, def in map.provinces do
		local radius = math.sqrt(def.area / math.pi) * STUDS_PER_PIXEL
		local diameter = math.max(3, radius * 2 * DISC_FILL)
		local height = if def.terrain == "Mountain" then MOUNTAIN_HEIGHT else DISC_HEIGHT
		local pos = MapRenderer.toWorld(def.center) + Vector3.new(0, height / 2, 0)
		-- cylinders lie along X; roll them upright to make flat discs
		local disc = makePart(
			"P" .. def.id,
			Vector3.new(height, diameter, diameter),
			CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
			provinceColor(def, ClientState.province(def.id)),
			provinces
		)
		disc.Shape = Enum.PartType.Cylinder
		disc:SetAttribute("ProvinceId", def.id)
		if def.terrain ~= "Mountain" then
			local record = ClientState.province(def.id)
			local development = if record then record.development else def.development
			makeLabel(disc, def.name .. "\n" .. pips(development), 1.5, LABEL_DISTANCE, 12)
		end
		discs[def.id] = disc
	end

	local box = Instance.new("SelectionBox")
	box.Name = "ProvinceSelection"
	box.LineThickness = 0.4
	box.Color3 = Color3.new(1, 1, 1)
	box.SurfaceTransparency = 1
	box.Visible = false
	box.Parent = model
	provinceBox = box
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
local function setMarker(provinceId: number, text: string?)
	local existing = markers[provinceId]
	if text == nil then
		if existing then
			existing.gui.Enabled = false
		end
		return
	end
	if existing == nil then
		local disc = discs[provinceId]
		if disc == nil then
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
		gui.Parent = disc
		existing = { gui = gui, label = label }
		markers[provinceId] = existing
	end
	local marker = assert(existing, "marker")
	marker.label.Text = text
	marker.gui.Enabled = true
end

local function refreshProvince(record: Snapshot.ProvinceRecord)
	local map = ClientState.map()
	local disc = discs[record.id]
	if map == nil or disc == nil then
		return
	end
	local def = map.provinces[record.id]
	disc.Color = provinceColor(def, record)
	local gui = disc:FindFirstChild("Label")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = def.name .. "\n" .. pips(record.development)
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
	local up = Vector3.new(0, TOKEN_HEIGHT, 0)
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
			local label = makeLabel(
				part,
				"",
				2,
				if neutral then LABEL_DISTANCE else LABEL_DISTANCE * 3,
				if neutral then 11 else 13
			)
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
	local prev = MapRenderer.centerOf(from) + Vector3.new(0, 1.2, 0)
	for _, id in path do
		local nextPoint = MapRenderer.centerOf(id) + Vector3.new(0, 1.2, 0)
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
	local box = provinceBox
	if box then
		-- hide instead of clearing Adornee, so the same code also runs in the headless harness
		if provinceId and discs[provinceId] then
			box.Adornee = discs[provinceId]
		end
		box.Visible = provinceId ~= nil
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
			refreshArmies()
		end
	end)
	ClientState.onDelta(function(delta)
		for _, record in delta.provinces do
			refreshProvince(record)
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
