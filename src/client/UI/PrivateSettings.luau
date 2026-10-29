--!strict
-- A private server's settings in the Lobby (docs/MONETIZATION.md 3.4): during the map vote the owner gets a
-- Settings button (a gear) and a sheet with every setting; everyone sees a one-line summary under the vote cards.
-- Every tap sends RequestSetting; the server checks it (Sim.Lobby.setting, Sim.Settings.set) and the next Lobby
-- view (once a second) shows the result. The sheet fits a 667×375 phone in landscape without scrolling: two tabs,
-- Rules (two columns of five settings) and Teams (a cell per player), with the reward line and Done beside them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Lobby = require(Shared.Sim.Lobby)
local Maps = require(Shared.Maps)
local Settings = require(Shared.Sim.Settings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local TextWidth = require(Client.TextWidth)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local LABEL_WIDTH = 88 -- "Bot level" and "Disasters" with their icons
local OPTION_WIDTH = 76
local OPTION_PAD = 14 -- a tab's caption keeps this much room (the map row's tabs fit their names)
local LEFT_SHARE = 0.58 -- the Rules page's left column (the map row is the widest)
local VALUE_WIDTH = 60 -- the bot count between its arrows
local HEADER_HEIGHT = Widgets.BUTTON_HEIGHT -- the tabs, the reward line and Done
local TAB_WIDTH = 104
local TEAM_CELL = Vector2.new(120, 36)
local TEXT_SIZE = 14
local SETTINGS_WIDTH = 140
local LOBBY_BUTTONS = 4 -- the round buttons in the bottom-left corner during the vote (shop, quests, trophies, pass)

type Option = { button: TextButton, key: string, value: string | number | boolean }

local PrivateSettings = {}

local gui: ScreenGui
local sheetGui: ScreenGui
local panel: Frame? = nil
local openButton: TextButton
local summaryLabel: TextLabel
local rewardLabel: TextLabel
local botsLabel: TextLabel
local teamGrid: Frame
local pages: { [string]: Frame } = {} -- "Rules" and "Teams"
local pageTabs: { [string]: TextButton } = {}
local page = "Rules"
local options: { Option } = {}
local teamButtons: { [number]: TextButton } = {} -- userId -> button
local teamsFor = "" -- the player list the team buttons were built for
local open = false

local function me(): number
	return Players.LocalPlayer.UserId
end

local function isOwner(view: Lobby.LobbyView?): boolean
	return view ~= nil and view.phase == "Lobby" and view.owner ~= 0 and view.owner == me()
end

-- One line for everyone: what the next match plays (shown after a lock icon, so it starts "Private server").
function PrivateSettings.summary(s: Types.MatchSettings): string
	local parts = {
		"Private server",
		string.format("%d min", s.minutes),
		string.format("%d min peace", s.peaceMinutes),
		string.format("%d %s bots", s.bots, s.difficulty),
	}
	if not s.powers then
		table.insert(parts, "powers off")
	end
	if not s.disasters then
		table.insert(parts, "no disasters")
	end
	if not s.diplomacy then
		table.insert(parts, "no insults, gifts or access")
	end
	if not s.events then
		table.insert(parts, "no events")
	end
	if #s.teams > 0 then
		table.insert(parts, "teams set")
	end
	if s.theme == "Default" then
		table.insert(parts, "default theme")
	end
	return table.concat(parts, " · ")
end

-- A setting's row: its icon and name, then its options as tabs (the chosen one is gold).
local function row(parent: Instance, order: number, icon: string, text: string): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	f.LayoutOrder = order
	f.Parent = parent
	Widgets.list(f, true, Theme.space.xs)
	local l = Widgets.label(f, text, TEXT_SIZE, Widgets.BUTTON_HEIGHT)
	l.Size = UDim2.fromOffset(LABEL_WIDTH, Widgets.BUTTON_HEIGHT)
	l.TextWrapped = false
	l.LayoutOrder = 0
	Widgets.leadIcon(l, icon, Theme.size.icon)
	return f
end

local function option(parent: Frame, key: string, value: string | number | boolean, text: string, width: number?)
	local b = Widgets.tab(parent, text, width or OPTION_WIDTH, false, function()
		Intents.setting(key, value)
	end)
	b.Name = "Setting_" .. key .. "_" .. tostring(value)
	b.TextSize = TEXT_SIZE
	b.LayoutOrder = #parent:GetChildren()
	table.insert(options, { button = b, key = key, value = value })
end

