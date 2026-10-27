--!strict
-- The land itself: every province built from its real shape (triangles from MapData, two wedges each), with the
-- biome's Roblox material, relief by terrain, rocky ridges on mountains, Terrain water for seas and border lines.
-- Recolouring a province only touches its own parts.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)

local MapStyle = require(script.Parent.MapStyle)

local MapSurface = {}

export type Province = {
	model: Model,
	parts: { BasePart },
	top: number, -- surface height
}

local provinces: { [number]: Province } = {}
local borders: { { a: number, b: number, parts: { BasePart } } } = {}

local function newPart(class: string, parent: Instance, material: Enum.Material, color: Color3): BasePart
	local part = Instance.new(class) :: BasePart
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- One flat triangle a-b-c (world points on the same height) as two wedges, `thickness` studs thick, centred on
-- the triangle's plane. The classic two-wedge construction: the vertex opposite the longest edge splits it in two
-- right triangles, each filled by one wedge.
local function triangle(a: Vector3, b: Vector3, c: Vector3, thickness: number, out: { BasePart }, make: () -> BasePart)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	if ac:Cross(ab).Magnitude < 1e-6 then
		return -- degenerate
	end
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local w1 = make()
	w1.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	table.insert(out, w1)
	local w2 = make()
	w2.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	table.insert(out, w2)
end

-- A rocky ridge (Λ in cross-section) with a snow cap, for mountain provinces.
local function ridge(at: Vector3, length: number, yaw: number, parent: Instance, rock: Color3, out: { BasePart })
	local width = length * 0.55
	local tall = 2.5 + length * 0.25
	local function half(scale: number, base: number, material: Enum.Material, color: Color3)
		local w, hgt = width * scale, tall * scale
		for _, flip in { 0, math.pi } do
			local wedge = newPart("WedgePart", parent, material, color)
			wedge.CastShadow = true
			wedge.Size = Vector3.new(length * scale, hgt, w / 2)
			wedge.CFrame = CFrame.new(at + Vector3.new(0, base + hgt / 2, 0))
				* CFrame.Angles(0, yaw + flip, 0)
				* CFrame.new(0, 0, -w / 4)
			table.insert(out, wedge)
		end
	end
	half(1, 0, Enum.Material.Rock, rock)
	half(0.34, tall * 0.66, Enum.Material.Snow, Color3.fromHex("#f4f7fa"))
end

local function setupWorld(map: Types.MapDef, size: Vector2, parent: Instance)
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	local terrain = workspace.Terrain
	terrain:Clear()
	local water = MapStyle.water[map.theme]
	if water then
		terrain.WaterColor = water
		terrain.WaterWaveSize = 0.08
		terrain.WaterWaveSpeed = 6
		terrain.WaterReflectance = 0.4
		terrain.WaterTransparency = 0.3
		terrain:FillBlock(CFrame.new(0, -2, 0), Vector3.new(size.X * 1.8, 4, size.Y * 1.8), Enum.Material.Water)
	else
		-- Skyshards: the islands float over a deep sky
		local void = newPart("Part", parent, Enum.Material.SmoothPlastic, MapStyle.void)
		void.Name = "Void"
		void.Size = Vector3.new(size.X * 2, 1, size.Y * 2)
		void.CFrame = CFrame.new(0, -30, 0)
		void.CanQuery = false
	end
end

