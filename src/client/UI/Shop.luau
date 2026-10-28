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
local GAP = Theme.space.m -- between cards
local TODAY_GAP = Theme.space.s
local TAB_GAP = Theme.space.xs
local FOOTER_HEIGHT = 18
local PREVIEW_HEIGHT = 52
local COMPACT_PREVIEW = 40 -- the Today tab's cards: their section titles take a line
local TAG_HEIGHT = 36
local BUTTONS_HEIGHT = 2 * Widgets.BUTTON_HEIGHT + Theme.space.s -- a card's price buttons, stacked
local TITLE_HEIGHT = 32 -- an offer card's icon and name
local LINE = 17 -- a 14 px line
local HISTORY_ROW = 32
local DATE_WIDTH = 104
local PRICE_WIDTH = 96
local TEST_WIDTH = 150
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
local offerPanel: Frame
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

-- Stack a card's buttons and tags from the bottom of its button area up, each centred.
local function stack(items: { GuiObject })
	local y = BUTTONS_HEIGHT
	for i = #items, 1, -1 do
		local item = items[i]
		local h = item.Size.Y.Offset
		y -= h
		item.AnchorPoint = Vector2.new(0.5, 0)
		item.Position = UDim2.new(0.5, 0, 0, y)
		y -= Theme.space.s
	end
end

local function buttonArea(card: Frame): Frame
	local area = Instance.new("Frame")
	area.Name = "Buttons"
	area.BackgroundTransparency = 1
	area.AnchorPoint = Vector2.new(0, 1)
	area.Position = UDim2.fromScale(0, 1)
	area.Size = UDim2.new(1, 0, 0, BUTTONS_HEIGHT)
	area.Parent = card
	return area
end

-- A raised card (Widgets.card) sized by the grid it sits in, outlined in its rarity's colour.
local function newCard(parent: Instance, name: string, order: number, outline: Color3?): Frame
	local card = Widgets.card(parent)
	card.Name = name
	card.LayoutOrder = order
	card.AutomaticSize = Enum.AutomaticSize.None -- the grid's cell is its size
	local pad = card:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft = UDim.new(0, Theme.space.s)
		pad.PaddingRight = UDim.new(0, Theme.space.s)
		pad.PaddingTop = UDim.new(0, Theme.space.s)
		pad.PaddingBottom = UDim.new(0, Theme.space.s)
	end
	local stroke = card:FindFirstChild("Outline")
	if outline and stroke and stroke:IsA("UIStroke") then
		stroke.Color = outline
	end
	return card
end

-- The Robux price button (greyed out during a match: a tap explains why).
local function robuxButton(parent: Instance, id: string, listPrice: number): TextButton
	local b = Widgets.fitButton(
		parent,
		nil,
		ROBUX .. " " .. formatNumber(robuxPrice(id, listPrice)),
		Widgets.BUTTON,
		function()
			buyRobux(id)
		end,
		"BuyRobux"
	)
	if not robuxOpen() then
		Widgets.setEnabled(b, false)
	end
	return b
end

-- The little picture on a card, `height` px tall (pictures are 4 px less, 4:3 for flags).
local function preview(parent: Instance, item: Types.CatalogueItem, height: number)
	local holder = Instance.new("Frame")
	holder.Name = "Preview"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, height)
	holder.Parent = parent
	local color = myColor()
	local h = height - 4
	local function size(aspect: number): UDim2
		return UDim2.fromOffset(math.floor(h * aspect), h)
	end
	local thing: GuiObject
	if item.slot == "Flag" then
		thing = Cosmetics.flagLabel(holder, item.id, color, size(4 / 3))
	elseif item.slot == "Border" then
		thing = Cosmetics.swatchLabel(holder, item.art, "default", color, size(1.5))
	elseif item.slot == "Shades" then
		thing = Cosmetics.swatchLabel(holder, "solid", item.art, color, size(1.5))
	elseif item.slot == "Token" then
		thing = Cosmetics.tokenLabel(holder, item.id, color, size(1))
	elseif item.slot == "PowerFx" then
		thing = Cosmetics.effectLabel(holder, item.id, size(4 / 3))
	elseif item.slot == "Theme" then
		thing = Cosmetics.themeLabel(holder, item.id, size(1.75))
	elseif item.slot == "Frame" then
		local l = centred(holder, Players.LocalPlayer.Name, Theme.text.small, 28)
		l.Size = UDim2.new(1, -Theme.space.m, 0, 28)
		l.BackgroundColor3 = Theme.color.navyDeep
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
		thing = centred(holder, string.split(item.art, " ")[1], math.floor(h * 0.7), h)
	end
	thing.AnchorPoint = Vector2.new(0.5, 0.5)
	thing.Position = UDim2.fromScale(0.5, 0.5)
end

