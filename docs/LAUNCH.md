# Launch and growth plan

How Total World Chaos goes from a finished Phase 4 to a live game: soft-launch gates, the store page, paid ads, creators, update cadence and the analytics events. Prices, progression, revenue and the task cards are in `docs/MONETIZATION.md`. Sources are listed at the end of that doc. Figures marked **unverified** come from third parties only.

## 1. Stages

| Stage | When | Who plays | Goal | Exit |
| --- | --- | --- | --- | --- |
| Closed playtest | End of Phase 4 | Friends and 10 new testers | Gate 4 in DESIGN.md: 10 testers finish the tutorial without help | Gate 4 passed |
| Soft launch | 6 weeks before Season 1 | Public but not promoted, plus small ad tests | Read retention, session and funnel data on 2,000+ new players per test | Section 2 gates |
| Launch | Week 1 of Season 1 | Everyone | Fill servers, start the live-ops calendar | — |

Roblox experiences are public worldwide once published. Here "soft launch" means published without promotion, with small ad buys to bring in measurable groups of new players.

## 2. Soft-launch metrics and gates

Read every metric on groups of at least 2,000 new players. At an assumed $0.25 cost per play (unverified), that's about $500 of ads per read.

| Metric | Gate to start Season 1 and scale ads | Stop and fix if below | Benchmark (GameAnalytics, 1M+ MAU games) |
| --- | ---: | ---: | --- |
| Tutorial completion | ≥ 70% | 50% | — |
| D1 retention | ≥ 15% (12% acceptable with a fix plan) | 10% | median 10.3%, p99 22.2% |
| D7 retention | ≥ 4% (3% acceptable) | 2% | median 1.6%, p99 9.1% |
| New players who start a 2nd match | ≥ 50% | 35% | — |
| Match completion (stay to Results) | ≥ 70% | 55% | — |
| Average session | ≥ 30 min | 20 min | median 9.8, p99 21.1 |
| Human share of nations in public matches at peak hour | ≥ 40% | 25% | — |
| Win rate of any single start nation (fair = 10%) | ≤ 15% on every map | 20% | — |
| Server tick time | < 5 ms (DESIGN budget) | 10 ms | — |
| Phone frame rate on a low-end Android | ≥ 30 fps | 20 fps | — |
| Monthly payer conversion | ≥ 1% of MAU (directional) | — | 3.8% of players pay in a year, all games |

**What to fix first when a gate fails:**

| Failing metric | Likely cause | First fix |
| --- | --- | --- |
| Tutorial completion | Too many prompts, unclear taps | Cut a prompt, bigger arrows, test in Studio's phone emulator |
| D1 | First match not fun, or lost too early | Easier bots in the first match, faster Peace-phase expansion |
| 2nd match start | Results screen doesn't pull into the next match | "Stay for next match" selected by default, quest progress shown on Results |
| Match completion | Eliminated players leave | More Primordial XP, faster Primordial charges, clearer power UI |
| Average session | Quitting mid-match | Check the `MatchFlow` funnel for the phase where people leave |

## 3. Store page

### Name and description

- **Name:** Total World Chaos. At a season start add a short tag, for example "Total World Chaos [S1]", and drop it after two weeks.
- **Genre:** Strategy.
- **Description** (plain, keyword-rich, under 600 characters):

> Conquer the world in 25 minutes. 10 nations, one map, total chaos.
> Expand your borders, build an army, make allies and declare war on Earth, Eldmoor or Skyshards.
> Knocked out? Rise as a Primordial and rain meteors, plague and rebels on the nation that beat you.
> Play with friends, climb the weekly leaderboard and unlock flags, army tokens and map themes by playing.
> No pay-to-win: everything for sale is cosmetic.

### Icon (512×512, readable at about 150 px)

- A chunky pixel-art corner of the map: three nation colours (crimson, navy, gold) with bold borders, one castle.
- A flaming meteor crossing from top right toward the castle.
- No text: it can't be read at 150 px. High contrast against both light and dark backgrounds.
- Test 3 icons in the first soft-launch ad cell and keep the one with the best click-through.

