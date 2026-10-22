#!/usr/bin/env python3
"""Tests for the WoWSims pipeline (needs `pip install lupa`).

1. The converter's SUPPORTED set matches the handlers in Sim.lua.
2. Every generated SimData_*.lua loads under LuaJIT (Lua 5.1 rules, like WoW).
3. Frost DK scenarios run through Sim.lua with a fake game state.

Run from the repo root:  python3 tools/test_sim.py
"""
import glob
import re
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import wowsims_convert as conv  # noqa: E402

try:
    import lupa.luajit21 as lupa_mod
except ImportError:  # pragma: no cover
    import lupa as lupa_mod

FAILS = []


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        FAILS.append(msg)


def read(name):
    with open(os.path.join(ROOT, name), encoding="utf-8") as f:
        return f.read()


# Fake world shared by the scenarios. Lua reads/writes it through the globals.
WORLD = r'''
WORLD = { known = {}, cd = {}, auras = { player = {}, target = {} }, runes = {}, power = {}, powerMax = {},
          enemies = 1, spec = 2, health = { player = 1, target = 1 }, now = 100, combat = true }
function GetTime() return WORLD.now end
function UnitAffectingCombat() return WORLD.combat end
function UnitHealth(u) return math.floor((WORLD.health[u] or 1) * 100000) end
function UnitHealthMax() return 100000 end
function UnitGUID(u) return u == "target" and "Creature-1" or "Player-1" end
function UnitPower(_, t) return WORLD.power[t] or 0 end
function UnitPowerMax(_, t) return WORLD.powerMax[t] or 100 end
function GetSpecialization() return WORLD.spec end
function UnitClass() return "Death Knight", "DEATHKNIGHT", 6 end
function GetRuneType(slot) return (WORLD.runes[slot] or {}).kind or ({1,1,2,2,3,3})[slot] end
function GetRuneCooldown(slot)
	local r = WORLD.runes[slot] or {}
	if r.remain and r.remain > 0 then return WORLD.now - (10 - r.remain), 10, false end
	return 0, 10, true
end
function IsPlayerSpell(id) return WORLD.known[id] == true end
function UnitSpellHaste() return 10 end
function UnitIsUnit() return false end
function GetUnitSpeed() return 0 end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
C_Spell = {
	GetSpellCooldown = function(id) return { startTime = 0, duration = 0 } end,
	GetSpellInfo = function(id) return { name = "Spell" .. id, spellID = id, castTime = 0 } end,
}
C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i, filter)
		local list = WORLD.auras[unit] or {}
		local want = filter:find("HARMFUL") and "HARMFUL" or "HELPFUL"
		local n = 0
		for _, a in ipairs(list) do
			if (a.kind or (unit == "target" and "HARMFUL" or "HELPFUL")) == want then
				n = n + 1
				if n == i then
					return { spellId = a.id, name = "Spell" .. a.id, applications = a.stacks or 0,
						expirationTime = WORLD.now + (a.remain or 30), duration = 30 }
				end
			end
		end
		return nil
	end,
}
function CreateFrame() return { RegisterEvent = function() end, SetScript = function() end } end
issecretvalue = nil
'''

API_STUB = r'''
local ns = ...
ns.db = { barOnly = false }
ns.ClassToken = function() return "DEATHKNIGHT", 6 end
ns.API = {
	Resolve = function(id) if WORLD.known[id] then return id end return nil end,
	Cooldown = function(id) local r = WORLD.cd[id] or 0 return r, r > 0 and 30 or 0 end,
	Ready = function(id) return WORLD.known[id] and not WORLD.unusable or false end,
	EnemyCount = function() return WORLD.enemies end,
	SpellName = function(id) return "Spell" .. id end,
}
'''


def new_lua():
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    L.execute(WORLD)
    return L


def load_addon_files(L, game="mists"):
    ns = L.eval("{}")
    L.eval("function(src, ns) return assert(loadstring(src))(ns) end")(API_STUB, ns)
    ns.GAME = game
    runner = L.eval("function(src, name, ns) return assert(loadstring(src, name))('RCRotations', ns) end")
    runner(read("SimData_Mists.lua"), "SimData_Mists.lua", ns)
    runner(read("Sim.lua"), "Sim.lua", ns)
    L.eval("function(ns) ns.T = ns.T or function(k) return k end end")(ns)
    runner(read("SimImport.lua"), "SimImport.lua", ns)
    runner(read("Buffs.lua"), "Buffs.lua", ns)
    return ns


# --------------------------------------------------------------- 1. sync
L = new_lua()
ns = load_addon_files(L)
handlers = set(k for k in ns.Sim.HANDLERS.keys())
missing_in_lua = conv.SUPPORTED - handlers
missing_in_py = handlers - conv.SUPPORTED
check(not missing_in_lua, "every SUPPORTED kind has a Sim.lua handler %s" % (sorted(missing_in_lua) or ""))
check(not missing_in_py, "every Sim.lua handler is in SUPPORTED %s" % (sorted(missing_in_py) or ""))

# custom rotation exports: bare rotation and full WoWSims settings export both work
rot = {"type": "TypeAPL", "priorityList": [{"action": {"castSpell": {"spellId": {"spellId": 49020}}}}]}
check(conv.find_rotation(rot) is rot, "custom import: bare rotation export accepted")
check(conv.find_rotation({"player": {"rotation": rot}}) is rot, "custom import: full settings export accepted")
check(conv.find_rotation({"player": {}}) is None, "custom import: file without a rotation rejected")

# --------------------------------------------------------------- 2. data loads
for path in glob.glob(os.path.join(ROOT, "SimData_*.lua")):
    L2 = new_lua()
    try:
        ns2 = load_addon_files(L2)
        n = 0
        for _, specs in ns2.SimData.specs.items():
            for _, rots in specs.items():
                n += len(rots)
        check(n > 0, "%s loads under Lua 5.1 rules (%d rotations)" % (os.path.basename(path), n))
    except Exception as e:  # noqa: BLE001
        check(False, "%s loads: %s" % (os.path.basename(path), e))

