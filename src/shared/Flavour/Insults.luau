--!strict
-- Private flavour lines for the EU4 pack's insults (docs/DESIGN.md "Diplomacy"). An insult is a diplomatic action
-- with no message: the target and everyone else only see a neutral system line ("Rhine insulted you") and a marker.
-- Roblox's preset-text rule (DevForum, 26 March 2026, enforced from 26 April 2026: "Preset systems cannot be used for
-- social communication") forbids pre-written messages players send each other, so these lines are never sent to
-- anyone: after you insult (or insult back, or laugh one off), your own client picks one and shows it to you alone,
-- about what your own side did. Nothing here may ever be shown to another player.
-- One pool per map: Earth down to earth (jesters, scribes, catapults), Eldmoor fantasy, Skyshards sci-fi in space.
-- Silly, never mean: never about real peoples, countries, religions, appearance, family or identity, and no race of
-- the map in particular (any nation may be any race). "%s" is the other nation's name; a line may leave it out.

local Insults = {}

export type Kind = "insult" | "laugh"

Insults.BY_MAP = {
	earth = {
		insult = {
			"Your court jesters wrote a ballad about %s's catapults.",
			"Your heralds practised their best eye-roll at %s.",
			"Your scribes drew %s's castle as a sandcastle.",
			"Your drummers played a very cheeky solo at %s.",
			"Your generals are still chuckling at %s's banner.",
			"Your town crier announced it twice. For effect.",
			"Your mapmakers labelled %s 'here be snails'.",
			"Your knights did a little victory dance. Early.",
		},
		laugh = {
			"Your jesters turned %s's insult into a puppet show.",
			"Your soldiers laughed so hard they marched in step.",
			"Your court framed %s's insult and hung it up.",
			"Your heralds read it out loud. Everyone giggled.",
		},
	},
	eldmoor = {
		insult = {
			"Your bards wrote a song about %s's sleepy dragon.",
			"Your wizards blew a magic raspberry at %s.",
			"Your goblin scribes drew a very silly map of %s.",
			"Your trolls laughed so hard the bridge shook.",
			"Your court owl hooted %s's name sarcastically.",
			"Your knights polished their armour extra smugly.",
			"Your potion makers brewed a draught of pure sass.",
			"Your dragon puffed a smoke ring at %s's towers.",
		},
		laugh = {
			"Your bards turned %s's insult into a tavern song.",
			"Your trolls laughed until they rolled down a hill.",
			"Your wizards turned the insult into a frog.",
			"Your sages filed it in the Book of Funny Things.",
		},
	},
	skyshards = {
		insult = {
			"Your ship's computer rated %s's fleet one star.",
			"Your engineers beamed a dancing hologram to %s.",
			"Your crew named a space hamster after %s.",
			"Your pilots drew a smiley face in %s's sky.",
			"Your station AI laughed in binary for an hour.",
			"Your lasers spelled out 'nice try' near %s.",
			"Your shields hummed a smug little tune at %s.",
			"Your radar now marks %s as 'mostly harmless'.",
		},
		laugh = {
			"Your crew turned %s's insult into a ringtone.",
			"Your ship's computer filed it under 'cute'.",
			"Your engineers laughed so hard gravity flickered.",
			"Your station AI played a laugh track on loop.",
		},
	},
} :: { [string]: { insult: { string }, laugh: { string } } }

local FALLBACK = "earth" -- a map without its own pool (a new map before its lines are written)

-- The lines of one kind for a map (templates: "%s" is the other nation's name).
function Insults.lines(mapId: string, kind: Kind): { string }
	local pool = Insults.BY_MAP[mapId] or Insults.BY_MAP[FALLBACK]
	return if kind == "insult" then pool.insult else pool.laugh
end

-- The flavour line your client shows you alone after you insult (or insult back) `other`, or laugh off its insult.
-- `turn` picks the line (the client passes the event's tick plus the other nation's id, so it varies).
function Insults.flavour(mapId: string, kind: Kind, other: string, turn: number): string
	local pool = Insults.lines(mapId, kind)
	local template = pool[math.floor(turn) % #pool + 1]
	return (string.gsub(template, "%%s", function()
		return other
	end))
end

return Insults
