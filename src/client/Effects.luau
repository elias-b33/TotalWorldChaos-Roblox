--!strict
-- Map "juice" in the WorldBox pixel style (docs/DESIGN.md "UI and controls", "Sound and effects"): dust puffs and
-- crossed swords where a battle starts, a burst when it ends (bigger, with a skull, if an army was destroyed), a
-- ring in the new owner's colour when a province changes hands, spray and crossed swords where a sea battle starts and
-- a burst at its zone's centre when it ends (with a skull if a fleet sank), an effect for each Primordial power, and
-- a flash and a banner when the phase changes (a ribbon in the phase's colour with a pixel icon, hero text and a
-- shine). Sounds for the same moments come from Sounds.
--
-- Power-effect cosmetics: a power is drawn in its caster's equipped look (Cosmetics.powerEffect, PowerFx.LOOKS).
-- A look only picks colours and particle shapes; the area (PowerFx.AREA), the timing (POWER_SECONDS) and the
-- sound cue are the power's, the same for every look.
--
-- Client-only and cosmetic: it only reads ClientState (deltas, events, the snapshot). Particles are square frames on
-- the map canvas's "Effects" layer, sized in whole map pixels (at least MIN_PIXEL on screen) and moved with
-- TweenService. Cheap on phones: frames are pooled (at most MAX_PARTICLES), only a few effects run at once, and
-- effects off screen, or over provinces too small to see at this zoom, are skipped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Primordial = require(Shared.Sim.Primordial)
local Snapshot = require(Shared.Snapshot)

local Client = script.Parent
local ClientState = require(Client.ClientState)
local Cosmetics = require(Client.Cosmetics)
local MapRenderer = require(Client.MapRenderer)
local MapView = require(Client.MapView)
local Music = require(Client.Music)
local Palette = require(Client.Palette)
local PowerFx = require(Client.PowerFx)
local Sounds = require(Client.Sounds)
local Icons = require(Client.UI.Icons)
local Widgets = require(Client.UI.Widgets)

local Theme = Widgets.Theme

local MAX_PARTICLES = 240 -- pooled frames, all effects together (the map's GUI budget is 2,000 objects)
local MAX_MINOR = 8 -- other nations' battles and captures running at once
local MAX_MAJOR = 14 -- powers and your own fights may go past MAX_MINOR up to this
local MAX_PLAGUE_PROVINCES = 8 -- a Plague pulses over at most this many of the nation's provinces on screen
local MAX_SHIELDS = 6 -- shield domes drawn at once
local MIN_PIXEL = 4 -- a particle's smallest size on screen, in screen pixels
local MIN_PROVINCE_SCREEN = 16 -- minor effects skip provinces narrower than this on screen (screen pixels)
local SCREEN_MARGIN = 60 -- effects this close to the screen's edge (screen pixels) still play
local SYNC_SECONDS = 0.5 -- how often shield domes are checked
local FADE = 0.35 -- seconds a sprite takes to fade out
local METEOR_FALL = 0.7 -- seconds from the sky to the ground
local BANNER_SECONDS = 1.7 -- the pop (0.28 s) and a 1.4 s hold
local BANNER_TOP = 128 -- War and Cataclysm: the ribbon's top, under the toasts' line
local BANNER_POP = 0.6 -- the banner pops in from this scale
local BANNER_OVERSHOOT = 1.08 -- past its size, then back
local BANNER_FADE = 0.3 -- seconds it takes to fade out

local fx = Palette.fx

-- Pixel sprites: one character per particle, "." is empty.
local SWORDS = { "S.....S", ".S...S.", "..S.S..", "...S...", "..S.S..", ".H...H.", "H.....H" }
local SWORD_COLORS: { [string]: Color3 } = { S = fx.steel, H = fx.hilt }
local SKULL = { ".BBB.", "BKBKB", "BBBBB", ".BBB.", ".B.B." }
local SKULL_COLORS: { [string]: Color3 } = { B = fx.bone, K = fx.ink }
local FLAG = { "PFFF", "PFFF", "P...", "P...", "P..." }
local FLAG_COLORS: { [string]: Color3 } = { P = fx.pole, F = fx.ink }
local CRATER = { ".CCC.", "CDDDC", "CDDDC", ".CCC." }

-- Phase banners: a pixel icon and a few words on a ribbon in the phase's colour (its enamel style, and the flat
-- look's fill), and the flash colour. `duck`: the music dips under it so its sound lands (Results has its own sting
-- instead).
type Phase = {
	text: string,
	icon: string,
	style: string,
	plate: Color3,
	color: Color3,
	sound: Sounds.SoundName,
	duck: boolean?,
}
local PHASES: { [string]: Phase } = {
	War = {
		text = "WAR!",
		icon = "war",
		style = "war",
		plate = Theme.color.war,
		color = fx.fireRed,
		sound = "War",
		duck = true,
	},
	Cataclysm = {
		text = "CATACLYSM!",
		icon = "meteor",
		style = "cataclysm",
		plate = Theme.color.cataclysm,
		color = fx.fireOrange,
		sound = "Cataclysm",
		duck = true,
	},
	Results = {
		text = "MATCH OVER",
		icon = "flag",
		style = "gold",
		plate = Theme.color.gold,
		color = fx.gold,
		sound = "Results",
	},
}

