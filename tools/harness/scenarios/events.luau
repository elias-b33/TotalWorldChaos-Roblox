--!nocheck
-- The EU4 pack's event cards (docs/DESIGN.md "Events"), on Earth. Alice's card comes at the top right with its title
-- on a plate, a line of flavour, the province it's about, a countdown and two choices with their effects; Bob never
-- sees a word of it (cards go to their own player only). Alice picks one and a toast says what happened; the next
-- card runs out of time and its default happens; a choice she can't pay for is grey and does nothing. Bob's card is
-- his alone. A bot answers its card through the same command. event_card reaches analytics. With the setting off no
-- card comes and the server refuses a choice.

local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	Emulator.run(2)
	local state = H.state()
	local A, B = H.myNation(alice), H.myNation(bob)
	H.expect(A == 1 and B == 2 and state.mapId == "earth", "Alice is Rhine, Bob is Volga, on Earth")
	local Config = require("../../../src/shared/Config")
	local EventCards = require("../../../src/shared/Sim/EventCards")
	local EventText = require("../../../src/shared/Flavour/EventCards")
	local AIService = H.server("Services.AIService")
	local botStep = AIService.step
	AIService.step = function() end -- the bots hold still for now

	-- The next card this nation gets is this event, on the next game second (every other event counts as had).
	local function comes(nationId: number, id: string)
		local seen = {}
		for _, def in EventCards.EVENTS do
			if def.id ~= id then
				table.insert(seen, def.id)
			end
		end
		state.chronicles[nationId] = { nextAt = state.tick + 1, seen = seen, card = nil, last = nil }
	end
	-- Any of an event's words on a client's screen.
	local function wordsOn(client, id: string): string?
		local text = EventText.TEXT[id]
		for _, words in { text.title, text.line, text.choices[1], text.choices[2] } do
			local found = Emulator.findText(client, words)
			if found then
				return found
			end
		end
		return nil
	end
	local function customs(name: string, userId: number)
		local out = {}
		for _, r in Emulator.analytics do
			if r.method == "LogCustomEvent" and r.userId == userId and r.args[1] == name then
				local f = r.args[#r.args] or {}
				local keys = Emulator.roblox.Enum.AnalyticsCustomFieldKeys
				table.insert(
					out,
					table.concat({
						f[keys.CustomField01.Name] or "",
						f[keys.CustomField02.Name] or "",
						f[keys.CustomField03.Name] or "",
					}, ",")
				)
			end
		end
		return out
	end

	-- Alice's card: a development event, so it names a province
	state.nations[A].gold = 100
	comes(A, "Potholes")
	Emulator.run(2)
	local card = EventCards.open(state, A)
	H.expect(card ~= nil and card.event == "Potholes", "Rhine got the card")
	H.expect(H.find(alice, "EventCard") ~= nil, "Alice sees it at the top right")
	H.expect(Emulator.findText(alice, "Potholes Everywhere") ~= nil, "its title")
	H.expect(Emulator.findText(alice, "A cart lost a wheel") ~= nil, "its flavour line")
	local where = state.provinces[card.province]
	H.expect(Emulator.findText(alice, "In " .. where.name) ~= nil, "the province it's about: " .. where.name)
	H.expect(H.within(alice, "EventTimer", " s"), "a countdown")
	H.expect(H.hasButton(alice, "EventChoice1") and H.hasButton(alice, "EventChoice2"), "two choices")
	H.expect(H.within(alice, "EventChoice1", "-40") and H.iconIn(alice, "EventChoice1", "up"), "with their effects")
	H.expect(H.find(bob, "EventCard") == nil and wordsOn(bob, "Potholes") == nil, "Bob sees nothing of it")
	H.shot(alice, "card")

	-- she paves the roads: -40 gold, +1 development there, and a toast says so
	local dev = where.development
	Emulator.press(alice, "EventChoice1")
	Emulator.run(1.5)
	H.expect(H.find(alice, "EventCard") == nil, "the card is gone")
	H.expect(state.nations[A].gold < 100 and where.development == dev + 1, "-40 gold, +1 development in " .. where.name)
	H.expect(H.waitText(alice, "Pave the roads: -40 gold, +1 development in " .. where.name), "the toast tells her")
	H.shot(alice, "picked")
	H.expect(wordsOn(bob, "Potholes") == nil, "still nothing for Bob")

	-- the next card runs out of time: its default happens
	comes(A, "Traveller")
	Emulator.run(2)
	local traveller = EventCards.open(state, A)
	H.expect(traveller ~= nil and H.find(alice, "EventCard") ~= nil, "a new card")
	local place = state.provinces[traveller.province]
	local before = place.development
	Emulator.run(Config.EventCards.ChoiceTicks + 1)
	H.expect(EventCards.open(state, A) == nil and place.development == before + 1, "time ran out: Ask about farms")
	H.expect(H.find(alice, "EventCard") == nil, "the card is gone")
	H.expect(H.waitText(alice, "Time's up! Ask about farms"), "and the toast says what happened")

	-- a choice she can't pay for is grey and does nothing
	state.nations[A].gold = 0
	comes(A, "Potholes")
	Emulator.run(2)
	local poor = EventCards.open(state, A)
	H.expect(poor ~= nil, "another card")
	Emulator.press(alice, "EventChoice1")
	Emulator.run(1.5)
	H.expect(EventCards.open(state, A) == poor and H.find(alice, "EventCard") ~= nil, "Pave the roads needs 40 gold")
	H.shot(alice, "cant_pay")
	Emulator.press(alice, "EventChoice2")
	Emulator.run(1.5)
	H.expect(EventCards.open(state, A) == nil and state.nations[A].gold >= 25, "Sell the cobbles: +25 gold")

	-- Bob's card is his alone
	comes(B, "Cats")
	Emulator.run(2)
	H.expect(Emulator.findText(bob, "Too Many Cats") ~= nil, "Bob's card")
	H.expect(wordsOn(alice, "Cats") == nil, "Alice sees nothing of it")
	H.shot(bob, "card")
	Emulator.press(bob, "EventChoice2")
	Emulator.run(1.5)
	H.expect(H.waitText(bob, "Hold a cat show: +3,000 manpower"), "Bob's toast")
	H.expect(wordsOn(alice, "Cats") == nil, "Alice never sees it")

	-- a bot answers its card through the same command (it doesn't wait for the default)
	AIService.step = botStep
	local bot = 3 -- Tigris
	comes(bot, "Harvest")
	Emulator.run(1.5)
	local botCard = EventCards.open(state, bot)
	H.expect(botCard ~= nil, "Tigris got a card")
	local deadline = Emulator.now() + 10
	while EventCards.open(state, bot) ~= nil and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local last = state.chronicles[bot].last
	H.expect(last ~= nil and last.card == botCard.id and not last.auto, "Tigris answered it")
	H.expect(wordsOn(alice, "Harvest") == nil and wordsOn(bob, "Harvest") == nil, "no player saw the bot's card")

	-- analytics: event_card for each card a player's nation closed
	local logged = customs("event_card", alice.serverPlayer.UserId)
	H.expect(
		table.find(logged, "Potholes,earth,picked_1") ~= nil,
		"event_card: picked (" .. table.concat(logged, " ") .. ")"
	)
	H.expect(table.find(logged, "Traveller,earth,timeout_1") ~= nil, "event_card: timed out")
	H.expect(#customs("event_card", bob.serverPlayer.UserId) == 1, "Bob's one card")

	-- the setting off (a private server's choice): no card comes, and the server refuses a choice
	local next = state.nextCardId
	state.setup.settings.events = false
	comes(A, "Cats")
	Emulator.run(2)
	H.expect(state.nextCardId == next and H.find(alice, "EventCard") == nil, "no card with the setting off")
	H.client(alice, "Intents").eventChoice(next, 1)
	H.expect(H.waitText(alice, "Events are off on this server"), "and the server says why")
end

return {
	map = "earth", -- the map it needs (MAP overrides)
	run = run,
}
