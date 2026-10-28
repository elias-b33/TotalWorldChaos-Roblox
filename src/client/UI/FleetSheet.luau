--!strict
-- Bottom sheet while a fleet is selected (docs/DESIGN.md "Navies", Controls): tap your fleet, then a sea zone to sail
-- there or a coastal province to land the men aboard there, see the route and its time, tap Sail or Land. Someone
-- else's fleet shows the same facts without orders. Built from the UI kit like ArmySheet: a title with the ships and
-- their zone, chips (the owner when it isn't you, the men aboard out of the room, the troops aboard), a hint line
-- with an icon, and the buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Palette = require(Client.Palette)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local SHEET_WIDTH = 444
local CHIP_HEIGHT = 26
local MAX_TROOP_CHIPS = 2 -- troop types aboard shown as chips (the sheet stays one row wide on a phone)

-- What the player is about to order: sail to a zone, or sail to a zone off a coast and land there.
export type Order =
	{ kind: "Sail", zone: number, path: { number } }
	| { kind: "Land", province: number, path: { number } }

local FleetSheet = {}

local sheet: Frame
local title: TextLabel
local chips: Frame
local hint: TextLabel
local hintIcon: GuiObject
local buttons: Frame
local current: { fleet: number, order: Order? }? = nil
local onConfirm: ((number, Order) -> ())? = nil
local onCancel: (() -> ())? = nil
local onGone: ((number?) -> ())? = nil

local function shortMen(men: number): string
	return if men >= 1000 then string.format("%gk", math.floor(men / 100) / 10) else tostring(men)
end

local function zoneName(zoneId: number): string
	local zone = Relations.zone(zoneId)
	return if zone then zone.name else "?"
end

local function chip(icon: string, text: string, color: Color3?): TextLabel
	local c = Widgets.chip(chips, icon, text, nil, CHIP_HEIGHT)
	c.LayoutOrder = #chips:GetChildren()
	if color then
		c.TextColor3 = color
	end
	return c
end

local function render()
	local sel = current
	local fleet = if sel then ClientState.fleet(sel.fleet) else nil
	local map = ClientState.map()
	if sel == nil or fleet == nil or map == nil then
		sheet.Visible = false
		Widgets.clear(buttons) -- rebuilt when it opens
		Widgets.clear(chips)
		return
	end
	local me = ClientState.myNation()
	local mine = me ~= 0 and fleet.owner == me
	-- "3 Starships in Vega Drift"
	title.Text = string.format(
		"%d %s%s in %s",
		fleet.ships,
		map.ship,
		if fleet.ships == 1 then "" else "s",
		zoneName(fleet.zone)
	)

	-- whose it is (someone else's), the men aboard out of the room, the troop types aboard
	Widgets.clear(chips)
	if not mine then
		local owner = ClientState.nation(fleet.owner)
		local tint = if owner then Palette.nation(owner.colorIndex):Lerp(Color3.new(1, 1, 1), 0.4) else nil
		local c = chip(if owner then RaceInfo.icon(owner.race) else "flag", if owner then owner.name else "?", tint)
		c.Name = "Owner"
	end
	local capacity = fleet.ships * Config.Navy.ShipCapacity
	local aboard = chip("manpower", string.format("%s / %s aboard", shortMen(fleet.men), shortMen(capacity)))
	aboard.Name = "Aboard"
	for i, part in RaceInfo.composition(fleet.troops) do
		if i <= MAX_TROOP_CHIPS then
			local c = chip(RaceInfo.troopIcon(part.troop), shortMen(part.men) .. " " .. RaceInfo.troopName(part.troop))
			c.Name = "Troop_" .. part.troop
		end
	end

	Widgets.clear(buttons)
	local order = sel.order
	local icon = "ship"
	if fleet.retreating then
		hint.Text = string.format("Retreating to %s: no orders till it arrives", zoneName(fleet.dest))
		icon = "retreat"
	elseif mine and order then
		local fleetId = sel.fleet
		local seconds = Relations.sailTime(order.path, fleet)
		if order.kind == "Sail" then
			hint.Text = string.format("%s  ·  %d s sail", zoneName(order.zone), seconds)
		else
			hint.Text = string.format("Land at %s  ·  %d s sail", map.provinces[order.province].name, seconds)
		end
		icon = "clock"
		local verb = if order.kind == "Sail" then "Sail" else "Land"
		Widgets.iconTextButton(buttons, "check", verb, 120, Widgets.GOOD, function()
			if onConfirm then
				onConfirm(fleetId, order)
			end
		end, verb)
	elseif fleet.inBattle then
		hint.Text = "In a sea battle: wait for it to end"
		icon = "battle"
	elseif fleet.landAt ~= 0 then
		hint.Text = string.format("Landing at %s", map.provinces[fleet.landAt].name)
		icon = "arrow"
	elseif fleet.next ~= 0 then
		hint.Text = string.format("Sailing to %s", zoneName(fleet.dest))
		icon = "arrow"
	elseif not mine then
		hint.Text = if fleet.men > 0 then "Carrying an army" else "Standing at sea"
	elseif fleet.men > 0 then
		hint.Text = "Tap a sea to sail, or a coast to land"
		icon = "flag"
	else
		hint.Text = "Empty · tap a sea to sail there" -- (armies board from their own sheet: tap one, then this fleet)
		icon = "flag"
	end
	Icons.set(hintIcon, icon)
	Widgets.iconTextButton(buttons, "close", if mine then "Cancel" else "Close", 120, Widgets.BUTTON_OFF, function()
		if onCancel then
			onCancel()
		end
	end, "FleetCancel")
	sheet.Visible = true
end

-- Show a fleet (nil hides the sheet), with the order the player is about to confirm.
function FleetSheet.show(fleetId: number?, order: Order?)
	current = if fleetId then { fleet = fleetId, order = order } else nil
	render()
end

-- confirm(fleet, order) when Sail or Land is pressed; cancel() for Cancel; gone(keeper?) when the fleet left the map
-- (sunk, out of sight, or merged into `keeper`, a fleet of the same nation in the same zone).
function FleetSheet.init(confirmHandler: (number, Order) -> (), cancelHandler: () -> (), goneHandler: (number?) -> ())
	onConfirm = confirmHandler
	onCancel = cancelHandler
	onGone = goneHandler
	local gui = Widgets.screen("FleetSheet", 2)
	sheet = Widgets.sheet(gui, SHEET_WIDTH)
	sheet.Name = "Sheet"
	sheet.Visible = false
	Widgets.list(sheet, false, Theme.space.m)
	-- "3 Starships in Vega Drift" on a title plate on the sheet's top edge
	local _, plate = Widgets.header(sheet, "", "ship")
	title = plate
	chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.BackgroundTransparency = 1
	chips.Size = UDim2.new(1, 0, 0, CHIP_HEIGHT)
	chips.LayoutOrder = 2
	chips.Parent = sheet
	Widgets.list(chips, true, Theme.space.s)
	hint = Widgets.label(sheet, "", Theme.text.body, 22)
	hint.LayoutOrder = 3
	hintIcon = Widgets.leadIcon(hint, "ship", Theme.size.icon)
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
		for _, id in delta.removedFleets do
			if id == sel.fleet then
				local keeper: number? = nil
				for _, e in delta.events do
					if e.kind == "FleetMerged" and e.b == id then
						keeper = e.a
					end
				end
				if onGone then
					onGone(keeper)
				end
				return
			end
		end
		for _, f in delta.fleets do
			if f.id == sel.fleet then
				render()
				return
			end
		end
	end)
	ClientState.onReset(function()
		FleetSheet.show(nil)
	end)
end

return FleetSheet
