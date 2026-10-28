# Monetization, progression and retention plan

The business plan for Total World Chaos: what we sell, what players earn by playing, how they progress, what keeps them coming back, what it could earn, and what to build in Phases 4 and 5. Launch, store page, ads, creators and analytics events are in `docs/LAUNCH.md`.

This doc follows `docs/DESIGN.md`. Where it proposes a change to DESIGN.md, the exact text is in the [appendix](#appendix-proposed-designmd-changes). Every number here is a starting value. Earn rates and the level curve go in `Config.luau`; prices go in a catalogue module (see the task cards).

Platform facts were checked against Roblox's Creator Hub and newsroom in October 2026. Sources are at the end. Anything we couldn't verify is marked **unverified**.

## Contents

1. [Principles](#1-principles)
2. [Platform facts that shape the plan](#2-platform-facts-that-shape-the-plan)
3. [Catalogue and prices](#3-catalogue-and-prices)
4. [Currency: Glory](#4-currency-glory)
5. [Progression](#5-progression)
6. [Season pass](#6-season-pass)
7. [Retention and social](#7-retention-and-social)
8. [Live-ops calendar: the first 6 months](#8-live-ops-calendar-the-first-6-months)
9. [Revenue model](#9-revenue-model)
10. [Compliance and ethics for minors](#10-compliance-and-ethics-for-minors)
11. [Implementation plan: Phase 4 and 5 task cards](#11-implementation-plan-phase-4-and-5-task-cards)
12. [Decisions for the owner](#12-decisions-for-the-owner)
13. [Sources](#13-sources)

## 1. Principles

1. **Sell looks, convenience and private play. Never strength.** Nothing bought changes a match: no gold, regiments, manpower, Primordial charges, combat bonuses, start-position picks or information. A paying player and a free player with the same skill have the same chance to win.
2. **No loot boxes.** No paid random items, no random items bought with an earned currency, no "mystery" anything. Every reward is shown before you earn or buy it. Even free rewards are fixed, so there are no odds to disclose.
3. **Free players progress meaningfully.** A regular free player (2 matches a day, 5 days a week) earns a shop item every 1–3 days and finishes the free season track.
4. **Fair to 13–17-year-olds (and to younger players who arrive anyway).** Clear Robux prices, no countdown timers on offers, no pop-ups during a match, nothing that punishes a missed day, a purchase history screen, and no recurring charges at launch.
5. **Map colour is power.** Cosmetics never hide or change a nation's assigned colour (`Nation.colorIndex`), so the map stays readable at a glance (design pillar 1).
6. **Server authoritative.** Purchases, Glory, XP and equips go through the server. The client never grants anything.

## 2. Platform facts that shape the plan

| Topic | Fact (October 2026) | What it means for us |
| --- | --- | --- |
| DevEx | Standard rate **$0.0038 per earned Robux** for Robux earned since 5 Sep 2025 (older balances $0.0035). Minimum cash-out 30,000 earned Robux (= $114). Must be 13+, verified email, W-9/W-8 on file. | All revenue math uses $0.0038. |
| US 18+ DevEx rate | $0.0054 per earned Robux on passes, products, subscriptions and private servers bought by age-checked US 18+ players, from 8 June 2026. Player characters must be R15 or human/non-human custom rigs 100% of playtime. | Our players are a 2D map, not characters, so we almost certainly **don't qualify**. Not counted. |
| Creator share on passes, products, private servers | Widely reported as 70% of the Robux price (Roblox keeps 30%). **Unverified:** the Creator Hub pages we read don't state it. | Revenue math uses 70%. Check the first real sales report. |
| Developer products | 1 to 1 billion Robux. Grant only in `ProcessReceipt`; return `PurchaseGranted` only after saving. | Used for the season pass, starter pack, bundles and Robux shop items. |
| Game passes | Permanent ownership, checked with `UserOwnsGamePassAsync`. Cross-experience pass and product sales end 30 May 2026. | VIP is a pass. Sell everything inside the game. |
| Private servers | Free or a monthly Robux price. Changing the price cancels every active subscription. **Roblox Plus** subscribers get private servers free, and creators earn up to 100 Robux per Plus subscriber who spends 60+ minutes in a paid private server in 30 days. | Pick the price once and keep it. A paid price also earns from Plus members. |
| Roblox Plus | $4.99/month, launched 30 April 2026, replaces Premium for new sign-ups. A creator earns 250 Robux a month for the first 3 months (up to 750) when a user subscribes through `PromptRobloxSubscriptionPurchase` in their experience. | A Plus prompt on the private-server screen can earn more than the server itself (decision 5). |
| Premium Payouts | **Deprecated** on 24 July 2025, replaced by Creator Rewards. | Not in the model. |
| Creator Rewards | **Daily Engagement:** 5 Robux per Active Spender (spent $9.99+ on Roblox in 60 days) who plays 10+ minutes, if ours is one of the first 3 experiences they launch that day. **Audience Expansion:** 35% of the first $100 that new or returning users spend on Roblox in their first 60 days, if they arrive by our Share Link, direct link or name search, and we average 100+ DAU. 60-day hold. | A 25-minute match always passes 10 minutes, so we earn Daily Engagement from most qualifying players. Share Links matter for creators (`docs/LAUNCH.md`). |
| Creator Affiliate | **Deprecated** on 24 July 2025 and folded into Creator Rewards. | Not in the model. |
| Experience subscriptions | 70% of a Robux-priced subscription every month. Local-currency prices: $2.99, $4.99, $7.99, $9.99 or $14.99, 70% in month one then 100%, needs an ID- or phone-verified owner. No mutually exclusive tiers. | Possible later, not at launch (section 3.6). |
| Rewarded video ads | Experience needs 2,000+ unique monthly visitors, ID-verified owner with 2-step verification, an approved maturity questionnaire, and no free-form user creation. The reward must be a developer product we also sell, not random, not Robux, worth "3 to 10 Robux". Show only to users 13+. Roblox expects ads to add up to 3% of creator earnings at first and 5–10% long term. EPM is **unverified** (third parties say $5–15). | One small placement: a quest reroll (section 3.7). |
| Managed pricing | One opt-in for price optimization (tests price points on passes and products) and regional pricing (30–100% of the base price by country). New games and items are enrolled by default. Private servers and subscriptions are regionalized automatically. Hard-coded prices block opt-in. | Never hard-code prices in UI: read them from `MarketplaceService`. Glory prices stay the same everywhere. |
| Paid random items | Must show all outcomes and exact odds before purchase. `PolicyService` flags `ArePaidRandomItemsRestricted` per user. Free random rewards need no odds. | We sell none, so the rule never applies. |
| Age checks and chat | Since early 2026, chat needs a facial age check. Users are grouped into under 9, 9–12, 13–15, 16–17, 18–20 and 21+, and chat only with similar ages unless they're Trusted Connections. | We use Roblox's chat as-is and build no free-text chat. Emotes are icons. |
| Account types | Roblox Kids (5–8) and Roblox Select (9–15) launched in 2026. Minimal and Mild games are open to Kids and Select; Moderate games to Select and 16+. | Expect players under 13 even though we design for 13–18+. Our ethics rules assume it. |
| Parental controls | Parents set monthly spending limits and get spending notifications. Spending limits stop applying at 13. Details come from Roblox's help centre via search; the page blocked our fetch. | We add our own guardrails (section 10). |
| Ads Manager | Sponsored tiles on Home and in search. Auto-bid, cost per play (CPP), daily budget, targeting by audience, location, age, gender, genre and device. Ads Manager needs 13+; adding a card needs 18+. Robux can be converted to ad credits. Public CPP benchmarks are **unverified**. | Plan and math in `docs/LAUNCH.md`. |
| Brand integrations | Since 4 May 2026, paid brand deals inside experiences must be registered in Ads Manager. Some ad categories and rewarded formats are barred for under-13s. | No brand deals planned. |
| Analytics | `AnalyticsService`: custom, economy, funnel, onboarding-funnel and progression events. Limits: 100 custom event names, 10 funnels (100 steps each), 10 economy currencies, 3 custom fields (values past 8,000 combinations become "Other"), 120 + 20 × CCU requests per minute. Charts appear after about 24 hours and data is kept for 90 days. | Event plan in `docs/LAUNCH.md`. |
| Experience notifications | Opt-in, 13+ only, sent through Open Cloud. | Used sparingly for season and event starts. |

### Benchmarks

GameAnalytics' 2026 Roblox report covers 500+ games with at least 1M monthly users (Aug 2025 – Jul 2026). It has **no genre split**: we found no public strategy, tycoon or PvP breakdown and no public ARPDAU figure.

| Metric | p25 | Median | p90 | p99 |
| --- | ---: | ---: | ---: | ---: |
| D1 retention | 8.4% | 10.3% | — | 22.2% |
| D7 retention | 1.0% | 1.6% | — | 9.1% |
| D30 retention | 0.3% | 0.5% | — | 4.7% |
| Session length (min) | 7.3 | 9.8 | 14.7 | 21.1 |
| Sessions per player per day | 1.34 | 1.56 | 3.22 | 8.30 |
| ARPPU per game (USD, period not stated in the summary) | $0.32 | $0.70 | $2.33 | $55.31 |

Across all tracked games, 3.8% of players paid anything during the year. Roblox DAU fell from 152M (Q3 2025) to 123M (Q2 2026), per the same summary.

**Our genre today (Rotrends, October 2026, unverified tracker):** RoFront (World PvP) peaks around 28,900 CCU with a 7-day average of about 15,800; Conquer The World WW2 has about 9,600 current players; Navy War peaks around 4,500; Country War RTS sits around 1,700. A 15,000 peak CCU would put us in the genre's top three. That's our high scenario.

## 3. Catalogue and prices

US store prices for reference (**unverified**, third-party): 400 Robux = $4.99, 800 = $9.99, so 1 Robux ≈ $0.0125 to the buyer. Regional pricing lowers this in poorer markets.

### 3.1 Price ladder

Every cosmetic has a rarity. Rarity sets the price.

| Rarity | Robux | Glory | Robux why |
| --- | ---: | ---: | --- |
| Common | 49 | 500 | Under $1: an impulse buy for a teen. |
| Rare | 99 | 1,200 | About $1.25: the most common Roblox cosmetic price point. |
| Epic | 149 | 2,500 | Animated or effect-heavy items. |
| Legendary | 249 | — | Robux, season pass or achievement only. Kept rare so they stay special. |

Glory prices aren't changed by regional pricing. Robux prices are read live from `MarketplaceService` so managed pricing can test them.

### 3.2 Cosmetics

| Category | What it changes | Who sees it | Rarities | Price (Robux) |
| --- | --- | --- | --- | --- |
| Flag | The 16×12 pixel flag on your capital, nation list and Results | Everyone | Common, Rare, Epic (animated) | 49 / 99 / 149 |
| Border style | Pattern of your two-pixel nation border (dashes, runes, embers) | Everyone | Rare, Epic | 99 / 149 |
| Shade set ("palette") | Three shades **of your assigned colour** used for terrain shading in your provinces. Never a different hue. | Everyone | Common, Rare | 49 / 99 |
| Army token | The token sprite for your armies | Everyone | Rare, Epic, Legendary (animated) | 99 / 149 / 249 |
| Nation skin set | Matched flag + border + token | Everyone | Rare set, Epic set | 199 (pieces 297) / 299 (pieces 447) |
| Map theme | Re-skin of a map's terrain (Winter Skyshards, Ember Eldmoor, Night Earth). Nation colours unchanged, readability check before release. | You, and everyone when it wins the theme vote (below) | Rare | 99 |
| Primordial-power effect | How one power looks (meteor style, plague colour, blessing rays). Same area, timing and sound cue, so it's never harder to read. | Everyone | Common (colour), Rare (new style), Epic | 49 / 99 / 149 |
| Capital emote | An icon over your capital for 3 s, max one per 10 s | Everyone | Static, animated (own price, Glory 300 / 500) | 25 / 49 |
| Victory animation | Plays over the winner's capital on the Results screen | Everyone | Epic, Legendary | 149 / 249 |
| Nameplate frame | Frame around your name in the nation list, lobby and Results | Everyone | Common, Rare | 49 / 99 |
| Title | Text under your name ("the Unbroken") | Everyone | — | **Not sold.** Earned from ranks, achievements and seasons only. |

**Theme vote.** When a map wins the lobby vote, it uses the theme equipped by the most players who voted for it (ties go to the default theme). That shows a theme to the whole server and credits its owners on the loading card. A setting lets anyone always see the default theme.

Production is cheap because everything is pixel art: a flag takes about 30 minutes, a token 1–2 hours, a power effect 3–6 hours and a victory animation 1–2 days. Season 1 needs about 80 shop items plus 50 pass rewards.

### 3.3 VIP game pass: 249 Robux

| Benefit | Strength? |
| --- | --- |
| +25% account XP and Glory from matches (not from quests) | No: XP and Glory only unlock cosmetics |
| VIP flag set (Rare flag, border and token, VIP-only) | No |
| Gold nameplate frame and `[VIP]` chat tag | No |
| +1 daily quest reroll | No |

Why 249 instead of DESIGN.md's 199: VIP is bought once and kept forever, it's usually a game's top seller, and 249 Robux (about $3.10) is still below most VIP passes. Managed pricing will test it.

### 3.4 Private servers: 100 Robux a month

DESIGN.md's price stays. A group of friends can split it, and a paid price (not free) also earns up to 100 Robux a month from each Roblox Plus member who plays 60+ minutes in our paid servers. **Never change the price after launch**: Roblox cancels every active subscription when you do.

| Setting | Options | Default |
| --- | --- | --- |
| Map | Earth, Eldmoor, Skyshards (+ new maps) | Vote |
| Map theme | Any theme the owner owns | Default |
| Match length | 15, 25, 35 min | 25 |
| Peace phase | 0, 3, 5 min | 3 |
| Bots | 0–9, Easy / Normal / Hard | Fill to 10, Normal |
| Primordial powers | On / off | On |
| Cataclysm disasters | On / off | On |
| Lock teams | Owner pre-sets alliances | Off |

**Rewards in private servers:** with default rules and 4+ real players, everything counts (XP, Glory, quests). With custom rules or fewer than 4 real players: 50% XP and Glory, quests still progress except "win" quests, and no leaderboard points. That stops one player farming nine Easy bots.

### 3.5 Starter pack and bundles

| Offer | Price | Contents | Bought separately | Rules |
| --- | ---: | --- | ---: | --- |
| Starter pack | 149 | Rare "Vanguard" flag, Rare "Vanguard" token, Charge and Wave emotes, Common frame | 297 | One per account. Offered after your 2nd match. **No timer**, stays in the shop until bought. |
| Season pass bundle | 499 | Premium pass + 10 tiers | 299 + 10 tiers | Bought once at the start of a season. No single tier skips (section 6). |
| Theme bundle | 169 | Both themes of the season | 198 | Season only. |
| Primordial FX bundle | 249 | 4 Rare effects of one style | 396 | Rotates in the weekly slot. |
| Nation skin sets | 199 / 299 | See 3.2 | 297 / 447 | |

"Bought separately" is the real sum of the current prices. We never show a made-up "was" price.

### 3.6 Subscriptions: not at launch

We don't launch with an experience subscription:

- Anything worth subscribing for would be currency (we don't sell Glory) or strength (we don't sell it).
- VIP plus the season pass already cover the "I support this game" buyer.
- Recurring charges are the purchase type parents complain about most. Roblox Plus already gives free private servers.

**Revisit at month 5** if more than 30% of payers buy two season passes in a row. Candidate: "War Chest", 199 Robux a month (Robux-priced so any owner can run it): one exclusive cosmetic recolour each month, an animated nameplate shimmer and +1 quest reroll. Never Glory, XP or anything in a match.

### 3.7 Rewarded video: one placement

- **Placement:** on the Quests screen, "Watch an ad to reroll a quest". At most 2 ads a day per player.
- **Product:** "Quest reroll" developer product, 10 Robux. It has to be on sale for the ad reward to be allowed.
- Shown only after `AdService:GetAdAvailabilityNowAsync` says yes, and only to players 13+. Turn on "Exclude your most likely purchasers".
- No ads anywhere else: never during a match and never on the Results screen.

### 3.8 Rotating shop

| Slot | Count | Refresh | Contents |
| --- | ---: | --- | --- |
| Daily | 4 | 00:00 UTC | 2 Common, 1 Rare, 1 Epic |
| Weekly featured | 2 | Monday 00:00 UTC | 1 Legendary or nation skin set, 1 bundle |
| Core | 12 | Never | A fixed starter range, always on sale, so nobody has to wait for basics |
| Offers | 3 | Fixed | VIP, starter pack, season pass |

- The rotation is a fixed schedule from a seeded generator, the same for every player. It isn't personalised and nothing is random per player.
- **Every shop item comes back within 60 days**, and the shop says so. Only season-pass premium items and event rewards are one-time, and the pass says so before you buy.
- Glory is accepted for every Common, Rare and Epic item in the shop.

### 3.9 Never sell

Gold, manpower, regiments, buildings, Primordial charges or cooldowns, combat modifiers, start-position or draft-order picks, map vote weight, match information (fog, enemy plans), extra alliance slots, XP from other players, ranked rating, titles, Glory.

### 3.10 Shop setup (Creator Dashboard)

The catalogue is `src/shared/Catalogue.luau`; prices by rarity are in `Config.Shop`. Every Roblox id lives in one place at the top of the catalogue, `Catalogue.PRODUCT_IDS` and `Catalogue.VIP_PASS_ID`, and starts at **0**.

**Test mode.** While an id is 0, Studio grants that purchase free, through the same `ProcessReceipt` path with a made-up receipt (the shop header says "Studio test mode"). A live server refuses it ("Not on sale yet"), so a forgotten id can never give an item away. With "Enable Studio Access to API Services" on, test purchases save to the real DataStore for your own test account.

**What the owner creates** (Creator Dashboard → your experience → Monetization):

1. **Game pass** "VIP", 249 Robux. Put its id in `Catalogue.VIP_PASS_ID`.
2. **Developer products**, one per key of `Catalogue.PRODUCT_IDS`, priced as below. Put each id next to its key.

| Product keys | Price (Robux) |
| --- | ---: |
| `flag_tricolour`, `flag_cross`, `shades_dawn`, `shades_dusk`, `frame_bronze`, `fx_meteor_ice`, `fx_plague_violet` (Common) | 49 |
| `flag_sun`, `flag_crown`, `flag_vanguard`, `border_dashes`, `border_runes`, `shades_royal`, `token_shield`, `token_vanguard`, `frame_silver`, `fx_blessing_rays` (Rare) | 99 |
| `flag_comet`, `border_embers`, `token_tower`, `victory_fireworks`, `fx_meteor_comet` (Epic) | 149 |
| `token_dragon`, `victory_dragon` (Legendary) | 249 |
| `emote_charge`, `emote_wave`, `emote_gg`, `emote_laugh` (static emotes) | 25 |
| `emote_fire`, `emote_crown` (animated emotes) | 49 |
| `starter` (Starter Pack, once per account) | 149 |
| `set_royal` (Royal Set: Crown flag, Runes border, Shield token) | 199 |

3. Opt in to managed pricing if you want: the shop reads live prices with `MarketplaceService:GetProductInfo`, and the Config numbers are only shown while an id is 0.

**How a purchase flows.** The client asks (`RequestBuy`); `CommandRouter` checks the shape; `ShopService` checks the rules (`Sim/Shop`): Robux prompts only open in the Lobby, the draft and on Results, never during a match. Developer products are granted in `MarketplaceService.ProcessReceipt` → `PlayerDataService.processReceipt`: each purchase id is granted once, recorded in the purchase history and saved before `PurchaseGranted`. VIP is checked with `UserOwnsGamePassAsync` on join and on `PromptGamePassPurchaseFinished`, and the pass is added to the purchase history too.

## 4. Currency: Glory

**Decision: one soft currency, Glory, earned only by playing. It is never sold for Robux, directly or in a bundle.** Robux buys items directly.

Why one earned currency instead of Robux only:

- Free players need something to spend, or the shop is a wall.
- An earned-only currency can't become a paid random-items or "hidden price" problem, and it's easy to explain to parents: "you can't buy Glory".
- No second, paid currency: no confusing "gems" exchange rate between Robux and the item price.

### 4.1 Earn rates

| Source | Glory |
| --- | ---: |
| Finish a match (stay to Results) | 20 |
| Placement: 1st / 2nd / 3rd / 4th–5th / 6th–10th | 40 / 30 / 20 / 15 / 10 |
| Activity: +1 per province captured and per battle won | up to 15 |
| Rose as a Primordial and stayed to Results | 10 |
| First match of the day (UTC) | 50 |
| Daily quest: easy / medium / hard | 30 / 40 / 50 |
| Weekly quest (×3) | 150 each |
| Login calendar (7 play days, section 5.6) | 500 per cycle |
| Level up / rank up | 50 / +500 |
| Achievements | 50–500 one-time |
| VIP | +25% of match Glory |

An average match pays **about 49 Glory** (20 + 17 average placement + 8 activity + 4 Primordial). A match takes about 27.5 minutes with lobby, pick and Results, so matches alone pay about **107 Glory per hour**. Daily bonuses make the first hour of each day worth much more.

Leaving early pays nothing from placement or Primordial play, and match Glory is prorated by minutes played.

### 4.2 Earn per week and time to earn

Three player types. Weekly totals include matches, the first-match bonus, quests, the login calendar, and level-up Glory averaged over a season.

| | Casual | Regular | Heavy |
| --- | --- | --- | --- |
| Play pattern | 4 days, 1.5 matches a day | 5 days, 2 matches a day | 7 days, 5 matches a day |
| Hours a week | 2.8 | 4.6 | 16.0 |
| Glory a week | ~1,840 | ~2,670 | ~4,610 |
| Glory per hour played | ~670 | ~580 | ~290 |
| **Common (500)** | 1.9 days | 1.3 days | 0.8 days |
| **Rare (1,200)** | 4.6 days | 3.2 days | 1.8 days |
| **Epic (2,500)** | 9.5 days | 6.6 days | 3.8 days |

Glory per hour falls for heavy players because the daily bonuses are a bigger share of a short session. That's on purpose: it rewards coming back over grinding. A regular free player gets **one Epic a week, or a Rare every 3 days**.

**Glory sinks:** shop items (the main sink), clan creation (2,000, from month 4) and quest rerolls past the free one (100). Watch the Glory balance distribution weekly: if the median regular player holds more than 10,000 unspent Glory, the shop isn't interesting enough. Fix it with more items, not by cutting earn rates.

## 5. Progression

### 5.1 Account XP per match

| Source | XP |
| --- | ---: |
| Finish a match (stay to Results) | 100 |
| Placement: 1st / 2nd / 3rd / 4th–5th / 6th–10th | 150 / 100 / 75 / 50 / 25 |
| Alliance victory | Every member gets 1st place |
| Provinces captured | 5 each, max 100 |
| Battles won | 5 each, max 50 |
| Rose as a Primordial | 50 |
| Primordial power used | 10 each, max 50 |
| First match of the day | 200 |
| VIP | +25% of match XP |

Average match: about **245 XP** (100 + 55 average placement + 40 provinces + 25 battles + 25 Primordial). Primordial XP keeps eliminated players in the match (pillar: "nobody sits out").

**Anti-AFK:** a player who sends no command for 5 minutes in a row earns no match XP or Glory for that match. Leaving early prorates the 100 finish XP by minutes played and gives no placement XP.

### 5.2 Level curve

XP to go from level L to L+1 = **300 + 60 × (L − 1)**. Level 100 is the cap and needs **320,760 XP** in total.

| Player | XP a week | Level after 8 weeks | Weeks to level 100 |
| --- | ---: | ---: | ---: |
| Casual | ~5,620 | 35 | ~57 |
| Regular | ~8,700 | 44 | ~37 |
| Heavy | ~16,100 | 62 | ~20 |

A new player reaches level 2 after one match and level 4 after three matches on day one, so early levels come quickly. Level 100 is a year-long goal for a regular player.

| Lvl | To next | Total | Lvl | To next | Total | Lvl | To next | Total | Lvl | To next | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 300 | 0 | 26 | 1,800 | 25,500 | 51 | 3,300 | 88,500 | 76 | 4,800 | 189,000 |
| 2 | 360 | 300 | 27 | 1,860 | 27,300 | 52 | 3,360 | 91,800 | 77 | 4,860 | 193,800 |
| 3 | 420 | 660 | 28 | 1,920 | 29,160 | 53 | 3,420 | 95,160 | 78 | 4,920 | 198,660 |
| 4 | 480 | 1,080 | 29 | 1,980 | 31,080 | 54 | 3,480 | 98,580 | 79 | 4,980 | 203,580 |
| 5 | 540 | 1,560 | 30 | 2,040 | 33,060 | 55 | 3,540 | 102,060 | 80 | 5,040 | 208,560 |
| 6 | 600 | 2,100 | 31 | 2,100 | 35,100 | 56 | 3,600 | 105,600 | 81 | 5,100 | 213,600 |
| 7 | 660 | 2,700 | 32 | 2,160 | 37,200 | 57 | 3,660 | 109,200 | 82 | 5,160 | 218,700 |
| 8 | 720 | 3,360 | 33 | 2,220 | 39,360 | 58 | 3,720 | 112,860 | 83 | 5,220 | 223,860 |
| 9 | 780 | 4,080 | 34 | 2,280 | 41,580 | 59 | 3,780 | 116,580 | 84 | 5,280 | 229,080 |
| 10 | 840 | 4,860 | 35 | 2,340 | 43,860 | 60 | 3,840 | 120,360 | 85 | 5,340 | 234,360 |
| 11 | 900 | 5,700 | 36 | 2,400 | 46,200 | 61 | 3,900 | 124,200 | 86 | 5,400 | 239,700 |
| 12 | 960 | 6,600 | 37 | 2,460 | 48,600 | 62 | 3,960 | 128,100 | 87 | 5,460 | 245,100 |
| 13 | 1,020 | 7,560 | 38 | 2,520 | 51,060 | 63 | 4,020 | 132,060 | 88 | 5,520 | 250,560 |
| 14 | 1,080 | 8,580 | 39 | 2,580 | 53,580 | 64 | 4,080 | 136,080 | 89 | 5,580 | 256,080 |
| 15 | 1,140 | 9,660 | 40 | 2,640 | 56,160 | 65 | 4,140 | 140,160 | 90 | 5,640 | 261,660 |
| 16 | 1,200 | 10,800 | 41 | 2,700 | 58,800 | 66 | 4,200 | 144,300 | 91 | 5,700 | 267,300 |
| 17 | 1,260 | 12,000 | 42 | 2,760 | 61,500 | 67 | 4,260 | 148,500 | 92 | 5,760 | 273,000 |
| 18 | 1,320 | 13,260 | 43 | 2,820 | 64,260 | 68 | 4,320 | 152,760 | 93 | 5,820 | 278,760 |
| 19 | 1,380 | 14,580 | 44 | 2,880 | 67,080 | 69 | 4,380 | 157,080 | 94 | 5,880 | 284,580 |
| 20 | 1,440 | 15,960 | 45 | 2,940 | 69,960 | 70 | 4,440 | 161,460 | 95 | 5,940 | 290,460 |
| 21 | 1,500 | 17,400 | 46 | 3,000 | 72,900 | 71 | 4,500 | 165,900 | 96 | 6,000 | 296,400 |
| 22 | 1,560 | 18,900 | 47 | 3,060 | 75,900 | 72 | 4,560 | 170,400 | 97 | 6,060 | 302,400 |
| 23 | 1,620 | 20,460 | 48 | 3,120 | 78,960 | 73 | 4,620 | 174,960 | 98 | 6,120 | 308,460 |
| 24 | 1,680 | 22,080 | 49 | 3,180 | 82,080 | 74 | 4,680 | 179,580 | 99 | 6,180 | 314,580 |
| 25 | 1,740 | 23,760 | 50 | 3,240 | 85,260 | 75 | 4,740 | 184,260 | 100 | max | 320,760 |

"Total" is the XP needed to reach that level.

### 5.3 Ranks

One rank per 10 levels. A rank is an account level, **not skill**. Skill lives in the later ranked mode (section 7.5).

| Levels | Rank | Rank-up reward |
| --- | --- | --- |
| 1–9 | Settler | — |
| 10–19 | Chieftain | Title, Common frame, +500 Glory |
| 20–29 | Baron | Title, Common frame, +500 Glory |
| 30–39 | Count | Title, Rare frame, +500 Glory |
| 40–49 | Duke | Title, Rare frame, +500 Glory |
| 50–59 | Prince | Title, Rare flag, +500 Glory |
| 60–69 | King | Title, Epic frame, +500 Glory |
| 70–79 | Emperor | Title, Epic border, +500 Glory |
| 80–89 | Conqueror | Title, Epic token, +500 Glory |
| 90–99 | World Shaker | Title, Epic victory animation, +500 Glory |
| 100 | Primordial | Title, Legendary animated frame, +500 Glory |

Every level also gives 50 Glory, and every 5th level (not a rank-up) gives a Common cosmetic.

### 5.4 Daily quests

Three a day at 00:00 UTC: one easy, one medium and one hard, picked from a pool by a seeded generator (player id + day). One free reroll a day (+1 for VIP, +2 from rewarded video, or 100 Glory each after that). Unfinished daily quests stay for 2 days (max 6 waiting), so missing a day doesn't lose them.

| Tier | Reward | Examples |
| --- | --- | --- |
| Easy | 100 XP, 30 Glory | Play 1 match. Capture 3 neutral provinces. Recruit 5 regiments. Build 2 buildings. |
| Medium | 150 XP, 40 Glory | Win 3 battles. Develop a province to level 4. Form an alliance. Finish in the top 5. Use 2 Primordial powers. |
| Hard | 200 XP, 50 Glory | Capture an enemy capital. Hold 25 provinces at once. Finish in the top 3. Win a battle as an underdog. As a Primordial, use 4 powers. |

Rules for the quest pool:

- Every quest can be finished in normal play on every map.
- No quest asks you to lose, betray an ally, quit, or do anything that ruins other players' match.
- No quest needs a purchase or a specific cosmetic.

### 5.5 Weekly quests

Three a week (Monday 00:00 UTC), each worth 1,000 XP and 150 Glory. Examples: play 10 matches; win 1 match; play on all three maps; capture 100 provinces in total; win 50 battles; use 15 Primordial powers.

### 5.6 Login calendar, streaks and achievements

**Login calendar:** a 7-step cycle that moves one step on each **day you play**, not each calendar day. Missing days pauses it and never resets it.

| Step | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Glory | 25 | 25 | 50 | 50 | 75 | 75 | 200 |

**Play streak:** consecutive days with a finished match. One missed day per week is covered automatically. Streak rewards are cosmetic only: a flame on your nameplate at 3 days, a bigger flame at 7, a blue flame at 14 and the title "the Unyielding" at 30. A broken streak keeps every earned reward.

**Achievements:** one-time, shown with progress bars. 30 at launch. Examples:

| Achievement | Condition | Reward |
| --- | --- | --- |
| First Blood | Win a battle | 50 Glory |
| Land Grab | Capture 10 neutral provinces in one Peace phase | 100 Glory |
| Domination | Win by holding 40% of provinces | 300 Glory, title "the Dominant" |
| Better Together | Win an alliance victory | 200 Glory |
| Comeback | Win after being in the bottom 3 at 10:00 | 500 Glory, title "the Unbroken" |
| Kingmaker | As a Primordial, see an ally win | 200 Glory |
| Meteorologist | Kill 20,000 men with meteors (lifetime) | Rare meteor effect |
| Cartographer | Win on Earth, Eldmoor and Skyshards | 300 Glory, title "Cartographer" |
| Iron Wall | Defend a fort through 3 sieges in one match | 200 Glory |
| Centurion | Play 100 matches | Epic frame |
| World Shaker | Reach level 90 | Legendary token |

## 6. Season pass

| Setting | Value |
| --- | --- |
| Season length | 8 weeks |
| Tiers | 50 |
| XP per tier | 1,200 (season XP = account XP earned during the season, so one number to explain) |
| Total | 60,000 XP |
| Bonus tiers after 50 | 100 Glory per 2,400 XP, repeatable |
| Premium price | 299 Robux, or 499 for the bundle with 10 tiers |
| Tier skips | **None**, apart from the bundle at purchase |
| Buying late | Unlocks every premium reward up to your current tier at once |

**Pacing** (using the player types from section 4.2):

| | Casual | Regular | Heavy |
| --- | --- | --- | --- |
| Tier reached by week 8 | ~37 | 50 (in week 7) | 50 (in week 4) |

A regular player finishes with a week to spare, and a casual player gets most of the free track. No single tier skips means nobody is pushed to pay at the end of a season.

**Value:** the premium track has 40 cosmetics, a title and 2,250 Glory for 299 Robux. The free track has 10 cosmetics, a title and 2,500 Glory. Premium items are never sold later (the pass says so before purchase); a recolour may come back in a future season.

### Season 1: Rise of the Primordials

Theme: molten earth, ember and the old gods waking. Map theme: Ember Eldmoor.

| Tier | Free | Premium |
| ---: | --- | --- |
| 1 | GG emote | Ember Knight army token (Epic), given at once |
| 2 | — | 100 Glory |
| 3 | 100 Glory | Ember Banner flag (Rare) |
| 4 | — | Laugh emote |
| 5 | Ember Sigil flag (Common) | Molten nameplate frame (Rare) |
| 6 | — | 100 Glory |
| 7 | — | Ember plague colour (Common) |
| 8 | 100 Glory | Volcano emote (animated) |
| 9 | — | Cinder border (Rare) |
| 10 | Runic border (Rare) | Ember Meteor effect (Rare) |
| 11 | — | 100 Glory |
| 12 | — | Ashfall Rebels effect (Common) |
| 13 | 150 Glory | Crown Toss emote (animated) |
| 14 | — | Titan's Eye flag (Rare) |
| 15 | Salute emote | Lava Seam border (Epic) |
| 16 | — | 150 Glory |
| 17 | — | Molten Blessing effect (Rare) |
| 18 | 150 Glory | Obsidian army token (Rare) |
| 19 | — | Skull emote |
| 20 | Stone Meteor effect (Common) | Eruption victory animation (Epic) |
| 21 | — | 150 Glory |
| 22 | — | Firestorm Earthquake effect (Rare) |
| 23 | 200 Glory | Cracked Crown flag (Epic, animated) |
| 24 | — | Ember Shield effect (Rare) |
| 25 | Ashen nameplate frame (Common) | **Ember Eldmoor map theme** |
| 26 | — | 150 Glory |
| 27 | — | Magma Pulse border (Epic) |
| 28 | 200 Glory | Phoenix Rider army token (Epic) |
| 29 | — | Eruption emote (animated) |
| 30 | Stone Golem army token (Rare) | Storm Titan flag (Epic) |
| 31 | — | 200 Glory |
| 32 | — | Void Plague colour (Rare) |
| 33 | 250 Glory | Obsidian nameplate frame (Epic) |
| 34 | — | Primordial Roar emote (animated) |
| 35 | Volcano Peak emote | Lava Rebels effect (Epic) |
| 36 | — | 200 Glory |
| 37 | — | Worldsplitter Earthquake effect (Epic) |
| 38 | 250 Glory | Cinder Golem army token (Epic) |
| 39 | — | 250 Glory |
| 40 | Storm Banner flag (Rare) | Starfall Blessing effect (Epic) |
| 41 | — | Meteor Shower emote (animated) |
| 42 | — | 250 Glory |
| 43 | 300 Glory | Primordial Eye nameplate frame (Epic) |
| 44 | — | Sunfire Divine Shield effect (Epic) |
| 45 | Cinder Plague colour (Rare) | Ember shade set (Rare) |
| 46 | — | 300 Glory |
| 47 | — | Obsidian Crown flag (Legendary) |
| 48 | 300 Glory | 300 Glory |
| 49 | — | Primordial Rift border (Legendary) |
| 50 | Title "Season 1 Veteran", Season 1 badge, 500 Glory | Titan army token (Legendary, animated), Phoenix Meteor effect (Legendary), Titan Rising victory animation (Legendary), title "Primordial Herald" |

## 7. Retention and social

### 7.1 Parties and friends

- **Parties of up to 3** (the alliance cap). A party queues together and starts on neighbouring nations, as DESIGN.md says. They aren't auto-allied: allying is two taps.
- **Join a friend:** the main menu lists friends in Total World Chaos with a Join button. Invites use `SocialService:PromptGameInvite`.
- **Recruit a friend:** when someone you invited finishes 3 matches, you both get the "Comrades" flag (Rare, never sold). One per invited player, max 10 per account.

### 7.2 Clans (month 4)

- Up to 30 members, a 3–4 letter tag shown in the nation list, and a banner built from owned flag parts.
- Created for 2,000 Glory (a Glory sink, never Robux). The name and tag go through `TextService:FilterStringAsync`, there's no clan chat or description text, and Roblox's own chat applies.
- **Weekly clan score:** the sum of the top 20 members' weekly conquest points. The top 100 clans get a clan frame for the next week.

### 7.3 Leaderboards

| Board | Measure | Reset | Reward |
| --- | --- | --- | --- |
| Weekly conquest | Points: 1st 10, 2nd 7, 3rd 5, 4th–5th 3, 6th–10th 1. Public matches with 4+ real players only. | Monday 00:00 UTC | Top 100: "Warlord" frame for a week |
| Friends | Weekly conquest, friends only | Weekly | None (bragging) |
| Global level | Account XP | Never | None |
| Per-map wins | Wins on each map | Never | Map title at 100 wins |

### 7.4 Next-map vote and events

- **Next-map vote** after Results (already in DESIGN.md) keeps the same server together for match 2. Add the theme vote (section 3.2) and a "Stay for next match" button that's selected by default.
- **Weekend events** (from month 2): a free event quest line with an event-only cosmetic, and a light rule twist that's the same for everyone (Meteor Weekend: Primordial charges come twice as fast; Alliance Week: double XP for alliance victories). Rule twists are new design work: each needs a DESIGN.md change first.

### 7.5 Ranked mode (beta in month 5–6)

- Unlocks at level 15, which slows down smurf accounts.
- Starts only when peak CCU is 1,500+, so a 10-player ranked lobby fills in under 60 seconds.
- Standard rules, 10 real players to start (leavers become bots as usual), map rotates daily.
- A multiplayer skill rating (OpenSkill-style) with leagues: Bronze, Silver, Gold, Platinum, Diamond, Primordial.
- Leaving a ranked match: rating loss and a 10-minute queue ban.
- Rewards are cosmetic only: an end-of-season frame by league. Rating can never be bought.

### 7.6 Notifications

Experience notifications (opt-in, 13+) at most twice a week: season start, event start, and "your weekly rewards are ready". Never "come back or lose your streak".

## 8. Live-ops calendar: the first 6 months

Week 1 is public launch, which is also the start of Season 1. Soft launch runs for the 6 weeks before it (`docs/LAUNCH.md`). Holiday themes (Halloween, winter, Lunar New Year, summer) go into the rotating shop in whatever weeks they fall.

| Weeks | Season | Content update | Shop and themes | Event |
| --- | --- | --- | --- | --- |
| −6 to 0 | Pre-season (soft launch) | Tutorial, VIP, starter pack, core shop, analytics | Night Earth theme | Free "Founder" flag for everyone who plays before launch |
| 1 | **S1 Rise of the Primordials** | Season pass, quests, weekly leaderboard | Ember Eldmoor (pass), 4 new FX | Launch week: double XP |
| 3 | S1 | Balance patch from start-position win rates | | Meteor Weekend |
| 4–5 | S1 | Easy and Hard bots (DESIGN Phase 5), achievements wave 2 | Ember FX bundle | |
| 6 | S1 | Balance patch | | Alliance Week |
| 8 | S1 ends | Season 2 trailer | | Last-week double XP |
| 9 | **S2 Frozen Age** | Friends leaderboard, recruit-a-friend | Winter Skyshards (pass), Frozen Earth (shop) | |
| 11 | S2 | Balance patch | | Siege Weekend |
| 13 | S2 | **Clans** | Clan banner parts | Clan launch week |
| 15 | S2 | Creator Cup: community tournament in private servers | | Cup frame for finalists |
| 16 | S2 ends | Season 3 trailer, Map 4 teaser | | |
| 17 | **S3 Shattered Skies** | **Map 4** (built with `tools/mapgen`), ranked beta if CCU allows | Map 4 theme (pass) | Map 4 launch week |
| 19 | S3 | Balance patch for Map 4 | | Meteor Weekend |
| 21 | S3 | Ranked season 0 rewards, subscription test decision | | |
| 23 | S3 | Balance patch | | Alliance Week |
| 24 | S3 ends | Season 4 trailer | | |
| 25 | **S4** | Next map or mode, chosen from the data | | |

The cadence is a balance patch every 2–3 weeks, a content drop every 4 weeks, a season every 8 weeks and a new map every 16 weeks.

## 9. Revenue model

### 9.1 Funnel assumptions

| Step | Formula | Why |
| --- | --- | --- |
| Peak CCU → average CCU | average = peak ÷ 1.8 | Typical daily peak-to-average ratio (assumption). |
| Average CCU → DAU | DAU = average CCU × 1,440 ÷ 45 | We assume 45 minutes of play per DAU per day (about 1.6 matches), so **DAU ≈ 18 × peak CCU**. |
| DAU → MAU | MAU = DAU × 4 | DAU/MAU of 25% (assumption; our target KPI). |
| MAU → payers | payers = MAU × monthly conversion | 1.0% / 1.5% / 2.5%. GameAnalytics: 3.8% of players paid anything in a year, across all games. |
| Payer spend | ARPPU, Robux a month | 400 / 500 / 650. A payer typically buys a pass (299) and VIP (249) once, plus shop items. |
| Creator share | 70% of Robux spent | Widely reported, unverified (section 2). |
| Creator Rewards | Robux per DAU per day | 0.15 / 0.25 / 0.30. Base: 10% of DAU are Active Spenders × 50% launch us among their first 3 games × 5 Robux. **Unverified assumption**: Roblox doesn't publish the Active Spender share. |
| Other | 10% of IAP earnings | Plus prompts, rewarded video. Roblox expects ads to add up to 3% early. |
| DevEx | $0.0038 per earned Robux | Section 2. |

### 9.2 Three scenarios (steady state, months 4–6)

| | Low | Base | High |
| --- | ---: | ---: | ---: |
| Peak CCU | 300 | 2,000 | 15,000 |
| DAU | 5,400 | 36,000 | 270,000 |
| MAU | 21,600 | 144,000 | 1,080,000 |
| Monthly conversion | 1.0% | 1.5% | 2.5% |
| Payers a month | 216 | 2,160 | 27,000 |
| ARPPU (Robux) | 400 | 500 | 650 |
| Robux spent by players | 86,400 | 1,080,000 | 17,550,000 |
| Player spend (USD at $0.0125/Robux) | $1,080 | $13,500 | $219,000 |
| Earned Robux from purchases (70%) | 60,480 | 756,000 | 12,285,000 |
| Creator Rewards (Robux) | 24,300 | 270,000 | 2,430,000 |
| Other (Robux) | 6,048 | 75,600 | 1,228,500 |
| **Total earned Robux a month** | **90,828** | **1,101,600** | **15,943,500** |
| **DevEx a month** | **$345** | **$4,186** | **$60,585** |
| **DevEx a year** | **$4,142** | **$50,233** | **$727,024** |
| Gross ARPDAU (player spend) | $0.0067 | $0.0125 | $0.0270 |
| Net ARPDAU (DevEx) | $0.0021 | $0.0039 | $0.0075 |

Sample math for the base case: 2,000 peak CCU × 18 = 36,000 DAU; × 4 = 144,000 MAU; × 1.5% = 2,160 payers; × 500 Robux = 1,080,000 Robux; × 70% = 756,000 earned. Creator Rewards: 36,000 × 0.25 × 30 = 270,000. Other: 10% of 756,000 = 75,600. Total 1,101,600 × $0.0038 = $4,186 a month.

**Moonshot sensitivity:** revenue scales with CCU. At RoFront's peak (~29,000 CCU) with high-case rates, DevEx is about $117,000 a month. Tripling peak CCU matters far more than any price change.

**Base-case revenue mix (planning estimate):**

| Product | Share of Robux spent |
| --- | ---: |
| Season pass and bundle | 30% |
| Shop cosmetics (Robux) | 30% |
| VIP | 20% |
| Starter pack and bundles | 12% |
| Private servers | 8% |

Costs aren't in these numbers. Subtract the ads budget (`docs/LAUNCH.md`: $1,500 soft launch, $3,000 launch week, then $1,000–3,000 a month) and any art contractors. DevEx is pre-tax.

### 9.3 DevEx conversion

| Earned Robux | DevEx at $0.0038 |
| ---: | ---: |
| 30,000 (minimum) | $114 |
| 100,000 | $380 |
| 1,000,000 | $3,800 |
| 10,000,000 | $38,000 |

One Robux a player spends becomes 0.7 earned Robux, which is $0.00266 DevEx. A player paying $4.99 for 400 Robux and spending all of it with us yields about **$1.06**. Purchase Robux arrive after a hold of about 5 days; Creator Rewards after 60 days.

### 9.4 KPIs and targets

| KPI | Target | Benchmark | Why it matters |
| --- | ---: | --- | --- |
| D1 retention | ≥ 15% | median 10.3%, p99 22.2% | First-match fun and tutorial |
| D7 retention | ≥ 4% | median 1.6%, p99 9.1% | Quests and pass hook |
| D30 retention | ≥ 1.5% | median 0.5%, p99 4.7% | Long-term goals, social |
| Average session | ≥ 30 min | median 9.8, p99 21.1 | A match is 25 min, so lower means people quit mid-match |
| Match completion (stay to Results) | ≥ 70% | — | Primordial role working |
| Tutorial completion | ≥ 70% | — | Gate 4 |
| New players who start a 2nd match | ≥ 50% | — | Next-map vote working |
| DAU/MAU | ≥ 25% | — | Habit |
| Monthly payer conversion (MAU) | ≥ 1.5% | 3.8% yearly, all games | Offer quality |
| ARPPU | ≥ 500 Robux a month | — | Catalogue depth |
| Pass attach (payers who buy the pass) | ≥ 35% | — | Pass value |
| Premium pass owners who reach tier 50 | ≥ 50% | — | Pacing fairness |
| Human share of nations in public matches | ≥ 40% | — | Population health |
| Purchase complaints and refund requests | ~0 | — | Trust |

## 10. Compliance and ethics for minors

| Area | Rule we follow |
| --- | --- |
| Clear prices | Every price shows the Robux icon and amount, read live from `MarketplaceService` (so regional prices are correct). Glory prices show the Glory icon. No "was" prices that never existed. Bundles show the real sum of current prices. |
| No gambling | No paid random items, no random items for Glory, no free random rewards either. The rotating shop is the same for everyone. No trading and no gifting at launch (so `IsPaidItemTradingAllowed` and gift abuse never come up). |
| Nothing misleading | The shop says every item returns within 60 days. Pass-exclusive items are labelled before purchase. Thumbnails and trailers use real gameplay (also a Roblox video rule). |
| No pressure | No countdown timers on offers. No purchase prompts during a match. At most one offer pop-up per session (starter pack, after match 2), never before a player's 2nd match. No "you'll lose your streak" messages. No single tier skips. |
| Purchase transparency | An in-game Purchase History screen lists every Robux purchase from the receipt ledger. |
| Parental controls | Roblox handles spending limits and notifications for under-13s. We respect `PolicyService:GetPolicyInfoForPlayerAsync` (external links, paid random items, trading) and never link off-platform for users it disallows. |
| Ads | Rewarded video only for 13+ users, only on the Quests screen, never random. No brand deals. |
| Chat safety | We use Roblox `TextChatService` as-is, with no custom free-text chat. Emotes are icons. Clan names and tags go through `TextService:FilterStringAsync`. No user-uploaded images. |
| Data | ProfileStore holds game data only (XP, Glory, items, receipts). No personal data and no third-party analytics SDK; analytics use `AnalyticsService` only. |
| Maturity label | Fill in the Maturity & Compliance Questionnaire honestly. Abstract armies and meteors with no blood should land at Minimal or Mild, which makes us playable on Roblox Kids and Select accounts too. That's another reason every rule above assumes some players are under 13. |
| Owner requirements | DevEx needs the owner 13+ with tax forms. Rewarded video and `EditableImage` (the map) need an ID-verified owner. Adding a card to Ads Manager needs 18+ (otherwise convert Robux to ad credits). |

## 11. Implementation plan: Phase 4 and 5 task cards

Paste one per Claude Code session, in order. Same format as `docs/MAPS.md`.

**Architecture notes for every card**

- Progression rules are pure Luau in `src/shared/Sim/` with Lune tests. Services only call them.
- Earn rates, the level curve, quest rewards and season tiers go in `Config.Progression` and `Config.Season`. Item data and Robux and Glory prices go in a new `src/shared/Catalogue.luau` (cosmetic data, not balance).
- New types in `Types.luau`: `PlayerProfile`, `CatalogueItem`, `Rarity`, `CosmeticSlot`, `QuestDef`, `QuestState`, `MatchReward`, `SeasonState`. `MatchState` doesn't change; cosmetics travel next to it in `Snapshot`.
- Dates come in as a UTC day number (`math.floor(os.time() / 86400)`) passed from the service, so Sim never reads the clock.

```text
## Task: Progression rules
Phase: 4   Service: Sim/Progression
Goal: the server can turn a finished match into XP, Glory, level and rank for each player.
Read first: docs/MONETIZATION.md sections 4.1, 5.1–5.3; src/shared/Types.luau; src/shared/Config.luau
Do:
- Config.Progression: every number in MONETIZATION 4.1 and 5.1 (match XP and Glory, caps, VIP multiplier, AFK window), the curve 300 + 60·(L−1), cap 100, rank names
- Sim/Progression.luau: matchReward(result, playerStats, isVip, isFirstMatchToday, rulesAreStandard) -> MatchReward; xpToNext(level); levelFor(totalXp); rankFor(level)
- Per-player match stats in MatchService: provinces captured, battles won, rose as Primordial, powers used, last command time, minutes played
- Lune tests: level 100 needs 320,760 XP; level 2 at 300; the average match pays ~245 XP and ~49 Glory; caps hold; leaving early prorates; AFK pays 0; private custom rules pay 50%
Don't: touch Roblox APIs in Sim; save anything (that's PlayerDataService)
Done when: lune run tests/run passes; stylua, selene and rojo build pass
```

```text
## Task: PlayerDataService with ProfileStore
Phase: 4   Service: PlayerDataService
Goal: XP, Glory, owned items, equipped cosmetics, quests and receipts persist across sessions safely.
Read first: docs/MONETIZATION.md sections 4, 5, 10 (Data); DESIGN.md "Technical architecture"; CLAUDE.md (ProfileStore arrives in Phase 4)
Do:
- Add ProfileStore (the one allowed package) under ServerScriptService/Server/Packages
- PlayerProfile v1: version, xp, level, glory, owned {itemId: true}, equipped {slot: itemId}, quests, loginStep, streak, achievements, season {id, xp, premium, claimed}, receipts {receiptId: timestamp} (keep the last 200), purchaseHistory, settings
- Session lock, autosave, release on leave; kick with a friendly message if the profile can't load
- Migrations table keyed by version
- At Results: call Sim/Progression, apply the reward, send the breakdown to the client
- Results screen: XP bar, Glory gained, level-up and rank-up moments
Don't: save MatchState; trust any client value; grant Robux items here (ShopService does it)
Done when: Studio test with "Enable Studio Access to API Services": play a match, rejoin, XP and Glory are kept; two servers can't load the same profile; build and lint pass
```

```text
## Task: Quests, login calendar and streaks
Phase: 4   Service: Sim/Quests + PlayerDataService
Goal: 3 daily and 3 weekly quests, a login calendar and a play streak, as in MONETIZATION 5.4–5.6.
Read first: docs/MONETIZATION.md 5.4–5.6; src/shared/Sim/Rng.luau
Do:
- Config.Progression.Quests: pool with id, tier, stat, target, reward
- Sim/Quests.luau: dailyFor(userId, day, rng), weeklyFor(userId, week, rng), progress(state, matchStats), reroll(state, rng); keep up to 6 unfinished dailies for 2 days
- Sim/Login.luau: advance the calendar on a play day only; streak with one covered missed day a week
- Quests UI: list, progress bars, claim, 1 free reroll
- RequestQuestReroll and RequestClaim go through CommandRouter
- Lune tests: the same user and day always give the same quests; tiers are 1 easy, 1 medium, 1 hard; progress caps at target; a missed day pauses the calendar
Don't: add quests that need losing, betraying or buying
Done when: tests pass; in Studio a quest completes during a match and pays at Results
```

```text
## Task: Catalogue, ShopService and VIP
Phase: 4   Service: ShopService
Goal: players buy cosmetics with Robux or Glory, buy VIP and the starter pack, and equip items.
Read first: docs/MONETIZATION.md sections 3, 4, 10; Roblox docs for developer products (ProcessReceipt) and passes
Do:
- src/shared/Catalogue.luau: itemId, slot, rarity, name, robuxProductId?, glory?, art id, season?
- ProcessReceipt: look up the receipt id in profile.receipts first (idempotent); grant; save; return PurchaseGranted only after saving, NotProcessedYet on failure
- VIP pass: UserOwnsGamePassAsync on join, PromptGamePassPurchaseFinished
- Glory purchases: RequestBuy(itemId) through CommandRouter checks the price and balance on the server
- RequestEquip(slot, itemId) checks ownership
- Shop UI: core, daily, weekly and offers tabs; Robux prices from MarketplaceService (never hard-coded); bundles show the real sum
- Purchase History screen from the receipt ledger
- Starter pack shown once per session at most, after match 2, no timer
Don't: sell Glory or anything in-match; show prompts during a match; add trading or gifting
Done when: in Studio a test purchase grants once even if ProcessReceipt fires twice; VIP shows its tag; Glory purchase fails cleanly with too little Glory; build and lint pass
```

```text
## Task: Cosmetics in the match
Phase: 4   Service: Replicator + MapRenderer + UI
Goal: everyone sees each nation's flag, border style, shade set, army token, emotes, power effects and victory animation.
Read first: docs/MONETIZATION.md 1 (rule 5), 3.2; DESIGN.md "Map rendering"; docs/MAPS.md "Art direction"
Do:
- Snapshot carries nationCosmetics {nationId: equipped} next to MatchState; bots use defaults
- PixelArt: border patterns and shade sets stay inside the nation's hue (test: shade hue within ±8° of the assigned colour)
- RequestEmote(emoteId) through CommandRouter, 1 per 10 s, owned only
- Power effects keep the same area, timing and sound cue as the default
- Theme vote: the winning map uses the theme equipped by most voters for it; a setting forces the default theme
Don't: let any cosmetic change a nation's colour, hide armies, or change timings
Done when: 2-player Studio test shows each player's flag, token and emote to the other; build and lint pass
```

```text
## Task: Private server settings
Phase: 4   Service: MatchService + UI
Goal: private server owners pick the map, theme, length, peace, bots, powers, disasters and team locks.
Read first: docs/MONETIZATION.md 3.4; DESIGN.md "Match structure"
Do:
- Detect a private server (game.PrivateServerId ~= "" and PrivateServerOwnerId); owner-only settings sheet in the Lobby
- Config holds allowed values; Sim reads match settings from MatchState setup, not globals
- Rewards: standard rules and 4+ humans = full; otherwise 50% and no "win" quests or leaderboard points
- Optional: Roblox Plus prompt on this screen (decision 5 in MONETIZATION 12)
Don't: change the private server price after launch
Done when: in a Studio private-server simulation the owner changes the length to 15 min and the match ends at 15:00
```

```text
## Task: Analytics
Phase: 5   Service: TelemetryService
Goal: every event in docs/LAUNCH.md "Analytics events" is logged, so the weekly balance patch and the KPIs come from data.
Read first: docs/LAUNCH.md "Analytics events"; Roblox AnalyticsService docs (limits)
Do:
- Services/TelemetryService.luau wraps AnalyticsService (named so it doesn't clash with the Roblox service); one function per event; drops events past a per-minute budget of 120 + 20·CCU
- Onboarding funnel, Shop, SeasonPass, StarterPack and MatchFlow funnels; Glory economy events; AccountLevel and SeasonTier progression events; the custom events
- Keep under 100 custom event names and 3 custom fields
Don't: log user names or any personal data; add a third-party SDK
Done when: "View events" in Creator Hub shows each event from a Studio test session; build and lint pass
```

```text
## Task: Season pass
Phase: 5   Service: Sim/Season + SeasonService
Goal: 8-week seasons with 50 tiers, free and premium tracks, as in MONETIZATION 6.
Read first: docs/MONETIZATION.md 6; Catalogue.luau
Do:
- Config.Season: id, start and end day, 1,200 XP per tier, 50 tiers, bonus tier 2,400 XP -> 100 Glory, reward list
- Sim/Season.luau: tierFor(seasonXp); claimable(state); claim(state, tier, track)
- Premium pass and pass bundle as developer products through ShopService; buying late unlocks all earned premium rewards
- Season UI with both tracks; a pass-exclusive label
- Lune tests: tier math, no double claims, bundle adds 10 tiers once
Don't: sell single tier skips
Done when: tests pass; Studio test buys the pass and claims tiers 1–3
```

```text
## Task: Rotating shop
Phase: 5   Service: Sim/ShopRotation
Goal: 4 daily and 2 weekly slots from a fixed schedule, with every item back within 60 days.
Read first: docs/MONETIZATION.md 3.8
Do:
- Sim/ShopRotation.luau: rotation(day, catalogue, rng) -> slots, seeded by day so every server agrees
- Lune test: over 365 days every rotating item appears at least once in every 60-day window; no item twice in one day
Don't: personalise or randomise per player
Done when: tests pass; two Studio servers show the same daily shop
```

```text
## Task: Leaderboards and achievements
Phase: 5   Service: LeaderboardService + PlayerDataService
Goal: weekly conquest, friends and global level boards; 30 achievements.
Read first: docs/MONETIZATION.md 5.6, 7.3
Do:
- OrderedDataStore per week key for conquest points (public matches with 4+ humans); global level board
- Friends board from the weekly store, filtered by friends in the server's cache
- Sim/Achievements.luau: check(profileStats, matchStats) -> newly earned ids; Lune tests
- Top 100 weekly get the Warlord frame for the next week
Don't: count private custom-rules matches
Done when: tests pass; a Studio match updates the weekly board
```

```text
## Task: Rewarded video and notifications
Phase: 5   Service: ShopService + UI
Goal: the quest reroll ad and opt-in season notifications.
Read first: docs/MONETIZATION.md 3.7, 7.6, 10 (Ads)
Do:
- "Quest reroll" developer product (10 Robux); rewarded video reward from it; max 2 a day; GetAdAvailabilityNowAsync before showing the button
- Experience notifications opt-in prompt after the first finished match (CanPromptOptInAsync first)
Don't: show ads anywhere else, or to users the API reports as ineligible
Done when: Studio shows the button only when an ad is available; build and lint pass
```

## 12. Decisions for the owner

| # | Decision | Recommendation |
| --- | --- | --- |
| 1 | One earned-only soft currency (Glory) next to Robux, never sold | Yes |
| 2 | VIP at 249 Robux instead of DESIGN.md's 199 | Yes, then let managed pricing test it |
| 3 | Nation colour stays assigned; "palette" becomes shade sets within that colour | Yes (protects pillar 1) |
| 4 | Season pass: 8 weeks, 50 tiers, 299 Robux, no single tier skips | Yes |
| 5 | Roblox Plus prompt on the private-server screen (250 Robux a month for 3 months per new subscriber) | Yes, only on that screen |
| 6 | No experience subscription at launch; revisit at month 5 | Yes |
| 7 | Theme vote: the winning map uses the most popular equipped theme among its voters | Yes, with an opt-out setting |
| 8 | Rewarded video only for quest rerolls | Yes |
| 9 | Titles are earned, never sold | Yes |
| 10 | Clans at month 4, ranked beta at month 5–6 behind a 1,500 peak CCU gate | Yes |

## 13. Sources

Roblox (official):

- DevEx rates and eligibility: <https://create.roblox.com/docs/production/monetization/developer-exchange>
- US 18+ DevEx rate: <https://create.roblox.com/docs/production/monetization/18-plus-devex-rate>, <https://about.roblox.com/newsroom/2026/04/roblox-fuels-high-fidelity-games-over-18-players-increases-qualifying-devex-rate-42>
- Developer products: <https://create.roblox.com/docs/production/monetization/developer-products>
- Game passes: <https://create.roblox.com/docs/production/monetization/game-passes>
- Private servers: <https://create.roblox.com/docs/production/monetization/private-servers>
- Roblox Plus: <https://about.roblox.com/en-au/newsroom/2026/04/introducing-roblox-plus-subscription>
- Experience subscriptions: <https://create.roblox.com/docs/production/monetization/subscriptions>
- Managed pricing: <https://create.roblox.com/docs/production/monetization/managed-pricing>; regional pricing launch: <https://about.roblox.com/newsroom/2025/04/roblox-launches-regional-pricing-for-in-experience-items>
- Engagement-based (Premium) payouts, deprecated: <https://create.roblox.com/docs/production/monetization/engagement-based-payouts>
- Creator Rewards: <https://create.roblox.com/docs/creator-rewards>, <https://devforum.roblox.com/t/introducing-creator-rewards-earn-more-by-growing-the-community/3777628>
- Creator Affiliate, deprecated: <https://create.roblox.com/docs/affiliates>
- Rewarded video ads: <https://create.roblox.com/docs/production/promotion/rewarded-video-ads>, <https://create.roblox.com/docs/production/promotion/ad-integrations>, <https://devforum.roblox.com/t/more-creators-can-now-use-rewarded-video-ads/3838678>
- Paid random items: <https://create.roblox.com/docs/production/monetization/paid-random-items>
- Age checks and chat: <https://about.roblox.com/newsroom/2025/11/roblox-requires-age-checks-limits-minor-and-adult-chat>
- Content maturity labels: <https://create.roblox.com/docs/production/promotion/content-maturity>
- Parental controls (help centre; seen in search, the page blocked our fetch): <https://en.help.roblox.com/hc/articles/30428367965460>
- Ads Manager: <https://create.roblox.com/docs/production/promotion/ads-manager>
- AnalyticsService: <https://create.roblox.com/docs/reference/engine/classes/AnalyticsService>; event types and limits: <https://create.roblox.com/docs/production/analytics/event-types>
- Experience notifications: <https://create.roblox.com/docs/production/promotion/experience-notifications>
- Thumbnails and videos: <https://create.roblox.com/docs/production/publishing/thumbnails>
- Q1 2026 shareholder letter (ad policy): <https://www.sec.gov/Archives/edgar/data/0001315098/000162828026028882/ex991-q12026earningsshar.htm>

Third party:

- GameAnalytics 2026 Roblox benchmark report: <https://www.gameanalytics.com/reports/2026-roblox-report>; summary: <https://gamedevreports.substack.com/p/gameanalytics-key-roblox-and-roblox>
- Brand-integration rules and 2027 revenue share: <https://www.pocketgamer.biz/roblox-to-take-cut-of-in-game-brand-deals-from-2027-under-new-advertising-rules>
- Rewarded video expansion: <https://www.emarketer.com/content/roblox-expands-rewarded-video-tools-creators-advertisers>; EPM estimate (unverified): <https://rolearn.dev/insights/rewarded-video-ads-new-revenue-stream>
- Robux store prices (unverified): <https://rowatcher.com/news/robux-prices-bundles-2026-guide>
- Genre CCU (Rotrends): <https://www.rotrends.com/game/10768172922/RoFront-World-PvP>, <https://www.rotrends.com/game/4983034985/Conquer-The-World-WW2>

**Could not verify:** the 70% creator share on passes, products and private servers (not stated on the pages we read); US Robux store prices; Ads Manager CPP; rewarded video EPM; genre-level retention, conversion, ARPDAU and session benchmarks; the share of our DAU who are Roblox Active Spenders; exact parental-control settings (help page blocked).

## Appendix: proposed DESIGN.md changes

Replace the whole "Monetization and retention" section with:

```markdown
## Monetization and retention

Sell looks, convenience and private play, never strength. Full plan: `docs/MONETIZATION.md`; launch and analytics: `docs/LAUNCH.md`.

| Product | Type | Price (Robux) |
| --- | --- | --- |
| Cosmetics by rarity: Common / Rare / Epic / Legendary | Shop item | 49 / 99 / 149 / 249 (Glory 500 / 1,200 / 2,500 / —) |
| Nation skins: flag, border style, shade set (within your assigned colour), army token; matched sets | Shop item | 49–249; sets 199 / 299 |
| Map themes: re-skins of the maps (e.g. Ember Eldmoor); the winning map uses its voters' most-equipped theme | Shop item | 99 |
| Primordial-power effects: meteor style, plague colour | Shop item | 49–149 |
| Capital emotes | Shop item | 25–49 |
| Victory animations, nameplate frames | Shop item | 49–249 |
| VIP: VIP flag set, gold frame, chat tag, +25% match XP and Glory, +1 quest reroll | Game pass | 249 |
| Private servers: map, theme, length, peace, bots, powers, disasters | Private server | 100 per month |
| Season pass: 8 weeks, 50 tiers, free and premium tracks | Developer product | 299 (499 with 10 tiers) |
| Starter pack (once per account, no timer) | Developer product | 149 |

**Glory** is the only soft currency. It is earned by playing (about 49 per match plus quests) and is never sold.

**Never sell:** gold, regiments, manpower, Primordial-power charges, combat bonuses, start positions, titles, Glory or anything else that changes a match. No paid random items (loot boxes), no countdown offers, no prompts during a match, no single tier skips.

**Retention:** account XP (300 + 60 × (level − 1) per level, cap 100) and ten ranks; 3 daily and 3 weekly quests; a login calendar that pauses instead of resetting; achievements; the server votes on the next map after Results; weekly, friends and global leaderboards; parties of up to 3 start next to each other; clans and a ranked mode after launch.
```

Replace Phase 4's shop and player-data lines and add these lines to Phase 4 and Phase 5:

```markdown
### Phase 4: Polish and shop

- [ ] Progression rules in Sim: match XP and Glory, level curve, ranks
- [ ] `PlayerDataService` (ProfileStore): XP, Glory, items, receipts; Results screen rewards
- [ ] Daily and weekly quests, login calendar, play streak
- [ ] Shop: catalogue, Robux and Glory purchases, VIP pass, starter pack, purchase history
- [ ] Cosmetics shown in the match: flags, borders, tokens, emotes, power effects, victory animations, theme vote
- [ ] Private server settings

### Phase 5: Soft launch

- [ ] Analytics events (`docs/LAUNCH.md`): match length, quit time, phase reached, win rate by start position, funnels, economy
- [ ] Season pass (8 weeks, 50 tiers)
- [ ] Rotating shop
- [ ] Weekly, friends and global leaderboards; achievements
- [ ] Rewarded video quest reroll; experience notifications
- [ ] Soft-launch gates met (`docs/LAUNCH.md`) before Season 1
```

Add to "Open questions → Still open": "Ranked mode: beta in month 5–6 if peak CCU ≥ 1,500 (`docs/MONETIZATION.md` 7.5)."
