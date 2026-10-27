--!strict
-- Applies one intent for one nation, after checking every rule. Players and bots both come through here
-- (via CommandRouter), so an illegal move is impossible no matter who asks.
-- Returns true, or false plus a reason code the client turns into a short message.

local Army = require("./Army")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Economy = require("./Economy")
local Movement = require("./Movement")
local Types = require("../Types")

type MatchState = Types.MatchState
type Command = Types.Command

local ACTIVE_PHASES = { Peace = true, War = true, Cataclysm = true }

local Commands = {}

local function ownedProvince(state: MatchState, nationId: number, provinceId: number): (Types.Province?, string?)
	local province = state.provinces[provinceId]
	if province == nil then
		return nil, "UnknownProvince"
	end
	if province.owner ~= nationId then
		return nil, "NotYourProvince"
	end
	return province, nil
end

local function develop(state: MatchState, nationId: number, provinceId: number): (boolean, string?)
	local province, err = ownedProvince(state, nationId, provinceId)
	if province == nil then
		return false, err
	end
	if province.development >= Config.Economy.MaxDevelopment then
		return false, "MaxDevelopment"
	end
	local nation = state.nations[nationId]
	local cost = Economy.developCost(province.development)
	if nation.gold < cost then
		return false, "NotEnoughGold"
	end
	nation.gold -= cost
	province.development += 1
	return true, nil
end

local function build(
	state: MatchState,
	nationId: number,
	provinceId: number,
	building: Types.Building
): (boolean, string?)
	local cost = Economy.buildingCost(building)
	if cost == nil then
		return false, "BadBuilding"
	end
	local province, err = ownedProvince(state, nationId, provinceId)
	if province == nil then
		return false, err
	end
	if province.building ~= "None" then
		return false, "AlreadyBuilt"
	end
	local nation = state.nations[nationId]
	if nation.gold < cost then
		return false, "NotEnoughGold"
	end
	nation.gold -= cost
	province.building = building
	return true, nil
end

local function recruit(state: MatchState, nationId: number, provinceId: number, regiments: number): (boolean, string?)
	if regiments ~= math.floor(regiments) or regiments < 1 or regiments > Config.Army.MaxRecruitPerCommand then
		return false, "BadAmount"
	end
	local province, err = ownedProvince(state, nationId, provinceId)
	if province == nil then
		return false, err
	end
	local nation = state.nations[nationId]
	local gold, manpower = Economy.recruitCost(regiments)
	if nation.gold < gold then
		return false, "NotEnoughGold"
	end
	if nation.manpower < manpower then
		return false, "NotEnoughManpower"
	end
	nation.gold -= gold
	nation.manpower -= manpower
	Army.reinforce(state, nationId, provinceId, regiments * Config.Army.MenPerRegiment)
	return true, nil
end

function Commands.apply(state: MatchState, nationId: number, command: Command): (boolean, string?)
	local nation = state.nations[nationId]
	if nation == nil or nation.eliminated then
		return false, "NoNation"
	end
	if not ACTIVE_PHASES[state.phase] then
		return false, "WrongPhase"
	end
	if command.kind == "Develop" then
		return develop(state, nationId, command.province)
	elseif command.kind == "Build" then
		return build(state, nationId, command.province, command.building)
	elseif command.kind == "Recruit" then
		return recruit(state, nationId, command.province, command.regiments)
	elseif command.kind == "Move" then
		return Movement.order(state, nationId, command.army, command.to)
	elseif command.kind == "Diplomacy" then
		local action = command.action
		if action == "War" then
			return Diplomacy.declareWar(state, nationId, command.target)
		elseif action == "Ally" then
			return Diplomacy.propose(state, "Ally", nationId, command.target, 0)
		elseif action == "Peace" then
			return Diplomacy.propose(state, "Peace", nationId, command.target, command.gold)
		elseif action == "AcceptAlly" then
			return Diplomacy.accept(state, "Ally", nationId, command.target)
		elseif action == "AcceptPeace" then
			return Diplomacy.accept(state, "Peace", nationId, command.target)
		end
	end
	return false, "UnknownCommand"
end

return Commands
