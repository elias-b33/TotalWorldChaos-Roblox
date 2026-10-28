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
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local BUTTON_SIZE = 68
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

-- The pixel icon of each power (the emoji above stay for map badges and toasts).
local POWER_ICONS: { [string]: string } = {
	Meteor = "meteor",
	Plague = "plague",
	Rebels = "rebels",
	Earthquake = "earthquake",
	Blessing = "blessing",
	Shield = "powerShield",
}

local HINTS: { [string]: string } = {
	Army = "👆 Tap an army",
	Nation = "👆 Tap a nation's land",
	Province = "👆 Tap a province",
}

local Powers = {}

local powerButton: TextButton
local chargesLabel: TextLabel
local picker: Frame
local bar: Frame
local barTitle: TextLabel
local barTitleIcon: GuiObject
local barCost: TextLabel
local barHint: TextLabel
local barButtons: Frame
local banner: TextLabel
local toast: (string) -> () = function(_text: string) end
local onOpen: () -> () = function() end

local choosing: Types.PrimordialPower? = nil -- a power picked, waiting for a target
local target: number? = nil
local targetText = ""
local blocked: string? = nil -- why the last tapped target can't be hit (an immune nation), shown in the bar
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
	blocked = nil
	picker.Visible = false
	bar.Visible = false
	-- hidden panels drop their buttons (they are rebuilt on open), so they don't count against the GUI budget
	Widgets.clear(picker)
	Widgets.clear(barButtons)
	clearHighlight()
end

-- A sandbox world: every power is free, whether you hold a nation or watch (Sim.Sandbox).
local function free(): boolean
	local snap = ClientState.snapshot()
	return snap ~= nil and snap.setup.sandbox == true
end

local function refreshButton()
	local snap = ClientState.snapshot()
	local charges = if snap and not snap.setup.settings.powers then nil else ClientState.myCharges() -- off: no button
	-- in a sandbox the sandbox panel's Powers button opens the picker instead (UI/Sandbox)
	powerButton.Visible = charges ~= nil and not free()
	chargesLabel.Text = tostring(charges or 0)
	if charges == nil and not free() then
		closeAll()
	end
end

local function renderPicker()
	Widgets.clear(picker)
	local charges = if free() then math.huge else ClientState.myCharges() or 0
	for i, power in Primordial.POWERS do
		local cost = Primordial.cost(power)
		local enough = charges >= cost
		local b = Widgets.actionButton(
			picker,
			POWER_ICONS[power],
			power,
			if free() then {} else { { "charge", tostring(cost) } },
			Vector2.new(PICK_WIDTH, PICK_HEIGHT),
			Widgets.SPECIAL,
			function()
				if not enough then
					toast("⚡ Not enough charges")
					return
				end
				Powers.choose(power)
			end,
			power
		)
		b.LayoutOrder = i
		if not enough then
			Widgets.setEnabled(b, false)
		end
	end
end

local function renderBar()
	local power = choosing
	if power == nil then
		bar.Visible = false
		return
	end
	barTitle.Text = power
	Icons.set(barTitleIcon, POWER_ICONS[power])
	barCost.Text = tostring(Primordial.cost(power))
	barCost.Visible = not free()
	Widgets.setIconText(
		barHint,
		if target then "➜ " .. targetText else blocked or HINTS[Primordial.TARGETS[power]],
		"arrow"
	)
	Widgets.clear(barButtons)
	local chosen = target
	if chosen then
		Widgets.iconTextButton(barButtons, "check", "Confirm", 140, Widgets.GOOD, function()
			Intents.power(power, chosen)
			closeAll()
		end, "✅ Confirm")
	end
	Widgets.iconTextButton(barButtons, "close", "Cancel", 120, Widgets.BUTTON_OFF, closeAll, "✕ Cancel")
	bar.Visible = true
end

-- Pick a power: the picker closes and the map waits for a target.
function Powers.choose(power: Types.PrimordialPower)
	choosing = power
	target = nil
	blocked = nil
	picker.Visible = false
	Widgets.clear(picker)
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
	blocked = nil
	local hit = 0 -- the nation the power would hit (0 = nobody)
	if want == "Army" then
		local armyId = if army then army.id elseif province then armyIn(province) else nil
		local chosen = if armyId then ClientState.army(armyId) else nil
		if chosen then
			target = chosen.id
			hit = chosen.owner
			local owner = if chosen.rebel
				then "Rebels"
				elseif chosen.owner == 0 then "Neutral"
				else nationName(chosen.owner)
			targetText =
				string.format("%s's army (%s) at %s", owner, shortMen(chosen.men), provinceName(chosen.location))
			MapRenderer.selectArmy(chosen.id)
		end
	elseif province then
		local record = ClientState.province(province)
		if want == "Nation" then
			if record and record.owner ~= 0 then
				target = record.owner
				hit = record.owner
				targetText = nationName(record.owner)
				MapRenderer.select(province)
			end
		else
			target = province
			hit = if record then record.owner else 0
			targetText = provinceName(province)
			MapRenderer.select(province)
		end
	end
	-- a harmful power can't hit a nation that is still immune (the server would refuse it): no Confirm
	local victim = if hit ~= 0 then ClientState.nation(hit) else nil
	local immuneFor = if victim then victim.powerImmuneUntil - ClientState.tick() else 0
	if target and Primordial.HARMFUL[power] and immuneFor > 0 then
		target = nil
		blocked = string.format("🛡 %s is immune for %d s", nationName(hit), immuneFor)
		toast(blocked)
	elseif target == nil then
		toast(HINTS[want])
	end
	renderBar()