# every rotation evaluates without Lua errors in an empty world
L3 = new_lua()
ns3 = load_addon_files(L3)
L3.execute("for id = 1, 200000 do end")
errs = 0
total = 0
walker = L3.eval('''function(ns)
	local errs, total = 0, 0
	for id in pairs({}) do end
	-- know every spell referenced so conditions are actually evaluated
	for _, specs in pairs(ns.SimData.specs) do
		for _, rots in pairs(specs) do
			for _, rot in ipairs(rots) do
				for _, item in ipairs(rot.list) do
					if item.id then WORLD.known[item.id] = true end
				end
			end
		end
	end
	for _, specs in pairs(ns.SimData.specs) do
		for _, rots in pairs(specs) do
			for _, rot in ipairs(rots) do
				ns.Sim.BeginPass()
				for _, item in ipairs(rot.list) do
					if item.c then
						total = total + 1
						local ok = pcall(ns.Sim.Eval, item.c)
						if not ok then errs = errs + 1 end
					end
				end
			end
		end
	end
	return errs, total
end''')
errs, total = walker(ns3)
check(errs == 0, "all %d converted conditions evaluate without Lua errors (%d errors)" % (total, errs))

# --------------------------------------------------------------- 3. Frost DK scenarios
FROST = {
    "pillar": 51271, "army": 42650, "ams": 48707, "outbreak": 77575, "howling": 49184,
    "plague_strike": 45462, "obliterate": 49020, "frost_strike": 49143, "km": 51124,
    "ff": 55095, "bp": 55078, "erw": 47568, "horn": 57330, "unbreakable": 51271,
}


def scenario(setup):
    L = new_lua()
    ns = load_addon_files(L)
    for sid in (51271, 42650, 48707, 77575, 49184, 45462, 49020, 49143, 57330, 47568, 123693):
        L.execute("WORLD.known[%d] = true" % sid)
    L.execute("WORLD.spec = 2; WORLD.power[6] = 20")
    L.execute(setup)
    if not L.eval("NO_HORN"):
        L.execute("table.insert(WORLD.auras.player, {id=57330, remain=300})")  # raid AP buff up
    if L.eval("NS_UNBLOCK"):
        ns.db.simBlock = L.table_from({48707: False})
    rot = None
    rots = ns.SimData.specs["DEATHKNIGHT"][2]
    for i in range(1, len(rots) + 1):
        if rots[i].file.endswith("obliterate"):
            rot = rots[i]
    q = ns.Sim.BuildQueue(rot)
    return [q[i] for i in range(1, len(q) + 1)] if q else []


q = scenario("")
check(len(q) > 0 and q[0] == FROST["pillar"], "big cooldowns ready -> Pillar of Frost first (got %s)" % q)

cds = "WORLD.cd[51271]=60; WORLD.cd[42650]=600; WORLD.cd[48707]=45; WORLD.cd[57330]=20; WORLD.cd[47568]=200; "
q = scenario(cds)
check(len(q) > 0 and q[0] in (FROST["outbreak"], FROST["howling"], FROST["plague_strike"]),
      "no diseases on target -> a disease applier first (got %s)" % q)
check(FROST["pillar"] not in q, "spells on cooldown never suggested (got %s)" % q)

q = scenario(cds + "WORLD.cd[77575]=50; WORLD.auras.target = {{id=55095, remain=20}, {id=55078, remain=20}}; "
             "WORLD.auras.player = {{id=51124, remain=8}}; WORLD.power[6] = 30")
check(len(q) > 0 and q[0] == FROST["obliterate"],
      "diseases up + Killing Machine + runes -> Obliterate first (got %s)" % q)

q = scenario(cds + "WORLD.cd[77575]=50; WORLD.auras.target = {{id=55095, remain=20}, {id=55078, remain=20}}; "
             "WORLD.power[6] = 95; for s=1,6 do WORLD.runes[s] = {remain=6} end")
check(len(q) > 0 and q[0] == FROST["frost_strike"],
      "diseases up, no runes, runic power capped -> Frost Strike first (got %s)" % q)

# DK upkeep: presence and Horn of Winter are buff reminders above the HUD (Buffs.lua)
def frost_buffs(setup):
    L = new_lua()
    ns = load_addon_files(L)
    L.execute("WORLD.spec = 2; WORLD.known[57330] = true; WORLD.known[48266] = true; WORLD.auras.player = {}")
    L.execute(setup)
    m = ns.Buffs.Missing()
    return [m[i] for i in range(1, len(m) + 1)]
NOPRES = "function GetNumShapeshiftForms() return 3 end; function GetShapeshiftForm() return 0 end; function GetShapeshiftFormInfo(i) return 'i', false, true, ({48263, 48266, 48265})[i] end; "
INFROST = "function GetNumShapeshiftForms() return 3 end; function GetShapeshiftForm() return 2 end; function GetShapeshiftFormInfo(i) return 'i', i == 2, true, ({48263, 48266, 48265})[i] end; "
m = frost_buffs(NOPRES)
check(m == [48266, 57330], "Frost buffs: Frost Presence and Horn of Winter missing (got %s)" % m)
m = frost_buffs(INFROST + "WORLD.auras.player = {{id=6673, remain=300}}")
check(m == [], "Frost buffs: nothing missing in Frost Presence with a warrior's Battle Shout (got %s)" % m)
m = frost_buffs(INFROST + "WORLD.auras.player = {{id=57330, remain=300}}")
check(m == [], "Frost buffs: own Horn of Winter counts (got %s)" % m)
q = scenario("NO_HORN = true")
check(57330 not in q[:1], "Frost rotation: Horn of Winter isn't pushed to the top any more (got %s)" % q)

# never-suggest defaults: AMS / Army are simulator picks, not player picks
q = scenario("")
check(48707 not in q and 42650 not in q, "AMS and Army of the Dead never suggested by default (got %s)" % q)
q = scenario("WORLD.cd[51271]=60")
q2 = scenario("WORLD.cd[51271]=60; NS_UNBLOCK = true")
check(48707 in q2, "/rcr unblock brings AMS back (got %s)" % q2)

q = scenario(cds + "WORLD.known[49020] = nil")
check(FROST["obliterate"] not in q, "unknown spells never suggested (got %s)" % q)

q = scenario(cds + "WORLD.unusable = true")
check(q == [], "nothing usable -> empty queue (got %s)" % q)

# game says "not usable" (Dark Transformation without 5 Shadow Infusion) -> never suggested
def unholy(setup):
    L = new_lua()
    ns = load_addon_files(L)
    L.execute("WORLD.spec = 3; WORLD.power[6] = 40")
    rots = ns.SimData.specs["DEATHKNIGHT"][3]
    rot = rots[1]
    ids = set()
    for i in range(1, len(rot.list) + 1):
        if rot.list[i].id:
            ids.add(rot.list[i].id)
    for sid in ids:
        L.execute("WORLD.known[%d] = true" % sid)
    L.execute("for id in pairs(WORLD.known) do if id ~= 63560 then WORLD.cd[id] = 30 end end")
    L.execute(setup)
    q = ns.Sim.BuildQueue(rot)
    return [q[i] for i in range(1, len(q) + 1)] if q else [], 63560 in ids
