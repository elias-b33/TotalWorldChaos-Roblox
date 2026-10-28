--!nocheck
-- Phase 4: cosmetics in the match, part 2. In the Lobby Alice buys and equips the Night theme (Carol has it too,
-- Bob brings Winter) and they all vote Earth: Night wins the theme vote, the draft credits Alice and Carol, and
-- everyone's map is painted in Night. Bob opts out and sees the classic map. Then each power-effect variant plays
-- through the real flow (cast -> event with the caster -> Effects in the caster's look), photographed mid-animation.

local Emulator = require("../Emulator")
local H = require("../H")

local function run()
	local Primordial = require("../../../src/shared/Sim/Primordial")
	local Army = require("../../../src/shared/Sim/Army")
	-- press a button on one shop card (several cards show the same price)
	local pressIn = H.pressIn
	Emulator.run(1)
	local alice = Emulator.addClient("Alice")
	local bob = Emulator.addClient("Bob")
	local carol = Emulator.addClient("Carol")
	Emulator.run(2)
	local Data = H.server("Services.PlayerDataService")
	local LobbyService = H.server("Services.LobbyService")
	H.expect(LobbyService.phase() == "Lobby", "the server opens the Lobby")

	-- Alice buys the Night theme for Glory and equips it; her power effects are all variants
	Data.update(alice.serverPlayer, function(d)
		d.glory = 3000
		d.owned.fx_meteor_comet, d.owned.fx_plague_violet, d.owned.fx_blessing_rays = true, true, true
		d.equipped.PowerFxMeteor = "fx_meteor_comet"
		d.equipped.PowerFxPlague = "fx_plague_violet"
		d.equipped.PowerFxBlessing = "fx_blessing_rays"
	end)
	Data.update(carol.serverPlayer, function(d)
		d.owned.theme_night = true
		d.equipped.Theme = "theme_night"
	end)
	Data.update(bob.serverPlayer, function(d)
		d.owned.theme_winter, d.owned.fx_meteor_ice = true, true
		d.equipped.Theme = "theme_winter"
		d.equipped.PowerFxMeteor = "fx_meteor_ice"
	end)
	H.server("Services.ShopService").onPhase("Lobby")
	Emulator.run(1)
	Emulator.press(alice, "ShopButton")
	Emulator.run(0.5)
	Emulator.press(alice, "Tab_Theme")
	Emulator.run(1)
	H.expect(alice.localPlayer.PlayerGui:FindFirstChild("ThemePreview", true) ~= nil, "theme cards show a painted map")
	pressIn(alice, "Card_theme_night", "1,200", "medal")
	Emulator.run(1)
	local data = Data.data(alice.serverPlayer)
	H.expect(data.owned.theme_night == true and data.glory == 1800, "Night bought for 1,200 Glory")
	pressIn(alice, "Card_theme_night", "Equip")
	Emulator.run(1)
	H.expect(data.equipped.Theme == "theme_night", "Alice equipped Night")
	H.expect(Emulator.findText(alice, "What you see") ~= nil, "the Themes tab has the opt-out card")
	H.shot(alice, "shop_themes")
	Emulator.press(alice, "Tab_PowerFx")
	Emulator.run(1)
	H.expect(alice.localPlayer.PlayerGui:FindFirstChild("EffectPreview", true) ~= nil, "power effects show a preview")
	H.shot(alice, "shop_powers")
	Emulator.press(alice, "✕")
	Emulator.run(0.5)

	-- the vote: Alice's cards are painted in Night; everyone votes Earth (Night 2, Winter 1)
	Emulator.run(2)
	H.expect(Emulator.findText(alice, "You bring the Night theme") ~= nil, "the vote says Alice brings Night")
	H.expect(H.client(alice, "Cosmetics").myTheme() == "night", "her thumbnails are painted in Night")
	H.shot(alice, "vote_night_cards")
	for _, client in { alice, bob, carol } do
		Emulator.press(client, "Card_earth")
		Emulator.press(client, "Card_earth")
	end
	local deadline = Emulator.now() + 70
	while LobbyService.phase() == "Lobby" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	local state = H.state()
	H.expect(state.mapId == "earth" and state.theme == "theme_night", "Earth won, painted in Night (2 votes to 1)")
	Emulator.run(1.5)
	H.expect(Emulator.findText(alice, "Night Earth, brought by Alice, Carol") ~= nil, "the draft credits its owners")
	H.shot(bob, "draft_night_earth")

	-- the match: every client paints Night
	deadline = Emulator.now() + 60
	while state.phase == "Pick" and Emulator.now() < deadline do
		Emulator.run(1)
	end
	Emulator.run(2)
	H.expect(state.phase == "Peace", "the match started")
	for _, client in { alice, bob, carol } do
		H.expect(H.client(client, "ClientState").snapshot().theme == "theme_night", client.name .. " got the theme")
		H.expect(H.client(client, "Cosmetics").matchTheme() == "night", client.name .. " paints the map in Night")
	end
	Emulator.run(3) -- the painting is spread over frames
	H.shot(alice, "night_earth")
	local A, B = H.myNation(alice), H.myNation(bob)
	local MapView = H.client(alice, "MapView")
	local capital = state.nations[A].capital
	MapView.centreOn(H.provinceMap(alice, capital), true)
	Emulator.run(2)
	H.shot(alice, "night_close_up")

	-- Bob opts out: "always classic", saved in his profile; his map repaints in the classic look
	Emulator.press(bob, "ShopButton")
	Emulator.run(0.5)
	Emulator.press(bob, "Tab_Theme")
	Emulator.run(0.5)
	pressIn(bob, "Card_ThemeSetting", "Always classic")
	Emulator.run(1)
	H.expect(Data.data(bob.serverPlayer).settings.defaultTheme == true, "the opt-out is saved")
	H.expect(H.client(bob, "Cosmetics").matchTheme() == "", "Bob's map goes back to classic")
	Emulator.press(bob, "✕")
	Emulator.run(3)
	H.shot(bob, "bob_opted_out")
	H.expect(H.client(alice, "Cosmetics").matchTheme() == "night", "Alice still sees Night")

	-- War: each power-effect variant, cast through Sim.Primordial (the event carries the caster)
	state.tick = 179
	Emulator.run(2)
	local Effects = H.client(alice, "Effects")
	local function cast(by: number, power: string, target: number)
		state.nations[by].charges = 5
		for _, n in state.nations do
			n.powerImmuneUntil = 0
		end
		state.powerCooldowns = {} -- and each caster's 2-minute cooldown
		local ok, why = Primordial.use(state, { nation = by }, power, target)
		H.expect(ok, power .. " was cast (" .. tostring(why) .. ")")
	end
	local function waitFor(kind: string, look: string)
		local start = Emulator.now()
		local function seen()
			for _, h in Effects.history() do
				if h.at >= start and h.kind == kind and h.look == look then
					return true
				end
			end
			return false
		end
		local until_ = Emulator.now() + 5
		while not seen() and Emulator.now() < until_ do
			Emulator.run(0.1)
		end
		H.expect(seen(), kind .. " plays in the " .. (if look == "" then "default" else look) .. " look")
	end
	local bobCapital = state.nations[B].capital
	MapView.centreOn(H.provinceMap(alice, bobCapital), true)
	Emulator.run(1.5)
	local target = Army.spawn(state, B, bobCapital, 6000)
	Emulator.run(1.2)
	cast(A, "Meteor", target.id)
	waitFor("Meteor", "comet")
	Emulator.run(0.45)
	H.shot(alice, "fx_comet_falling")
	Emulator.run(0.45)
	H.shot(alice, "fx_comet_impact")
	Emulator.run(3)

	cast(A, "Plague", B)
	waitFor("Plague", "violet")
	Emulator.run(0.5)
	H.shot(alice, "fx_violet_plague")
	Emulator.run(3)

	MapView.centreOn(H.provinceMap(alice, capital), true)
	Emulator.run(1.5)
	cast(A, "Blessing", capital)
	waitFor("Blessing", "rays")
	Emulator.run(0.6)
	H.shot(alice, "fx_sun_rays")
	Emulator.run(3)

	local mine = Army.spawn(state, A, capital, 6000)
	Emulator.run(1.2)
	cast(B, "Meteor", mine.id)
	waitFor("Meteor", "ice")
	Emulator.run(0.45)
	H.shot(alice, "fx_ice_falling")
	Emulator.run(0.45)
	H.shot(alice, "fx_ice_impact")
	Emulator.run(3)

	-- Carol has no variants: her Meteor keeps the default look; sounds are the same cue for every look
	local C = H.myNation(carol)
	Army.spawn(state, A, capital, 6000) -- joins the army already standing there (stacks merge)
	Emulator.run(1.2)
	local other
	for _, army in state.armies do
		if army.owner == A and army.location == capital then
			other = army
		end
	end
	cast(C, "Meteor", other.id)
	waitFor("Meteor", "")
	Emulator.run(2)
	local impacts = 0
	for _, s in Emulator.sounds do
		if s.name == "MeteorImpact" then
			impacts += 1
		end
	end
	H.expect(impacts >= 3, "every Meteor look lands with the same impact sound")
end

return {
	lobby = true, -- it runs the Lobby; the rest boot with SkipLobby
	run = run,
}
