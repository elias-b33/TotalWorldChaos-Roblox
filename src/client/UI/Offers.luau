--!strict
-- Alliance and peace offers made to you, as cards under the top bar with an Accept button. They expire on their own.
-- Each card: the offer with its icon, a countdown chip and the Accept button.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Relations = require(Client.Relations)
local HudLayout = require(script.Parent.HudLayout)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local WIDTH = 290

local Offers = {}

local column: Frame
local shownKey = ""

local function render()
	local me = ClientState.myNation()
	local offers = Relations.offersTo(me)
	local tick = ClientState.tick()
	local keyParts = {}
	for _, o in offers do
		table.insert(keyParts, o.id .. ":" .. (o.expiresAt - tick))
	end
	local key = table.concat(keyParts, ",")
	if key == shownKey then
		return
	end
	shownKey = key
	Widgets.clear(column)
	for i, o in offers do
		local from = ClientState.nation(o.from)
		local name = if from then from.name else "?"
		local card = Widgets.panel(column, WIDTH)
		card.Name = "Offer"
		card.LayoutOrder = i
		Widgets.list(card, false, Theme.space.s)
		local text = if o.kind == "Ally"
			then name .. " wants an alliance"
			else name .. " offers peace" .. (if o.tribute > 0 then " +" .. o.tribute .. " gold" else "")
		local line = Widgets.label(card, text, Theme.text.body, 36)
		line.LayoutOrder = 1
		Widgets.leadIcon(line, if o.kind == "Ally" then "handshake" else "peace", Theme.icon.small)
		local footer = Instance.new("Frame")
		footer.BackgroundTransparency = 1
		footer.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
		footer.LayoutOrder = 2
		footer.Parent = card
		local action = if o.kind == "Ally" then "AcceptAlly" else "AcceptPeace"
		local fromId = o.from
		Widgets.iconTextButton(footer, "check", "Accept", 130, Widgets.GOOD, function()
			Intents.diplomacy(action, fromId)
		end, "✅ Accept")
		local timer = Widgets.chip(footer, "hourglass", tostring(math.max(0, o.expiresAt - tick)) .. " s", 80)
		timer.AnchorPoint = Vector2.new(1, 0.5)
		timer.Position = UDim2.fromScale(1, 0.5)
	end
end

function Offers.init()
	local gui = Widgets.screen("Offers", 3)
	column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(1, 0)
	column.Size = UDim2.fromOffset(WIDTH, 300)
	column.Parent = gui
	Widgets.list(column, false, Theme.space.m)
	local function place()
		Widgets.fit(column, nil, UDim2.new(1, -10, 0, HudLayout.contentTop()))
	end
	place()
	HudLayout.onChange(place)
	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- once a second is plenty: offers change with deltas and count down slowly
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 then
			acc = 0
			render()
		end
	end)
end

return Offers
