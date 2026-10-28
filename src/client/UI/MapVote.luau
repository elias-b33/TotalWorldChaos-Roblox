--!strict
-- The map vote in the Lobby (docs/MAPS.md "Task: Map vote"): one big card per map with a pixel-art thumbnail,
-- its title, a one-line pitch and the votes so far. Tap a card to choose it, tap it again to vote.
-- A server locked to one map shows just that card. Full screen, above everything else.
-- Theme vote (docs/MONETIZATION.md 3.2): your thumbnails are painted in the map theme you have equipped, and the
-- hint says you bring it; the map that wins is painted in the theme most of its voters bring.

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local MapGrid = require(Shared.MapGrid)
local Maps = require(Shared.Maps)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local Palette = require(Client.Palette)
local PixelArt = require(Client.PixelArt)
local ShopState = require(Client.ShopState)
local Widgets = require(script.Parent.Widgets)

local THUMB_FACTOR = 4 -- thumbnails are the map grid at 1/4 resolution (Earth 256×128)
local THUMB_HEIGHT = 120
local CARD_WIDTH_MAX = 260
local CARD_HEIGHT = 224
local CARD_GAP = 12
local PAINT_SLICE = 0.008 -- seconds of painting per frame
local SELECTED = Color3.fromRGB(255, 230, 90)

-- One short line each (docs/MAPS.md): it has to fit a phone card at 14 px.
local PITCH: { [string]: string } = {
	earth = "The real world, crowded",
	eldmoor = "Kingdoms ring a rich heart",
	skyshards = "Floating isles, fast and fair",
}
local ICON: { [string]: string } = { earth = "🌍", eldmoor = "🏰", skyshards = "☁" }

type Card = { button: ImageButton, stroke: UIStroke, votes: TextLabel, status: TextLabel }

local MapVote = {}

local gui: ScreenGui
local root: Frame
local title: TextLabel
local hint: TextLabel
local timer: TextLabel
local row: Frame
local cards: { [string]: Card } = {}
local cardsFor = "" -- the map list the cards were built for
local selected: string? = nil
local thumbs: { [string]: EditableImage | false } = {} -- painted thumbnails by map id and theme (false = not possible)

local function packed(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

-- Paint a map's thumbnail (start territories in nation colours) into an EditableImage. nil if the device or the
-- game settings don't allow EditableImage: the card then stays a plain coloured card.
local function paintThumb(map: Types.MapDef, look: string): EditableImage?
	local grid = MapGrid.downsample(MapGrid.decode(map), THUMB_FACTOR)
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(grid.width, grid.height) })
	end)
	if not ok or image == nil then
		return nil
	end
	local last = os.clock()
	local art = PixelArt.new(map, grid, function()
		if os.clock() - last > PAINT_SLICE then
			task.wait()
			last = os.clock()
		end
	end, look)
	local owners: { [number]: number } = {}
	for _, p in map.provinces do
		owners[p.id] = p.startOwner or 0
	end
	local colors: { [number]: number } = {}
	for _, n in map.nations do
		colors[n.slot] = packed(Palette.nation(n.colorIndex))
	end
	PixelArt.setOwners(art, owners, colors)
	image:WritePixelsBuffer(Vector2.zero, Vector2.new(art.width, art.height), art.pixels)
	return image
end

local function showThumb(holder: Frame, map: Types.MapDef)
	local function attach(image: EditableImage)
		local label = Instance.new("ImageLabel")
		label.Name = "Thumb"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromScale(0.5, 0)
		label.Size = UDim2.fromOffset(math.floor(THUMB_HEIGHT * map.imageSize.x / map.imageSize.y), THUMB_HEIGHT)
		label.BackgroundTransparency = 1
		label.ResampleMode = Enum.ResamplerMode.Pixelated
		label.ImageContent = Content.fromObject(image)
		label.Parent = holder
	end
	local look = Cosmetics.myTheme()
	local key = map.id .. ":" .. look
	local cached = thumbs[key]
	if cached then
		attach(cached)
	elseif cached == nil then
		task.spawn(function()
			local image = paintThumb(map, look)
			thumbs[key] = image or false
			if image and holder.Parent then
				attach(image)
			end
		end)
	end
end

