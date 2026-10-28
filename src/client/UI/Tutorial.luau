--!strict
-- The tutorial prompts (docs/DESIGN.md "Tutorial"): a small card under the top bar with the step counter, one short
-- line and a hint, an arrow over the province to tap, and a glowing outline on the button to press. The server
-- decides which prompt is current (Sim.Tutorial, the Tutorial remote); the player does every step with the normal
-- UI, so this module only looks at what is on screen and points.
--
-- Nothing here covers what it points at: the card sits top left (clear of toasts, offers and the bottom sheets),
-- the map arrow stands above its province and under every panel, and a button gets an outline, not a cover.
-- Built from the UI kit: a panel with a gold outline, a gold step pill, a title and a hint with pixel icons, and the
-- arrows are the kit's pixel arrow turned to point down, in gold. A hint that says to tap the map wears that same
-- arrow; a hint that names a button wears the button's own icon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Intents = require(Client.Intents)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local Icons = require(script.Parent.Icons)
local Powers = require(script.Parent.Powers)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local CARD_WIDTH = 236 -- clear of the toasts in the middle of the top (Hud TOAST_WIDTH)
local CARD_TOP = 52 -- under the top bar
local STEP_WIDTH = 40 -- the "2/6" pill
local TITLE_HEIGHT = 24
local SKIP_WIDTH = 60
local HINT_ICON = 16 -- the hint's icon, so a hint like "Tap +1 Regiment" fits one line
local HINT_TOP = 30 -- the hint line and Skip sit under the title
local ARROW_SIZE = 48 -- the 16×16 pixel arrow at 3× (whole pixels stay crisp)
local ARROW_TURN = 90 -- the kit's arrow points right; turned this many degrees it points down
local RING_SHARE = 0.6 -- the ring round a province: this share of its radius on screen...
local RING_MIN = 22 -- ...within these pixels
local RING_MAX = 90
local RING_EDGE = 5 -- the ring's dark edge under its 3 px gold line, so it shows on any terrain
local SEARCH_SECONDS = 0.2 -- how often the on-screen buttons are checked
local SKIP_CONFIRM_SECONDS = 3
local GLOW = Theme.color.gold
local NO_TINT = Color3.new(1, 1, 1) -- an icon in its own colours (a tint multiplies them)
local STEPS = { "Take", "Recruit", "Siege", "Ally", "War", "Power" } -- Sim.Tutorial.STEPS
-- the panels whose buttons a prompt can point at
local PANELS = { "ProvinceSheet", "ArmySheet", "Powers" }
local POINT = "point" -- a hint's icon when it says to tap the map: the map arrow itself

-- Each prompt's title: an icon and a few words.
local TITLES: { [string]: { icon: string, text: string } } = {
	Take = { icon = "flag", text = "Take grey land" },
	Recruit = { icon = "sword", text = "Recruit soldiers" },
	Siege = { icon = "hourglass", text = "Siege grey land" },
	Ally = { icon = "handshake", text = "Make an ally" },
	War = { icon = "war", text = "Declare war" },
	Power = { icon = "sparkles", text = "Use a power" },
}

local Tutorial = {}

local view: Types.TutorialView? = nil
local getSelectedArmy: () -> number? = function()
	return nil
end
local playerGui: PlayerGui
local cardGui: ScreenGui
local card: Frame
local stepLabel: TextLabel
local titleLabel: TextLabel
local titleIcon: GuiObject
local hintLabel: TextLabel
local hintIcon: GuiObject
local skipButton: TextButton
local doneCard: Frame
local doneButtons: Frame
local leaveButton: TextButton -- "Play online" while the prompts are skipped or done and leaving works here
local pointerGui: ScreenGui
local pointer: GuiObject
local ring: Frame
local buttonArrow: GuiObject
local glow: UIStroke? = nil -- on glowOn; panels rebuild their buttons, so each button gets its own
local skipArmedUntil = 0
local doneDismissed = false
local centredKey = ""
local pointAt: number? = nil -- province the map arrow points at
local glowOn: GuiButton? = nil -- button that glows

