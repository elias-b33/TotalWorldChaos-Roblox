--!strict
-- Every balance number in the game (docs/DESIGN.md). Times are in ticks; 1 tick = 1 second = 1 game day.
-- Change one or two numbers per playtest, not ten.

local Config = {}

-- Match ------------------------------------------------------------------------------------------

Config.DefaultMap = "skyshards" -- "earth" | "eldmoor" | "skyshards"; the map vote arrives in Phase 4
Config.MaxPlayers = 12
Config.NationsPerMatch = 10
Config.TickSeconds = 1
Config.MonthTicks = 10 -- income and upkeep are paid every month

Config.Phases = {
	-- Lobby and Pick come with the map vote and nation draft; until then a match starts in Peace
	LobbyTicks = 60,
	PickTicks = 30,
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

-- Network and security ---------------------------------------------------------------------------

Config.Net = {
	MaxIntentsPerSecond = 10,
}

-- Bots -------------------------------------------------------------------------------------------

Config.Bots = {
	Easy = { planTicks = 6, attackRatio = 1.6, noPlayerWarTicks = 8 * 60 },
	Normal = { planTicks = 3, attackRatio = 1.3 },
	Hard = { planTicks = 2, attackRatio = 1.1 },
	DefendRatio = 0.8,
	MenPerProvince = 800,
	BotsPlanningPerTick = 2,
}

return Config
