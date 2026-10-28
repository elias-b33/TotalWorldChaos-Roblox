--!strict
-- The shop (docs/MONETIZATION.md 3, 10), phone first: a 🛒 button opens a full-screen panel with tabs (offers, one
-- per cosmetic slot, purchase history), five item cards per page with a preview, the Robux and Glory prices and
-- the owned / equipped state. Also the starter-pack offer (at most once per session, after the 2nd match, never
-- during a match, no timer).
--
-- Rules for minors (section 10): every price shows its currency icon, Robux prices are read live from
-- MarketplaceService (the Config list price only while a product id is unset), bundles show the real sum of their
-- pieces, no random items, no countdowns, no prompts during a match (the server refuses them).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Shop = require(Shared.Sim.Shop)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local ProfileState = require(Client.ProfileState)
local ShopState = require(Client.ShopState)
local Widgets = require(script.Parent.Widgets)

local ROBUX = utf8.char(0xE002) -- Roblox's Robux icon in every Roblox font
local GLORY = "🏅"
local PER_PAGE = 5 -- item cards per page
local HISTORY_PER_PAGE = 6
local BUTTON_SIZE = 52
local HEADER_HEIGHT = 40
local TAB_HEIGHT = 44
local FOOTER_HEIGHT = 18
local CARD = Color3.fromRGB(32, 35, 50)
local GOLD = Color3.fromRGB(242, 193, 78)
local OFF_TEXT = Color3.fromRGB(150, 152, 165)
local DEFAULT_COLOR = 1 -- previews use your nation's colour, or red before you have one

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(190, 194, 205),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 170, 60),
}

type Tab = { id: string, icon: string, label: string }
local TABS: { Tab } = {
	{ id = "Offers", icon = "🎁", label = "Offers" },
	{ id = "Flag", icon = "🏳", label = "Flags" },
	{ id = "Border", icon = "🧱", label = "Borders" },
	{ id = "Shades", icon = "🎨", label = "Shades" },
	{ id = "Token", icon = "♟", label = "Tokens" },
	{ id = "Emote", icon = "😀", label = "Emotes" },
	{ id = "Victory", icon = "🏆", label = "Victory" },
	{ id = "Frame", icon = "🖼", label = "Frames" },
	{ id = "PowerFx", icon = "✨", label = "Powers" },
	{ id = "History", icon = "🧾", label = "History" },
}

local SLOT_NAMES: { [string]: string } = {
	Flag = "Flag",
	Token = "Token",
	Border = "Border",
	Shades = "Shades",
	Frame = "Frame",
	Emote = "Emote",
	Victory = "Victory",
	PowerFx = "Effect",
}

local ShopUI = {}

local toast: (string) -> () = function(_text: string) end
local gui: ScreenGui
local openButton: TextButton
local panel: Frame
local gloryLabel: TextLabel
local vipLabel: TextLabel
local testLabel: TextLabel
local pageLabel: TextLabel
local tabRow: Frame
local content: Frame
local footer: TextLabel
local offerPanel: Frame
local tab = "Offers"
local page = 1
local livePrices: { [string]: number } = {} -- live Robux prices by item or offer id
local asked: { [string]: boolean } = {}

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
				return MarketplaceService:GetProductInfo(productId, kind)
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

local function cardButton(parent: Instance, text: string, color: Color3, onPress: () -> ()): TextButton
	local b = Widgets.button(parent, text, 0, color, onPress)
	b.Size = UDim2.new(1, 0, 0, 40)
	b.TextSize = 15
	return b
end

local function stateButton(parent: Instance, text: string)
	local b = cardButton(parent, text, Widgets.BUTTON_OFF, function() end)
	b.AutoButtonColor = false
	b.TextColor3 = OFF_TEXT
end

local function centred(parent: Instance, text: string, size: number, height: number, color: Color3?): TextLabel
	local l = Widgets.label(parent, text, size, height)
	l.TextXAlignment = Enum.TextXAlignment.Center
	if color then
		l.TextColor3 = color
	end
	return l
end

