--!strict
-- Army bookkeeping. Movement, battles and sieges arrive in Phase 2.

local Types = require("../Types")

type MatchState = Types.MatchState
type Army = Types.Army

local Army = {}

-- Takes the next army id. Ids count up for the whole match and are never reused, so a client's token, selected
-- army or route, and a command still in the queue, can't end up meaning a newer army.
function Army.nextId(state: MatchState): number
	local id = state.nextArmyId
	state.nextArmyId = id + 1
	return id
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

function Army.spawn(state: MatchState, owner: number, location: number, men: number): Army
	local army: Army = {
		id = Army.nextId(state),
		owner = owner,
		location = location,
		men = men,
		path = {},
		moveProgress = 0,
		inBattle = false,
	}
	state.armies[army.id] = army
	return army
end

-- New regiments join an idle army already in the province, or form a new one.
function Army.reinforce(state: MatchState, owner: number, location: number, men: number): Army
	local army = Army.idleAt(state, owner, location)
	if army then
		army.men += men
		return army
	end
	return Army.spawn(state, owner, location, men)
end

return Army
