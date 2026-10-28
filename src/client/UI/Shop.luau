--!strict
-- The shop (docs/MONETIZATION.md 3, 10), phone first: a cart button opens a full-screen panel with tabs (offers, the
-- rotating shop, one per cosmetic slot, purchase history), five item cards per page with a preview, the Robux and
-- Glory prices and the owned / equipped state. Also the starter-pack offer (at most once per session, after the 2nd
-- match, never during a match, no timer). Built from the UI kit (docs/DESIGN.md "UI style"); the panel's contents
-- are built when it opens and dropped when it closes.
--
-- Rules for minors (section 10): every price shows its currency icon (the Robux glyph, the Glory medal), Robux
-- prices are read live from MarketplaceService (the Config list price only while a product id is unset), bundles
-- show the real sum of their pieces, no random items, no countdowns, no prompts during a match (the server refuses
-- them). Power effects show a pixel preview of the effect, map themes a small map painted in the theme; the Themes
-- tab also holds the opt-out ("always show me the classic map").
-- The rotating shop (section 3.8, Sim.ShopRotation): the Today tab shows the 4 daily and 2 weekly slots with the
-- time until they change; a rotating item outside its days says it is back within 60 days. Season-pass rewards only
-- show once owned; the Offers tab links to the season pass screen (UI.Season).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Config = require(Shared.Config)
local Season = require(Shared.Sim.Season)
local Shop = require(Shared.Sim.Shop)
local ShopRotation = require(Shared.Sim.ShopRotation)
local SimAds = require(Shared.Sim.Ads)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local ProfileState = require(Client.ProfileState)
local SeasonState = require(Client.SeasonState)
local ShopState = require(Client.ShopState)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local ROBUX = utf8.char(0xE002) -- Roblox's Robux icon in every Roblox font
local PER_PAGE = 5 -- item cards per page
local OFFERS_PER_PAGE = 3 -- offer cards are wider: what's inside is a list
local TODAY_COLUMNS = 6 -- 4 daily and 2 weekly slots
local HISTORY_PER_PAGE = 6
local BAR = Widgets.BUTTON_HEIGHT -- the header and the tab row
local GAP = 9 -- between item cards: five 152 px cards fill an 844 px phone's 796 (docs/UI_DIRECTION.md 7.12)
local OFFER_GAP = Theme.space.m
local TODAY_GAP = Theme.space.s
local TAB_GAP = Theme.space.xs
local FOOTER_HEIGHT = 18
-- the window: at most as big as on an 844 x 390 phone (a tablet shows the same cards larger, by its DeviceScale),
-- and what its padding, header, tabs and footer leave for the cards (the padding under the title plate and at the
-- bottom, two 44 px rows, the footer and four gaps, the header's included)
local MAX_WINDOW = Vector2.new(828, 366)
local CHROME = Vector2.new(2 * Theme.frame.pad.side, 160)
-- a card (docs/UI_DIRECTION.md 7.12): its rarity tag rides on its top edge, the lit display well under it, the
-- name, a detail line when there is room, and the prices at the bottom
local TAG_ROOM = 10 -- above the cards: their tags and title plates ride on the top edge
local TAG_RIDE = 10 -- a rarity tag's top above its card
local RARITY_TAG_HEIGHT = 26
local CARD_SIDE = 12 -- the display well and the prices inside the card's frame
-- the well's top, the gap under it, the space over the bottom area and under it: under a tag on a full card, tighter
-- on the Today tab's six (no tag: the well starts inside the frame's top band)
local NORMAL = { top = 22, gap = 4, spacing = 6, bottom = 14 }
local COMPACT = { top = 14, gap = 2, spacing = 4, bottom = 12 }
local WELL_RIM = 3 -- the glow inside the well's rim
local WELL_INSET = 4 -- round the preview inside the well
local MIN_WELL = 24
local PREVIEW = 48 -- a preview's height in a full-size well
local NAME_HEIGHT = 18
local DETAIL_HEIGHT = 16
local PRICE_PAD = 6 -- a price button's sides
local PRICE_GAP = 4 -- between two prices side by side, or stacked
local TAG_HEIGHT = 32
local TITLE_HEIGHT = 22 -- a bundle card's name
local LINE = 17 -- a 14 px line
local HISTORY_ROW = 32
local DATE_WIDTH = 104
local PRICE_WIDTH = 96
local TEST_WIDTH = 150
local GLORY_WIDTH = 96 -- the Glory counter: "12,345" and its medal
local SECONDS_PER_DAY = 86400
local DEFAULT_COLOR = 1 -- previews use your nation's colour, or red before you have one
local SEASON_PASS = "Season Pass"

type Tab = { id: string, icon: string, label: string }
local TABS: { Tab } = {
	{ id = "Offers", icon = "gift", label = "Offers" },
	{ id = "Today", icon = "reroll", label = "Today" },
	{ id = "Flag", icon = "flag", label = "Flags" },
	{ id = "Border", icon = "border", label = "Borders" },
	{ id = "Shades", icon = "palette", label = "Shades" },
	{ id = "Token", icon = "sword", label = "Tokens" },
	{ id = "Emote", icon = "smile", label = "Emotes" },
	{ id = "Victory", icon = "trophy", label = "Victory" },
	{ id = "Frame", icon = "frame", label = "Frames" },
	{ id = "PowerFx", icon = "meteor", label = "Powers" },
	{ id = "Theme", icon = "map", label = "Themes" },
	{ id = "History", icon = "scroll", label = "History" },
}
-- the selected tab is twice as wide (its icon and name), the others show their icon
local TAB_UNITS = #TABS + 1

local SLOT_NAMES: { [string]: string } = {
	Flag = "Flag",
	Token = "Token",
	Border = "Border",
	Shades = "Shades",
	Frame = "Frame",
	Emote = "Emote",
	Victory = "Victory",
	PowerFx = "Effect",
	Theme = "Theme",
}
local SLOT_ICONS: { [string]: string } = {}
for _, t in TABS do
	SLOT_ICONS[t.id] = t.icon
end

-- The open panel's pieces (nil while the shop is closed: its contents are dropped).
type Refs = {
	glory: TextLabel,
	vip: TextLabel,
	test: TextLabel,
	pager: Frame,
	page: TextLabel,
	tabs: Frame,
	content: Frame,
	footer: TextLabel,
}

local ShopUI = {}

local toast: (string) -> () = function(_text: string) end
local gui: ScreenGui
local openButton: TextButton
local panel: Frame
local panelSize = MAX_WINDOW -- the window's size in phone px (placePanel)
local offerPanel: Frame
local offerDim: Frame