-- Is this item or offer in the shop today? Core items always are; rotating ones in their slots (Sim.ShopRotation).
local function onSaleToday(id: string): boolean
	local view = ShopState.view()
	local rotation = if view then view.rotation else nil
	return rotation == nil or ShopRotation.onSale(id, rotation.day)
end

local function itemCard(item: Types.CatalogueItem, order: number, parent: Instance, compact: boolean?)
	local rarity = Theme.rarity[item.rarity] or Theme.color.textDim
	local card = newCard(parent, "Card_" .. item.id, order, if item.rarity ~= "Common" then rarity else nil)
	local top = if compact then COMPACT_PREVIEW else PREVIEW_HEIGHT
	preview(card, item, top)
	local name = centred(card, item.name, Theme.text.body, 18)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(0, top + 2)
	local detail = item.rarity
	if item.power then
		detail ..= " · " .. item.power
	elseif item.slot == "Theme" and not item.free then
		detail ..= " · any map"
	elseif item.animated then
		detail ..= " · animated"
	elseif item.free then
		detail = "Free"
	elseif item.vipOnly then
		detail = "VIP only"
	elseif item.earned then
		detail ..= " · earned"
	end
	local line = centred(
		card,
		detail,
		Theme.text.small,
		16,
		if item.free then Theme.color.textDim elseif item.vipOnly then Theme.color.gold else rarity
	)
	line.Name = "Rarity"
	line.Position = UDim2.fromOffset(0, top + 20)

	local area = buttonArea(card)
	local items: { GuiObject } = {}
	if ShopState.owns(item.id) then
		if item.slot == "Emote" then
			table.insert(items, Widgets.tag(area, "check", "Owned", TAG_HEIGHT))
		elseif ShopState.isEquipped(item) then
			local t = Widgets.tag(area, "check", "Equipped", TAG_HEIGHT)
			t.TextColor3 = Theme.color.goldPale
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
		local back = centred(area, string.format("Back within %d days", RETURN_DAYS), Theme.text.small, 2 * LINE)
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
			local b = Widgets.fitButton(area, "medal", formatNumber(cost), Widgets.GOLD, function()
				Intents.buy(item.id, "Glory")
			end, "BuyGlory")
			if summary == nil or summary.glory < cost then
				Widgets.setEnabled(b, false) -- still sends: the server says "Not enough Glory"
			end
			table.insert(items, b)
		end
	end
	stack(items)
end

-- An offer card's top: its pixel icon and name.
local function offerTitle(card: Frame, icon: string, name: string)
	local title = Widgets.title(card, name, Theme.text.heading, TITLE_HEIGHT)
	title.Name = "Title"
	Widgets.leadIcon(title, icon, Theme.icon.medium, Theme.space.s)
end