local Effects = {}

type Particle = { frame: Frame, serial: number, tweens: { Tween } }
type Dome = { frame: Frame, dots: { { p: Particle, serial: number } }, unit: number }

local layer: Frame? = nil
local size = Vector2.new(1024, 512)
local generation = 0 -- bumps with every new map: effects still running for an old one stop
local free: { Particle } = {}
local pooled: { Particle } = {} -- every particle on the current canvas, so a new map can stop their tweens
local created = 0
local active = 0
local domes: { [number]: Dome } = {}
local battles: { [number]: boolean } = {}
local armyAt: { [number]: number } = {}
local fleetAt: { [number]: number } = {} -- each fleet's sea zone
local seaFights: { [number]: boolean } = {} -- zones with a sea battle going on
local phase = ""
local lastShown = ""
local lastProvince = 0
type Shown = { kind: string, province: number, at: number, look: string } -- look: a power's look ("" = default)
local history: { Shown } = {} -- the last few effects shown
local seed = 20240611

local flash: Frame
local banner: TextLabel
local bannerIcon: GuiObject
local bannerScale: UIScale
local bannerSerial = 0

-- Helpers ------------------------------------------------------------------------------------------------

-- A small seeded generator, so effects look the same every time (and in the harness).
local function rand(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function between(a: number, b: number): number
	return a + (b - a) * rand()
end

local function at(p: Vector2): UDim2
	return UDim2.fromScale(math.floor(p.X + 0.5) / size.X, math.floor(p.Y + 0.5) / size.Y)
end

local function square(n: number): UDim2
	return UDim2.fromScale(n / size.X, n / size.Y)
end

-- One particle's size in map pixels: 1 when zoomed in, bigger when zoomed out so it stays visible.
local function unit(): number
	return math.max(1, math.ceil(MIN_PIXEL / MapView.zoom()))
end

local function nationColor(nationId: number): Color3
	local nation = ClientState.nation(nationId)
	return if nation then Palette.nation(nation.colorIndex) else Palette.garrison
end

local function acquire(color: Color3): Particle?
	local parent = layer
	if parent == nil then
		return nil
	end
	local p = table.remove(free)
	if p == nil then
		if created >= MAX_PARTICLES then
			return nil
		end
		created += 1
		local frame = Instance.new("Frame")
		frame.Name = "Fx"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.ZIndex = 2
		frame.Parent = parent
		p = { frame = frame, serial = 0, tweens = {} }
		table.insert(pooled, p :: Particle)
	end
	local particle = p :: Particle
	particle.serial += 1
	particle.frame.BackgroundColor3 = color
	particle.frame.BackgroundTransparency = 0
	particle.frame.Visible = true
	return particle
end

-- Back to the pool, unless it was already released and reused (serial) or its map is gone.
local function release(p: Particle, serial: number)
	if p.serial ~= serial or p.frame.Parent == nil then
		return
	end
	for _, t in p.tweens do
		t:Cancel()
	end
	table.clear(p.tweens)
	p.serial += 1
	p.frame.Visible = false
	table.insert(free, p)
end

local function tween(
	p: Particle,
	seconds: number,
	style: Enum.EasingStyle,
	goals: { [string]: any },
	after: number?,
	forever: boolean?
)
	local info =
		TweenInfo.new(seconds, style, Enum.EasingDirection.Out, if forever then -1 else 0, forever == true, after or 0)
	local t = TweenService:Create(p.frame, info, goals)
	table.insert(p.tweens, t)
	t:Play()
end

-- One square particle from a to b (map pixels), size s0 -> s1 map pixels, fading out over `seconds`.
local function spark(color: Color3, a: Vector2, b: Vector2, s0: number, s1: number, seconds: number, startFade: number?)
	local p = acquire(color)
	if p == nil then
		return
	end
	local serial = p.serial
	p.frame.Position = at(a)
	p.frame.Size = square(s0)
	p.frame.BackgroundTransparency = startFade or 0
	tween(p, seconds, Enum.EasingStyle.Quad, { Position = at(b), Size = square(s1) })
	tween(p, seconds * 0.6, Enum.EasingStyle.Linear, { BackgroundTransparency = 1 }, seconds * 0.4) -- solid, then fades
	task.delay(seconds, release, p, serial)
end

-- `count` particles flying out from c to between r0 and r1 map pixels, drifting up by `rise`.
local function burst(
	c: Vector2,
	colors: { Color3 },
	count: number,
	r0: number,
	r1: number,
	s: number,
	seconds: number,
	rise: number?
)
	for i = 1, count do
		local angle = (i / count + between(-0.06, 0.06)) * 2 * math.pi
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		local to = c + dir * between(r0, r1) - Vector2.new(0, rise or 0)
		spark(colors[(i - 1) % #colors + 1], c + dir * r0 * 0.3, to, s, math.max(1, s / 2), seconds * between(0.8, 1.1))
	end
end

-- A ring of particles growing from radius r0 to r1 together.
local function ring(c: Vector2, color: Color3, count: number, r0: number, r1: number, s: number, seconds: number)
	for i = 1, count do
		local angle = i / count * 2 * math.pi
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		spark(color, c + dir * r0, c + dir * r1, s, s, seconds)
	end
end

-- A flash: one square growing from the centre and fading.
local function pop(c: Vector2, color: Color3, maxSize: number, seconds: number)
	spark(color, c, c, maxSize * 0.2, maxSize, seconds, 0.15)
end

-- A pixel sprite that pops in around c (or standing on c when `bottom`), holds, then fades.
local function sprite(
	c: Vector2,
	rows: { string },
	colors: { [string]: Color3 },
	u: number,
	hold: number,
	bottom: boolean?
)
	local h, w = #rows, #rows[1]
	local ox, oy = (w + 1) / 2, if bottom then h + 0.5 else (h + 1) / 2
	local grow = 0.25
	for row = 1, h do
		for col = 1, w do
			local color = colors[string.sub(rows[row], col, col)]
			local p = if color then acquire(color) else nil
			if p then
				local offset = Vector2.new(col - ox, row - oy) * u
				local serial = p.serial
				p.frame.Position = at(c + offset * 0.2)
				p.frame.Size = square(u * 0.2)
				tween(p, grow, Enum.EasingStyle.Back, { Position = at(c + offset), Size = square(u) })
				tween(p, FADE, Enum.EasingStyle.Linear, { BackgroundTransparency = 1 }, grow + hold)
				task.delay(grow + hold + FADE, release, p, serial)
			end
		end
	end
end

-- Room for one more effect? Minor ones stop at MAX_MINOR, major ones at MAX_MAJOR.
local function begin(major: boolean, seconds: number, kind: string, provinceId: number, look: string?): boolean
	if active >= (if major then MAX_MAJOR else MAX_MINOR) then
		return false
	end
	active += 1
	lastShown, lastProvince = kind, provinceId
	table.insert(history, { kind = kind, province = provinceId, at = os.clock(), look = look or "" })
	if #history > 32 then
		table.remove(history, 1)
	end
	local g = generation
	task.delay(seconds, function()
		if g == generation then
			active -= 1
		end
	end)
	return true
end

-- Worth drawing: on screen, and (for minor effects) the province is big enough at this zoom.
local function visible(provinceId: number, minor: boolean): boolean
	if layer == nil or provinceId == 0 or ClientState.map() == nil then
		return false
	end
	if not MapView.onScreen(MapRenderer.centerOf(provinceId), SCREEN_MARGIN) then
		return false
	end
	return not minor or MapRenderer.provinceWidth(provinceId) * MapView.zoom() >= MIN_PROVINCE_SCREEN
end

local function involvesMe(provinceId: number): boolean
	local me = ClientState.myNation()
	local record = ClientState.province(provinceId)
	if me == 0 or record == nil then
		return false
	end
	if record.owner == me then
		return true
	end
	local snapshot = ClientState.snapshot()
	if snapshot then
		for _, a in snapshot.armies do
			if a.location == provinceId and a.owner == me then
				return true
			end
		end
	end
	return false
end

-- Battles and captures ------------------------------------------------------------------------------------

local function battleStarted(provinceId: number)
	local mine = involvesMe(provinceId)
	if visible(provinceId, not mine) and begin(mine, 1.2, "BattleStart", provinceId) then
		local c, u = MapRenderer.centerOf(provinceId), unit()
		burst(c, { fx.dust, fx.dustGrey }, 10, 3 * u, 7 * u, 2 * u, 0.7, 2 * u)
		sprite(c - Vector2.new(0, 7 * u), SWORDS, SWORD_COLORS, u, 0.6)
		Sounds.play("BattleStart")
	elseif mine then
		Sounds.play("BattleStart")
	end
end

local function battleEnded(provinceId: number, winner: number, loser: number, destroyed: boolean)
	local me = ClientState.myNation()
	local mine = me ~= 0 and (winner == me or loser == me)
	local sound: Sounds.SoundName = if destroyed then "ArmyDestroyed" else "BattleEnd"
	if
		visible(provinceId, not mine)
		and begin(mine, 1.4, if destroyed then "ArmyDestroyed" else "BattleEnd", provinceId)
	then
		local c, u = MapRenderer.centerOf(provinceId), unit()
		local colors = { nationColor(winner), fx.white, fx.dust }
		if destroyed then
			pop(c, fx.white, 16 * u, 0.4)
			burst(c, colors, 22, 2 * u, 13 * u, 2 * u, 0.9, 2 * u)
			sprite(c - Vector2.new(0, 7 * u), SKULL, SKULL_COLORS, u, 0.8)
		else
			burst(c, colors, 12, 2 * u, 8 * u, 2 * u, 0.6, u)
		end
		Sounds.play(sound)
	elseif mine then
		Sounds.play(sound)
	end
end

-- Sea battles (docs/DESIGN.md "Navies"): at the zone's centre, where its fleets stand.

local function seaVisible(zoneId: number): boolean
	return layer ~= nil and MapView.onScreen(MapRenderer.zoneCenterOf(zoneId), SCREEN_MARGIN)
end

local function myFleetIn(zoneId: number): boolean
	local me = ClientState.myNation()
	local snapshot = ClientState.snapshot()
	if me ~= 0 and snapshot then
		for _, f in snapshot.fleets do
			if f.zone == zoneId and f.owner == me then
				return true
			end
		end
	end
	return false
end

local function seaBattleStarted(zoneId: number)
	local mine = myFleetIn(zoneId)
	if seaVisible(zoneId) and begin(mine, 1.2, "SeaBattleStart", 0) then
		local c, u = MapRenderer.zoneCenterOf(zoneId), unit()
		burst(c, { fx.white, fx.shield }, 10, 3 * u, 7 * u, 2 * u, 0.7, 2 * u)
		sprite(c - Vector2.new(0, 7 * u), SWORDS, SWORD_COLORS, u, 0.6)
		Sounds.play("BattleStart")
	elseif mine then
		Sounds.play("BattleStart")
	end
end

local function seaBattleEnded(zoneId: number, winner: number, loser: number, sunk: boolean)
	local me = ClientState.myNation()
	local mine = me ~= 0 and (winner == me or loser == me)
	local sound: Sounds.SoundName = if sunk then "ArmyDestroyed" else "BattleEnd"
	if seaVisible(zoneId) and begin(mine, 1.4, if sunk then "FleetSunk" else "SeaBattleEnd", 0) then
		local c, u = MapRenderer.zoneCenterOf(zoneId), unit()
		local colors = { nationColor(winner), fx.white, fx.shield }
		if sunk then
			pop(c, fx.white, 16 * u, 0.4)
			burst(c, colors, 22, 2 * u, 13 * u, 2 * u, 0.9, 2 * u)
			sprite(c - Vector2.new(0, 7 * u), SKULL, SKULL_COLORS, u, 0.8)
		else
			burst(c, colors, 12, 2 * u, 8 * u, 2 * u, 0.6, u)
		end
		Sounds.play(sound)
	elseif mine then
		Sounds.play(sound)
	end
end

local function captured(provinceId: number, newOwner: number, oldOwner: number)
	local me = ClientState.myNation()
	local mine = me ~= 0 and (newOwner == me or oldOwner == me)
	local sound: Sounds.SoundName = if me ~= 0 and oldOwner == me then "Lost" else "Capture"
	if visible(provinceId, not mine) and begin(mine, 1, "Capture", provinceId) then
		local c, u = MapRenderer.centerOf(provinceId), unit()
		-- a lighter tint of the new owner's colour, so the ring shows over land just washed in that colour
		local color = nationColor(newOwner):Lerp(fx.white, 0.35)
		pop(c, fx.white, 12 * u, 0.4)
		ring(c, color, 16, 2 * u, 13 * u, 2 * u, 0.8)
		ring(c, nationColor(newOwner), 10, u, 8 * u, 2 * u, 0.6)
		Sounds.play(sound)
	elseif mine then
		Sounds.play(sound)
	end
end

-- Primordial powers ------------------------------------------------------------------------------------------

local DEFAULT_LOOK = PowerFx.look("Meteor") :: PowerFx.Look
local colors3: { [number]: Color3 } = {}

-- A packed 0xRRGGBB colour (PowerFx) as a Color3, made once.
local function color3(c: number): Color3
	local made = colors3[c]
	if made == nil then
		made = Color3.fromRGB(bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 255), bit32.band(c, 255))
		colors3[c] = made
	end
	return made :: Color3
end

local function colorList(list: { number }): { Color3 }
	local out = {}
	for i, c in list do
		out[i] = color3(c)
	end
	return out
end

-- A bar-shaped particle (w × h map pixels) that pops in at p, holds, then fades: the pieces of a star.
local function bar(color: Color3, p: Vector2, w: number, h: number, hold: number)
	local particle = acquire(color)
	if particle == nil then
		return
	end
	local serial = particle.serial
	particle.frame.Position = at(p)
	particle.frame.Size = UDim2.fromScale(w / size.X, 0)
	tween(particle, 0.2, Enum.EasingStyle.Quad, { Size = UDim2.fromScale(w / size.X, h / size.Y) })
	tween(particle, FADE, Enum.EasingStyle.Linear, { BackgroundTransparency = 1 }, 0.2 + hold)
	task.delay(0.2 + hold + FADE, release, particle, serial)
end

-- A four-point star: a horizontal and a vertical bar.
local function star(color: Color3, p: Vector2, u: number, hold: number)
	bar(color, p, 3 * u, u, hold)
	bar(color, p, u, 3 * u, hold)
end

local function meteor(c: Vector2, u: number, look: PowerFx.Look)
	local g = generation
	local comet = look.style == "comet"
	local start = c + Vector2.new(22 * u, -36 * u)
	Sounds.play("MeteorFall")
	-- the rock and its bright centre (the comet adds a glowing plus around its head), falling together
	local parts = { { look.core, Vector2.zero, 4 }, { look.inner, Vector2.zero, 2 } }
	if comet then
		for _, d in { Vector2.new(2, 0), Vector2.new(-2, 0), Vector2.new(0, 2), Vector2.new(0, -2) } do
			table.insert(parts, { look.inner, d, 1 })
		end
	end
	local falling: { Particle } = {}
	for _, part in parts do
		local p = acquire(color3(part[1] :: number))
		if p then
			local offset = (part[2] :: Vector2) * u
			p.frame.Position = at(start + offset)
			p.frame.Size = square((part[3] :: number) * u)
			tween(p, METEOR_FALL, Enum.EasingStyle.Linear, { Position = at(c + offset) })
			table.insert(falling, p)
		end
	end
	local trail = colorList(look.particles)
	local t0 = os.clock()
	local step = 0
	while os.clock() - t0 < METEOR_FALL do
		step += 1
		local p = start:Lerp(c, (os.clock() - t0) / METEOR_FALL)
		local drift = Vector2.new(between(-1, 1) * u, -2 * u)
		if comet then
			-- a long glittering tail: sparks that hang in the air longer, and a twinkle beside each
			spark(trail[(step - 1) % #trail + 1], p, p + drift * 0.4, 2 * u, u, 0.8)
			spark(trail[1], p + Vector2.new(between(-2, 2), between(-2, 2)) * u, p, u, u, 0.6)
		else
			spark(trail[(step - 1) % #trail + 1], p, p + drift, 2 * u, u, 0.45)
		end
		task.wait(0.05)
		if g ~= generation then
			return
		end
	end
	for _, p in falling do
		release(p, p.serial)
	end
	-- impact: the flash, a ring, crater dust, a crater, and the screen shake from the spec
	MapView.shake(8, 0.5)
	Sounds.play("MeteorImpact")
	pop(c, color3(look.flash), 20 * u, 0.35)
	ring(c, color3(look.ring), 14, 2 * u, PowerFx.AREA.Meteor * u, 2 * u, 0.6)
	burst(c, colorList(look.debris), 18, 3 * u, 11 * u, 2 * u, 1, 3 * u)
	sprite(c, CRATER, { C = color3(look.rim), D = color3(look.pit) }, u, 2)
	if comet then
		-- a burst of stars over the crater
		for i = 1, 6 do
			local angle = i / 6 * 2 * math.pi
			star(trail[(i - 1) % 2 + 1], c + Vector2.new(math.cos(angle), math.sin(angle)) * 8 * u, u, 0.5)
		end
	end
end

-- Returns how many provinces it pulses over.
local function plague(nationId: number, look: PowerFx.Look): number
	local snapshot = ClientState.snapshot()
	if snapshot == nil then
		return 0
	end
	local shown = 0
	local colors = colorList(look.particles)
	local ringColor = color3(look.ring)
	for _, record in snapshot.provinces do
		if shown >= MAX_PLAGUE_PROVINCES then
			break
		end
		if record.owner == nationId and visible(record.id, false) then
			shown += 1
			local c, u = MapRenderer.centerOf(record.id), unit()
			for pulse = 0, 2 do
				task.delay(pulse * 0.6 + shown * 0.05, function()
					ring(c, ringColor, 10, u, PowerFx.AREA.Plague * u, 2 * u, 0.8)
					for i = 1, 4 do
						local from = c + Vector2.new(between(-5, 5), between(-3, 3)) * u
						spark(colors[(i - 1) % #colors + 1], from, from - Vector2.new(0, 6 * u), 2 * u, u, 0.9)
					end
				end)
			end
		end
	end
	return shown
end

local function rebels(c: Vector2, u: number)
	local spots = { Vector2.new(-6, 1), Vector2.new(5, -3), Vector2.new(-1, 5), Vector2.new(7, 5) }
	for i, offset in spots do
		task.delay((i - 1) * 0.15, function()
			local base = c + offset * u
			sprite(base, FLAG, FLAG_COLORS, u, 2.2, true)
			burst(base, { fx.dust, fx.dustGrey }, 5, u, 4 * u, u, 0.5, u)
		end)
	end
end

local function earthquake(c: Vector2, u: number)
	MapView.shake(4, 1)
	local turn = between(0, 2 * math.pi)
	for crack = 1, 4 do
		local angle = turn + crack * math.pi / 2 + between(-0.4, 0.4)
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		local side = Vector2.new(-dir.Y, dir.X)
		local p = c
		for k = 1, 7 do
			p = p + dir * 2 * u + side * math.floor(between(-1.5, 1.5) + 0.5) * u
			local spot = p
			task.delay(k * 0.05, function()
				local particle = acquire(fx.crack)
				if particle then
					local serial = particle.serial
					particle.frame.Position = at(spot)
					particle.frame.Size = square(u)
					tween(particle, 0.5, Enum.EasingStyle.Linear, { BackgroundTransparency = 1 }, 1.8)
					task.delay(2.3, release, particle, serial)
				end
				if k % 3 == 0 then
					spark(fx.dust, spot, spot - Vector2.new(0, 3 * u), 2 * u, u, 0.6)
				end
			end)
		end
	end
	burst(c, { fx.dust, fx.earth }, 10, 2 * u, 7 * u, 2 * u, 0.8, 2 * u)
end

-- A beam of light coming down into the province from `top`, `length` map pixels long.
local function beam(color: Color3, top: Vector2, u: number, length: number)
	local p = acquire(color)
	if p == nil then
		return
	end
	local serial = p.serial
	p.frame.AnchorPoint = Vector2.new(0.5, 0)
	p.frame.Position = at(top)
	p.frame.Size = UDim2.fromScale(2 * u / size.X, 0)
	p.frame.BackgroundTransparency = 0.25
	tween(p, 0.35, Enum.EasingStyle.Quad, { Size = UDim2.fromScale(2 * u / size.X, length / size.Y) })
	tween(p, 0.5, Enum.EasingStyle.Linear, { BackgroundTransparency = 1 }, 0.9)
	task.delay(1.4, function()
		if p.serial == serial then
			p.frame.AnchorPoint = Vector2.new(0.5, 0.5) -- back to the pool's usual anchor
		end
		release(p, serial)
	end)
end

local function blessing(c: Vector2, u: number, look: PowerFx.Look)
	local rays = look.style == "rays"
	ring(c, color3(look.ring), 12, 2 * u, PowerFx.AREA.Blessing * u, 2 * u, 0.9)
	local colors = colorList(look.particles)
	if rays then
		-- five beams of light, inside the blessing's ring
		for i, x in { -8, -4, 0, 4, 8 } do
			task.delay((i - 1) * 0.08, beam, color3(look.ray), c + Vector2.new(x * u, -10 * u), u, 14 * u)
		end
	end
	for i = 1, if rays then 12 else 20 do
		task.delay(i * 0.06, function()
			local color = colors[(i - 1) % #colors + 1]
			local spot = c + Vector2.new(between(-8, 8), between(-6, 6)) * u
			if rays then
				star(color, spot, u, 0.4) -- four-point stars instead of squares
				return
			end
			local p = acquire(color)
			if p == nil then
				return
			end
			local serial = p.serial
			p.frame.Position = at(spot)
			p.frame.Size = square(0)
			tween(p, 0.3, Enum.EasingStyle.Quad, { Size = square(2 * u), Position = at(spot - Vector2.new(0, u)) })
			task.delay(0.3, function()
				if p.serial == serial then
					tween(
						p,
						0.5,
						Enum.EasingStyle.Quad,
						{ Size = square(0), Position = at(spot - Vector2.new(0, 4 * u)) }
					)
				end
			end)
			task.delay(0.8, release, p, serial)
		end)
	end
end

local function shieldCast(c: Vector2, u: number)
	ring(c, fx.shield, 16, 12 * u, 3 * u, 2 * u, 0.5)
	pop(c, fx.shield, 12 * u, 0.5)
end

local POWER_SECONDS: { [string]: number } = {
	Meteor = METEOR_FALL + 2.5,
	Plague = 2.5,
	Rebels = 3.2,
	Earthquake = 2.5,
	Blessing = 2.2,
	Shield = 0.8,
}

local POWER_DRAW: { [string]: (Vector2, number, PowerFx.Look) -> () } = {
	Meteor = meteor,
	Rebels = rebels,
	Earthquake = earthquake,
	Blessing = blessing,
	Shield = shieldCast,
}

-- `by`: the caster's nation (0 for a Cataclysm disaster): its equipped look for this power, else the default.
local function power(name: string?, hit: number, provinceId: number, by: number)
	if name == nil then
		return
	end
	local mine = hit ~= 0 and hit == ClientState.myNation()
	local seconds = POWER_SECONDS[name] or 2
	local sound: Sounds.SoundName? = if name == "Meteor" then "MeteorImpact" else name :: any
	local art = if by ~= 0 then Cosmetics.art(Cosmetics.powerEffect(by, name)) else ""
	local look = PowerFx.look(name, art) or DEFAULT_LOOK -- powers without variants ignore it
	local lookName = if PowerFx.LOOKS[name] and PowerFx.LOOKS[name][art] then art else ""
	if name == "Plague" then
		-- over the whole nation, not one province
		local shown = if begin(true, seconds, name, provinceId, lookName) then plague(hit, look) else 0
		if shown > 0 or mine then
			Sounds.play("Plague")
		end
		return
	end
	local draw = POWER_DRAW[name]
	if draw and visible(provinceId, false) and begin(true, seconds, name, provinceId, lookName) then
		if name ~= "Meteor" and sound then
			Sounds.play(sound)
		end
		local c, u = MapRenderer.centerOf(provinceId), unit()
		task.spawn(draw, c, u, look)
	elseif mine and sound then
		Sounds.play(sound)
	end
end

-- Shield domes: a translucent blue dome and a twinkling pixel ring for as long as the shield lasts ------------------

local function removeDome(provinceId: number)
	local dome = domes[provinceId]
	if dome then
		dome.frame:Destroy()
		for _, d in dome.dots do
			release(d.p, d.serial)
		end
		domes[provinceId] = nil
	end
end

local function makeDome(provinceId: number): Dome?
	local parent = layer
	if parent == nil then
		return nil
	end
	local u = unit()
	local c = MapRenderer.centerOf(provinceId)
	local radius = math.max(8 * u, math.floor(MapRenderer.provinceWidth(provinceId) * 0.3))
	local frame = Instance.new("Frame")
	frame.Name = "Dome" .. provinceId
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = at(c)
	frame.Size = square(radius * 2)
	frame.BackgroundColor3 = fx.shield
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.ZIndex = 2
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	frame.Parent = parent
	local dome: Dome = { frame = frame, dots = {}, unit = u }
	local count = 14
	for i = 1, count do
		local angle = i / count * 2 * math.pi
		local p = acquire(if i % 2 == 0 then fx.shield else fx.white)
		if p then
			p.frame.Position = at(c + Vector2.new(math.cos(angle), math.sin(angle)) * radius)
			p.frame.Size = square(u * 2)
			tween(p, 0.6, Enum.EasingStyle.Sine, { BackgroundTransparency = 0.7 }, (i % 4) * 0.15, true)
			table.insert(dome.dots, { p = p, serial = p.serial })
		end
	end
	return dome
end

local function syncDomes()
	local snapshot = ClientState.snapshot()
	if snapshot == nil or layer == nil then
		return
	end
	local tick = ClientState.tick()
	local wanted: { [number]: boolean } = {}
	local count = 0
	for _, record in snapshot.provinces do
		if record.shieldUntil > tick and count < MAX_SHIELDS and visible(record.id, false) then
			wanted[record.id] = true
			count += 1
		end
	end
	for provinceId, dome in domes do
		if not wanted[provinceId] or dome.unit ~= unit() then
			removeDome(provinceId)
		end
	end
	for provinceId in wanted do
		if domes[provinceId] == nil then
			domes[provinceId] = makeDome(provinceId)
		end
	end
end

-- Phase flash and banner ------------------------------------------------------------------------------------

local function phaseChanged(name: string)
	local def = PHASES[name]
	if def == nil then
		return
	end
	lastShown, lastProvince = name, 0
	table.insert(history, { kind = name, province = 0, at = os.clock(), look = "" })
	Sounds.play(def.sound)
	if def.duck then
		Music.duck()
	end
	flash.BackgroundColor3 = def.color
	flash.BackgroundTransparency = 0.45
	flash.Visible = true
	TweenService:Create(flash, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	bannerSerial += 1
	local serial = bannerSerial
	-- War and Cataclysm pop under the toasts; MATCH OVER pops on the Results window's ribbon, as wide, and fades
	-- to show it ("YOU WIN!") underneath
	local results = name == "Results"
	local y = if results then Theme.results.ribbonY else BANNER_TOP + Widgets.RIBBON_HEIGHT // 2
	local bannerSize = UDim2.fromOffset(if results then Theme.results.ribbonWidth else 0, Widgets.RIBBON_HEIGHT)
	Widgets.fit(banner, bannerSize, UDim2.new(0.5, 0, 0, y))
	banner.Text = def.text
	Widgets.restyle(banner, def.style)
	banner.BackgroundColor3 = def.plate -- the flat look's fill
	Icons.set(bannerIcon, def.icon)
	Widgets.fade(banner, 0, 0)
	banner.Visible = true
	local k = Widgets.uiScale()
	if Widgets.reducedMotion() then
		bannerScale.Scale = k
	else
		-- pop: 0.6 -> 1.08 -> 1, then the shine sweeps across
		bannerScale.Scale = BANNER_POP * k
		local grow = TweenService:Create(
			bannerScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = BANNER_OVERSHOOT * k }
		)
		grow.Completed:Connect(function()
			if bannerSerial == serial then
				TweenService:Create(bannerScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad), { Scale = k }):Play()
			end
		end)
		grow:Play()
		Widgets.shine(banner, 0.28)
	end
	task.delay(BANNER_SECONDS, function()
		if bannerSerial == serial then
			Widgets.fade(banner, 1, BANNER_FADE)
		end
	end)
	task.delay(BANNER_SECONDS + BANNER_FADE + 0.05, function()
		if bannerSerial == serial then
			banner.Visible = false
			flash.Visible = false
		end
	end)
end

-- Wiring ---------------------------------------------------------------------------------------------------

local function remember(snapshot: Snapshot.SnapshotData)
	battles, armyAt, fleetAt, seaFights = {}, {}, {}, {}
	for _, record in snapshot.provinces do
		battles[record.id] = record.battle
	end
	for _, a in snapshot.armies do
		armyAt[a.id] = a.location
	end
	for _, f in snapshot.fleets do
		fleetAt[f.id] = f.zone
		if f.inBattle then
			seaFights[f.zone] = true
		end
	end
	phase = snapshot.phase
end

-- Draw on the current map's canvas. A new map means a new canvas: every pooled frame went with the old one.
local function bind()
	generation += 1
	for _, p in pooled do -- their frames went with the old canvas: stop tweening them
		for _, t in p.tweens do
			t:Cancel()
		end
	end
	free, pooled, created, active, domes = {}, {}, 0, 0, {}
	layer = MapRenderer.layer("Effects")
	size = MapRenderer.mapSize()
end

local function onReset(snapshot: Snapshot.SnapshotData)
	bind()
	remember(snapshot)
end

local function onDelta(delta: Snapshot.DeltaData)
	if layer ~= MapRenderer.layer("Effects") then
		bind()
	end
	-- armies gone this tick, by where they stood: a battle there destroyed an army (one that merged into another
	-- stack, a "Merged" event, or went aboard a fleet, "Embarked", wasn't destroyed); fleets gone, by their zone: a sea
	-- battle sank them (one that merged into another, "FleetMerged", didn't sink)
	local merged: { [number]: boolean } = {}
	local fleetMerged: { [number]: boolean } = {}
	for _, e in delta.events do
		if e.kind == "Merged" then
			merged[e.b] = true
		elseif e.kind == "Embarked" then
			merged[e.a] = true
		elseif e.kind == "FleetMerged" then
			fleetMerged[e.b] = true
		end
	end
	local sunkAt: { [number]: boolean } = {}
	for _, id in delta.removedFleets do
		local zone = fleetAt[id]
		if zone and not fleetMerged[id] then
			sunkAt[zone] = true
		end
		fleetAt[id] = nil
	end
	for _, f in delta.fleets do
		fleetAt[f.id] = f.zone
	end
	-- sea battles starting: zones where a fleet fights now and nobody fought before this delta
	local fightingNow: { [number]: boolean } = {}
	local snapshot = ClientState.snapshot()
	local fleets: { Snapshot.FleetRecord } = if snapshot then snapshot.fleets else {}
	for _, f in fleets do
		if f.inBattle then
			fightingNow[f.zone] = true
		end
	end
	for zone in fightingNow do
		if not seaFights[zone] then
			seaBattleStarted(zone)
		end
	end
	local destroyedAt: { [number]: boolean } = {}
	for _, id in delta.removedArmies do
		local where = armyAt[id]
		if where and not merged[id] then
			destroyedAt[where] = true
		end
		armyAt[id] = nil
	end
	local fighting: { [number]: boolean } = {} -- battles seen before this delta or starting in it
	for _, record in delta.provinces do
		fighting[record.id] = battles[record.id] or record.battle
		local was = battles[record.id]
		battles[record.id] = record.battle
		if record.battle and not was then
			battleStarted(record.id)
		end
	end
	for _, e in delta.events do
		if e.kind == "BattleEnded" then
			if not (fighting[e.province] or battles[e.province]) then
				battleStarted(e.province) -- won in a single round: the start and the end land together
			end
			battleEnded(e.province, e.a, e.b, destroyedAt[e.province] == true)
		elseif e.kind == "ProvinceTaken" then
			captured(e.province, e.a, e.b)
		elseif e.kind == "Power" or e.kind == "Disaster" then
			power(Primordial.POWERS[e.a], e.b, e.province, e.by or 0)
		elseif e.kind == "SeaBattle" and e.zone then
			if not (fightingNow[e.zone] or seaFights[e.zone]) then
				seaBattleStarted(e.zone) -- over in a single round: the start and the end land together
			end
			seaBattleEnded(e.zone, e.a, e.b, sunkAt[e.zone] == true)
		end
	end
	seaFights = fightingNow
	for _, a in delta.armies do
		armyAt[a.id] = a.location
	end
	if delta.phase ~= phase then
		phase = delta.phase
		phaseChanged(phase)
	end
	syncDomes()
end

-- What is running, for the harness: effects at once, particles in use, shield domes, the last effect shown and
-- its province (0 for a phase change).
function Effects.stats(): { active: number, particles: number, domes: number, last: string, province: number }
	local domeCount = 0
	for _ in domes do
		domeCount += 1
	end
	return { active = active, particles = created - #free, domes = domeCount, last = lastShown, province = lastProvince }
end

-- The last few effects shown (kind, province, os.clock() when it started, a power's look), oldest first, for the
-- harness.
function Effects.history(): { Shown }
	return history
end

function Effects.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Effects"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.None -- the flash covers the whole screen, notch and home bar included
	gui.DisplayOrder = 11 -- over the Results screen (10), under the map vote (20); it never takes taps
	flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.BackgroundTransparency = 1
	flash.Visible = false
	flash.Parent = gui
	-- the phase banner: a ribbon in the phase's colour (docs/UI_DIRECTION.md 7.8) with its icon and hero text, under
	-- the toasts' line; it pops in, its shine sweeps, and it fades out
	banner = Widgets.ribbon(gui, "WAR!", "war", Theme.color.war)
	banner.Name = "Banner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Visible = false
	bannerIcon = banner:FindFirstChild("Icon") :: GuiObject
	bannerScale = Instance.new("UIScale")
	bannerScale.Name = "DeviceScale" -- Widgets.fit shares it
	bannerScale.Parent = banner
	Widgets.fit(banner, nil, UDim2.new(0.5, 0, 0, BANNER_TOP + Widgets.RIBBON_HEIGHT // 2))
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	ClientState.onReset(onReset)
	ClientState.onDelta(onDelta)
	local sinceSync = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sinceSync += dt
		if sinceSync >= SYNC_SECONDS then
			sinceSync = 0
			syncDomes()
		end
	end)
end

return Effects
