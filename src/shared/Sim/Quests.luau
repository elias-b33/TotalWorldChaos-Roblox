--!strict
-- Daily and weekly quests (docs/MONETIZATION.md 5.4–5.5): 3 daily quests (one easy, one medium, one hard) from
-- 00:00 UTC and 3 weekly ones from Monday 00:00 UTC, picked from Config.Progression.Quests.Pool by a generator
-- seeded with the player and the day or week, so the same player always gets the same quests on the same day.
-- Unfinished daily quests stay for 2 days (6 at most); a finished quest stays until it is claimed. Progress comes
-- from the match stats at Results (or when a player leaves), claiming pays XP and Glory, and a daily quest can be
-- rerolled: free ones first (1 a day, +1 VIP, +2 from the rewarded video in Phase 5), then for Glory.
-- Pure: the services pass in the profile, the UTC day, VIP and the Rng.

local Config = require("../Config")
local Login = require("./Login")
local Progression = require("./Progression")
local Rng = require("./Rng")
local Types = require("../Types")

type Profile = Types.PlayerProfile
type Book = Types.QuestBook
type Quest = Types.QuestState
type Def = Types.QuestDef
type Rng = Rng.Rng

local Q = Config.Progression.Quests
local POOL: { Def } = Q.Pool :: any
local DAILY_TIERS: { Types.QuestTier } = { "Easy", "Medium", "Hard" }
local DAILY_SALT = 1
local WEEKLY_SALT = 2
local REROLL_SALT = 3
local WARM_UP = 4 -- numbers thrown away after seeding

local Quests = {}

local byId: { [string]: Def } = {}
for _, def in POOL do
	byId[def.id] = def
end

function Quests.def(id: string): Def?
	return byId[id]
end

local function ofTier(tier: Types.QuestTier): { Def }
	local out = {}
	for _, def in POOL do
		if def.tier == tier then
			table.insert(out, def)
		end
	end
	return out
end

-- The week (Monday to Sunday, UTC) a UTC day number is in.
Quests.weekOf = Login.weekOf

-- 32-bit FNV-1a over the numbers, so neighbouring players and days get unrelated seeds.
local function hash(values: { number }): number
	local h = 2166136261
	for _, v in values do
		local n = math.floor(v) % 4294967296
		for _ = 1, 4 do
			h = bit32.bxor(h, n % 256)
			h = (bit32.lshift(h, 24) + h * 403) % 4294967296 -- h × 16777619, mod 2^32
			n = n // 256
		end
	end
	return h
end

-- A seeded Rng for one player and one period (day or week). salt keeps dailies, weeklies and rerolls apart.
function Quests.rngFor(userId: number, period: number, salt: number, extra: number?): Rng
	local rng = Rng.new(hash({ userId, period, salt, extra or 0 }))
	for _ = 1, WARM_UP do
		Rng.next(rng)
	end
	return rng
end

local function newQuest(def: Def, period: number, prefix: string): Quest
	return {
		key = string.format("%s%d-%s", prefix, period, def.id),
		id = def.id,
		day = period,
		progress = 0,
		claimed = false,
	}
end

