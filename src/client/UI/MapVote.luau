--!strict
-- The map vote in the Lobby (docs/MAPS.md "Task: Map vote"): one big card per map with a pixel-art thumbnail,
-- its title, a one-line pitch and the votes so far. Tap a card to choose it, tap it again to vote.
-- A server locked to one map shows just that card. Full screen, above everything else.
-- A server's first match has a first pick instead (docs/DESIGN.md "Match structure"): the same cards, but only the
-- first player who chose Play online picks (tap a card, tap again); everyone else sees who is picking.
-- Theme vote (docs/MONETIZATION.md 3.2): your thumbnails are painted in the map theme you have equipped, and the
-- hint says you bring it; the map that wins is painted in the theme most of its voters bring.
-- The kit (docs/UI_DIRECTION.md 7.14): each card a raised plate with its thumbnail in a recessed well, the name in
-- outlined Fredoka One, the pitch dim, the votes in a chip; the card you tapped and the one you voted for are
-- outlined in gold (with "Tap again" or a "Your vote" tag). The title is plain hero text, the timer a counter.
-- The screen covers Roblox's top-bar row (Widgets.coverScreen), so the cards have the whole height on a phone; the
-- title and its hint start right of Roblox's buttons in that row.

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
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme

local THUMB_FACTOR = 4 -- thumbnails are the map grid at 1/4 resolution (Earth 256×128)
local THUMB_HEIGHT = 120
local THUMB_INSET = 4 -- the thumbnail sits this far inside its well
local CARD_WIDTH_MAX = 260
local CARD_HEIGHT = 224
local CARD_GAP = 12
local PAINT_SLICE = 0.008 -- seconds of painting per frame
local TIMER_WIDTH = 92
local EDGE = 16 -- the title's and the timer's margins (more where Roblox's buttons sit in the top-bar row)
local TITLE_ROOM = 144 -- the timer's room right of the title

-- One short line each (docs/MAPS.md): it has to fit a phone card at 14 px.
local PITCH: { [string]: string } = {
	earth = "The real world, crowded",
	eldmoor = "Kingdoms ring a rich heart",
	skyshards = "Floating isles, fast and fair",
}
local ICON: { [string]: string } = { earth = "globe", eldmoor = "castle", skyshards = "sparkles" }

type Card = { button: ImageButton, votes: TextLabel, status: TextLabel }

local MapVote = {}

local gui: ScreenGui
local root: Frame
local title: TextLabel
local titleIcon: GuiObject
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
		label.Size = UDim2.fromScale(1, 1)
		label.ScaleType = Enum.ScaleType.Fit -- the whole map inside the card on any phone, keeping its shape
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

-- Fill `holder` with a map's thumbnail in your theme: its sea colour at once, the painted map when it's ready (or
-- just the colour without EditableImage). The start menu's Singleplayer cards use it too.
function MapVote.thumbnail(holder: Frame, mapId: string)
	local map = Maps.get(mapId)
	local background = Palette.background[map.theme] or Palette.background.earth
	local themed = PixelArt.themeColor(Cosmetics.myTheme(), packed(background), false, map.theme == "sky")
	holder.BackgroundColor3 =
		Color3.fromRGB(bit32.rshift(themed, 16), bit32.band(bit32.rshift(themed, 8), 255), bit32.band(themed, 255))
	showThumb(holder, map)
end

local function buildCard(mapId: string, index: number, count: number): Card
	local map = Maps.get(mapId)
	local button = Instance.new("ImageButton")
	button.Name = "Card_" .. mapId
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Position = UDim2.new((index - 1) / count, CARD_GAP // 2, 0, 0)
	button.Size = UDim2.new(1 / count, -CARD_GAP, 0, CARD_HEIGHT)
	button.Parent = row
	Widgets.material(button, "raised")
	Widgets.padding(button, Theme.space.m)
	Widgets.list(button, false, Theme.space.s)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(CARD_WIDTH_MAX, CARD_HEIGHT)
	limit.Parent = button

	-- the thumbnail in a recessed well: the map's sea colour fills the well inside its rim
	local well = Instance.new("ImageLabel")
	well.Name = "ThumbWell"
	well.Size = UDim2.new(1, 0, 0, THUMB_HEIGHT)
	well.BorderSizePixel = 0
	well.LayoutOrder = 1
	well.Parent = button
	Widgets.material(well, "well")
	Widgets.padding(well, THUMB_INSET)
	local holder = Instance.new("Frame")
	holder.Name = "ThumbHolder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BorderSizePixel = 0
	holder.Parent = well
	MapVote.thumbnail(holder, mapId)

	local name = Widgets.title(button, map.title, Theme.text.title, 24)
	name.TextColor3 = Theme.color.text
	name.LayoutOrder = 2
	Widgets.leadIcon(name, ICON[mapId] or "map", Theme.size.icon)
	local pitch = Widgets.hint(button, PITCH[mapId] or "", Theme.text.small, 20)
	pitch.LayoutOrder = 3
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, 26)
	footer.LayoutOrder = 4
	footer.Parent = button
	local votes = Widgets.chip(footer, "ballot", "", 64, 26)
	votes.Name = "Votes"
	-- "Your vote" (a tag), "Tap again" or "Locked" at the right
	local status = Widgets.tag(footer, "check", "", 26)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(1, 0)
	status.Position = UDim2.fromScale(1, 0)
	status.TextWrapped = false

	button.Activated:Connect(function()
		local view = LobbyState.view()
		if view == nil or view.locked or view.phase ~= "Lobby" then
			return
		end
		if view.first and view.chooser ~= Players.LocalPlayer.UserId then
			return -- someone else picks the map
		end
		if selected == mapId then
			Intents.vote(mapId)
			selected = nil
		else
			selected = mapId
		end
		MapVote.render()
	end)
	return { button = button, votes = votes, status = status }
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
	local picking = view.first and view.chooser == Players.LocalPlayer.UserId
	if view.first then
		title.Text = if picking or view.chooser == 0 then "Pick the map" else view.chooserName .. " is picking the map"
		hint.Text = if picking
			then "Tap a card, tap again to play"
			elseif view.chooser == 0 then "The first to tap Play online picks it"
			else "The match starts once it's picked"
	else
		title.Text = if view.locked then "This server plays one map" else "Vote for the map"
		hint.Text = if view.locked then "The draft starts soon" else "Tap a card, tap again to vote"
	end
	Icons.set(titleIcon, if view.first then "map" elseif view.locked then "lock" else "ballot")
	timer.Visible = not view.first or view.chooser ~= 0
	local bring = myThemeName()
	if bring and (picking or not view.first) then
		hint.Text ..= "  ·  You bring the " .. bring .. " theme"
	end
	local mine = LobbyState.myVote()
	for i, id in view.maps do
		local card = cards[id]
		if card == nil then
			continue
		end
		card.votes.Text = tostring(view.counts[i] or 0)
		card.votes.Visible = not view.locked and not view.first
		if view.locked then
			Widgets.setIconText(card.status, "🔒 Locked", "lock")
		elseif mine == id then
			Widgets.setIconText(card.status, if view.first then "✅ Your pick" else "✅ Your vote", "check")
		elseif selected == id then
			Widgets.setIconText(card.status, "👆 Tap again", "arrow")
		else
			card.status.Text = ""
		end
		card.status.Visible = card.status.Text ~= ""
		card.status.TextColor3 = if mine == id then Theme.color.gold else Theme.color.text
		Widgets.setChosen(card.button, selected == id or mine == id)
	end
	root.Visible = true
end

local function updateTimer()
	if root.Visible then
		local s = LobbyState.secondsLeft()
		timer.Text = string.format("%d:%02d", s // 60, s % 60)
	end
end

-- The title, its hint and the timer sit in Roblox's top-bar row: clear of Roblox's buttons.
local function placeTop()
	local left, right = Widgets.topbarMargins(gui, EDGE, EDGE)
	title.Position = UDim2.fromOffset(left, 8)
	title.Size = UDim2.new(1, -(left + right + TITLE_ROOM - EDGE), 0, 34)
	hint.Position = UDim2.fromOffset(left, 44)
	hint.Size = UDim2.new(1, -(left + right + TITLE_ROOM - EDGE), 0, 20)
	timer.Position = UDim2.new(1, -right, 0, 12)
end

function MapVote.init()
	gui = Widgets.screen("MapVote", 20)
	Widgets.coverScreen(gui)
	root = Instance.new("Frame")
	root.Name = "Root"
	root.Active = true -- nothing behind the vote can be tapped
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Theme.color.slate900
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = gui
	Widgets.bevel(root, true) -- a gentle light from the top

	-- plain hero text (no plate), outlined in ink, the pixel icon before it
	title = Widgets.title(root, "", Theme.text.hero, 34)
	title.TextColor3 = Theme.color.text
	titleIcon = Widgets.leadIcon(title, "ballot", Theme.icon.medium)
	hint = Widgets.hint(root, "", Theme.text.small, 20)
	timer = Widgets.counter(root, "hourglass", "", TIMER_WIDTH)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(1, 0)
	placeTop()
	HudLayout.onChange(placeTop) -- Roblox's row changed, or the screen did

	row = Instance.new("Frame")
	row.Name = "Cards"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(12, 70)
	row.Size = UDim2.new(1, -24, 1, -82)
	row.Parent = root

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
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
