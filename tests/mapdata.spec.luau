--!strict
-- The generated maps follow the rules in docs/MAPS.md.
local MapGrid = require("../src/shared/MapGrid")
local Maps = require("../src/shared/Maps")
local T = require("./TestKit")

for _, id in Maps.ids do
	local map = Maps.get(id)
	local provinces = map.provinces

	T.test(id .. ": province ids are 1..N and within the 150 budget", function()
		T.expect(#provinces > 0 and #provinces <= 150, "province count " .. #provinces)
		for i, p in provinces do
			T.equal(p.id, i)
		end
	end)

	T.test(id .. ": neighbours are valid and symmetric", function()
		for _, p in provinces do
			for _, n in p.neighbors do
				T.expect(provinces[n] ~= nil, p.name .. " has unknown neighbour " .. n)
				T.expect(n ~= p.id, p.name .. " neighbours itself")
				T.expect(table.find(provinces[n].neighbors, p.id) ~= nil, p.name .. " -> " .. n .. " is one-way")
			end
		end
	end)

	T.test(id .. ": the province grid covers every province about its size", function()
		local grid = MapGrid.decode(map)
		T.equal(buffer.len(grid.ids), grid.width * grid.height)
		T.equal(map.imageSize.y / grid.height, grid.scale, "same scale on both axes")
		local count: { [number]: number } = {}
		for i = 0, buffer.len(grid.ids) - 1 do
			local pid = buffer.readu8(grid.ids, i)
			count[pid] = (count[pid] or 0) + 1
		end
		local centred = 0
		for _, p in provinces do
			local expected = p.area / (grid.scale * grid.scale)
			local n = count[p.id] or 0
			T.expect(n > expected * 0.7 and n < expected * 1.3, p.name .. " has " .. n .. " grid pixels")
			if MapGrid.at(grid, p.center.x / grid.scale, p.center.y / grid.scale) == p.id then
				centred += 1
			end
		end
		T.expect(centred >= #provinces * 0.95, "province centres lie in their province: " .. centred)
	end)

	T.test(id .. ": every strait is a neighbour link", function()
		for _, s in map.straits do
			T.expect(table.find(provinces[s.a].neighbors, s.b) ~= nil, "strait " .. s.a .. "-" .. s.b)
		end
	end)

	T.test(id .. ": every passable province reaches every other", function()
		local start
		local passable = 0
		for _, p in provinces do
			if p.terrain ~= "Mountain" then
				passable += 1
				start = start or p.id
			end
		end
		local seen = { [start] = true }
		local queue = { start }
		local count = 1
		while #queue > 0 do
			local cur = table.remove(queue) :: number
			for _, n in provinces[cur].neighbors do
				if not seen[n] and provinces[n].terrain ~= "Mountain" then
					seen[n] = true
					count += 1
					table.insert(queue, n)
				end
			end
		end
		T.equal(count, passable, "reachable passable provinces")
	end)

	T.test(id .. ": 10 nations, each with 8 provinces and 17 development", function()
		T.equal(#map.nations, 10)
		for _, n in map.nations do
			local owned, dev = 0, 0
			for _, p in provinces do
				if p.startOwner == n.slot then
					owned += 1
					dev += p.development
				end
			end
			T.equal(owned, 8, n.name .. " provinces")
			T.equal(dev, 17, n.name .. " development")
			local cap = provinces[n.capital]
			T.expect(cap.isCapital and cap.startOwner == n.slot, n.name .. " capital")
		end
	end)

	T.test(id .. ": mountains are never owned and development is 1..5", function()
		for _, p in provinces do
			T.expect(p.development >= 1 and p.development <= 5, p.name .. " development")
			if p.terrain == "Mountain" then
				T.expect(p.startOwner == nil, p.name .. " is an owned mountain")
			end
		end
	end)
end

T.finish()
