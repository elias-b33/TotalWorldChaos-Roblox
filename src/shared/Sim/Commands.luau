--!strict
-- Applies one intent for one nation, after checking every rule. Players and bots both come through here
-- (via CommandRouter), so an illegal move is impossible no matter who asks.
-- Returns true, or false plus a reason code the client turns into a short message.

local Army = require("./Army")
local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Economy = require("./Economy")
local Movement = require("./Movement")
local Primordial = require("./Primordial")
local Troops = require("./Troops")
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
	local nation = state.nations[nationId]
	local cost = Economy.buildingCost(building, nation.race) -- a Hills race pays less for a fort
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
	if nation.gold < cost then
		return false, "NotEnoughGold"
	end
	nation.gold -= cost
	province.building = building
	return true, nil
end

-- Regiments of one troop type: the shared roles for everyone, an elite only for the races whose elite it is
-- (WrongRace).
local function recruit(
	state: MatchState,
	nationId: number,
	provinceId: number,
	regiments: number,
	troop: Types.Troop
): (boolean, string?)
	if regiments ~= math.floor(regiments) or regiments < 1 or regiments > Config.Army.MaxRecruitPerCommand then
		return false, "BadAmount"
	end
	if not Troops.isTroop(troop) then
		return false, "BadTroop"
	end
	local province, err = ownedProvince(state, nationId, provinceId)
	if province == nil then
		return false, err
	end
	local nation = state.nations[nationId]
	if not Troops.canRecruit(nation.race, troop) then
		return false, "WrongRace"
	end
	local gold, manpower = Economy.recruitCost(regiments, troop)
	if nation.gold < gold then
		return false, "NotEnoughGold"
	end
	if nation.manpower < manpower then
		return false, "NotEnoughManpower"
	end
	nation.gold -= gold
	nation.manpower -= manpower
	Army.reinforce(state, nationId, provinceId, regiments * Config.Army.MenPerRegiment, troop)
	return true, nil
end

function Commands.apply(state: MatchState, nationId: number, command: Command): (boolean, string?)
	local nation = state.nations[nationId]
	if nation == nil or nation.eliminated then
		return false, "NoNation"
	end
	if state.phase == "Results" then
		return false, "MatchOver"
	elseif not ACTIVE_PHASES[state.phase] then
		return false, "WrongPhase"
	end
	if command.kind == "Develop" then
		return develop(state, nationId, command.province)
	elseif command.kind == "Build" then
		return build(state, nationId, command.province, command.building)
	elseif command.kind == "Recruit" then
		return recruit(state, nationId, command.province, command.regiments, command.troop)
	elseif command.kind == "Move" then
		return Movement.order(state, nationId, command.army, command.to)
	elseif command.kind == "Power" then
		return Primordial.use(state, { nation = nationId }, command.power, command.target)
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
		elseif action == "Insult" then
			return Diplomacy.insult(state, nationId, command.target)
		elseif action == "InsultBack" then
			return Diplomacy.insultBack(state, nationId, command.target)
		elseif action == "LaughOff" then
			return Diplomacy.laughOff(state, nationId, command.target)
		elseif action == "Gift" then
			return Diplomacy.gift(state, nationId, command.target)
		elseif action == "Access" then
			return Diplomacy.propose(state, "Access", nationId, command.target, 0)
		elseif action == "AcceptAccess" then
			return Diplomacy.accept(state, "Access", nationId, command.target)
		end
	end
	return false, "UnknownCommand"
end

-- An eliminated player's Primordial: powers are the only thing it can do.
function Commands.applyPrimordial(state: MatchState, userId: number, command: Command): (boolean, string?)
	if state.primordials[userId] == nil then
		return false, "NoNation"
	end
	if command.kind ~= "Power" then
		return false, "Primordial"
	end
	return Primordial.use(state, { userId = userId }, command.power, command.target)
end

-- Who acts on a queued command (CommandRouter, tick order step 1).
-- A bot (userId nil) acts for its nation while a bot still runs it: once a player has taken the nation over, a
-- bot command still in the queue is refused (bots get no reply, so it is dropped silently). A player (userId set; nationId is the nation they hold, if any) acts
-- for their living nation, or as their Primordial once it is eliminated. Anyone else is spectating.
function Commands.applyFor(state: MatchState, userId: number?, nationId: number?, command: Command): (boolean, string?)
	local nation = if nationId then state.nations[nationId] else nil
	if nationId and nation and not nation.eliminated then
		local mine = if userId then nation.userId == userId else nation.controller == "Bot" and nation.userId == nil
		if mine then
			return Commands.apply(state, nationId, command)
		end
	end
	if userId and state.primordials[userId] then
		return Commands.applyPrimordial(state, userId, command)
	end
	return false, "NoNation"
end

return Commands
