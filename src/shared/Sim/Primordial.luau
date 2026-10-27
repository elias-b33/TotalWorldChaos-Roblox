--!strict
-- Primordial powers, elimination and the Cataclysm's disasters (docs/DESIGN.md "Primordial powers",
-- "Elimination and leavers"; tick order step 6).
--
-- Who casts: a living nation pays with its own charges; an eliminated player rises as a Primordial
-- (MatchState.primordials) with charges of their own. Powers work in War and Cataclysm, never in Peace.
-- Harmful powers (Meteor, Plague, Rebels, Earthquake) respect the nation's 30 s immunity and start it again;
-- Blessing and Shield are gifts and ignore it. A Primordial may target anyone, the nation that beat them included.

local Army = require("./Army")
local Config = require("../Config")
local Events = require("./Events")
local Rng = require("./Rng")
local Types = require("../Types")

type MatchState = Types.MatchState
type Power = Types.PrimordialPower

export type TargetKind = "Army" | "Nation" | "Province"

-- A living nation (nation set) or an eliminated player's Primordial (userId set).
export type Caster = { nation: number?, userId: number? }

local Primordial = {}

-- Fixed order: events carry a power as its index in this list.
Primordial.POWERS = { "Meteor", "Plague", "Rebels", "Earthquake", "Blessing", "Shield" } :: { Power }

Primordial.TARGETS = {
	Meteor = "Army",
	Plague = "Nation",
	Rebels = "Province",
	Earthquake = "Province",
	Blessing = "Province",
	Shield = "Province",
} :: { [string]: TargetKind }

Primordial.HARMFUL = { Meteor = true, Plague = true, Rebels = true, Earthquake = true } :: { [string]: boolean }

-- What a Cataclysm disaster can be.
local DISASTERS: { Power } = { "Meteor", "Plague", "Rebels", "Earthquake" }

local function sortedKeys(t: { [number]: any }): { number }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

local function living(state: MatchState, id: number): boolean
	local n = state.nations[id]
	return n ~= nil and not n.eliminated
end

function Primordial.index(power: Power): number
	return table.find(Primordial.POWERS, power) or 0
end

function Primordial.cost(power: Power): number
	local p = Config.Primordial.Powers
	if power == "Meteor" then
		return p.Meteor.charges
	elseif power == "Plague" then
		return p.Plague.charges
	elseif power == "Rebels" then
		return p.Rebels.charges
	elseif power == "Earthquake" then
		return p.Earthquake.charges
	elseif power == "Blessing" then
		return p.Blessing.charges
	end
	return p.Shield.charges
end

-- Where a power aimed at a nation lands on the map: its capital if it still holds it, else its first province.
local function seatOf(state: MatchState, nationId: number): number
	local nation = state.nations[nationId]
	local capital = state.provinces[nation.capital]
	if capital and capital.owner == nationId then
		return nation.capital
	end
	for _, id in sortedKeys(state.provinces) do
		if state.provinces[id].owner == nationId then
			return id
		end
	end
	return nation.capital
end

-- Is this a valid target for the power? Returns the nation it hits (0 = neutral, nobody) and the province it
-- lands in, or nil and a reason code.
function Primordial.check(state: MatchState, power: Power, target: number): (number?, number, string?)
	local kind = Primordial.TARGETS[power]
	if kind == nil then
		return nil, 0, "BadRequest"
	end
	local hit, at = 0, 0
	if kind == "Army" then
		local army = state.armies[target]
		if army == nil then
			return nil, 0, "UnknownArmy"
		end
		hit, at = army.owner, army.location
	elseif kind == "Nation" then
		if not living(state, target) then
			return nil, 0, "BadTarget"
		end
		hit, at = target, seatOf(state, target)
	else
		local province = state.provinces[target]
		if province == nil then
			return nil, 0, "UnknownProvince"
		end
		if province.terrain == "Mountain" then
			return nil, 0, "BadTarget"
		end
		hit, at = province.owner or 0, target
		if power == "Earthquake" then
			if province.building == "None" then
				return nil, 0, "NoBuilding"
			end
		elseif province.owner == nil then
			return nil, 0, "BadTarget" -- Rebels, Blessing and Shield need a nation's province
		end
	end
	if Primordial.HARMFUL[power] and hit ~= 0 and state.nations[hit].powerImmuneUntil > state.tick then
		return nil, 0, "Immune"
	end
	return hit, at, nil
end

