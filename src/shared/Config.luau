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
	-- a server's first match has no vote: the first player to choose Play online picks the map within this long
	-- (the clock starts when they choose it), else a random map. Under Config.Ads.MinVoteSecondsLeft, so no rewarded
	-- video starts during it (the pick can end at any second).
	FirstPickTicks = 20,
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
	MaxRecruitPerCommand = 10, -- regiments in one Recruit intent
	MoveTicks = { Plains = 5, Forest = 8, Hills = 8 }, -- normal troops
	FastMoveTicks = { Plains = 3, Forest = 6, Hills = 6 }, -- fast troops (Config.Troops: fast = true)
	MinArmyMen = 500, -- smaller armies are destroyed after a battle
}

-- Troops (docs/DESIGN.md "Troops"): every race recruits a roster of five (Config.Races[race].roster), one troop for
-- each role (Sim.Troops.ROLES):
--   line     the base of every army: cheap, as good attacking as defending
--   ranged   the defenders: weak attacking, strong holding a province
--   fast     marches fast (Config.Army.FastMoveTicks)
--   elite    the race's signature and its strongest regiment in battle
--   special  one trick each, a small hook in the rules (Sim.Troops):
--              siegeSpeed   an army with them in it besieges this many times as fast
--              terrain      these men fight with +terrainBonus combat strength in battles in that terrain
--              pathfinder   they march through forest and hills at plains speed (an army keeps its slowest pace)
--              vsNeutral    these men fight with +vsNeutral combat strength against neutral garrisons and Rebels
-- Earth's five cultures share four human troops (Infantry, Archers, Cavalry, Catapults) and each adds its own elite;
-- on Eldmoor and Skyshards every race has five troops of its own. Neutral garrisons and Rebels are Earth's line
-- Infantry. One regiment is 1,000 men: what it costs, its upkeep in gold per month (what limits armies: income /
-- upkeep is the army a nation keeps), and how it fights: in a battle a side's strength is its men × attack
-- (attackers) or × defence (defenders). name: what the UI calls it; the UI's icon is its id in lower case
-- (src/client/IconArt.luau) and its army token a soldier (CosmeticArt.SOLDIERS). Ids are letters only (the network
-- encodes a composition as "Infantry:3000,Archers:1000"). Tuned with bot tournaments: docs/BALANCE.md section 19.
Config.Troops = {
	-- Earth: the human troops every culture recruits
	Infantry = {
		name = "Infantry",
		role = "line",
		gold = 10,
		manpower = 1000,
		upkeep = 1.5,
		attack = 1.0,
		defence = 1.0,
	},
	Archers = {
		name = "Archers",
		role = "ranged",
		gold = 15,
		manpower = 1000,
		upkeep = 2,
		attack = 0.75,
		defence = 1.5,
	},
	Cavalry = {
		name = "Cavalry",
		role = "fast",
		gold = 25,
		manpower = 1000,
		upkeep = 3,
		attack = 1.5,
		defence = 1.0,
		fast = true,
	},
	Catapults = {
		name = "Catapults",
		role = "special",
		gold = 20,
		manpower = 750,
		upkeep = 2,
		attack = 0.5,
		defence = 0.5,
		siegeSpeed = 2,
	},
	-- Earth: each culture's elite (Knights are also Eldmoor's Humans')
	Knights = {
		name = "Knights",
		role = "elite",
		gold = 35,
		manpower = 1000,
		upkeep = 4,
		attack = 2.0,
		defence = 1.25,
		fast = true,
	},
	Legionaries = {
		name = "Legionaries",
		role = "elite",
		gold = 25,
		manpower = 1000,
		upkeep = 2,
		attack = 1.5,
		defence = 1.75,
	},
	HorseArchers = {
		name = "Horse archers",
		role = "elite",
		gold = 25,
		manpower = 1000,
		upkeep = 2.5,
		attack = 1.5,
		defence = 1.25,
		fast = true,
	},
	Crossbowmen = {
		name = "Crossbowmen",
		role = "elite",
		gold = 20,
		manpower = 1000,
		upkeep = 2.5,
		attack = 1.5,
		defence = 1.5,
	},
	Pikemen = {
		name = "Pikemen",
		role = "elite",
		gold = 15,
		manpower = 1000,
		upkeep = 1.75,
		attack = 1.5,
		defence = 2.0,
	},
	-- Eldmoor: the Humans
	Footmen = { name = "Footmen", role = "line", gold = 10, manpower = 1000, upkeep = 1.5, attack = 1.0, defence = 1.0 },
	Longbowmen = {
		name = "Longbowmen",
		role = "ranged",
		gold = 15,
		manpower = 1000,
		upkeep = 2,
		attack = 0.8,
		defence = 1.45,
	},
	Lancers = {
		name = "Lancers",
		role = "fast",
		gold = 25,
		manpower = 1000,
		upkeep = 3,
		attack = 1.6,
		defence = 0.9,
		fast = true,
	},
	Battlemages = {
		name = "Battlemages",
		role = "special",
		gold = 20,
		manpower = 750,
		upkeep = 2,
		attack = 1.25,
		defence = 0.75,
		vsNeutral = 0.3,
	},
	-- Eldmoor: the Elves
	Wardens = {
		name = "Wardens",
		role = "line",
		gold = 11,
		manpower = 1000,
		upkeep = 1.5,
		attack = 0.95,
		defence = 1.1,
	},
	ElvenArchers = {
		name = "Elven archers",
		role = "ranged",
		gold = 16,
		manpower = 1000,
		upkeep = 2,
		attack = 0.85,
		defence = 1.5,
	},
	ElkRiders = {
		name = "Elk riders",
		role = "fast",
		gold = 24,
		manpower = 1000,
		upkeep = 2.75,
		attack = 1.4,
		defence = 1.1,
		fast = true,
	},
	Rangers = {
		name = "Rangers",
		role = "elite",
		gold = 20,
		manpower = 1000,
		upkeep = 2.5,
		attack = 1.25,
		defence = 1.75,
	},
	Treants = {
		name = "Treants",
		role = "special",
		gold = 22,
		manpower = 1000,
		upkeep = 2.25,
		attack = 1.0,
		defence = 1.5,
		terrain = "Forest",
		terrainBonus = 0.5,
	},
	-- Eldmoor: the Orcs
	Grunts = { name = "Grunts", role = "line", gold = 9, manpower = 750, upkeep = 1.5, attack = 1.1, defence = 1.0 },
	SpearThrowers = {
		name = "Spear throwers",
		role = "ranged",
		gold = 13,
		manpower = 750,
		upkeep = 1.75,
		attack = 0.9,
		defence = 1.4,
	},
	WolfRiders = {
		name = "Wolf riders",
		role = "fast",
		gold = 20,
		manpower = 750,
		upkeep = 2.5,
		attack = 1.5,
		defence = 0.8,
		fast = true,
	},
	Berserkers = {
		name = "Berserkers",
		role = "elite",
		gold = 12,
		manpower = 750,
		upkeep = 1.5,
		attack = 2.0,
		defence = 0.75,
	},
	Trolls = {
		name = "Trolls",
		role = "special",
		gold = 24,
		manpower = 1000,
		upkeep = 2.25,
		attack = 1.5,
		defence = 1.25,
		terrain = "Hills",
		terrainBonus = 0.5,
	},
	-- Eldmoor: the Dwarves
	Axemen = { name = "Axemen", role = "line", gold = 12, manpower = 1000, upkeep = 1.5, attack = 1.05, defence = 1.1 },
	Firelocks = {
		name = "Firelocks",
		role = "ranged",
		gold = 18,
		manpower = 1000,
		upkeep = 2.25,
		attack = 0.9,
		defence = 1.6,
	},
	RamRiders = {
		name = "Ram riders",
		role = "fast",
		gold = 26,
		manpower = 1000,
		upkeep = 3,
		attack = 1.4,
		defence = 1.2,
		fast = true,
	},
	Ironguard = {
		name = "Ironguard",
		role = "elite",
		gold = 25,
		manpower = 1000,
		upkeep = 2,
		attack = 1.75,
		defence = 2.0,
	},
	Sappers = {
		name = "Sappers",
		role = "special",
		gold = 18,
		manpower = 1000,
		upkeep = 2,
		attack = 0.75,
		defence = 1.0,
		siegeSpeed = 2,
	},
	-- Eldmoor: the Lizardfolk
	Scaleguards = {
		name = "Scaleguards",
		role = "line",
		gold = 10,
		manpower = 1000,
		upkeep = 1.5,
		attack = 1.1,
		defence = 0.9,
	},
	Blowgunners = {
		name = "Blowgunners",
		role = "ranged",
		gold = 14,
		manpower = 1000,
		upkeep = 2,
		attack = 0.8,
		defence = 1.4,
	},
	RaptorRiders = {
		name = "Raptor riders",
		role = "fast",
		gold = 22,
		manpower = 750,
		upkeep = 2.75,
		attack = 1.6,
		defence = 0.9,
		fast = true,
	},
	CrocodileGuard = {
		name = "Crocodile guard",
		role = "elite",
		gold = 25,
		manpower = 1000,
		upkeep = 2.5,
		attack = 1.75,
		defence = 1.75,
	},
	SwampStalkers = {
		name = "Swamp stalkers",
		role = "special",
		gold = 16,
		manpower = 750,
		upkeep = 1.75,
		attack = 1.2,
		defence = 0.8,
		pathfinder = true,
	},
	-- Skyshards: the Marines
	Troopers = {
		name = "Troopers",
		role = "line",
		gold = 10,
		manpower = 1000,
		upkeep = 1.5,
		attack = 1.0,
		defence = 1.0,
	},
	Gunners = {
		name = "Gunners",
		role = "ranged",
		gold = 15,
		manpower = 1000,
		upkeep = 2,
		attack = 0.75,
		defence = 1.5,
	},
	HoverBikes = {
		name = "Hover bikes",
		role = "fast",
		gold = 25,
		manpower = 1000,
		upkeep = 3,
		attack = 1.5,
		defence = 1.0,
		fast = true,
	},
	Mechs = { name = "Mechs", role = "elite", gold = 35, manpower = 1000, upkeep = 3.5, attack = 2.25, defence = 2.0 },
	Artillery = {
		name = "Artillery",
		role = "special",
		gold = 22,
		manpower = 750,
		upkeep = 2,
		attack = 0.6,
		defence = 0.5,
		siegeSpeed = 2,
	},
	-- Skyshards: the Robots
	Automatons = {
		name = "Automatons",
		role = "line",
		gold = 10,
		manpower = 1000,
		upkeep = 1.5,
		attack = 1.0,
		defence = 1.0,
	},
	Laserbots = {
		name = "Laserbots",
		role = "ranged",
		gold = 15,
		manpower = 1000,
		upkeep = 2,
		attack = 0.85,
		defence = 1.45,
	},
	Drones = {
		name = "Drones",
		role = "fast",
		gold = 18,
		manpower = 750,
		upkeep = 2,
		attack = 1.3,
		defence = 0.8,
		fast = true,
	},
	Juggernauts = {
		name = "Juggernauts",
		role = "elite",
		gold = 30,
		manpower = 1000,
		upkeep = 3,
		attack = 1.75,
		defence = 2.25,
	},
	Crawlers = {
		name = "Crawlers",
		role = "special",
		gold = 18,
		manpower = 1000,
		upkeep = 2.25,
		attack = 1.25,
		defence = 1.25,
		terrain = "Hills",
		terrainBonus = 0.5,
	},
	-- Skyshards: the Insectoids
	Swarmlings = {
		name = "Swarmlings",
		role = "line",
		gold = 9,
		manpower = 1000,
		upkeep = 1.4,
		attack = 0.95,
		defence = 0.85,
	},
	AcidSpitters = {
		name = "Acid spitters",
		role = "ranged",
		gold = 13,
		manpower = 750,
		upkeep = 2,
		attack = 0.8,
		defence = 1.3,
	},
	Wasps = {
		name = "Wasps",
		role = "fast",
		gold = 20,
		manpower = 750,
		upkeep = 2.5,
		attack = 1.5,
		defence = 0.8,
		fast = true,
	},
	HiveWarriors = {
		name = "Hive warriors",
		role = "elite",
		gold = 14,
		manpower = 750,
		upkeep = 2,
		attack = 1.75,
		defence = 0.75,
	},
	Burrowers = {
		name = "Burrowers",
		role = "special",
		gold = 14,
		manpower = 750,
		upkeep = 2,
		attack = 1.2,
		defence = 0.9,
		pathfinder = true,
	},
	-- Skyshards: the Crystal folk
	Shardlings = {
		name = "Shardlings",
		role = "line",
		gold = 10,
		manpower = 1000,
		upkeep = 1.5,
		attack = 1.0,
		defence = 1.15,
	},
	PrismCasters = {
		name = "Prism casters",
		role = "ranged",
		gold = 16,
		manpower = 1000,
		upkeep = 2,
		attack = 0.8,
		defence = 1.6,
	},
	ShardGliders = {
		name = "Shard gliders",
		role = "fast",
		gold = 25,
		manpower = 1000,
		upkeep = 3,
		attack = 1.4,
		defence = 1.1,
		fast = true,
	},
	Golems = { name = "Golems", role = "elite", gold = 22, manpower = 1000, upkeep = 2, attack = 1.5, defence = 2.25 },
	Resonators = {
		name = "Resonators",
		role = "special",
		gold = 18,
		manpower = 1000,
		upkeep = 2,
		attack = 1.0,
		defence = 1.4,
		terrain = "Forest",
		terrainBonus = 0.5,
	},
	-- Skyshards: the Energy beings
	Sparks = { name = "Sparks", role = "line", gold = 10, manpower = 1000, upkeep = 1.5, attack = 1.1, defence = 0.9 },
	ArcCasters = {
		name = "Arc casters",
		role = "ranged",
		gold = 15,
		manpower = 1000,
		upkeep = 2,
		attack = 0.85,
		defence = 1.4,
	},
	StormWisps = {
		name = "Storm wisps",
		role = "fast",
		gold = 25,
		manpower = 1000,
		upkeep = 3,
		attack = 1.6,
		defence = 0.9,
		fast = true,
	},
	Stormlords = {
		name = "Stormlords",
		role = "elite",
		gold = 35,
		manpower = 1000,
		upkeep = 3.5,
		attack = 2.0,
		defence = 1.5,
	},
	IonStorms = {
		name = "Ion storms",
		role = "special",
		gold = 18,
		manpower = 750,
		upkeep = 2,
		attack = 1.3,
		defence = 0.7,
		vsNeutral = 0.4,
	},
}