-- The little picture on a card.
local function preview(parent: Instance, item: Types.CatalogueItem)
	local holder = Instance.new("Frame")
	holder.Name = "Preview"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 56)
	holder.LayoutOrder = 1
	holder.Parent = parent
	local color = myColor()
	local thing: GuiObject
	if item.slot == "Flag" then
		thing = Cosmetics.flagLabel(holder, item.id, color, UDim2.fromOffset(64, 48))
	elseif item.slot == "Border" then
		thing = Cosmetics.swatchLabel(holder, item.art, "default", color, UDim2.fromOffset(72, 48))
	elseif item.slot == "Shades" then
		thing = Cosmetics.swatchLabel(holder, "solid", item.art, color, UDim2.fromOffset(72, 48))
	elseif item.slot == "Token" then
		thing = Cosmetics.tokenLabel(holder, item.id, color, UDim2.fromOffset(48, 48))
	elseif item.slot == "Frame" then
		local l = centred(holder, Players.LocalPlayer.Name, 14, 28)
		l.Size = UDim2.fromOffset(110, 28)
		local frameColor = Cosmetics.frameColor(item.id)
		if frameColor then
			l.BackgroundTransparency = 0.85
			l.BackgroundColor3 = frameColor
			local stroke = Instance.new("UIStroke")
			stroke.Color = frameColor
			stroke.Thickness = 2
			stroke.Parent = l
		end
		Widgets.corner(l, 6)
		thing = l
	else -- emotes, victory animations, power effects: their icon (the first frame)
		local icon = string.split(item.art, " ")[1]
		local l = centred(holder, icon, 34, 48)
		l.Size = UDim2.fromOffset(80, 48)
		thing = l
	end
	thing.AnchorPoint = Vector2.new(0.5, 0.5)
	thing.Position = UDim2.fromScale(0.5, 0.5)
end

local function itemCard(item: Types.CatalogueItem, order: number)
	local card = Instance.new("Frame")
	card.Name = "Card_" .. item.id
	card.BackgroundColor3 = CARD
	card.LayoutOrder = order
	card.Parent = content
	Widgets.corner(card, 10)
	Widgets.padding(card, 6)
	local list = Widgets.list(card, false, 4)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local stroke = Instance.new("UIStroke")
	stroke.Color = RARITY_COLORS[item.rarity] or Widgets.BUTTON_OFF
	stroke.Thickness = 1
	stroke.Parent = card

	preview(card, item)
	centred(card, item.name, 14, 18).LayoutOrder = 2
	local detail = item.rarity
	if item.power then
		detail ..= " · " .. item.power
	elseif item.animated then
		detail ..= " · animated"
	elseif item.free then
		detail = "Free"
	elseif item.vipOnly then
		detail = "VIP only"
	end
	centred(card, detail, 12, 14, RARITY_COLORS[item.rarity]).LayoutOrder = 3

	local buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 84)
	buttons.LayoutOrder = 4
	buttons.Parent = card
	Widgets.list(buttons, false, 4)

	if ShopState.owns(item.id) then
		if item.slot == "Emote" then
			stateButton(buttons, "✅ Owned")
		elseif ShopState.isEquipped(item) then
			stateButton(buttons, "✅ Equipped")
		else
			cardButton(buttons, "Equip", Widgets.GOOD, function()
				Intents.equip(item.id)
			end)
		end
		return
	end
	if item.vipOnly then
		cardButton(buttons, "👑 Comes with VIP", Widgets.BUTTON_OFF, function()
			tab, page = "Offers", 1
			render()
		end)
		return
	end
	if item.robux then
		local price = robuxPrice(item.id, item.robux)
		cardButton(
			buttons,
			ROBUX .. " " .. formatNumber(price),
			if robuxOpen() then Widgets.BUTTON else Widgets.BUTTON_OFF,
			function()
				buyRobux(item.id)
			end
		)
	end
	if item.glory then
		local summary = ProfileState.summary()
		local enough = summary ~= nil and summary.glory >= item.glory
		local b = cardButton(
			buttons,
			GLORY .. " " .. formatNumber(item.glory),
			if enough then GOLD else Widgets.BUTTON_OFF,
			function()
				Intents.buy(item.id, "Glory")
			end
		)
		b.TextColor3 = if enough then Color3.fromRGB(40, 28, 0) else OFF_TEXT
	end
end

