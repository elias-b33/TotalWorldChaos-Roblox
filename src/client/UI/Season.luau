--!strict
-- The season pass screen (docs/MONETIZATION.md 6), phone first: the free track above the premium one, eight tiers a
-- page, each reward with its picture and a Claim button once reached (and, on the premium track, with the pass). The
-- header has your tier and season XP bar and the days left; the footer the pass and the pass bundle (Robux, only
-- outside a match like every purchase), the "pass rewards are exclusive" label shown before buying, and Claim all.
-- Opens from the 🎟 button in the Lobby, the Results screen and the shop's Offers tab. No single tier skips are sold.
-- No pressure (section 10): the days left are a fact, not a countdown, and nothing pops up on its own.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Config = require(Shared.Config)
local Season = require(Shared.Sim.Season)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local ProfileState = require(Client.ProfileState)
local SeasonState = require(Client.SeasonState)
local ShopState = require(Client.ShopState)
local Shop = require(script.Parent.Shop)
local Widgets = require(script.Parent.Widgets)

local ROBUX = utf8.char(0xE002) -- Roblox's Robux icon in every Roblox font
local GLORY = "🏅"
local TIERS_PER_PAGE = 8
local BUTTON_SIZE = 52
local HEADER_HEIGHT = 40
local FOOTER_HEIGHT = 44
local TIER_HEADER = 18
local LABEL_WIDTH = 64
local GAP = 4
local CARD = Color3.fromRGB(32, 35, 50)
local EMPTY = Color3.fromRGB(24, 26, 38)
local GOLD = Color3.fromRGB(242, 193, 78)
local OFF_TEXT = Color3.fromRGB(150, 152, 165)
local BAR_BACK = Color3.fromRGB(50, 54, 70)
local PREMIUM = Color3.fromRGB(120, 70, 160)
local DEFAULT_COLOR = 1 -- previews use your nation's colour, or red before you have one

local RARITY_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(190, 194, 205),
	Rare = Color3.fromRGB(90, 160, 255),
	Epic = Color3.fromRGB(190, 110, 255),
	Legendary = Color3.fromRGB(255, 170, 60),
}

local SeasonUI = {}

local gui: ScreenGui
local openButton: TextButton
local badge: TextLabel
local panel: Frame
local titleLabel: TextLabel
local tierLabel: TextLabel
local tierFill: Frame
local daysLabel: TextLabel
local pageLabel: TextLabel
local track: Frame
local footer: Frame
local page = 1
local toast: (string) -> () = function(_text: string) end

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

local function myColor(): number
	local me = ClientState.nation(ClientState.myNation())
	return if me then me.colorIndex else DEFAULT_COLOR
end

local function centred(parent: Instance, text: string, size: number, height: number, color: Color3?): TextLabel
	local l = Widgets.label(parent, text, size, height)
	l.TextXAlignment = Enum.TextXAlignment.Center
	if color then
		l.TextColor3 = color
	end
	return l
end

local function pages(): number
	return math.ceil((Config.Season.Tiers + 1) / TIERS_PER_PAGE) -- the last column is the bonus reward
end

-- A reward's short name for its cell.
local function rewardName(r: Types.SeasonReward): string
	if r.item then
		local item = Catalogue.item(r.item)
		return if item then item.name else r.item
	elseif r.glory then
		return formatNumber(r.glory) .. " Glory"
	elseif r.title then
		return "“" .. r.title .. "”"
	end
	return "Season badge"
end

-- A reward's little picture: the cosmetic as the shop draws it, or an icon.
local function preview(parent: Instance, r: Types.SeasonReward)
	local holder = Instance.new("Frame")
	holder.Name = "Preview"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, 40)
	holder.LayoutOrder = 1
	holder.Parent = parent
	local item = if r.item then Catalogue.item(r.item) else nil
	local color = myColor()
	local thing: GuiObject
	if item and item.slot == "Flag" then
		thing = Cosmetics.flagLabel(holder, item.id, color, UDim2.fromOffset(48, 36))
	elseif item and item.slot == "Token" then
		thing = Cosmetics.tokenLabel(holder, item.id, color, UDim2.fromOffset(36, 36))
	elseif item and item.slot == "Border" then
		thing = Cosmetics.swatchLabel(holder, item.art, "default", color, UDim2.fromOffset(54, 36))
	elseif item and item.slot == "Shades" then
		thing = Cosmetics.swatchLabel(holder, "solid", item.art, color, UDim2.fromOffset(54, 36))
	elseif item and item.slot == "PowerFx" then
		thing = Cosmetics.effectLabel(holder, item.id, UDim2.fromOffset(48, 36))
	elseif item and item.slot == "Theme" then
		thing = Cosmetics.themeLabel(holder, item.id, UDim2.fromOffset(72, 36))
	elseif item and item.slot == "Frame" then
		local l = centred(holder, "Name", 12, 22)
		l.Size = UDim2.fromOffset(64, 22)
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
	else
		local icon = if item
			then string.split(item.art, " ")[1]
			elseif r.glory then GLORY
			elseif r.title then "🏷"
			else "🎖"
		local l = centred(holder, icon, 26, 36)
		l.Size = UDim2.fromOffset(60, 36)
		thing = l
	end
	thing.AnchorPoint = Vector2.new(0.5, 0.5)
	thing.Position = UDim2.fromScale(0.5, 0.5)
