--!strict
-- War, alliances, peace and truces (docs/DESIGN.md "Diplomacy"), plus the relation checks every other rule uses.
-- Nation 0 is "neutral" (garrisons, Rebels): hostile to everyone, friends with no one.

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

-- Armies may enter their own, allied, neutral and enemy (at war) land; never mountains or peaceful foreign land.
function Diplomacy.canEnter(state: MatchState, nationId: number, provinceId: number): boolean
	local p = state.provinces[provinceId]
	if p == nil or p.terrain == "Mountain" then
		return false
	end
	local owner = p.owner
	return owner == nil or Diplomacy.friendly(state, nationId, owner) or Diplomacy.atWar(state, nationId, owner)
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

-- Propose an alliance or peace. The other nation has Config.Diplomacy.OfferTicks to accept.
function Diplomacy.propose(
	state: MatchState,
	kind: "Ally" | "Peace",
	from: number,
	to: number,
	tribute: number
): (boolean, string?)
	if from == to or not living(state, to) then
		return false, "BadTarget"
	end
	if kind == "Ally" then
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

-- `accepter` takes the offer `from` made to them.
function Diplomacy.accept(state: MatchState, kind: "Ally" | "Peace", accepter: number, from: number): (boolean, string?)
	local i, offer = findOffer(state, kind, from, accepter)
	if i == nil or offer == nil then
		return false, "NoOffer"
	end
	if kind == "Ally" then
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

-- Drop expired offers and truces (tick order step 8).
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
end

return Diplomacy
