--!strict
-- What is drawn on the 2D map (docs/DESIGN.md "Map rendering"): the pixel-art image painted by PixelArt
-- (terrain, owners, the selected province), straits, province names, army tokens gliding between province
-- centres, battle and siege markers, the coalition leader's crown and route lines. Everything sits on MapView's
-- canvas, placed in map pixels. The terrain is painted in the match's map theme (Cosmetics.matchTheme).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local CatchUp = require(Shared.Sim.CatchUp)
local Config = require(Shared.Config)
local MapGrid = require(Shared.MapGrid)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)
local LabelLayout = require(script.Parent.LabelLayout)
local Cosmetics = require(script.Parent.Cosmetics)
local MapView = require(script.Parent.MapView)
local Palette = require(script.Parent.Palette)
local PixelArt = require(script.Parent.PixelArt)
local ShopState = require(script.Parent.ShopState)

local NAME_MIN_PIXELS = 70 -- a province's name shows once the province is this wide on screen
local NAME_RELAYOUT = 0.04 -- names are laid out again when the zoom changes by this share
local NAME_OFFSET = 6 -- screen pixels between a province's centre and the top of its name
local NAME_HEIGHT, PIPS_HEIGHT = 18, 16
local DETAIL_ZOOM = 0.9 -- garrisons and development pips show from this share of the region zoom inwards
local TEXT_SIZE = 14 -- the smallest text on the map (docs/DESIGN.md "UI and controls")
local TOKEN_SIZE = 14 -- army token, screen pixels
local TOKEN_SKIN_SIZE = 18 -- a token skin's 12×12 sprite, screen pixels
local TOKEN_PICK = 20 -- a tap this close to a token's centre (screen pixels) picks the army
local TOKEN_SPACING = 4 -- map pixels between tokens standing in one province
local TOKEN_SMOOTHING = 6 -- higher = tokens catch up with their target faster
local TOKEN_EDGE = Color3.fromRGB(20, 20, 28) -- army token outline (selected: yellow; Rebels: Palette.rebelEdge)
local DOT_SPACING = 4 -- map pixels between the dots of a route or strait
local PIXELATED_FROM = 1.5 -- zoom from which map pixels are drawn hard-edged (smooth below, so thin lines don't flicker)
local PAINT_SLICE = 0.008 -- seconds of painting per frame while a map is painted for the first time
-- The close-up detail (PixelArt.paintDetail): a second image laid over the part of the map in view when zoomed in.
local DETAIL_FROM = 4 -- screen pixels per map pixel from which it shows (more if the screen is too big for it)
local DETAIL_OFF = 0.85 -- it is freed again below this share of that zoom
local DETAIL_WIDTH = 1024 -- its image's width; the height follows the screen's shape (at most 1024)
local DETAIL_COVER = 0.8 -- the view fills at most this share of it, so a short pan stays inside it
local DETAIL_SETTLE = 0.15 -- seconds the view keeps still before the close-up is repainted around it
local DETAIL_SLICE = 0.006 -- seconds of close-up painting per frame
local FLAG_WIDTH, FLAG_HEIGHT = 24, 18 -- a capital's 16×12 flag, screen pixels
local EMOTE_SIZE = 26 -- capital emote icon, screen pixels
local VICTORY_SIZE = 32 -- victory animation over a winner's capital
local VICTORY_FRAME_SECONDS = 0.4

local MapRenderer = {}

type Token = {
	frame: Frame,
	stroke: UIStroke,
	label: TextLabel,
	pos: Vector2,
	target: Vector2,
	neutral: boolean, -- a neutral garrison: hidden below the region zoom
	rebel: boolean, -- Rebels: owner 0 too, but always shown, with a 🏴
	owner: number,
	province: number,
	skinned: boolean, -- drawn with a token skin sprite (no square outline unless selected)
}

local grid: MapGrid.Grid? = nil
local art: PixelArt.Art? = nil
local image: EditableImage? = nil
local imageLabel: ImageLabel? = nil
local size = Vector2.new(1024, 512)
local generation = 0 -- bumps with every new map, so a painting finished for an old one is ignored
local grids: { [string]: MapGrid.Grid } = {} -- decoded grids by map id
local arts: { [string]: PixelArt.Art } = {} -- painted maps by map id and resolution (one theme each), reused
local painting: { map: Types.MapDef, grid: MapGrid.Grid }? = nil -- what the current map is painted from
local warned = false
local closeUp: PixelArt.Detail? = nil -- the close-up, its image and the label showing it (nil when zoomed out)
local detailImage: EditableImage? = nil
local detailLabel: ImageLabel? = nil
local detailAllowed = false -- full resolution only, and not after the device refused the image
local detailJob = 0 -- bumps with every close-up paint; a paint that is no longer the latest stops
local detailBusy = false
local viewKey = "" -- where the view was last frame, and how long it has stayed there
local viewStill = 0
local layers: { [string]: Frame } = {}
local widths: { [number]: number } = {} -- each province's width in map pixels
local namesLaidOut = { zoom = -1, detail = false }
local labels: { [number]: { frame: Frame, pips: TextLabel, width: number } } = {} -- width: of the name, on screen
local markers: { [number]: TextLabel } = {}
local effects: { [number]: TextLabel } = {}
local crowns: { [number]: TextLabel } = {}
local tokens: { [number]: Token } = {}
local flags: { [number]: { frame: Frame, key: string } } = {}
local victories: { { label: TextLabel, frames: { string } } } = {}
local victoryClock = 0
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

-- A province's rough radius in map pixels (from its area).
function MapRenderer.radiusOf(provinceId: number): number
	local map = ClientState.map()
	local g = grid
	if map == nil or g == nil then
		return 0
	end
	return math.sqrt(map.provinces[provinceId].area / (g.scale * g.scale) / math.pi)
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

-- Names of provinces wide enough on screen, minus any that would overlap a bigger province's name.
local function layoutNames(z: number, detail: boolean)
	local last = namesLaidOut
	if last.detail == detail and last.zoom > 0 and math.abs(z / last.zoom - 1) < NAME_RELAYOUT then
		return
	end
	namesLaidOut = { zoom = z, detail = detail }
	local boxes: { LabelLayout.Box } = {}
	for id, label in labels do
		local width = widths[id] or 0
		if width * z >= NAME_MIN_PIXELS then
			local c = MapRenderer.centerOf(id) * z
			table.insert(boxes, {
				id = id,
				x = c.X - label.width / 2,
				y = c.Y + NAME_OFFSET,
				w = label.width,
				h = if detail then NAME_HEIGHT + PIPS_HEIGHT else NAME_HEIGHT,
				priority = width,
			})
		end
	end
	local shown = LabelLayout.place(boxes)
	for id, label in labels do
		label.frame.Visible = shown[id] == true
		label.pips.Visible = detail
	end
end

-- Everything that depends on the zoom: names, garrisons, and how the pixels are sampled.
-- An army's size label shows from the region zoom inwards; zoomed out, only on your own armies, Rebels and the
-- selected army, so a busy map isn't a pile of numbers.
local function sizeShown(id: number, token: Token, detail: boolean): boolean
	local me = ClientState.myNation()
	return detail or token.rebel or id == selectedArmy or (me ~= 0 and token.owner == me)
end

local function onZoom(z: number)
	local detail = detailVisible(z)
	layoutNames(z, detail)
	for id, token in tokens do
		if token.neutral then
			token.frame.Visible = detail
		end
		token.label.Visible = sizeShown(id, token, detail)
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

-- Send part of a painting to its image: only the changed rectangle (x0, y0, x1, y1), unless most of it changed.
local function upload(editable: EditableImage, pixels: buffer, width: number, height: number, d: { number })
	local x0, y0, x1, y1 = d[1], d[2], d[3], d[4]
	local w, h = x1 - x0 + 1, y1 - y0 + 1
	if w * h * 2 >= width * height then
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(width, height), pixels)
		return
	end
	local rect = buffer.create(w * h * 4)
	for row = 0, h - 1 do
		buffer.copy(rect, row * w * 4, pixels, ((y0 + row) * width + x0) * 4, w * 4)
	end
	editable:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), rect)
