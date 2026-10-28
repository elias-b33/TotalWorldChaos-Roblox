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
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local BUTTON_MARGIN = Vector2.new(14, 24) -- the power button from the screen's right and bottom (its charges under it)
local BUTTON_SIZE = 64 -- the large medallion
local PICK_COLUMNS = 3 -- the six powers in two rows
local PICK_WIDTH = 132 -- a slot tile
local PICK_GAP = Theme.space.m
local BUTTON_WIDTH = 200 -- Confirm and Cancel side by side fill the targeting sheet
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
local pickerTiles: Frame
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
	Widgets.clear(pickerTiles)
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

-- The six powers as slot tiles on a royal base: the icon, the name and the charges it costs (in red when you have
-- fewer; the tile greys out but still explains in a toast).
local function renderPicker()
	Widgets.clear(pickerTiles)
	local charges = if free() then math.huge else ClientState.myCharges() or 0
	for i, power in Primordial.POWERS do
		local cost = Primordial.cost(power)
		local enough = charges >= cost
		local b = Widgets.slotTile(
			pickerTiles,
			POWER_ICONS[power],
			power,
			-- free in a sandbox: no cost to show
			if free()
				then {}
				elseif enough then { { "charge", tostring(cost) } }
				else { { "charge", tostring(cost), "short" } },
			Vector2.new(PICK_WIDTH, Widgets.TILE_HEIGHT),
			"powers",
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
		Widgets.iconTextButton(barButtons, "check", "Confirm", BUTTON_WIDTH, Widgets.GOOD, function()
			Intents.power(power, chosen)
			closeAll()
		end, "✅ Confirm")
	end
	Widgets.iconTextButton(barButtons, "close", "Cancel", BUTTON_WIDTH, Widgets.BUTTON_OFF, closeAll, "✕ Cancel")
	bar.Visible = true
end

-- Pick a power: the picker closes and the map waits for a target.
function Powers.choose(power: Types.PrimordialPower)
	choosing = power
	target = nil
	blocked = nil
	picker.Visible = false
	Widgets.clear(pickerTiles)
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
	-- nor one this player hit less than Config.Primordial.TargetCooldownTicks ago (Primordial.casterKey)
	local cooldownFor = 0
	if target and Primordial.HARMFUL[power] and victim then
		local snap = ClientState.snapshot()
		local mine = ClientState.myPrimordial()
		local key = if mine then "u" .. mine.userId else "n" .. tostring(ClientState.myNation())
		for _, c in if snap then snap.powerCooldowns or {} else {} do
			if c.caster == key and c.target == hit then
				cooldownFor = c.untilTick - ClientState.tick()
			end
		end
	end
	if target and Primordial.HARMFUL[power] and immuneFor > 0 then
		target = nil
		blocked = string.format("🛡 %s is immune for %d s", nationName(hit), immuneFor)
		toast(blocked)
	elseif target and Primordial.HARMFUL[power] and cooldownFor > 0 then
		target = nil
		blocked = string.format("⏳ You can hit %s again in %d s", nationName(hit), cooldownFor)
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

-- Move the picker (the sandbox panel opens it beside itself instead of beside the power button). The picker is a
-- fitted root (tablets): Widgets.fit keeps its new place when the UI's scale changes.
function Powers.placePicker(anchor: Vector2, position: UDim2)
	picker.AnchorPoint = anchor
	Widgets.fit(picker, nil, position)
end

function Powers.init(showToast: (string) -> (), openHandler: () -> ())
	toast = showToast
	onOpen = openHandler
	local gui = Widgets.screen("Powers", 4)

	-- the power button: the large royal medallion with the sparkles, your charges in a well under it
	powerButton = Widgets.medallionButton(gui, "large", "power", "sparkles", "PowerButton", Powers.toggle)
	powerButton.AnchorPoint = Vector2.new(1, 1)
	powerButton.Position = UDim2.new(1, -BUTTON_MARGIN.X, 1, -BUTTON_MARGIN.Y)
	powerButton.Visible = false
	chargesLabel = Widgets.chip(powerButton, "charge", "0", nil, 24)
	chargesLabel.Name = "Charges"
	chargesLabel.AnchorPoint = Vector2.new(0.5, 0)
	chargesLabel.Position = UDim2.new(0.5, 0, 1, -8)
	chargesLabel.ZIndex = 5

	-- the picker: an iron panel docked at the bottom beside the power button (clear of the toasts and offers under the
	-- top bar), the six powers in a 3 x 2 grid of slot tiles
	picker = Widgets.panel(gui, PICK_COLUMNS * PICK_WIDTH + (PICK_COLUMNS - 1) * PICK_GAP + 2 * Widgets.PANEL_PAD)
	picker.Name = "Picker"
	picker.AnchorPoint = Vector2.new(1, 1)
	picker.Position = UDim2.new(1, -(BUTTON_MARGIN.X + BUTTON_SIZE + Theme.space.m), 1, -Theme.space.m)
	picker.Visible = false
	Widgets.header(picker, "Powers", "sparkles")
	pickerTiles = Instance.new("Frame")
	pickerTiles.Name = "Tiles"
	pickerTiles.BackgroundTransparency = 1
	pickerTiles.Size = UDim2.fromScale(1, 0)
	pickerTiles.AutomaticSize = Enum.AutomaticSize.Y
	pickerTiles.Parent = picker
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(PICK_WIDTH, Widgets.TILE_HEIGHT)
	grid.CellPadding = UDim2.fromOffset(PICK_GAP, PICK_GAP)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = pickerTiles

	-- the targeting bar: which power, what to tap, Confirm / Cancel
	bar = Widgets.sheet(gui, 444)
	bar.Name = "TargetBar"
	bar.Visible = false
	Widgets.list(bar, false, Theme.space.s)
	-- the power on a title plate on the bar's top edge, its cost in charges under it
	local _, plate = Widgets.header(bar, "", "sparkles")
	barTitle = plate
	barTitleIcon = barTitle:FindFirstChild("Icon") :: GuiObject
	local titleRow = Instance.new("Frame")
	titleRow.Name = "Cost"
	titleRow.BackgroundTransparency = 1
	titleRow.Size = UDim2.new(1, 0, 0, 28)
	titleRow.LayoutOrder = 1
	titleRow.Parent = bar
	Widgets.list(titleRow, true, Theme.space.m)
	barCost = Widgets.chip(titleRow, "charge", "", nil, 28)
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

	-- a status plate (not a button): the sparkles and the line, on the slate plate toasts use
	banner = Widgets.label(gui, "You rose as a Primordial", Theme.text.body, 36)
	banner.Name = "PrimordialBanner"
	banner.Size = UDim2.fromOffset(270, 36)
	banner.BackgroundColor3 = Widgets.SPECIAL
	banner.BackgroundTransparency = 0.05
	banner.FontFace = Theme.font.display
	banner.TextWrapped = false
	banner.Visible = false
	Widgets.corner(banner, Theme.radius.s)
	Widgets.stroke(banner)
	Widgets.padding(banner, Theme.space.m, 0)
	Widgets.leadIcon(banner, "sparkles", Theme.size.icon)
	Widgets.skin(banner, "plate", "plate")
	Widgets.shadow(banner, "plate")

	-- the banner at the top left under the top bar, clear of toasts, offers and the picker
	local function place()
		Widgets.fit(banner, nil, UDim2.fromOffset(12, HudLayout.contentTop()))
	end
	place()
	HudLayout.onChange(place)
	Widgets.fitScreen(gui) -- tablets: the screen's roots grow with the UI's scale
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
