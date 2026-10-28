--!strict
-- War, alliances, peace and truces (docs/DESIGN.md "Diplomacy"), plus the relation checks every other rule uses.
-- Nation 0 is "neutral" (garrisons, Rebels): hostile to everyone, friends with no one.
-- The EU4 pack's actions (a match setting, MatchSettings.diplomacy): insults, an action with no message (the
-- insulted nation gets a short grudge, a combat bonus against the insulter, and may insult back or laugh it off),
-- gifts of a little gold, and military access (asked and accepted like an alliance; the guest's armies may enter the owner's
-- land for a while, and walk home when it ends: Diplomacy.endedAccess, Movement.endAccess).

local Config = require("../Config")
local Events = require("./Events")
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
	-- military access between the two sides ends with the war (Diplomacy.endedAccess, the next movement step)
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

-- Insults and gifts --------------------------------------------------------------------------------------------
-- An insult is a diplomatic action with no message (Roblox's preset-text rule: docs/DESIGN.md "Diplomacy"): the
-- others only learn that it happened. Its answers (insult back, laugh it off) are actions too.

-- Seconds (ticks) until `a` may do `kind` again: "Insult" to `b`, "Gift" to anyone (b = 0). 0 = now.
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

-- Does `holder` hold a grudge against `against` right now? (against = 0: is `holder` in high spirits?)
function Diplomacy.grudge(state: MatchState, holder: number, against: number): boolean
	for _, g in state.grudges or {} do
		if g.holder == holder and g.against == against and g.untilTick > state.tick then
			return true
		end
	end
	return false
end

-- Start (or restart) `holder`'s grudge against `against` (0 = high spirits) for `ticks`.
local function setGrudge(state: MatchState, holder: number, against: number, ticks: number)
	local kept = {}
	for _, g in state.grudges do
		if not (g.holder == holder and g.against == against) then
			table.insert(kept, g)
		end
	end
	if ticks > 0 then
		table.insert(kept, { holder = holder, against = against, untilTick = state.tick + ticks })
	end
	state.grudges = kept
end

-- The open answer window of a nation insulted by `insulter` (nil if it can't answer, or answered already).
function Diplomacy.answerWindow(state: MatchState, insulted: number, insulter: number): Types.Answer?
	for _, w in state.answers or {} do
		if w.from == insulted and w.to == insulter and w.untilTick > state.tick then
			return w
		end
	end
	return nil
end

local function closeWindow(state: MatchState, insulted: number, insulter: number)
	local kept = {}
	for _, w in state.answers do
		if not (w.from == insulted and w.to == insulter) then
			table.insert(kept, w)
		end
	end
	state.answers = kept
end

-- The checks every insult and answer share: the setting, a living other nation, never an ally.
local function mayInsult(state: MatchState, from: number, to: number): (boolean, string?)
	if not packOn(state) then
		return false, "DiplomacyOff"
	end
	if from == to or not living(state, to) then
		return false, "BadTarget"
	end
	if Diplomacy.allied(state, from, to) then
		return false, "Allied"
	end
	return true, nil
end

-- `from` insults `to`. Never an ally, and once per Config.Diplomacy.InsultCooldownTicks per pair (each way). The
-- insulted nation holds a grudge against the insulter for Config.Diplomacy.GrudgeTicks (a new insult starts it again)
-- and may answer for Config.Diplomacy.AnswerTicks.
function Diplomacy.insult(state: MatchState, from: number, to: number): (boolean, string?)
	local ok, err = mayInsult(state, from, to)
	if not ok then
		return false, err
	end
	if Diplomacy.cooldownLeft(state, "Insult", from, to) > 0 then
		return false, "Cooldown"
	end
	local d = Config.Diplomacy
	startCooldown(state, "Insult", from, to, d.InsultCooldownTicks)
	setGrudge(state, to, from, d.GrudgeTicks)
	closeWindow(state, to, from)
	table.insert(state.answers, { from = to, to = from, untilTick = state.tick + d.AnswerTicks })
	Events.push(state, "Insult", from, to)
	return true, nil
end

-- `from` answers `to`'s insult in kind, while its answer window is open (once per insult): now `to` holds a grudge
-- against `from` too. It needn't wait for `from`'s own insult wait, but starts it; `to` gets no answer window (the
-- exchange is over). `from`'s grudge stays.
function Diplomacy.insultBack(state: MatchState, from: number, to: number): (boolean, string?)
	local ok, err = mayInsult(state, from, to)
	if not ok then
		return false, err
	end
	if Diplomacy.answerWindow(state, from, to) == nil then
		return false, "NoAnswer"
	end
	local d = Config.Diplomacy
	closeWindow(state, from, to)
	startCooldown(state, "Insult", from, to, d.InsultCooldownTicks)
	setGrudge(state, to, from, d.GrudgeTicks)
	Events.push(state, "InsultBack", from, to)
	return true, nil
end

-- `from` laughs `to`'s insult off, while its answer window is open: its grudge against `to` ends, and it is in high
-- spirits (Config.Diplomacy.LaughBonus in every battle) for Config.Diplomacy.LaughTicks.
function Diplomacy.laughOff(state: MatchState, from: number, to: number): (boolean, string?)
	if not packOn(state) then
		return false, "DiplomacyOff"
	end
	if Diplomacy.answerWindow(state, from, to) == nil then
		return false, "NoAnswer"
	end
	closeWindow(state, from, to)
	setGrudge(state, from, to, 0)
	setGrudge(state, from, 0, Config.Diplomacy.LaughTicks)
	Events.push(state, "LaughedOff", from, to)
	return true, nil
end

-- `from` sends `to` Config.Diplomacy.GiftGold gold: not while they are at war, and one gift per GiftCooldownTicks
-- whoever it goes to (the wait is stored against nation 0), so gifts stay a little gold.
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
	if Diplomacy.cooldownLeft(state, "Gift", from, 0) > 0 then
		return false, "Cooldown"
	end
	local gold = Config.Diplomacy.GiftGold
	local giver = state.nations[from]
	if giver.gold < gold then
		return false, "NotEnoughGold"
	end
	giver.gold -= gold
	state.nations[to].gold += gold
	startCooldown(state, "Gift", from, 0, Config.Diplomacy.GiftCooldownTicks)
	Events.push(state, "Gift", from, to)
	return true, nil
end

-- Battle.modifier: Config.Diplomacy.GrudgeBonus for a side if one of its nations holds a grudge against one of the
-- nations it fights, else Config.Diplomacy.LaughBonus if one of its nations is in high spirits (the whole side shares
-- it, like the race and catch-up bonuses; they don't stack: the best one counts).
function Diplomacy.grudgeBonus(state: MatchState, mine: { number }, theirs: { number }): number
	local best = 0
	for _, g in state.grudges or {} do
		if g.untilTick > state.tick and table.find(mine, g.holder) then
			if g.against == 0 then
				best = math.max(best, Config.Diplomacy.LaughBonus)
			elseif table.find(theirs, g.against) then
				best = math.max(best, Config.Diplomacy.GrudgeBonus)
			end
		end
	end
	return best
end

-- Military access that ended: it ran out, the two are at war, or one of them is gone. Removes those grants and
-- returns them, so the movement step (Movement.endAccess, tick order step 2) sends the guests' armies home.
function Diplomacy.endedAccess(state: MatchState): { Types.Access }
	local kept, ended = {}, {}
	for _, x in state.access or {} do
		if
			x.untilTick > state.tick
			and living(state, x.owner)
			and living(state, x.guest)
			and not Diplomacy.atWar(state, x.owner, x.guest)
		then
			table.insert(kept, x)
		else
			table.insert(ended, x)
		end
	end
	if #ended > 0 then
		state.access = kept
	end
	return ended
end

-- Drop expired offers, truces, grudges, answer windows and waits (tick order step 8), and whatever involves an
-- eliminated nation. Military access ends in the movement step instead (Diplomacy.endedAccess).
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
	-- the second nation may be 0 (high spirits; a gift's wait): it stands for anyone
	local function live(list: { any }, a: string, b: string): { any }
		local out = {}
		for _, x in list do
			if x.untilTick > state.tick and living(state, x[a]) and (x[b] == 0 or living(state, x[b])) then
				table.insert(out, x)
			end
		end
		return out
	end
	state.grudges = live(state.grudges, "holder", "against")
	state.answers = live(state.answers, "from", "to")
	state.cooldowns = live(state.cooldowns, "a", "b")
end

return Diplomacy
