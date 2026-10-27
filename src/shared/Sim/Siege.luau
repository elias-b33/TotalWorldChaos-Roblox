--!strict
-- Sieges (tick order step 4): an army standing alone in an enemy or neutral province besieges it for
-- TicksPerDevelopment × development ticks, ×2 with a fort, ×3 for a capital. Then the province flips.

local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Events = require("./Events")
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

function Siege.step(state: MatchState)
	local here: { [number]: { Types.Army } } = {}
	local ids = {}
	for id in state.armies do
		table.insert(ids, id)
	end
	table.sort(ids)
	for _, id in ids do
		local a = state.armies[id]
		here[a.location] = here[a.location] or {}
		table.insert(here[a.location], a)
	end

	for provinceId, province in state.provinces do
		local armies = here[provinceId] or {}
		local leader: number? = nil
		local blocked = false
		for _, a in armies do
			local hostileToOwner = province.owner == nil or Diplomacy.atWar(state, a.owner, province.owner)
			local defending = province.owner ~= nil and Diplomacy.friendly(state, a.owner, province.owner)
			if a.inBattle or a.owner == 0 or defending then
				blocked = true -- a fight, a neutral garrison or the owner's own army holds the province
			elseif #a.path == 0 and hostileToOwner then
				if leader == nil then
					leader = a.owner
				elseif not Diplomacy.friendly(state, leader, a.owner) then
					blocked = true -- two rival besiegers: nobody makes progress
				end
			end
		end
		if leader == nil or blocked then
			province.siege = nil
		elseif province.shieldUntil and province.shieldUntil > state.tick then
			-- Divine shield: the siege waits
			if province.siege and province.siege.by ~= leader then
				province.siege = nil
			end
		else
			local current = province.siege
			local siege = if current and current.by == leader
				then current
				else { by = leader, progress = 0, required = Siege.required(province) }
			province.siege = siege
			siege.progress += 1
			if siege.progress >= siege.required then
				local old = province.owner
				province.owner = leader
				province.siege = nil
				Events.push(state, "ProvinceTaken", leader, old or 0, provinceId)
			end
		end
	end
end

return Siege