### Thumbnails (16:9, 1920×1080, up to 10 images or videos)

Keep key art out of the bottom 15%, where the player count is drawn. Use thumbnail personalization (2–5 active thumbnails) so Roblox tests them for us.

| # | Shot | Text overlay (max 4 words) |
| --- | --- | --- |
| 1 | Earth mid-war: big crimson empire with the coalition crown, armies clashing in Europe | "Conquer the world" |
| 2 | Primordial meteor hitting an army, screen-shake frame | "Rise as a Primordial" |
| 3 | Three allied nations (green diplomacy view) surrounding a rival | "Ally with friends" |
| 4 | The three maps side by side (the vote cards) | "3 worlds" |
| 5 | Season 1 rewards: Titan token, Phoenix meteor, Ember Eldmoor | "Season 1 is live" |

### Trailer brief (30 s, real gameplay only)

Roblox only accepts authentic gameplay video and allows 3 video uploads a month, so get it right before uploading. Cut a 16:9 version for the store page and a 9:16 version for TikTok and YouTube Shorts.

| Time | Shot | Audio |
| --- | --- | --- |
| 0–3 s | Map vote card flips to Earth; lobby counts down | Drum hit |
| 3–8 s | Fast-forward Peace phase: borders spread across the map | Rising music |
| 8–14 s | War declared toast; two armies collide; province flips | Battle hits |
| 14–20 s | Player eliminated; screen turns to Primordial view; meteor strikes | Bass drop |
| 20–26 s | Cataclysm: disaster hits; alliance takes 65%; victory animation | Peak |
| 26–30 s | Logo, "Free to play. Everything for sale is cosmetic." | Sting |

### Maturity, localization and links

- Fill in the Maturity & Compliance Questionnaire honestly (expected: Minimal or Mild). It's also required for rewarded video.
- Turn on Roblox's automatic translation. After soft launch, hand-check the top 5 languages by players in our analytics.
- Link a Roblox community group for update news. Add Discord only when there are moderators; it's 13+, and links must respect `PolicyService` for players who aren't allowed external links.

## 4. Sponsored ads (Ads Manager)

Ads Manager runs Sponsored tiles on Home and in search with auto-bidding on cost per play (CPP). Roblox doesn't publish CPP; a third-party estimate for competitive genres is **$0.15–0.40 per play (unverified)**. The math below uses $0.25.

**Paid plays won't pay for themselves directly.** A new player's 30-day value in the base case is about $0.01:

- expected active days in the first 30 ≈ 1 + 6 days × ~8% + 23 days × ~2.5% ≈ 2.1 days (from D1 15%, D7 4%, D30 1.5%)
- × net ARPDAU $0.0039 ≈ **$0.008 per new player**, against $0.25 per play.

Ads are for **seeding**: enough players to fill 12-player lobbies with humans, and the engagement signals that drive Roblox's own recommendations. So spend only when the soft-launch gates are met, and judge ads by organic growth, not direct payback.

| Phase | Budget | Plan | Keep going only if |
| --- | ---: | --- | --- |
| Soft launch, weeks −5 to −2 | $1,500 | 3 cells of $500: (a) icon/thumbnail test, (b) 13–17 phones, strategy genre, (c) 18+ all devices | Each cell gives 2,000+ plays and a clean retention read |
| Launch week | $3,000 | Best cell from soft launch, Season 1 thumbnail, US/UK/CA/AU first, then broaden | D1 of ad players ≥ 12% |
| Months 2–6 | $1,000–3,000 a month | Burst on season and map launches only (weeks 1, 9, 17), New Players and Lapsed Players audiences | Organic plays in the week after a burst ≥ 1.5× the week before |
| **Total, first 6 months** | **≤ $12,000** | | |

Notes:

