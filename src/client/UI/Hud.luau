--!strict
-- Top bar (your nation, gold, manpower, rank, phase and timer) and toasts for what happens in the world.
-- Icons and numbers, no paragraphs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Match = require(Shared.Sim.Match)
local Settings = require(Shared.Sim.Settings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Palette = require(Client.Palette)
local ProfileState = require(Client.ProfileState)
local Relations = require(Client.Relations)
local Sounds = require(Client.Sounds)

local BAR_HEIGHT = 44
local BAR_PADDING = 12 -- left and right
local BAR_GAP = 10 -- between items
local TOAST_SECONDS = 2.5

local Hud = {}

local gui: ScreenGui
local goldLabel: TextLabel
local manpowerLabel: TextLabel
local clockLabel: TextLabel
local rankLabel: TextLabel
local nationLabel: TextLabel
local nationSwatch: Frame
local levelLabel: TextLabel
local toastLabel: TextLabel
local toastUntil = 0
local toastQueue: { string } = {}
local MAX_QUEUED_TOASTS = 4

local function label(parent: Instance, text: string, width: number, align: Enum.TextXAlignment?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(0, width, 1, 0)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 18
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.Text = text
	l.Parent = parent
	return l
end

local function barButton(parent: Instance, name: string, text: string, order: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(BAR_HEIGHT, BAR_HEIGHT)
	button.BackgroundTransparency = 1
	button.Font = Enum.Font.GothamBold
	button.TextSize = 22
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.LayoutOrder = order
	button.Parent = parent
	return button
end

-- On narrow screens (small or notched phones) the least important items step aside, in this order, so the bar
-- never runs off the screen.
local function fitBar(bar: Frame, optional: { GuiObject })
	local available = bar.AbsoluteSize.X - 2 * BAR_PADDING
	if available <= 0 then
		return -- not laid out yet
	end
	local function needed(): number
		local total, count = 0, 0
		for _, child in bar:GetChildren() do
			if child:IsA("GuiObject") and child.Visible then
				total += child.Size.X.Offset
				count += 1
			end
		end
		return total + math.max(count - 1, 0) * BAR_GAP
	end
	for _, item in optional do
		item.Visible = true
	end
	for _, item in optional do
		if needed() <= available then
			break
		end
		item.Visible = false
	end
end

local function formatNumber(n: number): string
	if math.abs(n) >= 10000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(math.floor(n))
end

local function formatClock(seconds: number): string
	seconds = math.max(0, seconds)
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local PHASE_ICONS: { [string]: string } = {
	Peace = "🕊",
	War = "⚔",
	Cataclysm = "☄",
	Results = "🏁",
}

local function refresh()
	local me = ClientState.nation(ClientState.myNation())
	if me and me.eliminated then
		goldLabel.Text = ""
		manpowerLabel.Text = ""
		nationLabel.Text = "✨ Primordial"
		nationSwatch.Visible = false
		rankLabel.Text = ""
	elseif me then
		goldLabel.Text = "💰 " .. formatNumber(me.gold)
		goldLabel.TextColor3 = if me.gold < 0 then Color3.fromRGB(255, 120, 120) else Color3.new(1, 1, 1)
		manpowerLabel.Text = "👥 " .. formatNumber(me.manpower)
		nationLabel.Text = me.name
		nationSwatch.BackgroundColor3 = Palette.nation(me.colorIndex)
		nationSwatch.Visible = true
		rankLabel.Text = "🏆 #" .. Relations.rank(me.id)
	else
		goldLabel.Text = ""
		manpowerLabel.Text = ""
		nationLabel.Text = "👀 Spectating"
		nationSwatch.Visible = false
		rankLabel.Text = ""
	end
end

local function updateClock()
	local tick = ClientState.tick()
	local snap = ClientState.snapshot()
	local setup = if snap then snap.setup else nil -- a private server's match length and Peace
	local phase = if snap and snap.result then "Results" else Match.phaseAt(tick, setup)
	local remaining = if phase == "Results" then 0 else Settings.timing(setup).matchEnd - tick
	clockLabel.Text = (PHASE_ICONS[phase] or "") .. " " .. formatClock(remaining)
	if os.clock() > toastUntil then
		local nextText = table.remove(toastQueue, 1)
		if nextText then
			toastLabel.Text = nextText
			toastLabel.Visible = true
			toastUntil = os.clock() + TOAST_SECONDS
		elseif toastLabel.Visible then
			toastLabel.Visible = false
		end
	end
end

-- Queue a toast; they show one after another.
function Hud.toast(text: string)
	if #toastQueue < MAX_QUEUED_TOASTS then
		table.insert(toastQueue, text)
	end
end

local function nationName(id: number): string
	local n = ClientState.nation(id)
	return if n then n.name else "Rebels"
end

local function provinceName(id: number): string
	local map = ClientState.map()
	return if map and map.provinces[id] then map.provinces[id].name else "?"
end

-- The toast for a world event, from this player's point of view (nil = not worth interrupting for).
-- Without a nation (spectating, or between seats) myNation is 0, the same id events use for neutral land,
-- garrisons and Rebels: nil then, so nothing neutral reads as "you".
local function eventText(e: Types.MatchEvent): string?
	local mine = ClientState.myNation()
	local me = if mine ~= 0 then mine else nil
	if e.kind == "WarDeclared" then
		if e.b == me then
			return "⚔ " .. nationName(e.a) .. " declared war on you!"
		elseif e.a == me then
			return "⚔ You declared war on " .. nationName(e.b)
		end
		return "⚔ " .. nationName(e.a) .. " declared war on " .. nationName(e.b)
	elseif e.kind == "PeaceMade" then
		if e.a == me or e.b == me then
			return "🕊 Peace with " .. nationName(if e.a == me then e.b else e.a)
		end
		return "🕊 " .. nationName(e.a) .. " and " .. nationName(e.b) .. " made peace"
	elseif e.kind == "AllianceFormed" then
		return "🤝 " .. nationName(e.a) .. " and " .. nationName(e.b) .. " are allies"
	elseif e.kind == "ProvinceTaken" then
		if e.a == me then
			return "🏴 You took " .. provinceName(e.province)
		elseif e.b == me then
			return "🏳 " .. nationName(e.a) .. " took " .. provinceName(e.province) .. "!"
		end
	elseif e.kind == "BattleEnded" then
		if e.a == me then
			return "🎉 Battle won at " .. provinceName(e.province)
		elseif e.b == me then
			return "💀 Battle lost at " .. provinceName(e.province)
		end
	elseif e.kind == "Offer" and e.b == me then
		return "📜 " .. nationName(e.a) .. " sent you an offer"
	end
	return nil
end

function Hud.init(onCapitalButton: () -> (), onNationsButton: () -> (), onShopButton: (() -> ())?)
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local bar = Instance.new("Frame")
	bar.Name = "TopBar"
	bar.Active = true -- swallow taps so they don't reach the map
	bar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	bar.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	bar.BackgroundTransparency = 0.08 -- nearly solid: map names behind it would read as clutter
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, BAR_PADDING)
	padding.PaddingRight = UDim.new(0, BAR_PADDING)
	padding.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, BAR_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	-- capital button: recentres the camera on your capital (stands in for double-tapping it)
	barButton(bar, "Capital", "⭐", 1).Activated:Connect(onCapitalButton)

	nationSwatch = Instance.new("Frame")
	nationSwatch.Size = UDim2.fromOffset(14, 14)
	nationSwatch.BorderSizePixel = 0
	nationSwatch.LayoutOrder = 2
	nationSwatch.Parent = bar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = nationSwatch

	nationLabel = label(bar, "", 110)
	nationLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nationLabel.LayoutOrder = 3
	goldLabel = label(bar, "", 80)
	goldLabel.LayoutOrder = 4
	manpowerLabel = label(bar, "", 88)
	manpowerLabel.LayoutOrder = 5
	rankLabel = label(bar, "", 56)
	rankLabel.LayoutOrder = 6
	clockLabel = label(bar, "", 84)
	clockLabel.LayoutOrder = 7

	barButton(bar, "NationsButton", "🌍", 8).Activated:Connect(onNationsButton)

	-- your account level (MONETIZATION.md 5.2), from the saved profile
	levelLabel = label(bar, "", 52)
	levelLabel.Name = "Level"
	levelLabel.LayoutOrder = 9
	ProfileState.onChange(function()
		local summary = ProfileState.summary()
		levelLabel.Text = if summary then "🎖 " .. summary.level else ""
	end)

	-- the shop (MONETIZATION.md 3): cosmetics only, Robux purchases open after the match
	if onShopButton then
		barButton(bar, "ShopButton", "🛒", 10).Activated:Connect(onShopButton)
	end

	-- sound on and off for the session (docs/DESIGN.md "Sound and effects")
	Sounds.attachMuteButton(barButton(bar, "Mute", "🔊", 11))

	local optional: { GuiObject } = { levelLabel, rankLabel, nationSwatch }
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fitBar(bar, optional)
	end)
	fitBar(bar, optional)

	toastLabel = Instance.new("TextLabel")
	toastLabel.Name = "Toast"
	toastLabel.AnchorPoint = Vector2.new(0.5, 0)
	toastLabel.Position = UDim2.new(0.5, 0, 0, BAR_HEIGHT + 10)
	toastLabel.Size = UDim2.fromOffset(340, 40)
	toastLabel.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	toastLabel.BackgroundTransparency = 0.15
	toastLabel.Font = Enum.Font.GothamBold
	toastLabel.TextSize = 16
	toastLabel.TextColor3 = Color3.new(1, 1, 1)
	toastLabel.Visible = false
	toastLabel.Parent = gui
	local toastCorner = Instance.new("UICorner")
	toastCorner.CornerRadius = UDim.new(0, 10)
	toastCorner.Parent = toastLabel

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onReset(refresh)
	ClientState.onDelta(function(delta)
		if #delta.nations > 0 or #delta.provinces > 0 then
			refresh()
		end
		for _, e in delta.events do
			local text = eventText(e)
			if text then
				Hud.toast(text)
			end
		end
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(_kind: string, text: string)
		Hud.toast(text)
	end)
	RunService.Heartbeat:Connect(updateClock)
end

return Hud
