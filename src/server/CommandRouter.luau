--!strict
-- Every intent from players (and later bots) comes through here.
-- 1. Check the shape of what the client sent (never trust it) and the rate limit.
-- 2. Queue it; GameLoop applies the queue at the start of the next tick (tick order step 1).
-- 3. Sim.Commands checks the game rules and changes state; the player gets CommandResult(requestId, ok, reason).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Commands = require(Shared.Sim.Commands)
local Config = require(Shared.Config)
local RateLimit = require(Shared.RateLimit)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type Pending = {
	player: Player?, -- nil for bots
	requestId: number,
	botNation: number?, -- set for bots; players are looked up when the command is applied
	command: Types.Command,
}

local BUILDINGS = { Farm = true, Barracks = true, Fort = true }

local CommandRouter = {}

local queue: { Pending } = {}
local limiter = RateLimit.new(Config.Net.MaxIntentsPerSecond)
local commandResult: RemoteEvent
local nationOf: (Player) -> number?

local function isId(v: unknown): boolean
	return type(v) == "number" and v == v and v >= 1 and v <= 1e6 and v == math.floor(v)
end

local function reply(player: Player?, requestId: number, ok: boolean, reason: string?)
	if player and player.Parent == Players then
		commandResult:FireClient(player, requestId, ok, reason)
	end
end

-- Shared entry for every client remote: request ids, rate limit, then queue.
local function accept(player: Player, requestId: unknown, build: () -> Types.Command?)
	if not isId(requestId) then
		return -- malformed: drop silently
	end
	local id = requestId :: number
	if not RateLimit.allow(limiter, player.UserId, os.clock()) then
		reply(player, id, false, "TooFast")
		return
	end
	local command = build()
	if command == nil then
		reply(player, id, false, "BadRequest")
		return
	end
	table.insert(queue, { player = player, requestId = id, botNation = nil, command = command })
end

function CommandRouter.init(getNation: (Player) -> number?)
	nationOf = getNation
	commandResult = Remotes.event("CommandResult")

	Remotes.event("RequestDevelop").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, province: unknown)
			accept(player, requestId, function()
				if not isId(province) then
					return nil
				end
				return { kind = "Develop", province = province :: number }
			end)
		end)

	Remotes.event("RequestBuild").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, province: unknown, building: unknown)
			accept(player, requestId, function()
				if not isId(province) or type(building) ~= "string" or not BUILDINGS[building] then
					return nil
				end
				return { kind = "Build", province = province :: number, building = building :: Types.Building }
			end)
		end)

	Remotes.event("RequestRecruit").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, province: unknown, regiments: unknown)
			accept(player, requestId, function()
				if not isId(province) or not isId(regiments) then
					return nil
				end
				return { kind = "Recruit", province = province :: number, regiments = regiments :: number }
			end)
		end)

	Players.PlayerRemoving:Connect(function(player)
		RateLimit.forget(limiter, player.UserId)
	end)
end

-- Bots (Phase 3) call this with the same commands players send.
function CommandRouter.submitForBot(nationId: number, command: Types.Command)
	table.insert(queue, { player = nil, requestId = 0, botNation = nationId, command = command })
end

-- Tick order step 1: apply everything queued since the last tick, in arrival order.
function CommandRouter.applyQueued(state: Types.MatchState)
	local pending = queue
	queue = {}
	for _, item in pending do
		local nationId = item.botNation
		if item.player then
			nationId = if item.player.Parent == Players then nationOf(item.player) else nil
		end
		local ok, reason
		if nationId == nil then
			ok, reason = false, "NoNation"
		else
			ok, reason = Commands.apply(state, nationId, item.command)
		end
		reply(item.player, item.requestId, ok, reason)
	end
end

-- A new match makes queued intents meaningless.
function CommandRouter.clear()
	queue = {}
end

return CommandRouter
