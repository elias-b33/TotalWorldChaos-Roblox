--!strict
-- Bottom sheet for the tapped province (docs/DESIGN.md "UI and controls"): who owns it, development, building and
-- who is standing there; one-tap actions on your own provinces (develop, build, recruit one regiment of each of
-- the five troops of your race's roster, move an army) and diplomacy on foreign ones (war, ally, peace, and the EU4
-- pack's insult, gift and military access). Every button shows its price; the server decides. On an owned coast,
-- "Ships" opens the choice of how many of the map's ships to launch (docs/DESIGN.md "Navies"); a blockaded coast's
-- tile is greyed with an anchor.
-- Built from the UI kit (docs/UI_DIRECTION.md 7.10): the province's name on a title plate, a row of chips (icon +
-- value, the development as the map's pip bar) and rows of slot tiles, five to a row: routine actions on calm slate
-- tiles whose base says their group (build bronze, recruit green), decisions (war, ally, peace) in full colour.
-- Every tile shows its price in gold (in red when you can't pay it) and greys out when it can't be done.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Economy = require(Shared.Sim.Economy)
local Troops = require(Shared.Sim.Troops)
local Snapshot = require(Shared.Snapshot)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local Palette = require(Client.Palette)
local RaceInfo = require(Client.RaceInfo)
local Relations = require(Client.Relations)
local MapRenderer = require(Client.MapRenderer)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
-- As wide as a centred sheet can be and still clear the power button on an 844 px phone: five tiles of 124 px. On a
-- 667 px phone it docks left at 566 px, and the tiles are 102 px (Widgets.tileWidth).
local SHEET_WIDTH = 676
local COLUMNS = 5 -- tiles to a row: five troops, or Develop, the three buildings and Move
local MIN_TILE = 100 -- a sixth tile (a coast's Ships) joins its row when tiles stay this wide ("Horse archers" fits)
local GAP = Theme.space.s -- between tiles
local CHIP_HEIGHT = Theme.size.chip
local CHIP_GAP = Theme.space.s
local PIP_SCALE = 2 -- the pip bar at the map's scale, in a well 10 px wider each side
local LONG_CAPTION = 12 -- characters that fit a tile's caption at the kit's size; longer ones (troop names like
-- "Crocodile guard") are set a size or two smaller
local COUNTER_BADGE = 20 -- the counter badge on a recruit tile (the troop it beats): it sits on the tile's base at
-- the bottom right, clear of the costs even on a 667 px phone's 102 px tiles; offsets from the tile's padded content
-- box (Widgets.slotTile: 6 px each side, 12 px of base below), 4 px in from the right edge and 2 px up from the bottom
local COUNTER_X = 2
local COUNTER_Y = 10

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
-- the rows of tiles: build (Develop, the buildings, Move) and recruit (bronze and green slot tiles), diplomacy with a
-- foreign owner (full colour)
local buildRow: Frame
local recruitRow: Frame
local diplomacyRow: Frame
local grids: { UIGridLayout } = {}
local selected: number? = nil
local shipPicker = false -- "Ships" was pressed: the actions are the 1-5 ships to launch, and Back
local onClose: (() -> ())? = nil
local onSelectArmy: ((number) -> ())? = nil

local function shortMen(men: number): string
	return if men >= 1000 then string.format("%gk", math.floor(men / 100) / 10) else tostring(men)
end

-- A slot tile in a row: a pixel icon, a caption and its costs (icon + number pairs; a third entry "short" shows the
-- number in red). `style` is the row's group ("build", "recruit") or a decision's colour. Greyed out when it can't
-- be done (a tap still goes to the server, which explains in a toast). `name` keeps the old caption the tutorial
-- and the harness look for.
local function action(
	row: Frame,
	icon: string,
	caption: string,
	costs: { { string } },
	style: string | Color3,
	enabled: boolean,
	onPress: () -> (),
	name: string?
): TextButton
	local size = Vector2.new(grids[1].CellSize.X.Offset, Widgets.TILE_HEIGHT)
	local b = Widgets.slotTile(row, icon, caption, costs, size, style, onPress, name)
	b.LayoutOrder = #row:GetChildren()
	if #caption > LONG_CAPTION then
		b.TextSize = if #caption > LONG_CAPTION + 1 then Theme.text.small - 2 else Theme.text.small - 1
	end
	if not enabled then
		Widgets.setEnabled(b, false)
	end
	return b
end

-- Counters (docs/DESIGN.md "Troops"): the role shares of the enemy armies (nations at war with me) in a province and
-- next to it, or nil when there are none.
local function enemyMix(provinceId: number, me: number): { [string]: number }?
	local snap, map = ClientState.snapshot(), ClientState.map()
	if snap == nil or map == nil then
		return nil
	end
	local near = { [provinceId] = true }
	for _, n in map.provinces[provinceId].neighbors do
		near[n] = true
	end
	local men: Types.Composition = {}
	local any = false
	for _, a in snap.armies do
		if near[a.location] and a.owner ~= 0 and Relations.atWar(me, a.owner) then
			any = true
			for troop, n in Troops.decode(a.troops) do
				men[troop] = (men[troop] or 0) + n
			end
		end
	end
	return if any then Troops.roleShares(men) else nil
end

-- What the counter badges would say for this province now ("" without enemies near): re-render when it changes.
local shownHints = ""
local function hintKey(provinceId: number): string
	local me = ClientState.myNation()
	local mix = if me ~= 0 then enemyMix(provinceId, me) else nil
	if mix == nil then
		return ""
	end
	local parts = {}
	for _, role in Troops.ROLES do
		table.insert(parts, Troops.counterHint(role, mix, Config.Bots.CounterMinScore) or "-")
	end
	return table.concat(parts, ",")
end

-- A recruit tile's counter badge: the icon of the troop of my roster it beats, on the tile's base at the bottom right. Green when it is
-- the pick against the enemy armies near this province, red when they beat it (the rule bots use:
-- Troops.counterHint). Attributes Beats (the troop) and Hint ("good", "bad" or "") for the harness.
local function counterBadge(tile: GuiObject, troop: string, race: string, mix: { [string]: number }?)
	local role = Troops.role(troop :: Types.Troop)
	local beatsRole = if role then Troops.beats(role) else nil
	local beaten = if beatsRole then Troops.ofRole(race :: Types.Race, beatsRole) else nil
	if role == nil or beaten == nil then
		return -- elites and specials beat nothing
	end
	local hint = if mix then Troops.counterHint(role, mix, Config.Bots.CounterMinScore) else nil
	local color = if hint == "good"
		then Theme.color.emerald
		elseif hint == "bad" then Theme.color.crimson
		else Theme.color.slate
	local b = Widgets.badge(tile, "", color)
	b.Name = "Counter"
	b.AutomaticSize = Enum.AutomaticSize.None
	b.Size = UDim2.fromOffset(COUNTER_BADGE, COUNTER_BADGE)
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, COUNTER_X, 1, COUNTER_Y)
	b:SetAttribute("Beats", beaten)
	b:SetAttribute("Hint", hint or "")
	local icon = Icons.label(b, RaceInfo.troopIcon(beaten), Theme.size.icon)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.ZIndex = 5
end

-- A cost you may not be able to pay: { icon, number, "short" when `have` is under `need` }.
local function cost(icon: string, text: string, have: number, need: number): { string }
	return if have < need then { icon, text, "short" } else { icon, text }
end

local function chip(parent: Instance, icon: string, text: string, color: Color3?): TextLabel
	local c = Widgets.chip(parent, icon, text, nil, CHIP_HEIGHT)
	c.LayoutOrder = #parent:GetChildren()
	if color then
		c.TextColor3 = color
	end
	return c
end

-- A chip's width, estimated (TextService isn't available everywhere this runs) and erring wide: its padding, icon
-- and gap, then Fredoka One 15 at about 8 px a character.
local function textChipWidth(text: string): number
	return 36 + 8 * (utf8.len(text) or #text)
end

local function chipWidth(c: GuiObject): number
	return if c:IsA("TextLabel") then textChipWidth(c.Text) else c.Size.X.Offset
end

-- The width inside the sheet's frame.
local function innerWidth(): number
	local pad = sheet:FindFirstChildOfClass("UIPadding")
	return sheet.Size.X.Offset - (if pad then pad.PaddingLeft.Offset + pad.PaddingRight.Offset else 0)
end

-- Battle, siege and the armies standing here, as chips: on the info row when they fit beside its chips (most of the
-- time: the sheet stays short), else on a row of their own.
local function renderStatus(provinceId: number, record: Snapshot.ProvinceRecord)
	Widgets.clear(status)
	local snap = ClientState.snapshot()
	local chips: { { icon: string, text: string, color: Color3?, name: string? } } = {}
	if record.battle then
		table.insert(chips, { icon = "battle", text = "Battle" })
	elseif record.siegeRequired > 0 then -- siegeBy is 0 for Rebels
		local by = ClientState.nation(record.siegeBy)
		local progress = math.floor(100 * record.siegeProgress / record.siegeRequired)
		local text = string.format("%s siege %d%%", if by then by.name else "Rebels", progress)
		table.insert(chips, { icon = "hourglass", text = text })
	end
	if record.blockade ~= 0 then -- an enemy fleet off this coast (docs/DESIGN.md "Navies")
		local by = ClientState.nation(record.blockade)
		table.insert(
			chips,
			{ icon = "anchor", text = "Blockade: " .. (if by then by.name else "?"), name = "Blockade" }
		)
	end
	if snap then
		for _, a in snap.armies do
			if a.location == provinceId then
				local owner = ClientState.nation(a.owner)
				if a.rebel then
					table.insert(chips, { icon = "rebels", text = shortMen(a.men) .. " Rebels" })
				elseif a.owner == 0 then
					table.insert(chips, { icon = "shield", text = shortMen(a.men) .. " garrison" })
				else
					-- the icon of the troop type it is mostly made of, as on its badge on the map
					local tint = if owner then Palette.nation(owner.colorIndex):Lerp(Color3.new(1, 1, 1), 0.45) else nil
					table.insert(chips, {
						icon = RaceInfo.mainTroopIcon(a.troops),
						text = shortMen(a.men) .. " " .. (if owner then owner.name else "?"),
						color = tint,
						name = "ArmyChip" .. a.id,
					})
				end
			end
		end
	end
	local used = -CHIP_GAP
	for _, c in info:GetChildren() do
		if c:IsA("GuiObject") then
			used += chipWidth(c) + CHIP_GAP
		end
	end
	for _, c in chips do
		used += textChipWidth(c.text) + CHIP_GAP
	end
	local row = if used <= innerWidth() then info else status
	for _, c in chips do
		local made = chip(row, c.icon, c.text, c.color)
		if c.name then
			made.Name = c.name
		end
	end
	status.Visible = #status:GetChildren() > 1 -- more than its layout
end

local function pips(development: number): string
	return string.rep("●", development) .. string.rep("○", Config.Economy.MaxDevelopment - development)
end

-- The development: the map's pixel pip bar in a well, or gold text pips without EditableImage.
local function pipChip(parent: Instance, development: number)
	local content, size = MapRenderer.pipBar(development)
	if content == nil then
		chip(parent, "up", pips(development), Theme.color.gold).Name = "Development"
		return
	end
	local well = Instance.new("ImageLabel")
	well.Name = "Development"
	well.BorderSizePixel = 0
	well.Size = UDim2.fromOffset(size.X * PIP_SCALE + 20, CHIP_HEIGHT)
	well.LayoutOrder = #parent:GetChildren()
	well.Parent = parent
	Widgets.material(well, "well")
	local bar = Instance.new("ImageLabel")
	bar.Name = "Pips"
	bar.BackgroundTransparency = 1
	bar.ResampleMode = Enum.ResamplerMode.Pixelated
	bar.ImageContent = content
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.fromOffset(size.X * PIP_SCALE, size.Y * PIP_SCALE)
	bar.Parent = well
end

-- How many tiles a row holds: five, or six when a row has six (a coast's Ships tile) and they still fit at
-- MIN_TILE (an 844 px phone); else the sixth wraps onto a new row.
local function sizeTiles()
	local most = COLUMNS
	for _, row in { buildRow, recruitRow, diplomacyRow } do
		most = math.max(most, #row:GetChildren() - 1) -- less its grid
	end
	local columns = COLUMNS
	if most > COLUMNS and Widgets.tileWidth(innerWidth(), most, GAP) >= MIN_TILE then
		columns = most
	end
	local cell = UDim2.fromOffset(Widgets.tileWidth(innerWidth(), columns, GAP), Widgets.TILE_HEIGHT)
	for _, grid in grids do
		grid.CellSize = cell
	end
end

-- Show the rows that have tiles, sized to fill the sheet, and the sheet.
local function showRows()
	local any = false
	for _, row in { buildRow, recruitRow, diplomacyRow } do
		row.Visible = #row:GetChildren() > 1 -- more than its grid
		any = any or row.Visible
	end
	sizeTiles()
	actions.Visible = any
	sheet.Visible = true
end

local function clearActions()
	Widgets.clear(buildRow)
	Widgets.clear(recruitRow)
	Widgets.clear(diplomacyRow)
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
		clearActions()
		return
	end
	local provinceId: number = id -- non-optional copy for the button callbacks
	shownHints = hintKey(provinceId)
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
	pipChip(info, record.development)
	if record.building ~= "None" then
		chip(info, BUILDING_ICONS[record.building] or "castle", record.building)
	else
		chip(info, "castle", "No building", Theme.color.textDim)
	end
	renderStatus(provinceId, record)

	clearActions()
	local coastal = def.zones ~= nil and #def.zones > 0
	if shipPicker and mine and me and coastal then
		-- how many ships to launch into the port zone, Config.Navy.ShipGold each (MaxShipsPerCommand at most), in
		-- place of the build row; Back returns to it
		for n = 1, Config.Navy.MaxShipsPerCommand do
			local price = n * Config.Navy.ShipGold
			action(
				buildRow,
				"ship",
				if n == 1 then "1 ship" else n .. " ships",
				{ cost("gold", tostring(price), me.gold, price) },
				"build",
				me.gold >= price,
				function()
					shipPicker = false
					Intents.buildShips(provinceId, n)
					render()
				end,
				"Ships_" .. n
			)
		end
		action(buildRow, "back", "Back", {}, Widgets.BUTTON_OFF, true, function()
			shipPicker = false
			render()
		end, "ShipsBack")
		showRows()
		return
	end
	shipPicker = false
	if mine and me then
		local gold = me.gold
		if record.development < Config.Economy.MaxDevelopment then
			local price = Economy.developCost(record.development)
			local costs = { cost("gold", tostring(price), gold, price) }
			action(buildRow, "up", "Develop", costs, "build", gold >= price, function()
				Intents.develop(provinceId)
			end)
		end
		if record.building == "None" then
			for _, building in BUILDABLE do
				local price = Economy.buildingCost(building, me.race :: Types.Race) or 0 -- Hills races: cheaper forts
				local costs = { cost("gold", tostring(price), gold, price) }
				action(buildRow, BUILDING_ICONS[building], building, costs, "build", gold >= price, function()
					Intents.build(provinceId, building)
				end)
			end
		end
		-- ships on a coast: the tile opens the 1-5 choice. A blockaded coast launches nothing: greyed, saying so,
		-- with the anchor (a tap asks the server anyway, which says why in a toast)
		if coastal then
			local blockaded = record.blockade ~= 0
			local shipGold = Config.Navy.ShipGold
			action(
				buildRow,
				"ship",
				if blockaded then "Blockaded" else "Ships",
				{ if blockaded then { "anchor", "" } else cost("gold", tostring(shipGold), gold, shipGold) },
				"build",
				not blockaded and gold >= shipGold,
				function()
					if blockaded then
						Intents.buildShips(provinceId, 1)
					else
						shipPicker = true
						render()
					end
				end,
				"Ships"
			)
		end
		-- one regiment of each troop of your race's roster: line, ranged, fast, elite and special, each button named
		-- "Recruit_<troop id>" (the tutorial and the harness look for them); the line, ranged and fast tiles show the
		-- troop each beats, and which one to pick against the enemy armies near here
		local mix = enemyMix(provinceId, me.id)
		for _, troop in RaceInfo.troops(me.race) do
			local recruitGold, recruitManpower = Economy.recruitCost(1, troop)
			local manpowerText = if recruitManpower % 1000 == 0
				then recruitManpower // 1000 .. "k"
				else tostring(recruitManpower) -- Berserkers: 750
			local tile = action(
				recruitRow,
				RaceInfo.troopIcon(troop),
				RaceInfo.troopName(troop),
				{
					cost("gold", tostring(recruitGold), gold, recruitGold),
					cost("manpower", manpowerText, me.manpower, recruitManpower),
				},
				"recruit",
				gold >= recruitGold and me.manpower >= recruitManpower,
				function()
					Intents.recruit(provinceId, 1, troop)
				end,
				"Recruit_" .. troop
			)
			counterBadge(tile, troop, me.race, mix)
		end
	end
	-- your armies standing here: tap to pick one up and send it somewhere (last in the build row, by the thumb)
	local snap = ClientState.snapshot()
	if me and snap then
		for _, a in snap.armies do
			if a.location == provinceId and a.owner == me.id then
				local armyId = a.id
				action(
					buildRow,
					"arrow",
					"Move",
					{ { RaceInfo.mainTroopIcon(a.troops), shortMen(a.men) } },
					"build",
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
	-- diplomacy with the owner of a foreign province: decisions, in full colour (war crimson, ally azure, peace
	-- emerald)
	if owner and me and owner.id ~= me.id and snap then
		local target = owner.id
		local atWar, allied = Relations.atWar(me.id, target), Relations.allied(me.id, target)
		if atWar then
			for _, tribute in Config.Diplomacy.PeaceTributes do
				local costs = if tribute == 0 then {} else { cost("gold", "+" .. tribute, me.gold, tribute) }
				action(diplomacyRow, "peace", "Peace", costs, Widgets.GOOD, me.gold >= tribute, function()
					Intents.diplomacy("Peace", target, tribute)
				end, "Peace_" .. tribute)
			end
		else
			local canWar = snap.phase ~= "Peace"
				and not allied
				and not Relations.truce(me.id, target)
				and Relations.borders(me.id, target)
			action(diplomacyRow, "war", "Declare war", {}, Widgets.DANGER, canWar, function()
				Intents.diplomacy("War", target)
			end)
			if not allied then
				action(diplomacyRow, "handshake", "Ally", {}, Widgets.BUTTON, true, function()
					Intents.diplomacy("Ally", target)
				end, "🤝 Ally")
			end
		end
		-- the EU4 pack (a match setting): insult (an action with no message; never an ally), a gift, ask for military
		-- access; the same diplomacy row, after war, ally and peace
		if snap.setup.settings.diplomacy then
			if not allied then
				local wait = Relations.cooldown("Insult", me.id, target)
				local costs = if wait > 0 then { { "hourglass", wait .. " s" } } else {}
				action(diplomacyRow, "grudge", "Insult", costs, Widgets.BUTTON, wait == 0, function()
					Intents.diplomacy("Insult", target)
				end, "Insult")
			end
			if not atWar then
				local gift = Config.Diplomacy.GiftGold
				local wait = Relations.cooldown("Gift", me.id, 0) -- one gift a minute, whoever it goes to
				local costs = if wait > 0
					then { { "hourglass", wait .. " s" } }
					else { cost("gold", tostring(gift), me.gold, gift) }
				action(diplomacyRow, "gift", "Gift", costs, Widgets.GOOD, wait == 0 and me.gold >= gift, function()
					Intents.diplomacy("Gift", target)
				end, "Gift")
				if not allied and not Relations.hasAccess(me.id, target) then
					action(diplomacyRow, "access", "Access", {}, Widgets.BUTTON, true, function()
						Intents.diplomacy("Access", target)
					end, "Access")
				end
			end
		end
	end
	showRows()
end

function ProvinceSheet.show(provinceId: number?)
	if provinceId ~= selected then
		shipPicker = false
	end
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
	Widgets.list(row, true, CHIP_GAP)
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

	-- the province's name on a title plate on the sheet's top edge, the close gem on its corner
	local _, plate = Widgets.header(sheet, "", "flag", function()
		ProvinceSheet.show(nil)
		if onClose then
			onClose()
		end
	end)
	title = plate
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
	Widgets.list(actions, false, GAP)
	local function tileRow(order: number, name: string): Frame
		local row = Instance.new("Frame")
		row.Name = name
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(1, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.LayoutOrder = order
		row.Visible = false
		row.Parent = actions
		local grid = Instance.new("UIGridLayout")
		grid.CellPadding = UDim2.fromOffset(GAP, GAP)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row
		table.insert(grids, grid)
		return row
	end
	buildRow = tileRow(1, "Build")
	recruitRow = tileRow(2, "Recruit")
	diplomacyRow = tileRow(3, "Diplomacy")
	-- five (or six) tiles fill a row inside the sheet's frame, however wide the sheet docks
	sizeTiles()
	sheet:GetPropertyChangedSignal("Size"):Connect(sizeTiles)

	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onReset(function()
		ProvinceSheet.show(nil)
	end)
	ClientState.onDelta(function(delta)
		if selected == nil then
			return
		end
		-- the sheet shows prices and enabled buttons, so refresh when this province, any nation or the diplomacy (a
		-- war, an insult's wait) changes
		local relevant = #delta.nations > 0 or delta.diplomacy ~= nil
		for _, r in delta.provinces do
			relevant = relevant or r.id == selected
		end
		-- and when the recruit tiles' counter hints change (enemy armies came or left)
		relevant = relevant or (#delta.armies > 0 or #delta.removedArmies > 0) and hintKey(selected) ~= shownHints
		if relevant then
			render()
		end
	end)
end

return ProvinceSheet
