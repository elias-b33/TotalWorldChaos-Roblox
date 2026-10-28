--!strict
-- Private server settings (docs/MONETIZATION.md 3.4): allowed values, who may change them, and every rule that
-- reads them from MatchState.setup (the clock, powers, disasters, bots, teams, rewards).
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Lobby = require("../src/shared/Sim/Lobby")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Primordial = require("../src/shared/Sim/Primordial")
local Progression = require("../src/shared/Sim/Progression")
local Rng = require("../src/shared/Sim/Rng")
local Settings = require("../src/shared/Sim/Settings")
local T = require("./TestKit")
local Tick = require("../src/shared/Sim/Tick")
local Types = require("../src/shared/Types")

local map = Maps.get("skyshards")
local OWNER = 501

local function custom(changes: { [string]: any }): Types.MatchSettings
	local s = Settings.defaults()
	for key, value in changes do
		assert(Settings.set(s, key, value, 0, Maps.ids))
	end
	return s
end

local function privateMatch(changes: { [string]: any }): Types.MatchState
	return Match.new(map, Settings.setup(true, custom(changes)))
end

-- Defaults -------------------------------------------------------------------------------------------------

T.test("the defaults are what public servers play", function()
	local d = Settings.defaults()
	local t = Settings.timing(Settings.setup(false, d))
	T.equal(t.peaceEnd, Config.Phases.PeaceEndTick)
	T.equal(t.warEnd, Config.Phases.WarEndTick)
	T.equal(t.matchEnd, Config.Phases.MatchEndTick)
	T.equal(d.difficulty, Config.Bots.Difficulty)
	T.equal(d.bots, Config.Private.MaxBots)
	T.expect(d.powers and d.disasters and d.map == "" and #d.teams == 0)
	T.expect(table.find(Config.Private.Minutes, d.minutes) ~= nil, "the default length is an option")
	T.expect(table.find(Config.Private.PeaceMinutes, d.peaceMinutes) ~= nil, "the default peace is an option")
	local state = Match.new(map)
	T.equal(state.setup.private, false, "Match.new without a setup: a public server")
	T.expect(Settings.isStandard(state.setup.settings))
end)

-- Changing settings ----------------------------------------------------------------------------------------

T.test("only the allowed values are taken", function()
	local s = Settings.defaults()
	T.expect((Settings.set(s, "minutes", 15, 0, Maps.ids)))
	T.equal(s.minutes, 15)
	T.equal(select(2, Settings.set(s, "minutes", 20, 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "peaceMinutes", 4, 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "bots", 10, 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "bots", 2.5, 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "difficulty", "Insane", 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "powers", "no", 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "map", "atlantis", 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "theme", "Neon", 0, Maps.ids)), "BadSetting")
	T.equal(select(2, Settings.set(s, "gold", 9999, 0, Maps.ids)), "BadRequest")
	T.expect((Settings.set(s, "bots", 0, 0, Maps.ids)))
	T.expect((Settings.set(s, "difficulty", "Hard", 0, Maps.ids)))
	T.expect((Settings.set(s, "powers", false, 0, Maps.ids)))
	T.expect((Settings.set(s, "theme", "Default", 0, Maps.ids)))
	T.expect((Settings.set(s, "map", "earth", 0, Maps.ids)))
	T.expect((Settings.set(s, "map", "", 0, Maps.ids)), "back to the vote")
	T.equal(s.minutes, 15, "a refused value changes nothing")
end)

T.test("teams hold up to the alliance size; team 0 takes a player out", function()
	local s = Settings.defaults()
	for userId = 1, Config.Diplomacy.MaxAllianceSize do
		T.expect((Settings.set(s, "team", userId, 1, Maps.ids)))
	end
	T.equal(select(2, Settings.set(s, "team", 99, 1, Maps.ids)), "TeamFull")
	T.expect((Settings.set(s, "team", 1, 1, Maps.ids)), "staying in your own team is fine")
	T.equal(select(2, Settings.set(s, "team", 99, Config.Private.Teams + 1, Maps.ids)), "BadSetting")
	T.expect((Settings.set(s, "team", 2, 2, Maps.ids)), "moving to another team")
	T.equal(Settings.teamOf(s, 2), 2)
	T.expect((Settings.set(s, "team", 99, 1, Maps.ids)), "now there is room")
	T.expect((Settings.set(s, "team", 2, 0, Maps.ids)))
	T.equal(Settings.teamOf(s, 2), 0)
	T.equal(#s.teams, 3)
end)

T.test("only the owner changes settings, only during the vote; a map setting locks the vote", function()
	local public = Lobby.new(Maps.ids, nil)
	T.equal(select(2, Lobby.setting(public, OWNER, "minutes", 15, 0)), "NotOwner", "a public server has no owner")
	local lobby = Lobby.new(Maps.ids, nil, OWNER, Settings.defaults())
	T.equal(
		select(2, Lobby.apply(lobby, nil, 7, { kind = "Setting", key = "minutes", value = 15, extra = 0 })),
		"NotOwner"
	)
	T.expect((Lobby.apply(lobby, nil, OWNER, { kind = "Setting", key = "minutes", value = 15, extra = 0 })))
	T.equal(lobby.settings.minutes, 15)
	T.expect((Lobby.setting(lobby, OWNER, "map", "eldmoor", 0)))
	T.equal(lobby.locked, "eldmoor")
	T.equal(#lobby.maps, 1)
	T.equal(select(2, Lobby.vote(lobby, 7, "earth")), "Locked")
	T.equal(Lobby.winner(lobby, Rng.new(1)), "eldmoor")
	T.expect((Lobby.setting(lobby, OWNER, "map", "", 0)))
	T.equal(lobby.locked, nil)
	T.equal(#lobby.maps, #Maps.ids, "every map is back on the cards")
	-- the next lobby keeps the settings (the service passes the same table), the map lock included
	assert(Lobby.setting(lobby, OWNER, "map", "earth", 0))
	local next = Lobby.new(Maps.ids, nil, OWNER, lobby.settings)
	T.equal(next.locked, "earth")
	T.equal(next.settings.minutes, 15)
	-- the draft has started: too late
	Lobby.startPick(next, Match.new(map), { OWNER }, Rng.new(1))
	T.equal(select(2, Lobby.setting(next, OWNER, "minutes", 35, 0)), "WrongPhase")
	-- everyone sees them
	local view = Lobby.view(next, { [OWNER] = "Olivia", [7] = "Pete" })
	T.expect(view.private and view.owner == OWNER and view.settings.minutes == 15)
	T.equal(#view.players, 2)
end)

-- The clock ------------------------------------------------------------------------------------------------

T.test("match length and peace move the phases; the Cataclysm is always the last 5 minutes", function()
	local state = privateMatch({ minutes = 15 })
	local cataclysm = Config.Phases.MatchEndTick - Config.Phases.WarEndTick
	T.equal(Match.phaseAt(0, state.setup), "Peace")
	T.equal(Match.phaseAt(Config.Phases.PeaceEndTick, state.setup), "War")
	T.equal(Match.phaseAt(15 * 60 - cataclysm - 1, state.setup), "War")
	T.equal(Match.phaseAt(15 * 60 - cataclysm, state.setup), "Cataclysm")
	T.equal(Match.phaseAt(15 * 60, state.setup), "Results")
	local long = privateMatch({ minutes = 35, peaceMinutes = 5 })
	T.equal(Match.phaseAt(5 * 60 - 1, long.setup), "Peace")
	T.equal(Match.phaseAt(5 * 60, long.setup), "War")
	T.equal(Match.phaseAt(30 * 60, long.setup), "Cataclysm")
	T.equal(Match.phaseAt(35 * 60 - 1, long.setup), "Cataclysm")
	local noPeace = privateMatch({ peaceMinutes = 0 })
	T.equal(noPeace.phase, "War", "no Peace: the match starts at war")
	T.equal(Match.phaseAt(0, nil), "Peace", "no setup: the defaults")
end)

T.test("a 15-minute match ends at 15:00 with the best score", function()
	local state = privateMatch({ minutes = 15 })
	state.tick = 15 * 60 - 2
	state.phase = Match.phaseAt(state.tick, state.setup)
	local rng = Rng.new(1)
	Tick.advance(state, rng)
	T.equal(state.result, nil, "still playing at 14:59")
	T.equal(Tick.advance(state, rng), "Results")
	local result = state.result :: Types.MatchResult
	T.equal(result.kind, "Score")
	T.equal(result.endedAt, 15 * 60)
end)

-- Powers and disasters -------------------------------------------------------------------------------------

T.test("powers off: no charges, and every power is refused", function()
	local state = privateMatch({ powers = false })
	state.tick = Config.Phases.PeaceEndTick
	state.phase = "War"
	local rng = Rng.new(1)
	for _ = 1, Config.Primordial.NationChargeTicks do
		Tick.advance(state, rng)
	end
	T.equal(state.nations[1].charges, 0, "no charges come")
	state.nations[1].charges = 5
	local ok, reason =
		Commands.apply(state, 1, { kind = "Power", power = "Blessing", target = state.nations[1].capital })
	T.equal(ok, false)
	T.equal(reason, "PowersOff")
	state.primordials[9] = { userId = 9, charges = 5, chargeTicks = 0 }
	T.equal(
		select(2, Commands.applyPrimordial(state, 9, { kind = "Power", power = "Plague", target = 2 })),
		"PowersOff"
	)
end)

T.test("disasters follow the match's Cataclysm, and stop when turned off", function()
	local state = privateMatch({ minutes = 15 })
	local warEnd = Settings.timing(state.setup).warEnd
	state.tick = warEnd + Config.Primordial.CataclysmDisasterTicks
	state.phase = Match.phaseAt(state.tick, state.setup)
	T.equal(state.phase, "Cataclysm")
	T.expect(Primordial.disasterDue(state), "a disaster a minute into a 15-minute match's Cataclysm")
	local calm = privateMatch({ minutes = 15, disasters = false })
	calm.tick, calm.phase = state.tick, state.phase
	T.expect(not Primordial.disasterDue(calm), "disasters off")
end)

-- Bots and teams -------------------------------------------------------------------------------------------

T.test("the bot count takes the other nations off the map; their land turns neutral", function()
	local state = privateMatch({ bots = 3 })
	Match.seatPlayer(state, 11)
	Match.seatPlayer(state, 12)
	Settings.prepare(state, Rng.new(4))
	local players, bots = 0, 0
	for _, n in state.nations do
		if n.controller == "Player" then
			players += 1
		else
			bots += 1
		end
	end
	T.equal(players, 2)
	T.equal(bots, 3)
	for _, p in state.provinces do
		T.expect(p.owner == nil or state.nations[p.owner] ~= nil, "every owned province has a nation")
		if p.owner == nil and p.terrain ~= "Mountain" then
			local guarded = false
			for _, a in state.armies do
				guarded = guarded or (a.location == p.id and a.owner == 0)
			end
			T.expect(guarded, "neutral land has a garrison: " .. p.name)
		end
	end
	-- a public match keeps every nation
	local full = Match.new(map)
	Match.seatPlayer(full, 11)
	Settings.prepare(full, Rng.new(4))
	local count = 0
	for _ in full.nations do
		count += 1
	end
	T.equal(count, #map.nations)
end)

T.test("locked teams start allied, and nobody can make another alliance", function()
	local s = custom({})
	for _, userId in { 11, 12, 13, 14 } do
		assert(Settings.set(s, "team", userId, if userId <= 13 then 1 else 2, Maps.ids))
	end
	local state = Match.new(map, Settings.setup(true, s))
	for _, userId in { 11, 12, 13, 14, 15 } do
		Match.seatPlayer(state, userId)
	end
	Settings.prepare(state, Rng.new(1))
	local a, b, c = Match.nationOf(state, 11) :: number, Match.nationOf(state, 12) :: number, Match.nationOf(state, 13)
	T.expect(Diplomacy.allied(state, a, b) and Diplomacy.allied(state, a, c :: number), "team 1 is one alliance")
	local d = Match.nationOf(state, 14) :: number
	T.expect(not Diplomacy.allied(state, a, d), "team 2 is apart (one player: no alliance)")
	local e = Match.nationOf(state, 15) :: number
	state.tick, state.phase = Config.Phases.PeaceEndTick, "War"
	T.equal(select(2, Diplomacy.propose(state, "Ally", d, e, 0)), "TeamsLocked")
	T.equal(select(2, Diplomacy.propose(state, "Peace", d, e, 0)), "NotAtWar", "peace offers still work")
end)

-- Rewards --------------------------------------------------------------------------------------------------

local function seat(state: Types.MatchState, humans: number)
	for userId = 1, humans do
		Match.seatPlayer(state, 100 + userId)
	end
end

T.test("rewards: full on public servers; private needs default rules and 4 players", function()
	local public = Match.new(map)
	seat(public, 1)
	T.expect(Settings.fullRewards(public), "a public server always pays in full")
	local three = Match.new(map, Settings.setup(true))
	seat(three, 3)
	T.expect(not Settings.fullRewards(three), "3 players on a private server: half")
	local four = Match.new(map, Settings.setup(true))
	seat(four, Config.Private.FullRewardHumans)
	T.expect(Settings.fullRewards(four), "4 players with default rules: full")
	local looks = privateMatch({ map = "earth", theme = "Default" })
	seat(looks, 4)
	T.expect(Settings.fullRewards(looks), "the map and the theme aren't rules")
	for key, value in
		{ minutes = 15, peaceMinutes = 0, bots = 8, difficulty = "Easy", powers = false, disasters = false }
	do
		local state = privateMatch({ [key] = value })
		seat(state, 10)
		T.expect(not Settings.fullRewards(state), key .. " is a custom rule: half")
	end
end)

T.test("a private match with custom rules pays half the XP and Glory", function()
	local state = privateMatch({ minutes = 15 })
	seat(state, 4)
	local stats = Progression.newStats(101, 0)
	stats.seated = true
	state.tick = 15 * 60 - 1
	Tick.advance(state, Rng.new(1))
	T.equal((state.result :: Types.MatchResult).endedAt, 15 * 60)
	stats.lastCommandAt = state.tick
	local full = Progression.matchReward(state, stats, { vip = false, firstMatchToday = false, standardRules = true })
	local half = Progression.matchReward(
		state,
		stats,
		{ vip = false, firstMatchToday = false, standardRules = Settings.fullRewards(state) }
	)
	T.expect(full.xp > 0, "the match pays something")
	T.equal(half.xp, math.floor(full.xp * Config.Progression.CustomRulesShare + 0.5))
	T.equal(half.glory, math.floor(full.glory * Config.Progression.CustomRulesShare + 0.5))
	local finish = 0
	for _, line in full.lines do
		finish += if line.kind == "Finish" then line.xp else 0
	end
	T.equal(finish, Config.Progression.FinishXp, "a whole 15-minute match counts as a whole match")
end)

T.finish()
