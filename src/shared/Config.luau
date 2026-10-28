--!strict
-- Every balance number in the game (docs/DESIGN.md). Times are in ticks; 1 tick = 1 second = 1 game day.
-- Change one or two numbers per playtest, not ten.

local Config = {}

-- Match ------------------------------------------------------------------------------------------

Config.DefaultMap = "skyshards" -- "earth" | "eldmoor" | "skyshards"; used when the Lobby is skipped (SkipLobby)
Config.MaxPlayers = 12
Config.NationsPerMatch = 10
Config.TickSeconds = 1
Config.MonthTicks = 10 -- income and upkeep are paid every month

Config.Phases = {
	LobbyTicks = 60, -- the map vote (also after Results, for the next map)
	PickTicks = 30, -- the whole nation draft; whoever is still waiting when it runs out gets a random nation
	PickTurnMaxTicks = 8, -- one player's turn in the draft: PickTicks / players, within these bounds
	PickTurnMinTicks = 3,
	PeaceEndTick = 3 * 60, -- no wars between nations before this
	WarEndTick = 20 * 60, -- Cataclysm from here
	MatchEndTick = 25 * 60, -- Results from here
	ResultsTicks = 30,
}

-- Start ------------------------------------------------------------------------------------------

Config.StartGold = 100
Config.StartManpower = 3000
Config.NeutralGarrison = 1000 -- men in a neutral province unless the map sets more

-- Economy ----------------------------------------------------------------------------------------

Config.Economy = {
	GoldPerDevelopment = 1, -- per month
	ManpowerPerDevelopment = 100, -- per month
	CapitalGold = 5, -- per month
	MaxDevelopment = 5,
	DevelopCostPerLevel = 30, -- developing costs this × current level
}

Config.Buildings = {
	Farm = { cost = 50, goldBonus = 0.5 },
	Barracks = { cost = 40, manpowerBonus = 0.5 },
	Fort = { cost = 60, defenceBonus = 0.5, siegeMultiplier = 2 },
}

-- Armies -----------------------------------------------------------------------------------------

Config.Army = {
	MenPerRegiment = 1000,
	RegimentGold = 10,
	RegimentManpower = 1000,
	UpkeepPerRegiment = 1.5, -- gold per month: income / 1.5 is the army a nation can keep (docs/BALANCE.md 15)
	MaxRecruitPerCommand = 10, -- regiments in one Recruit intent
	MoveTicks = { Plains = 5, Forest = 8, Hills = 8 },
	MinArmyMen = 500, -- smaller armies are destroyed after a battle
}

Config.Battle = {
	Rounds = 3,
	KillRatePerRound = 0.15, -- each side kills this × its own strength × modifiers
	TerrainDefenceBonus = 0.25, -- defender in forest or hills
	UnderdogBonus = 0.5, -- a defending underdog holds like a fort (docs/BALANCE.md 5)
	CoalitionBonus = 0.3,
	RandomSpread = 0.1, -- ± per battle
}

Config.Siege = {
	TicksPerDevelopment = 10,
	CapitalMultiplier = 3,
	GraceTicks = 10, -- an interrupted siege keeps its progress this long
}

-- Diplomacy --------------------------------------------------------------------------------------

Config.Diplomacy = {
	MaxAllianceSize = 3,
	TruceTicks = 3 * 60,
	CoalitionThreshold = 0.2, -- share of the ownable provinces (not mountains) that puts a crown on a nation
	OfferTicks = 30, -- alliance and peace offers expire after this
	PeaceTributes = { 0, 50, 100 }, -- gold a peace offer can include (the buttons in the province sheet)
}

-- Primordial powers ------------------------------------------------------------------------------

Config.Primordial = {
	NationChargeTicks = 4 * 60,
	PrimordialChargeTicks = 60,
	ImmunityTicks = 30, -- a nation is hit at most once per 30 s (by a harmful power)
	MaxCharges = 5, -- charges stop piling up here (nations and Primordials alike)
	EliminationProvinces = 3, -- a nation without its capital and with fewer provinces than this is eliminated
	CataclysmChargeMultiplier = 2,
	CataclysmDisasterTicks = 60,
	Powers = {
		Meteor = { charges = 2, armyLoss = 0.5, developmentLoss = 1 },
		Plague = { charges = 2, manpowerLoss = 0.5, ticks = 60 },
		Rebels = { charges = 2, men = 3000 },
		Earthquake = { charges = 1 },
		Blessing = { charges = 1, goldBonus = 1.0, ticks = 60 },
		Shield = { charges = 1, ticks = 30 },
	},
}

