--!strict
-- Map pings (docs/NEXT_FEATURES.md 4, docs/DESIGN.md "UI and controls"): icons for your allies, never words.
--
-- The wheel: a long press on a province (MapView.onLongPress), or the ping button on its sheet, opens four gem
-- buttons round the spot: Attack (crossed swords, crimson), Defend (shield, azure), Help (fire, gold), Look (eye,
-- slate), with an "Allies only" plate over them. Tap one to ping (Intents.ping); tap anywhere else to close it.
--
-- The markers: the server sends a ping only to the sender's alliance (PingService). Each shows for its lifetime on the
-- map's pooled "Markers" layer (MapMarkers): the ping's icon in a medallion on a stem, the sender's flag beside it
-- and two pulse rings in the sender's colour. An ally's ping also brings a toast in the kit's style ("⚔ Niger:
-- Attack · Mesopotamia": the toast's icon is the ping's) and the Ping sound when it is in view or on your land.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local Client = script.Parent.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local Intents = require(Client.Intents)
local MapMarkers = require(Client.MapMarkers)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local Palette = require(Client.Palette)
local Relations = require(Client.Relations)
local Sounds = require(Client.Sounds)
local Widgets = require(script.Parent.Widgets)

local Theme = Widgets.Theme

local GEM = Theme.size.button -- the wheel's gem buttons: 44 px touch targets
local DISC = 176 -- the dark disc behind the wheel
local LABEL_HEIGHT = 18
local LABEL_WIDTH = 72
local MARGIN = Theme.space.m -- the wheel keeps this far inside the screen and under the top bar
local REACH_X = DISC / 2 -- how far the wheel reaches from its centre: sideways, up (with the plate) and down
local REACH_UP = DISC / 2 + 24
local REACH_DOWN = DISC / 2
local PLATE_TOP = -DISC / 2 - 16 -- the "Allies only" plate's centre over the wheel's centre
local SPOT = 14 -- the little ring on the spot the wheel pings
local PING_PHASES = { Peace = true, War = true, Cataclysm = true }

-- Each kind: its pixel icon, gem colour (and the medallion's style), the emoji that gives the toast its icon, and its
-- gem's centre in the wheel (screen px from the wheel's centre).
local LOOKS: { [string]: { icon: string, color: Color3, style: string, emoji: string, at: Vector2 } } = {
	Attack = { icon = "war", color = Theme.color.crimson, style = "crimson", emoji = "⚔", at = Vector2.new(0, -58) },
	Defend = {
		icon = "powerShield",
		color = Theme.color.azure,
		style = "azure",
		emoji = "🛡",
		at = Vector2.new(58, -6),
	},
	Help = { icon = "fire", color = Theme.color.gold, style = "gold", emoji = "🔥", at = Vector2.new(0, 46) },
	Look = { icon = "eye", color = Theme.color.slate, style = "slate", emoji = "👀", at = Vector2.new(-58, -6) },
}

local Pings = {}

type Shown = { by: number, kind: string, province: number, untilTick: number }

local gui: ScreenGui
local catcher: TextButton -- the whole screen under an open wheel: a tap on it closes the wheel
local wheel: Frame? = nil
local target: number? = nil -- the province the open wheel pings
local showToast: ((string) -> ())? = nil
local active: { [number]: Shown } = {} -- ping id -> what shows on the map
local shownCount = 0

local function closeWheel()
	target = nil
	if wheel then
		wheel:Destroy() -- a closed wheel keeps no GUI objects
		wheel = nil
	end
	catcher.Visible = false
end

local function send(kind: string)
	local province = target
	closeWheel()
	if province then
		Intents.ping(kind, province)
	end
end

