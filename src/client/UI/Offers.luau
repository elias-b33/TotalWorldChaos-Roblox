--!strict
-- Alliance and peace offers made to you, as cards under the top bar with an Accept button. They expire on their own.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Relations = require(Client.Relations)
local Widgets = require(script.Parent.Widgets)

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
		local card = Widgets.panel(column, 290)
		card.LayoutOrder = i
		Widgets.list(card, false, 6)
		local text = if o.kind == "Ally"
			then "🤝 " .. name .. " wants an alliance"
			else "🕊 " .. name .. " offers peace" .. (if o.tribute > 0 then " +💰" .. o.tribute else "")
		Widgets.label(card, string.format("%s  ⌛%d", text, math.max(0, o.expiresAt - tick)), 14, 36)
		local action = if o.kind == "Ally" then "AcceptAlly" else "AcceptPeace"
		local fromId = o.from
		Widgets.button(card, "✅ Accept", 120, Widgets.GOOD, function()
			Intents.diplomacy(action, fromId)
		end).LayoutOrder =
			2
	end
end

function Offers.init()
	local gui = Widgets.screen("Offers", 3)
	column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(1, 0)
	column.Position = UDim2.new(1, -8, 0, 52)
	column.Size = UDim2.fromOffset(290, 300)
	column.Parent = gui
	Widgets.list(column, false, 6)
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