-- Earth's cultures all recruit the human troops, each with its own elite.
local function human(elite: string): { [string]: string }
	return { line = "Infantry", ranged = "Archers", fast = "Cavalry", elite = elite, special = "Catapults" }
end

-- Races, the peoples nations belong to (docs/DESIGN.md "Races"): every nation has one (map data: picking a nation
-- picks its race); neutral garrisons and Rebels have none. A player is one race for the whole match and recruits
-- only its roster: one troop per role (Config.Troops). Each race has one passive, a kind from Sim.Races.PASSIVES
-- with its numbers here. name: what the UI calls it.
--   Gold      goldBonus: more gross gold income (provinces and capital, before upkeep)
--   Manpower  manpowerBonus: more manpower income
--   Forest    forestBonus: more combat strength in battles in forest provinces; forest costs plains move time
--   Hills     hillsDefenceBonus: more combat strength defending in hills; fortCostMultiplier: forts cost less
--   Upkeep    upkeepMultiplier: armies cost less gold a month
--   Swift     moveMultiplier: armies march faster (each step's ticks × this, rounded, at least 1)
--   Attack    attackBonus: more combat strength when attacking
-- Combat bonuses add to the battle modifier like the terrain, fort and catch-up bonuses, for the whole side. Tuned
-- with bot tournaments: docs/BALANCE.md sections 18 and 19.
Config.Races = {
	-- Earth (realistic): human cultures, given to nations by terrain and balance
	Kingdom = { name = "Kingdom", passive = "Gold", goldBonus = 0.1, roster = human("Knights") },
	Empire = { name = "Empire", passive = "Attack", attackBonus = 0.05, roster = human("Legionaries") },
	Nomads = { name = "Nomads", passive = "Swift", moveMultiplier = 0.85, roster = human("HorseArchers") },
	Republic = { name = "Republic", passive = "Upkeep", upkeepMultiplier = 0.85, roster = human("Crossbowmen") },
	Clans = {
		name = "Clans",
		passive = "Hills",
		hillsDefenceBonus = 0.25,
		fortCostMultiplier = 0.5,
		roster = human("Pikemen"),
	},
	-- Eldmoor (fantasy)
	Humans = {
		name = "Humans",
		passive = "Gold",
		goldBonus = 0.08,
		roster = {
			line = "Footmen",
			ranged = "Longbowmen",
			fast = "Lancers",
			elite = "Knights",
			special = "Battlemages",
		},
	},
	Elves = {
		name = "Elves",
		passive = "Forest",
		forestBonus = 0.05,
		roster = {
			line = "Wardens",
			ranged = "ElvenArchers",
			fast = "ElkRiders",
			elite = "Rangers",
			special = "Treants",
		},
	},
	Orcs = {
		name = "Orcs",
		passive = "Manpower",
		manpowerBonus = 0.2,
		roster = {
			line = "Grunts",
			ranged = "SpearThrowers",
			fast = "WolfRiders",
			elite = "Berserkers",
			special = "Trolls",
		},
	},
	Dwarves = {
		name = "Dwarves",
		passive = "Hills",
		hillsDefenceBonus = 0.25,
		fortCostMultiplier = 0.5,
		roster = { line = "Axemen", ranged = "Firelocks", fast = "RamRiders", elite = "Ironguard", special = "Sappers" },
	},
	Lizardfolk = {
		name = "Lizardfolk",
		passive = "Attack",
		attackBonus = 0.1,
		roster = {
			line = "Scaleguards",
			ranged = "Blowgunners",
			fast = "RaptorRiders",
			elite = "CrocodileGuard",
			special = "SwampStalkers",
		},
	},
	-- Skyshards (sci-fi in space)
	Marines = {
		name = "Marines",
		passive = "Gold",
		goldBonus = 0.12,
		roster = { line = "Troopers", ranged = "Gunners", fast = "HoverBikes", elite = "Mechs", special = "Artillery" },
	},
	Robots = {
		name = "Robots",
		passive = "Upkeep",
		upkeepMultiplier = 0.85,
		roster = {
			line = "Automatons",
			ranged = "Laserbots",
			fast = "Drones",
			elite = "Juggernauts",
			special = "Crawlers",
		},
	},
	Insectoids = {
		name = "Insectoids",
		passive = "Manpower",
		manpowerBonus = 0.2,
		roster = {
			line = "Swarmlings",
			ranged = "AcidSpitters",
			fast = "Wasps",
			elite = "HiveWarriors",
			special = "Burrowers",
		},
	},
	Crystals = {
		name = "Crystal folk",
		passive = "Forest",
		forestBonus = 0.15,
		roster = {
			line = "Shardlings",
			ranged = "PrismCasters",
			fast = "ShardGliders",
			elite = "Golems",
			special = "Resonators",
		},
	},
	Energy = {
		name = "Energy beings",
		passive = "Swift",
		moveMultiplier = 0.85,
		roster = {
			line = "Sparks",
			ranged = "ArcCasters",
			fast = "StormWisps",
			elite = "Stormlords",
			special = "IonStorms",
		},
	},
}

-- Each map's cast (docs/MAPS.md): its five races, two nations each (the map data says which nation is which).
Config.Casts = {
	earth = { races = { "Kingdom", "Empire", "Nomads", "Republic", "Clans" } },
	eldmoor = { races = { "Humans", "Elves", "Orcs", "Dwarves", "Lizardfolk" } },
	skyshards = { races = { "Marines", "Robots", "Insectoids", "Crystals", "Energy" } },
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

-- Navies (docs/DESIGN.md "Navies"): one ship type per map (Galleon, Dragonship, Starship; MapDef.ship), the same
-- numbers on every map. A sea battle is a land battle's rule with a fleet's hull as its men. First numbers, to be
-- tuned with bot tournaments once bots sail (navies stage 3).
Config.Navy = {
	ShipGold = 25, -- one ship (no manpower)
	ShipUpkeep = 1, -- gold per ship per month (a damaged fleet pays for what is left of it)
	ShipHull = 1000, -- one ship's strength in a sea battle, like a regiment's men (attack and defence 1)
	ShipCapacity = 1000, -- men one ship carries: one regiment of any troop type
	MaxShipsPerCommand = 5, -- ships in one BuildShips order
	MoveTicks = 8, -- to sail into the next sea zone
	MinHull = 500, -- a fleet left with less than half a ship sinks after a battle, with everyone aboard
	BlockadeGoldLoss = 0.5, -- a blockaded province loses this share of its gold income
	BlockadeSiegeSpeed = 1.25, -- the blockader's side besieges a blockaded province this much faster
}

-- Diplomacy --------------------------------------------------------------------------------------

Config.Diplomacy = {
	MaxAllianceSize = 3,
	TruceTicks = 3 * 60,
	CoalitionThreshold = 0.2, -- share of the ownable provinces (not mountains) that puts a crown on a nation
	OfferTicks = 30, -- alliance, peace and military access offers expire after this
	PeaceTributes = { 0, 50, 100 }, -- gold a peace offer can include (the buttons in the province sheet)
	-- Insults (a diplomatic action with no message, docs/DESIGN.md "Diplomacy"): one nation insults another at most
	-- this often (each way)
	InsultCooldownTicks = 90,
	AnswerTicks = 30, -- the insulted nation may answer (insult back or laugh it off) this long
	GrudgeTicks = 3 * 60, -- an insult gives the insulted nation a grudge against the insulter for this long...
	GrudgeBonus = 0.1, -- ...worth this much combat strength in battles against the insulter (whole side, like races)
	LaughTicks = 60, -- laughing an insult off trades the grudge for high spirits this long...
	LaughBonus = 0.05, -- ...worth this much combat strength in every battle (doesn't stack with a grudge: the best counts)
	MarkerSeconds = 5, -- how long the insult marker stays over the insulted nation's capital (client)
	GiftGold = 25, -- a gift: a little gold to another nation
	GiftCooldownTicks = 60, -- a nation sends one gift (to anyone) at most this often
	AccessTicks = 3 * 60, -- military access: the guest's armies may enter the owner's land this long (a war between
	-- them ends it); when it ends, the guest's armies there walk home under the white flag
}

-- Event cards (the EU4 pack, stage 2; docs/DESIGN.md "Events") -----------------------------------------------------
-- Every few minutes each living nation gets an event card: a title and a line of flavour (Shared/Flavour/EventCards:
-- shown only to that nation's player) and two choices. Rules: Sim/EventCards.luau. A choice's effects, any of:
--   gold, manpower   added (negative: a cost, which must be affordable when choosing)
--   development      levels added to the card's province (up to Config.Economy.MaxDevelopment)
--   regiments        infantry regiments raised in the card's province (your capital if the province was lost)
--   ships            ships launched into the card's coastal province's port zone
--   boost            the nation's gold income × (1 + boost) for boostTicks
-- `default` is the choice that happens when the card runs out of time (always one with no cost). `map`: only on
-- that map (nil: every map). `needs`: "coast" (a coastal province), "fleet" (a fleet: from navies stage 2 on) or
-- "war" (at war with someone). About 50 gold's worth a choice (100 manpower = 1 gold, a level of development 60):
-- about two months of a starting nation's income, the same for everyone. docs/BALANCE.md section 21.
Config.EventCards = {
	FirstTicks = 2 * 60, -- nation 1's first card comes this far into the match...
	StaggerTicks = 3, -- ...each next nation's this much later (the cards don't all land on one tick)...
	EveryTicks = 3 * 60, -- ...and each next card this long after the last one closed
	ChoiceTicks = 20, -- a card waits this long for an answer, then its default choice happens
	BoostTicks = 2 * 60, -- an income boost lasts this long
	Events = {
		-- shared: every map (the text suits a castle, a wizard's tower and a space station alike)
		{ id = "Harvest", default = 1, choices = { { gold = 50 }, { manpower = 4000 } } },
		{ id = "Circus", default = 1, choices = { { gold = 40 }, { gold = -20, boost = 0.2 } } },
		{ id = "Potholes", default = 2, choices = { { gold = -40, development = 1 }, { gold = 25 } } },
		{ id = "Volunteers", default = 2, choices = { { regiments = 2 }, { gold = 30 } } },
		{ id = "TreasureMap", default = 2, choices = { { manpower = -1000, gold = 80 }, { gold = 30 } } },
		{ id = "Inventor", default = 2, choices = { { gold = -40, boost = 0.25 }, { manpower = 2500 } } },
		{ id = "Festival", default = 2, choices = { { gold = -30, manpower = 6000 }, { manpower = 2500 } } },
		{ id = "Traveller", default = 1, choices = { { development = 1 }, { regiments = 2 } } },
		{ id = "Drills", default = 2, choices = { { gold = -20, regiments = 3 }, { manpower = 2500 } } },
		{ id = "Cats", default = 1, choices = { { gold = 30 }, { manpower = 3000 } } },
		{ id = "WarChest", needs = "war", default = 1, choices = { { gold = 60 }, { regiments = 2 } } },
		{ id = "Flotsam", needs = "coast", default = 1, choices = { { gold = 50 }, { gold = -30, development = 1 } } },
		-- Earth: down to earth
		{
			id = "PrintingPress",
			map = "earth",
			default = 2,
			choices = { { gold = -20, development = 1 }, { manpower = 3000 } },
		},
		{ id = "Comet", map = "earth", default = 2, choices = { { gold = -30, development = 1 }, { gold = 40 } } },
		{ id = "SpiceCaravan", map = "earth", default = 2, choices = { { boost = 0.2 }, { gold = 40 } } },
		{
			id = "Windmills",
			map = "earth",
			default = 2,
			choices = { { manpower = -1500, development = 1 }, { gold = 30 } },
		},
		{ id = "Joust", map = "earth", default = 2, choices = { { gold = -20, manpower = 6000 }, { gold = 40 } } },
		{
			id = "FishingFleet",
			map = "earth",
			needs = "coast",
			default = 1,
			choices = { { gold = 40 }, { manpower = 3000 } },
		},
		{ id = "Galleons", map = "earth", needs = "fleet", default = 2, choices = { { ships = 1 }, { gold = 40 } } },
		-- Eldmoor: fantasy
		{ id = "DragonNap", map = "eldmoor", default = 1, choices = { { gold = 50 }, { regiments = 2 } } },
		{ id = "Lemonade", map = "eldmoor", default = 1, choices = { { gold = 40 }, { gold = -20, development = 1 } } },
		{
			id = "TrollToll",
			map = "eldmoor",
			default = 2,
			choices = { { gold = -20, boost = 0.2 }, { regiments = 2 } },
		},
		{ id = "FairyRing", map = "eldmoor", default = 1, choices = { { gold = 40 }, { manpower = 4000 } } },
		{ id = "GriffinEgg", map = "eldmoor", default = 1, choices = { { gold = 60 }, { regiments = 2 } } },
		{
			id = "MerfolkMarket",
			map = "eldmoor",
			needs = "coast",
			default = 2,
			choices = { { boost = 0.2 }, { gold = 40 } },
		},
		{
			id = "Dragonships",
			map = "eldmoor",
			needs = "fleet",
			default = 2,
			choices = { { ships = 1 }, { gold = 40 } },
		},
		-- Skyshards: sci-fi in space
		{
			id = "OreAsteroid",
			map = "skyshards",
			default = 1,
			choices = { { gold = 50 }, { gold = -30, development = 1 } },
		},
		{ id = "SpaceOpera", map = "skyshards", default = 2, choices = { { manpower = 4000 }, { gold = 40 } } },
		{
			id = "SolarFlare",
			map = "skyshards",
			default = 1,
			choices = { { boost = 0.2 }, { gold = -20, development = 1 } },
		},
		{ id = "MoonTomatoes", map = "skyshards", default = 1, choices = { { gold = 40 }, { manpower = 4000 } } },
		{ id = "CargoPod", map = "skyshards", default = 1, choices = { { gold = 60 }, { regiments = 2 } } },
		{
			id = "CometIce",
			map = "skyshards",
			needs = "coast",
			default = 1,
			choices = { { gold = 40 }, { manpower = 3000 } },
		},
		{
			id = "Starships",
			map = "skyshards",
			needs = "fleet",
			default = 2,
			choices = { { ships = 1 }, { gold = 40 } },
		},
	},
}

-- Primordial powers ------------------------------------------------------------------------------

Config.Primordial = {
	NationChargeTicks = 4 * 60,
	PrimordialChargeTicks = 60,
	ImmunityTicks = 60, -- a nation is hit by a harmful power at most once per 60 s, from anyone
	TargetCooldownTicks = 120, -- and by the same caster at most once per 2 minutes: nobody can focus one nation
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
	-- leaderboard points and placement achievements (top 3, wins) need at least this part of the match played: a
	-- late joiner seated into a winning nation gets prorated XP and Glory, not the win
	PlacementMinShare = 0.5,
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

-- Achievements (docs/MONETIZATION.md 5.6): one-time, checked with every match reward (Sim.Achievements). kind:
-- Best = the best single match; Sum = matches add up; Lifetime = a profile number; Maps = maps won on. Stats are
-- Sim.Achievements.tally's (match) and lifetime's (profile). Win-type stats never count in a private match with
-- custom rules or too few players (like "win" quests). Rewards: Glory (50–500), a title or a cosmetic (Catalogue).
Config.Achievements = {
	ComebackTick = 600, -- "Comeback": in the bottom 3 (of the nations still in the match) at 10:00
	Maps = { "earth", "eldmoor", "skyshards" }, -- "Cartographer": win on each of these
	List = {
		{ id = "first_blood", name = "First Blood", stat = "Battles", kind = "Best", target = 1, glory = 50 },
		{ id = "land_grab", name = "Land Grab", stat = "PeaceNeutral", kind = "Best", target = 10, glory = 100 },
		{
			id = "domination",
			name = "Domination",
			stat = "Domination",
			kind = "Best",
			target = 1,
			glory = 300,
			title = "title_dominant",
		},
		{
			id = "better_together",
			name = "Better Together",
			stat = "AllianceWin",
			kind = "Best",
			target = 1,
			glory = 200,
		},
		{
			id = "comeback",
			name = "Comeback",
			stat = "Comeback",
			kind = "Best",
			target = 1,
			glory = 500,
			title = "title_unbroken",
		},
		{ id = "kingmaker", name = "Kingmaker", stat = "Kingmaker", kind = "Best", target = 1, glory = 200 },
		{
			id = "meteorologist",
			name = "Meteorologist",
			stat = "MeteorKills",
			kind = "Sum",
			target = 20000,
			glory = 0,
			item = "fx_meteor_storm",
		},
		{
			id = "cartographer",
			name = "Cartographer",
			stat = "MapWins",
			kind = "Maps",
			target = 3,
			glory = 300,
			title = "title_cartographer",
		},
		{ id = "iron_wall", name = "Iron Wall", stat = "FortHolds", kind = "Best", target = 3, glory = 200 },
		{
			id = "centurion",
			name = "Centurion",
			stat = "LifeMatches",
			kind = "Lifetime",
			target = 100,
			glory = 0,
			item = "frame_centurion",
		},
		{
			id = "world_shaker",
			name = "World Shaker",
			stat = "Level",
			kind = "Lifetime",
			target = 90,
			glory = 0,
			item = "token_world_shaker",
		},
		{ id = "victor", name = "Victor", stat = "LifeWins", kind = "Lifetime", target = 1, glory = 100 },
		{
			id = "champion",
			name = "Champion",
			stat = "LifeWins",
			kind = "Lifetime",
			target = 10,
			glory = 300,
			title = "title_champion",
		},
		{ id = "veteran", name = "Veteran", stat = "LifeMatches", kind = "Lifetime", target = 10, glory = 100 },
		{ id = "seasoned", name = "Seasoned", stat = "LifeMatches", kind = "Lifetime", target = 50, glory = 200 },
		{ id = "pathfinder", name = "Pathfinder", stat = "LifeCaptures", kind = "Lifetime", target = 100, glory = 100 },
		{ id = "conqueror", name = "Conqueror", stat = "LifeCaptures", kind = "Lifetime", target = 500, glory = 300 },
		{
			id = "battle_hardened",
			name = "Battle-Hardened",
			stat = "LifeBattles",
			kind = "Lifetime",
			target = 100,
			glory = 200,
		},
		{ id = "general", name = "General", stat = "Battles", kind = "Best", target = 10, glory = 150 },
		{ id = "regicide", name = "Regicide", stat = "Capitals", kind = "Best", target = 1, glory = 100 },
		{
			id = "kingslayer",
			name = "Kingslayer",
			stat = "Capitals",
			kind = "Best",
			target = 3,
			glory = 300,
			title = "title_kingslayer",
		},
		{ id = "empire", name = "Empire", stat = "Held", kind = "Best", target = 40, glory = 200 },
		{ id = "builder", name = "Builder", stat = "Buildings", kind = "Best", target = 5, glory = 50 },
		{ id = "prosperity", name = "Prosperity", stat = "DevLevel", kind = "Best", target = 5, glory = 100 },
		{ id = "diplomat", name = "Diplomat", stat = "Alliances", kind = "Best", target = 1, glory = 50 },
		{ id = "risen", name = "Risen", stat = "Risen", kind = "Best", target = 1, glory = 100 },
		{ id = "wrath", name = "Primordial Wrath", stat = "Powers", kind = "Best", target = 5, glory = 100 },
		{
			id = "hand_of_fate",
			name = "Hand of Fate",
			stat = "LifePowers",
			kind = "Lifetime",
			target = 100,
			glory = 200,
			title = "title_fateful",
		},
		{ id = "drill_sergeant", name = "Drill Sergeant", stat = "Regiments", kind = "Best", target = 30, glory = 50 },
		{ id = "podium", name = "Podium", stat = "Top3", kind = "Best", target = 1, glory = 50 },
	},
}

-- Leaderboards (docs/MONETIZATION.md 7.3): weekly conquest points (one OrderedDataStore per week, Monday 00:00 UTC),
-- the friends view of it and the global level board (account XP). Services/LeaderboardService keeps DataStore use
-- inside Roblox's budgets: one batch of writes per match at Results, reads cached and refreshed on an interval.
Config.Leaderboards = {
	Points = { 10, 7, 5, 3, 3, 1, 1, 1, 1, 1 }, -- weekly conquest points by placement (1st..10th)
	MinHumans = 4, -- points only in public matches with this many real players (who held a nation)
	WarlordTop = 100, -- last week's top this many wear the Warlord frame this week
	RefreshSeconds = 120, -- how often a server reads the boards again
	ReadRows = 200, -- weekly rows read (the friends view is filtered from these), in pages of up to 100
	LevelRows = 50, -- global level rows read
	ShownRows = 50, -- rows sent to clients per board
	MaxFriends = 200, -- friends read per player (Players:GetFriendsAsync, the player's own list only)
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
	EpicSetRobux = 299, -- nation skin set of three Epic pieces
}

-- Rotating shop (docs/MONETIZATION.md 3.8, Sim.ShopRotation): a fixed schedule from a seeded generator, the same for
-- every player and server. Core items (Shared.Catalogue.CORE) are always on sale; every other sold item rotates.
Config.ShopRotation = {
	Daily = { Common = 2, Rare = 1, Epic = 1 }, -- new at 00:00 UTC
	WeeklyLegendary = 1, -- new on Monday 00:00 UTC: Legendary items
	WeeklyBundles = 1, -- and bundles (nation skin sets)
	ReturnDays = 60, -- every rotating item is back within this many days, and the shop says so
	Seed = 31013, -- the schedule's seed (changing it reshuffles every future day)
}

-- Season pass (docs/MONETIZATION.md 6, Sim.Season): 8-week seasons, 50 tiers, a free and a premium track. Season XP is
-- the account XP earned during the season. Tier n opens at (n - 1) × XpPerTier; after the last tier's bar is full
-- (Tiers × XpPerTier), every BonusXp more pays BonusGlory. No single tier skips are sold: only the bundle's tiers,
-- once, with the pass. Buying the pass late opens every premium reward up to your tier at once.
Config.Season = {
	Tiers = 50,
	XpPerTier = 1200,
	BonusXp = 2400,
	BonusGlory = 100,
	BundleTiers = 10,
	PassRobux = 299, -- developer product "season_pass"
	BundleRobux = 499, -- developer product "season_bundle": the pass + BundleTiers tiers
	-- Seasons by UTC day number, [startDay, endDay): the current one is chosen by the day. Add the next season here.
	Seasons = {
		{ id = "S1", name = "Rise of the Primordials", startDay = 20749, endDay = 20805 }, -- Fri 2026-10-23, 8 weeks
	},
}

-- Each season's rewards, one row per tier: { free, premium }. A number is Glory, "title:…" a title, "badge:…" a season
-- badge, any other string a Shared.Catalogue item id, a table several of these, false nothing.
Config.Season.Rewards = {
	S1 = {
		{ "emote_gg", "token_ember_knight" }, -- 1
		{ false, 100 },
		{ 100, "flag_ember_banner" },
		{ false, "emote_laugh" },
		{ "flag_ember_sigil", "frame_molten" }, -- 5
		{ false, 100 },
		{ false, "fx_plague_ember" },
		{ 100, "emote_volcano" },
		{ false, "border_embers" },
		{ "border_runes", "fx_meteor_ember" }, -- 10
		{ false, 100 },
		{ false, "fx_plague_ash" },
		{ 150, "emote_crown_toss" },
		{ false, "flag_titan_eye" },
		{ "emote_salute", "frame_lava_seam" }, -- 15
		{ false, 150 },
		{ false, "fx_blessing_molten" },
		{ 150, "token_obsidian" },
		{ false, "emote_skull" },
		{ "fx_meteor_stone", "victory_eruption" }, -- 20
		{ false, 150 },
		{ false, "fx_meteor_firestorm" },
		{ 200, "flag_cracked_crown" },
		{ false, "fx_blessing_ember" },
		{ "frame_ashen", "theme_autumn" }, -- 25
		{ false, 150 },
		{ false, "victory_magma" },
		{ 200, "token_phoenix_rider" },
		{ false, "emote_eruption" },
		{ "token_stone_golem", "flag_storm_titan" }, -- 30
		{ false, 200 },
		{ false, "fx_plague_void" },
		{ 250, "frame_obsidian" },
		{ false, "emote_roar" },
		{ "emote_volcano_peak", "fx_meteor_lava" }, -- 35
		{ false, 200 },
		{ false, "fx_blessing_worldsplitter" },
		{ 250, "token_cinder_golem" },
		{ false, 250 },
		{ "flag_storm_banner", "fx_blessing_starfall" }, -- 40
		{ false, "emote_meteor_shower" },
		{ false, 250 },
		{ 300, "frame_primordial_eye" },
		{ false, "fx_blessing_sunfire" },
		{ "fx_plague_cinder", "shades_royal" }, -- 45
		{ false, 300 },
		{ false, "flag_obsidian_crown" },
		{ 300, 300 },
		{ false, "frame_rift" },
		{ -- 50
			{ 500, "title:Season 1 Veteran", "badge:S1" },
			{ "token_titan", "fx_meteor_phoenix", "victory_titan", "title:Primordial Herald" },
		},
	},
}

-- Match features (the "EU4 pack", docs/DESIGN.md): each is a match setting (Sim.Settings) with this default, so a
-- private server, and later a sandbox mode, can turn it off. false here turns it off on every server.
Config.Features = {
	Diplomacy = true, -- insults and their answers, gifts, military access (war, alliances and peace are always on)
	Events = true, -- event cards with two choices every few minutes (Config.EventCards)
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
	-- the troop mix by role (docs/DESIGN.md "Bot AI"): the line troop is the base; a threatened province raises the
	-- ranged troop while it is under RangedShare of the bot's men; at war it buys its special while under
	-- SpecialShare, else its elite and its fast troop while under EliteShare and FastShare (the one furthest below
	-- its share first), when it can pay and keep UpkeepReserveMonths
	RangedShare = 0.3,
	SpecialShare = 0.1,
	EliteShare = 0.2,
	FastShare = 0.1,
	OfferCooldownTicks = 90, -- a bot repeats an alliance or peace offer to the same nation at most this often
	MaxRouteChecks = 6, -- paths checked per army per plan (keeps planning cheap)
	-- insults (docs/DESIGN.md "Bot AI"): now and then a bot insults a rival, and an insulted bot answers back and leans
	-- towards war with its insulter
	InsultChance = 0.002, -- per plan (Normal bots plan every 3 s: about one insult per bot in a 25-minute match)
	InsultBackChance = 0.5, -- an insulted bot insults back (it decides once per insult; else it keeps its grudge)
	GrudgeAttackRatio = 0.85, -- against a nation it holds a grudge against, a bot needs this share of its attack ratio
	GrudgeMinRatio = 1, -- ...but never less than this much of the enemy's strength (Hard's 1.1 × 0.85 would be 0.94)
	-- event cards (Sim.EventCards.worth): a bot takes the choice worth more gold, counting the rest at these rates
	EventWorth = {
		Manpower = 0.01, -- gold per man (100 manpower = 1 gold, the price ratio of a regiment)
		Development = 60, -- a development level (what developing 2 -> 3 costs)
		Regiment = 15, -- a free regiment in peace (its price, less the upkeep it brings)...
		RegimentAtWar = 30, -- ...and while at war
		Ship = 20, -- a free ship
	},
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

-- The singleplayer sandbox (docs/DESIGN.md "Sandbox"): Sim.Sandbox, Services/SandboxService, UI/Sandbox ----------

Config.Sandbox = {
	Speeds = { 0, 1, 2, 4 }, -- the time controls: game ticks per real second (0 = paused)
	StartSpeed = 1,
	Difficulty = "Normal", -- every bot in a sandbox world
	BeatSeconds = 0.25, -- the sandbox loop wakes this often: controls and orders land within a beat, even paused
	MaxTicksPerBeat = 4, -- a late beat catches up at most this many ticks (a longer stall is skipped, not replayed)
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

-- Music (docs/DESIGN.md "Sound and effects", docs/NEXT_FEATURES.md 6): src/client/Music, src/client/MusicMood ---------

Config.Music = {
	Volume = 0.35, -- the music's level (its AudioFader): under the sounds, which play at 0.35-0.7
	FadeSeconds = 2.5, -- a mood change crossfades the old track out and the new one in over this long
	MinMoodSeconds = 40, -- Peace and War never switch back within this long (a quick peace doesn't flip it twice)
	BattleWindowSeconds = 30, -- in the War phase, War plays while at war or this long after a battle of yours
	DuckVolume = 0.12, -- the music's level under the War and Cataclysm banners, so their sounds land
	DuckSeconds = 2.6, -- how long it stays down (a banner shows for about this long)
	DuckFadeSeconds = 0.3, -- down and back up again over this long
}

return Config
