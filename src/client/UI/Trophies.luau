--!strict
-- The Trophies screen (docs/MONETIZATION.md 5.6, 7.3), phone first: your 30 achievements with progress bars and
-- rewards (and the title you wear), and the weekly, friends and global level leaderboards. Opens from the trophy
-- button in the Lobby (after the cart and the scroll) and from the Results screen. Boards show display names only.
-- Built from the UI kit (docs/UI_DIRECTION.md 7.14): achievements as raised plates like quest rows (the ones a
-- match just unlocked glow gold), board rows as raised plates with your own marked in gold. The panel's contents
-- are built when it opens and dropped when it closes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Catalogue = require(ReplicatedStorage.Shared.Catalogue)
local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local ShopState = require(Client.ShopState)
local TrophyState = require(Client.TrophyState)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local GLORY = "🏅"
local LOBBY_SLOT = 2 -- the third round button in the Lobby's bottom-left row (after the cart and the scroll)
local BAR = Widgets.BUTTON_HEIGHT -- the header and the controls row
local GAP = Theme.space.xs
local COLUMNS = 3 -- achievement cards per row
local CARD_ROWS = 3 -- nine to a page: room for three lines inside a raised plate's rim on a phone
local BOARD_COLUMNS = 2
local BOARD_ROWS = 8
local ROW_HEIGHT = 26
local RANK_WIDTH = 34
local VALUE_WIDTH = 90
local TITLE_BUTTON = 184
local BAR_SHARE = 0.3 -- of an achievement card: its progress bar
local GLORY_WIDTH = 58 -- an achievement's "+500" Glory, before its title or item
local BAR_HEIGHT = 12 -- an achievement's progress bar
local MARKER = 3 -- the gold marker on your board row's left

type Tab = "Achievements" | "Weekly" | "Friends" | "Level"
local TABS: { Tab } = { "Achievements", "Weekly", "Friends", "Level" }
local TAB_ICONS: { [Tab]: string } =
	{ Achievements = "trophy", Weekly = "calendar", Friends = "manpower", Level = "globe" }
-- 1st, 2nd and 3rd on a board: gold, silver, bronze
local PODIUM: { Color3 } = { Theme.color.gold, Theme.color.textDim, Theme.color.goldDeep }

-- What each achievement asks, by stat (Config.Achievements.List). %s is the target.
local TEXT: { [string]: { one: string, many: string } } = {
	Battles = { one = "Win a battle", many = "Win %s battles in one match" },
	PeaceNeutral = { one = "Take a neutral province in Peace", many = "Take %s neutral provinces in one Peace" },
	Domination = { one = "Win by holding half the world", many = "Win by holding half the world" },
	AllianceWin = { one = "Win an alliance victory", many = "Win an alliance victory" },
	Comeback = { one = "Win after being bottom 3 at 10:00", many = "Win after being bottom 3 at 10:00" },
	Kingmaker = { one = "As a Primordial, see an ally win", many = "As a Primordial, see an ally win" },
	MeteorKills = { one = "Kill %s men with meteors", many = "Kill %s men with meteors" },
	MapWins = { one = "Win on Earth, Eldmoor and Skyshards", many = "Win on Earth, Eldmoor and Skyshards" },
	FortHolds = { one = "Hold a fort through a siege", many = "Hold forts through %s sieges in one match" },
	LifeMatches = { one = "Play a match", many = "Play %s matches" },
	Level = { one = "Reach level %s", many = "Reach level %s" },
	LifeWins = { one = "Win a match", many = "Win %s matches" },
	LifeCaptures = { one = "Capture a province", many = "Capture %s provinces" },
	LifeBattles = { one = "Win a battle", many = "Win %s battles" },
	Capitals = { one = "Capture an enemy capital", many = "Capture %s capitals in one match" },
	Held = { one = "Hold %s provinces at once", many = "Hold %s provinces at once" },
	Buildings = { one = "Build a building", many = "Build %s buildings in one match" },
	DevLevel = { one = "Develop a province to level %s", many = "Develop a province to level %s" },
	Alliances = { one = "Form an alliance", many = "Form %s alliances in one match" },
	Risen = { one = "Rise as a Primordial, stay to the end", many = "Rise as a Primordial, stay to the end" },
	Powers = { one = "Use a power", many = "Use %s powers in one match" },
	LifePowers = { one = "Use a Primordial power", many = "Use %s Primordial powers" },
	Regiments = { one = "Recruit a regiment", many = "Recruit %s regiments in one match" },
	Top3 = { one = "Finish in the top 3", many = "Finish in the top 3, %s times" },
}