-- The cards' row: the window less its padding, header, tabs and footer (phone px).
local function contentSize(): Vector2
	return panelSize - CHROME
end
local ui: Refs? = nil
local tab = "Offers"
local page = 1
local livePrices: { [string]: number } = {} -- live Robux prices by item or offer id
local asked: { [string]: boolean } = {}
local rotationAt = os.clock() -- when the rotating shop's view arrived (its *Left times count from then)
local openSeason: (() -> ())? = nil -- UI.Season's opener (set by UI.Season, which requires this module)
local RETURN_DAYS = Config.ShopRotation.ReturnDays -- every rotating item is back within this many days

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

local function myColor(): number
	local me = ClientState.nation(ClientState.myNation())
	return if me then me.colorIndex else DEFAULT_COLOR
end

local render: () -> () = function() end -- set below

-- The price to show: MarketplaceService's live price once the product exists (managed and regional pricing),
-- else the list price from Config.
local function robuxPrice(id: string, listPrice: number): number
	local productId = Catalogue.productId(id)
	if productId == 0 then
		return listPrice
	end
	if livePrices[id] then
		return livePrices[id]
	end
	if not asked[id] then
		asked[id] = true
		task.spawn(function()
			local ok, info = pcall(function()
				local kind = if id == "vip" then Enum.InfoType.GamePass else Enum.InfoType.Product
				return MarketplaceService:GetProductInfoAsync(productId, kind)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				livePrices[id] = info.PriceInRobux
				render()
			end
		end)
	end
	return listPrice
end

local function robuxOpen(): boolean
	local view = ShopState.view()
	return view ~= nil and view.robuxOpen
end

local function buyRobux(id: string)
	if not robuxOpen() then
		toast("🛒 Robux purchases open after the match")
		return
	end
	Intents.buy(id, "Robux")
end

-- A text line centred in its parent, cut with … when too long.
local function centred(
	parent: Instance,
	text: string,
	size: number,
	height: number,
	color: Color3?,
	wrapped: boolean?
): TextLabel
	local l = Widgets.label(parent, text, size, height)
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.TextWrapped = wrapped == true
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if color then
		l.TextColor3 = color
	end
	return l
end

-- A price's width on its button, estimated for Fredoka One 14 (TextService isn't available everywhere this runs),
-- erring a little wide: it decides whether a card's two prices fit side by side.
local function priceWidth(text: string, icon: boolean): number
	local w = 2 * PRICE_PAD + (if icon then Theme.size.icon + 2 else 0)
	for _, code in utf8.codes(text) do
		local c = utf8.char(code)
		w += if c == ROBUX then 15 elseif string.match(c, "%d") then 8 elseif c == "," or c == " " then 4 else 9
	end
	return w
end

-- A price button (docs/UI_DIRECTION.md 7.12): 44 px tall, as wide as its currency icon and number in Fredoka One
-- 14. Robux on emerald (the Robux glyph in the text), Glory on gold (the medal).
local function priceButton(
	parent: Instance,
	icon: string?,
	text: string,
	color: Color3,
	onPress: () -> (),
	name: string
): TextButton
	local b = Widgets.button(parent, text, 0, color, onPress)
	b.Name = name
	b.AutomaticSize = Enum.AutomaticSize.X
	b.TextSize = Theme.text.small
	b.TextWrapped = false
	Widgets.padding(b, PRICE_PAD, 0)
	if icon then
		Widgets.leadIcon(b, icon, Theme.size.icon, 2)
	end
	b:SetAttribute("Estimate", priceWidth(text, icon ~= nil))
	return b
end

-- The bottom of a card (prices, Equip, a tag): two prices side by side when both fit (centred, 4 px apart), else
-- everything stacked and centred, Robux on top. Returns the height it takes.
local function arrange(area: Frame, items: { GuiObject }, width: number): number
	if #items == 2 then
		local a, b = items[1]:GetAttribute("Estimate"), items[2]:GetAttribute("Estimate")
		if type(a) == "number" and type(b) == "number" and a + PRICE_GAP + b <= width then
			local row = Widgets.list(area, true, PRICE_GAP)
			row.HorizontalAlignment = Enum.HorizontalAlignment.Center
			row.VerticalAlignment = Enum.VerticalAlignment.Top
			for i, item in items do
				item.LayoutOrder = i
			end
			return Widgets.BUTTON_HEIGHT
		end
	end
	local y = 0
	for i, item in items do
		item.AnchorPoint = Vector2.new(0.5, 0)
		item.Position = UDim2.new(0.5, 0, 0, y)
		y += item.Size.Y.Offset + (if i < #items then PRICE_GAP else 0)
	end
	return y
end

-- A card's bottom area, `height` px tall over the card's bottom border, as wide as its display well.
local function buttonArea(card: Frame, height: number, compact: boolean?): Frame
	local area = Instance.new("Frame")
	area.Name = "Buttons"
	area.BackgroundTransparency = 1
	area.AnchorPoint = Vector2.new(0, 1)
	area.Position = UDim2.new(0, CARD_SIDE, 1, -(if compact then COMPACT else NORMAL).bottom)
	area.Size = UDim2.new(1, -2 * CARD_SIDE, 0, height)
	area.Parent = card
	return area
end

-- A card in the grid: `material` is its frame (a rarity's colour, "plate" for free and earned things, "brass" for
-- VIP and offers), `size` its cell. Children are placed on the card's whole box (no padding).
local function newCard(parent: Instance, name: string, order: number, material: string | Color3, size: Vector2): Frame
	local card = Widgets.card(parent)
	card.Name = name
	card.LayoutOrder = order
	card.AutomaticSize = Enum.AutomaticSize.None -- the grid's cell is its size
	card.Size = UDim2.fromOffset(size.X, size.Y)
	Widgets.material(card, material)
	Widgets.padding(card, 0)
	return card
end

-- The rarity tag on a card's top edge (docs/UI_DIRECTION.md 7.12): a small plate in the rarity's colour with the
-- rarity in capitals, dark text on the light ones. Named "Rarity".
local function rarityTag(card: Frame, text: string, color: Color3)
	local t = Instance.new("TextLabel")
	t.Name = "Rarity"
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0, -TAG_RIDE)
	t.Size = UDim2.fromOffset(0, RARITY_TAG_HEIGHT)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.BackgroundColor3 = color
	t.BorderSizePixel = 0
	t.FontFace = Theme.font.label
	t.TextSize = Theme.text.small
	t.TextColor3 = if color == Theme.rarity.Common
			or color == Theme.rarity.Legendary
			or color == Theme.color.gold
		then Theme.color.textDark
		else Theme.color.text
	t.Text = string.upper(text)
	t.ZIndex = 3
	t.Parent = card
	Widgets.corner(t, Theme.radius.s)
	Widgets.stroke(t)
	local pad = Widgets.padding(t, 10, 0)
	if Widgets.skin(t, "titlePlate", color) then
		pad.PaddingBottom = UDim.new(0, 4) -- the caption sits on the plate's face, above its darker base rows
	end
