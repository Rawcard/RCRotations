#!/usr/bin/env python3
"""WoW Forever check: run the whole addon on the camelot client for all nine
Forever classes, with the retail-style API Forever uses and secret values in
combat (target health, names, auras and cooldowns hidden from addons).

  pip install lupa
  python3 tools/test_forever.py

For each class and role: login, out-of-combat ticks, then a fight with secret
values (ticks, casts, auras, power, nameplates on, menu and windows open),
then leaving combat. Fails on any Lua error, and when no spell is suggested.
"""
import os
import sys

import lupa.luajit21 as lupa_mod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASSES = [("WARRIOR", 1), ("PALADIN", 2), ("HUNTER", 3), ("ROGUE", 4), ("PRIEST", 5),
           ("SHAMAN", 7), ("MAGE", 8), ("WARLOCK", 9), ("DRUID", 11)]

RUN = r"""
NO_SECRETS = NO_SECRETS_WANTED
local ns = {}
local files = {}
for line in io.lines(ADDON_DIR .. "/RCRotations_Camelot.toc") do
	line = line:gsub("\r", "")
	if line:match("%.lua$") then files[#files + 1] = line end
end
for _, f in ipairs(files) do
	local chunk = assert(loadfile(ADDON_DIR .. "/" .. f))
	local ok, err = pcall(chunk, "RCRotations", ns)
	if not ok then error("LOAD " .. f .. ": " .. tostring(err)) end
end
assert(ns.GAME == "forever", "camelot client must be detected as WoW Forever (got " .. tostring(ns.GAME) .. ")")

local function fire(ev, ...)
	for _, f in ipairs(ALLFRAMES) do
		local fn = f.scripts.OnEvent
		if fn and (not f.events or f.events[ev]) then
			local ok, err = pcall(fn, f, ev, ...)
			if not ok then error("EVENT " .. ev .. ": " .. tostring(err)) end
		end
	end
end
local function update(dt)
	local due = TIMERS
	TIMERS = {}
	for _, fn in ipairs(due) do
		local ok, err = pcall(fn)
		if not ok then error("timer: " .. tostring(err)) end
	end
	for _, f in ipairs(ALLFRAMES) do
		local fn = f.scripts.OnUpdate
		if fn then
			local ok, err = pcall(fn, f, dt)
			if not ok then error("OnUpdate: " .. tostring(err)) end
		end
	end
end
local function step(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then error(label .. ": " .. tostring(err)) end
end

fire("ADDON_LOADED", "RCRotations")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
for _, fn in ipairs(TIMERS) do step("timer", fn) end
TIMERS = {}

-- the class knows every spell its lists use; put them on the action bars
local classKey = ({ WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
	SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" })[CLASS_FILE]
local book = ns.Spell and ns.Spell[classKey]
assert(type(book) == "table", "no spell table for " .. CLASS_FILE)
local slot = 0
for _, id in pairs(book) do
	if type(id) == "number" and id > 0 then
		KNOWN[id] = true
		if slot < 60 then slot = slot + 1; ACTION[slot] = id end
	end
end
if ns.API and ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
if ns.GlowInvalidate then pcall(ns.GlowInvalidate) end
fire("ACTIONBAR_SLOT_CHANGED", 0)
for i = 1, 20 do update(0.05) end

local report = { roles = {} }
local function suggest()
	local q = ns.BuildQueue and ns.BuildQueue() or {}
	return q[1]
end

local roles = {}
local seen = {}
for i = 1, 8 do
	local r = ns.db.role or "damage"
	if seen[r] then break end
	seen[r] = true
	roles[#roles + 1] = r
	step("CycleRole", ns.CycleRole)
end

NOW = 1000
for _, role in ipairs(roles) do
	ns.db.role = role
	if ns.InvalidateTick then ns.InvalidateTick() end
	-- out of combat, no target
	COMBAT, TARGET = false, false
	step("tick idle " .. role, ns.Tick)
	-- pull: target, then combat with secret values
	TARGET = true
	fire("PLAYER_TARGET_CHANGED")
	step("tick target " .. role, ns.Tick)
	COMBAT = true
	fire("PLAYER_REGEN_DISABLED")
	fire("PLAYER_ENTER_COMBAT")
	local hits = 0
	for t = 1, 40 do
		NOW = NOW + 0.25
		step("tick combat " .. role, ns.Tick)
		update(0.25)
		local id = suggest()
		if id then
			hits = hits + 1
			if t % 6 == 0 then
				fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", id)
				fire("UNIT_SPELLCAST_SENT", "player", "Bandit", "Cast-1", id)
			end
		end
		if t % 5 == 0 then
			fire("UNIT_AURA", "target")
			fire("UNIT_AURA", "player")
			fire("UNIT_POWER_UPDATE", "player", "MANA")
			fire("UNIT_HEALTH", "target")
		end
		if t == 10 then
			fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
			fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
		end
	end
	report.roles[role] = hits
	local flashed = false
	for i = 1, 60 do
		local b = BUTTONS[i]
		for _, f in pairs(b and rawget(b, "RCRFlash") or {}) do
			if f.shown then flashed = true end
		end
	end
	report.flash = (report.flash or 0) + (flashed and 1 or 0)
	COMBAT = false
	fire("PLAYER_REGEN_ENABLED")
	fire("PLAYER_LEAVE_COMBAT")
	step("tick after combat " .. role, ns.Tick)
end

-- features: nameplates in and out of combat, menu, windows, what's new
step("plates on", SlashCmdList.RCROT, "plates")
COMBAT = true
NOW = NOW + 1
update(0.6)
fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
update(0.6)
-- hostility itself hidden (secret boolean): bars fade through SetAlphaFromBoolean
SECRET_BOOLS, COMBAT = true, true
update(0.6)
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local p1 = PLATES_LIST[1].UnitFrame.healthBar
assert((p1.fromBool or 0) > 0, "secret hostility: Blizzard plate bar faded with SetAlphaFromBoolean")
local p3 = PLATES_LIST[3].unitFrame.Health
assert((p3.fromBool or 0) > 0, "secret hostility: ElvUI plate bar faded with SetAlphaFromBoolean")
SECRET_BOOLS, COMBAT = false, false
fire("PLAYER_REGEN_ENABLED")
update(0.6)
assert(PLATES_LIST[1].UnitFrame.healthBar.alpha == 0, "out of combat: enemy plate bar hidden")
step("plates off", SlashCmdList.RCROT, "plates")
update(0.6)
assert(PLATES_LIST[1].UnitFrame.healthBar.alpha == 1, "option off: bar back")
step("menu", ns.ToggleOptions)
step("refresh menu", ns.RefreshOptions or function() end)
step("what's new", ns.ShowWhatsNew)
step("copy link", ns.ShowCopyLink)
step("close menu", ns.ToggleOptions)
-- buff reminders (Forever list): out of combat only, never when buffs are hidden
step("buffs", function()
	COMBAT, AURAS_SECRET = false, false
	AURAS.player = {}
	local m = ns.Buffs.Missing()
	report.buffs = #m
	BUFFS_SEEN = {}
	for i, id in ipairs(m) do BUFFS_SEEN[i] = id end
	COMBAT = true
	assert(#ns.Buffs.Missing() == 0, "no buff reminders in combat on Forever")
	COMBAT = false
	AURAS.player = { { spellId = 1, name = "Buff" } }
	AURAS_SECRET = true
	assert(#ns.Buffs.Missing() == 0, "no buff reminders while buffs are hidden")
	AURAS_SECRET = false
	-- every reminder goes away once its buff is up
	AURAS.player = {}
	for _, id in ipairs(m) do
		AURAS.player[#AURAS.player + 1] = { spellId = id, name = "Spell" .. id }
	end
	PET = true
	local left = ns.Buffs.Missing()
	PET = false
	for _, id in ipairs(left) do
		for _, was in ipairs(m) do
			assert(id ~= was, "reminder for " .. id .. " stays after the buff is up")
		end
	end
	AURAS.player = { { spellId = 1, name = "Buff" } }
	local function has(list, id) for _, x in ipairs(list) do if x == id then return true end end return false end
	local S = ns.Spell
	if CLASS_FILE == "PALADIN" then
		-- another paladin's Greater Blessing of Kings and any aura count
		AURAS.player = { { spellId = 25898, name = "Spell25898" }, { spellId = S.Paladin.RetributionAura, name = "Spell" .. S.Paladin.RetributionAura } }
		assert(#ns.Buffs.Missing() == 0, "paladin: any blessing (even a Greater one) and any aura count")
	elseif CLASS_FILE == "WARLOCK" then
		AURAS.player = { { spellId = S.Warlock.DemonArmor, name = "Spell" .. S.Warlock.DemonArmor } }
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", S.Warlock.SummonFelhunter)
		assert(has(ns.Buffs.Missing(), S.Warlock.SummonFelhunter), "warlock: suggests the demon summoned last")
	elseif CLASS_FILE == "DRUID" then
		-- group: a party member near you without your Mark
		local origExists, origName = UnitExists, UnitName
		IsInGroup = function() return true end
		GetNumSubgroupMembers = function() return 1 end
		UnitExists = function(u) if u == "party1" then return true end return origExists(u) end
		UnitName = function(u) if u == "party1" then return "Leo" end return origName(u) end
		AURAS.player = { { spellId = S.Druid.MarkoftheWild, name = "Spell" .. S.Druid.MarkoftheWild } }
		AURAS.party1 = {}
		NOW = NOW + 2
		assert(has(ns.Buffs.Missing(), S.Druid.MarkoftheWild), "druid: party member without Mark of the Wild")
		AURAS.party1 = { { spellId = 21849, name = "Spell21849" } }
		NOW = NOW + 2
		assert(not has(ns.Buffs.Missing(), S.Druid.MarkoftheWild), "druid: Gift of the Wild on them counts")
		IsInGroup = function() return false end
		UnitExists, UnitName = origExists, origName
	end
	AURAS.player = { { spellId = 1, name = "Buff" } }
end)
for _, cmd in ipairs({ "lock", "unlock", "flash", "flash", "soon", "soon", "news", "app" }) do
	step("slash " .. cmd, SlashCmdList.RCROT, cmd)
end
step("final tick", ns.Tick)

local missing = {}
for k in pairs(MISSING) do missing[#missing + 1] = k end
table.sort(missing)
report.missing = table.concat(missing, " ")
report.flash = report.flash or 0
report.buffs = report.buffs or 0
report.list = ns.UsingBuiltInList and ns.UsingBuiltInList() and "built-in" or "other"
REPORT = report
"""


