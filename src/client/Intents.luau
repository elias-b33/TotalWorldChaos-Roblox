--!strict
-- Sends intents to the server and reports refusals. The server answers every request with
-- CommandResult(requestId, ok, reason); the visible state change arrives separately in the next delta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

-- Short, icon-first messages for every reason code (Sim.Commands and CommandRouter).
local REASONS: { [string]: string } = {
	NotEnoughGold = "💰 Not enough gold",
	NotEnoughManpower = "👥 Not enough manpower",
	MaxDevelopment = "⬆ Already at max development",
	AlreadyBuilt = "🏗 This province already has a building",
	NotYourProvince = "🚫 Not your province",
	UnknownProvince = "🚫 Unknown province",
	WrongPhase = "⏳ Not now",
	NoNation = "👀 You're spectating",
	TooFast = "⏱ Too fast, slow down",
	BadAmount = "🚫 Bad amount",
	BadTroop = "🚫 Unknown troop",
	WrongRace = "🚫 Only its own race can recruit that troop",
	BadBuilding = "🚫 Unknown building",
	BadRequest = "🚫 Bad request",
	UnknownArmy = "🚫 That army is gone",
	NotYourArmy = "🚫 Not your army",
	InBattle = "💥 It's in a battle",
	Retreating = "🏳 It's retreating home",
	NoPath = "🚫 Can't get there",
	BadTarget = "🚫 Not possible",
	PeaceTime = "🕊 No wars until Peace ends",
	Allied = "🤝 You're allies",
	AlreadyAtWar = "⚔ Already at war",
	Truce = "🕊 Truce still running",
	NoBorder = "🗺 You must share a border or a sea",
	AlreadyAllied = "🤝 Already allied",
	AtWar = "⚔ You're at war",
	NotAtWar = "🕊 You're not at war",
	AllianceFull = "🤝 Alliance is full (3)",
	NoOffer = "⌛ That offer expired",
	NotEnoughCharges = "⚡ Not enough charges",
	Immune = "🛡 Hit by a power less than 30 s ago",
	NoBuilding = "🏚 No building there",
	OwnTarget = "🚫 Not on yourself",
	NoPowersYet = "⏳ Powers unlock when Peace ends",
	MatchOver = "🏁 The match is over",
	Primordial = "✨ Primordials only use powers",
	Locked = "🔒 This server's map is set",
	UnknownMap = "🚫 Unknown map",
	NotYourTurn = "⏳ Wait for your turn",
	Taken = "🚫 Already taken",
	UnknownItem = "🚫 Unknown item",
	NotForGlory = "🏅 Not sold for Glory",
	NotForRobux = "🚫 Not sold for Robux",
	NotEnoughGlory = "🏅 Not enough Glory",
	Owned = "✅ You already own it",
	NotOwned = "🔒 You don't own it yet",
	CantEquip = "🚫 Can't wear that",
	InMatch = "🛒 Robux purchases open after the match",
	NotForSale = "🚫 Not on sale yet",
	NotLoaded = "⏳ Your save is still loading",
	TryAgain = "⏳ Try again in a moment",
	Unknown = "🚫 That quest is gone",
	Claimed = "✅ Already claimed",
	NotDone = "📜 Not finished yet",
	NotDaily = "📜 Only daily quests can be rerolled",
	Done = "✅ That quest is finished",
	NoOther = "📜 No other quest to swap in",
	NotOwner = "🔒 Only the server's owner can change that",
	BadSetting = "🚫 Not an option",
	TeamFull = "👥 That team is full (3)",
	PowersOff = "✨ Powers are off on this server",
	TeamsLocked = "🔒 Teams are set on this server",
	AdNotNow = "📺 Ads only play early in the map vote",
	AdBusy = "📺 An ad is already playing",
	NoAdReward = "📺 No ad reroll to earn right now",
	AdFailed = "📺 The ad didn't play to the end",
	NotInShop = "🔄 Not in the shop today: back within 60 days",
	NoSeason = "🎟 No season is running",
	TierLocked = "🔒 Reach that tier first",
	NeedPass = "🎟 That reward needs the premium pass",
	NothingToClaim = "🎟 Nothing to claim yet",
	-- the EU4 pack
	DiplomacyOff = "🔒 Insults, gifts and access are off on this server",
	Cooldown = "⏳ Wait a little before doing that again",
	NoAnswer = "💢 Too late to answer that one",
	AlreadyAccess = "🚶 You can already march through their land",
	EventsOff = "🔒 Events are off on this server",
	NoEvent = "📜 That event is over",
	BadChoice = "🚫 Not one of the choices",
}

