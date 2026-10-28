--!strict
-- Smarter PvP (docs/DESIGN.md "Troops", "Armies and combat"): troop counters, morale and flanking, on Skyshards.
local Army = require("../src/shared/Sim/Army")
local Battle = require("../src/shared/Sim/Battle")
local Bot = require("../src/shared/Sim/Bot")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Movement = require("../src/shared/Sim/Movement")
local Rng = require("../src/shared/Sim/Rng")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Troops = require("../src/shared/Sim/Troops")
local Types = require("../src/shared/Types")

Config.Battle.RandomSpread = 0 -- deterministic battles in this file
Battle.bonus = function()
	return 0 -- no catch-up bonuses: the numbers below are the rules alone
end

local map = Maps.get("skyshards")
local byName: { [string]: number } = {}
for _, p in map.provinces do
	byName[p.name] = p.id
end
local function id(name: string): number
	return assert(byName[name], "no province " .. name)
end

local AURORA, ZEPHYR = 1, 2
local FIELD = id("Cinder Reach") -- plains, between Cinder Rock and Zephyr Leeward
local WEST, EAST = id("Cinder Rock"), id("Zephyr Leeward")
local MAX = Config.Battle.MoraleMax

-- Aurora and Zephyr at war, no armies anywhere, the field Zephyr's plain land without a building.
local function atWar(): (Types.MatchState, Rng.Rng)
	local state = Match.new(map)
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	for armyId in state.armies do
		state.armies[armyId] = nil
	end
	state.provinces[WEST].owner = AURORA
	state.provinces[FIELD].owner = ZEPHYR
	state.provinces[FIELD].terrain = "Plains"
	state.provinces[FIELD].building = "None"
	state.provinces[EAST].terrain = "Plains"
	assert(Diplomacy.declareWar(state, AURORA, ZEPHYR))
	return state, Rng.new(1)
end

local function run(state: Types.MatchState, rng: Rng.Rng, ticks: number)
	for _ = 1, ticks do
		Tick.advance(state, rng)
	end
end

local function lastBattle(state: Types.MatchState): Types.MatchEvent?
	local found = nil
	for _, e in state.events do
		if e.kind == "BattleEnded" then
			found = e
		end
	end
	return found
end

-- Counters ------------------------------------------------------------------------------------------------

T.test(
	"the counter cycle: ranged beats line, line beats fast, fast beats ranged; elite and special are neutral",
	function()
		local allLine = Troops.roleShares({ Infantry = 3000 })
		local bonus, penalty = Config.Battle.CounterBonus, Config.Battle.CounterPenalty
		T.near(Troops.counter("ranged", allLine), 1 + bonus, 1e-9, "archers on infantry")
		T.near(Troops.counter("line", allLine), 1, 1e-9, "infantry on infantry")
		T.near(Troops.counter("fast", allLine), 1 - penalty, 1e-9, "cavalry on infantry")
		T.near(Troops.counter("elite", allLine), 1, 1e-9)
		T.near(Troops.counter("special", allLine), 1, 1e-9)
		local allRanged = Troops.roleShares({ Archers = 2000 })
		T.near(Troops.counter("fast", allRanged), 1 + bonus, 1e-9, "cavalry on archers")
		T.near(Troops.counter("line", allRanged), 1 - penalty, 1e-9, "infantry on archers")
		local allFast = Troops.roleShares({ Cavalry = 2000 })
		T.near(Troops.counter("line", allFast), 1 + bonus, 1e-9, "infantry on cavalry")
		T.near(Troops.counter("ranged", allFast), 1 - penalty, 1e-9, "archers on cavalry")
		-- the share of the enemy's men counts: a quarter archers is a quarter of the bonus
		local mixed = Troops.roleShares({ Infantry = 3000, Archers = 1000 })
		T.near(mixed.line, 0.75, 1e-9)
		T.near(Troops.counter("fast", mixed), 1 + bonus * 0.25 - penalty * 0.75, 1e-9)
		-- elites and specials in the enemy's army dilute the shares: they count as men nothing beats
		local withElite = Troops.roleShares({ Infantry = 1000, Knights = 1000 })
		T.near(Troops.counter("ranged", withElite), 1 + bonus * 0.5, 1e-9)
	end
)

