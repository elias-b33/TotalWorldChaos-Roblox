--!strict
-- Tiny test helper for Lune specs. Each spec calls TestKit.test(...) and ends with TestKit.finish().

local process = require("@lune/process")

local TestKit = {}

local passed = 0
local failed = 0

local function show(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

function TestKit.test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

function TestKit.expect(condition: any, message: string?)
	if not condition then
		error(message or "expected a truthy value", 2)
	end
end

function TestKit.equal(actual: any, expected: any, message: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if message then message .. ": " else "",
				show(expected),
				show(actual)
			),
			2
		)
	end
end

function TestKit.near(actual: number, expected: number, tolerance: number, message: string?)
	if math.abs(actual - expected) > tolerance then
		error(
			string.format(
				"%sexpected %s ± %s, got %s",
				if message then message .. ": " else "",
				expected,
				tolerance,
				actual
			),
			2
		)
	end
end

function TestKit.finish()
	print(string.format("  %d passed, %d failed", passed, failed))
	if failed > 0 then
		process.exit(1)
	end
end

return TestKit
