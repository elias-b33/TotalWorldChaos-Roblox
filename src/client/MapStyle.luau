--!strict
-- How each biome looks: a built-in Roblox material (real PBR textures, no uploads needed) and its natural colour.
-- In the Political view the colour is replaced by the owner's nation colour; the material keeps the terrain
-- readable underneath (docs/MAPS.md "Art direction"). Heights give the map relief.

local MapStyle = {}

export type Style = { material: Enum.Material, color: Color3 }

local function s(material: Enum.Material, hex: string): Style
	return { material = material, color = Color3.fromHex(hex) }
end

local M = Enum.Material

local BIOMES: { [string]: Style } = {
	-- Earth
	grassland = s(M.Grass, "#6f9a3c"),
	steppe = s(M.Grass, "#b3a862"),
	savanna = s(M.Grass, "#c9a952"),
	desert = s(M.Sand, "#dcb377"),
	tundra = s(M.Ground, "#9a9884"),
	forest = s(M.LeafyGrass, "#3f7a2e"),
	taiga = s(M.LeafyGrass, "#2e6646"),
	jungle = s(M.LeafyGrass, "#2f8c34"),
	hills = s(M.Ground, "#7b8a46"),
	drylands = s(M.Sandstone, "#b08d5c"),
	mountains = s(M.Rock, "#7a756d"),
	ice = s(M.Snow, "#e8f0f5"),
	-- Eldmoor
	meadow = s(M.Grass, "#74bd45"),
	frostfields = s(M.Snow, "#dfe9f2"),
	dunes = s(M.Sand, "#e89a45"),
	wildwood = s(M.LeafyGrass, "#1f8a63"),
	highlands = s(M.Ground, "#7c9a5e"),
	ashlands = s(M.CrackedLava, "#3a3236"),
	peaks = s(M.Rock, "#6a7390"),
	-- Skyshards
	skymeadow = s(M.Grass, "#86d35a"),
	heartruins = s(M.Marble, "#e6dfcf"),
	crystalgrove = s(M.LeafyGrass, "#9a52b4"),
	crags = s(M.Slate, "#8a84a0"),
	stormspire = s(M.Basalt, "#3a3f58"),
}

local FALLBACK = s(M.Grass, "#7fa04a")

function MapStyle.biome(name: string): Style
	return BIOMES[name] or FALLBACK
end

-- Height of each terrain's surface above the sea, in studs: hills and mountains stand out.
MapStyle.height = {
	Plains = 1,
	Forest = 1.4,
	Hills = 2,
	Mountain = 3,
} :: { [string]: number }

-- What lies around the land: Roblox terrain water for seas, a deep sky for Skyshards.
MapStyle.water = {
	earth = Color3.fromHex("#1d5f8a"),
	fantasy = Color3.fromHex("#1b8db8"),
} :: { [string]: Color3 }

MapStyle.void = Color3.fromHex("#20265a")

-- Province borders: thin between your own provinces, bold where two nations meet.
MapStyle.border = Color3.fromHex("#14161c")
MapStyle.borderThin = 0.35
MapStyle.borderBold = 0.9

-- Owned land: the nation colour, nudged towards the terrain colour so the material still reads.
MapStyle.ownerBlend = 0.15

return MapStyle
