--!strict
-- Every nation's equipped cosmetics, as replicated next to the match (Snapshot.cosmetics), and the GUI pieces that
-- show them: pixel-art flags and army tokens (EditableImages painted by CosmeticArt, cached and shared), border and
-- shade swatches, nameplate frame colours. Bots and unknown nations show the defaults; with the default token, a
-- nation's armies are a soldier of its race (Cosmetics.armyLabel).
--
-- Primordial-power effects: Cosmetics.powerEffect(nationId, power) says which effect variant a nation has equipped
-- ("" = the default look); Effects draws it (PowerFx) with the default's area, timing and sound cue.
-- Map themes: Cosmetics.matchTheme() is the look the map is painted in (the theme vote's winner, or the classic look
-- for a player who opted out), Cosmetics.myTheme() the one you bring to the vote (shown on your vote cards).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local MapGrid = require(Shared.MapGrid)
local Maps = require(Shared.Maps)
local Shop = require(Shared.Sim.Shop)
local Types = require(Shared.Types)

local Client = script.Parent
local ClientState = require(Client.ClientState)
local CosmeticArt = require(Client.CosmeticArt)
local Palette = require(Client.Palette)
local PixelArt = require(Client.PixelArt)
local PowerFx = require(Client.PowerFx)
local ShopState = require(Client.ShopState)

local FRAME_SECONDS = 0.3 -- animated flags and tokens: one frame this long
local THEME_PREVIEW_FACTOR = 8 -- a theme's shop preview is the map at 1/8 resolution (Earth 128×64)

type Animated = { label: ImageLabel, frames: { EditableImage } }

local Cosmetics = {}

local images: { [string]: EditableImage | false } = {} -- painted images by key (false = EditableImage unavailable)
local animated: { Animated } = {}
local listeners: { () -> () } = {}
local byNation: { [number]: Types.NationCosmetics } = {}
local clock = 0
local frameIndex = 0

local function packed(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local indexedList: { Types.NationCosmetics }? = nil -- the snapshot list byNation was built from

-- Index the snapshot's list by nation. Snapshot.apply replaces the list when it changes, so a new list = rebuild.
local function index()
	local snap = ClientState.snapshot()
	local list = if snap then snap.cosmetics else nil
	if list ~= indexedList then
		indexedList = list
		byNation = {}
		for _, c in list or {} do
			byNation[c.nation] = c
		end
	end
end

local function changed()
	for _, fn in listeners do
		task.spawn(fn)
	end
end

-- A nation's cosmetics (the defaults for bots and unknown nations).
function Cosmetics.of(nationId: number): Types.NationCosmetics
	index()
	return byNation[nationId] or Shop.defaultCosmetics(nationId)
end

-- The art name of a catalogue item ("" if unknown).
function Cosmetics.art(itemId: string): string
	local item = Catalogue.item(itemId)
	return if item then item.art else ""
end

-- Which power-effect item a nation shows for a Primordial power ("" = the default look).
function Cosmetics.powerEffect(nationId: number, power: string): string
	return Cosmetics.of(nationId).powerFx[power] or ""
end

-- An icon for each map theme's look (shop tab, draft credit line).
Cosmetics.THEME_ICONS = { classic = "🗺", night = "🌙", winter = "❄", autumn = "🍂" } :: { [string]: string }

-- The PixelArt look of a theme item ("" for the classic look or anything unknown).
function Cosmetics.themeLook(themeId: string): string
	local item = Catalogue.item(themeId)
	if item == nil or item.slot ~= "Theme" or item.art == "classic" then
		return ""
	end
	return item.art
end

-- Has this player opted out of themes ("always show the classic map")?
function Cosmetics.classicOnly(): boolean
	local view = ShopState.view()
	return view ~= nil and view.defaultTheme == true
end

-- The look this match's map is painted in: the theme vote's winner, unless you opted out.
function Cosmetics.matchTheme(): string
	local snap = ClientState.snapshot()
	if snap == nil or Cosmetics.classicOnly() then
		return ""
	end
	return Cosmetics.themeLook(snap.theme or "")
end

-- The look of the theme you have equipped (your vote cards show it), unless you opted out.
function Cosmetics.myTheme(): string
	local view = ShopState.view()
	if view == nil or Cosmetics.classicOnly() then
		return ""
	end
	return Cosmetics.themeLook(view.equipped.Theme or "")
end

-- Called when any nation's cosmetics change (and on every new match).
function Cosmetics.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

-- An EditableImage with these RGBA pixels, painted once per key and shared by every label that shows it.
local function image(key: string, paint: () -> (buffer, number, number)): EditableImage?
	local cached = images[key]
	if cached ~= nil then
		return if cached then cached else nil
	end
	local pixels, w, h = paint()
	local ok, result = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
	end)
	if not ok or result == nil then
		images[key] = false
		return nil
	end
	local editable = result :: EditableImage
	editable:WritePixelsBuffer(Vector2.zero, Vector2.new(w, h), pixels)
	images[key] = editable
	return editable
