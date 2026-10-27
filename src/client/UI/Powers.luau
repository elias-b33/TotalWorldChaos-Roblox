--!strict
-- Primordial powers (docs/DESIGN.md "UI and controls"): the power button with your charges, a picker of the six
-- powers, then tap a target on the map and Confirm. Also the toasts and map badges for powers and disasters, and
-- the Primordial view once your nation is eliminated (a banner; the button stays; the map stays free to explore).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Primordial = require(Shared.Sim.Primordial)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local Widgets = require(script.Parent.Widgets)

local BUTTON_SIZE = 72
local PICK_WIDTH = 150
local PICK_HEIGHT = 56 -- big touch targets
local FLASH_SECONDS = 4 -- a strike's badge stays this long on the map

local ICONS: { [string]: string } = {
	Meteor = "☄️",
	Plague = "🦠",
	Rebels = "🏴",
	Earthquake = "🌋",
	Blessing = "🌟",
	Shield = "🛡️",
}

local HINTS: { [string]: string } = {
	Army = "👆 Tap an army",
	Nation = "👆 Tap a nation's land",
	Province = "👆 Tap a province",
}

local Powers = {}

local powerButton: TextButton
local picker: Frame
local bar: Frame
local barTitle: TextLabel
local barHint: TextLabel
local barButtons: Frame
local banner: TextLabel
local toast: (string) -> () = function(_text: string) end
local onOpen: () -> () = function() end

local choosing: Types.PrimordialPower? = nil -- a power picked, waiting for a target
local target: number? = nil
local targetText = ""
local wasPrimordial = false
local flashes: { [number]: { text: string, untilClock: number } } = {}
local shownEffects: { [number]: string } = {}

local function nationName(id: number): string
	local n = ClientState.nation(id)
	return if n then n.name else "Rebels"
end

local function provinceName(id: number): string
	local map = ClientState.map()
	return if map and map.provinces[id] then map.provinces[id].name else "?"
end

local function shortMen(men: number): string
	return if men >= 1000 then string.format("%gk", math.floor(men / 100) / 10) else tostring(men)
end

local function clearHighlight()
	MapRenderer.select(nil)
	MapRenderer.selectArmy(nil)
end

local function closeAll()
	choosing = nil
	target = nil
	picker.Visible = false
	bar.Visible = false
	clearHighlight()
end

local function refreshButton()
	local charges = ClientState.myCharges()
	powerButton.Visible = charges ~= nil
	powerButton.Text = "✨\n⚡" .. tostring(charges or 0)
	if charges == nil then
		closeAll()
	end
end

local function renderPicker()
	Widgets.clear(picker)
	local charges = ClientState.myCharges() or 0
	for i, power in Primordial.POWERS do
		local cost = Primordial.cost(power)
		local enough = charges >= cost
		local b = Widgets.button(
			picker,
			ICONS[power] .. " " .. power .. "\n⚡" .. cost,
			PICK_WIDTH,
			if enough then Widgets.BUTTON else Widgets.BUTTON_OFF,
			function()
				if not enough then
					toast("⚡ Not enough charges")
					return
				end
				Powers.choose(power)
			end
		)
		b.Name = power
		b.Size = UDim2.fromOffset(PICK_WIDTH, PICK_HEIGHT)
		b.LayoutOrder = i
	end
end

local function renderBar()
	local power = choosing
	if power == nil then
		bar.Visible = false
		return
	end
	barTitle.Text = string.format("%s %s  ·  ⚡%d", ICONS[power], power, Primordial.cost(power))
	barHint.Text = if target then "➜ " .. targetText else HINTS[Primordial.TARGETS[power]]
	Widgets.clear(barButtons)
	local chosen = target
	if chosen then
		Widgets.button(barButtons, "✅ Confirm", 140, Widgets.GOOD, function()
			Intents.power(power, chosen)
			closeAll()
		end)
	end
	Widgets.button(barButtons, "✕ Cancel", 120, Widgets.BUTTON_OFF, closeAll)
	bar.Visible = true
end

-- Pick a power: the picker closes and the map waits for a target.
function Powers.choose(power: Types.PrimordialPower)
	choosing = power
	target = nil
	picker.Visible = false
	clearHighlight()
	renderBar()
end

-- True while a picked power waits for a tap on the map.
function Powers.targeting(): boolean
	return choosing ~= nil
end

