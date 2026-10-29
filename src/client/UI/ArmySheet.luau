--!strict
-- Bottom sheet while an army is selected (docs/DESIGN.md "Moving armies"): tap the army, tap the destination,
-- see the route and arrival time, tap Go. Or tap one of your fleets instead of a destination: the army walks to the
-- fleet's coast and boards it (docs/DESIGN.md "Navies"), confirmed with Board. Built from the UI kit
-- (docs/UI_DIRECTION.md 7.10): the army's size and place on a title plate, its composition as chips (each troop's
-- icon and its men, docs/DESIGN.md "Troops": five fit a row; with its name too while three or fewer types and every
-- named chip fit the row), its morale as a bar (docs/DESIGN.md "Armies and combat": green when rested, gold when
-- tired, red when broken), its special's trick when it has one, the route line (an icon, the destination, the march
-- time dimmer) and Go (or Board) / Cancel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Config = require(ReplicatedStorage.Shared.Config)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local MapBadges = require(Client.MapBadges)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local TextWidth = require(Client.TextWidth)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local SHEET_WIDTH = 444
local BUTTON_WIDTH = 200 -- Go and Cancel side by side fill the sheet
local LINE_HEIGHT = 22
local NAMED_CHIPS = 3 -- up to this many troop types, a chip shows the troop's name; more show the icon and men only
local MORALE_BAR = 160 -- the morale bar's width
local MORALE_COLORS: { [string]: Color3 } =
	{ good = Theme.color.emerald, low = Theme.color.gold, broken = Theme.color.crimson }
local CHIP_SIDES = 36 -- a chip's padding, icon and gap round its text (Widgets.chip)
local CHIP_GAP = Theme.space.s

local ArmySheet = {}

