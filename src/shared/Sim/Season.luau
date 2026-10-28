--!strict
-- The season pass (docs/MONETIZATION.md 6): 8-week seasons with 50 tiers, a free and a premium track. Season XP is
-- the account XP earned during the season (Sim.Progression.addXp adds it to profile.season); the tier comes from it.
-- Rewards are claimed one by one or all at once; the premium track needs the pass. Buying the pass late opens every
-- premium reward up to your tier at once; the pass bundle adds Config.Season.BundleTiers tiers, once. No single tier
-- skips. When a season ends, whatever you earned and didn't claim is granted the next time you play.
-- Pure: SeasonService passes in the profile and the season the UTC day falls in (Season.current).

local Catalogue = require("../Catalogue")
local Config = require("../Config")
local Types = require("../Types")

type Profile = Types.PlayerProfile
type State = Types.SeasonState
type Def = Types.SeasonDef
type Reward = Types.SeasonReward
type Track = Types.SeasonTrack

local C = Config.Season

local Season = {}

Season.TRACKS = { "Free", "Premium" } :: { Track }

-- Config.Season.Rewards rows -> reward lists (a number is Glory, "title:"/"badge:" a title or badge, else an item id).
local function parseOne(v: any): Reward
	if type(v) == "number" then
		return { glory = v }
	end
	local s = v :: string
	if string.sub(s, 1, 6) == "title:" then
		return { title = string.sub(s, 7) }
	elseif string.sub(s, 1, 6) == "badge:" then
		return { badge = string.sub(s, 7) }
	end
	return { item = s }
end

local function parse(v: any): { Reward }
	if v == false or v == nil then
		return {}
	elseif type(v) == "table" then
		local out = {}
		for _, one in v do
			table.insert(out, parseOne(one))
		end
		return out
	end
	return { parseOne(v) }
end

local defs: { Def } = {}
local byId: { [string]: Def } = {}
for _, s in C.Seasons do
	local tiers: { Types.SeasonTier } = {}
	for _, row in (Config.Season.Rewards :: any)[s.id] or {} do
		table.insert(tiers, { free = parse(row[1]), premium = parse(row[2]) })
	end
	local def: Def = { id = s.id, name = s.name, startDay = s.startDay, endDay = s.endDay, tiers = tiers }
	table.insert(defs, def)
	byId[def.id] = def
end

Season.DEFS = defs

function Season.def(id: string): Def?
	return byId[id]
end

-- The season running on a UTC day, or nil between seasons.
function Season.current(day: number): Def?
	for _, def in defs do
		if day >= def.startDay and day < def.endDay then
			return def
		end
	end
	return nil
end

-- The first season starting after `day` (for "next season soon"), or nil.
function Season.nextAfter(day: number): Def?
	local best: Def? = nil
	for _, def in defs do
		if def.startDay > day and (best == nil or def.startDay < best.startDay) then
			best = def
		end
	end
	return best
end

function Season.newState(id: string): State
	return { id = id, xp = 0, premium = false, bundle = false, claimed = {}, bonus = 0 }
end

-- Season XP with the bundle's tiers.
function Season.effectiveXp(state: State): number
	return state.xp + (if state.bundle then C.BundleTiers * C.XpPerTier else 0)
end

