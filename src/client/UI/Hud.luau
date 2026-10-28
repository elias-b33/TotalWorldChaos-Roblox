--!strict
-- Top bar (your nation, gold, manpower, rank, phase and timer) and toasts for what happens in the world.
-- Icons and numbers, no paragraphs: each value is a chip with a pixel icon (Widgets.chip).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local InsultLines = require(Shared.Flavour.Insults)
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
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local BAR_HEIGHT = Theme.size.bar
local BAR_PADDING = 12 -- left and right
local BAR_GAP = 8 -- between items
local BAR_BUTTON = 40 -- icon buttons in the bar (the bar's full height is the touch target)
local TOAST_SECONDS = 2.5
local TOAST_WIDTH = 340 -- clear of the tutorial card at the top left
local LEFT_PANELS = 264 -- the nations drawer (8 + 256 px) and the tutorial card (8 + 236 px) stay left of the toasts

local Hud = {}

local gui: ScreenGui
local goldLabel: TextLabel
local manpowerLabel: TextLabel
local clockLabel: TextLabel
local clockIcon: GuiObject
local rankLabel: TextLabel
local nationLabel: TextLabel
local nationSwatch: Frame
local nationIcon: GuiObject
local levelLabel: TextLabel
local toastLabel: TextLabel
local toastUntil = 0
local toastQueue: { string } = {}
local MAX_QUEUED_TOASTS = 4

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
	Peace = "peace",
	War = "war",
	Cataclysm = "meteor",
	Results = "flag",
}

local function refresh()
	local me = ClientState.nation(ClientState.myNation())
	local alive = me ~= nil and not me.eliminated
	goldLabel.Visible = alive
	manpowerLabel.Visible = alive
	rankLabel.Visible = alive
	nationSwatch.Visible = alive
	nationIcon.Visible = not alive
	if me and me.eliminated then
		nationLabel.Text = "Primordial"
		Icons.set(nationIcon, "sparkles")
	elseif me then
		goldLabel.Text = formatNumber(me.gold)
		goldLabel.TextColor3 = if me.gold < 0 then Theme.color.warn else Theme.color.text
		manpowerLabel.Text = formatNumber(me.manpower)
		nationLabel.Text = me.name
		nationSwatch.BackgroundColor3 = Palette.nation(me.colorIndex)
		rankLabel.Text = "#" .. Relations.rank(me.id)
	else
		nationLabel.Text = "Spectating"
		Icons.set(nationIcon, "eye")
	end
end

local function updateClock()
	local tick = ClientState.tick()
	local snap = ClientState.snapshot()
	local setup = if snap then snap.setup else nil -- a private server's match length and Peace
	local phase = if snap and snap.result then "Results" else Match.phaseAt(tick, setup)
	local remaining = if phase == "Results" then 0 else Settings.timing(setup).matchEnd - tick
	clockLabel.Text = formatClock(remaining)
	clockLabel:SetAttribute("Phase", phase)
	Icons.set(clockIcon, PHASE_ICONS[phase] or "clock")
	if os.clock() > toastUntil then
		local nextText = table.remove(toastQueue, 1)
		if nextText then
			Widgets.setToast(toastLabel, nextText)
			toastLabel.Visible = true
			toastUntil = os.clock() + TOAST_SECONDS
		elseif toastLabel.Visible then
			toastLabel.Visible = false
		end
	end
end