end

local function colours(colorIndex: number): (number, number)
	return packed(Palette.nation(colorIndex)), packed(Palette.border(colorIndex))
end

-- An ImageLabel for painted frames (animated when there are several), or a plain coloured Frame when the device
-- can't make EditableImages.
local function pixelLabel(parent: Instance, frames: { EditableImage? }, size: UDim2, fallback: Color3): GuiObject
	local first = frames[1]
	if first == nil then
		local f = Instance.new("Frame")
		f.Size = size
		f.BackgroundColor3 = fallback
		f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end
	local label = Instance.new("ImageLabel")
	label.Size = size
	label.BackgroundTransparency = 1
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageContent = Content.fromObject(first)
	label.Parent = parent
	if #frames > 1 then
		local list = {}
		for _, f in frames do
			if f then
				table.insert(list, f)
			end
		end
		table.insert(animated, { label = label, frames = list })
	end
	return label
end

-- A nation's flag (catalogue item id) in its colour.
function Cosmetics.flagLabel(parent: Instance, flagId: string, colorIndex: number, size: UDim2): GuiObject
	local design = Cosmetics.art(flagId)
	local nation, border = colours(colorIndex)
	local count = if CosmeticArt.ANIMATED_FLAGS[design] then CosmeticArt.FLAG_FRAMES else 1
	local frames: { EditableImage? } = {}
	for f = 0, count - 1 do
		frames[f + 1] = image(string.format("flag:%s:%d:%d", design, colorIndex, f), function()
			return CosmeticArt.flag(design, nation, border, f)
		end)
	end
	local label = pixelLabel(parent, frames, size, Palette.nation(colorIndex))
	label.Name = "Flag"
	return label
end

-- An army token sprite (catalogue item id) in a nation's colour.
function Cosmetics.tokenLabel(parent: Instance, tokenId: string, colorIndex: number, size: UDim2): GuiObject
	local skin = Cosmetics.art(tokenId)
	local nation, border = colours(colorIndex)
	local frames: { EditableImage? } = {}
	for f = 0, CosmeticArt.tokenFrames(skin) - 1 do
		frames[f + 1] = image(string.format("token:%s:%d:%d", skin, colorIndex, f), function()
			return CosmeticArt.token(skin, nation, border, f)
		end)
	end
	local label = pixelLabel(parent, frames, size, Palette.nation(colorIndex))
	label.Name = "TokenSkin"
	label:SetAttribute("Skin", skin)
	return label
end

-- A nation's army on the map (docs/DESIGN.md "Map rendering"): its equipped token skin, or, with the default token,
-- a little soldier of its race (CosmeticArt.SOLDIERS). nil means the plain square: a race without a soldier, or a
-- device that can't paint one.
function Cosmetics.armyLabel(
	parent: Instance,
	nationId: number,
	race: string,
	colorIndex: number,
	size: UDim2
): GuiObject?
	local token = Cosmetics.of(nationId).token
	if token ~= Catalogue.DEFAULTS.Token then
		return Cosmetics.tokenLabel(parent, token, colorIndex, size)
	end
	if CosmeticArt.SOLDIERS[race] == nil then
		return nil
	end
	local nation, border = colours(colorIndex)
	local frame = image(string.format("soldier:%s:%d", race, colorIndex), function()
		return CosmeticArt.soldier(race, nation, border)
	end)
	if frame == nil then
		return nil
	end
	local label = pixelLabel(parent, { frame }, size, Palette.nation(colorIndex))
	label.Name = "TokenSkin"
	label:SetAttribute("Soldier", race)
	return label