def run(cls, cid, no_secrets=False):
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.ADDON_DIR = ROOT
    g.TOC_FILE = "RCRotations_Camelot.toc"
    g.BUILD_TOC = 16001
    g.CLASS_FILE = cls
    g.CLASS_ID = cid
    g.NO_SECRETS_WANTED = no_secrets
    L.execute(open(os.path.join(ROOT, "tools", "forever_env.lua"), encoding="utf-8").read() + "\n" + RUN)
    r = g.REPORT
    roles = {str(k): int(v) for k, v in r.roles.items()}
    seen = g.BUFFS_SEEN
    buffs = [int(seen[i]) for i in range(1, len(seen) + 1)] if seen else []
    return roles, str(r.missing), str(r.list), int(r.flash), buffs


def main():
    failed = 0
    allmissing = set()
    for cls, cid in CLASSES:
        try:
            roles, missing, lst, flashes, buffs = run(cls, cid)
        except Exception as e:  # noqa: BLE001
            failed += 1
            print("FAIL %-8s %s" % (cls, str(e)[:600]))
            continue
        allmissing.update(missing.split())
        empty = [r for r, n in roles.items() if n == 0]
        status = "OK  " if not empty and flashes > 0 else "FAIL"
        if empty or flashes == 0:
            failed += 1
        print("%s %-8s list=%s  buffs reminded with none up: %s  action-bar flash in %d/%d roles  combat ticks with a suggestion: %s%s" % (
            status, cls, lst, buffs, flashes, len(roles), ", ".join("%s %d/40" % kv for kv in sorted(roles.items())),
            ("  (nothing suggested for: %s)" % ", ".join(empty)) if empty else ""))
    if allmissing:
        print("APIs the addon looked up that this test doesn't provide: " + " ".join(sorted(allmissing)))
    print("ALL PASS" if not failed else "%d FAILED" % failed)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
