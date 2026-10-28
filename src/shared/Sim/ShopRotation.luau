--!strict
-- The rotating shop (docs/MONETIZATION.md 3.8): 4 daily slots (2 Common, 1 Rare, 1 Epic, new at 00:00 UTC) and 2
-- weekly slots (a Legendary item and a bundle, new on Monday 00:00 UTC), next to the core range
-- (Shared.Catalogue.CORE), which is always on sale. Pure: the schedule depends only on the UTC day, so every server
-- and every player sees the same shop. Never personalised, nothing random per player.
--
-- The schedule: each rarity's pool is shuffled once per cycle by a generator seeded with Config.ShopRotation.Seed,
-- the slot and the cycle number, and the cycle's days take its items in order (k a day). A cycle lasts
-- ceil(pool / k) days, so an item comes back at most 2 cycles - 1 days later and never twice on one day.
-- tests/shoprotation.spec.luau checks the 60-day promise on the real catalogue over a year.

local Catalogue = require("../Catalogue")
local Config = require("../Config")
local Login = require("./Login")
local Rng = require("./Rng")
local Types = require("../Types")

local R = Config.ShopRotation
local SECONDS_PER_DAY = 86400
local DAYS_PER_WEEK = 7

local ShopRotation = {}

export type Pools = {
	Common: { string },
	Rare: { string },
	Epic: { string },
	Legendary: { string },
	Bundle: { string },
}

export type Rotation = { daily: { string }, weekly: { string } }

local SALTS = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Bundle = 5 }

local core: { [string]: boolean } = {}
for _, id in Catalogue.CORE do
	core[id] = true
end

-- The rotating items by rarity and the rotating bundles, in catalogue order: every sold item outside the core range
-- (not the defaults, VIP items or season-pass rewards) and every weekly offer.
function ShopRotation.pools(): Pools
	local pools: Pools = { Common = {}, Rare = {}, Epic = {}, Legendary = {}, Bundle = {} }
	for _, item in Catalogue.ITEMS do
		if item.robux and not core[item.id] then
			table.insert((pools :: any)[item.rarity], item.id)
		end
	end
	for _, offer in Catalogue.OFFERS do
		if offer.weekly then
			table.insert(pools.Bundle, offer.id)
		end
	end
	return pools
end

local POOLS = ShopRotation.pools()
local rotating: { [string]: boolean } = {}
for _, pool in POOLS :: any do
	for _, id in pool :: { string } do
		rotating[id] = true
	end
end

-- 32-bit FNV-1a over the numbers, so neighbouring cycles get unrelated seeds.
local function hash(values: { number }): number
	local h = 2166136261
	for _, v in values do
		local n = math.floor(v) % 4294967296
		for _ = 1, 4 do
			h = bit32.bxor(h, n % 256)
			h = (bit32.lshift(h, 24) + h * 403) % 4294967296
			n = n // 256
		end
	end
	return h
end

-- How many periods (days or weeks) one shuffled pass through a pool lasts.
function ShopRotation.cycleLength(poolSize: number, perPeriod: number): number
	return math.ceil(poolSize / math.max(1, math.min(perPeriod, poolSize)))
end

-- `k` items of `pool` for one period (day or week): the period's place in its cycle's shuffled order.
function ShopRotation.pick(pool: { string }, k: number, period: number, salt: number): { string }
	local n = #pool
	k = math.min(k, n)
	if k <= 0 then
		return {}
	end
	local length = ShopRotation.cycleLength(n, k)
	local cycle, place = period // length, period % length
	local order = table.clone(pool)
	local rng = Rng.new(hash({ R.Seed, salt, cycle }))
	for i = n, 2, -1 do -- Fisher-Yates
		local j = Rng.int(rng, 1, i)
		order[i], order[j] = order[j], order[i]
	end
	local out = {}
	for i = 1, k do
		table.insert(out, order[(place * k + i - 1) % n + 1])
	end
	return out
end

-- The rotating shop on a UTC day: daily item ids (Commons, then the Rare, then the Epic) and the week's Legendary
-- item and bundle. `pools` defaults to the catalogue's.
function ShopRotation.rotation(day: number, pools: Pools?): Rotation
	local p = pools or POOLS
	local daily = {}
	for _, rarity in { "Common", "Rare", "Epic" } do
		for _, id in ShopRotation.pick((p :: any)[rarity], (R.Daily :: any)[rarity], day, SALTS[rarity]) do
			table.insert(daily, id)
		end
	end
	local week = Login.weekOf(day)
	local weekly = ShopRotation.pick(p.Legendary, R.WeeklyLegendary, week, SALTS.Legendary)
	for _, id in ShopRotation.pick(p.Bundle, R.WeeklyBundles, week, SALTS.Bundle) do
		table.insert(weekly, id)
	end
	return { daily = daily, weekly = weekly }
end

-- Does this item or offer rotate (only on sale in its slots)? Core items, the defaults, VIP and season items, the
-- always-on offers (VIP, starter pack) and the season pass don't.
function ShopRotation.rotates(id: string): boolean
	return rotating[id] == true
end

-- Is this item or offer on sale on this day? Everything that doesn't rotate is (the shop rules decide the rest).
function ShopRotation.onSale(id: string, day: number): boolean
	if not rotating[id] then
		return true
	end
	local r = ShopRotation.rotation(day)
	return table.find(r.daily, id) ~= nil or table.find(r.weekly, id) ~= nil
end

-- What the shop shows: today's slots and the seconds until each refresh. secondsIntoDay: seconds since 00:00 UTC.
function ShopRotation.view(day: number, secondsIntoDay: number): Types.RotationView
	local r = ShopRotation.rotation(day)
	local nextWeek = (Login.weekOf(day) + 1) * DAYS_PER_WEEK - 3 -- the next Monday's day number (Login.weekOf)
	local into = math.clamp(secondsIntoDay, 0, SECONDS_PER_DAY - 1)
	return {
		day = day,
		daily = r.daily,
		weekly = r.weekly,
		dailyLeft = SECONDS_PER_DAY - into,
		weeklyLeft = (nextWeek - day) * SECONDS_PER_DAY - into,
	}
end

return ShopRotation
