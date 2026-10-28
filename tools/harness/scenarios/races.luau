--!nocheck
-- Races and troops (docs/DESIGN.md "Races", "Troops"). The draft shows every nation's race and the tapped one's
-- bonus, and picking Ironholds makes Alice the Dwarves; the nations drawer shows the races; the province sheet
-- recruits each troop the Dwarves can raise into one army whose sheet shows the composition; the server refuses
-- another race's elite; Ironguard besiege faster than infantry; and archers win a battle defending that they lose
-- attacking.

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

	-- the province sheet: one recruit button per troop the Dwarves raise, each with its price
	local nation = state.nations[me]
	nation.gold, nation.manpower = 1000, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	H.expect(
		Emulator.findText(alice, "Ironguard") ~= nil and Emulator.findText(alice, "Knights") == nil,
		"Infantry, Archers, Cavalry and Ironguard, no other race's elite"
	)
	H.shot(alice, "recruit_buttons")
	local t = Config.Troops
	for _, button in { "Regiment", "Archers", "Cavalry", "Ironguard" } do
		Emulator.press(alice, button)
		Emulator.run(1.2)
	end
	local army = Army.idleAt(state, me, nation.capital)
	H.expect(army ~= nil and army.men == 4000, "the four regiments make one army")
	H.expect(
		army.troops.Infantry == 1000
			and army.troops.Archers == 1000
			and army.troops.Cavalry == 1000
			and army.troops.Ironguard == 1000,
		"one regiment of each troop type"
	)
	H.expect(
		nation.gold == 1000 - t.Infantry.gold - t.Archers.gold - t.Cavalry.gold - t.Ironguard.gold,
		"each at its own price"
	)
	-- on the map: a dwarf soldier, and a badge with its main troop's icon (four equal regiments: the dearest, and of
	-- cavalry and ironguard at the same price, the elite); the province sheet's chips say the same, and its owner chip
	-- shows the Dwarves
	local sprite = H.mapObject(alice, "Army" .. army.id) and H.mapObject(alice, "Army" .. army.id):FindFirstChild("TokenSkin")
	H.expect(sprite ~= nil and sprite:GetAttribute("Soldier") == "Dwarves", "Alice's army is a dwarf soldier on the map")
	H.expect(select(2, H.badge(alice, army.id)) == "ironguard", "its badge shows the Ironguard: equal men, the dearest troop")
	H.expect(H.iconIn(alice, "ArmyChip" .. army.id, "ironguard"), "so does its chip on the province sheet")
	H.expect(H.iconIn(alice, "Owner", "dwarves"), "the owner chip shows the Dwarves' icon")

	-- the army sheet shows the composition as chips
	Emulator.press(alice, "Move")
	Emulator.run(0.5)
	for _, troop in { "Infantry", "Archers", "Cavalry", "Ironguard" } do
		H.expect(Emulator.findText(alice, "1k " .. troop) ~= nil, "the army sheet shows 1k " .. troop)
	end
	H.shot(alice, "army_composition")
	Emulator.press(alice, "Cancel")
	Emulator.run(0.5)

	-- the server refuses another race's elite (the sheet never offers it; a hacked client could still ask)
	H.client(alice, "Intents").recruit(nation.capital, 1, "Knights")
	Emulator.run(1.2)
	H.expect(Emulator.findText(alice, "Only its own race can recruit that troop") ~= nil, "the refusal toast")
	H.expect(army.troops.Knights == nil and army.men == 4000, "and no knights joined")
	H.shot(alice, "refused_elite")

	-- Ironguard besiege faster (Config.Troops.Ironguard.siegeSpeed): Alice's Ironguard and her infantry each besiege
	-- a neutral province of the same development (garrisons gone); the Ironguard's falls first
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
	Army.spawn(state, me, fastId, 1000, "Ironguard")
	Army.spawn(state, me, slowId, 1000) -- infantry
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, fastId), true)
	Emulator.run(8)
	local fast, slow = state.provinces[fastId].siege, state.provinces[slowId].siege
	H.expect(fast ~= nil and slow ~= nil, "both sieges are running")
	H.expect(
		math.abs(fast.progress - t.Ironguard.siegeSpeed * slow.progress) < 1e-9,
		string.format("Ironguard %.2f vs infantry %d after the same seconds", fast.progress, slow.progress)
	)
	H.shot(alice, "ironguard_siege")
	deadline = Emulator.now() + required
	while state.provinces[fastId].owner ~= me and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[fastId].owner == me, "the Ironguard took their province")
	H.expect(state.provinces[slowId].owner == nil, "while the infantry's siege still runs")
	deadline = Emulator.now() + required
	while state.provinces[slowId].owner ~= me and Emulator.now() < deadline do
		Emulator.run(1)
	end
	H.expect(state.provinces[slowId].owner == me, "the infantry's province falls later")

	-- a battle where troop types matter: 3,000 archers holding Alice's plains province beat 3,000 attacking infantry;
	-- the same archers attacking the enemy's plains province lose to 3,000 defending infantry
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
	state.nations[enemy].race = "Humans" -- no forest or hills bonus could decide it anyway, on plains
	state.wars[999] = { id = 999, attackers = { me }, defenders = { enemy }, startedAt = state.tick }
	H.expect(Diplomacy.atWar(state, me, enemy), "Alice is at war with " .. state.nations[enemy].name)
	local function fight(where: number, archerSide: number, infantrySide: number)
		for id, a in state.armies do
			if a.location == where then
				state.armies[id] = nil
			end
		end
		local archers = Army.spawn(state, archerSide, where, 3000, "Archers")
		local infantry = Army.spawn(state, infantrySide, where, 3000)
		return archers, infantry
	end
	local won0 = nation.battlesWon
	local holders, raiders = fight(home, me, enemy)
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, home), true)
	Emulator.run(1.5)
	H.shot(alice, "archers_hold")
	Emulator.run(3)
	H.expect(nation.battlesWon == won0 + 1, "defending, the archers won")
	H.expect(state.armies[raiders.id] == nil or raiders.retreating == true, "the infantry was beaten off")
	H.expect(state.armies[holders.id] ~= nil and holders.men > raiders.men, "the archers kept more men")
	Emulator.run(1)
	H.expect(select(2, H.badge(alice, holders.id)) == "archers", "the archers' badge shows the bow once the battle is over")
	local enemyWon0 = state.nations[enemy].battlesWon
	local attackers = fight(away, me, enemy)
	Emulator.run(4.5)
	-- (the enemy is a bot at war: it may win other battles meanwhile, so count at least this one)
	H.expect(state.nations[enemy].battlesWon > enemyWon0, "attacking, the same archers lost")
	H.expect(state.armies[attackers.id] == nil or attackers.retreating == true, "and fell back")
	local held = false -- (the infantry may have merged with the raiders that fell back there)
	for _, a in state.armies do
		held = held or (a.owner == enemy and a.location == away and not a.retreating)
	end
	H.expect(held and state.provinces[away].owner == enemy, "the defending infantry holds its province")
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, away), true)
	Emulator.run(1.5)
	H.shot(alice, "archers_attack")

	-- another race's sheet: an Orc nation's elite is the Berserkers (750 manpower)
	nation.race = "Orcs"
	Emulator.run(1.5)
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "Berserkers") ~= nil and Emulator.findText(alice, "Ironguard") == nil, "Orcs recruit Berserkers")
	H.expect(Emulator.findText(alice, "750") ~= nil, "for 750 manpower")
	H.shot(alice, "orc_buttons")
end

return {
	lobby = true, -- the draft shows every nation's race
	run = run,
}
