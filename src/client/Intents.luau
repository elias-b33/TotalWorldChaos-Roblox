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
	BadBuilding = "🚫 Unknown building",
	BadRequest = "🚫 Bad request",
	UnknownArmy = "🚫 That army is gone",
	NotYourArmy = "🚫 Not your army",
	InBattle = "💥 It's in a battle",
	Retreating = "🏳 It's retreating home",
	NoPath = "🚫 Can't get there",
	BadTarget = "🚫 Not possible",
	PeaceTime = "🕊 No wars until 3:00",
	Allied = "🤝 You're allies",
	AlreadyAtWar = "⚔ Already at war",
	Truce = "🕊 Truce still running",
	NoBorder = "🗺 You must share a border",
	AlreadyAllied = "🤝 Already allied",
	AtWar = "⚔ You're at war",
	NotAtWar = "🕊 You're not at war",
	AllianceFull = "🤝 Alliance is full (3)",
	NoOffer = "⌛ That offer expired",
	NotEnoughCharges = "⚡ Not enough charges",
	Immune = "🛡 Hit by a power less than 30 s ago",
	NoBuilding = "🏚 No building there",
	OwnTarget = "🚫 Not on yourself",
	NoPowersYet = "⏳ Powers unlock at 3:00",
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

function Intents.recruit(provinceId: number, regiments: number)
	send("RequestRecruit", provinceId, regiments)
end

function Intents.move(armyId: number, to: number)
	send("RequestMove", armyId, to)
end

-- action: War | Ally | AcceptAlly | Peace | AcceptPeace
function Intents.diplomacy(action: string, target: number, gold: number?)
	send("RequestDiplomacy", action, target, gold or 0)
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

return Intents