end

local function cellButton(parent: Instance, text: string, color: Color3, onPress: () -> ()): TextButton
	local b = Widgets.button(parent, text, 0, color, onPress)
	b.Name = "Action"
	b.Size = UDim2.new(1, 0, 0, 30)
	b.TextSize = 13
	b.LayoutOrder = 3
	return b
end

local function stateButton(parent: Instance, text: string)
	local b = cellButton(parent, text, Widgets.BUTTON_OFF, function() end)
	b.AutoButtonColor = false
	b.TextColor3 = OFF_TEXT
end

-- One reward cell: picture, name and Claim / ✅ / 🔒.
local function rewardCell(
	parent: Instance,
	view: Types.SeasonView,
	tier: number,
	which: Types.SeasonTrack,
	order: number
)
	local def = Season.def(view.id)
	local rewards = if def then Season.rewards(def, tier, which) else {}
	local cell = Instance.new("Frame")
	cell.Name = string.format("Reward_%s%d", if which == "Free" then "F" else "P", tier)
	cell.BackgroundColor3 = if #rewards > 0 then CARD else EMPTY
	cell.LayoutOrder = order
	cell.Parent = parent
	Widgets.corner(cell, 8)
	if #rewards == 0 then
		return
	end
	Widgets.padding(cell, 4)
	local list = Widgets.list(cell, false, 2)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local first = rewards[1]
	local item = if first.item then Catalogue.item(first.item) else nil
	local stroke = Instance.new("UIStroke")
	stroke.Color = if item
		then RARITY_COLORS[item.rarity] or Widgets.BUTTON_OFF
		elseif first.glory then GOLD
		else PREMIUM
	stroke.Thickness = 1
	stroke.Parent = cell
	preview(cell, first)
	local name = rewardName(first) .. (if #rewards > 1 then string.format(" +%d", #rewards - 1) else "")
	local label = centred(cell, name, 12, 28)
	label.LayoutOrder = 2
	label.TextTruncate = Enum.TextTruncate.AtEnd
	local key = Season.key(tier, which)
	if SeasonState.claimed(key) then
		stateButton(cell, "✅")
	elseif tier > view.tier then
		stateButton(cell, "🔒")
	elseif which == "Premium" and not view.premium then
		stateButton(cell, "🎟 Pass")
	else
		cellButton(cell, "Claim", Widgets.GOOD, function()
			Intents.claimSeason(tier, which)
		end)
	end
end

-- The column after the last tier: 100 Glory per 2,400 XP past it, repeatable.
local function bonusColumn(parent: Instance, view: Types.SeasonView, order: number)
	local column = Instance.new("Frame")
	column.Name = "Bonus"
	column.BackgroundTransparency = 1
	column.LayoutOrder = order
	column.Parent = parent
	Widgets.list(column, false, GAP)
	local head = centred(column, "⭐ Bonus", 12, TIER_HEADER, GOLD)
	head.LayoutOrder = 0
	local cell = Instance.new("Frame")
	cell.Name = "Reward_Bonus"
	cell.BackgroundColor3 = CARD
	cell.Size = UDim2.new(1, 0, 1, -(TIER_HEADER + GAP))
	cell.LayoutOrder = 1
	cell.Parent = column
	Widgets.corner(cell, 8)
	Widgets.padding(cell, 4)
	Widgets.list(cell, false, 4).HorizontalAlignment = Enum.HorizontalAlignment.Center
	centred(cell, GLORY, 26, 40).LayoutOrder = 1
	local text = string.format(
		"%d Glory\nevery %s XP\nafter tier %d",
		Config.Season.BonusGlory,
		formatNumber(Config.Season.BonusXp),
		Config.Season.Tiers
	)
	centred(cell, text, 12, 64, OFF_TEXT).LayoutOrder = 2
	if view.bonusReady > 0 then
		cellButton(cell, string.format("Claim %d", view.bonusReady), Widgets.GOOD, Intents.claimAllSeason)
	else
		stateButton(cell, if view.tier >= Config.Season.Tiers then "⏳" else "🔒")
	end
end

-- The page of tiers: a header row of tier numbers, the free track, the premium track.
local function renderTrack(view: Types.SeasonView)
	Widgets.clear(track)
	local labels = Instance.new("Frame")
	labels.Name = "Labels"
	labels.BackgroundTransparency = 1
	labels.Size = UDim2.new(0, LABEL_WIDTH, 1, 0)
	labels.Parent = track
	-- two rows under the tier numbers, each half of what is left
	local half = (TIER_HEADER + 2 * GAP) // 2
	local rowSize = UDim2.new(1, 0, 0.5, -half)
	for i, info in { { "Free", Color3.fromRGB(90, 200, 120) }, { "🎟 Pass", GOLD } } do
		local l = centred(labels, info[1] :: string, 13, 0, info[2] :: Color3)
		l.Position = if i == 1 then UDim2.fromOffset(0, TIER_HEADER + GAP) else UDim2.new(0, 0, 0.5, half)
		l.Size = rowSize
	end
	local columns = Instance.new("Frame")
	columns.Name = "Tiers"
	columns.BackgroundTransparency = 1
	columns.Position = UDim2.fromOffset(LABEL_WIDTH + GAP, 0)
	columns.Size = UDim2.new(1, -(LABEL_WIDTH + GAP), 1, 0)
	columns.Parent = track
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / TIERS_PER_PAGE, -GAP, 1, 0)
	grid.CellPadding = UDim2.fromOffset(GAP, 0)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = columns
	local firstTier = (page - 1) * TIERS_PER_PAGE + 1
	for tier = firstTier, math.min(view.maxTier, firstTier + TIERS_PER_PAGE - 1) do
		local column = Instance.new("Frame")
		column.Name = "Tier" .. tier
		column.BackgroundTransparency = 1
		column.LayoutOrder = tier
		column.Parent = columns
		local list = Widgets.list(column, false, GAP)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		local reached = tier <= view.tier
		local head = centred(column, tostring(tier), 13, TIER_HEADER, if reached then GOLD else OFF_TEXT)
		head.LayoutOrder = 0
		if tier == view.tier then
			head.Text = "▶ " .. tier
		end
		for i, which in Season.TRACKS do
			rewardCell(column, view, tier, which, i)
		end
		for _, child in column:GetChildren() do
			if child:IsA("Frame") then
				child.Size = rowSize
			end
		end
	end
	if firstTier + TIERS_PER_PAGE - 1 > view.maxTier then
		bonusColumn(columns, view, view.maxTier + 1)
	end
