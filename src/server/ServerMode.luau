--!strict
-- What this server is for (docs/DESIGN.md "Sandbox", "Tutorial"): public and private servers play matches; a
-- reserved server of this place plays the tutorial or a sandbox world for the one player sent there.
-- A reserved server can't be told its purpose when it is made, so the player sent there carries it in their
-- teleport data ({ mode = "sandbox", map = "earth" }; the tutorial's teleports send { tutorial = true }): the server
-- reads it from the first player to arrive, and keeps it. Teleport data comes through the client, so a forged one
-- can only turn a tutorial into a sandbox (neither pays anything a player could farm).
-- In Studio (and the harness) there are no reserved servers: the Workspace attributes "Sandbox" (true or a map id)
-- and "Tutorial" pick the mode, the sandbox first.

local Players = game:GetService("Players")

export type Mode = "Match" | "Tutorial" | "Sandbox"

local ServerMode = {}

local arrival: { [string]: any }? = nil -- the first player's teleport data, on a reserved server

-- Is this a reserved server (no private-server owner)? Only the tutorial and the sandbox make them.
function ServerMode.reserved(): boolean
	local ok, reserved = pcall(function()
		return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
	end)
	return ok and reserved == true
end

local function studioSandbox(): boolean
	local value = workspace:GetAttribute("Sandbox")
	return value == true or (type(value) == "string" and value ~= "")
end

function ServerMode.get(): Mode
	if studioSandbox() then
		return "Sandbox"
	elseif workspace:GetAttribute("Tutorial") == true then
		return "Tutorial"
	elseif ServerMode.reserved() then
		local data = arrival
		return if data and data.mode == "sandbox" then "Sandbox" else "Tutorial"
	end
	return "Match"
end

-- What the first player brought: the sandbox's map (`map`), or nil.
function ServerMode.data(key: string): any
	local data = arrival
	return if data then data[key] else nil
end

-- A reserved server waits for its first player before it starts anything: their teleport data says what it is for.
-- Returns at once anywhere else.
function ServerMode.await()
	if arrival ~= nil or not ServerMode.reserved() or studioSandbox() then
		return
	end
	local first = Players:GetPlayers()[1] or Players.PlayerAdded:Wait()
	local ok, data = pcall(function()
		return first:GetJoinData().TeleportData
	end)
	arrival = if ok and type(data) == "table" then data else {}
	print(string.format("[server] reserved server for %s", ServerMode.get()))
end

return ServerMode
