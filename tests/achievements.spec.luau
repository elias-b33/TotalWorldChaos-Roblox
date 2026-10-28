--!strict
-- Achievements (docs/MONETIZATION.md 5.6): 30 one-time goals, each paying Glory, a title or a cosmetic once.
local Achievements = require("../src/shared/Sim/Achievements")
local Army = require("../src/shared/Sim/Army")
local Catalogue = require("../src/shared/Catalogue")
local Commands = require("../src/shared/Sim/Commands")
local Config = require("../src/shared/Config")
local Diplomacy = require("../src/shared/Sim/Diplomacy")
local Events = require("../src/shared/Sim/Events")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Progression = require("../src/shared/Sim/Progression")
local Shop = require("../src/shared/Sim/Shop")
local T = require("./TestKit")
local Types = require("../src/shared/Types")

local A = Config.Achievements
local ALICE, BOB = 101, 102

-- A match on `mapId` with Alice on nation 1 and Bob on nation 2.
local function match(mapId: string?): Types.MatchState
	local state = Match.new(Maps.get(mapId or "skyshards"))
	Match.seatPlayer(state, ALICE)
	Match.seatPlayer(state, BOB)
	state.tick = Config.Phases.PeaceEndTick + 10
	state.phase = "War"
	return state
end

-- The match is over: `winners` won (by `kind`).
local function finish(state: Types.MatchState, winners: { number }, kind: ("Domination" | "Alliance" | "Score")?)
	state.tick = Config.Phases.MatchEndTick
	state.phase = "Results"
	state.result = { kind = kind or "Score", winners = winners, scores = {}, endedAt = state.tick }
end

local function stats(userId: number?): Types.PlayerMatchStats
	local s = Progression.newStats(userId or ALICE, 0)
	s.seated = true
	return s
end

-- Stayed to Results with a nation, this placement.
local function reward(placement: number?, afk: boolean?): Types.MatchReward
	return { xp = 0, glory = 0, lines = {}, placement = placement, stayed = true, afk = afk == true }
end

local function check(state, profile, s, r, standard: boolean?): ({ string }, number)
	return Achievements.check(state, profile, s, r, standard ~= false)
end

