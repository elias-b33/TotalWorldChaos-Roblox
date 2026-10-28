--!strict
-- Bot AI (docs/DESIGN.md "Bot AI"): the priority list, difficulties, the schedule, and whole bot-only matches
-- that never send a command the server refuses.
local Army = require("../src/shared/Sim/Army")
local Bot = require("../src/shared/Sim/Bot")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Rng = require("../src/shared/Sim/Rng")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

type MatchState = Types.MatchState

local map = Maps.get("skyshards")
local byName: { [string]: number } = {}
for _, p in map.provinces do
	byName[p.name] = p.id
end
local function id(name: string): number
	return assert(byName[name], "no province " .. name)
end

local AURORA, ZEPHYR, UMBRA = 1, 2, 10

-- The server's loop without Roblox: queued commands, Tick.advance, then bots plan for the next tick.
local function play(state: MatchState, ticks: number?, seed: number?, difficulty: Bot.Difficulty?): (number, number)
	local battleRng, botRng = Rng.new(seed or 1), Rng.new((seed or 1) + 1000)
	local schedule = Bot.newSchedule()
	local queue: { Bot.Order } = {}
	local commands, rejected = 0, 0
	local stopAt = if ticks then state.tick + ticks else math.huge
	while state.result == nil and state.tick < stopAt do
		for _, order in queue do
			commands += 1
			local ok, reason = Commands.apply(state, order.nation, order.command)
			if not ok then
				rejected += 1
				print(
					string.format("       rejected %s for %d: %s", order.command.kind, order.nation, tostring(reason))
				)
			end
		end
		Tick.advance(state, battleRng)
		queue = Bot.step(schedule, state, botRng, difficulty or "Normal")
		table.clear(state.events)
	end
	return commands, rejected
end

local function warPhase(state: MatchState, tick: number?)
	state.tick = tick or Config.Phases.PeaceEndTick
	state.phase = "War"
end

local function removeGarrisons(state: MatchState)
	for armyId, a in state.armies do
		if a.owner == 0 then
			state.armies[armyId] = nil
		end
	end
end

-- Zephyr takes every neutral province, so it is Aurora's only neighbour (through the drift isles and approach).
local function zephyrTakesTheWorld(state: MatchState)
	removeGarrisons(state)
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			p.owner = ZEPHYR
		end
	end
end

