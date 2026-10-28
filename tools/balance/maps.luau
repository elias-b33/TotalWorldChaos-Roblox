--!strict
-- Map facts the balance numbers depend on: provinces, mountains, neutral land, development and garrisons.
--   lune run tools/balance/maps
local Config = require("../../src/shared/Config")
local Maps = require("../../src/shared/Maps")

print(
	"| Map | Provinces (all) | Mountains | Ownable | Start-owned | Neutral | Neutral dev 1/2/3/4/5 "
		.. "| Neutral garrisons (men: count) | Provinces for crown / domination (of ownable) | Forest+hills share of land |"
)
print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
for _, id in Maps.ids do
	local m = Maps.get(id)
	local total, mountains, neutral, owned, rough = 0, 0, 0, 0, 0
	local dev = { 0, 0, 0, 0, 0 }
	local garrisons: { [number]: number } = {}
	for _, p in m.provinces do
		total += 1
		if p.terrain == "Mountain" then
			mountains += 1
		else
			if p.terrain ~= "Plains" then
				rough += 1
			end
			if p.startOwner == nil then
				neutral += 1
				dev[p.development] += 1
				local g = p.garrison or Config.NeutralGarrison
				garrisons[g] = (garrisons[g] or 0) + 1
			else
				owned += 1
			end
		end
	end
	local gs = {}
	for men, n in garrisons do
		table.insert(gs, { men, n })
	end
	table.sort(gs, function(a, b)
		return a[1] < b[1]
	end)
	local gtext = {}
	for _, g in gs do
		table.insert(gtext, string.format("%d: %d", g[1], g[2]))
	end
	local devText = {}
	for _, n in dev do
		table.insert(devText, tostring(n))
	end
	print(
		string.format(
			"| %s | %d | %d | %d | %d | %d | %s | %s | %d / %d | %.0f%% |",
			id,
			total,
			mountains,
			total - mountains,
			owned,
			neutral,
			table.concat(devText, "/"),
			table.concat(gtext, ", "),
			math.ceil(Config.Diplomacy.CoalitionThreshold * (total - mountains)), -- shares count ownable land only
			math.ceil(Config.Win.DominationShare * (total - mountains)),
			100 * rough / (total - mountains)
		)
	)
end
