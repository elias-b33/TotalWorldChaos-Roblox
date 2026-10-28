--!strict
-- War, alliances, peace and truces (docs/DESIGN.md "Diplomacy"), plus the relation checks every other rule uses.
-- Nation 0 is "neutral" (garrisons, Rebels): hostile to everyone, friends with no one.
-- The EU4 pack's actions (a match setting, MatchSettings.diplomacy): insults with a pre-written joke line (the
-- insulted nation gets a short grudge, a combat bonus against the insulter, and may answer with a comeback), gifts of
-- a little gold, and military access (asked and accepted like an alliance; the guest's armies may enter the owner's
-- land for a while).

local Config = require("../Config")
local Events = require("./Events")
local Insults = require("../Flavour/Insults")
local Types = require("../Types")

type MatchState = Types.MatchState

local Diplomacy = {}

-- Relations ---------------------------------------------------------------------------------------

function Diplomacy.atWar(state: MatchState, a: number, b: number): boolean
	if a == b or a == 0 or b == 0 then
		return false
	end
	for _, war in state.wars do
		local aAtt, aDef = table.find(war.attackers, a) ~= nil, table.find(war.defenders, a) ~= nil
		local bAtt, bDef = table.find(war.attackers, b) ~= nil, table.find(war.defenders, b) ~= nil
		if (aAtt and bDef) or (aDef and bAtt) then
			return true
		end
	end
	return false
end

function Diplomacy.allied(state: MatchState, a: number, b: number): boolean
	if a == b or a == 0 or b == 0 then
		return false
	end
	local na, nb = state.nations[a], state.nations[b]
	return na ~= nil and nb ~= nil and na.allianceId ~= nil and na.allianceId == nb.allianceId
end

-- Same nation or allies: their armies fight on the same side and may share provinces.
function Diplomacy.friendly(state: MatchState, a: number, b: number): boolean
	return a == b or Diplomacy.allied(state, a, b)
end

-- Armies of hostile owners fight when they meet.
function Diplomacy.hostile(state: MatchState, a: number, b: number): boolean
	if a == b then
		return false
	end
	return a == 0 or b == 0 or Diplomacy.atWar(state, a, b)
end

function Diplomacy.hasTruce(state: MatchState, a: number, b: number): boolean
	for _, t in state.truces do
		if t.untilTick > state.tick and ((t.a == a and t.b == b) or (t.a == b and t.b == a)) then
			return true
		end
	end
	return false
end

-- True if any province of a touches a province of b (straits count).
function Diplomacy.borders(state: MatchState, a: number, b: number): boolean
	for _, p in state.provinces do
		if p.owner == a then
			for _, n in p.neighbors do
				if state.provinces[n].owner == b then
					return true
				end
			end
		end
	end
	return false
end

-- Military access: may `guest`'s armies enter `owner`'s land right now?
function Diplomacy.hasAccess(state: MatchState, guest: number, owner: number): boolean
	for _, a in state.access or {} do
		if a.guest == guest and a.owner == owner and a.untilTick > state.tick then
			return true
		end
	end
	return false
end

-- Armies may enter their own, allied, neutral and enemy (at war) land, and land they have military access to; never
-- mountains or other peaceful foreign land.
function Diplomacy.canEnter(state: MatchState, nationId: number, provinceId: number): boolean
	local p = state.provinces[provinceId]
	if p == nil or p.terrain == "Mountain" then
		return false
	end
	local owner = p.owner
	return owner == nil
		or Diplomacy.friendly(state, nationId, owner)
		or Diplomacy.atWar(state, nationId, owner)
		or Diplomacy.hasAccess(state, nationId, owner)
end

function Diplomacy.allianceMembers(state: MatchState, nationId: number): { number }
	local nation = state.nations[nationId]
	if nation and nation.allianceId then
		local alliance = state.alliances[nation.allianceId]
		if alliance then
			return table.clone(alliance.members)
		end
	end
	return { nationId }
end

-- Actions -----------------------------------------------------------------------------------------

local function nextKey(t: { [number]: any }): number
	local maxId = 0
	for id in t do
		maxId = math.max(maxId, id)
	end
	return maxId + 1
end

local function living(state: MatchState, id: number): boolean
	local n = state.nations[id]
	return n ~= nil and not n.eliminated
end

