--!strict
-- Phase 1 prototype map (docs/DESIGN.md "Map rendering"): one flat disc per province at its centre, sized by its
-- area, with links between neighbours. Colours change only when ownership changes; army tokens are rebuilt when
-- armies change. Phase 4 swaps the discs for generated province meshes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local LABEL_DISTANCE = 220 -- labels show only when zoomed in this close (studs)

local MapRenderer = {}

local root: Model? = nil
local discs: { [number]: Part } = {}
local armyFolder: Folder? = nil
local selectionBox: SelectionBox? = nil
local mapSize = Vector2.new(1024, 512)

-- Map pixel -> world position on the ground plane (the map is centred on the origin, north is -Z).
function MapRenderer.toWorld(p: Types.Point): Vector3
	return Vector3.new(p.x * STUDS_PER_PIXEL - mapSize.X / 2, 0, p.y * STUDS_PER_PIXEL - mapSize.Y / 2)
end

function MapRenderer.mapSize(): Vector2
	return mapSize
end

function MapRenderer.provinceFolder(): Instance?
	return if root then root:FindFirstChild("Provinces") else nil
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

local function makeLabel(parent: BasePart, text: string, height: number, maxDistance: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
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

local function provinceColor(def: Types.ProvinceDef, record: Snapshot.ProvinceRecord?): Color3
	if def.terrain == "Mountain" then
		return Palette.neutral.Mountain
	end
	local owner = if record then record.owner else 0
	if owner ~= 0 then
		local nation = ClientState.nation(owner)
		if nation then
			return Palette.nation(nation.colorIndex)
		end
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
			makeLabel(disc, def.name .. "\n" .. pips(development), 2, LABEL_DISTANCE)
		end
		discs[def.id] = disc
	end

	local box = Instance.new("SelectionBox")
	box.Name = "Selection"
	box.LineThickness = 0.4
	box.Color3 = Color3.new(1, 1, 1)
	box.SurfaceTransparency = 1
	box.Parent = model
	selectionBox = box

	model.Parent = workspace
	root = model
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
end

local function shortMen(men: number): string
	if men >= 1000 then
		return string.format("%gk", math.floor(men / 100) / 10)
	end
	return tostring(men)
end

-- Army tokens: a small block above the province with the army's size. Rebuilt on change (at most 60 armies).
local function refreshArmies()
	local folder = armyFolder
	local snapshot = ClientState.snapshot()
	local map = ClientState.map()
	if folder == nil or snapshot == nil or map == nil then
		return
	end
	folder:ClearAllChildren()
	local perProvince: { [number]: number } = {}
	for _, army in snapshot.armies do
		local slot = perProvince[army.location] or 0
		perProvince[army.location] = slot + 1
		local nation = ClientState.nation(army.owner)
		local color = if nation then Palette.nation(nation.colorIndex) else Palette.neutral.Plains
		local pos = MapRenderer.toWorld(map.provinces[army.location].center) + Vector3.new(slot * 3, 2.5, 0)
		local token = makePart("Army" .. army.id, Vector3.new(2.4, 1.6, 2.4), CFrame.new(pos), color, folder)
		token.Material = Enum.Material.Neon
		token.CanQuery = false
		makeLabel(token, "⚔ " .. shortMen(army.men), 2, LABEL_DISTANCE * 2)
	end
end

function MapRenderer.select(provinceId: number?)
	local box = selectionBox
	if box then
		-- hide instead of clearing Adornee, so the same code also runs in the headless harness
		if provinceId and discs[provinceId] then
			box.Adornee = discs[provinceId]
		end
		box.Visible = provinceId ~= nil
	end
end

function MapRenderer.init()
	ClientState.onReset(function()
		local map = ClientState.map()
		if map then
			build(map)
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
end

return MapRenderer