end

local function renderFooter(view: Types.SeasonView)
	Widgets.clear(footer)
	local robuxOpen = ShopState.view() ~= nil and (ShopState.view() :: Types.ShopView).robuxOpen
	if view.premium then
		local l = Widgets.label(
			footer,
			if view.bundle then "🎟 Premium pass + 10 tiers ✅" else "🎟 Premium pass ✅",
			14,
			FOOTER_HEIGHT
		)
		l.Size = UDim2.fromOffset(230, FOOTER_HEIGHT)
		l.TextColor3 = GOLD
		l.LayoutOrder = 1
	else
		for i, info in
			{
				{ "season_pass", Config.Season.PassRobux, "🎟 Pass" },
				{ "season_bundle", Config.Season.BundleRobux, "🎟 Pass +10 tiers" },
			}
		do
			local id, listPrice, text = info[1] :: string, info[2] :: number, info[3] :: string
			local price = Shop.robuxPrice(id, listPrice)
			local b = Widgets.button(
				footer,
				string.format("%s  %s %s", text, ROBUX, formatNumber(price)),
				if i == 1 then 150 else 200,
				if robuxOpen then PREMIUM else Widgets.BUTTON_OFF,
				function()
					if not robuxOpen then
						toast("🛒 Robux purchases open after the match")
						return
					end
					Intents.buy(id, "Robux")
				end
			)
			b.Name = if i == 1 then "BuyPass" else "BuyBundle"
			b.TextSize = 14
			b.LayoutOrder = i
		end
	end
	local note = Widgets.label(
		footer,
		if view.premium
			then "Pass rewards are only in this season and never sold later.\nTiers are earned by playing: no tier skips are sold."
			else "Pass rewards are only in this season,\nnever sold later. Buying late opens all\nyou reached. No tier skips.",
		11,
		FOOTER_HEIGHT
	)
	note.Name = "PassNote"
	note.Size = UDim2.new(1, -(if view.premium then 230 else 358) - 160 - 3 * 8, 0, FOOTER_HEIGHT)
	note.TextColor3 = OFF_TEXT
	note.LayoutOrder = 3
	local claimAll = Widgets.button(
		footer,
		if view.ready > 0 then string.format("Claim all (%d)", view.ready) else "Claim all",
		160,
		if view.ready > 0 then Widgets.GOOD else Widgets.BUTTON_OFF,
		Intents.claimAllSeason
	)
	claimAll.Name = "ClaimAll"
	claimAll.TextSize = 14
	claimAll.LayoutOrder = 4
