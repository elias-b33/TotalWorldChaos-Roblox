--!strict
-- Power-effect cosmetics (docs/MONETIZATION.md 3.2): every shop variant has a look, changes how its power looks, and
-- keeps the power's area (and, since a look holds only colours and a style, its timing and sound cue).
local Catalogue = require("../src/shared/Catalogue")
local PowerFx = require("../src/client/PowerFx")
local T = require("./TestKit")

local LOOK_FIELDS = {
	style = true,
	ring = true,
	core = true,
	inner = true,
	flash = true,
	particles = true,
	debris = true,
	rim = true,
	pit = true,
	ray = true,
}

local function pixelAt(pixels: buffer, w: number, x: number, y: number): number
	return buffer.readu32(pixels, (y * w + x) * 4)
end

T.test("every power-effect item has a look for its power", function()
	local items = Catalogue.ofSlot("PowerFx")
	T.expect(#items >= 4, "the shop sells power effects")
	for _, item in items do
		local power = assert(item.power, item.id .. " names its power")
		T.expect(PowerFx.LOOKS[power] ~= nil and PowerFx.LOOKS[power][item.art] ~= nil, item.id .. " has a look")
		T.expect(PowerFx.look(power, item.art) ~= PowerFx.look(power, ""), item.id .. " is not the default look")
	end
end)

T.test("a look holds colours and a known style only: no area, timing or sound of its own", function()
	for power, looks in PowerFx.LOOKS do
		T.expect(PowerFx.AREA[power] ~= nil, power .. " has one area for every look")
		T.expect(looks.default ~= nil, power .. " has a default look")
		for name, look in looks do
			for key in look :: any do
				T.expect(
					LOOK_FIELDS[key] == true,
					string.format("%s %s: %s is a colour or the style", power, name, key)
				)
			end
			T.expect(table.find(PowerFx.STYLES[power], look.style) ~= nil, power .. " " .. name .. " has a known style")
			T.expect(#look.particles > 0, power .. " " .. name .. " has particle colours")
		end
	end
end)

T.test("Common variants only recolour; Rare and Epic ones have a style of their own", function()
	for _, item in Catalogue.ofSlot("PowerFx") do
		local look = assert(PowerFx.look(item.power :: string, item.art))
		if item.rarity == "Common" then
			T.equal(look.style, "default", item.id .. " keeps the default style")
		else
			T.expect(look.style ~= "default", item.id .. " has a new style")
		end
		local default = assert(PowerFx.look(item.power :: string, ""))
		T.expect(look.ring ~= default.ring or look.particles[1] ~= default.particles[1], item.id .. " changes colours")
	end
end)

T.test("an unknown look falls back to the default; powers without variants have none", function()
	T.equal(PowerFx.look("Meteor", "nonsense"), PowerFx.look("Meteor", ""))
	T.equal(PowerFx.look("Rebels", ""), nil)
end)

T.test("the shop preview shows each variant differently, over the same patch of ground", function()
	local w, h = PowerFx.PREVIEW_SIZE.w, PowerFx.PREVIEW_SIZE.h
	for _, item in Catalogue.ofSlot("PowerFx") do
		local power = item.power :: string
		local pixels, pw, ph = PowerFx.preview(power, item.art)
		T.equal(pw, w)
		T.equal(ph, h)
		T.equal(buffer.len(pixels), w * h * 4)
		local default = PowerFx.preview(power, "")
		T.expect(buffer.tostring(pixels) ~= buffer.tostring(default), item.id .. "'s preview differs from the default")
		local ground = PowerFx.preview("Rebels", "") -- no effect drawn: just the ground
		-- the corners stay ground: the effect is drawn in the middle, inside its area
		for _, corner in { { 0, h - 1 }, { w - 1, h - 1 } } do
			T.equal(pixelAt(pixels, w, corner[1], corner[2]), pixelAt(ground, w, corner[1], corner[2]))
		end
		-- every pixel is opaque
		for i = 0, w * h - 1 do
			T.expect(bit32.rshift(buffer.readu32(pixels, i * 4), 24) == 255, "opaque")
		end
	end
end)

T.finish()
