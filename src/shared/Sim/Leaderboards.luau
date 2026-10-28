--!strict
-- Leaderboards (docs/MONETIZATION.md 7.3): weekly conquest points (1st 10, 2nd 7, 3rd 5, 4th–5th 3, 6th–10th 1) from
-- public matches with 4+ real players, reset every Monday 00:00 UTC (one board per week); the friends view of the
-- weekly board; the global level board (account XP); and the Warlord frame for last week's top 100. Pure: the service
-- reads and writes the OrderedDataStores and passes in what it read, the week and the profile.

local Config = require("../Config")
local Progression = require("./Progression")
local Settings = require("./Settings")
local Types = require("../Types")

type Profile = Types.PlayerProfile
type BoardRow = Types.BoardRow

-- One board entry as read from an OrderedDataStore (the key is the userId).
export type Entry = { userId: number, value: number }

local L = Config.Leaderboards
local WARLORD = "frame_warlord"

local Leaderboards = {}

Leaderboards.WARLORD = WARLORD

-- Does this match give weekly points? Public servers only (never a private server, whatever its rules), with
-- Config.Leaderboards.MinHumans real players (who held a nation).
function Leaderboards.counts(state: Types.MatchState): boolean
	return not state.setup.private and Settings.humans(state) >= L.MinHumans
end

-- The points a finished match gives a player: by placement, for staying to Results with a nation, never AFK, and
-- having played at least Config.Progression.PlacementMinShare of the match.
function Leaderboards.points(reward: Types.MatchReward): number
	if reward.afk or not reward.stayed or reward.placement == nil then
		return 0
	end
	if (reward.share or 1) < Config.Progression.PlacementMinShare then
		return 0 -- joined too late for the placement to be theirs
	end
	return L.Points[reward.placement] or 0
end

-- The DataStore scope of a week's board ("W2857").
function Leaderboards.weekKey(week: number): string
	return "W" .. tostring(week)
end

-- Entries best first (ties: lower userId first, so every server shows the same order).
function Leaderboards.sorted(entries: { Entry }): { Entry }
	local out = table.clone(entries)
	table.sort(out, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.userId < b.userId
	end)
	return out
end

-- Put what this server knows to be newer (players here: their own totals) over what was read.
function Leaderboards.merge(entries: { Entry }, known: { [number]: number }): { Entry }
	local out: { Entry } = {}
	local seen: { [number]: boolean } = {}
	for _, e in entries do
		local value = known[e.userId] or e.value
		table.insert(out, { userId = e.userId, value = math.max(value, e.value) })
		seen[e.userId] = true
	end
	for userId, value in known do
		if not seen[userId] and value > 0 then
			table.insert(out, { userId = userId, value = value })
		end
	end
	return Leaderboards.sorted(out)
end

-- The friends view: you and your friends among the weekly entries (read, merged with what this server knows).
-- You are always on it, with 0 points before your first counted match.
function Leaderboards.friends(weekly: { Entry }, friendIds: { number }, me: number): { Entry }
	local wanted: { [number]: boolean } = { [me] = true }
	for _, id in friendIds do
		wanted[id] = true
	end
	local out = {}
	local found = false
	for _, e in weekly do
		if wanted[e.userId] then
			table.insert(out, e)
			found = found or e.userId == me
		end
	end
	if not found then
		table.insert(out, { userId = me, value = 0 })
	end
	return Leaderboards.sorted(out)
end

-- Rank of a user among sorted entries (equal values share a rank), or 0 if absent.
function Leaderboards.rank(entries: { Entry }, userId: number): number
	local rank, lastValue = 0, nil
	for i, e in entries do
		if e.value ~= lastValue then
			rank, lastValue = i, e.value
		end
		if e.userId == userId then
			return rank
		end
	end
	return 0
end

-- Rows for a client: rank, display name and value, the first Config ShownRows. withLevel: the value is account XP
-- (the global level board), so each row also shows the level. Names come from `nameOf` (display names only).
function Leaderboards.rows(
	entries: { Entry },
	me: number,
	nameOf: (number) -> string,
	withLevel: boolean?
): { BoardRow }
	local out = {}
	for i, e in entries do
		if i > L.ShownRows then
			break
		end
		table.insert(out, {
			rank = Leaderboards.rank(entries, e.userId),
			name = nameOf(e.userId),
			value = e.value,
			me = e.userId == me,
			level = if withLevel then Progression.levelFor(e.value) else nil,
		})
	end
	return out
end

-- The user ids of a week's top Config.Leaderboards.WarlordTop (entries sorted best first).
function Leaderboards.top(entries: { Entry }): { number }
	local out = {}
	for i, e in entries do
		if i > L.WarlordTop or e.value <= 0 then
			break
		end
		table.insert(out, e.userId)
	end
	return out
end

-- What the Warlord frame should be this week: owned (and for which week) while the player was in last week's top
-- (`lastTop`); kept for the week it was given in; gone once a new week starts and they weren't.
local function warlordFor(profile: Profile, userId: number, week: number, lastTop: { number }): (boolean, number?)
	if table.find(lastTop, userId) then
		return true, week
	elseif profile.settings.warlordWeek == week then
		return profile.owned[WARLORD] == true, week
	end
	return false, nil
end

-- Would refreshWarlord change the profile? (So the service saves only when it must.) nil lastTop: no.
function Leaderboards.warlordDue(profile: Profile, userId: number, week: number, lastTop: { number }?): boolean
	if lastTop == nil then
		return false
	end
	local owned, grantedFor = warlordFor(profile, userId, week, lastTop)
	return owned ~= (profile.owned[WARLORD] == true) or grantedFor ~= profile.settings.warlordWeek
end

-- Give or take the Warlord frame for this week from last week's top (`lastTop`, nil when it couldn't be read:
-- nothing changes then). Returns true if the player's frame changed.
function Leaderboards.refreshWarlord(profile: Profile, userId: number, week: number, lastTop: { number }?): boolean
	if lastTop == nil then
		return false
	end
	local had = profile.owned[WARLORD] == true
	local owned, grantedFor = warlordFor(profile, userId, week, lastTop)
	profile.owned[WARLORD] = if owned then true else nil
	profile.settings.warlordWeek = grantedFor
	return had ~= owned
end

return Leaderboards
