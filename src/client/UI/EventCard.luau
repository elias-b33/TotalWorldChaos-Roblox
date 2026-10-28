--!strict
-- The EU4 pack's event cards (docs/DESIGN.md "Events"): every few minutes your nation gets a card at the top right,
-- first in the offers column: an iron panel with the event's title on its plate, a line of flavour, where it happens,
-- a countdown and two choices side by side, each with its effects as icon chips. It stays short (about 160 px) so it
-- clears the power button at the bottom right of a phone. Tap one; when time runs out the default happens.
-- Choices you can't pay for are grey. After a card closes a toast says what happened.
-- The server tells this client about its own nation's cards only (Replicator.sendCards), by event id: the words come
-- from Shared.Flavour.EventCards and are shown here and nowhere else. Built from the UI kit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local EventCards = require(Shared.Sim.EventCards)
local EventText = require(Shared.Flavour.EventCards)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Offers = require(script.Parent.Offers)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local CARD_ORDER = 0 -- in the offers column: above the insult card (1) and the offers (10 and up)
local PLATE_ROOM = 14 -- the title plate rides this far above the card's top edge
local CHOICE_HEIGHT = 52 -- at least 44 px tall on phones; the two sit side by side, so the card stays short
local INFO_HEIGHT = 24 -- the province and the countdown
local TIMER_WIDTH = 76
local BOOST_MINUTES = Config.EventCards.BoostTicks * Config.TickSeconds // 60

local EventCard = {}

type Shown = { button: TextButton, choice: EventCards.Choice, can: boolean }

local view: Types.EventCardView? = nil
local card: Frame? = nil
local gap: Frame? = nil
local timer: TextLabel? = nil
local buttons: { Shown } = {}
local shownCard = 0 -- the card on screen (0 = none)
local shownHere: { [number]: boolean } = {} -- cards this client showed: only their outcome gets a toast
local toldCard = 0 -- the last closed card the toast told about
local toast: ((string) -> ())? = nil

local function provinceName(id: number): string
	local map = ClientState.map()
	return if map and map.provinces[id] then map.provinces[id].name else "?"
end

local function drop()
	if card then
		card:Destroy()
	end
	if gap then
		gap:Destroy()
	end
	card, gap, timer, buttons, shownCard = nil, nil, nil, {}, 0
end

local function affordable(choice: EventCards.Choice): boolean
	local me = ClientState.nation(ClientState.myNation())
	if me == nil then
		return false
	end
	return me.gold >= -math.min(0, choice.gold or 0) and me.manpower >= -math.min(0, choice.manpower or 0)
end

-- The countdown and which choices you can pay for, once a second.
local function refresh()
	local v = view
	if card == nil or v == nil then
		return
	end
	local left = v.untilTick - ClientState.tick()
	if left < -2 then
		drop() -- the server closed it (its default happened); the toast comes with the next view
		return
	end
	if timer then
		timer.Text = math.max(0, left) .. " s"
	end
	for _, shown in buttons do
		local can = affordable(shown.choice)
		if can ~= shown.can then
			shown.can = can
			Widgets.setEnabled(shown.button, can)
		end
	end
end