-- Queue a toast; they show one after another. A leading emoji becomes the toast's pixel icon.
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
			return "🚩 You took " .. provinceName(e.province)
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
	elseif e.kind == "Insult" or e.kind == "InsultBack" or e.kind == "LaughedOff" then
		-- the EU4 pack: an insult carries no message (Roblox's preset-text rule, docs/DESIGN.md "Diplomacy"). The one it
		-- was aimed at gets a neutral system line; the one who did it gets a game-written flavour line that only their
		-- own client ever shows (Shared.Flavour.Insults). Everyone else sees the map's marker only.
		if e.b == me then
			if e.kind == "Insult" then
				return "💢 " .. nationName(e.a) .. " insulted you!"
			elseif e.kind == "InsultBack" then
				return "💢 " .. nationName(e.a) .. " insulted you back!"
			end
			return "😀 " .. nationName(e.a) .. " laughed off your insult"
		elseif e.a == me then
			local snap = ClientState.snapshot()
			local kind: InsultLines.Kind = if e.kind == "LaughedOff" then "laugh" else "insult"
			local turn = ClientState.tick() + e.b
			return "😀 " .. InsultLines.flavour(if snap then snap.mapId else "", kind, nationName(e.b), turn)
		end
	elseif e.kind == "Gift" and e.b == me then
		return string.format("🎁 %s sent you %d gold", nationName(e.a), Config.Diplomacy.GiftGold)
	elseif e.kind == "AccessGranted" then
		local minutes = Config.Diplomacy.AccessTicks * Config.TickSeconds // 60
		if e.b == me then
			return string.format("🚶 %s lets your armies through for %d min", nationName(e.a), minutes)
		elseif e.a == me then
			return string.format("🚶 %s's armies may cross your land for %d min", nationName(e.b), minutes)
		end
	end
	return nil
end

-- A plain icon button in the bar. `name` is what the harness presses.
local function barButton(parent: Instance, name: string, icon: string, order: number, onPress: () -> ()): TextButton
	local button = Widgets.iconButton(parent, icon, name, BAR_BUTTON, nil, onPress)
	button.LayoutOrder = order
	return button
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
	bar.BackgroundColor3 = Theme.color.navy
	bar.BackgroundTransparency = 0 -- solid: map names behind it would read as clutter
	bar.BorderSizePixel = 0
	bar.Parent = gui
	Widgets.stroke(bar)
	Widgets.bevel(bar, true)
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
	barButton(bar, "Capital", "castle", 1, onCapitalButton)

	-- your nation: its colour (a Primordial or a spectator gets an icon instead) and its name
	nationSwatch = Instance.new("Frame")
	nationSwatch.Name = "Swatch"
	nationSwatch.Size = UDim2.fromOffset(16, 16)
	nationSwatch.BorderSizePixel = 0
	nationSwatch.LayoutOrder = 2
	nationSwatch.Parent = bar
	Widgets.corner(nationSwatch, Theme.radius.s)
	Widgets.stroke(nationSwatch)
	nationIcon = Widgets.icon(bar, "eye", Theme.size.icon)
	nationIcon.LayoutOrder = 2
	nationIcon.Visible = false

	nationLabel = Widgets.label(bar, "", Theme.text.heading, BAR_HEIGHT)
	nationLabel.Name = "Nation"
	nationLabel.FontFace = Theme.font.display
	nationLabel.Size = UDim2.fromOffset(110, BAR_HEIGHT)
	nationLabel.TextWrapped = false
	nationLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nationLabel.LayoutOrder = 3

	goldLabel = Widgets.chip(bar, "gold", "", 80)
	goldLabel.Name = "Gold"
	goldLabel.LayoutOrder = 4
	manpowerLabel = Widgets.chip(bar, "manpower", "", 84)
	manpowerLabel.Name = "Manpower"
	manpowerLabel.LayoutOrder = 5
	rankLabel = Widgets.chip(bar, "trophy", "", 62)
	rankLabel.Name = "Rank"
	rankLabel.LayoutOrder = 6
	clockLabel = Widgets.chip(bar, "peace", "", 86)
	clockLabel.Name = "Clock"
	clockLabel.LayoutOrder = 7
	clockIcon = clockLabel:FindFirstChild("Icon") :: GuiObject

	barButton(bar, "NationsButton", "globe", 8, onNationsButton)

	-- your account level (MONETIZATION.md 5.2), from the saved profile
	levelLabel = Widgets.chip(bar, "medal", "", 52)
	levelLabel.Name = "Level"
	levelLabel.LayoutOrder = 9
	ProfileState.onChange(function()
		local summary = ProfileState.summary()
		levelLabel.Text = if summary then tostring(summary.level) else ""
	end)

	-- the shop (MONETIZATION.md 3): cosmetics only, Robux purchases open after the match
	if onShopButton then
		barButton(bar, "ShopButton", "cart", 10, onShopButton)
	end

	-- sound on and off for the session (docs/DESIGN.md "Sound and effects")
	local mute = barButton(bar, "Mute", "soundOn", 11, function() end)
	local muteIcon = mute:FindFirstChild("Icon") :: GuiObject
	Sounds.attachMuteButton(mute, function(muted: boolean)
		Icons.set(muteIcon, if muted then "soundOff" else "soundOn")
		mute:SetAttribute("Muted", muted)
	end)

	local optional: { GuiObject } = { levelLabel, rankLabel, nationSwatch }
	bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		fitBar(bar, optional)
	end)
	fitBar(bar, optional)

	toastLabel = Widgets.toast(gui, BAR_HEIGHT + 10, TOAST_WIDTH)
	-- centred in the room right of the top-left panels, so a toast never covers them, even on a 667 px phone
	toastLabel.Position = UDim2.new(0.5, LEFT_PANELS // 2, 0, BAR_HEIGHT + 10)

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
