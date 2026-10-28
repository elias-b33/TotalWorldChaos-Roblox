--!strict
-- The top bar (docs/UI_DIRECTION.md 7.9): floating plates in Roblox's own top-bar row, no band. Your nation (a
-- slate gem with your flag: tap to re-centre on your capital), gold and manpower counters with their icons riding
-- over them, the clock in a medallion ringed in the phase's colour, your rank and level, and gem buttons for the
-- nations drawer, the shop and the sound. A scrim behind keeps them readable over snow and sea. On a narrow screen
-- the least important items step aside (fitBar); on a wide one the groups spread out. Also the toasts for what
-- happens in the world, under the bar.

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
local Cosmetics = require(Client.Cosmetics)
local LobbyState = require(Client.LobbyState)
local ProfileState = require(Client.ProfileState)
local Relations = require(Client.Relations)
local Sounds = require(Client.Sounds)
local HudLayout = require(script.Parent.HudLayout)
local Icons = require(script.Parent.Icons)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme
local ITEM = HudLayout.ITEM -- a gem button's height; every plate centres on its face line
local FACE = 17 -- a gem button's face centre, from its top
local GAP = Theme.space.m -- between items in a group
local GROUP_GAP = Theme.space.l -- between groups
local MAX_SPREAD = 24 -- on a wide screen, at most this much more between two groups
local NATION_MAX = 140 -- the nation button at most
local NATION_FLAG = 48 -- the nation button with its flag only (a small phone)
local FLAG_SIZE = Vector2.new(24, 18)
local RANK_WIDTH = 64 -- "#10": a trophy and two digits
local LEVEL_WIDTH = 50 -- a medal and two digits
local COUNTER_OVERHANG = 10 -- a counter's icon rides this far over its left end
local CLOCK_OVERHANG = 18 -- the clock's medallion, over the clock's left end
local SCRIM_FADE = 20 -- the scrim reaches this far under the bar
local TOAST_SECONDS = 2.5
local TOAST_WIDTH = 340 -- clear of the tutorial card at the top left
local LEFT_PANELS = 264 -- the nations drawer (8 + 256 px) and the tutorial card stay left of the toasts

local Hud = {}

type Item = {
	obj: GuiObject,
	group: number, -- items of a group sit GAP apart; groups GROUP_GAP apart (and more on wide screens)
	width: number, -- the room it takes, overhangs included
	offset: number, -- where the object starts in that room
	height: number, -- the object's height: it centres on the face line (a gem button sits on it)
	right: boolean?, -- in the right-hand group
}

local gui: ScreenGui
local scrim: Frame
local bar: Frame
local barScale: UIScale
local capital: TextButton
local nationLabel: TextLabel
local nationIcon: GuiObject
local flag: GuiObject? = nil
local flagKey = ""
local goldLabel: TextLabel
local manpowerLabel: TextLabel
local clockLabel: TextLabel
local clockMedallion: ImageLabel
local clockIcon: GuiObject
local rankLabel: TextLabel
local levelLabel: TextLabel
local items: { Item } = {}
local nationWidth = NATION_MAX
local toastLabel: TextLabel
local toastUntil = 0
local toastQueue: { string } = {}
local MAX_QUEUED_TOASTS = 4

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

-- The phase medallion's ring: green in Peace, red at War, purple in the Cataclysm, gold on Results.
local PHASE_STYLES: { [string]: string } = {
	Peace = "peace",
	War = "war",
	Cataclysm = "cataclysm",
	Results = "gold",
}

-- Where Hud.contentTop() starts and the bar's own row: see HudLayout.
function Hud.contentTop(): number
	return HudLayout.contentTop()
end

