--!strict
-- Bottom sheet while an army is selected (docs/DESIGN.md "Moving armies"): tap the army, tap the destination,
-- see the route and arrival time, tap Go. Or tap one of your fleets instead of a destination: the army walks to the
-- fleet's coast and boards it (docs/DESIGN.md "Navies"), confirmed with Board. Built from the UI kit: a title with the
-- army's size, its composition as chips (a troop icon and its men each, docs/DESIGN.md "Troops"), a hint line with an
-- icon, and Go (or Board) / Cancel buttons.

local Players = game:GetService("Players")

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local SHEET_WIDTH = 444

local ArmySheet = {}

local sheet: Frame
local title: TextLabel
local chips: Frame
local hint: TextLabel
local hintIcon: GuiObject
local buttons: Frame
-- board: the fleet the army is about to walk to and board, and the march to its coast
type Boarding = { fleet: number, path: { number } }

local current: { army: number, dest: number?, path: { number }?, board: Boarding? }? = nil
local onGo: ((number, number) -> ())? = nil
local onCancel: (() -> ())? = nil
local onBoard: ((number, number) -> ())? = nil

-- Do you have a fleet on the map (so the hint can say armies board them)?
local function haveFleet(): boolean
	local snap = ClientState.snapshot()
	local me = ClientState.myNation()
	if snap and me ~= 0 then
		for _, f in snap.fleets do
			if f.owner == me then
				return true
			end
		end
	end
	return false
end

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
	-- the composition: one chip per troop type in the stack
	Widgets.clear(chips)
	for i, part in RaceInfo.composition(army.troops) do
		local name = RaceInfo.troopName(part.troop) -- as the map calls it
		local chip = Widgets.chip(chips, RaceInfo.troopIcon(part.troop), shortMen(part.men) .. " " .. name, nil, 26)
		chip.Name = "Troop_" .. part.troop
		chip.LayoutOrder = i
	end
	Widgets.clear(buttons)
	local dest, path, board = sel.dest, sel.path, sel.board
	local fleet = if board then ClientState.fleet(board.fleet) else nil
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
	elseif board and fleet then
		local zone = Relations.zone(fleet.dest)
		hint.Text = string.format(
			"Board in %s  ·  %d s march",
			if zone then zone.name else "?",
			Relations.travelTime(board.path, army)
		)
		icon = "ship"
		local armyId, fleetId = sel.army, board.fleet
		Widgets.iconTextButton(buttons, "ship", "Board", 120, Widgets.GOOD, function()
			if onBoard then
				onBoard(armyId, fleetId)
			end
		end, "Board")
	elseif army.inBattle then
		hint.Text = "In battle: wait for it to end"
		icon = "battle"
	elseif army.dest ~= 0 then
		hint.Text = string.format("Marching to %s · tap a new destination", map.provinces[army.dest].name)
	else
		hint.Text = if haveFleet() then "Tap where to go, or a fleet to board" else "Tap where to go"
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

-- dest and path: a destination to confirm with Go; board: a fleet to walk to and board, confirmed with Board.
function ArmySheet.show(armyId: number?, dest: number?, path: { number }?, board: Boarding?)
	current = if armyId then { army = armyId, dest = dest, path = path, board = board } else nil
	render()
end

-- go(army, destination) for Go; cancel() for Cancel; board(army, fleet) for Board.
function ArmySheet.init(
	goHandler: (number, number) -> (),
	cancelHandler: () -> (),
	boardHandler: ((number, number) -> ())?
)
	onGo = goHandler
	onCancel = cancelHandler
	onBoard = boardHandler
	local gui = Widgets.screen("ArmySheet", 2)
	sheet = Widgets.sheet(gui, SHEET_WIDTH)
	sheet.Name = "Sheet"
	sheet.Visible = false
	Widgets.list(sheet, false, Theme.space.m)
	-- "3k at Aurora Landing" on a title plate on the sheet's top edge
	local _, plate = Widgets.header(sheet, "", "sword")
	title = plate
	chips = Instance.new("Frame")
	chips.Name = "Troops"
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, 26)
	chips.LayoutOrder = 2
	chips.Parent = sheet
	Widgets.list(chips, true, Theme.space.s)
	hint = Widgets.label(sheet, "", Theme.text.body, 22)
	hint.LayoutOrder = 3
	hintIcon = Widgets.leadIcon(hint, "arrow", Theme.size.icon)
	buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	buttons.LayoutOrder = 4
	buttons.Parent = sheet
	Widgets.list(buttons, true, 8)
	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
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