-- Pick `count` different quests from `defs`, skipping ids in `taken`.
local function pick(defs: { Def }, count: number, rng: Rng, taken: { [string]: boolean }): { Def }
	local left = {}
	for _, def in defs do
		if not taken[def.id] then
			table.insert(left, def)
		end
	end
	local out = {}
	while #out < count and #left > 0 do
		table.insert(out, table.remove(left, Rng.int(rng, 1, #left)) :: Def)
	end
	return out
end

-- The day's 3 daily quests: one easy, one medium, one hard.
function Quests.dailyFor(_userId: number, day: number, rng: Rng): { Quest }
	local out = {}
	for _, tier in DAILY_TIERS do
		for _, def in pick(ofTier(tier), 1, rng, {}) do
			table.insert(out, newQuest(def, day, "d"))
		end
	end
	return out
end

-- The week's weekly quests (Config.Progression.Quests.WeeklyCount, all different).
function Quests.weeklyFor(_userId: number, week: number, rng: Rng): { Quest }
	local out = {}
	for _, def in pick(ofTier("Weekly"), Q.WeeklyCount, rng, {}) do
		table.insert(out, newQuest(def, week, "w"))
	end
	return out
end

function Quests.isDone(quest: Quest): boolean
	local def = byId[quest.id]
	return def ~= nil and quest.progress >= def.target
end

-- Bring the book up to `today`: a new day drops claimed and expired daily quests and adds the day's three (the
-- oldest unfinished go first past Config MaxWaiting), and resets the rerolls; a new week replaces the weekly
-- quests. Finished quests nobody claimed yet always stay. Same player and day: the same quests.
function Quests.refresh(book: Book, userId: number, today: number)
	if book.day ~= today then
		local kept: { Quest } = {}
		for _, quest in book.daily do
			local known = byId[quest.id] ~= nil
			local fresh = quest.day + Q.DailyKeepDays - 1 >= today
			if known and not quest.claimed and (Quests.isDone(quest) or fresh) then
				table.insert(kept, quest)
			end
		end
		for _, quest in Quests.dailyFor(userId, today, Quests.rngFor(userId, today, DAILY_SALT)) do
			table.insert(kept, quest)
		end
		-- too many waiting: drop the oldest unfinished ones
		local unfinished = 0
		for _, quest in kept do
			unfinished += if Quests.isDone(quest) then 0 else 1
		end
		local i = 1
		while unfinished > Q.MaxWaiting and i <= #kept do
			if not Quests.isDone(kept[i]) then
				table.remove(kept, i)
				unfinished -= 1
			else
				i += 1
			end
		end
		book.daily = kept
		book.day = today
		book.rerollsUsed = 0
		book.videoRerolls = 0
	end
	local week = Quests.weekOf(today)
	if book.week ~= week then
		local kept: { Quest } = {}
		for _, quest in book.weekly do
			if byId[quest.id] ~= nil and not quest.claimed and Quests.isDone(quest) then
				table.insert(kept, quest)
			end
		end
		for _, quest in Quests.weeklyFor(userId, week, Quests.rngFor(userId, week, WEEKLY_SALT)) do
			table.insert(kept, quest)
		end
		book.weekly = kept
		book.week = week
	end
end

-- What one match counts for each quest stat. reward: the match reward (placement, stayed, AFK).
function Quests.tally(stats: Types.PlayerMatchStats, reward: Types.MatchReward): { [string]: number }
	local place = if reward.stayed then reward.placement else nil
	local finished = reward.stayed and stats.seated and not reward.afk
	return {
		Matches = if finished then 1 else 0,
		NeutralCaptures = stats.neutralTaken,
		Captures = stats.provincesTaken,
		Regiments = stats.regiments,
		Buildings = stats.buildings,
		Developments = stats.developed,
		DevLevel = stats.bestDevelopment,
		Battles = stats.battlesWon,
		Alliances = stats.alliances,
		Top5 = if place and place <= 5 then 1 else 0,
		Top3 = if place and place <= 3 then 1 else 0,
		Wins = if place == 1 then 1 else 0,
		Capitals = stats.capitalsTaken,
		Held = stats.mostProvinces,
		Powers = stats.powersUsed,
	}
end

-- Add a match's tally to one quest (capped at its target). Returns the progress added.
function Quests.progress(quest: Quest, tally: { [string]: number }, counted: { [string]: number }): number
	local def = byId[quest.id]
	if def == nil or quest.claimed or quest.progress >= def.target then
		return 0
	end
	local value = tally[def.stat] or 0
	local new = if def.max then math.max(quest.progress, value) else quest.progress + value - (counted[def.stat] or 0)
	new = math.clamp(new, quest.progress, def.target)
	local gained = new - quest.progress
	quest.progress = new
	return gained
end

-- A match is over for this player (Results, or leaving early): count it for every quest. AFK counts nothing.
-- What an earlier leave already counted comes off, so leaving and rejoining counts once. Returns the progress
-- each quest gained, by key.
function Quests.applyMatch(book: Book, stats: Types.PlayerMatchStats, reward: Types.MatchReward): { [string]: number }
	local gains: { [string]: number } = {}
	if reward.afk then
		return gains
	end
	local tally = Quests.tally(stats, reward)
	for _, list in { book.daily, book.weekly } do
		for _, quest in list do
			local gained = Quests.progress(quest, tally, stats.questCounted)
			if gained > 0 then
				gains[quest.key] = gained
			end
		end
	end
	stats.questCounted = tally
	return gains
end

local function find(book: Book, key: string): (Quest?, boolean)
	for _, quest in book.daily do
		if quest.key == key then
			return quest, true
		end
	end
	for _, quest in book.weekly do
		if quest.key == key then
			return quest, false
		end
	end
	return nil, false
end

function Quests.reward(def: Def): (number, number)
	local r = Q.Rewards[def.tier]
	return r.xp, r.glory
end

-- Claim a finished quest: its XP and Glory (and any level-up). Returns ok, or false and a reason: Unknown,
-- Claimed, NotDone.
function Quests.claim(profile: Profile, key: string): (boolean, string?)
	local quest = find(profile.quests, key)
	local def = if quest then byId[quest.id] else nil
	if quest == nil or def == nil then
		return false, "Unknown"
	end
	if quest.claimed then
		return false, "Claimed"
	end
	if quest.progress < def.target then
		return false, "NotDone"
	end
	quest.claimed = true
	local xp, glory = Quests.reward(def)
	Progression.addXp(profile, xp, glory)
	return true, nil
end

-- Free rerolls left today.
function Quests.freeRerolls(book: Book, vip: boolean): number
	local allowed = Q.FreeRerolls + (if vip then Config.Shop.VipQuestRerolls else 0) + book.videoRerolls
	return math.max(0, allowed - book.rerollsUsed)
end

-- Phase 5 hook: the rewarded video on the Quests screen gives one more free reroll today (up to
-- Config VideoRerolls). Returns false once today's are used up.
function Quests.grantVideoReroll(book: Book): boolean
	if book.videoRerolls >= Q.VideoRerolls then
		return false
	end
	book.videoRerolls += 1
	return true
end

-- Swap an unfinished daily quest for another of the same tier that isn't in the list. Free rerolls first, then
-- Config RerollGlory each. The Rng comes from Quests.rerollRng. Returns ok, or false and a reason: Unknown,
-- NotDaily, Done, NotEnoughGlory, NoOther.
function Quests.reroll(profile: Profile, key: string, vip: boolean, rng: Rng): (boolean, string?)
	local book = profile.quests
	local quest, daily = find(book, key)
	local def = if quest then byId[quest.id] else nil
	if quest == nil or def == nil then
		return false, "Unknown"
	end
	if not daily then
		return false, "NotDaily"
	end
	if quest.claimed or Quests.isDone(quest) then
		return false, "Done"
	end
	local free = Quests.freeRerolls(book, vip) > 0
	if not free and profile.glory < Q.RerollGlory then
		return false, "NotEnoughGlory"
	end
	local taken: { [string]: boolean } = {}
	for _, q in book.daily do
		taken[q.id] = true
	end
	local other = pick(ofTier(def.tier), 1, rng, taken)[1]
	if other == nil then
		return false, "NoOther"
	end
	if not free then
		profile.glory -= Q.RerollGlory
	end
	book.rerollsUsed += 1
	local index = table.find(book.daily, quest) :: number
	book.daily[index] = newQuest(other, quest.day, "d")
	return true, nil
end

-- The Rng for a player's next reroll today (seeded, so a replay gives the same quest).
function Quests.rerollRng(book: Book, userId: number): Rng
	return Quests.rngFor(userId, book.day, REROLL_SALT, book.rerollsUsed)
end

local function entry(quest: Quest, today: number, daily: boolean): Types.QuestEntry?
	local def = byId[quest.id]
	if def == nil then
		return nil
	end
	local xp, glory = Quests.reward(def)
	return {
		key = quest.key,
		id = quest.id,
		tier = def.tier,
		stat = def.stat,
		target = def.target,
		progress = quest.progress,
		claimed = quest.claimed,
		xp = xp,
		glory = glory,
		daysLeft = if daily then math.max(0, quest.day + Q.DailyKeepDays - 1 - today) else 0,
	}
end

-- What the player's client is shown: the quests, rerolls, the login calendar and the streak. gains: what the last
-- match added to each quest, for the Results screen.
function Quests.view(profile: Profile, today: number, vip: boolean, gains: { [string]: number }?): Types.QuestView
	local book = profile.quests
	local daily, weekly = {}, {}
	for _, quest in book.daily do
		local e = entry(quest, today, true)
		if e then
			table.insert(daily, e)
		end
	end
	for _, quest in book.weekly do
		local e = entry(quest, today, false)
		if e then
			table.insert(weekly, e)
		end
	end
	local view: Types.QuestView = {
		daily = daily,
		weekly = weekly,
		freeRerolls = Quests.freeRerolls(book, vip),
		rerollGlory = Q.RerollGlory,
		calendar = { glory = {}, step = 0, playedToday = false },
		streak = 0,
		best = 0,
		flame = 0,
		gains = gains or {},
	}
	Login.fillView(view, profile.login, today)
	return view
end

return Quests