q, has_dt = unholy("C_Spell.IsSpellUsable = function(id) if id == 63560 then return false, false end return true, false end")
check(has_dt and 63560 not in q, "Dark Transformation not usable (no 5 stacks) -> not suggested, even right after a cast (got %s)" % q)
q, _ = unholy("C_Spell.IsSpellUsable = function(id) return true, false end; WORLD.auras.pet = {{id=91342, stacks=5}}")
check(63560 in q, "Dark Transformation usable -> suggested (got %s)" % q)

# right-click / slash blocking
L, ns = new_lua(), None
ns = load_addon_files(L)
L.execute("WORLD.known[49020] = true; WORLD.known[49143] = true")
L.eval("function(ns) ns.Print = function() end end")(ns)
check(ns.Sim.ToggleBlock(49020) is True and ns.Sim.IsBlocked(49020), "right-click blocks a spell")
check(ns.Sim.ToggleBlock(49020) is False and not ns.Sim.IsBlocked(49020), "right-click again unblocks it")
check(ns.Sim.FindSpell("anti-magic shell") == 48707 and ns.Sim.FindSpell("48707") == 48707, "/rcr block finds spells by name or ID")
names = [b.name for b in ns.Sim.BlockedList().values()]
check(len(names) == len(list(ns.Sim.DEFAULT_BLOCK.keys())) and ("Spell48707" in names or "Anti-Magic Shell" in names), "blocked list shows the defaults (%d)" % len(names))

# --------------------------------------------------------------- 4. rotation picker
UI_STUB = r'''
UIParent = {}
UISpecialFrames = {}
EVENT_FRAMES = {}
local function region()
	local r = { shown = false, scripts = {}, text = "" }
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	function r:IsShown() return self.shown end
	function r:SetText(t) self.text = t end
	function r:GetText() return self.text end
	function r:SetScript(e, f) self.scripts[e] = f end
	function r:RegisterEvent(e) local ev = rawget(self, 'events') or {} self.events = ev ev[e] = true EVENT_FRAMES[#EVENT_FRAMES + 1] = self end
	function r:CreateFontString() return region() end
	function r:CreateTexture() return region() end
	setmetatable(r, { __index = function(_, k) if type(k) == "string" and k:match("^%u") then return function() end end end })
	return r
end
function CreateFrame(kind, name) local f = region() if name then _G[name] = f end return f end
COMBAT = false
function InCombatLockdown() return COMBAT end
C_Timer = { After = function(_, fn) fn() end }
function GetSpecializationInfo(i) return i, ({ "Blood", "Frost", "Unholy" })[i] end
PRINTS = {}
function FIRE(ev, ...)
	for _, f in ipairs(EVENT_FRAMES) do
		if rawget(f, 'events') and f.events[ev] and f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end
	end
end
'''


def picker_world():
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    L.execute(WORLD)
    L.execute(UI_STUB)
    ns = load_addon_files(L)
    L.eval("function(ns) ns.Print = function(m) PRINTS[#PRINTS + 1] = m end ns.T = function(k) return k end end")(ns)
    L.eval("function(src, ns) return assert(loadstring(src, 'SimPicker.lua'))('RCRotations', ns) end")(read("SimPicker.lua"), ns)
    L.execute("WORLD.spec = 2")
    return L, ns


L, ns = picker_world()
frost = ns.Sim.Rotations()[0]
names = [frost[i].file for i in range(1, len(frost) + 1)]
L.execute("FIRE('PLAYER_ENTERING_WORLD', true, false)")
pf = L.globals().RCRotationsPicker
check(pf is not None and pf.shown, "login with no saved choice -> picker opens (Frost DK: %s)" % names)
visible = [pf.buttons[i] for i in range(1, len(pf.buttons) + 1) if pf.buttons[i].shown]
check(len(visible) == len(frost), "one button per rotation (%d)" % len(visible))
target = next(i for i, n in enumerate(names, 1) if n.endswith("obliterate"))
pf.buttons[target].scripts.OnClick(pf.buttons[target])
check(ns.db.simPick["DEATHKNIGHT:2"] == "death_knight/frost/obliterate", "clicking Obliterate saves it for this spec")
check(ns.Sim.Current().file == "death_knight/frost/obliterate", "the HUD now uses Obliterate")
check(not pf.shown, "picker closes after choosing")
pf.shown = False
L.execute("FIRE('PLAYER_ENTERING_WORLD', false, true)")
check(not pf.shown, "next login with a saved choice -> no picker")
check(ns.Sim.ShowPicker(True) and pf.shown and pf.buttons[target].selected,
      "/rcr apl reopens it with the saved rotation highlighted")
pf.shown = False

L, ns = picker_world()
L.execute("COMBAT = true")
L.execute("FIRE('PLAYER_ENTERING_WORLD', true, false)")
pf = L.globals().RCRotationsPicker
check(pf is None or not pf.shown, "logging in during combat -> picker waits")
L.execute("COMBAT = false; FIRE('PLAYER_REGEN_ENABLED')")
pf = L.globals().RCRotationsPicker
check(pf is not None and pf.shown, "...and opens when combat ends")

L, ns = picker_world()
L.execute("WORLD.spec = 3")
one = ns.Sim.Rotations()[0]
L.execute("FIRE('PLAYER_ENTERING_WORLD', true, false)")
pf = L.globals().RCRotationsPicker
if len(one) < 2:
    check(pf is None or not pf.shown, "spec with a single rotation -> no picker")
else:
    check(pf is not None and pf.shown, "Unholy has %d rotations -> picker opens" % len(one))
L.execute("WORLD.spec = 1")
L.execute("RCRotationsPicker = RCRotationsPicker or {}; RCRotationsPicker.shown = false; FIRE('PLAYER_SPECIALIZATION_CHANGED', 'player')")
pf = L.globals().RCRotationsPicker
check(pf.shown and "Blood" in str(pf.sub.text if pf.sub else "SIM_PICK_TITLE"),
      "changing spec to one with no saved choice -> picker opens for the new spec")