local function offerCard(offer: Types.ShopOffer, order: number)
	local card = Instance.new("Frame")
	card.Name = "Card_" .. offer.id
	card.BackgroundColor3 = CARD
	card.LayoutOrder = order
	card.Parent = content
	Widgets.corner(card, 10)
	Widgets.padding(card, 6)
	local list = Widgets.list(card, false, 3)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1
	stroke.Parent = card

	centred(card, offer.icon, 28, 34).LayoutOrder = 1
	centred(card, offer.name, 15, 18).LayoutOrder = 2
	-- what's inside, one line each (short lines: they must fit a phone card)
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
			local item = Catalogue.item(id)
			if item then
				table.insert(lines, item.name .. " " .. (SLOT_NAMES[item.slot] or ""))
			end
		end
	end
	centred(card, table.concat(lines, "\n"), 12, 78, OFF_TEXT).LayoutOrder = 3
	local note = if offer.kind == "Pass"
		then "Yours forever"
		else string.format("Bought separately: %s %s", ROBUX, formatNumber(Shop.bundleValue(offer.id)))
	if offer.oncePerAccount and offer.kind == "Product" then
		note ..= "\nOne per account"
	end
	centred(card, note, 12, 30, GOLD).LayoutOrder = 4
	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, 40)
	buttons.LayoutOrder = 5
	buttons.Parent = card
	Widgets.list(buttons, false, 4)
	if ShopState.owns(offer.id) then
		stateButton(buttons, "✅ Owned")
	else
		local price = robuxPrice(offer.id, offer.robux)
		cardButton(
			buttons,
			ROBUX .. " " .. formatNumber(price),
			if robuxOpen() then Widgets.BUTTON else Widgets.BUTTON_OFF,
			function()
				buyRobux(offer.id)
			end
		)
	end
end

local function historyName(id: string?): string
	if id == nil then
		return "?"
	end
	local item = Catalogue.item(id)
	if item then
		return item.name .. " " .. (SLOT_NAMES[item.slot] or "")
	end
	local offer = Catalogue.offer(id)
	return if offer then offer.icon .. " " .. offer.name else id
end

