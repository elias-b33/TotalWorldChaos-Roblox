--!strict
-- Battles (tick order step 3): when hostile armies share a province they fight Config.Battle.Rounds rounds,
-- one per tick. Each round, each side kills enemy men equal to KillRatePerRound × its own strength × modifiers.
-- A side's strength is the sum of its men × each troop's attack (attackers) or defence (defenders), with the
-- specials' terrain and anti-garrison tricks (Troops.strength); losses split over an army's troop types in
-- proportion to their men (Army.shrinkTo). Race bonuses (Sim.Races) add to the modifier. Then the side with fewer men retreats: it walks to its nearest owned province (Pathing.retreatPath) at
-- its own speed, can't take orders, and doesn't fight, block or besiege on the way (Army.retreating). Armies under
-- MinArmyMen are destroyed, and so is a loser with no way home.

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

export type Sides = {
	defenderOwner: number,
	defenders: { Army },
	attackers: { Army },
}

-- Extra combat strength for a side (catch-up rules plug in here). Owners are the nations fighting on that side.
export type BonusFn = (state: MatchState, owners: { number }, enemies: { number }, defending: boolean) -> number

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

-- A side's combat strength before modifiers: each troop's men × its defence (defenders) or attack (attackers), with
-- the specials' tricks for a battle in `terrain` (and against neutral armies: `vsNeutral`).
function Battle.strength(side: { Army }, defending: boolean, terrain: Types.Terrain?, vsNeutral: boolean?): number
	local s = 0
	for _, a in side do
		s += Troops.strength(a.troops, defending, terrain, vsNeutral)
	end
	return s
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

local function takeLosses(side: { Army }, losses: number)
	local total = men(side)
	if total <= 0 then
		return
	end
	for _, a in side do
		Army.shrinkTo(a, math.floor(a.men - losses * a.men / total + 0.5)) -- every troop type loses its share
	end
end

-- Combat multiplier for one side this round.
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
	local mine = owners(if defending then sides.defenders else sides.attackers)
	local theirs = owners(if defending then sides.attackers else sides.defenders)
	m += Races.battleBonus(state, province, mine, defending) -- Forest in forest, Hills defending hills, Attack
	return math.max(0.1, m + Battle.bonus(state, mine, theirs, defending))
end

local function finish(state: MatchState, provinceId: number, sides: Sides)
	local defMen, attMen = men(sides.defenders), men(sides.attackers)
	local winners, losers = sides.defenders, sides.attackers
	if attMen > defMen then
		winners, losers = sides.attackers, sides.defenders
	end
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
	Events.push(state, "BattleEnded", winners[1].owner, losers[1].owner, provinceId)
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
				}
				state.battles[provinceId] = battle
			end
			for _, a in sides.defenders do
				a.inBattle = true
			end
			for _, a in sides.attackers do
				a.inBattle = true
			end
			local terrain = state.provinces[provinceId].terrain
			local defKills = Battle.strength(sides.defenders, true, terrain, allNeutral(sides.attackers))
				* Config.Battle.KillRatePerRound
				* Battle.modifier(state, provinceId, sides, true, battle.defenderRoll)
			local attKills = Battle.strength(sides.attackers, false, terrain, allNeutral(sides.defenders))
				* Config.Battle.KillRatePerRound
				* Battle.modifier(state, provinceId, sides, false, battle.attackerRoll)
			takeLosses(sides.attackers, defKills)
			takeLosses(sides.defenders, attKills)
			battle.round += 1
			if battle.round >= Config.Battle.Rounds or men(sides.attackers) <= 0 or men(sides.defenders) <= 0 then
				finish(state, provinceId, sides)
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

return Battle
