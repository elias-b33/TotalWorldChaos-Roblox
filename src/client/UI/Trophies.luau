--!strict
-- The Trophies screen (docs/MONETIZATION.md 5.6, 7.3), phone first: your 30 achievements with progress bars and
-- rewards (and the title you wear), and the weekly, friends and global level leaderboards. Opens from the 🏆 button
-- in the Lobby (next to 🛒 and 📜) and from the Results screen. Boards show display names only.

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

local GLORY = "🏅"
local BUTTON_SIZE = 52
local LOBBY_SLOT = 2 -- the third round button in the Lobby's bottom-left row (after 🛒 and 📜)
local HEADER_HEIGHT = 40
local CONTROLS_HEIGHT = 36
local GAP = 4
local COLUMNS = 3 -- achievement cards per row
local CARD_ROWS = 5
local CARD_HEIGHT = 48
local BOARD_COLUMNS = 2
local BOARD_ROWS = 10
local ROW_HEIGHT = 22
local TAB_WIDTH = 132
local PAGER_WIDTH = 160 -- ◀ 1/2 ▶ and the gaps around it
local CARD = Color3.fromRGB(32, 35, 50)
local DONE_CARD = Color3.fromRGB(56, 48, 22)
local GOLD = Color3.fromRGB(242, 193, 78)
local OFF_TEXT = Color3.fromRGB(150, 152, 165)
local BAR_BACK = Color3.fromRGB(50, 54, 70)
local ME = Color3.fromRGB(60, 90, 150)

type Tab = "Achievements" | "Weekly" | "Friends" | "Level"
local TABS: { Tab } = { "Achievements", "Weekly", "Friends", "Level" }

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

local Trophies = {}

local gui: ScreenGui
local openButton: TextButton
local panel: Frame
local tabButtons: { [Tab]: TextButton } = {}
local controls: Frame
local body: Frame
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

-- What it pays: "+300 🏅 · 🎖 the Dominant", "🎁 Centurion frame".
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

local function bar(parent: Instance, share: number, color: Color3): Frame
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.BackgroundColor3 = BAR_BACK
	back.BorderSizePixel = 0
	back.Parent = parent
	Widgets.corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	Widgets.corner(fill, 4)
	return back
end

local function grid(parent: Instance, columns: number, height: number)
	local g = Instance.new("UIGridLayout")
	g.CellSize = UDim2.new(1 / columns, -GAP, 0, height)
	g.CellPadding = UDim2.fromOffset(GAP, GAP)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.FillDirection = Enum.FillDirection.Horizontal
	g.Parent = parent
end

-- One achievement: name, what it asks, a progress bar, and what it pays.
local function card(a: Types.AchievementEntry, order: number, recent: boolean)
	local c = Instance.new("Frame")
	c.Name = "Achievement_" .. a.id
	c.BackgroundColor3 = if a.done then DONE_CARD else CARD
	c.LayoutOrder = order
	c.Parent = body
	Widgets.corner(c, 8)
	if recent then
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD
		stroke.Thickness = 2
		stroke.Parent = c
	end
	local name = Widgets.label(c, (if a.done then "✅ " else "🏆 ") .. a.name, 13, 16)
	name.Position = UDim2.fromOffset(8, 3)
	name.Size = UDim2.new(1, -16, 0, 16)
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextColor3 = if a.done then GOLD else Color3.new(1, 1, 1)
	local text = Widgets.label(c, Trophies.text(a), 11, 14)
	text.Position = UDim2.fromOffset(8, 18)
	text.Size = UDim2.new(1, -16, 0, 14)
	text.TextWrapped = false
	text.TextTruncate = Enum.TextTruncate.AtEnd
	text.TextColor3 = OFF_TEXT
	local progress = bar(c, a.progress / a.target, if a.done then GOLD else Widgets.BUTTON)
	progress.Position = UDim2.fromOffset(8, 36)
	progress.Size = UDim2.new(0.38, -8, 0, 6)
	local reward = Widgets.label(c, Trophies.rewardText(a), 11, 14)
	reward.Name = "Reward"
	reward.Position = UDim2.new(0.38, 4, 0, 32)
	reward.Size = UDim2.new(0.62, -12, 0, 14)
	reward.TextWrapped = false
	reward.TextTruncate = Enum.TextTruncate.AtEnd
	reward.TextXAlignment = Enum.TextXAlignment.Right
	reward.TextColor3 = if a.done then OFF_TEXT else GOLD
end