local SLOT_NAMES: { [string]: string } = { Frame = "frame", Token = "token", PowerFx = "effect" }

-- The open panel's pieces (nil while the screen is closed: its contents are dropped).
type Refs = { tabs: { [Tab]: TextButton }, controls: Frame, body: Frame }

local Trophies = {}

local gui: ScreenGui
local openButton: TextButton
local panel: Frame
local ui: Refs? = nil
local tab: Tab = "Achievements"
local page = 1

local function formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

-- "Win 3 battles in one match" (also used by the Results screen).
function Trophies.text(a: Types.AchievementEntry): string
	local t = TEXT[a.stat]
	if t == nil then
		return a.name
	end
	local pattern = if a.target == 1 then t.one else t.many
	return if string.find(pattern, "%%s") then string.format(pattern, formatNumber(a.target)) else pattern
end

-- What it pays: "+300 🏅 · 🎖 the Dominant", "🎁 Centurion frame" (for other screens; this one shows icons).
function Trophies.rewardText(a: Types.AchievementEntry): string
	local parts = {}
	if a.glory > 0 then
		table.insert(parts, string.format("+%d %s", a.glory, GLORY))
	end
	local title = if a.title then Catalogue.item(a.title) else nil
	if title then
		table.insert(parts, "🎖 " .. title.name)
	end
	local item = if a.item then Catalogue.item(a.item) else nil
	if item then
		table.insert(parts, string.format("🎁 %s %s", item.name, SLOT_NAMES[item.slot] or ""))
	end
	return table.concat(parts, " · ")
end

local function grid(parent: Instance, columns: number, height: UDim)
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(1 / columns, -GAP, height.Scale, height.Offset)
	g.CellPadding = UDim2.fromOffset(GAP, GAP)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.FillDirection = Enum.FillDirection.Horizontal
	g.Parent = parent
end

-- One reward piece on a card: an icon and a short text (Glory, a title, an item), from `x` to the card's right
-- edge, cut with … when too long.
local function rewardPiece(parent: Instance, icon: string, text: string, x: number, color: Color3): TextLabel
	local l = Widgets.label(parent, text, Theme.text.small, 16)
	l.Name = "Reward"
	l.FontFace = Theme.font.display
	l.TextColor3 = color
	l.TextWrapped = false
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Position = UDim2.fromOffset(x, 0)
	l.Size = UDim2.new(1, -x, 0, 16)
	Widgets.leadIcon(l, icon, 14, 2)
	return l
end

