--!strict
-- The tutorial prompts (docs/DESIGN.md "Tutorial"): a small card under the top bar with the step counter, one short
-- line and a hint, an arrow over the province to tap, and a glowing outline on the button to press. The server
-- decides which prompt is current (Sim.Tutorial, the Tutorial remote); the player does every step with the normal
-- UI, so this module only looks at what is on screen and points.
--
-- Nothing here covers what it points at: the card sits top left (clear of toasts, offers and the bottom sheets),
-- the map arrow stands above its province and under every panel, and a button gets an outline, not a cover.

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
local Powers = require(script.Parent.Powers)
local Widgets = require(script.Parent.Widgets)

local CARD_WIDTH = 236
local CARD_TOP = 52 -- under the top bar
local SKIP_WIDTH = 64
local HINT_TOP = 26 -- the hint line and Skip sit under the title
local ARROW_SIZE = 44
local RING_SHARE = 0.6 -- the ring round a province: this share of its radius on screen...
local RING_MIN = 22 -- ...within these pixels
local RING_MAX = 90
local SEARCH_SECONDS = 0.2 -- how often the on-screen buttons are checked
local SKIP_CONFIRM_SECONDS = 3
local GLOW = Color3.fromRGB(255, 214, 64)
local STEPS = { "Take", "Recruit", "Siege", "Ally", "War", "Power" } -- Sim.Tutorial.STEPS
-- the panels whose buttons a prompt can point at
local PANELS = { "ProvinceSheet", "ArmySheet", "Powers" }

local TITLES: { [string]: string } = {
	Take = "🏴 Take grey land",
	Recruit = "⚔ Recruit soldiers",
	Siege = "⏳ Siege grey land",
	Ally = "🤝 Make an ally",
	War = "⚔ Declare war",
	Power = "✨ Use a power",
}

local Tutorial = {}

local view: Types.TutorialView? = nil
local getSelectedArmy: () -> number? = function()
	return nil
end
local playerGui: PlayerGui
local cardGui: ScreenGui
local card: Frame
local titleLabel: TextLabel
local hintLabel: TextLabel
local skipButton: TextButton
local doneCard: Frame
local doneButtons: Frame
local pointerGui: ScreenGui
local pointer: TextLabel
local ring: Frame
local buttonArrow: TextLabel
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
-- Hints stay one short line on a phone (about 17 characters).
local function marchPlan(v: Types.TutorialView): (string, string?, number?)
	if findButton("✅ Go") then
		return "Tap ✅ Go", "✅ Go", v.province
	end
	if getSelectedArmy() then
		return "👇 Tap grey land", nil, v.province
	end
	local idle = nil
	for _, a in myArmies() do
		if a.dest == v.province or a.location == v.province then
			local hint = if a.inBattle
				then "💥 Battle!"
				elseif a.dest ~= 0 then "⏳ Marching…"
				else "⏳ Siege running…"
			return hint, nil, v.province
		end
		if a.dest == 0 and not a.inBattle and idle == nil then
			idle = a
		end
	end
	if findButton("➜ Move") then
		return "Tap ➜ Move", "➜ Move", nil
	end
	if idle then
		return "👇 Tap your army", nil, idle.location
	end
	if findButton("Regiment") then
		return "Tap +1 Regiment", "Regiment", nil
	end
	local me = ClientState.nation(ClientState.myNation())
	return "👇 Tap your land", nil, if me then me.capital else nil
end

-- The hint line, the button to glow (a needle for findButton) and the province to point at, for this moment.
local function plan(v: Types.TutorialView): (string, string?, number?)
	local step = STEPS[v.step]
	if step == "Take" or step == "Siege" then
		return marchPlan(v)
	elseif step == "Recruit" then
		if findButton("Regiment") then
			return "Tap +1 Regiment", "Regiment", nil
		end
		return "👇 Tap your land", nil, v.province
	elseif step == "Ally" then
		if findButton("🤝 Ally") then
			return "Tap 🤝 Ally", "🤝 Ally", nil
		end
		return "👇 Tap their land", nil, v.province
	elseif step == "War" then
		if findButton("Declare") then
			return "Tap ⚔ Declare war", "Declare", nil
		end
		return "👇 Tap their land", nil, v.province
	elseif step == "Power" then
		if findButton("✅ Confirm") then
			return "Tap ✅ Confirm", "✅ Confirm", nil
		end
		if Powers.targeting() then
			return "👇 Tap your land", nil, v.province
		end
		if findButton("Blessing") then
			return "Pick 🌟 Blessing", "Blessing", nil
		end
		return "Tap the ✨ button", "PowerButton", nil
	end
	return "", nil, nil
end

local function title(v: Types.TutorialView): string
	local step = STEPS[v.step]
	local text = TITLES[step] or ""
	if step == "Ally" and v.nation ~= 0 then
		text = "🤝 Ally with " .. nationName(v.nation)
	elseif step == "War" and v.nation ~= 0 then
		text = "⚔ War on " .. nationName(v.nation)
	end
	return string.format("%d/%d  %s", v.step, v.total, text)
end