-- Build the whole map under `parent`. toWorld turns map pixels into ground positions.
function MapSurface.build(map: Types.MapDef, size: Vector2, parent: Instance, toWorld: (number, number) -> Vector3)
	provinces = {}
	borders = {}
	setupWorld(map, size, parent)

	local land = Instance.new("Folder")
	land.Name = "Provinces"
	land.Parent = parent
	for _, def in map.provinces do
		local style = MapStyle.biome(def.biome)
		local top = MapStyle.height[def.terrain] or 1
		local model = Instance.new("Model")
		model.Name = "P" .. def.id
		local parts: { BasePart } = {}
		local function make(): BasePart
			local w = newPart("WedgePart", model, style.material, style.color)
			w:SetAttribute("ProvinceId", def.id)
			return w
		end
		local tris = def.tris
		local y = top / 2
		for i = 1, #tris - 5, 6 do
			local a = toWorld(tris[i], tris[i + 1]) + Vector3.new(0, y, 0)
			local b = toWorld(tris[i + 2], tris[i + 3]) + Vector3.new(0, y, 0)
			local c = toWorld(tris[i + 4], tris[i + 5]) + Vector3.new(0, y, 0)
			triangle(a, b, c, top, parts, make)
		end
		if def.terrain == "Mountain" then
			-- a few ridges on the biggest triangles, so mountains read as mountains from any zoom
			local spots = {}
			for i = 1, #tris - 5, 6 do
				local ax, ay, bx, by, cx, cy = tris[i], tris[i + 1], tris[i + 2], tris[i + 3], tris[i + 4], tris[i + 5]
				local area = math.abs((bx - ax) * (cy - ay) - (cx - ax) * (by - ay)) / 2
				table.insert(spots, { area = area, x = (ax + bx + cx) / 3, y = (ay + by + cy) / 3 })
			end
			table.sort(spots, function(p, q)
				return p.area > q.area
			end)
			for k = 1, math.min(4, #spots) do
				local spot = spots[k]
				local length = math.clamp(math.sqrt(spot.area) * 0.5, 3, 16)
				local yaw = ((def.id * 37 + k * 71) % 360) * math.pi / 180
				ridge(toWorld(spot.x, spot.y) + Vector3.new(0, top, 0), length, yaw, model, style.color, parts)
			end
		end
		for _, part in parts do
			part:SetAttribute("ProvinceId", def.id) -- ridges too, so taps on them select the province
		end
		model.Parent = land
		provinces[def.id] = { model = model, parts = parts, top = top }
	end

	local lines = Instance.new("Folder")
	lines.Name = "Borders"
	lines.Parent = parent
	for _, border in map.borders do
		local pa, pb = provinces[border.a], provinces[border.b]
		local yTop = math.max(pa and pa.top or 1, pb and pb.top or 1) + 0.06
		local segs: { BasePart } = {}
		local pts = border.points
		for i = 1, #pts - 3, 2 do
			local p0 = toWorld(pts[i], pts[i + 1]) + Vector3.new(0, yTop, 0)
			local p1 = toWorld(pts[i + 2], pts[i + 3]) + Vector3.new(0, yTop, 0)
			local length = (p1 - p0).Magnitude
			if length > 0.01 then
				local seg = newPart("Part", lines, Enum.Material.SmoothPlastic, MapStyle.border)
				seg.Name = "Border"
				seg.CanQuery = false
				seg.Size = Vector3.new(MapStyle.borderThin, 0.1, length + MapStyle.borderThin)
				seg.CFrame = CFrame.lookAt((p0 + p1) / 2, p1)
				table.insert(segs, seg)
			end
		end
		table.insert(borders, { a = border.a, b = border.b, parts = segs })
	end
end

function MapSurface.province(id: number): Province?
	return provinces[id]
end

function MapSurface.top(id: number): number
	local p = provinces[id]
	return if p then p.top else 1
end

-- Paint one province. Mountains keep their rock, whoever claims them.
function MapSurface.paint(id: number, color: Color3)
	local p = provinces[id]
	if p == nil then
		return
	end
	for _, part in p.parts do
		if part.Material ~= Enum.Material.Rock and part.Material ~= Enum.Material.Snow then
			part.Color = color
		end
	end
end

-- Bold lines where two different owners meet, thin lines inside a nation (owner 0 = neutral).
function MapSurface.updateBorders(ownerOf: (number) -> number)
	for _, b in borders do
		local bold = ownerOf(b.a) ~= ownerOf(b.b)
		local width = if bold then MapStyle.borderBold else MapStyle.borderThin
		for _, seg in b.parts do
			if math.abs(seg.Size.X - width) > 1e-3 then
				local length = seg.Size.Z - seg.Size.X + width
				seg.Size = Vector3.new(width, 0.1, length)
				seg.Transparency = if bold then 0 else 0.45
			end
		end
	end
end

return MapSurface
