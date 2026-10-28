--!strict
-- A private server's settings in the Lobby (docs/MONETIZATION.md 3.4): during the map vote the owner gets a
-- Settings button (a gear) and a sheet with every setting; everyone sees a one-line summary under the vote cards.
-- Every tap sends RequestSetting; the server checks it (Sim.Lobby.setting, Sim.Settings.set) and the next Lobby
-- view (once a second) shows the result. The sheet fits a phone in landscape without scrolling: two columns.

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
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local LABEL_WIDTH = 104
local OPTION_WIDTH = 76
local HEADER_HEIGHT = 36
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

local function option(parent: Frame, key: string, value: string | number | boolean, text: string)
	local b = Widgets.tab(parent, text, OPTION_WIDTH, false, function()
		Intents.setting(key, value)
	end)
	b.Name = "Setting_" .. key .. "_" .. tostring(value)
	b.TextSize = TEXT_SIZE
	b.LayoutOrder = #parent:GetChildren()
	table.insert(options, { button = b, key = key, value = value })
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

-- The settings sheet, built the first time the owner opens it (most servers are public and never need its
-- 150 or so GUI objects).
local function buildPanel()
	local p = Instance.new("Frame")
	panel = p
	p.Name = "SettingsPanel"
	p.Active = true
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.5)
	p.Size = UDim2.new(1, -16, 1, -16)
	p.BackgroundColor3 = Widgets.PANEL
	p.BorderSizePixel = 0
	p.Visible = false
	p.Parent = sheetGui
	Widgets.corner(p, Theme.radius.l)
	Widgets.stroke(p)
	Widgets.bevel(p, true)
	Widgets.padding(p, Theme.space.l, Theme.space.m)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(900, 600)
	limit.Parent = p

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.Parent = p
	local title = Widgets.title(header, "Private server settings", Theme.text.heading, HEADER_HEIGHT)
	title.Size = UDim2.fromScale(0.45, 1)
	Widgets.leadIcon(title, "gear", Theme.icon.small)
	rewardLabel = Widgets.hint(header, "", TEXT_SIZE, HEADER_HEIGHT)
	rewardLabel.Name = "Rewards"
	rewardLabel.Position = UDim2.fromScale(0.45, 0)
	rewardLabel.Size = UDim2.new(0.55, -116, 1, 0)
	local done = Widgets.iconTextButton(header, "check", "Done", 104, Widgets.GOOD, function()
		open = false
		PrivateSettings.render()
	end)
	done.Name = "SettingsDone"
	done.AnchorPoint = Vector2.new(1, 0.5)
	done.Position = UDim2.fromScale(1, 0.5)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, HEADER_HEIGHT + 6)
	body.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 6))
	body.Parent = p
	local left = column(body, 0, 0.52)
	local right = column(body, 0.53, 0.47)

	local map = row(left, 1, "map", "Map")
	option(map, "map", "", "Vote")
	for _, id in Maps.ids do
		option(map, "map", id, Maps.get(id).title)
	end
	local theme = row(left, 2, "palette", "Theme")
	for _, t in Config.Private.Themes do
		option(theme, "theme", t, t)
	end
	local length = row(left, 3, "clock", "Length")
	for _, m in Config.Private.Minutes do
		option(length, "minutes", m, m .. " min")
	end
	local peace = row(left, 4, "peace", "Peace")
	for _, m in Config.Private.PeaceMinutes do
		option(peace, "peaceMinutes", m, if m == 0 then "None" else m .. " min")
	end
	local bots = row(left, 5, "bot", "Bots")
	local function stepBots(delta: number)
		local view = LobbyState.view()
		if view then
			Intents.setting("bots", math.clamp(view.settings.bots + delta, 0, Config.Private.MaxBots))
		end
	end
	local less = Widgets.button(bots, "−", Widgets.BUTTON_HEIGHT, Widgets.BUTTON, function()
		stepBots(-1)
	end)
	less.Name = "BotsLess"
	less.LayoutOrder = 1
	botsLabel = Widgets.label(bots, "", 16, Widgets.BUTTON_HEIGHT)
	botsLabel.FontFace = Theme.font.display
	botsLabel.Size = UDim2.fromOffset(OPTION_WIDTH, Widgets.BUTTON_HEIGHT)
	botsLabel.TextXAlignment = Enum.TextXAlignment.Center
	botsLabel.LayoutOrder = 2
	local more = Widgets.button(bots, "+", Widgets.BUTTON_HEIGHT, Widgets.BUTTON, function()
		stepBots(1)
	end)
	more.Name = "BotsMore"
	more.LayoutOrder = 3
	local level = row(left, 6, "gear", "Bot level")
	for _, d in Config.Private.Difficulties do
		option(level, "difficulty", d, d)
	end

	local powers = row(right, 1, "sparkles", "Powers")
	option(powers, "powers", true, "On")
	option(powers, "powers", false, "Off")
	local disasters = row(right, 2, "meteor", "Disasters")
	option(disasters, "disasters", true, "On")
	option(disasters, "disasters", false, "Off")
	local teamsTitle = Widgets.label(right, "Teams: tap a player (same team = allies)", TEXT_SIZE, 22)
	teamsTitle.LayoutOrder = 3
	Widgets.leadIcon(teamsTitle, "teams", Theme.size.icon)
	teamGrid = Instance.new("Frame")
	teamGrid.Name = "Teams"
	teamGrid.BackgroundTransparency = 1
	teamGrid.Size = UDim2.new(1, 0, 0, 4 * TEAM_CELL.Y + 3 * 4)
	teamGrid.LayoutOrder = 4
	teamGrid.Parent = right
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(TEAM_CELL.X, TEAM_CELL.Y)
	grid.CellPadding = UDim2.fromOffset(4, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = teamGrid
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

	-- the summary: a dark strip with a lock icon and one line, between the Lobby's round buttons and Settings
	local left = Widgets.cornerRowEnd(LOBBY_BUTTONS) + Theme.space.m
	summaryLabel = Widgets.label(gui, "", TEXT_SIZE, Widgets.BUTTON_HEIGHT)
	summaryLabel.Name = "Summary"
	summaryLabel.AnchorPoint = Vector2.new(0, 1)
	summaryLabel.Position = UDim2.new(0, left, 1, -Theme.space.l)
	summaryLabel.Size = UDim2.new(1, -(left + SETTINGS_WIDTH + Theme.space.l + Theme.space.m), 0, Widgets.BUTTON_HEIGHT)
	summaryLabel.BackgroundColor3 = Theme.color.navyDeep
	summaryLabel.BackgroundTransparency = 0.1
	summaryLabel.TextColor3 = Theme.color.goldPale
	summaryLabel.Visible = false
	Widgets.corner(summaryLabel, Theme.radius.m)
	Widgets.stroke(summaryLabel)
	Widgets.padding(summaryLabel, Theme.space.m, 0)
	Widgets.leadIcon(summaryLabel, "lock", Theme.size.icon)

	openButton = Widgets.iconTextButton(gui, "gear", "Settings", SETTINGS_WIDTH, Widgets.BUTTON, function()
		open = true
		PrivateSettings.render()
	end)
	openButton.Name = "SettingsButton"
	openButton.AnchorPoint = Vector2.new(1, 1)
	openButton.Position = UDim2.new(1, -12, 1, -12)
	openButton.Visible = false

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	sheetGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	LobbyState.onChange(function()
		PrivateSettings.render()
	end)
end

return PrivateSettings
