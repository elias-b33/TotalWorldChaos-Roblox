--!strict
-- The shop rules (Sim.Shop) and the catalogue: prices, Glory purchases, Robux purchase checks, grants, equipping,
-- the cosmetics every nation shows, emote cooldowns and the starter-pack offer.
local Catalogue = require("../src/shared/Catalogue")
local Config = require("../src/shared/Config")
local Maps = require("../src/shared/Maps")
local Match = require("../src/shared/Sim/Match")
local Progression = require("../src/shared/Sim/Progression")
local Shop = require("../src/shared/Sim/Shop")
local Snapshot = require("../src/shared/Snapshot")
local T = require("./TestKit")

local S = Config.Shop

T.test("prices come from the rarity ladder in Config", function()
	local sun = assert(Catalogue.item("flag_sun"))
	T.equal(sun.rarity, "Rare")
	T.equal(sun.robux, S.RobuxPrice.Rare)
	T.equal(sun.glory, S.GloryPrice.Rare)
	local dragon = assert(Catalogue.item("token_dragon"))
	T.equal(dragon.robux, 249)
	T.equal(dragon.glory, nil, "Legendary is not sold for Glory")
	local wave = assert(Catalogue.item("emote_wave"))
	T.equal(wave.robux, S.EmoteRobux.Static)
	T.equal(wave.glory, S.EmoteGlory.Static)
	T.equal(assert(Catalogue.item("emote_fire")).glory, S.EmoteGlory.Animated)
end)

T.test("every item has a known slot, a unique id and a price or a reason to have none", function()
	local seen = {}
	for _, item in Catalogue.ITEMS do
		T.expect(seen[item.id] == nil, "duplicate id " .. item.id)
		seen[item.id] = true
		T.expect(table.find(Catalogue.SLOTS, item.slot) ~= nil, "slot of " .. item.id)
		if item.free or item.vipOnly or item.season then
			T.equal(item.robux, nil, item.id .. " is not sold")
		else
			T.expect(item.robux ~= nil, item.id .. " has a Robux price")
			T.expect(Catalogue.PRODUCT_IDS[item.id] ~= nil, item.id .. " has a product id entry")
		end
		if item.slot == "PowerFx" then
			T.expect(item.power ~= nil, item.id .. " names its power")
		end
	end
	for slot, id in Catalogue.DEFAULTS do
		local item = assert(Catalogue.item(id))
		T.equal(item.slot, slot)
		T.expect(item.free, id .. " is free")
	end
	for _, offer in Catalogue.OFFERS do
		for _, id in offer.items do
			T.expect(Catalogue.item(id) ~= nil, offer.id .. " contains " .. id)
		end
	end
end)

T.test("bundles show the real sum of their pieces", function()
	-- starter pack: Rare flag 99 + Rare token 99 + two static emotes 25 + 25 + Common frame 49
	T.equal(Shop.bundleValue("starter"), 297)
	T.equal(assert(Catalogue.offer("starter")).robux, 149)
	T.equal(Shop.bundleValue("set_royal"), 297)
	T.equal(assert(Catalogue.offer("set_royal")).robux, S.RareSetRobux)
end)

T.test("a Glory purchase checks the price and the balance", function()
	local p = Progression.newProfile()
	p.glory = 1199
	local ok, reason = Shop.buyWithGlory(p, "flag_sun", false)
	T.equal(ok, false)
	T.equal(reason, "NotEnoughGlory")
	T.equal(p.glory, 1199, "nothing was taken")
	T.equal(p.owned.flag_sun, nil)
	p.glory = 1500
	T.expect(Shop.buyWithGlory(p, "flag_sun", false), "bought")
	T.equal(p.glory, 300)
	T.equal(p.owned.flag_sun, true)
	ok, reason = Shop.buyWithGlory(p, "flag_sun", false)
	T.equal(reason, "Owned")
	T.equal(p.glory, 300, "never charged twice")
end)