-- One board row: rank, display name (a level on the level board), value. Your own row is highlighted.
local function boardRow(row: Types.BoardRow, order: number, unit: string)
	local r = Instance.new("Frame")
	r.Name = "Row"
	r.BackgroundColor3 = if row.me then ME else CARD
	r.LayoutOrder = order
	r.Parent = body
	Widgets.corner(r, 6)
	local medal = if row.rank == 1 then "🥇" elseif row.rank == 2 then "🥈" elseif row.rank == 3 then "🥉" else ""
	local name = Widgets.label(
		r,
		string.format("%s %d. %s%s", medal, row.rank, row.name, if row.level then "  · Lv " .. row.level else ""),
		13,
		ROW_HEIGHT
	)
	name.Position = UDim2.fromOffset(8, 0)
	name.Size = UDim2.new(1, -96, 1, 0)
	name.TextWrapped = false
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local units = if row.value == 1 and unit == "pts" then "pt" else unit
	local value = Widgets.label(r, formatNumber(row.value) .. " " .. units, 13, ROW_HEIGHT)
	value.AnchorPoint = Vector2.new(1, 0)
	value.Position = UDim2.new(1, -8, 0, 0)
	value.Size = UDim2.fromOffset(90, ROW_HEIGHT)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextColor3 = GOLD
end

local function info(text: string, width: number?)
	local l = Widgets.label(controls, text, 12, CONTROLS_HEIGHT)
	l.Name = "Info"
	l.Size = UDim2.new(1, -(width or 0), 1, 0)
	l.TextColor3 = OFF_TEXT
	l.LayoutOrder = 1
	return l
end

local render: () -> ()

-- ◀ 1/2 ▶ at the right of the controls row.
local function pager(pages: number)
	page = math.clamp(page, 1, math.max(1, pages))
	if pages <= 1 then
		return
	end
	local prev = Widgets.button(controls, "◀", 44, Widgets.BUTTON, function()
		page = if page <= 1 then pages else page - 1
		render()
	end)
	prev.Name = "PrevPage"
	prev.Size = UDim2.fromOffset(44, CONTROLS_HEIGHT)
	prev.LayoutOrder = 3
	local count = Widgets.label(controls, string.format("%d/%d", page, pages), 13, CONTROLS_HEIGHT)
	count.Size = UDim2.fromOffset(40, CONTROLS_HEIGHT)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.LayoutOrder = 4
	local nextButton = Widgets.button(controls, "▶", 44, Widgets.BUTTON, function()
		page = if page >= pages then 1 else page + 1
		render()
	end)
	nextButton.Name = "NextPage"
	nextButton.Size = UDim2.fromOffset(44, CONTROLS_HEIGHT)
	nextButton.LayoutOrder = 5
end

