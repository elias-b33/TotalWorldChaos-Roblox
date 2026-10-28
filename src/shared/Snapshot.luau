--!strict
-- What the server sends clients: a full snapshot on join, then a delta of changed records every tick.
-- Records are flat arrays of plain values because RemoteEvents mangle sparse or mixed tables.
-- Neutral owner and "no player" are sent as 0 instead of nil for the same reason. Pure Luau (tested with Lune).

local Troops = require("./Sim/Troops")
local Types = require("./Types")

type MatchState = Types.MatchState

export type ProvinceRecord = {
	id: number,
	owner: number, -- 0 = neutral
	development: number,
	building: Types.Building,
	siegeBy: number, -- 0 = no siege
	siegeProgress: number,
	siegeRequired: number,
	battle: boolean,
	shieldUntil: number, -- tick; 0 = never shielded
	blessedUntil: number, -- tick a Blessing ends; 0 = none
}

export type NationRecord = {
	id: number,
	name: string,
	colorIndex: number,
	race: string, -- Types.Race: picking the nation picks it
	controller: string,
	userId: number, -- 0 = bot
	capital: number,
	gold: number,
	manpower: number,
	charges: number,
	plagueUntil: number, -- tick a Plague ends; 0 = none
	powerImmuneUntil: number, -- tick its immunity to harmful powers ends (the power picker greys it out until then)
	eliminated: boolean,
	allianceId: number, -- 0 = none
	battlesWon: number,
}

export type ArmyRecord = {
	id: number,
	owner: number,
	location: number,
	men: number,
	troops: string, -- its composition, Sim.Troops.encode ("Infantry:3000,Archers:1000"); Troops.decode reads it
	next: number, -- next province on its route, 0 = standing still
	dest: number, -- end of its route, 0 = standing still
	inBattle: boolean,
	rebel: boolean, -- an owner-0 army raised by the Rebels power (else owner 0 is a neutral garrison)
	retreating: boolean, -- beaten and walking home: takes no orders
}

-- Wars, alliances, truces and pending offers: small, so sent whole whenever any of it changes. Also the EU4 pack's
-- military access, insults' grudges, open answer windows and waits (the buttons grey out on the client).
export type DiplomacyData = {
	wars: { { id: number, attackers: { number }, defenders: { number } } },
	alliances: { { id: number, members: { number } } },
	truces: { { a: number, b: number, untilTick: number } },
	offers: { Types.Offer },
	access: { Types.Access },
	grudges: { Types.Grudge },
	answers: { Types.Answer },
	cooldowns: { Types.Cooldown },
}

-- An eliminated player's Primordial: only charges change, so the list is sent whole whenever it changes.
export type PrimordialRecord = { userId: number, charges: number }

-- Unreliable position updates for moving armies: the client slides tokens between province centres.
export type ArmyPosition = { id: number, from: number, to: number, progress: number }

export type SnapshotData = {
	mapId: string,
	setup: Types.MatchSetup, -- the private server's settings (fixed for the match: never in a delta)
	tick: number,
	phase: Types.Phase,
	provinces: { ProvinceRecord },
	nations: { NationRecord },
	armies: { ArmyRecord },
	diplomacy: DiplomacyData,
	primordials: { PrimordialRecord },
	result: Types.MatchResult?,
	cosmetics: { Types.NationCosmetics }, -- each nation's equipped looks, next to MatchState (Sim.Shop)
	theme: string, -- the map theme everyone sees (MatchState.theme; "" = classic). Set before the match starts.
}

export type DeltaData = {
	tick: number,
	phase: Types.Phase,
	provinces: { ProvinceRecord },
	nations: { NationRecord },
	armies: { ArmyRecord },
	removedArmies: { number },
	diplomacy: DiplomacyData?, -- only when it changed
	primordials: { PrimordialRecord }?, -- only when it changed
	result: Types.MatchResult?, -- only when it changed
	cosmetics: { Types.NationCosmetics }?, -- only when it changed
	events: { Types.MatchEvent },
}

local Snapshot = {}

