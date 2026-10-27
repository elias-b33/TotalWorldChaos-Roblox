--!strict
-- Top bar (your nation, gold, manpower, rank, phase and timer) and toasts for what happens in the world.
-- Icons and numbers, no paragraphs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Match = require(Shared.Sim.Match)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Palette = require(Client.Palette)
local Relations = require(Client.Relations)

local BAR_HEIGHT = 44
local TOAST_SECONDS = 2.5

local Hud = {}

local gui: ScreenGui
local goldLabel: TextLabel
local manpowerLabel: TextLabel
local clockLabel: TextLabel
local rankLabel: TextLabel
local nationLabel: TextLabel
local nationSwatch: Frame
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
	if me then
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
	local phase = if snap and snap.result then "Results" else Match.phaseAt(tick)
	local remaining = if phase == "Results" then 0 else Config.Phases.MatchEndTick - tick
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
local function eventText(e: Types.MatchEvent): string?
	local me = ClientState.myNation()
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

function Hud.init(onCapitalButton: () -> (), onNationsButton: () -> ())
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local bar = Instance.new("Frame")
	bar.Name = "TopBar"
	bar.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	bar.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	bar.BackgroundTransparency = 0.25
	bar.BorderSizePixel = 0
	bar.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bar

	-- capital button: recentres the camera on your capital (stands in for double-tapping it)
	local home = Instance.new("TextButton")
	home.Name = "Capital"
	home.Size = UDim2.fromOffset(BAR_HEIGHT, BAR_HEIGHT)
	home.BackgroundTransparency = 1
	home.Font = Enum.Font.GothamBold
	home.TextSize = 22
	home.Text = "⭐"
	home.TextColor3 = Color3.new(1, 1, 1)
	home.LayoutOrder = 1
	home.Parent = bar
	home.Activated:Connect(onCapitalButton)

	nationSwatch = Instance.new("Frame")
	nationSwatch.Size = UDim2.fromOffset(14, 14)
	nationSwatch.BorderSizePixel = 0
	nationSwatch.LayoutOrder = 2
	nationSwatch.Parent = bar
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = nationSwatch

	nationLabel = label(bar, "", 130)
	nationLabel.LayoutOrder = 3
	goldLabel = label(bar, "", 90)
	goldLabel.LayoutOrder = 4
	manpowerLabel = label(bar, "", 100)
	manpowerLabel.LayoutOrder = 5
	rankLabel = label(bar, "", 64)
	rankLabel.LayoutOrder = 6
	clockLabel = label(bar, "", 90)
	clockLabel.LayoutOrder = 7

	local nationsButton = Instance.new("TextButton")
	nationsButton.Name = "NationsButton"
	nationsButton.Size = UDim2.fromOffset(BAR_HEIGHT, BAR_HEIGHT)
	nationsButton.BackgroundTransparency = 1
	nationsButton.Font = Enum.Font.GothamBold
	nationsButton.TextSize = 22
	nationsButton.Text = "🌍"
	nationsButton.TextColor3 = Color3.new(1, 1, 1)
	nationsButton.LayoutOrder = 8
	nationsButton.Parent = bar
	nationsButton.Activated:Connect(onNationsButton)

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