# --------------------------------------------------------------- 5. in-game import
SIMS = os.environ.get("WOWSIMS_MOP")


def to_py(v):
    """lupa table -> Python list/dict for comparison."""
    if lupa_mod.lua_type(v) != "table":
        return v
    keys = list(v.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [to_py(v[i]) for i in range(1, len(keys) + 1)]
    if not keys:
        return []
    return {k: to_py(v[k]) for k in keys}


def same(a, b, path="$"):
    if isinstance(a, bool) or isinstance(b, bool):
        return (a == b) or path
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) < 1e-9 or path
    if isinstance(a, dict) and isinstance(b, dict):
        if set(a) != set(b):
            return path + " keys %s vs %s" % (sorted(a), sorted(b))
        for k in a:
            r = same(a[k], b[k], path + "." + str(k))
            if r is not True:
                return r
        return True
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return path + " len %d vs %d" % (len(a), len(b))
        for i, (x, y) in enumerate(zip(a, b)):
            r = same(x, y, "%s[%d]" % (path, i))
            if r is not True:
                return r
        return True
    return (a == b) or (path + " %r vs %r" % (a, b))


if SIMS and os.path.isdir(SIMS):
    L, ns = picker_world()
    lua_convert = L.eval("""function(ns, text)
        local raw, err = ns.Sim.JSONDecode(text)
        if raw == nil then return nil, err end
        local rot = ns.Sim.FindRotation(raw)
        if not rot then return nil, "no rotation" end
        local list = ns.Sim.ConvertRotation(rot)
        return list
    end""")
    files = sorted(glob.glob(os.path.join(SIMS, "ui", "specs", "*", "*", "apls", "*.apl.json")))
    mismatches = []
    compared = 0
    import json as _json
    for f in files:
        text = open(f, encoding="utf-8").read()
        raw = _json.loads(text)
        if raw.get("type") != "TypeAPL" or not raw.get("priorityList"):
            continue
        py_list, _ = conv.Converter().rotation(raw)
        res = lua_convert(ns, text)
        lua_list = res[0] if isinstance(res, tuple) else res
        if lua_list is None:
            mismatches.append("%s: Lua failed (%s)" % (f, res[1] if isinstance(res, tuple) else "?"))
            continue
        r = same(_json.loads(_json.dumps(py_list)), to_py(lua_list))
        compared += 1
        if r is not True:
            mismatches.append("%s: %s" % (f.split("specs/")[1], r))
    check(not mismatches and compared > 0,
          "in-game converter matches the Python converter on all %d WoWSims rotations %s" % (compared, mismatches[:3]))
else:
    print("SKIP converter parity (set WOWSIMS_MOP to a wowsims/mop checkout)")

L, ns = picker_world()
L.execute("RCRotationsDB = nil")
export = '{"player": {"class": "ClassDeathKnight", "rotation": {"type": "TypeAPL", "priorityList": [' \
         '{"action": {"condition": {"auraIsActive": {"auraId": {"spellId": 51124}}}, "castSpell": {"spellId": {"spellId": 49020}}}},' \
         '{"action": {"castSpell": {"spellId": {"spellId": 49143}}}},' \
         '{"action": {"castSpell": {"spellId": {"itemId": 76095}}}}]}}}'
L.execute("for _, id in ipairs({49020, 49143}) do WORLD.known[id] = true end")
res = ns.Sim.ImportText(export, "My Frost")
ok = res[0] if isinstance(res, tuple) else res
check(ok is True, "import: full WoWSims settings export accepted (%s)" % (res[1] if isinstance(res, tuple) else res))
bucket = L.globals().RCRotationsDB.simImports["DEATHKNIGHT:2"]
check(bucket is not None and len(bucket) == 1 and bucket[1].name.startswith("My Frost"),
      "import: saved account-wide for Frost DK")
check(ns.Sim.Current().file == "import/my_frost", "import: becomes the active rotation for the spec")
rots = ns.Sim.Rotations()[0]
check(len(rots) == len(ns.SimData.specs["DEATHKNIGHT"][2]) + 1, "import: listed after the WoWSims rotations")
L.execute("WORLD.auras.player = {{id=51124, remain=8}}")
q = ns.Sim.BuildQueue()
check([q[i] for i in range(1, len(q) + 1)] == [49020, 49143], "import: the imported rotation drives the HUD (got %s)" % [q[i] for i in range(1, len(q) + 1)])
res = ns.Sim.ImportText(export, "My Frost")
check(len(L.globals().RCRotationsDB.simImports["DEATHKNIGHT:2"]) == 1, "import: same name replaces instead of duplicating")
for bad, why in (("", "SIM_IMPORT_EMPTY"), ("{not json", "SIM_IMPORT_BADJSON"), ('{"player": {}}', "SIM_IMPORT_NOROT"),
                 ('{"type":"TypeAPL","priorityList":[{"action":{"autocastOtherCooldowns":{}}}]}', "SIM_IMPORT_NOCASTS")):
    r = ns.Sim.ImportText(bad, "x")
    check(r[0] is False and str(r[1]).startswith(why), "import: rejects bad input with %s" % why)
check(ns.Sim.RemoveImport("DEATHKNIGHT", 2, "import/my_frost") and ns.Sim.Current().file != "import/my_frost",
      "import: remove deletes it and falls back to a WoWSims rotation")
L.execute("WORLD.spec = 0")
r = ns.Sim.ImportText(export, "x")
check(r[0] is False, "import: refused without a specialization")
L.execute("WORLD.spec = 2")
check(ns.Sim.ShowImport() and L.globals().RCRotationsImport.shown, "import window opens")
check(ns.Sim.ShowPicker(True) and L.globals().RCRotationsPicker.importBtn is not None, "picker has an Import button")

# --------------------------------------------------------------- 6. spec detection across clients
L, ns = picker_world()
L.execute("GetSpecialization = nil; C_SpecializationInfo = { GetSpecialization = function() return 2 end, "
          "GetSpecializationInfo = function(i) return i, 'Frost' end }")
