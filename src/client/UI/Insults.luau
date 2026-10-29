--!strict
-- The answer card for an insult (docs/DESIGN.md "Diplomacy", the EU4 pack): when another nation insults you, a card
-- in the offers column at the top right (until its window closes) shows the timer, your grudge, and two answers:
-- Insult back and Laugh it off. Insults carry no message (Roblox's preset-text rule), so the card only offers game
-- actions; the server checks everything (Sim.Diplomacy). Built from the UI kit like the event card above it: an iron
-- panel with "Answer <nation>" on its title plate, an info row (your grudge, and the seconds left in a chip) and the
-- two answers side by side.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Relations = require(Client.Relations)
local Offers = require(script.Parent.Offers)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local CARD_ORDER = 2 -- in the offers column: under the event card (0), above the offers (10 and up)
local PLATE_ROOM = 14 -- the title plate rides this far above the card's top edge
local ANSWER_HEIGHT = 52 -- the two answer buttons: at least 44 px tall on phones
local INFO_HEIGHT = 34 -- the grudge (two lines at most) and the countdown in a chip, as on the event card
local TIMER_HEIGHT = 24
local TIMER_WIDTH = 76

local Insults = {}

local card: Frame? = nil
local gap: Frame? = nil
local cardKey = ""
local cardTimer: TextLabel? = nil
local cardGrudge: TextLabel? = nil

local function nationName(id: number): string
	local n = ClientState.nation(id)
	return if n then n.name else "?"
end

local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function percent(bonus: number): number
	return math.floor(bonus * 100 + 0.5)
end

local function dropCard()
	if card then
		card:Destroy()
	end
	if gap then
		gap:Destroy()
	end
	card, gap, cardTimer, cardGrudge, cardKey = nil, nil, nil, nil, ""
end

local function renderCard()
	local me = ClientState.myNation()
	local mine = ClientState.nation(me)
	local window = if mine and not mine.eliminated then Relations.answerFor(me) else nil
	if window == nil then
		dropCard()
		return
	end
	local left = math.max(0, window.untilTick - ClientState.tick())
	local grudge = Relations.grudge(me, window.to)
	local grudgeText =
		string.format("Grudge: +%d%% vs them for %s", percent(Config.Diplomacy.GrudgeBonus), clock(grudge))
	local key = window.to .. ":" .. window.untilTick
	if key == cardKey and card then
		if cardTimer then
			cardTimer.Text = left .. " s"
		end
		if cardGrudge then
			cardGrudge.Text = grudgeText
		end
		return
	end
	dropCard()
	cardKey = key
	local column = Offers.column()
	local room = Instance.new("Frame")
	room.Name = "AnswerGap"
	room.BackgroundTransparency = 1
	room.Size = UDim2.new(1, 0, 0, PLATE_ROOM)
	room.LayoutOrder = CARD_ORDER - 1
	room.Parent = column
	gap = room
	local made = Widgets.panel(column, Offers.WIDTH)
	made.Name = "Answer"
	made.LayoutOrder = CARD_ORDER
	Widgets.list(made, false, Theme.space.s)
	Widgets.header(made, "Answer " .. nationName(window.to), "grudge")
	card = made
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, 0, 0, INFO_HEIGHT)
	info.LayoutOrder = 1
	info.Parent = made
	local hint = Widgets.hint(info, grudgeText, Theme.text.small, INFO_HEIGHT)
	hint.Name = "Grudge"
	hint.Size = UDim2.new(1, -(TIMER_WIDTH + Theme.space.s), 1, 0)
	cardGrudge = hint
	local timer = Widgets.chip(info, "hourglass", left .. " s", TIMER_WIDTH, TIMER_HEIGHT)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(1, 0.5)
	timer.Position = UDim2.fromScale(1, 0.5)
	cardTimer = timer
	local row = Instance.new("Frame")
	row.Name = "Answers"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, ANSWER_HEIGHT)
	row.LayoutOrder = 3
	row.Parent = made
	Widgets.list(row, true, Theme.space.s)
	local insulter = window.to
	local size = Vector2.new(0, ANSWER_HEIGHT)
	-- insult back: they hold a grudge against you too; laugh it off: your grudge turns into high spirits
	local back = Widgets.actionButton(row, "grudge", "Insult back", {}, size, Widgets.DANGER, function()
		Intents.diplomacy("InsultBack", insulter)
		dropCard()
	end, "InsultBack")
	local spirits = string.format("+%d%% %s", percent(Config.Diplomacy.LaughBonus), clock(Config.Diplomacy.LaughTicks))
	local laugh = Widgets.actionButton(
		row,
		"smile",
		"Laugh it off",
		{ { "sword", spirits } },
		size,
		Widgets.GOOD,
		function()
			Intents.diplomacy("LaughOff", insulter)
			dropCard()
		end,
		"LaughOff"
	)
	for i, b in { back, laugh } do
		b.Size = UDim2.new(0.5, -Theme.space.s // 2, 0, ANSWER_HEIGHT)
		b.LayoutOrder = i
	end
end

function Insults.init()
	ClientState.onReset(dropCard)
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
