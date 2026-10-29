--!strict
-- The start menu (docs/DESIGN.md "Match structure"): a brass window over the map for a player arriving on a public
-- or private server, with three big tiles (Play online in gold, Singleplayer, How to play) and under them a line
-- saying what the server is doing (who picks the map, the vote, the draft, a match). The server opens it (the Menu
-- remote) and closes it once it has taken Play online (Intents.playOnline), so a lost tap leaves it open.
--   Singleplayer   three map cards: tap one, tap it again (Intents.enterSandbox), off to a world of your own
--   How to play    five pages of three steps, each an icon and one short line: grow, war, allies, powers, winning
-- ✕ on those two goes back. The window is built while open and dropped when it closes (Widgets.clear), sits above
-- every other screen with the screen dimmed behind it, and fits 667×375 phones and tablets (Widgets.fit).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Remotes = require(Shared.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local LobbyState = require(Client.LobbyState)
local MapVote = require(script.Parent.MapVote)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme

local TILE = Vector2.new(150, 116) -- a tile on the first page, a step in the guide
local CARD = Vector2.new(150, 128) -- a Singleplayer map card
local THUMB_HEIGHT = 72
local GAP = Theme.space.m
local WIDTH = 3 * TILE.X + 2 * GAP + 2 * Widgets.PANEL_PAD
local LINE = 20 -- the status line
local RETRY_SECONDS = 2 -- Play online takes another tap if the server hasn't answered by then
local NOTICE_SECONDS = 6 -- a message from the server stays on the status line this long

type Step = { icon: string, text: string }
type Page = { title: string, icon: string, steps: { Step } }

local function percent(share: number): string
	return string.format("%d%%", math.floor(share * 100 + 0.5))
end

-- How to play: icons over words, one short line per step (the numbers come from Config).
local GUIDE: { Page } = {
	{
		title = "Grow",
		icon = "castle",
		steps = {
			{ icon = "castle", text = "Tap your land: recruit" },
			{ icon = "infantry", text = "Tap your army, a land, Go" },
			{ icon = "flag", text = "Win the siege: it's yours" },
		},
	},
	{
		title = "War and sieges",
		icon = "war",
		steps = {
			{ icon = "peace", text = string.format("%d min of Peace first", Config.Phases.PeaceEndTick // 60) },
			{ icon = "war", text = "Then declare war on a neighbour" },
			{ icon = "hourglass", text = "Stand on enemy land to siege it" },
		},
	},
	{
		title = "Allies",
		icon = "handshake",
		steps = {
			{ icon = "handshake", text = string.format("Alliances of up to %d", Config.Diplomacy.MaxAllianceSize) },
			{ icon = "shield", text = "Allies join your wars" },
			{ icon = "peace", text = "Offer peace to end a war" },
		},
	},
	{
		title = "Primordial powers",
		icon = "sparkles",
		steps = {
			{ icon = "charge", text = "Charges build up over time" },
			{ icon = "meteor", text = "Meteor, Plague, Shield and more" },
			{ icon = "skull", text = "Knocked out? Rise as a Primordial" },
		},
	},
	{
		title = "How to win",
		icon = "crown",
		steps = {
			{ icon = "crown", text = "Hold " .. percent(Config.Win.DominationShare) .. " of the land" },
			{ icon = "handshake", text = "Or " .. percent(Config.Win.AllianceShare) .. " with your allies" },
			{
				icon = "trophy",
				text = string.format("Or the top score at %d:00", Config.Phases.MatchEndTick // 60),
			},
		},
	},
}

local Menu = {}

local gui: ScreenGui
local dim: Frame
local window: Frame? = nil
local status: TextLabel? = nil
local open = false
local page = "Main" -- Main | Maps | Guide
local guidePage = 1
local chosenMap: string? = nil
local mapCards: { [string]: TextButton } = {}
local onlineSentAt = -math.huge
local notice = ""
local noticeUntil = 0
local lastStatus = 0

-- The status line: a message from the server for a few seconds, else what the server is doing.
local function statusText(): string
	if notice ~= "" and os.clock() < noticeUntil then
		return notice
	end
	if page == "Maps" then
		return "🗺 A world of your own: tap a map, tap it again"
	end
	local view = LobbyState.view()
	if view and view.phase == "Lobby" then
		if view.first then
			return if view.chooser ~= 0
				then "🗺 " .. view.chooserName .. " is picking the map"
				else "🗺 The first to tap Play online picks the map"
		end
		local s = LobbyState.secondsLeft()
		return string.format("🗳 Map vote: %d:%02d left", s // 60, s % 60)
	elseif view and view.phase == "Pick" then
		return "🚩 The nation draft is on"
	end
	local snap = ClientState.snapshot()
	if snap and snap.phase == "Results" then
		return "🏆 The next match starts soon"
	elseif snap then
		return "⚔ A match is on: take over a nation"
	end
	return ""
end

local function refreshStatus()
	local label = status
	if label then
		Widgets.setIconText(label, statusText(), "map")
	end
	lastStatus = os.clock()
end

local function addStatus(parent: Frame, order: number)
	local label = Widgets.hint(parent, "", Theme.text.small, LINE)
	label.Name = "MenuStatus"
	label.LayoutOrder = order
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextWrapped = false
	Widgets.leadIcon(label, "map", Theme.size.icon)
	status = label
	refreshStatus()
end

local function row(parent: Frame, order: number, height: number): Frame
	local r = Instance.new("Frame")
	r.Name = "Row" .. order
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, height)
	r.LayoutOrder = order
	r.Parent = parent
	local list = Widgets.list(r, true, GAP)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	return r
end

-- A big button: a 48 px icon over its caption.
local function tile(
	parent: Instance,
	order: number,
	icon: string,
	caption: string,
	color: Color3,
	onPress: () -> ()
): TextButton
	local b = Widgets.button(parent, caption, TILE.X, color, onPress)
	b.Size = UDim2.fromOffset(TILE.X, TILE.Y)
	b.LayoutOrder = order
	b.TextSize = Theme.text.button
	b.TextYAlignment = Enum.TextYAlignment.Bottom
	Widgets.padding(b, Theme.space.s, Theme.space.m)
	local i = Widgets.icon(b, icon, Theme.size.iconLarge)
	i.AnchorPoint = Vector2.new(0.5, 0)
	i.Position = UDim2.new(0.5, 0, 0, Theme.space.xs)
	i.ZIndex = 2
	return b
end

local show: (string) -> () -- below

-- The window for the current page, with its title plate (and ✕ back to the first page on the others).
local function frame(title: string, icon: string, back: boolean): Frame
	if window then
		window:Destroy()
	end
	status = nil
	mapCards = {}
	local f = Widgets.panel(gui, WIDTH, "brass")
	f.Name = "Menu"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, 0, 0.5, Theme.size.titlePlate // 4)
	Widgets.list(f, false, GAP)
	Widgets.header(
		f,
		title,
		icon,
		if back
			then function()
				show("Main")
			end
			else nil
	)
	Widgets.fit(f)
	window = f
	return f
end

local function playOnline()
	if os.clock() - onlineSentAt < RETRY_SECONDS then
		return
	end
	onlineSentAt = os.clock()
	Intents.playOnline()
end

local function buildMain()
	local f = frame("Total World Chaos", "globe", false)
	local tiles = row(f, 1, TILE.Y)
	tile(tiles, 1, "globe", "Play online", Widgets.GOLD, playOnline)
	tile(tiles, 2, "crown", "Singleplayer", Widgets.BUTTON, function()
		Intents.signal("MenuChoice", "singleplayer")
		show("Maps")
	end)
	tile(tiles, 3, "scroll", "How to play", Widgets.BUTTON_OFF, function()
		Intents.signal("MenuChoice", "guide")
		guidePage = 1
		show("Guide")
	end)
	addStatus(f, 2)
end

local function paintCards()
	for id, card in mapCards do
		local chosen = chosenMap == id
		card.BackgroundColor3 = if chosen then Widgets.GOLD else Widgets.BUTTON_OFF
		card.TextColor3 = if chosen then Theme.color.textDark else Theme.color.text
		card.Text = if chosen then "Play " .. Maps.get(id).title else Maps.get(id).title
	end
end

-- Singleplayer: a map card per map; the second tap on one sends you to a world of your own on it.
local function buildMaps()
	local f = frame("Singleplayer", "crown", true)
	local cards = row(f, 1, CARD.Y)
	for i, id in Maps.ids do
		local card = Widgets.button(cards, Maps.get(id).title, CARD.X, Widgets.BUTTON_OFF, function()
			if chosenMap ~= id then
				chosenMap = id
				paintCards()
				return
			end
			Intents.enterSandbox(id)
			notice = "🌍 Off to your world…"
			noticeUntil = os.clock() + NOTICE_SECONDS
			chosenMap = nil
			paintCards()
			refreshStatus()
		end)
		card.Name = "World_" .. id
		card.Size = UDim2.fromOffset(CARD.X, CARD.Y)
		card.LayoutOrder = i
		card.TextYAlignment = Enum.TextYAlignment.Bottom
		Widgets.padding(card, Theme.space.s, Theme.space.s)
		local holder = Instance.new("Frame")
		holder.Name = "ThumbHolder"
		holder.Size = UDim2.new(1, 0, 0, THUMB_HEIGHT)
		holder.BorderSizePixel = 0
		holder.ZIndex = 2
		holder.Parent = card
		Widgets.corner(holder, Theme.radius.s)
		Widgets.stroke(holder)
		MapVote.thumbnail(holder, id)
		mapCards[id] = card
	end
	paintCards()
	addStatus(f, 2)
end

-- How to play: one page of the guide, a pager under it.
local function buildGuide()
	local data = GUIDE[guidePage]
	local f = frame("How to play", "scroll", true)
	local heading = Widgets.title(f, data.title, Theme.text.title, Theme.size.iconButton)
	heading.Name = "GuideTitle"
	heading.LayoutOrder = 1
	Widgets.leadIcon(heading, data.icon, Theme.size.iconButton)
	local steps = row(f, 2, TILE.Y)
	for i, step in data.steps do
		local cell = Widgets.card(steps, TILE.X, TILE.Y)
		cell.Name = "Step" .. i
		cell.LayoutOrder = i
		local icon = Widgets.icon(cell, step.icon, Theme.size.iconLarge)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.fromScale(0.5, 0)
		local text = Widgets.label(cell, step.text, Theme.text.body, 40)
		text.AnchorPoint = Vector2.new(0, 1)
		text.Position = UDim2.fromScale(0, 1)
		text.TextXAlignment = Enum.TextXAlignment.Center
	end
	local footer = row(f, 3, Widgets.BUTTON_HEIGHT)
	local _, label = Widgets.pager(footer, function()
		guidePage = if guidePage > 1 then guidePage - 1 else #GUIDE
		show("Guide")
	end, function()
		guidePage = if guidePage < #GUIDE then guidePage + 1 else 1
		show("Guide")
	end)
	label.Text = string.format("%d/%d", guidePage, #GUIDE)
end

show = function(name: string)
	page = name
	chosenMap = nil
	if name == "Maps" then
		buildMaps()
	elseif name == "Guide" then
		buildGuide()
	else
		buildMain()
	end
end

local function setOpen(on: boolean)
	open = on
	dim.Visible = on
	if on then
		notice = ""
		show("Main")
	else
		if window then
			window:Destroy()
		end
		window = nil
		status = nil
		mapCards = {}
	end
end

-- Is the start menu on screen?
function Menu.isOpen(): boolean
	return open
end

function Menu.init()
	gui = Widgets.screen("Menu", 40) -- above every other screen: the lobby, the shop and the meta screens
	Widgets.coverScreen(gui) -- the dim covers Roblox's top-bar row too, and the window centres on the whole screen
	dim = Instance.new("Frame")
	dim.Name = "MenuDim"
	dim.Active = true -- nothing behind the menu can be tapped
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Theme.color.slate950
	dim.BackgroundTransparency = 0.4
	dim.BorderSizePixel = 0
	dim.Visible = false
	dim.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Remotes.event("Menu").OnClientEvent:Connect(function(on: boolean)
		setOpen(on == true)
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(_kind: string, text: string)
		if open then -- the toasts are under the menu: its status line shows the message instead
			notice = text
			noticeUntil = os.clock() + NOTICE_SECONDS
			refreshStatus()
		end
	end)
	LobbyState.onChange(function()
		if open then
			refreshStatus()
		end
	end)
	RunService.Heartbeat:Connect(function()
		if open and os.clock() - lastStatus >= 0.5 then
			refreshStatus() -- the vote's clock, and a message running out
		end
	end)
end

return Menu
