--!strict
-- The shop catalogue (docs/MONETIZATION.md 3.2, 3.3, 3.5): every cosmetic, its slot, rarity and look, the offers
-- (VIP pass, starter pack, nation skin sets) and, in one place, the Roblox developer product and game pass ids.
-- Prices come from Config.Shop by rarity, so a balance change never touches this file. Pure data: no Roblox APIs.
--
-- PRODUCT IDS: every id below is 0 until the owner creates the product on the Creator Dashboard (see
-- docs/MONETIZATION.md "Shop setup"). While an id is 0, Studio grants that purchase free (test mode) and a live
-- server refuses it, so nothing can be bought for nothing in a published game.

local Config = require("./Config")
local Types = require("./Types")

type Item = Types.CatalogueItem
type Offer = Types.ShopOffer

local S = Config.Shop

local Catalogue = {}

-- Developer products (one per Robux item and per product offer) and the VIP game pass. 0 = not created yet.
Catalogue.PRODUCT_IDS = {
	flag_tricolour = 0,
	flag_cross = 0,
	flag_sun = 0,
	flag_crown = 0,
	flag_vanguard = 0,
	flag_comet = 0,
	border_dashes = 0,
	border_runes = 0,
	border_embers = 0,
	shades_dawn = 0,
	shades_dusk = 0,
	shades_royal = 0,
	token_shield = 0,
	token_vanguard = 0,
	token_tower = 0,
	token_dragon = 0,
	emote_charge = 0,
	emote_wave = 0,
	emote_gg = 0,
	emote_laugh = 0,
	emote_fire = 0,
	emote_crown = 0,
	victory_fireworks = 0,
	victory_dragon = 0,
	frame_bronze = 0,
	frame_silver = 0,
	fx_meteor_ice = 0,
	fx_plague_violet = 0,
	fx_blessing_rays = 0,
	fx_meteor_comet = 0,
	theme_night = 0,
	theme_winter = 0,
	theme_autumn = 0,
	starter = 0,
	set_royal = 0,
	set_siege = 0,
	season_pass = 0, -- the season's premium pass (Config.Season.PassRobux), sold through SeasonService
	season_bundle = 0, -- the pass + Config.Season.BundleTiers tiers (Config.Season.BundleRobux)
} :: { [string]: number }

Catalogue.VIP_PASS_ID = 0

-- The equip slots shown in the shop, in tab order.
Catalogue.SLOTS =
	{ "Flag", "Border", "Shades", "Token", "Emote", "Victory", "Frame", "PowerFx", "Theme" } :: { Types.CosmeticSlot }

-- What every nation starts with (and what bots always show).
Catalogue.DEFAULTS = {
	Flag = "flag_banner",
	Border = "border_solid",
	Shades = "shades_default",
	Token = "token_square",
	Frame = "frame_none",
	Victory = "victory_trophy",
	Theme = "theme_classic",
} :: { [string]: string }

local items: { Item } = {}
local byId: { [string]: Item } = {}

-- A cosmetic priced by its rarity: Glory for Common, Rare and Epic; Robux for all of them.
local function add(id: string, slot: Types.CosmeticSlot, rarity: Types.Rarity, name: string, art: string, extra: any?)
	local item: Item = {
		id = id,
		slot = slot,
		rarity = rarity,
		name = name,
		art = art,
		glory = (S.GloryPrice :: any)[rarity],
		robux = (S.RobuxPrice :: any)[rarity],
	}
	for k, v in extra or {} do
		(item :: any)[k] = v
	end
	if item.free or item.vipOnly or item.season then
		item.glory, item.robux = nil, nil -- defaults, VIP items and season-pass rewards are never sold
	end
	table.insert(items, item)
	byId[id] = item
end

local FREE = { free = true }
local VIP = { vipOnly = true }
local ANIMATED = { animated = true }

local function emote(id: string, name: string, icon: string, animated: boolean, season: string?)
	local kind = if animated then "Animated" else "Static"
	add(id, "Emote", if animated then "Rare" else "Common", name, icon, {
		animated = animated,
		glory = (S.EmoteGlory :: any)[kind],
		robux = (S.EmoteRobux :: any)[kind],
		season = season,
	})
end

