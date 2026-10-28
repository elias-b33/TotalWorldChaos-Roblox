--!nocheck
-- Phase 4: sound and effects. Every effect fires through the real flow (server state -> events in the delta ->
-- the client's Effects) and is photographed mid-animation; sounds are checked in the emulator's log.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local A = H.myNation(alice)
	local Effects = H.client(alice, "Effects")
	local MapView = H.client(alice, "MapView")
	local Army = require("../../../src/shared/Sim/Army")
	local Primordial = require("../../../src/shared/Sim/Primordial")
	local function soundsNamed(name: string): number
		local n = 0
		for _, s in Emulator.sounds do
			if s.name == name then
				n += 1
			end
		end
		return n
	end
	-- run in small steps until Effects shows `kind` (over `province`, if given); the bots fight battles of their own
	local function waitFor(kind: string, seconds: number?, province: number?)
		local start = Emulator.now()
		local function seen()
			for _, h in Effects.history() do
				if h.at >= start and h.kind == kind and (province == nil or h.province == province) then
					return true
				end
			end
			return false
		end
		local deadline = Emulator.now() + (seconds or 10)
		while not seen() and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		H.expect(seen(), "the " .. kind .. " effect plays")
	end

	H.expect(H.iconShown(alice, "soundOn"), "the mute button sits in the top bar")
	local taps = soundsNamed("Tap")
	Emulator.press(alice, "Capital")
	Emulator.run(0.5)
	H.expect(soundsNamed("Tap") == taps + 1, "a button tap plays the tap sound")
	Emulator.press(alice, "✕")

	-- the War banner
	state.tick = 178
	waitFor("War", 5)
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "WAR!") ~= nil, "the War banner shows")
	H.expect(soundsNamed("War") == 1, "the War sound plays")
	H.shot(alice, "phase_war")
	Emulator.run(3)

	-- a battle against the garrison of the nearest neutral province
	local capital = state.nations[A].capital
	local here = H.provinceMap(alice, capital)
	local target, best = nil, math.huge
	for id, p in state.provinces do
		local garrisoned = false
		for _, a in state.armies do
			garrisoned = garrisoned or (a.owner == 0 and a.location == id)
		end
		local d = (H.provinceMap(alice, id) - here).Magnitude
		if p.owner == nil and p.terrain ~= "Mountain" and garrisoned and d < best then
			target, best = id, d
		end
	end
	H.expect(target ~= nil, "found a garrisoned neutral province")
	MapView.centreOn(H.provinceMap(alice, target), true)
	Emulator.run(1.5)
	Army.spawn(state, A, target, 3000) -- big enough to win, small enough for a three-round fight
	waitFor("BattleStart", 5, target)
	Emulator.run(0.3)
	H.expect(Effects.stats().particles > 10, "dust and crossed swords are on the map")
	H.shot(alice, "battle_start")
	waitFor("ArmyDestroyed", 40, target)
	Emulator.run(0.25)
	H.expect(soundsNamed("ArmyDestroyed") >= 1, "a destroyed army plays its sound")
	H.shot(alice, "army_destroyed")

	-- the siege, sped up, and the capture ring in Alice's colour
	local deadline = Emulator.now() + 20
	while state.provinces[target].siege == nil and Emulator.now() < deadline do
		Emulator.run(0.5)
	end
	local siege = state.provinces[target].siege
	H.expect(siege ~= nil, "the siege began")
	siege.progress = math.max(siege.progress, siege.required - 2)
	waitFor("Capture", 10, target)
	Emulator.run(0.25)
	H.expect(state.provinces[target].owner == A, "Alice took the province")
	H.expect(soundsNamed("Capture") >= 1, "the capture sound plays")
	H.shot(alice, "capture")
	Emulator.run(2)

	-- Primordial powers, cast by Zephyr's nation through Sim.Primordial (immunity cleared between harmful ones)
	local caster = { nation = 2 }
	local function cast(power: string, targetId: number)
		state.nations[2].charges = 5
		state.nations[A].powerImmuneUntil = 0
		local ok, why = Primordial.use(state, caster, power, targetId)
		H.expect(ok, power .. " was cast (" .. tostring(why) .. ")")
	end
	MapView.centreOn(here, true)
	Emulator.run(1.5)
	local army = Army.spawn(state, A, capital, 6000)
	Emulator.run(1.5)
	cast("Meteor", army.id)
	waitFor("Meteor", 3, capital)
	Emulator.run(0.4)
	H.shot(alice, "meteor_falling")
	Emulator.run(0.5)
	H.expect(soundsNamed("MeteorImpact") == 1, "the meteor lands with a bang")
	H.shot(alice, "meteor_impact")
	Emulator.run(3)

	cast("Plague", A)
	waitFor("Plague", 3, capital)
	Emulator.run(0.5)
	H.shot(alice, "plague")
	Emulator.run(3)

	cast("Rebels", capital)
	waitFor("Rebels", 3, capital)
	Emulator.run(0.8)
	H.shot(alice, "rebels")
	Emulator.run(3)

	state.provinces[capital].building = "Farm"
	cast("Earthquake", capital)
	waitFor("Earthquake", 3, capital)
	Emulator.run(0.6)
	H.shot(alice, "earthquake")
	Emulator.run(3)

	cast("Blessing", capital)
	waitFor("Blessing", 3, capital)
	Emulator.run(0.7)
	H.shot(alice, "blessing")
	Emulator.run(2.5)

	cast("Shield", capital)
	waitFor("Shield", 3, capital)
	Emulator.run(1.5)
	H.expect(Effects.stats().domes == 1, "a shield dome stands over the province")
	H.shot(alice, "shield")
	H.expect(Effects.stats().particles <= 240, "particles stay inside the pool")

	-- mute: nothing plays until unmuted, and it is remembered
	Emulator.press(alice, "Mute")
	Emulator.run(0.2)
	H.expect(H.iconShown(alice, "soundOff"), "the button shows muted")
	local before = #Emulator.sounds
	cast("Blessing", capital)
	waitFor("Blessing", 3, capital)
	Emulator.run(1)
	H.expect(#Emulator.sounds == before, "muted: no sounds")
	Emulator.press(alice, "Mute")
	Emulator.run(0.2)
	H.expect(H.iconShown(alice, "soundOn"), "unmuted again")

	-- the Cataclysm banner, then the shield runs out and its dome goes
	state.tick = 20 * 60 - 2
	waitFor("Cataclysm", 5)
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "CATACLYSM") ~= nil, "the Cataclysm banner shows")
	H.shot(alice, "phase_cataclysm")
	Emulator.run(3)
	H.expect(Effects.stats().domes == 0, "the dome is gone once the shield ends")
	H.expect(Effects.stats().active <= 14, "only a few effects run at once")

	-- Results: Aurora takes 40% of the world; the banner shows over the results screen
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	waitFor("Results", 5)
	Emulator.run(0.4)
	H.expect(Emulator.findText(alice, "MATCH OVER") ~= nil, "the Results banner shows")
	H.expect(soundsNamed("Results") == 1, "the Results sound plays")
	H.shot(alice, "phase_results")
end

return { run = run }
