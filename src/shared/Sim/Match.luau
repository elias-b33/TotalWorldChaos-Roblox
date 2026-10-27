--!strict
-- Match setup, phases and seats (which player controls which nation).

local Army = require("./Army")
local Config = require("../Config")
local Types = require("../Types")

type MatchState = Types.MatchState
type MapDef = Types.MapDef
type Phase = Types.Phase

local Match = {}

-- A fresh match on a map: start territories, capitals, start gold and manpower. Every nation starts as a bot.
function Match.new(map: MapDef): MatchState
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
	local state: MatchState = {
		mapId = map.id,
		tick = 0,
		phase = "Peace",
		provinces = provinces,
		nations = nations,
		armies = {},
		wars = {},
		alliances = {},
		truces = {},
		primordials = {},
		battles = {},
		offers = {},
		events = {},
		result = nil,
	}
	-- neutral land starts with a garrison, so expanding means a small fight first
	for _, def in map.provinces do
		if def.startOwner == nil and def.terrain ~= "Mountain" then
			Army.spawn(state, 0, def.id, def.garrison or Config.NeutralGarrison)
		end
	end
	return state
end

-- Phase for a match tick. Lobby and Pick are not used until the map vote and draft exist.
function Match.phaseAt(tick: number): Phase
	local p = Config.Phases
	if tick < p.PeaceEndTick then
		return "Peace"
	elseif tick < p.WarEndTick then
		return "War"
	elseif tick < p.MatchEndTick then
		return "Cataclysm"
	end
	return "Results"
end

-- True once Results has been shown long enough to start the next match.
function Match.isOver(state: MatchState): boolean
	local result = state.result
	return result ~= nil and state.tick >= result.endedAt + Config.Phases.ResultsTicks
end

-- Give a joining player the lowest-numbered nation a bot is playing. Returns nil if every seat is taken.
function Match.seatPlayer(state: MatchState, userId: number): number?
	for id, nation in state.nations do
		if nation.userId == userId then
			return id
		end
	end
	local best: number? = nil
	for id, nation in state.nations do
		if nation.controller == "Bot" and not nation.eliminated and (best == nil or id < best) then
			best = id
		end
	end
	if best then
		local nation = state.nations[best]
		nation.controller = "Player"
		nation.userId = userId
	end
	return best
end

-- A player who leaves is replaced by a bot instantly.
function Match.unseatPlayer(state: MatchState, userId: number)
	for _, nation in state.nations do
		if nation.userId == userId then
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
