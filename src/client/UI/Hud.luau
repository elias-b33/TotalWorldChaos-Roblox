--!strict
-- Top bar (gold, manpower, phase and timer, your nation) and toasts. Icons and numbers, no paragraphs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Match = require(Shared.Sim.Match)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Palette = require(Client.Palette)

local BAR_HEIGHT = 44
local TOAST_SECONDS = 2.5

local Hud = {}

local gui: ScreenGui
local goldLabel: TextLabel
local manpowerLabel: TextLabel
local clockLabel: TextLabel
local nationLabel: TextLabel
local nationSwatch: Frame
local toastLabel: TextLabel
local toastUntil = 0

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
	else
		goldLabel.Text = ""
		manpowerLabel.Text = ""
		nationLabel.Text = "👀 Spectating"
		nationSwatch.Visible = false
	end
end

local function updateClock()
	local tick = ClientState.tick()
	local phase = Match.phaseAt(tick)
	local remaining = Config.Phases.MatchEndTick - tick
	clockLabel.Text = (PHASE_ICONS[phase] or "") .. " " .. formatClock(remaining)
	if toastLabel.Visible and os.clock() > toastUntil then
		toastLabel.Visible = false
	end
end

function Hud.toast(text: string)
	toastLabel.Text = text
	toastLabel.Visible = true
	toastUntil = os.clock() + TOAST_SECONDS
end

function Hud.init(onCapitalButton: () -> ())
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
	clockLabel = label(bar, "", 90)
	clockLabel.LayoutOrder = 6

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
		if #delta.nations > 0 then
			refresh()
		end
	end)
	Remotes.event("Notify").OnClientEvent:Connect(function(_kind: string, text: string)
		Hud.toast(text)
	end)
	RunService.Heartbeat:Connect(updateClock)
end

return Hud
