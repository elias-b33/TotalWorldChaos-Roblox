--!strict
-- Navies (docs/DESIGN.md "Navies"): ships, fleets and sea zones.
--
-- Every map's water (Skyshards' void) is split into named sea zones (MapDef.seaZones), each with its neighbouring
-- zones and the coastal provinces it touches. A nation launches ships (the map's one ship type, Config.Navy) from a
-- coastal province it owns into that province's port zone; its ships standing still in one zone are one fleet, one
-- token, like an army's regiments. Fleets sail from zone to zone. An army walks to a coast of a friendly fleet's zone
-- and boards it, as many men as the ships carry (the rest stay ashore); the fleet carries them, and lands them all
-- on any coast of its zone, where they fight and besiege as usual.
--
-- Hostile fleets in one zone fight with the land battle's rule (Config.Battle: 3 rounds, each side kills 15% of its
-- strength × modifiers a round), a fleet's hull standing for an army's men. The side left weaker retreats: each of
-- its fleets sails to the nearest other zone off a friendly coast, carrying its men along; a fleet with nowhere to
-- go, or left under Config.Navy.MinHull, sinks with everyone aboard.
--
-- Control of the sea: a fleet at war with a nation in a strait's zone stops that nation's armies crossing the strait
-- (Diplomacy.crossable), and next to one of its coastal provinces, with no friendly fleet in that zone, blockades it
-- (Province.blockade): the province loses part of its gold (Economy) and the blockader's side besieges it faster
-- (Siege). A blockaded province can't launch ships.
--
-- Tick order (Sim.Tick): Navy.step before armies move (fleets sail, armies board, fleets land, fleets merge),
-- Navy.battleStep after the land battles, Navy.blockades before sieges and pay.
-- Who sees which fleet: Navy.visible, the one place fog of war plugs in.

local Army = require("./Army")
local CatchUp = require("./CatchUp")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Events = require("./Events")
local Pathing = require("./Pathing")
local Rng = require("./Rng")
local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState
type Fleet = Types.Fleet
type Composition = Types.Composition

local Navy = {}

local function sortedIds(t: { [number]: any }): { number }
	local ids = {}
	for id in t do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Fleets ------------------------------------------------------------------------------------------------------

-- Ships in a fleet: its hull in whole ships, rounded up (a damaged ship still sails and carries its regiment).
function Navy.ships(fleet: Fleet): number
	return math.ceil(fleet.hull / Config.Navy.ShipHull)
end

-- Men a fleet can carry in all, and how many more it can take aboard.
function Navy.capacity(fleet: Fleet): number
	return Navy.ships(fleet) * Config.Navy.ShipCapacity
end

function Navy.room(fleet: Fleet): number
	return math.max(0, Navy.capacity(fleet) - fleet.men)
end

-- The one helper that changes the men aboard: sets the composition (types with no men are dropped) and keeps `men`,
-- the total, in step with it (like Army.setTroops).
function Navy.setCargo(fleet: Fleet, troops: Composition)
	local clean: Composition = {}
	local total = 0
	for _, troop in Troops.LIST do
		local men = troops[troop]
		if men and men > 0 then
			clean[troop] = men
			total += men
		end
	end
	fleet.troops = clean
	fleet.men = total
end

local function addTroops(a: Composition, b: Composition): Composition
	local sum = table.clone(a)
	for _, troop in Troops.LIST do
		local men = b[troop]
		if men then
			sum[troop] = (sum[troop] or 0) + men
		end
	end
	return sum
end

-- The fleet an id means now: a fleet that merged into another lives on in it (like Army.resolve).
function Navy.resolve(state: MatchState, id: number): number
	local seen = 0
	while state.fleets[id] == nil and state.fleetMergedInto[id] ~= nil and seen < 100 do
		id = state.fleetMergedInto[id]
		seen += 1
	end
	return id
end

-- A new fleet of `ships` ships, empty.
function Navy.spawn(state: MatchState, owner: number, zone: number, ships: number): Fleet
	local fleet: Fleet = {
		id = state.nextFleetId,
		owner = owner,
		zone = zone,
		hull = ships * Config.Navy.ShipHull,
		troops = {},
		men = 0,
		path = {},
		moveProgress = 0,
		inBattle = false,
	}
	state.nextFleetId += 1
	state.fleets[fleet.id] = fleet
	return fleet
