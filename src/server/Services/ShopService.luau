--!strict
-- The shop (docs/MONETIZATION.md "Catalogue, ShopService and VIP"): Glory purchases, Robux purchases through
-- MarketplaceService, the VIP game pass, equipping, capital emotes and the starter-pack offer, and every player's
-- equipped cosmetics for the Replicator. Thin wrapper: the rules are in Shared.Sim.Shop, the items in
-- Shared.Catalogue, saving is PlayerDataService's.
--
-- Robux: MarketplaceService.ProcessReceipt goes through PlayerDataService.processReceipt (each purchase id is
-- granted once and saved before PurchaseGranted). Prompts only open outside a match (Lobby, draft, Results).
-- Test mode: an item whose product id is still 0 is granted free in Studio, through the same receipt path with a
-- made-up receipt, and refused on a live server.

local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Remotes = require(Shared.Remotes)
local Shop = require(Shared.Sim.Shop)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local PlayerDataService = require(script.Parent.PlayerDataService)
local TelemetryService = require(script.Parent.TelemetryService)

local ShopService = {}

local getPhase: () -> string
local getState: () -> Types.MatchState?
local nationOf: (Player) -> number?
local shopRemote: RemoteEvent
local vipCache: { [Player]: boolean } = {}
local vipChecked: { [Player]: boolean } = {} -- the join check (checkVip) has finished
local offered: { [Player]: boolean } = {} -- the starter pack was offered this session
local lastEmote: { [Player]: number } = {} -- match tick of the player's last emote
local emoteMatch: Types.MatchState? = nil -- the match those ticks belong to

local VIP_WAIT_SECONDS = 15 -- how long a reward waits for a joining player's VIP check
local PASS_CHECK_TRIES = 3 -- UserOwnsGamePassAsync attempts after a pass purchase
local PASS_CHECK_RETRY_SECONDS = 2

local function testMode(): boolean
	return RunService:IsStudio() and Catalogue.hasPlaceholders()
end

function ShopService.isVip(player: Player): boolean
	return vipCache[player] == true
end

-- isVip once the player's join check has finished (waits for it, up to VIP_WAIT_SECONDS): for a reward paid as
-- soon as a profile loads, which can run before the check.
function ShopService.awaitVip(player: Player): boolean
	local deadline = os.clock() + VIP_WAIT_SECONDS
	while not vipChecked[player] and player.Parent == Players and os.clock() < deadline do
		task.wait()
	end
	return ShopService.isVip(player)
end

-- Does Roblox say the player owns the VIP pass? nil if the check failed.
local function ownsPass(player: Player): boolean?
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Catalogue.VIP_PASS_ID)
	end)
	return if ok then owns == true else nil
end