local function openWheel(provinceId: number, at: Vector2)
	closeWheel()
	target = provinceId
	local screen = MapView.screenSize()
	local top = MapView.topBand()
	local k = Widgets.uiScale() -- tablets: the wheel grows with the rest of the UI (phones stay at 1)
	local left, right = MARGIN + REACH_X * k, screen.X - MARGIN - REACH_X * k
	local high, low = top + MARGIN + REACH_UP * k, screen.Y - MARGIN - REACH_DOWN * k
	local x = math.clamp(at.X, left, math.max(left, right))
	local y = math.clamp(at.Y, high, math.max(high, low))
	catcher.Visible = true

	local root = Instance.new("Frame")
	root.Name = "PingWheel"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromOffset(x, y)
	root.Size = UDim2.fromOffset(DISC, DISC)
	root.BackgroundColor3 = Theme.color.slate950
	root.BackgroundTransparency = 0.35
	root.BorderSizePixel = 0
	root.ZIndex = 2
	root.Parent = gui
	Widgets.corner(root, DISC)
	Widgets.stroke(root)
	local scale = Instance.new("UIScale")
	scale.Scale = k
	scale.Parent = root
	wheel = root

	-- the spot being pinged
	local spot = Instance.new("Frame")
	spot.Name = "Spot"
	spot.AnchorPoint = Vector2.new(0.5, 0.5)
	spot.Position = UDim2.fromScale(0.5, 0.5)
	spot.Size = UDim2.fromOffset(SPOT, SPOT)
	spot.BackgroundTransparency = 1
	spot.Parent = root
	Widgets.corner(spot, SPOT)
	local ring = Widgets.stroke(spot, Theme.color.text, Theme.stroke)
	ring.Name = "Ring"

	for i, kind in Config.Pings.Kinds do
		local look = LOOKS[kind]
		local b = Widgets.iconButton(root, look.icon, "Ping_" .. kind, GEM, look.color, function()
			send(kind)
		end)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, look.at.X, 0.5, look.at.Y)
		b.LayoutOrder = i
		Widgets.shadow(b, "plate")
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, look.at.X, 0.5, look.at.Y + GEM / 2)
		label.Size = UDim2.fromOffset(LABEL_WIDTH, LABEL_HEIGHT)
		label.BackgroundTransparency = 1
		label.FontFace = Theme.font.display
		label.TextSize = Theme.text.body
		label.TextColor3 = Theme.color.text
		label.Text = kind
		label.Parent = root
		Widgets.textStroke(label)
	end

	-- who sees it: your allies, nobody else
	local plate = Widgets.chip(root, "handshake", "Allies only")
	plate.Name = "AlliesOnly"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.new(0.5, 0, 0.5, PLATE_TOP)
end

local function living(): number?
	local me = ClientState.myNation()
	local nation = if me ~= 0 then ClientState.nation(me) else nil
	return if nation and not nation.eliminated then me else nil
end

-- Does your nation have a living ally (someone to ping for)?
function Pings.hasAllies(): boolean
	local me = living()
	local snap = ClientState.snapshot()
	if me == nil or snap == nil then
		return false
	end
	for _, nation in snap.nations do
		if nation.id ~= me and not nation.eliminated and Relations.allied(me, nation.id) then
			return true
		end
	end
	return false
end

-- Open the wheel for a province at a screen point (map-screen coordinates, as MapView hands them out). What the
-- server would refuse is said at once instead: a mountain, a phase without orders, no allies. Spectators and
-- Primordials have nothing to ping with: nothing happens.
function Pings.open(provinceId: number, at: Vector2)
	local snap = ClientState.snapshot()
	local map = ClientState.map()
	if living() == nil or snap == nil or map == nil or map.provinces[provinceId] == nil then
		return
	end
	local say = showToast
	local reason = if snap.result or not PING_PHASES[snap.phase]
		then "WrongPhase"
		elseif map.provinces[provinceId].terrain == "Mountain" then "BadTarget"
		elseif not Pings.hasAllies() then "NoAllies"
		else nil
	if reason then
		if say then
			say(Intents.text(reason))
		end
		return
	end
	openWheel(provinceId, at)
end