-- The tier a season XP total reaches: tier 1 at 0 XP, one more every Config.Season.XpPerTier, up to the last.
function Season.tierFor(seasonXp: number): number
	return math.clamp(1 + seasonXp // C.XpPerTier, 1, C.Tiers)
end

function Season.tierOf(state: State): number
	return Season.tierFor(Season.effectiveXp(state))
end

-- Bonus rewards earned past the last tier: one per Config.Season.BonusXp once the last tier's bar is full.
function Season.bonusEarned(state: State): number
	return math.max(0, (Season.effectiveXp(state) - C.Tiers * C.XpPerTier) // C.BonusXp)
end

-- "F12" / "P12": the claimed-reward key of a tier on a track.
function Season.key(tier: number, track: Track): string
	return (if track == "Free" then "F" else "P") .. tier
end

-- A tier's rewards on one track ({} for nothing or an unknown tier).
function Season.rewards(def: Def, tier: number, track: Track): { Reward }
	local t = def.tiers[tier]
	if t == nil then
		return {}
	end
	return if track == "Free" then t.free else t.premium
end

-- May this reward be claimed now? (NoSeason, Unknown, TierLocked, NeedPass, Claimed)
function Season.canClaim(state: State, def: Def?, tier: number, track: Track): (boolean, string?)
	if def == nil or state.id ~= def.id then
		return false, "NoSeason"
	end
	if #Season.rewards(def, tier, track) == 0 then
		return false, "Unknown"
	end
	if tier > Season.tierOf(state) then
		return false, "TierLocked"
	end
	if track == "Premium" and not state.premium then
		return false, "NeedPass"
	end
	if state.claimed[Season.key(tier, track)] then
		return false, "Claimed"
	end
	return true, nil
end

-- Every reward claimable now, as { tier, track } in tier order (free before premium).
function Season.claimable(state: State, def: Def?): { { tier: number, track: Track } }
	local out = {}
	if def == nil then
		return out
	end
	for tier = 1, math.min(Season.tierOf(state), #def.tiers) do
		for _, track in Season.TRACKS do
			if Season.canClaim(state, def, tier, track) then
				table.insert(out, { tier = tier, track = track })
			end
		end
	end
	return out
end

-- Give one reward. Items, titles and badges go in profile.owned (titles as "title:…" and as the wearable title
-- item of that name, badges as "badge:…"); an item already owned stays owned. Returns the Glory it paid.
function Season.grant(profile: Profile, reward: Reward): number
	if reward.item then
		profile.owned[reward.item] = true
	end
	if reward.title then
		profile.owned["title:" .. reward.title] = true
		local wearable = Catalogue.titleNamed(reward.title) -- worn from the 🏆 screen like an achievement's
		if wearable then
			profile.owned[wearable] = true
		end
	end
	if reward.badge then
		profile.owned["badge:" .. reward.badge] = true
	end
	local glory = reward.glory or 0
	profile.glory += glory
	return glory
end

-- Claim one tier's reward on one track. Returns ok (or false and a reason, see canClaim) and the Glory it paid.
function Season.claim(profile: Profile, def: Def?, tier: number, track: Track): (boolean, string?, number)
	local state = profile.season
	local ok, reason = Season.canClaim(state, def, tier, track)
	if not ok or def == nil then
		return false, reason, 0
	end
	state.claimed[Season.key(tier, track)] = true
	local glory = 0
	for _, reward in Season.rewards(def, tier, track) do
		glory += Season.grant(profile, reward)
	end
	return true, nil, glory
end

-- Pay the bonus rewards past the last tier not paid yet. Returns the Glory.
function Season.claimBonus(profile: Profile): number
	local state = profile.season
	local due = Season.bonusEarned(state) - state.bonus
	if due <= 0 then
		return 0
	end
	state.bonus += due
	local glory = due * C.BonusGlory
	profile.glory += glory
	return glory
end

-- Claim everything claimable now, bonus rewards included. Returns how many rewards and the Glory they paid.
function Season.claimAll(profile: Profile, def: Def?): (number, number)
	local count, glory = 0, 0
	for _, c in Season.claimable(profile.season, def) do
		local ok, _, g = Season.claim(profile, def, c.tier, c.track)
		if ok then
			count += 1
			glory += g
		end
	end
	if def and profile.season.id == def.id then
		local bonus = Season.bonusEarned(profile.season) - profile.season.bonus
		if bonus > 0 then
			count += bonus
			glory += Season.claimBonus(profile)
		end
	end
	return count, glory
end

-- Does the profile's season state need Season.sync (another season, or fields missing from an older save)?
function Season.needsSync(profile: Profile, def: Def?): boolean
	local state = profile.season :: any
	if state == nil or state.bundle == nil or state.bonus == nil or state.claimed == nil then
		return true
	end
	return state.id ~= (if def then def.id else "")
end

-- Move the profile to the season running now (nil between seasons). The season it leaves grants what was earned and
-- not claimed first. Returns true if the season changed (and the rewards and Glory that finishing it paid).
function Season.sync(profile: Profile, def: Def?): (boolean, number, number)
	local state = profile.season :: any
	if state == nil then
		profile.season = Season.newState(if def then def.id else "")
		return true, 0, 0
	end
	-- an older save: fill in what it lacks
	state.xp = state.xp or 0
	state.premium = state.premium == true
	state.bundle = state.bundle == true
	state.claimed = state.claimed or {}
	state.bonus = state.bonus or 0
	local id = if def then def.id else ""
	if state.id == id then
		return false, 0, 0
	end
	local count, glory = Season.claimAll(profile, Season.def(state.id))
	profile.season = Season.newState(id)
	return true, count, glory
end

-- May the player buy the pass (or the bundle) now? (NoSeason, Owned: one pass per season, so the bundle's tiers come
-- once and there are no tier skips to buy.)
function Season.canBuyPass(profile: Profile, def: Def?): (boolean, string?)
	if def == nil or profile.season.id ~= def.id then
		return false, "NoSeason"
	end
	if profile.season.premium then
		return false, "Owned"
	end
	return true, nil
end

-- A pass purchase went through (ProcessReceipt): premium for the profile's season, and the bundle's tiers once.
-- Every premium reward up to the tier reached is claimable at once.
function Season.buyPass(profile: Profile, bundle: boolean)
	local state = profile.season
	state.premium = true
	if bundle then
		state.bundle = true
	end
end

-- What the player's client sees. `def` = the season running today (nil between seasons).
function Season.view(profile: Profile, def: Def?, today: number): Types.SeasonView
	local state = profile.season
	if def == nil or state.id ~= def.id then
		local nextDef = Season.nextAfter(today)
		return {
			id = "",
			name = "",
			daysLeft = 0,
			xp = 0,
			tier = 0,
			maxTier = C.Tiers,
			xpIntoTier = 0,
			xpForTier = C.XpPerTier,
			premium = false,
			bundle = false,
			claimed = {},
			ready = 0,
			bonusReady = 0,
			nextStartDay = if nextDef then nextDef.startDay else nil,
		}
	end
	local xp = Season.effectiveXp(state)
	local tier = Season.tierOf(state)
	local into, need
	if xp >= C.Tiers * C.XpPerTier then
		into, need = (xp - C.Tiers * C.XpPerTier) % C.BonusXp, C.BonusXp
	else
		into, need = xp - (tier - 1) * C.XpPerTier, C.XpPerTier -- the last tier's bar fills up to the bonus rewards
	end
	local claimed = {}
	for key, yes in state.claimed do
		if yes then
			table.insert(claimed, key)
		end
	end
	table.sort(claimed)
	local bonusReady = Season.bonusEarned(state) - state.bonus
	return {
		id = def.id,
		name = def.name,
		daysLeft = math.max(0, def.endDay - 1 - today),
		xp = xp,
		tier = tier,
		maxTier = #def.tiers,
		xpIntoTier = into,
		xpForTier = need,
		premium = state.premium,
		bundle = state.bundle,
		claimed = claimed,
		ready = #Season.claimable(state, def) + bonusReady,
		bonusReady = bonusReady,
		nextStartDay = nil,
	}
end

return Season