-- The title you wear: tap to wear the next one you own (or none).
local function titleButton(view: Types.AchievementView)
	local shop = ShopState.view()
	local current = if shop and shop.equipped.Title then shop.equipped.Title else view.title
	local options = { Catalogue.DEFAULTS.Title }
	for _, id in view.titles do
		table.insert(options, id)
	end
	local item = Catalogue.item(current)
	local text = if item and current ~= Catalogue.DEFAULTS.Title then "🎖 " .. item.name else "🎖 No title"
	local b = Widgets.button(
		controls,
		text .. (if #options > 1 then "  ▸" else ""),
		200,
		Widgets.BUTTON_OFF,
		function()
			if #options <= 1 then
				return
			end
			local i = table.find(options, current) or 1
			Intents.equip(options[i % #options + 1])
		end
	)
	b.Name = "TitleButton"
	b.TextSize = 13
	b.Size = UDim2.fromOffset(200, CONTROLS_HEIGHT)
	b.LayoutOrder = 2
end

local function renderAchievements()
	local view = TrophyState.achievements()
	if view == nil then
		info("⏳ Loading your achievements…")
		return
	end
	local perPage = COLUMNS * CARD_ROWS
	local pages = math.ceil(#view.list / perPage)
	info(
		string.format("%d of %d earned · each pays once", TrophyState.doneCount(), #view.list),
		206 + (if pages > 1 then PAGER_WIDTH else 0)
	)
	titleButton(view)
	pager(pages)
	grid(body, COLUMNS, CARD_HEIGHT)
	for i = (page - 1) * perPage + 1, math.min(page * perPage, #view.list) do
		local a = view.list[i]
		card(a, i, table.find(view.recent, a.id) ~= nil)
	end
end

local function renderBoard()
	local boards = TrophyState.boards()
	if boards == nil then
		info("⏳ Loading the leaderboards…")
		return
	end
	local rows = if tab == "Weekly" then boards.weekly elseif tab == "Friends" then boards.friends else boards.level
	local perPage = BOARD_COLUMNS * BOARD_ROWS
	local pages = math.ceil(#rows / perPage)
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
			if boards.warlord then " · ⚔ you wear it now" else ""
		)
		if tab == "Friends" then
			text = string.format("You and your friends · %d pts%s", boards.myPoints, rank)
		end
	end
	if not boards.live then
		text ..= " · 🧪 not saved (no DataStore access)"
	end
	info(text, if pages > 1 then PAGER_WIDTH else 0)
	pager(pages)
	grid(body, BOARD_COLUMNS, ROW_HEIGHT)
	if #rows == 0 then
		local empty = Widgets.label(body, "No points yet this week: public matches with 4+ players count", 13, 22)
		empty.TextColor3 = OFF_TEXT
		return
	end
	-- fill down the first column, then the second
	for i = (page - 1) * perPage + 1, math.min(page * perPage, #rows) do
		local k = i - (page - 1) * perPage - 1
		local order = (k % BOARD_ROWS) * BOARD_COLUMNS + k // BOARD_ROWS
		boardRow(rows[i], order, if tab == "Level" then "XP" else "pts")
	end
end

render = function()
	if panel == nil or not panel.Visible then
		return
	end
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == tab then Widgets.BUTTON else Widgets.BUTTON_OFF
	end
	tabButtons.Achievements.Text = string.format("🏆 Achievements %d", TrophyState.doneCount())
	Widgets.clear(controls)
	Widgets.clear(body)
	for _, child in body:GetChildren() do
		if child:IsA("UIGridLayout") then
			child:Destroy()
		end
	end
	if tab == "Achievements" then
		renderAchievements()
	else
		renderBoard()
	end
end

local function refreshButton()
	local inLobby = LobbyState.phase() ~= "None" or ClientState.snapshot() == nil
	openButton.Visible = inLobby and not panel.Visible
end

local function setOpen(open: boolean)
	panel.Visible = open
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
	local buttonGui = Widgets.screen("TrophiesButton", 29) -- under full-screen panels, like the 📜 button

	openButton = Instance.new("TextButton")
	openButton.Name = "TrophiesButton"
	openButton.AnchorPoint = Vector2.new(0, 1)
	openButton.Position = UDim2.new(0, 12 + LOBBY_SLOT * (BUTTON_SIZE + 10), 1, -12)
	openButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	openButton.BackgroundColor3 = Color3.fromRGB(150, 110, 30)
	openButton.Font = Enum.Font.GothamBold
	openButton.TextSize = 24
	openButton.TextColor3 = Color3.new(1, 1, 1)
	openButton.Text = "🏆"
	openButton.Parent = buttonGui
	Widgets.corner(openButton, BUTTON_SIZE // 2)
	openButton.Activated:Connect(function()
		setOpen(true)
	end)

	panel = Instance.new("Frame")
	panel.Name = "TrophiesPanel"
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
	local title = Widgets.label(header, "🏆 Trophies", 20, HEADER_HEIGHT)
	title.Size = UDim2.fromOffset(120, HEADER_HEIGHT)
	local tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromOffset(126, 0)
	tabRow.Size = UDim2.new(1, -(126 + 50), 1, 0)
	tabRow.Parent = header
	Widgets.list(tabRow, true, 6)
	local labels: { [Tab]: string } =
		{ Achievements = "🏆 Achievements", Weekly = "📅 Weekly", Friends = "👥 Friends", Level = "🌍 Level" }
	for i, name in TABS do
		local b = Widgets.button(tabRow, labels[name], TAB_WIDTH, Widgets.BUTTON_OFF, function()
			tab, page = name, 1
			render()
		end)
		b.Name = "Tab" .. name
		b.TextSize = 14
		b.Size = UDim2.fromOffset(if name == "Achievements" then TAB_WIDTH + 20 else TAB_WIDTH - 20, HEADER_HEIGHT)
		b.LayoutOrder = i
		tabButtons[name] = b
	end
	local close = Widgets.button(header, "✕", 44, Widgets.DANGER, function()
		setOpen(false)
	end)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(44, HEADER_HEIGHT)

	controls = Instance.new("Frame")
	controls.Name = "Controls"
	controls.BackgroundTransparency = 1
	controls.Size = UDim2.new(1, 0, 0, CONTROLS_HEIGHT)
	controls.LayoutOrder = 2
	controls.Parent = panel
	Widgets.list(controls, true, 6).VerticalAlignment = Enum.VerticalAlignment.Center

	body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + CONTROLS_HEIGHT + 12))
	body.LayoutOrder = 3
	body.Parent = panel

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