end

local function viewportSize(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(800, 600)
end

-- The close-up's image size for this screen, and the zoom it shows from (where the screen fits well inside it).
local function detailSize(vp: Vector2): (number, number)
	local f = PixelArt.DETAIL.factor
	local h = math.ceil(DETAIL_WIDTH * vp.Y / math.max(vp.X, 1) / f) * f
	return DETAIL_WIDTH, math.clamp(h, 16 * f, 1024)
end

local function detailZoom(vp: Vector2): number
	local w, h = detailSize(vp)
	local f = PixelArt.DETAIL.factor
	return math.max(DETAIL_FROM, vp.X / (w / f * DETAIL_COVER), vp.Y / (h / f * DETAIL_COVER))
end

-- Free the close-up and its image (zoomed out, a new map), so phones get the memory back right away.
local function freeDetail()
	detailJob += 1
	detailBusy = false
	closeUp = nil
	if detailLabel then
		detailLabel:Destroy()
		detailLabel = nil
	end
	if detailImage then
		detailImage:Destroy()
		detailImage = nil
	end
end

-- Paint the close-up around a map point, a few milliseconds per frame (the old one stays up meanwhile), then show it.
local function startDetail(a: PixelArt.Art, vp: Vector2, centre: Vector2)
	local w, h = detailSize(vp)
	local d = closeUp
	if d == nil or d.width ~= w or d.height ~= h then
		freeDetail()
		local ok, result = pcall(function()
			return AssetService:CreateEditableImage({ Size = Vector2.new(w, h) })
		end)
		local imageLayer = layers.Image
		if not ok or result == nil or imageLayer == nil then
			detailAllowed = false -- the device can't spare it: the map stays as it is
			return
		end
		detailImage = result
		local label = Instance.new("ImageLabel")
		label.Name = "Detail"
		label.BackgroundTransparency = 1
		label.ResampleMode = Enum.ResamplerMode.Pixelated
		label.ZIndex = 2
		label.Visible = false
		label.ImageContent = Content.fromObject(result)
		label.Parent = imageLayer
		detailLabel = label
		d = PixelArt.newDetail(w, h)
		closeUp = d
	end
	local target = d :: PixelArt.Detail
	local x0, y0 = PixelArt.detailOrigin(a, target, centre.X, centre.Y)
	detailJob += 1
	local job = detailJob
	detailBusy = true
	task.spawn(function()
		local last = os.clock()
		local ok = pcall(PixelArt.paintDetail, a, target, x0, y0, function()
			if detailJob ~= job then
				error("a newer close-up replaced this one")
			end
			if os.clock() - last > DETAIL_SLICE then
				task.wait()
				last = os.clock()
			end
		end)
		if detailJob ~= job then
			return
		end
		detailBusy = false
		local editable, label = detailImage, detailLabel
		if not ok or art ~= a or closeUp ~= target or editable == nil or label == nil then
			return
		end
		PixelArt.takeDetailDirty(target)
		editable:WritePixelsBuffer(Vector2.zero, Vector2.new(target.width, target.height), target.pixels)
		label.Position = UDim2.fromScale(target.x0 / size.X, target.y0 / size.Y)
		label.Size = UDim2.fromScale(target.cols / size.X, target.rows / size.Y)
		label.Visible = true
	end)
end

-- Once a frame: show the close-up when zoomed in far enough, repaint it when the view has settled somewhere it
-- doesn't cover, catch it up with ownership and selection changes, and free it when zoomed out.
local function stepDetail(dt: number)
	local a = art
	if a == nil or not detailAllowed or imageLabel == nil then
		if detailImage then
			freeDetail()
		end
		return
	end
	local vp = viewportSize()
	local z = MapView.zoom()
	if z < detailZoom(vp) * (if detailImage then DETAIL_OFF else 1) then
		if detailImage then
			freeDetail()
		end
		return
	end
	local p0, p1 = MapView.toMap(Vector2.zero), MapView.toMap(vp)
	local key = string.format("%d,%d,%d", math.floor(p0.X), math.floor(p0.Y), math.floor(z * 50))
	if key ~= viewKey then
		viewKey, viewStill = key, 0
	else
		viewStill += dt
	end
	local d, label, editable = closeUp, detailLabel, detailImage
	if d and label and editable and not detailBusy then
		if d.painted ~= a then
			label.Visible = false -- painted from an older painting (another theme)
		elseif
			math.max(p0.X, 0) >= d.x0
			and math.max(p0.Y, 0) >= d.y0
			and math.min(p1.X, a.width) <= d.x0 + d.cols
			and math.min(p1.Y, a.height) <= d.y0 + d.rows
		then
			if PixelArt.syncDetail(a, d) then
				local rect = PixelArt.takeDetailDirty(d)
				if rect then
					upload(editable, d.pixels, d.width, d.height, rect)
				end
			end
			return
		end
	end
	if not detailBusy and viewStill >= DETAIL_SETTLE then
		startDetail(a, vp, (p0 + p1) / 2)
	end
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
	local styles: { [number]: PixelArt.NationStyle } = {}
	for _, nation in snapshot.nations do
		colors[nation.id] = packed(Palette.nation(nation.colorIndex))
		borders[nation.id] = packed(Palette.border(nation.colorIndex))
		-- border style and shade set (cosmetics): always shades of the nation's own colours
		local c = Cosmetics.of(nation.id)
		local border, shades = Cosmetics.art(c.border), Cosmetics.art(c.shades)
		if border ~= "solid" or shades ~= "default" then
			styles[nation.id] = { border = border, shades = shades }
		end
	end
	PixelArt.setStyles(a, styles)
	PixelArt.setOwners(a, owners, colors, borders)
end

-- Each nation's flag (its equipped cosmetic) on a little pole left of its capital (armies stand at the centre),
-- while it holds the capital.
local function refreshFlags()
	local snapshot = ClientState.snapshot()
	local flagLayer = layers.Flags
	if snapshot == nil or flagLayer == nil then
		return
	end
	local owners: { [number]: number } = {}
	for _, record in snapshot.provinces do
		owners[record.id] = record.owner
	end
	local alive: { [number]: boolean } = {}
	for _, nation in snapshot.nations do
		local show = not nation.eliminated and owners[nation.capital] == nation.id
		local flagId = Cosmetics.of(nation.id).flag
		local key = flagId .. ":" .. nation.colorIndex
		local entry = flags[nation.id]
		if entry and (not show or entry.key ~= key) then
			entry.frame:Destroy()
			flags[nation.id] = nil
			entry = nil
		end
		if show and entry == nil then
			local holder = Instance.new("Frame")
			holder.Name = "Flag" .. nation.id
			holder.AnchorPoint = Vector2.new(1, 1)
			holder.Position = at(MapRenderer.centerOf(nation.capital)) + UDim2.fromOffset(-10, 8)
			holder.Size = UDim2.fromOffset(FLAG_WIDTH + 3, FLAG_HEIGHT + 8)
			holder.BackgroundTransparency = 1
			holder.Parent = flagLayer
			local pole = Instance.new("Frame")
			pole.Name = "Pole"
			pole.Size = UDim2.new(0, 2, 1, 0)
			pole.BackgroundColor3 = Color3.fromRGB(40, 32, 26)
			pole.BorderSizePixel = 0
			pole.Parent = holder
			local flag =
				Cosmetics.flagLabel(holder, flagId, nation.colorIndex, UDim2.fromOffset(FLAG_WIDTH, FLAG_HEIGHT))
			flag.Position = UDim2.fromOffset(3, 0)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(20, 20, 28)
			stroke.Thickness = 1
			stroke.Parent = flag
			flags[nation.id] = { frame = holder, key = key }
		end
		alive[nation.id] = true
	end
	for id, entry in flags do
		if not alive[id] then
			entry.frame:Destroy()
			flags[id] = nil
		end
	end
end

-- A capital emote (MatchEvent "Emote": a = nation, b = emote index, province = capital) for a few seconds.
local function showEmote(e: Types.MatchEvent)
	local item = Catalogue.ofSlot("Emote")[e.b]
	local emoteLayer = layers.Emotes
	if item == nil or emoteLayer == nil or e.province == 0 then
		return
	end
	local label = textLabel(emoteLayer, item.art)
	label.Name = "Emote" .. e.a
	label.TextSize = EMOTE_SIZE
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = at(MapRenderer.centerOf(e.province)) + UDim2.fromOffset(0, -58)
	label.Size = UDim2.fromOffset(EMOTE_SIZE + 12, EMOTE_SIZE + 8)
	label.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	label.BackgroundTransparency = 0.25
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = label
	local myGeneration = generation
	task.delay(Config.Shop.EmoteShowSeconds, function()
		if generation == myGeneration then
			label:Destroy()
		end
	end)
end

-- The winners' victory animations over their capitals while Results shows (frames of the item's art, cycled).
local function refreshVictory()
	local snapshot = ClientState.snapshot()
	local victoryLayer = layers.Emotes
	for _, v in victories do
		v.label:Destroy()
	end
	victories = {}
	local result = if snapshot then snapshot.result else nil
	if result == nil or victoryLayer == nil then
		return
	end
	for _, nationId in result.winners do
		local nation = ClientState.nation(nationId)
		if nation then
			local frames = string.split(Cosmetics.art(Cosmetics.of(nationId).victory), " ")
			local label = textLabel(victoryLayer, frames[1] or "🏆")
			label.Name = "Victory" .. nationId
			label.TextSize = VICTORY_SIZE
			label.AnchorPoint = Vector2.new(0.5, 1)
			label.Position = at(MapRenderer.centerOf(nation.capital)) + UDim2.fromOffset(0, -32)
			label.Size = UDim2.fromOffset(VICTORY_SIZE + 16, VICTORY_SIZE + 8)
			table.insert(victories, { label = label, frames = frames })
		end
	end
