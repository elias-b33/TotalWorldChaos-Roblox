--!strict
-- Battles (tick order step 3, docs/DESIGN.md "Armies and combat"): when hostile armies share a province they fight up
-- to Config.Battle.Rounds rounds, one per tick. Each round, each side kills enemy men equal to KillRatePerRound × its
-- own strength × modifiers. A side's strength is the sum of its men × each troop's attack (attackers) or defence
-- (defenders), with the specials' terrain and anti-garrison tricks and each troop's counter against the other side's
-- mix (Troops.strength); losses split over an army's troop types in proportion to their men (Army.shrinkTo). Race
-- bonuses (Sim.Races), the catch-up rules and flanking (Battle.directions) add to the modifier.
-- Every round also costs both sides morale (Battle.moraleDrop). A side whose morale breaks loses at once; else after
-- the last round the side with fewer men loses (Battle.loser). The loser walks to its nearest owned province
-- (Pathing.retreatPath) at its own speed, can't take orders, and doesn't fight, block or besiege on the way
-- (Army.retreating). Armies under MinArmyMen are destroyed, and so is a loser with no way home. Out of battle, morale
-- comes back in steps (Battle.recoverMorale).
-- Each battle keeps an account of what each side's flank and troop counters did (the enemy men they killed and the
-- morale those losses cost), so the BattleEnded event can say whether a flank or the counters decided it: whether,
-- without them, the other side would have won.

local Army = require("./Army")
local CatchUp = require("./CatchUp")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Events = require("./Events")
local Pathing = require("./Pathing")
local Races = require("./Races")
local Rng = require("./Rng")
local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState
type Army = Types.Army
type BattleEdge = Types.BattleEdge

export type Sides = {
	defenderOwner: number,
	defenders: { Army },
	attackers: { Army },
}

-- Extra combat strength for a side (catch-up rules plug in here). Owners are the nations fighting on that side.
export type BonusFn = (state: MatchState, owners: { number }, enemies: { number }, defending: boolean) -> number

-- One side of a battle as Battle.outcome plays it out: its men, the enemy men each of its men kills in a round
-- (strength × modifier × KillRatePerRound / men) and its morale.
export type Fighter = { men: number, rate: number, morale: number }

export type Loser = "attackers" | "defenders"

local Battle = {}

Battle.bonus = CatchUp.battleBonus :: BonusFn

-- Who fights whom in a province. Defenders: the province owner's side if present, else the neutral garrison,
-- else whoever is first (lowest army id). Attackers: every army hostile to the defenders.
function Battle.sides(state: MatchState, provinceId: number, armies: { Army }): Sides?
	if #armies < 2 then
		return nil
	end
	local province = state.provinces[provinceId]
	local defenderOwner = armies[1].owner
	local owner = province.owner
	for _, a in armies do
		if owner ~= nil and Diplomacy.friendly(state, a.owner, owner) then
			defenderOwner = a.owner
			break
		elseif owner == nil and a.owner == 0 then
			defenderOwner = 0
		end
	end
	local defenders, attackers = {}, {}
	for _, a in armies do
		if a.owner == defenderOwner or (defenderOwner ~= 0 and Diplomacy.friendly(state, a.owner, defenderOwner)) then
			table.insert(defenders, a)
		elseif Diplomacy.hostile(state, a.owner, defenderOwner) then
			table.insert(attackers, a)
		end
	end
	if #defenders == 0 or #attackers == 0 then
		return nil
	end
	return { defenderOwner = defenderOwner, defenders = defenders, attackers = attackers }
end

local function men(side: { Army }): number
	local n = 0
	for _, a in side do
		n += a.men
	end
	return n
end

-- Men per troop type of a whole side (what the other side's counters look at).
function Battle.composition(side: { Army }): Types.Composition
	local out: Types.Composition = {}
	for _, a in side do
		for _, troop in Troops.LIST do
			local n = a.troops[troop]
			if n then
				out[troop] = (out[troop] or 0) + n
			end
		end
	end
	return out
end

-- A side's combat strength before modifiers: each troop's men × its defence (defenders) or attack (attackers), with
-- the specials' tricks for a battle in `terrain` (and against neutral armies: `vsNeutral`), and with the enemy's
-- composition (`enemy`) each troop's counter against it.
function Battle.strength(
	side: { Army },
	defending: boolean,
	terrain: Types.Terrain?,
	vsNeutral: boolean?,
	enemy: Types.Composition?
): number
	local s = 0
	for _, a in side do
		s += Troops.strength(a.troops, defending, terrain, vsNeutral, enemy)
	end
	return s
end

-- How many directions a side came into its battle from: each army's `from` (the province it stepped in from), or
-- the battle's province for an army that was already standing there (Army.from is nil once it settles: defenders at
-- home, besiegers, armies just raised or landed).
function Battle.directions(side: { Army }): number
	local seen: { [number]: boolean } = {}
	local n = 0
	for _, a in side do
		local d = a.from or a.location
		if not seen[d] then
			seen[d] = true
			n += 1
		end
	end
	return n