-- A choice's button, half the card wide so the two sit side by side: its name at the top, its effects as icon chips
-- at the bottom (Widgets.actionButton's layout without the big lead icon, which leaves no room for a name).
local function choiceButton(parent: Instance, caption: string, chips: { { string } }, onPress: () -> ()): TextButton
	local b = Widgets.button(parent, caption, 0, Widgets.BUTTON, onPress)
	b.Size = UDim2.new(0.5, -Theme.space.s // 2, 0, CHOICE_HEIGHT)
	b.TextSize = Theme.text.small + 1
	b.TextWrapped = false
	b.TextTruncate = Enum.TextTruncate.AtEnd
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.TextYAlignment = Enum.TextYAlignment.Top
	local skinned = Widgets.skinned(b)
	local pad = Widgets.padding(b, Theme.space.s, 0)
	pad.PaddingTop = UDim.new(0, if skinned then 5 else 7)
	pad.PaddingBottom = UDim.new(0, if skinned then 14 else 9)
	local row = Instance.new("Frame")
	row.Name = "Effects"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0, 1)
	row.Position = UDim2.fromScale(0, 1)
	row.Size = UDim2.new(1, 0, 0, 16)
	row.ZIndex = 2
	row.Parent = b
	Widgets.list(row, true, Theme.space.xs)
	for i, chip in chips do
		local l = Widgets.label(row, chip[2], Theme.text.small, 16)
		l.Name = "Effect"
		l.FontFace = Theme.font.display
		l.TextColor3 = if chip[1] == "gold" then Theme.color.gold else Theme.color.text
		l.Size = UDim2.fromOffset(0, 16)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.TextWrapped = false
		l.LayoutOrder = i
		l.ZIndex = 2
		Widgets.textStroke(l, 1.5)
		Widgets.leadIcon(l, chip[1], Theme.size.icon, 2)
	end
	return b
end

local function build(v: Types.EventCardView)
	drop()
	local text = EventText.TEXT[v.event]
	local def = EventCards.def(v.event)
	if text == nil or def == nil then
		return
	end
	local column = Offers.column()
	local room = Instance.new("Frame")
	room.Name = "EventGap"
	room.BackgroundTransparency = 1
	room.Size = UDim2.new(1, 0, 0, PLATE_ROOM)
	room.LayoutOrder = CARD_ORDER - 1
	room.Parent = column
	gap = room
	local made = Widgets.panel(column, Offers.WIDTH)
	made.Name = "EventCard"
	made.LayoutOrder = CARD_ORDER
	Widgets.list(made, false, Theme.space.s)
	Widgets.header(made, text.title, "scroll")
	card = made
	shownCard = v.card
	shownHere[v.card] = true
	local line = Widgets.hint(made, text.line, Theme.text.small, 34)
	line.Name = "Flavour"
	line.LayoutOrder = 1
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.BackgroundTransparency = 1
	info.Size = UDim2.new(1, 0, 0, INFO_HEIGHT)
	info.LayoutOrder = 2
	info.Parent = made
	if v.province ~= 0 then
		local where = Widgets.hint(info, "In " .. provinceName(v.province), Theme.text.small, INFO_HEIGHT)
		where.Name = "Where"
		where.Size = UDim2.new(1, -(TIMER_WIDTH + Theme.space.s), 1, 0)
		where.TextTruncate = Enum.TextTruncate.AtEnd
		Widgets.leadIcon(where, "flag", Theme.size.icon)
	end
	local left = math.max(0, v.untilTick - ClientState.tick())
	local clock = Widgets.chip(info, "hourglass", left .. " s", TIMER_WIDTH, INFO_HEIGHT)
	clock.Name = "EventTimer"
	clock.AnchorPoint = Vector2.new(1, 0.5)
	clock.Position = UDim2.fromScale(1, 0.5)
	timer = clock
	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, CHOICE_HEIGHT)
	row.LayoutOrder = 3
	row.Parent = made
	Widgets.list(row, true, Theme.space.s)
	local cardId = v.card
	for i, choice in def.choices do
		local b = choiceButton(row, text.choices[i], EventText.chips(choice, BOOST_MINUTES), function()
			if affordable(choice) then
				Intents.eventChoice(cardId, i)
				drop()
			end
		end)
		b.Name = "EventChoice" .. i
		b.LayoutOrder = i
		table.insert(buttons, { button = b, choice = choice, can = true })
	end
	refresh()
end

-- What happened to the last card this client showed: "📜 Sell the extra: +50 gold", or "⌛ Time's up! …".
local function tell(v: Types.EventCardView)
	if v.lastCard == 0 or v.lastCard == toldCard or not shownHere[v.lastCard] then
		return
	end
	toldCard = v.lastCard
	local text = EventText.TEXT[v.lastEvent]
	local def = EventCards.def(v.lastEvent)
	local choice = if def then def.choices[v.lastChoice] else nil
	if text == nil or choice == nil then
		return
	end
	local place = if v.lastProvince ~= 0 then provinceName(v.lastProvince) else nil
	local said = text.choices[v.lastChoice] .. ": " .. EventText.summary(choice, BOOST_MINUTES, place)
	if toast then
		toast(if v.lastAuto then "⌛ Time's up! " .. said else "📜 " .. said)
	end
end

local function onView(v: Types.EventCardView)
	view = v
	tell(v)
	if v.card == 0 then
		drop()
	elseif v.card ~= shownCard then
		build(v)
	end
end

-- showToast: Hud.toast (the outcome of a card).
function EventCard.init(showToast: (string) -> ())
	toast = showToast
	ClientState.onReset(function()
		drop()
		view = nil
		shownHere = {}
		toldCard = 0
	end)
	Remotes.event("EventCard").OnClientEvent:Connect(onView)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 then
			acc = 0
			refresh()
		end
	end)
end

return EventCard
