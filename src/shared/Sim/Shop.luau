--!strict
-- Shop rules (docs/MONETIZATION.md 3, 4, 10): what a player owns, Glory purchases, which Robux purchases are
-- allowed, what a purchase grants, equipping, the cosmetics each nation shows, emote cooldowns and the starter-pack
-- offer. Pure: ShopService passes in the profile, whether the player has VIP and the match tick.
-- Nothing here changes a match: cosmetics only pick looks, inside the nation's own colour.

local Catalogue = require("../Catalogue")
local Config = require("../Config")
local Login = require("./Login")
local Types = require("../Types")

type Profile = Types.PlayerProfile
type Item = Types.CatalogueItem
type Cosmetics = Types.NationCosmetics

local S = Config.Shop

local Shop = {}

-- Equipped is keyed by slot, except Primordial-power effects: one per power ("PowerFxMeteor").
function Shop.equipKey(item: Item): string
	if item.slot == "PowerFx" then
		return "PowerFx" .. (item.power or "")
	end
	return item.slot
end

-- Does the player own this item or offer? Defaults are free, VIP items come with the pass.
function Shop.owns(profile: Profile, id: string, vip: boolean): boolean
	if id == "vip" then
		return vip
	end
	local item = Catalogue.item(id)
	if item then
		return item.free == true or profile.owned[id] == true or (item.vipOnly == true and vip)
	end
	local offer = Catalogue.offer(id)
	if offer then
		if profile.owned[id] then
			return true
		end
		-- an offer whose every piece you already have counts as owned (nobody pays twice for the same items)
		for _, itemId in offer.items do
			if not Shop.owns(profile, itemId, vip) then
				return false
			end
		end
		return true
	end
	return false
end

-- Buy an item with Glory. Returns ok, or false and a reason: UnknownItem, NotForGlory, Owned, NotEnoughGlory.
function Shop.buyWithGlory(profile: Profile, id: string, vip: boolean): (boolean, string?)
	local item = Catalogue.item(id)
	if item == nil then
		return false, "UnknownItem"
	end
	local price = item.glory
	if price == nil then
		return false, "NotForGlory"
	end
	if Shop.owns(profile, id, vip) then
		return false, "Owned"
	end
	if profile.glory < price then
		return false, "NotEnoughGlory"
	end
	profile.glory -= price
	profile.owned[id] = true
	return true, nil
end

-- May the player start a Robux purchase of this item or offer? (UnknownItem, NotForRobux, Owned)
function Shop.canBuyRobux(profile: Profile, id: string, vip: boolean): (boolean, string?)
	local item = Catalogue.item(id)
	local offer = Catalogue.offer(id)
	if item == nil and offer == nil then
		return false, "UnknownItem"
	end
	if item and item.robux == nil then
		return false, "NotForRobux"
	end
	if Shop.owns(profile, id, vip) then
		return false, "Owned"
	end
	return true, nil
end

