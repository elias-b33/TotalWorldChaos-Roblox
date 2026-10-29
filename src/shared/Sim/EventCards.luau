--!strict
-- The EU4 pack, stage 2: events with choices (docs/DESIGN.md "Events"). Every few minutes each living nation gets an
-- event card: a title and a line of flavour (Shared/Flavour/EventCards: game narration that only that nation's
-- player ever sees; the server sends a card to its own player alone, never in the delta) and two choices with clear
-- effects. A card waits Config.EventCards.ChoiceTicks for an answer (players tap, bots answer through the same
-- command), then its default choice happens. The pool is shared events plus each map's own (Config.EventCards
-- .Events); an event that needs a coast, a fleet or a war only comes to a nation that has one, and a nation gets each
-- event once until it has had every one it can get. A match setting (MatchSettings.events, Config.Features.Events).
-- Pure: randomness from the seeded Rng.

local Army = require("./Army")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Economy = require("./Economy")
local Navy = require("./Navy")
local Rng = require("./Rng")
local Types = require("../Types")

type MatchState = Types.MatchState
type EventCard = Types.EventCard
type Chronicle = Types.Chronicle

-- A choice's effects (Config.EventCards has what each one does).
export type Choice = {
	gold: number?,
	manpower: number?,
	development: number?,
	regiments: number?,
	ships: number?,
	boost: number?,
}

export type Def = {
	id: string,
	map: string?,
	needs: string?, -- "coast" | "fleet" | "war"
	default: number,
	choices: { Choice },
}

local E = Config.EventCards
local ACTIVE_PHASES = { Peace = true, War = true, Cataclysm = true }

local EventCards = {}

EventCards.EVENTS = E.Events :: { Def }

local byId: { [string]: Def } = {}
for _, def in EventCards.EVENTS do
	byId[def.id] = def
end

function EventCards.def(id: string): Def?
	return byId[id]
end

-- Is the setting on in this match?
function EventCards.enabled(state: MatchState): boolean
	return state.setup.settings.events == true
end

-- Rules ---------------------------------------------------------------------------------------------------------------

local function sortedKeys(t: { [number]: any }): { number }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function living(state: MatchState, nationId: number): boolean
	local nation = state.nations[nationId]
	return nation ~= nil and not nation.eliminated
end

local function atWarWithAnyone(state: MatchState, nationId: number): boolean
	for id in state.nations do
		if Diplomacy.atWar(state, nationId, id) then
			return true
		end
	end
	return false
end

local function hasFleet(state: MatchState, nationId: number): boolean
	for _, fleet in state.fleets or {} do
		if fleet.owner == nationId then
			return true
		end
	end
	return false
end

-- Does a choice land in a province (and so the card needs one)?
local function placed(choice: Choice): boolean
	return (choice.development or 0) > 0 or (choice.regiments or 0) > 0 or (choice.ships or 0) > 0
end

local function needsProvince(def: Def): boolean
	for _, c in def.choices do
		if placed(c) then
			return true
		end
	end
	return def.needs == "coast" or def.needs == "fleet"
end

local function develops(def: Def): boolean
	for _, c in def.choices do
		if (c.development or 0) > 0 then
			return true
		end
	end
	return false
end

-- The provinces a card of this event could be about: the nation's own, on a coast when it needs one (a fleet's ships
-- launch from there), under the top development when a choice develops it. Sorted.
function EventCards.sites(state: MatchState, nationId: number, def: Def): { number }
	local out = {}
	local coastal = def.needs == "coast" or def.needs == "fleet"
	local growing = develops(def)
	for _, id in sortedKeys(state.provinces) do
		local p = state.provinces[id]
		if
			p.owner == nationId
			and (not coastal or Navy.port(state, id) ~= nil)
			and (not growing or p.development < Config.Economy.MaxDevelopment)
		then
			table.insert(out, id)
		end
	end
	return out
end

-- Could this nation get this event now? Its map, what it needs, and a province for it if it needs one.
function EventCards.eligible(state: MatchState, nationId: number, def: Def): boolean
	if def.map ~= nil and def.map ~= state.mapId then
		return false
	end
	if def.needs == "war" and not atWarWithAnyone(state, nationId) then
		return false
	end
	if def.needs == "fleet" and not hasFleet(state, nationId) then
		return false
	end
	return not needsProvince(def) or #EventCards.sites(state, nationId, def) > 0
end

