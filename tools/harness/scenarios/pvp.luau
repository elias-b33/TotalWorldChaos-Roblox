--!nocheck
-- Smarter PvP (docs/DESIGN.md "Troops", "Armies and combat"): the recruit tiles' counter badges (what each troop
-- beats, and the pick against the enemy armies near), an army's morale on the army sheet and under its token, the
-- morale bars in a battle, and battle toasts that say when a morale break or a flank decided it.

local Emulator = require("../Emulator")
local H = require("../H")
local provinceByName = H.provinceByName

local Army = require("../../../src/shared/Sim/Army")
local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
local Movement = require("../../../src/shared/Sim/Movement")
local Troops = require("../../../src/shared/Sim/Troops")

-- The counter badge on the recruit tile of `troop`, if the tile shows one.
local function badgeOn(client, troop: string)
	local tile = H.button(client, "Recruit_" .. troop)
	return if tile then tile:FindFirstChild("Counter") else nil
end

-- An army's morale bar under its token, when it shows.
local function moraleBar(client, armyId: number)
	local token = H.mapObject(client, "Army" .. armyId)
	local bar = token and token:FindFirstChild("Morale")
	return if bar and bar.Visible then bar else nil
end

-- Wait until a visible text contains `text` (a toast), for at most `seconds` of game time.
local function waitFor(client, text: string, seconds: number): boolean
	local deadline = Emulator.now() + seconds
	while Emulator.now() < deadline do
		if Emulator.findText(client, text) then
			return true
		end
		Emulator.run(0.25)
	end
	return false
end

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	local mine, theirs = state.nations[A].race, state.nations[B].race
	local line, ranged, fast = Troops.ofRole(mine, "line"), Troops.ofRole(mine, "ranged"), Troops.ofRole(mine, "fast")
	local rock, reach = provinceByName("Cinder Rock"), provinceByName("Cinder Reach")
	local leeward = provinceByName("Zephyr Leeward")
	-- the War phase: Aurora holds Cinder Rock, Zephyr Cinder Reach next to it; no garrisons there
	state.tick = 179
	state.provinces[rock].owner = A
	state.provinces[reach].owner = B
	for id, a in state.armies do
		if a.location == rock or a.location == reach or a.location == leeward then
			state.armies[id] = nil
		end
	end
	state.nations[A].gold, state.nations[A].manpower = 1000, 20000
	Emulator.run(2)
	H.expect((Diplomacy.declareWar(state, A, B)), "Aurora and Zephyr are at war")
	Emulator.run(8) -- the war's banner and toasts pass

	-- 1. Counters: the line, ranged and fast recruit tiles show the troop each beats
	H.tapProvince(alice, rock)
	Emulator.run(0.5)
	local onRanged, onLine, onFast = badgeOn(alice, ranged), badgeOn(alice, line), badgeOn(alice, fast)
	H.expect(onRanged ~= nil and onRanged:GetAttribute("Beats") == line, "the ranged tile shows the line troop it beats")
	H.expect(onLine ~= nil and onLine:GetAttribute("Beats") == fast, "the line tile shows the fast troop")
	H.expect(onFast ~= nil and onFast:GetAttribute("Beats") == ranged, "the fast tile shows the ranged troop")
	H.expect(H.iconIn(alice, "Recruit_" .. ranged, Troops.icon(line)), "as its icon")
	H.expect(
		badgeOn(alice, Troops.ofRole(mine, "elite")) == nil and badgeOn(alice, Troops.ofRole(mine, "special")) == nil,
		"elites and specials beat nothing: no badge"
	)
	H.expect(onRanged:GetAttribute("Hint") == "", "no enemy army near: no pick")
	H.shot(alice, "counter_badges")
	-- enemy line troops next door: the ranged tile is the pick (gold), the fast tile is weak against them (crimson)
	local guard = Army.spawn(state, B, reach, 4000, Troops.ofRole(theirs, "line"))
	Emulator.run(1.5)
	H.expect(badgeOn(alice, ranged):GetAttribute("Hint") == "good", "against their line troops the ranged tile is the pick")
	H.expect(badgeOn(alice, fast):GetAttribute("Hint") == "bad", "and the fast troop is weak")
	H.expect(badgeOn(alice, line):GetAttribute("Hint") == "", "the line troop: neither")
	H.shot(alice, "counter_pick")

	-- 2. Morale on the army sheet and under the token
	local tired = Army.spawn(state, A, rock, 3500, line)
	tired.morale = 40
	Emulator.run(1.5)
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	H.expect(H.textOf(alice, "Value") == "40", "the army sheet shows its morale")
	local sheetBar = H.client(alice, "UI.ArmySheet") and alice.localPlayer.PlayerGui:FindFirstChild("Progress", true)
	H.expect(sheetBar ~= nil and sheetBar:GetAttribute("Tone") == "low", "on a gold bar: tired")
	local bar = moraleBar(alice, tired.id)
	H.expect(bar ~= nil and bar:GetAttribute("Morale") == 40, "a bar under its token on the map")
	H.shot(alice, "army_morale")
	Emulator.press(alice, "Cancel")
	Emulator.run(0.5)

	-- 3. A battle: the tired army, with more men, breaks against a fresh one
	local fresh = Army.spawn(state, B, rock, 3000, Troops.ofRole(theirs, "line"))
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, rock), true)
	Emulator.run(1.2)
	H.expect(tired.inBattle and moraleBar(alice, fresh.id) ~= nil, "in battle: both tokens show their morale")
	H.shot(alice, "battle_morale")
	H.expect(waitFor(alice, "Your army broke at Cinder Rock", 6), "Alice: your army broke (with more men)")
	H.expect(tired.retreating == true, "the broken army retreats")
	H.expect(Emulator.findText(bob, "They broke at Cinder Rock") ~= nil, "Bob: they broke")
	H.shot(alice, "broke_toast")
	H.shot(bob, "broke_toast_winner")

	-- 4. A flank: two of Alice's stacks march on Bob's army at Cinder Reach from two sides on the same tick
	state.armies[fresh.id] = nil
	state.provinces[leeward].owner = A
	Emulator.run(8) -- the toasts pass
	local west = Army.spawn(state, A, rock, 2100, line)
	local east = Army.spawn(state, A, leeward, 2100, line)
	Emulator.run(1.5)
	H.expect(Movement.order(state, A, west.id, reach) and Movement.order(state, A, east.id, reach), "both marching")
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, reach), true)
	local deadline = Emulator.now() + 15
	while not west.inBattle and Emulator.now() < deadline do
		Emulator.run(0.25)
	end
	H.expect(west.inBattle and east.inBattle and state.armies[east.id] ~= nil, "they arrived together and fight as two")
	H.shot(alice, "flank_battle")
	H.expect(waitFor(alice, "Flank attack", 6), "Alice: the flank won it")
	H.expect(state.armies[guard.id] == nil or guard.retreating == true, "Bob's army lost")
	H.expect(Emulator.findText(bob, "Flanked at Cinder Reach") ~= nil, "Bob: flanked")
	H.shot(alice, "flank_toast")
end

return { run = run }