end

-- Standing still and free: no route, no fight, no retreat, no landing under way. Such fleets of one nation in one
-- zone merge, and new ships join one.
function Navy.idle(fleet: Fleet): boolean
	return #fleet.path == 0 and not fleet.inBattle and not fleet.retreating and fleet.landAt == nil
end

-- A nation's idle fleet in a zone (the lowest id), if there is one.
function Navy.idleAt(state: MatchState, owner: number, zone: number): Fleet?
	local found: Fleet? = nil
	for _, fleet in state.fleets do
		if fleet.owner == owner and fleet.zone == zone and Navy.idle(fleet) then
			if found == nil or fleet.id < found.id then
				found = fleet
			end
		end
	end
	return found
end

-- Where a fleet is heading: the end of its route, else where it is.
function Navy.destination(fleet: Fleet): number
	return if #fleet.path > 0 then fleet.path[#fleet.path] else fleet.zone
end

-- Who sees which fleet. Everyone sees every fleet for now: fog of war (the EU4 pack) plugs in here, and bots and
-- clients ask here before they act on a fleet they don't own.
function Navy.visible(_state: MatchState, _viewer: number, _fleet: Fleet): boolean
	return true
end

-- Zones and coasts ---------------------------------------------------------------------------------------------

-- The sea zones a province is a coast of (its port first); empty inland.
local NONE: { number } = {}
function Navy.shores(state: MatchState, provinceId: number): { number }
	return state.shores[provinceId] or NONE
end

-- The zone ships built in a province launch into: the one it shares most shore with. nil inland.
function Navy.port(state: MatchState, provinceId: number): number?
	return Navy.shores(state, provinceId)[1]
end

function Navy.touches(state: MatchState, provinceId: number, zone: number): boolean
	return table.find(Navy.shores(state, provinceId), zone) ~= nil
end

-- Does `nationId` (or an ally) hold a coast of this zone?
function Navy.friendlyCoast(state: MatchState, nationId: number, zone: number): boolean
	for _, p in state.zones[zone].coasts do
		local owner = state.provinces[p].owner
		if owner ~= nil and Diplomacy.friendly(state, nationId, owner) then
			return true
		end
	end
	return false
end

-- The route from one zone to the nearest zone `want` accepts (fewest zones; ties to the lower zone id): {} if `from`
-- is wanted, nil if none is.
function Navy.route(state: MatchState, from: number, want: (number) -> boolean): { number }?
	if want(from) then
		return {}
	end
	local cameFrom: { [number]: number } = { [from] = from }
	local queue = { from }
	local head = 1
	while head <= #queue do
		local cur = queue[head]
		head += 1
		for _, n in state.zones[cur].neighbors do
			if cameFrom[n] == nil then
				cameFrom[n] = cur
				if want(n) then
					local path = { n }
					local step = cur
					while step ~= from do
						table.insert(path, 1, step)
						step = cameFrom[step]
					end
					return path
				end
				table.insert(queue, n)
			end
		end
	end
	return nil
end

-- Orders (Sim.Commands) --------------------------------------------------------------------------------------------

-- Launch `ships` ships from a coastal province into its port zone: they join the nation's idle fleet there, or
-- form a new one. A blockaded province launches nothing.
function Navy.build(state: MatchState, nationId: number, provinceId: number, ships: number): (boolean, string?)
	if ships ~= math.floor(ships) or ships < 1 or ships > Config.Navy.MaxShipsPerCommand then
		return false, "BadAmount"
	end
	local province = state.provinces[provinceId]
	if province == nil then
		return false, "UnknownProvince"
	end
	if province.owner ~= nationId then
		return false, "NotYourProvince"
	end
	local zone = Navy.port(state, provinceId)
	if zone == nil then
		return false, "NoCoast"
	end
	if province.blockade ~= nil then
		return false, "Blockaded"
	end
	local nation = state.nations[nationId]
	local cost = ships * Config.Navy.ShipGold
	if nation.gold < cost then
		return false, "NotEnoughGold"
	end
	nation.gold -= cost
	local fleet = Navy.idleAt(state, nationId, zone)
	if fleet then
		fleet.hull += ships * Config.Navy.ShipHull
	else
		Navy.spawn(state, nationId, zone, ships)
	end
	return true, nil