end

-- The flank bonus for a side that came from `directions` directions: FlankBonus per extra one, up to FlankMaxExtra.
function Battle.flankBonus(directions: number): number
	return Config.Battle.FlankBonus * math.clamp(directions - 1, 0, Config.Battle.FlankMaxExtra)
end

-- A side's morale: its armies' morale averaged by their men (full for a side without men).
function Battle.morale(side: { Army }): number
	local total, sum = 0, 0
	for _, a in side do
		total += a.men
		sum += a.men * a.morale
	end
	return if total > 0 then sum / total else Config.Battle.MoraleMax
end

-- The morale a round costs a side that lost `lost` of its `of` men: MoraleShock × the share lost + MoraleDrain, in
-- whole points.
function Battle.moraleDrop(lost: number, of: number): number
	local share = if of > 0 then math.min(lost / of, 1) else 1
	return math.floor(Config.Battle.MoraleShock * share + Config.Battle.MoraleDrain + 0.5)
end

-- Who loses, after a round (nil: they fight on): a side with no men left; else a side whose morale broke (both broke:
-- the lower morale); else, after the last round, the side with fewer men (the defenders win a tie). The second result
-- says whether the loser broke.
function Battle.loser(
	attMen: number,
	attMorale: number,
	defMen: number,
	defMorale: number,
	lastRound: boolean
): (Loser?, boolean)
	local byMen: Loser = if attMen > defMen then "defenders" else "attackers"
	if attMen <= 0 or defMen <= 0 then
		return byMen, false
	end
	local limit = Config.Battle.MoraleBreak
	local attBroke, defBroke = attMorale <= limit, defMorale <= limit
	if attBroke ~= defBroke then
		return if attBroke then "attackers" else "defenders", true
	elseif attBroke then
		if attMorale ~= defMorale then
			return if attMorale < defMorale then "attackers" else "defenders", true
		end
		return byMen, true
	elseif lastRound then
		return byMen, false
	end
	return nil, false
end

-- Plays out a battle between two sides that don't change (Battle.step's rules on whole sides): does `a` win, and
-- with how many men left? Bots judge attacks and defences with it.
function Battle.outcome(a: Fighter, b: Fighter, aDefends: boolean): (boolean, number)
	local am, bm, amo, bmo = a.men, b.men, a.morale, b.morale
	for round = 1, Config.Battle.Rounds do
		local aLost, bLost = math.min(bm * b.rate, am), math.min(am * a.rate, bm)
		amo = math.max(0, amo - Battle.moraleDrop(aLost, am))
		bmo = math.max(0, bmo - Battle.moraleDrop(bLost, bm))
		am, bm = am - aLost, bm - bLost
		local last = round == Config.Battle.Rounds
		local lost = if aDefends then Battle.loser(bm, bmo, am, amo, last) else Battle.loser(am, amo, bm, bmo, last)
		if lost then
			return (lost == "defenders") ~= aDefends, am
		end
	end
	return false, am
end

-- Is every army on this side neutral (garrisons and Rebels)?
local function allNeutral(side: { Army }): boolean
	for _, a in side do
		if a.owner ~= 0 then
			return false
		end
	end
	return true
end

local function owners(side: { Army }): { number }
	local out = {}
	for _, a in side do
		if table.find(out, a.owner) == nil then
			table.insert(out, a.owner)
		end
	end
	return out
end

-- Kills `losses` men of a side (every army and troop type loses its share); returns the men it really lost.
local function takeLosses(side: { Army }, losses: number): number
	local total = men(side)
	if total <= 0 then
		return 0
	end
	for _, a in side do
		Army.shrinkTo(a, math.floor(a.men - losses * a.men / total + 0.5)) -- every troop type loses its share
	end
	return total - men(side)
end

local function lowerMorale(side: { Army }, drop: number)
	for _, a in side do
		a.morale = math.max(0, a.morale - drop)
	end
end

