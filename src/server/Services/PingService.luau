--!strict
-- Map pings to the people allowed to see them (docs/NEXT_FEATURES.md 4). Thin: the rules are in Shared.Sim.Pings.
-- After each tick, every new ping goes to the players of the sender's living alliance (Pings.recipients, the sender
-- included) with FireClient, never FireAllClients: pings are never in the snapshot or the delta, so enemies,
-- neutrals and spectators can't read them from the network. A ping that leaves early (the sender's third ping
-- replaced it, or the sender fell) is taken off the same players' maps with PingGone; the rest fade on their own
-- at untilTick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Pings = require(Shared.Sim.Pings)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local PingService = {}

local pingRemote: RemoteEvent
local goneRemote: RemoteEvent
local current: Types.MatchState? = nil
local sentUpTo = 0 -- the highest ping id already sent in this match
local shown: { [number]: { players: { Player }, untilTick: number } } = {} -- ping id -> who got it

function PingService.init()
	pingRemote = Remotes.event("Ping")
	goneRemote = Remotes.event("PingGone")
end

-- After tick order steps 1-8: send this tick's new pings, and take back the ones that went early.
function PingService.afterTick(state: Types.MatchState)
	if state ~= current then
		current = state -- a new match: its ping ids start again
		sentUpTo = 0
		shown = {}
	end
	local live: { [number]: boolean } = {}
	for _, ping in state.pings do
		live[ping.id] = true
		if ping.id > sentUpTo then
			sentUpTo = ping.id
			local players = {}
			for _, nationId in Pings.recipients(state, ping) do
				local userId = state.nations[nationId].userId
				local player = if userId then Players:GetPlayerByUserId(userId) else nil
				if player then
					-- Ping(id, by, kind, province, untilTick)
					pingRemote:FireClient(player, ping.id, ping.by, ping.kind, ping.province, ping.untilTick)
					table.insert(players, player)
				end
			end
			shown[ping.id] = { players = players, untilTick = ping.untilTick }
		end
	end
	for id, entry in shown do
		if not live[id] then
			if state.tick <= entry.untilTick then
				for _, player in entry.players do
					if player.Parent == Players then
						goneRemote:FireClient(player, id)
					end
				end
			end
			shown[id] = nil
		end
	end
end

return PingService