- Adding a card to Ads Manager needs an 18+ account. Otherwise convert earned Robux into ad credits; the conversion is permanent.
- Rowatcher warns that budgets under about $500 give noisy analytics, which is why each cell is $500.
- The Lapsed Players audience needs 20,000+ lapsed players and Recent Players needs 10,000+, so those audiences open up only after launch.

## 5. Creators and influencers

Roblox's Creator Affiliate program is gone, but **Creator Rewards Audience Expansion** pays us 35% of the first $100 that a new or returning Roblox user spends in their first 60 days, if they arrive through our **Share Link** (or direct link or search) and we average 100+ DAU. Give every creator their own Share Link: it tracks clicks, sign-ups and spend in Analytics → Share Links, and it earns more than a paid ad play.

| Tier | Audience | Offer | When |
| --- | --- | --- | --- |
| Micro | 1k–50k subscribers | Early access, a free private server for their community, a creator code that gives viewers a free Common flag once | Soft launch onwards |
| Mid | 50k–500k | A paid video or stream (market rates **unverified**; budget $3,000 for 3–6 videos in months 1–3) plus the micro offer | After the D7 gate passes |
| Large | 500k+ | Only with proof of retention; a custom "creator" flag design they choose (free for their viewers via code, never sold) | Month 3+, if D7 ≥ 4% |

Rules:

