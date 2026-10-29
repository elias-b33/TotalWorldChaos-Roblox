--!strict
-- The EU4 pack, stage 2: event cards with choices (docs/DESIGN.md "Events"). When cards come and close, what each
-- effect does, what a choice must afford, which events a nation may get, the match setting, the bots' answers, what
-- a player's client is told, and the words on every card.
local Army = require("../src/shared/Sim/Army")
local Bot = require("../src/shared/Sim/Bot")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Economy = require("../src/shared/Sim/Economy")
local EventCards = require("../src/shared/Sim/EventCards")
local EventText = require("../src/shared/Flavour/EventCards")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Navy = require("../src/shared/Sim/Navy")
local Rng = require("../src/shared/Sim/Rng")
local Settings = require("../src/shared/Sim/Settings")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Tutorial = require("../src/shared/Sim/Tutorial")
local Types = require("../src/shared/Types")

type MatchState = Types.MatchState

local E = Config.EventCards
local A, B = 1, 2

local function fresh(mapId: string?): MatchState
	return Match.new(Maps.get(mapId or "earth"))
end

-- Deal nation `nationId` a card of event `id` now (every other event counts as already had).
local function dealt(state: MatchState, nationId: number, id: string): Types.EventCard
	local seen = {}
	for _, def in EventCards.EVENTS do
		if def.id ~= id then
			table.insert(seen, def.id)
		end
	end
	state.chronicles[nationId] = { nextAt = state.tick, seen = seen, card = nil, last = nil }
	local card = EventCards.deal(state, nationId, Rng.new(7))
	assert(card and card.event == id, "dealt " .. id)
	return card
end

local function choose(state: MatchState, nationId: number, card: Types.EventCard, choice: number): (boolean, string?)
	return Commands.apply(state, nationId, { kind = "EventChoice", card = card.id, choice = choice })
end

-- The words ------------------------------------------------------------------------------------------------------------

