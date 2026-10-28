--!nocheck
-- Phase 4: the shop. In the Lobby Alice gets the starter-pack offer, opens the shop, buys a flag with Glory, fails
-- to buy one with too little Glory, buys an Epic flag, VIP, a token and an emote with Robux (Studio test mode:
-- product ids are 0), equips them, and checks the purchase history; a receipt processed twice grants once. In the
-- match everyone sees her flag on her capital and in the nations list, her token skin and her emote, and Robux
-- purchases are closed.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	local ROBUX = utf8.char(0xE002)
	-- press a button on one shop card (several cards show the same price)
	local pressIn = H.pressIn
	-- call a server function that may yield (saves) on the emulator's scheduler and wait for its answer
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
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local Data = H.server("Services.PlayerDataService")
	local ShopService = H.server("Services.ShopService")
	local ShopState = H.client(alice, "ShopState")
	local player = alice.serverPlayer
	H.expect(ShopState.view() ~= nil and ShopState.view().robuxOpen, "Alice's shop state arrived: Robux open in the Lobby")
	H.expect(ShopState.view().testMode, "product ids are 0: Studio test mode")
	Emulator.press(alice, "Card_skyshards")
	Emulator.press(alice, "Card_skyshards")

	-- a returning player with 3,000 Glory and two finished matches: the starter pack is offered once
	Data.update(player, function(data)
		data.glory = 3000
		data.stats.matches = 2
	end)
	ShopService.onPhase("Lobby")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "Starter Pack") ~= nil, "the starter-pack offer pops up after the 2nd match")
	H.expect(Emulator.findText(alice, "Bought separately: " .. ROBUX .. " 297") ~= nil, "with the real sum of its pieces")
	H.shot(alice, "starter_offer")
	Emulator.press(alice, "Not now")
	ShopService.onPhase("Lobby")
	Emulator.run(1)
	H.expect(Emulator.findText(alice, "Not now") == nil, "at most once per session")

	-- the shop: offers first
	Emulator.press(alice, "ShopButton")
	Emulator.run(0.5)
	H.expect(H.textOf(alice, "Glory") == "3,000" and H.iconShown(alice, "medal"), "the shop shows Alice's Glory")
	H.expect(Emulator.findText(alice, ROBUX .. " 249") ~= nil, "VIP shows its Robux price")
	H.shot(alice, "shop_offers")

	-- a flag for Glory
	Emulator.press(alice, "Tab_Flag")
	Emulator.run(0.5)
	H.shot(alice, "shop_flags")
	pressIn(alice, "Card_flag_sun", "1,200", "medal")
	Emulator.run(1)
	local data = Data.data(player)
	H.expect(data.owned.flag_sun == true and data.glory == 1800, "Rising Sun bought for 1,200 Glory")
	H.expect(H.textOf(alice, "Glory") == "1,800", "the shop shows the new balance")

	-- too little Glory for the Epic Comet: refused, nothing taken
	Emulator.press(alice, "NextPage")
	Emulator.run(0.3)
	pressIn(alice, "Card_flag_comet", "2,500", "medal")
	Emulator.run(1)
	H.expect(data.glory == 1800 and data.owned.flag_comet == nil, "a Glory purchase with too little Glory fails cleanly")
	H.expect(Emulator.findText(alice, "Not enough Glory") ~= nil, "and says why")

	-- the Comet with Robux (test mode): granted through the receipt path, once
	pressIn(alice, "Card_flag_comet", ROBUX .. " 149")
	Emulator.run(1.5)
	H.expect(data.owned.flag_comet == true, "the Comet was granted (test-mode Robux purchase)")
	H.expect(#data.purchaseHistory == 1 and data.purchaseHistory[1].item == "flag_comet", "and recorded in the history")
	local receipts = 0
	for _ in data.receipts do
		receipts += 1
	end
	H.expect(receipts == 1, "with one receipt in the ledger")
	pressIn(alice, "Card_flag_comet", "Equip")
	Emulator.run(1)
	H.expect(data.equipped.Flag == "flag_comet", "Alice equipped the Comet")
	H.expect(H.within(alice, "Card_flag_comet", "Equipped") and H.iconIn(alice, "Card_flag_comet", "check"), "the card says Equipped")
	H.shot(alice, "shop_flag_equipped")

	-- ProcessReceipt firing twice for one purchase grants once
	local receipt = { PurchaseId = "twice-1", PlayerId = player.UserId, ProductId = 0, CurrencySpent = 49 }
	local first = await(ShopService.receipt, receipt, "flag_cross")
	local second = await(ShopService.receipt, receipt, "flag_cross")
	local granted = Emulator.roblox.Enum.ProductPurchaseDecision.PurchaseGranted
	H.expect(first == granted and second == granted, "both calls answer PurchaseGranted")
	H.expect(#data.purchaseHistory == 2, "but the purchase was granted and recorded once")
	local saved = H.saved(player.UserId).Data
	H.expect(saved.receipts["twice-1"] ~= nil and saved.owned.flag_cross, "and saved before PurchaseGranted")
	local unknown = await(Emulator.processReceipt, { PurchaseId = "x", PlayerId = player.UserId, ProductId = 123, CurrencySpent = 1 })
	H.expect(unknown == Emulator.roblox.Enum.ProductPurchaseDecision.NotProcessedYet, "an unknown product is not granted")

	-- VIP (game pass, test mode): the VIP set and the gold frame
	Emulator.press(alice, "Tab_Offers")
	Emulator.run(0.3)
	pressIn(alice, "Card_vip", ROBUX .. " 249")
	Emulator.run(1.5)
	H.expect(ShopService.isVip(player), "Alice has VIP")
	H.expect(player:GetAttribute("Vip") == true, "her player carries the VIP attribute (chat tag)")
	H.expect(H.textOf(alice, "Vip") == "VIP" and H.iconShown(alice, "crown"), "the shop shows her VIP")

	-- a border for Glory, a token and an emote for Robux, all equipped
	Emulator.press(alice, "Tab_Border")
	Emulator.run(0.3)
	pressIn(alice, "Card_border_dashes", "1,200", "medal")
	Emulator.run(1)
	H.expect(data.owned.border_dashes and data.glory == 600, "Dashes border bought for Glory")
	pressIn(alice, "Card_border_dashes", "Equip")
	Emulator.run(1)
	Emulator.press(alice, "Tab_Token")
	Emulator.run(0.3)
	pressIn(alice, "Card_token_shield", ROBUX .. " 99")
	Emulator.run(1.5)
	pressIn(alice, "Card_token_shield", "Equip")
	Emulator.run(1)
	H.expect(data.equipped.Border == "border_dashes" and data.equipped.Token == "token_shield", "border and token equipped")
	Emulator.press(alice, "Tab_Emote")
	Emulator.run(0.3)
	pressIn(alice, "Card_emote_charge", ROBUX .. " 25")
	Emulator.run(1.5)
	H.expect(data.owned.emote_charge == true, "an emote bought")
	H.shot(alice, "shop_emotes")
	Emulator.press(alice, "Tab_History")
	Emulator.run(0.5)
	H.expect(Emulator.findText(alice, "Comet Flag") ~= nil, "Purchase History lists the Comet")
	H.expect(Emulator.findText(alice, "VIP") ~= nil, "and VIP")
	H.shot(alice, "shop_history")
	Emulator.press(alice, "✕")
	Emulator.run(0.3)

	-- the match: the vote and the draft run out, everyone gets a nation
	local LobbyService = H.server("Services.LobbyService")
	local deadline = Emulator.now() + 120
	while LobbyService.active() and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(2)
	local state = H.state()
	local A = H.myNation(alice)
	H.expect(state.phase == "Peace" and A ~= 0, "the match started and Alice has a nation")
	local mine
	for _, c in H.client(bob, "ClientState").snapshot().cosmetics do
		if c.nation == A then
			mine = c
		end
	end
	H.expect(mine and mine.flag == "flag_comet" and mine.border == "border_dashes", "Bob's client knows Alice's flag and border")
	H.expect(mine.token == "token_shield" and mine.vip and mine.frame == "frame_gold", "and her token skin and VIP frame")
	H.expect(ShopState.view().robuxOpen == false, "Robux purchases closed for the match")
	local ok, reason = await(ShopService.apply, player, { kind = "Buy", item = "flag_vanguard", currency = "Robux" })
	H.expect(ok == false and reason == "InMatch", "the server refuses a Robux purchase during a match")

	-- Alice's flag on her capital (on Bob's screen too) and an army with her token skin
	local nation = state.nations[A]
	nation.gold, nation.manpower = 200, 10000
	Emulator.press(alice, "Capital")
	Emulator.run(1)
	Emulator.press(alice, "Regiment")
	Emulator.run(2)
	local flagOnMap = alice.localPlayer.PlayerGui:FindFirstChild("Flag" .. A, true)
	H.expect(flagOnMap ~= nil and flagOnMap:FindFirstChild("Flag") ~= nil, "Alice's flag stands by her capital")
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Flag" .. A, true) ~= nil, "Bob sees it too")
	-- (every nation's army has a sprite now, a soldier of its race by default: look at Alice's own army)
	local aliceArmy
	for id, a in state.armies do
		if a.owner == A then
			aliceArmy = id
		end
	end
	local aliceToken = bob.localPlayer.PlayerGui:FindFirstChild("Army" .. tostring(aliceArmy), true)
	local skin = aliceToken and aliceToken:FindFirstChild("TokenSkin")
	H.expect(
		skin ~= nil and skin:GetAttribute("Skin") == "shield" and skin:GetAttribute("Soldier") == nil,
		"Bob sees Alice's army with her token skin, the Shield: an equipped token wins over her race's soldier"
	)
	-- Bob has no token equipped: his army is a soldier of his nation's race
	local B = H.myNation(bob)
	local bobsArmy = require("../../../src/shared/Sim/Army").spawn(state, B, state.nations[B].capital, 1000)
	Emulator.run(1.5)
	local bobToken = alice.localPlayer.PlayerGui:FindFirstChild("Army" .. bobsArmy.id, true)
	local soldier = bobToken and bobToken:FindFirstChild("TokenSkin")
	H.expect(
		soldier ~= nil and soldier:GetAttribute("Soldier") == state.nations[B].race and soldier:GetAttribute("Skin") == nil,
		"Alice sees Bob's army as a soldier of his race (" .. state.nations[B].race .. ")"
	)

	-- her emote over the capital, seen by Bob
	Emulator.press(alice, "😀")
	Emulator.run(0.3)
	Emulator.press(alice, "📯")
	Emulator.run(1.2)
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Emote" .. A, true) ~= nil, "Bob sees Alice's emote")
	Emulator.press(alice, "✕") -- close the province sheet for a clear view
	Emulator.run(0.3)
	H.shot(alice, "map_flag_emote")
	Emulator.run(3)
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Emote" .. A, true) == nil, "the emote disappears after 3 s")
	Emulator.press(alice, "😀")
	Emulator.run(0.3)
	Emulator.press(alice, "📯")
	Emulator.run(1.2)
	H.expect(bob.localPlayer.PlayerGui:FindFirstChild("Emote" .. A, true) == nil, "one emote per 10 seconds")

	-- the nations list shows flags, the VIP tag and the frame
	Emulator.press(bob, "NationsButton")
	Emulator.run(0.5)
	H.expect(Emulator.findText(bob, "Alice") ~= nil or Emulator.findText(bob, nation.name) ~= nil, "Bob's nations list")
	H.expect(Emulator.findText(bob, "VIP") ~= nil, "shows Alice's VIP tag")
	H.shot(bob, "nations_list")
	Emulator.press(bob, "NationsButton")

	-- Alice wins: her victory animation plays over her capital on Results; Robux purchases open again
	Data.update(player, function(d)
		d.owned.victory_fireworks = true
		d.equipped.Victory = "victory_fireworks"
	end)
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
	H.expect(state.result ~= nil, "Alice won")
	local report = H.client(alice, "ProfileState").reward()
	local vipLine
	for _, line in report.reward.lines do
		if line.kind == "Vip" then
			vipLine = line
		end
	end
	H.expect(vipLine ~= nil and vipLine.xp > 0 and vipLine.glory > 0, "VIP adds 25% match XP and Glory to her reward")
	local victory = bob.localPlayer.PlayerGui:FindFirstChild("Victory" .. A, true)
	H.expect(victory ~= nil and string.find("🎆 ✨ 🎇", victory.Text, 1, true) ~= nil, "Bob sees her fireworks")
	H.expect(ShopState.view().robuxOpen, "Robux purchases are open on the Results screen")
	H.expect(Emulator.findText(alice, "Starter Pack") == nil, "the starter pack isn't offered twice in a session")
	H.shot(bob, "results")
	bob.localPlayer.PlayerGui.Results.Enabled = false -- hide the Results panel to see the map under it
	H.client(bob, "MapView").centreOn(H.provinceMap(bob, state.nations[A].capital), true)
	Emulator.run(1.5)
	H.shot(bob, "victory")
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	run = run,
}
