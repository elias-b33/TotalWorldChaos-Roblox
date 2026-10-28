--!strict
-- The season pass screen (docs/MONETIZATION.md 6), phone first: the free track above the premium one, eight tiers a
-- page, each reward with its picture and a Claim button once reached (and, on the premium track, with the pass); a
-- claimable reward's whole cell is the button. The header has the season, your tier and season XP bar and the days
-- left; the footer the pass and the pass bundle (Robux, only outside a match like every purchase), the "pass rewards
-- are only in this season" label shown before buying, and Claim all.
-- Opens from the ticket button in the Lobby, the Results screen and the shop's Offers tab. No single tier skips are
-- sold. No pressure (section 10): the days left are a fact, not a countdown, and nothing pops up on its own.
-- Built from the UI kit (docs/DESIGN.md "UI style"); the panel's contents are built when it opens and dropped when
-- it closes.

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

local Theme = Widgets.Theme
local ROBUX = utf8.char(0xE002) -- Roblox's Robux icon in every Roblox font
local TIERS_PER_PAGE = 8
local BAR = Widgets.BUTTON_HEIGHT -- the header and the footer
local TIER_HEADER = 18
local LABEL_WIDTH = 52 -- "Free" and "Pass" left of the tracks
local GAP = Theme.space.xs
local HALF = (TIER_HEADER + 2 * GAP) // 2 -- each track row is half of what is left under the tier numbers, less this
local TIER_BOX = 172
local PREVIEW_HEIGHT = 30
local NAME_HEIGHT = 34 -- two 14 px lines
local PILL = 30 -- a cell's Claim button or state tag (the whole claimable cell is the touch target)
local PASS_WIDTH = 128
local BUNDLE_WIDTH = 188
local STATUS_WIDTH = 220
local CLAIM_WIDTH = 108
local SECONDS_PER_DAY = 86400
local DEFAULT_COLOR = 1 -- previews use your nation's colour, or red before you have one

-- The open panel's pieces (nil while the screen is closed: its contents are dropped).
type Refs = {
	title: TextLabel,
	tier: TextLabel,
	tierBar: Frame,
	days: TextLabel,
	pager: Frame,
	page: TextLabel,
	track: Frame,
	footer: Frame,
}

local SeasonUI = {}

local gui: ScreenGui
local openButton: TextButton
local badge: TextLabel
local panel: Frame
local ui: Refs? = nil
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
	l.TextTruncate = Enum.TextTruncate.AtEnd
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

-- A reward's little picture: the cosmetic as the shop draws it, or a pixel icon.
local function preview(parent: Instance, r: Types.SeasonReward)
	local holder = Instance.new("Frame")
	holder.Name = "Preview"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, 0, 0, PREVIEW_HEIGHT)
	holder.Parent = parent
	local item = if r.item then Catalogue.item(r.item) else nil
	local color = myColor()
	local thing: GuiObject
	if item and item.slot == "Flag" then
		thing = Cosmetics.flagLabel(holder, item.id, color, UDim2.fromOffset(40, 30))
	elseif item and item.slot == "Token" then
		thing = Cosmetics.tokenLabel(holder, item.id, color, UDim2.fromOffset(30, 30))
	elseif item and item.slot == "Border" then
		thing = Cosmetics.swatchLabel(holder, item.art, "default", color, UDim2.fromOffset(45, 30))
	elseif item and item.slot == "Shades" then
		thing = Cosmetics.swatchLabel(holder, "solid", item.art, color, UDim2.fromOffset(45, 30))
	elseif item and item.slot == "PowerFx" then
		thing = Cosmetics.effectLabel(holder, item.id, UDim2.fromOffset(40, 30))
	elseif item and item.slot == "Theme" then
		thing = Cosmetics.themeLabel(holder, item.id, UDim2.fromOffset(60, 30))
	elseif item and item.slot == "Frame" then
		local l = centred(holder, "Name", Theme.text.small, 22)
		l.FontFace = Theme.font.display
		l.Size = UDim2.new(1, -Theme.space.xs, 0, 22)
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
	elseif item then -- emotes and victory animations are emoji over a capital: their first frame
		thing = centred(holder, string.split(item.art, " ")[1], 24, PREVIEW_HEIGHT)
	else
		thing = Widgets.icon(holder, if r.glory then "medal" elseif r.title then "crown" else "star", 24)
	end
	thing.AnchorPoint = Vector2.new(0.5, 0.5)
	thing.Position = UDim2.fromScale(0.5, 0.5)
