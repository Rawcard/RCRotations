#!/usr/bin/env python3
"""Convert WoWSims rotation files (APL JSON) into an RCRotations data file.

Usage:
    python3 tools/wowsims_convert.py --sims PATH_TO_WOWSIMS_MOP_CHECKOUT \
        --out SimData_Mists.lua --report sim-report.md

WoWSims (https://github.com/wowsims/mop) is MIT licensed. Each rotation keeps
its source path, and the generated file records the WoWSims commit it came
from.

What the converter does
- Inlines value variables (variableRef) and action groups (groupReference),
  substituting group variable placeholders, so the in-game evaluator never has
  to resolve names.
- Parses constants: "30s" -> 30, "500ms" -> 0.5, "60%" -> 0.6, "true" -> true.
- Turns every value node into a compact Lua table: {k = "auraIsActive", id = 51271}.
- Value kinds the evaluator does not model (boss timers, trinket proc
  tracking, ...) are replaced by a documented stand-in constant and listed in
  the report as "approximated".
- Actions the evaluator can't recommend (item swaps, prepull, moves, ...) are
  dropped and listed in the report.

The set of value kinds implemented in-game lives in Sim.lua. tools/test_sim.py
checks that this file's SUPPORTED set and Sim.lua's handlers agree.
"""

import argparse
import os.path as _osp
import sys as _sys
_sys.path.insert(0, _osp.dirname(_osp.abspath(__file__)))  # for tools/tuning.py

import datetime
import glob
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

# --------------------------------------------------------------------------
# Class / spec layout. Spec index = GetSpecialization() order in MoP.
# --------------------------------------------------------------------------
SPECS = {
    "death_knight": ("DEATHKNIGHT", {"blood": 1, "frost": 2, "unholy": 3}),
    "druid": ("DRUID", {"balance": 1, "feral": 2, "guardian": 3, "restoration": 4}),
    "hunter": ("HUNTER", {"beast_mastery": 1, "marksmanship": 2, "survival": 3}),
    "mage": ("MAGE", {"arcane": 1, "fire": 2, "frost": 3}),
    "monk": ("MONK", {"brewmaster": 1, "mistweaver": 2, "windwalker": 3}),
    "paladin": ("PALADIN", {"holy": 1, "protection": 2, "retribution": 3}),
    "priest": ("PRIEST", {"discipline": 1, "holy": 2, "shadow": 3}),
    "rogue": ("ROGUE", {"assassination": 1, "combat": 2, "subtlety": 3}),
    "shaman": ("SHAMAN", {"elemental": 1, "enhancement": 2, "restoration": 3}),
    "warlock": ("WARLOCK", {"affliction": 1, "demonology": 2, "destruction": 3}),
    "warrior": ("WARRIOR", {"arms": 1, "fury": 2, "protection": 3}),
}

# Value kinds evaluated live by Sim.lua (keep in sync; tools/test_sim.py checks).
SUPPORTED = {
    "and", "or", "not", "cmp", "math", "max", "min",
    "currentTime", "currentTimePercent", "remainingTime", "remainingTimePercent",
    "isExecutePhase", "numberTargets", "bossCurrentTarget",
    "currentHealth", "currentHealthPercent", "maxHealth",
    "currentMana", "currentManaPercent",
    "currentRage", "maxRage", "currentEnergy", "maxEnergy", "energyRegenPerSecond", "energyTimeToTarget",
    "currentFocus", "maxFocus", "focusRegenPerSecond", "focusTimeToTarget",
    "currentComboPoints", "maxComboPoints", "currentRunicPower", "maxRunicPower",
    "currentSolarEnergy", "currentLunarEnergy", "druidCurrentEclipsePhase",
    "currentGenericResource", "monkCurrentChi", "monkMaxChi", "brewmasterMonkCurrentStaggerPercent",
    "currentRuneCount", "currentNonDeathRuneCount", "currentRuneDeath", "currentRuneActive",
    "runeCooldown", "nextRuneCooldown", "runeSlotCooldown", "fullRuneCooldown",
    "gcdIsReady", "gcdTimeToReady", "remainingCastTime", "unitIsMoving",
    "spellIsKnown", "spellCanCast", "spellIsReady", "spellTimeToReady", "spellCastTime",
    "spellIsChanneling", "spellCurrentCost", "spellNumCharges", "spellTimeToCharge",
    "spellGcdHastedDuration", "spellFullCooldown", "spellIsCasting",
    "auraIsKnown", "auraIsActive", "auraIsInactive", "auraRemainingTime", "auraNumStacks",
    "auraShouldRefresh",
    "dotIsActive", "dotIsActiveOnAllTargets", "dotRemainingTime", "dotLowestRemainingTime",
    "dotTickFrequency", "totemRemainingTime",
}