local function renderDone(v: Types.TutorialView)
	Widgets.clear(doneButtons)
	if v.canLeave then
		Widgets.button(doneButtons, "🌍 Play online", 150, Widgets.GOOD, function()
			Intents.tutorial("Leave")
		end)
	end
	Widgets.button(doneButtons, if v.canLeave then "Stay" else "✅ Keep playing", 150, Widgets.BUTTON, function()
		doneDismissed = true
		doneCard.Visible = false
	end)
end

-- Check what is on screen: the hint, the glowing button and the map arrow.
local function refresh()
	local v = view
	local active = v ~= nil and v.step >= 1 and v.step <= v.total
	card.Visible = active
	pointAt = nil
	local target: GuiButton? = nil
	if v and active then
		local hint, needle, province = plan(v)
		titleLabel.Text = title(v)
		hintLabel.Text = hint
		target = if needle then findButton(needle) else nil
		pointAt = if province and province ~= 0 then province else nil
		-- a new place to look: bring it on screen once (closer at the start of a prompt)
		local key = v.step .. ":" .. (pointAt or 0)
		if key ~= centredKey and pointAt and ClientState.map() then
			MapView.centreOn(MapRenderer.centerOf(pointAt), not string.find(centredKey, "^" .. v.step .. ":"))
			centredKey = key
		end
	end
	if os.clock() > skipArmedUntil then
		skipButton.Text = "⏭ Skip"
		skipButton.BackgroundColor3 = Widgets.BUTTON_OFF
	end
	doneCard.Visible = v ~= nil and v.step > v.total and not doneDismissed
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
		local size = workspace.CurrentCamera.ViewportSize
		local x = math.clamp(screen.X, ARROW_SIZE / 2, math.max(ARROW_SIZE / 2, size.X - ARROW_SIZE / 2))
		local y = math.clamp(screen.Y - radius - 2, ARROW_SIZE + CARD_TOP, math.max(ARROW_SIZE + CARD_TOP, size.Y))
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

	-- the map arrow: on the whole screen like the map, above the map and under every panel
	pointerGui = Widgets.screen("TutorialPointer", -5)
	pointerGui.ScreenInsets = Enum.ScreenInsets.None
	pointer = Instance.new("TextLabel")
	pointer.Name = "Pointer"
	pointer.AnchorPoint = Vector2.new(0.5, 1)
	pointer.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
	pointer.BackgroundTransparency = 1
	pointer.Font = Enum.Font.GothamBold
	pointer.TextSize = 36
	pointer.Text = "👇"
	pointer.TextColor3 = GLOW
	pointer.Visible = false
	pointer.Parent = pointerGui
	ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = pointerGui
	Widgets.corner(ring, 999)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = GLOW
	ringStroke.Thickness = 3
	ringStroke.Parent = ring
	pointerGui.Parent = playerGui

	cardGui = Widgets.screen("Tutorial", 5)
	card = Widgets.panel(cardGui, CARD_WIDTH)
	card.Name = "Card"
	card.Position = UDim2.fromOffset(8, CARD_TOP)
	card.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = GLOW
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	-- "2/6  ⚔ Recruit soldiers" across the top; the hint under it, with Skip on its right
	titleLabel = Widgets.label(card, "", 15, 22)
	titleLabel.Name = "Title"
	hintLabel = Widgets.label(card, "", 15, 40)
	hintLabel.Name = "Hint"
	hintLabel.TextColor3 = GLOW
	hintLabel.Position = UDim2.fromOffset(0, HINT_TOP)
	hintLabel.Size = UDim2.new(1, -SKIP_WIDTH - 6, 0, 40)
	-- two taps to skip, so a stray tap doesn't throw the tutorial away
	skipButton = Widgets.button(card, "⏭ Skip", SKIP_WIDTH, Widgets.BUTTON_OFF, function()
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
	skipButton.TextSize = 14
	skipButton.AnchorPoint = Vector2.new(1, 0)
	skipButton.Position = UDim2.new(1, 0, 0, HINT_TOP)

	-- the end: a card in the middle of the screen
	doneCard = Widgets.panel(cardGui, 340)
	doneCard.Name = "Done"
	doneCard.AnchorPoint = Vector2.new(0.5, 0.5)
	doneCard.Position = UDim2.fromScale(0.5, 0.5)
	doneCard.Visible = false
	Widgets.list(doneCard, false, 8)
	Widgets.label(doneCard, "🎉 Tutorial done!", 22, 30).LayoutOrder = 1
	Widgets.label(doneCard, "Now go rule the world!", 16, 26).LayoutOrder = 2
	doneButtons = Instance.new("Frame")
	doneButtons.Name = "Buttons"
	doneButtons.BackgroundTransparency = 1
	doneButtons.Size = UDim2.new(1, 0, 0, Widgets.BUTTON_HEIGHT)
	doneButtons.LayoutOrder = 3
	doneButtons.Parent = doneCard
	Widgets.list(doneButtons, true, 8)

	-- the arrow over a glowing button
	buttonArrow = pointer:Clone()
	buttonArrow.Name = "ButtonArrow"
	buttonArrow.Parent = cardGui
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