-- Combat multiplier for one side this round: its terrain, fort, race, flank and catch-up bonuses and its roll.
function Battle.modifier(state: MatchState, provinceId: number, sides: Sides, defending: boolean, roll: number): number
	local province = state.provinces[provinceId]
	local m = 1 + roll
	if defending then
		if province.terrain == "Forest" or province.terrain == "Hills" then
			m += Config.Battle.TerrainDefenceBonus
		end
		if
			province.building == "Fort"
			and province.owner ~= nil
			and Diplomacy.friendly(state, province.owner, sides.defenderOwner)
		then
			m += Config.Buildings.Fort.defenceBonus
		end
	end
	local side = if defending then sides.defenders else sides.attackers
	local mine = owners(side)
	local theirs = owners(if defending then sides.attackers else sides.defenders)
	m += Races.battleBonus(state, province, mine, defending) -- Forest in forest, Hills defending hills, Attack
	m += Battle.flankBonus(Battle.directions(side))
	return math.max(0.1, m + Battle.bonus(state, mine, theirs, defending))
end

local function newEdge(): BattleEdge
	return { flankMen = 0, flankMorale = 0, counterMen = 0, counterMorale = 0 }
end

-- One side's blows in a round: the enemy men it kills, and the shares of them its flank and its counters account for.
type Blow = { kills: number, flankShare: number, counterShare: number }

local function blow(state: MatchState, provinceId: number, sides: Sides, defending: boolean, roll: number): Blow
	local side = if defending then sides.defenders else sides.attackers
	local enemy = if defending then sides.attackers else sides.defenders
	local terrain = state.provinces[provinceId].terrain
	local neutral = allNeutral(enemy)
	local plain = Battle.strength(side, defending, terrain, neutral)
	local full = Battle.strength(side, defending, terrain, neutral, Battle.composition(enemy))
	local mod = Battle.modifier(state, provinceId, sides, defending, roll)
	return {
		kills = full * Config.Battle.KillRatePerRound * mod,
		flankShare = math.min(Battle.flankBonus(Battle.directions(side)) / mod, 1),
		counterShare = if full > 0 then (full - plain) / full else 0,
	}
end

-- Books what a side's flank and counters did this round: the enemy lost `lost` of its `of` men to its blow.
local function credit(edge: BattleEdge, b: Blow, lost: number, of: number)
	local perMan = if of > 0 then Config.Battle.MoraleShock / of else 0
	local flankMen, counterMen = lost * b.flankShare, lost * b.counterShare
	edge.flankMen += flankMen
	edge.flankMorale += flankMen * perMan
	edge.counterMen += counterMen
	edge.counterMorale += counterMen * perMan
end

