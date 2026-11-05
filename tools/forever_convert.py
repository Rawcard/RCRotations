#!/usr/bin/env python3
"""Build SimData_Forever.lua: the WoWSims Forever rotations, plus the 1-20
starter rotations, for WoW Forever.

    tools/forever_export.sh <wowsims/forever checkout> <export dir>
    python3 tools/forever_convert.py --sims <wowsims/forever checkout> \
        --export <export dir> --out SimData_Forever.lua --report forever-report.md

WoWSims Forever (https://github.com/wowsims/forever) is MIT licensed. Its
rotations are written in JSON or in SIML; forever_export.sh turns the SIML ones
into JSON with the WoWSims CLI, then this file converts them all with the same
converter as the MoP rotations (wowsims_convert.py).

Every rotation carries:
  role     the playstyle it's for: "damage", "tank", or for Hunters and
           Shamans "range"/"melee"/"caster"; healer rotations aren't bundled
           (WoWSims heals a simulated raid; the built-in heal lists stay)
  talents  points per talent tree of the WoWSims build it was made for, so
           the addon can pick the one closest to your talents
  style    optional: a Paladin playstyle it belongs to ("twist", "shockadin")
Starter rotations (rotations/forever/starters/<class>.json, written by hand)
are used below level 20.
"""
import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wowsims_convert import Converter, find_rotation, lua  # noqa: E402

CLASSES = {
    "druid": "DRUID", "hunter": "HUNTER", "mage": "MAGE", "paladin": "PALADIN", "priest": "PRIEST",
    "rogue": "ROGUE", "shaman": "SHAMAN", "warlock": "WARLOCK", "warrior": "WARRIOR",
}

# What to bundle. file: path in the export dir. talents: "build" (in the file),
# ("preset", "<class>/<spec>", "<ConstName>") from that spec's presets.ts,
# ("defaults", "<class>/<spec>") from its defaults.siml, or None (only
# rotation for its role). rotation: for build files with no rotation of their
# own, the APL file they use.
SOURCES = [
    # Druid
    {"file": "druid/balance/apls/default.apl.json", "name": "Balance", "role": "damage",
     "talents": ("preset", "druid/balance", "StandardTalents")},
    {"file": "druid/feralcat/apls/adaptive.apl.json", "name": "Feral Cat", "role": "damage",
     "talents": ("preset", "druid/feralcat", "CatTalents")},
    {"file": "druid/feralbear/apls/adaptive.apl.json", "name": "Feral Bear", "role": "tank",
     "talents": ("preset", "druid/feralbear", "BearTalents")},
    # Hunter (the builds carry their talents and rotation)
    {"file": "hunter/dps/builds/bm.json", "name": "Beast Mastery", "role": "range", "talents": "build"},
    {"file": "hunter/dps/builds/bm_weave.json", "name": "Beast Mastery (melee weave)", "role": "range", "talents": "build"},
    {"file": "hunter/dps/builds/mm.json", "name": "Marksmanship", "role": "range", "talents": "build"},
    {"file": "hunter/dps/builds/mm_weave.json", "name": "Marksmanship (melee weave)", "role": "range", "talents": "build"},
    {"file": "hunter/dps/builds/sv.json", "name": "Survival", "role": "range", "talents": "build"},
    {"file": "hunter/dps/builds/sv_weave.json", "name": "Survival (melee weave)", "role": "range", "talents": "build"},
    {"file": "hunter/dps/builds/sv_melee.json", "name": "Survival (melee)", "role": "melee", "talents": "build"},
    # Mage
    {"file": "mage/dps/apls/arcane.apl.json", "name": "Arcane", "role": "damage",
     "talents": ("preset", "mage/dps", "ArcaneTalents")},
    {"file": "mage/dps/apls/arcaneFireFill.apl.json", "name": "Arcane / Fire", "role": "damage",
     "talents": ("preset", "mage/dps", "ArcaneFireTalents")},
    {"file": "mage/dps/apls/deepFire.apl.json", "name": "Fire", "role": "damage",
     "talents": ("preset", "mage/dps", "FireTalents")},
    {"file": "mage/dps/apls/ffb.apl.json", "name": "Frostfire", "role": "damage",
     "talents": ("preset", "mage/dps", "FFBTalents")},
    {"file": "mage/dps/apls/frost.apl.json", "name": "Frost", "role": "damage",
     "talents": ("preset", "mage/dps", "FrostIncinTalents")},
    # Paladin
    {"file": "paladin/retribution/builds/unsealed_wrath.json", "rotation": "paladin/retribution/apls/default.apl.json",
     "name": "Retribution (Unsealed Wrath twist)", "role": "damage", "style": "twist", "talents": "build"},
    {"file": "paladin/retribution/builds/holy_shock.json", "rotation": "paladin/retribution/apls/holy_shock.apl.json",
     "name": "Shockadin (Holy Shock)", "role": "damage", "style": "shockadin", "talents": "build"},
    {"file": "paladin/protection/apls/default.apl.json", "name": "Protection", "role": "tank",
     "talents": ("defaults", "paladin/protection")},
    # Priest
    {"file": "priest/dps/builds/testing.build.json", "name": "Shadow", "role": "damage", "talents": "build"},
    {"file": "priest/dps/builds/smite_testing.build.json", "name": "Smite", "role": "damage", "talents": "build"},
    # Rogue
    {"file": "rogue/dps/apls/default.apl.json", "name": "Rogue", "role": "damage", "talents": None},
    # Shaman
    {"file": "shaman/elemental/builds/testing.build.json", "name": "Elemental", "role": "caster", "talents": "build"},
    {"file": "shaman/enhancement/builds/testing.build.json", "name": "Enhancement", "role": "melee", "talents": "build"},
    # Warlock
    {"file": "warlock/dps/builds/aff_wrack.build.json", "name": "Affliction (Wrack)", "role": "damage", "talents": "build"},
    {"file": "warlock/dps/builds/demo_fire_brand.build.json", "name": "Demonology (Fire Brand)", "role": "damage", "talents": "build"},
    {"file": "warlock/dps/builds/demo_shadow_brand.build.json", "name": "Demonology (Shadow Brand)", "role": "damage", "talents": "build"},
    {"file": "warlock/dps/builds/destro.build.json", "name": "Destruction", "role": "damage", "talents": "build"},
    {"file": "warlock/dps/builds/sm_ruin.build.json", "name": "SM / Ruin", "role": "damage", "talents": "build"},
    # Warrior
    {"file": "warrior/dps/apls/arms.apl.json", "name": "Arms", "role": "damage",
     "talents": ("preset", "warrior/dps", "ArmsTalents")},
    {"file": "warrior/dps/apls/fury.apl.json", "name": "Fury", "role": "damage",
     "talents": ("preset", "warrior/dps", "FuryTalents")},
    {"file": "warrior/protection/apls/default.apl.json", "name": "Protection", "role": "tank",
     "talents": ("preset", "warrior/protection", "ProtectionTalents")},
]