-- Declare war on a nation you border. Your allies join you and theirs join them.
function Diplomacy.declareWar(state: MatchState, a: number, b: number): (boolean, string?)
	if a == b or not living(state, b) then
		return false, "BadTarget"
	end
	if state.phase == "Peace" then
		return false, "PeaceTime"
	end
	if Diplomacy.allied(state, a, b) then
		return false, "Allied"
	end
	if Diplomacy.atWar(state, a, b) then
		return false, "AlreadyAtWar"
	end
	if Diplomacy.hasTruce(state, a, b) then
		return false, "Truce"
	end
	if not Diplomacy.borders(state, a, b) then
		return false, "NoBorder"
	end
	local attackers = Diplomacy.allianceMembers(state, a)
	local defenders = Diplomacy.allianceMembers(state, b)
	local id = nextKey(state.wars)
	state.wars[id] = { id = id, attackers = attackers, defenders = defenders, startedAt = state.tick }
	-- military access between the two sides ends with the war (their armies may enter as enemies anyway)
	local kept = {}
	for _, x in state.access or {} do
		local across = (table.find(attackers, x.owner) ~= nil and table.find(defenders, x.guest) ~= nil)
			or (table.find(defenders, x.owner) ~= nil and table.find(attackers, x.guest) ~= nil)
		if not across then
			table.insert(kept, x)
		end
	end
	state.access = kept
	Events.push(state, "WarDeclared", a, b)
	return true, nil
end

local function findOffer(state: MatchState, kind: string, from: number, to: number): (number?, Types.Offer?)
	for i, o in state.offers do
		if o.kind == kind and o.from == from and o.to == to and o.expiresAt > state.tick then
			return i, o
		end
	end
	return nil, nil
end

-- The EU4 pack's actions (insults, gifts, military access) are a match setting.
local function packOn(state: MatchState): boolean
	return state.setup.settings.diplomacy == true
end

