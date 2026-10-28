--!strict
-- Bottom sheet for the tapped province (docs/DESIGN.md "UI and controls"): who owns it, development, building and
-- who is standing there; one-tap actions on your own provinces (develop, build, recruit one regiment of each of
-- the five troops of your race's roster, move an army) and diplomacy on foreign ones (war, ally, peace). Every button
-- shows its price; the server decides.
-- Built from the UI kit: a header, a row of chips (icon + value) and big icon buttons with their cost.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Economy = require(Shared.Sim.Economy)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Palette = require(Client.Palette)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local SHEET_WIDTH = 560
local CELL = Vector2.new(128, 52) -- action buttons: at least 44 px tall on phones
local CHIP_HEIGHT = 26

local TERRAIN_ICONS: { [string]: string } = { Plains = "farm", Forest = "tree", Hills = "hills", Mountain = "mountain" }
local BUILDING_ICONS: { [string]: string } = { Farm = "farm", Barracks = "sword", Fort = "castle" }
local BUILDABLE: { Types.Building } = { "Farm", "Barracks", "Fort" }

local ProvinceSheet = {}

local sheet: Frame
local title: TextLabel
local titleIcon: GuiObject
local info: Frame
local status: Frame
local actions: Frame
local selected: number? = nil
local onClose: (() -> ())? = nil
local onSelectArmy: ((number) -> ())? = nil

local function shortMen(men: number): string
	return if men >= 1000 then string.format("%gk", math.floor(men / 100) / 10) else tostring(men)
end

-- An action button: a pixel icon, a caption and its cost (icon + number pairs) under the caption. Greyed out when
-- you can't afford it (a tap still goes to the server, which explains in a toast). `name` keeps the old caption
-- the tutorial and the harness look for.
local function action(
	icon: string,
	caption: string,
	costs: { { string } },
	color: Color3,
	enabled: boolean,
	onPress: () -> (),
	name: string?
)
	local b = Widgets.actionButton(actions, icon, caption, costs, CELL, color, onPress, name)
	b.LayoutOrder = #actions:GetChildren()
	if not enabled then
		Widgets.setEnabled(b, false)
	end
end

local function chip(parent: Instance, icon: string, text: string, color: Color3?): TextLabel
	local c = Widgets.chip(parent, icon, text, nil, CHIP_HEIGHT)
	c.LayoutOrder = #parent:GetChildren()
	if color then
		c.TextColor3 = color
	end
	return c
end

-- Battle, siege and the armies standing here, as chips.
local function renderStatus(provinceId: number, record: Snapshot.ProvinceRecord)
	Widgets.clear(status)
	local snap = ClientState.snapshot()
	if record.battle then
		chip(status, "battle", "Battle")
	elseif record.siegeRequired > 0 then -- siegeBy is 0 for Rebels
		local by = ClientState.nation(record.siegeBy)
		chip(
			status,
			"hourglass",
			string.format(
				"%s siege %d%%",
				if by then by.name else "Rebels",
				math.floor(100 * record.siegeProgress / record.siegeRequired)
			)
		)
	end
	if snap then
		for _, a in snap.armies do
			if a.location == provinceId then
				local owner = ClientState.nation(a.owner)
				if a.rebel then
					chip(status, "rebels", shortMen(a.men) .. " Rebels")
				elseif a.owner == 0 then
					chip(status, "shield", shortMen(a.men) .. " garrison")
				else
					-- the icon of the troop type it is mostly made of, as on its badge on the map
					local tint = if owner then Palette.nation(owner.colorIndex):Lerp(Color3.new(1, 1, 1), 0.45) else nil
					local c = chip(
						status,
						RaceInfo.mainTroopIcon(a.troops),
						shortMen(a.men) .. " " .. (if owner then owner.name else "?"),
						tint
					)
					c.Name = "ArmyChip" .. a.id
				end
			end
		end
	end
	status.Visible = #status:GetChildren() > 1 -- more than its layout
end

local function pips(development: number): string
	return string.rep("●", development) .. string.rep("○", Config.Economy.MaxDevelopment - development)
end

local function render()
	local id = selected
	local map = ClientState.map()
	local record = if id then ClientState.province(id) else nil
	if id == nil or map == nil or record == nil then
		sheet.Visible = false
		-- a hidden sheet keeps no chips or buttons (they are rebuilt when it opens): fewer GUI objects
		Widgets.clear(info)
		Widgets.clear(status)
		Widgets.clear(actions)
		return
	end
	local provinceId: number = id -- non-optional copy for the button callbacks
	local def = map.provinces[provinceId]
	local owner = ClientState.nation(record.owner)
	local me = ClientState.nation(ClientState.myNation())
	if me and me.eliminated then
		me = nil -- a Primordial looks, but gives no orders (powers have their own button)
	end
	local mine = owner ~= nil and me ~= nil and owner.id == me.id

	title.Text = def.name
	Icons.set(titleIcon, if def.isCapital then "crown" else TERRAIN_ICONS[def.terrain] or "flag")

	-- the info chips: terrain, owner (your relation with it, else its race), development, building
	Widgets.clear(info)
	chip(info, TERRAIN_ICONS[def.terrain] or "flag", def.terrain)
	if owner then
		local relation = if me and owner.id ~= me.id then Icons.fromEmoji(Relations.icon(me.id, owner.id)) else nil
		local race = if owner.race ~= "" then RaceInfo.icon(owner.race) else "flag"
		local c =
			chip(info, relation or race, owner.name, Palette.nation(owner.colorIndex):Lerp(Color3.new(1, 1, 1), 0.4))
		c.Name = "Owner"
	else
		chip(info, "flag", if def.terrain == "Mountain" then "Impassable" else "Neutral", Theme.color.textDim)
	end
	chip(info, "up", pips(record.development), Theme.color.gold)
	if record.building ~= "None" then
		chip(info, BUILDING_ICONS[record.building] or "castle", record.building)
	else
		chip(info, "castle", "No building", Theme.color.textDim)
	end
	renderStatus(provinceId, record)

	Widgets.clear(actions)
	if mine and me then
		local gold = me.gold
		if record.development < Config.Economy.MaxDevelopment then
			local cost = Economy.developCost(record.development)
			action("up", "Develop", { { "gold", tostring(cost) } }, Widgets.BUTTON, gold >= cost, function()
				Intents.develop(provinceId)
			end)
		end
		if record.building == "None" then
			for _, building in BUILDABLE do
				local cost = Economy.buildingCost(building, me.race :: Types.Race) or 0 -- Hills races: cheaper forts
				action(
					BUILDING_ICONS[building],
					building,
					{ { "gold", tostring(cost) } },
					Widgets.BUTTON,
					gold >= cost,
					function()
						Intents.build(provinceId, building)
					end
				)
			end
		end
		-- one regiment of each troop of your race's roster: line, ranged, fast, elite and special, each button named
		-- "Recruit_<troop id>" (the tutorial and the harness look for them)
		for _, troop in RaceInfo.troops(me.race) do
			local recruitGold, recruitManpower = Economy.recruitCost(1, troop)
			local manpowerText = if recruitManpower % 1000 == 0
				then recruitManpower // 1000 .. "k"
				else tostring(recruitManpower) -- Berserkers: 750
			action(
				RaceInfo.troopIcon(troop),
				RaceInfo.troopName(troop),
				{ { "gold", tostring(recruitGold) }, { "manpower", manpowerText } },
				Widgets.GOOD,
				gold >= recruitGold and me.manpower >= recruitManpower,
				function()
					Intents.recruit(provinceId, 1, troop)
				end,
				"Recruit_" .. troop
			)
		end
	end
	-- your armies standing here: tap to pick one up and send it somewhere
	local snap = ClientState.snapshot()
	if me and snap then
		for _, a in snap.armies do
			if a.location == provinceId and a.owner == me.id then
				local armyId = a.id
				action(
					"arrow",
					"Move",
					{ { RaceInfo.mainTroopIcon(a.troops), shortMen(a.men) } },
					Widgets.GOOD,
					not a.inBattle and not a.retreating,
					function()
						if onSelectArmy then
							onSelectArmy(armyId)
						end
					end,
					"➜ Move"
				)
			end
		end
	end
	-- diplomacy with the owner of a foreign province
	if owner and me and owner.id ~= me.id and snap then
		local target = owner.id
		if Relations.atWar(me.id, target) then
			for _, tribute in Config.Diplomacy.PeaceTributes do
				local costs = if tribute == 0 then {} else { { "gold", "+" .. tribute } }
				action("peace", "Peace", costs, Widgets.BUTTON, me.gold >= tribute, function()
					Intents.diplomacy("Peace", target, tribute)
				end, "Peace_" .. tribute)
			end
		else
			local canWar = snap.phase ~= "Peace"
				and not Relations.allied(me.id, target)
				and not Relations.truce(me.id, target)
				and Relations.borders(me.id, target)
			action("war", "Declare war", {}, Widgets.DANGER, canWar, function()
				Intents.diplomacy("War", target)
			end)
			if not Relations.allied(me.id, target) then
				action("handshake", "Ally", {}, Widgets.BUTTON, true, function()
					Intents.diplomacy("Ally", target)
				end, "🤝 Ally")
			end
		end
	end
	actions.Visible = #actions:GetChildren() > 1
	sheet.Visible = true
end

function ProvinceSheet.show(provinceId: number?)
	selected = provinceId
	render()
end

local function chipRow(order: number, name: string): Frame
	local row = Instance.new("Frame")
	row.Name = name
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, CHIP_HEIGHT)
	row.LayoutOrder = order
	row.Parent = sheet
	Widgets.list(row, true, Theme.space.s)
	return row
