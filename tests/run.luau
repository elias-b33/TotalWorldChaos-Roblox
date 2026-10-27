--!strict
-- Runs every tests/*.spec.luau in its own Lune process and exits non-zero if any fails.
-- Usage: lune run tests/run            (all specs)
--        lune run tests/run economy    (specs whose name contains "economy")

local fs = require("@lune/fs")
local process = require("@lune/process")

local filter = process.args[1]
local specs = {}
for _, name in fs.readDir("tests") do
	if string.sub(name, -10) == ".spec.luau" and (filter == nil or string.find(name, filter, 1, true)) then
		table.insert(specs, name)
	end
end
table.sort(specs)

local failedSpecs = {}
for _, name in specs do
	print(name)
	local result = process.exec("lune", { "run", "tests/" .. name }, { stdio = "inherit" })
	if not result.ok then
		table.insert(failedSpecs, name)
	end
end

print(string.format("\n%d spec files, %d failed", #specs, #failedSpecs))
for _, name in failedSpecs do
	print("  FAILED: " .. name)
end
if #specs == 0 or #failedSpecs > 0 then
	process.exit(1)
end