end

-- Toasts --------------------------------------------------------------------------------------------

local function powerText(e: Types.MatchEvent): string
	local power = Primordial.POWERS[e.a] or "?"
	local icon = ICONS[power] or "✨"
	local mine = ClientState.myNation()
	local me = if mine ~= 0 then mine else nil -- 0 is neutral too: a spectator is never "you"
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

-- Open the picker of the six powers, or close it (and any power waiting for a target) if it is open.
function Powers.toggle()
	if picker.Visible then
		closeAll()
		return
	end
	closeAll()
	onOpen()
	renderPicker()
	picker.Visible = true
end

-- True while the picker is open.
function Powers.isOpen(): boolean
	return picker.Visible
end

-- Move the picker (the sandbox panel opens it beside itself instead of above the power button).
function Powers.placePicker(anchor: Vector2, position: UDim2)
	picker.AnchorPoint = anchor
	picker.Position = position
end

function Powers.init(showToast: (string) -> (), openHandler: () -> ())
	toast = showToast
	onOpen = openHandler
	local gui = Widgets.screen("Powers", 4)

	-- the power button: a big purple sparkle with your charges in a badge
	powerButton = Widgets.iconButton(gui, "sparkles", "PowerButton", BUTTON_SIZE, Widgets.SPECIAL, Powers.toggle)
	powerButton.AnchorPoint = Vector2.new(1, 1)
	powerButton.Position = UDim2.new(1, -14, 1, -14)
	powerButton.Visible = false
	local round = powerButton:FindFirstChildOfClass("UICorner")
	if round then
		round.CornerRadius = UDim.new(0.5, 0)
	end
	chargesLabel = Widgets.chip(powerButton, "charge", "0", nil, 24)
	chargesLabel.Name = "Charges"
	chargesLabel.BackgroundColor3 = Theme.color.ink
	chargesLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	chargesLabel.Position = UDim2.new(0.5, 0, 1, -2)
	Widgets.stroke(chargesLabel, Theme.color.gold)

	-- the picker: 2 columns × 3 rows above the button
	picker = Widgets.panel(gui, 2 * PICK_WIDTH + 8 + 2 * Theme.space.l + 2) -- two columns
	picker.Name = "Picker"
	picker.AnchorPoint = Vector2.new(1, 1)
	picker.Position = UDim2.new(1, -12, 1, -BUTTON_SIZE - 30)
	picker.Visible = false
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(PICK_WIDTH, PICK_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = picker

	-- the targeting bar: which power, what to tap, Confirm / Cancel
	bar = Widgets.sheet(gui, 440)
	bar.Name = "TargetBar"
	bar.Visible = false
	Widgets.list(bar, false, Theme.space.s)
	local titleRow = Instance.new("Frame")
	titleRow.Name = "Title"
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, 30)
	titleRow.LayoutOrder = 1
	titleRow.Parent = bar
	Widgets.list(titleRow, true, Theme.space.m)
	barTitle = Widgets.title(titleRow, "", Theme.text.title, 30)
	barTitle.Size = UDim2.fromOffset(0, 30)
	barTitle.AutomaticSize = Enum.AutomaticSize.X
	barTitleIcon = Widgets.leadIcon(barTitle, "sparkles", Theme.icon.small)
	barCost = Widgets.chip(titleRow, "charge", "", nil, 26)
	barCost.LayoutOrder = 2
	barHint = Widgets.label(bar, "", Theme.text.body, 22)
	barHint.LayoutOrder = 2
	Widgets.leadIcon(barHint, "arrow", Theme.size.icon)
	barButtons = Instance.new("Frame")
	barButtons.Name = "Buttons"
	barButtons.BackgroundTransparency = 1
	barButtons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	barButtons.LayoutOrder = 3
	barButtons.Parent = bar
	Widgets.list(barButtons, true, 8)

	banner = Widgets.label(gui, "You rose as a Primordial", Theme.text.body, 34)
	banner.Name = "PrimordialBanner"
	banner.Position = UDim2.fromOffset(12, 54) -- top left, clear of toasts, offers and the picker
	banner.Size = UDim2.fromOffset(270, 34)
	banner.BackgroundColor3 = Widgets.SPECIAL
	banner.BackgroundTransparency = 0.05
	banner.FontFace = Theme.font.display
	banner.TextWrapped = false
	banner.Visible = false
	Widgets.corner(banner, Theme.radius.m)
	Widgets.stroke(banner)
	Widgets.padding(banner, Theme.space.m, 0)
	Widgets.leadIcon(banner, "sparkles", Theme.size.icon)

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