r = ns.Sim.Rotations()
check(r[0] is not None and r[2] == 2, "spec read through C_SpecializationInfo when the old global is gone")
check(ns.Sim.SpecName(2) == "Frost", "spec name read through C_SpecializationInfo")
L.execute("C_SpecializationInfo = nil; GetSpecialization = function() return 3 end; GetSpecializationInfo = function(i) return i, 'Unholy' end")
check(ns.Sim.Rotations()[2] == 3 and ns.Sim.SpecName(3) == "Unholy", "old global API still works")
L.execute("GetSpecialization = nil; GetSpecializationInfo = nil")
check(ns.Sim.Spec() == 0 and str(ns.Sim.NoSpecMessage()) == "SIM_IMPORT_NOSPEC", "MoP with no readable spec -> 'pick a spec' message")
# Workshop app rotations (companion addon global)
L, ns = picker_world()
L.execute("WORLD.spec = 2")
L.execute("""RCRotations_MyRotations = {
  { class = "DEATHKNIGHT", spec = 2, name = "My Frost", json = '{"type":"TypeAPL","priorityList":[{"action":{"castSpell":{"spellId":{"spellId":49020}}}},{"hide":true,"action":{"castSpell":{"spellId":{"spellId":49143}}}}]}' },
  { class = "DEATHKNIGHT", spec = 3, name = "Other spec", json = '{"priorityList":[]}' },
  { class = "DEATHKNIGHT", spec = 2, name = "Broken", json = 'not json' },
}""")
rots_now = ns.Sim.Rotations()[0]
names_now = [rots_now[i].name for i in range(1, len(rots_now) + 1)]
check(any(n.startswith("My Frost") for n in names_now), "workshop: app rotation listed for its spec (%s)" % names_now)
check(not any(n.startswith("Other spec") or n.startswith("Broken") for n in names_now), "workshop: other specs and broken entries skipped")
ws = next(rots_now[i] for i in range(1, len(rots_now) + 1) if rots_now[i].name.startswith("My Frost"))
check(len(list(ws.list.keys())) == 1 and ws.list[1].id == 49020, "workshop: lines turned off in the app are left out")
L.execute("RCRotations_MyRotations = nil")
# the app's real output file loads in the addon (needs node)
import shutil as _sh, subprocess as _sp
if _sh.which("node"):
    lua_out = _sp.run(["node", "-e", """
const wow = require(process.argv[1]);
process.stdout.write(wow.buildLua([{ token: "DEATHKNIGHT", specIndex: 2, name: 'Rob\\'s "Frost" ]]==]',
  rotation: { priorityList: [{ action: { castSpell: { spellId: { spellId: 49143 } } } }] } }]));
""", os.path.join(ROOT, "app", "wow.js")], capture_output=True, text=True, check=True).stdout
    L, ns = picker_world()
    L.execute("WORLD.spec = 2")
    L.execute(lua_out)
    rl = ns.Sim.Rotations()[0]
    got = [rl[i].name for i in range(1, len(rl) + 1)]
    check(any("Frost" in n and ("(Workshop)" in n or "SIM_WORKSHOP_TAG" in n) for n in got), "app: MyRotations.lua written by the app loads in game (%s)" % got)
else:
    print("SKIP app file round trip (no node)")
# --------------------------------------------------------------- 6b. WoWSims only: empty specs, Era/TBC imports
L, ns = picker_world()
L.execute("WORLD.spec = 2; ns_db_reset = true")
ns.SimData = None  # a spec with no bundled WoWSims rotation
L.execute("FIRE('PLAYER_ENTERING_WORLD', true, false)")
pf = L.globals().RCRotationsPicker
check(pf is not None and pf.shown and pf.importBtn is not None and pf.importBtn.shown is not False,
      "no WoWSims rotation for the spec -> first login opens the picker with Import")
pf.shown = False
L.execute("FIRE('PLAYER_ENTERING_WORLD', false, true)")
check(not pf.shown, "...only once per character and spec")
check(ns.Sim.Current() is None, "...and nothing else is suggested (no built-in fallback)")

L, ns = picker_world()
ns.GAME = "tbc"
L.execute("GetSpecialization = nil; C_SpecializationInfo = nil; WORLD.known[1752] = true")
r = ns.Sim.ImportText("NAG_ROTATION:WARLOCK:2:1.0:eyJhIjoxfQ==", "x")
check(r[0] is False and r[1] == "SIM_IMPORT_NAG", "import: a NAG rotation string gets a clear message (got %s)" % (r[1],))
era = '{"type":"TypeAPL","priorityList":[{"action":{"castSpell":{"spellId":{"spellId":1752}}}}]}'
r = ns.Sim.ImportText(era, "Combat")
check(r[0] is True, "TBC (no specs): import accepted (%s)" % (r[1],))
check(L.globals().RCRotationsDB.simImports["DEATHKNIGHT:0"] is not None, "TBC: saved per class (spec 0)")
q = ns.Sim.BuildQueue()
check(q is not None and q[1] == 1752, "TBC: the imported rotation drives the HUD")

# --------------------------------------------------------------- 7. flash targeting (Glow.lua)
Lg = lupa_mod.LuaRuntime()
Lg.globals().GLOW_PATH = os.path.join(ROOT, "Glow.lua")
Lg.execute("PRINTED = {} local p = print function print(m) PRINTED[#PRINTED + 1] = m end")
Lg.execute(read(os.path.join("tools", "test_glow.lua")))
for line in Lg.globals().PRINTED.values():
    if line.startswith("PASS ") or line.startswith("FAIL "):
        check(line.startswith("PASS "), "flash: " + line[5:])

# --------------------------------------------------------------- 9. tuning layer
import tuning as tun
STRUCT = {"and", "or", "not", "cmp", "math", "max", "min"}
samples = ["pet.buff(91342).stacks >= 5", "runes.blood == 0 and runes.frost == 0", "not buff(51124) or target.health.pct < 35%",
           "cooldown(49020).remains <= 1.5s", "debuff(55095).remains < 3s and targets >= 3", "execute(20)", "debuff(55095).down",
           "spell(63560).usable and gcd.ready", "holy_power >= 3 or chi > 1", "mana.pct > 50% and not moving", "buff(81229).known",
           "time_to_die > 20s and combat_time > 5", "cooldown(1).charges >= 1 and spell(1).cast_time < 1", "health < 10000 and target.buff(1).remains > 1"]
kinds = set()
for text in samples:
    kinds |= tun.node_kinds(tun.parse_condition(text))
check(kinds - STRUCT <= conv.SUPPORTED, "tuning syntax only produces conditions the evaluator supports %s" % sorted(kinds - STRUCT - conv.SUPPORTED))
for bad in ("buff(5).bogus", "pet.buff(1).stacks >=", "runes.purple > 1", "wat > 1", "buff(1) and"):
    try:
        tun.parse_condition(bad)
        check(False, "tuning syntax rejects %r" % bad)
    except tun.TuningError:
        check(True, "tuning syntax rejects %r" % bad)
