--!strict
-- Map pings (docs/DESIGN.md "UI and controls", docs/NEXT_FEATURES.md 4): an allied nation puts an icon (Attack,
-- Defend, Help or Look) on a province for its alliance. Pings carry no text from players: the marker is an icon and
-- a flag. They live in MatchState.pings for Config.Pings.LifeTicks, never in the snapshot or the delta: PingService
-- sends each new one to Pings.recipients only, so enemies and neutrals can't read them from the network.
-- The cooldown and the per-minute cap count each nation's recent pings (MatchState.pingSent).

local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Types = require("../Types")

type MatchState = Types.MatchState
type Ping = Types.Ping

local ACTIVE_PHASES = { Peace = true, War = true, Cataclysm = true }

local KINDS: { [string]: boolean } = {}
for _, kind in Config.Pings.Kinds do
	KINDS[kind] = true
end

local Pings = {}

-- Is `v` one of the four ping kinds (Config.Pings.Kinds)? For CommandRouter's shape check.
function Pings.isKind(v: unknown): boolean
	return type(v) == "string" and KINDS[v] == true
end

local function living(state: MatchState, nationId: number): boolean
	local nation = state.nations[nationId]
	return nation ~= nil and not nation.eliminated
end

-- The sender's living alliance members, the sender first (its own team sees its pings too). Never an enemy, never a
-- neutral: a nation in no alliance has only itself.
function Pings.team(state: MatchState, nationId: number): { number }
	local team = { nationId }
	for _, member in Diplomacy.allianceMembers(state, nationId) do
		if member ~= nationId and living(state, member) and Diplomacy.allied(state, nationId, member) then
			table.insert(team, member)
		end
	end
	return team
end

-- Who sees a ping: the sender's living alliance members, the sender included (nobody else, ever).
function Pings.recipients(state: MatchState, ping: Ping): { number }
	if not living(state, ping.by) then
		return {}
	end
	return Pings.team(state, ping.by)
end

-- The ticks of this nation's pings still inside the per-minute window.
local function recent(state: MatchState, nationId: number, tick: number): { number }
	local kept = {}
	for _, t in state.pingSent[nationId] or {} do
		if tick - t < Config.Pings.MinuteTicks then
			table.insert(kept, t)
		end
	end
	return kept
end

-- May this nation ping `province` now? Its nation is alive and allied with another living nation, the match is in
-- Peace, War or Cataclysm, the province exists and isn't a mountain, and the cooldown and the per-minute cap allow
-- it. Returns true, or false and a reason: NoNation, BadRequest (an unknown kind), Phase, NoAllies, BadTarget,
-- TooSoon, TooMany.
function Pings.canPing(
	state: MatchState,
	nationId: number,
	kind: string,
	province: number,
	tick: number
): (boolean, string?)
	if not living(state, nationId) then
		return false, "NoNation"
	end
	if not Pings.isKind(kind) then
		return false, "BadRequest"
	end
	if not ACTIVE_PHASES[state.phase] then
		return false, "Phase"
	end
	if #Pings.team(state, nationId) < 2 then
		return false, "NoAllies"
	end
	local target = state.provinces[province]
	if target == nil or target.terrain == "Mountain" then
		return false, "BadTarget"
	end
	local sent = recent(state, nationId, tick)
	local last = sent[#sent]
	if last and tick - last < Config.Pings.CooldownTicks then
		return false, "TooSoon"
	end
	if #sent >= Config.Pings.MaxPerMinute then
		return false, "TooMany"
	end
	return true, nil
end

-- Put a ping on the map (after Pings.canPing): it lives until `untilTick` (tick + LifeTicks) and the sender's oldest
-- live pings past Config.Pings.MaxActive give way to it. Returns the new ping.
function Pings.add(state: MatchState, nationId: number, kind: Types.PingKind, province: number, tick: number): Ping
	local ping: Ping = {
		id = state.nextPingId,
		by = nationId,
		kind = kind,
		province = province,
		untilTick = tick + Config.Pings.LifeTicks,
	}
	state.nextPingId += 1
	table.insert(state.pings, ping)
	local sent = recent(state, nationId, tick)
	table.insert(sent, tick)
	state.pingSent[nationId] = sent
	-- the sender's live pings, oldest first (pings are appended in order): drop the oldest past the cap
	local mine = 0
	for _, p in state.pings do
		if p.by == nationId then
			mine += 1
		end
	end
	local drop = mine - Config.Pings.MaxActive
	if drop > 0 then
		local kept = {}
		for _, p in state.pings do
			if p.by == nationId and drop > 0 then
				drop -= 1
			else
				table.insert(kept, p)
			end
		end
		state.pings = kept
	end
	return ping
end

-- Tick order step 6 (with charges and timers): pings past their `untilTick` go, and so do the pings of a sender that
-- has fallen. Ticks older than the per-minute window are forgotten.
function Pings.expire(state: MatchState)
	local kept = {}
	for _, p in state.pings do
		if state.tick <= p.untilTick and living(state, p.by) then
			table.insert(kept, p)
		end
	end
	if #kept ~= #state.pings then
		state.pings = kept
	end
	for nationId in state.pingSent do
		local sent = recent(state, nationId, state.tick)
		state.pingSent[nationId] = if #sent > 0 then sent else nil
	end
end

return Pings