local function buildCard(mapId: string, index: number, count: number): Card
	local map = Maps.get(mapId)
	local button = Instance.new("ImageButton")
	button.Name = "Card_" .. mapId
	button.AutoButtonColor = false
	button.BackgroundColor3 = Widgets.PANEL
	button.Position = UDim2.new((index - 1) / count, CARD_GAP // 2, 0, 0)
	button.Size = UDim2.new(1 / count, -CARD_GAP, 0, CARD_HEIGHT)
	button.Parent = row
	Widgets.corner(button, 12)
	Widgets.padding(button, 8)
	Widgets.list(button, false, 6)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(CARD_WIDTH_MAX, CARD_HEIGHT)
	limit.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = SELECTED
	stroke.Enabled = false
	stroke.Parent = button

	local holder = Instance.new("Frame")
	holder.Name = "ThumbHolder"
	holder.Size = UDim2.new(1, 0, 0, THUMB_HEIGHT)
	local background = Palette.background[map.theme] or Palette.background.earth
	local themed = PixelArt.themeColor(Cosmetics.myTheme(), packed(background), false, map.theme == "sky")
	holder.BackgroundColor3 =
		Color3.fromRGB(bit32.rshift(themed, 16), bit32.band(bit32.rshift(themed, 8), 255), bit32.band(themed, 255))
	holder.BorderSizePixel = 0
	holder.LayoutOrder = 1
	holder.Parent = button
	Widgets.corner(holder, 8)
	showThumb(holder, map)

	Widgets.label(button, (ICON[mapId] or "🗺") .. " " .. map.title, 18, 24).LayoutOrder = 2
	local pitch = Widgets.label(button, PITCH[mapId] or "", 14, 20)
	pitch.Font = Enum.Font.Gotham
	pitch.TextColor3 = Color3.fromRGB(200, 204, 220)
	pitch.LayoutOrder = 3
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, 24)
	footer.LayoutOrder = 4
	footer.Parent = button
	local votes = Widgets.label(footer, "", 16, 24)
	votes.Size = UDim2.fromScale(0.35, 1)
	local status = Widgets.label(footer, "", 14, 24)
	status.Position = UDim2.fromScale(0.35, 0)
	status.Size = UDim2.fromScale(0.65, 1)
	status.TextXAlignment = Enum.TextXAlignment.Right

	button.Activated:Connect(function()
		local view = LobbyState.view()
		if view == nil or view.locked or view.phase ~= "Lobby" then
			return
		end
		if selected == mapId then
			Intents.vote(mapId)
			selected = nil
		else
			selected = mapId
		end
		MapVote.render()
	end)
	return { button = button, stroke = stroke, votes = votes, status = status }
end

-- The name of the theme you bring to the vote, or nil for the classic look.
local function myThemeName(): string?
	local view = ShopState.view()
	local item = if view and Cosmetics.myTheme() ~= "" then Catalogue.item(view.equipped.Theme or "") else nil
	return if item then item.name else nil
end

function MapVote.render()
	local view = LobbyState.view()
	if view == nil or view.phase ~= "Lobby" then
		root.Visible = false
		selected = nil
		return
	end
	local key = table.concat(view.maps, ",") .. "|" .. Cosmetics.myTheme() -- a new theme repaints the thumbnails
	if key ~= cardsFor then
		Widgets.clear(row)
		cards = {}
		cardsFor = key
		for i, id in view.maps do
			cards[id] = buildCard(id, i, #view.maps)
		end
	end
	title.Text = if view.locked then "🔒 This server plays one map" else "🗳 Vote for the map"
	hint.Text = if view.locked then "The draft starts soon" else "Tap a card, tap again to vote"
	local bring = myThemeName()
	if bring then
		hint.Text ..= "  ·  🎨 You bring the " .. bring .. " theme"
	end
	local mine = LobbyState.myVote()
	for i, id in view.maps do
		local card = cards[id]
		if card == nil then
			continue
		end
		card.votes.Text = if view.locked then "" else "🗳 " .. tostring(view.counts[i] or 0)
		if view.locked then
			card.status.Text = "🔒 Locked"
		elseif mine == id then
			card.status.Text = "✅ Your vote"
		elseif selected == id then
			card.status.Text = "👆 Tap again"
		else
			card.status.Text = ""
		end
		card.stroke.Enabled = selected == id or mine == id
		card.stroke.Color = if selected == id then SELECTED else Widgets.GOOD
	end
	root.Visible = true
end

local function updateTimer()
	if root.Visible then
		local s = LobbyState.secondsLeft()
		timer.Text = string.format("⏳ %d:%02d", s // 60, s % 60)
	end
end

function MapVote.init()
	gui = Widgets.screen("MapVote", 20)
	root = Instance.new("Frame")
	root.Name = "Root"
	root.Active = true -- nothing behind the vote can be tapped
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui

	title = Widgets.label(root, "", 22, 32)
	title.Position = UDim2.fromOffset(16, 8)
	title.Size = UDim2.new(1, -160, 0, 32)
	hint = Widgets.label(root, "", 14, 20)
	hint.Font = Enum.Font.Gotham
	hint.TextColor3 = Color3.fromRGB(200, 204, 220)
	hint.Position = UDim2.fromOffset(16, 40)
	hint.Size = UDim2.new(1, -160, 0, 20)
	timer = Widgets.label(root, "", 22, 32)
	timer.AnchorPoint = Vector2.new(1, 0)
	timer.Position = UDim2.new(1, -16, 0, 8)
	timer.Size = UDim2.fromOffset(130, 32)
	timer.TextXAlignment = Enum.TextXAlignment.Right

	row = Instance.new("Frame")
	row.Name = "Cards"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(12, 70)
	row.Size = UDim2.new(1, -24, 1, -82)
	row.Parent = root

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	LobbyState.onChange(function()
		MapVote.render()
	end)
	ShopState.onChange(function()
		MapVote.render() -- you equipped another theme: your thumbnails follow
	end)
	RunService.Heartbeat:Connect(updateTimer)
end

return MapVote
