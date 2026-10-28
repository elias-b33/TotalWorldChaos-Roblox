# How conquering works

The complete math of the current rules, read from the code (`src/shared/Sim/`, `src/shared/Config.luau`), and the numbers a designer needs to tune them. `docs/DESIGN.md` is the spec; this document says what the code actually does with it and what that means in a match.

Every number below comes from `Config.luau` as of this document or from one of the scripts in `tools/balance/`. The scripts call the real Sim modules, so after a Config change you rerun them and the numbers follow.

| Script | What it produces |
| --- | --- |
| `lune run tools/balance/maps` | Map facts: provinces, mountains, neutral land, garrisons (section 1) |
| `lune run tools/balance/battles` | Monte-Carlo battles through `Sim/Battle`: win chance and losses vs strength ratio; writes `tools/balance/data/battles.csv` (section 5) |
| `lune run tools/balance/conquest` | Time and cost to take a neutral province, through `Sim/Tick` (section 7) |
| `lune run tools/balance/catchup` | Overextension by size, where the thresholds sit, break-even ratios; writes `data/catchup.csv` (section 9) |
| `lune run tools/balance/expansion` | Whole matches with a greedy planner: Peace income, best-case domination, free-for-all; writes `data/expansion_*.csv` (sections 10–12). About 3 minutes (`MAP=earth` for one map). `SET="Siege.TicksPerDevelopment=20"` runs a what-if (section 14) |
| `lune run tools/harness/tournament` | Bot-only matches (Normal bots, 20 seeds × 3 maps, about 65 s): match length, wars, conquests, leader changes, Primordial powers used, army totals at 15:00 and 25:00 (section 15), wins per start slot against the fair share (section 17: use 200 seeds per map, about 12 min each). Takes `SET="…"` too |
| `python3 tools/balance/charts.py` | The four charts in `docs/images/balance_*.png`, from the CSVs (Pillow; matplotlib isn't installed) |

`tools/balance/Planner.luau` is the greedy player used by `expansion`. It is **not** the bot AI: it sends ordinary commands through `Sim/Commands`, so it obeys every rule, and it plays close to the fastest possible expansion. It never defends on purpose (armies standing in their own provinces still fight), so its matches are faster and bloodier than real ones. The bot tournament is the other bracket: Normal bots defend, keep a reserve and only attack at 1.3× strength, so their matches are slower than real players'. A real match sits between the two.

Time: 1 tick = 1 second = 1 game day. A month is 10 ticks. Peace is 0:00–3:00, War 3:00–20:00, Cataclysm 20:00–25:00.

## 0. The balance pass (what changed)

This document was first written before bots existed; its sections 13 and 14 listed rule problems and recommended Config changes. The balance pass fixed the rule problems, added two rules the first bot soak asked for, and applied the Config values below. All numbers in sections 1–12 are rerun under the new rules.

| Change | Before | After | Why (section) |
| --- | --- | --- | --- |
| Rival besiegers at peace | both stand still forever | the first besieger keeps the siege; the other waits and takes over (from zero) when it leaves | 13.1 |
| Shares (crown, domination, alliance) | % of all provinces | % of the **ownable** provinces (mountains don't count) | 13.2 |
| Retreats | teleport to the nearest owned province | walk there at normal speed; no orders, no fighting, no blocking or besieging on the way (🏳 on the token) | 13.3 |
| Interrupted siege | progress reset at once | progress kept for `Siege.GraceTicks` = 10 s | 13.4 |
| Armies in one province | any number of tokens | a nation's standing armies in one province merge (the lowest id stays) | 15 |
| Bot Primordial powers | never used | Meteor on the biggest army of a nation at war with the bot, not immune | 15 |
| `Army.UpkeepPerRegiment` | 0.5 | **1.5** | late-game army explosion (15), rush (12) |
| `Win.DominationShare` | 0.4 of all | **0.5** of ownable | 12 |
| `Win.AllianceShare` | 0.55 of all | **0.65** of ownable | 15 |
| `Battle.UnderdogBonus` | 0.2 | **0.5** | 14 |
| `Battle.CoalitionBonus` | 0.1 | **0.3** | 14 |
| `Diplomacy.CoalitionThreshold` | 0.25 of all | **0.2** of ownable | 14 |
| `StartManpower` | 5000 | **3000** | 14 |
| `Siege.TicksPerDevelopment` | 10 | 10 (kept) | 14: measured, but it halves bot wars |

**Match length, before → after:**

| Measure | Before | After |
| --- | --- | --- |
| Greedy free-for-all (planner, catch-up on, 15 games): median end | 8:29 | **25:00** (score win) |
| …games past 15:00 / reaching 25:00 | 3 / 0 of 15 | **12 / 8 of 15** (earliest end 11:31) |
| Greedy, catch-up off (same 15 seeds): median end | 8:40 | 14:29 |
| Best case, one greedy nation against nine frozen ones: fastest domination per map | 4:18–5:12 | 5:04–5:30 |
| Bot tournament (60 matches): median end | 25:00 | 25:00 |
| …ended before 25:00 (all by alliance victory) | 4 of 60 (21:05–23:40) | 10 of 60 (15:41–24:54) |
| …provinces taken from nations per match (Earth / Eldmoor / Skyshards) | 57.8 / 45.2 / 53.7 | 55.7 / 50.1 / 41.7 |
| …men in all armies at 25:00 (median, per map) | 484k–652k | **167k–216k** |
| …biggest nation's men at 25:00 | 156k–185k | **39k–54k** |

## 1. The maps

`tools/balance/maps.luau`:

| Map | Provinces (all) | Mountains | Ownable | Start-owned | Neutral | Neutral dev 1/2/3/4/5 | Neutral garrisons (men: count) | Provinces for crown (20%) / domination (50%) | Forest+hills share of land |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Earth | 150 | 11 | 139 | 80 | 59 | 22/28/9/0/0 | 1000: 54, 2000: 5 | 28 / 70 | 52% |
| Eldmoor | 147 | 11 | 136 | 80 | 56 | 13/21/9/13/0 | 1000: 41, 2000: 2, 3000: 13 | 28 / 68 | 51% |
| Skyshards | 131 | 11 | 120 | 80 | 40 | 0/20/10/10/0 | 1000: 20, 2000: 10, 3000: 10 | 24 / 60 | 42% |

Every nation starts with 8 provinces and 17 development. (Rows updated after the start-position pass, section 17; the other sections were measured on the maps before it, with 146 Eldmoor provinces.) The crown, domination and alliance thresholds count only the **ownable** provinces: mountains can never be owned, so they don't count (before the balance pass, 40% of all provinces was really 43–44% of the land a nation could hold).

## 2. Economy

`Sim/Economy.luau`. Paid every 10 ticks (ticks 10, 20, 30, …), to every living nation.

| Flow | Per month |
| --- | --- |
| Gold from a province | development × 1, ×1.5 with a farm |
| Manpower from a province | development × 100, ×1.5 with barracks |
| Capital bonus | +5 gold, only while the nation holds its own capital |
| Overextension | gross gold (provinces + capital) × `CatchUp.overextension(provinces)` (section 9) |
| Upkeep | 1.5 gold per 1,000 men in the field (fractional: a 2,400-man army costs 3.6) |

Net gold = gross gold × overextension − upkeep. Gold can go negative (debt); nothing can be bought until it is positive again. Manpower has no cap and no upkeep.

**A starting nation** earns 17 + 5 = **22 gold and 1,700 manpower a month**, and starts with 100 gold and 3,000 manpower. Doing nothing, it holds 100 + 18 × 22 = **496 gold and 33,600 manpower at 3:00**. That buys 33 regiments, but 33 regiments cost 49.5 gold a month to keep, more than twice a starting income: **upkeep, not manpower, is what limits an army now**. A nation can keep about income ÷ 1.5 regiments (15 at the start, 50 on 75 gold a month) and has to stop recruiting, or run into debt, past that. Overextension cuts gold, so it also cuts the army a big nation can keep.

## 3. Costs and payback

Payback is in months (10 s). "Gold-equivalent" counts 100 manpower as 1 gold, the price ratio of a regiment (10 gold + 1,000 manpower).

| Purchase | Cost | Gain per month | Payback, gold only | Payback, gold-equivalent |
| --- | --- | --- | --- | --- |
| Develop 1 → 2 | 30 | +1 gold, +100 manpower | 30 months (5:00) | 15 months (2:30) |
| Develop 2 → 3 | 60 | +1 gold, +100 manpower | 60 months (10:00) | 30 months (5:00) |
| Develop 3 → 4 | 90 | +1 gold, +100 manpower | 90 months (15:00) | 45 months (7:30) |
| Develop 4 → 5 | 120 | +1 gold, +100 manpower | 120 months (20:00) | 60 months (10:00) |
| Farm on dev d | 50 | +0.5 d gold | 100 / d months (dev 2: 8:20, dev 4: 4:10) | same |
| Barracks on dev d | 40 | +50 d manpower | never in gold | 80 / d months (dev 2: 6:40, dev 4: 3:20) |
| Fort | 60 | none | never | — (defence: section 5; siege ×2: section 6) |
| Regiment | 10 gold + 1,000 manpower | −1.5 gold upkeep | — | upkeep over the 22 minutes of War + Cataclysm: 198 gold, 19.8× its price |
| Neutral province, dev d | ~330–1,400 men lost (section 7) | +d gold, +100 d manpower | | 0.7–14 months |

Develop also adds 5 score per level. In a 25-minute match (150 months) only level 1 → 2 and 2 → 3 pay back in gold before the end, and anything bought after ~10:00 only pays back as score. Taking land is by far the best investment: a neutral province pays back its losses in under 6 months in most cases.

## 4. Movement

`Sim/Movement.luau`, `Sim/Pathing.luau`. An army moves along a breadth-first path (fewest provinces, not fastest) through land it may enter: its own, allied, neutral, and enemy land at war. Never mountains, never land of a nation it is at peace with.

Entering a province takes the ticks of **that province's** terrain: **5 s for plains, 8 s for forest and hills.** An order given before a tick starts counting that tick, so one plains step arrives 5 ticks after the order. Crossing 3 plains provinces takes 15 s; 3 hill provinces, 24 s. Armies in battle don't move, and an army whose way closes (peace, an ally leaving) stops where it is.

After moving, a nation's armies that stand still in the same province (no route, not fighting, not retreating) **merge into one** (the lowest army id keeps the men). There is no split command: to besiege several provinces at once, recruit or send separate armies.

## 5. Battles

`Sim/Battle.luau`, tick step 3. When hostile armies share a province they fight `Rounds` = 3 rounds, one per tick, starting on the tick they meet (movement runs first, so an army fights on its arrival tick).

**Sides.** Defenders are the province owner and its allies if any of them is there; in neutral land, the garrison; otherwise the lowest-numbered army's side. Attackers are every army hostile to the defenders. Nations at peace sharing a province don't fight. Retreating armies take no part.

**Each round**, at the same time:

```text
attacker losses = 0.15 × defender men × defender modifier
defender losses = 0.15 × attacker men × attacker modifier
modifier = max(0.1, 1 + roll + terrain + fort + catch-up)
```

Losses are spread over a side's armies in proportion to their size and rounded to whole men. A battle stops early if a side reaches 0.

| Modifier | Who | Value |
| --- | --- | --- |
| Roll | each side, drawn once per battle, uniform | −0.10 … +0.10 |
| Terrain | defender in forest or hills | +0.25 |
| Fort | defender, if the province owner (or an ally) defends | +0.50 (not neutral garrisons) |
| Underdog | defending side containing an underdog (section 9) | +0.50 |
| Coalition | a nation's side fighting a crowned nation (section 9) | +0.30 |

**After round 3** the side with more men wins (a tie goes to the defender). Every loser army **retreats on foot**: it gets the shortest route (fewest steps, over land it may enter) to the nearest province its owner holds and walks it at normal speed. While retreating it takes no orders, doesn't fight, doesn't block a siege and doesn't besiege; it is an ordinary army again when it arrives (or when its way closes). With no way home, or under 500 men, it is destroyed. Winner armies under 500 men are destroyed too. Neutral garrisons never retreat, so a beaten garrison is always gone. Each winning nation gets +1 battle won (+2 score).

**Why the bonuses matter less than they look.** With equal modifiers m, the sum of both armies shrinks by (1 − 0.15 m) each round and their difference grows by (1 + 0.15 m): after 3 rounds the sum is ×0.614 and the difference ×1.521. So on plains **the larger army wins** unless the rolls flip a near-even fight, and a modifier only moves the break-even point a little, because the defender's bonus only applies to the kills of a shrinking army. The exact break-even ratio (attacker men per defender man to win half the time, `tools/balance/catchup.luau`, matching the Monte-Carlo to 0.001):

| Situation | Defender modifier | Break-even attacker : defender |
| --- | --- | --- |
| Plains | 1.00 | 1.000 |
| Forest/hills | 1.25 | 1.074 |
| Fort | 1.50 | 1.146 |
| Fort + hills | 1.75 | 1.217 |
| Plains, underdog defends | 1.50 | 1.146 |
| Forest/hills, underdog defends | 1.75 | 1.217 |
| Plains, coalition attacks the leader (attacker 1.30) | 1.00 | 0.919 |
| Plains, the leader attacks the coalition (defender 1.30) | 1.30 | 1.088 |
| Fort + hills, underdog defends against the leader | 2.55 | 1.436 |

A +25% terrain bonus is worth 7% more men, a +50% fort (or the underdog bonus) 15%, the +30% coalition bonus 8%. The ±10% roll moves the outcome by about ±3% of the ratio, so **battles are close to deterministic**: from 5% above break-even the attacker always wins.

![Attacker win chance vs. strength ratio](images/balance_battles.png)

Win chance and losses, 2,000 battles per row against a 3,000-man defender (`tools/balance/battles.luau`, full tables with all ratios and the catch-up cases in its output). Losses are the share of each side's men gone afterwards.

| Ratio | Plains: win / att. loss / def. loss | Forest/hills | Fort (= underdog on plains) | Fort + hills |
| --- | --- | --- | --- | --- |
| 0.90 | 0% / 44% / 34% | 0% / 55% / 32% | 0% / 66% / 31% | 0% / 77% / 29% |
| 1.00 | 49% / 39% / 39% | 0% / 48% / 37% | 0% / 58% / 35% | 0% / 68% / 34% |
| 1.10 | 100% / 34% / 43% | 82% / 43% / 42% | 4% / 52% / 40% | 0% / 61% / 38% |
| 1.25 | 100% / 30% / 50% | 100% / 37% / 48% | 100% / 44% / 47% | 87% / 52% / 45% |
| 1.50 | 100% / 23% / 61% | 100% / 29% / 59% | 100% / 35% / 58% | 100% / 41% / 57% |
| 2.00 | 100% / 16% / 91% | 100% / 20% / 88% | 100% / 24% / 85% | 100% / 28% / 83% |

Where defence bonuses really bite is **losses**: at 1.25 : 1 the attacker wins everywhere, but loses 30% of its men on plains and 52% against a fort in the hills. A losing army typically keeps 40–65% of its men and walks home, so one battle rarely destroys anything; at 2 : 1 the defender's remnant falls under 500 men (and is destroyed) only 25–55% of the time.

## 6. Sieges

`Sim/Siege.luau`, tick step 4. An army besieges when it stands still in a neutral province or one whose owner it is at war with, is not in battle, and nothing blocks it. Blockers: a neutral garrison, any army of the owner or its allies, or a battle there. Progress is +1 per tick; at the requirement the province flips at once (the owner changes, buildings and development stay). Army size doesn't matter: one regiment besieges as fast as forty. Retreating armies neither besiege nor block.

**One siege per province.** Whoever started it keeps it while one of its armies (or an ally's) stands there; a besieger at peace with it waits instead of blocking (no deadlock, no fight in Peace), and starts its own siege from zero once the first one is gone. When two arrive on the same tick, the lower army id starts first.

**Grace period.** An interrupted siege (a battle, a defending army walking in, the besieger stepping out) keeps its progress for `Siege.GraceTicks` = 10 s, then resets; a besieger that comes back or wins the battle in time carries on where it stopped. Peace with the owner, or the province changing hands, ends the siege at once. A Divine shield pauses it without the grace clock running.

Required ticks = 10 × development, ×2 with a fort, ×3 for a capital:

| Development | Plain | Fort | Capital | Fort + capital |
| --- | --- | --- | --- | --- |
| 1 | 10 s | 20 s | 30 s | 60 s |
| 2 | 20 s | 40 s | 60 s | 120 s |
| 3 | 30 s | 60 s | 90 s | 180 s |
| 4 | 40 s | 80 s | 120 s | 240 s |
| 5 | 50 s | 100 s | 150 s | 300 s |

Siege progress starts on the arrival tick (or the tick a battle there ends), so from the order an undefended province next door flips after **move + required − 1** ticks, and a defended one after **move + required + 1** (the 3-round battle adds 2, and with the grace period the battle no longer costs the progress made before it).

## 7. Neutral garrisons and the cost of a neutral province

Neutral land (not mountains) starts with a garrison of `NeutralGarrison` = 1,000 men unless the map sets more (section 1). Garrisons never move, never grow back, never get a fort bonus (the fort rule needs an owner), but do get the forest/hills +25%. They fight anyone, in Peace too.

From an owned province next door, through the real tick loop (`tools/balance/conquest.luau`, 40 rolls per row). The smallest force that always wins is 1 regiment more than the garrison (an equal force wins half the time and a 10% smaller one never):

| Garrison | Terrain | Regiments sent | Men lost | Loss cost | Time to flip, dev 1 / 2 / 3 / 4 / 5 | Payback, dev 1 / 2 / 4 |
| --- | --- | --- | --- | --- | --- | --- |
| 1,000 | Plains | 2 | 329 | 3.3 gold + 329 manpower | 16 / 26 / 36 / 46 / 56 s | 3.3 / 1.6 / 0.8 months |
| 1,000 | Forest/hills | 2 | 413 | 4.1 + 413 | 19 / 29 / 39 / 49 / 59 s | 4.1 / 2.1 / 1.0 |
| 2,000 | Plains | 3 | 719 | 7.2 + 719 | same | 7.2 / 3.6 / 1.8 |
| 2,000 | Forest/hills | 3 | 902 | 9.0 + 902 | same + 3 s | 9.0 / 4.5 / 2.3 |
| 3,000 | Plains | 4 | 1,109 | 11.1 + 1,109 | same | 11.1 / 5.5 / 2.8 |
| 3,000 | Forest/hills | 4 | 1,391 | 13.9 + 1,391 | same + 3 s | 13.9 / 7.0 / 3.5 |

Sending one regiment more barely lowers losses (329 → 269 men against 1,000 on plains), because the garrison's kills depend on its own size. The time to flip is the move plus 10 s per development plus 1 s: development, not the garrison, sets the time. The army is free again right after, so an army of 2 regiments can take a dev-2 plains neutral every ~26 s plus travel. (The loss cost leaves out upkeep: 2 regiments cost 3 gold a month while they march.)

## 8. Peace and tributes

`Sim/Diplomacy.luau`. War needs a shared border (straits count) and no truce; allies on both sides join. A peace offer lasts 30 s and may carry a tribute of 0, 50 or 100 gold, paid by the proposer to the accepter when it is accepted. Peace ends that whole war for everyone in it, and every pair of former enemies gets a 3-minute truce. No land changes hands: what was sieged stays sieged, and sieges still running between them end.

A 100-gold tribute is 4.5 months of a starting nation's income, or 10 regiments' price. It can't buy back land, so it is only worth paying to stop a war you are losing.

## 9. Catch-up

`Sim/CatchUp.luau`, hooked into `Economy.monthlyIncome` (one line) and `Battle.bonus`.

- **Overextension:** gold multiplier = 1 − 0.05 × floor((provinces − 20) / 5), never below 0. 21–24 provinces: ×1.00; 25–29: ×0.95; 30–34: ×0.90; 60: ×0.60. It cuts gross gold (provinces + capital) before upkeep. Manpower is not cut. With upkeep at 1.5, gold sets the army a nation can keep (section 2), so overextension now caps the leader's army too: at 60 provinces it can keep about 53 regiments instead of 88.
- **Underdog:** among living nations, a nation is an underdog if it is not the largest and it plus every nation at or below its province count make 3 or fewer. So the 3 smallest are underdogs, a tie at the cut-off leaves the whole tie out, nobody is one while all are level (the start of every match), and there are never more than 3. Their side gets +0.50 combat modifier **when defending in a battle**: not when attacking, not against sieges. An ally fighting beside an underdog on defence shares it.
- **Coalition:** every living nation with at least 20% of the **ownable** provinces wears the crown (normally one; two or more crowned nations are possible). Any side with a nation on it gets +0.30 when the other side has a crowned nation, attacking or defending. Neutral garrisons and Rebels don't get it. The client draws 👑 over the crowned nation's capital (over its first province if the capital is lost). Bots join a war against a crowned leader that is already at war.
- Eliminated nations are ignored by all three.

![Overextension caps gold income](images/balance_overextension.png)

How much they bite (`tools/balance/catchup.luau`):

| Provinces | Gold multiplier | Gross gold / month without → with (average dev) |
| --- | --- | --- |
| 20 | 1.00 | 47.5 → 47.5 |
| 25 | 0.95 | 58.1 → 55.2 |
| 30 | 0.90 | 68.8 → 61.9 |
| 40 | 0.80 | 90.0 → 72.0 |
| 50 | 0.70 | 111.2 → 77.9 |
| 60 | 0.60 | 132.5 → 79.5 |
| 70 | 0.50 | 153.8 → 76.9 |

| Map | Crown at | Gold multiplier at the crown | Domination at | Gold multiplier at domination |
| --- | --- | --- | --- | --- |
| Earth | 28 provinces | 0.95 | 70 | 0.50 |
| Eldmoor | 27 | 0.95 | 66 | 0.55 |
| Skyshards | 24 | 1.00 | 60 | 0.60 |

Gross gold stops growing at about 55–60 provinces (~80 gold a month), well before domination now. In battle the underdog +0.50 is worth 15% more men and the coalition +0.30 is worth 8% (section 5).

## 10. Income growth in Peace

`tools/balance/expansion.luau`, part 1: all 10 nations run the greedy planner from 0:00 (expand into the best development-per-second neutral target they can beat, recruit on demand, spend spare gold on the best-yield improvement). Net gold is after upkeep for the armies the planner keeps.

| Time | Earth: provinces / net gold (median) | Eldmoor | Skyshards |
| --- | --- | --- | --- |
| 0:00 | 8 / 22.0 | 8 / 22.0 | 8 / 22.0 |
| 0:30 | 8.5 / 15.8 | 8 / 16.0 | 8 / 16.1 |
| 1:00 | 12 / 19.9 | 10.5 / 18.8 | 11 / 19.1 |
| 2:00 | 13.5 / 21.9 | 11.5 / 21.3 | 12 / 23.1 |
| 3:00 | 13.5 / 21.9 | 12 / 22.1 | 12 / 23.1 |

![Income in the Peace phase](images/balance_peace_income.png)

- A nation grows from 8 to **12–13.5 provinces** in Peace, as before; its gross income grows by about a third, but the armies it keeps for expanding eat most of that (net 22–23 gold at 3:00), and its manpower income grows from 1,700 to 2,800–2,950.
- **Neutral land runs out by 2:00–2:30** on every map (none left at 3:00), so the last 30–60 s of Peace are for building and recruiting. Doubling siege time would stretch the expansion to the end of Peace (section 14), but it halves the bots' conquests in the War.
- Start positions are uneven on Earth and Eldmoor: at 3:00 the best nation holds 16 (Earth) or 18 (Eldmoor) provinces and the worst 12 or 9. Skyshards is perfectly symmetric (12 each).

## 11. After Peace: snowball and the best case

`expansion.luau`, part 2: from the 3:00 state above, one nation keeps playing greedily and declares war on every neighbour, the other nine freeze (no commands, armies stay where they stood). Each of the 10 nations is tried as the aggressor. This is the fastest a nation can conquer against opponents who don't react: a **best case**, not a forecast.

| Map | Variant | Crown (20%) median / best | 50% domination median / best | Provinces at 4:00 | Net gold at 4:00 | Regiments at 4:00 |
| --- | --- | --- | --- | --- | --- | --- |
| Earth | real rules | 3:57 / 3:47 | **5:30 / 5:04** | 29.5 | 7.4 | 31.0 |
| Earth | catch-up off | 3:57 / 3:47 | 5:24 / 4:49 | 30 | 11.6 | 31.0 |
| Earth | opponents' armies removed | 3:53 / 3:42 | 4:59 / 4:36 | 33.5 | 11.3 | 35.0 |
| Eldmoor | real rules | 4:01 / 3:37 | **5:34 / 5:14** | 26 | 9.8 | 30.8 |
| Eldmoor | catch-up off | 4:01 / 3:37 | 5:27 / 5:14 | 26 | 11.3 | 31.9 |
| Eldmoor | opponents' armies removed | 3:57 / 3:31 | 5:01 / 4:38 | 29 | 8.0 | 34.6 |
| Skyshards | real rules | 4:04 / 4:02 | **5:38 / 5:30** | 21 | 11.9 | 30.3 |
| Skyshards | catch-up off | 4:04 / 4:02 | 5:32 / 5:29 | 21 | 12.1 | 30.3 |
| Skyshards | opponents' armies removed | 4:11 / 4:06 | 5:26 / 5:12 | 20 | 31.6 | 15.6 |

- **Best-case domination (now 50% of the ownable land): 5:04 on Earth, 5:14 on Eldmoor, 5:30 on Skyshards** (fastest slot, real rules; it was 4:18–5:12 for 40% of all provinces). Against frozen opponents nothing can stop a rush: movement and siege time are still the only limits, and the conqueror starts the War with ~30 regiments.
- What changed is the cost of keeping that army: at 4:00 the conqueror nets only 7–12 gold a month after upkeep, and most of its income goes to upkeep. Against opponents who fight back (section 12) that is what stops it.

## 12. Can a 25-minute match end early?

`expansion.luau`, part 3: from the same 3:00 state, all 10 nations keep playing greedily and attack every neighbour. Five seeds per map (only the battle rolls differ), with catch-up on and off.

![How fast someone dominates](images/balance_domination.png)

| Map | Catch-up on: result (5 seeds) | Catch-up off |
| --- | --- | --- |
| Earth | 16:10, 17:18, score ×3 | 8:41, 9:33, 10:03, 10:25, 22:59 |
| Eldmoor | 11:31, 11:47, 16:36, 21:47, score | 10:58, 14:29, 14:29, 18:02, 19:08 |
| Skyshards | 14:45, score ×4 | 8:44, 9:46, 14:52, 15:45, 17:32 |

- With catch-up on, **8 of 15 greedy free-for-alls reach the score win at 25:00 and 12 of 15 last past 15:00**; the earliest ends at 11:31. Before the balance pass all 15 ended by domination, at a median 8:29.
- Catch-up now matters: the same seeds without it end at a median 14:29. Upkeep makes overextension cut armies, not just gold, and the coalition +30% is enough to beat a leader at 0.92 : 1.
- Shares rise and fall: in many long games the leader reaches 35–45% around 10:00 and is pushed back to 25–35% by 15:00 (the chart).

**Verdict:** a match against greedy, aggressive players now usually runs deep into the War or reaches the Cataclysm, and a rush against passive opponents still needs 5+ minutes of War. Against bots matches almost always reach 25:00 (section 15).

## 13. Things the numbers exposed (status after the balance pass)

1. **Two rival besiegers blocked each other for good in Peace.** Fixed: the first besieger keeps the siege, a later one at peace with it waits and takes over from zero when the first leaves (section 6). Bots no longer need their "smaller side gives way" workaround: a bot whose rival holds the siege gives way, and bots still don't march on a province a rival stands in. Tests: `tests/war.spec.luau`.
2. **Domination counted mountains.** Fixed: the crown, domination and alliance victory count ownable provinces only, on the server (`CatchUp.counts`, `Victory`), in bots and on the client's crown (`CatchUp.ownableCount`).
3. **Retreats teleported.** Fixed: beaten armies walk home at normal speed and can't be ordered, can't fight and don't block or besiege on the way; the token shows 🏳 and slides like any moving army, and the army sheet says where it is going. Harness scenario `retreat`.
4. **A siege reset when interrupted.** Fixed: 10 s grace (`Siege.GraceTicks`).
5. **Overextension only cuts gold.** Decided: kept as it is. With upkeep at 1.5 gold per regiment, gold is what limits an army (section 2), so the gold cut already shrinks the leader's army; cutting manpower too would add a second rule for little.
6. **Additive combat modifiers are weak.** Decided: kept additive (simple, and "+50%" on a modifier reads naturally); the catch-up bonuses were raised instead (+50% underdog, +30% coalition), so their effect in men (15% and 8%) is now big enough to matter.

New observations from the bot tournament:

7. **Late-game armies exploded** (one nation over 150,000 men at 25:00, 100+ tokens): gold income grows with development, and at 0.5 gold upkeep a nation could keep 2 regiments per gold of income. Fixed with `UpkeepPerRegiment` 1.5 and the merge rule (section 15).
8. **Manpower piles up.** Bots bank hundreds of thousands of manpower by the Cataclysm (over 200,000 each in a soak at the old upkeep) because gold, not manpower, limits recruiting. Harmless now (upkeep caps armies), but manpower barely matters after the first minutes. A manpower cap (EU4 style) would make it matter again; not done.
9. **Start positions:** Eldmoor's Frostmarch and Elderwood and Earth's Amazon win 7–9 of 20 bot matches each and Ironholds, Sunscorch, Tigris and Niger almost never; Skyshards is closer (Umbra 7, every other slot 0–3). Fixed (section 17): one cause was the bots' planning order (it followed nation ids), the rest was the maps.

## 14. The recommended Config changes, measured

The first version of this document recommended five Config changes without applying them. The balance pass measured them with both brackets (greedy planner and bots), under the fixed rules. The first four rows still had a hard army cap that was tried and dropped (see below):

| Change | Greedy FFA (median end, 15 games) | Bots (provinces taken from nations per match, Earth / Eldmoor / Skyshards) | Applied |
| --- | --- | --- | --- |
| None (fixed rules, old Config) | 8:42 | 37 / 34 / 29 | — |
| All five (siege 20, underdog 0.5, coalition 0.3, crown 0.2, start manpower 3000) | 11:28 | 18 / 21 / 10 | — |
| All five + domination 50% | 16:56 | same | — |
| Four (siege kept at 10) + domination 50% | 14:43 | 31 / 32 / 24 | — |
| Four + domination 50% + upkeep 1.5 (no cap) + alliance 65% | **25:00** | **56 / 50 / 42** | **yes** |
| Upkeep 1.5 alone | 12:03 | — | — |

- **Siege time 20 was not applied.** It slows the greedy rush (8:42 → 11:28 with the others), but it halves the bots' wars (37 → 18 provinces taken per match on Earth, 29 → 10 on Skyshards): the 1 player + 9 bots match would turn static. A 15 s siege was in between on both counts.
- **Domination at 50%** is the strongest lever that leaves bots alone (they never get near it): "own half the world" is also easy to explain. The alliance victory went from 55% to 65% so three allies need clearly more than one dominant nation.
- **Upkeep 1.5** fixed the late-game army explosion and slowed the rush the most. A hard army cap (5 + 1.5 regiments per province) was tried first: it capped armies just as well but cut the bots' wars by 40%, because every nation sat at the same cap and nobody reached the 1.3× attack ratio. Upkeep scales with income instead, so rich nations still out-arm poor ones, and the cap was dropped.

## 15. The bot tournament

`lune run tools/harness/tournament` (20 seeds × 3 maps, Normal bots, the real Sim). It found what the planner can't: a static War, and armies that grew without limit.

| Map | Before: ended early / taken from nations / leader changes / men at 15:00 → 25:00 (all, biggest nation) / tokens stacked at 25:00 | After |
| --- | --- | --- |
| Earth | 1 of 20 / 57.8 / 3.4 / 138k → 600k (179k) / 71 | 4 of 20 / 55.7 / 3.1 / 149k → 167k (39k) / 0 |
| Eldmoor | 1 of 20 / 45.2 / 1.9 / 169k → 484k (156k) / 62 | 5 of 20 / 50.1 / 2.5 / 143k → 181k (51k) / 0 |
| Skyshards | 2 of 20 / 53.7 / 2.7 / 182k → 652k (185k) / 77 | 1 of 20 / 41.7 / 2.8 / 121k → 216k (54k) / 0 |

- Every early end is an alliance victory: before 21:05–23:40, now 15:41–24:54. Nobody dominates bots; the leader holds 25–31 provinces at 25:00 (the crown appears in most matches now that it sits at 20%).
- Armies at 15:00 are about the same; at 25:00 there are a third as many men and the biggest nation holds 39k–54k instead of 156k–185k, so a 3,000-man Rebels or a Meteor (−50% of one army) matters again. Bots now use Meteor about 22–25 times per match (all nations together).
- Standing armies sharing a province with another of the same owner: 62–77 tokens at 25:00 before, none now (the merge rule). Army counts at 25:00 fell from 102–125 to 31–40.
- No slot wins most matches on any map (most: 7–9 of 20).

## 16. Bot difficulties

`lune run tools/harness/tournament 20 all A/B` plays mixed matches: half the nations on difficulty A, half on B, swapped every seed so each start position plays both (20 seeds × 3 maps = 60 matches, 300 nations per side). `Player` stands in for players: nations marked as players and planned by the Normal bot every 3 s, so Easy's and Hard's player rules apply to them.

| Matchup (A / B) | Wins A / B | Avg final provinces A / B | Ended with no land A / B | A took from B before 8:00 / whole match |
| --- | --- | --- | --- | --- |
| Hard / Normal | 56% / 44% | 13.7 / 12.3 | 73 / 89 | 485 / 1010 |
| Easy / Normal | 31% / 69% | 12.0 / 13.9 | 72 / 52 | 309 / 686 |
| Easy / Player | 24% / 76% | 10.1 / 15.9 | 87 / 28 | **3** / 369 |
| Hard / Player | 38% / 62% | 12.7 / 13.3 | 56 / 55 | 195 / 636 |

- Hard beats Normal and Easy loses to it, as the spec says.
- Easy leaves players alone early: 0 wars declared on players before 8:00, and 3 provinces taken from them (armies already marching on a neutral province a player took first). Until 8:00 an Easy bot doesn't march into a player's land or use a power on one even in a war the player started; it only defends. Before that rule it took 24 provinces from players before 8:00 in 30 matches.
- Hard is the hardest on players: they end with 13.3 provinces against Hard and 15.9 against Easy, and twice as many of them lose all their land (55 against 28). Hard wins fewer matches against players than against Normal bots because every Hard bot goes after the leading player instead of the easiest land; that's the point of Hard.
- `Config.Bots.BotsPlanningPerTick` (2) caps how often bots really plan: with 9 bots each plans about every 4.5 s, so Hard's 2 s and Normal's 3 s only show with fewer bots. Raising the cap costs server time; it wasn't needed for the ranking above.

## 17. Start positions (per-map balance)

The Phase 5 task "per-map balance from win rate by start position". `lune run tools/harness/tournament 200 <map>` plays 200 bot matches (Normal) per map and prints each slot's wins and its **share**: wins over the fair share (all wins, alliance co-winners included, divided by 10). The goal: on every map no slot above about 2× and none (almost) never winning.

**How noisy is it?** A slot's win count at 200 seeds moves by about ±5 (±0.2×) from one batch of seeds to the next, and 20 seeds (the old tournament default) can't tell a 2× slot from a fair one. Skyshards is perfectly symmetric, so its "after" spread is pure noise: **0.65×–1.16× is what a fair map looks like at 200 seeds**. Everything below was measured on the same 200 seeds before and after.

**What was wrong**

1. **A bot habit, not the map: the planning order followed nation ids.** `Bot.step` lets two bots plan per tick, and at match start they lined up by id, so the same pairs always planned at the same moment relative to the monthly payday. On Skyshards slots 9 and 10 planned their first expansion right after the first payday, recruited a fourth regiment first, and so took their Heartstone Approach at 1:01 instead of 1:41 (the others' 3,000-man stacks couldn't beat its 2,000 garrison straight after a drift isle). They then had 13 provinces at 3:00 against 11.5 for their neighbours, and every bot attacks its weakest neighbour: Umbra declared war on Aurora 88 times in 100 matches, Verdance on Rime 91 times, and on a perfectly symmetric map Umbra won 42 matches and Rime 2. **Fix:** the first planning order is shuffled from the bots' rng each match (`Bot.step`, test in `tests/bot.spec.luau`). The same order bias was also hiding in the Earth and Eldmoor numbers.
2. **Eldmoor: walled-in kingdoms.** Ironholds and Sunscorch had no way into the Crownlands and 1–2 neutral provinces of their own, so they had the fewest provinces at 3:00 (9 and 10, against 14–16) and were every neighbour's first war at 3:03 (eliminated in 89–90% of matches). Frostmarch, the only kingdom with a Dragonspine gap to itself, took the rich Crownlands and won 63% of matches.
3. **Earth: safe backyards beat the crowded middle.** Amazon (South America) and Mekong (South-East Asia and Oceania) held about 15 provinces nobody else could reach and never lost them; Amazon's only neighbour was Niger, across the Dakar–Natal lane, and it declared war on Niger 85 times in 100 matches. Niger and Tigris had the least neutral land (11.5 provinces at 3:00, against 14–16) and several such neighbours; Ganges sat between Mekong and Yangtze, which both attacked it.

**What changed** (generator only, details in `docs/MAPS.md`; every nation still starts with 8 provinces and 17 development)

| Map | Change | Why |
| --- | --- | --- |
| All | Bots' first planning order random per match (`Bot.step`) | Fixed order favoured the same slots every match |
| Eldmoor | Four one-province passes through the Dragonspine (Wyrmcoast, Ironholds, Sunscorch, Saltmarsh) | Every mainland kingdom gets its own door to the Crownlands |
| Eldmoor | Elderwood's capital moves south (Silverglade) | Its start territory no longer touches Ironholds; the north forest starts neutral |
| Eldmoor | An eighth Isle of Mists province (Oakshire) | Mistborn starts on its island, not on a foothold against Ironholds |
| Eldmoor | 2,000-man garrisons on Highcairn and Duskshade | Ironholds' two open flanks hold out longer |
| Earth | Dakar–Natal lane removed | Amazon's only target was Niger |
| Earth | Oman and Mauretania added; Westralia and Araucania merged into Outback and Patagonia | Free land moves from Mekong's and Amazon's backyards to Tigris and Niger |
| Earth | 2,000-man garrisons on Ob, Yenisei, the Horn, Abyssinia and Madagascar | Volga's and Zambezi's quiet backyards fill more slowly |

Garrisons were the weakest lever and a cliff: 2,000 men on all of Oceania barely slowed Mekong, 3,000 turned it from 2.6× into 0.1× (its armies spent Peace on the outback while Ganges ate it). Moving land between backyards and the middle, and giving walled-in nations a way out, changed the most.

**Earth** (fair share 22.3 wins before, 27.6 after: more alliance victories, 11 → 37)

| Slot | Nation (capital) | Before: wins (share) | Bot fix only, 100 seeds | After: wins (share) | Avg final provinces before → after |
| --- | --- | --- | --- | --- | --- |
| 1 | Rhine (Rhineland) | 8 (0.36×) | 5 (0.47×) | **34 (1.23×)** | 9.4 → 13.4 |
| 2 | Volga (Muscovy) | 34 (1.52×) | 13 (1.23×) | **48 (1.74×)** | 16.9 → 15.5 |
| 3 | Tigris (Mesopotamia) | 4 (0.18×) | 4 (0.38×) | **26 (0.94×)** | 5.9 → 9.6 |
| 4 | Ganges (Ganges Plain) | 10 (0.45×) | 1 (0.09×) | **43 (1.56×)** | 9.1 → 14.9 |
| 5 | Yangtze (Yangtze Valley) | 9 (0.40×) | 5 (0.47×) | **9 (0.33×)** | 14.9 → 12.0 |
| 6 | Mekong (Mekong) | 57 (2.56×) | 23 (2.17×) | **22 (0.80×)** | 23.0 → 16.7 |
| 7 | Niger (Niger Bend) | 0 (0.00×) | 1 (0.09×) | **21 (0.76×)** | 2.0 → 9.2 |
| 8 | Zambezi (Zambezi) | 34 (1.52×) | 14 (1.32×) | **47 (1.70×)** | 19.9 → 16.6 |
| 9 | Mississippi (Mississippi) | 11 (0.49×) | 10 (0.94×) | **12 (0.43×)** | 15.8 → 15.3 |
| 10 | Amazon (Amazonia) | 56 (2.51×) | 30 (2.83×) | **14 (0.51×)** | 21.9 → 15.7 |

**Eldmoor** (fair share 31.8 before, 25.8 after: alliance victories 59 → 29)

| Slot | Nation (capital) | Before: wins (share) | Bot fix only, 100 seeds | After: wins (share) | Avg final provinces before → after |
| --- | --- | --- | --- | --- | --- |
| 1 | Mistborn (Oakstead) | 67 (2.11×) | 36 (2.43×) | **30 (1.16×)** | 21.7 → 15.7 |
| 2 | Saltmarsh (Thornthicket) | 22 (0.69×) | 9 (0.61×) | **20 (0.78×)** | 15.0 → 10.3 |
| 3 | Ironholds (Stoneridge) | 0 (0.00×) | 0 (0.00×) | **17 (0.66×)** | 1.1 → 10.3 |
| 4 | Frostmarch (Hoarreach) | 125 (3.93×) | 44 (2.97×) | **37 (1.43×)** | 22.5 → 12.4 |
| 5 | Greenvale (Stoneheath) | 0 (0.00×) | 3 (0.20×) | **17 (0.66×)** | 4.3 → 9.8 |
| 6 | Elderwood (Silvershade → Silverglade) | 71 (2.23×) | 36 (2.43×) | **27 (1.05×)** | 24.2 → 19.6 |
| 7 | Wyrmcoast (Clovershire) | 11 (0.35×) | 5 (0.34×) | **39 (1.51×)** | 14.7 → 16.4 |
| 8 | Sunscorch (Dunehaven) | 0 (0.00×) | 0 (0.00×) | **28 (1.09×)** | 0.8 → 12.5 |
| 9 | Ashen Dominion (Scorchoasis) | 17 (0.53×) | 10 (0.68×) | **22 (0.85×)** | 10.5 → 12.6 |
| 10 | Corsairs (Moonroot) | 5 (0.16×) | 5 (0.34×) | **21 (0.81×)** | 16.0 → 16.3 |

**Skyshards** (map unchanged; fair share 21.2 before, 21.6 after)

| Slot | Nation | Before: wins (share) | Bot fix only, 100 seeds | After: wins (share) | Avg final provinces before → after |
| --- | --- | --- | --- | --- | --- |
| 1 | Aurora | 9 (0.42×) | 14 (1.27×) | **24 (1.11×)** | 7.3 → 12.3 |
| 2 | Zephyr | 28 (1.32×) | 11 (1.00×) | **20 (0.93×)** | 13.6 → 12.0 |
| 3 | Nimbus | 17 (0.80×) | 5 (0.45×) | **14 (0.65×)** | 10.8 → 11.3 |
| 4 | Tempest | 17 (0.80×) | 13 (1.18×) | **22 (1.02×)** | 12.2 → 11.8 |
| 5 | Halo | 22 (1.04×) | 12 (1.09×) | **24 (1.11×)** | 12.1 → 12.8 |
| 6 | Solace | 16 (0.75×) | 13 (1.18×) | **25 (1.16×)** | 10.7 → 11.4 |
| 7 | Ember | 22 (1.04×) | 12 (1.09×) | **21 (0.97×)** | 14.3 → 12.2 |
| 8 | Rime | 2 (0.09×) | 9 (0.82×) | **22 (1.02×)** | 6.8 → 12.6 |
| 9 | Verdance | 37 (1.75×) | 13 (1.18×) | **21 (0.97×)** | 15.5 → 11.5 |
| 10 | Umbra | 42 (1.98×) | 8 (0.73×) | **23 (1.06×)** | 16.5 → 12.2 |

**Result:** Earth 0.33×–1.74× (was 0×–2.56×), Eldmoor 0.66×–1.51× (was 0×–3.93×), Skyshards 0.65×–1.16× (was 0.09×–1.98×). Other match numbers barely moved: matches still end at 25:00 in 80–96% of games, wars per match 9.6–10.6, provinces taken from nations per match 40 / 49 / 37 (Earth / Eldmoor / Skyshards; Earth was 48: fewer easy victims).

**Still to watch**

- **Yangtze (0.33×)** is Earth's weakest slot. Once Mekong lost its extra Oceania province, Mekong became Yangtze's "weakest neighbour", and Yangtze declares war on it about 75 times in 100 matches; the war through hills, jungle and sea lanes goes nowhere while Ganges and Volga attack Yangtze. Cutting Bengal–Sichuan (what-if) only moved it to 0.44×, within noise, so it was left alone. A bot that weighed terrain and straits when picking its war target would help here; the spec says "weakest neighbour", so that is a design question, not a map fix.
- **Mississippi (0.43×)** now fights Amazon, its only neighbour in the Americas.
- Player behaviour differs from bots: once real matches run, use the "win rate by start position" analytics event (`docs/LAUNCH.md`) and redo this with the same levers.
