--!strict
-- Analytics event payloads (docs/LAUNCH.md "Analytics events"): the event plan as data, and pure builders that turn
-- match state, lobby votes, rewards and purchases into TelemetryEvents. Services/TelemetryService only sends them to
-- Roblox's AnalyticsService. Also the per-minute request budget (120 + 20 × players).
--
-- No names, chat or other personal data: events carry a userId only so the service can hand AnalyticsService the
-- Player it requires. Custom field values are short strings (map ids, nation slots, buckets, item ids).

local Config = require("../Config")
local Diplomacy = require("./Diplomacy")
local Progression = require("./Progression")
local Types = require("../Types")

type MatchState = Types.MatchState
type Event = Types.TelemetryEvent

local T = Config.Telemetry

local Telemetry = {}

-- The plan -----------------------------------------------------------------------------------------------------

-- Every custom event name (AnalyticsService allows 100). LogCustomEvent is only ever called with one of these.
Telemetry.CUSTOM_EVENTS = {
	"nation_start",
	"match_win",
	"match_end",
	"player_quit",
	"player_eliminated",
	"player_result",
	"primordial_power_used",
	"bot_replaced_leaver",
	"afk_flagged",
	"map_vote",
	"quest_completed",
	"quest_rerolled",
	"ad_rewarded",
	"emote_used",
	"purchase_failed",
	"notification_opt_in",
	"tutorial_skipped",
	"sandbox_started",
	"menu_shown",
	"menu_choice",
	"first_pick",
	"ping_sent",
	-- the EU4 pack (docs/DESIGN.md)
	"diplomacy_action",
	"event_card",
	"music_setting",
}

-- The EU4 pack's diplomatic actions diplomacy_action logs, by Command action (field 1).
local DIPLOMACY_ACTIONS: { [string]: string } = {
	Insult = "insult",
	InsultBack = "insult_back",
	LaughOff = "laugh_off",
	Gift = "gift",
	Access = "access_asked",
	AcceptAccess = "access_granted",
}

-- The one-time onboarding funnel (LogOnboardingFunnelStepEvent), in step order.
Telemetry.ONBOARDING = {
	"joined",
	"lobby_loaded",
	"map_voted",
	"nation_picked",
	"first_neutral_captured", -- 5-10: the tutorial's six prompts, in order (Sim.Tutorial.STEPS)
	"first_recruit",
	"first_siege_done",
	"first_ally",
	"first_war",
	"first_power_used",
	"first_match_finished",
	"second_match_started",
}

-- Recurring funnels (LogFunnelStepEvent; Roblox allows 10), each with its steps in order.
Telemetry.FUNNELS = {
	MatchFlow = { "lobby", "pick", "peace", "war", "cataclysm", "results", "next_match_started" },
	Shop = { "shop_opened", "item_viewed", "purchase_prompted", "purchase_completed" },
	StarterPack = { "offer_shown", "offer_opened", "purchase_prompted", "purchase_completed" },
	SeasonPass = { "pass_viewed", "purchase_prompted", "purchase_completed" }, -- ready for the season pass
} :: { [string]: { string } }