# Kinds with no live equivalent: replaced by a constant, reported as approximated.
STAND_IN = {
    "bossSpellTimeToReady": 999,
    "bossSpellIsCasting": False,
    "bossSpellIsKnown": False,
    "bossSpellCastTimeRemaining": 0,
    "unitDistance": 5,
    "autoTimeToNext": 1,
    "spellTravelTime": 0.5,
    "spellCpm": 0,
    "spellChanneledTicks": 0,
    "spellInFlight": False,
    "auraInternalCooldown": 0,
    "auraIcdIsReady": True,
    "allTrinketStatProcsActive": False,
    "anyTrinketStatProcsActive": False,
    "anyTrinketStatProcsAvailable": False,
    "trinketProcsMinRemainingTime": 0,
    "trinketProcsMaxRemainingIcd": 0,
    "numEquippedStatProcTrinkets": 0,
    "numStatBuffCooldowns": 0,
    "anyStatBuffCooldownsActive": False,
    "anyStatBuffCooldownsMinDuration": 0,
    "dotTimeToNextTick": 1,
    "dotBaseDuration": 0,
    "dotPercentIncrease": 0,
    "dotCritPercentIncrease": 0,
    "dotTickRatePercentIncrease": 0,
    "sequenceIsComplete": False,
    "sequenceIsReady": True,
    "sequenceTimeToReady": 0,
    "channelClipDelay": 0,
    "inputDelay": 0.1,
    "frontOfTarget": False,
    "catExcessEnergy": 0,
    "catNewSavageRoarDuration": 0,
    "warlockHandOfGuldanInFlight": False,
    "warlockHauntInFlight": False,
    "mageCurrentCombustionDotEstimate": 0,
    "shamanFireElementalDuration": 60,
    "protectionPaladinDamageTakenLastGlobal": 0,
    "afflictionCurrentSnapshot": 0,
    "afflictionExhaleWindow": False,
    "actionGroupUsed": False,
    "activeItemSwapSet": False,
    "auraIsActiveWithReactionTime": None,  # handled as auraIsActive
    "auraIsInactiveWithReactionTime": None,
    "auraIcdIsReadyWithReactionTime": True,
}
ALIASES = {
    "auraIsActiveWithReactionTime": "auraIsActive",
    "auraIsInactiveWithReactionTime": "auraIsInactive",
}

CAST_ACTIONS = ("castSpell", "castFriendlySpell", "channelSpell", "multidot", "strictMultidot", "multishield")
DROPPED_ACTIONS = {
    "autocastOtherCooldowns", "castAllStatBuffCooldowns", "cancelSpellCast", "changeTarget",
    "activateAura", "activateAuraWithStacks", "activateAllStatBuffProcAuras", "cancelAura",
    "triggerIcd", "itemSwap", "move", "moveDuration", "damageAmplifier", "resetSequence",
    "customRotation", "warlockNextExhaleTarget", "catOptimalRotationAction", "guardianHotwDpsRotation",
}

