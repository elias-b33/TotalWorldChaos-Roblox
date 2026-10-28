"""Before/after gallery for UI work: puts the same harness screenshot from two runs side by side and counts the GUI
objects (every instance under each ScreenGui: frames, labels, strokes, corners...) from the kept scene files.

    KEEP_SCENE=1 lune run tools/harness/play smoke      # in both checkouts (before and after), then:
    python3 tools/harness/gui_gallery.py BEFORE_OUT AFTER_OUT [OUT_DIR]

BEFORE_OUT and AFTER_OUT are tools/harness/out folders; the gallery goes to OUT_DIR (default tools/harness/out/gui):
one PNG per shot plus counts.md.
"""

from __future__ import annotations

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

# (scenario/shot, caption, ScreenGuis whose objects are counted)
SHOTS = [
    ("smoke/02_capital", "Top bar and province sheet (your capital)", ["Hud", "ProvinceSheet"]),
    ("smoke/04_foreign", "Province sheet (a neighbour)", ["ProvinceSheet"]),
    ("war/01_route_preview", "Army sheet (route preview)", ["ArmySheet"]),
    ("war/08_peace_offer", "Offer card, toast and peace buttons", ["Offers", "Hud", "ProvinceSheet"]),
    ("war/09_nations", "Nations drawer", ["Nations"]),
    ("primordial/01_primordial", "Primordial: top bar and banner", ["Hud", "Powers"]),
    ("primordial/02_picker", "Power picker", ["Powers"]),
    ("primordial/03_target", "Power target bar", ["Powers"]),
    ("lobby/01_vote", "Map vote", ["MapVote"]),
    ("lobby/02_voted", "Map vote (voted)", ["MapVote"]),
    ("lobby/03_draft", "Nation draft", ["Draft"]),
    ("private/01_vote_summary", "Private server: summary and Settings button", ["PrivateSettings"]),
    ("private/03_settings_custom", "Private server settings", ["PrivateSettingsSheet"]),
    # the meta screens (step 2A)
    ("leaderboards/01_lobby_button", "Lobby round buttons", ["Shop", "QuestsButton", "TrophiesButton", "SeasonButton"]),
    ("shop/01_starter_offer", "Starter-pack offer", ["Shop"]),
    ("shop/02_shop_offers", "Shop: Offers", ["Shop"]),
    ("shop/03_shop_flags", "Shop: Flags (Robux and Glory prices)", ["Shop"]),
    ("shop/04_shop_flag_equipped", "Shop: equipped, not today, VIP only", ["Shop"]),
    ("shop/05_shop_emotes", "Shop: Emotes (owned)", ["Shop"]),
    ("shop/06_shop_history", "Shop: purchase history", ["Shop"]),
    ("themes/01_shop_themes", "Shop: Themes and the opt-out card", ["Shop"]),
    ("themes/02_shop_powers", "Shop: Powers", ["Shop"]),
    ("leaderboards/09_shop_frames", "Shop: Frames (earned, not sold)", ["Shop"]),
    ("season/09_shop_day1", "Shop: Today (the rotating shop)", ["Shop"]),
    ("season/11_shop_offers", "Shop: Offers with the season pass card", ["Shop"]),
    ("season/02_season_screen", "Season pass", ["Season"]),
    ("season/05_pass_bought", "Season pass: pass bought", ["Season"]),
    ("season/08_season_last_page", "Season pass: last page and bonus", ["Season"]),
    ("quests/02_lobby_quests", "Quests", ["Quests"]),
    ("quests/06_rerolled", "Quests: claimed and rerolled", ["Quests"]),
    ("quests/07_calendar_streak", "Quests: calendar and streak", ["Quests"]),
    ("ads/02_ad_button_test_mode", "Quests: Watch an ad", ["Quests"]),
    ("leaderboards/02_lobby_trophies", "Trophies: achievements", ["Trophies"]),
    ("leaderboards/04_achievements", "Trophies: achievements done", ["Trophies"]),
    ("leaderboards/05_weekly", "Trophies: weekly board", ["Trophies"]),
    ("leaderboards/07_level", "Trophies: level board", ["Trophies"]),
    ("shop/07_map_flag_emote", "Emote button", ["Emotes"]),
    ("tutorial/12_prompt5_button", "Tutorial glow on Declare war", ["ProvinceSheet"]),
    # step 2B: the match screens and the map overlays
    ("progression/01_results_reward", "Results: standings, reward breakdown, level bar", ["Results"]),
    ("quests/04_results_quests", "Results: quests moved, Quests button", ["Results"]),
    ("season/03_results", "Results with the season pass button", ["Results"]),
    ("leaderboards/03_results", "Results: achievements unlocked", ["Results"]),
    ("tutorial/01_prompt1_army", "Tutorial card, map arrow and ring", ["Tutorial", "TutorialPointer"]),
    ("tutorial/07_prompt2_button", "Tutorial hint, button arrow and glow", ["Tutorial", "ProvinceSheet"]),
    ("tutorial/13_prompt6_power", "Tutorial: the power button prompt", ["Tutorial"]),
    ("tutorial/16_done", "Tutorial end card", ["Tutorial"]),
    ("tutorial/17_skip_confirm", "Tutorial Skip, second tap", ["Tutorial"]),
    ("tutorial/18_skipped_play_online", "Play online after Skip", ["Tutorial"]),
    ("effects/01_phase_war", "War banner", ["Effects"]),
    ("effects/12_phase_cataclysm", "Cataclysm banner and a siege pill", ["Effects", "Map"]),
    ("effects/13_phase_results", "Results banner over the results", ["Effects", "Results"]),
    ("look/01_whole_map", "Map overlays: whole map", ["Map"]),
    ("look/02_region", "Map overlays: region zoom, pip bars and garrisons", ["Map"]),
    ("look/03_close_up", "Map overlays: close-up layer, garrisons, pip bars", ["Map"]),
    ("look/04_mountain", "Names over the close-up layer: mountains", ["Map"]),
    ("look/05_coast", "Names over the close-up layer: coast", ["Map"]),
    ("look/06_forest", "Names over the close-up layer: forest", ["Map"]),
    ("look/07_overlays_whole", "Overlays zoomed out: icon-only pills", ["Map"]),
    ("look/08_overlays_region", "Overlays at the region zoom: siege, powers, selection", ["Map"]),
    ("look/09_overlays_close", "Overlays close up: status row over the selected army", ["Map"]),
    ("war/02_marching", "Army badges, names and pips (region zoom)", ["Map"]),
    ("war/04_siege", "Siege pill stacked over the army badge", ["Map"]),
    ("war/10_crown", "Coalition crown on the flag pole", ["Map"]),
    ("primordial/07_rebels", "Whole map: sieges and the Rebels badge", ["Map"]),
    ("primordial/08_rebels_close", "Rebels badge and siege pills", ["Map"]),
    ("retreat/02_retreating", "Retreating army beside the winner", ["Map"]),
    ("effects/11_shield", "Battle and power pills", ["Map"]),
    # races and troops on the map: race soldiers, the main troop's badge icon, each race's capital
    ("races/06_ironguard_siege", "Races: a dwarf army besieging (soldier token, troop icon badges)", ["Map"]),
    ("races/07_archers_hold", "Races: archers holding a province, capitals by race (Eldmoor)", ["Map"]),
    ("races/08_archers_attack", "Races: archers attacking, an orc capital (Eldmoor)", ["Map"]),
    ("kingdoms/01_whole_map", "Kingdoms: a soldier of its race by every capital (whole map)", ["Map"]),
    ("kingdoms/02_humans_region", "Kingdoms: Humans at the region zoom (knights badge)", ["Map"]),
    ("kingdoms/03_humans_close", "Kingdoms: the Humans' capital close up", ["Map"]),
    ("kingdoms/04_elves_region", "Kingdoms: Elves at the region zoom (archers badge)", ["Map"]),
    ("kingdoms/05_elves_close", "Kingdoms: the Elves' tree hall close up", ["Map"]),
    ("kingdoms/06_orcs_region", "Kingdoms: Orcs at the region zoom (berserkers badge)", ["Map"]),
    ("kingdoms/07_orcs_close", "Kingdoms: the Orcs' war camp close up", ["Map"]),
    ("kingdoms/08_dwarves_region", "Kingdoms: Dwarves at the region zoom (ironguard badge)", ["Map"]),
    ("kingdoms/09_dwarves_close", "Kingdoms: the Dwarves' stone hall close up", ["Map"]),
    ("kingdoms/10_orc_capital_sheet", "Kingdoms: province sheet of an Orc capital (race and troop chips)", ["ProvinceSheet", "Map"]),
]