-- One achievement: name (a tick once done), what it asks, a progress bar, and what it pays. The ones just
-- unlocked are outlined in gold.
local function card(body: Frame, a: Types.AchievementEntry, order: number, recent: boolean)
	local c = Widgets.card(body)
	c.Name = "Achievement_" .. a.id
	c.AutomaticSize = Enum.AutomaticSize.None
	c.LayoutOrder = order
	local pad = c:FindFirstChildOfClass("UIPadding")
	if pad then -- clear of the plate's lit top and its deeper base
		pad.PaddingTop = UDim.new(0, Theme.space.s)
		pad.PaddingBottom = UDim.new(0, Theme.space.m)
	end
	if recent then -- just unlocked: a gold glow (and, in the flat look, a gold edge)
		Widgets.glow(c, Theme.color.gold)
		local outline = c:FindFirstChild("Outline")
		if outline and outline:IsA("UIStroke") then
			outline.Color = Theme.color.gold
		end
	end
	local name = Widgets.label(c, a.name, Theme.text.body, 18)
	name.Name = "Name"
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = if a.done then Theme.color.gold else Theme.color.text
	Widgets.leadIcon(name, if a.done then "check" else "trophy", 16, Theme.space.xs)
	local text = Widgets.hint(c, Trophies.text(a), Theme.text.small, 16)
	text.Name = "Asks"
	text.Position = UDim2.fromOffset(0, 18)
	text.TextWrapped = false
	text.TextTruncate = Enum.TextTruncate.AtEnd
	-- the bar and what it pays along the bottom
	local progress = Widgets.progress(c, nil, BAR_HEIGHT, if a.done then Theme.color.gold else Theme.color.azure)
	progress.AnchorPoint = Vector2.new(0, 1)
	progress.Position = UDim2.new(0, 0, 1, -2)
	progress.Size = UDim2.new(BAR_SHARE, -Theme.space.s, 0, BAR_HEIGHT)
	Widgets.setProgress(progress, a.progress / a.target)
	-- what it pays, after the bar: Glory, then a title (crown) or an item (gift), cut short on a narrow card
	local rewards = Instance.new("Frame")
	rewards.Name = "Rewards"
	rewards.BackgroundTransparency = 1
	rewards.AnchorPoint = Vector2.new(0, 1)
	rewards.Position = UDim2.fromScale(BAR_SHARE, 1)
	rewards.Size = UDim2.new(1 - BAR_SHARE, 0, 0, 16)
	rewards.Parent = c
	local color = if a.done then Theme.color.textDim else Theme.color.gold
	local x = 0
	if a.glory > 0 then
		rewardPiece(rewards, "medal", "+" .. a.glory, 0, color)
		x = GLORY_WIDTH
	end
	local title = if a.title then Catalogue.item(a.title) else nil
	local item = if a.item then Catalogue.item(a.item) else nil
	if title then
		rewardPiece(rewards, "crown", title.name, x, color)
	elseif item then
		rewardPiece(rewards, "gift", string.format("%s %s", item.name, SLOT_NAMES[item.slot] or ""), x, color)
	end
end

-- One board row: rank, display name (a level on the level board), value. Your own row is highlighted.
local function boardRow(body: Frame, row: Types.BoardRow, order: number, unit: string)
	local r = Instance.new("ImageLabel")
	r.Name = "Row"
	r.BorderSizePixel = 0
	r.LayoutOrder = order
	r.Parent = body
	Widgets.material(r, "raised")
	if row.me then -- your row: a gold marker at its left, your name in gold
		local marker = Instance.new("Frame")
		marker.Name = "Marker"
		marker.BackgroundColor3 = Theme.color.gold
		marker.BorderSizePixel = 0
		marker.Position = UDim2.fromOffset(2, 4)
		marker.Size = UDim2.new(0, MARKER, 1, -8)
		marker.ZIndex = 2
		marker.Parent = r
	end
	local rank = Widgets.label(r, tostring(row.rank), Theme.text.body, ROW_HEIGHT)
	rank.Name = "Rank"
	rank.FontFace = Theme.font.display
	rank.TextXAlignment = Enum.TextXAlignment.Center
	rank.Size = UDim2.fromOffset(RANK_WIDTH, ROW_HEIGHT)
	rank.TextColor3 = PODIUM[row.rank] or Theme.color.slate300
	Widgets.textStroke(rank)
	local name = Widgets.label(
		r,
		string.format("%s%s", row.name, if row.level then "  · Lv " .. row.level else ""),
		Theme.text.small,
		ROW_HEIGHT
	)
	name.Position = UDim2.fromOffset(RANK_WIDTH, 0)
	name.Size = UDim2.new(1, -(RANK_WIDTH + VALUE_WIDTH), 1, 0)
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	if row.me then
		name.TextColor3 = Theme.color.gold
	end
	local units = if row.value == 1 and unit == "pts" then "pt" else unit
	local value = Widgets.label(r, formatNumber(row.value) .. " " .. units, Theme.text.small, ROW_HEIGHT)
	value.FontFace = Theme.font.display
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -Theme.space.m, 0, 0)
	value.Size = UDim2.fromOffset(VALUE_WIDTH, ROW_HEIGHT)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = Theme.color.gold
	Widgets.textStroke(value)
end

-- The controls row's line on the left (it shrinks for the title button and the pager).
local function info(controls: Frame, text: string, icon: string?, right: number)
	local l = Widgets.hint(controls, text, Theme.text.small, BAR)
	l.Name = "Info"
	l.Size = UDim2.new(1, -right, 1, 0)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if icon then
		Widgets.leadIcon(l, icon, 16, Theme.space.xs)
	end
	return l