end

local function render()
	if panel == nil or not panel.Visible then
		return
	end
	local view = SeasonState.view()
	Widgets.clear(track)
	Widgets.clear(footer)
	if view == nil or view.id == "" then
		titleLabel.Text = "🎟 Season pass"
		tierLabel.Text = ""
		tierFill.Size = UDim2.fromScale(0, 1)
		daysLabel.Text = ""
		pageLabel.Text = ""
		local text = "⏳ Loading the season…"
		if view and view.nextStartDay then
			local t = os.date("!*t", view.nextStartDay * 86400) :: any
			text = string.format("🎟 The next season starts on %04d-%02d-%02d", t.year, t.month, t.day)
		elseif view then
			text = "🎟 The next season is coming soon"
		end
		Widgets.label(track, text, 16, 30)
		return
	end
	page = math.clamp(page, 1, pages())
	titleLabel.Text = "🎟 " .. view.name
	tierLabel.Text =
		string.format("Tier %d · %s/%s XP", view.tier, formatNumber(view.xpIntoTier), formatNumber(view.xpForTier))
	tierFill.Size = UDim2.fromScale(math.clamp(view.xpIntoTier / math.max(1, view.xpForTier), 0, 1), 1)
	daysLabel.Text = string.format("📅 %d day%s left", view.daysLeft, if view.daysLeft == 1 then "" else "s")
	pageLabel.Text = string.format("%d/%d", page, pages())
	renderTrack(view)
	renderFooter(view)
end

local function refreshButton()
	-- the map vote only: during the draft the bottom row holds the "✔ Pick" button
	local phase = LobbyState.phase()
	local inLobby = phase == "Lobby" or (phase ~= "Pick" and ClientState.snapshot() == nil)
	openButton.Visible = inLobby and not panel.Visible and SeasonState.view() ~= nil
	local ready = SeasonState.readyCount()
	badge.Visible = ready > 0
	badge.Text = tostring(ready)
end

local function setOpen(open: boolean)
	if open and not panel.Visible then
		local view = SeasonState.view()
		-- start on the page with the first reward to claim, else the current tier
		local tier = if view then math.max(1, view.tier) else 1
		if view and view.id ~= "" then
			local def = Season.def(view.id)
			for t = 1, view.tier do
				local ready = false
				for _, which in Season.TRACKS do
					local key = Season.key(t, which)
					local has = def ~= nil and #Season.rewards(def, t, which) > 0
					local allowed = which == "Free" or view.premium
					ready = ready or (has and allowed and not SeasonState.claimed(key))
				end
				if ready then
					tier = t
					break
				end
			end
		end
		page = (tier - 1) // TIERS_PER_PAGE + 1
		Intents.seasonViewed() -- analytics: SeasonPass pass_viewed
	end
	panel.Visible = open
	refreshButton()
	if open then
		render()
	end
end

function SeasonUI.open()
	setOpen(true)
end

function SeasonUI.close()
	setOpen(false)
end

function SeasonUI.isOpen(): boolean
	return panel.Visible
end

-- "🎟 Season · tier 3", or with the rewards waiting (for buttons in other panels).
function SeasonUI.buttonText(): string
	local view = SeasonState.view()
	if view == nil or view.id == "" then
		return "🎟 Season"
	end
	if view.ready > 0 then
		return string.format("🎟 Tier %d · %d ready", view.tier, view.ready)
	end
	return string.format("🎟 Season · tier %d", view.tier)
end