T.test("30 achievements, each with a unique id and name, a known stat and a real reward", function()
	T.equal(#A.List, 30)
	local ids, names = {}, {}
	local matchStats = Achievements.tally(match(), stats(), reward(5), true)
	for _, def in Achievements.LIST do
		T.expect(ids[def.id] == nil, "unique id " .. def.id)
		T.expect(names[def.name] == nil, "unique name " .. def.name)
		ids[def.id], names[def.name] = true, true
		local known = matchStats[def.stat] ~= nil
			or def.kind == "Lifetime" and def.stat ~= "" and (def.stat == "Level" or string.sub(def.stat, 1, 4) == "Life")
			or def.kind == "Maps"
		T.expect(known, def.id .. " counts a known stat")
		T.expect(def.target >= 1, def.id .. " has a target")
		T.expect(def.glory >= 0 and def.glory <= 500, def.id .. " pays 0-500 Glory")
		T.expect(def.glory > 0 or def.title ~= nil or def.item ~= nil, def.id .. " pays something")
		for _, id in { def.title, def.item } do
			local item = Catalogue.item(id :: string)
			T.expect(id == nil or (item ~= nil and item.earned == true), def.id .. " gives an earned catalogue item")
		end
		if def.title then
			T.equal((Catalogue.item(def.title) :: Types.CatalogueItem).slot, "Title")
		end
	end
	-- the examples the doc names
	T.equal((Achievements.def("first_blood") :: Types.AchievementDef).glory, 50)
	T.equal((Achievements.def("comeback") :: Types.AchievementDef).title, "title_unbroken")
	T.equal((Catalogue.item("frame_centurion") :: Types.CatalogueItem).rarity, "Epic")
	T.equal((Catalogue.item("token_world_shaker") :: Types.CatalogueItem).rarity, "Legendary")
	T.equal((Catalogue.item("fx_meteor_storm") :: Types.CatalogueItem).rarity, "Rare")
end)

T.test("First Blood: a won battle pays 50 Glory once", function()
	local profile = Progression.newProfile()
	local state = match()
	finish(state, { 3 })
	local s = stats()
	s.battlesWon = 1
	local earned, glory = check(state, profile, s, reward(4))
	T.expect(table.find(earned, "first_blood") ~= nil, "earned")
	T.equal(glory, profile.glory)
	T.expect(glory >= 50)
	T.expect(Achievements.isDone(profile, "first_blood"))
	local before = profile.glory
	local again = check(match(), profile, stats(), reward(4))
	T.expect(table.find(again, "first_blood") == nil, "never earned twice")
	local s2 = stats()
	s2.battlesWon = 5
	finish(state, { 3 })
	local later = check(state, profile, s2, reward(4))
	T.expect(table.find(later, "first_blood") == nil and profile.glory == before, "never paid twice")
end)

T.test("an AFK match counts nothing", function()
	local profile = Progression.newProfile()
	local s = stats()
	s.battlesWon = 3
	local earned, glory = check(match(), profile, s, reward(1, true))
	T.equal(#earned, 0)
	T.equal(glory, 0)
	T.equal(profile.achievements.first_blood, nil)
end)

T.test("Best keeps the best match; Sum adds matches up and a leave then Results counts once", function()
	local profile = Progression.newProfile()
	local s = stats()
	s.battlesWon = 4
	check(match(), profile, s, reward(5))
	T.equal(profile.achievements.general, 4, "General: 4 of 10 battles in one match")
	local s2 = stats()
	s2.battlesWon = 2
	check(match(), profile, s2, reward(5))
	T.equal(profile.achievements.general, 4, "a worse match doesn't lower it")

	local s3 = stats()
	s3.feats.meteorKills = 12000
	local r = reward(nil)
	r.stayed = false -- left early
	check(match(), profile, s3, r)
	T.equal(profile.achievements.meteorologist, 12000)
	s3.feats.meteorKills = 15000 -- came back, killed 3,000 more, stayed to Results
	check(match(), profile, s3, reward(6))
	T.equal(profile.achievements.meteorologist, 15000, "the leave's 12,000 counted once")
	local s4 = stats()
	s4.feats.meteorKills = 9000
	local earned = check(match(), profile, s4, reward(6))
	T.equal(profile.achievements.meteorologist, 20000, "capped at the target")
	T.expect(table.find(earned, "meteorologist") ~= nil, "Meteorologist after 20,000 men")
	T.expect(Shop.owns(profile, "fx_meteor_storm", false), "pays the Rare meteor effect")
	local ok = Shop.equip(profile, "fx_meteor_storm", false)
	T.expect(ok, "which can be equipped")
end)

T.test("lifetime achievements read the profile: Centurion's frame, World Shaker's token", function()
	local profile = Progression.newProfile()
	profile.stats.matches = 99
	local earned = check(match(), profile, stats(), reward(7))
	T.expect(table.find(earned, "veteran") ~= nil and table.find(earned, "seasoned") ~= nil, "10 and 50 matches")
	T.equal(profile.achievements.centurion, 99)
	T.expect(not Shop.owns(profile, "frame_centurion", false))
	profile.stats.matches = 100
	earned = check(match(), profile, stats(), reward(7))
	T.equal(#earned, 1)
	T.equal(earned[1], "centurion", "Centurion at 100 matches")
	T.expect(Shop.owns(profile, "frame_centurion", false), "the Epic frame")
	profile.xp = Progression.totalXpFor(90)
	profile.level = 90
	earned = check(match(), profile, stats(), reward(7))
	T.expect(table.find(earned, "world_shaker") ~= nil, "World Shaker at level 90")
	T.expect(Shop.owns(profile, "token_world_shaker", false), "the Legendary token")
	T.expect(not Shop.buyWithGlory(profile, "token_world_shaker", false), "never sold")
end)

T.test("Cartographer: a win on each of the three maps", function()
	local profile = Progression.newProfile()
	for i, mapId in { "earth", "earth", "eldmoor" } do
		local state = match(mapId)
		finish(state, { 1 })
		check(state, profile, stats(), reward(1))
		T.equal(
			Achievements.progressOf(Achievements.def("cartographer") :: any, profile.achievements.cartographer),
			if i < 3 then 1 else 2
		)
	end
	local lost = match("skyshards")
	finish(lost, { 2 })
	check(lost, profile, stats(), reward(2))
	T.expect(not Achievements.isDone(profile, "cartographer"), "a loss on the third map doesn't count")
	local won = match("skyshards")
	finish(won, { 1 })
	local earned = check(won, profile, stats(), reward(1))
	T.expect(table.find(earned, "cartographer") ~= nil, "earned on the third map")
	T.expect(profile.owned.title_cartographer == true, "with its title")
end)

T.test("Domination pays a title; a private match with custom rules counts no win-type stats", function()
	local custom = Progression.newProfile()
	local state = match()
	finish(state, { 1 }, "Domination")
	local earned = check(state, custom, stats(), reward(1), false)
	T.expect(table.find(earned, "domination") == nil, "custom rules: no Domination")
	T.expect(table.find(earned, "podium") ~= nil, "but a top-3 finish still counts (like quests)")

	local profile = Progression.newProfile()
	earned = check(state, profile, stats(), reward(1))
	T.expect(table.find(earned, "domination") ~= nil, "Domination")
	T.expect(profile.owned.title_dominant == true, "the Dominant")
	T.expect(Shop.equip(profile, "title_dominant", false), "titles equip like a cosmetic")
	T.equal(Shop.cosmeticsOf(profile, false, 1).title, "title_dominant", "and show on the nation")
	T.equal(Shop.cosmeticsOf(Progression.newProfile(), false, 1).title, nil, "no title by default")
	T.expect(not Shop.equip(profile, "title_unbroken", false), "only owned titles")
end)

T.test("a late joiner's placement counts for nothing: no win, no top 3", function()
	local state = match()
	finish(state, { 1 }, "Domination")
	local late = reward(1)
	late.share = Config.Progression.PlacementMinShare - 0.01
	local earned = check(state, Progression.newProfile(), stats(), late)
	T.expect(table.find(earned, "domination") == nil, "no Domination")
	T.expect(table.find(earned, "podium") == nil, "no top 3")
	late.share = Config.Progression.PlacementMinShare
	earned = check(state, Progression.newProfile(), stats(), late)
	T.expect(table.find(earned, "domination") ~= nil, "half the match owns the win")
end)

T.test("an alliance victory, Comeback and Kingmaker", function()
	local profile = Progression.newProfile()
	local state = match()
	finish(state, { 1, 2 }, "Alliance")
	local s = stats()
	s.feats.lowAtCheck = true
	local earned = check(state, profile, s, reward(1))
	T.expect(table.find(earned, "better_together") ~= nil, "Better Together")
	T.expect(table.find(earned, "comeback") ~= nil and profile.owned.title_unbroken, "Comeback, the Unbroken")

	-- Bob rose as a Primordial; his old ally Alice wins
	local bobProfile = Progression.newProfile()
	state.primordials[BOB] = { userId = BOB, charges = 0, chargeTicks = 0 }
	local bob = stats(BOB)
	bob.feats.allies = { 1 }
	earned = check(state, bobProfile, bob, reward(nil))
	T.expect(table.find(earned, "kingmaker") ~= nil, "Kingmaker")
	T.expect(table.find(earned, "risen") ~= nil, "Risen")
	local stranger = stats(BOB)
	stranger.feats.allies = { 5 }
	T.expect(
		table.find(check(state, Progression.newProfile(), stranger, reward(nil)), "kingmaker") == nil,
		"not without an ally winning"
	)
end)

T.test("observe: neutral land in Peace, Meteor kills, forts that held, allies and the bottom 3 at 10:00", function()
	local state = match()
	local byUser = { [ALICE] = stats(ALICE), [BOB] = stats(BOB) }
	local feats = byUser[ALICE].feats
	state.phase = "Peace"
	state.tick = 50
	Events.push(state, "ProvinceTaken", 1, 0, 7)
	Events.push(state, "ProvinceTaken", 1, 3, 8) -- not neutral
	Achievements.observe(state, byUser)
	T.equal(feats.peaceNeutral, 1)
	state.events = {}
	state.phase = "War"
	Events.push(state, "ProvinceTaken", 1, 0, 9)
	Achievements.observe(state, byUser)
	T.equal(feats.peaceNeutral, 1, "War captures don't count")
	T.equal(feats.lowAtCheck, nil, "not checked before 10:00")

	-- a real Meteor names the men it killed
	state.events = {}
	state.nations[1].charges = 5
	local target
	for id, p in state.provinces do
		if p.owner == 3 and not p.isCapital then
			target = id
		end
	end
	local army = Army.spawn(state, 3, target, 4000)
	local ok, err = Commands.apply(state, 1, { kind = "Power", power = "Meteor", target = army.id })
	T.expect(ok, err)
	T.equal(state.events[#state.events].men, 2000)
	Achievements.observe(state, byUser)
	T.equal(feats.meteorKills, 2000)

	-- a fort of Alice's besieged, then the siege ends with the fort still hers
	state.events = {}
	local fort
	for id, p in state.provinces do
		if p.owner == 1 and not p.isCapital then
			fort = id
		end
	end
	local province = state.provinces[fort]
	province.building = "Fort"
	province.siege = { by = 3, progress = 1, required = 60, lastTick = state.tick }
	Achievements.observe(state, byUser)
	T.equal(feats.fortHolds, 0)
	province.siege = nil
	Achievements.observe(state, byUser)
	T.equal(feats.fortHolds, 1, "one siege held")
	province.siege = { by = 3, progress = 1, required = 60, lastTick = state.tick }
	Achievements.observe(state, byUser)
	province.owner = 3
	province.siege = nil
	Achievements.observe(state, byUser)
	T.equal(feats.fortHolds, 1, "a fort that fell doesn't count")

	-- allies, then the 10:00 check: Alice holds the least land of the nations still in
	T.expect((Diplomacy.ally(state, 1, 2)))
	Achievements.observe(state, byUser)
	T.equal(feats.allies[1], 2)
	for id, p in state.provinces do
		if p.owner == 1 and id ~= state.nations[1].capital then
			p.owner = 4
		end
	end
	state.tick = A.ComebackTick
	Achievements.observe(state, byUser)
	T.equal(feats.lowAtCheck, true, "Alice was in the bottom 3 at 10:00")
	T.equal(byUser[BOB].feats.lowAtCheck, false)
	state.nations[1].eliminated = true
	Achievements.observe(state, byUser)
	T.equal(feats.allies[1], 2, "allies stay as they were when Alice's nation fell")
end)

T.test("the view shows progress (capped), rewards and the titles owned", function()
	local profile = Progression.newProfile()
	profile.achievements.general = 4
	profile.achievements.cartographer = 1 + 4 -- earth and skyshards
	profile.owned.title_champion = true
	local view = Achievements.view(profile, "title_champion", { "general" })
	T.equal(#view.list, 30)
	for _, a in view.list do
		if a.id == "general" then
			T.equal(a.progress, 4)
			T.equal(a.target, 10)
			T.equal(a.done, false)
		elseif a.id == "cartographer" then
			T.equal(a.progress, 2, "two maps")
		end
	end
	T.equal(view.titles[1], "title_champion")
	T.equal(view.title, "title_champion")
	profile.owned.title_s1_veteran = true -- a season-pass title is listed with the achievements' ones
	T.expect(table.find(Achievements.view(profile, "title_none").titles, "title_s1_veteran") ~= nil, "season title")
	T.equal(view.recent[1], "general")
end)

T.finish()