end

-- The painted map in the match's theme: reused from an earlier match on this map if it has that theme, or painted
-- now, a few milliseconds per frame (the old painting stays up meanwhile). Only one theme per map is kept.
local function paintMap()
	local job = painting
	if job == nil then
		return
	end
	local map, g = job.map, job.grid
	local look = Cosmetics.matchTheme()
	local background = Palette.background[map.theme] or Palette.background.earth
	local canvas = MapView.canvas()
	local back = if canvas then canvas.Parent else nil
	if back and back:IsA("Frame") then
		local themed = PixelArt.themeColor(look, packed(background), false, map.theme == "sky")
		back.BackgroundColor3 =
			Color3.fromRGB(bit32.rshift(themed, 16), bit32.band(bit32.rshift(themed, 8), 255), bit32.band(themed, 255))
	end
	local key = map.id .. ":" .. g.width
	local cached = arts[key]
	if cached and cached.look == look then
		art = cached
		PixelArt.select(cached, nil)
		PixelArt.invalidate(cached)
		return
	end
	local myGeneration = generation
	task.spawn(function()
		local last = os.clock()
		local painted = PixelArt.new(map, g, function()
			if os.clock() - last > PAINT_SLICE then
				task.wait()
				last = os.clock()
			end
		end, look)
		arts[key] = painted
		if generation == myGeneration and Cosmetics.matchTheme() == look then
			local old = art
			art = painted
			if old then
				PixelArt.select(painted, old.selected)
			end
			paintOwners()
			PixelArt.invalidate(painted)
		end
	end)
