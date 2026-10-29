--!strict
-- The words on the EU4 pack's event cards (docs/DESIGN.md "Events"): each event's title, one line of flavour and its
-- two choices' names, by event id (the rules and numbers are in Config.EventCards and Sim.EventCards). This is game
-- narration, shown only to the nation it happened to: the server sends a nation's card to its own player alone, as
-- an event id, and that client looks the words up here. Nothing here is ever sent to or shown to another player.
-- Shared events suit a castle, a wizard's tower and a space station alike; Earth's are down to earth, Eldmoor's
-- fantasy, Skyshards' sci-fi in space. Playful and silly, never mean: nothing about real peoples, countries,
-- religions, appearance, family or identity, no race of the map in particular, no nation's name, no profanity.

local EventText = {}

export type Text = { title: string, line: string, choices: { string } }

-- The longest a title, a line and a choice's name may be (a Lune test checks every one).
EventText.MAX_TITLE = 26
EventText.MAX_LINE = 60
EventText.MAX_CHOICE = 16 -- two choice buttons side by side on a 290 px card

EventText.TEXT = {
	-- shared
	Harvest = {
		title = "A Bumper Harvest",
		line = "The barns are so full the doors won't shut.",
		choices = { "Sell the extra", "Feed recruits" },
	},
	Circus = {
		title = "The Circus Is in Town",
		line = "Jugglers, acrobats and one very confused goat.",
		choices = { "Sell tickets", "Free shows" },
	},
	Potholes = {
		title = "Potholes Everywhere",
		line = "A cart lost a wheel and the whole market saw it.",
		choices = { "Pave the roads", "Sell the cobbles" },
	},
	Volunteers = {
		title = "Volunteers at the Gate",
		line = "A crowd turned up in matching hats, ready to help.",
		choices = { "Sign them up", "Put them to work" },
	},
	TreasureMap = {
		title = "A Treasure Map!",
		line = "Found in a library book 300 years overdue.",
		choices = { "Send diggers", "Sell the map" },
	},
	Inventor = {
		title = "A Clever Inventor",
		line = "Her new gadget only exploded twice this week.",
		choices = { "Fund her lab", "Borrow helpers" },
	},
	Festival = {
		title = "A Grand Festival",
		line = "Everyone wants a party. The cooks want a bigger pot.",
		choices = { "Huge party", "Small picnic" },
	},
	Traveller = {
		title = "A Wise Traveller",
		line = "She offers advice and asks only for a warm meal.",
		choices = { "Ask about farms", "Ask about armies" },
	},
	Drills = {
		title = "The Drill Sergeant",
		line = "The new sergeant wants more marching. Lots more.",
		choices = { "Extra drills", "Day off for all" },
	},
	Cats = {
		title = "Too Many Cats",
		line = "The storehouse cats have had a very busy year.",
		choices = { "Guard the grain", "Hold a cat show" },
	},
	WarChest = {
		title = "The War Chest",
		line = "Townsfolk empty their piggy banks for the war.",
		choices = { "Fill the chest", "Raise regiments" },
	},
	Flotsam = {
		title = "Shiny Things Drift In",
		line = "The tide (or the void) brought a heap of shiny junk.",
		choices = { "Sell the junk", "Build a new dock" },
	},
	-- Earth
	PrintingPress = {
		title = "A Printing Press",
		line = "The scribes are worried. The readers are thrilled.",
		choices = { "Print books", "Print posters" },
	},
	Comet = {
		title = "A Comet in the Sky",
		line = "The stargazers stayed up all night and want cocoa.",
		choices = { "Fund stargazers", "Sell souvenirs" },
	},
	SpiceCaravan = {
		title = "A Spice Caravan",
		line = "Pepper, cinnamon and some very loud camels.",
		choices = { "Open a market", "Tax the caravan" },
	},
	Windmills = {
		title = "Windmill Fever",
		line = "The miller says the wind is finally on our side.",
		choices = { "Build windmills", "Sell the flour" },
	},
	Joust = {
		title = "A Grand Tournament",
		line = "Knights joust, squires cheer, a horse steals a pie.",
		choices = { "Hold the joust", "Sell seats" },
	},
	FishingFleet = {
		title = "The Fishing Boats Return",
		line = "The nets are so full the boats sit low in the water.",
		choices = { "Sell the catch", "Feed the troops" },
	},
	Galleons = {
		title = "A Shipwright's Bet",
		line = "Two shipwrights bet who can build a galleon faster.",
		choices = { "Let them race", "Make them pay up" },
	},
	-- Eldmoor
	DragonNap = {
		title = "A Dragon Naps Nearby",
		line = "It snores so loudly the castle windows rattle.",
		choices = { "Charge visitors", "Train squires" },
	},
	Lemonade = {
		title = "The Wizard's Apprentice",
		line = "He turned the well water into lemonade. Again.",
		choices = { "Bottle and sell", "Give him a tower" },
	},
	TrollToll = {
		title = "A Troll Under the Bridge",
		line = "It charges a toll and always says please.",
		choices = { "Pay the toll", "Hire its cousins" },
	},
	FairyRing = {
		title = "A Fairy Ring",
		line = "Mushrooms in a perfect circle. Farmers dance round it.",
		choices = { "Pick mushrooms", "Moon dance!" },
	},
	GriffinEgg = {
		title = "A Griffin Egg",
		line = "Found in the castle garden, warm and wobbling.",
		choices = { "Sell the egg", "Raise a griffin" },
	},
	MerfolkMarket = {
		title = "The Merfolk Market",
		line = "Merfolk swap shiny shells for fresh bread at the shore.",
		choices = { "Open a market", "Trade for pearls" },
	},
	Dragonships = {
		title = "A Dragonship Race",
		line = "Two shipwrights bet who can carve a dragonship faster.",
		choices = { "Let them race", "Make them pay up" },
	},
	-- Skyshards
	OreAsteroid = {
		title = "An Asteroid Full of Ore",
		line = "The scanners beep happily: there's metal in that rock.",
		choices = { "Mine it", "Build a base" },
	},
	SpaceOpera = {
		title = "The Ship's Computer Sings",
		line = "It learned opera and won't stop. The crew loves it.",
		choices = { "Broadcast it", "Sell recordings" },
	},
	SolarFlare = {
		title = "A Solar Flare",
		line = "Free energy! Also, slightly crispy antennas.",
		choices = { "Charge batteries", "Better antennas" },
	},
	MoonTomatoes = {
		title = "Giant Space Tomatoes",
		line = "The greenhouse tomatoes grew as big as small moons.",
		choices = { "Sell tomatoes", "Feed troopers" },
	},
	CargoPod = {
		title = "A Lost Cargo Pod",
		line = "It drifted by with a 'Fragile' sticker and no address.",
		choices = { "Open it up", "Arm the troopers" },
	},
	CometIce = {
		title = "Comet Ice Delivery",
		line = "A comet passed close and filled the water tanks.",
		choices = { "Sell the water", "Bubble baths!" },
	},
	Starships = {
		title = "A Starship Race",
		line = "Two shipwrights bet who can build a starship faster.",
		choices = { "Let them race", "Make them pay up" },
	},
} :: { [string]: Text }