-- Flags: the 16×12 pixel flag on your capital, in the nations list and on Results (CosmeticArt.FLAGS).
add("flag_banner", "Flag", "Common", "Banner", "banner", FREE)
add("flag_tricolour", "Flag", "Common", "Tricolour", "tricolour")
add("flag_cross", "Flag", "Common", "Northern Cross", "cross")
add("flag_sun", "Flag", "Rare", "Rising Sun", "sun")
add("flag_crown", "Flag", "Rare", "Crown", "crown")
add("flag_vanguard", "Flag", "Rare", "Vanguard", "vanguard")
add("flag_comet", "Flag", "Epic", "Comet", "comet", ANIMATED)
add("flag_vip", "Flag", "Rare", "VIP Standard", "vip", VIP)

-- Border styles: the pattern of your nation border, always in shades of your border colour.
add("border_solid", "Border", "Common", "Solid", "solid", FREE)
add("border_dashes", "Border", "Rare", "Dashes", "dashes")
add("border_runes", "Border", "Rare", "Runes", "runes")
add("border_embers", "Border", "Epic", "Embers", "embers")
add("border_vip", "Border", "Rare", "Laurel", "laurel", VIP)

-- Shade sets: three shades of your own colour for the wash over your provinces. Never another hue.
add("shades_default", "Shades", "Common", "Classic", "default", FREE)
add("shades_dawn", "Shades", "Common", "Dawn", "dawn")
add("shades_dusk", "Shades", "Common", "Dusk", "dusk")
add("shades_royal", "Shades", "Rare", "Royal", "royal")

-- Army tokens: the sprite of your armies on the map.
add("token_square", "Token", "Common", "Square", "square", FREE)
add("token_shield", "Token", "Rare", "Shield", "shield")
add("token_vanguard", "Token", "Rare", "Vanguard", "vanguard")
add("token_tower", "Token", "Epic", "Siege Tower", "tower")
add("token_dragon", "Token", "Legendary", "Dragon", "dragon", ANIMATED)
add("token_vip", "Token", "Rare", "VIP Lion", "lion", VIP)

-- Capital emotes: an icon over your capital for a few seconds.
emote("emote_charge", "Charge", "📯", false)
emote("emote_wave", "Wave", "👋", false)
emote("emote_gg", "GG", "🤝", false)
emote("emote_laugh", "Laugh", "😂", false)
emote("emote_fire", "On Fire", "🔥", true)
emote("emote_crown", "Crowned", "👑", true)

-- Victory animations: over the winner's capital on the Results screen (frames separated by spaces).
add("victory_trophy", "Victory", "Common", "Trophy", "🏆", FREE)
add("victory_fireworks", "Victory", "Epic", "Fireworks", "🎆 ✨ 🎇", ANIMATED)
add("victory_dragon", "Victory", "Legendary", "Dragon's Roar", "🐉 🔥 🐉", ANIMATED)

-- Nameplate frames: around your name in the nations list.
add("frame_none", "Frame", "Common", "Plain", "none", FREE)
add("frame_bronze", "Frame", "Common", "Bronze", "bronze")
add("frame_silver", "Frame", "Rare", "Silver", "silver")
add("frame_gold", "Frame", "Rare", "VIP Gold", "gold", VIP)

-- Primordial-power effects: how one power looks (PowerFx.LOOKS). Same area, timing and sound cue as the default.
-- Common recolours it, Rare gives it a new style, Epic a new style with more animation.
add("fx_meteor_ice", "PowerFx", "Common", "Ice Meteor", "ice", { power = "Meteor" })
add("fx_plague_violet", "PowerFx", "Common", "Violet Plague", "violet", { power = "Plague" })
add("fx_blessing_rays", "PowerFx", "Rare", "Sun Rays", "rays", { power = "Blessing" })
add("fx_meteor_comet", "PowerFx", "Epic", "Comet Strike", "comet", { power = "Meteor", animated = true })

-- Map themes: a re-skin of the terrain on any map (PixelArt.THEMES), e.g. "Night Earth". Nation colours never
-- change. You see yours on the vote cards; everyone sees it when it wins the theme vote (Sim.Lobby.chooseTheme).
add("theme_classic", "Theme", "Common", "Classic", "classic", FREE)
add("theme_night", "Theme", "Rare", "Night", "night")
add("theme_winter", "Theme", "Rare", "Winter", "winter")
add("theme_autumn", "Theme", "Rare", "Autumn", "autumn")