T.test("Glory can't buy Legendary, VIP-only, free or unknown items", function()
	local p = Progression.newProfile()
	p.glory = 100000
	T.equal(select(2, Shop.buyWithGlory(p, "token_dragon", false)), "NotForGlory")
	T.equal(select(2, Shop.buyWithGlory(p, "flag_vip", false)), "NotForGlory")
	T.equal(select(2, Shop.buyWithGlory(p, "flag_banner", false)), "NotForGlory")
	T.equal(select(2, Shop.buyWithGlory(p, "gold", false)), "UnknownItem")
	T.equal(p.glory, 100000)
end)

T.test("Robux purchases: items not owned, offers once, VIP once", function()
	local p = Progression.newProfile()
	T.expect(Shop.canBuyRobux(p, "flag_comet", false), "an Epic flag")
	T.equal(select(2, Shop.canBuyRobux(p, "flag_vip", false)), "NotForRobux")
	T.equal(select(2, Shop.canBuyRobux(p, "flag_banner", false)), "NotForRobux")
	T.equal(select(2, Shop.canBuyRobux(p, "nope", false)), "UnknownItem")
	T.expect(Shop.canBuyRobux(p, "vip", false), "VIP")
	T.equal(select(2, Shop.canBuyRobux(p, "vip", true)), "Owned")
	T.expect(Shop.canBuyRobux(p, "starter", false), "the starter pack")
	Shop.grant(p, "starter")
	T.equal(select(2, Shop.canBuyRobux(p, "starter", false)), "Owned", "once per account")
	for _, id in assert(Catalogue.offer("starter")).items do
		T.equal(p.owned[id], true, "the pack granted " .. id)
	end
end)

T.test("an offer whose pieces you all own counts as owned", function()
	local p = Progression.newProfile()
	p.owned.flag_crown, p.owned.border_runes = true, true
	T.expect(Shop.canBuyRobux(p, "set_royal", false), "one piece missing")
	p.owned.token_shield = true
	T.equal(select(2, Shop.canBuyRobux(p, "set_royal", false)), "Owned")
end)

T.test("granting the VIP pass records it but grants no items itself", function()
	local p = Progression.newProfile()
	Shop.grant(p, "vip")
	T.equal(p.owned.vip, true)
	T.equal(p.owned.flag_vip, nil, "VIP items come with the pass status, not the profile")
end)

T.test("equipping needs ownership; VIP items need VIP", function()
	local p = Progression.newProfile()
	T.equal(select(2, Shop.equip(p, "flag_sun", false)), "NotOwned")
	T.expect(Shop.equip(p, "flag_banner", false), "defaults are owned by everyone")
	p.owned.flag_sun = true
	T.expect(Shop.equip(p, "flag_sun", false), "equipped")
	T.equal(p.equipped.Flag, "flag_sun")
	T.equal(select(2, Shop.equip(p, "flag_vip", false)), "NotOwned")
	T.expect(Shop.equip(p, "flag_vip", true), "with VIP")
	T.equal(select(2, Shop.equip(p, "emote_wave", true)), "CantEquip")
	p.owned.fx_meteor_ice = true
	T.expect(Shop.equip(p, "fx_meteor_ice", false), "a power effect")
	T.equal(p.equipped.PowerFxMeteor, "fx_meteor_ice")
end)

T.test("a nation shows its owner's equipped cosmetics, defaults otherwise", function()
	local p = Progression.newProfile()
	local c = Shop.cosmeticsOf(p, false, 3)
	T.equal(c.nation, 3)
	T.equal(c.flag, "flag_banner")
	T.equal(c.border, "border_solid")
	T.equal(c.token, "token_square")
	T.equal(c.frame, "frame_none")
	T.equal(c.vip, false)
	p.owned.flag_cross, p.owned.border_dashes, p.owned.token_shield = true, true, true
	p.owned.fx_meteor_ice = true
	p.equipped.Flag, p.equipped.Border, p.equipped.Token = "flag_cross", "border_dashes", "token_shield"
	p.equipped.PowerFxMeteor = "fx_meteor_ice"
	c = Shop.cosmeticsOf(p, false, 3)
	T.equal(c.flag, "flag_cross")
	T.equal(c.border, "border_dashes")
	T.equal(c.token, "token_shield")
	T.equal(c.powerFx.Meteor, "fx_meteor_ice")
	T.equal(c.powerFx.Plague, nil)
end)