-- A choice's effects as Config.EventCards writes them.
export type Effects = {
	gold: number?,
	manpower: number?,
	development: number?,
	regiments: number?,
	ships: number?,
	boost: number?,
}

-- 4000 -> "4,000"
local function grouped(n: number): string
	local s = tostring(math.abs(math.floor(n)))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

local function signed(n: number): string
	return (if n < 0 then "-" else "+") .. grouped(n)
end

local function plural(n: number, one: string, many: string): string
	return grouped(n) .. " " .. (if n == 1 then one else many)
end

-- A choice's effects as { icon, text } pairs for the card's buttons, icons and numbers (pixel icon names:
-- src/client/IconArt.luau; "up" is development, "sword" regiments, "anchor" ships, "blessing" an income boost),
-- costs and gains in one fixed order. boostMinutes: how long an income boost lasts.
function EventText.chips(effects: Effects, boostMinutes: number): { { string } }
	local out: { { string } } = {}
	if effects.gold then
		table.insert(out, { "gold", signed(effects.gold) })
	end
	if effects.manpower then
		table.insert(out, { "manpower", signed(effects.manpower) })
	end
	if effects.development then
		table.insert(out, { "up", "+" .. effects.development })
	end
	if effects.regiments then
		table.insert(out, { "sword", "+" .. effects.regiments })
	end
	if effects.ships then
		table.insert(out, { "anchor", "+" .. effects.ships })
	end
	if effects.boost then
		table.insert(
			out,
			{ "blessing", string.format("+%d%% gold %d min", math.floor(effects.boost * 100 + 0.5), boostMinutes) }
		)
	end
	return out
end

-- The same in words, for the toast after a choice: "+50 gold, +1 development in Kent".
function EventText.summary(effects: Effects, boostMinutes: number, place: string?): string
	local parts = {}
	if effects.gold then
		table.insert(parts, signed(effects.gold) .. " gold")
	end
	if effects.manpower then
		table.insert(parts, signed(effects.manpower) .. " manpower")
	end
	local where = if place then " in " .. place else ""
	if effects.development then
		table.insert(parts, "+" .. effects.development .. " development" .. where)
	end
	if effects.regiments then
		table.insert(parts, "+" .. plural(effects.regiments, "regiment", "regiments") .. where)
	end
	if effects.ships then
		table.insert(parts, "+" .. plural(effects.ships, "ship", "ships") .. where)
	end
	if effects.boost then
		table.insert(parts, string.format("+%d%% gold for %d min", math.floor(effects.boost * 100 + 0.5), boostMinutes))
	end
	return table.concat(parts, ", ")
end

return EventText