local function nationName(id: number): string
	local n = ClientState.nation(id)
	return if n then n.name else "?"
end

-- An icon in the tutorial's gold (a pixel icon is tinted; the emoji fallback takes the colour as text).
local function tint(obj: GuiObject, color: Color3)
	if obj:IsA("ImageLabel") then
		obj.ImageColor3 = color
	elseif obj:IsA("TextLabel") then
		obj.TextColor3 = color
	end
end

-- The map arrow: the kit's pixel arrow turned to point down, in gold.
local function arrow(parent: Instance, name: string): GuiObject
	local a = Icons.label(parent, "arrow", ARROW_SIZE)
	a.Name = name
	a.AnchorPoint = Vector2.new(0.5, 1)
	a.Rotation = ARROW_TURN
	a.Visible = false
	tint(a, GLOW)
	return a
end

local function visible(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("ScreenGui") and not node.Enabled then
			return false
		end
		node = node.Parent
	end
	return true
end

-- The first visible button in the game's panels whose text contains `needle` (or that is named `needle`).
local function findButton(needle: string): TextButton?
	for _, name in PANELS do
		local gui = playerGui:FindFirstChild(name)
		if gui then
			for _, d in gui:GetDescendants() do
				if
					d:IsA("TextButton")
					and (d.Name == needle or string.find(d.Text, needle, 1, true) ~= nil)
					and visible(d)
				then
					return d
				end
			end
		end
	end
	return nil
end

local function myArmies(): { any }
	local out = {}
	local snap = ClientState.snapshot()
	local me = ClientState.myNation()
	if snap then
		for _, a in snap.armies do
			if a.owner == me then
				table.insert(out, a)
			end
		end
	end
	return out
end

-- Take and Siege: pick up an army, tap the grey province, Go, then wait for the fight and the siege.
-- Each returns the hint's icon, the hint (one short line on a phone, two at most), the button to glow (a needle for
-- findButton) and the province to point at.
local function marchPlan(v: Types.TutorialView): (string, string, string?, number?)
	if findButton("✅ Go") then
		return "check", "Tap Go", "✅ Go", v.province
	end
	if getSelectedArmy() then
		return POINT, "Tap grey land", nil, v.province
	end
	local idle = nil
	for _, a in myArmies() do
		if a.dest == v.province or a.location == v.province then
			if a.inBattle then
				return "battle", "Battle!", nil, v.province
			end
			return "hourglass", if a.dest ~= 0 then "Marching…" else "Siege running…", nil, v.province
		end
		if a.dest == 0 and not a.inBattle and idle == nil then
			idle = a
		end
	end
	if findButton("➜ Move") then
		return "arrow", "Tap Move", "➜ Move", nil
	end
	if idle then
		return POINT, "Tap your army", nil, idle.location
	end
	if findButton("Regiment") then
		return "sword", "Tap Infantry", "Regiment", nil
	end
	local me = ClientState.nation(ClientState.myNation())
	return POINT, "Tap your land", nil, if me then me.capital else nil
end

-- The hint's icon and line, the button to glow and the province to point at, for this moment.
local function plan(v: Types.TutorialView): (string, string, string?, number?)
	local step = STEPS[v.step]
	if step == "Take" or step == "Siege" then
		return marchPlan(v)
	elseif step == "Recruit" then
		if findButton("Regiment") then
			return "sword", "Tap Infantry", "Regiment", nil
		end
		return POINT, "Tap your land", nil, v.province
	elseif step == "Ally" then
		if findButton("🤝 Ally") then
			return "handshake", "Tap Ally", "🤝 Ally", nil
		end
		return POINT, "Tap their land", nil, v.province
	elseif step == "War" then
		if findButton("Declare") then
			return "war", "Tap Declare war", "Declare", nil
		end
		return POINT, "Tap their land", nil, v.province
	elseif step == "Power" then
		if findButton("✅ Confirm") then
			return "check", "Tap Confirm", "✅ Confirm", nil
		end
		if Powers.targeting() then
			return POINT, "Tap your land", nil, v.province
		end
		if findButton("Blessing") then
			return "blessing", "Pick Blessing", "Blessing", nil
		end
		return "sparkles", "Tap the power button", "PowerButton", nil
	end
	return "sparkles", "", nil, nil
