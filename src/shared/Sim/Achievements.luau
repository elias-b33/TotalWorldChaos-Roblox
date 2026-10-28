--!strict
-- Achievements (docs/MONETIZATION.md 5.6): 30 one-time goals in Config.Achievements.List, each paying Glory, a title
-- or a cosmetic once. They are checked with every match reward (Results, or leaving early), from what the player did
-- in the match (Progression's stats and the feats `observe` keeps here) and from the profile's lifetime numbers.
-- Progress lives in profile.achievements (id -> value); an achievement is earned the moment its value reaches the
-- target, and pays then. An AFK match counts nothing; a private match with custom rules or too few players counts
-- everything but the win-type stats (like "win" quests). Pure: the services pass in the match, the profile and the
-- stats.

local Catalogue = require("../Catalogue")
local Config = require("../Config")
local Match = require("./Match")
local Types = require("../Types")
local Victory = require("./Victory")

type MatchState = Types.MatchState
type Profile = Types.PlayerProfile
type Stats = Types.PlayerMatchStats
type Def = Types.AchievementDef

local A = Config.Achievements
local LIST: { Def } = A.List :: any
local METEOR = 1 -- index of "Meteor" in Sim.Primordial.POWERS (kept here so this module stays light)
local BOTTOM = 3 -- "Comeback": in the bottom this many at the check

local Achievements = {}

Achievements.LIST = LIST

local byId: { [string]: Def } = {}
for _, def in LIST do
	byId[def.id] = def
end

function Achievements.def(id: string): Def?
	return byId[id]
end

-- Per-tick feats ------------------------------------------------------------------------------------------------

local function userOfNation(state: MatchState, nationId: number): number?
	local nation = state.nations[nationId]
	return if nation then nation.userId else nil
end

-- After Progression.observe, before the events are cleared: count this tick's neutral captures in Peace and Meteor
-- kills, sieges the players' forts held out against, who each player is allied with, and the bottom 3 at 10:00.
function Achievements.observe(state: MatchState, statsByUser: { [number]: Stats })
	for _, e in state.events do
		if e.kind == "ProvinceTaken" and e.b == 0 and state.phase == "Peace" then
			local userId = userOfNation(state, e.a)
			local stats = if userId then statsByUser[userId] else nil
			if stats then
				stats.feats.peaceNeutral += 1
			end
		elseif e.kind == "Power" and e.a == METEOR and e.by and e.men then
			local userId = userOfNation(state, e.by)
			local stats = if userId then statsByUser[userId] else nil
			if stats then
				stats.feats.meteorKills += e.men
			end
		end
	end
	local ranked: { number }? = nil -- the nations still in the match, best score first (worked out once, if needed)
	local function ranking(): { number }
		if ranked == nil then
			local list = {}
			for _, s in Victory.scores(state) do
				if not state.nations[s.nation].eliminated then
					table.insert(list, s.nation)
				end
			end
			ranked = list
		end
		return ranked :: { number }
	end
	for userId, stats in statsByUser do
		local nationId = Match.nationOf(state, userId)
		local nation = if nationId then state.nations[nationId] else nil
		if nationId == nil or nation == nil or nation.eliminated then
			continue
		end
		local feats = stats.feats
		-- forts under siege; a siege that ends with the fort still theirs is one held
		for provinceId in feats.besieged do
			local p = state.provinces[provinceId]
			if p == nil or p.owner ~= nationId then
				feats.besieged[provinceId] = nil
			elseif p.siege == nil then
				feats.besieged[provinceId] = nil
				feats.fortHolds += 1
			end
		end
		for id, p in state.provinces do
			if p.owner == nationId and p.building == "Fort" and p.siege ~= nil then
				feats.besieged[id] = true
			end
		end
		local alliance = if nation.allianceId then state.alliances[nation.allianceId] else nil
		local allies = {}
		for _, member in if alliance then alliance.members else {} do
			if member ~= nationId then
				table.insert(allies, member)
			end
		end
		feats.allies = allies
		if feats.lowAtCheck == nil and state.tick >= A.ComebackTick then
			local list = ranking()
			local place = table.find(list, nationId)
			local lateJoiner = stats.joinedAt > A.ComebackTick and stats.playedTicks == 0 -- wasn't here at 10:00
			feats.lowAtCheck = not lateJoiner and place ~= nil and place > #list - BOTTOM
		end
	end
end

-- Match tally ---------------------------------------------------------------------------------------------------

-- What one match counts for each match stat. standard: Sim.Settings.fullRewards (win-type stats need it). Also
-- returns the map won on (nil if not a counted win).
function Achievements.tally(
	state: MatchState,
	stats: Stats,
	reward: Types.MatchReward,
	standard: boolean
): ({ [string]: number }, string?)
	local finished = reward.stayed and stats.seated and not reward.afk
	-- a placement (top 3, a win) counts only for a player who played enough of the match to own it
	local played = (reward.share or 1) >= Config.Progression.PlacementMinShare
	local place = if finished and played then reward.placement else nil
	local result = state.result
	local won = place == 1 and standard and result ~= nil
	local kind = if result then result.kind else ""
	local primordial = reward.stayed and state.primordials[stats.userId] ~= nil
	local alliesWon = false
	if primordial and standard and result then
		for _, ally in stats.feats.allies do
			alliesWon = alliesWon or table.find(result.winners, ally) ~= nil
		end
	end
	local function flag(on: boolean): number
		return if on then 1 else 0
	end
	local feats = stats.feats
	return {
		Battles = stats.battlesWon,
		PeaceNeutral = feats.peaceNeutral,
		Capitals = stats.capitalsTaken,
		Buildings = stats.buildings,
		Regiments = stats.regiments,
		DevLevel = stats.bestDevelopment,
		Alliances = stats.alliances,
		Held = stats.mostProvinces,
		Powers = stats.powersUsed,
		MeteorKills = feats.meteorKills,
		FortHolds = feats.fortHolds,
		Top3 = flag(place ~= nil and place <= 3),
		Domination = flag(won and kind == "Domination"),
		AllianceWin = flag(won and kind == "Alliance"),
		Comeback = flag(won and feats.lowAtCheck == true),
		Kingmaker = flag(alliesWon),
		Risen = flag(primordial),
	},
		if won then state.mapId else nil
end

-- A lifetime number from the profile.
function Achievements.lifetime(profile: Profile, stat: string): number
	local s = profile.stats
	if stat == "LifeMatches" then
		return s.matches
	elseif stat == "LifeWins" then
		return s.wins
	elseif stat == "LifeCaptures" then
		return s.provincesTaken
	elseif stat == "LifeBattles" then
		return s.battlesWon
	elseif stat == "LifePowers" then
		return s.powersUsed
	elseif stat == "Level" then
		return profile.level
	end
	return 0
end

local function bits(n: number): number
	local count = 0
	while n > 0 do
		count += n % 2
		n //= 2
	end
	return count
end

-- Progress shown for a stored value (Maps keep one bit per map in Config.Achievements.Maps).
function Achievements.progressOf(def: Def, value: number): number
	return math.min(if def.kind == "Maps" then bits(value) else value, def.target)
end

function Achievements.isDone(profile: Profile, id: string): boolean
	local def = byId[id]
	return def ~= nil and Achievements.progressOf(def, profile.achievements[id] or 0) >= def.target
end

-- Move every unfinished achievement with a match's tally (nil tally: only the lifetime ones). counted: what an
-- earlier leave already counted for Sum stats this match. Returns the ids earned now, in list order.
function Achievements.advance(
	profile: Profile,
	tally: { [string]: number }?,
	mapWon: string?,
	counted: { [string]: number }
): { string }
	local earned = {}
	for _, def in LIST do
		local before = profile.achievements[def.id] or 0
		if Achievements.progressOf(def, before) >= def.target then
			continue
		end
		local value = before
		if def.kind == "Lifetime" then
			value = Achievements.lifetime(profile, def.stat)
		elseif tally and def.kind == "Best" then
			value = math.max(before, tally[def.stat] or 0)
		elseif tally and def.kind == "Sum" then
			value = before + math.max(0, (tally[def.stat] or 0) - (counted[def.stat] or 0))
		elseif def.kind == "Maps" and mapWon then
			local index = table.find(A.Maps, mapWon)
			if index then
				local bit = 2 ^ (index - 1)
				value = if (before // bit) % 2 == 1 then before else before + bit
			end
		end
		if def.kind ~= "Maps" then
			value = math.min(value, def.target)
		end
		if value ~= before then
			profile.achievements[def.id] = value
		end
		if Achievements.progressOf(def, value) >= def.target then
			table.insert(earned, def.id)
		end
	end
	return earned
end

-- Pay an earned achievement: its Glory, title and cosmetic. Returns the Glory.
function Achievements.pay(profile: Profile, id: string): number
	local def = byId[id]
	if def == nil then
		return 0
	end
	profile.glory += def.glory
	if def.title then
		profile.owned[def.title] = true
	end
	if def.item then
		profile.owned[def.item] = true
	end
	return def.glory
end

-- A match is over for this player (Results, or leaving early): count it, pay what it earned. Returns the ids earned
-- and the Glory paid. An AFK match counts nothing. What an earlier leave already counted comes off.
function Achievements.check(
	state: MatchState,
	profile: Profile,
	stats: Stats,
	reward: Types.MatchReward,
	standard: boolean
): ({ string }, number)
	if reward.afk then
		return {}, 0
	end
	local tally, mapWon = Achievements.tally(state, stats, reward, standard)
	local earned = Achievements.advance(profile, tally, mapWon, stats.feats.counted)
	stats.feats.counted = tally
	local glory = 0
	for _, id in earned do
		glory += Achievements.pay(profile, id)
	end
	return earned, glory
end

-- What the player's client is shown. recent: ids the last match earned.
function Achievements.view(profile: Profile, equippedTitle: string, recent: { string }?): Types.AchievementView
	local list = {}
	for _, def in LIST do
		local progress = Achievements.progressOf(def, profile.achievements[def.id] or 0)
		table.insert(list, {
			id = def.id,
			name = def.name,
			stat = def.stat,
			target = def.target,
			progress = progress,
			done = progress >= def.target,
			glory = def.glory,
			title = def.title,
			item = def.item,
		})
	end
	local titles = {} -- every title the player owns (achievements', the season pass's), in catalogue order
	for _, item in Catalogue.ITEMS do
		if item.slot == "Title" and item.id ~= Catalogue.DEFAULTS.Title and profile.owned[item.id] then
			table.insert(titles, item.id)
		end
	end
	return { list = list, titles = titles, title = equippedTitle, recent = recent or {} }
end

return Achievements
