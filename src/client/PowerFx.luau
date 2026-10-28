--!strict
-- How each Primordial power looks (docs/MONETIZATION.md 3.2 "Primordial-power effect"): the default look and the
-- shop's variants, which change only colours and particle shapes. The area (AREA), the timing and the sound cue
-- belong to the power, not the look, so Effects draws every variant over the same ground, for the same time, with
-- the same sound: a variant is never harder to read. Common variants recolour ("ice", "violet"); Rare and Epic
-- ones have a style of their own ("rays": light beams; "comet": a glittering tail, a glowing head and a star burst).
-- Also paints the little preview the shop shows. Pure Luau (packed 0xRRGGBB colours, RGBA buffers), tested in Lune.

local PowerFx = {}

export type Look = {
	style: string, -- "default", or a variant style the power knows (STYLES)
	ring: number, -- the main ring or wave
	core: number, -- Meteor: the falling rock; others: unused
	inner: number, -- Meteor: its bright centre
	flash: number, -- the impact flash
	particles: { number }, -- Meteor: the trail; Plague: rising motes; Blessing: sparkles
	debris: { number }, -- Meteor: what flies out of the crater
	rim: number, -- Meteor: the crater's rim
	pit: number, -- Meteor: the crater's pit
	ray: number, -- Blessing "rays": the light beams
}

-- How far each power's effect reaches, in particle units (Effects scales a unit by the zoom). Same for every look.
PowerFx.AREA = { Meteor = 14, Plague = 8, Blessing = 11 } :: { [string]: number }

-- The drawing styles each power has (any other style is drawn as "default").
PowerFx.STYLES = { Meteor = { "default", "comet" }, Plague = { "default" }, Blessing = { "default", "rays" } } :: {
	[string]: { string },
}

local function look(base: Look?, change: { [string]: any }): Look
	local out = table.clone(base or {
		style = "default",
		ring = 0xffffff,
		core = 0xffffff,
		inner = 0xffffff,
		flash = 0xffffff,
		particles = { 0xffffff },
		debris = {},
		rim = 0,
		pit = 0,
		ray = 0xffffff,
	}) :: any
	for k, v in change do
		out[k] = v
	end
	return out :: Look
end

