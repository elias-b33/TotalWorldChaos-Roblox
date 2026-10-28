--!strict
-- Insults (docs/DESIGN.md "Diplomacy", the EU4 pack): the picker of pre-written joke insults for this map (a bottom
-- sheet opened by the province sheet's Insult button: a few lines at a time, "Others" shows the next ones), and the
-- card that lets you answer an insult with a pre-written comeback (in the offers column at the top right, until its
-- window closes). Lines come from Shared.Flavour.Insults; players only ever send a line's number, and the server
-- checks everything (Sim.Diplomacy). Built from the UI kit.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local InsultLines = require(Shared.Flavour.Insults)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Relations = require(Client.Relations)
local Offers = require(script.Parent.Offers)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local SHEET_WIDTH = 440
local PAGE = 4 -- lines the picker shows at once
local LINE_HEIGHT = Widgets.BUTTON_HEIGHT
local CARD_ORDER = 1 -- in the offers column: above the offers
local CARD_OPTIONS = 2 -- comebacks the card offers (of the map's pool)

local Insults = {}

local sheet: Frame
local title: TextLabel
local lines: Frame
local target: number? = nil
local page = 0
local onOpen: (() -> ())? = nil

local card: Frame? = nil
local cardKey = ""
local cardTimer: TextLabel? = nil

local function mapId(): string
	local snap = ClientState.snapshot()
	return if snap then snap.mapId else ""
end

local function nationName(id: number): string
	local n = ClientState.nation(id)
	return if n then n.name else "?"
end

local function quoted(text: string): string
	return "“" .. text .. "”"
end

-- The picker ---------------------------------------------------------------------------------------------------

local function renderPicker()
	Widgets.clear(lines)
	local who = target
	if who == nil then
		sheet.Visible = false
		return
	end
	title.Text = "Insult " .. nationName(who)
	local pool = InsultLines.lines(mapId(), "insults")
	local first = (page * PAGE) % math.max(#pool, 1)
	for k = 0, math.min(PAGE, #pool) - 1 do
		local index = (first + k) % #pool + 1
		local b = Widgets.button(lines, quoted(pool[index]), SHEET_WIDTH, Widgets.BUTTON_OFF, function()
			Intents.diplomacy("Insult", who, 0, index)
			Insults.close()
		end)
		b.Name = "Insult_" .. index
		b.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
		b.TextSize = Theme.text.small
		b.FontFace = Theme.font.body
		b.LayoutOrder = k
		Widgets.padding(b, Theme.space.m, 0)
	end
	sheet.Visible = true
end

-- Open the picker for an insult to `nationId` (the province sheet's Insult button).
function Insults.open(nationId: number)
	if onOpen then
		onOpen() -- the picker replaces any open sheet
	end
	target = nationId
	page = 0
	renderPicker()
end

function Insults.close()
	target = nil
	renderPicker()
end

function Insults.isOpen(): boolean
	return target ~= nil
end

-- The comeback card ------------------------------------------------------------------------------------------------

local function dropCard()
	if card then
		card:Destroy()
	end
	card, cardTimer, cardKey = nil, nil, ""
end

local function renderCard()
	local me = ClientState.myNation()
	local mine = ClientState.nation(me)
	local window = if mine and not mine.eliminated then Relations.comebackFor(me) else nil
	if window == nil then
		dropCard()
		return
	end
	local left = math.max(0, window.untilTick - ClientState.tick())
	local key = window.to .. ":" .. window.untilTick
	if key == cardKey and card then
		if cardTimer then
			cardTimer.Text = left .. " s"
		end
		return
	end
	dropCard()
	cardKey = key
	local made = Widgets.panel(Offers.column(), Offers.WIDTH)
	made.Name = "Comeback"
	made.LayoutOrder = CARD_ORDER
	Widgets.list(made, false, Theme.space.s)
	card = made
	local head = Instance.new("Frame")
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, 30)
	head.LayoutOrder = 1
	head.Parent = made
	local heading = Widgets.title(head, "Answer " .. nationName(window.to), Theme.text.body, 30)
	heading.Size = UDim2.new(1, -72, 1, 0)
	Widgets.leadIcon(heading, "speech", Theme.size.icon)
	local timer = Widgets.chip(head, "hourglass", left .. " s", 66, 28)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(1, 0.5)
	timer.Position = UDim2.fromScale(1, 0.5)
	cardTimer = timer
	local grudge = Relations.grudge(me, window.to)
	if grudge > 0 then
		local hint = Widgets.hint(
			made,
			string.format(
				"Grudge: +%d%% in battles against them for %d:%02d",
				math.floor(Config.Diplomacy.GrudgeBonus * 100 + 0.5),
				grudge // 60,
				grudge % 60
			),
			Theme.text.small,
			20
		)
		hint.Name = "Grudge"
		hint.LayoutOrder = 2
	end
	-- a couple of the map's comebacks, picked from the insult so every card offers different ones
	local pool = InsultLines.lines(mapId(), "comebacks")
	local insulter = window.to
	for k = 0, math.min(CARD_OPTIONS, #pool) - 1 do
		local index = (window.line + window.untilTick + k) % #pool + 1
		local b = Widgets.button(made, quoted(pool[index]), Offers.WIDTH, Widgets.BUTTON, function()
			Intents.diplomacy("Comeback", insulter, 0, index)
			dropCard()
		end)
		b.Name = "Comeback_" .. index
		b.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
		b.TextSize = Theme.text.small
		b.FontFace = Theme.font.body
		b.LayoutOrder = 3 + k
		Widgets.padding(b, Theme.space.s, 0)
	end
end

-- onOpenHandler: closes the other sheets when the picker opens.
function Insults.init(onOpenHandler: () -> ())
	onOpen = onOpenHandler
	local gui = Widgets.screen("Insults", 2)
	sheet = Widgets.sheet(gui, SHEET_WIDTH)
	sheet.Name = "Sheet"
	sheet.Visible = false
	Widgets.list(sheet, false, Theme.space.s)
	local header
	header, title = Widgets.header(sheet, "", "speech", Insults.close)
	header.LayoutOrder = 1
	lines = Instance.new("Frame")
	lines.Name = "Lines"
	lines.BackgroundTransparency = 1
	lines.Size = UDim2.fromScale(1, 0)
	lines.AutomaticSize = Enum.AutomaticSize.Y
	lines.LayoutOrder = 2
	lines.Parent = sheet
	Widgets.list(lines, false, Theme.space.s)
	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	footer.LayoutOrder = 3
	footer.Parent = sheet
	local more = Widgets.iconTextButton(footer, "reroll", "Others", 140, Widgets.BUTTON, function()
		page += 1
		renderPicker()
	end, "InsultOthers")
	more.AnchorPoint = Vector2.new(0, 0.5)
	more.Position = UDim2.fromScale(0, 0.5)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onReset(function()
		Insults.close()
		dropCard()
	end)
	ClientState.onDelta(function(delta)
		if delta.diplomacy or #delta.nations > 0 then
			renderCard()
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 then
			acc = 0
			renderCard() -- the countdown, and the window closing
		end
	end)
end

return Insults
