--!strict
-- Player saves (docs/MONETIZATION.md "PlayerDataService with ProfileStore"): loads a player's profile with a
-- ProfileStore session lock when they join, releases it when they leave, and applies changes such as match
-- rewards. Thin wrapper: the profile's shape and every rule are in Shared.Sim.Progression.
--
-- Session lock: only one server at a time can hold a profile; a second server waits, then takes it over and the
-- first one ends its session (and kicks the player there). Autosave every 5 minutes, a save after every reward,
-- and a final save on leave and on shutdown are ProfileStore's. The leave hooks run once per session: when the
-- player leaves, or just before the final save if the server shuts down first.
-- Without DataStore access (Studio with "Enable Studio Access to API Services" off) ProfileStore switches to its
-- in-memory mock store by itself: everything works, nothing outlives the test. The harness emulates DataStoreService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Sim.Progression)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local ProfileStore = require(script.Parent.Parent.Packages.ProfileStore)

type Data = Types.PlayerProfile
type Profile = ProfileStore.Profile<Data>

local STORE_NAME = "PlayerData"
local KEY_PREFIX = "Player_"
local MAX_RECEIPTS = 200 -- receipts and purchase history keep the newest this many
local LOAD_FAILED = "Your save couldn't be loaded. Please rejoin in a minute."
local SESSION_TAKEN = "Your save was opened on another server. Please rejoin."

local PlayerDataService = {}

local store = ProfileStore.New(STORE_NAME, Progression.newProfile())
local profiles: { [Player]: Profile } = {}
local leaveHooks: { (Player, Data) -> () } = {}
local loadHooks: { (Player, Data) -> () } = {}
local leaveHooksRan: { [Profile]: boolean } = {}
local profileRemote: RemoteEvent

local function sendSummary(player: Player, data: Data)
	profileRemote:FireClient(player, Progression.summary(data))
end

local function runHooks(hooks: { (Player, Data) -> () }, player: Player, data: Data, what: string)
	for _, hook in hooks do
		local ok, err = pcall(hook, player, data)
		if not ok then
			warn(string.format("[data] %s hook failed: %s", what, tostring(err)))
		end
	end
end

-- Once per session: a leaver's prorated match reward and the like, written before the final save.
local function runLeaveHooks(player: Player, profile: Profile)
	if leaveHooksRan[profile] then
		return
	end
	leaveHooksRan[profile] = true
	runHooks(leaveHooks, player, profile.Data, "leave")
end

local function load(player: Player)
	local params: any = {
		Cancel = function() -- stop trying once the player has gone
			return player.Parent ~= Players
		end,
	}
	local profile = store:StartSessionAsync(KEY_PREFIX .. player.UserId, params)
	if profile == nil then
		if player.Parent == Players then
			player:Kick(LOAD_FAILED)
		end
		return
	end
	profile:AddUserId(player.UserId) -- GDPR: lets a data-erasure request find this key
	profile:Reconcile() -- fields added to the template since the last save
	Progression.migrate(profile.Data)
	profile.OnLastSave:Connect(function(reason)
		-- the server is shutting down before the player left: pay what leaving would have paid, before the save
		if reason == "Shutdown" then
			runLeaveHooks(player, profile)
		end
	end)
	profile.OnSessionEnd:Connect(function()
		leaveHooksRan[profile] = nil
		if profiles[player] == profile then
			profiles[player] = nil
			-- still here: another server took the profile (on shutdown everyone is leaving anyway)
			if not ProfileStore.IsClosing then
				player:Kick(SESSION_TAKEN)
			end
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession() -- left while loading
		return
	end
	profiles[player] = profile
	sendSummary(player, profile.Data)
	for _, hook in loadHooks do
		task.spawn(hook, player, profile.Data)
	end
end

local function release(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	profiles[player] = nil -- first, so OnSessionEnd doesn't kick a player who is leaving anyway
	runLeaveHooks(player, profile)
	profile:EndSession() -- saves and releases the session lock
end

function PlayerDataService.init()
	profileRemote = Remotes.event("Profile")
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
end

-- The loaded profile, or nil while it loads (or if it couldn't). Change it only through PlayerDataService.update.
function PlayerDataService.data(player: Player): Data?
	local profile = profiles[player]
	return if profile then profile.Data else nil
end

-- Change a loaded profile, save it now and send the player their new summary. Returns what `change` returned,
-- or nil if the profile isn't loaded.
function PlayerDataService.update<T>(player: Player, change: (Data) -> T): T?
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return nil
	end
	local result = change(profile.Data)
	profile:Save()
	sendSummary(player, profile.Data)
	return result
end

-- Run `hook` with a leaving player's profile just before its final save (e.g. a leaver's prorated reward).
function PlayerDataService.onLeaving(hook: (Player, Data) -> ())
	table.insert(leaveHooks, hook)
end

-- Run `hook` (in its own thread) once a joining player's profile has loaded: sending a new player to the
-- tutorial, checking the VIP pass, a Results reward that waited for the profile.
function PlayerDataService.onLoaded(hook: (Player, Data) -> ())
	table.insert(loadHooks, hook)
end

local function trimReceipts(data: Data)
	local count, oldestId, oldestAt = 0, nil :: string?, math.huge
	for id, at in data.receipts do
		count += 1
		if at < oldestAt then
			oldestId, oldestAt = id, at
		end
	end
	if count > MAX_RECEIPTS and oldestId then
		data.receipts[oldestId] = nil
	end
	while #data.purchaseHistory > MAX_RECEIPTS do
		table.remove(data.purchaseHistory, 1)
	end
end

-- The ProcessReceipt hook for developer products: ShopService's MarketplaceService.ProcessReceipt calls this with
-- the catalogue item or offer the product sells and its grant function. Grants each purchase id once, records it
-- in the purchase history, and answers PurchaseGranted only after the receipt is saved, as Roblox requires.
function PlayerDataService.processReceipt(receipt: any, item: string, grant: (Data) -> ()): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local profile = if player then profiles[player] else nil
	if profile == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local id = tostring(receipt.PurchaseId)
	local data = profile.Data
	if data.receipts[id] == nil then
		grant(data)
		data.receipts[id] = os.time()
		table.insert(
			data.purchaseHistory,
			{ product = receipt.ProductId, robux = receipt.CurrencySpent, at = os.time(), item = item }
		)
		trimReceipts(data)
		profile:Save()
		if player then
			sendSummary(player, data)
		end
	end
	while profile:IsActive() and (profile.LastSavedData :: Data).receipts[id] == nil do
		task.wait()
	end
	return if (profile.LastSavedData :: Data).receipts[id] ~= nil
		then Enum.ProductPurchaseDecision.PurchaseGranted
		else Enum.ProductPurchaseDecision.NotProcessedYet
end

return PlayerDataService