T.test("about thirty events, shared and per map, each with its words, two choices and a free default", function()
	local KEYS = { gold = true, manpower = true, development = true, regiments = true, ships = true, boost = true }
	-- the three words CLAUDE.md bans everywhere, spelled backwards so they never appear in the code themselves
	local banned = { string.reverse("dog"), string.reverse("enivid"), string.reverse("yloh"), "damn", "stupid" }
	local names: { string } = {}
	for _, mapId in Maps.ids do
		for _, def in Maps.get(mapId).nations do
			table.insert(names, string.lower(def.name))
		end
	end
	local perMap: { [string]: number } = { shared = 0 }
	local ids: { [string]: boolean } = {}
	for _, def in EventCards.EVENTS do
		T.expect(not ids[def.id], "one id per event: " .. def.id)
		ids[def.id] = true
		local where = def.map or "shared"
		perMap[where] = (perMap[where] or 0) + 1
		T.expect(def.map == nil or Maps.get(def.map) ~= nil, def.id .. ": a real map")
		T.expect(def.needs == nil or def.needs == "coast" or def.needs == "fleet" or def.needs == "war", def.id)
		T.equal(#def.choices, 2, def.id .. ": two choices")
		local default = def.choices[def.default]
		T.expect(default ~= nil, def.id .. ": the default is one of them")
		T.expect((default.gold or 0) >= 0 and (default.manpower or 0) >= 0, def.id .. ": the default costs nothing")
		local text = EventText.TEXT[def.id]
		T.expect(text ~= nil, def.id .. " has its words")
		if text then
			T.equal(#text.choices, 2, def.id .. ": two choice names")
			T.expect(#text.title <= EventText.MAX_TITLE, "title too long: " .. text.title)
			T.expect(#text.line <= EventText.MAX_LINE, "line too long: " .. text.line)
			local all = { text.title, text.line }
			for i, choice in def.choices do
				local effects = 0
				for key, value in choice :: { [string]: number } do
					T.expect(KEYS[key] ~= nil and value ~= 0, def.id .. ": a known effect " .. key)
					effects += 1
				end
				T.expect(effects >= 1 and effects <= 2, def.id .. ": one or two effects a choice")
				T.expect(#text.choices[i] <= EventText.MAX_CHOICE, "choice too long: " .. text.choices[i])
				T.equal(#EventText.chips(choice, 2), effects, def.id .. ": a chip per effect")
				table.insert(all, text.choices[i])
			end
			for _, words in all do
				local lower = string.lower(words)
				for _, word in banned do
					T.expect(string.find(lower, word, 1, true) == nil, "banned word in: " .. words)
				end
				for _, name in names do
					T.expect(string.find(lower, name, 1, true) == nil, "names a nation: " .. words)
				end
			end
		end
	end
	for id in EventText.TEXT do
		T.expect(ids[id], "words for an event that doesn't exist: " .. id)
	end
	T.expect(#EventCards.EVENTS >= 30, "about thirty events")
	T.expect(perMap.shared >= 10, "a shared pool")
	for _, mapId in Maps.ids do
		T.expect((perMap[mapId] or 0) >= 6, mapId .. " has its own events")
	end
	T.equal(EventText.summary({ gold = -40, development = 1 }, 2, "Kent"), "-40 gold, +1 development in Kent")
	T.equal(EventText.summary({ manpower = 12000 }, 2), "+12,000 manpower")
	T.equal(EventText.summary({ boost = 0.25 }, 2), "+25% gold for 2 min")
	T.equal(EventText.chips({ regiments = 1, ships = 2 }, 2)[2][1], "anchor")
end)

-- Timing ---------------------------------------------------------------------------------------------------------------

T.test("each nation's first card comes at its own time; unanswered, its default happens", function()
	local state = fresh()
	local rng = Rng.new(3)
	T.equal(state.phase, "Peace", "cards come in Peace too")
	state.tick = E.FirstTicks - 1
	EventCards.step(state, rng)
	T.equal(EventCards.open(state, A), nil, "not yet")
	state.tick = E.FirstTicks
	EventCards.step(state, rng)
	local card = EventCards.open(state, A)
	T.expect(card ~= nil, "nation 1's card")
	T.equal(EventCards.open(state, B), nil, "nation 2's comes a little later")
	state.tick = E.FirstTicks + E.StaggerTicks
	EventCards.step(state, rng)
	T.expect(EventCards.open(state, B) ~= nil, "now")
	-- a known event, so the default's effect can be checked
	state.chronicles[A].card = nil
	local harvest = dealt(state, A, "Harvest")
	T.equal(harvest.untilTick, state.tick + E.ChoiceTicks)
	local gold = state.nations[A].gold
	state.tick = harvest.untilTick - 1
	EventCards.step(state, rng)
	T.expect(EventCards.open(state, A) == harvest, "it waits for an answer")
	state.tick = harvest.untilTick
	EventCards.step(state, rng)
	T.equal(EventCards.open(state, A), nil, "then closes")
	T.equal(state.nations[A].gold, gold + 50, "with its default: +50 gold")
	local last = state.chronicles[A].last :: Types.EventOutcome
	T.expect(last.card == harvest.id and last.choice == 1 and last.auto, "time ran out: the default")
	T.equal(state.chronicles[A].nextAt, state.tick + E.EveryTicks, "the next one comes a few minutes later")
end)

T.test("a whole match through the tick loop: a card every few minutes for every nation, none in Results", function()
	local state = fresh("eldmoor")
	local rng = Rng.new(11)
	for _ = 1, 10 * 60 do
		Tick.advance(state, rng)
	end
	for id, nation in state.nations do
		if not nation.eliminated then
			local c = state.chronicles[id]
			T.expect(#c.seen >= 3, "nation " .. id .. " had 3 cards in 10 minutes (" .. #c.seen .. ")")
		end
	end
	local before = state.nextCardId
	state.phase = "Results"
	state.result = { kind = "Score", winners = { A }, scores = {}, endedAt = state.tick }
	for _ = 1, E.EveryTicks + E.ChoiceTicks do
		Tick.advance(state, rng)
	end
	T.equal(state.nextCardId, before, "no cards once the match is over")
end)

-- Choices and effects ------------------------------------------------------------------------------------------------

T.test("a choice goes through the same command as every order; once, on the open card", function()
	local state = fresh()
	local card = dealt(state, A, "Harvest")
	local manpower = state.nations[A].manpower
	T.equal(select(2, choose(state, B, card, 1)), "NoEvent", "not another nation's card")
	T.equal(select(2, choose(state, A, card, 3)), "BadChoice")
	T.expect(choose(state, A, card, 2))
	T.equal(state.nations[A].manpower, manpower + 4000, "Feed the recruits: +4,000 manpower")
	local last = state.chronicles[A].last :: Types.EventOutcome
	T.expect(last.choice == 2 and not last.auto, "picked, not timed out")
	T.equal(select(2, choose(state, A, card, 1)), "NoEvent", "a late tap can't answer it again")
	local next = dealt(state, A, "Cats")
	T.equal(select(2, choose(state, A, card, 1)), "NoEvent", "nor the next card")
	T.expect(choose(state, A, next, 1))
end)

T.test("a cost must be affordable when choosing; development lands in the card's province", function()
	local state = fresh()
	local card = dealt(state, A, "Potholes")
	local p = state.provinces[card.province]
	T.equal(p.owner, A, "one of the nation's provinces")
	T.expect(p.development < Config.Economy.MaxDevelopment, "one it can still develop")
	state.nations[A].gold = 39
	T.equal(select(2, choose(state, A, card, 1)), "NotEnoughGold")
	state.nations[A].gold = 40
	local dev = p.development
	T.expect(choose(state, A, card, 1))
	T.equal(state.nations[A].gold, 0)
	T.equal(p.development, dev + 1, "Pave the roads: +1 development there")
	local map = dealt(state, A, "TreasureMap")
	state.nations[A].manpower = 999
	T.equal(select(2, choose(state, A, map, 1)), "NotEnoughManpower")
	T.expect(choose(state, A, map, 2), "the free choice is always open")
end)

T.test("regiments, ships and an income boost; a lost province's share is lost, regiments go to the capital", function()
	local state = fresh()
	local volunteers = dealt(state, A, "Volunteers")
	T.expect(choose(state, A, volunteers, 1))
	local army = Army.idleAt(state, A, volunteers.province) :: Types.Army
	T.expect(army ~= nil and army.troops.Infantry ~= nil and army.men >= 2000, "two regiments of infantry there")
	-- the province changes hands before the choice: the regiments go to the capital, development is lost
	local drills = dealt(state, A, "Drills")
	local capital = state.nations[A].capital
	for _, id in EventCards.sites(state, A, EventCards.def("Drills") :: EventCards.Def) do
		if id ~= capital then
			drills.province = id -- one that isn't the capital
		end
	end
	state.provinces[drills.province].owner = B
	local before = 0
	for _, a in state.armies do
		if a.owner == A and a.location == capital then
			before += a.men
		end
	end
	T.expect(choose(state, A, drills, 1))
	local after = 0
	for _, a in state.armies do
		if a.owner == A and a.location == capital then
			after += a.men
		end
	end
	T.equal(after, before + 3000, "three regiments at the capital instead")
	local comet = dealt(state, A, "Comet")
	state.provinces[comet.province].owner = B
	local dev = state.provinces[comet.province].development
	T.expect(choose(state, A, comet, 1))
	T.equal(state.provinces[comet.province].development, dev, "development in a lost province is lost")
	-- an income boost: gold income × 1.25 for BoostTicks, the best one counts
	local income = Economy.monthlyIncome(state, A).gold
	local inventor = dealt(state, A, "Inventor")
	T.expect(choose(state, A, inventor, 1))
	T.near(Economy.monthlyIncome(state, A).gold, income * 1.25, 1e-6, "+25% gold")
	table.insert(state.boosts, { nation = A, bonus = 0.1, untilTick = state.tick + 10 })
	T.near(Economy.boost(state, A), 0.25, 1e-9, "boosts don't stack: the best counts")
	state.tick += E.BoostTicks
	EventCards.step(state, Rng.new(1))
	T.equal(#state.boosts, 0, "boosts run out")
	T.near(Economy.monthlyIncome(state, A).gold, income, 1e-6)
	-- a fleet's event: a ship launches into the card's coast's port zone and joins the fleet there
	local coast = EventCards.sites(state, A, EventCards.def("Galleons") :: EventCards.Def)[1]
	local zone = Navy.port(state, coast) :: number
	local fleet = Navy.spawn(state, A, zone, 1)
	local galleons = dealt(state, A, "Galleons")
	T.expect(choose(state, A, galleons, 1))
	local ships = 0
	for _, f in state.fleets do
		if f.owner == A then
			ships += Navy.ships(f)
		end
	end
	T.equal(ships, 2, "one more ship")
	T.expect(fleet.hull == 2 * Config.Navy.ShipHull or galleons.province ~= coast, "joined the fleet in its port")
end)

-- Who gets what --------------------------------------------------------------------------------------------------------

T.test("a map's own events only on that map; a coast, a fleet or a war only when the nation has one", function()
	local earth, sky = fresh("earth"), fresh("skyshards")
	local function can(state: MatchState, id: string, nationId: number?): boolean
		return EventCards.eligible(state, nationId or A, EventCards.def(id) :: EventCards.Def)
	end
	T.expect(can(earth, "Harvest") and can(sky, "Harvest"), "shared events everywhere")
	T.expect(can(earth, "Joust") and not can(sky, "Joust"), "Earth's on Earth")
	T.expect(can(sky, "CargoPod") and not can(earth, "CargoPod"), "Skyshards' on Skyshards")
	T.expect(not can(earth, "Galleons"), "no fleet: no fleet events")
	local coast = EventCards.sites(earth, A, EventCards.def("FishingFleet") :: EventCards.Def)
	T.expect(#coast > 0 and can(earth, "FishingFleet"), "Rhine has a coast")
	Navy.spawn(earth, A, Navy.port(earth, coast[1]) :: number, 1)
	T.expect(can(earth, "Galleons"), "a fleet: its events")
	for _, id in coast do
		earth.provinces[id].owner = B
	end
	T.expect(not can(earth, "FishingFleet") and not can(earth, "Flotsam"), "no coast: no coastal events")
	T.expect(not can(earth, "WarChest"), "at peace: no war events")
	earth.tick, earth.phase = Config.Phases.PeaceEndTick, "War"
	earth.wars[1] = { id = 1, attackers = { A }, defenders = { B }, startedAt = earth.tick }
	T.expect(Diplomacy.atWar(earth, A, B) and can(earth, "WarChest"), "at war: war events")
end)

T.test("a nation gets each event once until it has had every one it can get", function()
	local state = fresh("skyshards")
	local rng = Rng.new(5)
	local possible = 0
	for _, def in EventCards.EVENTS do
		if EventCards.eligible(state, A, def) then
			possible += 1
		end
	end
	T.expect(possible >= 15, "plenty to draw from (" .. possible .. ")")
	local had: { [string]: boolean } = {}
	for _ = 1, possible do
		local card = EventCards.deal(state, A, rng) :: Types.EventCard
		T.expect(not had[card.event], "no repeat: " .. card.event)
		had[card.event] = true
		state.chronicles[A].card = nil
	end
	T.expect(EventCards.deal(state, A, rng) ~= nil, "then the pool starts again")
	T.equal(#state.chronicles[A].seen, 1)
end)

T.test("the match setting turns cards off (not a custom rule); the tutorial has none", function()
	local d = Settings.defaults()
	T.equal(d.events, Config.Features.Events)
	T.expect(table.find(Settings.FEATURES, "events") ~= nil and table.find(Settings.CUSTOM_FEATURES, "events") == nil)
	local s = Settings.defaults()
	T.expect(Settings.set(s, "events", false, 0, Maps.ids))
	T.equal(select(2, Settings.set(s, "events", "no", 0, Maps.ids)), "BadSetting")
	T.expect(Settings.isStandard(s), "full rewards without events")
	local state = Match.new(Maps.get("earth"), Settings.setup(true, s))
	state.tick = E.FirstTicks + 60
	EventCards.step(state, Rng.new(1))
	T.equal(state.nextCardId, 1, "no cards")
	state.setup.settings.events = true
	local card = dealt(state, A, "Cats")
	state.setup.settings.events = false
	T.equal(select(2, choose(state, A, card, 1)), "EventsOff")
	local tutorial = fresh(Config.Tutorial.Map)
	Tutorial.setup(tutorial, Config.Tutorial.PlayerSlot)
	T.equal(tutorial.setup.settings.events, false, "the tutorial plays without event cards")
end)

-- Bots and the client --------------------------------------------------------------------------------------------------

T.test("bots answer once, through the same command, with the affordable choice worth the most", function()
	local state = fresh()
	local W = Config.Bots.EventWorth
	T.equal(EventCards.worth(state, A, { gold = -20, development = 1 }), W.Development - 20)
	T.equal(EventCards.worth(state, A, { manpower = 4000 }), 4000 * W.Manpower)
	T.equal(EventCards.worth(state, A, { regiments = 2 }), 2 * W.Regiment, "in peace")
	local months = E.BoostTicks / Config.MonthTicks
	T.near(EventCards.worth(state, A, { boost = 0.2 }), 0.2 * Economy.monthlyIncome(state, A).gold * months, 1e-9)
	local card = dealt(state, A, "Traveller") -- +1 development or +2 regiments: the development is worth more
	local id, choice = EventCards.botChoice(state, A)
	T.expect(id == card.id and choice == 1, "a level of development")
	local memory = Bot.newMemory()
	local commands = Bot.plan(state, A, Rng.new(2), "Normal", memory)
	local answer: Types.Command? = nil
	for _, c in commands do
		if c.kind == "EventChoice" then
			answer = c
		end
	end
	T.expect(answer ~= nil, "the plan answers the card")
	local a = answer :: any
	T.expect(a.card == card.id and a.choice == 1)
	for _, c in Bot.plan(state, A, Rng.new(3), "Normal", memory) do
		T.expect(c.kind ~= "EventChoice", "once per card")
	end
	T.expect(Commands.apply(state, A, a), "and the server takes it")
	-- an unaffordable choice is never picked, however much it is worth
	local potholes = dealt(state, A, "Potholes")
	state.nations[A].gold = 0
	local _, pick = EventCards.botChoice(state, A)
	T.equal(pick, 2, "the free choice when the other costs too much")
	T.expect(choose(state, A, potholes, 2))
end)

T.test("a player's client hears about its own nation's card only; a nation that is gone loses its card", function()
	local state = fresh()
	local card = dealt(state, A, "Harvest")
	local mine = EventCards.view(state, A)
	T.expect(mine.card == card.id and mine.event == "Harvest" and mine.untilTick == card.untilTick)
	local theirs = EventCards.view(state, B)
	T.expect(theirs.card == 0 and theirs.event == "" and theirs.lastCard == 0, "nothing about another's card")
	T.equal(EventCards.view(state, nil).card, 0, "a spectator hears nothing")
	T.expect(choose(state, A, card, 1))
	local after = EventCards.view(state, A)
	T.expect(after.card == 0 and after.lastCard == card.id and after.lastChoice == 1 and not after.lastAuto)
	for _, v in { mine, after } do
		for key, value in v :: { [string]: any } do
			T.expect(type(value) ~= "table", "flat for the network: " .. key)
		end
	end
	local other = dealt(state, B, "Cats")
	state.nations[B].eliminated = true
	EventCards.step(state, Rng.new(1))
	T.equal(EventCards.open(state, B), nil, "an eliminated nation's card goes")
	T.equal(state.chronicles[B].last, nil, "with no effect")
	T.expect(other.id > card.id)
end)

T.finish()
