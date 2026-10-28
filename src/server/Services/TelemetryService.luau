--!strict
-- Analytics (docs/LAUNCH.md "Analytics events", MONETIZATION "Task: Analytics"): wraps Roblox's AnalyticsService
-- (named TelemetryService so the two never clash). One function per event; the payloads are built by the pure
-- Shared.Sim.Telemetry, this service only finds the Player, keeps the per-minute budget and sends.
--
--   Onboarding funnel  joined, lobby_loaded (client), map_voted, nation_picked, the 6 tutorial prompts,
--                      first_match_finished, second_match_started; only for players with fewer than
--                      Config.Telemetry.OnboardingMatches finished matches
--   MatchFlow funnel   lobby, pick, peace, war, cataclysm, results, next_match_started (session matchId-userId)
--   Shop funnel        shop_opened and item_viewed (client), purchase_prompted, purchase_completed
--   StarterPack funnel offer_shown, offer_opened (client), purchase_prompted, purchase_completed (session userId)
--   SeasonPass funnel  ready (TelemetryService.seasonPass), unused until the season pass exists
--   Economy            Glory sources (match_reward, level_up) and sinks (shop items); Robux IAP sinks
--   Progression        AccountLevel (Complete for each level passed, Start for the new one); SeasonTier ready
--   Custom events      the 18 in LAUNCH.md (Sim.Telemetry.CUSTOM_EVENTS); a sandbox server sends only
--                      sandbox_started and the economy
--
-- AnalyticsService only accepts events from servers of a published game: in Studio the calls go nowhere. Set a
-- "TelemetryLog" attribute on Workspace in Studio to print every event to the Output instead (docs/STUDIO.md).
-- Analytics must never break the game: every call is wrapped in pcall and failures are printed, never warned.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Catalogue = require(Shared.Catalogue)
local Config = require(Shared.Config)
local Maps = require(Shared.Maps)
local Match = require(Shared.Sim.Match)
local Telemetry = require(Shared.Sim.Telemetry)
local Tutorial = require(Shared.Sim.Tutorial)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local LobbyService = require(script.Parent.LobbyService)
local MatchService = require(script.Parent.MatchService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Event = Types.TelemetryEvent

local CUSTOM_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}
local STARTER = "starter" -- the starter pack's offer id (Shared.Catalogue)

local TelemetryService = {}

