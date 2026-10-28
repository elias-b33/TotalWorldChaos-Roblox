--!strict
-- Bots at sea (docs/DESIGN.md "Bot AI" and "Navies"): ships only for land no route reaches, the gold share and the
-- difficulty knobs, embarking and landing, staying clear of stronger fleets (only those Navy.visible shows),
-- contesting blockades, blockading besieged coasts, gathering spare fleets, and war declared across the sea.
local Army = require("../src/shared/Sim/Army")
local Bot = require("../src/shared/Sim/Bot")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Economy = require("../src/shared/Sim/Economy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Navy = require("../src/shared/Sim/Navy")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

type MatchState = Types.MatchState
type Command = Types.Command

Config.Battle.RandomSpread = 0 -- deterministic battles in this file

local sky = Maps.get("skyshards")
local byName: { [string]: number } = {}
for _, p in sky.provinces do
	byName[p.name] = p.id
end
local function id(name: string): number
	return assert(byName[name], "no province " .. name)
end

local AURORA, ZEPHYR, UMBRA = 1, 2, 10
local VEGA, LYRA, POLARIS = 1, 2, 10 -- the space zones round Aurora, Zephyr and Umbra

local function find(commands: { Command }, kind: string): Command?
	for _, c in commands do
		if c.kind == kind then
			return c
		end
	end
	return nil
end

local function plan(state: MatchState, nationId: number, difficulty: Bot.Difficulty?): { Command }
	return Bot.plan(state, nationId, Rng.new(1), difficulty or "Normal")
end

-- Every neutral province but `keep` becomes Umbra's, and only `keep`'s garrison stays.
local function umbraTakesTheRest(state: MatchState, keep: number?)
	for armyId, a in state.armies do
		if a.location ~= keep then
			state.armies[armyId] = nil
		end
	end
	for pid, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" and pid ~= keep then
			p.owner = UMBRA
		end
	end
end

-- Peace on Skyshards with every neutral province Umbra's but Zephyr Approach (its garrison stays, 1,000 men).
-- Aurora's 7,000 men can walk nowhere new (Zephyr and Umbra are at peace with it); Zephyr Approach is a coast of the
-- next space zone.
local function island(): MatchState
	local state = Match.new(sky)
	local target = id("Zephyr Approach")
	umbraTakesTheRest(state, target)
	for _, a in state.armies do
		Army.setTroops(a, { Infantry = Config.NeutralGarrison })
	end
	state.tick = 10
	state.nations[AURORA].gold = 1000
	Army.spawn(state, AURORA, id("Aurora Gate"), 7000)
	return state
end

-- The War phase, and `a` at war with `b` (whether or not they could declare it) unless they are the same.
local function war(state: MatchState, a: number, b: number)
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	if a ~= b then
		state.wars[1] = { id = 1, attackers = { a }, defenders = { b }, startedAt = state.tick }
	end
end

local function loaded(state: MatchState, owner: number, zone: number, ships: number, men: number): Types.Fleet
	local fleet = Navy.spawn(state, owner, zone, ships)
	Navy.setCargo(fleet, { Infantry = men })
	return fleet
end

-- Ships ------------------------------------------------------------------------------------------------------------

T.test("no route by land: ships at the army's nearest port, as many as the gold share allows", function()
	local state = island()
	local c = plan(state, AURORA)[1]
	T.equal(c and c.kind, "BuildShips")
	if c and c.kind == "BuildShips" then
		T.equal(c.province, id("Aurora Gate"), "the army stands on a coast: its own port")
		local income = Economy.monthlyIncome(state, AURORA).gold
		local share = math.floor(Config.Bots.Normal.navyGoldShare * income)
		T.expect(share >= 1 and share < 7, "the share is the limit here (" .. share .. ")")
		T.equal(c.ships, math.min(Config.Bots.Normal.fleetShips, share), "ships within the gold share")
	end
end)

T.test("difficulty knobs: Easy spends a smaller share on ships, Hard a bigger one", function()
	local function ships(difficulty: Bot.Difficulty): number
		local c = find(plan(island(), AURORA, difficulty), "BuildShips")
		return if c and c.kind == "BuildShips" then c.ships else 0
	end
	local easy, normal, hard = ships("Easy"), ships("Normal"), ships("Hard")
	T.expect(easy >= 1 and easy < normal and normal < hard, string.format("%d < %d < %d", easy, normal, hard))
	T.expect(hard <= Config.Bots.Hard.fleetShips, "at most fleetShips for one landing")
end)

T.test("land my armies can walk to: they march, no ships", function()
	local state = island()
	state.provinces[id("Aurora Approach")].owner = nil -- now a neutral neighbour (with no garrison)
	local commands = plan(state, AURORA)
	T.equal(find(commands, "BuildShips"), nil, "no ships")
	T.equal(commands[1] and commands[1].kind, "Move")
end)

T.test("ships keep the upkeep reserve: no gold to spare, no ships", function()
	local state = island()
	state.nations[AURORA].gold = Config.Bots.UpkeepReserveMonths * Economy.upkeep(state, AURORA) + 10
	T.equal(find(plan(state, AURORA), "BuildShips"), nil)
end)

T.test(
	"a spare fleet sails to the port instead of new ships, and the army embarks once enough ships are there",
	function()
		local state = island()
		local fleet = Navy.spawn(state, AURORA, POLARIS, 3)
		local commands = plan(state, AURORA)
		local sail = find(commands, "Sail")
		T.expect(sail ~= nil and sail.kind == "Sail" and sail.fleet == fleet.id and sail.zone == VEGA, "sails to Vega")
		T.equal(find(commands, "BuildShips"), nil, "no new ships while it has enough")
		fleet.zone, fleet.path = VEGA, {}
		local embark = plan(state, AURORA)[1]
		T.expect(embark and embark.kind == "Embark" and embark.fleet == fleet.id, "the army embarks")
	end
)

T.test("the whole landing: ships, embark, sail, land, and the landed army takes the coast", function()
	local state = island()
	for nationId, nation in state.nations do
		if nationId ~= AURORA then
			nation.controller = "Player" -- only Aurora plans
		end
	end
	local target = id("Zephyr Approach")
	local battleRng, botRng = Rng.new(1), Rng.new(2)
	local schedule = Bot.newSchedule()
	local queue: { Bot.Order } = {}
	local seen: { [string]: boolean } = {}
	local rejected = 0
	for _ = 1, 200 do
		for _, order in queue do
			if not Commands.apply(state, order.nation, order.command) then
				rejected += 1
			end
		end
		Tick.advance(state, battleRng)
		for _, e in state.events do
			seen[e.kind] = true
		end
		table.clear(state.events)
		queue = Bot.step(schedule, state, botRng, "Normal")
		if state.provinces[target].owner == AURORA then
			break
		end
	end
	T.equal(rejected, 0, "rejected commands")
	T.expect(seen.Landed, "the army landed") -- (3,000 of its 7,000 men boarded: no "Embarked", the rest stay)
	T.equal(state.provinces[target].owner, AURORA, "Zephyr Approach taken from the sea")
end)

-- Fleets at sea ------------------------------------------------------------------------------------------------

-- At war with Zephyr, every neutral province Umbra's, no armies: Aurora's 3 ships with 3,000 men in Vega and a
-- Zephyr fleet of `zephyrShips` in Lyra (Zephyr's only zone).
local function landingCase(zephyrShips: number): (MatchState, Types.Fleet)
	local state = Match.new(sky)
	umbraTakesTheRest(state, nil)
	war(state, AURORA, ZEPHYR)
	local fleet = loaded(state, AURORA, VEGA, 3, 3000)
	Navy.spawn(state, ZEPHYR, LYRA, zephyrShips)
	return state, fleet
end

local function landsOn(commands: { Command }, fleet: Types.Fleet): number?
	local c = find(commands, "Land")
	return if c and c.kind == "Land" and c.fleet == fleet.id then c.province else nil
end

T.test("men aboard land where they win, never past a stronger fleet (home instead)", function()
	local state, fleet = landingCase(1)
	local at = landsOn(plan(state, AURORA), fleet)
	T.expect(at and state.provinces[at].owner == ZEPHYR, "lands on Zephyr past its single ship")
	state, fleet = landingCase(5)
	at = landsOn(plan(state, AURORA), fleet)
	T.expect(at and state.provinces[at].owner == AURORA, "five Zephyr ships in the way: lands at home")
end)

T.test("bots reckon only with the fleets Navy.visible shows them", function()
	local state, fleet = landingCase(5)
	local visible = Navy.visible
	Navy.visible = function(_s: MatchState, viewer: number, f: Types.Fleet): boolean
		return not (viewer == AURORA and f.owner == ZEPHYR)
	end
	local ok, at = pcall(function()
		return landsOn(plan(state, AURORA), fleet)
	end)
	Navy.visible = visible
	T.expect(ok, tostring(at))
	T.expect(at and state.provinces[at].owner == ZEPHYR, "it doesn't see the five ships, so it sails")
end)

T.test("a fleet contests a blockade of my coast only when it beats the blockaders", function()
	local function contest(zephyrShips: number): boolean
		local state = Match.new(sky)
		umbraTakesTheRest(state, nil)
		war(state, AURORA, ZEPHYR)
		Navy.spawn(state, ZEPHYR, VEGA, zephyrShips)
		local mine = Navy.spawn(state, AURORA, LYRA, 3) -- off Zephyr's coast: it would stay to blockade
		Navy.blockades(state)
		T.equal(state.provinces[id("Aurora Landing")].blockade, ZEPHYR, "Aurora's coast is blockaded")
		local c = find(plan(state, AURORA), "Sail")
		return c ~= nil and c.kind == "Sail" and c.fleet == mine.id and c.zone == VEGA
	end
	T.equal(contest(1), true, "3 ships sail against 1")
	T.equal(contest(3), false, "3 ships stay away from 3")
end)

T.test("an empty fleet blockades the enemy coast my army besieges", function()
	local state = Match.new(sky)
	umbraTakesTheRest(state, nil)
	war(state, AURORA, ZEPHYR)
	Army.spawn(state, AURORA, id("Zephyr Landing"), 3000)
	local fleet = Navy.spawn(state, AURORA, POLARIS, 2)
	Tick.advance(state, Rng.new(1)) -- the siege starts
	T.expect(state.provinces[id("Zephyr Landing")].siege ~= nil, "Aurora besieges Zephyr Landing")
	local c = find(plan(state, AURORA), "Sail")
	T.expect(c and c.kind == "Sail" and c.fleet == fleet.id and c.zone == LYRA, "sails off the besieged coast")
end)

T.test("spare fleets gather at the home port", function()
	local state = Match.new(sky)
	state.tick = 10
	local a = Navy.spawn(state, AURORA, LYRA, 1)
	local b = Navy.spawn(state, AURORA, POLARIS, 2)
	local sails: { [number]: number } = {}
	for _, c in plan(state, AURORA) do
		if c.kind == "Sail" then
			sails[c.fleet] = c.zone
		end
	end
	T.equal(sails[a.id], VEGA, "the fleet in Lyra sails home")
	T.equal(sails[b.id], VEGA, "the fleet in Polaris sails home")
end)

-- War across the sea ---------------------------------------------------------------------------------------------

T.test("nobody to fight by land: war on a nation across a shared sea", function()
	local earth = Maps.get("earth")
	local state = Match.new(earth)
	local MISSISSIPPI, AMAZON = 9, 10
	for armyId in state.armies do
		state.armies[armyId] = nil
	end
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			p.owner = AMAZON
		end
	end
	war(state, MISSISSIPPI, MISSISSIPPI)
	for nationId in state.nations do
		if nationId ~= MISSISSIPPI and Diplomacy.borders(state, MISSISSIPPI, nationId) then
			table.insert(state.truces, { a = MISSISSIPPI, b = nationId, untilTick = math.huge })
		end
	end
	state.nations[MISSISSIPPI].gold = 1000
	Army.spawn(state, MISSISSIPPI, state.nations[MISSISSIPPI].capital, 7000)
	local c = find(plan(state, MISSISSIPPI), "Diplomacy")
	T.expect(c and c.kind == "Diplomacy" and c.action == "War", "declares war")
	if c and c.kind == "Diplomacy" then
		T.expect(not Diplomacy.borders(state, MISSISSIPPI, c.target), "on a nation it doesn't border by land")
		T.expect(Diplomacy.sharesSea(state, MISSISSIPPI, c.target), "but shares a sea with")
	end
end)

T.finish()