- Work only with adult creators, or through a guardian or agency for minors.
- Paid videos must be labelled as ads (#ad and the platform's paid-promotion setting).
- Never ask creators to promise "free Robux" or anything we don't sell.
- Creator codes give cosmetics only, once per account, never Glory.

**Best clip moments to pitch:** a Primordial taking revenge with a meteor, a last-second alliance victory, an underdog comeback, 1 player against 9 Hard bots, and Earth geography memes. Make the Results screen screenshot-friendly: a big map thumbnail, placement, provinces and battles.

**Community events:** from week 15, a monthly "Creator Cup" in private servers, hosted by a creator. Finalists win a cup frame, never Robux.

## 6. Update cadence

| Rhythm | What | Day and time |
| --- | --- | --- |
| Weekly | Bug fixes, quest pool and shop rotation checks | Tuesday 15:00 UTC (quiet hours) |
| Every 2–3 weeks | Balance patch from start-position win rates (DESIGN Phase 5) | Tuesday 15:00 UTC |
| Every 4 weeks | Content drop: new cosmetics, an event, a feature | Friday 17:00 UTC (after school in Europe, lunch in the US) |
| Every 8 weeks | New season | Friday 17:00 UTC |
| Every 16 weeks | New map | With a season start |

- Announce each update in the community group and on the loading screen.
- Use `MessagingService` to warn live servers 5 minutes before an update restart. Never restart in the middle of a match: let matches finish, and send new players to new servers.

## 7. Analytics events

Everything goes through `AnalyticsService`, wrapped in `Services/TelemetryService.luau`. Platform limits: 100 custom event names, 10 funnels (100 steps each), 10 economy currencies, 3 custom fields per event (values past 8,000 combinations become "Other"), and 120 + 20 × CCU requests per minute. Charts take about 24 hours to appear, and data is kept for 90 days.

Retention, session length, playtime and Robux revenue come from Roblox's built-in dashboards, so we don't log them.

How it is built:

- `Shared/Sim/Telemetry.luau` holds the plan below as data and builds every payload (pure, tested); `TelemetryService` finds the Player, keeps the budget and calls `AnalyticsService`. One function per event.
- AnalyticsService only accepts events from servers of a **published** game, never from clients or Studio. In Studio the Workspace attribute `TelemetryLog` prints each event to the Output (`docs/STUDIO.md`).
- Budget: each server sends at most 120 + 20 × its players per minute and drops the rest (the Output says how many).
- Every call needs a Player. Match-wide events (`nation_start`, `match_end`, `match_win`, and `player_result` for bot nations) go out for the player in the server with the lowest userId.
- No names, chat or other personal data: userIds only where AnalyticsService needs the Player. Custom field values are strings (map ids, nation slots, buckets, item ids); match minutes have one decimal.
- UI-only steps (`lobby_loaded`, `shop_opened`, `item_viewed`, `offer_opened`) come from the client through `RequestTelemetry`, checked and rate-limited by `CommandRouter`. They change nothing in the game.

### Onboarding funnel (`LogOnboardingFunnelStepEvent`)

| Step | Name |
| ---: | --- |
| 1 | `joined` |
| 2 | `lobby_loaded` |
| 3 | `map_voted` |
| 4 | `nation_picked` |
| 5 | `first_neutral_captured` |
| 6 | `first_recruit` |
| 7 | `first_siege_done` |
| 8 | `first_ally` |
| 9 | `first_war` |
| 10 | `first_power_used` |
| 11 | `first_match_finished` |
| 12 | `second_match_started` |

Steps 5–10 are the tutorial prompts in DESIGN.md, logged as each one is done. Steps are only logged for players with fewer than 2 finished matches. `lobby_loaded` is the client saying its screens are built. Roblox counts a skipped step as done when a later one arrives, so a skipped tutorial also logs `tutorial_skipped` (custom events below). `TutorialService` still prints `[tutorial] … started`, `finished in N s` and `skipped at prompt N` in the Output.

### Funnels (`LogFunnelStepEvent`, 6 of the 10 allowed)

| Funnel | Session id | Steps |
| --- | --- | --- |
| `MatchFlow` | matchId + userId | 1 `lobby`, 2 `pick`, 3 `peace`, 4 `war`, 5 `cataclysm`, 6 `results`, 7 `next_match_started` |
| `Shop` | one per shop open | 1 `shop_opened`, 2 `item_viewed`, 3 `purchase_prompted`, 4 `purchase_completed` |
| `StarterPack` | userId | 1 `offer_shown`, 2 `offer_opened`, 3 `purchase_prompted`, 4 `purchase_completed` |
| `SeasonPass` | userId + seasonId | 1 `pass_viewed`, 2 `purchase_prompted`, 3 `purchase_completed` |
| `PrivateServer` | private server id | 1 `settings_opened`, 2 `custom_match_started` |
| `Party` | partyId | 1 `invite_sent`, 2 `invite_accepted`, 3 `party_match_started` |

`MatchFlow` answers "phase reached" from the DESIGN.md Phase 5 list. Each step is logged once per player and match: `lobby` when the vote opens or they join it, `pick` when they have a nation (drafted, or seated on joining), `peace`/`war`/`cataclysm`/`results` when they are in that phase with a nation or a Primordial, and `next_match_started` on the old session when they get a nation in the following match.

- `Shop`: `shop_opened` and `item_viewed` (another tab or page, once per session) come from the client; `purchase_prompted` is a buy the server accepted, `purchase_completed` a granted purchase (a Glory buy logs both at once).
- `StarterPack`: `offer_shown` when the server sends the pop-up, `offer_opened` when the client shows it.
- `SeasonPass` is ready (`TelemetryService.seasonPass`) for the season pass task. `PrivateServer` and `Party` wait for those features.

### Economy (`LogEconomyEvent`)

| Currency | Flow | transactionType (`Enum.AnalyticsEconomyTransactionType`) | itemSku |
| --- | --- | --- | --- |
| `Glory` | Source | Gameplay | `match_reward`, `quest_daily`, `quest_weekly`, `level_up`, `achievement`, `season_tier` |
| `Glory` | Source | TimedReward | `login_calendar` |
| `Glory` | Sink | Shop | catalogue item id |
| `Glory` | Sink | Gameplay | `quest_reroll`, `clan_create` |
| `Robux` | Sink | IAP | catalogue offer or item id (`vip`, `starter`, `set_royal`, item id; later `season_pass_s1`) |

Always pass the ending balance (Robux: 0, since games can't read a player's Robux balance). `match_reward` and `level_up` (level-ups and rank-ups) come from every match reward; `TelemetryService.glory` is ready for the quest, login and reroll rows. Add up to 3 custom fields: `level_bucket` (1–9, 10–29, 30+), `is_vip`, `is_payer`.

### Progression (`LogProgressionEvent` / `LogProgressionCompleteEvent`)

| Path | Level | Level name |
| --- | --- | --- |
| `AccountLevel` | 1–100 | Rank name (`Complete` for every level passed, `Start` for the new one; `Start` 1 on a new account) |
| `SeasonTier` | 1–50 | `S1` … |

### Custom events (`LogCustomEvent`)

| Event | Value | Field 1 | Field 2 | Field 3 | Answers |
| --- | --- | --- | --- | --- | --- |
| `nation_start` | 1 | map | start_nation (1–10) | controller (human, bot) | Starts per position |
| `match_win` | 1 | map | start_nation | win_type (domination, alliance, score) | **Win rate by start position** (÷ `nation_start`) |
| `match_end` | match minutes | map | win_type | humans (1–3, 4–6, 7–12) | **Match length** |
| `player_quit` | minute of the match | map | phase | was_primordial | **Quit time** |
| `player_eliminated` | minute of the match | map | start_nation | phase | Snowballing |
| `player_result` | placement | map | start_nation | controller | Placement spread |
| `primordial_power_used` | 1 | power | map | user_kind (living, primordial) | Power balance |
| `bot_replaced_leaver` | minute of the match | map | phase | — | Leaver rate |
| `afk_flagged` | 1 | map | phase | — | Anti-AFK |
| `map_vote` | 1 | map | round (lobby, next) | theme | Map popularity |
| `quest_completed` | 1 | quest_id | tier | — | Quest difficulty |
| `quest_rerolled` | 1 | source (free, vip, ad, glory) | — | — | Reroll demand |
| `ad_rewarded` | 1 | placement | result (completed, failed) | — | Ad health |
| `emote_used` | 1 | emote_id | — | — | Cosmetic use |
| `purchase_failed` | 1 | product | reason | — | Shop bugs |
| `notification_opt_in` | 1 | result (shown, ineligible) | — | — | Notification reach |
| `tutorial_skipped` | prompt reached (1–6) | prompt name | — | — | Tutorial completion |

That's 17 custom event names out of 100, so there's room for events and new modes. `nation_start` is logged a minute into the match (or at Results, if sooner), so late joiners count as human; `player_result` is logged for every nation. `quest_rerolled` is logged for every reroll with what paid for it (a Glory reroll also logs the `quest_reroll` Glory sink), `ad_rewarded` for every rewarded video and `notification_opt_in` for the notification prompt; `quest_completed` is ready for the quest claim. Roblox doesn't tell the game whether the player accepted the notification prompt, so `notification_opt_in` logs `shown` (the prompt opened) or `ineligible` (Roblox said not to ask); the opt-in count is on the Creator Dashboard (experience notifications analytics, "Opted-in Users").

**Weekly review (every Monday, 30 minutes):**

1. D1 and D7 of last week's new players.
2. The `MatchFlow` drop-off by phase.
3. Win rate by start nation per map: anything above 15% goes into the next balance patch.
4. Shop funnel conversion.
5. The Glory balance median.
6. Payer conversion and ARPPU against the KPI table in `docs/MONETIZATION.md`.

## 8. Launch checklist

- [ ] Soft-launch gates (section 2) met
- [ ] Maturity questionnaire done; owner ID-verified (needed for rewarded video and `EditableImage`)
- [ ] Managed pricing on for every pass and product; no hard-coded Robux prices in the UI
- [ ] Private server price set once (100 Robux)
- [ ] `ProcessReceipt` idempotency tested: a duplicate receipt grants once
- [ ] Purchase History screen live
- [ ] Icon, 5 thumbnails and the trailer uploaded; thumbnail personalization on
- [ ] Share Links made for every creator
- [ ] Season 1 content complete (50 tiers, about 80 shop items)
- [ ] Weekly review dashboard bookmarked
