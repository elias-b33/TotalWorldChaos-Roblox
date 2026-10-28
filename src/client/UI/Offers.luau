--!strict
-- Alliance, peace and military access offers made to you, as cards under the top bar with an Accept button. They
-- expire on their own. Each card: the offer with its icon, a countdown chip and the Accept button. Other cards that
-- come to you share the column (Offers.column(): the insult you may answer, above the offers).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Relations = require(Client.Relations)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local WIDTH = 290
local OFFERS_ORDER = 10 -- offers stack under the other cards in the column (their LayoutOrder is below this)

local Offers = {}

local column: Frame
local shownKey = ""

-- The column of cards under the top bar at the right (offers, and the cards other screens add above them), and its
-- cards' width.
function Offers.column(): Frame
	return column
end

Offers.WIDTH = WIDTH

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
	for _, child in column:GetChildren() do
		if child.Name == "Offer" then -- only the offers: other cards share the column
			child:Destroy()
		end
	end
	for i, o in offers do
		local from = ClientState.nation(o.from)
		local name = if from then from.name else "?"
		local card = Widgets.panel(column, WIDTH)
		card.Name = "Offer"
		card.LayoutOrder = OFFERS_ORDER + i
		Widgets.list(card, false, Theme.space.s)
		local text = if o.kind == "Ally"
			then name .. " wants an alliance"
			elseif o.kind == "Access" then name .. " asks to march through your land"
			else name .. " offers peace" .. (if o.tribute > 0 then " +" .. o.tribute .. " gold" else "")
		local line = Widgets.label(card, text, Theme.text.body, 36)
		line.LayoutOrder = 1
		local icon = if o.kind == "Ally" then "handshake" elseif o.kind == "Access" then "access" else "peace"
		Widgets.leadIcon(line, icon, Theme.icon.small)
		local footer = Instance.new("Frame")
		footer.BackgroundTransparency = 1
		footer.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
		footer.LayoutOrder = 2
		footer.Parent = card
		local action = if o.kind == "Ally"
			then "AcceptAlly"
			elseif o.kind == "Access" then "AcceptAccess"
			else "AcceptPeace"
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
	-- under the top bar and the toast line (Hud: the bar + 10, one button tall), so a toast never hides behind a card
	column.Position = UDim2.new(1, -10, 0, Theme.size.bar + 10 + Widgets.BUTTON_HEIGHT + Theme.space.s)
	column.Size = UDim2.fromOffset(WIDTH, 300)
	column.Parent = gui
	Widgets.list(column, false, Theme.space.m)
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