local function chronicleOf(state: MatchState, nationId: number): Chronicle
	local chronicles = state.chronicles
	local c = chronicles[nationId]
	if c == nil then
		c = { nextAt = E.FirstTicks + (nationId - 1) * E.StaggerTicks, seen = {}, card = nil, last = nil }
		chronicles[nationId] = c
	end
	return c
end

-- The nation's open card, if it has one.
function EventCards.open(state: MatchState, nationId: number): EventCard?
	local c = state.chronicles and state.chronicles[nationId]
	return if c then c.card else nil
end

-- Deal this nation a card now, from the events it may get that it hasn't had yet (all of them again once it has had
-- every one). nil when there is none it may get.
function EventCards.deal(state: MatchState, nationId: number, rng: Rng.Rng): EventCard?
	local c = chronicleOf(state, nationId)
	local fresh, all = {}, {}
	for _, def in EventCards.EVENTS do
		if EventCards.eligible(state, nationId, def) then
			table.insert(all, def)
			if table.find(c.seen, def.id) == nil then
				table.insert(fresh, def)
			end
		end
	end
	if #all == 0 then
		return nil
	end
	if #fresh == 0 then
		c.seen = {}
		fresh = all
	end
	local def = fresh[Rng.int(rng, 1, #fresh)]
	local province = 0
	if needsProvince(def) then
		local sites = EventCards.sites(state, nationId, def)
		province = sites[Rng.int(rng, 1, #sites)]
	end
	local card: EventCard =
		{ id = state.nextCardId, event = def.id, province = province, untilTick = state.tick + E.ChoiceTicks }
	state.nextCardId += 1
	table.insert(c.seen, def.id)
	c.card = card
	return card
end

-- Can the nation pay this choice's costs (negative gold or manpower) right now?
function EventCards.affordable(state: MatchState, nationId: number, choice: Choice): boolean
	local nation = state.nations[nationId]
	return nation.gold >= -math.min(0, choice.gold or 0) and nation.manpower >= -math.min(0, choice.manpower or 0)
end

-- Where a card's regiments go: its province while the nation holds it, else the capital, else nowhere.
local function barracks(state: MatchState, nationId: number, card: EventCard): number?
	local p = state.provinces[card.province]
	if p and p.owner == nationId then
		return card.province
	end
	local capital = state.provinces[state.nations[nationId].capital]
	if capital and capital.owner == nationId then
		return state.nations[nationId].capital
	end
	return nil
end

local function apply(state: MatchState, nationId: number, card: EventCard, choice: Choice)
	local nation = state.nations[nationId]
	nation.gold += choice.gold or 0
	nation.manpower += choice.manpower or 0
	local p = state.provinces[card.province]
	local held = p ~= nil and p.owner == nationId
	if (choice.development or 0) > 0 and p and held then
		p.development = math.min(Config.Economy.MaxDevelopment, p.development + (choice.development :: number))
	end
	if (choice.regiments or 0) > 0 then
		local where = barracks(state, nationId, card)
		if where then
			Army.reinforce(state, nationId, where, (choice.regiments :: number) * Config.Army.MenPerRegiment)
		end
	end
	local zone = if held then Navy.port(state, card.province) else nil
	if (choice.ships or 0) > 0 and zone then
		local ships = choice.ships :: number
		local fleet = Navy.idleAt(state, nationId, zone)
		if fleet then
			fleet.hull += ships * Config.Navy.ShipHull
		else
			Navy.spawn(state, nationId, zone, ships)
		end
	end
	if (choice.boost or 0) > 0 then
		local boost = { nation = nationId, bonus = choice.boost :: number, untilTick = state.tick + E.BoostTicks }
		table.insert(state.boosts, boost)
	end
end

-- Close the nation's open card with this choice (its effects happen) and set when the next one comes.
local function close(state: MatchState, nationId: number, index: number, auto: boolean)
	local c = chronicleOf(state, nationId)
	local card = c.card :: EventCard
	local def = EventCards.def(card.event) :: Def
	apply(state, nationId, card, def.choices[index])
	c.card = nil
	c.last = { card = card.id, event = card.event, province = card.province, choice = index, auto = auto }
	c.nextAt = state.tick + E.EveryTicks
end

-- The EventChoice command: choice 1 or 2 on the nation's open card `cardId`. Refused once the card has closed (a
-- late tap can't answer the next card), or when the choice costs more than the nation has.
function EventCards.choose(state: MatchState, nationId: number, cardId: number, index: number): (boolean, string?)
	if not EventCards.enabled(state) then
		return false, "EventsOff"
	end
	local card = EventCards.open(state, nationId)
	if card == nil or card.id ~= cardId then
		return false, "NoEvent"
	end
	local def = EventCards.def(card.event) :: Def
	local choice = def.choices[index]
	if choice == nil then
		return false, "BadChoice"
	end
	if not EventCards.affordable(state, nationId, choice) then
		local short = state.nations[nationId].gold < -math.min(0, choice.gold or 0)
		return false, if short then "NotEnoughGold" else "NotEnoughManpower"
	end
	close(state, nationId, index, false)
	return true, nil
end

-- Tick order step 8: unanswered cards whose time ran out take their default choice; nations whose next card is due
-- get one (in Peace, War and the Cataclysm); boosts that ran out go; an eliminated nation's open card goes with it.
function EventCards.step(state: MatchState, rng: Rng.Rng)
	if not EventCards.enabled(state) then
		return
	end
	if state.chronicles == nil then
		state.chronicles = {}
	end
	if state.boosts == nil then
		state.boosts = {}
	end
	if state.nextCardId == nil then
		state.nextCardId = 1
	end
	local kept = {}
	for _, b in state.boosts do
		if b.untilTick > state.tick then
			table.insert(kept, b)
		end
	end
	state.boosts = kept
	for _, id in sortedKeys(state.nations) do
		local c = chronicleOf(state, id)
		local card = c.card
		if not living(state, id) then
			c.card = nil
		elseif card ~= nil then
			if state.tick >= card.untilTick then
				close(state, id, (EventCards.def(card.event) :: Def).default, true)
			end
		elseif state.tick >= c.nextAt and ACTIVE_PHASES[state.phase] then
			if EventCards.deal(state, id, rng) == nil then
				c.nextAt = state.tick + E.EveryTicks -- nothing it may get now: try again later
			end
		end
	end
end

-- Studio's DevEvent switch (DevService, docs/STUDIO.md): every nation's next card comes in `ticks` (from the next
-- step on; an open card stays open).
function EventCards.soon(state: MatchState, ticks: number)
	for _, id in sortedKeys(state.nations) do
		chronicleOf(state, id).nextAt = state.tick + ticks
	end
end

-- Bots -----------------------------------------------------------------------------------------------------------------

-- What a choice is worth to this nation, in gold (Config.Bots.EventWorth): gold, manpower at the regiment's price
-- ratio, development, regiments (more at war), ships, and an income boost at the nation's income now.
function EventCards.worth(state: MatchState, nationId: number, choice: Choice): number
	local w = Config.Bots.EventWorth
	local regiment = if atWarWithAnyone(state, nationId) then w.RegimentAtWar else w.Regiment
	local value = (choice.gold or 0)
		+ (choice.manpower or 0) * w.Manpower
		+ (choice.development or 0) * w.Development
		+ (choice.regiments or 0) * regiment
		+ (choice.ships or 0) * w.Ship
	if (choice.boost or 0) > 0 then
		local months = E.BoostTicks / Config.MonthTicks
		value += (choice.boost :: number) * Economy.monthlyIncome(state, nationId).gold * months
	end
	return value
end

-- A bot's answer to its open card: the affordable choice worth the most (the default on a tie). nil without a card.
function EventCards.botChoice(state: MatchState, nationId: number): (number?, number?)
	local card = EventCards.open(state, nationId)
	if card == nil then
		return nil, nil
	end
	local def = EventCards.def(card.event) :: Def
	local best, bestWorth = def.default, EventCards.worth(state, nationId, def.choices[def.default])
	for i, choice in def.choices do
		local value = EventCards.worth(state, nationId, choice)
		if i ~= def.default and value > bestWorth and EventCards.affordable(state, nationId, choice) then
			best, bestWorth = i, value
		end
	end
	return card.id, best
end

-- The client ------------------------------------------------------------------------------------------------------------

-- What this nation's player is told (Types.EventCardView): its open card and its last closed one. Sent to that
-- player alone (Replicator.sendCards).
function EventCards.view(state: MatchState, nationId: number?): Types.EventCardView
	local c = if nationId and state.chronicles then state.chronicles[nationId] else nil
	local card = if c then c.card else nil
	local last = if c then c.last else nil
	return {
		card = if card then card.id else 0,
		event = if card then card.event else "",
		province = if card then card.province else 0,
		untilTick = if card then card.untilTick else 0,
		lastCard = if last then last.card else 0,
		lastEvent = if last then last.event else "",
		lastProvince = if last then last.province else 0,
		lastChoice = if last then last.choice else 0,
		lastAuto = if last then last.auto else false,
	}
end

return EventCards
