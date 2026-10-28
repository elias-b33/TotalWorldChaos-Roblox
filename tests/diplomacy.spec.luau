--!strict
-- The EU4 pack's diplomacy (docs/DESIGN.md "Diplomacy"): insults with pre-written joke lines, comebacks, grudges,
-- gifts and military access; the match setting that turns them off; and the bots' part in it.
local Army = require("../src/shared/Sim/Army")
local Battle = require("../src/shared/Sim/Battle")
local Bot = require("../src/shared/Sim/Bot")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Insults = require("../src/shared/Flavour/Insults")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Pathing = require("../src/shared/Sim/Pathing")
local Rng = require("../src/shared/Sim/Rng")
local Settings = require("../src/shared/Sim/Settings")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

type MatchState = Types.MatchState

-- Earth: Ganges borders Tigris, Yangtze and Mekong at the start (Skyshards' shards touch nobody at first)
local map = Maps.get("earth")
local RHINE, VOLGA, TIGRIS, GANGES, YANGTZE, MEKONG, AMAZON = 1, 2, 3, 4, 5, 6, 10
local AURORA, ZEPHYR, NIMBUS = RHINE, VOLGA, TIGRIS -- three nations far apart

local function fresh(): MatchState
	return Match.new(map)
end

local function insult(state: MatchState, from: number, to: number, line: number?): (boolean, string?)
	return Commands.apply(
		state,
		from,
		{ kind = "Diplomacy", action = "Insult", target = to, gold = 0, line = line or 1 }
	)
end

local function act(state: MatchState, from: number, action: Types.DiplomacyAction, to: number, line: number?)
	return Commands.apply(state, from, { kind = "Diplomacy", action = action, target = to, gold = 0, line = line })
end

local function warPhase(state: MatchState)
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
end

local function lastEvent(state: MatchState): Types.MatchEvent
	return state.events[#state.events]
end

-- Two nations whose land touches.
local function neighbours(state: MatchState): (number, number)
	assert(Diplomacy.borders(state, GANGES, YANGTZE), "Ganges borders Yangtze")
	return GANGES, YANGTZE
end

-- Insults, comebacks and grudges ---------------------------------------------------------------------------------

T.test("an insult needs a line of the map's pool; it gives the insulted a grudge and a comeback window", function()
	local state = fresh()
	T.equal(state.phase, "Peace", "insults work in Peace too")
	T.equal(select(2, insult(state, AURORA, ZEPHYR, 0)), "BadRequest", "no line")
	T.equal(select(2, insult(state, AURORA, ZEPHYR, #Insults.lines("earth", "insults") + 1)), "BadRequest")
	T.equal(select(2, insult(state, AURORA, AURORA, 1)), "BadTarget", "not yourself")
	T.expect((insult(state, AURORA, ZEPHYR, 3)))
	local e = lastEvent(state)
	T.equal(e.kind, "Insult")
	T.equal(e.a, AURORA)
	T.equal(e.b, ZEPHYR)
	T.equal(e.line, 3, "the event carries the line for the speech bubble and the toast")
	T.expect(Diplomacy.grudge(state, ZEPHYR, AURORA), "Zephyr holds a grudge against Aurora")
	T.expect(not Diplomacy.grudge(state, AURORA, ZEPHYR), "not the other way round")
	local window = Diplomacy.comebackWindow(state, ZEPHYR, AURORA)
	T.expect(window ~= nil, "Zephyr may answer back")
	T.equal((window :: Types.Comeback).line, 3, "the window remembers the insult")
	T.equal((window :: Types.Comeback).untilTick, state.tick + Config.Diplomacy.ComebackTicks)
end)

T.test("one insult per pair per cooldown, each way; never an ally", function()
	local state = fresh()
	T.expect((insult(state, AURORA, ZEPHYR)))
	T.equal(select(2, insult(state, AURORA, ZEPHYR)), "Cooldown")
	T.equal(Diplomacy.cooldownLeft(state, "Insult", AURORA, ZEPHYR), Config.Diplomacy.InsultCooldownTicks)
	T.expect((insult(state, ZEPHYR, AURORA)), "the insulted may insult back: each way has its own wait")
	T.expect((insult(state, AURORA, NIMBUS)), "and Aurora may insult someone else")
	state.tick += Config.Diplomacy.InsultCooldownTicks
	T.expect((insult(state, AURORA, ZEPHYR)), "after the wait, again")
	T.expect((Diplomacy.ally(state, AURORA, NIMBUS)))
	state.tick += Config.Diplomacy.InsultCooldownTicks
	T.equal(select(2, insult(state, AURORA, NIMBUS)), "Allied", "nobody insults an ally")
end)

T.test("a comeback answers the insult once, while its window is open; the grudge stays", function()
	local state = fresh()
	T.equal(select(2, act(state, ZEPHYR, "Comeback", AURORA, 1)), "NoComeback", "nothing to answer yet")
	insult(state, AURORA, ZEPHYR)
	T.equal(select(2, act(state, ZEPHYR, "Comeback", AURORA, 0)), "BadRequest", "a comeback needs a line too")
	T.equal(select(2, act(state, NIMBUS, "Comeback", AURORA, 1)), "NoComeback", "only the insulted answers")
	T.expect((act(state, ZEPHYR, "Comeback", AURORA, 2)))
	local e = lastEvent(state)
	T.equal(e.kind, "Comeback")
	T.equal(e.a, ZEPHYR)
	T.equal(e.b, AURORA)
	T.equal(e.line, 2)
	T.equal(select(2, act(state, ZEPHYR, "Comeback", AURORA, 2)), "NoComeback", "once per insult")
	T.expect(Diplomacy.grudge(state, ZEPHYR, AURORA), "answering doesn't end the grudge")
	-- a window closes on its own
	state.tick += Config.Diplomacy.InsultCooldownTicks
	insult(state, AURORA, ZEPHYR)
	state.tick += Config.Diplomacy.ComebackTicks
	T.equal(select(2, act(state, ZEPHYR, "Comeback", AURORA, 1)), "NoComeback", "too late")
end)

T.test("a grudge is a combat bonus for the insulted side against the insulter, for a few minutes", function()
	local state = fresh()
	warPhase(state)
	local a, b = neighbours(state)
	assert(Diplomacy.declareWar(state, a, b))
	local where = state.nations[b].capital
	local defender = Army.spawn(state, b, where, 3000)
	local attacker = Army.spawn(state, a, where, 3000)
	local sides = assert(Battle.sides(state, where, { defender, attacker }))
	local before = Battle.modifier(state, where, sides, true, 0)
	local attackBefore = Battle.modifier(state, where, sides, false, 0)
	assert(insult(state, a, b)) -- the attacker insults the defender
	T.near(Battle.modifier(state, where, sides, true, 0), before + Config.Diplomacy.GrudgeBonus, 1e-9, "insulted side")
	T.near(Battle.modifier(state, where, sides, false, 0), attackBefore, 1e-9, "the insulter gets nothing")
	-- it lasts GrudgeTicks, then Diplomacy.expire drops it
	state.tick += Config.Diplomacy.GrudgeTicks - 1
	T.expect(Diplomacy.grudge(state, b, a))
	state.tick += 1
	Diplomacy.expire(state)
	T.equal(#state.grudges, 0, "the grudge is over")
	T.near(Battle.modifier(state, where, sides, true, 0), before, 1e-9)
end)

T.test("a grudge only counts against the insulter (and its side)", function()
	local state = fresh()
	assert(insult(state, NIMBUS, ZEPHYR)) -- Nimbus, not Aurora, insulted Zephyr
	T.equal(Diplomacy.grudgeBonus(state, { ZEPHYR }, { AURORA }), 0)
	T.equal(Diplomacy.grudgeBonus(state, { ZEPHYR }, { AURORA, NIMBUS }), Config.Diplomacy.GrudgeBonus, "allies too")
	T.equal(Diplomacy.grudgeBonus(state, { AURORA, ZEPHYR }, { NIMBUS }), Config.Diplomacy.GrudgeBonus, "the side")
	T.equal(Diplomacy.grudgeBonus(state, { 0 }, { NIMBUS }), 0, "garrisons hold no grudges")
end)

-- Gifts ---------------------------------------------------------------------------------------------------------------

T.test("a gift moves a little gold, not to an enemy, once per cooldown", function()
	local state = fresh()
	local gold = Config.Diplomacy.GiftGold
	local a0, z0 = state.nations[AURORA].gold, state.nations[ZEPHYR].gold
	T.expect((act(state, AURORA, "Gift", ZEPHYR)))
	T.equal(state.nations[AURORA].gold, a0 - gold)
	T.equal(state.nations[ZEPHYR].gold, z0 + gold)
	T.equal(lastEvent(state).kind, "Gift")
	T.equal(select(2, act(state, AURORA, "Gift", ZEPHYR)), "Cooldown")
	state.tick += Config.Diplomacy.GiftCooldownTicks
	state.nations[AURORA].gold = gold - 1
	T.equal(select(2, act(state, AURORA, "Gift", ZEPHYR)), "NotEnoughGold")
	state.nations[AURORA].gold = 500
	warPhase(state)
	local a, b = neighbours(state)
	assert(Diplomacy.declareWar(state, a, b))
	T.equal(select(2, act(state, a, "Gift", b)), "AtWar", "no gifts to an enemy")
end)

-- Military access ------------------------------------------------------------------------------------------------------

T.test("military access is asked and accepted like an alliance, and lets the guest's armies in", function()
	local state = fresh()
	local a, b = neighbours(state)
	-- a province of b's that a's armies can't reach until access is granted
	local inside: number? = nil
	for id, p in state.provinces do
		if p.owner == b and not p.isCapital then
			inside = id
		end
	end
	local target = inside :: number
	local from = state.nations[a].capital
	T.equal(Diplomacy.canEnter(state, a, target), false, "at peace: no entry")
	T.equal(Pathing.find(state, a, from, target), nil)
	T.equal(select(2, act(state, b, "AcceptAccess", a)), "NoOffer", "nothing to accept yet")
	T.expect((act(state, a, "Access", b)))
	T.equal(lastEvent(state).kind, "Offer")
	T.equal(state.offers[1].kind, "Access")
	T.expect((act(state, b, "AcceptAccess", a)))
	T.equal(lastEvent(state).kind, "AccessGranted")
	T.equal(lastEvent(state).a, b, "the owner lets...")
	T.equal(lastEvent(state).b, a, "...the guest through")
	T.expect(Diplomacy.hasAccess(state, a, b))
	T.expect(not Diplomacy.hasAccess(state, b, a), "access goes one way")
	T.expect(Diplomacy.canEnter(state, a, target))
	T.expect(Pathing.find(state, a, from, target) ~= nil, "a's armies may march through")
	T.equal(select(2, act(state, a, "Access", b)), "AlreadyAccess")
	-- it runs out
	state.tick += Config.Diplomacy.AccessTicks
	T.equal(Diplomacy.canEnter(state, a, target), false, "access lasts AccessTicks")
	Diplomacy.expire(state)
	T.equal(#state.access, 0)
end)

T.test("a war between them ends military access; enemies and allies can't ask for it", function()
	local state = fresh()
	local a, b = neighbours(state)
	assert(act(state, a, "Access", b))
	assert(act(state, b, "AcceptAccess", a))
	warPhase(state)
	assert(Diplomacy.declareWar(state, b, a))
	T.equal(#state.access, 0, "the war ended it")
	T.equal(select(2, act(state, a, "Access", b)), "AtWar")
	T.expect((Diplomacy.ally(state, NIMBUS, ZEPHYR)) or Diplomacy.allied(state, NIMBUS, ZEPHYR))
	T.equal(select(2, act(state, NIMBUS, "Access", ZEPHYR)), "AlreadyAllied", "allies may enter anyway")
end)

T.test("an army with access walks into the land, and stops where access ends", function()
	local state = fresh()
	local a, b = neighbours(state)
	-- a province of a's next to a province of b's (x), and another province of b's next to x (y)
	local start, x, y = 0, 0, 0
	for id, p in state.provinces do
		if p.owner == a then
			for _, n in p.neighbors do
				local q = state.provinces[n]
				if q.owner == b and q.terrain ~= "Mountain" then
					for _, m in q.neighbors do
						if state.provinces[m].owner == b and state.provinces[m].terrain ~= "Mountain" then
							start, x, y = id, n, m
						end
					end
				end
			end
		end
	end
	assert(start ~= 0, "found a way into b's land")
	local army = Army.spawn(state, a, start, 2000)
	local move: Types.Command = { kind = "Move", army = army.id, to = x }
	T.equal(select(2, Commands.apply(state, a, move)), "NoPath", "no way in without access")
	assert(act(state, a, "Access", b))
	assert(act(state, b, "AcceptAccess", a))
	T.expect((Commands.apply(state, a, move)), "with access, the march is accepted")
	local rng = Rng.new(1)
	for _ = 1, Config.Army.MoveTicks.Hills do
		Tick.advance(state, rng)
	end
	T.equal(army.location, x, "the army walked into b's province")
	T.equal(state.provinces[x].owner, b, "and it stays b's: no siege, no battle")
	T.expect(state.provinces[x].siege == nil)
	assert(Commands.apply(state, a, { kind = "Move", army = army.id, to = y }))
	for _, grant in state.access do
		grant.untilTick = state.tick + 1 -- access runs out next tick
	end
	Tick.advance(state, rng)
	T.equal(#army.path, 0, "the way closed: the army stops where it stands")
	T.equal(army.location, x)
end)

-- The match setting ----------------------------------------------------------------------------------------------------

T.test("the diplomacy setting turns insults, comebacks, gifts and access off", function()
	local settings = Settings.defaults()
	T.equal(settings.diplomacy, Config.Features.Diplomacy, "Config.Features gives the default")
	T.expect((Settings.set(settings, "diplomacy", false, 0, Maps.ids)))
	T.equal(select(2, Settings.set(settings, "diplomacy", "no", 0, Maps.ids)), "BadSetting")
	T.equal(Settings.isStandard(settings), false, "turning a feature off is a custom rule")
	local state = Match.new(map, Settings.setup(true, settings))
	for _, action in { "Insult", "Gift", "Access", "AcceptAccess", "Comeback" } :: { Types.DiplomacyAction } do
		T.equal(select(2, act(state, AURORA, action, ZEPHYR, 1)), "DiplomacyOff", action)
	end
	T.expect((act(state, AURORA, "Ally", ZEPHYR)), "alliances are always on")
end)

-- Bots -------------------------------------------------------------------------------------------------------------------

local function withConfig(path: { string }, value: any, fn: () -> ())
	local node: any = Config
	for i = 1, #path - 1 do
		node = node[path[i]]
	end
	local key = path[#path]
	local old = node[key]
	node[key] = value
	local ok, err = pcall(fn)
	node[key] = old
	if not ok then
		error(err, 0)
	end
end

local function planned(commands: { Types.Command }, action: string): Types.Command?
	for _, c in commands do
		if c.kind == "Diplomacy" and c.action == action then
			return c
		end
	end
	return nil
end

T.test("bots insult a rival now and then, with a line of the map's pool", function()
	withConfig({ "Bots", "InsultChance" }, 1, function()
		local state = fresh()
		local a = neighbours(state)
		local commands = Bot.plan(state, a, Rng.new(5), "Normal", Bot.newMemory())
		local c = planned(commands, "Insult")
		T.expect(c ~= nil, "the bot insulted someone")
		local command = c :: any
		T.expect(Insults.valid("earth", "insults", command.line), "a line of the pool")
		T.expect(Diplomacy.borders(state, a, command.target), "a neighbour (no wars yet)")
		T.expect((Commands.apply(state, a, command)), "the server takes it")
	end)
	withConfig({ "Bots", "InsultChance" }, 0, function()
		local state = fresh()
		local a = neighbours(state)
		T.equal(planned(Bot.plan(state, a, Rng.new(5), "Normal", Bot.newMemory()), "Insult"), nil, "never at 0")
	end)
end)

T.test("an insulted bot answers back once, and lets a nation through that asks", function()
	withConfig({ "Bots", "ComebackChance" }, 1, function()
		local state = fresh()
		assert(insult(state, AURORA, ZEPHYR))
		assert(act(state, NIMBUS, "Access", ZEPHYR))
		local memory = Bot.newMemory()
		local commands = Bot.plan(state, ZEPHYR, Rng.new(3), "Normal", memory)
		local answer = planned(commands, "Comeback") :: any
		T.expect(answer ~= nil and answer.target == AURORA, "Zephyr answers Aurora")
		T.expect(Insults.valid("earth", "comebacks", answer.line))
		local accept = planned(commands, "AcceptAccess") :: any
		T.expect(accept ~= nil and accept.target == NIMBUS, "and lets Nimbus through")
		T.equal(planned(Bot.plan(state, ZEPHYR, Rng.new(4), "Normal", memory), "Comeback"), nil, "decided once")
	end)
	-- a bot refuses access to a nation that insulted it
	local state = fresh()
	assert(insult(state, AURORA, ZEPHYR))
	assert(act(state, AURORA, "Access", ZEPHYR))
	T.equal(planned(Bot.plan(state, ZEPHYR, Rng.new(3), "Normal", Bot.newMemory()), "AcceptAccess"), nil)
end)

T.test("an insulted bot leans towards war with its insulter", function()
	-- Ganges borders Tigris, Yangtze and Mekong; the free land goes to Amazon (no garrisons to expand into first)
	local state = fresh()
	warPhase(state)
	for armyId, a in state.armies do
		if a.owner == 0 then
			state.armies[armyId] = nil
		end
	end
	for _, p in state.provinces do
		if p.owner == nil and p.terrain ~= "Mountain" then
			p.owner = AMAZON
		end
	end
	-- Ganges is strong; Mekong, the insulter, is the strongest of its neighbours
	Army.spawn(state, GANGES, state.nations[GANGES].capital, 20000)
	Army.spawn(state, MEKONG, state.nations[MEKONG].capital, 4000)
	local function warTarget(): number?
		local commands = Bot.plan(state, GANGES, Rng.new(9), "Normal", Bot.newMemory())
		local war = planned(commands, "War")
		return if war then (war :: any).target else nil
	end
	local before = warTarget()
	T.expect(before ~= nil and before ~= MEKONG, "without a grudge: a weaker neighbour (" .. tostring(before) .. ")")
	assert(insult(state, MEKONG, GANGES))
	T.equal(warTarget(), MEKONG, "with a grudge: the insulter")
end)

-- The lines -------------------------------------------------------------------------------------------------------------

T.test("every map has its own lines, short, and none uses a banned word or a river name", function()
	local banned = { "god", "divine", "holy" }
	local rivers: { string } = {}
	for _, def in Maps.get("earth").nations do
		table.insert(rivers, string.lower(def.name))
	end
	local seen: { [string]: string } = {}
	for _, mapId in Maps.ids do
		local insults, comebacks = Insults.lines(mapId, "insults"), Insults.lines(mapId, "comebacks")
		T.expect(#insults >= 6, mapId .. ": several insults to pick from")
		T.expect(#comebacks >= 4, mapId .. ": several comebacks")
		T.expect(Insults.BY_MAP[mapId] ~= nil, mapId .. " has its own pool")
		for _, list in { insults, comebacks } do
			for _, line in list do
				T.expect(#line <= 60, "short enough for a toast: " .. line)
				local lower = string.lower(line)
				for _, word in banned do
					T.expect(string.find(lower, word, 1, true) == nil, "banned word in: " .. line)
				end
				if mapId == "earth" then
					for _, river in rivers do
						T.expect(string.find(lower, river, 1, true) == nil, "Earth line names a river: " .. line)
					end
				end
				T.expect(seen[line] == nil, "a line used twice: " .. line)
				seen[line] = mapId
			end
		end
	end
	T.equal(Insults.line("skyshards", "insults", 99), nil)
	T.expect(Insults.valid("eldmoor", "comebacks", 1))
	T.equal(Insults.valid("eldmoor", "comebacks", 1.5), false)
end)

T.finish()
