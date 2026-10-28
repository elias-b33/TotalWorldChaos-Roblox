--!strict
-- Army bookkeeping: ids, spawning, reinforcing, and the army's composition (men per troop type, docs/DESIGN.md
-- "Troops"). Army.men is the total and Army.troops the composition; Army.setTroops is the one place either changes,
-- so they always agree: recruits, merges, battle losses and a Meteor all go through it.

local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState
type Army = Types.Army
type Troop = Types.Troop
type Composition = Types.Composition

local Army = {}

-- Takes the next army id. Ids count up for the whole match and are never reused, so a client's token, selected
-- army or route, and a command still in the queue, can't end up meaning a newer army.
function Army.nextId(state: MatchState): number
	local id = state.nextArmyId
	state.nextArmyId = id + 1
	return id
end

-- The army an id means now: an army that merged into another stack (Movement.mergeStacks) lives on in the one
-- that took its men, so an order or a power aimed at it just before the merge still lands. Ids of armies that
-- are simply gone come back unchanged (the caller then answers UnknownArmy).
function Army.resolve(state: MatchState, id: number): number
	local seen = 0
	while state.armies[id] == nil and state.mergedInto[id] ~= nil and seen < 100 do
		id = state.mergedInto[id]
		seen += 1
	end
	return id
end

-- The one helper that changes an army's men: sets its composition (types with no men are dropped) and keeps `men`,
-- the total, in step with it.
function Army.setTroops(army: Army, troops: Composition)
	local clean: Composition = {}
	local total = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men and men > 0 then
			clean[troop] = men
			total += men
		end
	end
	army.troops = clean
	army.men = total
end

-- An army down to `total` men (battle losses, a Meteor): every troop type loses its share, in proportion to its men.
function Army.shrinkTo(army: Army, total: number)
	Army.setTroops(army, Troops.split(army.troops, math.max(0, total)))
end

-- A stack takes in another army's men (merging, reinforcing): the compositions add up.
function Army.add(army: Army, troops: Composition)
	local sum = table.clone(army.troops)
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men then
			sum[troop] = (sum[troop] or 0) + men
		end
	end
	Army.setTroops(army, sum)
end

-- An army of this owner standing still in the province, if there is one.
function Army.idleAt(state: MatchState, owner: number, location: number): Army?
	local found: Army? = nil
	for _, army in state.armies do
		if army.owner == owner and army.location == location and #army.path == 0 and not army.inBattle then
			if found == nil or army.id < found.id then
				found = army
			end
		end
	end
	return found
end

-- A new army of `men` men of one troop type (infantry unless told otherwise: garrisons, Rebels, tests).
function Army.spawn(state: MatchState, owner: number, location: number, men: number, troop: Troop?): Army
	local army: Army = {
		id = Army.nextId(state),
		owner = owner,
		location = location,
		men = 0,
		troops = {},
		path = {},
		moveProgress = 0,
		inBattle = false,
	}
	local kind: Troop = troop or Troops.BASE
	Army.setTroops(army, { [kind] = men })
	state.armies[army.id] = army
	return army
end

-- New regiments join an idle army already in the province, or form a new one.
function Army.reinforce(state: MatchState, owner: number, location: number, men: number, troop: Troop?): Army
	local kind: Troop = troop or Troops.BASE
	local army = Army.idleAt(state, owner, location)
	if army then
		Army.add(army, { [kind] = men })
		return army
	end
	return Army.spawn(state, owner, location, men, kind)
end

return Army
