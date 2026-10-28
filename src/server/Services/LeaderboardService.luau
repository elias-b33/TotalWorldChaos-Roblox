--!strict
-- Leaderboards (docs/MONETIZATION.md 7.3): weekly conquest points in an OrderedDataStore per week (scope "W<week>",
-- new every Monday 00:00 UTC), the global level board (account XP) and each player's friends view of the weekly
-- board, sent to every player on join and after every refresh. Last week's top 100 wear the Warlord frame.
--
-- DataStore budgets: writes go in one batch after each Results (one increment and one set per player); reads are
-- cached and refreshed every Config.Leaderboards.RefreshSeconds (2 sorted pages of the weekly board and 1 of the
-- level board), plus one GetAsync per joining player (their own points) and one sorted read of last week's board per
-- week. Fair play (section 10): boards show display names only, and the friends list API is called only for each
-- player's own friends. Without DataStore access (Studio with API access off) the boards live in this server's
-- memory, so a Studio match still shows them moving.
-- Thin wrapper: the rules are in Shared.Sim.Leaderboards.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserService = game:GetService("UserService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Leaderboards = require(Shared.Sim.Leaderboards)
local Login = require(Shared.Sim.Login)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local ShopService = require(script.Parent.ShopService)

type Entry = Leaderboards.Entry

local L = Config.Leaderboards
local CONQUEST_STORE = "Conquest" -- one scope per week (Leaderboards.weekKey)
local LEVEL_STORE = "Level"
local PAGE_SIZE = 100 -- the largest page GetSortedAsync returns
local NAME_BATCH = 100 -- user ids per UserService:GetUserInfosByUserIdsAsync call

-- One board: an OrderedDataStore, or a table in this server's memory. Every call may yield; nil = it failed.
type Board = {
	increment: (userId: number, delta: number) -> number?,
	set: (userId: number, value: number) -> boolean,
	get: (userId: number) -> number?,
	top: (count: number) -> { Entry }?,
}

local LeaderboardService = {}

local remote: RemoteEvent
local live = false -- the real DataStores answer
local ready = false -- the DataStore check is done
local memory: { [string]: { [number]: number } } = {} -- boards kept in memory when not live
local week = -1 -- the week the caches are for
local weekly: { Entry } = {} -- this week's top rows, as last read
local levels: { Entry } = {} -- the level board's top rows, as last read
local lastTop: { number }? = nil -- last week's top (the Warlord frame), read once per week
local known: { [number]: number } = {} -- this week's points of players in this server (newer than `weekly`)
local knownXp: { [number]: number } = {} -- account XP of players in this server
local friends: { [number]: { number } } = {} -- each player's friends (their own list), by userId
local names: { [number]: string } = {} -- display names
local pendingPoints: { [number]: number } = {} -- written at the next flush
local pendingXp: { [number]: number } = {}
local flushQueued = false

local function currentWeek(): number
	return Login.weekOf(ProgressionService.today()) -- DevDay moves it in Studio
end

local function realBoard(store: OrderedDataStore): Board
	return {
		increment = function(userId: number, delta: number): number?
			local ok, value = pcall(function()
				return store:IncrementAsync(tostring(userId), delta)
			end)
			return if ok and type(value) == "number" then value else nil
		end,
		set = function(userId: number, value: number): boolean
			return (pcall(function()
				store:SetAsync(tostring(userId), value)
			end))
		end,
		get = function(userId: number): number?
			local ok, value = pcall(function()
				return store:GetAsync(tostring(userId))
			end)
			return if ok and type(value) == "number" then value else nil
		end,
		top = function(count: number): { Entry }?
			local ok, rows = pcall(function()
				local out: { Entry } = {}
				local pages = store:GetSortedAsync(false, math.min(count, PAGE_SIZE))
				while true do
					for _, item in pages:GetCurrentPage() do
						local userId = tonumber(item.key)
						if userId and #out < count then
							table.insert(out, { userId = userId, value = item.value })
						end
					end
					if #out >= count or pages.IsFinished then
						break
					end
					pages:AdvanceToNextPageAsync()
				end
				return out
			end)
			return if ok then rows else nil
		end,
	}
end

local function memoryBoard(key: string): Board
	local data = memory[key] or {}
	memory[key] = data
	return {
		increment = function(userId: number, delta: number): number?
			data[userId] = (data[userId] or 0) + delta
			return data[userId]
		end,
		set = function(userId: number, value: number): boolean
			data[userId] = value
			return true
		end,
		get = function(userId: number): number?
			return data[userId]
		end,
		top = function(count: number): { Entry }?
			local out: { Entry } = {}
			for userId, value in data do
				table.insert(out, { userId = userId, value = value })
			end
			out = Leaderboards.sorted(out)
			while #out > count do
				table.remove(out)
			end
			return out
		end,
	}
end

local function board(name: string, scope: string?): Board
	if live then
		return realBoard(DataStoreService:GetOrderedDataStore(name, scope))
	end
	return memoryBoard(name .. "/" .. (scope or ""))
end

local function conquest(forWeek: number): Board
	return board(CONQUEST_STORE, Leaderboards.weekKey(forWeek))
end

local function nameOf(userId: number): string
	return names[userId] or "…"
end

-- Display names for ids we don't know yet (UserService; display names only, nothing else is kept).
local function fetchNames(entries: { Entry })
	local missing = {}
	for _, e in entries do
		if names[e.userId] == nil and not table.find(missing, e.userId) then
			table.insert(missing, e.userId)
		end
	end
	for i = 1, #missing, NAME_BATCH do
		local batch = table.move(missing, i, math.min(i + NAME_BATCH - 1, #missing), 1, {})
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(batch)
		end)
		if ok and type(infos) == "table" then
			for _, info in infos do
				names[info.Id] = info.DisplayName
			end
		end
	end
end

function LeaderboardService.sendView(player: Player)
	local data = PlayerDataService.data(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	local me = player.UserId
	local thisWeek = Leaderboards.merge(weekly, known)
	local view: Types.BoardsView = {
		week = week,
		weekly = Leaderboards.rows(thisWeek, me, nameOf),
		friends = Leaderboards.rows(Leaderboards.friends(thisWeek, friends[me] or {}, me), me, nameOf),
		level = Leaderboards.rows(Leaderboards.merge(levels, knownXp), me, nameOf, true),
		myPoints = known[me] or 0,
		myRank = Leaderboards.rank(thisWeek, me),
		warlord = data.owned[Leaderboards.WARLORD] == true,
		live = live,
	}
	remote:FireClient(player, view)
end

local function sendAll()
	for _, player in Players:GetPlayers() do
		LeaderboardService.sendView(player)
	end
end

-- The Warlord frame for this week, from last week's top (read once per week).
local function refreshWarlord(player: Player)
	if lastTop == nil then
		local rows = conquest(week - 1).top(L.WarlordTop)
		lastTop = if rows then Leaderboards.top(rows) else nil
	end
	local top = lastTop
	local data = PlayerDataService.data(player)
	if data == nil or top == nil then
		return
	end
	if Leaderboards.warlordDue(data, player.UserId, week, top) then -- saves only when something changes
		PlayerDataService.update(player, function(profile)
			Leaderboards.refreshWarlord(profile, player.UserId, week, top)
		end)
		ShopService.refresh(player)
	end
end

-- A player's own points this week (one read when they join or a week starts).
local function readOwn(player: Player)
	known[player.UserId] = conquest(week).get(player.UserId) or known[player.UserId] or 0
end

-- A new week (Monday 00:00 UTC, or DevDay in Studio): fresh boards, everyone's points and Warlord frames again.
local function checkWeek(): boolean
	local now = currentWeek()
	if now == week then
		return false
	end
	week = now
	weekly, known, lastTop = {}, {}, nil
	for _, player in Players:GetPlayers() do
		if PlayerDataService.data(player) then
			readOwn(player)
			refreshWarlord(player)
		end
	end
	return true
end

-- Read the boards again (cached until the next refresh), then send everyone their view.
local function refresh()
	checkWeek()
	local rows = conquest(week).top(L.ReadRows)
	if rows then
		weekly = rows
	end
	local levelRows = board(LEVEL_STORE).top(L.LevelRows)
	if levelRows then
		levels = levelRows
	end
	fetchNames(weekly)
	fetchNames(levels)
	sendAll()
end

-- After Results: one write per board for each player the match moved, then a fresh read.
local function flush()
	flushQueued = false
	checkWeek()
	local points, xp = pendingPoints, pendingXp
	pendingPoints, pendingXp = {}, {}
	local scores = conquest(week)
	for userId, add in points do
		local total = scores.increment(userId, add)
		known[userId] = total or ((known[userId] or 0) + add)
	end
	local levelBoard = board(LEVEL_STORE)
	for userId, value in xp do
		levelBoard.set(userId, value)
	end
	refresh()
end

-- Inside the match reward's profile update (must not yield): queue the points and the new XP for the next flush.
local function onReward(
	player: Player,
	data: Types.PlayerProfile,
	_stats: Types.PlayerMatchStats,
	report: Types.RewardReport,
	state: Types.MatchState
)
	local userId = player.UserId
	local points = if Leaderboards.counts(state) then Leaderboards.points(report.reward) else 0
	if points > 0 then
		pendingPoints[userId] = (pendingPoints[userId] or 0) + points
	end
	if report.reward.xp ~= 0 then
		pendingXp[userId] = data.xp
	end
	knownXp[userId] = data.xp
	if not flushQueued and (next(pendingPoints) ~= nil or next(pendingXp) ~= nil) then
		flushQueued = true
		task.defer(flush)
	end
end

-- A player's profile loaded: their name, own friends, points and XP, the Warlord frame, then their view.
local function onLoaded(player: Player, data: Types.PlayerProfile)
	while not ready do
		task.wait()
	end
	local userId = player.UserId
	names[userId] = player.DisplayName
	knownXp[userId] = data.xp
	checkWeek()
	readOwn(player)
	refreshWarlord(player)
	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(userId)
	end)
	local list: { number } = {}
	while ok and pages do
		for _, friend in pages:GetCurrentPage() do
			if #list < L.MaxFriends then
				table.insert(list, friend.Id)
				names[friend.Id] = friend.DisplayName
			end
		end
		if #list >= L.MaxFriends or pages.IsFinished then
			break
		end
		ok = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
	end
	friends[userId] = list
	LeaderboardService.sendView(player)
end

function LeaderboardService.init()
	remote = Remotes.event("Boards")
	ProgressionService.onReward(onReward)
	PlayerDataService.onLoaded(onLoaded)
	Players.PlayerRemoving:Connect(function(player)
		friends[player.UserId] = nil
		known[player.UserId] = nil -- the board itself keeps their points
		knownXp[player.UserId] = nil
	end)
	task.spawn(function()
		live = pcall(function()
			DataStoreService:GetOrderedDataStore(LEVEL_STORE):GetAsync("0")
		end)
		if not live then
			print("[leaderboards] no DataStore access: the boards live in this server's memory")
		end
		ready = true
		refresh()
		while true do
			task.wait(L.RefreshSeconds)
			refresh()
		end
	end)
end

return LeaderboardService
