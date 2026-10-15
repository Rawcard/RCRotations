#!/usr/bin/env python3
"""RCRotations tuning layer: fixes applied on top of WoWSims rotations.

The tuning file (rotations/tuning/mists.json) holds per-spec fixes that the
converter compiles into SimData_Mists.lua. In game they're applied to every
rotation for that spec, bundled or imported, so a fix is written once and
survives every WoWSims update.

File format (JSON). Keys are "*" (every spec), "<class>/<spec>" (every
rotation of a spec) or "<class>/<spec>/<rotation>" (one rotation, by its
WoWSims file name):

    {
      "death_knight/unholy": {
        "require": [ { "spell": 63560, "when": "pet.buff(91342).stacks >= 5",
                       "why": "Dark Transformation needs 5 Shadow Infusion" } ],
        "block":   [ { "spell": 42650, "why": "Army is a pre-pull cooldown" } ],
        "move":    [ { "spell": 49206, "before": 77575 } ],
        "add":     [ { "spell": 47568, "when": "runes.blood == 0 and runes.frost == 0",
                       "before": 85948, "why": "Empower Rune Weapon when out of runes" } ]
      }
    }

- require: the spell is only suggested when "when" is true (added to the
  rotation's own condition).
- block: never suggest the spell for this spec (players can still unblock it
  in game with /rcr unblock, like the built-in never-suggest list).
- move: put the spell right "before" another spell, or "to": "top"/"bottom".
- add: a new line, placed "before" a spell or "at": "top"/"bottom" (default
  bottom), with an optional "when".

Conditions ("when") use a short readable syntax; see CONDITION SYNTAX below
or rotations/tuning/README.md.
"""

import json
import re

# --------------------------------------------------------------------------
# CONDITION SYNTAX
#
#   buff(51124)                 player has the aura (also .up)
#   buff(51124).down            player lacks it
#   buff(51124).remains         seconds left
#   buff(51124).stacks          stack count
#   buff(81229).known           talent/passive known
#   pet.buff(91342).stacks      on the pet;  target.buff(...) on the target
#   debuff(55095)               your dot/debuff on the target (.remains, .stacks)
#   cooldown(49020).ready       off cooldown (also: .remains, .charges)
#   spell(49020).usable         castable right now (also: .known, .cast_time)
#   health.pct  target.health.pct  mana  mana.pct
#   rage energy focus runic_power combo_points chi
#   holy_power shadow_orbs soul_shards demonic_fury burning_embers
#   runes.blood runes.frost runes.unholy runes.death
#   targets  combat_time  time_to_die  execute(20)  moving  gcd.ready
#   stance (0 = none, e.g. no seal)   stance(31801) seal/presence/stance active
#   numbers: 5  2.5s  500ms  35%  ·  true false
#   operators: and or not  == != < <= > >=  + - * /  ( )
# --------------------------------------------------------------------------


class TuningError(Exception):
    pass


TOKEN = re.compile(r"""
    \s*(?:
      (?P<num>\d+(?:\.\d+)?)(?P<unit>ms|s|%)?
    | (?P<op>==|!=|<=|>=|<|>|\+|-|\*|/|\(|\)|\.)
    | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
    )""", re.X)

RESOURCES = {
    "rage": "currentRage", "energy": "currentEnergy", "focus": "currentFocus",
    "runic_power": "currentRunicPower", "combo_points": "currentComboPoints",
    "chi": "monkCurrentChi", "mana": "currentMana",
    "holy_power": "currentGenericResource", "shadow_orbs": "currentGenericResource",
    "soul_shards": "currentGenericResource", "demonic_fury": "currentGenericResource",
    "burning_embers": "currentGenericResource",
    "targets": "numberTargets", "combat_time": "currentTime", "time_to_die": "remainingTime",
}
CMP = {"==": "==", "!=": "~=", "<": "<", "<=": "<=", ">": ">", ">=": ">="}
UNITS = {"player", "target", "pet"}


def tokenize(text):
    pos, out = 0, []
    text = text.strip()
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            raise TuningError("can't read %r at position %d" % (text[pos:pos + 12], pos))
        pos = m.end()
        if m.group("num") is not None:
            n = float(m.group("num"))
            unit = m.group("unit")
            if unit == "ms":
                n /= 1000.0
            elif unit == "%":
                n /= 100.0
            out.append(("num", n))
        elif m.group("op"):
            out.append(("op", m.group("op")))
        else:
            word = m.group("name")
            out.append(("kw" if word in ("and", "or", "not", "true", "false") else "name", word))
    return out


