--!nocheck
-- The EU4 pack's diplomacy (docs/DESIGN.md "Diplomacy"), on Earth. Insults carry no message (Roblox's preset-text
-- rule): Alice presses Insult on the province sheet; Bob gets a neutral toast and an answer card, both see a marker
-- over Volga's capital, and only Alice sees a game-written flavour line. Bob insults back (Alice gets the grudge and
-- the toast), then laughs a second insult off (high spirits). Alice sends a gift and asks for military access, Bob
-- grants it from the offer card and Alice's army marches into his land; when the access runs out, the army walks home
-- under the white flag. The nations drawer's rows open a nation's sheet. Bots insult now and then and insult back.
-- With the setting off the buttons are gone and the server refuses.

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
	local Army = require("../../../src/shared/Sim/Army")
	local Diplomacy = require("../../../src/shared/Sim/Diplomacy")
	local Flavour = require("../../../src/shared/Flavour/Insults")
	local AIService = H.server("Services.AIService")
	local botStep = AIService.step
	AIService.step = function() end -- the bots hold still while the players talk
	local target: number? = nil
	for id, p in state.provinces do
		if p.owner == B and not p.isCapital and (target == nil or id < target) then
			target = id
		end
	end
	local volga = target :: number

	-- No flavour line may ever reach a player who didn't act: every line of every kind, with either name.
	local function flavourOn(client): string?
		for _, kind in { "insult", "laugh" } do
			for i in Flavour.lines("earth", kind) do
				for _, name in { "Rhine", "Volga", "Tigris" } do
					local line = Flavour.flavour("earth", kind, name, i - 1)
					if Emulator.findText(client, line) then
						return line
					end
				end
			end
		end
		return nil
	end
	local function waitFlavour(client): boolean
		local deadline = Emulator.now() + 12
		while flavourOn(client) == nil and Emulator.now() < deadline do
			Emulator.run(0.25)
		end
		return flavourOn(client) ~= nil
	end

	-- the province sheet of one of Bob's provinces: insult, gift and ask for access beside war and ally
	H.tapProvince(alice, volga)
	for _, name in { "Declare war", "Ally", "Insult", "Gift", "Ask access" } do
		H.expect(H.hasButton(alice, name), "the sheet has " .. name)
	end
	H.shot(alice, "foreign_sheet")

	-- Insult: one tap, no message
	Emulator.press(alice, "Insult")
	Emulator.run(1.5)
	H.expect(Diplomacy.grudge(state, B, A), "Volga holds a grudge against Rhine")
	H.expect(Diplomacy.answerWindow(state, B, A) ~= nil, "and may answer")
	H.expect(H.waitText(bob, "Rhine insulted you!"), "Bob gets a neutral toast")
	H.expect(H.find(bob, "Answer") ~= nil, "and the answer card")
	H.expect(Emulator.findText(bob, "Grudge: +10%") ~= nil, "which tells him about his grudge")
	H.expect(H.find(bob, "InsultBack") ~= nil and H.find(bob, "LaughOff") ~= nil, "Insult back and Laugh it off")
	H.expect(H.mapObject(bob, "Insulted" .. B) ~= nil, "a marker over Volga's capital, for Bob...")
	H.expect(H.mapObject(alice, "Insulted" .. B) ~= nil, "...and for Alice")
	H.expect(waitFlavour(alice), "Alice alone gets a game-written flavour line")
	H.expect(flavourOn(bob) == nil, "Bob never sees it")
	H.client(bob, "MapView").centreOn(H.provinceMap(bob, state.nations[B].capital), true)
	Emulator.run(1)
	H.shot(bob, "insulted")
	H.shot(alice, "insulter")

	-- Bob insults back from the card: now Rhine holds a grudge against Volga too
	Emulator.press(bob, "InsultBack")
	Emulator.run(1.5)
	H.expect(Diplomacy.grudge(state, A, B), "Rhine holds a grudge against Volga now")
	H.expect(Diplomacy.answerWindow(state, B, A) == nil, "one answer per insult")
	H.expect(Diplomacy.answerWindow(state, A, B) == nil, "and no answer to an answer")
	H.expect(H.waitText(alice, "Volga insulted you back!"), "Alice is told")
	H.expect(H.mapObject(alice, "Insulted" .. A) ~= nil, "a marker over Rhine's capital")
	H.expect(H.find(bob, "Answer") == nil, "Bob's card is gone")
	H.expect(waitFlavour(bob), "Bob gets his own flavour line")

	-- a second insult (the wait cleared on the server), which Bob laughs off
	state.cooldowns = {}
	H.client(alice, "Intents").diplomacy("Insult", B)
	Emulator.run(1.5)
	H.expect(H.find(bob, "LaughOff") ~= nil, "a new card")
	H.shot(bob, "answer_card")
	Emulator.press(bob, "LaughOff")
	Emulator.run(1.5)
	H.expect(not Diplomacy.grudge(state, B, A) and Diplomacy.grudge(state, B, 0), "Volga traded its grudge for high spirits")
	H.expect(H.waitText(alice, "Volga laughed off your insult"), "Alice is told")

	-- the Insult button waits; a gift goes through
	H.tapProvince(alice, volga)
	H.expect(H.within(alice, "Insult", " s"), "the Insult button counts its wait down")
	local bobGold = state.nations[B].gold
	state.nations[A].gold = 200
	Emulator.run(1.1)
	Emulator.press(alice, "Gift")
	Emulator.run(1.5)
	H.expect(state.nations[B].gold == bobGold + 25, "Bob got 25 gold")
	H.expect(H.waitText(bob, "sent you 25 gold"), "and a toast")

	-- military access: Alice asks, Bob accepts from the offer card, Alice's army marches into Volga's land
	local home = state.nations[A].capital
	local army = Army.spawn(state, A, home, 3000)
	H.expect(H.client(alice, "Relations").path(A, home, volga) == nil, "no route into Volga at peace")
	H.tapProvince(alice, volga)
	Emulator.press(alice, "Ask access")
	Emulator.run(1.5)
	H.expect(H.waitText(bob, "asks to march through your land"), "Bob sees Alice's request")
	H.shot(bob, "access_offer")
	Emulator.press(bob, "Accept")
	Emulator.run(1.5)
	H.expect(Diplomacy.hasAccess(state, A, B), "Rhine has military access to Volga")
	H.expect(H.waitText(alice, "lets your armies through"), "Alice is told")
	Emulator.press(alice, "Capital") -- her capital's sheet: Move picks up the army standing there
	Emulator.run(1.5)
	Emulator.press(alice, "Move")
	Emulator.run(0.3)
	H.tapProvince(alice, volga)
	H.expect(Emulator.findText(alice, "s march") ~= nil, "the route into Volga's land is open")
	H.shot(alice, "access_route")
	Emulator.press(alice, "Go")
	Emulator.run(1.5)
	H.expect(#army.path > 0, "the server accepted the march")
	local arriveBy = Emulator.now() + 30
	while state.provinces[army.location].owner ~= B and Emulator.now() < arriveBy do
		Emulator.run(1)
	end
	H.expect(state.provinces[army.location].owner == B, "Alice's army stands in Volga's land")
	H.expect(state.battles[army.location] == nil and state.provinces[army.location].siege == nil, "no fight, no siege")

	-- the nations drawer: Volga's row shows the access mark; a tap shows its capital with the same buttons
	Emulator.press(alice, "NationsButton")
	Emulator.run(0.5)
	H.expect(H.iconIn(alice, "Nation" .. B, "access"), "Volga's row shows the access mark")
	H.shot(alice, "drawer")
	Emulator.press(alice, "Nation" .. B)
	Emulator.run(2)
	local capitalName = state.provinces[state.nations[B].capital].name
	H.expect(Emulator.findText(alice, capitalName) ~= nil, "the sheet of Volga's capital opens")
	H.expect(H.hasButton(alice, "Gift") and not H.hasButton(alice, "Ask access"), "with its diplomacy buttons")
	Emulator.press(alice, "✕")

	-- the access runs out: the army walks home under the white flag
	for _, grant in state.access do
		grant.untilTick = state.tick + 1
	end
	Emulator.run(2)
	H.expect(army.retreating == true, "access over: Alice's army walks home")
	H.client(alice, "MapView").centreOn(H.provinceMap(alice, army.location), true)
	Emulator.run(1)
	H.expect(select(2, H.badge(alice, army.id)) == "retreat", "under the white flag")
	H.shot(alice, "access_over")

	-- bots: they insult now and then, and insult back
	local Config = H.shared("Config")
	local chance, back = Config.Bots.InsultChance, Config.Bots.InsultBackChance
	Config.Bots.InsultChance, Config.Bots.InsultBackChance = 1, 1
	AIService.step = botStep
	local bot = 3 -- Tigris
	H.client(alice, "Intents").diplomacy("Insult", bot)
	local deadline = Emulator.now() + 20
	local botInsults = 0
	repeat
		Emulator.run(1)
		botInsults = 0
		for _, c in state.cooldowns do
			if c.kind == "Insult" and state.nations[c.a].controller == "Bot" then
				botInsults += 1
			end
		end
	until (botInsults > 0 and Diplomacy.answerWindow(state, bot, A) == nil) or Emulator.now() > deadline
	Config.Bots.InsultChance, Config.Bots.InsultBackChance = chance, back
	H.expect(botInsults > 0, "bots insult their rivals now and then (" .. botInsults .. " so far)")
	H.expect(Diplomacy.grudge(state, bot, A), "Tigris holds a grudge against Rhine")
	H.expect(Diplomacy.grudge(state, A, bot), "and insulted Alice back")
	H.expect(H.waitText(alice, "Tigris insulted you back!"), "Alice hears it")

	-- the setting off (a private server's choice; the client learns it from the snapshot)
	state.setup.settings.diplomacy = false
	H.server("Replicator").sendSnapshot(alice.serverPlayer, state, A)
	Emulator.run(2)
	H.tapProvince(alice, volga)
	H.expect(not H.hasButton(alice, "Gift") and not H.hasButton(alice, "Insult"), "no insult or gift buttons")
	H.client(alice, "Intents").diplomacy("Gift", B)
	H.expect(H.waitText(alice, "are off on this server"), "and the server says why")
end

return {
	map = "earth", -- the map it needs (MAP overrides)
	run = run,
}
