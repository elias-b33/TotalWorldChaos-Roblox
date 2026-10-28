--!strict
-- Account progression (docs/MONETIZATION.md 4.1, 5.1–5.3): what a match pays each player in XP and Glory, the
-- level curve and ranks, and the saved profile's shape. Pure: the services pass in the match, the player's stats,
-- whether they are VIP and the UTC day, so Sim never reads the clock or the network.

local Config = require("../Config")
local Match = require("./Match")
local Types = require("../Types")

type MatchState = Types.MatchState
type MatchReward = Types.MatchReward
type Profile = Types.PlayerProfile
type Stats = Types.PlayerMatchStats

export type RewardOptions = {
	vip: boolean,
	firstMatchToday: boolean, -- no paid match yet on this UTC day
	standardRules: boolean, -- false on a private server with custom rules
}

local P = Config.Progression

local Progression = {}

Progression.PROFILE_VERSION = 3

-- Level curve and ranks ---------------------------------------------------------------------------------

-- XP from `level` to the next one (0 at the cap).
function Progression.xpToNext(level: number): number
	if level >= P.MaxLevel then
		return 0
	end
	return P.LevelBaseXp + P.LevelStepXp * (level - 1)
end

-- Total XP needed to reach `level`.
function Progression.totalXpFor(level: number): number
	local n = math.clamp(level, 1, P.MaxLevel) - 1
	return P.LevelBaseXp * n + P.LevelStepXp * n * (n - 1) / 2
end

function Progression.levelFor(totalXp: number): number
	local level = 1
	while level < P.MaxLevel and totalXp >= Progression.totalXpFor(level + 1) do
		level += 1
	end
	return level
end

