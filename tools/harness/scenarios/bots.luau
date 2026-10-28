--!nocheck
-- Phase 3: Alice and nine bots for six game minutes on Skyshards. The bots expand in Peace and go to war after
-- it, every command goes through the real CommandRouter, and a nation whose player leaves plays on as a bot.

local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	Emulator.run(2)
	local state = H.state()
	local me = H.myNation(alice)
	H.expect(me == 1, "Alice is seated as nation 1")
	local Match = require("../../../src/shared/Sim/Match")
	local start = {}
	for id, nation in state.nations do
		if id ~= me then
			H.expect(nation.controller == "Bot", nation.name .. " is a bot")
			start[id] = Match.provinceCount(state, id)
		end
	end

	-- count what bots submit and what the server refuses (dry runs inside the planner use copies of the state)
	local CommandRouter = H.server("CommandRouter")
	local submitted, rejected = {}, {}
	local submit = CommandRouter.submitForBot
	CommandRouter.submitForBot = function(nationId, command)
		submitted[nationId] = (submitted[nationId] or 0) + 1
		submit(nationId, command)
	end
	local sharedNode = Emulator.server.dm:GetService("ReplicatedStorage").Shared
	local Commands = Emulator.server.modules[sharedNode.Sim.Commands]
	local apply = Commands.apply
	Commands.apply = function(s, nationId, command)
		local ok, reason = apply(s, nationId, command)
		if not ok and s == H.state() and s.nations[nationId] and s.nations[nationId].controller == "Bot" then
			table.insert(rejected, string.format("%s %s: %s", s.nations[nationId].name, command.kind, tostring(reason)))
		end
		return ok, reason
	end

	H.shot(alice, "start")
	Emulator.run(60)
	local moving = 0
	for _, a in state.armies do
		if a.owner ~= me and a.owner ~= 0 and #a.path > 0 then
			moving += 1
		end
	end
	H.expect(moving > 0, "bot armies are marching after a minute")
	Emulator.run(115) -- just before the war phase
	H.shot(alice, "peace_expansion")
	local grown = 0
	for id, n in start do
		if Match.provinceCount(state, id) > n then
			grown += 1
		end
	end
	H.expect(grown >= 8, string.format("%d of 9 bots expanded in Peace", grown))

	-- Bob joins, takes a bot's nation, and leaves: it plays on as a bot straight away
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local B = H.myNation(bob)
	H.expect(B == 2 and state.nations[B].controller == "Player", "Bob takes over Zephyr")
	local before = submitted[B] or 0
	Emulator.run(10)
	H.expect((submitted[B] or 0) == before, "no bot plans for Bob's nation while he plays")
	Emulator.removeClient(bob)
	Emulator.run(10)
	H.expect(state.nations[B].controller == "Bot", "Zephyr is a bot again after Bob left")
	H.expect((submitted[B] or 0) > before, "the bot carries on for Zephyr")

	Emulator.run(360 - Emulator.now())
	H.shot(alice, "six_minutes")
	local total0, total = 0, 0
	for id, n in start do
		total0 += n
		total += Match.provinceCount(state, id)
		print(
			string.format("    %-10s %2d -> %2d provinces", state.nations[id].name, n, Match.provinceCount(state, id))
		)
	end
	H.expect(total > total0, string.format("bots own more provinces than they started with (%d -> %d)", total0, total))
	H.expect(next(state.wars) ~= nil, "bots went to war after Peace")
	local sent = 0
	for _, n in submitted do
		sent += n
	end
	for _, line in rejected do
		print("    rejected: " .. line)
	end
	H.expect(sent > 100 and #rejected <= 2, string.format("%d bot commands, %d refused by the server", sent, #rejected))
	Commands.apply = apply
	CommandRouter.submitForBot = submit
end

return { run = run }