local function sendView(player: Player, starterOffer: boolean?)
	local data = PlayerDataService.data(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	local open = Shop.robuxOpen(getPhase())
	shopRemote:FireClient(player, Shop.view(data, ShopService.isVip(player), open, starterOffer == true, testMode()))
end

-- VIP: the game pass from Roblox, or (Studio test mode only, while the pass id is 0) the saved test purchase. If
-- Roblox can't be asked, the saved ownership (an in-game purchase, or an earlier check that said yes) counts.
local function checkVip(player: Player, data: Types.PlayerProfile)
	local vip = vipCache[player] == true
	if Catalogue.VIP_PASS_ID ~= 0 then
		local owns = ownsPass(player)
		if owns == nil then
			vip = vip or data.owned.vip == true
		elseif owns then
			vip = true
			if not data.owned.vip then
				PlayerDataService.edit(player, function(profile) -- remembered for a check that fails later
					profile.owned.vip = true
				end)
			end
		end
	elseif RunService:IsStudio() then
		vip = vip or data.owned.vip == true
	end
	vipCache[player] = vip
	vipChecked[player] = true
	player:SetAttribute("Vip", vip) -- for the [VIP] chat tag on every client
	sendView(player)
end

-- A receipt for an item or offer: grant once, save, then PurchaseGranted. Also used by test mode and the VIP pass.
function ShopService.receipt(receipt: any, id: string): Enum.ProductPurchaseDecision
	local fresh = false -- granted now, not a repeat of a receipt already granted
	local decision = PlayerDataService.processReceipt(receipt, id, function(data)
		Shop.grant(data, id)
		fresh = true
	end)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player and decision == Enum.ProductPurchaseDecision.PurchaseGranted then
		if fresh then
			TelemetryService.purchased(player, id, receipt.CurrencySpent) -- analytics
		end
		if id == "vip" then
			vipCache[player] = true
			player:SetAttribute("Vip", true)
		end
		sendView(player)
	end
	return decision
end

local function onReceipt(receipt: any): Enum.ProductPurchaseDecision
	local id = Catalogue.byProductId(receipt.ProductId)
	if id == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- not ours (yet): Roblox retries later
	end
	return ShopService.receipt(receipt, id)
end

-- The ledger entry for a game pass, so it shows in Purchase History like a product (one per player and pass).
local function passReceipt(player: Player, passId: number): any
	return {
		PurchaseId = string.format("pass-%d-%d", passId, player.UserId),
		PlayerId = player.UserId,
		ProductId = passId,
		CurrencySpent = (Catalogue.offer("vip") :: Types.ShopOffer).robux,
	}
end

local function buyRobux(player: Player, id: string): (boolean, string?)
	if not Shop.robuxOpen(getPhase()) then
		return false, "InMatch" -- no purchase prompts during a match
	end
	local data = PlayerDataService.data(player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, reason = Shop.canBuyRobux(data, id, ShopService.isVip(player))
	if not ok then
		return false, reason
	end
	local productId = Catalogue.productId(id)
	if productId == 0 then
		if not RunService:IsStudio() then
			return false, "NotForSale" -- the owner hasn't created this product yet
		end
		-- test mode: the same receipt path, with a made-up receipt
		local item = Catalogue.item(id)
		local offer = Catalogue.offer(id)
		local receipt = {
			PurchaseId = "studio-" .. HttpService:GenerateGUID(false),
			PlayerId = player.UserId,
			ProductId = 0,
			CurrencySpent = if item and item.robux then item.robux elseif offer then offer.robux else 0,
		}
		local granted = ShopService.receipt(receipt, id) == Enum.ProductPurchaseDecision.PurchaseGranted
		return granted, if granted then nil else "TryAgain"
	end
	local offer = Catalogue.offer(id)
	local prompted = pcall(function()
		if offer and offer.kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, productId)
		else
			MarketplaceService:PromptProductPurchase(player, productId)
		end
	end)
	return prompted, if prompted then nil else "TryAgain"
end

local function emote(player: Player, id: string): (boolean, string?)
	local state = getState()
	local nationId = nationOf(player)
	if state == nil or nationId == nil or state.result ~= nil then
		return false, "NoNation"
	end
	if emoteMatch ~= state then
		emoteMatch = state
		table.clear(lastEmote)
	end
	local data = PlayerDataService.data(player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, reason = Shop.canEmote(data, id, ShopService.isVip(player), lastEmote[player], state.tick)
	if not ok then
		return false, reason
	end
	lastEmote[player] = state.tick
	local index = table.find(Catalogue.ofSlot("Emote"), Catalogue.item(id)) or 0
	-- an event goes out with the next delta to every client: the icon over the capital
	table.insert(state.events, { kind = "Emote", a = nationId, b = index, province = state.nations[nationId].capital })
	return true, nil
end

local function applyIntent(player: Player, intent: Types.ShopIntent): (boolean, string?)
	local vip = ShopService.isVip(player)
	local rule: ((Types.PlayerProfile, string, boolean) -> (boolean, string?))? = nil
	if intent.kind == "Buy" and intent.currency == "Glory" then
		rule = Shop.buyWithGlory
	elseif intent.kind == "Equip" then
		rule = Shop.equip
	elseif intent.kind == "Buy" then
		return buyRobux(player, intent.item)
	elseif intent.kind == "DefaultTheme" then
		local on = intent.on
		local changed = PlayerDataService.edit(player, function(data) -- a setting: saved with the autosave
			Shop.setDefaultTheme(data, on)
			return true
		end)
		sendView(player)
		return changed ~= nil, if changed then nil else "NotLoaded"
	else
		return emote(player, intent.item)
	end
	-- a refused request changes nothing and writes nothing; an equip rides on the autosave and the final save;
	-- Glory spent is saved at once
	local apply = rule :: (Types.PlayerProfile, string, boolean) -> (boolean, string?)
	local result = PlayerDataService.edit(player, function(data)
		local ok, reason = apply(data, intent.item, vip)
		return { ok = ok, reason = reason }
	end)
	if result and result.ok and intent.kind == "Buy" then
		PlayerDataService.save(player)
	end
	sendView(player)
	if result == nil then
		return false, "NotLoaded"
	end
	return result.ok, result.reason
end

-- A shop request from CommandRouter (shape already checked). May yield (saves, prompts).
function ShopService.apply(player: Player, intent: Types.ShopIntent): (boolean, string?)
	local ok, reason = applyIntent(player, intent)
	TelemetryService.shopIntent(player, intent, ok, reason) -- analytics
	return ok, reason
end

-- Every loaded player's equipped cosmetics by userId, for Snapshot.cosmetics.
function ShopService.cosmeticsByUser(): { [number]: Types.NationCosmetics }
	local out = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.data(player)
		if data then
			out[player.UserId] = Shop.cosmeticsOf(data, ShopService.isVip(player), 0)
		end
	end
	return out
end

-- Every loaded player's equipped map theme by userId, for the theme vote.
function ShopService.themesByUser(): { [number]: string }
	local out = {}
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.data(player)
		if data then
			out[player.UserId] = Shop.themeOf(data, ShopService.isVip(player))
		end
	end
	return out
end

-- Every nation's cosmetics in a match: players' own, defaults for bots.
function ShopService.cosmetics(state: Types.MatchState): { Types.NationCosmetics }
	return Shop.nationCosmetics(state, ShopService.cosmeticsByUser())
end

-- The phase changed: Robux purchases open or close for everyone, and after a match the starter pack may be offered
-- (once per session, never during a match).
function ShopService.onPhase(phase: string)
	for _, player in Players:GetPlayers() do
		local data = PlayerDataService.data(player)
		local offer = data ~= nil
			and Shop.robuxOpen(phase)
			and Shop.shouldOfferStarter(data, offered[player] == true, ShopService.isVip(player))
		if offer then
			offered[player] = true
			TelemetryService.starterOffered(player) -- analytics
		end
		sendView(player, offer)
	end
end

function ShopService.init(
	phaseGetter: () -> string,
	stateGetter: () -> Types.MatchState?,
	nationGetter: (Player) -> number?
)
	getPhase = phaseGetter
	getState = stateGetter
	nationOf = nationGetter
	shopRemote = Remotes.event("Shop")
	MarketplaceService.ProcessReceipt = onReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not (bought and passId == Catalogue.VIP_PASS_ID and passId ~= 0) then
			return
		end
		-- Roblox's word for it before granting (a pass bought here shows at once)
		for try = 1, PASS_CHECK_TRIES do
			local owns = ownsPass(player)
			if owns then
				ShopService.receipt(passReceipt(player, passId), "vip")
				return
			elseif owns == false or try == PASS_CHECK_TRIES or player.Parent ~= Players then
				warn(
					string.format(
						"[shop] %s: VIP purchase finished but not confirmed (checked on next join)",
						player.Name
					)
				)
				return
			end
			task.wait(PASS_CHECK_RETRY_SECONDS)
		end
	end)
	PlayerDataService.onLoaded(checkVip)
	CommandRouter.onShop(ShopService.apply)
	Players.PlayerRemoving:Connect(function(player)
		offered[player] = nil
		lastEmote[player] = nil
		-- after every PlayerRemoving handler: the leaver's prorated reward (PlayerDataService's leave hooks) still
		-- reads their VIP, whichever handler Roblox runs first
		task.defer(function()
			vipCache[player] = nil
			vipChecked[player] = nil
		end)
	end)
end

return ShopService
