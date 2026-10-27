--!strict
-- Bottom sheet for the tapped province (docs/DESIGN.md "UI and controls"): who owns it, development, building and
-- who is standing there; one-tap actions on your own provinces (develop, build, recruit, move an army) and
-- diplomacy on foreign ones (war, ally, peace). Every button shows its price; the server decides.

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
local Relations = require(Client.Relations)

local SHEET_WIDTH = 560
local BUTTON_HEIGHT = 48 -- at least 44 px on phones

local TERRAIN_ICONS: { [string]: string } = { Plains = "🌾", Forest = "🌲", Hills = "⛰", Mountain = "🏔" }
local BUILDING_ICONS: { [string]: string } = { None = "", Farm = "🌾", Barracks = "⚔", Fort = "🏰" }
local BUILDABLE: { Types.Building } = { "Farm", "Barracks", "Fort" }

local ProvinceSheet = {}

local sheet: Frame
local title: TextLabel
local info: TextLabel
local status: TextLabel
local actions: Frame
local selected: number? = nil
local onClose: (() -> ())? = nil
local onSelectArmy: ((number) -> ())? = nil

local function text(parent: Instance, size: number, height: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, height)
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function button(caption: string, enabled: boolean, onPress: () -> ())
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(124, BUTTON_HEIGHT)
	b.BackgroundColor3 = if enabled then Color3.fromRGB(60, 120, 220) else Color3.fromRGB(70, 72, 84)
	b.AutoButtonColor = enabled
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextWrapped = true
	b.TextColor3 = if enabled then Color3.new(1, 1, 1) else Color3.fromRGB(170, 170, 180)
	b.Text = caption
	b.Parent = actions
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	b.Activated:Connect(onPress)
end

local function shortMen(men: number): string
	return if men >= 1000 then string.format("%gk", math.floor(men / 100) / 10) else tostring(men)
end

-- "🛡 1k garrison", "⚔ 3k Zephyr", "⏳ siege 40%", "💥 battle" for whatever is going on in the province.
local function statusLine(provinceId: number, record: Snapshot.ProvinceRecord): string
	local snap = ClientState.snapshot()
	local parts = {}
	if record.battle then
		table.insert(parts, "💥 Battle")
	elseif record.siegeBy ~= 0 and record.siegeRequired > 0 then
		local by = ClientState.nation(record.siegeBy)
		table.insert(
			parts,
			string.format(
				"⏳ %s siege %d%%",
				if by then by.name else "?",
				math.floor(100 * record.siegeProgress / record.siegeRequired)
			)
		)
	end
	if snap then
		for _, a in snap.armies do
			if a.location == provinceId then
				local owner = ClientState.nation(a.owner)
				table.insert(
					parts,
					if a.owner == 0
						then "🛡 " .. shortMen(a.men) .. " garrison"
						else "⚔ " .. shortMen(a.men) .. " " .. (if owner then owner.name else "?")
				)
			end
		end
	end
	return table.concat(parts, "   ·   ")
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
		return
	end
	local provinceId: number = id -- non-optional copy for the button callbacks
	local def = map.provinces[provinceId]
	local owner = ClientState.nation(record.owner)
	local me = ClientState.nation(ClientState.myNation())
	local mine = owner ~= nil and me ~= nil and owner.id == me.id

	title.Text = (if def.isCapital then "⭐ " else "") .. def.name
	local relation = if owner and me and owner.id ~= me.id then Relations.icon(me.id, owner.id) .. " " else ""
	local ownerText = if owner
		then relation .. owner.name
		elseif def.terrain == "Mountain" then "Impassable"
		else "Neutral"
	info.Text = string.format(
		"%s %s   ·   %s   ·   %s %s",
		TERRAIN_ICONS[def.terrain] or "",
		ownerText,
		pips(record.development),
		BUILDING_ICONS[record.building] or "",
		if record.building == "None" then "No building" else record.building
	)
	info.TextColor3 = if owner
		then Palette.nation(owner.colorIndex):Lerp(Color3.new(1, 1, 1), 0.35)
		else Color3.new(1, 1, 1)
	status.Text = statusLine(provinceId, record)
	status.Visible = status.Text ~= ""

	for _, child in actions:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	if mine and me then
		local gold = me.gold
		if record.development < Config.Economy.MaxDevelopment then
			local cost = Economy.developCost(record.development)
			button("⬆ Develop\n💰" .. cost, gold >= cost, function()
				Intents.develop(provinceId)
			end)
		end
		if record.building == "None" then
			for _, building in BUILDABLE do
				local cost = Economy.buildingCost(building) or 0
				button(BUILDING_ICONS[building] .. " " .. building .. "\n💰" .. cost, gold >= cost, function()
					Intents.build(provinceId, building)
				end)
			end
		end
		local recruitGold, recruitManpower = Economy.recruitCost(1)
		button(
			"⚔ +1 Regiment\n💰" .. recruitGold .. " 👥" .. recruitManpower // 1000 .. "k",
			gold >= recruitGold and me.manpower >= recruitManpower,
			function()
				Intents.recruit(provinceId, 1)
			end
		)
	end
	-- your armies standing here: tap to pick one up and send it somewhere
	local snap = ClientState.snapshot()
	if me and snap then
		for _, a in snap.armies do
			if a.location == provinceId and a.owner == me.id then
				local armyId = a.id
				button("➜ Move\n⚔ " .. shortMen(a.men), not a.inBattle, function()
					if onSelectArmy then
						onSelectArmy(armyId)
					end
				end)
			end
		end
	end
	-- diplomacy with the owner of a foreign province
	if owner and me and owner.id ~= me.id and snap then
		local target = owner.id
		if Relations.atWar(me.id, target) then
			for _, tribute in Config.Diplomacy.PeaceTributes do
				local caption = if tribute == 0 then "🕊 Peace" else "🕊 Peace\n+💰" .. tribute
				button(caption, me.gold >= tribute, function()
					Intents.diplomacy("Peace", target, tribute)
				end)
			end
		else
			local canWar = snap.phase ~= "Peace"
				and not Relations.allied(me.id, target)
				and not Relations.truce(me.id, target)
				and Relations.borders(me.id, target)
			button("⚔ Declare\nwar", canWar, function()
				Intents.diplomacy("War", target)
			end)
			if not Relations.allied(me.id, target) then
				button("🤝 Ally", true, function()
					Intents.diplomacy("Ally", target)
				end)
			end
		end
	end
	sheet.Visible = true
