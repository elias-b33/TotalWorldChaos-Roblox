--!strict
-- The custom texture pack (assets/textures/hd, made by tools/mapgen/materials.py): one MaterialVariant per map
-- material. A variant is used when MaterialService already has it (made in Studio's Material Manager) or when its
-- image ids are filled in below; otherwise parts keep the built-in Roblox material. See docs/MAPS.md
-- "Custom texture pack".

local MaterialService = game:GetService("MaterialService")

local MaterialPack = {}

type Entry = {
	name: string,
	base: Enum.Material,
	studsPerTile: number,
	-- image asset ids ("rbxassetid://123"), filled in after uploading assets/textures/hd/<name>/*.png
	color: string,
	normal: string,
	roughness: string,
}

local M = Enum.Material

-- Same names, base materials and tile sizes as tools/mapgen/materials.py.
local ENTRIES: { Entry } = {
	{ name = "TWC_Grass", base = M.Grass, studsPerTile = 64, color = "", normal = "", roughness = "" },
	{ name = "TWC_Forest", base = M.LeafyGrass, studsPerTile = 40, color = "", normal = "", roughness = "" },
	{ name = "TWC_Sand", base = M.Sand, studsPerTile = 64, color = "", normal = "", roughness = "" },
	{ name = "TWC_Ground", base = M.Ground, studsPerTile = 48, color = "", normal = "", roughness = "" },
	{ name = "TWC_Sandstone", base = M.Sandstone, studsPerTile = 64, color = "", normal = "", roughness = "" },
	{ name = "TWC_Rock", base = M.Rock, studsPerTile = 48, color = "", normal = "", roughness = "" },
	{ name = "TWC_Snow", base = M.Snow, studsPerTile = 64, color = "", normal = "", roughness = "" },
	{ name = "TWC_Ash", base = M.CrackedLava, studsPerTile = 48, color = "", normal = "", roughness = "" },
	{ name = "TWC_Marble", base = M.Marble, studsPerTile = 48, color = "", normal = "", roughness = "" },
	{ name = "TWC_Slate", base = M.Slate, studsPerTile = 48, color = "", normal = "", roughness = "" },
	{ name = "TWC_Basalt", base = M.Basalt, studsPerTile = 40, color = "", normal = "", roughness = "" },
}

local available: { [Enum.Material]: string } = {}

-- Find or create the variants. Call once before building the map.
function MaterialPack.setup()
	available = {}
	for _, entry in ENTRIES do
		local existing = MaterialService:FindFirstChild(entry.name, true)
		if existing and existing:IsA("MaterialVariant") then
			available[entry.base] = entry.name
		elseif entry.color ~= "" then
			local variant = Instance.new("MaterialVariant")
			variant.Name = entry.name
			variant.BaseMaterial = entry.base
			variant.StudsPerTile = entry.studsPerTile
			variant.ColorMap = entry.color
			variant.NormalMap = entry.normal
			variant.RoughnessMap = entry.roughness
			variant.Parent = MaterialService
			available[entry.base] = entry.name
		end
	end
end

-- The variant to put on a part of this material, or nil to keep the built-in look.
function MaterialPack.variantFor(material: Enum.Material): string?
	return available[material]
end

return MaterialPack