T.test("VIP shows the gold frame; a lost VIP item falls back to the default", function()
	local p = Progression.newProfile()
	T.equal(Shop.cosmeticsOf(p, true, 1).frame, "frame_gold")
	T.equal(Shop.cosmeticsOf(p, true, 1).vip, true)
	p.equipped.Flag = "flag_vip"
	T.equal(Shop.cosmeticsOf(p, true, 1).flag, "flag_vip")
	T.equal(Shop.cosmeticsOf(p, false, 1).flag, "flag_banner", "the pass is gone")
	p.equipped.Flag = "flag_nonexistent"
	T.equal(Shop.cosmeticsOf(p, false, 1).flag, "flag_banner", "an unknown id")
	p.equipped.Flag = "border_dashes"
	p.owned.border_dashes = true
	T.equal(Shop.cosmeticsOf(p, false, 1).flag, "flag_banner", "an item of another slot")
end)

T.test("every nation gets cosmetics: players their own, bots the defaults", function()
	local state = Match.new(Maps.get("skyshards"))
	local nation = assert(Match.seatPlayer(state, 501))
	local p = Progression.newProfile()
	p.owned.flag_sun = true
	p.equipped.Flag = "flag_sun"
	local list = Shop.nationCosmetics(state, { [501] = Shop.cosmeticsOf(p, false, 0) })
	local count = 0
	for _ in state.nations do
		count += 1
	end
	T.equal(#list, count)
	for i, c in list do
		if i > 1 then
			T.expect(c.nation > list[i - 1].nation, "sorted by nation id")
		end
		T.equal(c.flag, if c.nation == nation then "flag_sun" else "flag_banner")
	end
end)

T.test("cosmetics travel in the snapshot and only change the delta when they change", function()
	local state = Match.new(Maps.get("skyshards"))
	Match.seatPlayer(state, 501)
	local p = Progression.newProfile()
	local before = Snapshot.full(state, Shop.nationCosmetics(state, { [501] = Shop.cosmeticsOf(p, false, 0) }))
	T.expect(#before.cosmetics > 0, "the snapshot carries cosmetics")
	local same = Snapshot.full(state, Shop.nationCosmetics(state, { [501] = Shop.cosmeticsOf(p, false, 0) }))
	T.equal(Snapshot.diff(before, same), nil, "nothing changed")
	p.owned.border_runes = true
	p.equipped.Border = "border_runes"
	local after = Snapshot.full(state, Shop.nationCosmetics(state, { [501] = Shop.cosmeticsOf(p, false, 0) }))
	local delta = assert(Snapshot.diff(before, after))
	T.expect(delta.cosmetics ~= nil, "the delta carries the new cosmetics")
	Snapshot.apply(before, delta)
	T.equal(before.cosmetics[1].border, "border_runes")
	T.equal(#Snapshot.full(state).cosmetics, 0, "no cosmetics given: an empty list")
end)

T.test("map themes: equipped like any cosmetic; the classic look by default; the opt-out is saved", function()
	local p = Progression.newProfile()
	T.equal(Shop.themeOf(p, false), "theme_classic")
	T.equal(select(2, Shop.equip(p, "theme_night", false)), "NotOwned")
	T.expect(Shop.buyWithGlory(p, "theme_night", false) == false, "not enough Glory")
	p.glory = S.GloryPrice.Rare
	T.expect(Shop.buyWithGlory(p, "theme_night", false), "a Rare theme for Glory")
	T.expect(Shop.equip(p, "theme_night", false), "equipped")
	T.equal(p.equipped.Theme, "theme_night")
	T.equal(Shop.themeOf(p, false), "theme_night")
	T.equal(Shop.view(p, false, false, false, false).defaultTheme, false)
	Shop.setDefaultTheme(p, true)
	T.equal(p.settings.defaultTheme, true)
	T.equal(Shop.view(p, false, false, false, false).defaultTheme, true)
	Shop.setDefaultTheme(p, false)
	T.equal(p.settings.defaultTheme, nil)
end)

T.test("the match's theme travels in the snapshot", function()
	local state = Match.new(Maps.get("earth"))
	T.equal(Snapshot.full(state).theme, "", "classic")
	state.theme = "theme_winter"
	T.equal(Snapshot.full(state).theme, "theme_winter")
end)

T.test("emotes: owned only, one per cooldown", function()
	local p = Progression.newProfile()
	T.equal(select(2, Shop.canEmote(p, "emote_wave", false, nil, 100)), "NotOwned")
	T.equal(select(2, Shop.canEmote(p, "flag_sun", false, nil, 100)), "UnknownItem")
	p.owned.emote_wave = true
	T.expect(Shop.canEmote(p, "emote_wave", false, nil, 100), "first emote")
	T.equal(select(2, Shop.canEmote(p, "emote_wave", false, 100, 100 + S.EmoteCooldownTicks - 1)), "TooFast")
	T.expect(Shop.canEmote(p, "emote_wave", false, 100, 100 + S.EmoteCooldownTicks), "after the cooldown")
end)

T.test("the starter pack is offered from the 2nd match, once per session, until bought", function()
	local p = Progression.newProfile()
	p.stats.matches = S.StarterPackAfterMatches - 1
	T.equal(Shop.shouldOfferStarter(p, false), false, "never before the 2nd match")
	p.stats.matches = S.StarterPackAfterMatches
	T.equal(Shop.shouldOfferStarter(p, false), true)
	T.equal(Shop.shouldOfferStarter(p, true), false, "once per session")
	Shop.grant(p, "starter")
	T.equal(Shop.shouldOfferStarter(p, false), false, "not after buying")
end)

T.test("Robux purchases open only outside a match", function()
	T.expect(Shop.robuxOpen("Lobby"), "lobby")
	T.expect(Shop.robuxOpen("Pick"), "draft")
	T.expect(Shop.robuxOpen("Results"), "results")
	T.equal(Shop.robuxOpen("Peace"), false)
	T.equal(Shop.robuxOpen("War"), false)
	T.equal(Shop.robuxOpen("Cataclysm"), false)
end)

T.test("the shop view lists owned items and the newest purchases first", function()
	local p = Progression.newProfile()
	p.owned.flag_sun = true
	p.owned.emote_wave = true
	for i = 1, S.HistoryShown + 5 do
		table.insert(p.purchaseHistory, { product = 0, robux = 49, at = i, item = "flag_cross" })
	end
	local view = Shop.view(p, true, false, false, true)
	T.equal(#view.owned, 2)
	T.equal(view.owned[1], "emote_wave", "sorted")
	T.equal(#view.history, S.HistoryShown)
	T.equal(view.history[1].at, S.HistoryShown + 5, "newest first")
	T.equal(view.vip, true)
	T.equal(view.testMode, true)
end)

T.test("product ids: unset ids never match a receipt", function()
	T.equal(Catalogue.byProductId(0), nil)
	T.equal(Catalogue.productId("flag_sun"), Catalogue.PRODUCT_IDS.flag_sun)
	T.equal(Catalogue.productId("vip"), Catalogue.VIP_PASS_ID)
	T.equal(Catalogue.productId("flag_banner"), 0, "free items have no product")
end)

T.finish()
