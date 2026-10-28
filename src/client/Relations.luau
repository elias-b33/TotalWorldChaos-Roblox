--!strict
-- Read-only questions about the client's copy of the match, for the UI: who is at war, who may go where,
-- scores and ranks. The server re-checks everything; this only decides which buttons to show.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Navy = require(Shared.Sim.Navy)
local Pathing = require(Shared.Sim.Pathing)
local Races = require(Shared.Sim.Races)
local Snapshot = require(Shared.Snapshot)
local Troops = require(Shared.Sim.Troops)
local Types = require(Shared.Types)

local ClientState = require(script.Parent.ClientState)

local Relations = {}

local function diplomacy()
	local snap = ClientState.snapshot()
	return if snap then snap.diplomacy else nil
end

function Relations.atWar(a: number, b: number): boolean
	local d = diplomacy()
	if d == nil or a == b or a == 0 or b == 0 then
		return false
	end
	for _, w in d.wars do
		local aAtt, aDef = table.find(w.attackers, a) ~= nil, table.find(w.defenders, a) ~= nil
		local bAtt, bDef = table.find(w.attackers, b) ~= nil, table.find(w.defenders, b) ~= nil
		if (aAtt and bDef) or (aDef and bAtt) then
			return true
		end
	end
	return false
end

function Relations.allied(a: number, b: number): boolean
	if a == b or a == 0 or b == 0 then
		return false
	end
	local na, nb = ClientState.nation(a), ClientState.nation(b)
	return na ~= nil and nb ~= nil and na.allianceId ~= 0 and na.allianceId == nb.allianceId
end

function Relations.truce(a: number, b: number): boolean
	local d = diplomacy()
	if d == nil then
		return false
	end
	local tick = ClientState.tick()
	for _, t in d.truces do
		if t.untilTick > tick and ((t.a == a and t.b == b) or (t.a == b and t.b == a)) then
			return true
		end
	end
	return false
end

-- "⚔" at war, "🤝" allied, "🕊" truce, "" otherwise.
function Relations.icon(a: number, b: number): string
	if Relations.atWar(a, b) then
		return "⚔"
	elseif Relations.allied(a, b) then
		return "🤝"
	elseif Relations.truce(a, b) then
		return "🕊"
	end
	return ""
end

-- Do a and b border each other by land, or by sea (both hold a coast of one sea zone, Sim.Diplomacy.sharesSea)? Either
-- lets them go to war.
function Relations.borders(a: number, b: number): boolean
	local snap, map = ClientState.snapshot(), ClientState.map()
	if snap == nil or map == nil then
		return false
	end
	for _, p in snap.provinces do
		if p.owner == a then
			for _, n in map.provinces[p.id].neighbors do
				if snap.provinces[n].owner == b then
					return true
				end
			end
		end
	end
	for _, zone in map.seaZones do
		local aHere, bHere = false, false
		for _, p in zone.coasts do
			local owner = snap.provinces[p].owner
			aHere = aHere or owner == a
			bHere = bHere or owner == b
		end
		if aHere and bHere then
			return true
		end
	end
	return false
end

function Relations.canEnter(nationId: number, provinceId: number): boolean
	local map = ClientState.map()
	local record = ClientState.province(provinceId)
	if map == nil or record == nil or map.provinces[provinceId].terrain == "Mountain" then
		return false
	end
	local owner = record.owner
	return owner == 0 or owner == nationId or Relations.allied(nationId, owner) or Relations.atWar(nationId, owner)
end

-- Each strait's two ends (both ways) and the sea zone it crosses, per map.
local straitZones: { [string]: { [number]: { [number]: number } } } = {}

-- A province's neighbours an army of `nationId` may step to: all of them, minus the straits whose sea zone holds a
-- fleet at war with it (Sim.Pathing.open, docs/DESIGN.md "Navies").
local function openNeighbors(map: Types.MapDef, nationId: number): (number) -> { number }
	local blocked: { [number]: boolean } = {}
	local snap = ClientState.snapshot()
	local fleets: { Snapshot.FleetRecord } = if snap then snap.fleets else {}
	for _, f in fleets do
		if not f.retreating and Relations.atWar(nationId, f.owner) then
			blocked[f.zone] = true
		end
	end
	if next(blocked) == nil then
		return function(id)
			return map.provinces[id].neighbors
		end
	end
	local ends = straitZones[map.id]
	if ends == nil then
		local made: { [number]: { [number]: number } } = {}
		for _, st in map.straits do
			made[st.a] = made[st.a] or {}
			made[st.b] = made[st.b] or {}
			made[st.a][st.b], made[st.b][st.a] = st.zone, st.zone
		end
		straitZones[map.id] = made
		ends = made
	end
	local across = ends :: { [number]: { [number]: number } }
	return function(id)
		local out = {}
		for _, n in map.provinces[id].neighbors do
			local zone = if across[id] then across[id][n] else nil
			if zone == nil or not blocked[zone] then
				table.insert(out, n)
			end
		end
		return out
	end
end

-- The route an army of `nationId` would take, or nil if it can't get there.
function Relations.path(nationId: number, from: number, to: number): { number }?
	local map = ClientState.map()
	if map == nil then
		return nil
	end
	return Pathing.search(openNeighbors(map, nationId), function(id)
		return Relations.canEnter(nationId, id)
	end, from, to)