end

local render: () -> ()

-- The pager at the right of the controls row (wraps round). Returns its width (0 with one page).
local function pager(controls: Frame, pages: number): number
	page = math.clamp(page, 1, math.max(1, pages))
	if pages <= 1 then
		return 0
	end
	local row, label = Widgets.pager(controls, function()
		page = if page <= 1 then pages else page - 1
		render()
	end, function()
		page = if page >= pages then 1 else page + 1
		render()
	end)
	row.AnchorPoint = Vector2.new(1, 0)
	row.Position = UDim2.fromScale(1, 0)
	label.Text = string.format("%d/%d", page, pages)
	return row.Size.X.Offset + Theme.space.m
end

-- The title you wear: tap to wear the next one you own (or none).
local function titleButton(controls: Frame, view: Types.AchievementView, right: number): number
	local shop = ShopState.view()
	local current = if shop and shop.equipped.Title then shop.equipped.Title else view.title
	local options = { Catalogue.DEFAULTS.Title }
	for _, id in view.titles do
		table.insert(options, id)
	end
	local item = Catalogue.item(current)
	local text = if item and current ~= Catalogue.DEFAULTS.Title then item.name else "No title"
	local b = Widgets.iconTextButton(controls, "crown", text, TITLE_BUTTON, Widgets.BUTTON_OFF, function()
		if #options <= 1 then
			return
		end
		local i = table.find(options, current) or 1
		Intents.equip(options[i % #options + 1])
	end, "TitleButton")
	b.TextSize = Theme.text.small
	b.TextWrapped = false
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.AnchorPoint = Vector2.new(1, 0)
	b.Position = UDim2.new(1, -right, 0, 0)
	if #options <= 1 then
		Widgets.setEnabled(b, false) -- nothing to wear yet: achievements give titles
	end
	return right + TITLE_BUTTON + Theme.space.m
end

local function renderAchievements(r: Refs)
	local view = TrophyState.achievements()
	if view == nil then
		info(r.controls, "Loading your achievements…", "hourglass", 0)
		return
	end
	local perPage = COLUMNS * CARD_ROWS
	local right = pager(r.controls, math.ceil(#view.list / perPage))
	right = titleButton(r.controls, view, right)
	info(
		r.controls,
		string.format("%d of %d earned · each pays once", TrophyState.doneCount(), #view.list),
		nil,
		right
	)
	grid(r.body, COLUMNS, UDim.new(1 / CARD_ROWS, -GAP))
	for i = (page - 1) * perPage + 1, math.min(page * perPage, #view.list) do
		local a = view.list[i]
		card(r.body, a, i, table.find(view.recent, a.id) ~= nil)
	end
end

local function renderBoard(r: Refs)
	local boards = TrophyState.boards()
	if boards == nil then
		info(r.controls, "Loading the leaderboards…", "hourglass", 0)
		return
	end
	local rows = if tab == "Weekly" then boards.weekly elseif tab == "Friends" then boards.friends else boards.level
	local perPage = BOARD_COLUMNS * BOARD_ROWS
	local right = pager(r.controls, math.ceil(#rows / perPage))
	local text
	if tab == "Level" then
		text = "Account XP, all time"
	else
		local rank = if boards.myRank > 0 then " · #" .. boards.myRank else ""
		text = string.format(
			"You: %d pts%s · resets Monday · top %d wear the Warlord frame next week%s",
			boards.myPoints,
			rank,
			Config.Leaderboards.WarlordTop,
			if boards.warlord then " · you wear it now" else ""
		)
		if tab == "Friends" then
			text = string.format("You and your friends · %d pts%s", boards.myPoints, rank)
		end
	end
	if not boards.live then
		text ..= " · not saved (no DataStore access)"
	end
	info(r.controls, text, if boards.warlord and tab == "Weekly" then "war" else nil, right)
	grid(r.body, BOARD_COLUMNS, UDim.new(0, ROW_HEIGHT))
	if #rows == 0 then
		local empty = Widgets.hint(r.body, "No points yet this week: public matches with 4+ players count", nil, 22)
		empty.Name = "Empty"
		return
	end
	-- fill down the first column, then the second
	for i = (page - 1) * perPage + 1, math.min(page * perPage, #rows) do
		local k = i - (page - 1) * perPage - 1
		local order = (k % BOARD_ROWS) * BOARD_COLUMNS + k // BOARD_ROWS
		boardRow(r.body, rows[i], order, if tab == "Level" then "XP" else "pts")
	end
end

render = function()
	local r = ui
	if r == nil or not panel.Visible then
		return
	end
	for name, b in r.tabs do
		Widgets.setTab(b, name == tab)
	end
	r.controls:ClearAllChildren()
	r.body:ClearAllChildren()
	if tab == "Achievements" then
		renderAchievements(r)
	else
		renderBoard(r)
	end
end

local function refreshButton()
	-- the map vote only (like the season pass): during the draft the bottom row holds the "Pick" button
	local phase = LobbyState.phase()
	local inLobby = phase == "Lobby" or (phase ~= "Pick" and ClientState.snapshot() == nil)
	openButton.Visible = inLobby and not panel.Visible
end

local setOpen: (boolean) -> ()

-- The panel's contents, built when it opens: header (title, tabs, close), the controls row and the body.
local function build(): Refs
	-- the title plate on the window's top edge, the close gem on its corner, the tabs under them
	Widgets.header(panel, "Trophies", "trophy", function()
		setOpen(false)
	end)
	local row = Instance.new("Frame")
	row.Name = "Tabs"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, BAR)
	row.LayoutOrder = 1
	row.Parent = panel
	Widgets.list(row, true, Theme.space.s)
	local tabs: { [Tab]: TextButton } = {}
	for i, name in TABS do
		local b = Widgets.tab(row, name, 0, false, function()
			tab, page = name, 1
			render()
		end)
		b.Name = "Tab" .. name
		b.TextSize = Theme.text.small
		b.TextWrapped = false
		b.AutomaticSize = Enum.AutomaticSize.X
		b.LayoutOrder = i
		Widgets.padding(b, Theme.space.m, 0)
		Widgets.leadIcon(b, TAB_ICONS[name], Theme.size.icon, Theme.space.xs)
		tabs[name] = b
	end

	local controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundTransparency = 1
	controls.Size = UDim2.new(1, 0, 0, BAR)
	controls.LayoutOrder = 2
	controls.Parent = panel

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -(2 * BAR + 3 * Theme.space.s)) -- three gaps: the header's too
	body.LayoutOrder = 3
	body.Parent = panel
	return { tabs = tabs, controls = controls, body = body }
end

setOpen = function(open: boolean)
	panel.Visible = open
	if open and ui == nil then
		ui = build()
	elseif not open and ui ~= nil then
		Widgets.clear(panel) -- a closed screen keeps no cards or rows (rebuilt when it opens)
		ui = nil
	end
	refreshButton()
	if open then
		render()
	end
end

-- Open on a tab ("Achievements" by default).
function Trophies.open(which: string?)
	if which and table.find(TABS, which :: Tab) then
		tab = which :: Tab
		page = 1
	end
	setOpen(true)
end

function Trophies.close()
	setOpen(false)
end

function Trophies.isOpen(): boolean
	return panel.Visible
end

function Trophies.init()
	gui = Widgets.screen("Trophies", 31) -- like the Quests screen: above the shop and the lobby screens
	local buttonGui = Widgets.screen("TrophiesButton", 29) -- under full-screen panels, like the scroll button

	openButton = Widgets.cornerButton(
		buttonGui,
		LOBBY_SLOT,
		"trophy",
		"TrophiesButton",
		Theme.color.secondary,
		function()
			setOpen(true)
		end
	)

	panel = Widgets.window(gui, "TrophiesPanel")
	Widgets.list(panel, false, Theme.space.s)

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	Widgets.fitScreen(buttonGui)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	buttonGui.Parent = gui.Parent

	TrophyState.onChange(render)
	ShopState.onChange(function()
		render() -- the title you wear
	end)
	ClientState.onReset(refreshButton)
	LobbyState.onChange(refreshButton)
end

return Trophies