-- The nation button's width for a name: the flag, the name in Fredoka One 18 (about 10 px a letter), the padding.
local function nationButtonWidth(name: string): number
	local w = 42 + (utf8.len(name) or #name) * 10 + 8
	return math.min(NATION_MAX, w + w % 2)
end

-- Lay the bar out (docs/UI_DIRECTION.md 7.9): the groups from the left, the buttons at the right end; on a narrow
-- screen the level, then the rank, then the nation's name step aside; on a wide one the groups spread out.
local function place()
	local row = HudLayout.row()
	local k = row.scale
	local width = (row.x1 - row.x0) / k
	bar.Position = UDim2.fromOffset(row.x0, row.top)
	bar.Size = UDim2.fromOffset(width, ITEM)
	barScale.Scale = k
	scrim.Size = UDim2.new(1, 0, 0, math.max(row.rowBottom, row.top + ITEM * k) + SCRIM_FADE)

	-- what fits: drop the optional items in order until the rest does
	local alive = goldLabel.Visible
	local showLevel, showRank, showName = true, alive, true
	local function needed(): number
		local total, lastGroup, rightWidth = 0, nil :: number?, 0
		for _, item in items do
			local shown = item.obj.Visible
			if item.obj == levelLabel then
				shown = showLevel
			elseif item.obj == rankLabel then
				shown = showRank
			end
			if shown then
				local w = if item.obj == capital then (if showName then nationWidth else NATION_FLAG) else item.width
				if item.right then
					rightWidth += w + (if rightWidth > 0 then GAP else 0)
				else
					total += w + (if lastGroup == nil then 0 elseif lastGroup == item.group then GAP else GROUP_GAP)
					lastGroup = item.group
				end
			end
		end
		return total + GROUP_GAP + rightWidth
	end
	if needed() > width then
		showLevel = false
	end
	if needed() > width then
		showRank = false
	end
	if needed() > width then
		showName = false
	end
	levelLabel.Visible = showLevel
	rankLabel.Visible = showRank and alive
	nationLabel.Visible = showName
	local capitalWidth = if showName then nationWidth else NATION_FLAG
	capital.Size = UDim2.fromOffset(capitalWidth, ITEM)

	-- the spare width spreads the left groups apart, a little
	local groups = 0
	local lastGroup: number? = nil
	for _, item in items do
		if item.obj.Visible and not item.right then
			if lastGroup ~= nil and lastGroup ~= item.group then
				groups += 1
			end
			lastGroup = item.group
		end
	end
	local spare = math.max(0, width - needed())
	local spread = if groups > 0 then math.min(MAX_SPREAD, spare // (groups + 1)) else 0

	local x = 0
	lastGroup = nil
	local rightX = width
	for i = #items, 1, -1 do -- the right-hand group, from the right end
		local item = items[i]
		if item.right and item.obj.Visible then
			rightX -= item.width
			item.obj.Position = UDim2.fromOffset(rightX + item.offset, 0)
			rightX -= GAP
		end
	end
	for _, item in items do
		if item.obj.Visible and not item.right then
			if lastGroup ~= nil then
				x += if lastGroup == item.group then GAP else GROUP_GAP + spread
			end
			lastGroup = item.group
			local w = if item.obj == capital then capitalWidth else item.width
			-- gem buttons sit on the row's top; everything else centres on their face line
			local top = if item.height >= ITEM then 0 else FACE - item.height / 2
			item.obj.Position = UDim2.fromOffset(x + item.offset, top)
			x += w
		end
	end
	if toastLabel then
		local toastTop = (HudLayout.barBottom() + HudLayout.GAP * Widgets.uiScale()) / Widgets.uiScale()
		Widgets.fit(toastLabel, nil, UDim2.new(0.5, LEFT_PANELS // 2, 0, toastTop))
	end
end

-- Your flag on the nation button, rebuilt only when it changes.
local function setFlag(nation: Types.NationState?)
	local key = if nation then Cosmetics.of(nation.id).flag .. ":" .. nation.colorIndex else ""
	if key == flagKey then
		return
	end
	flagKey = key
	if flag then
		flag:Destroy()
		flag = nil
	end
	if nation then
		local f = Cosmetics.flagLabel(
			capital,
			Cosmetics.of(nation.id).flag,
			nation.colorIndex,
			UDim2.fromOffset(FLAG_SIZE.X, FLAG_SIZE.Y)
		)
		f.AnchorPoint = Vector2.new(0, 0.5)
		f.Position = UDim2.new(0, 10, 0.5, 0)
		f.ZIndex = 3
		flag = f
	end
end

local function refresh()
	-- the bar is the match's: the lobby and the draft have screens of their own
	local inMatch = LobbyState.phase() == "None" and ClientState.snapshot() ~= nil
	bar.Visible = inMatch
	scrim.Visible = inMatch
	local me = ClientState.nation(ClientState.myNation())
	local alive = me ~= nil and not me.eliminated
	goldLabel.Visible = alive
	manpowerLabel.Visible = alive
	rankLabel.Visible = alive
	nationIcon.Visible = not alive
	if me and me.eliminated then
		nationLabel.Text = "Primordial"
		Icons.set(nationIcon, "sparkles")
		setFlag(nil)
	elseif me then
		goldLabel.Text = formatNumber(me.gold)
		goldLabel.TextColor3 = if me.gold < 0 then Theme.color.negative else Theme.color.text
		manpowerLabel.Text = formatNumber(me.manpower)
		nationLabel.Text = me.name
		rankLabel.Text = "#" .. Relations.rank(me.id)
		setFlag(me)
	else
		nationLabel.Text = "Spectating"
		Icons.set(nationIcon, "eye")
		setFlag(nil)
	end
	nationWidth = nationButtonWidth(nationLabel.Text)
	place()
end

local function updateClock()
	local tick = ClientState.tick()
	local snap = ClientState.snapshot()
	local setup = if snap then snap.setup else nil -- a private server's match length and Peace
	local phase = if snap and snap.result then "Results" else Match.phaseAt(tick, setup)
	local remaining = if phase == "Results" then 0 else Settings.timing(setup).matchEnd - tick
	clockLabel.Text = formatClock(remaining)
	if clockLabel:GetAttribute("Phase") ~= phase then
		clockLabel:SetAttribute("Phase", phase)
		Icons.set(clockIcon, PHASE_ICONS[phase] or "clock")
		Widgets.setMedallion(clockMedallion, PHASE_STYLES[phase] or "slate")
	end
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
	end
	return nil
end

-- A slate gem icon button in the bar. `name` is what the harness presses.
local function barButton(name: string, icon: string, onPress: () -> ()): TextButton
	local button = Widgets.iconButton(bar, icon, name, ITEM, Theme.color.slate, onPress)
	Widgets.shadow(button, "button")
	return button
end

local function add(obj: GuiObject, group: number, width: number, offset: number, height: number, right: boolean?)
	table.insert(items, { obj = obj, group = group, width = width, offset = offset, height = height, right = right })
end

function Hud.init(onCapitalButton: () -> (), onNationsButton: () -> (), onShopButton: (() -> ())?)
	gui = Instance.new("ScreenGui")
	gui.Name = "Hud"
	gui.ResetOnSpawn = false
	-- the bar sits in Roblox's own top-bar row: this screen's coordinates are the screen's
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- an ink shade fading down from the top: plates stay readable over snow and sea (it is not a bar)
	scrim = Instance.new("Frame")
	scrim.Name = "Scrim"
	scrim.BackgroundColor3 = Theme.color.ink
	scrim.BorderSizePixel = 0
	scrim.ZIndex = 0
	scrim.Parent = gui
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0.4, 1)
	fade.Parent = scrim

	bar = Instance.new("Frame")
	bar.Name = "TopBar"
	bar.Active = true -- swallow taps on the row so they don't reach the map
	bar.BackgroundTransparency = 1
	bar.Parent = gui
	barScale = Instance.new("UIScale")
	barScale.Name = "DeviceScale"
	barScale.Parent = bar

	-- your nation: tap to re-centre on your capital (stands in for double-tapping it)
	capital = Widgets.button(bar, "", NATION_MAX, Theme.color.slate, onCapitalButton)
	capital.Name = "Capital"
	Widgets.shadow(capital, "button")
	nationLabel = Widgets.label(capital, "", Theme.text.heading, 30)
	nationLabel.Name = "Nation"
	nationLabel.FontFace = Theme.font.display
	nationLabel.AnchorPoint = Vector2.new(0, 0.5)
	nationLabel.Position = UDim2.new(0, 42, 0.5, 0)
	nationLabel.Size = UDim2.new(1, -44, 0, 30)
	nationLabel.TextWrapped = false
	nationLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nationLabel.ZIndex = 3
	Widgets.textStroke(nationLabel)
	nationIcon = Widgets.icon(capital, "eye", Theme.size.icon)
	nationIcon.AnchorPoint = Vector2.new(0, 0.5)
	nationIcon.Position = UDim2.new(0, 14, 0.5, 0)
	nationIcon.ZIndex = 3
	nationIcon.Visible = false
	add(capital, 1, NATION_MAX, 0, ITEM)

	goldLabel = Widgets.counter(bar, "gold", "", 80)
	goldLabel.Name = "Gold"
	add(goldLabel, 2, COUNTER_OVERHANG + 80, COUNTER_OVERHANG, Theme.size.counter)
	manpowerLabel = Widgets.counter(bar, "manpower", "", 86)
	manpowerLabel.Name = "Manpower"
	add(manpowerLabel, 2, COUNTER_OVERHANG + 86, COUNTER_OVERHANG, Theme.size.counter)

	-- the clock: the phase in a medallion ringed in its colour, over the left end of the time's counter
	clockLabel = Widgets.counter(bar, nil, "", 80)
	clockLabel.Name = "Clock"
	clockMedallion, clockIcon = Widgets.medallion(clockLabel, "normal", "peace", "peace")
	clockMedallion.AnchorPoint = Vector2.new(0, 0.5)
	clockMedallion.Position = UDim2.new(0, -(CLOCK_OVERHANG + 26), 0.5, 0)
	clockLabel:SetAttribute("Phase", "Peace")
	local clockPad = clockLabel:FindFirstChildOfClass("UIPadding") :: UIPadding
	clockPad.PaddingLeft = UDim.new(0, 26) -- "24:56" just clear of the medallion
	clockPad.PaddingRight = UDim.new(0, Theme.space.xs)
	add(clockLabel, 3, CLOCK_OVERHANG + 80, CLOCK_OVERHANG, Theme.size.counter)

	rankLabel = Widgets.chip(bar, "trophy", "", RANK_WIDTH, Theme.size.counter)
	rankLabel.Name = "Rank"
	rankLabel.TextTruncate = Enum.TextTruncate.None -- "#10" fits
	local rankLabelPad = rankLabel:FindFirstChildOfClass("UIPadding") :: UIPadding
	rankLabelPad.PaddingRight = UDim.new(0, Theme.space.xs)
	Widgets.shadow(rankLabel, "counter")
	add(rankLabel, 4, RANK_WIDTH, 0, Theme.size.counter)

	-- your account level (MONETIZATION.md 5.2), from the saved profile
	levelLabel = Widgets.chip(bar, "medal", "", LEVEL_WIDTH, Theme.size.counter)
	levelLabel.Name = "Level"
	levelLabel.TextTruncate = Enum.TextTruncate.None
	local levelLabelPad = levelLabel:FindFirstChildOfClass("UIPadding") :: UIPadding
	levelLabelPad.PaddingRight = UDim.new(0, Theme.space.xs)
	Widgets.shadow(levelLabel, "counter")
	add(levelLabel, 4, LEVEL_WIDTH, 0, Theme.size.counter)
	ProfileState.onChange(function()
		local summary = ProfileState.summary()
		levelLabel.Text = if summary then tostring(summary.level) else ""
	end)

	add(barButton("NationsButton", "globe", onNationsButton), 5, ITEM, 0, ITEM, true)
	-- the shop (MONETIZATION.md 3): cosmetics only, Robux purchases open after the match
	if onShopButton then
		add(barButton("ShopButton", "cart", onShopButton), 5, ITEM, 0, ITEM, true)
	end
	-- sound on and off for the session (docs/DESIGN.md "Sound and effects")
	local mute = barButton("Mute", "soundOn", function() end)
	add(mute, 5, ITEM, 0, ITEM, true)
	local muteIcon = mute:FindFirstChild("Icon") :: GuiObject
	Sounds.attachMuteButton(mute, function(muted: boolean)
		Icons.set(muteIcon, if muted then "soundOff" else "soundOn")
		mute:SetAttribute("Muted", muted)
	end)

	toastLabel = Widgets.toast(gui, 0, TOAST_WIDTH)
	place()
	HudLayout.onChange(place)
	Widgets.onScale(place) -- the toast's line is in the UI's scale, which may change after the row does

	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui.Parent = playerGui
	-- the device's safe area (clear of a notch), for the fallback row: an empty screen that keeps to it
	local safe = Instance.new("ScreenGui")
	safe.Name = "SafeArea"
	safe.IgnoreGuiInset = true
	safe.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	safe.Parent = playerGui
	local function measureSafe()
		local ok, left, width = pcall(function()
			return safe.AbsolutePosition.X, safe.AbsoluteSize.X
		end)
		if ok and typeof(left) == "number" and typeof(width) == "number" and width > 0 then
			HudLayout.setSafeArea(left, left + width)
		end
	end
	safe:GetPropertyChangedSignal("AbsoluteSize"):Connect(measureSafe)
	safe:GetPropertyChangedSignal("AbsolutePosition"):Connect(measureSafe)
	measureSafe()

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
	LobbyState.onChange(refresh)
	Cosmetics.onChange(refresh)
	Remotes.event("Notify").OnClientEvent:Connect(function(_kind: string, text: string)
		Hud.toast(text)
	end)
	RunService.Heartbeat:Connect(updateClock)
	refresh()
end

return Hud