class Parser:
    def __init__(self, text):
        self.text = text
        self.toks = tokenize(text)
        self.i = 0

    def peek(self, kind=None, value=None):
        if self.i >= len(self.toks):
            return None
        t = self.toks[self.i]
        if kind and t[0] != kind:
            return None
        if value is not None and t[1] != value:
            return None
        return t

    def take(self, kind=None, value=None):
        t = self.peek(kind, value)
        if not t:
            got = self.toks[self.i][1] if self.i < len(self.toks) else "end of text"
            raise TuningError("expected %s, got %r in %r" % (value or kind, got, self.text))
        self.i += 1
        return t

    def parse(self):
        node = self.or_()
        if self.i != len(self.toks):
            raise TuningError("unexpected %r in %r" % (self.toks[self.i][1], self.text))
        return node

    def or_(self):
        vals = [self.and_()]
        while self.peek("kw", "or"):
            self.take()
            vals.append(self.and_())
        return vals[0] if len(vals) == 1 else {"k": "or", "v": vals}

    def and_(self):
        vals = [self.not_()]
        while self.peek("kw", "and"):
            self.take()
            vals.append(self.not_())
        return vals[0] if len(vals) == 1 else {"k": "and", "v": vals}

    def not_(self):
        if self.peek("kw", "not"):
            self.take()
            return {"k": "not", "v": [self.not_()]}
        return self.cmp()

    def cmp(self):
        left = self.sum()
        t = self.peek("op")
        if t and t[1] in CMP:
            self.take()
            right = self.sum()
            return {"k": "cmp", "op": CMP[t[1]], "v": [left, right]}
        return left

    def sum(self):
        node = self.term()
        while True:
            t = self.peek("op")
            if t and t[1] in "+-" and len(t[1]) == 1:
                self.take()
                node = {"k": "math", "op": t[1], "v": [node, self.term()]}
            else:
                return node

    def term(self):
        node = self.unary()
        while True:
            t = self.peek("op")
            if t and t[1] in "*/" and len(t[1]) == 1:
                self.take()
                node = {"k": "math", "op": t[1], "v": [node, self.unary()]}
            else:
                return node

    def unary(self):
        if self.peek("op", "-"):
            self.take()
            return {"k": "math", "op": "-", "v": [0, self.unary()]}
        return self.atom()

    def atom(self):
        t = self.peek()
        if not t:
            raise TuningError("condition ends too early: %r" % self.text)
        if t[0] == "num":
            self.take()
            return t[1]
        if t == ("kw", "true") or t == ("kw", "false"):
            self.take()
            return t[1] == "true"
        if t == ("op", "("):
            self.take()
            node = self.or_()
            self.take("op", ")")
            return node
        if t[0] == "name":
            return self.ref()
        raise TuningError("unexpected %r in %r" % (t[1], self.text))

    def arg(self):
        self.take("op", "(")
        n = self.take("num")[1]
        self.take("op", ")")
        return int(n) if n == int(n) else n

    def prop(self):
        if self.peek("op", "."):
            self.take()
            return self.take("name")[1]
        return None

    def ref(self):
        name = self.take("name")[1]
        unit = None
        if name in UNITS and self.peek("op", "."):
            unit = name
            self.take()
            name = self.take("name")[1]
        if name in ("buff", "aura"):
            sid = self.arg()
            prop = self.prop() or "up"
            u = unit or "player"
            kinds = {"up": "auraIsActive", "down": "auraIsInactive", "remains": "auraRemainingTime",
                     "stacks": "auraNumStacks", "known": "auraIsKnown"}
            if prop not in kinds:
                raise TuningError("buff(...).%s isn't a thing; use up, down, remains, stacks or known" % prop)
            return {"k": kinds[prop], "id": sid, "unit": u}
        if name in ("debuff", "dot"):
            sid = self.arg()
            prop = self.prop() or "up"
            u = unit or "target"
            if prop == "stacks":
                return {"k": "auraNumStacks", "id": sid, "unit": u}
            kinds = {"up": "dotIsActive", "remains": "dotRemainingTime"}
            if prop == "down":
                return {"k": "not", "v": [{"k": "dotIsActive", "id": sid, "unit": u}]}
            if prop not in kinds:
                raise TuningError("debuff(...).%s isn't a thing; use up, down, remains or stacks" % prop)
            return {"k": kinds[prop], "id": sid, "unit": u}
        if name in ("cooldown", "spell"):
            sid = self.arg()
            prop = self.prop() or ("ready" if name == "cooldown" else "usable")
            kinds = {"ready": "spellIsReady", "remains": "spellTimeToReady", "charges": "spellNumCharges",
                     "usable": "spellCanCast", "known": "spellIsKnown", "cast_time": "spellCastTime"}
            if prop not in kinds:
                raise TuningError("%s(...).%s isn't a thing; use %s" % (name, prop, ", ".join(sorted(kinds))))
            return {"k": kinds[prop], "id": sid}
        if name == "health":
            prop = self.prop()
            u = unit or "player"
            if prop == "pct":
                return {"k": "currentHealthPercent", "unit": u}
            if prop is None:
                return {"k": "currentHealth", "unit": u}
            raise TuningError("health.%s isn't a thing; use health or health.pct" % prop)
        if name == "mana":
            prop = self.prop()
            if prop == "pct":
                return {"k": "currentManaPercent", "unit": "player"}
            if prop is None:
                return {"k": "currentMana", "unit": "player"}
            raise TuningError("mana.%s isn't a thing; use mana or mana.pct" % prop)
        if name == "runes":
            self.take("op", ".")
            kind = self.take("name")[1]
            if kind not in ("blood", "frost", "unholy", "death"):
                raise TuningError("runes.%s isn't a rune type; use blood, frost, unholy or death" % kind)
            return {"k": "currentRuneCount", "rune": kind}
        if name == "execute":
            pct = self.arg()
            return {"k": "isExecutePhase", "pct": pct / 100.0 if pct > 1 else pct}
        if name == "gcd":
            prop = self.prop() or "ready"
            if prop == "ready":
                return {"k": "gcdIsReady"}
            if prop == "remains":
                return {"k": "gcdTimeToReady"}
            raise TuningError("gcd.%s isn't a thing; use gcd.ready or gcd.remains" % prop)
        if name == "stance":
            if self.peek("op", "("):
                return {"k": "playerStance", "id": self.arg()}
            return {"k": "playerStance"}
        if name == "moving":
            return {"k": "unitIsMoving", "unit": unit or "player"}
        if name in RESOURCES:
            return {"k": RESOURCES[name]}
        raise TuningError("unknown name %r in %r" % (name, self.text))