local Intents = {}

local nextId = 0
local onRefused: ((string) -> ())? = nil

function Intents.init(showMessage: (string) -> ())
	onRefused = showMessage
	Remotes.event("CommandResult").OnClientEvent:Connect(function(_requestId: number, ok: boolean, reason: string?)
		if not ok and onRefused then
			onRefused(REASONS[reason or ""] or ("🚫 " .. tostring(reason)))
		end
	end)
end

local function send(remoteName: string, ...: any)
	nextId += 1
	Remotes.event(remoteName):FireServer(nextId, ...)
end

function Intents.develop(provinceId: number)
	send("RequestDevelop", provinceId)
end

function Intents.build(provinceId: number, building: string)
	send("RequestBuild", provinceId, building)
end

-- troop: Infantry | Archers | Cavalry, or the nation's race's elite (Knights | Rangers | Berserkers | Ironguard)
function Intents.recruit(provinceId: number, regiments: number, troop: string)
	send("RequestRecruit", provinceId, regiments, troop)
end

function Intents.move(armyId: number, to: number)
	send("RequestMove", armyId, to)
end

-- action: War | Ally | AcceptAlly | Peace | AcceptPeace, and the EU4 pack's Insult | InsultBack | LaughOff | Gift |
-- Access | AcceptAccess (an insult carries no message)
function Intents.diplomacy(action: string, target: number, gold: number?)
	send("RequestDiplomacy", action, target, gold or 0)
end

-- The EU4 pack's event cards: choice 1 or 2 on your nation's open card.
function Intents.eventChoice(card: number, choice: number)
	send("RequestEventChoice", card, choice)
end

-- power: Meteor | Plague | Rebels | Earthquake | Blessing | Shield; target: army, nation or province id
function Intents.power(power: string, target: number)
	send("RequestPower", power, target)
end

-- Lobby: vote for a map, pick a start nation in the draft.
function Intents.vote(mapId: string)
	send("RequestVote", mapId)
end

function Intents.pick(nationId: number)
	send("RequestPick", nationId)
end

-- Lobby, private server owner: change a setting (Sim.Settings.set); "team" puts player `value` in team `extra`.
function Intents.setting(key: string, value: string | number | boolean, extra: number?)
	send("RequestSetting", key, value, extra or 0)
end

-- Tutorial: "Skip" it, or "Leave" for a public server once it is over.
function Intents.tutorial(action: string)
	send("RequestTutorial", action)
end

-- Shop: buy an item or offer with "Glory" or "Robux", wear an owned item, show an owned emote over your capital.
function Intents.buy(itemId: string, currency: string)
	send("RequestBuy", itemId, currency)
end

function Intents.equip(itemId: string)
	send("RequestEquip", itemId)
end

function Intents.emote(itemId: string)
	send("RequestEmote", itemId)
end

-- Quests: claim a finished quest's reward, or swap a daily quest for another (free rerolls first, then Glory).
function Intents.claimQuest(key: string)
	send("RequestClaim", key)
end

function Intents.rerollQuest(key: string)
	send("RequestQuestReroll", key)
end

-- Analytics: a UI-only funnel step ("Loaded", "ShopOpened", "ItemViewed", "OfferOpened"). No reply.
function Intents.signal(kind: string, arg: string?)
	Remotes.event("RequestTelemetry"):FireServer(kind, arg)
end

-- Rewarded video: play an ad for its reward ("quest_reroll": one more free quest reroll today).
function Intents.watchAd(placement: string)
	send("RequestAd", placement)
end

-- The map-theme opt-out: true = always show me the classic map.
-- Season pass: claim one tier's reward on a track, everything claimable, or tell the server the screen opened.
function Intents.claimSeason(tier: number, track: string)
	send("RequestSeason", "Claim", tier, track)
end

function Intents.claimAllSeason()
	send("RequestSeason", "ClaimAll")
end

function Intents.seasonViewed()
	send("RequestSeason", "Viewed")
end

function Intents.defaultTheme(on: boolean)
	send("RequestDefaultTheme", on)
end

return Intents