local function sortedKeys(t: { [number]: any }): { number }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- cosmetics (optional): every nation's equipped cosmetics (Sim.Shop.nationCosmetics); none = an empty list.
function Snapshot.full(state: MatchState, cosmetics: { Types.NationCosmetics }?): SnapshotData
	local provinces = {}
	for _, id in sortedKeys(state.provinces) do
		local p = state.provinces[id]
		local siege = p.siege
		table.insert(provinces, {
			id = p.id,
			owner = p.owner or 0,
			development = p.development,
			building = p.building,
			siegeBy = if siege then siege.by else 0,
			siegeProgress = if siege then siege.progress else 0,
			siegeRequired = if siege then siege.required else 0,
			battle = state.battles[p.id] ~= nil,
			shieldUntil = p.shieldUntil or 0,
			blessedUntil = p.buffs.Blessing or 0,
		})
	end
	local nations = {}
	for _, id in sortedKeys(state.nations) do
		local n = state.nations[id]
		table.insert(nations, {
			id = n.id,
			name = n.name,
			colorIndex = n.colorIndex,
			race = n.race,
			controller = n.controller,
			userId = n.userId or 0,
			capital = n.capital,
			gold = n.gold,
			manpower = n.manpower,
			charges = n.charges,
			plagueUntil = n.plagueUntil or 0,
			powerImmuneUntil = n.powerImmuneUntil,
			eliminated = n.eliminated,
			allianceId = n.allianceId or 0,
			battlesWon = n.battlesWon,
		})
	end
	local armies = {}
	for _, id in sortedKeys(state.armies) do
		local a = state.armies[id]
		table.insert(armies, {
			id = a.id,
			owner = a.owner,
			location = a.location,
			men = a.men,
			troops = Troops.encode(a.troops),
			next = a.path[1] or 0,
			dest = a.path[#a.path] or 0,
			inBattle = a.inBattle,
			rebel = a.rebel == true,
			retreating = a.retreating == true,
		})
	end
	return {
		mapId = state.mapId,
		setup = state.setup,
		tick = state.tick,
		phase = state.phase,
		provinces = provinces,
		nations = nations,
		armies = armies,
		diplomacy = Snapshot.diplomacy(state),
		primordials = Snapshot.primordials(state),
		result = state.result,
		cosmetics = cosmetics or {},
		theme = state.theme or "",
	}
end

function Snapshot.primordials(state: MatchState): { PrimordialRecord }
	local out = {}
	for _, userId in sortedKeys(state.primordials) do
		table.insert(out, { userId = userId, charges = state.primordials[userId].charges })
	end
	return out
end

function Snapshot.diplomacy(state: MatchState): DiplomacyData
	local wars = {}
	for _, id in sortedKeys(state.wars) do
		local w = state.wars[id]
		table.insert(wars, { id = w.id, attackers = table.clone(w.attackers), defenders = table.clone(w.defenders) })
	end
	local alliances = {}
	for _, id in sortedKeys(state.alliances) do
		local a = state.alliances[id]
		table.insert(alliances, { id = a.id, members = table.clone(a.members) })
	end
	local truces = {}
	for _, t in state.truces do
		table.insert(truces, { a = t.a, b = t.b, untilTick = t.untilTick })
	end
	local offers = {}
	for _, o in state.offers do
		table.insert(offers, table.clone(o))
	end
	local function copies(list: { any }?): { any }
		local out = {}
		for _, x in list or {} do
			table.insert(out, table.clone(x))
		end
		return out
	end
	return {
		wars = wars,
		alliances = alliances,
		truces = truces,
		offers = offers,
		access = copies(state.access),
		grudges = copies(state.grudges),
		answers = copies(state.answers),
		cooldowns = copies(state.cooldowns),
	}
end

-- Moving armies, for the unreliable ArmyPositions remote. `progress` is 0..1 towards `to`. ticksToEnter(province,
-- army): the ticks that army takes to step into that province (Sim.Movement.moveTicks).
function Snapshot.positions(state: MatchState, ticksToEnter: (number, Types.Army) -> number): { ArmyPosition }
	local out = {}
	for _, id in sortedKeys(state.armies) do
		local a = state.armies[id]
		local nextId = a.path[1]
		if nextId and not a.inBattle then
			table.insert(out, {
				id = a.id,
				from = a.location,
				to = nextId,
				progress = math.clamp(a.moveProgress / ticksToEnter(nextId, a), 0, 1),
			})
		end
	end
	return out
end

-- Order-independent text form of a plain value, for cheap "did this change" checks.
local function encode(v: any): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		local val = v[k]
		if val == nil then
			val = v[tonumber(k)]
		end
		table.insert(parts, k .. "=" .. encode(val))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function sameRecord(a: { [string]: any }, b: { [string]: any }): boolean
	for k, v in a do
		if b[k] ~= v then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function changed<T>(before: { T }, after: { T }): { T }
	local old: { [number]: T } = {}
	for _, r in before do
		old[(r :: any).id] = r
	end
	local out = {}
	for _, r in after do
		local prev = old[(r :: any).id]
		if prev == nil or not sameRecord(prev :: any, r :: any) then
			table.insert(out, r)
		end
	end
	return out
end

-- Records that differ between two snapshots, plus this tick's events. Returns nil when nothing changed but the tick.
function Snapshot.diff(before: SnapshotData, after: SnapshotData, events: { Types.MatchEvent }?): DeltaData?
	local removed = {}
	local alive: { [number]: boolean } = {}
	for _, a in after.armies do
		alive[a.id] = true
	end
	for _, a in before.armies do
		if not alive[a.id] then
			table.insert(removed, a.id)
		end
	end
	local delta: DeltaData = {
		tick = after.tick,
		phase = after.phase,
		provinces = changed(before.provinces, after.provinces),
		nations = changed(before.nations, after.nations),
		armies = changed(before.armies, after.armies),
		removedArmies = removed,
		diplomacy = if encode(before.diplomacy) ~= encode(after.diplomacy) then after.diplomacy else nil,
		primordials = if encode(before.primordials) ~= encode(after.primordials) then after.primordials else nil,
		result = if encode(before.result) ~= encode(after.result) then after.result else nil,
		cosmetics = if encode(before.cosmetics) ~= encode(after.cosmetics) then after.cosmetics else nil,
		events = if events then table.clone(events) else {},
	}
	if
		#delta.provinces == 0
		and #delta.nations == 0
		and #delta.armies == 0
		and #removed == 0
		and before.phase == after.phase
		and delta.diplomacy == nil
		and delta.primordials == nil
		and delta.result == nil
		and delta.cosmetics == nil
		and #delta.events == 0
	then
		return nil
	end
	return delta
end

local function merge<T>(list: { T }, updates: { T }): { T }
	local index: { [number]: number } = {}
	for i, r in list do
		index[(r :: any).id] = i
	end
	for _, r in updates do
		local i = index[(r :: any).id]
		if i then
			list[i] = r
		else
			table.insert(list, r)
			index[(r :: any).id] = #list
		end
	end
	return list
end

-- Client side: bring a snapshot up to date with a delta (changes it in place and returns it).
function Snapshot.apply(snapshot: SnapshotData, delta: DeltaData): SnapshotData
	snapshot.tick = delta.tick
	snapshot.phase = delta.phase
	merge(snapshot.provinces, delta.provinces)
	merge(snapshot.nations, delta.nations)
	merge(snapshot.armies, delta.armies)
	if delta.diplomacy then
		snapshot.diplomacy = delta.diplomacy
	end
	if delta.primordials then
		snapshot.primordials = delta.primordials
	end
	if delta.result then
		snapshot.result = delta.result
	end
	if delta.cosmetics then
		snapshot.cosmetics = delta.cosmetics
	end
	if #delta.removedArmies > 0 then
		local gone: { [number]: boolean } = {}
		for _, id in delta.removedArmies do
			gone[id] = true
		end
		local kept = {}
		for _, a in snapshot.armies do
			if not gone[a.id] then
				table.insert(kept, a)
			end
		end
		snapshot.armies = kept
	end
	return snapshot
end

return Snapshot
