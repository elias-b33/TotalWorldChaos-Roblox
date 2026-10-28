--!strict
-- The EU4 pack's diplomacy (docs/DESIGN.md "Diplomacy"): insults (an action with no message), their answers (insult
-- back, laugh it off), grudges, gifts and military access; the match setting that turns them off; the bots' part in
-- it; and the private flavour lines only the insulter sees.
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

local function act(state: MatchState, from: number, action: Types.DiplomacyAction, to: number): (boolean, string?)
	return Commands.apply(state, from, { kind = "Diplomacy", action = action, target = to, gold = 0 })
end

local function insult(state: MatchState, from: number, to: number): (boolean, string?)
	return act(state, from, "Insult", to)
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

-- Insults, answers and grudges ------------------------------------------------------------------------------------

T.test("an insult carries no message; it gives the insulted a grudge and a window to answer", function()
	local state = fresh()
	T.equal(state.phase, "Peace", "insults work in Peace too")
	T.equal(select(2, insult(state, AURORA, AURORA)), "BadTarget", "not yourself")
	T.equal(select(2, insult(state, AURORA, 99)), "BadTarget", "not a nation that isn't there")
	T.expect((insult(state, AURORA, ZEPHYR)))
	local e = lastEvent(state)
	T.equal(e.kind, "Insult")
	T.equal(e.a, AURORA)
	T.equal(e.b, ZEPHYR)
	local fields = 0
	for _ in e :: any do
		fields += 1
	end
	T.equal(fields, 4, "kind, a, b, province: nothing a player wrote or picked")
	T.expect(Diplomacy.grudge(state, ZEPHYR, AURORA), "Zephyr holds a grudge against Aurora")
	T.expect(not Diplomacy.grudge(state, AURORA, ZEPHYR), "not the other way round")
	local window = Diplomacy.answerWindow(state, ZEPHYR, AURORA)
	T.expect(window ~= nil, "Zephyr may answer")
	T.equal((window :: Types.Answer).untilTick, state.tick + Config.Diplomacy.AnswerTicks)
end)

T.test("one insult per pair per cooldown, each way; never an ally", function()
	local state = fresh()
	T.expect((insult(state, AURORA, ZEPHYR)))
	T.equal(select(2, insult(state, AURORA, ZEPHYR)), "Cooldown")
	T.equal(Diplomacy.cooldownLeft(state, "Insult", AURORA, ZEPHYR), Config.Diplomacy.InsultCooldownTicks)
	T.expect((insult(state, ZEPHYR, AURORA)), "the insulted may insult too: each way has its own wait")
	T.expect((insult(state, AURORA, NIMBUS)), "and Aurora may insult someone else")
	state.tick += Config.Diplomacy.InsultCooldownTicks
	T.expect((insult(state, AURORA, ZEPHYR)), "after the wait, again")
	T.expect((Diplomacy.ally(state, AURORA, NIMBUS)))
	state.tick += Config.Diplomacy.InsultCooldownTicks
	T.equal(select(2, insult(state, AURORA, NIMBUS)), "Allied", "nobody insults an ally")
end)

T.test("insult back: once, while the window is open; the insulter now holds a grudge too", function()
	local state = fresh()
	T.equal(select(2, act(state, ZEPHYR, "InsultBack", AURORA)), "NoAnswer", "nothing to answer yet")
	assert(insult(state, AURORA, ZEPHYR))
	assert(insult(state, ZEPHYR, NIMBUS)) -- Zephyr's own insult elsewhere doesn't matter
	T.equal(select(2, act(state, NIMBUS, "InsultBack", AURORA)), "NoAnswer", "only the insulted answers")
	T.expect((act(state, ZEPHYR, "InsultBack", AURORA)))
	local e = lastEvent(state)
	T.equal(e.kind, "InsultBack")
	T.equal(e.a, ZEPHYR)
	T.equal(e.b, AURORA)
	T.expect(Diplomacy.grudge(state, AURORA, ZEPHYR), "Aurora holds a grudge against Zephyr now")
	T.expect(Diplomacy.grudge(state, ZEPHYR, AURORA), "and Zephyr keeps its own")
	T.equal(Diplomacy.answerWindow(state, AURORA, ZEPHYR), nil, "no answer to an answer: the exchange is over")
	T.equal(select(2, act(state, ZEPHYR, "InsultBack", AURORA)), "NoAnswer", "once per insult")
	T.equal(Diplomacy.cooldownLeft(state, "Insult", ZEPHYR, AURORA), Config.Diplomacy.InsultCooldownTicks)
	-- a window closes on its own
	state.tick += Config.Diplomacy.InsultCooldownTicks
	assert(insult(state, AURORA, ZEPHYR))
	state.tick += Config.Diplomacy.AnswerTicks
	T.equal(select(2, act(state, ZEPHYR, "InsultBack", AURORA)), "NoAnswer", "too late")
end)

