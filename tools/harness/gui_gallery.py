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
