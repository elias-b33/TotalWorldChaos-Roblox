--!nocheck
-- Phase 5: the season pass and the rotating shop. Alice opens the season from the Lobby's ticket button, claims tier 1,
-- earns season XP in a match, claims free tiers from the Results screen, buys the pass (Studio test mode) and claims
-- the premium rewards it opens; then the shop's 🔄 Today tab on two days (DevDay), the same schedule any server
-- computes for those days.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	local ShopRotation = require("../../../src/shared/Sim/ShopRotation")
	local log = Emulator.analytics
	local pressIn = H.pressIn
	local function await(fn, ...)
		local args = table.pack(...)
		local result
		Emulator.task.spawn(function()
			result = table.pack(fn(table.unpack(args, 1, args.n)))
		end)
		local deadline = Emulator.now() + 10
		while result == nil and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		assert(result, "timed out")
		return table.unpack(result, 1, result.n)
	end
	-- a shared module as the server loaded it
	local function serverShared(path: string)
		local node = Emulator.server.dm:GetService("ReplicatedStorage").Shared
		for _, name in string.split(path, ".") do
			node = node:FindFirstChild(name)
		end
		return Emulator.server.modules[node]
	end
	local function funnel(name: string, userId: number): string
		local out = {}
		for _, r in log do
			if r.method == "LogFunnelStepEvent" and r.userId == userId and r.args[1] == name then
				table.insert(out, r.args[4])
			end
		end
		return table.concat(out, ",")
	end
	local LobbyService = H.server("Services.LobbyService")
	local Data = H.server("Services.PlayerDataService")
	local ShopService = H.server("Services.ShopService")
	local SeasonService = H.server("Services.SeasonService")
	local workspace = Emulator.server.dm:GetService("Workspace")

	-- Season 1 runs whatever the emulator's date (2023): the server's copy of it starts 3 days ago
	Emulator.run(1)
	local today = H.server("Services.DevService").today()
	local S1 = serverShared("Sim.Season").def("S1")
	S1.startDay, S1.endDay = today - 3, today + 53
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local player = alice.serverPlayer
	local SeasonState = H.client(alice, "SeasonState")
	local view = SeasonState.view()
	H.expect(view ~= nil and view.id == "S1" and view.tier == 1, "Alice is on Season 1, tier 1")
	H.expect(view.daysLeft == 52, "with 52 days left")
	H.expect(view.ready == 1, "tier 1's free reward is ready at once")
	-- a live server whose pass product id isn't set yet refuses the pass, and logs no prompt that never opened
	Emulator.studio = false
	local live, liveReason = await(ShopService.apply, player, { kind = "Buy", item = "season_pass", currency = "Robux" })
	Emulator.studio = true
	H.expect(live == false and liveReason == "NotForSale", "a live server without the pass product refuses it")
	H.expect(not string.find(funnel("SeasonPass", player.UserId), "purchase_prompted", 1, true), "and logs no purchase prompt")
	local lobbyButton
	for _, d in alice.localPlayer.PlayerGui:GetDescendants() do
		if d:IsA("TextButton") and d.Name == "SeasonButton" then
			lobbyButton = d
		end
	end
	H.expect(lobbyButton ~= nil and lobbyButton.Visible and H.iconOf(lobbyButton) == "ticket", "the Lobby shows the ticket button")
	H.shot(alice, "lobby_button")

	-- the season screen from the Lobby: both tracks, tier 1 to claim, the pass label before buying
	Emulator.press(alice, "SeasonButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Rise of the Primordials") ~= nil, "the season screen opens from the Lobby")
	H.expect(Emulator.findText(alice, "Pass rewards are only in this season") ~= nil, "pass rewards are labelled exclusive before buying")
	H.expect(Emulator.findText(alice, "Ember Knight") ~= nil, "the premium track shows its rewards")
	H.shot(alice, "season_screen")
	pressIn(alice, "Reward_F1", "Claim")
	Emulator.run(1)
	local data = Data.data(player)
	H.expect(data.owned.emote_gg == true and data.season.claimed.F1 == true, "Alice claimed tier 1: the GG emote")
	H.expect(H.iconOf(alice.localPlayer.PlayerGui:FindFirstChild("Reward_F1", true):FindFirstChild("Action")) == "check", "the cell shows it claimed")
	local again, why = await(SeasonService.apply, player, { kind = "Claim", tier = 1, track = "Free" })
	H.expect(again == false and why == "Claimed", "a second claim is refused")
	again, why = await(SeasonService.apply, player, { kind = "Claim", tier = 1, track = "Premium" })
	H.expect(again == false and why == "NeedPass", "the premium reward needs the pass")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- a match: its XP is season XP
	local deadline = Emulator.now() + 200
	while (LobbyService.active() or H.state().phase ~= "Peace" or H.myNation(alice) == 0) and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(1)
	H.expect(H.state().phase == "Peace" and H.myNation(alice) ~= 0, "a match started with Alice in it")
	local xp0, season0 = data.xp, data.season.xp
	local state = H.state()
	local A = H.myNation(alice)
	local nation = state.nations[A]
	nation.gold, nation.manpower = 300, 20000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	Emulator.press(alice, H.lineButton(alice))
	Emulator.run(1.2)
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" and not p.isCapital then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2.5)
	H.expect(state.result ~= nil and H.client(alice, "ProfileState").reward() ~= nil, "Alice won and got her reward")
	local earned = data.xp - xp0
	H.expect(earned > 0 and data.season.xp - season0 == earned, string.format("the match's %d XP is season XP too", earned))
	H.expect(SeasonState.view().xp == data.season.xp, "and her client knows")
	local resultsGui = alice.localPlayer.PlayerGui:FindFirstChild("Results")
	local seasonButton = resultsGui and resultsGui:FindFirstChild("SeasonButton", true)
	H.expect(seasonButton ~= nil and Emulator.findText(alice, seasonButton.Text) ~= nil and string.find(seasonButton.Text, "Season", 1, true) ~= nil, "the Results screen has a season button")
	H.shot(alice, "results")

	-- more play (two weeks' worth of XP), then the free tiers from the Results screen
	local Progression = serverShared("Sim.Progression")
	Data.update(player, function(d)
		Progression.addXp(d, 5 * 1200 - data.season.xp + 300, 0) -- tier 6
	end)
	SeasonService.sendView(player)
	Emulator.run(0.5)
	H.expect(SeasonState.view().tier == 6, "tier 6 after more play")
	Emulator.press(alice, "SeasonButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Tier 6") ~= nil, "the season screen opens from Results on tier 6")
	local glory0 = data.glory
	pressIn(alice, "Reward_F3", "Claim")
	Emulator.run(1)
	pressIn(alice, "Reward_F5", "Claim")
	Emulator.run(1)
	H.expect(data.glory == glory0 + 100, "tier 3 paid 100 Glory")
	H.expect(data.owned.flag_ember_sigil == true, "tier 5 gave the Ember Sigil flag")
	local passTag = alice.localPlayer.PlayerGui:FindFirstChild("Reward_P2", true):FindFirstChild("Action")
	H.expect(passTag.Text == "Pass" and H.iconOf(passTag) == "ticket", "premium cells ask for the pass")
	H.shot(alice, "free_claimed")

	-- the pass (Studio test mode: free, through the receipt path): every premium reward up to tier 6 opens at once
	H.expect(H.client(alice, "ShopState").view().robuxOpen, "Robux purchases are open on the Results screen")
	Emulator.press(alice, "BuyPass")
	Emulator.run(1.5)
	H.expect(data.season.premium == true, "Alice has the premium pass")
	H.expect(data.purchaseHistory[#data.purchaseHistory].item == "season_pass", "recorded in the purchase history")
	view = SeasonState.view()
	H.expect(view.premium and view.ready == 6, "premium tiers 1-6 are claimable at once")
	H.expect(H.textOf(alice, "PassStatus") == "Premium pass active", "the footer shows the pass")
	H.shot(alice, "pass_bought")
	Emulator.press(alice, "ClaimAll")
	Emulator.run(1)
	H.expect(data.owned.token_ember_knight and data.owned.flag_ember_banner and data.owned.frame_molten, "the premium rewards are Alice's")
	H.expect(SeasonState.view().ready == 0, "nothing left to claim")
	local ok, reason = await(ShopService.apply, player, { kind = "Buy", item = "season_bundle", currency = "Robux" })
	H.expect(ok == false and reason == "Owned", "the bundle can't be bought on top: no tier skips")
	H.shot(alice, "premium_claimed")
	for _ = 1, 3 do
		Emulator.press(alice, "Next")
	end
	Emulator.run(0.3)
	H.expect(Emulator.findText(alice, "4/") ~= nil, "page 4 (eight tiers a page on a phone, five on a 667 px one)")
	H.shot(alice, "season_page4")
	for _ = 1, 8 do -- to the last page (Next stops there)
		Emulator.press(alice, "Next")
	end
	Emulator.run(0.3)
	local function tier50(): boolean
		return Emulator.findText(alice, "Primordial Herald") ~= nil or Emulator.findText(alice, "Titan +3") ~= nil
	end
	local onLast = tier50()
	H.expect(Emulator.findText(alice, "every 2,400 XP") ~= nil, "the last page: the bonus reward")
	H.shot(alice, "season_last_page")
	if not onLast then -- five tiers a page (a 667 px phone): the bonus column has the last page to itself
		Emulator.press(alice, "Prev")
		Emulator.run(0.3)
	end
	H.expect(onLast or tier50(), "and tier 50")
	local steps = funnel("SeasonPass", player.UserId)
	H.expect(string.find(steps, "pass_viewed", 1, true) and string.find(steps, "purchase_prompted", 1, true) and string.find(steps, "purchase_completed", 1, true), "SeasonPass funnel: " .. steps)
	local tiers = 0
	for _, r in log do
		if r.method == "LogProgressionCompleteEvent" and r.args[1] == "SeasonTier" then
			tiers += 1
		end
	end
	H.expect(tiers >= 5, "SeasonTier progression events for the tiers passed")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the rotating shop: today's slots are the schedule every server computes for today
	local ShopUI = H.client(alice, "UI.Shop")
	local ShopState = H.client(alice, "ShopState")
	ShopUI.open("Today")
	Emulator.run(0.5)
	local rotation = ShopState.view().rotation
	local expected = ShopRotation.rotation(today)
	H.expect(rotation.day == today and table.concat(rotation.daily, ",") == table.concat(expected.daily, ","), "day 1's daily slots: " .. table.concat(rotation.daily, ", "))
	H.expect(table.concat(rotation.weekly, ",") == table.concat(expected.weekly, ","), "and the week's: " .. table.concat(rotation.weekly, ", "))
	for _, id in rotation.daily do
		H.expect(alice.localPlayer.PlayerGui:FindFirstChild("Card_" .. id, true) ~= nil, id .. " is on the Today tab")
	end
	local weeklyLine = Emulator.findText(alice, "Weekly · new in") ~= nil
	local paged = not weeklyLine and H.find(alice, "NextPage") ~= nil
	if paged then
		-- a small phone (VIEWPORT=667x375): the daily four and the weekly two get a page each
		H.shot(alice, "shop_day1")
		Emulator.press(alice, "NextPage")
		Emulator.run(0.3)
		weeklyLine = Emulator.findText(alice, "Weekly · new in") ~= nil
		H.shot(alice, "shop_day1_weekly")
		Emulator.press(alice, "PrevPage")
		Emulator.run(0.3)
	end
	H.expect(Emulator.findText(alice, "Daily · new items in") ~= nil and weeklyLine, "both sections say when they change")
	H.expect(Emulator.findText(alice, "Every item comes back within 60 days") ~= nil, "and that every item comes back")
	if not paged then
		H.shot(alice, "shop_day1")
	end
	Data.update(player, function(d)
		d.glory = 5000
	end)
	local offRare
	for _, id in ShopRotation.pools().Rare do
		if not ShopRotation.onSale(id, today) and not data.owned[id] then
			offRare = id
		end
	end
	ok, reason = await(ShopService.apply, player, { kind = "Buy", item = offRare, currency = "Glory" })
	H.expect(ok == false and reason == "NotInShop" and not data.owned[offRare], offRare .. " is not sold outside its days")
	local rare = rotation.daily[3]
	pressIn(alice, "Card_" .. rare, "BuyGlory", "medal")
	Emulator.run(1)
	H.expect(data.owned[rare] == true, "today's Rare (" .. rare .. ") bought for Glory")

	-- the next day (DevDay): new daily slots for everyone, the same as the schedule's
	workspace:SetAttribute("DevDay", 1)
	Emulator.run(7)
	rotation = ShopState.view().rotation
	expected = ShopRotation.rotation(today + 1)
	H.expect(rotation.day == today + 1, "the shop moved to the next day")
	H.expect(table.concat(rotation.daily, ",") == table.concat(expected.daily, ","), "day 2's daily slots: " .. table.concat(rotation.daily, ", "))
	H.expect(table.concat(rotation.daily, ",") ~= table.concat(ShopRotation.rotation(today).daily, ","), "different from day 1's")
	H.shot(alice, "shop_day2")
	Emulator.press(alice, "Tab_Offers")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Season Pass") ~= nil and Emulator.findText(alice, "See your pass") ~= nil, "the Offers tab has the season pass card")
	H.shot(alice, "shop_offers")
	Emulator.press(alice, "See your pass")
	Emulator.run(0.5)
	H.expect(H.client(alice, "UI.Season").isOpen() and not alice.localPlayer.PlayerGui.Shop.ShopPanel.Visible, "it opens the season screen")
	Emulator.press(alice, "✕")
	ShopUI.open("History")
	Emulator.run(0.5)
	H.expect(
		Emulator.findText(alice, "Season Pass") ~= nil and Emulator.findText(alice, "season_pass") == nil,
		"the purchase history names the pass, not its product id"
	)
	ShopUI.close()
	local saved = H.saved(player.UserId).Data
	H.expect(saved.season.premium and saved.season.claimed.P1 and saved.owned.token_ember_knight, "the pass and the claims are saved")
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	run = run,
}