-- Catch-up ---------------------------------------------------------------------------------------

Config.CatchUp = {
	OverextensionStart = 20, -- provinces
	OverextensionStep = 5, -- every this many extra provinces...
	OverextensionPenalty = 0.05, -- ...cut gold income by this
	UnderdogCount = 3, -- the nations with the fewest provinces get the underdog bonus
}

-- Win conditions ---------------------------------------------------------------------------------

Config.Win = {
	DominationShare = 0.5, -- of the ownable provinces (mountains don't count): half the land wins
	AllianceShare = 0.65,
	ScorePerProvince = 10,
	ScorePerDevelopment = 5,
	ScorePerBattleWon = 2,
}

-- Progression (docs/MONETIZATION.md 4.1, 5.1–5.3): account XP and Glory a match pays, the level curve, ranks.
-- Placement tables are indexed by finishing place 1..10.

Config.Progression = {
	FinishXp = 100, -- stayed to Results; leaving early prorates it by minutes played
	FinishGlory = 20,
	PlacementXp = { 150, 100, 75, 50, 50, 25, 25, 25, 25, 25 }, -- alliance victory: every member is 1st
	PlacementGlory = { 40, 30, 20, 15, 15, 10, 10, 10, 10, 10 },
	ProvinceXp = 5, -- per province captured
	MaxProvinceXp = 100,
	BattleXp = 5, -- per battle won
	MaxBattleXp = 50,
	ActivityGlory = 1, -- per province captured and per battle won...
	MaxActivityGlory = 15, -- ...up to this, both together
	PrimordialXp = 50, -- rose as a Primordial and stayed to Results
	PrimordialGlory = 10,
	PowerXp = 10, -- per Primordial power used
	MaxPowerXp = 50,
	FirstMatchXp = 200, -- first finished match of the UTC day
	FirstMatchGlory = 50,
	VipBonus = 0.25, -- VIP: +25% of match XP and Glory (not the first-match bonus)
	CustomRulesShare = 0.5, -- private servers with custom rules pay half
	AfkTicks = 5 * 60, -- no command for this long in a row: the match pays nothing
	LateJoinGraceTicks = 60, -- joining in the first minute still counts as playing the whole match
	LevelBaseXp = 300, -- XP from level L to L+1 = LevelBaseXp + LevelStepXp × (L − 1)
	LevelStepXp = 60,
	MaxLevel = 100,
	LevelUpGlory = 50,
	RankUpGlory = 500,
	LevelsPerRank = 10,
	Ranks = {
		"Settler",
		"Chieftain",
		"Baron",
		"Count",
		"Duke",
		"Prince",
		"King",
		"Emperor",
		"Conqueror",
		"World Shaker",
		"Primordial",
	},
}

-- Quests (docs/MONETIZATION.md 5.4–5.5): 3 daily quests (one per tier) and 3 weekly ones, picked from the pool by a
-- generator seeded with the player and the day or week. stat: what counts (Sim.Quests.tally); max = true: the best
-- single match counts, not the sum. Every quest can be done in normal play on every map; none asks to lose, betray
-- an ally, quit or buy anything (being a Primordial needs losing your nation, so no Primordial-only quests).
Config.Progression.Quests = {
	Rewards = {
		Easy = { xp = 100, glory = 30 },
		Medium = { xp = 150, glory = 40 },
		Hard = { xp = 200, glory = 50 },
		Weekly = { xp = 1000, glory = 150 },
	},
	WeeklyCount = 3,
	DailyKeepDays = 2, -- an unfinished daily quest stays on the day it came and the next one
	MaxWaiting = 6, -- unfinished daily quests kept at most (the oldest go first)
	FreeRerolls = 1, -- per day (VIP adds Config.Shop.VipQuestRerolls)
	VideoRerolls = 2, -- per day from the rewarded video (Phase 5)
	RerollGlory = 100, -- a reroll after the free ones
	Pool = {
		{ id = "play1", tier = "Easy", stat = "Matches", target = 1 },
		{ id = "neutral3", tier = "Easy", stat = "NeutralCaptures", target = 3 },
		{ id = "recruit5", tier = "Easy", stat = "Regiments", target = 5 },
		{ id = "build2", tier = "Easy", stat = "Buildings", target = 2 },
		{ id = "develop3", tier = "Easy", stat = "Developments", target = 3 },
		{ id = "battles3", tier = "Medium", stat = "Battles", target = 3 },
		{ id = "devlevel4", tier = "Medium", stat = "DevLevel", target = 4, max = true },
		{ id = "ally1", tier = "Medium", stat = "Alliances", target = 1 },
		{ id = "top5", tier = "Medium", stat = "Top5", target = 1 },
		{ id = "powers2", tier = "Medium", stat = "Powers", target = 2 },
		{ id = "capital1", tier = "Hard", stat = "Capitals", target = 1 },
		{ id = "hold25", tier = "Hard", stat = "Held", target = 25, max = true },
		{ id = "top3", tier = "Hard", stat = "Top3", target = 1 },
		{ id = "battles6", tier = "Hard", stat = "Battles", target = 6 },
		{ id = "capture10", tier = "Hard", stat = "Captures", target = 10 },
		{ id = "w_matches10", tier = "Weekly", stat = "Matches", target = 10 },
		{ id = "w_win1", tier = "Weekly", stat = "Wins", target = 1 },
		{ id = "w_capture100", tier = "Weekly", stat = "Captures", target = 100 },
		{ id = "w_battles50", tier = "Weekly", stat = "Battles", target = 50 },
		{ id = "w_powers15", tier = "Weekly", stat = "Powers", target = 15 },
		{ id = "w_top3x3", tier = "Weekly", stat = "Top3", target = 3 },
	},
}

-- Login calendar and play streak (docs/MONETIZATION.md 5.6). Both move only on a day with a finished match.
Config.Progression.Login = {
	CalendarGlory = { 25, 25, 50, 50, 75, 75, 200 }, -- the 7 steps; missing days pause it, never reset it
	StreakFlames = { 3, 7, 14, 30 }, -- streak days for: a flame, a bigger flame, a blue flame, "the Unyielding"
	CoveredMissesPerWeek = 1, -- missed days a week that don't break the streak
}

-- Shop (docs/MONETIZATION.md 3.1–3.5): prices by rarity, offers, emotes. Robux numbers are list prices: the shop
-- shows MarketplaceService's live price once a product id is set (Shared.Catalogue), so managed pricing can test it.
-- Glory is never sold.

Config.Shop = {
	RobuxPrice = { Common = 49, Rare = 99, Epic = 149, Legendary = 249 },
	GloryPrice = { Common = 500, Rare = 1200, Epic = 2500 }, -- Legendary: Robux, season pass or achievement only
	EmoteRobux = { Static = 25, Animated = 49 },
	EmoteGlory = { Static = 300, Animated = 500 },
	VipRobux = 249, -- game pass
	StarterPackRobux = 149, -- once per account
	RareSetRobux = 199, -- nation skin set: flag + border + token
	StarterPackAfterMatches = 2, -- the starter-pack offer pops up (once per session) from this many finished matches
	EmoteCooldownTicks = 10, -- one capital emote per player per this many seconds
	EmoteShowSeconds = 3, -- how long an emote shows over the capital
	VipQuestRerolls = 1, -- extra daily quest reroll for VIP (Sim.Quests)
	HistoryShown = 20, -- newest Robux purchases on the Purchase History screen
}

-- Network and security ---------------------------------------------------------------------------

Config.Net = {
	MaxIntentsPerSecond = 10,
	MaxShopIntentsPerSecond = 2, -- shop requests (buy, equip, emote, theme setting) on top of that, per player
}

-- Bots -------------------------------------------------------------------------------------------

Config.Bots = {
	-- noPlayerWarTicks: no war declared on a player before this tick; targetsLeadingPlayer: wars go to the player
	-- holding the most provinces first
	Easy = { planTicks = 6, attackRatio = 1.6, noPlayerWarTicks = 8 * 60, targetsLeadingPlayer = false },
	Normal = { planTicks = 3, attackRatio = 1.3, noPlayerWarTicks = 0, targetsLeadingPlayer = false },
	Hard = { planTicks = 2, attackRatio = 1.1, noPlayerWarTicks = 0, targetsLeadingPlayer = true },
	Difficulty = "Normal", -- what every bot plays on (a private server's owner can pick another: Config.Private)
	DefendRatio = 0.8,
	MenPerProvince = 800,
	BotsPlanningPerTick = 2,
	RecruitBatch = 3, -- regiments per Recruit when topping up (defending recruits what the threat needs)
	PeaceLossShare = 0.3, -- accept (and offer) white peace after losing this share of my provinces in a war
	UpkeepReserveMonths = 2, -- build only with gold left over after this many months of upkeep
	OfferCooldownTicks = 90, -- a bot repeats an alliance or peace offer to the same nation at most this often
	MaxRouteChecks = 6, -- paths checked per army per plan (keeps planning cheap)
}

-- Private servers (docs/MONETIZATION.md 3.4): what the owner may pick in the Lobby's settings sheet. The defaults
-- (Sim.Settings.defaults) are what public servers play: Config.Phases, Config.Bots.Difficulty, everything on.

Config.Private = {
	Minutes = { 15, 25, 35 }, -- match length; the Cataclysm is always its last (MatchEndTick - WarEndTick) ticks
	PeaceMinutes = { 0, 3, 5 },
	MaxBots = 9, -- bots 0..9; 9 fills every nation nobody plays
	Difficulties = { "Easy", "Normal", "Hard" },
	Themes = { "Vote", "Default" }, -- "Default" forces every map's default theme
	Teams = 4, -- team numbers the owner can give players (0 = no team); a team holds Config.Diplomacy.MaxAllianceSize
	FullRewardHumans = 4, -- a private match pays full XP and Glory with default rules and this many players
}

-- Tutorial (docs/DESIGN.md "Tutorial"): a new player's first match, on a reserved server of its own -------------

Config.Tutorial = {
	Map = "earth",
	PlayerSlot = 4, -- Ganges: borders three nations and has weak neutral land next door
	Bots = 5, -- the nations nearest the player stay, as bots; the rest of the map turns neutral
	Difficulty = "Easy",
	StartRegiments = 3, -- a ready army at the capital, so the first prompt (take a neutral province) can start at once
	GiftCharges = 1, -- the power prompt tops the player's charges up to this (a Blessing costs 1)
	TeleportRetries = 3, -- a failed teleport back to a public server is tried again this many times...
	TeleportRetrySeconds = 5, -- ...this long apart
}

-- Analytics (docs/LAUNCH.md "Analytics events"): Services/TelemetryService and Sim.Telemetry -------------------

Config.Telemetry = {
	BudgetBase = 120, -- AnalyticsService requests per window: BudgetBase + BudgetPerPlayer × players in the server
	BudgetPerPlayer = 20,
	BudgetWindowSeconds = 60, -- past the budget, events are dropped until the next window starts
	NationStartTick = 60, -- nation_start records who holds each start nation after the first minute (or at Results)
	HumanBuckets = { 3, 6, 12 }, -- match_end's humans field: 1-3, 4-6, 7-12
	LevelBuckets = { 9, 29 }, -- economy level_bucket: 1-9, 10-29, 30+
	OnboardingMatches = 2, -- onboarding steps are logged until a player has finished this many matches
	ClientSignalsPerSecond = 5, -- UI funnel signals one client may send (RequestTelemetry)
}

-- Rewarded video and experience notifications (docs/MONETIZATION.md 3.7, 7.6). The daily cap on ad rerolls is
-- Config.Progression.Quests.VideoRerolls.
Config.Ads = {
	QuestRerollRobux = 10, -- the "Quest reroll" developer product's price (Roblox wants an ad reward worth 3-10 Robux)
	MinVoteSecondsLeft = 32, -- ads only start in the map vote with this long left (a video lasts 6-30 s): never the draft
	NotificationPromptDelaySeconds = 2, -- back in the Lobby after the first finished match, wait this long, then ask
}

return Config
