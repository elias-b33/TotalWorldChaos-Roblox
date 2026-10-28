--!nocheck
-- Races and troops (docs/DESIGN.md "Races", "Troops"). The draft shows every nation's race and the tapped one's
-- bonus, and picking Ironholds makes Alice the Dwarves; the nations drawer shows the races; the province sheet
-- recruits each of the Dwarves' five troops into one army whose sheet shows the composition and the Sappers' trick;
-- the server refuses another race's troop; Sappers besiege faster than Axemen; and the Dwarves' ranged troop, the
-- Firelocks, wins a battle defending that it loses attacking.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	local Army = require("../../../src/shared/Sim/Army")
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	-- the Dwarves' one-line bonus as RaceInfo.bonus writes it from Config.Races ("+25% defending hills, forts -50%")
	local DWARVES = string.format(
		"+%d%% defending hills, forts -%d%%",
		math.floor(Config.Races.Dwarves.hillsDefenceBonus * 100 + 0.5),
		math.floor((1 - Config.Races.Dwarves.fortCostMultiplier) * 100 + 0.5)
	)
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local LobbyService = H.server("Services.LobbyService")
	Emulator.press(alice, "Card_eldmoor")
	Emulator.press(alice, "Card_eldmoor")
	local deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local state = H.state()
	H.expect(state.mapId == "eldmoor" and LobbyService.phase() == "Pick", "the draft runs on Eldmoor")
	Emulator.run(1.5)

	-- the draft: every card shows its nation's race (Eldmoor's cast: the four classic races and the Lizardfolk); the
	-- tapped nation gets a race card with its bonus
	local Races = require("../../../src/shared/Sim/Races")
	for _, race in Races.forMap("eldmoor") do
		H.expect(H.iconShown(alice, string.lower(race)), "a card shows the " .. string.lower(race) .. " icon")
	end
	H.expect(Emulator.findText(alice, "Saltmarsh\nLizardfolk") ~= nil, "Saltmarsh's card says Lizardfolk")
	local ironholds
	for id, n in state.nations do
		if n.name == "Ironholds" then
			ironholds = id
		end
	end
	H.expect(state.nations[ironholds].race == "Dwarves", "Ironholds are Dwarves (map data)")
	H.expect(Emulator.findText(alice, "Ironholds\nDwarves") ~= nil, "Ironholds' card says Dwarves")
	H.expect(Emulator.findText(alice, "Elderwood\nElves") ~= nil, "Elderwood's card says Elves")
	H.tapProvince(alice, state.nations[ironholds].capital, false)
	H.expect(Emulator.findText(alice, "Ironholds: Dwarves · " .. DWARVES) ~= nil, "the race card names the bonus")
	H.shot(alice, "draft")
	Emulator.press(alice, "Pick Ironholds")
	Emulator.run(1.5)
	H.expect(state.nations[ironholds].userId == alice.serverPlayer.UserId, "Alice picked Ironholds, and the Dwarves")
	deadline = Emulator.now() + 40
	while state.phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1.5)
	local me = H.myNation(alice)
	H.expect(me == ironholds and state.phase == "Peace", "the match starts with Alice on Ironholds")

	-- the nations drawer: a race icon on every row, and Alice's race and bonus under the rows
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Dwarves: " .. DWARVES) ~= nil, "the drawer says what being Dwarves gives")
	H.expect(H.iconShown(alice, "elves") and H.iconShown(alice, "orcs"), "and every row's race")
	H.shot(alice, "nations")
	Emulator.press(alice, "NationsButton")

	-- the province sheet: one recruit button for each of the Dwarves' five troops, each with its price
	local Troops = require("../../../src/shared/Sim/Troops")
	local ROSTER = { "Axemen", "Firelocks", "RamRiders", "Ironguard", "Sappers" }
	local nation = state.nations[me]
	nation.gold, nation.manpower = 1000, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for i, troop in Troops.roster("Dwarves") do
		H.expect(troop == ROSTER[i], "the Dwarves' " .. Troops.ROLES[i] .. " troop: " .. troop)
		H.expect(H.button(alice, "Recruit_" .. troop) ~= nil, "a recruit button for " .. Troops.name(troop))
	end
	H.expect(
		Emulator.findText(alice, "Ram riders") ~= nil and Emulator.findText(alice, "Knights") == nil,
		"each under its own name, and no other race's troop"
	)
	H.shot(alice, "recruit_buttons")
	local t = Config.Troops
	local spent = 0
	for _, troop in ROSTER do
		Emulator.press(alice, "Recruit_" .. troop)
		Emulator.run(1.2)
		spent += t[troop].gold
	end
	local army = Army.idleAt(state, me, nation.capital)
	H.expect(army ~= nil and army.men == 5000, "the five regiments make one army")
	local each = true
	for _, troop in ROSTER do
		each = each and army.troops[troop] == 1000
	end
	H.expect(each, "one regiment of each troop type")
	H.expect(nation.gold == 1000 - spent, "each at its own price")
	-- on the map: a soldier and a badge of its main troop (five equal regiments: the dearest, the Ram riders); the
	-- province sheet's chips say the same, and its owner chip shows the Dwarves
	local sprite = H.mapObject(alice, "Army" .. army.id)
		and H.mapObject(alice, "Army" .. army.id):FindFirstChild("TokenSkin")
	H.expect(sprite ~= nil and sprite:GetAttribute("Soldier") == "RamRiders", "Alice's army is a ram rider on the map")
	H.expect(
		select(2, H.badge(alice, army.id)) == "ramriders",
		"its badge shows the Ram riders: equal men, the dearest troop"
	)
	H.expect(H.iconIn(alice, "ArmyChip" .. army.id, "ramriders"), "so does its chip on the province sheet")
	H.expect(H.iconIn(alice, "Owner", "dwarves"), "the owner chip shows the Dwarves' icon")

	-- the army sheet shows the composition as chips (five types: icons and men, no names) and the Sappers' trick
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	for _, troop in ROSTER do
		H.expect(H.iconIn(alice, "Troop_" .. troop, Troops.icon(troop)), "the army sheet shows 1k " .. troop)
	end
	H.expect(
		Emulator.findText(alice, string.format("Sappers: besieges %gx as fast", t.Sappers.siegeSpeed)) ~= nil,
		"and what the Sappers do"
	)
	H.shot(alice, "army_composition")
	Emulator.press(alice, "Cancel")
	Emulator.run(0.5)

	-- the server refuses any other race's troop (the sheet never offers one; a hacked client could still ask)
	H.client(alice, "Intents").recruit(nation.capital, 1, "Knights")
	Emulator.run(1.2)
	H.expect(Emulator.findText(alice, "Only its own race can recruit that troop") ~= nil, "the refusal toast")
	H.expect(army.troops.Knights == nil and army.men == 5000, "and no knights joined")
	H.shot(alice, "refused_troop")

	-- Sappers besiege faster (Config.Troops.Sappers.siegeSpeed): Alice's Sappers and her Axemen each besiege a neutral
	-- province of the same development (garrisons gone); the Sappers' falls first
	local pair
	for _, a in state.provinces do
		for _, bId in a.neighbors do
			local b = state.provinces[bId]
			if
				pair == nil
				and a.owner == nil
				and b.owner == nil
				and a.terrain ~= "Mountain"
				and b.terrain ~= "Mountain"
				and a.development == b.development
				and a.development >= 2
			then
				local mineNear = false
				for _, n in a.neighbors do
					mineNear = mineNear or state.provinces[n].owner == me
				end
				if mineNear then
					pair = { a.id, b.id }
				end
			end
		end
	end
	H.expect(pair ~= nil, "two neutral provinces side by side near Alice")
	local fastId, slowId = pair[1], pair[2]
	for id, a in state.armies do
		if a.location == fastId or a.location == slowId then
			state.armies[id] = nil
		end
	end
	local required = state.provinces[fastId].development * Config.Siege.TicksPerDevelopment
	Army.spawn(state, me, fastId, 1000, "Sappers")
	Army.spawn(state, me, slowId, 1000) -- her line troop, the Axemen
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, fastId), true)
	Emulator.run(8)
	local fast, slow = state.provinces[fastId].siege, state.provinces[slowId].siege
	H.expect(fast ~= nil and slow ~= nil, "both sieges are running")
	H.expect(
		math.abs(fast.progress - t.Sappers.siegeSpeed * slow.progress) < 1e-9,
		string.format("Sappers %.2f vs Axemen %d after the same seconds", fast.progress, slow.progress)
	)
	H.shot(alice, "sappers_siege")
	deadline = Emulator.now() + required
	while state.provinces[fastId].owner ~= me and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[fastId].owner == me, "the Sappers took their province")
	H.expect(state.provinces[slowId].owner == nil, "while the Axemen's siege still runs")
	deadline = Emulator.now() + required
	while state.provinces[slowId].owner ~= me and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[slowId].owner == me, "the Axemen's province falls later")

	-- a battle where troop types matter: 3,000 Firelocks (the Dwarves' ranged troop) holding Alice's plains province
	-- beat 3,000 attacking Footmen; the same Firelocks attacking the enemy's plains province lose to 3,000 defending
	-- Footmen
	state.tick = 179
	Emulator.run(2)
	local enemy, home, away
	for _, p in state.provinces do
		if p.owner == me and p.terrain == "Plains" and not p.isCapital then
			for _, n in p.neighbors do
				local q = state.provinces[n]
				if enemy == nil and q.owner ~= nil and q.owner ~= me and q.terrain == "Plains" then
					enemy, home, away = q.owner, p.id, q.id
				end
			end
		end
	end
	if enemy == nil then
		-- no plains border: lend Alice a plains province next to a neighbour's plains
		for _, p in state.provinces do
			for _, n in p.neighbors do
				local q = state.provinces[n]
				if
					enemy == nil
					and p.owner ~= nil
					and p.owner ~= me
					and p.terrain == "Plains"
					and not p.isCapital
					and q.owner ~= nil
					and q.owner ~= me
					and q.owner ~= p.owner
					and q.terrain == "Plains"
				then
					p.owner = me
					enemy, home, away = q.owner, p.id, q.id
				end
			end
		end
	end
	H.expect(enemy ~= nil, "a plains province of Alice's next to a neighbour's plains")
	state.nations[enemy].race = "Humans" -- its line troop, Footmen (no forest or hills bonus could decide it, on plains)
	state.wars[999] = { id = 999, attackers = { me }, defenders = { enemy }, startedAt = state.tick }
	H.expect(Diplomacy.atWar(state, me, enemy), "Alice is at war with " .. state.nations[enemy].name)
	local function fight(where: number, archerSide: number, infantrySide: number)
		for id, a in state.armies do
			if a.location == where then
				state.armies[id] = nil
			end
		end
		local archers = Army.spawn(state, archerSide, where, 3000, "Firelocks")
		local infantry = Army.spawn(state, infantrySide, where, 3000) -- the Humans' Footmen
		return archers, infantry
	end
	local won0 = nation.battlesWon
	local holders, raiders = fight(home, me, enemy)
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, home), true)
	Emulator.run(1.5)
	H.shot(alice, "archers_hold")
	Emulator.run(3)
	H.expect(nation.battlesWon == won0 + 1, "defending, the Firelocks won")
	H.expect(state.armies[raiders.id] == nil or raiders.retreating == true, "the Footmen were beaten off")
	H.expect(state.armies[holders.id] ~= nil and holders.men > raiders.men, "the Firelocks kept more men")
	Emulator.run(1)
	H.expect(
		select(2, H.badge(alice, holders.id)) == "firelocks",
		"their badge shows the firelock once the battle is over"
	)
	local enemyWon0 = state.nations[enemy].battlesWon
	local attackers = fight(away, me, enemy)
	Emulator.run(4.5)
	-- (the enemy is a bot at war: it may win other battles meanwhile, so count at least this one)
	H.expect(state.nations[enemy].battlesWon > enemyWon0, "attacking, the same Firelocks lost")
	H.expect(state.armies[attackers.id] == nil or attackers.retreating == true, "and fell back")
	local held = false -- (the infantry may have merged with the raiders that fell back there)
	for _, a in state.armies do
		held = held or (a.owner == enemy and a.location == away and not a.retreating)
	end
	H.expect(held and state.provinces[away].owner == enemy, "the defending Footmen hold their province")
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, away), true)
	Emulator.run(1.5)
	H.shot(alice, "archers_attack")

	-- another race's sheet: the Orcs' five, most of them for 750 manpower
	nation.race = "Orcs"
	Emulator.run(1.5)
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	for _, troop in Troops.roster("Orcs") do
		H.expect(H.button(alice, "Recruit_" .. troop) ~= nil, "Orcs recruit " .. Troops.name(troop))
	end
	H.expect(Emulator.findText(alice, "Ironguard") == nil, "and no Dwarven troop")
	H.expect(Emulator.findText(alice, "750") ~= nil, "for 750 manpower")
	H.shot(alice, "orc_buttons")

	-- the longest troop names (the Lizardfolk's "Crocodile guard", "Swamp stalkers") take a smaller caption
	nation.race = "Lizardfolk"
	Emulator.run(1.5)
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	local guard = H.button(alice, "Recruit_CrocodileGuard")
	local footmen = H.button(alice, "Recruit_Scaleguards")
	H.expect(
		guard ~= nil and footmen ~= nil and guard.TextSize < footmen.TextSize,
		"Crocodile guard's caption is set smaller than Scaleguards'"
	)
	H.shot(alice, "lizardfolk_buttons")
end

return {
	lobby = true, -- the draft shows every nation's race
	run = run,
}