-- Propose an alliance, peace or military access (`from` asks to march through `to`'s land). The other nation has
-- Config.Diplomacy.OfferTicks to accept.
function Diplomacy.propose(
	state: MatchState,
	kind: "Ally" | "Peace" | "Access",
	from: number,
	to: number,
	tribute: number
): (boolean, string?)
	if kind == "Access" and not packOn(state) then
		return false, "DiplomacyOff"
	end
	if from == to or not living(state, to) then
		return false, "BadTarget"
	end
	if kind == "Access" then
		if Diplomacy.atWar(state, from, to) then
			return false, "AtWar"
		end
		if Diplomacy.allied(state, from, to) then
			return false, "AlreadyAllied" -- allies march through each other's land anyway
		end
		if Diplomacy.hasAccess(state, from, to) then
			return false, "AlreadyAccess"
		end
	elseif kind == "Ally" then
		if #state.setup.settings.teams > 0 then
			return false, "TeamsLocked" -- a private server's owner set the teams (Sim.Settings)
		end
		if Diplomacy.allied(state, from, to) then
			return false, "AlreadyAllied"
		end
		if Diplomacy.atWar(state, from, to) then
			return false, "AtWar"
		end
	else
		if not Diplomacy.atWar(state, from, to) then
			return false, "NotAtWar"
		end
		if
			tribute < 0
			or tribute ~= math.floor(tribute)
			or table.find(Config.Diplomacy.PeaceTributes, tribute) == nil
		then
			return false, "BadAmount"
		end
		if state.nations[from].gold < tribute then
			return false, "NotEnoughGold"
		end
	end
	local i = findOffer(state, kind, from, to)
	if i then
		table.remove(state.offers, i) -- a new offer replaces the old one
	end
	local id = 1
	for _, o in state.offers do
		id = math.max(id, o.id + 1)
	end
	table.insert(state.offers, {
		id = id,
		kind = kind,
		from = from,
		to = to,
		tribute = if kind == "Peace" then tribute else 0,
		expiresAt = state.tick + Config.Diplomacy.OfferTicks,
	})
	Events.push(state, "Offer", from, to, id)
	return true, nil
end

local function makePeace(state: MatchState, a: number, b: number)
	-- the war between them ends for everyone in it; every former enemy pair gets a truce
	for id, war in state.wars do
		local aAtt, aDef = table.find(war.attackers, a) ~= nil, table.find(war.defenders, a) ~= nil
		local bAtt, bDef = table.find(war.attackers, b) ~= nil, table.find(war.defenders, b) ~= nil
		if (aAtt and bDef) or (aDef and bAtt) then
			for _, x in war.attackers do
				for _, y in war.defenders do
					table.insert(state.truces, { a = x, b = y, untilTick = state.tick + Config.Diplomacy.TruceTicks })
				end
			end
			state.wars[id] = nil
		end
	end
	Events.push(state, "PeaceMade", a, b)
end

local function joinAlliance(state: MatchState, a: number, b: number): (boolean, string?)
	local na, nb = state.nations[a], state.nations[b]
	if na.allianceId and nb.allianceId then
		return false, "AlreadyAllied"
	end
	local existing = na.allianceId or nb.allianceId
	if existing then
		local alliance = state.alliances[existing]
		if #alliance.members >= Config.Diplomacy.MaxAllianceSize then
			return false, "AllianceFull"
		end
		local joiner = if na.allianceId then b else a
		for _, m in alliance.members do
			if Diplomacy.atWar(state, m, joiner) then
				return false, "AtWar"
			end
		end
		table.insert(alliance.members, joiner)
		state.nations[joiner].allianceId = existing
	else
		local id = nextKey(state.alliances)
		state.alliances[id] = { id = id, members = { a, b } }
		na.allianceId = id
		nb.allianceId = id
	end
	Events.push(state, "AllianceFormed", a, b)
	return true, nil
end

-- Ally two nations straight away (a private server's locked teams at match start; Sim.Settings.prepare).
function Diplomacy.ally(state: MatchState, a: number, b: number): (boolean, string?)
	if a == b or not living(state, a) or not living(state, b) then
		return false, "BadTarget"
	end
	return joinAlliance(state, a, b)
end

-- `accepter` takes the offer `from` made to them.
function Diplomacy.accept(
	state: MatchState,
	kind: "Ally" | "Peace" | "Access",
	accepter: number,
	from: number
): (boolean, string?)
	if kind == "Access" and not packOn(state) then
		return false, "DiplomacyOff"
	end
	local i, offer = findOffer(state, kind, from, accepter)
	if i == nil or offer == nil then
		return false, "NoOffer"
	end
	if kind == "Access" then
		if Diplomacy.atWar(state, from, accepter) then
			return false, "AtWar"
		end
		-- the accepter lets the proposer's armies through its land for a while (a new grant refreshes the old one)
		local kept = {}
		for _, x in state.access do
			if not (x.owner == accepter and x.guest == from) then
				table.insert(kept, x)
			end
		end
		table.insert(kept, { owner = accepter, guest = from, untilTick = state.tick + Config.Diplomacy.AccessTicks })
		state.access = kept
		Events.push(state, "AccessGranted", accepter, from)
	elseif kind == "Ally" then
		if Diplomacy.atWar(state, from, accepter) then
			return false, "AtWar"
		end
		local ok, err = joinAlliance(state, from, accepter)
		if not ok then
			return false, err
		end
	else
		if not Diplomacy.atWar(state, from, accepter) then
			table.remove(state.offers, i)
			return false, "NotAtWar"
		end
		local payer = state.nations[from]
		if payer.gold < offer.tribute then
			return false, "NotEnoughGold"
		end
		payer.gold -= offer.tribute
		state.nations[accepter].gold += offer.tribute
		makePeace(state, from, accepter)
	end
	table.remove(state.offers, i)
	return true, nil
end

-- Insults, comebacks and gifts ----------------------------------------------------------------------------

-- Seconds (ticks) until `a` may do `kind` ("Insult" | "Gift") to `b` again; 0 = now.
function Diplomacy.cooldownLeft(state: MatchState, kind: string, a: number, b: number): number
	for _, c in state.cooldowns or {} do
		if c.kind == kind and c.a == a and c.b == b and c.untilTick > state.tick then
			return c.untilTick - state.tick
		end
	end
	return 0
end

local function startCooldown(state: MatchState, kind: string, a: number, b: number, ticks: number)
	local kept = {}
	for _, c in state.cooldowns do
		if not (c.kind == kind and c.a == a and c.b == b) then
			table.insert(kept, c)
		end
	end
	table.insert(kept, { kind = kind, a = a, b = b, untilTick = state.tick + ticks })
	state.cooldowns = kept
end

-- Does `holder` hold a grudge against `against` right now?
function Diplomacy.grudge(state: MatchState, holder: number, against: number): boolean
	for _, g in state.grudges or {} do
		if g.holder == holder and g.against == against and g.untilTick > state.tick then
			return true
		end
	end
	return false
end

-- The open comeback window of a nation insulted by `insulter` (nil if it can't answer, or answered already).
function Diplomacy.comebackWindow(state: MatchState, insulted: number, insulter: number): Types.Comeback?
	for _, w in state.comebacks or {} do
		if w.from == insulted and w.to == insulter and w.untilTick > state.tick then
			return w
		end
	end
	return nil
end

-- `from` insults `to` with a pre-written line (its number in Shared.Flavour.Insults for this map). Never an ally,
-- and once per Config.Diplomacy.InsultCooldownTicks per pair (each way). The insulted nation holds a grudge against
-- the insulter for Config.Diplomacy.GrudgeTicks (a new insult starts it again) and may answer with a comeback for
-- Config.Diplomacy.ComebackTicks.
function Diplomacy.insult(state: MatchState, from: number, to: number, line: number): (boolean, string?)
	if not packOn(state) then
		return false, "DiplomacyOff"
	end
	if from == to or not living(state, to) then
		return false, "BadTarget"
	end
	if Diplomacy.allied(state, from, to) then
		return false, "Allied"
	end
	if not Insults.valid(state.mapId, "insults", line) then
		return false, "BadRequest"
	end
	if Diplomacy.cooldownLeft(state, "Insult", from, to) > 0 then
		return false, "Cooldown"
	end
	local d = Config.Diplomacy
	startCooldown(state, "Insult", from, to, d.InsultCooldownTicks)
	local grudges = {}
	for _, g in state.grudges do
		if not (g.holder == to and g.against == from) then
			table.insert(grudges, g)
		end
	end
	table.insert(grudges, { holder = to, against = from, untilTick = state.tick + d.GrudgeTicks })
	state.grudges = grudges
	local windows = {}
	for _, w in state.comebacks do
		if not (w.from == to and w.to == from) then
			table.insert(windows, w)
		end
	end
	table.insert(windows, { from = to, to = from, line = line, untilTick = state.tick + d.ComebackTicks })
	state.comebacks = windows
	Events.push(state, "Insult", from, to, 0, nil, nil, line)
	return true, nil
end

-- `from` answers `to`'s insult with a pre-written comeback, while its window is open (once per insult). Flavour only:
-- the grudge stays as it was.
function Diplomacy.comeback(state: MatchState, from: number, to: number, line: number): (boolean, string?)
	if not packOn(state) then
		return false, "DiplomacyOff"
	end
	if not Insults.valid(state.mapId, "comebacks", line) then
		return false, "BadRequest"
	end
	local window = Diplomacy.comebackWindow(state, from, to)
	if window == nil then
		return false, "NoComeback"
	end
	local windows = {}
	for _, w in state.comebacks do
		if w ~= window then
			table.insert(windows, w)
		end
	end
	state.comebacks = windows
	Events.push(state, "Comeback", from, to, 0, nil, nil, line)
	return true, nil
end

-- `from` sends `to` Config.Diplomacy.GiftGold gold: not while they are at war, once per GiftCooldownTicks per pair.
function Diplomacy.gift(state: MatchState, from: number, to: number): (boolean, string?)
	if not packOn(state) then
		return false, "DiplomacyOff"
	end
	if from == to or not living(state, to) then
		return false, "BadTarget"
	end
	if Diplomacy.atWar(state, from, to) then
		return false, "AtWar"
	end
	if Diplomacy.cooldownLeft(state, "Gift", from, to) > 0 then
		return false, "Cooldown"
	end
	local gold = Config.Diplomacy.GiftGold
	local giver = state.nations[from]
	if giver.gold < gold then
		return false, "NotEnoughGold"
	end
	giver.gold -= gold
	state.nations[to].gold += gold
	startCooldown(state, "Gift", from, to, Config.Diplomacy.GiftCooldownTicks)
	Events.push(state, "Gift", from, to)
	return true, nil
end

-- Battle.modifier: Config.Diplomacy.GrudgeBonus for a side if one of its nations holds a grudge against one of the
-- nations it fights (the whole side shares it, like the race and catch-up bonuses; it doesn't stack).
function Diplomacy.grudgeBonus(state: MatchState, mine: { number }, theirs: { number }): number
	for _, g in state.grudges or {} do
		if g.untilTick > state.tick and table.find(mine, g.holder) and table.find(theirs, g.against) then
			return Config.Diplomacy.GrudgeBonus
		end
	end
	return 0
end

-- Drop expired offers, truces, grudges, comeback windows, waits and military access (tick order step 8), and
-- whatever involves an eliminated nation.
function Diplomacy.expire(state: MatchState)
	local offers = {}
	for _, o in state.offers do
		if o.expiresAt > state.tick then
			table.insert(offers, o)
		end
	end
	state.offers = offers
	local truces = {}
	for _, t in state.truces do
		if t.untilTick > state.tick then
			table.insert(truces, t)
		end
	end
	state.truces = truces
	local function live(list: { any }, a: string, b: string): { any }
		local out = {}
		for _, x in list do
			if x.untilTick > state.tick and living(state, x[a]) and living(state, x[b]) then
				table.insert(out, x)
			end
		end
		return out
	end
	state.grudges = live(state.grudges, "holder", "against")
	state.comebacks = live(state.comebacks, "from", "to")
	state.cooldowns = live(state.cooldowns, "a", "b")
	state.access = live(state.access, "owner", "guest")
end

return Diplomacy
