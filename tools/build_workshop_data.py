#!/usr/bin/env python3
"""Build the data files for the RCRotations Workshop desktop app.

  python3 tools/build_workshop_data.py --sims <wowsims/mop checkout> --out app/data

Writes:
  rotations.json  every bundled WoWSims rotation (the same set as SimData_Mists.lua),
                  with class token and spec index so the app can save it for the
                  right spec in game
  names.json      spell and item names for the rotations' IDs (from the WoWSims
                  database, assets/database/*.json, plus a few common ones it lacks)

The nightly sync job runs this, so the app can pull fresh rotations from GitHub.
"""
import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wowsims_convert as conv  # noqa: E402

# Cast spells the WoWSims database has no name for.
EXTRA_NAMES = {
    5229: "Enrage", 6940: "Hand of Sacrifice", 14751: "Chakra: Chastise", 16857: "Faerie Fire",
    19574: "Bestial Wrath", 22812: "Barkskin", 22842: "Frenzied Regeneration", 34026: "Kill Command",
    47585: "Dispersion", 48566: "Mangle", 48572: "Shred", 48574: "Rake", 48577: "Ferocious Bite",
    49376: "Wild Charge", 49800: "Rip", 50213: "Tiger's Fury", 50613: "Arcane Torrent", 53401: "Rabid",
    58984: "Shadowmeld", 61336: "Survival Instincts", 62606: "Savage Defense", 74497: "Lifeblood",
    80313: "Pulverize", 82174: "Synapse Springs", 82692: "Focus Fire", 102558: "Incarnation: Son of Ursoc",
    102560: "Incarnation: Chosen of Elune", 104316: "Imp Swarm", 106922: "Might of Ursoc",
    108293: "Heart of the Wild", 111897: "Grimoire: Felhunter", 111898: "Grimoire: Felguard",
    114852: "Holy Prism", 114916: "Execution Sentence", 120696: "Halo", 122128: "Divine Star",
    127632: "Cascade", 129197: "Mind Flay (Insanity)", 129597: "Arcane Torrent", 103964: "Touch of Chaos",
    603: "Doom", 124916: "Chaos Wave", 104027: "Soul Fire (Metamorphosis)",
}


def load_names(sims):
    spells, items = {}, {}
    for fname in ("leftover_db.json", "db.json"):
        path = os.path.join(sims, "assets", "database", fname)
        if not os.path.exists(path):
            continue
        db = json.load(open(path))
        for x in db.get("spellIcons", []):
            spells[x["id"]] = x["name"]
        for key in ("items", "itemIcons", "consumables"):
            for x in db.get(key, []):
                if "name" in x:
                    items[x["id"]] = x["name"]
    for k, v in EXTRA_NAMES.items():
        spells.setdefault(k, v)
    return spells, items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sims", required=True)
    ap.add_argument("--custom", help="rotations/mists folder with your own rotations")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    rots = []
    for cls, (token, specs) in sorted(conv.SPECS.items()):
        for spec, idx in sorted(specs.items(), key=lambda kv: kv[1]):
            folders = [os.path.join(a.sims, "ui", "specs", cls, spec, "apls")]
            if a.custom:
                folders.append(os.path.join(a.custom, cls, spec))
            for folder in folders:
                if not os.path.isdir(folder):
                    continue
                for fn in sorted(os.listdir(folder)):
                    if not fn.endswith(".json"):
                        continue
                    raw = json.load(open(os.path.join(folder, fn)))
                    rot = conv.find_rotation(raw)
                    # same rule as wowsims_convert.py, so the app lists what the addon bundles
                    if not rot or rot.get("type", "TypeAPL") != "TypeAPL" or not rot.get("priorityList"):
                        continue
                    custom = folder != folders[0]
                    stem = re.sub(r"(\.apl)?\.json$", "", fn)
                    rots.append({
                        "cls": cls, "spec": spec, "token": token, "specIndex": idx,
                        "name": conv.pretty_name(stem) + (" (custom)" if custom else ""),
                        "file": "%s%s/%s/%s" % ("custom/" if custom else "", cls, spec, stem),
                        "rotation": rot,
                    })
    rots.sort(key=lambda r: (r["cls"], r["specIndex"], not r["file"].endswith("/default"), r["file"]))

    spells, items = load_names(a.sims)
    text = json.dumps([r["rotation"] for r in rots])
    need_s = {int(x) for x in re.findall(r'"spellId": ?(\d+)', text)}
    need_i = {int(x) for x in re.findall(r'"itemId": ?(\d+)', text)}
    names = {"spells": {str(i): spells[i] for i in sorted(need_s) if i in spells},
             "items": {str(i): items[i] for i in sorted(need_i) if i in items}}

    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "rotations.json"), "w") as f:
        json.dump({"source": "wowsims/mop", "rotations": rots}, f, separators=(",", ":"), sort_keys=True)
    with open(os.path.join(a.out, "names.json"), "w") as f:
        json.dump(names, f, separators=(",", ":"), sort_keys=True)
    print("wrote %d rotations, %d spell names" % (len(rots), len(names["spells"])))


if __name__ == "__main__":
    main()
