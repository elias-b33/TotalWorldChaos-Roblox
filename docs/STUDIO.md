# Testing in Roblox Studio

How to open the game in Studio, which settings it needs, and a short recipe for checking each feature. Everything here was also played headlessly (`tools/harness`), but rendering, input, sounds, teleports and purchases only really run in Studio.

## Open the project

1. Install [Rojo](https://rojo.space) 7.7 and its Studio plugin.
2. Either:
   - **Live sync:** run `rojo serve` in the repository, open a Baseplate in Studio, and press Connect in the Rojo plugin. Code changes sync while you test.
   - **A place file:** run `mkdir -p build && rojo build -o build/game.rbxlx` and open `build/game.rbxlx`.

## Settings

Game Settings → Security (some of these need the place published once):

| Setting | Why |
| --- | --- |
| Allow Mesh / Image APIs | The map art is one `EditableImage`. In a published game it fails without this; the map then shows names and tokens on a plain background and says "Map art is off". |
| Enable Studio Access to API Services | Optional. Real saves (XP, Glory, items) in Studio. Without it ProfileStore uses an in-memory store: everything works and nothing is kept. With it, Studio saves go to their own DataStore (`PlayerData_Studio`), never the live `PlayerData`, and the leaderboards to `Conquest_Studio` and `Level_Studio`: free test purchases and test history stay in Studio, and Studio starts from a fresh save. |

## Test switches (Workspace attributes)

Select Workspace in the Explorer and add attributes in the Properties window.

| Attribute | Type | Effect |
| --- | --- | --- |
| `SkipLobby` | boolean | Matches start straight in Peace (no map vote or draft) and restart on the same map. Handy for solo tests. |
| `MapId` | string | Locks the map: `earth`, `eldmoor` or `skyshards`. |
| `Theme` | string | Forces a map theme and skips the theme vote: `theme_night`, `theme_winter`, `theme_autumn`, or `theme_classic` for the classic look (what the private-server setting will do). |
| `Tutorial` | boolean | This server plays the tutorial match (in a live game, new players are teleported to one). |
| `TelemetryLog` | boolean | Prints every analytics event as `[telemetry] …` in the Output. AnalyticsService only accepts events from a published game, so this is how to check them in Studio. |
| `PrivateServerOwner` | number or boolean | Simulates a private (VIP) server: a userId is its owner, `true` makes the first player in the server the owner. The owner gets a Settings button (gear icon) in the Lobby. In Play solo your userId is your account's; in Clients and Servers the players are -1, -2, … (or use `true`). Don't combine with `SkipLobby` (no Lobby, no settings sheet). |

The test switches below are Studio-only. Set them during a test run on the **server's** Workspace (in Clients and Servers, the Server window). Each is applied once on the next game second and then removed:

| Attribute | Type | Effect |
| --- | --- | --- |
| `DevTick` | number | Sets the match clock in seconds: `179` is War in a second, `1199` the Cataclysm, `1499` the end of the match. A jump counts as time without an order: one of 300 or more makes every player AFK and the match pays nothing ("💤 No reward": no XP, Glory, quests, achievements, season XP or leaderboard points). To finish a match with its rewards, jump in steps under 300 (250, 500, 750, 1000, 1250, 1499) and give an order after each. |
| `DevCharges` | number | Every nation and Primordial gets this many power charges. |
| `DevGold` | number | Every nation with a player gets this much gold. |
| `DevDay` | number | Moves the server's UTC day this many days on (new daily quests, the login calendar and streak, the first-match bonus, the rotating shop, and the season the day falls in). Within 5 seconds everyone gets the new day's quests. `1` = tomorrow; `2` skips a day (the streak's covered missed day). Applied during a match or on Results, not in the Lobby. |

## Recipes

Start a test from the Test tab. Use Device to pick a phone in landscape (the UI is built for 844×390), and check the Output window for errors.

| What | How |
| --- | --- |
| A solo match | Set `SkipLobby`. Play: you and 9 bots. Tap a province, press Develop or +1 Regiment; tap your army, Move, tap a target, Go. |
| Map vote and draft | Clients and Servers, 3 players. Tap a card twice to vote; when it's your turn, tap a nation's land and press "Pick …". |
| Private server settings | Set `PrivateServerOwner` = `true`, Clients and Servers, 2 players. Player1 taps Settings (bottom right), picks 15 min, Hard, Powers Off, taps Player1 and Player2 under Teams (both "Team 1"), then Done. Player2 has no Settings button and sees the summary line (lock icon, "Private server · …") under the cards. When the match starts: the clock shows 15:00, no purple power button, both players are allies. `DevTick` = 599 starts the Cataclysm (10:00), 899 ends the match at 15:00. To see the reward line ("🔒 Private server: half") jump in steps under 300 (250, 500, 750, 899) and give an order after each: 5 minutes without an order counts as AFK and pays nothing. |
| War and battles | `DevTick` = 179. Tap a neighbour, Declare war, march an army in. Watch the dust, the crossed swords and the capture rings. |
| Primordial powers | `DevCharges` = 5. Press the purple power button (sparkles, charges in its badge), pick a power, tap a target, Confirm. Meteor shakes the screen; a second harmful power on the same nation within 30 s is refused ("immune"). |
| Becoming a Primordial | With 2 players at War, let one player's nation lose its capital and all but 2 provinces (or give its land away on the server). That player's top bar says "Primordial" (sparkles icon) and they cast powers. |
| Cataclysm and Results | `DevTick` = 1199, then 1499. Check the banners and the Results screen. For the XP and Glory breakdown, get there in steps under 300 with an order after each (see `DevTick`): one big jump pays nothing ("💤 No reward"). |
| Tutorial | Set `Tutorial`, Play solo, follow the six prompts; "⏭ Skip" takes two taps. Remove the attribute during the test (server's Workspace): the next match is a normal one and you get a nation in it. The "🌍 Play online" button and the teleports only show in a published game. |
| Map themes and the theme vote | Clients and Servers, 2 players. In the Lobby each opens 🛒 → Themes and equips a theme (free in Studio test mode); the vote cards repaint in it. Both vote for the same map: the draft says "🌙 Night Earth, brought by …" and both maps are painted in it. One player taps 🛒 → Themes → "Always classic": their map goes back to the classic look. Solo: set `SkipLobby` and `Theme` = `theme_winter`. |
| Power-effect looks | In the Lobby, 🛒 → Powers, equip Comet Strike, Violet Plague and Sun Rays. In the match set `DevCharges` = 5 and `DevTick` = 179, then cast Meteor, Plague and Blessing: both players see your looks; the area, timing and sounds are the same as the default. |
| Shop | In the Lobby tap 🛒 (or 🛒 in the top bar during a match). While the ids are 0, Robux items are free in Studio ("Studio test mode"). Equip a flag and check it by your capital and in the nations list (globe button). |
| Sounds | Every sound id is in `src/client/Sounds.luau`. They are stand-ins: the default character sounds every client ships, at different pitches. To try one: the client command bar, `require(game.Players.LocalPlayer.PlayerScripts.Client.Sounds).play("MeteorImpact")`. For the real game, pick sounds in the Creator Store (Toolbox → Audio), copy each id and put `rbxassetid://<id>` in the table. The speaker icon at the right end of the top bar mutes. |
| Quests, calendar, streak | Lobby: tap 📜 (bottom left, next to 🛒); in a match: the globe button → Quests (gold button in the drawer). Finish a match after doing what a quest asks, e.g. recruit 5 regiments (`DevTick` in steps under 300 with an order after each, see `DevTick`: a jump straight to 1499 counts as AFK and moves nothing): Results lists the quests it moved and the calendar step; tap "📜 Quests · 1 to claim" → Claim. Tap "🔄 Free" on a daily quest to reroll it (the next one costs 100 Glory). Set `DevDay` = 1 and finish another match: the calendar moves to step 2 and the streak to 2; at 3 days a 🔥 appears after your nation in the 🌍 list. |
| Rewarded video quest reroll | While `quest_reroll` in `Catalogue.PRODUCT_IDS` is 0 (Studio test mode). Play solo (no `SkipLobby`: ads only play during the map vote, while 32 s or more are left), tap 📜 in the first half of the vote, tap "🔄 Free" on a daily quest: "📺 Watch an ad (test) · +1 free reroll · 2 left today" appears in the header. Tap it: no video in test mode, the header says "1 free reroll today" and the button hides until you spend it. Spend it, watch the second one, spend it: the button is gone for the day ("Rerolls: 100🏅"). Start the match (or tap 🌍 → "📜 Quests" in a match): no button. With a real product id, Studio asks `AdService` and the button only shows if it answers `IsAvailable` (in Studio it usually doesn't, so test the live button in the published game with an account 13+). |
| Notification prompt | Turn on Studio Access to API Services with a fresh test account (or clear `settings.notificationsAsked` in its save), Play solo without `SkipLobby`, vote, and finish the match without it counting as idle (an AFK match never asks): jump `DevTick` in steps under 300 (250, 500, 750, 1000, 1250, 1499) and give an order after each. Back in the next Lobby, 2 s later, Roblox's "Enable notifications" prompt opens if `CanPromptOptInAsync` says yes (Studio may say no; the Output shows nothing either way). It never comes again for that profile. With `TelemetryLog`: `notification_opt_in shown` or `ineligible`. |
| Season pass | Season 1's days are in `Config.Season.Seasons` (from 2026-10-23 for 8 weeks): if today is outside them, the 🎟 screen says when the next season starts, so move `startDay` (UTC days since 1970) to test. Play solo. In the Lobby tap 🎟 (bottom left, next to 📜): tier 1's GG emote has a Claim button, the premium cells say "🎟 Pass". Claim it. Finish a match (`DevTick` in steps under 300 with an order after each; a jump straight to 1499 counts as AFK and pays no XP): the Results screen has "🎟 Season · tier N" next to 📜 Quests, and the season XP grew by the match XP. Tap it, then "🎟 Pass R$ 299" (free in Studio test mode, through the receipt path): every premium reward up to your tier gets a Claim button; "Claim all" takes them. The pass and bundle buttons are grey during a match (purchases open in the Lobby, the draft and on Results). In the shop, 🛒 → Tokens shows the Ember Knight once claimed; equip it. |
| Rotating shop | 🛒 → 🔄 Today: 4 daily cards (2 Common, 1 Rare, 1 Epic) and 2 weekly ones (a Legendary item and a nation skin set), with the time until each section changes. Two test sessions on the same UTC day (or Studio and a live server) show the same cards: the schedule depends only on the day. A rotating item in its slot tab says "🔄 Not today · Back within 60 days". Set `DevDay` = 1 during a match: within 5 seconds the Today tab shows the next day's cards (the weekly ones change on Mondays). |
| Analytics | Set `TelemetryLog` (and nothing else), Clients and Servers, 2 players. In the server's Output: `Onboarding … joined`, `lobby_loaded`, `MatchFlow … lobby`; tap 🛒 and a tab (`Shop … shop_opened`, `item_viewed`); vote (`map_vote` when the vote ends); `DevTick` = 1499 for `nation_start`, `match_end`, `match_win` and `player_result`. The Glory `match_reward` and `AccountLevel` events need a match without a `DevTick` jump (a jump counts as idle time, and an AFK match pays nothing). Live: Creator Hub → your experience → Analytics (Funnels, Economy, Progression, Custom Events), about 24 hours later. |
| Achievements | In the Lobby tap 🏆 (bottom left, after 🛒 and 📜): 30 achievements on 2 pages (◀ ▶). Play a match and win it: hand your nation half the land on the server (or recruit and conquer), or jump `DevTick` to 1499 in steps under 300 (an order after each) while you lead on score; one big jump counts as AFK and earns nothing. Results lists "🏆 Unlocked: …" and a "🏆 Achievements" Glory line; the 🏆 button there opens the screen with the new ones outlined in gold. A Domination win gives the title "the Dominant": tap "🎖 No title ▸" to wear it; in the next match 🌍 shows it after your nation's name. 🛒 → Frames shows Centurion and Warlord as "🏆 Achievement" / "⚔ Weekly top 100" (never sold). |
| Leaderboards | Clients and Servers, **4 players** (points need a public match with 4+ players), no `SkipLobby`. Play a match to Results (`DevTick` in steps under 300, 250, 500, … 1499, with an order from each player after each jump: one jump straight to 1499 makes everyone AFK and nobody scores). Tap 🏆 → 📅 Weekly: everyone's points (10, 7, 5, 3, 3, then 1 by place), "You: N pts · #rank"; 👥 Friends: only you and your Roblox friends (test accounts have none, so just you); 🌍 Level: account XP. Without Studio Access to API Services the boards live in the server's memory ("🧪 not saved"); with it they use Studio's own OrderedDataStores (`Conquest_Studio`, `Level_Studio`), never the live boards. To see the weekly reset and the Warlord frame: set `DevDay` = 7 on the server after a match; within 2 minutes the boards start a new week at 0 points and last week's top 100 own the Warlord frame (🛒 → Frames). |
| Saving | Turn on Studio Access to API Services, finish a match, stop, play again: the level chip (medal icon) and Glory are still there. Equips and the "Always classic" setting are saved with the autosave and when you leave (stop the test normally, don't close Studio); Glory purchases, rewards and Robux purchases are saved at once. |
| UI kit and pixel icons | Any test on a phone device (Device → a phone in landscape). Every icon in the top bar, sheets and buttons is a crisp pixel sprite, not an emoji. Press and hold a button: it squashes and its darker bottom edge sinks; release to spring back. Turn off Allow Mesh / Image APIs (Experience Settings → Security) and play again: the icons fall back to emoji, every button still works. On the narrowest phone in the Device list the top bar drops the level, rank and colour swatch rather than running off screen. |

## Before publishing

- Allow Mesh / Image APIs is on.
- The stand-in sounds in `Sounds.luau` are replaced with Creator Store or uploaded sounds you like.
- The VIP game pass and the developer products (including "Quest reroll" at 10 Robux, `season_pass` and `season_bundle`) exist, and their ids are in `src/shared/Catalogue.luau` (docs/MONETIZATION.md 3.10); rewarded video serving is on with "Quest reroll" as its reward.
- `Config.Season.Seasons` has the real Season 1 dates.
- The soft-launch checklist in docs/LAUNCH.md.