-- A dim block of short lines (what's inside), then a gold note under it.
local function offerText(card: Frame, lines: { string }, note: string)
	local list = Widgets.label(card, table.concat(lines, "\n"), Theme.text.small, LINE * #lines)
	list.Name = "Contents"
	list.FontFace = Theme.font.bodyLight
	list.TextColor3 = Theme.color.textDim
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextTruncate = Enum.TextTruncate.AtEnd
	list.Position = UDim2.fromOffset(0, TITLE_HEIGHT + Theme.space.xs)
	local noteLines = #string.split(note, "\n")
	local n = Widgets.label(card, note, Theme.text.small, LINE * noteLines)
	n.Name = "Note"
	n.TextColor3 = Theme.color.gold
	n.TextYAlignment = Enum.TextYAlignment.Top
	n.Position = UDim2.fromOffset(0, TITLE_HEIGHT + 2 * Theme.space.xs + LINE * #lines)
end

local function itemLine(id: string): string?
	local item = Catalogue.item(id)
	return if item then item.name .. " " .. (SLOT_NAMES[item.slot] or "") else nil
end

local OFFER_ICONS: { [string]: string } = { vip = "crown", starter = "gift" }

local function offerCard(offer: Types.ShopOffer, order: number, parent: Instance)
	local card = newCard(parent, "Card_" .. offer.id, order, Theme.color.gold)
	local icon = OFFER_ICONS[offer.id] or Icons.fromEmoji(offer.icon) or "gift"
	offerTitle(card, icon, offer.name)
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
	offerText(card, lines, note)
	local area = buttonArea(card)
	if ShopState.owns(offer.id) then
		stack({ Widgets.tag(area, "check", "Owned", TAG_HEIGHT) })
	else
		stack({ robuxButton(area, offer.id, offer.robux) })
	end
end

-- The Offers tab's season pass card: what the pass holds, and the way to its screen (bought there).
local function seasonCard(order: number, parent: Instance)
	local view = SeasonState.view()
	if view == nil or view.id == "" then
		return
	end
	local card = newCard(parent, "Card_season_pass", order, Theme.color.gold)
	offerTitle(card, "ticket", SEASON_PASS)
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
	}, string.format("No tier skips\nBundle: pass + %d tiers", Config.Season.BundleTiers))
	local area = buttonArea(card)
	local b = Widgets.fitButton(
		area,
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
	stack({ b })
end

-- The weekly bundle on the Today tab: the offer card, narrow enough for a sixth of the screen.
local function bundleCard(offer: Types.ShopOffer, order: number, parent: Instance)
	local card = newCard(parent, "Card_" .. offer.id, order, Theme.color.gold)
	local title = Widgets.title(card, offer.name, Theme.text.small, TITLE_HEIGHT)
	title.Name = "Title"
	Widgets.leadIcon(title, Icons.fromEmoji(offer.icon) or "gift", Theme.size.icon, Theme.space.xs)
	local names = {}
	for _, id in offer.items do
		local item = Catalogue.item(id)
		if item then
			table.insert(names, item.name)
		end
	end
	offerText(
		card,
		names,
		string.format("Separately:\n%s %s", ROBUX, formatNumber(Shop.bundleValue(offer.id, robuxPrice)))
	)
	local area = buttonArea(card)
	if ShopState.owns(offer.id) then
		stack({ Widgets.tag(area, "check", "Owned", TAG_HEIGHT) })
	else
		stack({ robuxButton(area, offer.id, offer.robux) })
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
local function renderToday(content: Frame)
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
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / TODAY_COLUMNS, -TODAY_GAP, 1, 0)
	grid.CellPadding = UDim2.fromOffset(TODAY_GAP, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = cards
	local order = 0
	for _, id in rotation.daily do
		local item = Catalogue.item(id)
		if item then
			order += 1
			itemCard(item, order, cards, true)
		end
	end
	for _, id in rotation.weekly do
		order += 1
		local item = Catalogue.item(id)
		local offer = Catalogue.offer(id)
		if item then
			itemCard(item, order, cards, true)
		elseif offer then
			bundleCard(offer, order, cards)
		end
	end
end

-- The Themes tab's last card: what you see when a theme wins the vote (the opt-out, saved in your profile).
local function themeSettingCard(order: number, parent: Instance)
	local card = newCard(parent, "Card_ThemeSetting", order, nil)
	local eye = Widgets.icon(card, "eye", Theme.icon.medium)
	eye.AnchorPoint = Vector2.new(0.5, 0)
	eye.Position = UDim2.new(0.5, 0, 0, Theme.space.s)
	local title = centred(card, "What you see", Theme.text.body, 18)
	title.Position = UDim2.fromOffset(0, PREVIEW_HEIGHT + 2)
	local classic = Cosmetics.classicOnly()
	-- short lines: they must fit a phone card
	local text = if classic
		then "Always the classic map, whatever theme wins"
		else "The theme the map's voters bring wins"
	local line = centred(card, text, Theme.text.small, 3 * LINE, Theme.color.textDim, true)
	line.FontFace = Theme.font.bodyLight
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.Position = UDim2.fromOffset(0, PREVIEW_HEIGHT + 22)
	local area = buttonArea(card)
	local b = Widgets.fitButton(
		area,
		nil,
		if classic then "Show themes" else "Always classic",
		Widgets.BUTTON,
		function()
			Intents.defaultTheme(not classic)
		end,
		"ThemeSetting"
	)
	b.TextSize = Theme.text.small
	stack({ b })
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
		local row = Instance.new("Frame")
		row.Name = "Purchase"
		row.BackgroundColor3 = Theme.color.navyRaised
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, 0, 0, HISTORY_ROW)
		row.LayoutOrder = i
		row.Parent = content
		Widgets.corner(row, Theme.radius.m)
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
		price.TextColor3 = Theme.color.goldPale
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
		renderToday(content)
		r.footer.Text = string.format(
			"The same shop for everyone, nothing random. Every item comes back within %d days.",
			RETURN_DAYS
		)
	else
		local perPage = if tab == "Offers" then OFFERS_PER_PAGE else PER_PAGE
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / perPage, -GAP, 1, 0)
		grid.CellPadding = UDim2.fromOffset(GAP, 0)
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
		for i = (page - 1) * perPage + 1, math.min(#entries, page * perPage) do
			if tab == "Offers" then
				offerCard(entries[i], i, content)
			else
				itemCard(entries[i], i, content)
			end
		end
		if extra > 0 and page == pages then
			if tab == "Theme" then
				themeSettingCard(#entries + 1, content)
			else
				seasonCard(#entries + 1, content)
			end
		end
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
	Widgets.list(info, true, Theme.space.m)
	local glory = Widgets.chip(info, "medal", "", nil, Theme.size.chip)
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
	Widgets.list(row, true, Theme.space.m)
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