OPS = {"OpEq": "==", "OpNe": "~=", "OpLt": "<", "OpLe": "<=", "OpGt": ">", "OpGe": ">="}
MATH = {"OpAdd": "+", "OpSub": "-", "OpMul": "*", "OpDiv": "/"}
EXECUTE = {"E20": 0.20, "E25": 0.25, "E35": 0.35, "E45": 0.45, "E90": 0.90}
RUNE_TYPE = {"RuneBlood": "blood", "RuneFrost": "frost", "RuneUnholy": "unholy", "RuneDeath": "death"}
# WoW rune slots: 1-2 Blood, 3-4 Unholy, 5-6 Frost.
RUNE_SLOT = {"SlotLeftBlood": 1, "SlotRightBlood": 2, "SlotLeftUnholy": 3, "SlotRightUnholy": 4,
             "SlotLeftFrost": 5, "SlotRightFrost": 6}
UNIT = {"Self": "player", "Player": "player", "Target": "target", "CurrentTarget": "target",
        "Pet": "pet", "PreviousTarget": "target", "NextTarget": "target"}
ECLIPSE = {"NeutralPhase": "neutral", "SolarPhase": "solar", "LunarPhase": "lunar"}
TOTEM = {"Earth": 2, "Air": 4, "Fire": 1, "Water": 3}  # GetTotemInfo slots


class Unsupported(Exception):
    pass


def parse_const(val):
    v = str(val).strip()
    if v in ("true", "false"):
        return v == "true"
    m = re.fullmatch(r"(-?[0-9.]+)\s*(ms|s|%)?", v)
    if not m:
        raise Unsupported("const:" + v)
    n = float(m.group(1))
    unit = m.group(2)
    if unit == "ms":
        n = n / 1000.0
    elif unit == "%":
        n = n / 100.0
    return int(n) if n == int(n) and unit != "%" and unit != "ms" else n


def action_id(aid):
    """Return a spell id, or None for items/other actions (potions etc.)."""
    if not isinstance(aid, dict):
        return None
    sid = aid.get("spellId")
    return int(sid) if sid else None


def unit_of(ref, default):
    if not isinstance(ref, dict) or not ref.get("type"):
        return default
    return UNIT.get(ref["type"], default)


