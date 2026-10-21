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
    588: "Inner Fire", 73413: "Inner Will", 81700: "Archangel", 81661: "Evangelism", 47540: "Penance",
    129250: "Power Word: Solace", 14914: "Holy Fire", 585: "Smite",
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


# ------------------------------------------------------------------ WoW Forever
# WoWSims has no WoW Forever sim. On Forever the addon uses the original Forever
# Rotation lists (Lists.lua). Export them as WoWSims-format rotations so the app
# can show and edit them; saved copies replace the built-in list in game.
FOREVER_ROLE_NAMES = {"damage": "Damage", "tank": "Tank", "heal": "Healer", "range": "Ranged",
                      "melee": "Melee", "caster": "Caster", "cat": "Cat", "bear": "Bear", "hybrid": "Hybrid"}
CLASS_DIR = {v[0]: k for k, v in conv.SPECS.items()}


def _words(key):
    return re.sub(r"(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])", " ", key).replace("ofthe", " of the ")


def _forever_lists(root):
    """Run Data.lua + Lists.lua (as WoW Forever) and return (lists, spell names)."""
    import lupa.luajit21 as lupa_mod  # same runtime family as the game (Lua 5.1)
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    ns = L.eval("{ GAME = 'forever' }")
    run = L.eval("function(src, name, ns) return assert(loadstring(src, name))('RCRotations', ns) end")
    for fn in ("Data.lua", "Lists.lua"):
        run(open(os.path.join(root, fn), encoding="utf-8").read(), fn, ns)
    keys = {}
    for _, cls in ns.Spell.items():
        if lupa_mod.lua_type(cls) != "table":
            continue
        for key, sid in cls.items():
            if isinstance(sid, (int, float)) and sid > 0:
                keys.setdefault(int(sid), set()).add(_words(str(key)))
    names = {}
    for sid, ks in keys.items():
        # one ID under several keys (Mangle Cat / Mangle Bear): keep the shared words
        parts = [k.split() for k in sorted(ks)]
        common = []
        for words in zip(*parts):
            if len(set(words)) != 1:
                break
            common.append(words[0])
        names[sid] = " ".join(common) if len(parts) > 1 and common else sorted(ks)[0]
    return ns, names


def _ids(v):
    """A spell ID, or the IDs in a Lua list, from a list option."""
    if v is None or v is True or v is False:
        return []
    if isinstance(v, (int, float)):
        return [int(v)]
    try:
        return [int(x) for x in v.values() if isinstance(x, (int, float))]
    except AttributeError:
        return []


def _forever_step(step):
    """One Forever Rotation step -> one WoWSims priority-list entry."""
    sid = int(step.id)
    o = step.opt
    get = (lambda k: o[k]) if o is not None else (lambda k: None)
    aura = lambda i, tgt=False: dict({"auraId": {"spellId": i}}, **({"sourceUnit": {"type": "CurrentTarget"}} if tgt else {}))
    cmp = lambda op, lhs, val: {"cmp": {"op": op, "lhs": lhs, "rhs": {"const": {"val": str(val)}}}}
    conds = []
    nb = get("nobuff")
    if nb is True:
        for i in [sid] + _ids(get("anybuff")):
            conds.append({"auraIsInactive": aura(i)})
    elif nb:
        conds += [{"auraIsInactive": aura(i)} for i in _ids(nb)]
    if get("needbuff"):
        conds += [{"auraIsActive": aura(i)} for i in _ids(get("needbuff"))]
    if get("needanybuff"):
        conds.append({"or": {"vals": [{"auraIsActive": aura(i)} for i in _ids(get("needanybuff"))]}})
    nd = get("nodebuff")
    stacks = get("stacks")
    if nd is True and stacks:
        conds.append(cmp("OpLt", {"auraNumStacks": aura(sid, True)}, int(stacks)))
    elif nd is True:
        conds.append({"not": {"val": {"dotIsActive": {"spellId": {"spellId": sid}}}}})
    elif nd:
        conds += [{"auraIsInactive": aura(i, True)} for i in _ids(nd)]
    if get("anydebuff"):
        conds += [{"auraIsInactive": aura(i, True)} for i in _ids(get("anydebuff"))]
    if get("needdebuff"):
        conds += [{"auraIsActive": aura(i, True)} for i in _ids(get("needdebuff"))]
    hp = get("hp")
    if hp:
        unit = {"sourceUnit": {"type": "CurrentTarget"}} if get("unit") == "target" else {}
        conds.append(cmp("OpLe", {"currentHealthPercent": unit}, "%d%%" % int(hp)))
    if get("hpMin"):
        conds.append(cmp("OpGe", {"currentHealthPercent": {}}, "%d%%" % int(get("hpMin"))))
    if get("comboMin"):
        conds.append(cmp("OpGe", {"currentComboPoints": {}}, int(get("comboMin"))))
    if get("enemiesMin"):
        conds.append(cmp("OpGe", {"numberTargets": {}}, int(get("enemiesMin"))))
    action = {"castSpell": {"spellId": {"spellId": sid}}}
    if len(conds) == 1:
        action["condition"] = conds[0]
    elif conds:
        action["condition"] = {"and": {"vals": conds}}
    entry = {"action": action}
    if step.on is False:
        entry["hide"] = True
    return entry


def forever_rotations(root):
    ns, names = _forever_lists(root)
    out = []
    for token, roles in sorted(ns.APLDefaults.items()):
        cls = CLASS_DIR.get(token)
        if not cls:
            continue
        seen = set()
        for role, steps in sorted(roles.items()):
            if id(steps) in seen or role == "hybrid":
                continue
            seen.add(id(steps))
            items = [_forever_step(steps[i]) for i in range(1, len(steps) + 1) if steps[i].id]
            if not items:
                continue
            rname = FOREVER_ROLE_NAMES.get(role, role.title())
            out.append({
                "cls": cls, "spec": "forever", "token": token, "specIndex": 0, "game": "forever",
                "name": "Forever Rotation: " + rname, "file": "forever/%s/%s" % (cls, role),
                "rotation": {"type": "TypeAPL", "prepullActions": [], "priorityList": items},
            })
    return out, names


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

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    forever, forever_names = forever_rotations(root)
    rots += forever

    spells, items = load_names(a.sims)
    for k, v in forever_names.items():
        spells.setdefault(k, v)
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