-- Season 1 "Rise of the Primordials" (docs/MONETIZATION.md 6): season-pass rewards, never sold. Their art is drawn by
-- the same painters as the shop's (CosmeticArt grids and frame colours, PowerFx looks, emote and animation icons).
local S1 = { season = "S1" }
local S1_ANIMATED = { season = "S1", animated = true }
local function s1Fx(power: string, animated: boolean?): { [string]: any }
	return { season = "S1", power = power, animated = animated }
end
add("flag_ember_sigil", "Flag", "Common", "Ember Sigil", "ember_sigil", S1)
add("flag_ember_banner", "Flag", "Rare", "Ember Banner", "ember_banner", S1)
add("flag_titan_eye", "Flag", "Rare", "Titan's Eye", "titan_eye", S1)
add("flag_storm_banner", "Flag", "Rare", "Storm Banner", "storm_banner", S1)
add("flag_cracked_crown", "Flag", "Epic", "Cracked Crown", "cracked_crown", S1_ANIMATED)
add("flag_storm_titan", "Flag", "Epic", "Storm Titan", "storm_titan", S1)
add("flag_obsidian_crown", "Flag", "Legendary", "Obsidian Crown", "obsidian_crown", S1)
add("token_ember_knight", "Token", "Epic", "Ember Knight", "ember_knight", S1)
add("token_obsidian", "Token", "Rare", "Obsidian", "obsidian", S1)
add("token_stone_golem", "Token", "Rare", "Stone Golem", "stone_golem", S1)
add("token_phoenix_rider", "Token", "Epic", "Phoenix Rider", "phoenix_rider", S1)
add("token_cinder_golem", "Token", "Epic", "Cinder Golem", "cinder_golem", S1)
add("token_titan", "Token", "Legendary", "Titan", "titan", S1_ANIMATED)
add("frame_ashen", "Frame", "Common", "Ashen", "ashen", S1)
add("frame_molten", "Frame", "Rare", "Molten", "molten", S1)
add("frame_lava_seam", "Frame", "Epic", "Lava Seam", "lava_seam", S1)
add("frame_obsidian", "Frame", "Epic", "Obsidian", "obsidian", S1)
add("frame_primordial_eye", "Frame", "Epic", "Primordial Eye", "primordial_eye", S1)
add("frame_rift", "Frame", "Legendary", "Primordial Rift", "rift", S1)
emote("emote_salute", "Salute", "✊", false, "S1")
emote("emote_volcano_peak", "Volcano Peak", "⛰", false, "S1")
emote("emote_skull", "Skull", "💀", false, "S1")
emote("emote_volcano", "Volcano", "🌋", true, "S1")
emote("emote_crown_toss", "Crown Toss", "🎉", true, "S1")
emote("emote_eruption", "Eruption", "💥", true, "S1")
emote("emote_roar", "Primordial Roar", "🐲", true, "S1")
emote("emote_meteor_shower", "Meteor Shower", "☄", true, "S1")
add("victory_eruption", "Victory", "Epic", "Eruption", "🌋 💥 🔥", S1_ANIMATED)
add("victory_magma", "Victory", "Epic", "Magma Pulse", "🔥 🌋 🔥", S1_ANIMATED)
add("victory_titan", "Victory", "Legendary", "Titan Rising", "🗿 ⚡ 🗿", S1_ANIMATED)
add("fx_meteor_stone", "PowerFx", "Common", "Stone Meteor", "stone", s1Fx("Meteor"))
add("fx_meteor_ember", "PowerFx", "Rare", "Ember Meteor", "ember", s1Fx("Meteor"))
add("fx_meteor_firestorm", "PowerFx", "Rare", "Firestorm Meteor", "firestorm", s1Fx("Meteor"))
add("fx_meteor_lava", "PowerFx", "Epic", "Lava Meteor", "lava", s1Fx("Meteor", true))
add("fx_meteor_phoenix", "PowerFx", "Legendary", "Phoenix Meteor", "phoenix", s1Fx("Meteor", true))
add("fx_plague_ember", "PowerFx", "Common", "Ember Plague", "ember", s1Fx("Plague"))
add("fx_plague_ash", "PowerFx", "Common", "Ashfall Plague", "ash", s1Fx("Plague"))
add("fx_plague_void", "PowerFx", "Common", "Void Plague", "void", s1Fx("Plague"))
add("fx_plague_cinder", "PowerFx", "Common", "Cinder Plague", "cinder", s1Fx("Plague"))
add("fx_blessing_molten", "PowerFx", "Rare", "Molten Blessing", "molten", s1Fx("Blessing"))
add("fx_blessing_ember", "PowerFx", "Rare", "Ember Halo", "ember", s1Fx("Blessing"))
add("fx_blessing_worldsplitter", "PowerFx", "Epic", "Worldsplitter Rays", "worldsplitter", s1Fx("Blessing", true))
add("fx_blessing_starfall", "PowerFx", "Epic", "Starfall Blessing", "starfall", s1Fx("Blessing", true))
add("fx_blessing_sunfire", "PowerFx", "Epic", "Sunfire Blessing", "sunfire", s1Fx("Blessing", true))