end

-- The prompt's icon and title ("Ally with Zephyr").
local function title(v: Types.TutorialView): (string, string)
	local step = STEPS[v.step]
	local def = TITLES[step] or { icon = "sparkles", text = "" }
	if step == "Ally" and v.nation ~= 0 then
		return def.icon, "Ally with " .. nationName(v.nation)
	elseif step == "War" and v.nation ~= 0 then
		return def.icon, "War on " .. nationName(v.nation)
	end
	return def.icon, def.text
end

local function setHint(icon: string, text: string)
	hintLabel.Text = text
	-- the map arrow's own arrow when the hint means "tap where the arrow points", else the button's icon
	local point = icon == POINT
	Icons.set(hintIcon, if point then "arrow" else icon)
	hintIcon.Rotation = if point then ARROW_TURN else 0
	tint(hintIcon, if point then GLOW else NO_TINT)
	hintIcon:SetAttribute("Points", point)
end

local function renderDone(v: Types.TutorialView)
	Widgets.clear(doneButtons)
	if v.canLeave then
		Widgets.iconTextButton(doneButtons, "globe", "Play online", 160, Widgets.GOOD, function()
			Intents.tutorial("Leave")
		end)
		Widgets.button(doneButtons, "Stay", 120, Widgets.BUTTON_OFF, function()
			doneDismissed = true
			doneCard.Visible = false
		end)
	else
		Widgets.iconTextButton(doneButtons, "check", "Keep playing", 180, Widgets.GOOD, function()
			doneDismissed = true
			doneCard.Visible = false
		end)
	end
end

-- Check what is on screen: the hint, the glowing button and the map arrow.
local function refresh()
	local v = view
	local active = v ~= nil and v.step >= 1 and v.step <= v.total
	card.Visible = active
	pointAt = nil
	local target: GuiButton? = nil
	if v and active then
		local icon, hint, needle, province = plan(v)
		local titleIconName, titleText = title(v)
		stepLabel.Text = string.format("%d/%d", v.step, v.total)
		titleLabel.Text = titleText
		Icons.set(titleIcon, titleIconName)
		setHint(icon, hint)
		target = if needle then findButton(needle) else nil
		pointAt = if province and province ~= 0 then province else nil
		-- a new place to look: bring it on screen once (closer at the start of a prompt)
		local key = v.step .. ":" .. (pointAt or 0)
		if key ~= centredKey and pointAt and ClientState.map() then
			MapView.centreOn(MapRenderer.centerOf(pointAt), not string.find(centredKey, "^" .. v.step .. ":"))
			centredKey = key
		end
	end
	if os.clock() > skipArmedUntil and skipButton.Text ~= "Skip" then
		skipButton.Text = "Skip"
		skipButton.BackgroundColor3 = Widgets.BUTTON_OFF
	end
	doneCard.Visible = v ~= nil and v.step > v.total and not doneDismissed
	-- after Skip, Stay or a teleport that failed: a way out stays on screen
	leaveButton.Visible = v ~= nil and v.canLeave and not card.Visible and not doneCard.Visible
	if target ~= glowOn or (glow and glow.Parent ~= target) then
		if glow and glow.Parent then
			glow:Destroy()
		end
		glow = nil
		glowOn = target
		if target then
			local stroke = Instance.new("UIStroke")
			stroke.Name = "TutorialGlow"
			stroke.Color = GLOW
			stroke.Thickness = 3
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = target
			glow = stroke
		end
	end
end