end

-- The little picture on a card, at most `h` px tall and `maxWidth` wide: flags 4:3, swatches 3:2, tokens square,
-- map themes 7:4, power effects 4:3, a nameplate frame round your name, an emote's first frame.
local function preview(parent: Instance, item: Types.CatalogueItem, h: number, maxWidth: number)
	local color = myColor()
	local function size(aspect: number): UDim2
		local height = math.min(h, math.floor(maxWidth / aspect))
		local width = math.floor(height * aspect)
		return UDim2.fromOffset(width - width % 2, height - height % 2)
	end
	local thing: GuiObject
	if item.slot == "Flag" then
		thing = Cosmetics.flagLabel(parent, item.id, color, size(4 / 3))
	elseif item.slot == "Border" then
		thing = Cosmetics.swatchLabel(parent, item.art, "default", color, size(1.5))
	elseif item.slot == "Shades" then
		thing = Cosmetics.swatchLabel(parent, "solid", item.art, color, size(1.5))
	elseif item.slot == "Token" then
		thing = Cosmetics.tokenLabel(parent, item.id, color, size(1))
	elseif item.slot == "PowerFx" then
		thing = Cosmetics.effectLabel(parent, item.id, size(4 / 3))
	elseif item.slot == "Theme" then
		thing = Cosmetics.themeLabel(parent, item.id, size(1.75))
	elseif item.slot == "Frame" then
		local l = centred(parent, Players.LocalPlayer.Name, Theme.text.small, 28)
		l.Size = UDim2.new(1, -2 * Theme.space.s, 0, 28)
		l.BackgroundColor3 = Theme.color.slate700
		l.BackgroundTransparency = 0
		local frameColor = Cosmetics.frameColor(item.id)
		if frameColor then
			l.BackgroundColor3 = frameColor
			l.BackgroundTransparency = 0.8
			Widgets.stroke(l, frameColor)
		end
		Widgets.corner(l, Theme.radius.m)
		thing = l
	else -- emotes and victory animations are emoji over a capital: their first frame
		thing = centred(parent, string.split(item.art, " ")[1], math.floor(h * 0.7), h)
	end
	thing.AnchorPoint = Vector2.new(0.5, 0.5)
	thing.Position = UDim2.fromScale(0.5, 0.5)
	thing.ZIndex = 2
end

-- The lit display well at the top of a card: a recessed well with a glow of the card's colour falling from its
-- top. Named "Preview".
local function displayWell(card: Frame, top: number, height: number, glow: Color3?): ImageLabel
	local well = Instance.new("ImageLabel")
	well.Name = "Preview"
	well.BorderSizePixel = 0
	well.Position = UDim2.fromOffset(CARD_SIDE, top)
	well.Size = UDim2.new(1, -2 * CARD_SIDE, 0, height)
	well.Parent = card
	Widgets.material(well, "well")
	if glow then
		local g = Instance.new("Frame")
		g.Name = "Glow"
		g.BorderSizePixel = 0
		g.BackgroundColor3 = glow
		g.Position = UDim2.fromOffset(WELL_RIM, WELL_RIM)
		g.Size = UDim2.new(1, -2 * WELL_RIM, 1, -2 * WELL_RIM)
		g.Parent = well
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new(0.55, 1)
		fade.Parent = g
	end
	return well
end

-- Where a page's cards put their wells, names and detail lines, so they line up across the row: under the
-- tallest bottom area on the page; the well (from `top`) takes what is left (the picture shrinks on a small phone).
type Geometry = { wellTop: number, wellHeight: number, nameTop: number, detail: boolean }

local function geometry(size: Vector2, area: number, detail: boolean, compact: boolean): Geometry
	local m = if compact then COMPACT else NORMAL
	local nameTop = size.Y - m.bottom - area - m.spacing - NAME_HEIGHT - (if detail then DETAIL_HEIGHT else 0)
	if detail and nameTop - m.gap - m.top < MIN_WELL + DETAIL_HEIGHT then
		detail = false -- no room: the picture matters more
		nameTop += DETAIL_HEIGHT
	end
	local wellHeight = math.max(nameTop - m.gap - m.top, MIN_WELL)
	return { wellTop = m.top, wellHeight = wellHeight, nameTop = nameTop, detail = detail }
end

-- A card built but for its well and name: its bottom area's height, whether it has a detail line, and what places
-- the rest once the page's geometry is known.
type Pending = { area: number, detail: boolean, finish: (Geometry) -> () }

