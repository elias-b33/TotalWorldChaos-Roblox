--!strict
-- Bottom sheet while an army is selected (docs/DESIGN.md "Moving armies"): tap the army, tap the destination,
-- see the route and arrival time, tap Go. Built from the UI kit: a title with the army's size, its composition as
-- chips (a troop icon and its men each, docs/DESIGN.md "Troops"; with its name while three or fewer types fit the
-- row), its special's trick when it has one, a hint line with an icon, and Go / Cancel buttons.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local NAMED_CHIPS = 3 -- up to this many troop types, a chip shows the troop's name; more show the icon and men only

local ArmySheet = {}

local sheet: Frame
local title: TextLabel
local chips: Frame
local trick: TextLabel
local hint: TextLabel
local hintIcon: GuiObject
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
		Widgets.clear(buttons) -- rebuilt when it opens
		Widgets.clear(chips)
		return
	end
	title.Text = string.format("%s at %s", shortMen(army.men), map.provinces[army.location].name)
	-- the composition: one chip per troop type in the stack, in role order; and its special's trick
	Widgets.clear(chips)
	local parts = RaceInfo.composition(army.troops)
	local trickText = ""
	for i, part in parts do
		local text = shortMen(part.men)
		if #parts <= NAMED_CHIPS then
			text ..= " " .. RaceInfo.troopName(part.troop)
		end
		local chip = Widgets.chip(chips, RaceInfo.troopIcon(part.troop), text, nil, 26)
		chip.Name = "Troop_" .. part.troop
		chip.LayoutOrder = i
		local t = RaceInfo.troopTrick(part.troop)
		if t ~= "" then
			trickText = RaceInfo.troopName(part.troop) .. ": " .. string.lower(string.sub(t, 1, 1)) .. string.sub(t, 2)
		end
	end
	trick.Text = trickText
	trick.Visible = trickText ~= ""
	Widgets.clear(buttons)
	local dest, path = sel.dest, sel.path
	local icon = "arrow"
	if army.retreating then
		local home = if army.dest ~= 0 then map.provinces[army.dest].name else "home"
		hint.Text = string.format("Retreating to %s: no orders till it arrives", home)
		icon = "retreat"
	elseif dest and path then
		hint.Text = string.format("%s  ·  %d s march", map.provinces[dest].name, Relations.travelTime(path, army))
		icon = "clock"
		local armyId = sel.army
		Widgets.iconTextButton(buttons, "check", "Go", 120, Widgets.GOOD, function()
			if onGo then
				onGo(armyId, dest)
			end
		end, "✅ Go")
	elseif army.inBattle then
		hint.Text = "In battle: wait for it to end"
		icon = "battle"
	elseif army.dest ~= 0 then
		hint.Text = string.format("Marching to %s · tap a new destination", map.provinces[army.dest].name)
	else
		hint.Text = "Tap where to go"
		icon = "flag"
	end
	Icons.set(hintIcon, icon)
	Widgets.iconTextButton(buttons, "close", "Cancel", 120, Widgets.BUTTON_OFF, function()
		if onCancel then
			onCancel()
		end
	end, "✕ Cancel")
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
	sheet = Widgets.sheet(gui, 440)
	sheet.Name = "Sheet"
	sheet.Visible = false
	Widgets.list(sheet, false, Theme.space.s)
	title = Widgets.title(sheet, "", Theme.text.title, 30)
	title.LayoutOrder = 1
	Widgets.leadIcon(title, "sword", Theme.icon.small)
	chips = Instance.new("Frame")
	chips.Name = "Troops"
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, 26)
	chips.LayoutOrder = 2
	chips.Parent = sheet
	Widgets.list(chips, true, Theme.space.s)
	trick = Widgets.label(sheet, "", Theme.text.small, 18)
	trick.Name = "Trick"
	trick.TextColor3 = Theme.color.textDim
	trick.LayoutOrder = 3
	hint = Widgets.label(sheet, "", Theme.text.body, 22)
	hint.LayoutOrder = 4
	hintIcon = Widgets.leadIcon(hint, "arrow", Theme.size.icon)
	buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	buttons.LayoutOrder = 5
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