-- The biggest army in a province, preferring ones that aren't yours.
local function armyIn(provinceId: number): Types.ArmyId?
	local snap = ClientState.snapshot()
	local me = ClientState.myNation()
	local best, bestScore = nil, -math.huge
	if snap then
		for _, a in snap.armies do
			if a.location == provinceId then
				local score = a.men - (if a.owner == me then 1e7 else 0)
				if score > bestScore then
					best, bestScore = a.id, score
				end
			end
		end
	end
	return best
end

-- A tap on the map while targeting: turn it into the power's target (army, nation or province).
function Powers.tap(kind: "Army" | "Province" | nil, id: number?)
	local power = choosing
	if power == nil or kind == nil or id == nil then
		return
	end
	local want = Primordial.TARGETS[power]
	local army = if kind == "Army" then ClientState.army(id) else nil
	local province = if army then army.location elseif kind == "Province" then id else nil
	clearHighlight()
	target = nil
	if want == "Army" then
		local armyId = if army then army.id elseif province then armyIn(province) else nil
		local chosen = if armyId then ClientState.army(armyId) else nil
		if chosen then
			target = chosen.id
			local owner = if chosen.owner == 0 then "Neutral" else nationName(chosen.owner)
			targetText =
				string.format("%s's army (%s) at %s", owner, shortMen(chosen.men), provinceName(chosen.location))
			MapRenderer.selectArmy(chosen.id)
		end
	elseif province then
		local record = ClientState.province(province)
		if want == "Nation" then
			if record and record.owner ~= 0 then
				target = record.owner
				targetText = nationName(record.owner)
				MapRenderer.select(province)
			end
		else
			target = province
			targetText = provinceName(province)
			MapRenderer.select(province)
		end
	end
	if target == nil then
		toast(HINTS[want])
	end
	renderBar()
end

-- Toasts --------------------------------------------------------------------------------------------

local function powerText(e: Types.MatchEvent): string
	local power = Primordial.POWERS[e.a] or "?"
	local icon = ICONS[power] or "✨"
	local me = ClientState.myNation()
	local who = if e.b == 0 then "neutral" elseif e.b == me then "your" else nationName(e.b) .. "'s"
	local text
	if power == "Meteor" then
		text = string.format("%s Meteor struck %s army at %s", icon, who, provinceName(e.province))
	elseif power == "Plague" then
		text = string.format("%s Plague strikes %s", icon, if e.b == me then "you" else nationName(e.b))
	elseif power == "Rebels" then
		text = string.format("%s Rebels rise in %s", icon, provinceName(e.province))
	elseif power == "Earthquake" then
		text = string.format("%s Earthquake in %s", icon, provinceName(e.province))
	elseif power == "Blessing" then
		text = string.format("%s %s is blessed", icon, provinceName(e.province))
	else
		text = string.format("%s %s is shielded", icon, provinceName(e.province))
	end
	if e.kind == "Disaster" then
		text = "🌩 Cataclysm! " .. text
	end
	return text
end

local function onEvent(e: Types.MatchEvent)
	if e.kind == "Power" or e.kind == "Disaster" then
		toast(powerText(e))
		local power = Primordial.POWERS[e.a]
		if power and e.province ~= 0 then
			flashes[e.province] = { text = ICONS[power], untilClock = os.clock() + FLASH_SECONDS }
		end
	elseif e.kind == "Eliminated" and e.a ~= ClientState.myNation() then
		toast("💀 " .. nationName(e.a) .. " was eliminated")
	end
end

-- Map badges: strikes for a few seconds, then shields, blessings and plagues with their seconds left -------------

local function refreshEffects()
	local snap = ClientState.snapshot()
	if snap == nil then
		return
	end
	local tick = ClientState.tick()
	local wanted: { [number]: string } = {}
	local function add(provinceId: number, text: string)
		wanted[provinceId] = if wanted[provinceId] then wanted[provinceId] .. " " .. text else text
	end
	for _, p in snap.provinces do
		if p.shieldUntil > tick then
			add(p.id, ICONS.Shield .. (p.shieldUntil - tick))
		end
		if p.blessedUntil > tick then
			add(p.id, ICONS.Blessing .. (p.blessedUntil - tick))
		end
	end
	for _, n in snap.nations do
		local capital = snap.provinces[n.capital]
		if n.plagueUntil > tick and capital and capital.owner == n.id then
			add(n.capital, ICONS.Plague .. (n.plagueUntil - tick))
		end
	end
	local now = os.clock()
	for provinceId, f in flashes do
		if f.untilClock > now then
			add(provinceId, f.text)
		else
			flashes[provinceId] = nil
		end
	end
	for provinceId, text in wanted do
		if shownEffects[provinceId] ~= text then
			MapRenderer.setEffect(provinceId, text)
		end
	end
	for provinceId in shownEffects do
		if wanted[provinceId] == nil then
			MapRenderer.setEffect(provinceId, nil)
		end
	end
	shownEffects = wanted
