--!nocheck
-- Saves and purchases: shop requests that change nothing write nothing (and have their own rate limit), an equip
-- waits for the autosave, a Glory purchase saves at once; a receipt Roblox retries while the profile is still
-- loading waits for it; a VIP whose Results reward waited for a loading profile still gets the +25%.

local Config = require("../../../src/shared/Config")
local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	-- call a server function that may yield on the emulator's scheduler and wait for its answer
	local function await(fn, ...)
		local args = table.pack(...)
		local result
		Emulator.task.spawn(function()
			result = table.pack(fn(table.unpack(args, 1, args.n)))
		end)
		local deadline = Emulator.now() + 70
		while result == nil and Emulator.now() < deadline do
			Emulator.run(0.1)
		end
		assert(result, "timed out")
		return table.unpack(result, 1, result.n)
	end
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(3)
	local Data = H.server("Services.PlayerDataService")
	local ShopService = H.server("Services.ShopService")
	local player = alice.serverPlayer
	local userId = player.UserId
	local data = Data.data(player)
	H.expect(data ~= nil, "Alice's profile loaded")
	H.expect(Emulator.dataStores.PlayerData == nil, "Studio saves go to their own store, never the live one")

	-- ten equips of an item that doesn't exist: no DataStore write, and the shop's rate limit answers most
	local answers = {}
	alice.dm:GetService("ReplicatedStorage").Remotes.CommandResult.OnClientEvent:Connect(function(_id, _ok, reason)
		table.insert(answers, reason)
	end)
	local before = H.writes(userId)
	local Intents = H.client(alice, "Intents")
	for _ = 1, 10 do
		Intents.equip("no_such_item")
	end
	Emulator.run(1.5)
	local tooFast = 0
	for _, reason in answers do
		tooFast += if reason == "TooFast" then 1 else 0
	end
	H.expect(#answers == 10 and tooFast == 10 - Config.Net.MaxShopIntentsPerSecond, "the shop's own rate limit")
	H.expect(H.writes(userId) == before, "refused shop requests write nothing to the DataStore")

	-- quest requests too: claims and rerolls of a quest that doesn't exist are refused and write nothing; a reroll
	-- that goes through is saved at once
	answers = {}
	for _ = 1, 4 do
		Intents.claimQuest("no-such-quest")
		Intents.rerollQuest("no-such-quest")
	end
	Emulator.run(1.5)
	H.expect(#answers == 8 and table.find(answers, "TooFast") == nil, "every quest request was answered")
	H.expect(H.writes(userId) == before, "refused quest requests write nothing to the DataStore")
	Intents.rerollQuest(data.quests.daily[1].key)
	Emulator.run(1.5)
	H.expect(H.writes(userId) == before + 1, "a free reroll saves at once")
	before = H.writes(userId)

	-- an equip changes the profile but waits for the autosave; Glory spent is saved at once
	Data.edit(player, function(d)
		d.glory = 1000
		d.owned.flag_cross = true
	end)
	Intents.equip("flag_cross")
	Emulator.run(1.5)
	H.expect(data.equipped.Flag == "flag_cross" and H.writes(userId) == before, "an equip waits for the autosave")
	Intents.buy("flag_tricolour", "Glory")
	Emulator.run(1.5)
	H.expect(data.owned.flag_tricolour and H.writes(userId) == before + 1, "a Glory purchase saves at once")
	H.expect(H.saved(userId).Data.equipped.Flag == "flag_cross", "with the equip in the same write")

	-- a receipt Roblox retries as Bob joins, before his profile has loaded: it waits for the profile
	local bob = Emulator.addClient("Bob")
	local receipt = { PurchaseId = "rejoin-1", PlayerId = bob.serverPlayer.UserId, ProductId = 0, CurrencySpent = 49 }
	H.expect(Data.data(bob.serverPlayer) == nil, "Bob's profile is still loading")
	local decision = await(ShopService.receipt, receipt, "flag_cross")
	H.expect(decision == Emulator.roblox.Enum.ProductPurchaseDecision.PurchaseGranted, "the receipt is granted")
	H.expect(Data.data(bob.serverPlayer).owned.flag_cross == true, "in the same session")

	-- VIP (Studio test mode: the saved pass) leaves and rejoins while another server still holds her save; the
	-- match ends while her profile loads, and the reward that waited for it still has the VIP +25%
	Data.update(player, function(d)
		d.owned.vip = true
	end)
	Emulator.removeClient(alice)
	Emulator.run(3)
	local entry = Emulator.dataStores[Data.STORE_NAME][Data.KEY_PREFIX .. userId]
	entry.value.MetaData.ActiveSession = { 1, "another-server", "x" }
	entry.value.MetaData.LastUpdate = 1700000000 + math.floor(Emulator.now())
	alice = Emulator.addClient("Alice", nil, userId)
	Emulator.run(2)
	player = alice.serverPlayer
	H.expect(Data.data(player) == nil, "Alice's profile waits for the other server")
	local state = H.state()
	local A = H.myNation(alice)
	H.expect(A ~= nil and A ~= 0, "Alice has her nation back")
	local total, given = 0, 0
	for _, p in state.provinces do
		total += 1
		given += if p.owner == A then 1 else 0
	end
	for _, p in state.provinces do
		if given < math.ceil(Config.Win.DominationShare * total) and p.owner ~= A and p.terrain ~= "Mountain" then
			p.owner = A
			given += 1
		end
	end
	Emulator.run(2)
	H.expect(state.result ~= nil and Data.data(player) == nil, "the match ended while her profile loads")
	local ProfileState = H.client(alice, "ProfileState")
	local deadline = Emulator.now() + 90
	while ProfileState.reward() == nil and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local report = ProfileState.reward()
	H.expect(report ~= nil, "the reward was paid once the profile loaded")
	local vipLine
	for _, line in report.reward.lines do
		if line.kind == "Vip" then
			vipLine = line
		end
	end
	H.expect(vipLine ~= nil and vipLine.xp > 0, "with the VIP +25%")
	H.expect(ShopService.isVip(player), "Alice is VIP")
end

return { run = run }
