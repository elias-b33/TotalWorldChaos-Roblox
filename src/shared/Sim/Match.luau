--!strict
-- Match setup, phases and seats (which player controls which nation).

local Army = require("./Army")
local Config = require("../Config")
local Settings = require("./Settings")
local Types = require("../Types")

type MatchState = Types.MatchState
type MapDef = Types.MapDef
type Phase = Types.Phase

local Match = {}

-- Phase for a match tick, on this setup's clock (nil = the defaults in Config.Phases). Lobby and Pick come before
-- tick 0 and are run by Sim.Lobby.
function Match.phaseAt(tick: number, setup: Types.MatchSetup?): Phase
	local t = Settings.timing(setup)
	if tick < t.peaceEnd then
		return "Peace"
	elseif tick < t.warEnd then
		return "War"
	elseif tick < t.matchEnd then
		return "Cataclysm"
	end
	return "Results"
end

-- A fresh match on a map: start territories, capitals, races, start gold and manpower. Every nation starts as a bot.
-- `setup` carries a private server's settings (nil = a public server's defaults); Settings.prepare applies the
-- bot count and teams once the players are seated.
function Match.new(map: MapDef, setup: Types.MatchSetup?): MatchState
	local provinces: { [number]: Types.Province } = {}
	for _, def in map.provinces do
		provinces[def.id] = {
			id = def.id,
			name = def.name,
			terrain = def.terrain,
			neighbors = table.clone(def.neighbors),
			owner = def.startOwner,
			development = def.development,
			building = "None",
			isCapital = def.isCapital,
			siege = nil,
			shieldUntil = nil,
			buffs = {},
		}
	end
	local nations: { [number]: Types.Nation } = {}
	for _, def in map.nations do
		nations[def.slot] = {
			id = def.slot,
			name = def.name,
			colorIndex = def.colorIndex,
			race = def.race,
			controller = "Bot",
			userId = nil,
			capital = def.capital,
			gold = Config.StartGold,
			manpower = Config.StartManpower,
			charges = 0,
			allianceId = nil,
			powerImmuneUntil = 0,
			eliminated = false,
			battlesWon = 0,
		}
	end
	-- the sea (docs/DESIGN.md "Navies"): zones, which zones each coast touches (its port first), each strait's zone
	local zones: { [number]: Types.SeaZone } = {}
	for _, z in map.seaZones or {} do
		zones[z.id] = { id = z.id, name = z.name, neighbors = table.clone(z.neighbors), coasts = table.clone(z.coasts) }
	end
	local shores: { [number]: { number } } = {}
	for _, def in map.provinces do
		if def.zones and #def.zones > 0 then
			shores[def.id] = table.clone(def.zones)
		end
	end
	local straits: { [number]: { [number]: number } } = {}
	for _, s in map.straits do
		if s.zone then
			straits[s.a] = straits[s.a] or {}
			straits[s.a][s.b] = s.zone
			straits[s.b] = straits[s.b] or {}
			straits[s.b][s.a] = s.zone
		end
	end
	local matchSetup = setup or Settings.setup(false)
	local state: MatchState = {
		mapId = map.id,
		setup = matchSetup,
		tick = 0,
		phase = Match.phaseAt(0, matchSetup),
		provinces = provinces,
		nations = nations,
		armies = {},
		wars = {},
		alliances = {},
		truces = {},
		primordials = {},
		seats = {},
		nextArmyId = 1,
		mergedInto = {},
		battles = {},
		zones = zones,
		shores = shores,
		straits = straits,
		fleets = {},
		nextFleetId = 1,
		fleetMergedInto = {},
		seaBattles = {},
		offers = {},
		events = {},
		pings = {},
		pingSent = {},
		nextPingId = 1,
		result = nil,
		grudges = {},
		answers = {},
		cooldowns = {},
		access = {},
		chronicles = {},
		boosts = {},
		nextCardId = 1,
	}
	-- neutral land starts with a garrison, so expanding means a small fight first
	for _, def in map.provinces do
		if def.startOwner == nil and def.terrain ~= "Mountain" then
			Army.spawn(state, 0, def.id, def.garrison or Config.NeutralGarrison)
		end
	end
	return state
end

-- True once Results has been shown long enough to start the next match.
function Match.isOver(state: MatchState): boolean
	local result = state.result
	return result ~= nil and state.tick >= result.endedAt + Config.Phases.ResultsTicks
end

-- Hand a nation to a player, and remember it was theirs (Match.seatPlayer gives it back if they rejoin).
function Match.assign(state: MatchState, nationId: number, userId: number)
	local nation = state.nations[nationId]
	nation.controller = "Player"
	nation.userId = userId
	state.seats[userId] = nationId
end

-- Seat a joining player. A player who held a nation earlier in this match gets it back while a bot runs it, or
-- rises as its Primordial if it was eliminated while they were away, so leaving never swaps a dying nation for a
-- healthy one. Anyone else gets the lowest-numbered bot nation, preferring ones no absent player held. Returns
-- nil if every seat is taken, or for a newcomer once the match has a result.
function Match.seatPlayer(state: MatchState, userId: number): number?
	for id, nation in state.nations do
		if nation.userId == userId then
			return id
		end
	end
	local held = state.seats[userId]
	local mine = if held then state.nations[held] else nil
	if held and mine and mine.userId == nil then
		Match.assign(state, held, userId)
		if mine.eliminated and state.primordials[userId] == nil then
			state.primordials[userId] = { userId = userId, charges = 0, chargeTicks = 0 }
		end
		return held
	end
	if state.result ~= nil then
		return nil -- the match is over: a newcomer watches the Results and gets a nation in the next match
	end
	local reserved: { [number]: boolean } = {}
	for other, id in state.seats do
		if other ~= userId then
			reserved[id] = true
		end
	end
	local best: number? = nil
	for id, nation in state.nations do
		if nation.controller == "Bot" and not nation.eliminated then
			local better = best == nil
				or (reserved[best] and not reserved[id])
				or (reserved[best] == reserved[id] and id < best)
			if better then
				best = id
			end
		end
	end
	if best then
		Match.assign(state, best, userId)
	end
	return best
end

-- A player who leaves is replaced by a bot instantly. An eliminated nation stays theirs (they rejoin as a Primordial).
-- Match.seats still remembers the nation, so a rejoining player gets it back.
function Match.unseatPlayer(state: MatchState, userId: number)
	for _, nation in state.nations do
		if nation.userId == userId and not nation.eliminated then
			nation.controller = "Bot"
			nation.userId = nil
		end
	end
end

function Match.nationOf(state: MatchState, userId: number): number?
	for id, nation in state.nations do
		if nation.userId == userId then
			return id
		end
	end
	return nil
end

function Match.provinceCount(state: MatchState, nationId: number): number
	local n = 0
	for _, p in state.provinces do
		if p.owner == nationId then
			n += 1
		end
	end
	return n
end

return Match
