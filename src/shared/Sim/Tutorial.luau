--!strict
-- The tutorial match (docs/DESIGN.md "Tutorial"): a new player against Config.Tutorial.Bots Easy bots, the rest of
-- the map neutral, and six prompts in order. Each prompt is finished with the normal UI; this module only watches
-- the match and says which prompt is next and where the arrow points.
--
--   1. Take     own a province you didn't start with (the player starts with a ready army)
--   2. Recruit  recruit a regiment
--   3. Siege    besiege a province
--   4. Ally     be in an alliance (bots accept the player's alliance offers)
--   5. War      be at war (Peace ends early when this prompt starts)
--   6. Power    use a Primordial power (this prompt tops the player's charges up)
--
-- Pure: TutorialService calls setup at match start, recordCommand for the player's commands, update after every
-- tick and botOrders for the bots' part (sent through CommandRouter like any bot command).

local Army = require("./Army")
local Bot = require("./Bot")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Match = require("./Match")
local Types = require("../Types")

type MatchState = Types.MatchState
type TutorialState = Types.TutorialState

local Tutorial = {}

Tutorial.STEPS = { "Take", "Recruit", "Siege", "Ally", "War", "Power" }

local function sortedKeys(t: { [number]: any }): { number }
	local ids = {}
	for id in t do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Hops from a nation's land to every province (mountains block the way, straits count).
local function distances(state: MatchState, from: number): { [number]: number }
	local dist: { [number]: number } = {}
	local queue = {}
	for _, id in sortedKeys(state.provinces) do
		if state.provinces[id].owner == from then
			dist[id] = 0
			table.insert(queue, id)
		end
	end
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		for _, n in state.provinces[id].neighbors do
			local p = state.provinces[n]
			if p and dist[n] == nil and p.terrain ~= "Mountain" then
				dist[n] = dist[id] + 1
				table.insert(queue, n)
			end
		end
	end
	return dist
end

-- The province of `nationId` closest to the measured land (math.huge if it can't be reached).
local function nearestProvince(state: MatchState, dist: { [number]: number }, nationId: number): (number?, number)
	local best: number?, bestD = nil, math.huge
	for _, id in sortedKeys(state.provinces) do
		local d = dist[id]
		if state.provinces[id].owner == nationId and d and d < bestD then
			best, bestD = id, d
		end
	end
	return best, bestD
end

local function menOf(state: MatchState, nationId: number): number
	local men = 0
	for _, a in state.armies do
		if a.owner == nationId then
			men += a.men
		end
	end
	return men
end

local function living(state: MatchState, id: number?): boolean
	local n = if id then state.nations[id] else nil
	return n ~= nil and not n.eliminated
end

-- Setup ----------------------------------------------------------------------------------------------------

-- Turn a fresh match into a tutorial match: the player's nation (`slot`) and the Config.Tutorial.Bots nations
-- nearest to it stay; every other nation leaves the match and its land turns neutral, with a garrison. The player
-- gets a ready army at the capital, and the slot is held for them (bots never play it).
function Tutorial.setup(state: MatchState, slot: number): TutorialState
	local player = state.nations[slot]
	assert(player, "no nation in tutorial slot " .. slot)
	local dist = distances(state, slot)
	type Candidate = { id: number, d: number }
	local others: { Candidate } = {}
	for _, id in sortedKeys(state.nations) do
		if id ~= slot then
			local _, d = nearestProvince(state, dist, id)
			table.insert(others, { id = id, d = d })
		end
	end
	table.sort(others, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return a.id < b.id
	end)
	for i, c in others do
		if i > Config.Tutorial.Bots then
			for _, pid in sortedKeys(state.provinces) do
				local p = state.provinces[pid]
				if p.owner == c.id then
					p.owner = nil
					p.isCapital = false
					Army.spawn(state, 0, pid, Config.NeutralGarrison)
				end
			end
			state.nations[c.id] = nil
		end
	end
	state.setup.settings.events = false -- no event cards: the tutorial's prompts are enough to read
	player.controller = "Player" -- held for the player until they arrive (Tutorial.seat)
	player.userId = nil
	Army.spawn(state, slot, player.capital, Config.Tutorial.StartRegiments * Config.Army.MenPerRegiment)
	local startProvinces = {}
	for id, p in state.provinces do
		if p.owner == slot then
			startProvinces[id] = true
		end
	end
	return {
		slot = slot,
		step = 1,
		startProvinces = startProvinces,
		actions = {},
		friend = nil,
		rival = nil,
		skipped = false,
		startedAt = state.tick,
		finishedAt = nil,
	}
end

-- Seat a joining player: the tutorial nation if nobody holds it, otherwise like any match.
function Tutorial.seat(state: MatchState, tut: TutorialState, userId: number): number?
	local nation = state.nations[tut.slot]
	if nation and not nation.eliminated and (nation.userId == nil or nation.userId == userId) then
		if nation.userId == nil then
			tut.startedAt = state.tick -- the clock starts when the player arrives
		end
		nation.controller = "Player"
		nation.userId = userId
		return tut.slot
	end
	return Match.seatPlayer(state, userId)
end

-- Partners -------------------------------------------------------------------------------------------------

-- The nation to declare war on: the weakest (fewest men) one bordering the player that isn't an ally; without a
-- border, the nearest one.
function Tutorial.pickRival(state: MatchState, tut: TutorialState): number?
	local me = tut.slot
	local dist = distances(state, me)
	local best: number?, bestKey: { number }? = nil, nil
	for _, id in sortedKeys(state.nations) do
		if id ~= me and living(state, id) and not Diplomacy.allied(state, me, id) then
			local _, d = nearestProvince(state, dist, id)
			local key = {
				if Diplomacy.borders(state, me, id) then 0 else 1,
				if Diplomacy.borders(state, me, id) then 0 else d,
				menOf(state, id),
				Match.provinceCount(state, id),
			}
			local better = bestKey == nil
			if bestKey then
				for i = 1, #key do
					if key[i] ~= bestKey[i] then
						better = key[i] < bestKey[i]
						break
					end
				end
			end
			if better then
				best, bestKey = id, key
			end
		end
	end
	return best
end

-- The nation to ally with: the nearest one that isn't the war prompt's rival (bigger armies first on a tie).
function Tutorial.pickFriend(state: MatchState, tut: TutorialState): number?
	local me = tut.slot
	local rival = Tutorial.pickRival(state, tut)
	local dist = distances(state, me)
	local best: number?, bestD, bestMen = nil, math.huge, -1
	for _, id in sortedKeys(state.nations) do
		if id ~= me and id ~= rival and living(state, id) and not Diplomacy.atWar(state, me, id) then
			local _, d = nearestProvince(state, dist, id)
			local men = menOf(state, id)
			if best == nil or d < bestD or (d == bestD and men > bestMen) then
				best, bestD, bestMen = id, d, men
			end
		end
	end
	return best or rival
end

-- Steps ----------------------------------------------------------------------------------------------------

function Tutorial.stepName(tut: TutorialState): string?
	return Tutorial.STEPS[tut.step]
end

function Tutorial.finished(tut: TutorialState): boolean
	return tut.step > #Tutorial.STEPS
end

-- Is the current prompt done?
function Tutorial.stepDone(state: MatchState, tut: TutorialState): boolean
	local me = tut.slot
	local step = Tutorial.stepName(tut)
	if step == "Take" then
		for id, p in state.provinces do
			if p.owner == me and not tut.startProvinces[id] then
				return true
			end
		end
	elseif step == "Recruit" then
		return tut.actions.Recruit == true
	elseif step == "Siege" then
		for _, p in state.provinces do
			local siege = p.siege
			if siege and siege.by == me then
				return true
			end
		end
	elseif step == "Ally" then
		return state.nations[me].allianceId ~= nil
	elseif step == "War" then
		for id in state.nations do
			if Diplomacy.atWar(state, me, id) then
				return true
			end
		end
	elseif step == "Power" then
		return tut.actions.Power == true
	end
	return false
end

-- What a prompt needs from the world when it starts.
local function enter(state: MatchState, tut: TutorialState)
	local step = Tutorial.stepName(tut)
	if step == "Ally" then
		tut.friend = Tutorial.pickFriend(state, tut)
	elseif step == "War" then
		tut.rival = Tutorial.pickRival(state, tut)
		if state.phase == "Peace" then
			-- Peace ends with the next tick, so war (and powers) can be used right away
			state.tick = math.max(state.tick, Config.Phases.PeaceEndTick - 1)
		end
	elseif step == "Power" then
		local nation = state.nations[tut.slot]
		nation.charges = math.max(nation.charges, Config.Tutorial.GiftCharges)
	end
end

-- A command the player sent (ok = the server carried it out). Commands done ahead of their prompt still count.
function Tutorial.recordCommand(tut: TutorialState, command: Types.Command, ok: boolean)
	if ok then
		tut.actions[command.kind] = true
	end
end

-- After a tick: move on to the next prompt once this one is done (one prompt per tick). Returns the new step
-- number when it changed (#STEPS + 1 = finished).
function Tutorial.update(state: MatchState, tut: TutorialState): number?
	local nation = state.nations[tut.slot]
	if tut.skipped or Tutorial.finished(tut) or state.result ~= nil then
		return nil
	end
	if nation == nil or nation.eliminated or nation.userId == nil then
		return nil -- nobody playing it yet
	end
	-- keep the prompt's partner valid
	local step = Tutorial.stepName(tut)
	if step == "Ally" and (not living(state, tut.friend) or Diplomacy.atWar(state, tut.slot, tut.friend or 0)) then
		tut.friend = Tutorial.pickFriend(state, tut)
	elseif step == "War" and (not living(state, tut.rival) or Diplomacy.allied(state, tut.slot, tut.rival or 0)) then
		tut.rival = Tutorial.pickRival(state, tut)
	end
	if not Tutorial.stepDone(state, tut) then
		return nil
	end
	tut.step += 1
	if Tutorial.finished(tut) then
		tut.finishedAt = state.tick
	else
		enter(state, tut)
	end
	return tut.step
end

-- Should a public server send this player to the tutorial? Not once it was finished, skipped or played to the
-- end of its match, and not if they already played a match (a tutorial teleport that failed, an old save).
-- Private servers never send anyone (TutorialService): friends who joined one stay together.
function Tutorial.needed(profile: Types.PlayerProfile): boolean
	return not profile.tutorialDone and profile.stats.matches == 0
end

-- The player skips the tutorial: no more prompts.
function Tutorial.skip(tut: TutorialState)
	tut.skipped = true
end

-- The bots' part: every bot accepts an alliance the player offers it (when the rules allow). Returns the orders
-- to send through CommandRouter.
function Tutorial.botOrders(state: MatchState, tut: TutorialState): { Bot.Order }
	local orders: { Bot.Order } = {}
	for _, o in state.offers do
		local bot = state.nations[o.to]
		if
			o.kind == "Ally"
			and o.from == tut.slot
			and o.expiresAt > state.tick
			and bot
			and bot.controller == "Bot"
			and not bot.eliminated
		then
			local command: Types.Command = { kind = "Diplomacy", action = "AcceptAlly", target = tut.slot, gold = 0 }
			if Bot.check(state, o.to, command) then
				table.insert(orders, { nation = o.to, command = command })
			end
		end
	end
	return orders
end

-- Where the arrow points ------------------------------------------------------------------------------------

-- A neutral province to take or besiege: where one of the player's armies is already heading (or standing), or
-- else the neutral neighbour with the smallest garrison.
function Tutorial.neutralTarget(state: MatchState, me: number): number?
	for _, id in sortedKeys(state.armies) do
		local a = state.armies[id]
		if a.owner == me then
			local dest = if #a.path > 0 then a.path[#a.path] else a.location
			local p = state.provinces[dest]
			if p and p.owner == nil and p.terrain ~= "Mountain" then
				return dest
			end
		end
	end
	local garrison: { [number]: number } = {}
	for _, a in state.armies do
		if a.owner == 0 then
			garrison[a.location] = (garrison[a.location] or 0) + a.men
		end
	end
	local best: number?, bestMen = nil, math.huge
	for _, id in sortedKeys(state.provinces) do
		if state.provinces[id].owner == me then
			for _, n in state.provinces[id].neighbors do
				local p = state.provinces[n]
				local men = garrison[n] or 0
				if
					p
					and p.owner == nil
					and p.terrain ~= "Mountain"
					and (men < bestMen or (men == bestMen and n < (best or 0)))
				then
					best, bestMen = n, men
				end
			end
		end
	end
	return best
end

-- The player's capital, or any province they own.
local function home(state: MatchState, me: number): number?
	local capital = state.nations[me].capital
	if state.provinces[capital] and state.provinces[capital].owner == me then
		return capital
	end
	for _, id in sortedKeys(state.provinces) do
		if state.provinces[id].owner == me then
			return id
		end
	end
	return nil
end

-- What the player's client shows: the prompt, the nation it names and the province the arrow points at.
function Tutorial.view(state: MatchState, tut: TutorialState): Types.TutorialView
	local view: Types.TutorialView =
		{ step = tut.step, total = #Tutorial.STEPS, province = 0, nation = 0, canLeave = false }
	local me = tut.slot
	if tut.skipped then
		view.step = 0
		return view
	end
	if not living(state, me) then
		return view
	end
	local step = Tutorial.stepName(tut)
	if step == "Take" or step == "Siege" then
		view.province = Tutorial.neutralTarget(state, me) or 0
	elseif step == "Recruit" or step == "Power" then
		view.province = home(state, me) or 0
	elseif step == "Ally" or step == "War" then
		local partner = if step == "Ally" then tut.friend else tut.rival
		if partner and living(state, partner) then
			view.nation = partner
			view.province = nearestProvince(state, distances(state, me), partner) or 0
		end
	end
	return view
end

return Tutorial