LABEL_H = 44
FONT = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"


def count(node) -> int:
    return sum(1 + count(c) for c in node.get("children", []))


def counts(scene_path: str, screens):
    if not os.path.exists(scene_path):
        return None
    with open(scene_path) as f:
        scene = json.load(f)
    by_name = {}
    for sg in scene["gui"]:
        by_name[sg["name"]] = by_name.get(sg["name"], 0) + count(sg)
    total = sum(by_name.values())
    return {name: by_name.get(name, 0) for name in screens}, total


def main(before: str, after: str, out: str):
    os.makedirs(out, exist_ok=True)
    font = ImageFont.truetype(FONT, 26) if os.path.exists(FONT) else ImageFont.load_default()
    rows = ["| Screen | Counted ScreenGuis | Before | After | Whole PlayerGui before | after |", "|---|---|---|---|---|---|"]
    for shot, caption, screens in SHOTS:
        a, b = os.path.join(before, shot + ".png"), os.path.join(after, shot + ".png")
        if not (os.path.exists(a) and os.path.exists(b)):
            print("skip (missing):", shot)
            continue
        ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
        w, h = ia.width + ib.width + 16, max(ia.height, ib.height) + LABEL_H
        img = Image.new("RGB", (w, h), (24, 24, 30))
        img.paste(ia, (0, LABEL_H))
        img.paste(ib, (ia.width + 16, LABEL_H))
        d = ImageDraw.Draw(img)
        d.text((12, 8), "BEFORE  ·  " + caption, font=font, fill=(200, 200, 210))
        d.text((ia.width + 28, 8), "AFTER", font=font, fill=(245, 194, 66))
        name = shot.replace("/", "_") + ".png"
        img.save(os.path.join(out, name))
        ca, cb = counts(os.path.join(before, shot + ".json"), screens), counts(os.path.join(after, shot + ".json"), screens)
        if ca and cb:
            per_a = " + ".join(f"{ca[0][s]}" for s in screens)
            per_b = " + ".join(f"{cb[0][s]}" for s in screens)
            rows.append(f"| {caption} | {', '.join(screens)} | {per_a} | {per_b} | {ca[1]} | {cb[1]} |")
        print("wrote", os.path.join(out, name))
    with open(os.path.join(out, "counts.md"), "w") as f:
        f.write("GUI objects (every instance under the ScreenGui, visible or not) at each shot.\n\n")
        f.write("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "tools/harness/out/gui")