-- UI-only funnel steps the client reports (RequestTelemetry): only these kinds are accepted.
Telemetry.CLIENT_SIGNALS = {
	Loaded = true, -- the client finished building its screens: onboarding "lobby_loaded"
	ShopOpened = true, -- Shop funnel step 1 (a new shop session)
	ItemViewed = true, -- Shop funnel step 2 (another tab or page of items)
	OfferOpened = true, -- StarterPack funnel step 2 (the pop-up is on screen)
	NotificationPrompt = true, -- notification_opt_in: "shown" (Roblox's opt-in prompt opened) or "ineligible"
	MenuChoice = true, -- menu_choice for the start menu's UI-only choices: "singleplayer" or "guide"
} :: { [string]: boolean }

-- menu_choice's choices: the start menu's three buttons. Play online is logged by the server when it acts on it;
-- Singleplayer (opening its map cards) and How to play come from the client (MenuChoice).
Telemetry.MENU_CHOICES = {
	online = true,
	singleplayer = true,
	guide = true,
} :: { [string]: boolean }

Telemetry.GLORY = "Glory"
Telemetry.ROBUX = "Robux"
Telemetry.ACCOUNT_LEVEL = "AccountLevel"
Telemetry.SEASON_TIER = "SeasonTier"

-- MatchFlow step for a match phase (Lobby and Pick are logged when they happen, not from MatchState.phase).
local PHASE_STEPS: { [string]: string } = {
	Peace = "peace",
	War = "war",
	Cataclysm = "cataclysm",
	Results = "results",
}

local customNames: { [string]: boolean } = {}
for _, name in Telemetry.CUSTOM_EVENTS do
	customNames[name] = true
end

-- Generic builders --------------------------------------------------------------------------------------------

local function blank(kind: string, name: string, value: number, userId: number?): Event
	return {
		kind = kind :: any,
		userId = userId,
		name = name,
		value = value,
		step = nil,
		session = nil,
		flow = nil,
		transaction = nil,
		balance = nil,
		fields = {},
	}
end

-- A custom event. `fields` are up to 3 strings (custom fields 1-3). Unknown names are a programming error.
function Telemetry.custom(name: string, value: number, fields: { string }, userId: number?): Event
	assert(customNames[name], "unknown custom event " .. name)
	assert(#fields <= 3, "at most 3 custom fields")
	local e = blank("Custom", name, value, userId)
	e.fields = fields
	return e
end

-- A recurring funnel step, by step name.
function Telemetry.funnel(funnel: string, session: string, stepName: string, userId: number): Event
	local steps = assert(Telemetry.FUNNELS[funnel], "unknown funnel " .. funnel)
	local step = assert(table.find(steps, stepName), "unknown step " .. stepName .. " in " .. funnel)
	local e = blank("Funnel", funnel, step, userId)
	e.step = stepName
	e.session = session
	return e
end

-- An onboarding funnel step, by step name.
function Telemetry.onboarding(stepName: string, userId: number): Event
	local step = assert(table.find(Telemetry.ONBOARDING, stepName), "unknown onboarding step " .. stepName)
	local e = blank("Onboarding", "Onboarding", step, userId)
	e.step = stepName
	return e
end

-- An economy event. amount is positive for sources and sinks alike (Roblox shows sinks as negative).
function Telemetry.economy(
	flow: "Source" | "Sink",
	currency: string,
	amount: number,
	balance: number,
	transaction: string,
	sku: string,
	fields: { string },
	userId: number
): Event
	local e = blank("Economy", currency, amount, userId)
	e.flow = flow
	e.balance = balance
	e.transaction = transaction
	e.step = sku
	e.fields = fields
	return e
end

-- A progression event: "Start" or "Complete" a level of a path.
function Telemetry.progression(
	path: string,
	status: "Start" | "Complete",
	level: number,
	levelName: string,
	userId: number
): Event
	local e = blank("Progression", path, level, userId)
	e.flow = status
	e.step = levelName
	return e
end

-- Field values -------------------------------------------------------------------------------------------------

-- Match minutes with one decimal (1 tick = 1 second).
function Telemetry.minutes(tick: number): number
	return math.floor(tick * Config.TickSeconds / 6) / 10
end

-- "1-3", "4-6", "7-12" from Config.Telemetry.HumanBuckets; "0" when no human played.
function Telemetry.humansBucket(humans: number): string
	if humans <= 0 then
		return "0"
	end
	local low = 1
	for _, high in T.HumanBuckets do
		if humans <= high then
			return string.format("%d-%d", low, high)
		end
		low = high + 1
	end
	return string.format("%d+", low)
end

-- "1-9", "10-29", "30+" from Config.Telemetry.LevelBuckets.
function Telemetry.levelBucket(level: number): string
	local low = 1
	for _, high in T.LevelBuckets do
		if level <= high then
			return string.format("%d-%d", low, high)
		end
		low = high + 1
	end
	return string.format("%d+", low)
end

local function flag(b: boolean): string
	return if b then "true" else "false"
end

-- The economy events' custom fields: level_bucket, is_vip, is_payer.
function Telemetry.economyFields(profile: Types.PlayerProfile, vip: boolean): { string }
	return { Telemetry.levelBucket(profile.level), flag(vip), flag(#profile.purchaseHistory > 0) }
end

function Telemetry.phaseStep(phase: string): string?
	return PHASE_STEPS[phase]
end

function Telemetry.winType(result: Types.MatchResult): string
	return string.lower(result.kind)
end

-- Did a human hold this nation at some point (now, or before leaving)?
local function humanHeld(state: MatchState, nationId: number): boolean
	if state.nations[nationId].userId ~= nil then
		return true
	end
	for _, held in state.seats do
		if held == nationId then
			return true
		end
	end
	return false
end

local function sortedNations(state: MatchState): { number }
	local ids = {}
	for id in state.nations do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

-- Match events -------------------------------------------------------------------------------------------------

-- nation_start for every nation (logged once per match, after Config.Telemetry.NationStartTick or at Results):
-- win rate by start position is match_win ÷ nation_start. Match-wide events have no userId.
function Telemetry.nationStarts(state: MatchState): { Event }
	local out = {}
	for _, id in sortedNations(state) do
		local controller = if humanHeld(state, id) then "human" else "bot"
		table.insert(out, Telemetry.custom("nation_start", 1, { state.mapId, tostring(id), controller }))
	end
	return out
end

-- At Results: match_end (match minutes), match_win for every winner, player_result (placement) for every nation.
function Telemetry.matchEnd(state: MatchState): { Event }
	local result = assert(state.result, "the match has no result")
	local winType = Telemetry.winType(result)
	local humans = 0
	for _ in state.seats do
		humans += 1
	end
	local out = {
		Telemetry.custom(
			"match_end",
			Telemetry.minutes(result.endedAt),
			{ state.mapId, winType, Telemetry.humansBucket(humans) }
		),
	}
	for _, id in result.winners do
		table.insert(out, Telemetry.custom("match_win", 1, { state.mapId, tostring(id), winType }))
	end
	for _, id in sortedNations(state) do
		local nation = state.nations[id]
		local controller = if nation.userId ~= nil then "human" else "bot"
		local e = Telemetry.custom(
			"player_result",
			Progression.placement(result, id),
			{ state.mapId, tostring(id), controller },
			nation.userId
		)
		table.insert(out, e)
	end
	return out
end

-- This tick's eliminations of nations a player holds (call before the events are cleared).
function Telemetry.eliminations(state: MatchState): { Event }
	local out = {}
	for _, e in state.events do
		local nation = if e.kind == "Eliminated" then state.nations[e.a] else nil
		if nation and nation.userId then
			table.insert(
				out,
				Telemetry.custom(
					"player_eliminated",
					Telemetry.minutes(state.tick),
					{ state.mapId, tostring(nation.id), state.phase },
					nation.userId
				)
			)
		end
	end
	return out
end

-- A player leaves a running match: player_quit (if they had a nation or a Primordial), and bot_replaced_leaver
-- when a bot takes over their living nation. Nothing once the match has a result.
function Telemetry.quit(state: MatchState, userId: number): { Event }
	local out = {}
	if state.result ~= nil then
		return out
	end
	local held = state.seats[userId]
	local primordial = state.primordials[userId] ~= nil
	if held == nil and not primordial then
		return out -- never played in this match
	end
	local minute = Telemetry.minutes(state.tick)
	table.insert(out, Telemetry.custom("player_quit", minute, { state.mapId, state.phase, flag(primordial) }, userId))
	local nation = if held then state.nations[held] else nil
	if nation and not nation.eliminated then
		table.insert(out, Telemetry.custom("bot_replaced_leaver", minute, { state.mapId, state.phase }, userId))
	end
	return out
end

-- A player used a Primordial power: as a living nation or as a Primordial.
function Telemetry.powerUsed(state: MatchState, userId: number, power: string): Event
	local living = false
	for _, nation in state.nations do
		if nation.userId == userId and not nation.eliminated then
			living = true
		end
	end
	local kind = if living then "living" else "primordial"
	return Telemetry.custom("primordial_power_used", 1, { power, state.mapId, kind }, userId)
end

-- A player pinged a province for their allies (Sim.Pings): the kind, the map, and whose province it is to the
-- sender: own, ally, enemy (at war with the sender) or neutral (unowned land, or a nation at peace with them).
function Telemetry.pingSent(state: MatchState, userId: number, kind: string, province: number): Event
	local sender = 0
	for id, nation in state.nations do
		if nation.userId == userId and not nation.eliminated then
			sender = id
		end
	end
	local p = state.provinces[province]
	local owner = if p then p.owner or 0 else 0
	local target = if owner ~= 0 and owner == sender
		then "own"
		elseif Diplomacy.allied(state, sender, owner) then "ally"
		elseif Diplomacy.atWar(state, sender, owner) then "enemy"
		else "neutral"
	return Telemetry.custom("ping_sent", 1, { string.lower(kind), state.mapId, target }, userId)
end

-- The sandbox ---------------------------------------------------------------------------------------------------

-- A sandbox world started for a player: start is "first" (they just arrived) or "new_world" (they made another).
function Telemetry.sandboxStarted(mapId: string, start: string, userId: number): Event
	return Telemetry.custom("sandbox_started", 1, { mapId, start }, userId)
end

-- What a sandbox server may send: sandbox_started and the economy events (real Robux and Glory spent in the shop).
-- No funnels, no onboarding steps, no match or player events: a sandbox is not a match.
function Telemetry.sandboxAllows(e: Event): boolean
	return e.kind == "Economy" or (e.kind == "Custom" and e.name == "sandbox_started")
end

-- The start menu ------------------------------------------------------------------------------------------------

-- What the server is doing while a player looks at the start menu: "first" (the first pick), "lobby" (the vote),
-- "pick" (the draft), "match" or "results". `lobby` is the open lobby (nil during a match), `matchPhase` the
-- running match's phase.
function Telemetry.menuWhere(lobby: Types.LobbyState?, matchPhase: string?): string
	if lobby then
		if lobby.phase == "Pick" then
			return "pick"
		end
		return if lobby.first then "first" else "lobby"
	end
	return if matchPhase == "Results" then "results" else "match"
end

-- The start menu opened for a player arriving on a public or private server.
function Telemetry.menuShown(where: string, private: boolean, userId: number): Event
	return Telemetry.custom("menu_shown", 1, { where, if private then "private" else "public" }, userId)
end

-- A start-menu choice (Telemetry.MENU_CHOICES) and what the server was doing (Telemetry.menuWhere).
function Telemetry.menuChoice(choice: string, where: string, userId: number): Event
	assert(Telemetry.MENU_CHOICES[choice], "unknown menu choice " .. choice)
	return Telemetry.custom("menu_choice", 1, { choice, where }, userId)
end

-- The first pick is over on `mapId`: the seconds the chooser took, the map, and whether they picked it ("picked")
-- or the time ran out ("timeout"). nil when the lobby wasn't a first pick or nobody was in line.
function Telemetry.firstPick(lobby: Types.LobbyState, mapId: string): Event?
	local chooser = lobby.queue[1]
	if not lobby.first or chooser == nil then
		return nil
	end
	local seconds = Config.Phases.FirstPickTicks - math.max(lobby.ticksLeft, 0)
	local how = if lobby.votes[chooser] then "picked" else "timeout"
	return Telemetry.custom("first_pick", seconds, { mapId, how }, chooser)
end

-- The EU4 pack --------------------------------------------------------------------------------------------------

-- A player's insult, answer to an insult, gift or military access request or grant went through: diplomacy_action with the
-- action, the map and who it was aimed at (human, bot). nil for any other command.
function Telemetry.diplomacy(state: MatchState, userId: number, command: Types.Command): Event?
	if command.kind ~= "Diplomacy" then
		return nil
	end
	local action = DIPLOMACY_ACTIONS[command.action]
	local target = state.nations[command.target]
	if action == nil or target == nil then
		return nil
	end
	local aimed = if target.userId ~= nil then "human" else "bot"
	return Telemetry.custom("diplomacy_action", 1, { action, state.mapId, aimed }, userId)
end

-- A player's event card closed (the EU4 pack, Sim.EventCards): event_card with the event, the map, and how it ended
-- ("picked_1", "picked_2", or "timeout_N" when time ran out and default choice N happened). nil without one.
function Telemetry.eventCard(state: MatchState, userId: number, outcome: Types.EventOutcome?): Event?
	if outcome == nil then
		return nil
	end
	local how = (if outcome.auto then "timeout_" else "picked_") .. outcome.choice
	return Telemetry.custom("event_card", 1, { outcome.event, state.mapId, how }, userId)
end

-- The speaker ----------------------------------------------------------------------------------------------------

-- A speaker toggle changed (RequestPreference "music" or "sounds"): both toggles after the change ("on" or "off")
-- and what the server was doing (Telemetry.menuWhere).
function Telemetry.musicSetting(music: boolean, sounds: boolean, where: string, userId: number): Event
	local function onOff(on: boolean): string
		return if on then "on" else "off"
	end
	return Telemetry.custom("music_setting", 1, { onOff(music), onOff(sounds), where }, userId)
end

-- The map vote is over: one map_vote per voter. round: "lobby" (the first vote on this server) or "next" (after
-- Results). themes: map id -> texture theme.
function Telemetry.mapVotes(lobby: Types.LobbyState, round: string, themes: { [string]: string }): { Event }
	local voters = {}
	for userId in lobby.votes do
		table.insert(voters, userId)
	end
	table.sort(voters)
	local out = {}
	for _, userId in voters do
		local map = lobby.votes[userId]
		table.insert(out, Telemetry.custom("map_vote", 1, { map, round, themes[map] or "?" }, userId))
	end
	return out
end

-- Economy and progression ---------------------------------------------------------------------------------------

-- A match reward was granted (Progression.grant's report): Glory sources (match_reward, level_up, achievement) with
-- their ending balances, and AccountLevel progression (Complete for every level passed, Start for the new one).
function Telemetry.reward(report: Types.RewardReport, fields: { string }, userId: number): { Event }
	local out = {}
	local levelGlory, matchGlory, achievementGlory = 0, 0, 0
	for _, line in report.reward.lines do
		if line.kind == "LevelUp" or line.kind == "RankUp" then
			levelGlory += line.glory
		elseif line.kind == "Achievement" then
			achievementGlory += line.glory -- achievements the match unlocked (Sim.Achievements)
		else
			matchGlory += line.glory
		end
	end
	local function rankName(level: number): string
		local _, name = Progression.rankFor(level)
		return name
	end
	local final = report.after.glory
	if matchGlory > 0 then
		table.insert(
			out,
			Telemetry.economy(
				"Source",
				Telemetry.GLORY,
				matchGlory,
				final - levelGlory - achievementGlory,
				"Gameplay",
				"match_reward",
				fields,
				userId
			)
		)
	end
	if levelGlory > 0 then
		table.insert(
			out,
			Telemetry.economy(
				"Source",
				Telemetry.GLORY,
				levelGlory,
				final - achievementGlory,
				"Gameplay",
				"level_up",
				fields,
				userId
			)
		)
	end
	if achievementGlory > 0 then
		table.insert(
			out,
			Telemetry.economy(
				"Source",
				Telemetry.GLORY,
				achievementGlory,
				final,
				"Gameplay",
				"achievement",
				fields,
				userId
			)
		)
	end
	for level = report.before.level, report.after.level - 1 do
		table.insert(out, Telemetry.progression(Telemetry.ACCOUNT_LEVEL, "Complete", level, rankName(level), userId))
	end
	if report.after.level > report.before.level then
		local level = report.after.level
		table.insert(out, Telemetry.progression(Telemetry.ACCOUNT_LEVEL, "Start", level, rankName(level), userId))
	end
	return out
end

-- A Glory purchase in the shop: a Shop sink with the item id and the balance after it.
function Telemetry.gloryPurchase(
	item: string,
	price: number,
	balance: number,
	fields: { string },
	userId: number
): Event
	return Telemetry.economy("Sink", Telemetry.GLORY, price, balance, "Shop", item, fields, userId)
end

-- A Robux purchase (game pass or developer product). Roblox doesn't tell games a player's Robux balance: 0.
function Telemetry.robuxPurchase(id: string, robux: number, fields: { string }, userId: number): Event
	return Telemetry.economy("Sink", Telemetry.ROBUX, robux, 0, "IAP", id, fields, userId)
end

-- Budget -------------------------------------------------------------------------------------------------------

export type Budget = { windowStart: number, used: number, dropped: number }

function Telemetry.newBudget(): Budget
	return { windowStart = -math.huge, used = 0, dropped = 0 }
end

-- Requests allowed per window with this many players in the server.
function Telemetry.limit(players: number): number
	return T.BudgetBase + T.BudgetPerPlayer * math.max(0, players)
end

-- May one more event go out at time `now` (seconds)? Fixed windows of Config.Telemetry.BudgetWindowSeconds.
-- The second result is how many events the window that just ended dropped (0 if none, or still in the window).
function Telemetry.allow(budget: Budget, now: number, players: number): (boolean, number)
	local droppedBefore = 0
	if now - budget.windowStart >= T.BudgetWindowSeconds then
		droppedBefore = budget.dropped
		budget.windowStart = now
		budget.used = 0
		budget.dropped = 0
	end
	if budget.used >= Telemetry.limit(players) then
		budget.dropped += 1
		return false, droppedBefore
	end
	budget.used += 1
	return true, droppedBefore
end

return Telemetry
