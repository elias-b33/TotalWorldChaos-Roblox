--!strict
-- Sieges (tick order step 4): an army standing alone in an enemy or neutral province besieges it for
-- TicksPerDevelopment × development ticks, ×2 with a fort, ×3 for a capital. Then the province flips.
-- Rebels (a neutral army standing in a nation's province) besiege it too; it turns neutral when they finish.
-- One siege per province: whoever started it keeps it while one of its armies (or an ally's) stands there; a rival
-- besieger at peace with it waits instead of blocking. An interrupted siege (a battle, a defender, the besieger
-- leaving) keeps its progress for Config.Siege.GraceTicks, then resets. Retreating armies are ignored.
-- Army size doesn't matter, but troops do: while an army with a siege troop in it (Catapults, Sappers, Artillery)
-- besieges (the holder's or an ally's), the siege moves that troop's Config.Troops siegeSpeed times as fast. A
-- province the besieger's side blockades from the sea (Sim.Navy) falls Config.Navy.BlockadeSiegeSpeed times as fast
-- on top of that.

local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Events = require("./Events")
local Troops = require("./Troops")
local Types = require("../Types")

type MatchState = Types.MatchState
type Province = Types.Province

local Siege = {}

function Siege.required(province: Province): number
	local t = Config.Siege.TicksPerDevelopment * province.development
	if province.building == "Fort" then
		t *= Config.Buildings.Fort.siegeMultiplier
	end
	if province.isCapital then
		t *= Config.Siege.CapitalMultiplier
	end
	return t
end

-- A siege only lasts while its holder may still besiege the province (peace or a flip ends it at once).
local function stillValid(state: MatchState, province: Province, by: number): boolean
	if by == 0 then
		return province.owner ~= nil -- Rebels only besiege a nation's land
	end
	return province.owner == nil or Diplomacy.atWar(state, by, province.owner)
end

function Siege.step(state: MatchState)
	local here: { [number]: { Types.Army } } = {}
	local ids = {}
	for id in state.armies do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local a = state.armies[id]
		if not a.retreating then
			here[a.location] = here[a.location] or {}
			table.insert(here[a.location], a)
		end
	end

	for provinceId, province in state.provinces do
		local besiegers: { number } = {} -- owners of armies standing here that may besiege it, in army id order
		local besieging: { Types.Army } = {} -- those armies
		local blocked = false
		for _, a in here[provinceId] or {} do
			local hostileToOwner = province.owner == nil or Diplomacy.atWar(state, a.owner, province.owner)
			local defending = province.owner ~= nil and Diplomacy.friendly(state, a.owner, province.owner)
			local rebels = a.owner == 0 and province.owner ~= nil -- Rebels besiege the province they rose in
			if a.inBattle or (a.owner == 0 and not rebels) or defending then
				blocked = true -- a fight, a neutral garrison or the owner's own army holds the province
			elseif #a.path == 0 and (hostileToOwner or rebels) then
				table.insert(besiegers, a.owner)
				table.insert(besieging, a)
			end
		end
		local current = province.siege
		if current and not stillValid(state, province, current.by) then
			province.siege = nil
			current = nil
		end
		-- the holder of the siege keeps it while it (or an ally) is here; otherwise the first besieger leads
		local leader: number? = nil
		if current then
			for _, owner in besiegers do
				if Diplomacy.friendly(state, current.by, owner) then
					leader = current.by
				end
			end
		end
		leader = leader or besiegers[1]
		local shielded = province.shieldUntil ~= nil and province.shieldUntil > state.tick
		if leader ~= nil and not blocked and not shielded then
			local siege = if current and current.by == leader
				then current
				else { by = leader, progress = 0, required = Siege.required(province), lastTick = state.tick }
			province.siege = siege
			-- siege troops besiege faster: the fastest army besieging with the leader sets the pace
			local speed = 1
			for _, a in besieging do
				if Diplomacy.friendly(state, leader, a.owner) then
					speed = math.max(speed, Troops.siegeSpeed(a.troops))
				end
			end
			-- and faster still where the leader's side blockades the province from the sea (Sim.Navy)
			local blockade = province.blockade
			if blockade ~= nil and Diplomacy.friendly(state, leader, blockade) then
				speed *= Config.Navy.BlockadeSiegeSpeed
			end
			siege.progress += speed
			siege.lastTick = state.tick
			if siege.progress >= siege.required then
				local old = province.owner
				province.owner = if leader == 0 then nil else leader -- Rebels leave neutral land behind
				province.siege = nil
				Events.push(state, "ProvinceTaken", leader, old or 0, provinceId)
			end
		elseif current then
			if shielded and leader == current.by and not blocked then
				current.lastTick = state.tick -- a Shield (Primordial power): the siege waits without losing progress
			elseif state.tick - current.lastTick > Config.Siege.GraceTicks then
				province.siege = nil -- interrupted for too long: progress is lost
			end
		end
	end
end

return Siege