local budget = Telemetry.newBudget()
local failed = false -- an AnalyticsService call failed (printed once)
local current: Types.MatchState? = nil
local matchId = ""
local keepId = false -- the Lobby opened a match id: the match it drafts keeps it
local matchesSeen = 0 -- matches played on this server (map_vote's round: "lobby" first, then "next")
local logged: { [number]: { [string]: boolean } } = {} -- userId -> MatchFlow steps logged in this match
local lastResults: { [number]: string } = {} -- userId -> MatchFlow session of the last Results they saw
local lastCommand: { [number]: number } = {} -- userId -> match tick of their last command (seat time at first)
local afk: { [number]: boolean } = {} -- afk_flagged sent this match
local startsLogged = false
local endLogged = false
local shopSession: { [Player]: string } = {}
local shopViewed: { [Player]: string } = {} -- the shop session item_viewed was sent for
local clientLoaded: { [Player]: boolean } = {}
local notified: { [Player]: boolean } = {} -- notification_opt_in was logged this session

-- Sending -------------------------------------------------------------------------------------------------------

local function newId(): string
	return HttpService:GenerateGUID(false)
end

-- Match-wide events (no userId) go out for the present player with the lowest userId: AnalyticsService needs one.
local function playerFor(e: Event): Player?
	if e.userId then
		return Players:GetPlayerByUserId(e.userId)
	end
	local best: Player? = nil
	for _, p in Players:GetPlayers() do
		if best == nil or p.UserId < best.UserId then
			best = p
		end
	end
	return best
end

local function fieldsOf(e: Event): { [string]: string }?
	if #e.fields == 0 then
		return nil
	end
	local out = {}
	for i, value in e.fields do
		out[CUSTOM_KEYS[i]] = value
	end
	return out
end

local function deliver(player: Player, e: Event)
	local fields = fieldsOf(e)
	if e.kind == "Custom" then
		AnalyticsService:LogCustomEvent(player, e.name, e.value, fields)
	elseif e.kind == "Funnel" then
		AnalyticsService:LogFunnelStepEvent(player, e.name, e.session or "", e.value, e.step or "", fields)
	elseif e.kind == "Onboarding" then
		AnalyticsService:LogOnboardingFunnelStepEvent(player, e.value, e.step or "", fields)
	elseif e.kind == "Economy" then
		local flow = if e.flow == "Sink"
			then Enum.AnalyticsEconomyFlowType.Sink
			else Enum.AnalyticsEconomyFlowType.Source
		AnalyticsService:LogEconomyEvent(
			player,
			flow,
			e.name,
			e.value,
			e.balance or 0,
			e.transaction or "",
			e.step or "",
			fields
		)
	elseif e.flow == "Complete" then
		AnalyticsService:LogProgressionCompleteEvent(player, e.name, e.value, e.step or "", fields)
	else
		AnalyticsService:LogProgressionStartEvent(player, e.name, e.value, e.step or "", fields)
	end
end

-- Send one event (for `player`, or the Player its userId names). Dropped past the budget or with nobody to send for.
-- A sandbox server sends only sandbox_started and the economy (Sim.Telemetry.sandboxAllows): no funnels.
function TelemetryService.send(e: Event, player: Player?)
	local target = player or playerFor(e)
	if target == nil then
		return
	end
	local state = MatchService.current()
	if state and state.setup.sandbox and not Telemetry.sandboxAllows(e) then
		return
	end
	local ok, dropped = Telemetry.allow(budget, os.clock(), #Players:GetPlayers())
	if dropped > 0 then
		print(string.format("[telemetry] over budget: %d events dropped in the last minute", dropped))
	end
	if not ok then
		return
	end
	if RunService:IsStudio() and workspace:GetAttribute("TelemetryLog") == true then
		print(
			string.format(
				"[telemetry] %s %s %s %s %s",
				e.kind,
				e.name,
				e.step or "",
				tostring(e.value),
				table.concat(e.fields, ",")
			)
		)
	end
	local sent, err = pcall(deliver, target, e)
	if not sent and not failed then
		failed = true
		print("[telemetry] AnalyticsService refused an event: " .. tostring(err))
	end
end

local function sendAll(events: { Event }, player: Player?)
	for _, e in events do
		TelemetryService.send(e, player)
	end
end

-- Onboarding -----------------------------------------------------------------------------------------------------

local function newcomer(player: Player): boolean
	local data = PlayerDataService.data(player)
	return data ~= nil and data.stats.matches < Config.Telemetry.OnboardingMatches
end

local function onboard(player: Player, stepName: string)
	if newcomer(player) then
		TelemetryService.send(Telemetry.onboarding(stepName, player.UserId), player)
	end
end

-- A tutorial prompt was done (1..6, Sim.Tutorial.STEPS): onboarding steps 5-10.
function TelemetryService.tutorialPrompt(player: Player, prompt: number)
	local name = Telemetry.ONBOARDING[4 + prompt]
	if name and prompt >= 1 and prompt <= #Tutorial.STEPS then
		onboard(player, name)
	end
end

-- The player skipped the tutorial at this prompt.
function TelemetryService.tutorialSkipped(player: Player, prompt: number)
	local name = Tutorial.STEPS[prompt] or "done"
	TelemetryService.send(Telemetry.custom("tutorial_skipped", prompt, { name }, player.UserId), player)
end

-- A sandbox world started for this player ("first" on arrival, "new_world" for another one).
function TelemetryService.sandboxStarted(player: Player, mapId: string, start: string)
	TelemetryService.send(Telemetry.sandboxStarted(mapId, start, player.UserId), player)
end

-- MatchFlow -----------------------------------------------------------------------------------------------------

local function sessionOf(userId: number): string
	return matchId .. "-" .. userId
end

-- Log a MatchFlow step once per match. True if it was new.
local function flowStep(player: Player, stepName: string): boolean
	local mine = logged[player.UserId]
	if mine == nil then
		mine = {}
		logged[player.UserId] = mine
	end
	if mine[stepName] then
		return false
	end
	mine[stepName] = true
	TelemetryService.send(Telemetry.funnel("MatchFlow", sessionOf(player.UserId), stepName, player.UserId), player)
	return true
end

-- The Lobby opened (the map vote): a new match id, and step 1 for everyone here.
function TelemetryService.lobbyOpened()
	matchId = newId()
	logged = {}
	keepId = true
	for _, player in Players:GetPlayers() do
		flowStep(player, "lobby")
	end
end

-- The map vote is over: map_vote for every voter, and their onboarding step.
function TelemetryService.voteOver(lobby: Types.LobbyState)
	local themes: { [string]: string } = {}
	for _, id in Maps.ids do
		themes[id] = Maps.get(id).theme
	end
	for _, e in Telemetry.mapVotes(lobby, if matchesSeen == 0 then "lobby" else "next", themes) do
		local player = Players:GetPlayerByUserId(e.userId or 0)
		if player then
			TelemetryService.send(e, player)
			onboard(player, "map_voted")
		end
	end
end

local function newMatch(state: Types.MatchState)
	current = state
	matchesSeen += 1
	if keepId then
		keepId = false
	else
		matchId = newId()
		logged = {}
	end
	lastCommand = {}
	afk = {}
	startsLogged = false
	endLogged = false
end

-- One player's part of a tick: seated (pick), the phase they reached, Results, AFK.
local function observePlayer(state: Types.MatchState, player: Player)
	local userId = player.UserId
	if Match.nationOf(state, userId) == nil and state.primordials[userId] == nil then
		return
	end
	if flowStep(player, "pick") then
		onboard(player, "nation_picked")
		local previous = lastResults[userId]
		if previous then
			lastResults[userId] = nil
			TelemetryService.send(Telemetry.funnel("MatchFlow", previous, "next_match_started", userId), player)
		end
		local data = PlayerDataService.data(player)
		if data and data.stats.matches == 1 then
			onboard(player, "second_match_started")
		end
		lastCommand[userId] = lastCommand[userId] or state.tick
	end
	local step = Telemetry.phaseStep(state.phase)
	if step and flowStep(player, step) and step == "results" then
		lastResults[userId] = sessionOf(userId)
		local data = PlayerDataService.data(player)
		if data and data.stats.matches <= 1 then
			onboard(player, "first_match_finished")
		end
	end
	local idleSince = lastCommand[userId] or state.tick
	if state.result == nil and not afk[userId] and state.tick - idleSince >= Config.Progression.AfkTicks then
		afk[userId] = true
		TelemetryService.send(Telemetry.custom("afk_flagged", 1, { state.mapId, state.phase }, userId), player)
	end
end

-- After tick order steps 2-8 (and the rewards), before the delta clears this tick's events.
function TelemetryService.afterTick(state: Types.MatchState)
	if state ~= current then
		newMatch(state)
	end
	sendAll(Telemetry.eliminations(state))
	if not startsLogged and (state.tick >= Config.Telemetry.NationStartTick or state.result ~= nil) then
		startsLogged = true
		sendAll(Telemetry.nationStarts(state))
	end
	for _, player in Players:GetPlayers() do
		observePlayer(state, player)
	end
	if state.result and not endLogged then
		endLogged = true
		sendAll(Telemetry.matchEnd(state))
	end
end

-- Economy and progression -----------------------------------------------------------------------------------------

local function economyFields(player: Player, data: Types.PlayerProfile): { string }
	return Telemetry.economyFields(data, player:GetAttribute("Vip") == true)
end

-- A match reward was granted (ProgressionService): Glory sources and AccountLevel progress. `data` is the profile
-- (needed while the player leaves, when PlayerDataService no longer lists it).
function TelemetryService.reward(player: Player, report: Types.RewardReport, data: Types.PlayerProfile?)
	local profile = data or PlayerDataService.data(player)
	if profile then
		sendAll(Telemetry.reward(report, economyFields(player, profile), player.UserId), player)
	end
end

-- Any other Glory change (quests, login calendar, rerolls...: the features that arrive later).
function TelemetryService.glory(
	player: Player,
	flow: "Source" | "Sink",
	amount: number,
	transaction: string,
	sku: string
)
	local data = PlayerDataService.data(player)
	if data and amount > 0 then
		local e = Telemetry.economy(
			flow,
			Telemetry.GLORY,
			amount,
			data.glory,
			transaction,
			sku,
			economyFields(player, data),
			player.UserId
		)
		TelemetryService.send(e, player)
	end
end

-- SeasonTier progression (the season pass, later): `completed` tier, or the tier just started.
function TelemetryService.seasonTier(player: Player, tier: number, seasonId: string, completed: boolean)
	local status: "Start" | "Complete" = if completed then "Complete" else "Start"
	TelemetryService.send(Telemetry.progression(Telemetry.SEASON_TIER, status, tier, seasonId, player.UserId), player)
end

-- Shop and starter pack ----------------------------------------------------------------------------------------

local function shopSessionOf(player: Player): string
	local session = shopSession[player]
	if session == nil then
		session = newId()
		shopSession[player] = session
	end
	return session
end

local function shopStep(player: Player, item: string, stepName: string)
	local e = if item == STARTER
		then Telemetry.funnel("StarterPack", tostring(player.UserId), stepName, player.UserId)
		else Telemetry.funnel("Shop", shopSessionOf(player), stepName, player.UserId)
	TelemetryService.send(e, player)
end

-- The starter-pack offer was sent to this player (ShopService).
function TelemetryService.starterOffered(player: Player)
	shopStep(player, STARTER, "offer_shown")
end

-- A shop request was answered (ShopService.apply): purchase_prompted, Glory sinks, failed Robux purchases, emotes.
function TelemetryService.shopIntent(player: Player, intent: Types.ShopIntent, ok: boolean, reason: string?)
	if intent.kind == "Emote" then
		if ok then
			TelemetryService.send(Telemetry.custom("emote_used", 1, { intent.item }, player.UserId), player)
		end
		return
	elseif intent.kind ~= "Buy" then
		return
	end
	if not ok then
		if intent.currency == "Robux" then
			local e = Telemetry.custom("purchase_failed", 1, { intent.item, reason or "Unknown" }, player.UserId)
			TelemetryService.send(e, player)
		end
		return
	end
	shopStep(player, intent.item, "purchase_prompted")
	if intent.currency == "Glory" then
		local data = PlayerDataService.data(player)
		local item = Catalogue.item(intent.item)
		if data and item and item.glory then
			local fields = economyFields(player, data)
			TelemetryService.send(
				Telemetry.gloryPurchase(intent.item, item.glory, data.glory, fields, player.UserId),
				player
			)
		end
		shopStep(player, intent.item, "purchase_completed")
	end
end

-- A Robux purchase was granted (a new receipt, not a repeat): the IAP sink and the funnel's last step.
function TelemetryService.purchased(player: Player, id: string, robux: number)
	local data = PlayerDataService.data(player)
	if data then
		TelemetryService.send(Telemetry.robuxPurchase(id, robux, economyFields(player, data), player.UserId), player)
	end
	shopStep(player, id, "purchase_completed")
end

-- The SeasonPass funnel (pass_viewed, purchase_prompted, purchase_completed), for the season pass task.
function TelemetryService.seasonPass(player: Player, seasonId: string, stepName: string)
	local session = player.UserId .. "-" .. seasonId
	TelemetryService.send(Telemetry.funnel("SeasonPass", session, stepName, player.UserId), player)
end

-- Custom events for features that arrive later ----------------------------------------------------------------------

function TelemetryService.questCompleted(player: Player, questId: string, tier: string)
	TelemetryService.send(Telemetry.custom("quest_completed", 1, { questId, tier }, player.UserId), player)
end

-- source: free, vip, ad, glory
function TelemetryService.questRerolled(player: Player, source: string)
	TelemetryService.send(Telemetry.custom("quest_rerolled", 1, { source }, player.UserId), player)
end

-- result: completed, failed
function TelemetryService.adRewarded(player: Player, placement: string, result: string)
	TelemetryService.send(Telemetry.custom("ad_rewarded", 1, { placement, result }, player.UserId), player)
end

-- result: shown (Roblox's opt-in prompt opened; Roblox doesn't tell the game which button was pressed) or
-- ineligible (CanPromptOptInAsync said no: under 13, already opted in, asked in the last 30 days, or it failed)
function TelemetryService.notificationOptIn(player: Player, result: string)
	TelemetryService.send(Telemetry.custom("notification_opt_in", 1, { result }, player.UserId), player)
end

-- Client signals ---------------------------------------------------------------------------------------------------

local function onSignal(player: Player, kind: string, arg: string?)
	if kind == "Loaded" then
		if not clientLoaded[player] then
			clientLoaded[player] = true
			onboard(player, "lobby_loaded") -- or when the profile loads, if it hasn't yet
		end
	elseif kind == "ShopOpened" then
		shopSession[player] = newId()
		shopStep(player, "", "shop_opened")
	elseif kind == "ItemViewed" then
		local session = shopSession[player]
		if session and shopViewed[player] ~= session then
			shopViewed[player] = session
			shopStep(player, "", "item_viewed")
		end
	elseif kind == "OfferOpened" then
		shopStep(player, STARTER, "offer_opened")
	elseif kind == "NotificationPrompt" and (arg == "shown" or arg == "ineligible") and not notified[player] then
		notified[player] = true -- once a session: the server asks a client at most once
		TelemetryService.notificationOptIn(player, arg :: string)
	end
end

function TelemetryService.init()
	CommandRouter.onTelemetry(onSignal)
	CommandRouter.observe(function(player: Player, command: Types.Command, ok: boolean)
		local state = current
		if state == nil then
			return
		end
		lastCommand[player.UserId] = state.tick
		if ok and command.kind == "Power" then
			TelemetryService.send(Telemetry.powerUsed(state, player.UserId, command.power), player)
		end
	end)
	PlayerDataService.onLoaded(function(player: Player, data: Types.PlayerProfile)
		onboard(player, "joined")
		if clientLoaded[player] then
			onboard(player, "lobby_loaded")
		end
		if data.stats.matches == 0 and data.xp == 0 then
			local e =
				Telemetry.progression(Telemetry.ACCOUNT_LEVEL, "Start", 1, Config.Progression.Ranks[1], player.UserId)
			TelemetryService.send(e, player)
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		if LobbyService.active() then
			flowStep(player, "lobby")
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = MatchService.current()
		if state and state == current and not LobbyService.active() then
			sendAll(Telemetry.quit(state, player.UserId), player)
		end
		shopSession[player] = nil
		shopViewed[player] = nil
		notified[player] = nil
		clientLoaded[player] = nil
		lastResults[player.UserId] = nil
	end)
end

return TelemetryService
