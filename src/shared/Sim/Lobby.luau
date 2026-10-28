--!strict
-- The lobby before every match (docs/DESIGN.md "Match structure"):
-- 1. Lobby: players join and vote on the map. Most votes wins; a tie (or no votes) is settled by the Rng.
--    A map the server set (Workspace "MapId", a private server's map setting) skips the vote. On a private server
--    the owner changes the next match's settings during the vote (Sim.Settings).
--    Theme vote (docs/MONETIZATION.md 3.2): the winning map is painted in the theme equipped by most of its voters.
-- 2. Pick: on the chosen map, players pick a start nation one at a time in a random draft order. A turn that runs
--    out picks a random free nation for that player. Bots keep every nation nobody picked.
-- Pure: takes the lobby (and the new match during the draft) plus an Rng, and changes them.

local Catalogue = require("../Catalogue")
local Config = require("../Config")
local Match = require("./Match")
local Rng = require("./Rng")
local Settings = require("./Settings")
local Types = require("../Types")

type LobbyState = Types.LobbyState
type MatchState = Types.MatchState

-- What clients are told about the lobby (the Lobby remote). Flat arrays only, so it survives the network.
export type LobbyView = {
	phase: string, -- "Lobby" | "Pick" | "None" (no lobby: a match is running)
	ticksLeft: number,
	maps: { string },
	locked: boolean,
	counts: { number }, -- votes for maps[i]
	votes: { { userId: number, map: string } },
	mapId: string, -- "" until the vote is over
	order: { { userId: number, name: string, nation: number } }, -- the draft order; nation 0 = not picked yet
	turn: number, -- index in order of who picks now
	turnTicksLeft: number,
	private: boolean, -- a private server: everyone sees the settings, the owner changes them
	owner: number, -- the private server's owner (userId), 0 = none here or a public server
	settings: Types.MatchSettings, -- the next match's settings
	players: { { userId: number, name: string } }, -- everyone in the server (the settings sheet's team list)
	theme: string, -- the theme the drafted map is painted in ("" until the vote is over)
	themeBy: { string }, -- names of the voters whose equipped theme won
}

local Lobby = {}

-- A fresh lobby: the vote on these maps, or no vote when the server locked one. A private server passes its owner
-- and its settings (kept from the last lobby): a map setting locks the map too.
function Lobby.new(maps: { string }, locked: string?, owner: number?, settings: Types.MatchSettings?): LobbyState
	local s = settings or Settings.defaults()
	local lock = locked or (if s.map ~= "" then s.map else nil)
	return {
		phase = "Lobby",
		ticksLeft = Config.Phases.LobbyTicks,
		maps = if lock then { lock } else table.clone(maps),
		pool = table.clone(maps),
		locked = lock,
		votes = {},
		mapId = nil,
		order = {},
		turn = 1,
		turnTicks = Config.Phases.PickTurnMaxTicks,
		turnTicksLeft = 0,
		picks = {},
		owner = owner,
		settings = s,
	}
end

-- Lock the vote to one map (nil: vote on every map again).
function Lobby.lock(lobby: LobbyState, mapId: string?)
	lobby.locked = mapId
	lobby.maps = if mapId then { mapId } else table.clone(lobby.pool)
end

-- A private server owner changes a setting. Only the owner, only during the vote (the draft already shows the
-- chosen map).
function Lobby.setting(
	lobby: LobbyState,
	userId: number,
	key: string,
	value: string | number | boolean,
	extra: number
): (boolean, string?)
	if lobby.owner == nil or lobby.owner ~= userId then
		return false, "NotOwner"
	end
	if lobby.phase ~= "Lobby" then
		return false, "WrongPhase"
	end
	local ok, reason = Settings.set(lobby.settings, key, value, extra, lobby.pool)
	if ok and key == "map" then
		Lobby.lock(lobby, if lobby.settings.map ~= "" then lobby.settings.map else nil)
	end
	return ok, reason
end

-- Votes per map, in the order of lobby.maps.
function Lobby.tally(lobby: LobbyState): { [string]: number }
	local counts: { [string]: number } = {}
	for _, id in lobby.maps do
		counts[id] = 0
	end
	for _, id in lobby.votes do
		if counts[id] then
			counts[id] += 1
		end
	end
	return counts
end

-- The map with the most votes; ties (and a vote nobody took part in) go to the Rng.
function Lobby.winner(lobby: LobbyState, rng: Rng.Rng): string
	if lobby.locked then
		return lobby.locked
	end
	local counts = Lobby.tally(lobby)
	local best = -1
	local tied: { string } = {}
	for _, id in lobby.maps do
		if counts[id] > best then
			best = counts[id]
			tied = { id }
		elseif counts[id] == best then
			table.insert(tied, id)
		end
	end
	return tied[Rng.int(rng, 1, #tied)]
end

function Lobby.vote(lobby: LobbyState, userId: number, mapId: string): (boolean, string?)
	if lobby.phase ~= "Lobby" then
		return false, "WrongPhase"
	end
	if lobby.locked then
		return false, "Locked"
	end
	if table.find(lobby.maps, mapId) == nil then
		return false, "UnknownMap"
	end
	lobby.votes[userId] = mapId
	return true, nil
end

-- The theme vote. The map is painted in the theme equipped by the most players who voted for it (every player in
-- `themes` when the server locked the map and nobody voted). The classic look doesn't count as a vote; a tie, or
-- nobody with a theme, gives the classic look. `forced` (a theme id the server set: Workspace "Theme", later the
-- private-server setting; the classic id forces the classic look) skips the vote. `themes`: userId -> the theme
-- each player has equipped (Sim.Shop.themeOf). Remembers and returns the theme id and the credited voters.
function Lobby.chooseTheme(
	lobby: LobbyState,
	mapId: string,
	themes: { [number]: string },
	forced: string?
): (string, { number })
	local classic = Catalogue.DEFAULTS.Theme
	local function valid(id: string?): boolean
		local item = if id then Catalogue.item(id) else nil
		return item ~= nil and item.slot == "Theme"
	end
	local everyone = lobby.locked ~= nil and next(lobby.votes) == nil
	local function votedFor(userId: number): boolean
		return everyone or lobby.votes[userId] == mapId
	end
	local chosen, credited = classic, {}
	if forced and valid(forced) then
		chosen = forced
	else
		local counts: { [string]: number } = {}
		for userId, theme in themes do
			if votedFor(userId) and theme ~= classic and valid(theme) then
				counts[theme] = (counts[theme] or 0) + 1
			end
		end
		local best, tied = 0, false
		for theme, n in counts do
			if n > best then
				chosen, best, tied = theme, n, false
			elseif n == best then
				tied = true
			end
		end
		if tied then
			chosen = classic
		end
		if chosen ~= classic then
			for userId, theme in themes do
				if theme == chosen and votedFor(userId) then
					table.insert(credited, userId)
				end
			end
			table.sort(credited)
		end
	end
	lobby.theme = chosen
	lobby.themeBy = credited
	return chosen, credited
end

local function isFree(nation: Types.Nation): boolean
	return nation.controller == "Bot" and nation.userId == nil and not nation.eliminated
end

local function nationCount(match: MatchState): number
	local n = 0
	for _ in match.nations do
		n += 1
	end
	return n
end

-- How long one turn lasts with this many players: the whole draft fits in Config.Phases.PickTicks.
function Lobby.turnTicks(players: number): number
	local p = Config.Phases
	return math.clamp(p.PickTicks // math.max(players, 1), p.PickTurnMinTicks, p.PickTurnMaxTicks)
end

-- The vote is over: the draft starts on `match` (a fresh match on the chosen map). `userIds` are the players in
-- the server; they are shuffled into the draft order (beyond one per nation, the rest watch).
function Lobby.startPick(lobby: LobbyState, match: MatchState, userIds: { number }, rng: Rng.Rng)
	local order = table.clone(userIds)
	for i = #order, 2, -1 do
		local j = Rng.int(rng, 1, i)
		order[i], order[j] = order[j], order[i]
	end
	local seats = nationCount(match)
	while #order > seats do
		table.remove(order)
	end
	lobby.phase = "Pick"
	lobby.mapId = match.mapId
	lobby.ticksLeft = Config.Phases.PickTicks
	lobby.order = order
	lobby.turn = 1
	lobby.turnTicks = Lobby.turnTicks(#order)
	lobby.turnTicksLeft = lobby.turnTicks
	lobby.picks = {}
	match.phase = "Pick"
	if lobby.theme and lobby.theme ~= Catalogue.DEFAULTS.Theme then
		match.theme = lobby.theme -- the theme vote's winner: everyone sees the map in it
	end
end

-- Who picks now (nil once the draft is done).
function Lobby.current(lobby: LobbyState): number?
	if lobby.phase ~= "Pick" then
		return nil
	end
	return lobby.order[lobby.turn]
end

local function seat(lobby: LobbyState, match: MatchState, userId: number, nationId: number)
	Match.assign(match, nationId, userId)
	lobby.picks[userId] = nationId
	lobby.turn += 1
	lobby.turnTicksLeft = lobby.turnTicks
end

-- A random free nation for a player whose turn ran out.
local function autoPick(lobby: LobbyState, match: MatchState, userId: number, rng: Rng.Rng)
	local free: { number } = {}
	for id, nation in match.nations do
		if isFree(nation) then
			table.insert(free, id)
		end
	end
	table.sort(free)
	if #free == 0 then
		lobby.turn += 1 -- nothing left: they watch
		lobby.turnTicksLeft = lobby.turnTicks
		return
	end
	seat(lobby, match, userId, free[Rng.int(rng, 1, #free)])
end

function Lobby.pick(lobby: LobbyState, match: MatchState, userId: number, nationId: number): (boolean, string?)
	if lobby.phase ~= "Pick" then
		return false, "WrongPhase"
	end
	if Lobby.current(lobby) ~= userId then
		return false, "NotYourTurn"
	end
	local nation = match.nations[nationId]
	if nation == nil then
		return false, "BadTarget"
	end
	if not isFree(nation) then
		return false, "Taken"
	end
	seat(lobby, match, userId, nationId)
	return true, nil
end

-- One lobby intent from a player. `match` is the new match during the draft (nil while voting).
function Lobby.apply(
	lobby: LobbyState,
	match: MatchState?,
	userId: number,
	intent: Types.LobbyIntent
): (boolean, string?)
	if intent.kind == "Vote" then
		return Lobby.vote(lobby, userId, intent.map)
	elseif intent.kind == "Pick" then
		if match == nil then
			return false, "WrongPhase"
		end
		return Lobby.pick(lobby, match, userId, intent.nation)
	elseif intent.kind == "Setting" then
		return Lobby.setting(lobby, userId, intent.key, intent.value, intent.extra)
	end
	return false, "BadRequest"
end

-- A player joined. While voting there is nothing to do; during the draft they join the end of the order if a
-- nation is left for them.
function Lobby.join(lobby: LobbyState, match: MatchState?, userId: number)
	if lobby.phase ~= "Pick" or match == nil or table.find(lobby.order, userId) then
		return
	end
	if #lobby.order < nationCount(match) then
		table.insert(lobby.order, userId)
	end
end

-- A player left: their vote goes, and during the draft their place in the order and any nation they picked.
function Lobby.leave(lobby: LobbyState, match: MatchState?, userId: number)
	lobby.votes[userId] = nil
	local index = table.find(lobby.order, userId)
	if lobby.phase ~= "Pick" or index == nil then
		return
	end
	table.remove(lobby.order, index)
	if lobby.picks[userId] then
		lobby.picks[userId] = nil
		if match then
			Match.unseatPlayer(match, userId)
			match.seats[userId] = nil -- they gave up their pick: the nation is free for the draft and for others
		end
	end
	if index < lobby.turn then
		lobby.turn -= 1
	elseif index == lobby.turn then
		lobby.turnTicksLeft = lobby.turnTicks -- the next player starts a full turn
	end
end

-- One second of lobby time. Returns true when this phase is over: the vote (then call Lobby.startPick) or the
-- draft (then Lobby.finish). During the draft a turn that runs out picks for that player, and when the whole
-- draft time runs out everyone still waiting gets a random nation.
function Lobby.step(lobby: LobbyState, match: MatchState?, rng: Rng.Rng): boolean
	lobby.ticksLeft -= 1
	if lobby.phase == "Lobby" then
		return lobby.ticksLeft <= 0
	end
	if match == nil then
		return true
	end
	local current = Lobby.current(lobby)
	if current then
		lobby.turnTicksLeft -= 1
		if lobby.turnTicksLeft <= 0 then
			autoPick(lobby, match, current, rng)
		end
	end
	if lobby.ticksLeft <= 0 then
		local waiting = Lobby.current(lobby)
		while waiting do
			autoPick(lobby, match, waiting, rng)
			waiting = Lobby.current(lobby)
		end
	end
	return Lobby.current(lobby) == nil
end

-- The draft is over: the match starts at tick 0 (in Peace, unless a private server set no Peace).
function Lobby.finish(match: MatchState)
	match.phase = Match.phaseAt(match.tick, match.setup)
end

local function playerList(names: { [number]: string }): { { userId: number, name: string } }
	local out = {}
	for userId, name in names do
		table.insert(out, { userId = userId, name = name })
	end
	table.sort(out, function(a, b)
		return a.userId < b.userId
	end)
	return out
end

-- The lobby as clients see it. `names` maps userIds to display names (everyone in the server). nil = no lobby (a
-- match is running). `private`: this is a private server (its owner may not be here).
function Lobby.view(lobby: LobbyState?, names: { [number]: string }, private: boolean?): LobbyView
	if lobby == nil then
		return {
			phase = "None",
			ticksLeft = 0,
			maps = {},
			locked = false,
			counts = {},
			votes = {},
			mapId = "",
			order = {},
			turn = 0,
			turnTicksLeft = 0,
			private = private == true,
			owner = 0,
			settings = Settings.defaults(),
			players = {},
			theme = "",
			themeBy = {},
		}
	end
	local tally = Lobby.tally(lobby)
	local counts = {}
	for i, id in lobby.maps do
		counts[i] = tally[id]
	end
	local votes = {}
	for userId, map in lobby.votes do
		table.insert(votes, { userId = userId, map = map })
	end
	table.sort(votes, function(a, b)
		return a.userId < b.userId
	end)
	local themeBy = {}
	for _, userId in lobby.themeBy or {} do
		table.insert(themeBy, names[userId] or "?")
	end
	local order = {}
	for _, userId in lobby.order do
		table.insert(order, { userId = userId, name = names[userId] or "?", nation = lobby.picks[userId] or 0 })
	end
	return {
		phase = lobby.phase,
		ticksLeft = math.max(lobby.ticksLeft, 0),
		maps = table.clone(lobby.maps),
		locked = lobby.locked ~= nil,
		counts = counts,
		votes = votes,
		mapId = lobby.mapId or "",
		order = order,
		turn = lobby.turn,
		turnTicksLeft = math.max(lobby.turnTicksLeft, 0),
		private = private == true or lobby.owner ~= nil,
		owner = lobby.owner or 0,
		settings = Settings.copy(lobby.settings),
		players = playerList(names),
		theme = lobby.theme or "",
		themeBy = themeBy,
	}
end

return Lobby
