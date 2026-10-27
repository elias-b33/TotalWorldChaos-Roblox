# How conquering works

The complete math of the current rules, read from the code (`src/shared/Sim/`, `src/shared/Config.luau`), and the numbers a designer needs to tune them. `docs/DESIGN.md` is the spec; this document says what the code actually does with it and what that means in a match.

Every number below comes from `Config.luau` as of this document or from one of the scripts in `tools/balance/`. The scripts call the real Sim modules, so after a Config change you rerun them and the numbers follow.

| Script | What it produces |
| --- | --- |
| `lune run tools/balance/maps` | Map facts: provinces, mountains, neutral land, garrisons (section 1) |
| `lune run tools/balance/battles` | Monte-Carlo battles through `Sim/Battle`: win chance and losses vs strength ratio; writes `tools/balance/data/battles.csv` (section 5) |
| `lune run tools/balance/conquest` | Time and cost to take a neutral province, through `Sim/Tick` (section 7) |
| `lune run tools/balance/catchup` | Overextension by size, where the thresholds sit, break-even ratios; writes `data/catchup.csv` (section 9) |
| `lune run tools/balance/expansion` | Whole matches with a greedy planner: Peace income, best-case domination, free-for-all; writes `data/expansion_*.csv` (sections 10–12). About 2.5 minutes. `SET="Siege.TicksPerDevelopment=20"` runs a what-if (section 14) |
| `python3 tools/balance/charts.py` | The four charts in `docs/images/balance_*.png`, from the CSVs (Pillow; matplotlib isn't installed) |

`tools/balance/Planner.luau` is the greedy player used by `expansion`. It is **not** the bot AI: it sends ordinary commands through `Sim/Commands`, so it obeys every rule, and it plays close to the fastest possible expansion. It never defends on purpose (armies standing in their own provinces still fight), so its matches are faster and bloodier than real ones.

Time: 1 tick = 1 second = 1 game day. A month is 10 ticks. Peace is 0:00–3:00, War 3:00–20:00, Cataclysm 20:00–25:00.

## 1. The maps

`tools/balance/maps.luau`:

| Map | Provinces (all) | Mountains | Ownable | Start-owned | Neutral | Neutral dev 1/2/3/4/5 | Neutral garrisons (men: count) | Provinces for 25% / 40% | Forest+hills share of land |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Earth | 150 | 11 | 139 | 80 | 59 | 22/28/9/0/0 | 1000: 59 | 38 / 60 | 52% |
| Eldmoor | 146 | 15 | 131 | 80 | 51 | 9/20/9/13/0 | 1000: 38, 3000: 13 | 37 / 59 | 50% |
| Skyshards | 131 | 11 | 120 | 80 | 40 | 0/20/10/10/0 | 1000: 20, 2000: 10, 3000: 10 | 33 / 53 | 42% |

Every nation starts with 8 provinces and 17 development. The 25% (crown) and 40% (domination) thresholds count **all** provinces, mountains included, but mountains can never be owned: domination really needs 43–44% of the land a nation can hold.

## 2. Economy

`Sim/Economy.luau`. Paid every 10 ticks (ticks 10, 20, 30, …), to every living nation.

| Flow | Per month |
| --- | --- |
| Gold from a province | development × 1, ×1.5 with a farm |
| Manpower from a province | development × 100, ×1.5 with barracks |
| Capital bonus | +5 gold, only while the nation holds its own capital |
| Overextension | gross gold (provinces + capital) × `CatchUp.overextension(provinces)` (section 9) |
| Upkeep | 0.5 gold per 1,000 men in the field (fractional: a 2,400-man army costs 1.2) |

Net gold = gross gold × overextension − upkeep. Gold can go negative (debt); nothing can be bought until it is positive again. Manpower has no cap and no upkeep.

**A starting nation** earns 17 + 5 = **22 gold and 1,700 manpower a month**, and starts with 100 gold and 5,000 manpower. Doing nothing, it holds 100 + 18 × 22 = **496 gold and 35,600 manpower at 3:00**: enough for 35 regiments the moment war opens. Manpower is the binding resource early (1,700 manpower = 1.7 regiments a month, but gold for 2.2), and banked manpower is why the first minutes of war are so fast (section 11).

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
| Regiment | 10 gold + 1,000 manpower | −0.5 gold upkeep | — | upkeep over the 22 minutes of War + Cataclysm: 66 gold, 6.6× its price |
| Neutral province, dev d | ~330–1,400 men lost (section 7) | +d gold, +100 d manpower | | 0.7–14 months |

Develop also adds 5 score per level. In a 25-minute match (150 months) only level 1 → 2 and 2 → 3 pay back in gold before the end, and anything bought after ~10:00 only pays back as score. Taking land is by far the best investment: a neutral province pays back its losses in under 6 months in most cases.

## 4. Movement

`Sim/Movement.luau`, `Sim/Pathing.luau`. An army moves along a breadth-first path (fewest provinces, not fastest) through land it may enter: its own, allied, neutral, and enemy land at war. Never mountains, never land of a nation it is at peace with.

Entering a province takes the ticks of **that province's** terrain: **5 s for plains, 8 s for forest and hills.** An order given before a tick starts counting that tick, so one plains step arrives 5 ticks after the order. Crossing 3 plains provinces takes 15 s; 3 hill provinces, 24 s. Armies in battle don't move, and an army whose way closes (peace, an ally leaving) stops where it is.

## 5. Battles

`Sim/Battle.luau`, tick step 3. When hostile armies share a province they fight `Rounds` = 3 rounds, one per tick, starting on the tick they meet (movement runs first, so an army fights on its arrival tick).

**Sides.** Defenders are the province owner and its allies if any of them is there; in neutral land, the garrison; otherwise the lowest-numbered army's side. Attackers are every army hostile to the defenders. Nations at peace sharing a province don't fight.

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
| Underdog | defending side containing an underdog (section 9) | +0.20 |
| Coalition | a nation's side fighting a crowned nation (section 9) | +0.10 |

**After round 3** the side with more men wins (a tie goes to the defender). Every loser army retreats **instantly** to the nearest province its owner holds (fewest steps over any non-mountain land) and stops; with nowhere to go, or under 500 men, it is destroyed. Winner armies under 500 men are destroyed too. Neutral garrisons never retreat, so a beaten garrison is always gone. Each winning nation gets +1 battle won (+2 score).

**Why the bonuses matter less than they look.** With equal modifiers m, the sum of both armies shrinks by (1 − 0.15 m) each round and their difference grows by (1 + 0.15 m): after 3 rounds the sum is ×0.614 and the difference ×1.521. So on plains **the larger army wins** unless the rolls flip a near-even fight, and a modifier only moves the break-even point a little, because the defender's bonus only applies to the kills of a shrinking army. The exact break-even ratio (attacker men per defender man to win half the time, `tools/balance/catchup.luau`, matching the Monte-Carlo to 0.001):

| Situation | Defender modifier | Break-even attacker : defender |
| --- | --- | --- |
| Plains | 1.00 | 1.000 |
| Forest/hills | 1.25 | 1.074 |
| Fort | 1.50 | 1.146 |
| Fort + hills | 1.75 | 1.217 |
| Plains, underdog defends | 1.20 | 1.059 |
| Plains, coalition attacks the leader (attacker 1.10) | 1.00 | 0.971 |

A +25% terrain bonus is worth 7% more men, a +50% fort 15%. The ±10% roll moves the outcome by about ±3% of the ratio, so **battles are close to deterministic**: from 5% above break-even the attacker always wins.

![Attacker win chance vs. strength ratio](images/balance_battles.png)

Win chance and losses, 2,000 battles per row against a 3,000-man defender (`tools/balance/battles.luau`, full tables with all ratios and the catch-up cases in its output). Losses are the share of each side's men gone afterwards.

| Ratio | Plains: win / att. loss / def. loss | Forest/hills | Fort | Fort + hills |
| --- | --- | --- | --- | --- |
| 0.90 | 0% / 44% / 34% | 0% / 55% / 32% | 0% / 66% / 31% | 0% / 77% / 29% |
| 1.00 | 49% / 39% / 39% | 0% / 48% / 37% | 0% / 58% / 35% | 0% / 68% / 34% |
| 1.10 | 100% / 34% / 43% | 82% / 43% / 42% | 4% / 52% / 40% | 0% / 61% / 38% |
| 1.25 | 100% / 30% / 50% | 100% / 37% / 48% | 100% / 45% / 47% | 87% / 52% / 45% |
| 1.50 | 100% / 23% / 61% | 100% / 30% / 59% | 100% / 35% / 58% | 100% / 41% / 57% |
| 2.00 | 100% / 16% / 91% | 100% / 20% / 88% | 100% / 24% / 85% | 100% / 28% / 83% |

Where defence bonuses really bite is **losses**: at 1.25 : 1 the attacker wins everywhere, but loses 30% of its men on plains and 52% against a fort in the hills. A losing army typically keeps 40–65% of its men and teleports home, so one battle rarely destroys anything; at 2 : 1 the defender's remnant falls under 500 men (and is destroyed) only 25–55% of the time.

## 6. Sieges

`Sim/Siege.luau`, tick step 4. An army besieges when it stands still in a neutral province or one whose owner it is at war with, is not in battle, and nobody blocks it. Blockers: a neutral garrison, any army of the owner or its allies, or a rival besieger that isn't its ally (then nobody progresses). Progress is +1 per tick; at the requirement the province flips at once (the owner changes, buildings and development stay). If the siege is blocked or the besieger leaves, progress resets to 0. Army size doesn't matter: one regiment besieges as fast as forty.

Required ticks = 10 × development, ×2 with a fort, ×3 for a capital:

| Development | Plain | Fort | Capital | Fort + capital |
| --- | --- | --- | --- | --- |
| 1 | 10 s | 20 s | 30 s | 60 s |
| 2 | 20 s | 40 s | 60 s | 120 s |
| 3 | 30 s | 60 s | 90 s | 180 s |
| 4 | 40 s | 80 s | 120 s | 240 s |
| 5 | 50 s | 100 s | 150 s | 300 s |

Siege progress starts on the arrival tick (or the tick a battle there ends), so from the order an undefended province next door flips after **move + required − 1** ticks, and a defended one after **move + required + 1** (the 3-round battle adds 2).

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

Sending one regiment more barely lowers losses (329 → 269 men against 1,000 on plains), because the garrison's kills depend on its own size. The time to flip is the move plus 10 s per development plus 1 s: development, not the garrison, sets the time. The army is free again right after, so an army of 2 regiments can take a dev-2 plains neutral every ~26 s plus travel.

## 8. Peace and tributes

`Sim/Diplomacy.luau`. War needs a shared border (straits count) and no truce; allies on both sides join. A peace offer lasts 30 s and may carry a tribute of 0, 50 or 100 gold, paid by the proposer to the accepter when it is accepted. Peace ends that whole war for everyone in it, and every pair of former enemies gets a 3-minute truce. No land changes hands: what was sieged stays sieged.

A 100-gold tribute is 4.5 months of a starting nation's income, or 10 regiments' price. It can't buy back land, so it is only worth paying to stop a war you are losing.

## 9. Catch-up

`Sim/CatchUp.luau`, hooked into `Economy.monthlyIncome` (one line) and `Battle.bonus`.

- **Overextension:** gold multiplier = 1 − 0.05 × floor((provinces − 20) / 5), never below 0. 21–24 provinces: ×1.00; 25–29: ×0.95; 30–34: ×0.90; 60: ×0.60. It cuts gross gold (provinces + capital) before upkeep. Manpower is not cut.
- **Underdog:** among living nations, a nation is an underdog if it is not the largest and it plus every nation at or below its province count make 3 or fewer. So the 3 smallest are underdogs, a tie at the cut-off leaves the whole tie out, nobody is one while all are level (the start of every match), and there are never more than 3. Their side gets +0.20 combat modifier **when defending in a battle**: not when attacking, not against sieges. An ally fighting beside an underdog on defence shares it.
- **Coalition:** every living nation with at least 25% of **all** provinces wears the crown (normally one; two crowned nations are possible). Any side with a nation on it gets +0.10 when the other side has a crowned nation, attacking or defending. Neutral garrisons and Rebels don't get it. The client draws 👑 over the crowned nation's capital (over its first province if the capital is lost).
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

| Map | Crown at | Gold multiplier at the crown | 40% at | Gold multiplier at 40% |
| --- | --- | --- | --- | --- |
| Earth | 38 provinces | 0.85 | 60 | 0.60 |
| Eldmoor | 37 | 0.85 | 59 | 0.65 |
| Skyshards | 33 | 0.90 | 53 | 0.70 |

Gross gold stops growing at about 55–60 provinces (~80 gold a month), right where domination happens. But gold is not what a conqueror runs short of (section 11), and in battle the underdog +0.20 is worth 6% more men and the coalition +0.10 is worth 3% (section 5).

## 10. Income growth in Peace

`tools/balance/expansion.luau`, part 1: all 10 nations run the greedy planner from 0:00 (expand into the best development-per-second neutral target they can beat, recruit on demand, spend spare gold on the best-yield improvement).

| Time | Earth: provinces / net gold (median) | Eldmoor | Skyshards |
| --- | --- | --- | --- |
| 0:00 | 8 / 22.0 | 8 / 22.0 | 8 / 22.0 |
| 0:30 | 9 / 20.8 | 8.5 / 20.7 | 9 / 20.7 |
| 1:00 | 12.5 / 27.2 | 11 / 24.8 | 11 / 24.7 |
| 2:00 | 13.5 / 29.5 | 12 / 26.4 | 12 / 29.2 |
| 3:00 | 13.5 / 29.5 | 12 / 26.9 | 12 / 29.2 |

![Income in the Peace phase](images/balance_peace_income.png)

- A nation grows from 8 to **12–13.5 provinces and from 22 to 27–30 net gold a month (+25–35%)** in Peace, and from 1,700 to 2,800–2,950 manpower.
- **Neutral land runs out by 2:00–2:30** on every map (0–1 neutral provinces left at 3:00), so the last 30–60 s of Peace have nothing to conquer.
- Start positions are uneven on Earth and Eldmoor: at 3:00 the best nation holds 16 (Earth) or 19 (Eldmoor) provinces and the worst 12 or 9. Eldmoor's slot 9 ends Peace with twice slot 3's income (46 vs 24 gold). Skyshards is perfectly symmetric (12 each).
- At 3:00 each greedy nation has banked about **420 gold and 42,000 manpower**, because nothing was left to spend manpower on.

## 11. After Peace: snowball and the best case

`expansion.luau`, part 2: from the 3:00 state above, one nation keeps playing greedily and declares war on every neighbour, the other nine freeze (no commands, armies stay where they stood). Each of the 10 nations is tried as the aggressor. This is the fastest a nation can conquer against opponents who don't react: a **best case**, not a forecast.

| Map | Variant | Crown (25%) median / best | 40% domination median / best | Provinces at 4:00 | Net gold at 4:00 | Regiments at 4:00 |
| --- | --- | --- | --- | --- | --- | --- |
| Earth | real rules | 4:12 / 3:54 | **4:54 / 4:25** | 31.5 | 36.1 | 50 |
| Earth | catch-up off | 4:12 / 3:54 | 4:53 / 4:22 | 32.5 | 42.7 | 50 |
| Earth | opponents' armies removed | 4:03 / 3:54 | 4:41 / 4:18 | 33.5 | 41.2 | 37 |
| Eldmoor | real rules | 4:20 / 4:02 | **5:07 / 4:42** | 26.5 | 34.9 | 47 |
| Eldmoor | catch-up off | 4:20 / 4:02 | 5:07 / 4:43 | 26 | 38.8 | 49 |
| Eldmoor | opponents' armies removed | 4:18 / 4:00 | 4:54 / 4:27 | 27 | 44.6 | 34 |
| Skyshards | real rules | 4:27 / 4:26 | **5:14 / 5:12** | 21 | 39.9 | 36 |
| Skyshards | catch-up off | 4:27 / 4:26 | 5:14 / 5:12 | 21 | 39.9 | 36 |
| Skyshards | opponents' armies removed | 4:32 / 4:31 | 5:12 / 5:12 | 20 | 46.7 | 17 |

- **Best-case 40% domination: 4:18 on Earth, 4:27 on Eldmoor, 5:12 on Skyshards** (fastest slot, any variant); the median slot under the real rules needs 4:54–5:14. That is 1:20–2:15 after war opens, and every slot on every map gets there.
- Why so fast: owned provinces have no garrison, a single regiment besieges at full speed, and the 35–50 regiments of banked manpower become 35–50 parallel sieges of 20–30 s each. Movement and siege time are the only limits.
- **Catch-up changes the best case by 0–4 seconds.** Overextension does bite on gold (Earth at 5:00: 40 net gold with it, 69 without; Skyshards: 59 vs 84), but the conqueror already holds its gold and manpower, so it doesn't slow the conquest. The coalition +10% shifts battles by 3%, inside the planner's 20% safety margin.

## 12. Can a 25-minute match end early?

`expansion.luau`, part 3: from the same 3:00 state, all 10 nations keep playing greedily and attack every neighbour. Five seeds per map (only the battle rolls differ), with catch-up on and off.

![How fast someone dominates](images/balance_domination.png)

| Map | Catch-up on: domination at (5 seeds) | Catch-up off |
| --- | --- | --- |
| Earth | 6:28, 7:34, 11:55, 17:51, 23:31 | 7:18, 8:02, 8:07, 10:13, 10:52 |
| Eldmoor | 6:38, 6:45, 6:53, 7:12, 8:29 | 6:47, 7:49, 8:22, 8:40, 10:13 |
| Skyshards | 7:33, 10:12, 10:13, 11:08, 16:22 | 8:31, 8:48, 11:58, 13:06, 13:06 |

- **All 30 matches ended by domination, none reached the score win at 25:00.** Median end 8:29 with catch-up, 8:40 without.
- Catch-up doesn't delay the typical game; it widens the spread (3 of 15 games went past 15:00 with it, none without), because when it matters at all it matters in long stalemates.
- The crown appeared in every match; in the fast games only 1–3 minutes before 40%.
- The planner never defends on purpose, so real players and bots will stretch this. But the rules make a rush strong: a nation that wins one big battle on plains can split into single regiments and take a province every 20–30 s per regiment.

**Verdict:** yes, a 25-minute match realistically ends early, often around minute 7–12, and a coordinated rush against passive opponents can end it at ~5:00, before the Cataclysm or any Primordial power matters.

## 13. Things the numbers exposed

These are rule observations, not Config values. None is changed in this pass.

1. **Two rival besiegers block each other for good in Peace.** Two nations at peace with armies in the same neutral province both stand still with no progress and can't fight until 3:00. A player can grief a neighbour's expansion with one regiment. (Found when the planner deadlocked; it now avoids provinces a rival stands in or marches to.)
2. **Domination counts mountains.** 40% of all provinces is 43–44% of ownable land (section 1). The crown threshold has the same quirk.
3. **Retreats teleport.** A beaten army is instantly in its nearest province, path cleared, at full speed for the next fight.
4. **A siege resets when interrupted.** A single defending regiment walking through erases 2 minutes of progress on a fortified capital.
5. **Overextension only cuts gold**, which a conqueror has plenty of; manpower is the real limit early and banked gold the limit later.
6. **Additive combat modifiers are weak** in a model where kills scale with the killer's own size (section 5): +20% is 6% more men. Making a modifier multiply the side's effective men in the winner check would make the listed percentages mean what they say.

## 14. Recommended Config changes

Not applied: the coordinator decides. No current value is clearly a bug. Effects measured with `SET="…" lune run tools/balance/expansion` (same seeds as sections 11–12; "FFA" is the section 12 free-for-all with catch-up on, 15 games).

| Change | Reason | Expected effect (measured) |
| --- | --- | --- |
| `Siege.TicksPerDevelopment` 10 → **20** | Siege time is 70–80% of the time to take a province, and the single biggest lever on match length. It also slows neutral expansion, which currently finishes a minute before Peace ends. | Best-case 40% (fastest per map): 4:18–5:12 → **4:57–6:40**. FFA median end **8:29 → 16:08**; 2 of 15 games now reach the score win at 25:00. Peace still clears the neutral land (0–4 left). |
| `Battle.UnderdogBonus` 0.2 → **0.5** | +0.2 is worth only 6% more men (section 5); +0.5 makes an underdog defend like a fort (break-even 1.146). | Underdog break-even 1.059 → 1.146. FFA median alone: 8:29 → 9:32; best case unchanged (frozen opponents). |
| `Battle.CoalitionBonus` 0.1 → **0.3** | +0.1 is worth 3% (break-even 0.971); +0.3 is worth 8% (0.919), enough to notice. | Together with the underdog change above. |
| `Diplomacy.CoalitionThreshold` 0.25 → **0.2** | The crown currently appears only 1–3 minutes before the leader wins; at 20% (26–30 provinces) the others see it coming. | With all five changes together: FFA median **14:32**, 2 of 15 to 25:00. |
| `StartManpower` 5000 → **3000** | 5,000 starting manpower plus 18 months of income banks ~40 regiments by 3:00, which powers the blitz in section 11. | Fewer regiments at 4:00 (Earth 50 → 36 with all five changes); slower parallel sieges. |

The five together: best case 5:05–6:03 per map (from 4:18–5:12), FFA median 14:32 (from 8:29).

Rule changes worth a design decision (not Config, so not in this table): apply overextension to manpower as well as gold; fix the rival-besieger deadlock in Peace (let the first besieger keep the siege, or let the later one leave); keep siege progress for a few seconds after an interruption; count only ownable provinces for the 25% and 40% thresholds.