T.test("laugh it off: the grudge turns into high spirits, a smaller bonus in every battle for a minute", function()
	local state = fresh()
	assert(insult(state, AURORA, ZEPHYR))
	T.expect((act(state, ZEPHYR, "LaughOff", AURORA)))
	local e = lastEvent(state)
	T.equal(e.kind, "LaughedOff")
	T.equal(e.a, ZEPHYR)
	T.equal(e.b, AURORA)
	T.expect(not Diplomacy.grudge(state, ZEPHYR, AURORA), "no grudge any more")
	T.expect(Diplomacy.grudge(state, ZEPHYR, 0), "high spirits")
	T.equal(Diplomacy.grudgeBonus(state, { ZEPHYR }, { NIMBUS }), Config.Diplomacy.LaughBonus, "against anyone")
	T.equal(Diplomacy.grudgeBonus(state, { ZEPHYR }, { 0 }), Config.Diplomacy.LaughBonus, "garrisons too")
	T.equal(Diplomacy.grudgeBonus(state, { AURORA }, { ZEPHYR }), 0, "the insulter gets nothing")
	T.equal(select(2, act(state, ZEPHYR, "LaughOff", AURORA)), "NoAnswer", "once per insult")
	-- a grudge and high spirits don't stack: the best one counts
	assert(insult(state, NIMBUS, ZEPHYR))
	T.equal(Diplomacy.grudgeBonus(state, { ZEPHYR }, { NIMBUS }), Config.Diplomacy.GrudgeBonus)
	-- high spirits last LaughTicks, then Diplomacy.expire drops them
	state.tick += Config.Diplomacy.LaughTicks
	T.equal(Diplomacy.grudgeBonus(state, { ZEPHYR }, { AURORA }), 0)
	Diplomacy.expire(state)
	for _, g in state.grudges do
		T.expect(g.against ~= 0, "high spirits are gone")
	end
	T.expect(Diplomacy.grudge(state, ZEPHYR, NIMBUS), "Nimbus's insult still stings")
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

T.test("a gift moves a little gold, not to an enemy, one gift per cooldown whoever it goes to", function()
	local state = fresh()
	local gold = Config.Diplomacy.GiftGold
	local a0, z0 = state.nations[AURORA].gold, state.nations[ZEPHYR].gold
	T.expect((act(state, AURORA, "Gift", ZEPHYR)))
	T.equal(state.nations[AURORA].gold, a0 - gold)
	T.equal(state.nations[ZEPHYR].gold, z0 + gold)
	T.equal(lastEvent(state).kind, "Gift")
	T.equal(select(2, act(state, AURORA, "Gift", ZEPHYR)), "Cooldown")
	T.equal(select(2, act(state, AURORA, "Gift", NIMBUS)), "Cooldown", "one gift budget, not one per nation")
	T.equal(Diplomacy.cooldownLeft(state, "Gift", AURORA, 0), Config.Diplomacy.GiftCooldownTicks)
	T.expect((act(state, ZEPHYR, "Gift", AURORA)), "the others give on their own clock")
	state.tick += Config.Diplomacy.GiftCooldownTicks
	Diplomacy.expire(state)
	T.equal(#state.cooldowns, 0, "waits run out")
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
	state.tick += Config.Diplomacy.AccessTicks - 1
	T.expect(Diplomacy.canEnter(state, a, target))
	T.equal(#Diplomacy.endedAccess(state), 0, "still on")
	state.tick += 1
	T.equal(Diplomacy.canEnter(state, a, target), false, "access lasts AccessTicks")
	T.equal(#Diplomacy.endedAccess(state), 1, "then it ends")
	T.equal(#state.access, 0)
end)

T.test("a war between them ends military access; enemies and allies can't ask for it", function()
	local state = fresh()
	local a, b = neighbours(state)
	assert(act(state, a, "Access", b))
	assert(act(state, b, "AcceptAccess", a))
	warPhase(state)
	assert(Diplomacy.declareWar(state, b, a))
	Tick.advance(state, Rng.new(1))
	T.equal(#state.access, 0, "the war ended it")
	T.equal(select(2, act(state, a, "Access", b)), "AtWar")
	T.expect((Diplomacy.ally(state, NIMBUS, ZEPHYR)) or Diplomacy.allied(state, NIMBUS, ZEPHYR))
	T.equal(select(2, act(state, NIMBUS, "Access", ZEPHYR)), "AlreadyAllied", "allies may enter anyway")
end)

T.test("an army with access walks into the land, and walks home under the white flag when access ends", function()
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
	T.expect(army.retreating == true, "access ended: the army walks home under the white flag")
	T.equal(army.path[#army.path], start, "to its nearest own province, over b's land")
	T.equal(select(2, Commands.apply(state, a, { kind = "Move", army = army.id, to = y })), "Retreating")
	for _ = 1, Config.Army.MoveTicks.Hills do
		Tick.advance(state, rng)
	end
	T.equal(army.location, start, "home")
	T.equal(army.retreating, nil, "a normal army again")
	T.equal(state.provinces[x].owner, b, "nothing changed hands")
end)

T.test("a war between host and guest sends the guest's armies home; they don't fight or besiege on the way", function()
	local state = fresh()
	local a, b = neighbours(state)
	local inside: number? = nil
	for id, p in state.provinces do
		if p.owner == b and not p.isCapital and (inside == nil or id < inside) then
			inside = id
		end
	end
	local x = inside :: number
	assert(act(state, a, "Access", b))
	assert(act(state, b, "AcceptAccess", a))
	local guest = Army.spawn(state, a, x, 4000) -- marched in with access
	local host = Army.spawn(state, b, x, 1000)
	warPhase(state)
	assert(Diplomacy.declareWar(state, a, b)) -- the guest stabs its host in the back...
	local rng = Rng.new(2)
	Tick.advance(state, rng)
	T.expect(guest.retreating == true, "...but its armies in the host's land walk home first")
	T.equal(state.battles[x], nil, "no battle with the host's army")
	T.equal(state.provinces[x].siege, nil, "and no siege")
	T.expect(host.men == 1000, "the host's army is untouched")
end)

-- The match setting ----------------------------------------------------------------------------------------------------

T.test("the diplomacy setting turns insults, their answers, gifts and access off", function()
	local settings = Settings.defaults()
	T.equal(settings.diplomacy, Config.Features.Diplomacy, "Config.Features gives the default")
	T.expect((Settings.set(settings, "diplomacy", false, 0, Maps.ids)))
	T.equal(select(2, Settings.set(settings, "diplomacy", "no", 0, Maps.ids)), "BadSetting")
	T.equal(Settings.isStandard(settings), true, "turning insults off keeps full rewards (nothing gets easier)")
	local state = Match.new(map, Settings.setup(true, settings))
	local actions =
		{ "Insult", "InsultBack", "LaughOff", "Gift", "Access", "AcceptAccess" } :: { Types.DiplomacyAction }
	for _, action in actions do
		T.equal(select(2, act(state, AURORA, action, ZEPHYR)), "DiplomacyOff", action)
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

T.test("bots insult a rival now and then", function()
	withConfig({ "Bots", "InsultChance" }, 1, function()
		local state = fresh()
		local a = neighbours(state)
		local commands = Bot.plan(state, a, Rng.new(5), "Normal", Bot.newMemory())
		local c = planned(commands, "Insult")
		T.expect(c ~= nil, "the bot insulted someone")
		local command = c :: any
		T.expect(Diplomacy.borders(state, a, command.target), "a neighbour (no wars yet)")
		T.expect((Commands.apply(state, a, command)), "the server takes it")
	end)
	withConfig({ "Bots", "InsultChance" }, 0, function()
		local state = fresh()
		local a = neighbours(state)
		T.equal(planned(Bot.plan(state, a, Rng.new(5), "Normal", Bot.newMemory()), "Insult"), nil, "never at 0")
	end)
end)

T.test("an insulted bot insults back once (never laughs it off), and lets a nation through that asks", function()
	withConfig({ "Bots", "InsultBackChance" }, 1, function()
		local state = fresh()
		assert(insult(state, AURORA, ZEPHYR))
		assert(act(state, NIMBUS, "Access", ZEPHYR))
		local memory = Bot.newMemory()
		local commands = Bot.plan(state, ZEPHYR, Rng.new(3), "Normal", memory)
		local answer = planned(commands, "InsultBack") :: any
		T.expect(answer ~= nil and answer.target == AURORA, "Zephyr insults Aurora back")
		T.equal(planned(commands, "LaughOff"), nil, "bots keep their grudges")
		local accept = planned(commands, "AcceptAccess") :: any
		T.expect(accept ~= nil and accept.target == NIMBUS, "and lets Nimbus through")
		T.equal(planned(Bot.plan(state, ZEPHYR, Rng.new(4), "Normal", memory), "InsultBack"), nil, "decided once")
	end)
	withConfig({ "Bots", "InsultBackChance" }, 0, function()
		local state = fresh()
		assert(insult(state, AURORA, ZEPHYR))
		local commands = Bot.plan(state, ZEPHYR, Rng.new(3), "Normal", Bot.newMemory())
		T.equal(planned(commands, "InsultBack"), nil, "at 0 it just keeps its grudge")
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

T.test("a grudge lowers a bot's attack ratio, but never below an even fight", function()
	for _, difficulty in { "Easy", "Normal", "Hard" } :: { Bot.Difficulty } do
		local ratio = Bot.settings(difficulty).attackRatio
		local lowered = ratio * Bot.grudgeFactor(ratio)
		T.expect(lowered < ratio, difficulty .. ": a lower bar against an insulter")
		T.expect(lowered >= Config.Bots.GrudgeMinRatio - 1e-9, difficulty .. ": never under an even fight")
	end
	T.near(Bot.grudgeFactor(Bot.settings("Normal").attackRatio), Config.Bots.GrudgeAttackRatio, 1e-9)
	T.near(Bot.settings("Hard").attackRatio * Bot.grudgeFactor(Bot.settings("Hard").attackRatio), 1, 1e-9, "Hard: 1×")
end)

-- The private flavour lines -----------------------------------------------------------------------------------------

T.test("every map has its own private flavour lines: short, silly, no banned word, no river name", function()
	-- the three words CLAUDE.md bans everywhere, spelled backwards so they never appear in the code themselves
	local banned = { string.reverse("dog"), string.reverse("enivid"), string.reverse("yloh") }
	local rivers: { string } = {}
	for _, def in Maps.get("earth").nations do
		table.insert(rivers, string.lower(def.name))
	end
	local seen: { [string]: string } = {}
	for _, mapId in Maps.ids do
		T.expect(Insults.BY_MAP[mapId] ~= nil, mapId .. " has its own pool")
		local longest = "" -- the map's longest nation name: the longest a line gets
		for _, def in Maps.get(mapId).nations do
			if #def.name > #longest then
				longest = def.name
			end
		end
		for _, kind in { "insult", "laugh" } :: { Insults.Kind } do
			local lines = Insults.lines(mapId, kind)
			T.expect(#lines >= 4, mapId .. ": several " .. kind .. " lines")
			for i, line in lines do
				local shown = Insults.flavour(mapId, kind, longest, i - 1)
				T.equal(shown, (string.gsub(line, "%%s", longest)), "the line, with the other nation's name")
				T.expect(#shown <= 64, "short enough for a toast: " .. shown)
				T.expect(string.sub(line, 1, 5) == "Your ", "about your own side: " .. line)
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
	T.equal(
		Insults.flavour("earth", "insult", "100%", 0),
		(string.gsub(Insults.lines("earth", "insult")[1], "%%s", "100%%"))
	)
end)

T.finish()