class Converter:
    def __init__(self):
        self.approximated = Counter()
        self.dropped = Counter()
        self.unsupported = Counter()

    # ---------------------------------------------------------------- values
    def value(self, node, ctx):
        if not isinstance(node, dict) or not node:
            raise Unsupported("empty-value")
        kinds = [k for k in node.keys() if k != "uuid"]
        if not kinds:
            raise Unsupported("empty-value")
        kind = kinds[0]
        body = node[kind] if isinstance(node[kind], dict) else {}
        kind = ALIASES.get(kind, kind)

        if kind == "const":
            return parse_const(body.get("val", "0"))
        if kind == "variableRef":
            name = body.get("name")
            if name in ctx["placeholders"]:
                return ctx["placeholders"][name]
            if name in ctx["variables"]:
                return self.value(ctx["variables"][name], ctx)
            raise Unsupported("variableRef:" + str(name))
        if kind == "variablePlaceholder":
            name = body.get("name")
            if name in ctx["placeholders"]:
                return ctx["placeholders"][name]
            raise Unsupported("variablePlaceholder:" + str(name))
        if kind in ("and", "or"):
            # The WoWSims editor can leave blank {} slots in a list; the sim ignores them.
            vals = [self.value(v, ctx) for v in body.get("vals", [])
                    if isinstance(v, dict) and [x for x in v if x != "uuid"]]
            return {"k": kind, "v": vals}
        if kind == "not":
            return {"k": "not", "v": [self.value(body.get("val"), ctx)]}
        if kind in ("max", "min"):
            return {"k": kind, "v": [self.value(v, ctx) for v in body.get("vals", [])]}
        if kind == "cmp":
            op = OPS.get(body.get("op"))
            if not op:
                raise Unsupported("cmp-op")
            return {"k": "cmp", "op": op, "v": [self.value(body.get("lhs"), ctx), self.value(body.get("rhs"), ctx)]}
        if kind == "math":
            op = MATH.get(body.get("op"))
            if not op:
                raise Unsupported("math-op")
            return {"k": "math", "op": op, "v": [self.value(body.get("lhs"), ctx), self.value(body.get("rhs"), ctx)]}

        if kind in STAND_IN and kind not in SUPPORTED:
            self.approximated[kind] += 1
            return STAND_IN[kind]
        if kind not in SUPPORTED:
            raise Unsupported(kind)

        out = {"k": kind}
        if "spellId" in body:
            sid = action_id(body["spellId"])
            if sid is None:
                # item / potion based checks: no live equivalent
                self.approximated[kind + "(item)"] += 1
                return False if kind.startswith(("spellIs", "spellCan", "aura", "dot")) else 0
            out["id"] = sid
        if "auraId" in body:
            aid = action_id(body["auraId"])
            if aid is None:
                self.approximated[kind + "(item)"] += 1
                return False if kind in ("auraIsActive", "auraIsKnown") else (True if kind == "auraIsInactive" else 0)
            out["id"] = aid
        if kind.startswith("aura"):
            out["unit"] = unit_of(body.get("sourceUnit"), "player")
        if kind.startswith("dot"):
            out["unit"] = unit_of(body.get("targetUnit"), "target")
        if kind in ("currentHealth", "currentHealthPercent", "currentMana", "currentManaPercent", "unitIsMoving"):
            out["unit"] = unit_of(body.get("sourceUnit"), "player")
        if kind == "isExecutePhase":
            out["pct"] = EXECUTE.get(body.get("threshold"), 0.2)
        if "runeType" in body:
            out["rune"] = RUNE_TYPE.get(body["runeType"], "blood")
        if "runeSlot" in body:
            out["slot"] = RUNE_SLOT.get(body["runeSlot"], 1)
        if kind == "auraShouldRefresh":
            mo = body.get("maxOverlap")
            out["overlap"] = self.value(mo, ctx) if mo else 0
        if kind in ("energyTimeToTarget", "focusTimeToTarget"):
            tgt = body.get("targetEnergy") or body.get("targetFocus")
            out["target"] = self.value(tgt, ctx) if tgt else 0
        if kind == "druidCurrentEclipsePhase":
            out["phase"] = ECLIPSE.get(body.get("eclipsePhase"), "neutral")
        if kind == "totemRemainingTime":
            out["slot"] = TOTEM.get(str(body.get("totemType", "")).replace("TotemType", ""), 1)
        return out

    # --------------------------------------------------------------- actions
    def action(self, act, ctx, out, source_note):
        if not isinstance(act, dict):
            return
        cond = None
        if act.get("condition"):
            cond = self.value(act["condition"], ctx)
        keys = [k for k in act.keys() if k not in ("condition", "uuid")]
        if not keys:
            return
        kind = keys[0]
        body = act[kind] if isinstance(act[kind], dict) else {}

        def with_cond(extra):
            if cond is None:
                return extra
            if extra is None:
                return cond
            return {"k": "and", "v": [cond, extra]}

        if kind in CAST_ACTIONS:
            sid = action_id(body.get("spellId"))
            if sid is None:
                self.dropped["item/potion cast"] += 1
                return
            item = {"id": sid}
            c = cond
            if kind in ("multidot", "strictMultidot"):
                # Recommend refreshing the dot on the current target.
                mo = body.get("maxOverlap")
                overlap = self.value(mo, ctx) if mo else 0
                need = {"k": "auraShouldRefresh", "id": sid, "unit": "target", "overlap": overlap}
                c = with_cond(need)
            if kind == "channelSpell":
                item["ch"] = True
            if c is not None:
                item["c"] = c
            out.append(item)
            return
        if kind == "groupReference":
            name = body.get("groupName")
            group = ctx["groups"].get(name)
            if not group:
                self.unsupported["groupReference:" + str(name)] += 1
                return
            placeholders = dict(ctx["placeholders"])
            for var in group.get("variables", []) or []:
                placeholders[var["name"]] = self.value(var.get("value"), ctx)
            for var in body.get("variables", []) or []:
                placeholders[var["name"]] = self.value(var.get("value"), ctx)
            sub = dict(ctx, placeholders=placeholders)
            inner = []
            for li in group.get("actions", []):
                if li.get("hide"):
                    continue
                try:
                    self.action(li.get("action"), sub, inner, source_note)
                except Unsupported as e:
                    self.unsupported[str(e)] += 1
            for it in inner:
                if cond is not None:
                    it["c"] = with_cond(it.get("c")) if it.get("c") is not None else cond
                out.append(it)
            return
        if kind == "schedule":
            # Scheduled cooldowns: recommend the inner action whenever its own
            # condition allows (the sim's fixed timestamps don't exist in game).
            self.approximated["schedule"] += 1
            inner = []
            self.action(body.get("innerAction"), ctx, inner, source_note)
            for it in inner:
                if cond is not None:
                    it["c"] = with_cond(it.get("c")) if it.get("c") is not None else cond
                out.append(it)
            return
        if kind in ("sequence", "strictSequence"):
            # Sequences need sim state. Recommend the first castable step.
            self.approximated[kind] += 1
            for sub in body.get("actions", []):
                inner = []
                self.action(sub, ctx, inner, source_note)
                if inner:
                    it = inner[0]
                    if cond is not None:
                        it["c"] = with_cond(it.get("c")) if it.get("c") is not None else cond
                    out.append(it)
                    break
            return
        if kind in ("wait", "waitUntil"):
            # "Wait while X" (e.g. while channeling): stop suggesting new casts.
            hold = cond
            if kind == "waitUntil" and body.get("condition"):
                until = self.value(body["condition"], ctx)
                hold = with_cond({"k": "not", "v": [until]})
            if hold is not None:
                out.append({"hold": True, "c": hold})
            return
        if kind in DROPPED_ACTIONS:
            self.dropped[kind] += 1
            return
        self.unsupported["action:" + kind] += 1

    def rotation(self, data):
        variables = {v["name"]: v.get("value") for v in data.get("valueVariables", []) or []}
        groups = {g["name"]: g for g in data.get("groups", []) or []}
        ctx = {"variables": variables, "groups": groups, "placeholders": {}}
        out = []
        skipped = 0
        for li in data.get("priorityList", []) or []:
            if li.get("hide"):
                continue
            try:
                self.action(li.get("action"), ctx, out, li.get("notes"))
            except Unsupported as e:
                self.unsupported[str(e)] += 1
                skipped += 1
        return out, skipped


