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
-- ...and every spell its bundled WoWSims Forever rotations use (in game, every
-- rank shares a name and the addon uses the rank you have)
local bundled = ns.SimData and ns.SimData.specs and ns.SimData.specs[CLASS_FILE]
for _, rot in ipairs(bundled and bundled[0] or {}) do
	for _, it in ipairs(rot.list or {}) do
		if it.id and not KNOWN[it.id] then
			KNOWN[it.id] = true
			if slot < 120 then slot = slot + 1; ACTION[slot] = it.id end
		end
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
local p1 = PLATES_LIST[1].UnitFrame
assert((p1.fromBool or 0) > 0, "secret hostility: Blizzard plate faded with SetAlphaFromBoolean")
local p3 = PLATES_LIST[3].unitFrame.Health
assert((p3.fromBool or 0) > 0, "secret hostility: ElvUI plate bar faded with SetAlphaFromBoolean")
SECRET_BOOLS, COMBAT = false, false
fire("PLAYER_REGEN_ENABLED")
update(0.6)
assert(PLATES_LIST[1].UnitFrame.alpha == 0, "out of combat: enemy plate hidden (bar, level, health text, icons)")
assert(CVARS.nameplateMaxDistance == "60", "names seen from further away (nameplateMaxDistance 60)")
do -- a mob someone else tagged: purple, not grey (grey reads as dead)
	local wasTap, wasSel = UnitIsTapDenied, UnitSelectionColor
	UnitIsTapDenied = function() return true end
	local r, g, b = ns.Plates.NameColor("nameplate1")
	assert(r == ns.Plates.TAPPED[1] and g == ns.Plates.TAPPED[2] and b == ns.Plates.TAPPED[3], "tagged mob: purple name")
	UnitIsTapDenied = function() return false end
	UnitSelectionColor = function() return 0.5, 0.5, 0.5 end -- the game's grey
	r, g, b = ns.Plates.NameColor("nameplate1")
	assert(r == ns.Plates.TAPPED[1], "tagged mob (game's grey): purple name")
	UnitSelectionColor = function() return 1, 0, 0 end
	r, g, b = ns.Plates.NameColor("nameplate1")
	assert(r == 1 and g == 0 and b == 0, "hostile mob: red name")
	UnitIsTapDenied, UnitSelectionColor = wasTap, wasSel
