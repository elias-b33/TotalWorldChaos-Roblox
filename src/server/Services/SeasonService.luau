--!strict
-- The season pass (docs/MONETIZATION.md 6): keeps each player's profile on the season the UTC day falls in, counts
-- the match rewards' XP for it (Sim.Progression.addXp adds account XP to the season), answers claims, sells the pass
-- and the pass bundle as developer products through ShopService, and sends each player their SeasonView. A new UTC day
-- (midnight, or DevDay in Studio) may start or end a season and always brings a new rotating shop.
-- Thin wrapper: the rules are in Shared.Sim.Season, the seasons and rewards in Config.Season, saving is
-- PlayerDataService's, purchases ShopService's.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Season = require(Shared.Sim.Season)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local DevService = require(script.Parent.DevService)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local ShopService = require(script.Parent.ShopService)
local TelemetryService = require(script.Parent.TelemetryService)

local DAY_CHECK_SECONDS = 5 -- how often to look for a new UTC day (midnight, or DevDay in Studio)
local GLORY_SKU = "season_tier" -- analytics: Glory from season rewards

local SeasonService = {}

local seasonRemote: RemoteEvent
local lastTier: { [Player]: number } = {} -- the tier the player was last seen on (SeasonTier progression events)
local checkedDay = -1

local function today(): number
	return DevService.today()
end

local function current(): Types.SeasonDef?
	return Season.current(today())
end

-- SeasonTier progression: Complete for every tier passed since we last looked, Start for the new one.
local function noteTier(player: Player, data: Types.PlayerProfile)
	local def = current()
	if def == nil or data.season.id ~= def.id then
		lastTier[player] = nil
		return
	end
	local tier = Season.tierOf(data.season)
	local before = lastTier[player]
	lastTier[player] = tier
	if before and tier > before then
		for t = before, tier - 1 do
			TelemetryService.seasonTier(player, t, def.id, true)
		end
		TelemetryService.seasonTier(player, tier, def.id, false)
	end
end

function SeasonService.sendView(player: Player)
	local data = PlayerDataService.data(player)
	if data == nil or player.Parent ~= Players then
		return
	end
	noteTier(player, data)
	seasonRemote:FireClient(player, Season.view(data, current(), today()))
end

-- Bring a player's season up to today (a season starts or ends: what the old one left unclaimed is granted) and show
-- it, with the day's rotating shop.
local function refresh(player: Player)
	local data = PlayerDataService.data(player)
	if data == nil then
		return
	end
	local def = current()
	if Season.needsSync(data, def) then
		local result = PlayerDataService.update(player, function(profile)
			local _, count, glory = Season.sync(profile, def)
			return { count = count, glory = glory }
		end)
		if result and result.glory > 0 then
			TelemetryService.glory(player, "Source", result.glory, "Gameplay", GLORY_SKU)
		end
		if result and result.count > 0 then
			ShopService.refresh(player) -- the leftover rewards are owned now
		end
	end
	SeasonService.sendView(player)
end

-- Inside the match reward's profile update: the reward's XP is already on the season (Progression.addXp). If a season
-- started since the player's last sync, the match counts for the new one.
local function onReward(
	player: Player,
	data: Types.PlayerProfile,
	_stats: Types.PlayerMatchStats,
	report: Types.RewardReport
)
	local def = current()
	if Season.needsSync(data, def) then
		local changed = Season.sync(data, def)
		if changed and def then
			data.season.xp += math.max(0, report.reward.xp)
		end
	end
	if player.Parent == Players then
		task.defer(SeasonService.sendView, player) -- after the update has saved
	end
end

local function claim(player: Player, intent: Types.SeasonIntent): (boolean, string?)
	local def = current()
	-- a refused claim writes nothing (a flood of claims never floods the DataStore); rewards are saved at once
	local result = PlayerDataService.edit(player, function(data)
		Season.sync(data, def)
		if intent.kind == "ClaimAll" then
			local count, glory = Season.claimAll(data, def)
			return { ok = count > 0, reason = if count > 0 then nil else "NothingToClaim", glory = glory }
		elseif intent.kind == "Claim" then
			local ok, reason, glory = Season.claim(data, def, intent.tier, intent.track)
			return { ok = ok, reason = reason, glory = glory }
		end
		return { ok = false, reason = "BadRequest", glory = 0 }
	end)
	if result and result.ok then
		PlayerDataService.save(player)
	end
	SeasonService.sendView(player)
	if result == nil then
		return false, "NotLoaded"
	end
	if result.ok then
		ShopService.refresh(player) -- new items to equip
		if result.glory > 0 then
			TelemetryService.glory(player, "Source", result.glory, "Gameplay", GLORY_SKU)
		end
	end
	return result.ok, result.reason
end

-- A season request from CommandRouter (shape already checked). May yield (saves).
function SeasonService.apply(player: Player, intent: Types.SeasonIntent): (boolean, string?)
	if intent.kind == "Viewed" then
		local def = current()
		if def then
			TelemetryService.seasonPass(player, def.id, "pass_viewed") -- analytics
		end
		return true, nil
	end
	return claim(player, intent)
end

-- The pass and the pass bundle, sold through the shop (Robux prompts only outside a match, like every purchase).
local function addPass(id: string, robux: number, bundle: boolean)
	ShopService.addProduct(id, {
		robux = robux,
		canBuy = function(_player: Player, data: Types.PlayerProfile): (boolean, string?)
			local def = current()
			if def and Season.needsSync(data, def) then
				return false, "TryAgain" -- the season changed a moment ago: the next refresh syncs it
			end
			return Season.canBuyPass(data, def)
		end,
		grant = function(data: Types.PlayerProfile)
			local def = current()
			if def then
				Season.sync(data, def)
			end
			-- paid for: always granted, even if the season ended a moment ago (on the season the profile is still on,
			-- else, with no season running, the next one: Season.sync)
			Season.buyPass(data, bundle)
		end,
		prompted = function(player: Player)
			local def = current()
			if def then
				TelemetryService.seasonPass(player, def.id, "purchase_prompted") -- analytics
			end
		end,
		granted = function(player: Player)
			local data = PlayerDataService.data(player)
			if data then
				TelemetryService.seasonPass(player, data.season.id, "purchase_completed") -- analytics
			end
			SeasonService.sendView(player)
		end,
	})
end

function SeasonService.init()
	seasonRemote = Remotes.event("Season")
	addPass("season_pass", Config.Season.PassRobux, false)
	addPass("season_bundle", Config.Season.BundleRobux, true)
	PlayerDataService.onLoaded(refresh)
	ProgressionService.onReward(onReward)
	CommandRouter.onSeason(SeasonService.apply)
	Players.PlayerRemoving:Connect(function(player)
		lastTier[player] = nil
	end)
	-- a new UTC day: the season may start or end, and the rotating shop changes for everyone
	checkedDay = today()
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_SECONDS)
			if today() ~= checkedDay then
				checkedDay = today()
				for _, player in Players:GetPlayers() do
					task.spawn(function()
						refresh(player)
						ShopService.refresh(player)
					end)
				end
			end
		end
	end)
end

return SeasonService