end

-- A fleet of this nation that may take an order now.
local function ownFleet(state: MatchState, nationId: number, fleetId: number): (Fleet?, string?)
	local fleet = state.fleets[Navy.resolve(state, fleetId)]
	if fleet == nil then
		return nil, "UnknownFleet"
	elseif fleet.owner ~= nationId then
		return nil, "NotYourFleet"
	elseif fleet.retreating then
		return nil, "Retreating"
	elseif fleet.inBattle then
		return nil, "InBattle"
	end
	return fleet, nil
end

local function setRoute(fleet: Fleet, path: { number })
	if #path == 0 or fleet.path[1] ~= path[1] then
		fleet.moveProgress = 0 -- keep progress if it keeps heading the same way
	end
	fleet.path = path
end

-- Sail to a zone (fewest zones on the way). Sailing where it stands stops it.
function Navy.sail(state: MatchState, nationId: number, fleetId: number, zone: number): (boolean, string?)
	local fleet, err = ownFleet(state, nationId, fleetId)
	if fleet == nil then
		return false, err
	end
	if state.zones[zone] == nil then
		return false, "UnknownZone"
	end
	local path = Navy.route(state, fleet.zone, function(z)
		return z == zone
	end)
	if path == nil then
		return false, "NoPath"
	end
	setRoute(fleet, path)
	fleet.landAt = nil
	return true, nil
end