-- The effect itself, on a target that passed check().
local function strike(state: MatchState, power: Power, target: number, hit: number, at: number)
	local p = Config.Primordial.Powers
	if power == "Meteor" then
		local army = state.armies[target]
		army.men = math.floor(army.men * (1 - p.Meteor.armyLoss))
		if army.men < Config.Army.MinArmyMen then
			state.armies[target] = nil
		end
		local province = state.provinces[at]
		province.development = math.max(1, province.development - p.Meteor.developmentLoss)
	elseif power == "Plague" then
		state.nations[target].plagueUntil = state.tick + p.Plague.ticks
	elseif power == "Rebels" then
		Army.spawn(state, 0, target, p.Rebels.men)
	elseif power == "Earthquake" then
		state.provinces[target].building = "None"
	elseif power == "Blessing" then
		state.provinces[target].buffs.Blessing = state.tick + p.Blessing.ticks
	elseif power == "Shield" then
		state.provinces[target].shieldUntil = state.tick + p.Shield.ticks
	end
	if Primordial.HARMFUL[power] and hit ~= 0 then
		state.nations[hit].powerImmuneUntil = state.tick + Config.Primordial.ImmunityTicks
	end
end

-- Charges the caster has, or nil if they can't cast at all.
function Primordial.chargesOf(state: MatchState, caster: Caster): number?
	if caster.nation then
		return if living(state, caster.nation) then state.nations[caster.nation].charges else nil
	elseif caster.userId then
		local primordial = state.primordials[caster.userId]
		return if primordial then primordial.charges else nil
	end
	return nil
end

-- Cast a power: phase, charges and target are all checked here. Returns true, or false plus a reason code.
function Primordial.use(state: MatchState, caster: Caster, power: Power, target: number): (boolean, string?)
	local charges = Primordial.chargesOf(state, caster)
	if charges == nil then
		return false, "NoNation"
	end
	if Primordial.TARGETS[power] == nil then
		return false, "BadRequest"
	end
	if state.phase ~= "War" and state.phase ~= "Cataclysm" then
		return false, "NoPowersYet"
	end
	local hit, at, err = Primordial.check(state, power, target)
	if hit == nil then
		return false, err
	end
	if Primordial.HARMFUL[power] and caster.nation ~= nil and hit == caster.nation then
		return false, "OwnTarget"
	end
	local cost = Primordial.cost(power)
	if charges < cost then
		return false, "NotEnoughCharges"
	end
	if caster.nation then
		state.nations[caster.nation].charges -= cost
	elseif caster.userId then
		state.primordials[caster.userId].charges -= cost
	end
	strike(state, power, target, hit, at)
	Events.push(state, "Power", Primordial.index(power), hit, at)
	return true, nil
end

-- Effects on income (hooks for Sim/Economy) ----------------------------------------------------------

-- Blessing: +100% gold from one province.
function Primordial.goldMultiplier(state: MatchState, province: Types.Province): number
	local ends = province.buffs.Blessing
	if ends and ends > state.tick then
		return 1 + Config.Primordial.Powers.Blessing.goldBonus
	end
	return 1
end

-- Plague: -50% manpower income for one nation.
function Primordial.manpowerMultiplier(state: MatchState, nationId: number): number
	local nation = state.nations[nationId]
	local ends = nation and nation.plagueUntil
	if ends and ends > state.tick then
		return 1 - Config.Primordial.Powers.Plague.manpowerLoss
	end
	return 1
end

-- Elimination ----------------------------------------------------------------------------------------

-- A nation is eliminated when it has lost its capital and holds fewer than 3 provinces.
function Primordial.shouldEliminate(state: MatchState, nationId: number): boolean
	local nation = state.nations[nationId]
	if nation == nil or nation.eliminated then
		return false
	end
	local capital = state.provinces[nation.capital]
	if capital and capital.owner == nationId then
		return false
	end
	local held = 0
	for _, p in state.provinces do
		if p.owner == nationId then
			held += 1
		end
	end
	return held < Config.Primordial.EliminationProvinces
end

-- The nation leaves the match: its armies disband, its last provinces turn neutral (with a fresh garrison where
-- no other army stands), it drops out of its wars, alliance and offers. A player rises as a Primordial and keeps
-- the nation's unspent charges; a bot simply ends. The nation keeps its userId so a rejoining player is still
-- the Primordial.
function Primordial.eliminate(state: MatchState, nationId: number)
	local nation = state.nations[nationId]
	nation.eliminated = true

	local occupied: { [number]: boolean } = {}
	for _, a in state.armies do
		if a.owner ~= nationId then
			occupied[a.location] = true
		end
	end
	for _, id in sortedKeys(state.provinces) do
		local p = state.provinces[id]
		if p.owner == nationId then
			p.owner = nil
			p.siege = nil
			if not occupied[id] and p.terrain ~= "Mountain" then
				Army.spawn(state, 0, id, Config.NeutralGarrison)
			end
		elseif p.siege and p.siege.by == nationId then
			p.siege = nil
		end
	end
	for _, id in sortedKeys(state.armies) do
		if state.armies[id].owner == nationId then
			state.armies[id] = nil
		end
	end

	for id, war in state.wars do
		local att = table.find(war.attackers, nationId)
		if att then
			table.remove(war.attackers, att)
		end
		local def = table.find(war.defenders, nationId)
		if def then
			table.remove(war.defenders, def)
		end
		if #war.attackers == 0 or #war.defenders == 0 then
			state.wars[id] = nil
		end
	end
	local allianceId = nation.allianceId
	local alliance = if allianceId then state.alliances[allianceId] else nil
	if allianceId and alliance then
		local i = table.find(alliance.members, nationId)
		if i then
			table.remove(alliance.members, i)
		end
		if #alliance.members < 2 then
			for _, m in alliance.members do
				state.nations[m].allianceId = nil
			end
			state.alliances[allianceId] = nil
		end
	end
	nation.allianceId = nil
	local offers = {}
	for _, o in state.offers do
		if o.from ~= nationId and o.to ~= nationId then
			table.insert(offers, o)
		end
	end
	state.offers = offers

	local userId = nation.userId
	if nation.controller == "Player" and userId then
		local existing = state.primordials[userId]
		local charges =
			math.min(Config.Primordial.MaxCharges, nation.charges + (if existing then existing.charges else 0))
		state.primordials[userId] = { userId = userId, charges = charges }
	end
	nation.charges = 0
	nation.plagueUntil = nil
	Events.push(state, "Eliminated", nationId)