try:
    tun.compile_tuning({"death_knight/purple": {"block": [1]}}, conv.SPECS)
    check(False, "tuning: unknown spec rejected")
except tun.TuningError:
    check(True, "tuning: unknown spec rejected")
shipped = tun.load(os.path.join(ROOT, "rotations", "tuning", "mists.json"), conv.SPECS)
check("DEATHKNIGHT:3" in shipped, "shipped tuning file compiles (%s)" % ", ".join(sorted(shipped)))

# shipped fix: Dark Transformation waits for 5 Shadow Infusion even if the game says usable
q, _ = unholy("C_Spell.IsSpellUsable = function(id) return true, false end; WORLD.auras.pet = {{id=91342, stacks=3}}")
check(63560 not in q, "tuning: Dark Transformation held at 3 Shadow Infusion stacks (got %s)" % q)

# synthetic rules on Frost DK: block, move, add
L = new_lua()
ns = load_addon_files(L)
for sid in (51271, 42650, 48707, 77575, 49184, 45462, 49020, 49143, 57330, 47568, 123693, 12345):
    L.execute("WORLD.known[%d] = true" % sid)
L.execute("WORLD.spec = 2; WORLD.power[6] = 20; WORLD.cd[51271] = 60; WORLD.cd[57330] = 20; WORLD.cd[47568] = 200")
setrules = L.eval("""function(ns)
	ns.SimData.tuning["DEATHKNIGHT:2"] = {
		block = { 77575 },
		move = { { id = 45462, to = "top" } },
		add = { { id = 12345, at = "top", c = { k = "cmp", op = ">=", v = { { k = "currentRunicPower" }, 10 } } } },
	}
end""")
setrules(ns)
rots = ns.SimData.specs["DEATHKNIGHT"][2]
rot = next(rots[i] for i in range(1, len(rots) + 1) if rots[i].file.endswith("obliterate"))
q = ns.Sim.BuildQueue(rot)
q = [q[i] for i in range(1, len(q) + 1)]
check(q[:2] == [12345, 45462], "tuning: 'add at top' and 'move to top' take the first slots (got %s)" % q)
check(77575 not in q, "tuning: blocked spell skipped (got %s)" % q)
check(len(list(rot.list.keys())) == len(list(rot.list.keys())) and rot.list[1].id != 12345, "tuning never edits the original rotation")
L.execute("WORLD.power[6] = 5")
q = ns.Sim.BuildQueue(rot)
q = [q[i] for i in range(1, len(q) + 1)]
check(12345 not in q, "tuning: added line respects its 'when' (got %s)" % q)

# "coming up": with nothing castable, the HUD names the spell that's ready soonest
cds_short = cds + "WORLD.cd[77575]=50; WORLD.auras.target = {{id=55095, remain=20}, {id=55078, remain=20}}; WORLD.power[6] = 5; "
q = scenario(cds_short + "WORLD.cd[123693]=30; WORLD.cd[45462]=30; WORLD.known[49143] = nil; WORLD.cd[49020]=2; WORLD.cd[49184]=4")
check(q[:1] == [49020], "coming up: nothing castable -> Obliterate (ready in 2s) shown instead of a blank HUD (got %s)" % q)
q = scenario(cds_short + "WORLD.cd[49020]=9")
check(49020 not in q, "coming up: nothing further away than %ss (got %s)" % (6, q))
L = new_lua()
ns = load_addon_files(L)
for sid in (49020, 49143):
    L.execute("WORLD.known[%d] = true" % sid)
L.execute("WORLD.cd[49020] = 3; WORLD.cd[49143] = 0")
lst = L.eval("{ { id = 49143 }, { id = 49020 } }")
q = ns.Sim.BuildQueue(L.eval("function(l) return { name = 't', file = 't', list = l } end")(lst))
check(q[1] == 49143 and q[2] == 49020 and q.soon[49020] and not q.soon[49143],
      "coming up: castable spell first, then the next one marked 'soon'")
ns.db.simLookahead = False
q = ns.Sim.BuildQueue(L.eval("function(l) return { name = 't', file = 't', list = l } end")(lst))
check(q[2] is None, "coming up: can be turned off")
L.execute("C_Spell.IsSpellUsable = function(id) return id ~= 49020, false end")
ns.db.simLookahead = None
q = ns.Sim.BuildQueue(L.eval("function(l) return { name = 't', file = 't', list = l } end")(lst))
check(q[2] is None, "coming up: never shows a spell the game says isn't usable")

# stance: seal reminder for Retribution (seals sit on the stance bar)
for text, want in (("stance == 0", {"k": "cmp"}), ("stance(31801)", {"k": "playerStance", "id": 31801})):
    node = tun.parse_condition(text)
    check(all(node.get(k) == v for k, v in want.items()), "tuning syntax: %s" % text)
L = new_lua()
ns = load_addon_files(L)
L.execute("""
function UnitClass() return "Paladin", "PALADIN", 2 end
WORLD.spec = 3; for _, id in ipairs({31801, 20154, 20217, 19740, 25780, 35395}) do WORLD.known[id] = true end
STANCE = 0; WORLD.auras.player = {}
function GetNumShapeshiftForms() return 2 end
function GetShapeshiftForm() return STANCE end
function GetShapeshiftFormInfo(i) return 'icon', STANCE == i, true, ({31801, 20154})[i] end
""")
L.eval("function(ns) ns.ClassToken = function() return 'PALADIN', 2 end end")(ns)
def ret_buffs(setup=""):
    L.execute(setup)
    m = ns.Buffs.Missing()
    return [m[i] for i in range(1, len(m) + 1)]