end

-- A nation's fleet on the map (docs/DESIGN.md "Map rendering"): the map's ship (MapDef.ship, CosmeticArt.SHIPS) in
-- its colours. nil when the device can't paint one (the token is a plain square then).
function Cosmetics.shipLabel(parent: Instance, ship: string, colorIndex: number, size: UDim2): GuiObject?
	local nation, border = colours(colorIndex)
	local frame = image(string.format("ship:%s:%d", ship, colorIndex), function()
		return CosmeticArt.ship(ship, nation, border)
	end)
	if frame == nil then
		return nil
	end
	local label = pixelLabel(parent, { frame }, size, Palette.nation(colorIndex))
	label.Name = "Ship"
	label:SetAttribute("Ship", ship)
	return label
end

-- A patch of map in a border style and shade set (catalogue art names), for the shop.
function Cosmetics.swatchLabel(
	parent: Instance,
	borderArt: string,
	shadesArt: string,
	colorIndex: number,
	size: UDim2
): GuiObject
	local nation, border = colours(colorIndex)
	local frame = image(string.format("swatch:%s:%s:%d", borderArt, shadesArt, colorIndex), function()
		return CosmeticArt.swatch(borderArt, shadesArt, nation, border)
	end)
	return pixelLabel(parent, { frame }, size, Palette.nation(colorIndex))
end

-- A power-effect item's preview: the effect mid-animation over a patch of grass (PowerFx.preview).
function Cosmetics.effectLabel(parent: Instance, itemId: string, size: UDim2): GuiObject
	local item = Catalogue.item(itemId)
	local power = if item and item.power then item.power else ""
	local art = if item then item.art else ""
	local frame = image("fx:" .. power .. ":" .. art, function()
		return PowerFx.preview(power, art)
	end)
	local label = pixelLabel(parent, { frame }, size, Palette.fx.gold)
	label.Name = "EffectPreview"
	return label
end

-- A theme item's preview: the current map (Earth before the first match) painted small in that theme, with every
-- nation's start land in its colour, so you can see the colours stay readable.
function Cosmetics.themeLabel(parent: Instance, themeId: string, size: UDim2): GuiObject
	local current = ClientState.map()
	local map = current or Maps.get("earth")
	local look = Cosmetics.themeLook(themeId)
	local frame = image("theme:" .. map.id .. ":" .. look, function()
		local grid = MapGrid.downsample(MapGrid.decode(map), THEME_PREVIEW_FACTOR)
		local art = PixelArt.new(map, grid, nil, look)
		local owners: { [number]: number } = {}
		for _, p in map.provinces do
			owners[p.id] = p.startOwner or 0
		end
		local colors: { [number]: number } = {}
		local borders: { [number]: number } = {}
		for _, n in map.nations do
			colors[n.slot] = packed(Palette.nation(n.colorIndex))
			borders[n.slot] = packed(Palette.border(n.colorIndex))
		end
		PixelArt.setOwners(art, owners, colors, borders)
		return art.pixels, art.width, art.height
	end)
	local label = pixelLabel(parent, { frame }, size, Palette.background[map.theme] or Palette.background.earth)
	label.Name = "ThemePreview"
	return label
end

-- The outline colour of a nameplate frame item, or nil for none.
function Cosmetics.frameColor(frameId: string): Color3?
	local c = CosmeticArt.FRAME_COLORS[Cosmetics.art(frameId)]
	if c == nil then
		return nil
	end
	return Color3.fromRGB(bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255))
end

function Cosmetics.init()
	ClientState.onReset(function()
		changed()
	end)
	ClientState.onDelta(function(delta)
		if delta.cosmetics then
			changed()
		end
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		if clock < FRAME_SECONDS then
			return
		end
		clock = 0
		frameIndex += 1
		local kept = {}
		for _, a in animated do
			if a.label.Parent ~= nil then
				a.label.ImageContent = Content.fromObject(a.frames[(frameIndex % #a.frames) + 1])
				table.insert(kept, a)
			end
		end
		animated = kept
	end)
end

return Cosmetics