end

local function build(map: Types.MapDef)
	generation += 1
	freeDetail()
	labels = {}
	markers = {}
	effects = {}
	crowns = {}
	tokens = {}
	flags = {}
	victories = {}
	layers = {}
	widths = {}
	namesLaidOut = { zoom = -1, detail = false }
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
	detailAllowed = g == full -- no close-up on a device that needs the half-size map
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

	painting = { map = map, grid = g }
	art = nil
	paintMap()

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
			frame.Position = at(MapRenderer.centerOf(def.id)) + UDim2.fromOffset(0, NAME_OFFSET)
			frame.Size = UDim2.fromOffset(150, NAME_HEIGHT + PIPS_HEIGHT)
			frame.BackgroundTransparency = 1
			frame.Parent = labelLayer
			local name = textLabel(frame, def.name)
			name.Size = UDim2.new(1, 0, 0, NAME_HEIGHT)
			local dev = textLabel(frame, pips(if record then record.development else def.development))
			dev.Position = UDim2.fromOffset(0, NAME_HEIGHT)
			dev.Size = UDim2.new(1, 0, 0, PIPS_HEIGHT)
			local width =
				math.max(LabelLayout.textWidth(def.name, TEXT_SIZE), LabelLayout.textWidth(dev.Text, TEXT_SIZE))
			labels[def.id] = { frame = frame, pips = dev, width = width }
		end
	end
	layer("Flags", canvas)
	layer("Tokens", canvas)
	layer("Markers", canvas)
	layer("Crowns", canvas)
	layer("Emotes", canvas)
	layer("Effects", canvas).ZIndex = 2 -- Effects' particles, over everything else
	onZoom(MapView.zoom())