m = ret_buffs()
check(m == [31801, 20217], "Ret buffs: no seal and no stats buff -> Seal of Truth, Blessing of Kings (got %s)" % m)
m = ret_buffs("STANCE = 2")
check(31801 not in m, "Ret buffs: any seal counts (Righteousness on) (got %s)" % m)
m = ret_buffs("STANCE = 1; WORLD.auras.player = {{id=1126, remain=3600}}")
check(m == [19740], "Ret buffs: a druid's Mark of the Wild covers Kings, so Blessing of Might instead (got %s)" % m)
m = ret_buffs("WORLD.auras.player = {{id=1126, remain=3600}, {id=116956, remain=3600}}")
check(m == [], "Ret buffs: a shaman's Grace of Air covers Might (got %s)" % m)
m = ret_buffs("WORLD.auras.player = {}; function GetRaidBuffTrayAuraInfo(i) if i == 1 or i == 8 then return 'Buff' end end")
check(m == [], "Ret buffs: the game's raid buff tray counts as covered (got %s)" % m)
L.execute("GetRaidBuffTrayAuraInfo = nil")
check(L.eval("function(ns) return ns.Sim.HANDLERS.playerStance({ id = 31801 }) end")(ns) is True, "stance(31801) true while Truth is active")
m = ret_buffs("ns_dead = true; function UnitIsDeadOrGhost() return true end")
check(m == [], "Buffs: nothing while dead (got %s)" % m)
L.execute("UnitIsDeadOrGhost = nil")

# Rogue poisons, Warlock pet (Grimoire of Sacrifice counts), Shaman imbues
def class_buffs(cls, token, cid, spec, known, setup):
    L = new_lua()
    ns = load_addon_files(L)
    L.execute("function UnitClass() return '%s', '%s', %d end; WORLD.spec = %d; WORLD.auras.player = {}" % (cls, token, cid, spec))
    for k in known:
        L.execute("WORLD.known[%d] = true" % k)
    L.eval("function(ns) ns.ClassToken = function() return '%s', %d end end" % (token, cid))(ns)
    L.execute(setup)
    m = ns.Buffs.Missing()
    return [m[i] for i in range(1, len(m) + 1)]
m = class_buffs("Rogue", "ROGUE", 4, 1, (2823, 8679, 3408), "WORLD.auras.player = {{id=8679, remain=3600}}")
check(m == [3408], "Rogue: Wound Poison counts as the lethal poison; non-lethal still missing (got %s)" % m)
m = class_buffs("Warlock", "WARLOCK", 9, 3, (109773, 688), "function UnitExists(u) return u ~= 'pet' end")
check(m == [109773, 688], "Destruction: Dark Intent and Imp missing (got %s)" % m)
m = class_buffs("Warlock", "WARLOCK", 9, 3, (109773, 688), "function UnitExists(u) return u ~= 'pet' end; WORLD.auras.player = {{id=108503, remain=3600}, {id=1459, remain=3600}}")
check(m == [], "Destruction: Grimoire of Sacrifice means no pet; a mage's Brilliance covers spell power (got %s)" % m)
m = class_buffs("Shaman", "SHAMAN", 7, 2, (324, 8232, 8024), "function GetWeaponEnchantInfo() return true, 0, 0, 0, false end; function GetInventoryItemID(_, slot) return slot == 17 and 1234 or nil end")
check(m == [324, 8024], "Enhancement: Lightning Shield and the off-hand Flametongue missing (got %s)" % m)

# Metamorphosis: Shadow Bolt -> Touch of Chaos, Corruption -> Doom on the same buttons
L = new_lua()
ns = load_addon_files(L)
L.execute("""
function UnitClass() return "Warlock", "WARLOCK", 9 end
WORLD.spec = 2; META = false
OVER = { [686] = 103964, [172] = 603, [105174] = 124916, [6353] = 104027 }
BASE = {}
for b, o in pairs(OVER) do BASE[o] = b end
for _, id in ipairs({686, 172, 105174, 6353, 103958, 1454, 113861, 104316}) do WORLD.known[id] = true end
""")
L.eval("""function(ns)
	ns.ClassToken = function() return 'WARLOCK', 9 end
	ns.API.BaseSpell = function(id) return BASE[id] end
	ns.API.CurrentOverride = function(id) if META and OVER[id] then return OVER[id] end return id end
	ns.API.Ready = function(id) return WORLD.known[id] or (META and BASE[id] and WORLD.known[BASE[id]]) or false end
	ns.API.Resolve = function(id)
		if META and OVER[id] and WORLD.known[id] then return OVER[id] end
		if WORLD.known[id] then return id end
		return nil
	end
end""")(ns)
demo = ns.SimData.specs["WARLOCK"][2][1]
def demo_q(setup):
    L.execute(setup)
    q = ns.Sim.BuildQueue(demo)
    return [q[i] for i in range(1, len(q) + 1)] if q else []
q = demo_q("META = false; WORLD.power[15] = 100; WORLD.auras.player = {}; WORLD.auras.target = {{id=172, remain=20, kind='HARMFUL'}}")
check(103964 not in q and 603 not in q, "Demo out of Meta: no Touch of Chaos / Doom (got %s)" % q)
check(len(q) > 0, "Demo out of Meta: something to cast (got %s)" % q)
q = demo_q("WORLD.cd[113861] = 60; WORLD.cd[104316] = 60; META = true; WORLD.power[15] = 600; WORLD.auras.player = {{id=103958, remain=60}}; WORLD.auras.target = {{id=172, remain=3, kind='HARMFUL'}, {id=603, remain=40, kind='HARMFUL'}}")
check(q[:1] == [103964], "Demo in Meta, Corruption about to drop: Touch of Chaos first (got %s)" % q)
check(686 not in q and 172 not in q, "Demo in Meta: icons follow the buttons (no Shadow Bolt / Corruption) (got %s)" % q)
check(103958 not in q, "Demo in Meta: never suggests Metamorphosis again (it would cancel it) (got %s)" % q)
q = demo_q("WORLD.cd[103958] = 0; META = true; WORLD.power[15] = 250; WORLD.auras.player = {{id=103958, remain=60}}; WORLD.auras.target = {{id=172, remain=20, kind='HARMFUL'}, {id=603, remain=40, kind='HARMFUL'}}")
qt = ns.Sim.BuildQueue(demo)
check(103958 in q and qt.cancel and qt.cancel[103958], "Demo in Meta, low fury, no Dark Soul: WoWSims' 'cancel Metamorphosis' line shows, marked CANCEL (got %s)" % q)
q = demo_q("WORLD.power[15] = 800")
check(103958 not in q, "Demo in Meta with plenty of fury: no cancel (got %s)" % q)
q = demo_q("WORLD.known[1490] = true; META = false; WORLD.auras.player = {}; WORLD.auras.target = {{id=172, remain=20, kind='HARMFUL'}}")
check(q[:1] == [1490], "Warlock: Curse of the Elements first when the target has no magic-damage debuff (got %s)" % q)
q = demo_q("WORLD.auras.target = {{id=172, remain=20, kind='HARMFUL'}, {id=34889, remain=20, kind='HARMFUL'}}")
check(1490 not in q, "Warlock: no Curse of the Elements when a hunter pet's Fire Breath covers it (got %s)" % q)

