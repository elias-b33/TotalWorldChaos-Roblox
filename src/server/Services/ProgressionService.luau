--!strict
-- Match XP and Glory (docs/MONETIZATION.md 4.1, 5.1): keeps each player's stats for the current match (captures,
-- battles won, powers used, time without a command) and pays the reward at Results, or when a player leaves early.
-- Thin wrapper: the rules are in Shared.Sim.Progression, saving is PlayerDataService's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Sim.Progression)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ShopService = require(script.Parent.ShopService)

local SECONDS_PER_DAY = 86400

local ProgressionService = {}

local getState: () -> Types.MatchState? -- nil before the first match (the first Lobby)
local current: Types.MatchState? = nil
local stats: { [number]: Types.PlayerMatchStats } = {} -- by userId, for the current match (leavers too)
-- Results rewards for players whose profile was still loading: paid when it loads (or dropped if they leave).
local owed: { [number]: { state: Types.MatchState, entry: Types.PlayerMatchStats } } = {}
local rewardRemote: RemoteEvent

local function today(): number
	return os.time() // SECONDS_PER_DAY -- UTC day number; Sim never reads the clock
end

local function isVip(player: Player): boolean
	return ShopService.isVip(player) -- +25% match XP and Glory (MONETIZATION 3.3)
end

local function options(player: Player, data: Types.PlayerProfile): Progression.RewardOptions
	return {
		vip = isVip(player),
		firstMatchToday = Progression.isFirstMatchToday(data, today()),
		standardRules = true, -- private-server custom rules arrive later
	}
end

local function startTracking(state: Types.MatchState)
	current = state
	stats = {}
	for _, player in Players:GetPlayers() do
		stats[player.UserId] = Progression.newStats(player.UserId, state.tick)
	end
end

-- Pay one player's Results reward, save, and show it. False if their profile isn't loaded yet.
local function pay(player: Player, state: Types.MatchState, entry: Types.PlayerMatchStats): boolean
	local report = PlayerDataService.update(player, function(data)
		local reward = Progression.matchReward(state, entry, options(player, data))
		return Progression.grant(data, entry, reward, today())
	end)
	if report then
		rewardRemote:FireClient(player, report)
	end
	return report ~= nil
end

-- Results: pay everyone who is still here (or as soon as a still-loading profile is ready).
local function payAll(state: Types.MatchState)
	for _, player in Players:GetPlayers() do
		local entry = stats[player.UserId]
		if entry and entry.leftAt == nil and not pay(player, state, entry) then
			owed[player.UserId] = { state = state, entry = entry }
		end
	end
	stats = {}
end

function ProgressionService.init(stateGetter: () -> Types.MatchState?)
	getState = stateGetter
	rewardRemote = Remotes.event("Reward")
	Players.PlayerAdded:Connect(function(player)
		local state = getState()
		if state and state == current and state.result == nil then
			local entry = stats[player.UserId]
			if entry then
				Progression.rejoin(entry, state.tick) -- back in the same match: one record, caps count once
			else
				stats[player.UserId] = Progression.newStats(player.UserId, state.tick)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		owed[player.UserId] = nil -- their profile never loaded here: nothing to write the reward to
	end)
	PlayerDataService.onLoaded(function(player)
		local due = owed[player.UserId]
		if due then
			owed[player.UserId] = nil
			pay(player, due.state, due.entry)
		end
	end)
	CommandRouter.observe(function(player: Player, command: Types.Command, ok: boolean)
		local entry = stats[player.UserId]
		if entry and current then
			Progression.recordCommand(entry, current.tick, command, ok)
		end
	end)
	-- leaving before Results: a prorated reward, saved with the profile's final save
	PlayerDataService.onLeaving(function(player, data)
		local entry = stats[player.UserId]
		local state = current
		if entry == nil or state == nil or state.result ~= nil then
			return
		end
		Progression.leave(entry, state.tick) -- the record stays: rejoining carries on with it
		Progression.grant(data, entry, Progression.matchReward(state, entry, options(player, data)), today())
	end)
end

-- After tick order steps 2-8, before the delta clears the events: count this tick's captures and battle wins,
-- and pay out when the match has just ended.
function ProgressionService.afterTick(state: Types.MatchState)
	if state ~= current then
		startTracking(state) -- a new match
	end
	if next(stats) == nil then
		return
	end
	Progression.observe(state, stats)
	if state.result then
		payAll(state)
	end
end

return ProgressionService