-- Every frame: the arrows follow the map and the buttons.
local function place()
	local bob = math.sin(os.clock() * 6) * 4
	local province = pointAt
	if province and ClientState.map() then
		-- a ring round the province, and the arrow standing on top of the ring
		local screen = MapView.toScreen(MapRenderer.centerOf(province))
		local radius = math.clamp(MapRenderer.radiusOf(province) * MapView.zoom() * RING_SHARE, RING_MIN, RING_MAX)
		ring.Size = UDim2.fromOffset(2 * radius, 2 * radius)
		ring.Position = UDim2.fromOffset(screen.X, screen.Y)
		ring.Visible = true
		-- over the ring and over the province's army badges, kept on screen and below the top bars, in full-screen
		-- coordinates (the pointer GUI covers what the map does)
		local size = MapView.screenSize()
		local top = ARROW_SIZE + MapView.topBand()
		local above = math.max(radius, MapRenderer.overlayTop(province))
		local x = math.clamp(screen.X, ARROW_SIZE / 2, math.max(ARROW_SIZE / 2, size.X - ARROW_SIZE / 2))
		local y = math.clamp(screen.Y - above - 2, top, math.max(top, size.Y))
		pointer.Position = UDim2.fromOffset(x, y + bob)
		pointer.Visible = true
	else
		pointer.Visible = false
		ring.Visible = false
	end
	local button = glowOn
	local stroke = glow
	if stroke and stroke.Parent then
		stroke.Thickness = 3 + (bob + 4) / 4
	else
		button = nil -- its panel rebuilt it; the next check finds the new one
	end
	-- an arrow above the glowing button, where the layout engine says it is (it stands clear of the button)
	if button and button.AbsoluteSize.X > 0 then
		local p, s = button.AbsolutePosition, button.AbsoluteSize
		buttonArrow.Position = UDim2.fromOffset(p.X + s.X / 2, p.Y - 2 + bob)
		buttonArrow.Visible = true
	else
		buttonArrow.Visible = false
	end
end