-- What a finished Robux purchase grants: the item, or every item of the offer (and the offer itself, so a
-- once-per-account offer can't be bought twice). The VIP pass is Roblox's to track; in test mode it is stored here.
function Shop.grant(profile: Profile, id: string)
	local offer = Catalogue.offer(id)
	if offer then
		profile.owned[id] = true
		if offer.kind == "Product" then
			for _, itemId in offer.items do
				profile.owned[itemId] = true
			end
		end
	elseif Catalogue.item(id) then
		profile.owned[id] = true
	end
end

-- Put an owned item in its slot. (UnknownItem, NotOwned, CantEquip)
function Shop.equip(profile: Profile, id: string, vip: boolean): (boolean, string?)
	local item = Catalogue.item(id)
	if item == nil then
		return false, "UnknownItem"
	end
	if item.slot == "Emote" then
		return false, "CantEquip" -- emotes are used, not worn
	end
	if not Shop.owns(profile, id, vip) then
		return false, "NotOwned"
	end
	profile.equipped[Shop.equipKey(item)] = id
	return true, nil
end

-- The item in an equip key, falling back to the default when nothing (or something no longer owned, such as a VIP
-- item after the pass is gone) is equipped. nil for an empty power-effect key.
function Shop.equippedIn(profile: Profile, key: string, vip: boolean): string?
	local id = profile.equipped[key]
	local item = if id then Catalogue.item(id) else nil
	if id and item and Shop.equipKey(item) == key and Shop.owns(profile, id, vip) then
		return id
	end
	if key == "Frame" and vip then
		return "frame_gold" -- the VIP pass alone already shows the gold frame
	end
	return Catalogue.DEFAULTS[key]
end

-- The defaults every bot shows.
function Shop.defaultCosmetics(nationId: number): Cosmetics
	local d = Catalogue.DEFAULTS
	return {
		nation = nationId,
		flag = d.Flag,
		border = d.Border,
		shades = d.Shades,
		token = d.Token,
		frame = d.Frame,
		victory = d.Victory,
		powerFx = {},
		vip = false,
	}
end

-- What one player's nation shows.
function Shop.cosmeticsOf(profile: Profile, vip: boolean, nationId: number): Cosmetics
	local c = Shop.defaultCosmetics(nationId)
	c.flag = Shop.equippedIn(profile, "Flag", vip) or c.flag
	c.border = Shop.equippedIn(profile, "Border", vip) or c.border
	c.shades = Shop.equippedIn(profile, "Shades", vip) or c.shades
	c.token = Shop.equippedIn(profile, "Token", vip) or c.token
	c.frame = Shop.equippedIn(profile, "Frame", vip) or c.frame
	c.victory = Shop.equippedIn(profile, "Victory", vip) or c.victory
	for _, item in Catalogue.ofSlot("PowerFx") do
		local key = Shop.equipKey(item)
		local id = Shop.equippedIn(profile, key, vip)
		if id and item.power then
			c.powerFx[item.power] = id
		end
	end
	c.vip = vip
	c.flame = Login.flameTier(profile.login) -- play-streak flame (earned for good, MONETIZATION 5.6)
	return c
end

-- Every nation's cosmetics, by nation id order: a player's own (byUser, keyed by userId) or the defaults.
function Shop.nationCosmetics(state: Types.MatchState, byUser: { [number]: Cosmetics }): { Cosmetics }
	local ids = {}
	for id in state.nations do
		table.insert(ids, id)
	end
	table.sort(ids)
	local out = {}
	for _, id in ids do
		local nation = state.nations[id]
		local mine = if nation.userId then byUser[nation.userId] else nil
		if mine then
			local c = table.clone(mine)
			c.nation = id
			c.powerFx = table.clone(mine.powerFx)
			table.insert(out, c)
		else
			table.insert(out, Shop.defaultCosmetics(id))
		end
	end
	return out
end

-- Capital emotes: owned only, and one per Config.Shop.EmoteCooldownTicks. lastTick = the tick of the player's
-- previous emote (nil = none this match).
function Shop.canEmote(profile: Profile, id: string, vip: boolean, lastTick: number?, tick: number): (boolean, string?)
	local item = Catalogue.item(id)
	if item == nil or item.slot ~= "Emote" then
		return false, "UnknownItem"
	end
	if not Shop.owns(profile, id, vip) then
		return false, "NotOwned"
	end
	if lastTick and tick - lastTick < S.EmoteCooldownTicks then
		return false, "TooFast"
	end
	return true, nil
end

-- The real sum of an offer's pieces at their current list prices (never a made-up "was" price).
function Shop.bundleValue(offerId: string): number
	local offer = Catalogue.offer(offerId)
	local sum = 0
	if offer then
		for _, id in offer.items do
			local item = Catalogue.item(id)
			sum += if item and item.robux then item.robux else 0
		end
	end
	return sum
end

-- The starter-pack pop-up: from the 2nd finished match, until bought, at most once per session (the service
-- remembers whether it was shown and never asks during a match).
function Shop.shouldOfferStarter(profile: Profile, shownThisSession: boolean): boolean
	return not shownThisSession and not profile.owned.starter and profile.stats.matches >= S.StarterPackAfterMatches
end

-- The player's own shop state, for the Shop remote.
function Shop.view(
	profile: Profile,
	vip: boolean,
	robuxOpen: boolean,
	starterOffer: boolean,
	testMode: boolean
): Types.ShopView
	local owned = {}
	for id, yes in profile.owned do
		if yes then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	local history = {}
	for i = #profile.purchaseHistory, math.max(1, #profile.purchaseHistory - S.HistoryShown + 1), -1 do
		table.insert(history, table.clone(profile.purchaseHistory[i]))
	end
	return {
		owned = owned,
		equipped = table.clone(profile.equipped),
		vip = vip,
		history = history,
		robuxOpen = robuxOpen,
		starterOffer = starterOffer,
		testMode = testMode,
	}
end

-- Robux purchases (prompts) only outside a match: in the Lobby, the draft and on the Results screen.
function Shop.robuxOpen(phase: string): boolean
	return phase == "Lobby" or phase == "Pick" or phase == "Results"
end

return Shop
