--!strict
-- Private server settings (docs/MONETIZATION.md 3.4; allowed values in Config.Private). The owner changes them in
-- the Lobby (Sim.Lobby checks who and when, this module what); the next match carries them in MatchState.setup,
-- and every rule that depends on them reads them from there: the phase clock (Match.phaseAt), powers and disasters
-- (Primordial), locked teams (Diplomacy), bot difficulty (AIService), rewards (Settings.fullRewards), and the EU4
-- pack's features (Settings.FEATURES: insults, gifts and military access in Diplomacy).
-- Public servers play the defaults. Pure: no Roblox, randomness from the seeded Rng.

local Army = require("./Army")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Rng = require("./Rng")
local Types = require("../Types")

type MatchSettings = Types.MatchSettings
type MatchSetup = Types.MatchSetup
type MatchState = Types.MatchState

-- When each phase starts, in match ticks.
export type Timing = { peaceEnd: number, warEnd: number, matchEnd: number }

local TICKS_PER_MINUTE = 60 // Config.TickSeconds

local Settings = {}

-- What public servers play: Config.Phases, Config.Bots.Difficulty, every nation filled, everything on.
function Settings.defaults(): MatchSettings
	return {
		map = "",
		theme = Config.Private.Themes[1],
		minutes = Config.Phases.MatchEndTick // TICKS_PER_MINUTE,
		peaceMinutes = Config.Phases.PeaceEndTick // TICKS_PER_MINUTE,
		bots = Config.Private.MaxBots,
		difficulty = Config.Bots.Difficulty :: Types.Difficulty,
		powers = true,
		disasters = true,
		teams = {},
		diplomacy = Config.Features.Diplomacy,
	}
end

-- The EU4 pack's features: on/off settings (MatchSettings keys), defaults in Config.Features. Those listed in
-- Settings.CUSTOM_FEATURES make a match "custom rules" (half rewards) when changed; the others don't, because turning
-- them off makes nothing easier to farm (insults, gifts and access: an owner may turn them off for younger players
-- and keep full rewards).
Settings.FEATURES = { "diplomacy" } :: { string }
Settings.CUSTOM_FEATURES = {} :: { string }

function Settings.copy(settings: MatchSettings): MatchSettings
	local out = table.clone(settings)
	out.teams = {}
	for _, entry in settings.teams do
		table.insert(out.teams, { userId = entry.userId, team = entry.team })
	end
	return out
end

-- A match's setup: a copy of the settings, so changing them in the next Lobby never touches a running match.
function Settings.setup(private: boolean, settings: MatchSettings?): MatchSetup
	return { private = private, settings = Settings.copy(settings or Settings.defaults()) }
end

-- Phase boundaries. The Cataclysm always lasts its default length and ends the match; Peace lasts the setting.
function Settings.timing(setup: MatchSetup?): Timing
	local p = Config.Phases
	if setup == nil then
		return { peaceEnd = p.PeaceEndTick, warEnd = p.WarEndTick, matchEnd = p.MatchEndTick }
	end
	local s = setup.settings
	local matchEnd = s.minutes * TICKS_PER_MINUTE
	return {
		peaceEnd = math.min(s.peaceMinutes * TICKS_PER_MINUTE, matchEnd),
		warEnd = math.max(matchEnd - (p.MatchEndTick - p.WarEndTick), 0),
		matchEnd = matchEnd,
	}
end

-- A player's team (0 = none).
function Settings.teamOf(settings: MatchSettings, userId: number): number
	for _, entry in settings.teams do
		if entry.userId == userId then
			return entry.team
		end
	end
	return 0
end

local function isWhole(v: unknown): boolean
	return type(v) == "number" and v == math.floor(v)
end

local function setTeam(settings: MatchSettings, userId: unknown, team: number): (boolean, string?)
	if not isWhole(userId) or not isWhole(team) or team < 0 or team > Config.Private.Teams then
		return false, "BadSetting"
	end
	local uid = userId :: number
	local members = 0
	for _, entry in settings.teams do
		if entry.team == team and entry.userId ~= uid then
			members += 1
		end
	end
	if team > 0 and members >= Config.Diplomacy.MaxAllianceSize then
		return false, "TeamFull"
	end
	for i, entry in settings.teams do
		if entry.userId == uid then
			table.remove(settings.teams, i)
			break
		end
	end
	if team > 0 then
		table.insert(settings.teams, { userId = uid, team = team })
		table.sort(settings.teams, function(a, b)
			return a.userId < b.userId
		end)
	end
	return true, nil
end

