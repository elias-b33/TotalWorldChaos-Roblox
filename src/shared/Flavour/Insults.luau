--!strict
-- The pre-written joke insults and comebacks (docs/DESIGN.md "Diplomacy"), one pool per map: Earth is down-to-earth,
-- Eldmoor fantasy, Skyshards sci-fi in space. Players only ever pick a line by its number, so there is no free text
-- to filter. Every line is playful and silly, never mean: it pokes at the other nation's armies, castles, maps,
-- wizards or starships, never at real peoples, countries, religions, appearance, family or identity, and Earth's lines
-- never mention its river names. Keep a line short (about 50 characters): it shows in a toast and a speech bubble.

local Insults = {}

export type Kind = "insults" | "comebacks"

Insults.BY_MAP = {
	earth = {
		insults = {
			"Your army marches like it's late for a nap.",
			"Your castle walls are mostly polite signs.",
			"Your scouts asked us for directions. Twice.",
			"We've seen fiercer generals at a picnic.",
			"Your catapults throw like a sleepy cabbage.",
			"Your war drums sound like a bucket with hiccups.",
			"Your maps still say 'here be dragons'.",
			"Your banner looks like a tablecloth that lost.",
		},
		comebacks = {
			"Bold words from someone with half a map.",
			"Our tablecloth banner will fly over your capital.",
			"We'll answer that on the battlefield. Politely.",
			"Our snail courier delivered that faster.",
			"Noted. Filed under 'things that made us laugh'.",
			"Keep talking. Our catapults are listening.",
		},
	},
	eldmoor = {
		insults = {
			"Your dragon is just a lizard with ambition.",
			"Your wizards can't even conjure a breakfast.",
			"Your knights polish armour more than they use it.",
			"Even the goblins rate your fortress one star.",
			"Your magic sword is a butter knife that glows.",
			"Your court bard only knows one song. About naps.",
			"Your war trolls keep stopping to smell flowers.",
			"Your potion of courage is mostly apple juice.",
		},
		comebacks = {
			"Our lizard with ambition is circling your castle.",
			"My wizard just turned your insult into a newt.",
			"The goblins gave you zero stars. They live there.",
			"Our bard is writing a song about your defeat.",
			"Big talk from a realm guarded by sleepy trolls.",
			"Your scroll of insults needs a spell check.",
		},
	},
	skyshards = {
		insults = {
			"Your shields run on two potato batteries.",
			"Your starships park like runaway asteroids.",
			"Your robots salute the wrong way round.",
			"Your laser cannons are very bright flashlights.",
			"Your station has the slowest wifi in the galaxy.",
			"Your crystals are glow sticks from a party shop.",
			"Your pilots need a map to find their own shard.",
			"Your fleet's top speed is 'drifting politely'.",
		},
		comebacks = {
			"Our potato batteries are charged and aimed at you.",
			"Message received. Rated one star. Deleted.",
			"Our robots saluted. Then they laughed.",
			"Error 404: a good insult was not found.",
			"Keep transmitting. Our shields find it relaxing.",
			"Bold words for a shard held together with tape.",
		},
	},
} :: { [string]: { insults: { string }, comebacks: { string } } }

local FALLBACK = "earth" -- a map without its own pool (a new map before its lines are written)

-- The lines of one kind for a map.
function Insults.lines(mapId: string, kind: Kind): { string }
	local pool = Insults.BY_MAP[mapId] or Insults.BY_MAP[FALLBACK]
	return if kind == "insults" then pool.insults else pool.comebacks
end

-- One line by its number, or nil if there is no such line.
function Insults.line(mapId: string, kind: Kind, index: number): string?
	return Insults.lines(mapId, kind)[index]
end

-- Is `index` a line of this kind on this map? (What a player sends is checked against this.)
function Insults.valid(mapId: string, kind: Kind, index: unknown): boolean
	return type(index) == "number"
		and index == math.floor(index)
		and index >= 1
		and index <= #Insults.lines(mapId, kind)
end

return Insults
