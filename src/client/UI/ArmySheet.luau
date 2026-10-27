--!strict
-- Bottom sheet while an army is selected (docs/DESIGN.md "Moving armies"): tap the army, tap the destination,
-- see the route and arrival time, tap Go.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Relations = require(Client.Relations)
local Widgets = require(script.Parent.Widgets)

local ArmySheet = {}

local sheet: Frame
local title: TextLabel
local hint: TextLabel
local buttons: Frame
local current: { army: number, dest: number?, path: { number }? }? = nil
local onGo: ((number, number) -> ())? = nil
local onCancel: (() -> ())? = nil

local function shortMen(men: number): string
	return if men >= 1000 then string.format("%gk", math.floor(men / 100) / 10) else tostring(men)
end

local function render()
	local sel = current
	local army = if sel then ClientState.army(sel.army) else nil
	local map = ClientState.map()
	if sel == nil or army == nil or map == nil then
		sheet.Visible = false
		return
	end
	title.Text = string.format("⚔ %s at %s", shortMen(army.men), map.provinces[army.location].name)
	Widgets.clear(buttons)
	local dest, path = sel.dest, sel.path
	if dest and path then
		hint.Text = string.format("➜ %s  ·  ⏱ %d s", map.provinces[dest].name, Relations.travelTime(path))
		local armyId = sel.army
		Widgets.button(buttons, "✅ Go", 120, Widgets.GOOD, function()
			if onGo then
				onGo(armyId, dest)
			end
		end)
	elseif army.inBattle then
		hint.Text = "💥 In battle: wait for it to end"
	elseif army.dest ~= 0 then
		hint.Text = string.format("➜ marching to %s · tap a new destination", map.provinces[army.dest].name)
	else
		hint.Text = "👆 Tap where to go"
	end
	Widgets.button(buttons, "✕ Cancel", 120, Widgets.BUTTON_OFF, function()
		if onCancel then
			onCancel()
		end
	end)
	sheet.Visible = true
end

function ArmySheet.show(armyId: number?, dest: number?, path: { number }?)
	current = if armyId then { army = armyId, dest = dest, path = path } else nil
	render()
end

function ArmySheet.init(goHandler: (number, number) -> (), cancelHandler: () -> ())
	onGo = goHandler
	onCancel = cancelHandler
	local gui = Widgets.screen("ArmySheet", 2)
	sheet = Widgets.panel(gui, 420)
	sheet.Name = "Sheet"
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -8)
	sheet.Visible = false
	Widgets.list(sheet, false, 6)
	title = Widgets.label(sheet, "", 18, 26)
	title.LayoutOrder = 1
	hint = Widgets.label(sheet, "", 15, 22)
	hint.LayoutOrder = 2
	buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	buttons.LayoutOrder = 3
	buttons.Parent = sheet
	Widgets.list(buttons, true, 8)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onDelta(function(delta)
		local sel = current
		if sel == nil then
			return
		end
		for _, a in delta.armies do
			if a.id == sel.army then
				render()
				return
			end
		end
		for _, id in delta.removedArmies do
			if id == sel.army then
				if onCancel then
					onCancel() -- the army is gone
				end
				return
			end
		end
	end)
	ClientState.onReset(function()
		ArmySheet.show(nil)
	end)
end

return ArmySheet