-- Change one setting, after checking the value is allowed. `maps` are the map ids the server can play.
-- key "team": player `value` (a userId) joins team `extra` (0 = no team).
function Settings.set(
	settings: MatchSettings,
	key: string,
	value: unknown,
	extra: number,
	maps: { string }
): (boolean, string?)
	local P = Config.Private
	if key == "team" then
		return setTeam(settings, value, extra)
	elseif key == "map" then
		if type(value) ~= "string" or (value ~= "" and table.find(maps, value :: string) == nil) then
			return false, "BadSetting"
		end
		settings.map = value :: string
	elseif key == "theme" then
		if type(value) ~= "string" or table.find(P.Themes, value :: string) == nil then
			return false, "BadSetting"
		end
		settings.theme = value :: string
	elseif key == "minutes" then
		if type(value) ~= "number" or table.find(P.Minutes, value :: number) == nil then
			return false, "BadSetting"
		end
		settings.minutes = value :: number
	elseif key == "peaceMinutes" then
		if type(value) ~= "number" or table.find(P.PeaceMinutes, value :: number) == nil then
			return false, "BadSetting"
		end
		settings.peaceMinutes = value :: number
	elseif key == "bots" then
		if not isWhole(value) or (value :: number) < 0 or (value :: number) > P.MaxBots then
			return false, "BadSetting"
		end
		settings.bots = value :: number
	elseif key == "difficulty" then
		if type(value) ~= "string" or table.find(P.Difficulties, value :: string) == nil then
			return false, "BadSetting"
		end
		settings.difficulty = value :: Types.Difficulty
	elseif key == "powers" or key == "disasters" then
		if type(value) ~= "boolean" then
			return false, "BadSetting"
		end
		if key == "powers" then
			settings.powers = value :: boolean
		else
			settings.disasters = value :: boolean
		end
	elseif table.find(Settings.FEATURES, key) then
		if type(value) ~= "boolean" then
			return false, "BadSetting"
		end
		(settings :: any)[key] = value
	else
		return false, "BadRequest"
	end
	return true, nil
end

-- Default rules? The map and the theme only change how a match looks, so they don't count, and neither do the EU4
-- pack's features outside Settings.CUSTOM_FEATURES; everything else does.
function Settings.isStandard(settings: MatchSettings): boolean
	local d = Settings.defaults()
	for _, key in Settings.CUSTOM_FEATURES do
		if (settings :: any)[key] ~= (d :: any)[key] then
			return false
		end
	end
	return settings.minutes == d.minutes
		and settings.peaceMinutes == d.peaceMinutes
		and settings.bots == d.bots
		and settings.difficulty == d.difficulty
		and settings.powers == d.powers
		and settings.disasters == d.disasters
		and #settings.teams == 0
end

-- Players who held a nation at some point in the match.
function Settings.humans(state: MatchState): number
	local n = 0
	for _ in state.seats do
		n += 1
	end
	return n
end

-- Full XP and Glory? Always on a public server; on a private one only with default rules and
-- Config.Private.FullRewardHumans players (otherwise Config.Progression.CustomRulesShare).
function Settings.fullRewards(state: MatchState): boolean
	local setup = state.setup
	if not setup.private then
		return true
	end
	return Settings.isStandard(setup.settings) and Settings.humans(state) >= Config.Private.FullRewardHumans
end

local function sortedKeys(t: { [number]: any }): { number }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	return keys
end

-- Take a nation off the map before the match starts: its land turns neutral, with a garrison.
local function removeNation(state: MatchState, nationId: number)
	for _, id in sortedKeys(state.provinces) do
		local p = state.provinces[id]
		if p.owner == nationId then
			p.owner = nil
			p.isCapital = false
			p.siege = nil
			Army.spawn(state, 0, id, Config.NeutralGarrison)
		end
	end
	for _, id in sortedKeys(state.armies) do
		if state.armies[id].owner == nationId then
			state.armies[id] = nil
		end
	end
	state.nations[nationId] = nil
end

-- Once the players are seated, right before tick 0: keep at most `bots` bot nations (the Rng picks which ones
-- go), and ally each locked team's players (up to Config.Diplomacy.MaxAllianceSize per team, lowest nation first).
function Settings.prepare(state: MatchState, rng: Rng.Rng)
	local settings = state.setup.settings
	local bots: { number } = {}
	for _, id in sortedKeys(state.nations) do
		local n = state.nations[id]
		if n.controller == "Bot" and n.userId == nil and not n.eliminated then
			table.insert(bots, id)
		end
	end
	while #bots > settings.bots do
		removeNation(state, table.remove(bots, Rng.int(rng, 1, #bots)) :: number)
	end
	local teams: { [number]: { number } } = {}
	for _, id in sortedKeys(state.nations) do
		local userId = state.nations[id].userId
		local team = if userId then Settings.teamOf(settings, userId) else 0
		if team > 0 then
			teams[team] = teams[team] or {}
			if #teams[team] < Config.Diplomacy.MaxAllianceSize then
				table.insert(teams[team], id)
			end
		end
	end
	for _, team in sortedKeys(teams) do
		local members = teams[team]
		for i = 2, #members do
			Diplomacy.ally(state, members[1], members[i])
		end
	end
end

return Settings