-- Rank index (1 = Settler) and name. One rank per 10 levels; level 100 is the last rank.
function Progression.rankFor(level: number): (number, string)
	local rank = math.clamp(level // P.LevelsPerRank + 1, 1, #P.Ranks)
	return rank, P.Ranks[rank]
end

function Progression.summary(profile: Profile): Types.ProfileSummary
	local rank, rankName = Progression.rankFor(profile.level)
	return {
		level = profile.level,
		xp = profile.xp,
		xpIntoLevel = profile.xp - Progression.totalXpFor(profile.level),
		xpForLevel = Progression.xpToNext(profile.level),
		glory = profile.glory,
		rank = rank,
		rankName = rankName,
	}
end

-- Match stats -------------------------------------------------------------------------------------------

function Progression.newStats(userId: number, tick: number): Stats
	return {
		userId = userId,
		joinedAt = tick,
		leftAt = nil,
		playedTicks = 0,
		seated = false,
		lastCommandAt = tick,
		longestIdle = 0,
		provincesTaken = 0,
		battlesWon = 0,
		powersUsed = 0,
		paidXp = 0,
		paidGlory = 0,
		neutralTaken = 0,
		capitalsTaken = 0,
		regiments = 0,
		buildings = 0,
		developed = 0,
		bestDevelopment = 0,
		alliances = 0,
		mostProvinces = 0,
		questCounted = {},
	}
end

local function closeIdle(stats: Stats, tick: number)
	stats.longestIdle = math.max(stats.longestIdle, tick - stats.lastCommandAt)
end

-- The player sent a command (any command counts against AFK; only a successful power counts as used). With the
-- match state (after the command), carried-out orders count for quests too.
function Progression.recordCommand(stats: Stats, tick: number, command: Types.Command, ok: boolean, state: MatchState?)
	closeIdle(stats, tick)
	stats.lastCommandAt = tick
	if not ok then
		return
	end
	if command.kind == "Power" then
		stats.powersUsed += 1
	elseif command.kind == "Recruit" then
		stats.regiments += command.regiments
	elseif command.kind == "Build" then
		stats.buildings += 1
	elseif command.kind == "Develop" then
		stats.developed += 1
		local province = if state then state.provinces[command.province] else nil
		if province then
			stats.bestDevelopment = math.max(stats.bestDevelopment, province.development)
		end
	end
end

local function seatedNow(state: MatchState, userId: number): boolean
	return Match.nationOf(state, userId) ~= nil or state.primordials[userId] ~= nil
end

local function statsOfNation(state: MatchState, statsByUser: { [number]: Stats }, nationId: number): Stats?
	local nation = state.nations[nationId]
	local userId = if nation then nation.userId else nil
	return if userId then statsByUser[userId] else nil
end

-- Count this tick's captures, battle wins and alliances for the players whose nations made them, the most
-- provinces each has held, and note who has a nation or a Primordial. Call before the events are cleared.
function Progression.observe(state: MatchState, statsByUser: { [number]: Stats })
	for userId, stats in statsByUser do
		if not stats.seated and stats.leftAt == nil and seatedNow(state, userId) then
			stats.seated = true
		end
	end
	for _, e in state.events do
		local stats = if e.kind == "ProvinceTaken"
				or e.kind == "BattleEnded"
				or e.kind == "AllianceFormed"
			then statsOfNation(state, statsByUser, e.a)
			else nil
		if stats and e.kind == "ProvinceTaken" then
			stats.provincesTaken += 1
			local province = state.provinces[e.province]
			if e.b == 0 then
				stats.neutralTaken += 1
			elseif province and province.isCapital then
				stats.capitalsTaken += 1
			end
		elseif stats and e.kind == "BattleEnded" then
			stats.battlesWon += 1
		elseif stats then
			stats.alliances += 1
		end
		if e.kind == "AllianceFormed" then
			local other = statsOfNation(state, statsByUser, e.b)
			if other then
				other.alliances += 1
			end
		end
	end
	local held: { [number]: number } = {}
	for _, p in state.provinces do
		if p.owner then
			held[p.owner] = (held[p.owner] or 0) + 1
		end
	end
	for nationId, count in held do
		local stats = statsOfNation(state, statsByUser, nationId)
		if stats and count > stats.mostProvinces then
			stats.mostProvinces = count
		end
	end
end

-- The player left before Results.
function Progression.leave(stats: Stats, tick: number)
	closeIdle(stats, tick)
	stats.leftAt = tick
end

-- The player came back to the same match: the record carries on, so caps and the finish share count once.
function Progression.rejoin(stats: Stats, tick: number)
	local leftAt = stats.leftAt
	if leftAt then
		stats.playedTicks += leftAt - stats.joinedAt
		stats.leftAt = nil
	end
	stats.joinedAt = tick
	stats.lastCommandAt = tick -- time away isn't idle time
end

-- Rewards -----------------------------------------------------------------------------------------------

-- Finishing place: every winner is 1st (an alliance victory makes all members 1st); the others follow by score,
-- and equal scores share a place.
function Progression.placement(result: Types.MatchResult, nationId: number): number
	if table.find(result.winners, nationId) then
		return 1
	end
	local mine = 0
	for _, s in result.scores do
		if s.nation == nationId then
			mine = s.score
		end
	end
	local better = 0
	for _, s in result.scores do
		if s.score > mine and not table.find(result.winners, s.nation) then
			better += 1
		end
	end
	return #result.winners + better + 1
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

local function add(reward: MatchReward, kind: string, xp: number, glory: number)
	if xp ~= 0 or glory ~= 0 then
		table.insert(reward.lines, { kind = kind, xp = xp, glory = glory })
		reward.xp += xp
		reward.glory += glory
	end
end

-- Add a row to a reward breakdown (and its totals). Nothing for a row of zeros.
Progression.addLine = add

-- What the match pays one player. Call at Results for everyone still here, or when a player leaves early.
-- Whatever an earlier leave already paid this match comes off the total, so leaving and rejoining pays the
-- caps once. Finish and the first-match bonus need a nation or a Primordial at some point (no spectators).
function Progression.matchReward(state: MatchState, stats: Stats, options: RewardOptions): MatchReward
	local result = state.result
	local stayed = result ~= nil and stats.leftAt == nil
	local endTick = stats.leftAt or (if result then result.endedAt else state.tick)
	local idle = math.max(stats.longestIdle, endTick - stats.lastCommandAt)
	local reward: MatchReward = { xp = 0, glory = 0, lines = {}, placement = nil, stayed = stayed, afk = false }
	if idle >= P.AfkTicks then
		reward.afk = true
		return reward
	end

	-- the part of the match they played (a full match ends at 25:00; the first minute counts as the start)
	local matchTicks = if stayed and result then result.endedAt else Config.Phases.MatchEndTick
	local played = stats.playedTicks + endTick - stats.joinedAt
	local share = math.clamp(played / math.max(1, matchTicks - P.LateJoinGraceTicks), 0, 1)
	local seated = stats.seated or seatedNow(state, stats.userId)
	if seated then
		add(reward, "Finish", round(P.FinishXp * share), round(P.FinishGlory * share))
	end
	local nationId = Match.nationOf(state, stats.userId)
	if stayed and result and nationId then
		local place = Progression.placement(result, nationId)
		local row = math.min(place, #P.PlacementXp)
		reward.placement = place
		add(reward, "Placement", round(P.PlacementXp[row] * share), round(P.PlacementGlory[row] * share))
	end

	local provinceGlory = math.min(stats.provincesTaken * P.ActivityGlory, P.MaxActivityGlory)
	local battleGlory = math.min(stats.battlesWon * P.ActivityGlory, P.MaxActivityGlory - provinceGlory)
	add(reward, "Provinces", math.min(stats.provincesTaken * P.ProvinceXp, P.MaxProvinceXp), provinceGlory)
	add(reward, "Battles", math.min(stats.battlesWon * P.BattleXp, P.MaxBattleXp), battleGlory)
	if stayed and state.primordials[stats.userId] ~= nil then
		add(reward, "Primordial", P.PrimordialXp, P.PrimordialGlory)
	end
	add(reward, "Powers", math.min(stats.powersUsed * P.PowerXp, P.MaxPowerXp), 0)

	if options.vip then
		add(reward, "Vip", round(reward.xp * P.VipBonus), round(reward.glory * P.VipBonus))
	end
	if stayed and seated and options.firstMatchToday then
		add(reward, "FirstMatch", P.FirstMatchXp, P.FirstMatchGlory)
	end
	if not options.standardRules then
		add(
			reward,
			"CustomRules",
			round(reward.xp * P.CustomRulesShare) - reward.xp,
			round(reward.glory * P.CustomRulesShare) - reward.glory
		)
	end
	add(reward, "PaidEarlier", -math.min(stats.paidXp, reward.xp), -math.min(stats.paidGlory, reward.glory))
	return reward
end

-- Profiles ----------------------------------------------------------------------------------------------

function Progression.newProfile(): Profile
	return {
		version = Progression.PROFILE_VERSION,
		xp = 0,
		level = 1,
		glory = 0,
		lastMatchDay = -1,
		owned = {},
		equipped = {},
		quests = { day = -1, week = -1, rerollsUsed = 0, videoRerolls = 0, daily = {}, weekly = {} },
		login = { step = 0, lastPlayDay = -1, streak = 0, best = 0, coveredWeek = -1 },
		achievements = {},
		season = { id = "", xp = 0, premium = false, claimed = {} },
		receipts = {},
		purchaseHistory = {},
		stats = { matches = 0, wins = 0, provincesTaken = 0, battlesWon = 0, powersUsed = 0 },
		settings = {},
		tutorialDone = false,
	}
end

-- Upgrades from one profile version to the next, keyed by the version they upgrade from.
local MIGRATIONS: { [number]: (Profile) -> () } = {
	-- 2 adds tutorialDone: someone who has already played a match never gets sent to the tutorial
	[1] = function(profile: Profile)
		profile.tutorialDone = profile.tutorialDone == true or profile.stats.matches > 0
	end,
	-- 3 fills in the quest book and the login calendar (placeholders until then, never used)
	[2] = function(profile: Profile)
		profile.quests = { day = -1, week = -1, rerollsUsed = 0, videoRerolls = 0, daily = {}, weekly = {} }
		profile.login = { step = 0, lastPlayDay = -1, streak = 0, best = 0, coveredWeek = -1 }
	end,
}

-- Bring a loaded profile up to date (missing fields are filled from newProfile by ProfileStore's Reconcile first).
function Progression.migrate(profile: Profile)
	while MIGRATIONS[profile.version] do
		MIGRATIONS[profile.version](profile)
		profile.version += 1
	end
	profile.level = Progression.levelFor(profile.xp)
end

-- Is this the player's first paid match on this UTC day?
function Progression.isFirstMatchToday(profile: Profile, today: number): boolean
	return profile.lastMatchDay ~= today
end

-- Add XP and Glory to a profile, with the level-ups (50 Glory each) and rank-ups (+500 Glory each) they bring.
-- Returns the level-up and rank-up Glory (already added).
function Progression.addXp(profile: Profile, xp: number, glory: number): (number, number)
	profile.xp += xp
	profile.glory += glory
	local newLevel = Progression.levelFor(profile.xp)
	if newLevel <= profile.level then
		return 0, 0
	end
	local rankBefore = Progression.rankFor(profile.level)
	local rankAfter = Progression.rankFor(newLevel)
	local levelGlory = (newLevel - profile.level) * P.LevelUpGlory
	local rankGlory = (rankAfter - rankBefore) * P.RankUpGlory
	profile.glory += levelGlory + rankGlory
	profile.level = newLevel
	return levelGlory, rankGlory
end

-- Apply a match reward to a profile: XP, Glory, levels (50 Glory each) and ranks (+500 Glory each), and the
-- lifetime stats. Returns the report for the Results screen, with the level-up and rank-up lines added.
function Progression.grant(profile: Profile, stats: Stats, reward: MatchReward, today: number): Types.RewardReport
	local before = Progression.summary(profile)
	local full: MatchReward = table.clone(reward)
	full.lines = table.clone(reward.lines)
	stats.paidXp += reward.xp
	stats.paidGlory += reward.glory
	local levelGlory, rankGlory = Progression.addXp(profile, reward.xp, reward.glory)
	add(full, "LevelUp", 0, levelGlory)
	add(full, "RankUp", 0, rankGlory)
	if reward.stayed and not reward.afk then
		profile.lastMatchDay = today
	end
	local lifetime = profile.stats
	if reward.stayed then
		lifetime.matches += 1
		if reward.placement == 1 then
			lifetime.wins += 1
		end
	end
	lifetime.provincesTaken += stats.provincesTaken
	lifetime.battlesWon += stats.battlesWon
	lifetime.powersUsed += stats.powersUsed
	return { reward = full, before = before, after = Progression.summary(profile) }
end

return Progression