local function only(commands: { Types.Command }): Types.Command
	T.equal(#commands >= 1, true, "the bot wanted to do something")
	return commands[1]
end

local function movesInto(state: MatchState, commands: { Types.Command }, owner: number): boolean
	for _, c in commands do
		if c.kind == "Move" and state.provinces[c.to].owner == owner then
			return true
		end
	end
	return false
end

local function declaresWar(commands: { Types.Command }): number?
	for _, c in commands do
		if c.kind == "Diplomacy" and c.action == "War" then
			return c.target
		end
	end
	return nil
end

-- Expand ------------------------------------------------------------------------------------------------

T.test("bots expand into neutral land in Peace", function()
	local state = Match.new(map)
	local neutral0 = 0
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			neutral0 += 1
		end
	end
	local _, rejected = play(state, Config.Phases.PeaceEndTick - 1)
	T.equal(state.phase, "Peace")
	T.equal(next(state.wars), nil, "no wars in Peace")
	T.equal(rejected, 0, "rejected commands")
	local neutral = 0
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			neutral += 1
		end
	end
	T.expect(
		neutral < neutral0 / 2,
		string.format("only %d of %d neutral provinces taken", neutral0 - neutral, neutral0)
	)
	for nationId in state.nations do
		T.expect(Match.provinceCount(state, nationId) > 8, state.nations[nationId].name .. " did not expand")
	end
end)

T.test("an army that can beat a neutral garrison marches on it", function()
	local state = Match.new(map)
	Army.spawn(state, AURORA, id("Aurora Windward"), 7000)
	local c = only(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	T.equal(c.kind, "Move")
	if c.kind == "Move" then
		T.equal(state.provinces[c.to].owner, nil, "the target is neutral")
	end
end)

-- Recruit -----------------------------------------------------------------------------------------------

T.test("bots recruit when below provinces × 800 men, and not above it", function()
	local state = Match.new(map)
	local c = only(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	T.equal(c.kind, "Recruit")
	if c.kind == "Recruit" then
		T.equal(state.provinces[c.province].owner, AURORA)
		T.expect(c.regiments >= 1 and c.regiments <= Config.Bots.RecruitBatch)
	end
	Army.spawn(state, AURORA, state.nations[AURORA].capital, 8 * Config.Bots.MenPerProvince)
	local next = only(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	T.expect(next.kind ~= "Recruit", "recruited with enough men")
end)

T.test("no manpower, no recruit", function()
	local state = Match.new(map)
	state.nations[AURORA].manpower = 0
	for _, c in Bot.plan(state, AURORA, Rng.new(1), "Normal") do
		T.expect(c.kind ~= "Recruit")
	end
end)

-- Defend ------------------------------------------------------------------------------------------------

-- Aurora holds Cinder Rock, Zephyr holds Cinder Reach next to it, they are at war, and a Zephyr army waits there.
local function borderWar(auroraMen: number, zephyrMen: number): MatchState
	local state = Match.new(map)
	warPhase(state)
	state.provinces[id("Cinder Rock")].owner = AURORA
	state.provinces[id("Cinder Reach")].owner = ZEPHYR
	removeGarrisons(state)
	assert(Diplomacy.declareWar(state, ZEPHYR, AURORA))
	if zephyrMen > 0 then
		Army.spawn(state, ZEPHYR, id("Cinder Reach"), zephyrMen)
	end
	if auroraMen > 0 then
		Army.spawn(state, AURORA, id("Aurora Landing"), auroraMen)
	end
	return state
end

T.test("bots defend a threatened border with their nearest army when strong enough", function()
	local state = borderWar(4000, 3000)
	local c = only(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	T.equal(c.kind, "Move")
	if c.kind == "Move" then
		T.equal(c.to, id("Cinder Rock"), "the army goes to the threatened province")
	end
end)

T.test("too weak to defend: recruit where the threat is", function()
	local state = borderWar(1000, 3000)
	local c = only(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	T.equal(c.kind, "Recruit")
	if c.kind == "Recruit" then
		T.equal(c.province, id("Cinder Rock"))
		T.expect(c.regiments >= 2, "recruits enough to stand")
	end
end)

T.test("an enemy army inside my land comes first", function()
	local state = borderWar(5000, 2000)
	Army.spawn(state, ZEPHYR, id("Aurora Fields"), 2500)
	local c = only(Bot.plan(state, AURORA, Rng.new(1), "Normal"))
	T.equal(c.kind, "Move")
	if c.kind == "Move" then
		T.equal(c.to, id("Aurora Fields"))
	end
end)

-- Attack ------------------------------------------------------------------------------------------------

local function attackSetup(zephyrMen: number): MatchState
	local state = Match.new(map)
	zephyrTakesTheWorld(state)
	state.nations[AURORA].gold = 0 -- nothing to buy, so only movement and diplomacy are left
	Army.spawn(state, AURORA, id("Aurora Windward"), 8000)
	Army.spawn(state, ZEPHYR, id("Cinder Rock"), zephyrMen)
	return state
end

T.test("bots never attack in Peace", function()
	local state = attackSetup(1000)
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.expect(not movesInto(state, commands, ZEPHYR), "moved into Zephyr in Peace")
	T.equal(declaresWar(commands), nil)
end)

T.test("not at war: declare on a weaker neighbour, never march in first", function()
	local state = attackSetup(4000)
	warPhase(state)
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.expect(not movesInto(state, commands, ZEPHYR), "marched into a nation it is not at war with")
	T.equal(declaresWar(commands), ZEPHYR)
end)

T.test("not at war: no war on a stronger neighbour", function()
	local state = attackSetup(9000)
	warPhase(state)
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.equal(declaresWar(commands), nil)
	T.expect(not movesInto(state, commands, ZEPHYR))
end)

T.test("at war and above the attack ratio: attack", function()
	local state = attackSetup(4000) -- 8000 against 4000 on plains: 2.0×
	warPhase(state)
	assert(Diplomacy.declareWar(state, AURORA, ZEPHYR))
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.expect(movesInto(state, commands, ZEPHYR), "did not attack")
	T.equal(commands[1].kind == "Move" and commands[1].to, id("Cinder Rock"), "strikes the army it was watching")
end)

T.test("at war but below the attack ratio: hold", function()
	-- Zephyr owns the world, so it wears the crown and Aurora fights it with the coalition bonus: 8000 men × that
	-- against this many is 1.2×, below Normal's 1.3× and above Hard's 1.1×
	local guard = math.floor(8000 * (1 + Config.Battle.CoalitionBonus) / 1.2)
	local state = attackSetup(guard)
	warPhase(state)
	assert(Diplomacy.declareWar(state, AURORA, ZEPHYR))
	-- every other Zephyr province is guarded too, so there is nothing weak to take
	for _, p in state.provinces do
		if p.owner == ZEPHYR and p.terrain ~= "Mountain" and p.id ~= id("Cinder Rock") then
			Army.spawn(state, ZEPHYR, p.id, guard)
		end
	end
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.expect(not movesInto(state, commands, ZEPHYR), "attacked below the ratio")
	-- Hard takes the risk at 1.1×
	local hard = Bot.plan(state, AURORA, Rng.new(1), "Hard")
	T.expect(movesInto(state, hard, ZEPHYR), "Hard should attack at 1.2×")
end)

-- Difficulties ------------------------------------------------------------------------------------------

T.test("Easy won't declare war on a player in the first 8 minutes", function()
	local state = attackSetup(4000)
	state.nations[ZEPHYR].controller = "Player"
	state.nations[ZEPHYR].userId = 42
	warPhase(state, 5 * 60)
	T.equal(declaresWar(Bot.plan(state, AURORA, Rng.new(1), "Easy")), nil)
	T.equal(declaresWar(Bot.plan(state, AURORA, Rng.new(1), "Normal")), ZEPHYR, "Normal would")
	warPhase(state, Config.Bots.Easy.noPlayerWarTicks)
	T.equal(declaresWar(Bot.plan(state, AURORA, Rng.new(1), "Easy")), ZEPHYR)
end)

T.test("Easy leaves a player's land alone in the first 8 minutes, even in a war the player started", function()
	local state = attackSetup(4000) -- 8000 against 4000: every difficulty would strike
	state.nations[ZEPHYR].controller = "Player"
	state.nations[ZEPHYR].userId = 42
	warPhase(state, 5 * 60)
	assert(Diplomacy.declareWar(state, ZEPHYR, AURORA))
	state.nations[AURORA].charges = Config.Primordial.Powers.Meteor.charges
	local function meteors(commands: { Types.Command }): boolean
		for _, c in commands do
			if c.kind == "Power" then
				return true
			end
		end
		return false
	end
	local easy = Bot.plan(state, AURORA, Rng.new(1), "Easy")
	T.expect(not movesInto(state, easy, ZEPHYR), "Easy marched into the player's land at 5:00")
	T.expect(not meteors(easy), "Easy used a power on the player at 5:00")
	local normal = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.expect(movesInto(state, normal, ZEPHYR) and meteors(normal), "Normal strikes back at once")
	warPhase(state, Config.Bots.Easy.noPlayerWarTicks)
	local later = Bot.plan(state, AURORA, Rng.new(1), "Easy")
	T.expect(movesInto(state, later, ZEPHYR) and meteors(later), "from 8:00 Easy strikes back too")
	-- bots are fair game for Easy all along
	state.nations[ZEPHYR].controller = "Bot"
	state.nations[ZEPHYR].userId = nil
	warPhase(state, 5 * 60)
	T.expect(movesInto(state, Bot.plan(state, AURORA, Rng.new(1), "Easy"), ZEPHYR), "Easy attacks a bot at 5:00")
end)

T.test("mixed difficulties: each bot plans on its own difficulty's clock", function()
	local state = Match.new(map)
	warPhase(state)
	local schedule = Bot.newSchedule()
	local levels: { [number]: Bot.Difficulty } = { [2] = "Hard", [3] = "Easy" }
	local seen: { [number]: number } = {}
	for _ = 1, 20 do
		state.tick += 1
		Bot.step(schedule, state, Rng.new(state.tick), "Normal", levels)
		for nationId, due in schedule.nextDue do
			local level = levels[nationId] or "Normal"
			if due == state.tick + Bot.settings(level).planTicks then
				seen[nationId] = Bot.settings(level).planTicks
			end
		end
	end
	T.equal(seen[2], Config.Bots.Hard.planTicks, "nation 2 waits Hard's planTicks")
	T.equal(seen[3], Config.Bots.Easy.planTicks, "nation 3 waits Easy's planTicks")
	T.equal(seen[4], Config.Bots.Normal.planTicks, "the others wait Normal's")
end)

T.test("Hard goes after the leading player, Normal after the weakest neighbour", function()
	local state = attackSetup(4000)
	state.provinces[id("Storm Reach")].owner = UMBRA -- Aurora now also borders Umbra, a weak bot
	Army.spawn(state, UMBRA, id("Umbra Landing"), 1000)
	state.nations[ZEPHYR].controller = "Player"
	state.nations[ZEPHYR].userId = 42
	warPhase(state)
	T.equal(declaresWar(Bot.plan(state, AURORA, Rng.new(1), "Normal")), UMBRA)
	T.equal(declaresWar(Bot.plan(state, AURORA, Rng.new(1), "Hard")), ZEPHYR)
end)

-- Diplomacy ---------------------------------------------------------------------------------------------

T.test("bots Meteor the biggest enemy army in a war, never an immune nation, along with their plan", function()
	local state = attackSetup(4000)
	warPhase(state)
	assert(Diplomacy.declareWar(state, AURORA, ZEPHYR))
	local small = Army.spawn(state, ZEPHYR, id("Cinder Reach"), 2000)
	local big = Army.spawn(state, ZEPHYR, id("Zephyr Landing"), 9000)
	T.expect(state.armies[small.id] and state.armies[big.id], "armies stand apart")
	local peaceful = Army.spawn(state, UMBRA, id("Umbra Landing"), 20000)
	local function meteor(commands: { Types.Command }): number?
		for _, c in commands do
			if c.kind == "Power" then
				T.equal(c.power, "Meteor")
				return c.target
			end
		end
		return nil
	end
	-- no charges, no power
	state.nations[AURORA].charges = 0
	T.equal(meteor(Bot.plan(state, AURORA, Rng.new(1), "Normal")), nil)
	state.nations[AURORA].charges = Config.Primordial.Powers.Meteor.charges
	local commands = Bot.plan(state, AURORA, Rng.new(1), "Normal")
	T.equal(meteor(commands), big.id, "the biggest army of a nation I'm at war with (not Umbra's, at peace)")
	T.expect(#commands >= 2, "the power rides along with the plan's other command")
	T.expect(peaceful.id ~= meteor(commands))
	-- the server takes it
	T.expect((Commands.apply(state, AURORA, { kind = "Power", power = "Meteor", target = big.id })))
	T.equal(big.men, 4500)
	-- Zephyr is now immune for a while: no wasted charge
	state.nations[AURORA].charges = Config.Primordial.Powers.Meteor.charges
	T.equal(meteor(Bot.plan(state, AURORA, Rng.new(1), "Normal")), nil)
	state.tick += Config.Primordial.ImmunityTicks
	T.expect(meteor(Bot.plan(state, AURORA, Rng.new(1), "Normal")) ~= nil, "immunity over")
end)

T.test("a bot that lost 30% of its provinces in a war accepts peace", function()
	local state = borderWar(0, 0)
	local memory = Bot.newMemory()
	state.nations[AURORA].gold = 0
	Bot.plan(state, AURORA, Rng.new(1), "Normal", memory) -- remembers 9 provinces at the start of the war
	assert(Diplomacy.propose(state, "Peace", ZEPHYR, AURORA, 0))
	local function accepts(): boolean
		for _, c in Bot.plan(state, AURORA, Rng.new(1), "Normal", memory) do
			if c.kind == "Diplomacy" and c.action == "AcceptPeace" then
				return true
			end
		end
		return false
	end
	T.expect(not accepts(), "accepted peace while winning")
	for _, name in { "Aurora Glade", "Aurora Grove", "Aurora Gate" } do
		state.provinces[id(name)].owner = ZEPHYR
	end
	T.expect(accepts(), "did not accept peace after losing a third of its land")
end)

-- Schedule ----------------------------------------------------------------------------------------------

T.test("bots are staggered and a leaver's nation is taken over at once", function()
	local state = Match.new(map)
	local schedule = Bot.newSchedule()
	local rng = Rng.new(3)
	Match.seatPlayer(state, 777) -- Alice takes nation 1
	local planTicks = Config.Bots.Normal.planTicks
	local lastPlanned: { [number]: number } = {}
	for _ = 1, 30 do
		state.tick += 1
		Bot.step(schedule, state, rng, "Normal")
		local planned = 0
		for nationId, due in schedule.nextDue do
			if due == state.tick + planTicks then
				planned += 1
				if lastPlanned[nationId] then
					T.expect(state.tick - lastPlanned[nationId] >= planTicks, "planned too often")
				end
				lastPlanned[nationId] = state.tick
			end
		end
		T.expect(planned <= Config.Bots.BotsPlanningPerTick, "too many bots planned in one tick")
	end
	T.equal(schedule.nextDue[1], nil, "the player's nation is not a bot")
	for nationId = 2, 10 do
		T.expect(lastPlanned[nationId] ~= nil, "bot " .. nationId .. " never planned")
	end
	Match.unseatPlayer(state, 777)
	state.tick += 1
	Bot.step(schedule, state, rng, "Normal")
	T.equal(schedule.nextDue[1], state.tick + planTicks, "the leaver's nation planned on the next tick")
end)

-- The order the bots first plan in sticks for the whole match (who plans right after each payday, who reaches
-- contested land first). It used to follow nation ids, so on the symmetric Skyshards slots 9 and 10 won 4× as
-- often as slots 1 and 8. Now it is drawn per match from the bots' rng.
T.test("the bots' first planning order is random per match, not by nation id", function()
	local planTicks = Config.Bots.Normal.planTicks
	local seeds = 40
	local sum: { [number]: number } = {}
	local orders: { [string]: boolean } = {}
	for seed = 1, seeds do
		local state = Match.new(map)
		local schedule = Bot.newSchedule()
		local rng = Rng.new(seed * 104729) -- spread the seeds: small ones give a near-zero first draw
		local first: { [number]: number } = {}
		local order = {}
		for _ = 1, 5 do
			state.tick += 1
			Bot.step(schedule, state, rng, "Normal")
			for nationId = 1, 10 do
				if first[nationId] == nil and schedule.nextDue[nationId] == state.tick + planTicks then
					first[nationId] = state.tick
					table.insert(order, nationId)
				end
			end
		end
		for nationId = 1, 10 do
			T.expect(first[nationId] ~= nil, "bot " .. nationId .. " did not plan in the first 5 ticks")
			sum[nationId] = (sum[nationId] or 0) + first[nationId]
		end
		orders[table.concat(order, ",")] = true
	end
	local distinct = 0
	for _ in orders do
		distinct += 1
	end
	T.expect(distinct >= seeds / 2, "only " .. distinct .. " different orders in " .. seeds .. " matches")
	for nationId = 1, 10 do
		local average = sum[nationId] / seeds -- ticks 1-5, so 3 on average for every slot
		T.expect(average > 2.3 and average < 3.7, string.format("bot %d first plans at tick %.1f", nationId, average))
	end
	-- the same rng gives the same order (deterministic tests and replays)
	local function firstPair(seed: number): string
		local state = Match.new(map)
		local schedule = Bot.newSchedule()
		state.tick = 1
		Bot.step(schedule, state, Rng.new(seed), "Normal")
		local ids = {}
		for nationId, due in schedule.nextDue do
			if due == 1 + planTicks then
				table.insert(ids, nationId)
			end
		end
		table.sort(ids)
		return table.concat(ids, ",")
	end
	T.equal(firstPair(7), firstPair(7))
end)

-- Whole matches -----------------------------------------------------------------------------------------

for _, mapId in Maps.ids do
	T.test(mapId .. ": 10 bots play 25 minutes, the Sim refuses (almost) nothing, and someone wins", function()
		for seed = 1, 2 do
			local state = Match.new(Maps.get(mapId))
			local commands, rejected = play(state, nil, seed)
			T.expect(commands > 1000, "only " .. commands .. " commands")
			T.expect(rejected <= 2, string.format("%d of %d commands rejected", rejected, commands))
			local result = state.result
			T.expect(result ~= nil and #result.winners >= 1, "no winner")
			local grew = false
			for nationId in state.nations do
				grew = grew or Match.provinceCount(state, nationId) > 15
			end
			T.expect(grew, "nobody grew")
		end
	end)
end

T.finish()
