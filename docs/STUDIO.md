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
| Enable Studio Access to API Services | Optional. Real saves (XP, Glory, items) in Studio. Without it ProfileStore uses an in-memory store: everything works and nothing is kept. With it, Studio test purchases save to your own account. |

## Test switches (Workspace attributes)

Select Workspace in the Explorer and add attributes in the Properties window.

| Attribute | Type | Effect |
| --- | --- | --- |
| `SkipLobby` | boolean | Matches start straight in Peace (no map vote or draft) and restart on the same map. Handy for solo tests. |
| `MapId` | string | Locks the map: `earth`, `eldmoor` or `skyshards`. |
| `Theme` | string | Forces a map theme and skips the theme vote: `theme_night`, `theme_winter`, `theme_autumn`, or `theme_classic` for the classic look (what the private-server setting will do). |
| `Tutorial` | boolean | This server plays the tutorial match (in a live game, new players are teleported to one). |

These three are Studio-only. Set them during a test run on the **server's** Workspace (in Clients and Servers, the Server window). Each is applied once on the next game second and then removed:

| Attribute | Type | Effect |
| --- | --- | --- |
| `DevTick` | number | Sets the match clock in seconds: `179` is War in a second, `1199` the Cataclysm, `1499` the end of the match. |
| `DevCharges` | number | Every nation and Primordial gets this many power charges. |
| `DevGold` | number | Every nation with a player gets this much gold. |

## Recipes

Start a test from the Test tab. Use Device to pick a phone in landscape (the UI is built for 844×390), and check the Output window for errors.

| What | How |
| --- | --- |
| A solo match | Set `SkipLobby`. Play: you and 9 bots. Tap a province, press Develop or +1 Regiment; tap your army, Move, tap a target, Go. |
| Map vote and draft | Clients and Servers, 3 players. Tap a card twice to vote; when it's your turn, tap a nation's land and press "✔ Pick …". |
| War and battles | `DevTick` = 179. Tap a neighbour, Declare war, march an army in. Watch the dust, the crossed swords and the capture rings. |
| Primordial powers | `DevCharges` = 5. Press ✨, pick a power, tap a target, Confirm. Meteor shakes the screen; a second harmful power on the same nation within 30 s is refused ("immune"). |
| Becoming a Primordial | With 2 players at War, let one player's nation lose its capital and all but 2 provinces (or give its land away on the server). That player sees "✨ Primordial" and casts powers. |
| Cataclysm and Results | `DevTick` = 1199, then 1499. Check the banners, the Results screen and the XP and Glory breakdown. |
| Tutorial | Set `Tutorial`, Play solo, follow the six prompts; "⏭ Skip" takes two taps. |
| Map themes and the theme vote | Clients and Servers, 2 players. In the Lobby each opens 🛒 → Themes and equips a theme (free in Studio test mode); the vote cards repaint in it. Both vote for the same map: the draft says "🌙 Night Earth, brought by …" and both maps are painted in it. One player taps 🛒 → Themes → "Always classic": their map goes back to the classic look. Solo: set `SkipLobby` and `Theme` = `theme_winter`. |
| Power-effect looks | In the Lobby, 🛒 → Powers, equip Comet Strike, Violet Plague and Sun Rays. In the match set `DevCharges` = 5 and `DevTick` = 179, then cast Meteor, Plague and Blessing: both players see your looks; the area, timing and sounds are the same as the default. |
| Shop | In the Lobby tap 🛒 (or 🛒 in the top bar during a match). While the ids are 0, Robux items are free in Studio ("Studio test mode"). Equip a flag and check it by your capital and in the 🌍 list. |
| Sounds | Every sound id is in `src/client/Sounds.luau`. Play each one once (the client command bar: `require(game.Players.LocalPlayer.PlayerScripts.Client.Sounds).play("MeteorImpact")`) and swap any that is missing. 🔊 in the top bar mutes. |
| Saving | Turn on Studio Access to API Services, finish a match, stop, play again: the level badge (🎖) and Glory are still there. |

## Before publishing

- Allow Mesh / Image APIs is on.
- Every sound in `Sounds.luau` plays.
- The VIP game pass and the developer products exist, and their ids are in `src/shared/Catalogue.luau` (docs/MONETIZATION.md 3.10).
- The soft-launch checklist in docs/LAUNCH.md.
