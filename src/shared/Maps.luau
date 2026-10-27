--!strict
-- Index of the playable maps. The map data itself is generated into ./MapData (see docs/MAPS.md).

local Types = require("./Types")

local Earth = require("./MapData/Earth")
local Eldmoor = require("./MapData/Eldmoor")
local Skyshards = require("./MapData/Skyshards")

local byId: { [string]: Types.MapDef } = {
	[Earth.id] = Earth,
	[Eldmoor.id] = Eldmoor,
	[Skyshards.id] = Skyshards,
}

local Maps = {}

Maps.ids = { Earth.id, Eldmoor.id, Skyshards.id }

function Maps.get(id: string): Types.MapDef
	local map = byId[id]
	assert(map, "unknown map: " .. tostring(id))
	return map
end

return Maps