Catalogue.ITEMS = items

-- The core range (docs/MONETIZATION.md 3.8): always on sale, so nobody waits for basics. Every other sold item and
-- every bundle rotates through the daily and weekly slots (Sim.ShopRotation).
Catalogue.CORE = {
	"flag_tricolour",
	"flag_sun",
	"flag_comet",
	"border_dashes",
	"shades_dawn",
	"token_shield",
	"emote_charge",
	"emote_wave",
	"victory_fireworks",
	"frame_bronze",
	"fx_meteor_ice",
	"theme_night",
} :: { string }

Catalogue.OFFERS = {
	{
		id = "vip",
		kind = "Pass",
		name = "VIP",
		icon = "👑",
		items = { "flag_vip", "border_vip", "token_vip", "frame_gold" },
		robux = S.VipRobux,
		oncePerAccount = true,
	},
	{
		id = "starter",
		kind = "Product",
		name = "Starter Pack",
		icon = "🎁",
		items = { "flag_vanguard", "token_vanguard", "emote_charge", "emote_wave", "frame_bronze" },
		robux = S.StarterPackRobux,
		oncePerAccount = true,
	},
	{
		id = "set_royal",
		kind = "Product",
		name = "Royal Set",
		icon = "🏰",
		items = { "flag_crown", "border_runes", "token_shield" },
		robux = S.RareSetRobux,
		oncePerAccount = false,
		weekly = true, -- a bundle: on sale in the weeks the rotating shop features it
	},
	{
		id = "set_siege",
		kind = "Product",
		name = "Siege Set",
		icon = "🔥",
		items = { "flag_comet", "border_embers", "token_tower" },
		robux = S.EpicSetRobux,
		oncePerAccount = false,
		weekly = true,
	},
} :: { Offer }

local offerById: { [string]: Offer } = {}
for _, offer in Catalogue.OFFERS do
	offerById[offer.id] = offer
end

function Catalogue.item(id: string): Item?
	return byId[id]
end

function Catalogue.offer(id: string): Offer?
	return offerById[id]
end

-- Items of one slot, in shop order.
function Catalogue.ofSlot(slot: string): { Item }
	local out = {}
	for _, item in items do
		if item.slot == slot then
			table.insert(out, item)
		end
	end
	return out
end

-- The developer product id of an item or product offer (0 = not created yet); the VIP pass id for "vip".
function Catalogue.productId(id: string): number
	if id == "vip" then
		return Catalogue.VIP_PASS_ID
	end
	return Catalogue.PRODUCT_IDS[id] or 0
end

-- Which item or offer a developer product id belongs to (ProcessReceipt). nil for unknown or unset ids.
function Catalogue.byProductId(productId: number): string?
	if productId == 0 then
		return nil
	end
	for id, pid in Catalogue.PRODUCT_IDS do
		if pid == productId then
			return id
		end
	end
	return nil
end

-- Is any product or pass id still 0? Then Studio runs the shop in test mode.
function Catalogue.hasPlaceholders(): boolean
	if Catalogue.VIP_PASS_ID == 0 then
		return true
	end
	for _, pid in Catalogue.PRODUCT_IDS do
		if pid == 0 then
			return true
		end
	end
	return false
end

return Catalogue