# ------------------------------------------------------------------ Lua out
def lua(v, indent=0):
    if v is True:
        return "true"
    if v is False:
        return "false"
    if v is None:
        return "nil"
    if isinstance(v, (int, float)):
        if isinstance(v, float):
            s = repr(round(v, 6))
            return s
        return str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "{" + ", ".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        parts = []
        for k in sorted(v.keys(), key=lambda k: (k != "k", k)):
            key = k if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) else "[" + lua(k) + "]"
            parts.append("%s = %s" % (key, lua(v[k])))
        return "{ " + ", ".join(parts) + " }"
    raise TypeError(type(v))


def find_rotation(raw):
    """Accept a bare rotation export or a full WoWSims settings export."""
    if not isinstance(raw, dict):
        return None
    if "priorityList" in raw:
        return raw
    for path in (("rotation",), ("player", "rotation"), ("settings", "player", "rotation")):
        node = raw
        for key in path:
            node = node.get(key) if isinstance(node, dict) else None
        if isinstance(node, dict) and "priorityList" in node:
            return node
    return None


def pretty_name(stem):
    return stem.replace("_", " ").replace("-", " ").title()


def git_head(path):
    try:
        sha = subprocess.check_output(["git", "-C", path, "rev-parse", "HEAD"], text=True).strip()
        date = subprocess.check_output(["git", "-C", path, "log", "-1", "--format=%cs"], text=True).strip()
        return sha, date
    except Exception:
        return "unknown", datetime.date.today().isoformat()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sims", required=True, help="path to a wowsims/mop checkout")
    ap.add_argument("--out", default="SimData_Mists.lua")
    ap.add_argument("--report", default=None)
    ap.add_argument("--game", default="mists")
    ap.add_argument("--tuning", default=None,
                    help="tuning file of per-spec fixes (rotations/tuning/mists.json)")
    ap.add_argument("--summary", default=None, help="write counts as JSON (used by the sync job)")
    ap.add_argument("--custom", default=None,
                    help="folder of your own rotations: <class>/<spec>/<name>.json (exported from WoWSims)")
    args = ap.parse_args()

    conv = Converter()
    tuning = {}
    if args.tuning and os.path.exists(args.tuning):
        import tuning as tuning_mod
        try:
            tuning = tuning_mod.load(args.tuning, SPECS)
        except tuning_mod.TuningError as e:
            sys.exit("tuning error: %s" % e)
    sha, date = git_head(args.sims)
    data = defaultdict(lambda: defaultdict(list))
    rows = []
    sources = []
    for path in sorted(glob.glob(os.path.join(args.sims, "ui", "specs", "*", "*", "apls", "*.apl.json"))):
        parts = path.split(os.sep)
        sources.append((path, parts[-4], parts[-3], os.path.basename(path)[: -len(".apl.json")], ""))
    if args.custom and os.path.isdir(args.custom):
        # Your own rotations: <custom>/<class>/<spec>/<name>.json, e.g.
        # rotations/mists/death_knight/frost/my_obliterate.json
        for path in sorted(glob.glob(os.path.join(args.custom, "*", "*", "*.json"))):
            parts = path.split(os.sep)
            stem = re.sub(r"(\.apl)?\.json$", "", os.path.basename(path))
            sources.append((path, parts[-3], parts[-2], stem, "custom/"))
    for path, cls_dir, spec_dir, stem, prefix in sources:
        if cls_dir not in SPECS or spec_dir not in SPECS[cls_dir][1]:
            if prefix:
                conv.unsupported["custom file in unknown class/spec folder: " + path] += 1
            continue
        token, specmap = SPECS[cls_dir]
        with open(path, encoding="utf-8") as f:
            raw = json.load(f)
        raw = find_rotation(raw)
        if not raw or raw.get("type", "TypeAPL") != "TypeAPL" or not raw.get("priorityList"):
            if prefix:
                conv.unsupported["custom file has no APL rotation: " + path] += 1
            continue
        before = sum(conv.unsupported.values())
        items, skipped = conv.rotation(raw)
        casts = sum(1 for i in items if "id" in i)
        rel = "%s%s/%s/%s" % (prefix, cls_dir, spec_dir, stem)
        data[token][specmap[spec_dir]].append({
            "name": pretty_name(stem) + (" (custom)" if prefix else ""), "file": rel, "list": items,
        })
        rows.append((rel, casts, skipped, sum(conv.unsupported.values()) - before))

    # default rotation first within each spec
    for token in data:
        for spec in data[token]:
            data[token][spec].sort(key=lambda r: (not r["file"].endswith("/default"), r["file"]))

    lines = [
        "-- GENERATED by tools/wowsims_convert.py. Do not edit by hand; re-run the converter.",
        "-- Source: WoWSims MoP (https://github.com/wowsims/mop, MIT) @ %s (%s)" % (sha, date),
        "local addonName, ns = ...",
        "if ns.GAME ~= %s then" % lua(args.game),
        "\treturn",
        "end",
        "ns.SimData = ns.SimData or {}",
        "ns.SimData.source = %s" % lua("wowsims/mop@" + sha[:10] + " (" + date + ")"),
        "ns.SimData.specs = {",
    ]
    for token in sorted(data):
        lines.append("\t%s = {" % token)
        for spec in sorted(data[token]):
            lines.append("\t\t[%d] = {" % spec)
            for rot in data[token][spec]:
                lines.append("\t\t\t{ name = %s, file = %s, list = {" % (lua(rot["name"]), lua(rot["file"])))
                for it in rot["list"]:
                    lines.append("\t\t\t\t" + lua(it) + ",")
                lines.append("\t\t\t} },")
            lines.append("\t\t},")
        lines.append("\t},")
    lines.append("}")
    # Per-spec fixes from the tuning file, applied in game on top of every
    # rotation for the spec (bundled or imported). See tools/tuning.py.
    lines.append("ns.SimData.tuning = {")
    for target in sorted(tuning):
        lines.append("\t[%s] = %s," % (lua(target), lua(tuning[target])))
    lines.append("}")
    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")

    total_rot = sum(len(v) for t in data.values() for v in t.values())
    report = ["## WoWSims rotation import",
              "",
              "Source: `wowsims/mop@%s` (%s). %d rotations across %d classes."
              % (sha[:10], date, total_rot, len(data)),
              "",
              "| Rotation | Casts | Skipped items |",
              "| --- | --- | --- |"]
    for rel, casts, skipped, _ in rows:
        report.append("| %s | %d | %d |" % (rel, casts, skipped))
    def block(title, counter, hint):
        report.extend(["", "### " + title, "", hint, ""])
        if not counter:
            report.append("None.")
        for k, n in counter.most_common():
            report.append("- `%s` x%d" % (k, n))
    block("Unsupported (item skipped)", conv.unsupported,
          "These conditions/actions have no evaluator yet, so the rotation line using them was left out. Adding them to Sim.lua and SUPPORTED brings the line back.")
    block("Approximated", conv.approximated,
          "Simulator-only values replaced with a fixed stand-in (see STAND_IN in the converter).")
    if tuning:
        report.extend(["", "### Tuning applied", ""])
        for target in sorted(tuning):
            rules = tuning[target]
            parts = ["%s %d" % (k, len(v)) for k, v in sorted(rules.items())]
            ids_in = set()
            for token in data:
                for spec in data[token]:
                    for rot in data[token][spec]:
                        key = "%s:%d" % (token, spec)
                        if target in ("*", key, "file:" + rot["file"]):
                            ids_in.update(i["id"] for i in rot["list"] if "id" in i)
            missing = sorted({r["id"] if isinstance(r, dict) else r for k in ("require", "move")
                              for r in rules.get(k, [])} - ids_in)
            note = (" (not in these rotations: %s)" % ", ".join(map(str, missing))) if missing and target != "*" else ""
            report.append("- `%s`: %s%s" % (target, ", ".join(parts), note))
    block("Dropped actions", conv.dropped,
          "Actions a rotation helper can't recommend (item swaps, prepull, moves, potions).")
    text = "\n".join(report) + "\n"
    if args.summary:
        with open(args.summary, "w", encoding="utf-8") as f:
            json.dump({"rotations": total_rot, "sha": sha, "date": date,
                       "unsupported": sum(conv.unsupported.values()),
                       "approximated": sum(conv.approximated.values()),
                       "dropped": sum(conv.dropped.values())}, f)
    if args.report:
        with open(args.report, "w", encoding="utf-8") as f:
            f.write(text)
    print("wrote %s: %d rotations, %d unsupported, %d approximated, %d dropped"
          % (args.out, total_rot, sum(conv.unsupported.values()), sum(conv.approximated.values()), sum(conv.dropped.values())))


if __name__ == "__main__":
    main()