-- Would the battle have gone the other way without the flank (`counters` false) or the troop counters (true)? Each
-- side gets back the men, and the morale, that the other side's flank or counters took from it, and the result is
-- worked out again (by the last round's rule when nobody would have broken).
local function decided(
	battle: Types.Battle,
	lost: Loser,
	att: number,
	attMorale: number,
	def: number,
	defMorale: number,
	counters: boolean
): boolean
	local a, d = battle.attackerEdge, battle.defenderEdge
	local again = if counters
		then Battle.loser(
			att + d.counterMen,
			attMorale + d.counterMorale,
			def + a.counterMen,
			defMorale + a.counterMorale,
			true
		)
		else Battle.loser(
			att + d.flankMen,
			attMorale + d.flankMorale,
			def + a.flankMen,
			defMorale + a.flankMorale,
			true
		)
	return again ~= lost
end

local function finish(
	state: MatchState,
	provinceId: number,
	sides: Sides,
	battle: Types.Battle,
	lost: Loser,
	broke: boolean
)
	local attMen, defMen = men(sides.attackers), men(sides.defenders)
	local attMorale, defMorale = Battle.morale(sides.attackers), Battle.morale(sides.defenders)
	local winners, losers = sides.defenders, sides.attackers
	if lost == "defenders" then
		winners, losers = sides.attackers, sides.defenders
	end
	local flank = decided(battle, lost, attMen, attMorale, defMen, defMorale, false)
	local counter = decided(battle, lost, attMen, attMorale, defMen, defMorale, true)
	local outnumbered = men(winners) < men(losers)
	for _, owner in owners(winners) do
		local nation = state.nations[owner]
		if nation then
			nation.battlesWon += 1
		end
	end
	-- losers retreat (or are destroyed if they have nowhere to go); tiny armies are destroyed either way
	for _, a in losers do
		local path = if a.owner ~= 0 then Pathing.retreatPath(state, a.owner, provinceId) else nil
		if path == nil or a.men < Config.Army.MinArmyMen then
			state.armies[a.id] = nil
		else
			a.path = path
			a.moveProgress = 0
			a.retreating = true
		end
	end
	for _, a in winners do
		if a.men < Config.Army.MinArmyMen then
			state.armies[a.id] = nil
		end
	end
	for _, a in sides.defenders do
		a.inBattle = false
	end
	for _, a in sides.attackers do
		a.inBattle = false
	end
	local event = Events.push(state, "BattleEnded", winners[1].owner, losers[1].owner, provinceId)
	-- only what is true, so the event stays small on the network
	event.broke = if broke then true else nil
	event.flank = if flank then true else nil
	event.counter = if counter then true else nil
	event.outnumbered = if outnumbered then true else nil
end

function Battle.step(state: MatchState, rng: Rng.Rng)
	-- group armies by province, in id order
	local ids = {}
	for id in state.armies do
		table.insert(ids, id)
	end
	table.sort(ids)
	local byProvince: { [number]: { Army } } = {}
	local provinceOrder = {}
	for _, id in ids do
		local a = state.armies[id]
		a.inBattle = false
		if not a.retreating then -- retreating armies walk past every fight
			if byProvince[a.location] == nil then
				byProvince[a.location] = {}
				table.insert(provinceOrder, a.location)
			end
			table.insert(byProvince[a.location], a)
		end
	end
	table.sort(provinceOrder)

	local active: { [number]: boolean } = {}
	for _, provinceId in provinceOrder do
		local sides = Battle.sides(state, provinceId, byProvince[provinceId])
		if sides then
			active[provinceId] = true
			local battle = state.battles[provinceId]
			if battle == nil then
				local spread = Config.Battle.RandomSpread
				battle = {
					province = provinceId,
					round = 0,
					attackerRoll = Rng.range(rng, -spread, spread),
					defenderRoll = Rng.range(rng, -spread, spread),
					attackerEdge = newEdge(),
					defenderEdge = newEdge(),
				}
				state.battles[provinceId] = battle
			end
			for _, a in sides.defenders do
				a.inBattle = true
			end
			for _, a in sides.attackers do
				a.inBattle = true
			end
			-- both sides strike at once, then each pays the round's morale for its losses
			local att = blow(state, provinceId, sides, false, battle.attackerRoll)
			local def = blow(state, provinceId, sides, true, battle.defenderRoll)
			local attBefore, defBefore = men(sides.attackers), men(sides.defenders)
			local attLost = takeLosses(sides.attackers, def.kills)
			local defLost = takeLosses(sides.defenders, att.kills)
			lowerMorale(sides.attackers, Battle.moraleDrop(attLost, attBefore))
			lowerMorale(sides.defenders, Battle.moraleDrop(defLost, defBefore))
			credit(battle.attackerEdge, att, defLost, defBefore)
			credit(battle.defenderEdge, def, attLost, attBefore)
			battle.round += 1
			local lost, broke = Battle.loser(
				men(sides.attackers),
				Battle.morale(sides.attackers),
				men(sides.defenders),
				Battle.morale(sides.defenders),
				battle.round >= Config.Battle.Rounds
			)
			if lost then
				finish(state, provinceId, sides, battle, lost, broke)
				state.battles[provinceId] = nil
				active[provinceId] = nil
			end
		end
	end
	-- battles where one side left or died out end without a result
	for provinceId in state.battles do
		if not active[provinceId] then
			state.battles[provinceId] = nil
		end
	end
end

-- Morale comes back out of battle (tick order step 3, after the battles): every MoraleRecoverTicks ticks (all armies
-- on the same tick, so a recovering army's record changes only then) by MoraleRecoverHome on its own land (garrisons
-- and Rebels: neutral land) and MoraleRecoverAbroad elsewhere, up to MoraleMax. Retreating armies recover too.
function Battle.recoverMorale(state: MatchState)
	if state.tick % Config.Battle.MoraleRecoverTicks ~= 0 then
		return
	end
	local max = Config.Battle.MoraleMax
	for _, a in state.armies do
		if not a.inBattle and a.morale < max then
			local home = (state.provinces[a.location].owner or 0) == a.owner
			local step = if home then Config.Battle.MoraleRecoverHome else Config.Battle.MoraleRecoverAbroad
			a.morale = math.min(max, a.morale + step)
		end
	end
end

return Battle