end

-- Navies --------------------------------------------------------------------------------------------------------

-- The sea zones a province is a coast of, its port (where ships launch) first; empty inland.
function Relations.shores(provinceId: number): { number }
	local map = ClientState.map()
	local def = if map then map.provinces[provinceId] else nil
	return if def and def.zones then def.zones else {}
end

-- A sea zone of the current map by id, or nil.
function Relations.zone(zoneId: number): Types.SeaZoneDef?
	local map = ClientState.map()
	if map then
		local z = map.seaZones[zoneId]
		if z and z.id == zoneId then
			return z
		end
		for _, def in map.seaZones do
			if def.id == zoneId then
				return def
			end
		end
	end
	return nil
end

-- The zones a fleet sails through from `from` to the nearest zone `want` accepts: the server's own route
-- (Sim.Navy.search). {} if it is there already, nil if it can't get there.
function Relations.seaRoute(from: number, want: (number) -> boolean): { number }?
	if Relations.zone(from) == nil then
		return nil
	end
	return Navy.search(function(z)
		local def = Relations.zone(z)
		return if def then def.neighbors else {}
	end, from, want)
end

-- The route to sail to a zone, or to the nearest zone off a coastal province (to land there).
function Relations.sailPath(from: number, zone: number): { number }?
	return Relations.seaRoute(from, function(z)
		return z == zone
	end)
end

function Relations.landingPath(from: number, provinceId: number): { number }?
	local shores = Relations.shores(provinceId)
	if #shores == 0 then
		return nil
	end
	return Relations.seaRoute(from, function(z)
		return table.find(shores, z) ~= nil
	end)
end

-- Seconds a fleet takes to sail a route (Config.Navy.MoveTicks a zone), less the way it has come towards the first.
function Relations.sailTime(path: { number }, fleet: Snapshot.FleetRecord?): number
	local ticks = #path * Config.Navy.MoveTicks
	if fleet and fleet.next ~= 0 and path[1] == fleet.next then
		ticks -= math.floor(fleet.progress * Config.Navy.MoveTicks / 100)
	end
	return math.max(0, ticks) * Config.TickSeconds
end

-- Men a fleet can still take aboard (Sim.Navy.room).
function Relations.room(fleet: Snapshot.FleetRecord): number
	return math.max(0, fleet.ships * Config.Navy.ShipCapacity - fleet.men)
end

-- Where an army walks to board a fleet: the nearest coast of the zone the fleet is in or heading to (Sim.Navy.embark),
-- or nil if it can't get there.
function Relations.boardingPath(army: Snapshot.ArmyRecord, fleet: Snapshot.FleetRecord): { number }?
	local map = ClientState.map()
	if map == nil then
		return nil
	end
	local zone = fleet.dest
	return Pathing.searchNearest(
		openNeighbors(map, army.owner),
		function(id)
			return Relations.canEnter(army.owner, id)
		end,
		army.location,
		function(id)
			return table.find(Relations.shores(id), zone) ~= nil
		end
	)
end

-- Seconds an army takes to walk a route (Sim.Movement.moveTicks): its slowest troop's speed, with a Forest race
-- crossing forest at plains speed and a Swift race marching faster. Without an army, normal infantry speed.
function Relations.travelTime(path: { number }, army: Snapshot.ArmyRecord?): number
	local map = ClientState.map()
	local t = 0
	if map then
		local troops: Types.Composition = if army then Troops.decode(army.troops) else { Infantry = 1 }
		local owner = if army then ClientState.nation(army.owner) else nil
		local race = if owner then owner.race :: Types.Race else nil
		for _, id in path do
			local terrain = Races.moveTerrain(race, map.provinces[id].terrain)
			t += Races.moveTicks(race, Troops.moveTicks(troops, terrain)) * Config.TickSeconds
		end
	end
	return t
end

function Relations.provinceCount(nationId: number): number
	local snap = ClientState.snapshot()
	local n = 0
	if snap then
		for _, p in snap.provinces do
			if p.owner == nationId then
				n += 1
			end
		end
	end
	return n
end

-- Same formula as Sim.Victory.score.
function Relations.score(nationId: number): number
	local snap = ClientState.snapshot()
	local nation = ClientState.nation(nationId)
	if snap == nil or nation == nil then
		return 0
	end
	local provinces, development = 0, 0
	for _, p in snap.provinces do
		if p.owner == nationId then
			provinces += 1
			development += p.development
		end
	end
	return provinces * Config.Win.ScorePerProvince
		+ development * Config.Win.ScorePerDevelopment
		+ nation.battlesWon * Config.Win.ScorePerBattleWon
end

-- 1 = best score.
function Relations.rank(nationId: number): number
	local snap = ClientState.snapshot()
	if snap == nil then
		return 0
	end
	local mine = Relations.score(nationId)
	local rank = 1
	for _, n in snap.nations do
		if n.id ~= nationId and Relations.score(n.id) > mine then
			rank += 1
		end
	end
	return rank
end

function Relations.offersTo(nationId: number)
	local d = diplomacy()
	local out = {}
	if d then
		local tick = ClientState.tick()
		for _, o in d.offers do
			if o.to == nationId and o.expiresAt > tick then
				table.insert(out, o)
			end
		end
	end
	return out
end

return Relations
