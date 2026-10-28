--!strict
-- The start menu (docs/DESIGN.md "Match structure"): a player arriving on a public or private server first sees a
-- framed window over the map with Play online, Singleplayer and How to play. Thin wrapper: it tells each client
-- when to show its menu (the Menu remote), answers Play online (RequestMenu through CommandRouter) by handing the
-- player to GameLoop's join (the first pick's line, the vote, the end of the draft, or a bot's nation mid-match) and
-- logs the menu events. Singleplayer is the sandbox's own entry (RequestSandbox "Enter", SandboxService) and How to
-- play is the client's alone.
--
-- Players still in the menu watch: they are neither drafted nor seated until they choose Play online. A server's
-- first match is a first pick instead of a vote (Sim.Lobby): the first player to choose Play online picks the map.
-- The menu is on for public and private servers (ServerMode "Match"), never on a tutorial or sandbox server. In
-- Studio, Workspace "SkipLobby" turns it off (solo tests start straight in a match) and "Menu" decides it: true
-- turns it on even with SkipLobby, false turns it off (the first match then votes like the others).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared")
local Shared = ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)

local Server = script.Parent.Parent
local CommandRouter = require(Server.CommandRouter)
local ServerMode = require(Server.ServerMode)
local TelemetryService = require(script.Parent.TelemetryService)

local MenuService = {}

local remote: RemoteEvent
local online: { [Player]: boolean } = {} -- chose Play online
local join: (Player) -> () = function(_player: Player) end -- GameLoop's: into this server's matches

-- Does an arriving player see the start menu here?
function MenuService.enabled(): boolean
	if ServerMode.get() ~= "Match" then
		return false
	end
	local setting = workspace:GetAttribute("Menu")
	if type(setting) == "boolean" then
		return setting
	end
	return workspace:GetAttribute("SkipLobby") ~= true
end

-- Has this player joined the matches here? Always, with the menu off.
function MenuService.isOnline(player: Player): boolean
	return online[player] == true or not MenuService.enabled()
end

-- Everyone in the server who joined the matches, in the order they came in.
function MenuService.onlinePlayers(): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if MenuService.isOnline(player) then
			table.insert(out, player)
		end
	end
	return out
end

-- A player arrived (GameLoop has sent them what the server is doing, to watch behind the menu).
function MenuService.show(player: Player)
	remote:FireClient(player, true)
	TelemetryService.menuShown(player)
	print(string.format("[menu] %s sees the start menu", player.Name))
end

-- Play online (CommandRouter checked the shape and the rate limit): the menu closes and the player joins.
local function apply(player: Player, action: Types.MenuAction): (boolean, string?)
	if action ~= "Online" then
		return false, "BadRequest"
	end
	remote:FireClient(player, false)
	if MenuService.isOnline(player) then
		return true, nil -- already in (a second tap, or the menu is off)
	end
	online[player] = true
	TelemetryService.menuChoice(player, "online")
	print(string.format("[menu] %s chose Play online", player.Name))
	join(player)
	return true, nil
end

-- `onJoin` puts a player who chose Play online into this server's matches (GameLoop).
function MenuService.init(onJoin: (Player) -> ())
	join = onJoin
	remote = Remotes.event("Menu")
	CommandRouter.onMenu(apply)
	Players.PlayerRemoving:Connect(function(player)
		online[player] = nil
	end)
end

return MenuService
