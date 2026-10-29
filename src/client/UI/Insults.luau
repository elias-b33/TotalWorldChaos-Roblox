--!strict
-- The answer card for an insult (docs/DESIGN.md "Diplomacy", the EU4 pack): when another nation insults you, a card
-- in the offers column at the top right (until its window closes) shows the timer, your grudge, and two answers:
-- Insult back and Laugh it off. Insults carry no message (Roblox's preset-text rule), so the card only offers game
-- actions; the server checks everything (Sim.Diplomacy). Built from the UI kit.

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
local CARD_ORDER = 1 -- in the offers column: above the offers
local ANSWER_HEIGHT = 52 -- the two answer buttons: at least 44 px tall on phones

local Insults = {}

local card: Frame? = nil
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
	card, cardTimer, cardGrudge, cardKey = nil, nil, nil, ""
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
	local made = Widgets.panel(Offers.column(), Offers.WIDTH)
	made.Name = "Answer"
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
	Widgets.leadIcon(heading, "grudge", Theme.size.icon)
	local timer = Widgets.chip(head, "hourglass", left .. " s", 66, 28)
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(1, 0.5)
	timer.Position = UDim2.fromScale(1, 0.5)
	cardTimer = timer
	local hint = Widgets.hint(made, grudgeText, Theme.text.small, 20)
	hint.Name = "Grudge"
	hint.LayoutOrder = 2
	cardGrudge = hint
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