end

-- A cell's state at its bottom: a Claim button, or a tag (claimed, locked, needs the pass). Named "Action".
local function action(cell: GuiObject, icon: string?, text: string?, onClaim: (() -> ())?)
	local a: GuiObject
	if onClaim then
		local b = Widgets.fitButton(cell, nil, text or "Claim", Widgets.GOOD, onClaim)
		b.TextSize = Theme.text.small
		b.Size = UDim2.fromOffset(0, PILL)
		a = b
	else
		a = Widgets.tag(cell, icon or "lock", text, PILL)
	end
	a.Name = "Action"
	a.AnchorPoint = Vector2.new(0.5, 1)
	a.Position = UDim2.fromScale(0.5, 1)
end

-- One reward cell: picture, name and Claim / claimed / locked / needs the pass. A claimable cell is a button.
local function rewardCell(
	column: Frame,
	view: Types.SeasonView,
	tier: number,
	which: Types.SeasonTrack,
	position: UDim2
)
	local def = Season.def(view.id)
	local rewards = if def then Season.rewards(def, tier, which) else {}
	local name = string.format("Reward_%s%d", if which == "Free" then "F" else "P", tier)
	local size = UDim2.new(1, 0, 0.5, -HALF)
	if #rewards == 0 then -- nothing on this track at this tier: an empty slot
		local slot = Instance.new("Frame")
		slot.Name = name
		slot.BackgroundColor3 = Theme.color.navyDeep
		slot.BackgroundTransparency = 0.4
		slot.BorderSizePixel = 0
		slot.Position = position
		slot.Size = size
		slot.Parent = column
		Widgets.corner(slot, Theme.radius.m)
		return
	end
	local key = Season.key(tier, which)
	local claimed = SeasonState.claimed(key)
	local locked = tier > view.tier
	local needsPass = which == "Premium" and not view.premium
	local function claim()
		Intents.claimSeason(tier, which)
	end
	local cell: GuiObject
	if not claimed and not locked and not needsPass then
		cell = Widgets.button(column, "", 0, Theme.color.navyRaised, claim)
	else
		local card = Widgets.card(column)
		card.AutomaticSize = Enum.AutomaticSize.None
		cell = card
	end
	cell.Name = name
	cell.Position = position
	cell.Size = size
	local pad = cell:FindFirstChildOfClass("UIPadding") or Widgets.padding(cell, GAP)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, GAP), UDim.new(0, GAP)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, GAP), UDim.new(0, GAP)
	local first = rewards[1]
	local item = if first.item then Catalogue.item(first.item) else nil
	local stroke = cell:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = if item
			then Theme.rarity[item.rarity] or Theme.color.ink
			elseif first.glory then Theme.color.gold
			else Theme.color.special
	end
	preview(cell, first)
	local label = Widgets.label(
		cell,
		rewardName(first) .. (if #rewards > 1 then string.format(" +%d", #rewards - 1) else ""),
		Theme.text.small,
		NAME_HEIGHT
	)
	label.Name = "Name"
	label.Position = UDim2.fromOffset(0, PREVIEW_HEIGHT + 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	if claimed then
		action(cell, "check", nil, nil)
	elseif locked then
		action(cell, "lock", nil, nil)
	elseif needsPass then
		action(cell, "ticket", "Pass", nil)
	else
		action(cell, nil, "Claim", claim)
	end
end

-- The column after the last tier: 100 Glory per 2,400 XP past it, repeatable.
local function bonusColumn(parent: Instance, view: Types.SeasonView, order: number)
	local column = Instance.new("Frame")
	column.Name = "Bonus"
	column.BackgroundTransparency = 1
	column.LayoutOrder = order
	column.Parent = parent
	local head = centred(column, "Bonus", Theme.text.small, TIER_HEADER, Theme.color.gold)
	head.FontFace = Theme.font.display
	head.Size = UDim2.fromOffset(0, TIER_HEADER)
	head.AutomaticSize = Enum.AutomaticSize.X
	head.AnchorPoint = Vector2.new(0.5, 0)
	head.Position = UDim2.fromScale(0.5, 0)
	Widgets.leadIcon(head, "star", 14, 2)
	local cell = Widgets.card(column)
	cell.Name = "Reward_Bonus"
	cell.AutomaticSize = Enum.AutomaticSize.None
	cell.Position = UDim2.fromOffset(0, TIER_HEADER + GAP)
	cell.Size = UDim2.new(1, 0, 1, -(TIER_HEADER + GAP))
	local outline = cell:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = Theme.color.gold
	end
	local pad = cell:FindFirstChildOfClass("UIPadding")
	if pad then
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, GAP), UDim.new(0, GAP)
	end
	local medal = Widgets.icon(cell, "medal", Theme.icon.medium)
	medal.AnchorPoint = Vector2.new(0.5, 0)
	medal.Position = UDim2.fromScale(0.5, 0)
	local text = Widgets.label(
		cell,
		string.format(
			"%d Glory every %s XP after tier %d",
			Config.Season.BonusGlory,
			formatNumber(Config.Season.BonusXp),
			Config.Season.Tiers
		),
		Theme.text.small,
		5 * 17
	)
	text.Name = "Text"
	text.FontFace = Theme.font.bodyLight
	text.TextColor3 = Theme.color.textDim
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Position = UDim2.fromOffset(0, Theme.icon.medium + GAP)
	if view.bonusReady > 0 then
		action(cell, nil, string.format("Claim %d", view.bonusReady), Intents.claimAllSeason)
	else
		action(cell, if view.tier >= Config.Season.Tiers then "hourglass" else "lock", nil, nil)
	end
end

-- The page of tiers: a header row of tier numbers, the free track, the premium track.
local function renderTrack(track: Frame, view: Types.SeasonView)
	Widgets.clear(track)
	local labels = Instance.new("Frame")
	labels.Name = "Labels"
	labels.BackgroundTransparency = 1
	labels.Size = UDim2.new(0, LABEL_WIDTH, 1, 0)
	labels.Parent = track
	for i, info in { { "Free", Theme.color.good }, { "Pass", Theme.color.gold } } do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = if i == 1 then UDim2.fromOffset(0, TIER_HEADER + GAP) else UDim2.new(0, 0, 0.5, HALF)
		row.Size = UDim2.new(1, 0, 0.5, -HALF)
		row.Parent = labels
		local l = centred(row, info[1] :: string, Theme.text.body, 20, info[2] :: Color3)
		l.FontFace = Theme.font.display
		l.AnchorPoint = Vector2.new(0, 0.5)
		l.Position = UDim2.fromScale(0, 0.5)
		if i == 2 then -- the premium track: the ticket above its name
			l.Position = UDim2.new(0, 0, 0.5, 12)
			local icon = Widgets.icon(row, "ticket", Theme.icon.small)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.new(0.5, 0, 0.5, -10)
		end
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
		local reached = tier <= view.tier
		local head = centred(
			column,
			tostring(tier),
			Theme.text.small,
			TIER_HEADER,
			if reached then Theme.color.gold else Theme.color.textDim
		)
		head.Name = "Head"
		head.FontFace = Theme.font.display
		if tier == view.tier then -- your tier: a gold pill
			head.BackgroundColor3 = Theme.color.gold
			head.BackgroundTransparency = 0
			head.TextColor3 = Theme.color.textDark
			Widgets.corner(head, Theme.radius.s)
		end
		rewardCell(column, view, tier, "Free", UDim2.fromOffset(0, TIER_HEADER + GAP))
		rewardCell(column, view, tier, "Premium", UDim2.new(0, 0, 0.5, HALF))
	end
	if firstTier + TIERS_PER_PAGE - 1 > view.maxTier then
		bonusColumn(columns, view, view.maxTier + 1)
	end
end

local function renderFooter(footer: Frame, view: Types.SeasonView)
	Widgets.clear(footer)
	local shop = ShopState.view()
	local robuxOpen = shop ~= nil and shop.robuxOpen
	local left: number
	if view.premium then
		local status = Widgets.chip(
			footer,
			"ticket",
			if view.bundle
				then string.format("Pass + %d tiers active", Config.Season.BundleTiers)
				else "Premium pass active",
			STATUS_WIDTH,
			BAR
		)
		status.Name = "PassStatus"
		status.TextSize = Theme.text.small
		status.TextColor3 = Theme.color.gold
		left = STATUS_WIDTH
	else
		local x = 0
		for i, info in
			{
				{ "season_pass", Config.Season.PassRobux, "Pass", PASS_WIDTH, "BuyPass" },
				{
					"season_bundle",
					Config.Season.BundleRobux,
					string.format("Pass +%d tiers", Config.Season.BundleTiers),
					BUNDLE_WIDTH,
					"BuyBundle",
				},
			}
		do
			local id, listPrice, text = info[1] :: string, info[2] :: number, info[3] :: string
			local width = info[4] :: number
			local price = Shop.robuxPrice(id, listPrice)
			local b = Widgets.iconTextButton(
				footer,
				"ticket",
				string.format("%s %s %s", text, ROBUX, formatNumber(price)),
				width,
				Widgets.SPECIAL,
				function()
					if not robuxOpen then
						toast("🛒 Robux purchases open after the match")
						return
					end
					Intents.buy(id, "Robux")
				end,
				info[5] :: string
			)
			b.TextSize = Theme.text.small
			b.TextWrapped = false
			b.Position = UDim2.fromOffset(x, 0)
			b.LayoutOrder = i
			if not robuxOpen then
				Widgets.setEnabled(b, false) -- purchases open in the Lobby, the draft and on Results
			end
			x += width + Theme.space.m
		end
		left = x - Theme.space.m
	end
	local note = Widgets.hint(
		footer,
		if view.premium
			then "Pass rewards are only in this season. Tiers come from playing: no tier skips."
			else "Pass rewards are only in this season. No tier skips.",
		Theme.text.small,
		BAR
	)
	note.Name = "PassNote"
	note.Position = UDim2.fromOffset(left + Theme.space.m, 0)
	note.Size = UDim2.new(1, -(left + CLAIM_WIDTH + 2 * Theme.space.m), 1, 0)
	note.TextTruncate = Enum.TextTruncate.AtEnd
	local claimAll = Widgets.button(
		footer,
		if view.ready > 0 then string.format("Claim all (%d)", view.ready) else "Claim all",
		CLAIM_WIDTH,
		Widgets.GOOD,
		Intents.claimAllSeason
	)
	claimAll.Name = "ClaimAll"
	claimAll.TextSize = Theme.text.small
	claimAll.AnchorPoint = Vector2.new(1, 0)
	claimAll.Position = UDim2.fromScale(1, 0)
	if view.ready == 0 then
		Widgets.setEnabled(claimAll, false)
	end
end

local function render()
	local r = ui
	if r == nil or not panel.Visible then
		return
	end
	local view = SeasonState.view()
	Widgets.clear(r.track)
	Widgets.clear(r.footer)
	if view == nil or view.id == "" then
		r.title.Text = "Season pass"
		r.tier.Text = ""
		Widgets.setProgress(r.tierBar, 0)
		r.days.Text = ""
		r.pager.Visible = false
		local text = "Loading the season…"
		if view and view.nextStartDay then
			local t = os.date("!*t", view.nextStartDay * SECONDS_PER_DAY) :: any
			text = string.format("The next season starts on %04d-%02d-%02d", t.year, t.month, t.day)
		elseif view then
			text = "The next season is coming soon"
		end
		local l = Widgets.label(r.track, text, Theme.text.body, 30)
		Widgets.leadIcon(l, if view then "calendar" else "hourglass", Theme.size.icon)
		return
	end
	page = math.clamp(page, 1, pages())
	r.title.Text = view.name
	r.tier.Text =
		string.format("Tier %d · %s/%s XP", view.tier, formatNumber(view.xpIntoTier), formatNumber(view.xpForTier))
	Widgets.setProgress(r.tierBar, view.xpIntoTier / math.max(1, view.xpForTier))
	r.days.Text = string.format("%d day%s left", view.daysLeft, if view.daysLeft == 1 then "" else "s")
	r.pager.Visible = true
	r.page.Text = string.format("%d/%d", page, pages())
	renderTrack(r.track, view)
	renderFooter(r.footer, view)
end

local function refreshButton()
	-- the map vote only: during the draft the bottom row holds the "Pick" button
	local phase = LobbyState.phase()
	local inLobby = phase == "Lobby" or (phase ~= "Pick" and ClientState.snapshot() == nil)
	openButton.Visible = inLobby and not panel.Visible and SeasonState.view() ~= nil
	Widgets.setCount(badge, SeasonState.readyCount())
end

local setOpen: (boolean) -> ()

-- The panel's contents, built when it opens: header (season, tier and XP bar, days left, pager, close), the page of
-- tiers and the footer.
local function build(): Refs
	-- the season's name on a title plate on the window's top edge, the close gem on its corner
	local _, title = Widgets.header(panel, "", "ticket", function()
		setOpen(false)
	end)
	local header = Instance.new("Frame")
	header.Name = "Info"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, BAR)
	header.LayoutOrder = 1
	header.Parent = panel
	local pager, pageLabel = Widgets.pager(header, function()
		page = math.max(1, page - 1)
		render()
	end, function()
		page = math.min(pages(), page + 1)
		render()
	end, "Prev", "Next")
	pager.AnchorPoint = Vector2.new(1, 0)
	pager.Position = UDim2.fromScale(1, 0)
	local right = pager.Size.X.Offset + Theme.space.m
	-- your tier: "Tier 6 · 300/1,200 XP", the bar, the days left
	local tierBox = Instance.new("Frame")
	tierBox.Name = "TierBox"
	tierBox.BackgroundTransparency = 1
	tierBox.AnchorPoint = Vector2.new(1, 0)
	tierBox.Position = UDim2.new(1, -right, 0, 0)
	tierBox.Size = UDim2.fromOffset(TIER_BOX, BAR)
	tierBox.Parent = header
	local tier = Widgets.label(tierBox, "", Theme.text.small, 16)
	tier.Name = "Tier"
	tier.FontFace = Theme.font.display
	tier.TextColor3 = Theme.color.gold
	tier.TextWrapped = false
	tier.TextTruncate = Enum.TextTruncate.AtEnd
	local bar = Widgets.progress(tierBox, nil, 8)
	bar.Name = "TierBar"
	bar.Position = UDim2.fromOffset(0, 19)
	local days = Widgets.hint(tierBox, "", Theme.text.small, 16)
	days.Name = "Days"
	days.Position = UDim2.fromOffset(0, 29)
	days.TextWrapped = false
	Widgets.leadIcon(days, "calendar", 14, Theme.space.xs)

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.Size = UDim2.new(1, 0, 1, -(2 * BAR + 3 * Theme.space.s)) -- three gaps: the header's too
	track.LayoutOrder = 2
	track.Parent = panel

	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, BAR)
	footer.LayoutOrder = 3
	footer.Parent = panel

	return {
		title = title,
		tier = tier,
		tierBar = bar,
		days = days,
		pager = pager,
		page = pageLabel,
		track = track,
		footer = footer,
	}
end

setOpen = function(open: boolean)
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
	if open and ui == nil then
		ui = build()
	elseif not open and ui ~= nil then
		Widgets.clear(panel) -- a closed screen keeps no cells or buttons (rebuilt when it opens)
		ui = nil
	end
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

-- "🎟 Season · tier 3", or with the rewards waiting (for buttons in other panels; the emoji becomes the ticket icon).
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
	-- the Lobby's ticket button, after the shop, quests and trophies, in a screen under the full-screen panels
	local buttonGui = Widgets.screen("SeasonButton", 29)

	openButton = Widgets.cornerButton(buttonGui, 3, "ticket", "SeasonButton", Theme.color.special, function()
		setOpen(true)
	end)
	openButton.Visible = false
	badge = Widgets.countBadge(openButton)

	panel = Widgets.window(gui, "SeasonPanel")
	Widgets.list(panel, false, Theme.space.s)

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	Widgets.fitScreen(buttonGui)
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
