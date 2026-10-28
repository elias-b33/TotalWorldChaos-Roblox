--!strict
-- Login calendar and play streak (docs/MONETIZATION.md 5.6). Both move on a "play day": a UTC day with a finished
-- match (stayed to Results, not AFK).
--   Calendar: a 7-step cycle, one step per play day, paying Config.Progression.Login.CalendarGlory. Missing days
--   pause it and never reset it.
--   Streak: consecutive play days; one missed day a week is covered. Its rewards are cosmetic (nameplate flames and
--   a title) and stay earned when the streak breaks: they follow the best streak.
-- Pure: the services pass in the UTC day.

local Config = require("../Config")
local Types = require("../Types")

type Login = Types.LoginState

local L = Config.Progression.Login

local Login = {}

-- The week (Monday to Sunday, UTC) a UTC day number is in. Day 0 (1 January 1970) was a Thursday.
function Login.weekOf(day: number): number
	return (day + 3) // 7
end
local weekOf = Login.weekOf

-- Would a play on `today` carry the streak on? (The day after the last play day, or one day later if this
-- week's covered missed day is still free.)
local function continues(login: Login, today: number): boolean
	if login.lastPlayDay < 0 then
		return false
	end
	local gap = today - login.lastPlayDay
	if gap == 1 then
		return true
	end
	return gap == 2 and L.CoveredMissesPerWeek > 0 and login.coveredWeek ~= weekOf(today - 1)
end

-- A finished match on `today`. The first one of a play day moves the calendar a step and the streak a day.
-- Returns the Glory the calendar step pays (0 if today was already a play day); the caller adds it.
function Login.recordPlay(login: Login, today: number): number
	if login.lastPlayDay == today then
		return 0
	end
	if continues(login, today) then
		if today - login.lastPlayDay == 2 then
			login.coveredWeek = weekOf(today - 1) -- the missed day is covered
		end
		login.streak += 1
	else
		login.streak = 1
	end
	login.best = math.max(login.best, login.streak)
	login.lastPlayDay = today
	login.step = login.step % #L.CalendarGlory + 1
	return L.CalendarGlory[login.step]
end

-- The streak as it stands today: 0 once it has lapsed (shown that way; the record changes on the next play day).
function Login.currentStreak(login: Login, today: number): number
	if login.lastPlayDay == today or continues(login, today) then
		return login.streak
	end
	return 0
end

-- The streak reward tier a streak of `days` has earned: 0 none, 1 a flame, 2 a bigger flame, 3 a blue flame,
-- 4 the title "the Unyielding".
function Login.tierFor(days: number): number
	local tier = 0
	for i, need in L.StreakFlames do
		if days >= need then
			tier = i
		end
	end
	return tier
end

-- The flame on the player's nameplate: earned rewards stay, so it follows the best streak.
function Login.flameTier(login: Login): number
	return Login.tierFor(login.best)
end

-- The calendar and streak part of the Quests view.
function Login.fillView(view: Types.QuestView, login: Login, today: number)
	view.calendar =
		{ glory = table.clone(L.CalendarGlory), step = login.step, playedToday = login.lastPlayDay == today }
	view.streak = Login.currentStreak(login, today)
	view.best = login.best
	view.flame = Login.flameTier(login)
end

return Login