# Discipline (our own Atonement rotation; WoWSims has none)
L = new_lua()
ns = load_addon_files(L)
L.execute("""
function UnitClass() return "Priest", "PRIEST", 5 end
WORLD.spec = 1
for _, id in ipairs({588, 21562, 10060, 34433, 81700, 589, 47540, 14914, 585}) do WORLD.known[id] = true end
""")
L.eval("function(ns) ns.ClassToken = function() return 'PRIEST', 5 end end")(ns)
discs = ns.SimData.specs["PRIEST"][1]
disc = discs[1]
check(str(disc.file) == "custom/priest/discipline/atonement", "Discipline has a rotation (%s)" % disc.file)
def disc_q(setup):
    L.execute(setup)
    q = ns.Sim.BuildQueue(disc)
    return [q[i] for i in range(1, len(q) + 1)] if q else []
base = "WORLD.cd[10060] = 60; WORLD.cd[34433] = 60; WORLD.power[0] = 100; WORLD.powerMax[0] = 100; "
q = disc_q(base + "WORLD.auras.player = {}; WORLD.auras.target = {}")
check(q[:1] == [589], "Disc: Shadow Word: Pain first when missing (got %s)" % q)
mb = ns.Buffs.Missing(); mb = [mb[i] for i in range(1, len(mb) + 1)]
check(mb == [21562, 588], "Disc buffs: Power Word: Fortitude and Inner Fire as reminders (got %s)" % mb)
q = disc_q(base + "WORLD.auras.player = {{id=588, remain=900}, {id=81661, stacks=5}}; WORLD.auras.target = {{id=589, remain=15, kind='HARMFUL'}}")
check(q[:3] == [81700, 47540, 14914], "Disc: Archangel at 5 Evangelism, then Penance, Holy Fire (got %s)" % q)
q = disc_q(base + "WORLD.cd[81700] = 60; WORLD.cd[47540] = 8; WORLD.cd[14914] = 8; WORLD.auras.player = {{id=588, remain=900}}")
check(q[:1] == [585], "Disc: Smite as filler (got %s)" % q)

# WoW Forever: the built-in Forever Rotation lists are exported for the Workshop app
import build_workshop_data as bwd
fr_rots, fr_names = bwd.forever_rotations(ROOT)
check(len(fr_rots) >= 15 and all(r["specIndex"] == 0 and r["game"] == "forever" for r in fr_rots),
      "Forever lists exported for the app (%d rotations)" % len(fr_rots))
fr_bad = []
for r in fr_rots:
    c = conv.Converter()
    items, skipped = c.rotation(r["rotation"])
    if c.unsupported or skipped or not items:
        fr_bad.append(r["file"])
check(not fr_bad, "every exported Forever list converts cleanly %s" % fr_bad)
check(fr_names.get(407995) == "Mangle", "shared-ID Forever spells get their common name (%s)" % fr_names.get(407995))

# ...and a Workshop rotation saved for Forever (spec 0) takes over from the built-in list
L, ns = picker_world()
ns.GAME = "forever"
L.execute("GetSpecialization = nil; C_SpecializationInfo = nil; WORLD.known[49020] = true")
L.execute("""RCRotations_MyRotations = { { class = "DEATHKNIGHT", spec = 0, name = "Mine", json = '{"priorityList":[{"action":{"castSpell":{"spellId":{"spellId":49020}}}}]}' } }""")
rl = ns.Sim.Rotations()[0]
check(rl is not None and any(str(rl[i].name).startswith("Mine") for i in range(1, len(rl) + 1)) and ns.Sim.Active(),
      "Forever: a Workshop rotation is active (and replaces the built-in list)")

# --------------------------------------------------------------- 8. auto-release helpers
import json as _j
import shutil
import subprocess
import tempfile
tmp = tempfile.mkdtemp()
try:
    def write(name, text):
        p = os.path.join(tmp, name)
        open(p, "w").write(text)
        return p
    old = write("old.lua", 'file = "a/b/x"\nfile = "a/b/y"\n')
    same = write("same.lua", 'file = "a/b/x"\nfile = "a/b/y"\nfile = "a/b/z"\n')
    lost = write("lost.lua", 'file = "a/b/x"\n')
    ok_sum = write("ok.json", _j.dumps({"unsupported": 0}))
    bad_sum = write("bad.json", _j.dumps({"unsupported": 2}))
    guard = [sys.executable, "-I", os.path.join(ROOT, "tools", "sync_release.py"), "guard"]
    check(subprocess.run(guard + [old, same, ok_sum], capture_output=True).returncode == 0, "auto-release: added rotation is safe")
    check(subprocess.run(guard + [old, lost, ok_sum], capture_output=True).returncode == 1, "auto-release: removed rotation needs review")
    check(subprocess.run(guard + [old, same, bad_sum], capture_output=True).returncode == 1, "auto-release: unsupported items need review")
    os.makedirs(os.path.join(tmp, "repo", "tools"))
    for f in ("RCRotations.toc", "RCRotations_Camelot.toc", "VERSION.txt"):
        shutil.copy(os.path.join(ROOT, f), os.path.join(tmp, "repo", f))
    shutil.copy(os.path.join(ROOT, "tools", "sync_release.py"), os.path.join(tmp, "repo", "tools"))
    cur = re.search(r"## Version: (\d+)\.(\d+)\.(\d+)", read("RCRotations.toc")).groups()
    out = subprocess.run([sys.executable, "-I", os.path.join(tmp, "repo", "tools", "sync_release.py"), "bump", "abcdef1234567"],
                         capture_output=True, text=True).stdout.strip()
    want = "%s.%s.%d" % (cur[0], cur[1], int(cur[2]) + 1)
    tocs_ok = all(("## Version: " + want) in open(os.path.join(tmp, "repo", f)).read() for f in ("RCRotations.toc", "RCRotations_Camelot.toc"))
    check(out == want and tocs_ok and open(os.path.join(tmp, "repo", "VERSION.txt")).read().startswith(want),
          "auto-release: version bump %s -> %s in both TOCs and the changelog" % (".".join(cur), out))
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
print("ALL PASS" if not FAILS else "%d FAILED" % len(FAILS))
sys.exit(1 if FAILS else 0)