-- The defaults (WorldBox's fire, plague green and gold; the same colours as Palette.fx).
local METEOR = look(nil, {
	ring = 0xf58231,
	core = 0xf58231,
	inner = 0xffe119,
	particles = { 0xffe119, 0xf58231, 0xe6194b, 0x5b5e5c },
	debris = { 0x7b572a, 0x5b5e5c, 0x9a9aa2 },
	rim = 0x7b572a,
	pit = 0x333333,
})
local PLAGUE = look(nil, { ring = 0x8bd14a, particles = { 0x8bd14a, 0x5a8f2e, 0xc6f07a } })
local BLESSING = look(nil, { ring = 0xffe119, particles = { 0xffe119, 0xfff6a8, 0xffffff } })

-- Looks by power, then by the item's art name ("" or "default" = the default look).
PowerFx.LOOKS = {
	Meteor = {
		default = METEOR,
		ice = look(METEOR, {
			ring = 0xa8dcff,
			core = 0x5aa8f0,
			inner = 0xe8f6ff,
			particles = { 0xe8f6ff, 0xa8dcff, 0x5aa8f0, 0x8fa3b3 },
			debris = { 0xdff3ff, 0x9ec9e6, 0x7d8a99 },
			rim = 0x9ec9e6,
			pit = 0x3f5f80,
		}),
		comet = look(METEOR, {
			style = "comet",
			ring = 0xd9b8ff,
			core = 0xb06cff,
			inner = 0xffffff,
			particles = { 0xffffff, 0xe0c8ff, 0xb08cff, 0x6a48c0 },
			debris = { 0xfff6a8, 0xd9b8ff, 0x8a6ad0 },
			rim = 0x8a6ad0,
			pit = 0x2a1d4a,
		}),
		-- Season 1 "Rise of the Primordials" (season-pass rewards)
		stone = look(METEOR, {
			ring = 0xb5ada0,
			core = 0x8a8478,
			inner = 0xd8d2c4,
			particles = { 0xd8d2c4, 0xa39c8f, 0x7a746a, 0x5b5e5c },
			debris = { 0x9a948c, 0x6e6a62, 0x4a4842 },
		}),
		ember = look(METEOR, {
			style = "comet",
			ring = 0xff8a3a,
			core = 0xff5a1a,
			inner = 0xffd27a,
			particles = { 0xffd27a, 0xff8a3a, 0xd8401c, 0x6a2a18 },
			debris = { 0xffb347, 0xc8502e, 0x5b3a2a },
			rim = 0x8c2a2a,
			pit = 0x3c1420,
		}),
		firestorm = look(METEOR, {
			style = "comet",
			ring = 0xe9290e,
			core = 0xb81a0a,
			inner = 0xfff0a0,
			particles = { 0xfff0a0, 0xff6a2a, 0xe9290e, 0x7a1a10 },
			debris = { 0xff9a3a, 0xb81a0a, 0x3a1a14 },
			rim = 0x7a1a10,
			pit = 0x2a0e0a,
		}),
		lava = look(METEOR, {
			style = "comet",
			ring = 0xff6a00,
			core = 0x2a1d24,
			inner = 0xff9a2a,
			particles = { 0xffc04a, 0xff6a00, 0xc83a0a, 0x2a1d24 },
			debris = { 0xff6a00, 0x4a3038, 0x2a1d24 },
			rim = 0xc83a0a,
			pit = 0x1a1014,
		}),
		phoenix = look(METEOR, {
			style = "comet",
			ring = 0xffd24a,
			core = 0xff7a1a,
			inner = 0xffffff,
			particles = { 0xffffff, 0xffe9a0, 0xffb347, 0xff5a1a },
			debris = { 0xfff6a8, 0xffb347, 0xe0602a },
			rim = 0xe0602a,
			pit = 0x5a2a10,
		}),
		-- earned (the Meteorologist achievement): a thunderstone streaking in, storm blue with lightning yellow
		storm = look(METEOR, {
			style = "comet",
			ring = 0x4a78d0,
			core = 0x2c4f9e,
			inner = 0xfff36a,
			particles = { 0xfff36a, 0xc8d8ff, 0x4a78d0, 0x2c3550 },
			debris = { 0x6f7d99, 0x4a5670, 0xfff36a },
			rim = 0x4a5670,
			pit = 0x1c2236,
		}),
	},
	Plague = {
		default = PLAGUE,
		violet = look(PLAGUE, { ring = 0xa45be0, particles = { 0xa45be0, 0x6a2f9e, 0xd9a8ff } }),
		-- Season 1 (colours only: Plague has no other style)
		ember = look(PLAGUE, { ring = 0xff7a2a, particles = { 0xff7a2a, 0xc8502e, 0xffc04a } }),
		ash = look(PLAGUE, { ring = 0x9a948c, particles = { 0xb5ada0, 0x6e6a62, 0xd8d2c4 } }),
		void = look(PLAGUE, { ring = 0x5a3aa0, particles = { 0x3a2a6a, 0x7a5ad0, 0x1d1d24 } }),
		cinder = look(PLAGUE, { ring = 0xd8401c, particles = { 0x4a3038, 0xd8401c, 0xffb347 } }),
	},
	Blessing = {
		default = BLESSING,
		rays = look(BLESSING, {
			style = "rays",
			ring = 0xffd24a,
			particles = { 0xffe9a0, 0xfff6a8, 0xffffff },
			ray = 0xfff2b0,
		}),
		-- Season 1 (all in the "rays" style)
		molten = look(BLESSING, {
			style = "rays",
			ring = 0xff8a3a,
			particles = { 0xffc04a, 0xff8a3a, 0xfff0a0 },
			ray = 0xffb070,
		}),
		ember = look(BLESSING, {
			style = "rays",
			ring = 0xe0602a,
			particles = { 0xff9a5a, 0xffd27a, 0xffffff },
			ray = 0xffc8a0,
		}),
		worldsplitter = look(BLESSING, {
			style = "rays",
			ring = 0x7cfbef,
			particles = { 0x7cfbef, 0xc8fff8, 0xffffff },
			ray = 0xb0fff6,
		}),
		starfall = look(BLESSING, {
			style = "rays",
			ring = 0xb08cff,
			particles = { 0xffffff, 0xe0c8ff, 0xfff6a8 },
			ray = 0xe0d0ff,
		}),
		sunfire = look(BLESSING, {
			style = "rays",
			ring = 0xffa000,
			particles = { 0xffe119, 0xff8a00, 0xffffff },
			ray = 0xffe080,
		}),
	},
} :: { [string]: { [string]: Look } }

-- The look to draw for a power with an item's art name ("" = default). Powers without variants return nil:
-- Effects draws them as before.
function PowerFx.look(power: string, art: string?): Look?
	local looks = PowerFx.LOOKS[power]
	if looks == nil then
		return nil
	end
	return looks[art or "default"] or looks.default
end

------------------------------------------------------------------------------------------------- shop preview

PowerFx.PREVIEW_SIZE = { w = 32, h = 24 }
local GROUND, GROUND_DARK = 0x7eaf46, 0x709940 -- a patch of WorldBox grass under the effect

local function rgba(c: number): number
	return 0xff000000 + bit32.band(c, 255) * 65536 + bit32.band(bit32.rshift(c, 8), 255) * 256 + bit32.rshift(c, 16)
end

-- One frame of the effect mid-animation over a patch of grass, for the shop card: RGBA pixels, width, height.
function PowerFx.preview(power: string, art: string?): (buffer, number, number)
	local w, h = PowerFx.PREVIEW_SIZE.w, PowerFx.PREVIEW_SIZE.h
	local pixels = buffer.create(w * h * 4)
	local function set(x: number, y: number, c: number)
		x, y = math.floor(x + 0.5), math.floor(y + 0.5)
		if x >= 0 and y >= 0 and x < w and y < h then
			buffer.writeu32(pixels, (y * w + x) * 4, rgba(c))
		end
	end
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			set(x, y, if (x * 7 + y * 13) % 11 == 0 then GROUND_DARK else GROUND)
		end
	end
	local l = PowerFx.look(power, art)
	if l == nil then
		return pixels, w, h
	end
	local cx, cy = w / 2, h / 2 + 2
	local function ring(radius: number, color: number, count: number)
		for i = 1, count do
			local a = i / count * 2 * math.pi
			set(cx + math.cos(a) * radius, cy + math.sin(a) * radius * 0.75, color)
		end
	end
	local p = l.particles
	if power == "Meteor" then
		-- the rock coming down from the top right, its trail behind it
		local hx, hy = cx - 2, cy
		local length = if l.style == "comet" then 16 else 10
		for k = 1, length do
			local tx, ty = hx + k * 0.9, hy - k * 0.7
			set(tx, ty, p[math.min(#p, 1 + (k - 1) // 3)])
			if l.style == "comet" and k % 3 == 0 then
				set(tx + 1, ty - 2, p[1]) -- glitter beside the tail
				set(tx - 1, ty + 2, p[2])
			end
		end
		for dy = -1, 1 do
			for dx = -1, 1 do
				set(hx + dx, hy + dy, l.core)
			end
		end
		set(hx, hy, l.inner)
		if l.style == "comet" then
			for _, d in { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } } do
				set(hx + d[1], hy + d[2], l.inner) -- the glowing plus around the head
			end
		end
		set(hx - 4, hy + 5, l.rim) -- a little debris below
		set(hx + 3, hy + 6, l.debris[1])
	elseif power == "Plague" then
		ring(8, l.ring, 18)
		ring(4, l.ring, 10)
		for i = 0, 5 do
			set(cx - 6 + i * 2.4, cy - 2 - (i % 3) * 2, p[i % #p + 1])
		end
	elseif power == "Blessing" then
		if l.style == "rays" then
			for _, x in { cx - 7, cx - 1, cx + 5 } do -- beams of light, two pixels wide
				for y = 2, math.floor(cy) + 2 do
					set(x, y, l.ray)
					set(x + 1, y, l.ray)
				end
			end
		end
		ring(9, l.ring, 20)
		if l.style == "rays" then
			-- a few four-point stars
			for i, s in { { -7, -1 }, { -2, 3 }, { 3, -2 }, { 7, 2 } } do
				local x, y = cx + s[1], cy + s[2]
				set(x, y, p[3])
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					set(x + d[1], y + d[2], p[(i - 1) % 2 + 1])
				end
			end
		else
			for i = 0, 6 do
				set(cx - 7 + i * 2.3, cy - 3 + (i % 2) * 3, p[i % #p + 1])
			end
		end
	end
	return pixels, w, h
end

return PowerFx
