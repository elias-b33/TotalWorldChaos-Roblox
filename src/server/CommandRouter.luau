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
local Primordial = require(Shared.Sim.Primordial)
local RateLimit = require(Shared.RateLimit)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

type Pending = {
	player: Player?, -- nil for bots
	requestId: number,
	botNation: number?, -- set for bots; players are looked up when the command is applied
	command: Types.Command,
}

type LobbyPending = { player: Player, requestId: number, intent: Types.LobbyIntent }

local BUILDINGS = { Farm = true, Barracks = true, Fort = true }
local MAX_MAP_ID = 32 -- longest map id a vote may name (the map list itself is checked by Sim.Lobby)
local DIPLOMACY_ACTIONS = { War = true, Ally = true, AcceptAlly = true, Peace = true, AcceptPeace = true }

local CommandRouter = {}

local queue: { Pending } = {}
local lobbyQueue: { LobbyPending } = {}
local limiter = RateLimit.new(Config.Net.MaxIntentsPerSecond)
local commandResult: RemoteEvent
local nationOf: (Player) -> number?
local observers: { (Player, Types.Command, boolean) -> () } = {}
local shopHandler: ((Player, Types.ShopIntent) -> (boolean, string?))? = nil
local MAX_ITEM_ID = 40 -- longest catalogue id a shop request may name (the catalogue itself is checked by Sim.Shop)

local function isId(v: unknown): boolean
	return type(v) == "number" and v == v and v >= 1 and v <= 1e6 and v == math.floor(v)
end

local function isAmount(v: unknown): boolean
	return type(v) == "number" and v == v and v >= 0 and v <= 1e6 and v == math.floor(v)
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

	Remotes.event("RequestMove").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, army: unknown, to: unknown)
			accept(player, requestId, function()
				if not isId(army) or not isId(to) then
					return nil
				end
				return { kind = "Move", army = army :: number, to = to :: number }
			end)
		end)

	Remotes.event("RequestDiplomacy").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, action: unknown, target: unknown, gold: unknown)
			accept(player, requestId, function()
				if type(action) ~= "string" or not DIPLOMACY_ACTIONS[action] or not isId(target) then
					return nil
				end
				local amount = if gold == nil then 0 else gold
				if not isAmount(amount) then
					return nil
				end
				return {
					kind = "Diplomacy",
					action = action :: Types.DiplomacyAction,
					target = target :: number,
					gold = amount :: number,
				}
			end)
		end)

	Remotes.event("RequestPower").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, power: unknown, target: unknown)
			accept(player, requestId, function()
				if type(power) ~= "string" or Primordial.TARGETS[power] == nil or not isId(target) then
					return nil
				end
				return { kind = "Power", power = power :: Types.PrimordialPower, target = target :: number }
			end)
		end)

	-- Lobby intents: the same request ids and rate limit, their own queue (Sim.Lobby checks the rules).
	local function acceptLobby(player: Player, requestId: unknown, intent: Types.LobbyIntent?)
		if not isId(requestId) then
			return
		end
		local id = requestId :: number
		if not RateLimit.allow(limiter, player.UserId, os.clock()) then
			reply(player, id, false, "TooFast")
		elseif intent == nil then
			reply(player, id, false, "BadRequest")
		else
			table.insert(lobbyQueue, { player = player, requestId = id, intent = intent })
		end
	end

	Remotes.event("RequestVote").OnServerEvent:Connect(function(player: Player, requestId: unknown, map: unknown)
		local ok = type(map) == "string" and #map <= MAX_MAP_ID
		acceptLobby(player, requestId, if ok then { kind = "Vote", map = map :: string } else nil)
	end)

	Remotes.event("RequestPick").OnServerEvent:Connect(function(player: Player, requestId: unknown, nation: unknown)
		acceptLobby(player, requestId, if isId(nation) then { kind = "Pick", nation = nation :: number } else nil)
	end)

	-- Shop intents: not tied to the match clock, so ShopService answers them right away (it may yield to save).
	local function acceptShop(player: Player, requestId: unknown, intent: Types.ShopIntent?)
		if not isId(requestId) then
			return
		end
		local id = requestId :: number
		if not RateLimit.allow(limiter, player.UserId, os.clock()) then
			reply(player, id, false, "TooFast")
		elseif intent == nil or shopHandler == nil then
			reply(player, id, false, "BadRequest")
		else
			local handler = shopHandler :: (Player, Types.ShopIntent) -> (boolean, string?)
			task.spawn(function()
				local ok, reason = handler(player, intent)
				reply(player, id, ok, reason)
			end)
		end
	end
	local function isItemId(v: unknown): boolean
		return type(v) == "string" and #v > 0 and #v <= MAX_ITEM_ID
	end

	Remotes.event("RequestBuy").OnServerEvent
		:Connect(function(player: Player, requestId: unknown, item: unknown, currency: unknown)
			local ok = isItemId(item) and (currency == "Glory" or currency == "Robux")
			acceptShop(
				player,
				requestId,
				if ok then { kind = "Buy", item = item :: string, currency = currency :: "Glory" | "Robux" } else nil
			)
		end)

	Remotes.event("RequestEquip").OnServerEvent:Connect(function(player: Player, requestId: unknown, item: unknown)
		acceptShop(player, requestId, if isItemId(item) then { kind = "Equip", item = item :: string } else nil)
	end)

	Remotes.event("RequestEmote").OnServerEvent:Connect(function(player: Player, requestId: unknown, item: unknown)
		acceptShop(player, requestId, if isItemId(item) then { kind = "Emote", item = item :: string } else nil)
	end)

	Remotes.event("RequestDefaultTheme").OnServerEvent:Connect(function(player: Player, requestId: unknown, on: unknown)
		acceptShop(player, requestId, if type(on) == "boolean" then { kind = "DefaultTheme", on = on } else nil)
	end)

	Players.PlayerRemoving:Connect(function(player)
		RateLimit.forget(limiter, player.UserId)
	end)
