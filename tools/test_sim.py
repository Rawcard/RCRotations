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
    return ns


# --------------------------------------------------------------- 1. sync
L = new_lua()
ns = load_addon_files(L)
handlers = set(k for k in ns.Sim.HANDLERS.keys())
missing_in_lua = conv.SUPPORTED - handlers
missing_in_py = handlers - conv.SUPPORTED
check(not missing_in_lua, "every SUPPORTED kind has a Sim.lua handler %s" % (sorted(missing_in_lua) or ""))
check(not missing_in_py, "every Sim.lua handler is in SUPPORTED %s" % (sorted(missing_in_py) or ""))

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

print()
print("ALL PASS" if not FAILS else "%d FAILED" % len(FAILS))
sys.exit(1 if FAILS else 0)