end

-- A layer of the current map's canvas by name (nil before the first map), the map's size in map pixels, and a
-- province's rough width in map pixels: for Effects, which draws on the "Effects" layer.
function MapRenderer.layer(name: string): Frame?
	return layers[name]
end

function MapRenderer.mapSize(): Vector2
	return size
end

function MapRenderer.provinceWidth(provinceId: number): number
	return widths[provinceId] or 0
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
	local rebel = army.rebel
	local neutral = army.owner == 0 and not rebel
	local px = if neutral then TOKEN_SIZE - 4 else TOKEN_SIZE
	local frame = Instance.new("Frame")
	frame.Name = "Army" .. army.id
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = at(target)
	frame.Size = UDim2.fromOffset(px, px)
	frame.BackgroundColor3 = if rebel then Palette.rebel else nationColor(army.owner)
	frame.BorderSizePixel = 0
	local stroke = Instance.new("UIStroke")
	stroke.Color = if rebel then Palette.rebelEdge else TOKEN_EDGE
	stroke.Thickness = 2
	stroke.Parent = frame
	-- an army token skin (cosmetic): the nation's sprite instead of the plain square
	local nation = if neutral then nil else ClientState.nation(army.owner)
	local skin = if nation then Cosmetics.of(army.owner).token else Catalogue.DEFAULTS.Token
	local skinned = nation ~= nil and skin ~= Catalogue.DEFAULTS.Token
	if nation and skinned then
		frame.Size = UDim2.fromOffset(TOKEN_SKIN_SIZE, TOKEN_SKIN_SIZE)
		frame.BackgroundTransparency = 1
		stroke.Enabled = false
		Cosmetics.tokenLabel(frame, skin, nation.colorIndex, UDim2.fromScale(1, 1))
	end
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
		rebel = rebel,
		owner = army.owner,
		province = army.location,
		skinned = skinned,
	}
	local detail = detailVisible(MapView.zoom())
	frame.Visible = not neutral or detail
	label.Visible = sizeShown(army.id, token, detail)
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
		local icon = if t.rebel
			then "🏴 "
			elseif t.neutral then "🛡 "
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
	local previous = selectedArmy
	if previous and tokens[previous] then
		local old = tokens[previous]
		old.stroke.Color = if old.rebel then Palette.rebelEdge else TOKEN_EDGE
		old.stroke.Thickness = 2
		old.stroke.Enabled = not old.skinned
	end
	selectedArmy = armyId
	local detail = detailVisible(MapView.zoom())
	if previous and tokens[previous] then
		tokens[previous].label.Visible = sizeShown(previous, tokens[previous], detail)
	end
	local token = if armyId then tokens[armyId] else nil
	if token and armyId then
		token.stroke.Color = Color3.fromRGB(255, 230, 90)
		token.stroke.Thickness = 3
		token.stroke.Enabled = true
		token.label.Visible = true
	end
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
			refreshFlags()
			refreshVictory()
		end
	end)
	ClientState.onDelta(function(delta)
		for _, record in delta.provinces do
			refreshProvince(record)
		end
		if #delta.provinces > 0 or #delta.nations > 0 then
			paintOwners()
			refreshCrowns()
			refreshFlags()
		end
		if #delta.armies > 0 or #delta.removedArmies > 0 then
			refreshArmies()
		end
		if delta.result then
			refreshVictory()
		end
		for _, e in delta.events do
			if e.kind == "Emote" then
				showEmote(e)
			end
		end
	end)
	-- the opt-out ("always show the classic map") was switched: repaint the terrain
	ShopState.onChange(function()
		local a = art
		if painting and a and a.look ~= Cosmetics.matchTheme() then
			paintMap()
		end
	end)
	-- someone equipped something: flags, borders, shades and tokens follow
	Cosmetics.onChange(function()
		if layers.Tokens == nil then
			return
		end
		paintOwners()
		refreshFlags()
		for id, token in tokens do
			token.frame:Destroy()
			tokens[id] = nil
		end
		local selected = selectedArmy
		selectedArmy = nil
		refreshArmies()
		MapRenderer.selectArmy(selected)
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
		-- victory animations cycle through their frames
		victoryClock += dt
		if victoryClock >= VICTORY_FRAME_SECONDS and #victories > 0 then
			victoryClock = 0
			for _, v in victories do
				local i = (table.find(v.frames, v.label.Text) or 0) % #v.frames + 1
				v.label.Text = v.frames[i]
			end
		end
		-- the pixel art goes to the screen at most once a frame
		local editable, painted = image, art
		if editable and painted and imageLabel then
			local d = PixelArt.takeDirty(painted)
			if d then
				upload(editable, painted.pixels, painted.width, painted.height, d)
			end
		end
		stepDetail(dt)
	end)
end

return MapRenderer