end

-- The Primordial view ------------------------------------------------------------------------------------

local function refreshPrimordial()
	local isPrimordial = ClientState.myPrimordial() ~= nil
	banner.Visible = isPrimordial
	if isPrimordial and not wasPrimordial then
		toast("✨ You rose as a Primordial")
		MapView.showWholeMap() -- the whole world is your target now
	end
	wasPrimordial = isPrimordial
end

function Powers.init(showToast: (string) -> (), openHandler: () -> ())
	toast = showToast
	onOpen = openHandler
	local gui = Widgets.screen("Powers", 4)

	powerButton = Instance.new("TextButton")
	powerButton.Name = "PowerButton"
	powerButton.AnchorPoint = Vector2.new(1, 1)
	powerButton.Position = UDim2.new(1, -12, 1, -12)
	powerButton.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
	powerButton.BackgroundColor3 = Color3.fromRGB(120, 70, 200)
	powerButton.Font = Enum.Font.GothamBold
	powerButton.TextSize = 20
	powerButton.TextColor3 = Color3.new(1, 1, 1)
	powerButton.Visible = false
	powerButton.Parent = gui
	Widgets.corner(powerButton, BUTTON_SIZE // 2)
	powerButton.Activated:Connect(function()
		if picker.Visible then
			closeAll()
			return
		end
		closeAll()
		onOpen()
		renderPicker()
		picker.Visible = true
	end)

	-- the picker: 2 columns × 3 rows above the button
	picker = Widgets.panel(gui, 2 * PICK_WIDTH + 28)
	picker.Name = "Picker"
	picker.AnchorPoint = Vector2.new(1, 1)
	picker.Position = UDim2.new(1, -12, 1, -BUTTON_SIZE - 20)
	picker.Visible = false
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(PICK_WIDTH, PICK_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = picker

	-- the targeting bar: which power, what to tap, Confirm / Cancel
	bar = Widgets.panel(gui, 420)
	bar.Name = "TargetBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -8)
	bar.Visible = false
	Widgets.list(bar, false, 6)
	barTitle = Widgets.label(bar, "", 18, 26)
	barTitle.LayoutOrder = 1
	barHint = Widgets.label(bar, "", 15, 22)
	barHint.LayoutOrder = 2
	barButtons = Instance.new("Frame")
	barButtons.Name = "Buttons"
	barButtons.BackgroundTransparency = 1
	barButtons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	barButtons.LayoutOrder = 3
	barButtons.Parent = bar
	Widgets.list(barButtons, true, 8)

	banner = Instance.new("TextLabel")
	banner.Name = "PrimordialBanner"
	banner.Position = UDim2.fromOffset(12, 52) -- top left, clear of toasts, offers and the picker
	banner.Size = UDim2.fromOffset(270, 32)
	banner.BackgroundColor3 = Color3.fromRGB(90, 50, 160)
	banner.BackgroundTransparency = 0.15
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 16
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Text = "✨ You rose as a Primordial"
	banner.Visible = false
	banner.Parent = gui
	Widgets.corner(banner, 10)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onReset(function()
		closeAll()
		flashes = {}
		shownEffects = {}
		wasPrimordial = ClientState.myPrimordial() ~= nil -- joining as a Primordial: no fanfare
		refreshButton()
		refreshPrimordial()
		refreshEffects()
	end)
	ClientState.onDelta(function(delta)
		if #delta.nations > 0 or delta.primordials then
			refreshButton()
			refreshPrimordial()
			if picker.Visible then
				renderPicker()
			end
		end
		for _, e in delta.events do
			onEvent(e)
		end
		if #delta.events > 0 or #delta.provinces > 0 or #delta.nations > 0 then
			refreshEffects()
		end
	end)
	-- the badges count down once a second
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 1 then
			acc = 0
			refreshEffects()
		end
	end)
end

return Powers