-- The province sheet's ping button: centre the map on the province and open the wheel over it.
function Pings.openFor(provinceId: number)
	local screen = MapView.screenSize()
	local top = MapView.topBand()
	MapView.centreOn(MapRenderer.centerOf(provinceId))
	Pings.open(provinceId, Vector2.new(screen.X / 2, top + (screen.Y - top) / 2))
end

function Pings.isOpen(): boolean
	return wheel ~= nil
end

local function hide(id: number)
	if active[id] then
		active[id] = nil
		shownCount -= 1
		MapMarkers.hide("Ping" .. id)
	end
end

local function clearAll()
	for id in active do
		MapMarkers.hide("Ping" .. id)
	end
	active = {}
	shownCount = 0
end

local function nationName(id: number): string
	local nation = ClientState.nation(id)
	return if nation then nation.name else "?"
end

local function provinceName(id: number): string
	local map = ClientState.map()
	local def = if map then map.provinces[id] else nil
	return if def then def.name else "?"
end

-- Ping(id, by, kind, province, untilTick) from PingService: one of your alliance's pings (or your own).
local function onPing(id: unknown, by: unknown, kind: unknown, province: unknown, untilTick: unknown)
	if type(id) ~= "number" or type(by) ~= "number" or type(province) ~= "number" or type(untilTick) ~= "number" then
		return
	end
	local look = if type(kind) == "string" then LOOKS[kind] else nil
	local map = ClientState.map()
	if look == nil or map == nil or map.provinces[province] == nil then
		return
	end
	if active[id] == nil then
		shownCount += 1
	end
	active[id] = { by = by, kind = kind :: string, province = province, untilTick = untilTick }
	local sender = ClientState.nation(by)
	local evicted = MapMarkers.show("Ping" .. id, MapRenderer.centerOf(province), {
		icon = look.icon,
		style = look.style,
		ring = if sender then Palette.nation(sender.colorIndex) else Theme.color.text,
		flagId = Cosmetics.of(by).flag,
		colorIndex = if sender then sender.colorIndex else nil,
	})
	local evictedId = if evicted then tonumber(string.sub(evicted, 5)) else nil
	if evictedId and active[evictedId] then
		active[evictedId] = nil -- the oldest marker gave way
		shownCount -= 1
	end
	if by == ClientState.myNation() then
		return -- your own ping: the marker is the answer
	end
	local say = showToast
	if say then
		say(string.format("%s %s: %s · %s", look.emoji, nationName(by), kind :: string, provinceName(province)))
	end
	local record = ClientState.province(province)
	local mine = record ~= nil and record.owner ~= 0 and record.owner == ClientState.myNation()
	if mine or MapView.onScreen(MapRenderer.centerOf(province), 0) then
		Sounds.play("Ping")
	end
end

function Pings.init(toast: (string) -> ())
	showToast = toast
	gui = Widgets.screen("Pings", 6) -- over the sheets, the drawer and the power picker; under Results (10)
	gui.ScreenInsets = Enum.ScreenInsets.None -- the map's coordinates: the wheel opens under the finger
	catcher = Instance.new("TextButton")
	catcher.Name = "PingCancel"
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Visible = false
	catcher.Parent = gui
	catcher.Activated:Connect(closeWheel)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	Remotes.event("Ping").OnClientEvent:Connect(onPing)
	Remotes.event("PingGone").OnClientEvent:Connect(function(id: unknown)
		if type(id) == "number" then
			hide(id)
		end
	end)
	ClientState.onReset(function()
		closeWheel()
		clearAll()
	end)
	-- a ping fades at its untilTick (the match clock, counted on between deltas); the wheel closes when orders stop
	RunService.Heartbeat:Connect(function()
		if shownCount == 0 and wheel == nil then
			return
		end
		local now = ClientState.tick()
		for id, p in active do
			if now > p.untilTick then
				hide(id)
			end
		end
		local snap = ClientState.snapshot()
		if wheel and (snap == nil or snap.result ~= nil or living() == nil) then
			closeWheel()
		end
	end)
end

return Pings