function SeasonUI.init(showToast: (string) -> ())
	toast = showToast
	gui = Widgets.screen("Season", 32) -- above the shop (30) and the quests (31): it opens from the shop's Offers tab
	-- the Lobby's 🎟 button, next to 🛒 and 📜, in a screen under the full-screen panels (like the 📜 button)
	local buttonGui = Widgets.screen("SeasonButton", 29)

	openButton = Instance.new("TextButton")
	openButton.Name = "SeasonButton"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 12 + 2 * (BUTTON_SIZE + 10), 1, -12)
	openButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	openButton.BackgroundColor3 = PREMIUM
	openButton.Font = Enum.Font.GothamBold
	openButton.TextSize = 24
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "🎟"
	openButton.Visible = false
	openButton.Parent = buttonGui
	Widgets.corner(openButton, BUTTON_SIZE // 2)
	openButton.Activated:Connect(function()
		setOpen(true)
	end)
	badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 4, 0, -4)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = Widgets.DANGER
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 12
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Visible = false
	badge.Parent = openButton
	Widgets.corner(badge, 10)

	panel = Instance.new("Frame")
	panel.Name = "SeasonPanel"
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
	Widgets.list(header, true, 6)
	titleLabel = Widgets.label(header, "", 17, HEADER_HEIGHT)
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromOffset(250, HEADER_HEIGHT)
	titleLabel.TextWrapped = false
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.LayoutOrder = 1
	local tierBox = Instance.new("Frame")
	tierBox.Name = "TierBox"
	tierBox.BackgroundTransparency = 1
	tierBox.Size = UDim2.fromOffset(190, HEADER_HEIGHT)
	tierBox.LayoutOrder = 2
	tierBox.Parent = header
	tierLabel = Widgets.label(tierBox, "", 13, 22)
	tierLabel.Name = "Tier"
	tierLabel.TextColor3 = GOLD
	local bar = Instance.new("Frame")
	bar.Name = "TierBar"
	bar.Position = UDim2.fromOffset(0, 26)
	bar.Size = UDim2.new(1, 0, 0, 8)
	bar.BackgroundColor3 = BAR_BACK
	bar.BorderSizePixel = 0
	bar.Parent = tierBox
	Widgets.corner(bar, 4)
	tierFill = Instance.new("Frame")
	tierFill.Name = "Fill"
	tierFill.Size = UDim2.fromScale(0, 1)
	tierFill.BackgroundColor3 = GOLD
	tierFill.BorderSizePixel = 0
	tierFill.Parent = bar
	Widgets.corner(tierFill, 4)
	daysLabel = Widgets.label(header, "", 13, HEADER_HEIGHT)
	daysLabel.Name = "Days"
	daysLabel.Size = UDim2.fromOffset(110, HEADER_HEIGHT)
	daysLabel.TextColor3 = OFF_TEXT
	daysLabel.LayoutOrder = 3
	local prev = Widgets.button(header, "◀", 44, Widgets.BUTTON_OFF, function()
		page = math.max(1, page - 1)
		render()
	end)
	prev.Name = "Prev"
	prev.Size = UDim2.fromOffset(44, HEADER_HEIGHT)
	prev.LayoutOrder = 4
	pageLabel = Widgets.label(header, "", 15, HEADER_HEIGHT)
	pageLabel.Size = UDim2.fromOffset(40, HEADER_HEIGHT)
	pageLabel.TextXAlignment = Enum.TextXAlignment.Center
	pageLabel.LayoutOrder = 5
	local nextButton = Widgets.button(header, "▶", 44, Widgets.BUTTON_OFF, function()
		page = math.min(pages(), page + 1)
		render()
	end)
	nextButton.Name = "Next"
	nextButton.Size = UDim2.fromOffset(44, HEADER_HEIGHT)
	nextButton.LayoutOrder = 6
	local close = Widgets.button(header, "✕", 44, Widgets.DANGER, function()
		setOpen(false)
	end)
	close.Name = "Close"
	close.Size = UDim2.fromOffset(44, HEADER_HEIGHT)
	close.LayoutOrder = 7

	track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + FOOTER_HEIGHT + 12))
	track.LayoutOrder = 2
	track.Parent = panel

	footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT)
	footer.LayoutOrder = 3
	footer.Parent = panel
	Widgets.list(footer, true, 8)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	buttonGui.Parent = gui.Parent

	Shop.setSeasonScreen(function()
		Shop.close()
		setOpen(true)
	end)
	SeasonState.onChange(function()
		refreshButton()
		render()
	end)
	ShopState.onChange(function(_offer: boolean)
		render() -- Robux purchases open or close
	end)
	ProfileState.onChange(render)
	ClientState.onReset(refreshButton)
	LobbyState.onChange(refreshButton)
end

return SeasonUI