local function renderHistory(): number
	local view = ShopState.view()
	local history = if view then view.history else {}
	local pages = math.max(1, math.ceil(#history / HISTORY_PER_PAGE))
	page = math.clamp(page, 1, pages)
	local list = Widgets.list(content, false, 4)
	list.Name = "HistoryList"
	if #history == 0 then
		Widgets.label(content, "🧾 No purchases yet. Every Robux purchase will be listed here.", 15, 30)
		return pages
	end
	for i = (page - 1) * HISTORY_PER_PAGE + 1, math.min(#history, page * HISTORY_PER_PAGE) do
		local h = history[i]
		local row = Instance.new("Frame")
		row.Name = "Purchase"
		row.BackgroundColor3 = CARD
		row.Size = UDim2.new(1, 0, 0, 30)
		row.LayoutOrder = i
		row.Parent = content
		Widgets.corner(row, 8)
		Widgets.padding(row, 4)
		Widgets.list(row, true, 12)
		local t = os.date("!*t", h.at) :: any -- Roblox's os.date only takes "*t" and "!*t"
		local date = Widgets.label(row, string.format("%04d-%02d-%02d", t.year, t.month, t.day), 14, 22)
		date.Size = UDim2.fromOffset(110, 22)
		local name = Widgets.label(row, historyName(h.item), 14, 22)
		name.Size = UDim2.fromOffset(360, 22)
		local price = Widgets.label(row, ROBUX .. " " .. formatNumber(h.robux), 14, 22)
		price.Size = UDim2.fromOffset(120, 22)
	end
	return pages
end

render = function()
	if panel == nil or not panel.Visible then
		return
	end
	local summary = ProfileState.summary()
	gloryLabel.Text = GLORY .. " " .. formatNumber(if summary then summary.glory else 0)
	local view = ShopState.view()
	vipLabel.Visible = view ~= nil and view.vip
	testLabel.Visible = view ~= nil and view.testMode
	for _, b in tabRow:GetChildren() do
		if b:IsA("TextButton") then
			b.BackgroundColor3 = if b.Name == "Tab_" .. tab then Widgets.BUTTON else Widgets.BUTTON_OFF
		end
	end
	content:ClearAllChildren()
	local pages = 1
	if tab == "History" then
		pages = renderHistory()
		footer.Text = "Purchase history: your Robux purchases, newest first"
	else
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / PER_PAGE, -6, 1, 0)
		grid.CellPadding = UDim2.fromOffset(6, 6)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = content
		local entries: { any } = if tab == "Offers" then Catalogue.OFFERS else Catalogue.ofSlot(tab)
		pages = math.max(1, math.ceil(#entries / PER_PAGE))
		page = math.clamp(page, 1, pages)
		for i = (page - 1) * PER_PAGE + 1, math.min(#entries, page * PER_PAGE) do
			if tab == "Offers" then
				offerCard(entries[i], i)
			else
				itemCard(entries[i], i)
			end
		end
		footer.Text = if robuxOpen()
			then "No random items: you always see what you get. Glory is earned by playing, never sold."
			else "Robux purchases open after the match. Glory purchases and equipping work any time."
	end
	pageLabel.Text = string.format("%d/%d", page, pages)
end

-- The floating 🛒 button is for the lobby screens, which cover the top bar; in a match the top bar has its own.
local function refreshButton()
	local inLobby = LobbyState.phase() ~= "None" or ClientState.snapshot() == nil
	openButton.Visible = inLobby and not panel.Visible
end

local function setOpen(open: boolean)
	if open and not panel.Visible then
		Intents.signal("ShopOpened") -- analytics: a new Shop funnel session
	end
	panel.Visible = open
	refreshButton()
	if open then
		render()
	end
end

-- The starter-pack pop-up: what's inside, the real sum, the price; no timer.
local function showStarterOffer()
	local offer = Catalogue.offer("starter")
	if offer == nil or ShopState.owns("starter") then
		return
	end
	Widgets.clear(offerPanel)
	Widgets.list(offerPanel, false, 6)
	Widgets.label(offerPanel, "🎁 Starter Pack", 20, 28).LayoutOrder = 1
	local names = {}
	for _, id in offer.items do
		local item = Catalogue.item(id)
		if item then
			table.insert(names, item.name .. " " .. (SLOT_NAMES[item.slot] or ""))
		end
	end
	local what = Widgets.label(offerPanel, table.concat(names, "\n"), 14, 18 * #names)
	what.LayoutOrder = 2
	local sum = Widgets.label(
		offerPanel,
		string.format("Bought separately: %s %s · one per account", ROBUX, formatNumber(Shop.bundleValue("starter"))),
		13,
		20
	)
	sum.TextColor3 = OFF_TEXT
	sum.LayoutOrder = 3
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	row.LayoutOrder = 4
	row.Parent = offerPanel
	Widgets.list(row, true, 8)
	local price = robuxPrice("starter", offer.robux)
	Widgets.button(row, ROBUX .. " " .. formatNumber(price) .. "  Buy", 170, Widgets.BUTTON, function()
		offerPanel.Visible = false
		buyRobux("starter")
	end)
	Widgets.button(row, "Not now", 150, Widgets.BUTTON_OFF, function()
		offerPanel.Visible = false
	end)
	offerPanel.Visible = true
	Intents.signal("OfferOpened") -- analytics
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

-- The top bar's 🛒 button.
function ShopUI.toggle()
	setOpen(not panel.Visible)
end

function ShopUI.init(showToast: (string) -> ())
	toast = showToast
	gui = Widgets.screen("Shop", 30) -- above the lobby screens: the shop opens in the lobby too

	openButton = Instance.new("TextButton")
	openButton.Name = "ShopButton"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 12, 1, -12)
	openButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	openButton.BackgroundColor3 = Color3.fromRGB(46, 120, 90)
	openButton.Font = Enum.Font.GothamBold
	openButton.TextSize = 24
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "🛒"
	openButton.Parent = gui
	Widgets.corner(openButton, BUTTON_SIZE // 2)
	openButton.Activated:Connect(function()
		setOpen(true)
	end)

	panel = Instance.new("Frame")
	panel.Name = "ShopPanel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -16, 1, -16)
	panel.BackgroundColor3 = Widgets.PANEL
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = gui
	Widgets.corner(panel, 12)
	Widgets.padding(panel, 10)
	Widgets.list(panel, false, 6)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.LayoutOrder = 1
	header.Parent = panel
	Widgets.list(header, true, 8)
	local title = Widgets.label(header, "🛒 Shop", 20, HEADER_HEIGHT)
	title.Size = UDim2.fromOffset(110, HEADER_HEIGHT)
	title.LayoutOrder = 1
	gloryLabel = Widgets.label(header, "", 18, HEADER_HEIGHT)
	gloryLabel.Name = "Glory"
	gloryLabel.Size = UDim2.fromOffset(110, HEADER_HEIGHT)
	gloryLabel.TextColor3 = GOLD
	gloryLabel.LayoutOrder = 2
	vipLabel = Widgets.label(header, "👑 VIP", 16, HEADER_HEIGHT)
	vipLabel.Size = UDim2.fromOffset(80, HEADER_HEIGHT)
	vipLabel.TextColor3 = GOLD
	vipLabel.LayoutOrder = 3
	testLabel = Widgets.label(header, "🧪 Studio test mode: purchases are free", 13, HEADER_HEIGHT)
	testLabel.Size = UDim2.fromOffset(250, HEADER_HEIGHT)
	testLabel.TextColor3 = OFF_TEXT
	testLabel.LayoutOrder = 4
	local prev = Widgets.button(header, "◀", 44, Widgets.BUTTON_OFF, function()
		page -= 1
		Intents.signal("ItemViewed", tab) -- analytics
		render()
	end)
	prev.Size = UDim2.fromOffset(44, HEADER_HEIGHT)
	prev.LayoutOrder = 5
	pageLabel = Widgets.label(header, "1/1", 15, HEADER_HEIGHT)
	pageLabel.Size = UDim2.fromOffset(40, HEADER_HEIGHT)
	pageLabel.TextXAlignment = Enum.TextXAlignment.Center
	pageLabel.LayoutOrder = 6
	local nextButton = Widgets.button(header, "▶", 44, Widgets.BUTTON_OFF, function()
		page += 1
		Intents.signal("ItemViewed", tab) -- analytics
		render()
	end)
	nextButton.Size = UDim2.fromOffset(44, HEADER_HEIGHT)
	nextButton.LayoutOrder = 7
	local close = Widgets.button(header, "✕", 44, Widgets.DANGER, function()
		setOpen(false)
	end)
	close.Name = "Close"
	close.Size = UDim2.fromOffset(44, HEADER_HEIGHT)
	close.LayoutOrder = 8

	tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.BackgroundTransparency = 1
	tabRow.Size = UDim2.new(1, 0, 0, TAB_HEIGHT)
	tabRow.LayoutOrder = 2
	tabRow.Parent = panel
	local tabGrid = Instance.new("UIGridLayout")
	tabGrid.CellSize = UDim2.new(1 / #TABS, -4, 0, TAB_HEIGHT)
	tabGrid.CellPadding = UDim2.fromOffset(4, 0)
	tabGrid.SortOrder = Enum.SortOrder.LayoutOrder
	tabGrid.Parent = tabRow
	for i, t in TABS do
		local b = Widgets.button(tabRow, t.icon .. "\n" .. t.label, 0, Widgets.BUTTON_OFF, function()
			tab, page = t.id, 1
			Intents.signal("ItemViewed", tab) -- analytics
			render()
		end)
		b.Name = "Tab_" .. t.id
		b.TextSize = 12
		b.LayoutOrder = i
	end

	content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + TAB_HEIGHT + FOOTER_HEIGHT + 18))
	content.LayoutOrder = 3
	content.Parent = panel

	footer = Widgets.label(panel, "", 12, FOOTER_HEIGHT)
	footer.Name = "Footer"
	footer.TextColor3 = OFF_TEXT
	footer.LayoutOrder = 4

	offerPanel = Widgets.panel(gui, 400)
	offerPanel.Name = "StarterOffer"
	offerPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	offerPanel.Position = UDim2.fromScale(0.5, 0.5)
	offerPanel.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ShopState.onChange(function(offer: boolean)
		if offer then
			showStarterOffer()
		elseif offerPanel.Visible and ShopState.owns("starter") then
			offerPanel.Visible = false
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
end

return ShopUI