end

function ProvinceSheet.init(closeHandler: () -> (), selectArmyHandler: (number) -> ())
	onClose = closeHandler
	onSelectArmy = selectArmyHandler
	local gui = Widgets.screen("ProvinceSheet")

	sheet = Widgets.sheet(gui, SHEET_WIDTH)
	sheet.Name = "Sheet"
	sheet.Visible = false
	Widgets.list(sheet, false, Theme.space.m)

	-- header: name on the left, close button on the right
	local header
	header, title = Widgets.header(sheet, "", "flag", function()
		ProvinceSheet.show(nil)
		if onClose then
			onClose()
		end
	end)
	header.Size = UDim2.new(1, 0, 0, 36)
	header.LayoutOrder = 1
	titleIcon = title:FindFirstChild("Icon") :: GuiObject

	info = chipRow(2, "Info")
	status = chipRow(3, "Status")

	actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.fromScale(1, 0)
	actions.AutomaticSize = Enum.AutomaticSize.Y
	actions.LayoutOrder = 4
	actions.Parent = sheet
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CELL.X, CELL.Y)
	grid.CellPadding = UDim2.fromOffset(Theme.space.m, Theme.space.m)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = actions

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onReset(function()
		ProvinceSheet.show(nil)
	end)
	ClientState.onDelta(function(delta)
		if selected == nil then
			return
		end
		-- the sheet shows prices and enabled buttons, so refresh when this province or any nation changes
		local relevant = #delta.nations > 0
		for _, r in delta.provinces do
			relevant = relevant or r.id == selected
		end
		if relevant then
			render()
		end
	end)
end

return ProvinceSheet
