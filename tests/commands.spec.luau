--!strict
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local T = require("./TestKit")

local function fresh()
	local state = Match.new(Maps.get("skyshards"))
	return state, state.nations[1], state.provinces[state.nations[1].capital]
end

local function foreignProvince(state, nationId: number): number
	for id, p in state.provinces do
		if p.owner ~= nil and p.owner ~= nationId then
			return id
		end
	end
	error("no foreign province")
end

T.test("develop raises development and costs 30 x level", function()
	local state, nation, capital = fresh()
	nation.gold = 1000
	local level = capital.development
	local ok, err = Commands.apply(state, 1, { kind = "Develop", province = capital.id })
	T.expect(ok, err)
	T.equal(capital.development, level + 1)
	T.equal(nation.gold, 1000 - 30 * level)
end)

T.test("develop stops at the maximum", function()
	local state, nation, capital = fresh()
	nation.gold = 10000
	capital.development = Config.Economy.MaxDevelopment
	local ok, err = Commands.apply(state, 1, { kind = "Develop", province = capital.id })
	T.expect(not ok)
	T.equal(err, "MaxDevelopment")
end)

T.test("you can only act on your own provinces", function()
	local state, nation = fresh()
	nation.gold = 1000
	local target = foreignProvince(state, 1)
	local ok, err = Commands.apply(state, 1, { kind = "Develop", province = target })
	T.expect(not ok)
	T.equal(err, "NotYourProvince")
	local ok2, err2 = Commands.apply(state, 1, { kind = "Develop", province = 9999 })
	T.expect(not ok2)
	T.equal(err2, "UnknownProvince")
end)

T.test("not enough gold changes nothing", function()
	local state, nation, capital = fresh()
	nation.gold = 5
	local level = capital.development
	local ok, err = Commands.apply(state, 1, { kind = "Develop", province = capital.id })
	T.expect(not ok)
	T.equal(err, "NotEnoughGold")
	T.equal(nation.gold, 5)
	T.equal(capital.development, level)
end)

T.test("one building per province", function()
	local state, nation, capital = fresh()
	nation.gold = 1000
	local ok = Commands.apply(state, 1, { kind = "Build", province = capital.id, building = "Farm" })
	T.expect(ok)
	T.equal(capital.building, "Farm")
	T.equal(nation.gold, 950)
	local ok2, err2 = Commands.apply(state, 1, { kind = "Build", province = capital.id, building = "Fort" })
	T.expect(not ok2)
	T.equal(err2, "AlreadyBuilt")
	T.equal(nation.gold, 950)
end)

T.test("building None is rejected", function()
	local state, nation, capital = fresh()
	nation.gold = 1000
	local ok, err = Commands.apply(state, 1, { kind = "Build", province = capital.id, building = "None" })
	T.expect(not ok)
	T.equal(err, "BadBuilding")
end)

T.test("recruit spends gold and manpower and merges into one army", function()
	local state, nation, capital = fresh()
	nation.gold, nation.manpower = 1000, 10000
	T.expect((Commands.apply(state, 1, { kind = "Recruit", province = capital.id, regiments = 2 })))
	T.expect((Commands.apply(state, 1, { kind = "Recruit", province = capital.id, regiments = 3 })))
	T.equal(nation.gold, 1000 - 50)
	T.equal(nation.manpower, 10000 - 5000)
	local armies = 0
	for _, a in state.armies do
		armies += 1
		T.equal(a.owner, 1)
		T.equal(a.location, capital.id)
		T.equal(a.men, 5000)
	end
	T.equal(armies, 1)
end)

T.test("recruit checks the amount and manpower", function()
	local state, nation, capital = fresh()
	nation.gold, nation.manpower = 1000, 1500
	for _, bad in { 0, -1, 1.5, Config.Army.MaxRecruitPerCommand + 1 } do
		local ok, err = Commands.apply(state, 1, { kind = "Recruit", province = capital.id, regiments = bad })
		T.expect(not ok, "accepted " .. bad)
		T.equal(err, "BadAmount")
	end
	local ok, err = Commands.apply(state, 1, { kind = "Recruit", province = capital.id, regiments = 2 })
	T.expect(not ok)
	T.equal(err, "NotEnoughManpower")
	T.equal(nation.gold, 1000)
end)

T.test("nothing happens during Results or for an eliminated nation", function()
	local state, nation, capital = fresh()
	nation.gold = 1000
	state.phase = "Results"
	local ok, err = Commands.apply(state, 1, { kind = "Develop", province = capital.id })
	T.expect(not ok)
	T.equal(err, "WrongPhase")
	state.phase = "War"
	nation.eliminated = true
	local ok2, err2 = Commands.apply(state, 1, { kind = "Develop", province = capital.id })
	T.expect(not ok2)
	T.equal(err2, "NoNation")
end)

T.test("debt blocks spending", function()
	local state, nation, capital = fresh()
	nation.gold = -3
	local ok, err = Commands.apply(state, 1, { kind = "Build", province = capital.id, building = "Barracks" })
	T.expect(not ok)
	T.equal(err, "NotEnoughGold")
end)

T.finish()