def tree_points(talents):
    """'050250002-501-0523' -> [points in tree 1, 2, 3]."""
    trees = (talents or "").split("-")
    out = []
    for i in range(3):
        digits = trees[i] if i < len(trees) else ""
        out.append(sum(int(c) for c in digits if c.isdigit()))
    return out


def preset_talents(sims, spec_dir, const):
    path = os.path.join(sims, "ui", "specs", spec_dir, "presets.ts")
    text = open(path, encoding="utf-8").read()
    m = re.search(r"const\s+%s\s*=\s*PresetUtils\.makePresetTalents\([^;]*?talentsString:\s*'([^']*)'" % re.escape(const),
                  text, re.S)
    if not m:
        raise SystemExit("talents %s not found in %s" % (const, path))
    return m.group(1)


def defaults_talents(sims, spec_dir):
    path = os.path.join(sims, "ui", "specs", spec_dir, "defaults.siml")
    m = re.search(r'^talents\s+"([^"]*)"', open(path, encoding="utf-8").read(), re.M)
    if not m:
        raise SystemExit("talents not found in " + path)
    return m.group(1)


def git_head(path):
    try:
        sha = subprocess.check_output(["git", "-C", path, "rev-parse", "HEAD"], text=True).strip()
        date = subprocess.check_output(["git", "-C", path, "log", "-1", "--format=%cs"], text=True).strip()
        return sha, date
    except Exception:
        return "unknown", datetime.date.today().isoformat()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sims", required=True, help="wowsims/forever checkout (for talents in presets)")
    ap.add_argument("--export", required=True, help="JSON from tools/forever_export.sh")
    ap.add_argument("--starters", default=None, help="rotations/forever/starters")
    ap.add_argument("--out", default="SimData_Forever.lua")
    ap.add_argument("--report", default=None)
    ap.add_argument("--summary", default=None)
    args = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    starters = args.starters or os.path.join(root, "rotations", "forever", "starters")

    conv = Converter()
    sha, date = git_head(args.sims)
    data = {}
    rows = []
    for src in SOURCES:
        path = os.path.join(args.export, src["file"])
        if not os.path.exists(path):
            conv.unsupported["missing in WoWSims Forever: " + src["file"]] += 1
            continue
        raw = json.load(open(path, encoding="utf-8"))
        talents = None
        if src["talents"] == "build":
            talents = (raw.get("player") or {}).get("talentsString") or raw.get("talentsString")
        elif isinstance(src["talents"], tuple) and src["talents"][0] == "preset":
            talents = preset_talents(args.sims, src["talents"][1], src["talents"][2])
        elif isinstance(src["talents"], tuple) and src["talents"][0] == "defaults":
            talents = defaults_talents(args.sims, src["talents"][1])
        if src.get("rotation"):
            raw = json.load(open(os.path.join(args.export, src["rotation"]), encoding="utf-8"))
        rot = find_rotation(raw)
        if not rot or not rot.get("priorityList"):
            conv.unsupported["no rotation in " + src["file"]] += 1
            continue
        before = sum(conv.unsupported.values())
        items, skipped = conv.rotation(rot)
        casts = sum(1 for i in items if "id" in i)
        cls = src["file"].split("/")[0]
        token = CLASSES[cls]
        entry = {"name": src["name"], "file": "forever/" + re.sub(r"(\.apl|\.build)?\.json$", "", src["file"]),
                 "role": src["role"], "list": items}
        if talents:
            entry["talents"] = tree_points(talents)
        if src.get("style"):
            entry["style"] = src["style"]
        data.setdefault(token, []).append(entry)
        rows.append((entry["file"], casts, skipped, sum(conv.unsupported.values()) - before))

    # 1-20 starters (hand written, same JSON format), first in each class
    for path in sorted(glob.glob(os.path.join(starters, "*.json"))):
        cls = os.path.basename(path)[:-5]
        if cls not in CLASSES:
            continue
        raw = json.load(open(path, encoding="utf-8"))
        items, skipped = conv.rotation(find_rotation(raw))
        token = CLASSES[cls]
        entry = {"name": "Starter (levels 1-19)", "file": "forever/starter/" + cls, "starter": True,
                 "maxLevel": 19, "role": "any", "list": items}
        data.setdefault(token, []).insert(0, entry)
        rows.append((entry["file"], sum(1 for i in items if "id" in i), skipped, 0))

    lines = [
        "-- GENERATED by tools/forever_convert.py. Do not edit by hand; re-run the converter.",
        "-- Source: WoWSims Forever (https://github.com/wowsims/forever, MIT) @ %s (%s)," % (sha, date),
        "-- plus the starter rotations in rotations/forever/starters.",
        "local addonName, ns = ...",
        'if ns.GAME ~= "forever" then',
        "\treturn",
        "end",
        "ns.SimData = ns.SimData or {}",
        "ns.SimData.source = %s" % lua("wowsims/forever@" + sha[:10] + " (" + date + ")"),
        "ns.SimData.specs = {",
    ]
    for token in sorted(data):
        lines.append("\t%s = {" % token)
        lines.append("\t\t[0] = {")
        for rot in data[token]:
            meta = {k: v for k, v in rot.items() if k != "list"}
            head = ", ".join("%s = %s" % (k, lua(meta[k])) for k in sorted(meta))
            lines.append("\t\t\t{ %s, list = {" % head)
            for it in rot["list"]:
                lines.append("\t\t\t\t" + lua(it) + ",")
            lines.append("\t\t\t} },")
        lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    lines.append("ns.SimData.tuning = ns.SimData.tuning or {}")
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    total = sum(len(v) for v in data.values())
    report = ["## WoWSims Forever rotations", "",
              "Source: `wowsims/forever@%s` (%s). %d rotations across %d classes." % (sha[:10], date, total, len(data)),
              "", "| Rotation | Casts | Skipped items |", "| --- | --- | --- |"]
    for rel, casts, skipped, _ in rows:
        report.append("| %s | %d | %d |" % (rel, casts, skipped))
    for title, counter in (("Unsupported (item skipped)", conv.unsupported), ("Approximated", conv.approximated),
                           ("Dropped actions", conv.dropped)):
        report.extend(["", "### " + title, ""])
        report.extend(["- `%s` x%d" % kv for kv in counter.most_common()] or ["None."])
    if args.report:
        open(args.report, "w", encoding="utf-8").write("\n".join(report) + "\n")
    if args.summary:
        json.dump({"rotations": total, "sha": sha, "date": date, "unsupported": sum(conv.unsupported.values()),
                   "approximated": sum(conv.approximated.values()), "dropped": sum(conv.dropped.values())},
                  open(args.summary, "w"))
    print("wrote %s: %d rotations, %d unsupported, %d approximated, %d dropped"
          % (args.out, total, sum(conv.unsupported.values()), sum(conv.approximated.values()), sum(conv.dropped.values())))


if __name__ == "__main__":
    main()