-- Finish a page of cards alike once they are all built; `compact` cards (the Today tab's six) have no tag on their
-- edge and tighter spacing.
local function finishCards(pending: { Pending }, size: Vector2, compact: boolean?)
	local area, detail = 0, false
	for _, p in pending do
		area = math.max(area, p.area)
		detail = detail or p.detail
	end
	local g = geometry(size, area, detail, compact == true)
	for _, p in pending do
		p.finish(g)
	end
end

-- A card's name (Fredoka One 16, outlined) and its detail line (dim) under it.
local function cardName(card: Frame, g: Geometry, name: string, detail: string?)
	local label = centred(card, name, Theme.text.body + 1, NAME_HEIGHT)
	label.Name = "Name"
	label.FontFace = Theme.font.display
	label.Position = UDim2.fromOffset(Theme.space.m, g.nameTop)
	label.Size = UDim2.new(1, -2 * Theme.space.m, 0, NAME_HEIGHT)
	Widgets.textStroke(label)
	if detail and g.detail then
		local d = centred(card, detail, Theme.text.small, DETAIL_HEIGHT, Theme.color.textDim)
		d.Name = "Detail"
		d.FontFace = Theme.font.bodyLight
		d.Position = UDim2.fromOffset(Theme.space.m, g.nameTop + NAME_HEIGHT)
		d.Size = UDim2.new(1, -2 * Theme.space.m, 0, DETAIL_HEIGHT)
	end
end

-- The Robux price button (greyed out during a match: a tap explains why).
local function robuxButton(parent: Instance, id: string, listPrice: number): TextButton
	local b = priceButton(parent, nil, ROBUX .. " " .. formatNumber(robuxPrice(id, listPrice)), Widgets.GOOD, function()
		buyRobux(id)
	end, "BuyRobux")
	if not robuxOpen() then
		Widgets.setEnabled(b, false)
	end
	return b
end

-- Is this item or offer in the shop today? Core items always are; rotating ones in their slots (Sim.ShopRotation).
local function onSaleToday(id: string): boolean
	local view = ShopState.view()
	local rotation = if view then view.rotation else nil
	return rotation == nil or ShopRotation.onSale(id, rotation.day)
end

-- What a card says under its name beyond its rarity (the power an effect is for, "Any map", "Animated").
local function detailOf(item: Types.CatalogueItem): string?
	if item.power then
		return item.power
	elseif item.slot == "Theme" and not item.free then
		return "Any map"
	elseif item.animated then
		return "Animated"
	end
	return nil
end

-- An item card (docs/UI_DIRECTION.md 7.12): its rarity's frame and tag, the lit display well with the preview,
-- the name, and at the bottom its prices or what you can do with it (Equip, Get VIP) or a tag saying why not.
local function itemCard(
	item: Types.CatalogueItem,
	order: number,
	parent: Instance,
	size: Vector2,
	compact: boolean?
): Pending
	local rarity = Theme.rarity[item.rarity] or Theme.color.textDim
	local plain = item.free or item.earned
	local material: string | Color3 = if item.vipOnly then "brass" elseif plain then "plate" else rarity
	local card = newCard(parent, "Card_" .. item.id, order, material, size)
	-- six to a row (compact), the frame's colour and the glow say the rarity: a tag would cost the picture its room
	if not compact then
		if item.free then
			rarityTag(card, "Free", Theme.color.slate)
		elseif item.vipOnly then
			rarityTag(card, "VIP", Theme.color.gold)
		else
			rarityTag(card, item.rarity, rarity)
		end
	end
	if not plain and not item.vipOnly and item.rarity ~= "Common" then
		Widgets.glow(card, rarity) -- Rare and better
	end

	local area = buttonArea(card, 0, compact)
	local items: { GuiObject } = {}
	if ShopState.owns(item.id) then
		if item.slot == "Emote" then
			table.insert(items, Widgets.tag(area, "check", "Owned", TAG_HEIGHT))
		elseif ShopState.isEquipped(item) then
			local t = Widgets.tag(area, "check", "Equipped", TAG_HEIGHT)
			t.TextColor3 = Theme.color.gold
			table.insert(items, t)
		else
			table.insert(
				items,
				Widgets.fitButton(area, nil, "Equip", Widgets.GOOD, function()
					Intents.equip(item.id)
				end, "Equip")
			)
		end
	elseif item.earned then -- never sold: an achievement (the Trophies screen) or the weekly top 100
		if item.id == "frame_warlord" then
			table.insert(items, Widgets.tag(area, "war", "Top 100", TAG_HEIGHT))
		else
			table.insert(items, Widgets.tag(area, "trophy", "Trophy", TAG_HEIGHT))
		end
	elseif item.vipOnly then
		table.insert(
			items,
			Widgets.fitButton(area, "crown", "Get VIP", Widgets.BUTTON_OFF, function()
				tab, page = "Offers", 1
				render()
			end, "GetVip")
		)
	elseif item.season then
		table.insert(items, Widgets.tag(area, "ticket", "Season", TAG_HEIGHT))
	elseif not onSaleToday(item.id) then
		table.insert(items, Widgets.tag(area, "reroll", "Not today", TAG_HEIGHT))
		local back = centred(area, string.format("Back within\n%d days", RETURN_DAYS), Theme.text.small, 2 * LINE)
		back.Size = UDim2.new(1, 0, 0, 2 * LINE)
		back.TextWrapped = true
		back.TextColor3 = Theme.color.textDim
		back.FontFace = Theme.font.bodyLight
		table.insert(items, back)
	else
		if item.robux then
			table.insert(items, robuxButton(area, item.id, item.robux))
		end
		if item.glory then
			local summary = ProfileState.summary()
			local cost = item.glory
			local b = priceButton(area, "medal", formatNumber(cost), Widgets.GOLD, function()
				Intents.buy(item.id, "Glory")
			end, "BuyGlory")
			if summary == nil or summary.glory < cost then
				Widgets.setEnabled(b, false) -- still sends: the server says "Not enough Glory"
			end
			table.insert(items, b)
		end
	end
	local areaHeight = arrange(area, items, size.X - 2 * CARD_SIDE)
	area.Size = UDim2.new(1, -2 * CARD_SIDE, 0, areaHeight)

	local detail = if compact then nil else detailOf(item)
	return {
		area = areaHeight,
		detail = detail ~= nil,
		finish = function(g: Geometry)
			cardName(card, g, item.name, detail)
			local glow = if plain then nil elseif item.vipOnly then Theme.color.gold else rarity
			local well = displayWell(card, g.wellTop, g.wellHeight, glow)
			local h = math.min(PREVIEW, g.wellHeight - 2 * WELL_INSET)
			preview(well, item, h, size.X - 2 * (CARD_SIDE + WELL_INSET))
		end,
	}
end

-- A dim block of short lines (what's inside) from `top`, in two columns on a `wide` card with more than four, then
-- a gold note under it.
local function offerText(card: Frame, lines: { string }, note: string, top: number, wide: boolean?)
	local columns = if wide and #lines > 4 then 2 else 1
	local rows = math.ceil(#lines / columns)
	for c = 1, columns do
		local part = table.move(lines, (c - 1) * rows + 1, math.min(#lines, c * rows), 1, {})
		local list = Widgets.label(card, table.concat(part, "\n"), Theme.text.small, LINE * rows)
		list.Name = "Contents"
		list.FontFace = Theme.font.bodyLight
		list.TextColor3 = Theme.color.textDim
		list.TextYAlignment = Enum.TextYAlignment.Top
		list.TextTruncate = Enum.TextTruncate.AtEnd
		list.Size = UDim2.new(1 / columns, if columns > 1 then -Theme.space.xs else 0, 0, LINE * rows)
		list.Position = UDim2.new((c - 1) / columns, 0, 0, top)
	end
	local noteLines = #string.split(note, "\n")
	local n = Widgets.label(card, note, Theme.text.small, LINE * noteLines)
	n.Name = "Note"
	n.TextColor3 = Theme.color.gold
	n.TextYAlignment = Enum.TextYAlignment.Top
	n.Position = UDim2.fromOffset(0, top + Theme.space.xs + LINE * rows)
end

local function itemLine(id: string): string?
	local item = Catalogue.item(id)
	return if item then item.name .. " " .. (SLOT_NAMES[item.slot] or "") else nil
end

local OFFER_ICONS: { [string]: string } = { vip = "crown", starter = "gift" }

-- An offer card (VIP, the starter pack, the season pass): a brass card with its name on a title plate on the top
-- edge, what's inside as dim lines, a gold note, and one button at the bottom.
local function offerFrame(
	parent: Instance,
	name: string,
	order: number,
	size: Vector2,
	icon: string,
	title: string
): Frame
	local card = newCard(parent, name, order, "brass", size)
	local pad = Widgets.padding(card, Theme.frame.pad.side, 0)
	pad.PaddingBottom = UDim.new(0, Theme.frame.pad.bottom)
	Widgets.header(card, title, icon)
	return card
end

-- The button at the bottom of an offer card, centred.
local function offerButton(card: Frame, item: GuiObject)
	local area = Instance.new("Frame")
	area.Name = "Buttons"
	area.BackgroundTransparency = 1
	area.AnchorPoint = Vector2.new(0, 1)
	area.Position = UDim2.fromScale(0, 1)
	area.Size = UDim2.new(1, 0, 0, item.Size.Y.Offset)
	area.Parent = card
	item.Parent = area
	item.AnchorPoint = Vector2.new(0.5, 0)
	item.Position = UDim2.fromScale(0.5, 0)
end

local function offerCard(offer: Types.ShopOffer, order: number, parent: Instance, size: Vector2)
	local icon = OFFER_ICONS[offer.id] or Icons.fromEmoji(offer.icon) or "gift"
	local card = offerFrame(parent, "Card_" .. offer.id, order, size, icon, offer.name)
	Widgets.glow(card, Theme.color.gold)
	-- what's inside, one short line each (they must fit a phone card)
	local lines = {}
	if offer.kind == "Pass" then
		lines = {
			"VIP flag, border, token",
			"Gold frame, [VIP] chat tag",
			"+25% match XP and Glory",
			"Never changes a match",
		}
	else
		for _, id in offer.items do
			local line = itemLine(id)
			if line then
				table.insert(lines, line)
			end
		end
	end
	local note = if offer.kind == "Pass"
		then "Yours forever"
		else string.format("Bought separately: %s %s", ROBUX, formatNumber(Shop.bundleValue(offer.id, robuxPrice)))
	if offer.oncePerAccount and offer.kind == "Product" then
		note ..= "\nOne per account"
	end
	offerText(card, lines, note, 0, true)
	if ShopState.owns(offer.id) then
		offerButton(card, Widgets.tag(card, "check", "Owned", TAG_HEIGHT))
	else
		offerButton(card, robuxButton(card, offer.id, offer.robux))
	end
end

-- The Offers tab's season pass card: what the pass holds, and the way to its screen (bought there).
local function seasonCard(order: number, parent: Instance, size: Vector2)
	local view = SeasonState.view()
	if view == nil or view.id == "" then
		return
	end
	local card = offerFrame(parent, "Card_season_pass", order, size, "ticket", SEASON_PASS)
	-- what the premium track holds, counted from the season's reward list
	local items, glory = 0, 0
	local def = Season.def(view.id)
	if def then
		for tier = 1, #def.tiers do
			for _, r in Season.rewards(def, tier, "Premium") do
				items += if r.item then 1 else 0
				glory += r.glory or 0
			end
		end
	end
	offerText(card, {
		view.name,
		string.format("%d cosmetics, a title", items),
		string.format("%s Glory on the way", formatNumber(glory)),
		"Only this season",
	}, string.format("No tier skips\nBundle: pass + %d tiers", Config.Season.BundleTiers), 0)
	local b = Widgets.fitButton(
		card,
		if view.premium then "check" else "ticket",
		if view.premium then "See your pass" else "See the pass",
		Widgets.SPECIAL,
		function()
			if openSeason then
				openSeason()
			end
		end,
		"SeeSeason"
	)
	offerButton(card, b)
end

-- The weekly bundle on the Today tab: a brass card as narrow as an item's, its name, what's inside, the real sum
-- and the price.
local function bundleCard(offer: Types.ShopOffer, order: number, parent: Instance, size: Vector2)
	local card = newCard(parent, "Card_" .. offer.id, order, "brass", size)
	Widgets.glow(card, Theme.color.gold)
	local inner = Instance.new("Frame")
	inner.Name = "Inside"
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.fromOffset(CARD_SIDE, COMPACT.top)
	inner.Size = UDim2.new(1, -2 * CARD_SIDE, 1, -(COMPACT.top + COMPACT.bottom))
	inner.Parent = card
	local title = Widgets.label(inner, offer.name, Theme.text.small, TITLE_HEIGHT)
	title.Name = "Title"
	title.FontFace = Theme.font.display
	title.TextColor3 = Theme.color.gold
	title.TextWrapped = false
	title.TextTruncate = Enum.TextTruncate.AtEnd
	Widgets.textStroke(title)
	Widgets.leadIcon(title, Icons.fromEmoji(offer.icon) or "gift", Theme.size.icon, Theme.space.xs)
	local names = {}
	for _, id in offer.items do
		local item = Catalogue.item(id)
		if item then
			table.insert(names, item.name)
		end
	end
	offerText(
		inner,
		names,
		string.format("Separately:\n%s %s", ROBUX, formatNumber(Shop.bundleValue(offer.id, robuxPrice))),
		TITLE_HEIGHT
	)
	if ShopState.owns(offer.id) then
		offerButton(inner, Widgets.tag(inner, "check", "Owned", TAG_HEIGHT))
	else
		offerButton(inner, robuxButton(inner, offer.id, offer.robux))
	end
end

-- "5 h 12 min" / "3 d 4 h": how long until a rotating slot changes (a fact on the screen, never a ticking timer).
local function timeLeft(seconds: number): string
	local s = math.max(0, math.floor(seconds - (os.clock() - rotationAt)))
	local d, h, m = s // SECONDS_PER_DAY, (s % SECONDS_PER_DAY) // 3600, (s % 3600) // 60
	if d > 0 then
		return string.format("%d d %d h", d, h)
	elseif h > 0 then
		return string.format("%d h %d min", h, m)
	end
	return string.format("%d min", math.max(1, m))
end

local function sectionTitle(parent: Instance, name: string, icon: string, text: string): TextLabel
	local l = Widgets.label(parent, text, Theme.text.small, 20)
	l.Name = name
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	Widgets.leadIcon(l, icon, 16, Theme.space.xs)
	return l
end

-- The Today tab: the 4 daily slots and the 2 weekly ones, each section with the time until it changes.
local function renderToday(content: Frame, area: Vector2)
	local view = ShopState.view()
	local rotation = if view then view.rotation else nil
	if rotation == nil then
		sectionTitle(content, "Loading", "hourglass", "Loading today's shop…")
		return
	end
	local share = #rotation.daily / TODAY_COLUMNS
	local daily = sectionTitle(content, "DailyTitle", "clock", "Daily · new items in " .. timeLeft(rotation.dailyLeft))
	daily.Size = UDim2.new(share, -TODAY_GAP, 0, 20)
	local weekly =
		sectionTitle(content, "WeeklyTitle", "calendar", "Weekly · new in " .. timeLeft(rotation.weeklyLeft))
	weekly.Position = UDim2.fromScale(share, 0)
	weekly.Size = UDim2.new(1 - share, 0, 0, 20)
	local cards = Instance.new("Frame")
	cards.Name = "Rotation"
	cards.BackgroundTransparency = 1
	cards.Position = UDim2.fromOffset(0, 24)
	cards.Size = UDim2.new(1, 0, 1, -24)
	cards.Parent = content
	local size = Vector2.new(Widgets.tileWidth(area.X, TODAY_COLUMNS, TODAY_GAP), area.Y - 24)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(size.X, size.Y)
	grid.CellPadding = UDim2.fromOffset(TODAY_GAP, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cards
	local pending: { Pending } = {}
	local order = 0
	for _, id in rotation.daily do
		local item = Catalogue.item(id)
		if item then
			order += 1
			table.insert(pending, itemCard(item, order, cards, size, true))
		end
	end
	for _, id in rotation.weekly do
		order += 1
		local item = Catalogue.item(id)
		local offer = Catalogue.offer(id)
		if item then
			table.insert(pending, itemCard(item, order, cards, size, true))
		elseif offer then
			bundleCard(offer, order, cards, size)
		end
	end
	finishCards(pending, size, true)
end

-- The Themes tab's last card: what you see when a theme wins the vote (the opt-out, saved in your profile). A
-- plain card like a free item's, the choice explained in its well.
local function themeSettingCard(order: number, parent: Instance, size: Vector2): Pending
	local card = newCard(parent, "Card_ThemeSetting", order, "plate", size)
	rarityTag(card, "Setting", Theme.color.slate)
	local classic = Cosmetics.classicOnly()
	local area = buttonArea(card, Widgets.BUTTON_HEIGHT)
	local b = Widgets.fitButton(
		area,
		"eye",
		if classic then "Show themes" else "Always classic",
		Widgets.BUTTON,
		function()
			Intents.defaultTheme(not classic)
		end,
		"ThemeSetting"
	)
	b.TextSize = Theme.text.small
	arrange(area, { b }, size.X - 2 * CARD_SIDE)
	return {
		area = Widgets.BUTTON_HEIGHT,
		detail = false,
		finish = function(g: Geometry)
			cardName(card, g, "What you see", nil)
			local well = displayWell(card, g.wellTop, g.wellHeight, nil)
			-- short lines: they must fit a phone card
			local text = if classic
				then "Always the classic map, whatever theme wins"
				else "The theme the map's voters bring wins"
			local line = centred(well, text, Theme.text.small, g.wellHeight, Theme.color.textDim, true)
			line.FontFace = Theme.font.bodyLight
			line.Size = UDim2.new(1, -2 * WELL_INSET, 1, 0)
			line.Position = UDim2.fromOffset(WELL_INSET, 0)
		end,
	}
end

-- A readable name for a Robux product that isn't a catalogue item or offer (the season pass and its bundle are
-- named with the season they were bought in, the rewarded video's product as on the store page).
local function productName(id: string, at: number): string?
	if id == "season_pass" or id == "season_bundle" then
		local name = if id == "season_bundle"
			then string.format("%s + %d tiers", SEASON_PASS, Config.Season.BundleTiers)
			else SEASON_PASS
		local def = Season.current(at // SECONDS_PER_DAY)
		return if def then name .. " · " .. def.name else name
	elseif id == SimAds.PRODUCT then
		return "Quest reroll"
	end
	return nil
end

-- A history row's pixel icon and name.
local function historyName(id: string?, at: number): (string, string)
	if id == nil then
		return "gift", "?"
	end
	local item = Catalogue.item(id)
	if item then
		return SLOT_ICONS[item.slot] or "gift", item.name .. " " .. (SLOT_NAMES[item.slot] or "")
	end
	local offer = Catalogue.offer(id)
	if offer then
		return OFFER_ICONS[offer.id] or Icons.fromEmoji(offer.icon) or "gift", offer.name
	end
	local product = productName(id, at)
	if product then
		return if id == SimAds.PRODUCT then "reroll" else "ticket", product
	end
	return "gift", id
end

local function renderHistory(content: Frame): number
	local view = ShopState.view()
	local history = if view then view.history else {}
	local pages = math.max(1, math.ceil(#history / HISTORY_PER_PAGE))
	page = math.clamp(page, 1, pages)
	local list = Widgets.list(content, false, Theme.space.xs)
	list.Name = "HistoryList"
	if #history == 0 then
		local empty = Widgets.label(content, "No purchases yet. Every Robux purchase will be listed here.", nil, 30)
		empty.TextColor3 = Theme.color.textDim
		Widgets.leadIcon(empty, "scroll", Theme.size.icon)
		return pages
	end
	for i = (page - 1) * HISTORY_PER_PAGE + 1, math.min(#history, page * HISTORY_PER_PAGE) do
		local h = history[i]
		local row = Instance.new("ImageLabel")
		row.Name = "Purchase"
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, HISTORY_ROW)
		row.LayoutOrder = i
		row.Parent = content
		Widgets.material(row, "raised")
		Widgets.padding(row, Theme.space.m, 0)
		local t = os.date("!*t", h.at) :: any -- Roblox's os.date only takes "*t" and "!*t"
		local date = Widgets.label(row, string.format("%04d-%02d-%02d", t.year, t.month, t.day), nil, HISTORY_ROW)
		date.Size = UDim2.fromOffset(DATE_WIDTH, HISTORY_ROW)
		date.TextColor3 = Theme.color.textDim
		local icon, text = historyName(h.item, h.at)
		local name = Widgets.label(row, text, nil, HISTORY_ROW)
		name.Name = "Item"
		name.Position = UDim2.fromOffset(DATE_WIDTH, 0)
		name.Size = UDim2.new(1, -(DATE_WIDTH + PRICE_WIDTH), 1, 0)
		name.TextWrapped = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		Widgets.leadIcon(name, icon, Theme.size.icon)
		local price = Widgets.label(row, ROBUX .. " " .. formatNumber(h.robux), nil, HISTORY_ROW)
		price.FontFace = Theme.font.display
		price.AnchorPoint = Vector2.new(1, 0)
		price.Position = UDim2.fromScale(1, 0)
		price.Size = UDim2.fromOffset(PRICE_WIDTH, HISTORY_ROW)
		price.TextXAlignment = Enum.TextXAlignment.Right
		price.TextColor3 = Theme.color.gold
	end
	return pages
end

local function selectTab(id: string)
	tab, page = id, 1
	Intents.signal("ItemViewed", tab) -- analytics
	render()
end

-- The tab row: the selected tab gold with its icon and name, the others dark wells with their icon.
local function renderTabs(r: Refs)
	Widgets.clear(r.tabs)
	for i, t in TABS do
		local selected = t.id == tab
		local b = Widgets.tab(r.tabs, "", 0, selected, function()
			selectTab(t.id)
		end)
		b.Name = "Tab_" .. t.id
		b.LayoutOrder = i
		b.Size = UDim2.new((if selected then 2 else 1) / TAB_UNITS, -TAB_GAP, 0, BAR)
		local icon: GuiObject
		if selected then
			local label = Widgets.label(b, t.label, Theme.text.small, BAR)
			label.Name = "Label"
			label.FontFace = Theme.font.display
			label.TextColor3 = Theme.color.textDark
			label.TextWrapped = false
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.Size = UDim2.fromOffset(0, BAR)
			label.AutomaticSize = Enum.AutomaticSize.X
			icon = Widgets.leadIcon(label, t.icon, Theme.size.icon, Theme.space.xs)
		else
			icon = Icons.label(b, t.icon, Theme.size.iconButton)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
		end
	end
end

render = function()
	local r = ui
	if r == nil or not panel.Visible then
		return
	end
	local summary = ProfileState.summary()
	r.glory.Text = formatNumber(if summary then summary.glory else 0)
	local view = ShopState.view()
	r.vip.Visible = view ~= nil and view.vip
	r.test.Visible = view ~= nil and view.testMode
	renderTabs(r)
	local content = r.content
	content:ClearAllChildren()
	local pages = 1
	if tab == "History" then
		pages = renderHistory(content)
		r.footer.Text = "Purchase history: your Robux purchases, newest first"
	elseif tab == "Today" then
		renderToday(content, contentSize())
		r.footer.Text = string.format(
			"The same shop for everyone, nothing random. Every item comes back within %d days.",
			RETURN_DAYS
		)
	else
		local perPage = if tab == "Offers" then OFFERS_PER_PAGE else PER_PAGE
		local gap = if tab == "Offers" then OFFER_GAP else GAP
		local area = contentSize()
		local size = Vector2.new(Widgets.tileWidth(area.X, perPage, gap), area.Y - TAG_ROOM)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, TAG_ROOM) -- the cards' tags and title plates ride above them
		pad.Parent = content
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(size.X, size.Y)
		grid.CellPadding = UDim2.fromOffset(gap, 0)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = content
		local entries: { any } = {}
		if tab == "Offers" then
			for _, offer in Catalogue.OFFERS do
				if not offer.weekly then -- bundles are in the Today tab in their weeks
					table.insert(entries, offer)
				end
			end
		else
			for _, item in Catalogue.ofSlot(tab) do
				if not item.season or ShopState.owns(item.id) then -- season rewards show once you have them
					table.insert(entries, item)
				end
			end
		end
		local extra = if (tab == "Offers" and SeasonState.active()) or tab == "Theme" then 1 else 0
		pages = math.max(1, math.ceil((#entries + extra) / perPage))
		page = math.clamp(page, 1, pages)
		local pending: { Pending } = {}
		for i = (page - 1) * perPage + 1, math.min(#entries, page * perPage) do
			if tab == "Offers" then
				offerCard(entries[i], i, content, size)
			else
				table.insert(pending, itemCard(entries[i], i, content, size))
			end
		end
		if extra > 0 and page == pages then
			if tab == "Theme" then
				table.insert(pending, themeSettingCard(#entries + 1, content, size))
			else
				seasonCard(#entries + 1, content, size)
			end
		end
		finishCards(pending, size)
		r.footer.Text = if robuxOpen()
			then "No random items: you always see what you get. Glory is earned by playing, never sold."
			else "Robux purchases open after the match. Glory purchases and equipping work any time."
	end
	r.pager.Visible = pages > 1
	r.page.Text = string.format("%d/%d", page, pages)
end

local setOpen: (boolean) -> ()

-- The panel's contents, built when it opens: header (title, Glory, VIP, test mode, pager, close), tabs, the
-- page of cards and a footer line.
local function build(): Refs
	-- the title plate on the window's top edge, the close gem on its corner
	Widgets.header(panel, "Shop", "cart", function()
		setOpen(false)
	end)
	local header = Instance.new("Frame")
	header.Name = "Info"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, BAR)
	header.LayoutOrder = 1
	header.Parent = panel
	local pager, pageLabel = Widgets.pager(header, function()
		page -= 1
		Intents.signal("ItemViewed", tab) -- analytics
		render()
	end, function()
		page += 1
		Intents.signal("ItemViewed", tab) -- analytics
		render()
	end)
	pager.AnchorPoint = Vector2.new(1, 0)
	pager.Position = UDim2.fromScale(1, 0)
	local info = Instance.new("Frame")
	info.Name = "Values"
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, -(pager.Size.X.Offset + Theme.space.m), 1, 0)
	info.Parent = header
	Widgets.list(info, true, Theme.space.l)
	local room = Instance.new("UIPadding")
	room.PaddingLeft = UDim.new(0, 10) -- the counter's medal rides over its left end
	room.Parent = info
	local glory = Widgets.counter(info, "medal", "", GLORY_WIDTH)
	glory.Name = "Glory"
	glory.LayoutOrder = 2
	local vip = Widgets.chip(info, "crown", "VIP", nil, Theme.size.chip)
	vip.Name = "Vip"
	vip.TextColor3 = Theme.color.gold
	vip.LayoutOrder = 3
	local test = Widgets.hint(info, "Studio test mode: purchases are free", Theme.text.small, BAR)
	test.Name = "TestMode"
	test.Size = UDim2.fromOffset(TEST_WIDTH, BAR)
	test.LayoutOrder = 4

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, BAR)
	tabs.LayoutOrder = 2
	tabs.Parent = panel
	Widgets.list(tabs, true, TAB_GAP)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 1, -(2 * BAR + FOOTER_HEIGHT + 4 * Theme.space.s)) -- four gaps: the header's too
	content.LayoutOrder = 3
	content.Parent = panel

	local footer = Widgets.hint(panel, "", Theme.text.small, FOOTER_HEIGHT)
	footer.Name = "Footer"
	footer.TextWrapped = false
	footer.TextTruncate = Enum.TextTruncate.AtEnd
	footer.LayoutOrder = 4

	return {
		glory = glory,
		vip = vip,
		test = test,
		pager = pager,
		page = pageLabel,
		tabs = tabs,
		content = content,
		footer = footer,
	}
end

-- The floating cart button is for the lobby screens, which cover the top bar; in a match the top bar has its own.
local function refreshButton()
	local inLobby = LobbyState.phase() ~= "None" or ClientState.snapshot() == nil
	openButton.Visible = inLobby and not panel.Visible
end

setOpen = function(open: boolean)
	if open and not panel.Visible then
		Intents.signal("ShopOpened") -- analytics: a new Shop funnel session
	end
	panel.Visible = open
	if open and ui == nil then
		ui = build()
	elseif not open and ui ~= nil then
		Widgets.clear(panel) -- a closed shop keeps no cards or buttons (rebuilt when it opens)
		ui = nil
	end
	refreshButton()
	if open then
		render()
	end
end

local function hideStarterOffer()
	offerPanel.Visible = false
	offerDim.Visible = false
	Widgets.clear(offerPanel)
end

-- The starter-pack pop-up: what's inside, the real sum, the price; no timer.
local function showStarterOffer()
	local offer = Catalogue.offer("starter")
	if offer == nil or ShopState.owns("starter") then
		return
	end
	Widgets.clear(offerPanel)
	Widgets.header(offerPanel, offer.name, "gift")
	-- what's inside, two columns, each with its slot's icon
	local items = Instance.new("Frame")
	items.Name = "Items"
	items.BackgroundTransparency = 1
	items.Size = UDim2.fromScale(1, 0)
	items.AutomaticSize = Enum.AutomaticSize.Y
	items.LayoutOrder = 2
	items.Parent = offerPanel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -Theme.space.xs, 0, 24)
	grid.CellPadding = UDim2.fromOffset(Theme.space.m, Theme.space.xs)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = items
	for i, id in offer.items do
		local item = Catalogue.item(id)
		if item then
			local l = Widgets.label(items, item.name .. " " .. (SLOT_NAMES[item.slot] or ""), nil, 24)
			l.LayoutOrder = i
			l.TextWrapped = false
			l.TextTruncate = Enum.TextTruncate.AtEnd
			Widgets.leadIcon(l, SLOT_ICONS[item.slot] or "gift", Theme.size.icon)
		end
	end
	local sum = Widgets.hint(
		offerPanel,
		string.format(
			"Bought separately: %s %s · one per account",
			ROBUX,
			formatNumber(Shop.bundleValue("starter", robuxPrice))
		),
		Theme.text.small,
		20
	)
	sum.Name = "Sum"
	sum.LayoutOrder = 3
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	row.LayoutOrder = 4
	row.Parent = offerPanel
	Widgets.list(row, true, Theme.space.m).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local price = robuxPrice("starter", offer.robux)
	local buy = Widgets.button(row, "Buy  " .. ROBUX .. " " .. formatNumber(price), 176, Widgets.GOOD, function()
		hideStarterOffer()
		buyRobux("starter")
	end)
	buy.Name = "BuyStarter"
	buy.LayoutOrder = 1
	local later = Widgets.button(row, "Not now", 150, Widgets.BUTTON_OFF, hideStarterOffer)
	later.Name = "NotNow"
	later.LayoutOrder = 2
	offerPanel.Visible = true
	offerDim.Visible = true
	Intents.signal("OfferOpened") -- analytics
end

-- The Robux price to show for an item, offer or product (live once its product id is set), for other screens.
function ShopUI.robuxPrice(id: string, listPrice: number): number
	return robuxPrice(id, listPrice)
end

-- UI.Season registers how to open the season pass screen (the Offers tab's season card).
function ShopUI.setSeasonScreen(open: () -> ())
	openSeason = open
end

-- Open the shop on a tab (e.g. from a scenario or another screen).
function ShopUI.open(tabId: string?)
	tab = tabId or tab
	page = 1
	setOpen(true)
end

function ShopUI.close()
	setOpen(false)
end

-- The top bar's cart button.
function ShopUI.toggle()
	setOpen(not panel.Visible)
end

function ShopUI.init(showToast: (string) -> ())
	toast = showToast
	gui = Widgets.screen("Shop", 30) -- above the lobby screens: the shop opens in the lobby too

	openButton = Widgets.cornerButton(gui, 0, "cart", "ShopButton", Theme.color.good, function()
		setOpen(true)
	end)

	panel = Widgets.window(gui, "ShopPanel")
	Widgets.list(panel, false, Theme.space.s)
	-- at most a phone's window: on a tablet the cards keep their size (it all grows by the DeviceScale)
	local function placePanel()
		local screen = Widgets.screenSize(gui) / Widgets.uiScale()
		local w = math.min(screen.X - 2 * Theme.space.m, MAX_WINDOW.X)
		local h = math.min(screen.Y - 3 * Theme.space.m, MAX_WINDOW.Y)
		panelSize = Vector2.new(w - w % 2, h - h % 2)
		Widgets.fit(panel, UDim2.fromOffset(panelSize.X, panelSize.Y), UDim2.new(0.5, 0, 0.5, Theme.space.xs))
		render()
	end
	placePanel()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placePanel)
	Widgets.onScale(placePanel)

	-- the starter-pack pop-up: a brass window over a dimmed screen
	offerDim = Instance.new("Frame")
	offerDim.Name = "StarterOfferDim"
	offerDim.Active = true -- taps on the dim never reach what is under it
	offerDim.Size = UDim2.fromScale(1, 1)
	offerDim.BackgroundColor3 = Theme.color.slate950
	offerDim.BackgroundTransparency = 0.4
	offerDim.BorderSizePixel = 0
	offerDim.Visible = false
	offerDim.Parent = gui
	offerPanel = Widgets.panel(gui, 400, "brass")
	offerPanel.Name = "StarterOffer"
	offerPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	offerPanel.Position = UDim2.fromScale(0.5, 0.5)
	offerPanel.Visible = false
	Widgets.list(offerPanel, false, Theme.space.s)

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ShopState.onChange(function(offer: boolean)
		rotationAt = os.clock()
		if offer then
			showStarterOffer()
		elseif offerPanel.Visible and ShopState.owns("starter") then
			hideStarterOffer()
		end
		render()
	end)
	ProfileState.onChange(render)
	ClientState.onReset(function()
		refreshButton()
		render()
	end)
	LobbyState.onChange(refreshButton)
	Cosmetics.onChange(render)
	SeasonState.onChange(render)
end

return ShopUI