end

-- Tutorial requests ("Skip", "Leave"): the shape and the rate limit are checked here, then `handler` runs at once
-- (they change the player's tutorial and profile, never the match).
function CommandRouter.onTutorial(handler: (Player, string) -> ())
	Remotes.event("RequestTutorial").OnServerEvent:Connect(function(player: Player, requestId: unknown, action: unknown)
		if not isId(requestId) then
			return
		end
		local id = requestId :: number
		if not RateLimit.allow(limiter, player.UserId, os.clock()) then
			reply(player, id, false, "TooFast")
		elseif action ~= "Skip" and action ~= "Leave" then
			reply(player, id, false, "BadRequest")
		else
			handler(player, action :: string)
			reply(player, id, true, nil)
		end
	end)
end

-- Lobby step 1: apply queued votes and picks in arrival order. Without a lobby (a match is running) they are
-- refused.
function CommandRouter.applyLobbyQueued(apply: ((userId: number, intent: Types.LobbyIntent) -> (boolean, string?))?)
	local pending = lobbyQueue
	lobbyQueue = {}
	for _, item in pending do
		local ok, reason = false, "WrongPhase"
		if apply and item.player.Parent == Players then
			ok, reason = apply(item.player.UserId, item.intent)
		end
		reply(item.player, item.requestId, ok, reason)
	end
end

-- Between matches (the Lobby) there is no match to give orders in: refuse whatever was queued.
function CommandRouter.refuseQueued(reason: string)
	local pending = queue
	queue = {}
	for _, item in pending do
		reply(item.player, item.requestId, false, reason)
	end
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
		local userId: number? = nil
		if item.player then
			local present = item.player.Parent == Players
			nationId = if present then nationOf(item.player) else nil
			userId = if present then item.player.UserId else nil
		end
		-- Sim decides who acts: the bot's nation, the player's living nation, or their Primordial (a player who left
		-- has neither and is refused)
		local ok, reason = Commands.applyFor(state, userId, nationId, item.command)
		reply(item.player, item.requestId, ok, reason)
		if item.player and userId then
			for _, observer in observers do
				observer(item.player, item.command, ok)
			end
		end
	end
end

-- Called with every player command once it has been applied (ok or not), e.g. for match stats.
function CommandRouter.observe(fn: (Player, Types.Command, boolean) -> ())
	table.insert(observers, fn)
end

-- ShopService handles shop intents (buy, equip, emote); the player gets CommandResult with its answer.
function CommandRouter.onShop(handler: (Player, Types.ShopIntent) -> (boolean, string?))
	shopHandler = handler
end

-- A new match makes queued intents meaningless.
function CommandRouter.clear()
	queue = {}
	lobbyQueue = {}
end

return CommandRouter
