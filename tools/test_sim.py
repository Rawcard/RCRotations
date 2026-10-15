#!/usr/bin/env python3
"""Tests for the WoWSims pipeline (needs `pip install lupa`).

1. The converter's SUPPORTED set matches the handlers in Sim.lua.
2. Every generated SimData_*.lua loads under LuaJIT (Lua 5.1 rules, like WoW).
3. Frost DK scenarios run through Sim.lua with a fake game state.

Run from the repo root:  python3 tools/test_sim.py
"""
import glob
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

q = scenario(cds + "WORLD.known[49020] = nil")
check(FROST["obliterate"] not in q, "unknown spells never suggested (got %s)" % q)

q = scenario(cds + "WORLD.unusable = true")
check(q == [], "nothing usable -> empty queue (got %s)" % q)

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
ns.GAME = "tbc"
check(str(ns.Sim.NoSpecMessage()).startswith("SIM_NOT_THIS_CLIENT"), "TBC/Era -> 'WoWSims rotations are for MoP Classic' message")

# --------------------------------------------------------------- 7. flash targeting (Glow.lua)
Lg = lupa_mod.LuaRuntime()
Lg.globals().GLOW_PATH = os.path.join(ROOT, "Glow.lua")
Lg.execute("PRINTED = {} local p = print function print(m) PRINTED[#PRINTED + 1] = m end")
Lg.execute(read(os.path.join("tools", "test_glow.lua")))
for line in Lg.globals().PRINTED.values():
    if line.startswith("PASS ") or line.startswith("FAIL "):
        check(line.startswith("PASS "), "flash: " + line[5:])

print()
print("ALL PASS" if not FAILS else "%d FAILED" % len(FAILS))
sys.exit(1 if FAILS else 0)