function Tutorial.init(selectedArmy: () -> number?)
	getSelectedArmy = selectedArmy
	playerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui

	-- the map arrow and the ring: on the whole screen like the map, above the map and under every panel
	pointerGui = Widgets.screen("TutorialPointer", -5)
	pointerGui.ScreenInsets = Enum.ScreenInsets.None
	pointer = arrow(pointerGui, "Pointer")
	ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = pointerGui
	Widgets.corner(ring, 999)
	local ringEdge = Instance.new("UIStroke")
	ringEdge.Color = Theme.color.ink
	ringEdge.Thickness = RING_EDGE
	ringEdge.Parent = ring
	local ringLine = Instance.new("Frame")
	ringLine.Name = "Line"
	ringLine.Size = UDim2.fromScale(1, 1)
	ringLine.BackgroundTransparency = 1
	ringLine.Parent = ring
	Widgets.corner(ringLine, 999)
	local ringGold = Instance.new("UIStroke")
	ringGold.Color = GLOW
	ringGold.Thickness = 3
	ringGold.Parent = ringLine
	pointerGui.Parent = playerGui

	-- the prompt card: a panel with a gold outline
	cardGui = Widgets.screen("Tutorial", 5)
	card = Widgets.panel(cardGui, CARD_WIDTH)
	card.Name = "Card"
	card.Position = UDim2.fromOffset(Theme.space.m, CARD_TOP)
	card.Visible = false
	local outline = card:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = GLOW
	end
	-- "2/6" in a gold pill and the prompt's title across the top; the hint under it, with Skip on its right
	stepLabel = Widgets.label(card, "", Theme.text.body, TITLE_HEIGHT)
	stepLabel.Name = "Step"
	stepLabel.Size = UDim2.fromOffset(STEP_WIDTH, TITLE_HEIGHT)
	stepLabel.BackgroundColor3 = GLOW
	stepLabel.BackgroundTransparency = 0
	stepLabel.FontFace = Theme.font.display
	stepLabel.TextColor3 = Theme.color.textDark
	stepLabel.TextXAlignment = Enum.TextXAlignment.Center
	stepLabel.TextWrapped = false
	Widgets.corner(stepLabel, Theme.radius.m)
	titleLabel = Widgets.title(card, "", Theme.text.heading, TITLE_HEIGHT)
	titleLabel.Name = "Title"
	titleLabel.TextColor3 = Theme.color.text
	titleLabel.Position = UDim2.fromOffset(STEP_WIDTH + Theme.space.s, 0)
	titleLabel.Size = UDim2.new(1, -(STEP_WIDTH + Theme.space.s), 0, TITLE_HEIGHT)
	titleIcon = Widgets.leadIcon(titleLabel, "flag", Theme.size.icon, Theme.space.xs)
	hintLabel = Widgets.label(card, "", Theme.text.body, Widgets.BUTTON_HEIGHT)
	hintLabel.Name = "Hint"
	hintLabel.TextColor3 = GLOW
	hintLabel.Position = UDim2.fromOffset(0, HINT_TOP)
	hintLabel.Size = UDim2.new(1, -SKIP_WIDTH - Theme.space.s, 0, Widgets.BUTTON_HEIGHT)
	hintIcon = Widgets.leadIcon(hintLabel, "arrow", HINT_ICON, Theme.space.xs)
	-- two taps to skip, so a stray tap doesn't throw the tutorial away
	skipButton = Widgets.button(card, "Skip", SKIP_WIDTH, Widgets.BUTTON_OFF, function()
		if os.clock() <= skipArmedUntil then
			skipArmedUntil = 0
			Intents.tutorial("Skip")
		else
			skipArmedUntil = os.clock() + SKIP_CONFIRM_SECONDS
			skipButton.Text = "Sure?"
			skipButton.BackgroundColor3 = Widgets.DANGER
		end
	end)
	skipButton.Name = "Skip"
	skipButton.TextSize = Theme.text.body
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, 0, 0, HINT_TOP)

	-- skipped, or the end card closed with Stay: a small way out where the card was
	leaveButton = Widgets.iconTextButton(cardGui, "globe", "Play online", 170, Widgets.GOOD, function()
		Intents.tutorial("Leave")
	end)
	leaveButton.Name = "PlayOnline"
	leaveButton.Position = UDim2.fromOffset(Theme.space.m, CARD_TOP)
	leaveButton.Visible = false

	-- the end: a card in the middle of the screen
	doneCard = Widgets.panel(cardGui, 340)
	doneCard.Name = "Done"
	doneCard.AnchorPoint = Vector2.new(0.5, 0.5)
	doneCard.Position = UDim2.fromScale(0.5, 0.5)
	doneCard.Visible = false
	Widgets.list(doneCard, false, Theme.space.m)
	local doneTitle = Widgets.title(doneCard, "Tutorial done!", Theme.text.hero, 36)
	doneTitle.LayoutOrder = 1
	Widgets.leadIcon(doneTitle, "trophy", Theme.size.iconLarge)
	Widgets.label(doneCard, "Now go rule the world!", Theme.text.heading, 26).LayoutOrder = 2
	doneButtons = Instance.new("Frame")
	doneButtons.Name = "Buttons"
	doneButtons.BackgroundTransparency = 1
	doneButtons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	doneButtons.LayoutOrder = 3
	doneButtons.Parent = doneCard
	Widgets.list(doneButtons, true, Theme.space.m)

	-- the arrow over a glowing button
	buttonArrow = arrow(cardGui, "ButtonArrow")
	cardGui.Parent = playerGui

	Remotes.event("Tutorial").OnClientEvent:Connect(function(newView: Types.TutorialView?)
		local old = view
		view = newView
		if newView and newView.step > newView.total and not (old and old.step > old.total) then
			doneDismissed = false
			renderDone(newView)
		end
		refresh()
	end)
	ClientState.onReset(function()
		centredKey = ""
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= SEARCH_SECONDS then
			acc = 0
			refresh()
		end
		place()
	end)
end

return Tutorial