T.test("a mixed army is safe, a one-troop army can be punished", function()
	local mixed: Types.Composition = { Infantry = 1000, Archers = 1000, Cavalry = 1000 }
	local mixedShares = Troops.roleShares(mixed)
	for _, role in { "line", "ranged", "fast" } :: { Types.TroopRole } do
		T.near(Troops.counter(role, mixedShares), 1, 1e-9, role .. " against a mixed army")
	end
	-- against any one-troop army the mixed army's men average no counter at all, and its strength stays near what it
	-- is without counters (the troops' attacks differ, so not exactly)
	for _, enemy in { { Infantry = 3000 }, { Archers = 3000 }, { Cavalry = 3000 } } :: { Types.Composition } do
		local shares = Troops.roleShares(enemy)
		local sum = 0
		for troop, n in mixed do
			sum += n * Troops.counter(Troops.stats(troop).role, shares)
		end
		T.near(sum / 3000, 1, 1e-9, "the average counter of a mixed army")
		local plain = Troops.strength(mixed, false, nil, false)
		T.near(Troops.strength(mixed, false, nil, false, enemy), plain, 0.1 * plain, "within 10%")
	end
	-- archers alone against cavalry alone: each archer deals 25% less, each rider 25% more
	local archers: Types.Composition = { Archers = 3000 }
	local riders: Types.Composition = { Cavalry = 3000 }
	T.near(
		Troops.strength(archers, true, nil, false, riders),
		3000 * Troops.stats("Archers").defence * (1 - Config.Battle.CounterPenalty),
		1e-6
	)
	T.near(
		Troops.strength(riders, false, nil, false, archers),
		3000 * Troops.stats("Cavalry").attack * (1 + Config.Battle.CounterBonus),
		1e-6
	)
end)

T.test("a battle round applies the counters: archers holding against infantry kill more", function()
	local state, rng = atWar()
	local defenders = Army.spawn(state, ZEPHYR, FIELD, 3000, "Archers")
	local attackers = Army.spawn(state, AURORA, FIELD, 3000, "Infantry")
	run(state, rng, 1)
	local rate = Config.Battle.KillRatePerRound
	local defKills = 3000 * Troops.stats("Archers").defence * (1 + Config.Battle.CounterBonus) * rate
	local attKills = 3000 * Troops.stats("Infantry").attack * (1 - Config.Battle.CounterPenalty) * rate
	T.equal(attackers.men, math.floor(3000 - defKills + 0.5))
	T.equal(defenders.men, math.floor(3000 - attKills + 0.5))
end)

-- Morale --------------------------------------------------------------------------------------------------

T.test("new armies start with full morale; a round costs MoraleShock × the share lost + MoraleDrain", function()
	local state, rng = atWar()
	local d = Army.spawn(state, ZEPHYR, FIELD, 4000, "Infantry")
	local a = Army.spawn(state, AURORA, FIELD, 4000, "Infantry")
	T.equal(a.morale, MAX)
	T.equal(d.morale, MAX)
	run(state, rng, 1)
	-- each side lost 15% of its men: 150 × 0.15 + 5 = 27.5, rounded
	local drop = Battle.moraleDrop(600, 4000)
	T.equal(drop, math.floor(Config.Battle.MoraleShock * 0.15 + Config.Battle.MoraleDrain + 0.5))
	T.equal(a.morale, MAX - drop)
	T.equal(d.morale, MAX - drop)
	T.expect(state.battles[FIELD] ~= nil, "an even fight goes on")
end)

T.test("a side whose morale breaks retreats at once, even before round 3 and with more men", function()
	local state, rng = atWar()
	local tired = Army.spawn(state, AURORA, FIELD, 3500, "Infantry")
	tired.morale = 30
	local fresh = Army.spawn(state, ZEPHYR, FIELD, 3000, "Infantry")
	run(state, rng, 1)
	T.expect(state.battles[FIELD] ~= nil, "round 1: still fighting")
	run(state, rng, 1)
	local e = assert(lastBattle(state), "the battle ended in round 2")
	T.equal(e.a, ZEPHYR, "the fresh side won")
	T.equal(e.b, AURORA)
	T.equal(e.broke, true, "the loser broke")
	T.equal(e.outnumbered, true, "the winner had fewer men")
	T.expect(tired.retreating == true, "the broken army walks home")
	T.expect(tired.men > fresh.men, "with more men than the winner")
end)

T.test("a fresh army beats a tired one of the same size, attacking or defending", function()
	for _, tiredAttacks in { true, false } do
		local state, rng = atWar()
		local tired = Army.spawn(state, if tiredAttacks then AURORA else ZEPHYR, FIELD, 3000, "Infantry")
		tired.morale = 60
		Army.spawn(state, if tiredAttacks then ZEPHYR else AURORA, FIELD, 3000, "Infantry")
		run(state, rng, Config.Battle.Rounds)
		local e = assert(lastBattle(state), "the battle is over")
		T.equal(e.b, tired.owner, "the tired army lost")
		T.equal(e.broke, true)
	end
end)

T.test("Battle.outcome plays a battle out like Battle.step", function()
	local state, rng = atWar()
	local d = Army.spawn(state, ZEPHYR, FIELD, 3000, "Archers")
	local a = Army.spawn(state, AURORA, FIELD, 4200, "Infantry")
	a.morale = 80
	local sides = assert(Battle.sides(state, FIELD, { d, a }))
	local function fighter(side: { Types.Army }, defending: boolean, enemy: { Types.Army }): Battle.Fighter
		local s = Battle.strength(side, defending, "Plains", false, Battle.composition(enemy))
		local m = side[1].men
		return {
			men = m,
			rate = s * Battle.modifier(state, FIELD, sides, defending, 0) * Config.Battle.KillRatePerRound / m,
			morale = Battle.morale(side),
		}
	end
	local attackerWins = Battle.outcome(
		fighter(sides.attackers, false, sides.defenders),
		fighter(sides.defenders, true, sides.attackers),
		false
	)
	local defenderWins = Battle.outcome(
		fighter(sides.defenders, true, sides.attackers),
		fighter(sides.attackers, false, sides.defenders),
		true
	)
	T.expect(attackerWins ~= defenderWins, "one side wins")
	run(state, rng, Config.Battle.Rounds)
	local e = assert(lastBattle(state) or nil, "the battle is over")
	T.equal(e.a == AURORA, attackerWins, "the prediction matches the battle")
end)

T.test("morale recovers out of battle in steps: faster on its own land", function()
	local state, rng = atWar()
	local home = Army.spawn(state, AURORA, WEST, 2000)
	local abroad = Army.spawn(state, AURORA, EAST, 2000) -- Zephyr's land, nobody there to fight
	home.morale, abroad.morale = 20, 20
	-- only on every MoraleRecoverTicks-th tick, so a resting army's record changes once in that many ticks
	local every = Config.Battle.MoraleRecoverTicks
	state.tick = every * 10 + 1
	run(state, rng, every - 2)
	T.equal(home.morale, 20, "no change between steps")
	run(state, rng, 1)
	T.equal(home.morale, 20 + Config.Battle.MoraleRecoverHome, "a step on its own land")
	T.equal(abroad.morale, 20 + Config.Battle.MoraleRecoverAbroad, "a smaller step abroad")
	run(state, rng, every * 20)
	T.equal(home.morale, MAX, "full at most")
end)

T.test("regiments joining an army and merging stacks average the morale by men", function()
	local state, rng = atWar()
	local army = Army.spawn(state, AURORA, WEST, 3000)
	army.morale = 20
	Army.reinforce(state, AURORA, WEST, 1000) -- new regiments come in fresh
	T.equal(army.men, 4000)
	T.equal(army.morale, math.floor((3000 * 20 + 1000 * MAX) / 4000 + 0.5))
	local other = Army.spawn(state, AURORA, WEST, 2000)
	other.morale = 50
	local before = army.morale
	Movement.mergeStacks(state)
	T.equal(state.armies[other.id], nil, "merged into the lower id")
	T.equal(army.men, 6000, "the men add up")
	T.equal(army.morale, math.floor((4000 * before + 2000 * 50) / 6000 + 0.5), "the morale: the average by men")
	-- an army arriving from a neighbour merges a tick later, once it has settled
	local walker = Army.spawn(state, AURORA, id("Aurora Landing"), 1000)
	assert(Movement.order(state, AURORA, walker.id, WEST))
	local deadline = 30
	while walker.location ~= WEST and deadline > 0 do
		run(state, rng, 1)
		deadline -= 1
	end
	T.expect(state.armies[walker.id] ~= nil, "not on the tick it arrives")
	run(state, rng, 1)
	T.equal(state.armies[walker.id], nil, "merged once settled")
end)

-- Flanking ------------------------------------------------------------------------------------------------

T.test("an army remembers the province it stepped in from until it settles", function()
	local state, rng = atWar()
	local army = Army.spawn(state, AURORA, WEST, 2000)
	T.equal(army.from, nil, "a new army counts where it stands")
	assert(Movement.order(state, AURORA, army.id, id("Aurora Landing")))
	local deadline = 40
	while army.location == WEST and deadline > 0 do
		run(state, rng, 1)
		deadline -= 1
	end
	T.equal(army.from, WEST, "it came from Cinder Rock")
	while #army.path > 0 and deadline > 0 do
		run(state, rng, 1)
		deadline -= 1
	end
	run(state, rng, 1)
	T.equal(army.from, nil, "standing still out of battle: settled")
end)

T.test("armies from two directions flank: +FlankBonus per extra direction, capped", function()
	local state = atWar()
	local d = Army.spawn(state, ZEPHYR, FIELD, 3000)
	local a1 = Army.spawn(state, AURORA, FIELD, 1500)
	local a2 = Army.spawn(state, AURORA, FIELD, 1500)
	a1.from, a2.from = WEST, WEST
	local sides = assert(Battle.sides(state, FIELD, { d, a1, a2 }))
	T.equal(Battle.directions(sides.attackers), 1)
	T.equal(Battle.directions(sides.defenders), 1, "the defender at home counts its province")
	T.near(Battle.modifier(state, FIELD, sides, false, 0), 1, 1e-9, "one direction: no flank")
	a2.from = EAST
	T.equal(Battle.directions(sides.attackers), 2)
	T.near(Battle.modifier(state, FIELD, sides, false, 0), 1 + Config.Battle.FlankBonus, 1e-9, "two directions")
	T.near(Battle.flankBonus(9), Config.Battle.FlankBonus * Config.Battle.FlankMaxExtra, 1e-9, "capped")
	-- an ally arriving from a neighbour gives the defenders a second direction too
	local d2 = Army.spawn(state, ZEPHYR, FIELD, 1000)
	d2.from = EAST
	local sides2 = assert(Battle.sides(state, FIELD, { d, d2, a1, a2 }))
	T.equal(Battle.directions(sides2.defenders), 2)
end)

T.test("two stacks marching in from two sides arrive together and a flank decides the battle", function()
	local function fight(twoSides: boolean): Types.MatchEvent
		local state, rng = atWar()
		state.provinces[EAST].owner = AURORA
		Army.spawn(state, ZEPHYR, FIELD, 3100, "Infantry") -- a little more than both stacks together
		local a1 = Army.spawn(state, AURORA, WEST, 1500, "Infantry")
		local a2 = Army.spawn(state, AURORA, if twoSides then EAST else WEST, 1520, "Infantry")
		assert(Movement.order(state, AURORA, a1.id, FIELD))
		assert(Movement.order(state, AURORA, a2.id, FIELD))
		local deadline = 30
		while state.battles[FIELD] == nil and deadline > 0 do
			run(state, rng, 1)
			deadline -= 1
		end
		T.expect(a1.inBattle and a2.inBattle, "both arrived on the same tick")
		run(state, rng, Config.Battle.Rounds)
		return assert(lastBattle(state) or nil)
	end
	local alone = fight(false)
	T.equal(alone.a, ZEPHYR, "from one side the defender holds")
	local flanked = fight(true)
	T.equal(flanked.a, AURORA, "from two sides the attackers win")
	T.equal(flanked.flank, true, "the flank decided it")
end)

T.test("counters can decide a battle: the event says so", function()
	local state, rng = atWar()
	Army.spawn(state, ZEPHYR, FIELD, 3000, "Cavalry")
	Army.spawn(state, AURORA, FIELD, 2700, "Infantry")
	run(state, rng, Config.Battle.Rounds)
	local e = assert(lastBattle(state) or nil)
	T.equal(e.a, AURORA, "infantry beat the cavalry")
	T.equal(e.counter, true, "the counters decided it")
	T.equal(e.flank, nil)
end)

-- Bots ---------------------------------------------------------------------------------------------------

-- Zephyr holds every province but Aurora's (no garrisons anywhere), at war with Aurora; both are Marines, so their
-- troops are the same: Troopers (line), Gunners (ranged), Hover bikes (fast), Mechs (elite).
local function botWar(): Types.MatchState
	local state = Match.new(map)
	for armyId in state.armies do
		state.armies[armyId] = nil
	end
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			p.owner = ZEPHYR
		end
	end
	state.nations[ZEPHYR].race = state.nations[AURORA].race
	state.nations[AURORA].gold = 0 -- nothing to buy unless a test says so
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	assert(Diplomacy.declareWar(state, AURORA, ZEPHYR))
	return state
end

local function movesTo(commands: { Types.Command }, to: number): { number }
	local armies = {}
	for _, c in commands do
		if c.kind == "Move" and c.to == to then
			table.insert(armies, c.army)
		end
	end
	return armies
end

local WINDWARD = id("Aurora Windward") -- next to Cinder Rock

T.test("bots raise the troop that beats the enemy armies near their land", function()
	for _, case in { { enemy = "Gunners", want = "fast" }, { enemy = "Troopers", want = "ranged" } } do
		local state = botWar()
		state.nations[AURORA].gold = 500
		-- holds the border and wants more men; it has its share of specials and elites already
		local army = Army.spawn(state, AURORA, WINDWARD, 2600, "Troopers")
		Army.add(army, { Artillery = 500, Mechs = 900 })
		Army.spawn(state, ZEPHYR, WEST, 2000, case.enemy)
		local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
		local c = commands[1]
		T.expect(c ~= nil and c.kind == "Recruit", "recruits")
		if c and c.kind == "Recruit" then
			T.equal(Troops.role(c.troop), case.want, "against " .. case.enemy)
		end
	end
end)

T.test("a tired army rests instead of attacking", function()
	local state = botWar()
	local army = Army.spawn(state, AURORA, WINDWARD, 8000, "Troopers")
	Army.spawn(state, ZEPHYR, WEST, 4000, "Troopers")
	T.expect(#movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST) == 1, "rested: it attacks")
	army.morale = Config.Bots.MinAttackMorale - 1
	T.equal(#movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST), 0, "tired: it stays")
end)

T.test("bots attack into a counter only with a bigger margin", function()
	local state = botWar()
	Army.spawn(state, AURORA, WINDWARD, 8000, "Troopers")
	Army.spawn(state, ZEPHYR, WEST, 3000, "Gunners") -- ranged beats line
	local extra = Config.Bots.CounteredExtraRatio
	T.expect(#movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST) == 1, "clearly good odds: it attacks")
	Config.Bots.CounteredExtraRatio = 5
	T.equal(#movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST), 0, "countered: it wants more")
	local edge = Config.Bots.CounterEdge
	Config.Bots.CounterEdge = 10 -- nothing counts as a counter
	T.expect(#movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST) == 1, "the margin is the counter's")
	Config.Bots.CounteredExtraRatio, Config.Bots.CounterEdge = extra, edge
end)

T.test("two stacks that can only take a province together strike it from two sides on the same tick", function()
	local state = botWar()
	state.provinces[FIELD].owner = AURORA -- Cinder Reach: Cinder Rock's other neighbour
	local a = Army.spawn(state, AURORA, WINDWARD, 2000, "Troopers")
	local b = Army.spawn(state, AURORA, FIELD, 2000, "Troopers")
	Army.spawn(state, ZEPHYR, WEST, 3000, "Troopers")
	local both = movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST)
	table.sort(both)
	T.equal(#both, 2, "both stacks march in")
	T.expect(both[1] == a.id and both[2] == b.id, "a and b")
	-- one stack alone doesn't try
	state.armies[b.id] = nil
	T.equal(#movesTo(Bot.plan(state, AURORA, Rng.new(1), "Normal"), WEST), 0)
end)

T.test("two free stacks take up places on two sides of a province first", function()
	local state = botWar()
	state.provinces[FIELD].owner = AURORA
	local a = Army.spawn(state, AURORA, id("Aurora Meadows"), 2000, "Troopers") -- next to Windward
	local b = Army.spawn(state, AURORA, FIELD, 2000, "Troopers")
	Army.spawn(state, ZEPHYR, WEST, 3000, "Troopers")
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.equal(#movesTo(commands, WEST), 0, "not yet")
	T.equal(movesTo(commands, WINDWARD)[1], a.id, "a takes its place next to Cinder Rock")
	T.equal(state.armies[b.id].location, FIELD, "b is in place already")
end)

-- Network -------------------------------------------------------------------------------------------------

T.test("the army record carries its morale", function()
	local state = atWar()
	local army = Army.spawn(state, AURORA, WEST, 2000)
	army.morale = 45
	local snap = Snapshot.full(state)
	local found = nil
	for _, r in snap.armies do
		if r.id == army.id then
			found = r
		end
	end
	T.equal(assert(found).morale, 45)
end)

T.finish()