-- Sail to the nearest zone off a coastal province and land everyone aboard there (on arrival, if the province is
-- still open to the fleet's owner: Diplomacy.canEnter).
function Navy.land(state: MatchState, nationId: number, fleetId: number, provinceId: number): (boolean, string?)
	local fleet, err = ownFleet(state, nationId, fleetId)
	if fleet == nil then
		return false, err
	end
	if state.provinces[provinceId] == nil then
		return false, "UnknownProvince"
	end
	local shores = Navy.shores(state, provinceId)
	if #shores == 0 then
		return false, "NoCoast"
	end
	if fleet.men <= 0 then
		return false, "NoTroops"
	end
	if not Diplomacy.canEnter(state, nationId, provinceId) then
		return false, "NoPath"
	end
	local path = Navy.route(state, fleet.zone, function(z)
		return table.find(shores, z) ~= nil
	end)
	if path == nil then
		return false, "NoPath"
	end
	setRoute(fleet, path)
	fleet.landAt = provinceId
	return true, nil
end

-- An army walks to the nearest coast of the zone a fleet of its nation is in (or heading to) and boards it there
-- (Navy.step), as many men as fit; the rest stay ashore as the same army.
function Navy.embark(state: MatchState, nationId: number, armyId: number, fleetId: number): (boolean, string?)
	local army = state.armies[Army.resolve(state, armyId)]
	if army == nil then
		return false, "UnknownArmy"
	elseif army.owner ~= nationId then
		return false, "NotYourArmy"
	elseif army.inBattle then
		return false, "InBattle"
	elseif army.retreating then
		return false, "Retreating"
	end
	local fleet = state.fleets[Navy.resolve(state, fleetId)]
	if fleet == nil then
		return false, "UnknownFleet"
	elseif fleet.owner ~= nationId then
		return false, "NotYourFleet"
	elseif fleet.retreating then
		return false, "Retreating"
	elseif Navy.room(fleet) <= 0 then
		return false, "FleetFull"
	end
	local zone = Navy.destination(fleet)
	local path = Pathing.nearest(state, nationId, army.location, function(p)
		return Navy.touches(state, p, zone)
	end)
	if path == nil then
		return false, "NoPath"
	end
	if #path == 0 or army.path[1] ~= path[1] then
		army.moveProgress = 0
	end
	army.path = path
	army.boardFleet = fleet.id
	return true, nil
end

-- Tick: sail, board, land, merge -----------------------------------------------------------------------------

-- An army standing on a coast boards the fleet it was sent to, if the fleet is in a zone of that coast: as many men
-- as there is room for, of every troop type in proportion. A fleet still on its way is waited for; a fleet that
-- stopped somewhere else, sank or filled up isn't, and the army simply stands.
local function board(state: MatchState, army: Types.Army, fleetId: number)
	local fleet = state.fleets[Navy.resolve(state, fleetId)]
	if fleet == nil or fleet.owner ~= army.owner or fleet.retreating then
		army.boardFleet = nil
		return
	end
	if fleet.inBattle or not Navy.touches(state, army.location, fleet.zone) then
		if Navy.idle(fleet) and not Navy.touches(state, army.location, fleet.zone) then
			army.boardFleet = nil -- it isn't coming
		end
		return
	end
	army.boardFleet = nil
	local room = Navy.room(fleet)
	if room <= 0 then
		return
	end
	local take = math.min(army.men, room)
	local aboard = Troops.split(army.troops, take)
	local rest: Composition = {}
	for _, troop in Troops.LIST do
		local left = (army.troops[troop] or 0) - (aboard[troop] or 0)
		if left > 0 then
			rest[troop] = left
		end
	end
	Navy.setCargo(fleet, addTroops(fleet.troops, aboard))
	if take >= army.men then
		state.armies[army.id] = nil -- (the event tells clients the token went aboard, it wasn't destroyed)
		Events.push(state, "Embarked", army.id, fleet.id, army.location, nil, nil, fleet.zone)
	else
		Army.setTroops(army, rest)
	end
end

-- A fleet that reached a zone off the province it was sent to land at puts everyone aboard ashore there, as one new
-- army; if the province has closed to its owner meanwhile (peace was made), they stay aboard.
local function unload(state: MatchState, fleet: Fleet)
	local at = fleet.landAt :: number
	fleet.landAt = nil
	if fleet.men <= 0 or not Navy.touches(state, at, fleet.zone) or not Diplomacy.canEnter(state, fleet.owner, at) then
		return
	end
	local army = Army.spawn(state, fleet.owner, at, 0)
	Army.setTroops(army, fleet.troops)
	Navy.setCargo(fleet, {})
	Events.push(state, "Landed", army.id, fleet.id, at, nil, nil, fleet.zone)
end

-- A nation's idle fleets in one zone become one: the lowest id keeps the others' ships and men (a "FleetMerged"
-- event; orders for the removed id reach the stack through Navy.resolve).
local function mergeFleets(state: MatchState)
	local keeper: { [string]: Fleet } = {}
	for _, id in sortedIds(state.fleets) do
		local fleet = state.fleets[id]
		if Navy.idle(fleet) then
			local key = fleet.owner .. ":" .. fleet.zone
			local first = keeper[key]
			if first == nil then
				keeper[key] = fleet
			else
				first.hull += fleet.hull
				Navy.setCargo(first, addTroops(first.troops, fleet.troops))
				state.fleets[id] = nil
				state.fleetMergedInto[id] = first.id
				Events.push(state, "FleetMerged", first.id, id, 0, nil, nil, fleet.zone)
			end
		end
	end
end

-- Tick order step 2, before armies move: fleets sail a zone every Config.Navy.MoveTicks (retreating ones too, and a
-- retreat ends on arrival), armies standing on a coast board their fleets, fleets that arrived land their men, and
-- each nation's idle fleets in one zone merge.
function Navy.step(state: MatchState)
	for _, id in sortedIds(state.fleets) do
		local fleet = state.fleets[id]
		local nextZone = fleet.path[1]
		if nextZone and not fleet.inBattle then
			fleet.moveProgress += 1
			if fleet.moveProgress >= Config.Navy.MoveTicks then
				fleet.zone = nextZone
				table.remove(fleet.path, 1)
				fleet.moveProgress = 0
			end
		end
		if fleet.retreating and #fleet.path == 0 then
			fleet.retreating = nil -- off a friendly coast: a normal fleet again
		end
	end
	for _, id in sortedIds(state.armies) do
		local army = state.armies[id]
		local fleetId = army.boardFleet
		if fleetId and #army.path == 0 and not army.inBattle and not army.retreating then
			board(state, army, fleetId)
		end
	end
	for _, id in sortedIds(state.fleets) do
		local fleet = state.fleets[id]
		if fleet.landAt and #fleet.path == 0 and not fleet.inBattle and not fleet.retreating then
			unload(state, fleet)
		end
	end
	mergeFleets(state)
end

-- Sea battles ------------------------------------------------------------------------------------------------------

export type Sides = { defenderOwner: number, defenders: { Fleet }, attackers: { Fleet } }

-- Who fights whom in a zone. Nobody owns the sea, so the first fleet (lowest id) with an enemy there holds it: its
-- side defends, and every fleet at war with it attacks.
function Navy.sides(state: MatchState, fleets: { Fleet }): Sides?
	for _, first in fleets do
		local defenders, attackers = {}, {}
		for _, f in fleets do
			if Diplomacy.friendly(state, f.owner, first.owner) then
				table.insert(defenders, f)
			elseif Diplomacy.atWar(state, f.owner, first.owner) then
				table.insert(attackers, f)
			end
		end
		if #attackers > 0 then
			return { defenderOwner = first.owner, defenders = defenders, attackers = attackers }
		end
	end
	return nil
end

local function hullOf(side: { Fleet }): number
	local n = 0
	for _, f in side do
		n += f.hull
	end
	return n
end

local function owners(side: { Fleet }): { number }
	local out = {}
	for _, f in side do
		if table.find(out, f.owner) == nil then
			table.insert(out, f.owner)
		end
	end
	return out
end

-- A side's combat multiplier: 1 + its random roll + the catch-up bonuses (underdog defending, coalition), as on
-- land; no terrain or forts at sea.
function Navy.modifier(state: MatchState, sides: Sides, defending: boolean, roll: number): number
	local mine = owners(if defending then sides.defenders else sides.attackers)
	local theirs = owners(if defending then sides.attackers else sides.defenders)
	return math.max(0.1, 1 + roll + CatchUp.battleBonus(state, mine, theirs, defending))
end

local function takeLosses(side: { Fleet }, losses: number)
	local total = hullOf(side)
	if total <= 0 then
		return
	end
	for _, f in side do
		f.hull = math.max(0, math.floor(f.hull - losses * f.hull / total + 0.5))
	end
end

-- The nearest other zone off a friendly coast, where a beaten fleet retreats to.
function Navy.retreatRoute(state: MatchState, fleet: Fleet): { number }?
	local from = fleet.zone
	return Navy.route(state, from, function(z)
		return z ~= from and Navy.friendlyCoast(state, fleet.owner, z)
	end)
end

local function finish(state: MatchState, zone: number, sides: Sides)
	local winners, losers = sides.defenders, sides.attackers
	if hullOf(sides.attackers) > hullOf(sides.defenders) then
		winners, losers = sides.attackers, sides.defenders
	end
	for _, owner in owners(winners) do
		local nation = state.nations[owner]
		if nation then
			nation.battlesWon += 1
		end
	end
	for _, f in losers do
		local path = if f.hull >= Config.Navy.MinHull then Navy.retreatRoute(state, f) else nil
		if path == nil then
			state.fleets[f.id] = nil -- sunk, and everyone aboard with it
		else
			f.path = path
			f.moveProgress = 0
			f.retreating = true
			f.landAt = nil
		end
	end
	for _, f in winners do
		if f.hull < Config.Navy.MinHull then
			state.fleets[f.id] = nil
		end
	end
	for _, f in sides.defenders do
		f.inBattle = false
	end
	for _, f in sides.attackers do
		f.inBattle = false
	end
	Events.push(state, "SeaBattle", winners[1].owner, losers[1].owner, 0, nil, nil, zone)
end

-- Tick order step 3, after the land battles: hostile fleets sharing a zone fight Config.Battle.Rounds rounds, one a
-- tick. Retreating fleets sail past every fight.
function Navy.battleStep(state: MatchState, rng: Rng.Rng)
	local byZone: { [number]: { Fleet } } = {}
	local zoneOrder = {}
	for _, id in sortedIds(state.fleets) do
		local f = state.fleets[id]
		f.inBattle = false
		if not f.retreating then
			if byZone[f.zone] == nil then
				byZone[f.zone] = {}
				table.insert(zoneOrder, f.zone)
			end
			table.insert(byZone[f.zone], f)
		end
	end
	table.sort(zoneOrder)
	local active: { [number]: boolean } = {}
	for _, zone in zoneOrder do
		local sides = Navy.sides(state, byZone[zone])
		if sides then
			active[zone] = true
			local battle = state.seaBattles[zone]
			if battle == nil then
				local spread = Config.Battle.RandomSpread
				battle = {
					zone = zone,
					round = 0,
					attackerRoll = Rng.range(rng, -spread, spread),
					defenderRoll = Rng.range(rng, -spread, spread),
				}
				state.seaBattles[zone] = battle
			end
			for _, f in sides.defenders do
				f.inBattle = true
			end
			for _, f in sides.attackers do
				f.inBattle = true
			end
			local defKills = hullOf(sides.defenders)
				* Config.Battle.KillRatePerRound
				* Navy.modifier(state, sides, true, battle.defenderRoll)
			local attKills = hullOf(sides.attackers)
				* Config.Battle.KillRatePerRound
				* Navy.modifier(state, sides, false, battle.attackerRoll)
			takeLosses(sides.attackers, defKills)
			takeLosses(sides.defenders, attKills)
			battle.round += 1
			if battle.round >= Config.Battle.Rounds or hullOf(sides.attackers) <= 0 or hullOf(sides.defenders) <= 0 then
				finish(state, zone, sides)
				state.seaBattles[zone] = nil
				active[zone] = nil
			end
		end
	end
	-- battles where one side left or sank end without a result
	for zone in state.seaBattles do
		if not active[zone] then
			state.seaBattles[zone] = nil
		end
	end
end

-- Blockades --------------------------------------------------------------------------------------------------------

-- Tick order, before sieges and pay: every coastal province with a fleet at war with its owner in one of its zones,
-- and no fleet of its owner's side in that zone, is blockaded by that fleet's nation (the lowest id if several).
-- A "Blockade" event goes out once per blockading nation, blockaded nation and zone when it starts.
function Navy.blockades(state: MatchState)
	local present: { [number]: { number } } = {} -- zone -> nations with a fleet there (not retreating)
	for _, id in sortedIds(state.fleets) do
		local f = state.fleets[id]
		if not f.retreating then
			local list = present[f.zone] or {}
			if table.find(list, f.owner) == nil then
				table.insert(list, f.owner)
			end
			present[f.zone] = list
		end
	end
	local started: { string } = {}
	local startedAt: { [string]: { a: number, b: number, province: number, zone: number } } = {}
	for _, id in sortedIds(state.provinces) do
		local p = state.provinces[id]
		local owner = p.owner
		local by: number?, byZone = nil, 0
		if owner ~= nil and next(present) ~= nil then
			for _, zone in Navy.shores(state, id) do
				local hostile: number? = nil
				local guarded = false
				for _, o in present[zone] or NONE do
					if Diplomacy.friendly(state, o, owner) then
						guarded = true
					elseif Diplomacy.atWar(state, o, owner) and (hostile == nil or o < hostile) then
						hostile = o
					end
				end
				if hostile and not guarded and (by == nil or hostile < by) then
					by, byZone = hostile, zone
				end
			end
		end
		if by and owner and p.blockade ~= by then
			local key = by .. ":" .. owner .. ":" .. byZone
			if startedAt[key] == nil then
				startedAt[key] = { a = by, b = owner, province = id, zone = byZone }
				table.insert(started, key)
			end
		end
		p.blockade = by
	end
	for _, key in started do
		local s = startedAt[key]
		Events.push(state, "Blockade", s.a, s.b, s.province, nil, nil, s.zone)
	end
end

-- Elimination: a nation leaving the match takes its fleets with it, and everyone aboard.
function Navy.disband(state: MatchState, nationId: number)
	for _, id in sortedIds(state.fleets) do
		if state.fleets[id].owner == nationId then
			state.fleets[id] = nil
		end
	end
end

return Navy
