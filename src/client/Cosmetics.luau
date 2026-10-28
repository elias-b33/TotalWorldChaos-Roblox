--!strict
-- Every nation's equipped cosmetics, as replicated next to the match (Snapshot.cosmetics), and the GUI pieces that
-- show them: pixel-art flags and army tokens (EditableImages painted by CosmeticArt, cached and shared), border and
-- shade swatches, nameplate frame colours. Bots and unknown nations show the defaults.
--
-- Hook for Primordial-power effects: Cosmetics.powerEffect(nationId, power) says which effect variant a nation has
-- equipped ("" = the default look). Effects keep the default's area, timing and sound cue.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Shop = require(Shared.Sim.Shop)
local Types = require(Shared.Types)

local Client = script.Parent
local ClientState = require(Client.ClientState)
local CosmeticArt = require(Client.CosmeticArt)
local Palette = require(Client.Palette)

local FRAME_SECONDS = 0.3 -- animated flags and tokens: one frame this long

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