def parse_condition(text):
    if not isinstance(text, str) or not text.strip():
        raise TuningError("empty condition")
    return Parser(text).parse()


def node_kinds(node, out=None):
    """All value kinds used in a compiled condition (for the sync check)."""
    out = set() if out is None else out
    if isinstance(node, dict):
        if "k" in node:
            out.add(node["k"])
        for v in node.values():
            node_kinds(v, out)
    elif isinstance(node, list):
        for v in node:
            node_kinds(v, out)
    return out


# --------------------------------------------------------------------------
# File loading / compilation
# --------------------------------------------------------------------------
def _spell(entry, where):
    if isinstance(entry, int):
        return entry
    if isinstance(entry, dict) and isinstance(entry.get("spell"), int):
        return entry["spell"]
    raise TuningError("%s: each entry needs a numeric \"spell\" ID" % where)


def compile_tuning(data, specs):
    """data: parsed tuning JSON. specs: {class_dir: (TOKEN, {spec_dir: index})}.

    Returns {target_key: rules} where target_key is "*", "TOKEN:spec" or
    "file:<class>/<spec>/<rotation>", and rules use evaluator nodes.
    """
    out = {}
    for key, rules in data.items():
        if key.startswith("_"):
            continue
        if not isinstance(rules, dict):
            raise TuningError("%s: expected an object" % key)
        if key == "*":
            target = "*"
        else:
            parts = key.split("/")
            if len(parts) not in (2, 3) or parts[0] not in specs or parts[1] not in specs[parts[0]][1]:
                raise TuningError("%s: unknown class/spec (use e.g. death_knight/unholy)" % key)
            token, specmap = specs[parts[0]]
            target = ("%s:%d" % (token, specmap[parts[1]])) if len(parts) == 2 else "file:" + key
        compiled = {}
        for entry in rules.get("block", []) or []:
            compiled.setdefault("block", []).append(_spell(entry, key + " block"))
        for entry in rules.get("require", []) or []:
            sid = _spell(entry, key + " require")
            try:
                cond = parse_condition(entry.get("when"))
            except TuningError as e:
                raise TuningError("%s require %d: %s" % (key, sid, e))
            compiled.setdefault("require", []).append({"id": sid, "c": cond})
        for entry in rules.get("move", []) or []:
            sid = _spell(entry, key + " move")
            move = {"id": sid}
            if "before" in entry:
                move["before"] = int(entry["before"])
            elif entry.get("to") in ("top", "bottom"):
                move["to"] = entry["to"]
            else:
                raise TuningError("%s move %d: needs \"before\": <spell> or \"to\": \"top\"/\"bottom\"" % (key, sid))
            compiled.setdefault("move", []).append(move)
        for entry in rules.get("add", []) or []:
            sid = _spell(entry, key + " add")
            item = {"id": sid}
            if entry.get("when"):
                try:
                    item["c"] = parse_condition(entry["when"])
                except TuningError as e:
                    raise TuningError("%s add %d: %s" % (key, sid, e))
            if "before" in entry:
                item["before"] = int(entry["before"])
            else:
                item["at"] = entry.get("at", "bottom")
                if item["at"] not in ("top", "bottom"):
                    raise TuningError("%s add %d: \"at\" must be top or bottom" % (key, sid))
            compiled.setdefault("add", []).append(item)
        unknown = set(rules) - {"block", "require", "move", "add", "notes", "why"}
        if unknown:
            raise TuningError("%s: unknown rule(s) %s (use block, require, move, add)" % (key, sorted(unknown)))
        if compiled:
            out[target] = compiled
    return out


def load(path, specs):
    with open(path, encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise TuningError("%s isn't valid JSON: %s" % (path, e))
    return compile_tuning(data, specs)