-- An on/off setting's row (powers, disasters, and the EU4 pack's insults and event cards).
local function onOff(parent: Instance, order: number, icon: string, text: string, key: string)
	local r = row(parent, order, icon, text)
	option(r, key, true, "On")
	option(r, key, false, "Off")
end

-- The map row's tabs: all as wide as the longest name needs (at least OPTION_WIDTH) where the column has room, else
-- each as wide as its own name, sharing out what is left ("Skyshards" needs more than a 667 px phone's even share).
local function mapWidths(texts: { string }, room: number): { number }
	local widths, total, widest = {}, 0, OPTION_WIDTH
	for i, text in texts do
		local w = math.ceil(TextWidth.measure(text, TEXT_SIZE)) + OPTION_PAD
		widths[i] = w + w % 2
		total += widths[i]
		widest = math.max(widest, widths[i])
	end
	local gaps = (#texts - 1) * Theme.space.xs
	if #texts * widest + gaps <= room then
		for i in widths do
			widths[i] = widest
		end
		return widths
	end
	local extra = math.max(0, (room - total - gaps) // #texts)
	for i, w in widths do
		widths[i] = w + extra - extra % 2
	end
	return widths
end

-- The next team for a player: the one after theirs that still has room (0 = no team).
local function nextTeam(settings: Types.MatchSettings, userId: number): number
	local team = Settings.teamOf(settings, userId)
	for _ = 1, Config.Private.Teams + 1 do
		team = (team + 1) % (Config.Private.Teams + 1)
		local members = 0
		for _, entry in settings.teams do
			if entry.team == team and entry.userId ~= userId then
				members += 1
			end
		end
		if team == 0 or members < Config.Diplomacy.MaxAllianceSize then
			return team
		end
	end
	return 0
end

local function buildTeams(view: Lobby.LobbyView)
	Widgets.clear(teamGrid)
	teamButtons = {}
	for i, p in view.players do
		local b = Widgets.button(teamGrid, p.name, TEAM_CELL.X, Widgets.BUTTON_OFF, function()
			local current = LobbyState.view()
			if current then
				Intents.setting("team", p.userId, nextTeam(current.settings, p.userId))
			end
		end)
		b.Name = "Team_" .. p.userId
		b.TextSize = TEXT_SIZE
		b.LayoutOrder = i
		teamButtons[p.userId] = b
	end
end

local function playersKey(view: Lobby.LobbyView): string
	local ids = {}
	for _, p in view.players do
		table.insert(ids, p.userId .. "=" .. p.name)
	end
	return table.concat(ids, ",")
end

local function column(parent: Instance, x: number, width: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromScale(x, 0)
	f.Size = UDim2.fromScale(width, 1)
	f.Parent = parent
	Widgets.list(f, false, 6)
	return f
end

-- Show a page of the sheet: "Rules" or "Teams".
local function showPage(name: string)
	page = name
	for key, frame in pages do
		frame.Visible = key == name
	end
	for key, tab in pageTabs do
		Widgets.setTab(tab, key == name)
	end
end

-- The settings sheet, built the first time the owner opens it (most servers are public and never need its
-- 150 or so GUI objects).
local function buildPanel()
	-- an iron sheet over the vote screen, its title on a plate on its top edge: a full-screen window's size (a phone's
	-- at most, grown by the device scale on a tablet)
	local p = Widgets.panel(sheetGui, 0)
	panel = p
	p.Name = "SettingsPanel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.AutomaticSize = Enum.AutomaticSize.None
	p.Visible = false
	local size = Widgets.windowSize(sheetGui)
	Widgets.fit(p, UDim2.fromOffset(size.X, size.Y), UDim2.new(0.5, 0, 0.5, Theme.space.xs))
	Widgets.header(p, "Private server settings", "gear")

	-- the two tabs, the reward line, Done
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.Parent = p
	for i, tab in { { "Rules", "gear" }, { "Teams", "teams" } } do
		local name = tab[1]
		local b = Widgets.tab(header, name, TAB_WIDTH, false, function()
			showPage(name)
		end)
		b.Name = "SettingsTab_" .. name
		b.Position = UDim2.fromOffset((i - 1) * (TAB_WIDTH + Theme.space.s), 0)
		Widgets.padding(b, Theme.space.m, 0) -- like the trophies' tabs: the icon inside the tab's edge
		Widgets.leadIcon(b, tab[2], Theme.size.icon, Theme.space.xs)
		pageTabs[name] = b
	end
	local tabsWidth = 2 * TAB_WIDTH + Theme.space.s + Theme.space.m
	rewardLabel = Widgets.hint(header, "", TEXT_SIZE, HEADER_HEIGHT)
	rewardLabel.Name = "Rewards"
	rewardLabel.Position = UDim2.fromOffset(tabsWidth, 0)
	rewardLabel.Size = UDim2.new(1, -(tabsWidth + 104 + Theme.space.m), 1, 0)
	local done = Widgets.iconTextButton(header, "check", "Done", 104, Widgets.GOOD, function()
		open = false
		PrivateSettings.render()
	end)
	done.Name = "SettingsDone"
	done.AnchorPoint = Vector2.new(1, 0.5)
	done.Position = UDim2.fromScale(1, 0.5)

	local function newPage(name: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Position = UDim2.fromOffset(0, HEADER_HEIGHT + Theme.space.m)
		f.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + Theme.space.m))
		f.Parent = p
		pages[name] = f
		return f
	end

	-- Rules: five settings a column (the map row is the widest, so the left column is wider)
	local rules = newPage("Rules")
	local left = column(rules, 0, LEFT_SHARE)
	local right = column(rules, LEFT_SHARE + 0.01, 0.99 - LEFT_SHARE)
	local sheetWidth = size.X - 2 * Widgets.PANEL_PAD
	local mapTexts = { "Vote" }
	for _, id in Maps.ids do
		table.insert(mapTexts, Maps.get(id).title)
	end
	local widths = mapWidths(mapTexts, sheetWidth * LEFT_SHARE - LABEL_WIDTH - Theme.space.xs)
	local map = row(left, 1, "map", "Map")
	option(map, "map", "", "Vote", widths[1])
	for i, id in Maps.ids do
		option(map, "map", id, Maps.get(id).title, widths[i + 1])
	end
	local length = row(left, 2, "clock", "Length")
	for _, m in Config.Private.Minutes do
		option(length, "minutes", m, m .. " min")
	end
	local peace = row(left, 3, "peace", "Peace")
	for _, m in Config.Private.PeaceMinutes do
		option(peace, "peaceMinutes", m, if m == 0 then "None" else m .. " min")
	end
	local theme = row(left, 4, "palette", "Theme")
	for _, t in Config.Private.Themes do
		option(theme, "theme", t, t)
	end
	local level = row(left, 5, "gear", "Bot level")
	for _, d in Config.Private.Difficulties do
		option(level, "difficulty", d, d)
	end

	local bots = row(right, 1, "bot", "Bots")
	local function stepBots(delta: number)
		local view = LobbyState.view()
		if view then
			Intents.setting("bots", math.clamp(view.settings.bots + delta, 0, Config.Private.MaxBots))
		end
	end
	local less = Widgets.button(bots, "−", Widgets.BUTTON_HEIGHT, Widgets.BUTTON_OFF, function()
		stepBots(-1)
	end)
	less.Name = "BotsLess"
	less.LayoutOrder = 1
	botsLabel = Widgets.label(bots, "", 16, Widgets.BUTTON_HEIGHT)
	botsLabel.FontFace = Theme.font.display
	botsLabel.Size = UDim2.fromOffset(VALUE_WIDTH, Widgets.BUTTON_HEIGHT)
	botsLabel.TextXAlignment = Enum.TextXAlignment.Center
	botsLabel.LayoutOrder = 2
	local more = Widgets.button(bots, "+", Widgets.BUTTON_HEIGHT, Widgets.BUTTON_OFF, function()
		stepBots(1)
	end)
	more.Name = "BotsMore"
	more.LayoutOrder = 3
	onOff(right, 2, "sparkles", "Powers", "powers")
	onOff(right, 3, "meteor", "Disasters", "disasters")
	-- the EU4 pack: insults (with gifts and military access), and event cards with choices
	onOff(right, 4, "grudge", "Insults", "diplomacy")
	onOff(right, 5, "scroll", "Events", "events")

	-- Teams: a cell per player, tap to move them to the next team
	local teams = newPage("Teams")
	Widgets.list(teams, false, Theme.space.s)
	local teamsTitle = Widgets.label(teams, "Tap a player to change their team (same team = allies)", TEXT_SIZE, 22)
	teamsTitle.LayoutOrder = 1
	Widgets.leadIcon(teamsTitle, "teams", Theme.size.icon)
	teamGrid = Instance.new("Frame")
	teamGrid.Name = "Teams"
	teamGrid.BackgroundTransparency = 1
	teamGrid.Size = UDim2.new(1, 0, 1, -(22 + Theme.space.s))
	teamGrid.LayoutOrder = 2
	teamGrid.Parent = teams
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TEAM_CELL.X, TEAM_CELL.Y)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = teamGrid
	showPage(page)
end

function PrivateSettings.render()
	local view = LobbyState.view()
	local voting = view ~= nil and view.phase == "Lobby"
	local owner = isOwner(view)
	if not owner then
		open = false
	end
	summaryLabel.Visible = voting and view ~= nil and view.private
	openButton.Visible = owner and not open
	if owner and open and panel == nil then
		buildPanel()
	end
	local sheet = panel
	if sheet then
		sheet.Visible = owner and open
	end
	if view == nil or not voting then
		return
	end
	local s = view.settings
	summaryLabel.Text = PrivateSettings.summary(s)
	if sheet == nil or not sheet.Visible then
		return
	end
	for _, o in options do
		local current: any = (s :: any)[o.key]
		Widgets.setTab(o.button, current == o.value)
	end
	botsLabel.Text = if s.bots >= Config.Private.MaxBots then string.format("%d (fill)", s.bots) else tostring(s.bots)
	local key = playersKey(view)
	if key ~= teamsFor then
		teamsFor = key
		buildTeams(view)
	end
	for _, p in view.players do
		local b = teamButtons[p.userId]
		local team = Settings.teamOf(s, p.userId)
		if b then
			b.Text = string.format("%s · %s", p.name, if team > 0 then "Team " .. team else "—")
			b.BackgroundColor3 = if team > 0 then Widgets.BUTTON else Widgets.BUTTON_OFF
		end
	end
	local standard = Settings.isStandard(s)
	local humans = #view.players
	if standard and humans >= Config.Private.FullRewardHumans then
		rewardLabel.Text = "Default rules: full XP and Glory"
	elseif standard then
		rewardLabel.Text = string.format("½ XP and Glory: fewer than %d players", Config.Private.FullRewardHumans)
	else
		rewardLabel.Text = "½ XP and Glory: custom rules"
	end
end

function PrivateSettings.init()
	gui = Widgets.screen("PrivateSettings", 25) -- the summary and the button: above the vote screen, below the shop
	sheetGui = Widgets.screen("PrivateSettingsSheet", 31) -- the sheet covers the shop's button too
	-- the whole screen, Roblox's top-bar row included: the sheet has the full height in Studio as in the harness, and
	-- its title plate starts right of Roblox's buttons (Widgets.header)
	Widgets.coverScreen(sheetGui)

	-- the summary: a plate with a lock icon and one line, between the Lobby's corner gems and Settings
	local left = Widgets.cornerRowEnd(LOBBY_BUTTONS) + Theme.space.m
	summaryLabel = Widgets.label(gui, "", TEXT_SIZE, Widgets.BUTTON_HEIGHT)
	summaryLabel.Name = "Summary"
	summaryLabel.AnchorPoint = Vector2.new(0, 1)
	summaryLabel.Position = UDim2.new(0, left, 1, -Theme.space.l)
	summaryLabel.Size = UDim2.new(1, -(left + SETTINGS_WIDTH + Theme.space.l + Theme.space.m), 0, Widgets.BUTTON_HEIGHT)
	summaryLabel.BackgroundColor3 = Theme.color.slate800
	summaryLabel.TextColor3 = Theme.color.brass200
	summaryLabel.TextWrapped = false
	summaryLabel.TextTruncate = Enum.TextTruncate.AtEnd
	summaryLabel.Visible = false
	Widgets.corner(summaryLabel, Theme.radius.s)
	Widgets.stroke(summaryLabel)
	Widgets.padding(summaryLabel, Theme.space.m, 0)
	Widgets.leadIcon(summaryLabel, "lock", Theme.size.icon)
	Widgets.skin(summaryLabel, "plate", "plate")
	Widgets.shadow(summaryLabel, "plate")

	openButton = Widgets.iconTextButton(gui, "gear", "Settings", SETTINGS_WIDTH, Widgets.BUTTON_OFF, function()
		open = true
		PrivateSettings.render()
	end)
	openButton.Name = "SettingsButton"
	openButton.AnchorPoint = Vector2.new(1, 1)
	openButton.Position = UDim2.new(1, -12, 1, -12)
	openButton.Visible = false
	Widgets.shadow(openButton, "button")

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	sheetGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	LobbyState.onChange(function()
		PrivateSettings.render()
	end)
end

return PrivateSettings