end

function ProvinceSheet.show(provinceId: number?)
	selected = provinceId
	render()
end

function ProvinceSheet.init(closeHandler: () -> (), selectArmyHandler: (number) -> ())
	onClose = closeHandler
	onSelectArmy = selectArmyHandler
	local gui = Instance.new("ScreenGui")
	gui.Name = "ProvinceSheet"
	gui.ResetOnSpawn = false

	sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	sheet.AnchorPoint = Vector2.new(0.5, 1)
	sheet.Position = UDim2.new(0.5, 0, 1, -8)
	sheet.Size = UDim2.fromOffset(SHEET_WIDTH, 0)
	sheet.AutomaticSize = Enum.AutomaticSize.Y
	sheet.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	sheet.BackgroundTransparency = 0.1
	sheet.Visible = false
	sheet.Parent = gui
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(SHEET_WIDTH, math.huge)
	constraint.Parent = sheet
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = sheet
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = sheet
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sheet

	-- header: name on the left, close button on the right
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 44)
	header.LayoutOrder = 1
	header.Parent = sheet
	title = text(header, 20, 44)
	title.Size = UDim2.new(1, -48, 1, 0)

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(44, 44)
	close.BackgroundTransparency = 1
	close.Font = Enum.Font.GothamBold
	close.TextSize = 20
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "✕"
	close.Parent = header
	close.Activated:Connect(function()
		ProvinceSheet.show(nil)
		if onClose then
			onClose()
		end
	end)

	info = text(sheet, 15, 22)
	status = text(sheet, 14, 20)
	status.LayoutOrder = 3
	info.LayoutOrder = 2

	actions = Instance.new("Frame")
	actions.Name = "Actions"
	actions.BackgroundTransparency = 1
	actions.Size = UDim2.fromScale(1, 0)
	actions.AutomaticSize = Enum.AutomaticSize.Y
	actions.LayoutOrder = 4
	actions.Parent = sheet
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(124, BUTTON_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(8, 8)
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