end
assert(PLATES_LIST[1].rcrName and PLATES_LIST[1].rcrName.shown, "out of combat: the enemy name still shows")
local eq = PLATES_LIST[3].unitFrame.QuestIcons
local elvName = PLATES_LIST[3].rcrName
assert(elvName, "ElvUI plate: our name")
assert(eq.Default.pts[1] and eq.Default.pts[1][2] == elvName and eq.Default.pts[1][1] == "LEFT", "ElvUI quest \"!\" icon right beside the name")
local softF = PLATES_LIST[3].unitFrame.SoftTargetFrame
assert(eq.Item.pts[1] and (eq.Item.pts[1][2] == elvName or eq.Item.pts[1][2] == softF) and eq.Item.pts[1][1] == "RIGHT", "ElvUI quest item icon on the left, beside the name")
local soft = PLATES_LIST[3].unitFrame.SoftTargetFrame
local last = soft.pts[#soft.pts]
assert(last and last[1] == "RIGHT" and (last[2] == elvName or last[2] == eq.Item), "loot marker (SoftTargetFrame) on the left beside the name")
assert(not ns.Plates.lastError, "no error laying out icons: " .. tostring(ns.Plates.lastError))
local qi = PLATES_LIST[1].UnitFrame.QuestIcon
assert(qi.pts[1] and qi.pts[1][2] == PLATES_LIST[1].rcrName and qi.pts[1][1] == "LEFT", "quest icon tucked in right beside the name")
-- the game anchors it back to the bar: it comes back beside the name
qi:SetPoint("LEFT", PLATES_LIST[1].UnitFrame.healthBar, "RIGHT", 4, 0)
assert(qi.pts[#qi.pts][2] == PLATES_LIST[1].rcrName, "quest icon stays beside the name when the game moves it")
-- the game resets the plate's alpha (range, target change): it stays hidden
PLATES_LIST[1].UnitFrame:SetAlpha(1)
assert(PLATES_LIST[1].UnitFrame.alpha == 0, "plate stays hidden when the game sets its alpha again")
do
	local was, wasPrint = C_NamePlate.GetNamePlateForUnit, ns.Print
	local lines = {}
	ns.Print = function(t) lines[#lines + 1] = tostring(t) end
	for _, i in ipairs({ 1, 3 }) do
		C_NamePlate.GetNamePlateForUnit = function() return PLATES_LIST[i] end
		step("platecheck", SlashCmdList.RCROT, "platecheck")
	end
	C_NamePlate.GetNamePlateForUnit, ns.Print = was, wasPrint
	PLATECHECK = table.concat(lines, "\n")
end
step("plates off", SlashCmdList.RCROT, "plates")
update(0.6)
assert(PLATES_LIST[1].UnitFrame.alpha == 1, "option off: plate back")
assert(CVARS.nameplateMaxDistance == "41", "option off: your own nameplate distance back")
assert(#qi.pts == 1 and qi.pts[1][2] == PLATES_LIST[1].UnitFrame.healthBar, "option off: quest icon back where the game put it")
assert(eq.Default.pts[1][2] == eq and eq.Item.pts[1][2] == eq, "option off: ElvUI quest icons back (centered on their frame when the anchor couldn't be read)")
-- range detector: yards to the target from in-range answers
step("range", function()
	local wasInfo, wasRange, wasHarm, wasCID = C_Spell.GetSpellInfo, C_Spell.IsSpellInRange, C_Spell.IsSpellHarmful, CheckInteractDistance
	local RANGES = { 5, 20, 30, 40 }
	local function rangeOf(id) return RANGES[id % 4 + 1] end
	C_Spell.GetSpellInfo = function(id)
		local i = wasInfo(id)
		if i then i.maxRange = rangeOf(id) end
		return i
	end
	C_Spell.IsSpellHarmful = function() return true end
	C_Spell.IsSpellInRange = function(id) return YARDS <= rangeOf(id) end
	CheckInteractDistance = function(_, i) return YARDS <= (i == 3 and 9 or i == 2 and 10 or 28) end
	ns.Range.Invalidate()
	for _, y in ipairs({ 3, 12, 22, 35, 70 }) do
		YARDS = y
		local lo, hi = ns.Range.Band("target")
		assert(lo, "range: no band at " .. y .. " yd")
		assert(lo <= y and (not hi or y <= hi), ("range: %d yd shown as %s"):format(y, tostring(ns.Range.Text(lo, hi))))
		RANGE_SEEN = (RANGE_SEEN or "") .. y .. "=" .. ns.Range.Text(lo, hi) .. " "
		local c = ns.Range.Color(lo, hi)
		local want = y <= 5 and "green" or y <= 40 and "yellow" or "red"
		local got = c[1] < 0.5 and "green" or c[2] > 0.5 and c[2] < 0.9 and "yellow" or c[2] < 0.5 and "red" or "white"
		assert(got == want, ("range: %d yd colored %s, wanted %s"):format(y, got, want))
	end
	-- yards above the enemy names
	YARDS = 22
	ns.Range.RefreshPlates()
	local fs = PLATES_LIST[1].rcrYards
	assert(fs and fs.shown, "range: yards above the enemy nameplate")
	assert(fs.pts[#fs.pts][2] == PLATES_LIST[1].rcrName or not (PLATES_LIST[1].rcrName and PLATES_LIST[1].rcrName.shown), "range: yards sit just above the enemy name")
	PLATE_YARDS = fs.text
	-- range-check items add checkpoints: a tighter range out of combat, none in combat
	local wasItem = C_Item
	C_Item = { IsItemInRange = function(id)
		for _, it in ipairs(ns.Range.HARM_ITEMS) do if it[1] == id then return YARDS <= it[2] end end
	end }
	YARDS = 22
	local lo, hi = ns.Range.Band("target")
	assert(lo == 20 and hi == 25, "range: items narrow 22 yd to 20-25, got " .. tostring(ns.Range.Text(lo, hi)))
	YARDS = 3.5
	lo, hi = ns.Range.Band("target")
	assert(lo == 3 and hi == 4, "range: items narrow 3.5 yd to 3-4, got " .. tostring(ns.Range.Text(lo, hi)))
	ITEM_YARDS = ns.Range.Text(lo, hi)
	COMBAT = true
	C_Item.IsItemInRange = function() error("item range check in combat") end
	YARDS = 22
	lo, hi = ns.Range.Band("target")
	assert(lo == 20 and hi == 28 or lo == 20 and hi == 30, "range: in combat, spells only: " .. tostring(ns.Range.Text(lo, hi)))
	COMBAT = false
	C_Item = wasItem
	-- in combat the game may hide the answers: no error, no made-up number
	C_Spell.IsSpellInRange = function() return secret(true) end
	CheckInteractDistance = function() return secret(true) end
	ns.Range.Invalidate()
	local lo = ns.Range.Band("target")
	assert(lo == nil, "range: hidden answers give no band")
	ns.Range.Refresh()
	assert(not ns.Range.label or not ns.Range.label.shown, "range: label hidden when unknown")
	C_Spell.IsSpellInRange = function(id) return YARDS <= rangeOf(id) end
	CheckInteractDistance = function(_, i) return YARDS <= (i == 3 and 9 or i == 2 and 10 or 28) end
	YARDS = 22
	ns.Range.Invalidate()
	ns.Range.Refresh()
	assert(ns.Range.label and ns.Range.label.shown, "range: label shows on the main icon")
	local was = ns.Print
	ns.Print = function() end
	SlashCmdList.RCROT("range")
	ns.Print = was
	C_Spell.GetSpellInfo, C_Spell.IsSpellInRange, C_Spell.IsSpellHarmful, CheckInteractDistance = wasInfo, wasRange, wasHarm, wasCID
	ns.Range.Invalidate()
end)
step("menu", ns.ToggleOptions)
step("refresh menu", ns.RefreshOptions or function() end)
step("what's new", ns.ShowWhatsNew)
step("copy link", ns.ShowCopyLink)
step("close menu", ns.ToggleOptions)
-- buff reminders (Forever list): checked out of combat, held through combat
step("buffs", function()
	COMBAT, AURAS_SECRET = false, false
	AURAS.player = {}
	local m = ns.Buffs.Missing()
	report.buffs = #m
	BUFFS_SEEN = {}
	for i, id in ipairs(m) do BUFFS_SEEN[i] = id end
	-- in combat (buffs hidden): the reminders from before the fight stay up
	COMBAT, AURAS_SECRET = true, true
	local during = ns.Buffs.Missing()
	if #during ~= #m then error("buff reminders went away in combat: " .. #m .. " before, " .. #during .. " during") end
	if #m > 0 then
		-- casting one clears it, even though the buff itself can't be seen
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-7", m[1])
		local after = ns.Buffs.Missing()
		if #after ~= #m - 1 then error("casting " .. m[1] .. " in combat didn't clear its reminder") end
		for _, id in ipairs(after) do if id == m[1] then error("reminder " .. id .. " stayed after casting it") end end
	end
	COMBAT, AURAS_SECRET = false, false
	AURAS.player = { { spellId = 1, name = "Buff" } }
	-- out of combat with buffs hidden (some maps): no new reminders appear
	local before = ns.Buffs.Missing()
	AURAS_SECRET = true
	local hiddenNow = ns.Buffs.Missing()
	assert(#hiddenNow == #before, "buffs hidden: the last reminders stay, nothing new appears")
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
		-- Blessing of Kings is a talent: not learned -> never suggested, even though
		-- the game answers a lookup by its name
		local kings = S.Paladin.BlessingKings
		local gsi, wasRole = C_Spell.GetSpellInfo, ns.db.role
		KNOWN[kings] = nil
		FUTURE[kings] = true -- greyed out in the spellbook
		-- ...and in the "Blessings" flyout next to Might, as on WoW Forever
		FLYOUT = { S.Paladin.BlessingMight, kings }
		C_Spell.GetSpellInfo = function(id)
			if id == "Blessing of Kings" then return { name = id, spellID = kings, iconID = 1 } end
			return gsi(id)
		end
		if ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
		ns.API.RebuildSpellBookIndex(true) -- the spellbook has been read
		ns.db.role = "damage"
		AURAS.player = {}
		local m2 = ns.Buffs.Missing()
		C_Spell.GetSpellInfo = gsi
		do -- /rcr spellcheck prints every answer, no errors
			local lines, wasPrint = {}, ns.Print
			ns.Print = function(t) lines[#lines + 1] = tostring(t) end
			step("spellcheck", SlashCmdList.RCROT, "spellcheck Blessing of Kings")
			ns.Print = wasPrint
			assert(#lines >= 5 and lines[#lines]:find("not known"), "spellcheck: " .. table.concat(lines, " / "))
			SPELLCHECK = table.concat(lines, "\n")
		end
		KNOWN[kings], FUTURE[kings], FLYOUT = true, nil, {}
		ns.API.RebuildSpellBookIndex(true)
		if ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
		ns.db.role = wasRole
		assert(not has(m2, kings), "Blessing of Kings suggested without the talent")
		assert(has(m2, S.Paladin.BlessingMight), "Blessing of Might suggested instead")
		AURAS.player = { { spellId = 1, name = "Buff" } }
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
-- Auto rotation: the starter below level 20, then the WoWSims Forever build
-- closest to your talents (for your playstyle); healing uses the built-in list
do
	local Sim = ns.Sim
	local list, token = Sim.Rotations()
	assert(list and #list >= 2, "Forever: bundled rotations for " .. CLASS_FILE)
	assert(list[1].starter, "the starter comes first")
	local roleWas, lvl, tabs = ns.db.role, UnitLevel, GetTalentTabInfo
	local level, pts = 10, { 0, 0, 0 }
	UnitLevel = function() return level end
	GetNumTalentTabs = function() return 3 end
	GetTalentTabInfo = function(i) return "Tree" .. i, nil, pts[i] end
	local function pick() Sim.InvalidateTalents() return Sim.AutoPick(list, token) end
	ns.db.simPick = nil
	assert(Sim.IsAuto(token, 0), "Auto is the default")
	ns.db.role = roles[1]
	assert(pick() == list[1], "level 10: the starter")
	-- Paladin: a seal that's already up (cast before the addon loaded) isn't asked for again
	if CLASS_FILE == "PALADIN" then
		local SOR = 20287 -- Seal of Righteousness rank 2: same name as rank 1
		TARGET, COMBAT, AURAS_SECRET = true, false, false
		AURAS.player = { { spellId = SOR, name = "Seal of Righteousness" } }
		NOW = NOW + 1
		local q = ns.BuildQueue()
		assert(q[1] ~= 21084 and q[1] ~= SOR, "seal already up (out of combat): not asked for again (got " .. tostring(q[1]) .. ")")
		COMBAT = true -- buffs hidden now
		NOW = NOW + 1
		q = ns.BuildQueue()
		assert(q[1] ~= 21084 and q[1] ~= SOR, "seal already up (in combat, hidden): not asked for again (got " .. tostring(q[1]) .. ")")
		COMBAT = false
		AURAS.player = { { spellId = 1, name = "Buff" } }
		NOW = NOW + 1
		q = ns.BuildQueue()
		assert(q[1] == 21084, "no seal: asks for Seal of Righteousness (got " .. tostring(q[1]) .. ")")
		-- in combat with no auras given at all: the seal you just cast counts
		for _, mode in ipairs({ "hidden", "none" }) do
			COMBAT, AURAS_SECRET, AURAS_NONE = true, mode == "hidden", mode == "none"
			NOW = NOW + 1
			fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-seal-" .. mode, 21084)
			for _ = 1, 3 do
				NOW = NOW + 1.5
				q = ns.BuildQueue()
				assert(q[1] ~= 21084 and q[1] ~= SOR, "in combat (" .. mode .. " buffs): Seal of Righteousness asked for again right after casting it")
			end
		end
		COMBAT, AURAS_SECRET, AURAS_NONE = false, false, false
	end
	-- the starter suggests a spell in a fight
	TARGET, COMBAT = true, true
	fire("PLAYER_TARGET_CHANGED")
	NOW = NOW + 20
	local sq = ns.BuildQueue()
	assert(sq[1] and sq[1] ~= 6603, "level 10 starter: suggests a spell (got " .. tostring(sq[1]) .. ")")
	report.starter = sq[1]
	-- a DoT you just cast isn't suggested again while debuffs are hidden
	if CLASS_FILE == "WARLOCK" then
		for _, mode in ipairs({ "hidden", "none" }) do
			AURAS_SECRET, AURAS_NONE = mode == "hidden", mode == "none"
			NOW = NOW + 30
			local first = ns.BuildQueue()[1]
			fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-dot-" .. mode, first)
			NOW = NOW + 1.6
			local again = ns.BuildQueue()[1]
			assert(first and again ~= first, mode .. " debuffs: " .. tostring(first) .. " suggested again right after casting it")
		end
		AURAS_SECRET, AURAS_NONE = false, false
	end
	level = 60
	local defaultRole = ({ DRUID = "hybrid", HUNTER = "range", SHAMAN = "caster" })[CLASS_FILE] or "damage"
	local checked = 0
	for _, rot in ipairs(list) do
		if not rot.starter and rot.talents then
			ns.db.role = (rot.role == "damage") and defaultRole or rot.role
			pts = { rot.talents[1], rot.talents[2], rot.talents[3] }
			local got = pick()
			assert(got, "level 60 " .. rot.name .. ": something picked")
			local same = got == rot or (got.talents and got.talents[1] == pts[1] and got.talents[2] == pts[2] and got.talents[3] == pts[3])
			assert(same, ("level 60 with %s talents (%d/%d/%d): picked %s"):format(rot.name, pts[1], pts[2], pts[3], tostring(got.name)))
			checked = checked + 1
		end
	end
	-- healing: no WoWSims healer rotation, the built-in heal list stays
	local hasHeal = false
	for _, r in ipairs(roles) do if r == "heal" then hasHeal = true end end
	if hasHeal then
		ns.db.role = "heal"
		assert(pick() == nil, "heal playstyle: built-in list")
	end
	-- Paladin playstyles name a build
	if CLASS_FILE == "PALADIN" then
		pts = { 0, 0, 0 }
		ns.db.role = "twist"
		assert(pick().style == "twist", "Seal Twist playstyle: the Unsealed Wrath build")
		ns.db.role = "shockadin"
		assert(pick().style == "shockadin", "Shockadin playstyle: the Holy Shock build")
	end
	-- picker: Auto first; /rcr apl cycles Auto -> each rotation -> Auto
	ns.db.role = roles[1]
	step("picker", Sim.ShowPicker, true)
	local seenAuto = false
	for _ = 1, #list + 1 do
		local _, _, isAuto = Sim.Cycle()
		if isAuto then seenAuto = true end
	end
	assert(seenAuto and Sim.IsAuto(token, 0), "cycling comes back to Auto")
	UnitLevel, GetTalentTabInfo = lvl, tabs
	Sim.InvalidateTalents()
	ns.db.role = roleWas
	report.auto = checked
end
-- several enemies in a fight: the enemy count and the auto AoE switch, also
-- with hostility, combat state and range hidden (WoW Forever in combat)
do
	TARGET, COMBAT = true, true
	ns.db.combatMode, ns.db.autoEnemies = "auto", 3
	local cid = CheckInteractDistance
	for _, hide in ipairs({ false, true }) do
		SECRET_BOOLS = hide
		CheckInteractDistance = function() return nil end -- not allowed in combat
		NOW = NOW + 1
		local n, n8 = ns.API.EnemyCount(), ns.API.EnemyCount(8)
		NOW = NOW + 1
		local mode = ns.ResolveCombatMode()
		CheckInteractDistance = cid
		local what = hide and "hidden values" or "readable values"
		if n ~= 3 or n8 ~= 3 then error("3 enemies in a fight (" .. what .. "): counted " .. tostring(n) .. " / " .. tostring(n8) .. " within 8 yd") end
		if mode ~= "aoe" then error("3 enemies (" .. what .. "): auto mode should switch to AoE, got " .. tostring(mode)) end
	end
	SECRET_BOOLS = false
	ns.db.combatMode, ns.db.autoEnemies = nil, nil
	report.aoe = "ok"
end
-- Paladin playstyles from WoW Forever: Seal Twist and Shockadin
if CLASS_FILE == "PALADIN" then
	local P = ns.Spell.Paladin
	local have = {}
	for _, r in ipairs(roles) do have[r] = true end
	assert(have.twist and have.shockadin, "Paladin has the Seal Twist and Shockadin playstyles")
	TARGET, COMBAT = true, true
	ns.db.role = "twist"
	if ns.InvalidateAPLCache then ns.InvalidateAPLCache() end
	NOW = NOW + 10
	-- Unsealed Wrath rhythm: 3 swings on Command, 1 on Righteousness
	ns.API.NoteSpellCast(P.SealCommand)
	assert(not ns.API.TwistReady(P.SealRighteousness), "twist: no swap before any swing")
	assert(not ns.API.TwistReady(P.SealCommand), "twist: never 'swap' to the seal you already have")
	NOW = NOW + 2.5 -- 1 swing (2.4 sec weapon)
	assert(not ns.API.TwistReady(P.SealRighteousness), "twist: 1 Command echo is not enough")
	assert(ns.API.EchoStacks(1311703) >= 1, "Echo of Command stacks counted from swings")
	NOW = NOW + 5 -- 3 swings
	assert(ns.API.EchoStacks(1311703) == 3, "Echo of Command: 3 stacks after 3 swings")
	assert(ns.API.TwistReady(P.SealRighteousness), "twist: after 3 swings on Command, swap to Righteousness")
	ns.API.NoteSpellCast(P.SealRighteousness)
	assert(ns.API.EchoStacks(1311703) == 0, "swapping seals spends the Command echoes")
	assert(not ns.API.TwistReady(P.SealCommand), "twist: Righteousness needs 1 swing first")
	NOW = NOW + 2.5
	assert(ns.API.TwistReady(P.SealCommand), "twist: after 1 swing on Righteousness, back to Command")
	-- auto-pick: Unsealed Wrath known -> Seal Twist
	KNOWN[1310735] = true
	local autoWas0 = ns.db.roleAuto
	ns.db.roleAuto = nil
	ns.db.role, ns.db.shockAuto, ns.API.shockCheckAt = "damage", nil, 0
	ns.SyncAutoRole()
	assert(ns.db.role == "twist", "damage Paladin with Unsealed Wrath switched to Seal Twist")
	KNOWN[1310735] = nil
	if ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
	ns.db.roleAuto = autoWas0
	ns.db.role = "twist"
	local seen = {}
	for _ = 1, 4 do
		local q = ns.BuildQueue()
		if q[1] then seen[q[1]] = true end
	end
	NOW = NOW + 1
	ns.db.role = "shockadin"
	if ns.InvalidateAPLCache then ns.InvalidateAPLCache() end
	local q = ns.BuildQueue()
	assert(q[1], "shockadin: suggests something in a fight")
	-- Holy Shock known: a damage Paladin becomes a Shockadin once
	local autoWas = ns.db.roleAuto
	ns.db.roleAuto = nil
	ns.db.role, ns.db.shockAuto, ns.API.shockCheckAt = "damage", nil, 0
	ns.SyncAutoRole()
	assert(ns.db.role == "shockadin", "damage Paladin with Holy Shock switched to Shockadin")
	ns.db.role = "damage"
	ns.API.shockCheckAt = 0
	ns.SyncAutoRole()
	assert(ns.db.role == "damage", "only once: picking Damage again sticks")
	ns.db.roleAuto = autoWas
	ns.db.role = roles[1]
	if ns.InvalidateAPLCache then ns.InvalidateAPLCache() end
	report.paladin = "twist+shockadin"

	-- a WoWSims Forever Retribution export (seal twisting with Unsealed Wrath)
	-- imported as-is: it must run the whole rotation, not only Auto Attack
	for id in RET_EXPORT:gmatch('"spellId":(%d+)') do KNOWN[tonumber(id)] = true end
	if ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
	local okI, msgI = ns.Sim.ImportText(RET_EXPORT, "Forever Ret")
	assert(okI, "WoWSims Forever export imports: " .. tostring(msgI))
	local castsI = tonumber(tostring(msgI):match("(%d+) spells"))
	assert(castsI and castsI >= 7, "WoWSims Forever export: most of it converts (" .. tostring(msgI) .. ")")
	local usable = C_Spell.IsSpellUsable
	C_Spell.IsSpellUsable = function(id) if id == 24239 or id == 24274 or id == 24275 then return false, false end return usable(id) end
	TARGET, COMBAT, AURAS_SECRET = true, true, true
	fire("PLAYER_TARGET_CHANGED")
	NOW = NOW + 30
	local got, order = {}, {}
	for t = 1, 60 do
		NOW = NOW + 0.5
		local q = ns.BuildQueue()
		local id = q[1]
		if id and id ~= 6603 then
			got[id] = (got[id] or 0) + 1
			if t % 2 == 0 then
				order[#order + 1] = id
				fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. t, id)
			end
		end
	end
	C_Spell.IsSpellUsable = usable
	AURAS_SECRET = false
	assert(order[1] == 20920, "imported rotation: starts by asking for Seal of Command (got " .. tostring(order[1]) .. ")")
	for _, need in ipairs({ { 20271, "Judgement" }, { 10333, "Holy Strike" }, { 20293, "twist to Seal of Righteousness" }, { 20924, "Consecration" } }) do
		assert(got[need[1]], "imported rotation suggests " .. need[2])
	end
	assert(not got[24239], "Hammer of Wrath only below 20% health")
	-- the twist: Righteousness only ever after Command, Command again after it
	local swaps = 0
	for i = 2, #order do
		if order[i] == 20293 then swaps = swaps + 1 end
	end
	assert(swaps >= 2, "imported rotation keeps twisting (" .. swaps .. " swaps to Righteousness)")
	ns.Sim.RemoveImport("PALADIN", ns.Sim.Spec(), "import/forever_ret")
	if ns.InvalidateTick then ns.InvalidateTick() end
end
-- nothing to press (a low level character): melee classes get Auto Attack
do
	local saved = KNOWN
	KNOWN = {}
	if ns.API and ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
	ns.db.role = roles[1]
	TARGET, COMBAT = true, true
	fire("PLAYER_TARGET_CHANGED")
	local q = ns.BuildQueue()
	local melee = ns.CLASS_DAMAGE_ICON[CLASS_FILE] == "melee"
	-- the melee play style of a caster/ranged class counts too
	for _, r in ipairs(roles) do
		if r == "melee" then ns.db.role = r; melee = true end
	end
	if ns.InvalidateTick then ns.InvalidateTick() end
	if ns.InvalidateAPLCache then ns.InvalidateAPLCache() end
	q = ns.BuildQueue()
	if melee then
		if q[1] ~= 6603 then error("nothing to press: expected Auto Attack, got " .. tostring(q[1])) end
		if q.soon and q.soon[6603] then error("Auto Attack should flash when not swinging yet") end
		local was = C_Spell.IsCurrentSpell
		C_Spell.IsCurrentSpell = function(id) return id == 6603 end
		q = ns.BuildQueue()
		C_Spell.IsCurrentSpell = was
		if q[1] ~= 6603 or not (q.soon and q.soon[6603]) then error("Auto Attack must not flash while already swinging") end
		ns.db.autoAttack = false
		q = ns.BuildQueue()
		ns.db.autoAttack = nil
		if q[1] == 6603 then error("Auto Attack shown though turned off") end
	elseif q[1] == 6603 then
		error("Auto Attack suggested for a " .. CLASS_FILE)
	end
	TARGET = false
	q = ns.BuildQueue()
	if q[1] == 6603 then error("Auto Attack suggested with no target") end
	report.auto = melee and "auto attack" or "-"
	KNOWN = saved
	if ns.API and ns.API.InvalidateSpells then pcall(ns.API.InvalidateSpells, true) end
end
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
    g.RET_EXPORT = open(os.path.join(ROOT, "tools", "fixtures", "forever_ret_twist.json"), encoding="utf-8").read()
    L.execute(open(os.path.join(ROOT, "tools", "forever_env.lua"), encoding="utf-8").read() + "\n" + RUN)
    r = g.REPORT
    if cls == "WARRIOR":
        print("  range:", g.RANGE_SEEN, "| plate:", g.PLATE_YARDS, "| items 3.5:", g.ITEM_YARDS)
    if cls == "WARRIOR" and os.environ.get("SHOW_PLATECHECK"):
        print(g.PLATECHECK)
    if cls == "PALADIN" and os.environ.get("SHOW_PLATECHECK"):
        print(g.SPELLCHECK)
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