local sheet: Frame
local title: TextLabel
local chips: Frame
local moraleRow: Frame
local moraleBar: Frame? = nil
local moraleTone = ""
local moraleText: TextLabel
local trick: TextLabel
local hint: TextLabel
local hintIcon: GuiObject
local march: TextLabel -- "· 18 s march", dimmer, after the destination
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
	-- the composition: one chip per troop type in the stack, in role order, its icon (as the map and the recruit
	-- tiles show it) and its men (and its name while three or fewer types fit the row); and its special's trick
	Widgets.clear(chips)
	local parts = RaceInfo.composition(army.troops)
	local trickText = ""
	-- names too, when there are few types and every named chip fits the row ("1.2k Crocodile guard" is wide)
	local named = #parts <= NAMED_CHIPS
	if named then
		local row = sheet.Size.X.Offset - 2 * Widgets.PANEL_PAD
		local total = -CHIP_GAP
		for _, part in parts do
			local text = shortMen(part.men) .. " " .. RaceInfo.troopName(part.troop)
			total += CHIP_SIDES + TextWidth.measure(text, Theme.text.body) + CHIP_GAP
		end
		named = total <= row
	end
	for i, part in parts do
		local text = shortMen(part.men)
		if named then
			text ..= " " .. RaceInfo.troopName(part.troop)
		end
		local chip = Widgets.chip(chips, RaceInfo.troopIcon(part.troop), text, nil, Theme.size.chip)
		chip.Name = "Troop_" .. part.troop
		chip.LayoutOrder = i
		local t = RaceInfo.troopTrick(part.troop)
		if t ~= "" then
			trickText = RaceInfo.troopName(part.troop) .. ": " .. string.lower(string.sub(t, 1, 1)) .. string.sub(t, 2)
		end
	end
	-- morale: the bar in its tone's colour (a new bar when the tone changes) and the number
	local fraction, tone = MapBadges.morale(army.morale, Config.Battle.MoraleMax)
	local bar = moraleBar
	if bar == nil or tone ~= moraleTone then
		moraleTone = tone
		if bar then
			bar:Destroy()
		end
		bar = Widgets.progress(moraleRow, MORALE_BAR, 14, MORALE_COLORS[tone])
		bar.LayoutOrder = 2
		bar:SetAttribute("Tone", tone)
		moraleBar = bar
	end
	Widgets.setProgress(bar :: Frame, fraction)
	moraleText.Text = tostring(army.morale)
	trick.Text = trickText
	trick.Visible = trickText ~= ""
	Widgets.clear(buttons)
	local dest, path, board = sel.dest, sel.path, sel.board
	local fleet = if board then ClientState.fleet(board.fleet) else nil
	local icon = "arrow"
	march.Visible = false
	if army.retreating then
		local home = if army.dest ~= 0 then map.provinces[army.dest].name else "home"
		hint.Text = string.format("Retreating to %s: no orders till it arrives", home)
		icon = "retreat"
	elseif dest and path then
		hint.Text = map.provinces[dest].name
		march.Text = string.format("·  %d s march", Relations.travelTime(path, army))
		march.Visible = true
		icon = "clock"
		local armyId = sel.army
		Widgets.iconTextButton(buttons, "check", "Go", BUTTON_WIDTH, Widgets.GOOD, function()
			if onGo then
				onGo(armyId, dest)
			end
		end, "✅ Go")
	elseif board and fleet then
		local zone = Relations.zone(fleet.dest)
		hint.Text = "Board in " .. (if zone then zone.name else "?")
		march.Text = string.format("·  %d s march", Relations.travelTime(board.path, army))
		march.Visible = true
		icon = "ship"
		local armyId, fleetId = sel.army, board.fleet
		Widgets.iconTextButton(buttons, "ship", "Board", BUTTON_WIDTH, Widgets.GOOD, function()
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
	Widgets.iconTextButton(buttons, "close", "Cancel", BUTTON_WIDTH, Widgets.BUTTON_OFF, function()
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
	chips.Size = UDim2.new(1, 0, 0, Theme.size.chip)
	chips.LayoutOrder = 2
	chips.Parent = sheet
	Widgets.list(chips, true, Theme.space.s)
	-- morale: the gold banner, a bar and the number (the bar is made in render, in its tone's colour)
	moraleRow = Instance.new("Frame")
	moraleRow.Name = "Morale"
	moraleRow.BackgroundTransparency = 1
	moraleRow.Size = UDim2.new(1, 0, 0, Theme.size.icon)
	moraleRow.LayoutOrder = 3
	moraleRow.Parent = sheet
	local moraleList = Widgets.list(moraleRow, true, Theme.space.s)
	moraleList.VerticalAlignment = Enum.VerticalAlignment.Center
	Icons.label(moraleRow, "morale", Theme.size.icon).LayoutOrder = 1
	moraleText = Widgets.label(moraleRow, "", Theme.text.small, Theme.size.icon)
	moraleText.Name = "Value"
	moraleText.FontFace = Theme.font.display
	moraleText.Size = UDim2.fromOffset(0, Theme.size.icon)
	moraleText.AutomaticSize = Enum.AutomaticSize.X
	moraleText.LayoutOrder = 3
	trick = Widgets.label(sheet, "", Theme.text.small, 18)
	trick.Name = "Trick"
	trick.TextColor3 = Theme.color.textDim
	trick.LayoutOrder = 4
	-- the route line: an icon and where to (or what is going on), then the march time, dimmer
	local route = Instance.new("Frame")
	route.Name = "Route"
	route.BackgroundTransparency = 1
	route.Size = UDim2.new(1, 0, 0, LINE_HEIGHT)
	route.LayoutOrder = 5
	route.Parent = sheet
	Widgets.list(route, true, Theme.space.s)
	hint = Widgets.label(route, "", Theme.text.body, LINE_HEIGHT)
	hint.Name = "Hint"
	hint.Size = UDim2.fromOffset(0, LINE_HEIGHT)
	hint.AutomaticSize = Enum.AutomaticSize.X
	hint.TextWrapped = false
	hint.LayoutOrder = 1
	hintIcon = Widgets.leadIcon(hint, "arrow", Theme.size.icon)
	march = Widgets.hint(route, "", Theme.text.body, LINE_HEIGHT)
	march.Name = "March"
	march.FontFace = Theme.font.body
	march.Size = UDim2.fromOffset(0, LINE_HEIGHT)
	march.AutomaticSize = Enum.AutomaticSize.X
	march.TextWrapped = false
	march.LayoutOrder = 2
	march.Visible = false
	buttons = Instance.new("Frame")
	buttons.Name = "Buttons"
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	buttons.LayoutOrder = 6
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
