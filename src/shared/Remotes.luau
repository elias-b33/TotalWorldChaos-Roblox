--!strict
-- The remotes from docs/DESIGN.md "Remotes". The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

local EVENTS = {
	-- client -> server
	"RequestMove",
	"RequestRecruit",
	"RequestBuild",
	"RequestDevelop",
	"RequestDiplomacy",
	"RequestPower",
	"RequestVote", -- lobby: mapId
	"RequestPick", -- lobby: nationId
	"RequestSetting", -- lobby, private server owner: key, value, extra (Sim.Settings.set)
	"RequestTutorial", -- tutorial: "Skip" | "Leave"
	"RequestBuy", -- shop: itemId, "Glory" | "Robux"
	"RequestEquip", -- shop: itemId
	"RequestEmote", -- shop: emote itemId
	"RequestClaim", -- quests: quest key
	"RequestQuestReroll", -- quests: quest key
	"RequestTelemetry", -- analytics: a UI funnel signal (Sim.Telemetry.CLIENT_SIGNALS) and an optional short string
	"RequestDefaultTheme", -- shop: true = always show the classic map (the theme opt-out)
	"RequestAd", -- rewarded video: the placement ("quest_reroll", Sim.Ads.PLACEMENT)
	"RequestSeason", -- season pass: "Claim" tier track | "ClaimAll" | "Viewed"
	-- server -> client
	"Lobby", -- the map vote and the draft (Sim.Lobby.LobbyView)
	"CommandResult",
	"Snapshot",
	"Delta",
	"Notify",
	"Profile", -- your ProfileSummary (on join and after every change)
	"Reward", -- your RewardReport at Results
	"Tutorial", -- your TutorialView in the tutorial match (nil = no prompts)
	"Shop", -- your ShopView (on join and after every change)
	"Quests", -- your QuestView (on join, at Results and after every change)
	"NotificationPrompt", -- after your first finished match: ask to turn on experience notifications (Sim.Ads)
	"Season", -- your SeasonView (on join, at Results and after every change)
}
local UNRELIABLE_EVENTS = { "ArmyPositions" }

local Remotes = {}

-- Server only.
function Remotes.create()
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for _, name in EVENTS do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in UNRELIABLE_EVENTS do
		local remote = Instance.new("UnreliableRemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.event(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.unreliableEvent(name: string): UnreliableRemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: UnreliableRemoteEvent
end

return Remotes
