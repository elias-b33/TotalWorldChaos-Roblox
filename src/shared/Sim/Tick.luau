--!strict
-- One game tick in the order from docs/DESIGN.md "Tick order". Step 1 (queued commands) happens before this
-- in CommandRouter, step 9 (the delta) after it in Replicator. Pure, so tests can run whole matches.

local Battle = require("./Battle")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Economy = require("./Economy")
local EventCards = require("./EventCards")
local Match = require("./Match")
local Movement = require("./Movement")
local Navy = require("./Navy")
local Primordial = require("./Primordial")
local Rng = require("./Rng")
local Siege = require("./Siege")
local Types = require("../Types")
local Victory = require("./Victory")

type MatchState = Types.MatchState

local Tick = {}

-- Advance one tick. Returns the new phase if it changed.
function Tick.advance(state: MatchState, rng: Rng.Rng): Types.Phase?
	state.tick += 1
	if state.result then
		return nil -- Results: the world stands still until the next match
	end
	local before = state.phase
	state.phase = Match.phaseAt(state.tick, state.setup)
	Movement.endAccess(state) -- 2: military access that ended sends the guests' armies home first...
	Navy.step(state) -- ...fleets sail, armies board, fleets land...
	Movement.step(state) -- ...then armies move and stacks merge
	Battle.step(state, rng) -- 3: land battles, then sea battles
	Navy.battleStep(state, rng)
	Navy.blockades(state) -- (before sieges and pay, which they speed up and cut)
	Siege.step(state) -- 4
	if state.tick % Config.MonthTicks == 0 then -- 5
		Economy.payMonth(state)
	end
	Primordial.step(state, rng) -- 6: eliminations, charges, effect timers, Cataclysm disasters
	-- 7: bots (Phase 3)
	Diplomacy.expire(state) -- 8: offers, insults' answer windows...
	EventCards.step(state, rng) -- ...and event cards (the default choice), then new cards
	if state.setup.sandbox then
		-- a sandbox world never ends: no win check and no last tick (Sim.Sandbox)
		return if state.phase ~= before then state.phase else nil
	end
	local result = Victory.check(state)
	if result == nil and state.phase == "Results" then
		result = Victory.byScore(state)
	end
	if result then
		Victory.finish(state, result)
	end
	if state.phase ~= before then
		return state.phase
	end
	return nil
end

return Tick