end

-- Charges, timers and disasters ------------------------------------------------------------------------

local function interval(state: MatchState, ticks: number): number
	local mult = if state.phase == "Cataclysm" then Config.Primordial.CataclysmChargeMultiplier else 1
	return math.max(1, math.floor(ticks / mult))
end

-- Living nations earn a charge every NationChargeTicks, Primordials every PrimordialChargeTicks; twice as fast in
-- the Cataclysm. Nobody holds more than MaxCharges.
function Primordial.charge(state: MatchState)
	local cap = Config.Primordial.MaxCharges
	if state.tick % interval(state, Config.Primordial.NationChargeTicks) == 0 then
		for _, nation in state.nations do
			if not nation.eliminated then
				nation.charges = math.min(cap, nation.charges + 1)
			end
		end
	end
	if state.tick % interval(state, Config.Primordial.PrimordialChargeTicks) == 0 then
		for _, primordial in state.primordials do
			primordial.charges = math.min(cap, primordial.charges + 1)
		end
	end
end

-- Forget plagues, blessings and shields that have run out.
function Primordial.expire(state: MatchState)
	for _, nation in state.nations do
		if nation.plagueUntil and nation.plagueUntil <= state.tick then
			nation.plagueUntil = nil
		end
	end
	for _, p in state.provinces do
		if p.shieldUntil and p.shieldUntil <= state.tick then
			p.shieldUntil = nil
		end
		for name, ends in p.buffs do
			if ends <= state.tick then
				p.buffs[name] = nil
			end
		end
	end
end

-- Every valid target for a power that hits a nation (not neutral land or garrisons), in id order.
function Primordial.targets(state: MatchState, power: Power): { number }
	local kind = Primordial.TARGETS[power]
	local pool: { [number]: any } = if kind == "Army"
		then state.armies
		elseif kind == "Nation" then state.nations
		else state.provinces
	local out = {}
	for _, id in sortedKeys(pool) do
		local hit = Primordial.check(state, power, id)
		if hit ~= nil and hit ~= 0 then
			table.insert(out, id)
		end
	end
	return out
end

-- True on the ticks a Cataclysm disaster strikes: every CataclysmDisasterTicks after the Cataclysm begins.
function Primordial.disasterDue(state: MatchState): boolean
	local since = state.tick - Config.Phases.WarEndTick
	return state.phase == "Cataclysm" and since > 0 and since % Config.Primordial.CataclysmDisasterTicks == 0
end

-- A random harmful power on a random valid target, chosen with the seeded Rng. Returns the power, or nil if
-- nothing could be hit.
function Primordial.disaster(state: MatchState, rng: Rng.Rng): Power?
	local start = Rng.int(rng, 1, #DISASTERS)
	for i = 0, #DISASTERS - 1 do
		local power = DISASTERS[(start - 1 + i) % #DISASTERS + 1]
		local options = Primordial.targets(state, power)
		if #options > 0 then
			local target = options[Rng.int(rng, 1, #options)]
			local hit, at = Primordial.check(state, power, target)
			if hit then
				strike(state, power, target, hit, at)
				Events.push(state, "Disaster", Primordial.index(power), hit, at)
				return power
			end
		end
	end
	return nil
end

-- Tick order step 6: eliminations, charges, timers, and the Cataclysm's disasters.
function Primordial.step(state: MatchState, rng: Rng.Rng)
	for _, id in sortedKeys(state.nations) do
		if Primordial.shouldEliminate(state, id) then
			Primordial.eliminate(state, id)
		end
	end
	Primordial.charge(state)
	Primordial.expire(state)
	if Primordial.disasterDue(state) then
		Primordial.disaster(state, rng)
	end
end

return Primordial
