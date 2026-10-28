--!strict
-- The singleplayer sandbox (docs/DESIGN.md "Sandbox"): a player's own world on a reserved server, WorldBox style.
-- All ten nations are bots. The player takes over any living nation whenever they like (the one they leave goes back
-- to a bot) or just watches, and casts every Primordial power for free either way (Commands, Primordial). They set
-- the time (pause, 1×, 2×, 4×: the server runs that many ticks a second) and switch the disasters on or off.
-- The rules the sandbox changes live with the rules they change, keyed on MatchState.setup.sandbox:
--   Settings.timing   the usual Peace, then War for ever: no Cataclysm, no 25:00
--   Tick              no win check, so nothing ends the world
--   Primordial        no 30 s immunity; free casts in every phase; disasters while switched on; a fallen player
--                     goes back to watching instead of rising as a Primordial
--   Progression       a sandbox pays no XP or Glory
-- This module holds the world's setup and its controls (MatchState.sandbox). Pure: no Roblox, no clock.

local Config = require("../Config")
local Match = require("./Match")
local Settings = require("./Settings")
local Types = require("../Types")

type MatchState = Types.MatchState

local Sandbox = {}

-- A sandbox world's setup: what public servers play, marked as a sandbox.
function Sandbox.setup(): Types.MatchSetup
	local setup = Settings.setup(false)
	setup.sandbox = true
	return setup
end

-- Turn a fresh match made with Sandbox.setup() into a running world: the clock at Config.Sandbox.StartSpeed, the
-- disasters off. Every nation is a bot (Match.new) and stays one until someone takes it over.
function Sandbox.start(state: MatchState)
	assert(state.setup.sandbox, "Sandbox.start needs a match made with Sandbox.setup()")
	state.sandbox = { speed = Config.Sandbox.StartSpeed, disasters = false, disastersFrom = 0 }
end

-- A new world on a map, ready to run.
function Sandbox.new(map: Types.MapDef): MatchState
	local state = Match.new(map, Sandbox.setup())
	Sandbox.start(state)
	return state
end

-- Game ticks per real second (0 = paused); 1 outside a sandbox.
function Sandbox.speed(state: MatchState): number
	local controls = state.sandbox
	return if controls then controls.speed else 1
end

-- The time controls: one of Config.Sandbox.Speeds (0 pauses the world).
function Sandbox.setSpeed(state: MatchState, speed: number): (boolean, string?)
	local controls = state.sandbox
	if controls == nil then
		return false, "NotSandbox"
	end
	if table.find(Config.Sandbox.Speeds, speed) == nil then
		return false, "BadSpeed"
	end
	controls.speed = speed
	return true, nil
end

-- Disasters on or off. Switched on, the first strikes Config.Primordial.CataclysmDisasterTicks later
-- (Primordial.disasterDue), then one every as many ticks.
function Sandbox.setDisasters(state: MatchState, on: boolean): (boolean, string?)
	local controls = state.sandbox
	if controls == nil then
		return false, "NotSandbox"
	end
	if on and not controls.disasters then
		controls.disastersFrom = state.tick
	end
	controls.disasters = on
	return true, nil
end

-- Take over a living nation, or watch (nationId 0). The nation the player held goes back to a bot at once: its
-- armies, wars and alliances stay as they are, and the bots plan for it again from the next tick. A nation another
-- player holds is "Taken" (only in Studio tests can a sandbox have two players).
function Sandbox.play(state: MatchState, userId: number, nationId: number): (boolean, string?)
	if state.sandbox == nil then
		return false, "NotSandbox"
	end
	if nationId ~= 0 then
		local nation = state.nations[nationId]
		if nation == nil then
			return false, "UnknownNation"
		elseif nation.eliminated then
			return false, "Eliminated"
		elseif nation.userId == userId then
			return true, nil -- already theirs
		elseif nation.controller ~= "Bot" or nation.userId ~= nil then
			return false, "Taken"
		end
	end
	local held = Match.nationOf(state, userId)
	if held then
		local old = state.nations[held]
		old.controller = "Bot"
		old.userId = nil
	end
	state.seats[userId] = nil
	if nationId ~= 0 then
		Match.assign(state, nationId, userId)
	end
	return true, nil
end

-- A player arriving in a sandbox watches until they take a nation over (a player who still holds one keeps it).
function Sandbox.seat(state: MatchState, userId: number): number?
	return Match.nationOf(state, userId)
end

-- The map a new world plays: `requested` if the server has it, "" for `fallback`. Nil and "UnknownMap" otherwise.
function Sandbox.mapFor(requested: string, maps: { string }, fallback: string): (string?, string?)
	if requested == "" then
		return fallback, nil
	end
	if table.find(maps, requested) == nil then
		return nil, "UnknownMap"
	end
	return requested, nil
end

-- A sandbox intent that changes the running world (Speed, Play, Disasters). Enter, Leave and NewWorld teleport the
-- player or restart the world: SandboxService runs those.
function Sandbox.apply(state: MatchState, userId: number, intent: Types.SandboxIntent): (boolean, string?)
	if state.sandbox == nil then
		return false, "NotSandbox"
	end
	if intent.kind == "Speed" then
		return Sandbox.setSpeed(state, intent.speed)
	elseif intent.kind == "Play" then
		return Sandbox.play(state, userId, intent.nation)
	elseif intent.kind == "Disasters" then
		return Sandbox.setDisasters(state, intent.on)
	end
	return false, "BadRequest"
end

return Sandbox
