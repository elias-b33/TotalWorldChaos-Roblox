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
Config.StartManpower = 5000
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
	UpkeepPerRegiment = 0.5, -- gold per month
	MaxRecruitPerCommand = 10, -- regiments in one Recruit intent
	MoveTicks = { Plains = 5, Forest = 8, Hills = 8 },
	MinArmyMen = 500, -- smaller armies are destroyed after a battle
}

Config.Battle = {
	Rounds = 3,
	KillRatePerRound = 0.15, -- each side kills this × its own strength × modifiers
	TerrainDefenceBonus = 0.25, -- defender in forest or hills
	UnderdogBonus = 0.2,
	CoalitionBonus = 0.1,
	RandomSpread = 0.1, -- ± per battle
}

Config.Siege = {
	TicksPerDevelopment = 10,
	CapitalMultiplier = 3,
}

-- Diplomacy --------------------------------------------------------------------------------------

Config.Diplomacy = {
	MaxAllianceSize = 3,
	TruceTicks = 3 * 60,
	CoalitionThreshold = 0.25, -- share of all provinces that puts a crown on a nation
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
	DominationShare = 0.4,
	AllianceShare = 0.55,
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

-- Network and security ---------------------------------------------------------------------------

Config.Net = {
	MaxIntentsPerSecond = 10,
}

-- Bots -------------------------------------------------------------------------------------------

Config.Bots = {
	-- noPlayerWarTicks: no war declared on a player before this tick; targetsLeadingPlayer: wars go to the player
	-- holding the most provinces first
	Easy = { planTicks = 6, attackRatio = 1.6, noPlayerWarTicks = 8 * 60, targetsLeadingPlayer = false },
	Normal = { planTicks = 3, attackRatio = 1.3, noPlayerWarTicks = 0, targetsLeadingPlayer = false },
	Hard = { planTicks = 2, attackRatio = 1.1, noPlayerWarTicks = 0, targetsLeadingPlayer = true },
	Difficulty = "Normal", -- what every bot plays on; private servers may pick later
	DefendRatio = 0.8,
	MenPerProvince = 800,
	BotsPlanningPerTick = 2,
	RecruitBatch = 3, -- regiments per Recruit when topping up (defending recruits what the threat needs)
	PeaceLossShare = 0.3, -- accept (and offer) white peace after losing this share of my provinces in a war
	UpkeepReserveMonths = 2, -- build only with gold left over after this many months of upkeep
	OfferCooldownTicks = 90, -- a bot repeats an alliance or peace offer to the same nation at most this often
	MaxRouteChecks = 6, -- paths checked per army per plan (keeps planning cheap)
}

-- Tutorial (docs/DESIGN.md "Tutorial"): a new player's first match, on a reserved server of its own -------------

Config.Tutorial = {
	Map = "earth",
	PlayerSlot = 4, -- Ganges: borders three nations and has weak neutral land next door
	Bots = 5, -- the nations nearest the player stay, as bots; the rest of the map turns neutral
	Difficulty = "Easy",
	StartRegiments = 3, -- a ready army at the capital, so the first prompt (take a neutral province) can start at once
	GiftCharges = 1, -- the power prompt tops the player's charges up to this (a Blessing costs 1)
}

return Config
