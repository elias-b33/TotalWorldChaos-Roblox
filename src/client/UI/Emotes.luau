--!strict
-- Capital emotes (docs/MONETIZATION.md 3.2): a 😀 button in the bottom-left corner, during a match, once you own an
-- emote. It opens a row of your emotes; tapping one shows it over your capital to everyone for a few seconds.
-- Icons only, no text chat. The server checks ownership and the cooldown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local ShopState = require(Client.ShopState)
local Widgets = require(script.Parent.Widgets)

local BUTTON_SIZE = 52
local EMOTE_BUTTON = 48

local Emotes = {}

local button: TextButton
local picker: Frame

local function owned(): { string }
	local out = {}
	for _, item in Catalogue.ofSlot("Emote") do
		if ShopState.owns(item.id) then
			table.insert(out, item.id)
		end
	end
	return out
end

local function inMatch(): boolean
	local snap = ClientState.snapshot()
	local me = ClientState.nation(ClientState.myNation())
	return snap ~= nil and snap.result == nil and me ~= nil and not me.eliminated
end

local function refresh()
	local show = inMatch() and #owned() > 0
	button.Visible = show
	if not show then
		picker.Visible = false
	end
end

local function renderPicker()
	Widgets.clear(picker)
	local ids = owned()
	picker.Size = UDim2.fromOffset(#ids * (EMOTE_BUTTON + 6) + 14, 0)
	for i, id in ids do
		local item = Catalogue.item(id)
		if item then
			local b = Widgets.button(picker, item.art, EMOTE_BUTTON, Widgets.BUTTON_OFF, function()
				picker.Visible = false
				Intents.emote(id)
			end)
			b.Name = "Emote_" .. id
			b.TextSize = 24
			b.LayoutOrder = i
		end
	end
end

function Emotes.init()
	local gui = Widgets.screen("Emotes", 3) -- under the nations drawer, which can cover the corner
	button = Instance.new("TextButton")
	button.Name = "EmoteButton"
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position = UDim2.new(0, 12, 1, -12)
	button.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(70, 72, 110)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 24
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = "😀"
	button.Visible = false
	button.Parent = gui
	Widgets.corner(button, BUTTON_SIZE // 2)
	button.Activated:Connect(function()
		picker.Visible = not picker.Visible
		if picker.Visible then
			renderPicker()
		end
	end)

	picker = Widgets.panel(gui, 0)
	picker.Name = "EmotePicker"
	picker.AnchorPoint = Vector2.new(0, 1)
	picker.Position = UDim2.new(0, 12, 1, -BUTTON_SIZE - 20)
	picker.Visible = false
	Widgets.list(picker, true, 6)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ShopState.onChange(function()
		refresh()
	end)
	ClientState.onReset(function()
		refresh()
	end)
	ClientState.onDelta(function(delta)
		if #delta.nations > 0 or delta.result then
			refresh()
		end
	end)
end

return Emotes
