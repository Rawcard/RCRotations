-- Missing buff reminders (MoP Classic).
--
-- Shows the buffs you should have up (your raid buff, armor, seal, presence,
-- stance, poisons, weapon imbues, shield, pet) as a row of icons above the
-- main HUD icon, and flashes their action buttons bright red. A reminder goes
-- away as soon as you have the buff, or an equivalent one from anyone else:
-- Mark of the Wild, Blessing of Kings and Legacy of the Emperor all count as
-- the 5% stats buff, and so on.
local addonName, ns = ...
local Buffs = {}
ns.Buffs = Buffs

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
	if ok then
		return a, b, c, d, e, f, g, h
	end
	return nil
end

-- Raid buff categories. In MoP the game itself reports which of these are
-- covered (GetRaidBuffTrayAuraInfo, the buff tray by the minimap), whoever
-- provides them. The aura lists are the fallback when that isn't available.
local CATEGORY = { stats = 1, stamina = 2, ap = 3, haste = 4, sp = 5, spellhaste = 6, crit = 7, mastery = 8 }
local EQUIVALENT = {
	stats = { 1126, 20217, 115921, 90363 }, -- Mark of the Wild, Blessing of Kings, Legacy of the Emperor, Embrace of the Shale Spider
	stamina = { 21562, 469, 6307, 90364 }, -- Power Word: Fortitude, Commanding Shout, Blood Pact, Qiraji Fortitude
	ap = { 57330, 6673, 19506 }, -- Horn of Winter, Battle Shout, Trueshot Aura
	sp = { 1459, 61316, 109773, 126309 }, -- Arcane / Dalaran Brilliance, Dark Intent, Still Water
	crit = { 17007, 24932, 1459, 61316, 116781, 24604, 90309, 126373, 126309 }, -- Leader of the Pack, Brilliance, Legacy of the White Tiger, pets
	mastery = { 19740, 116956, 93435, 128997 }, -- Blessing of Might, Grace of Air, Roar of Courage, Spirit Beast Blessing
}
Buffs.EQUIVALENT = EQUIVALENT

-- What each class keeps up. Fields:
--   spell   the spell to cast (shown and flashed)
--   alt     other spells that count as "this buff is up" (any one of them)
--   cats    raid buff categories it provides: only missing while one of them
--           isn't covered by anyone
--   specs   only for these specs (nil = all)
--   kind    "aura" (default), "stance" (seal/presence/stance/form), "pet",
--           "imbue" (shaman weapon enchant: "main" or "off")
--   combat  only remind in combat (forms you leave on purpose)
--   choose  kind "choice": you can only keep ONE of these up (a paladin's own
--           blessing, a warrior's own shout). Only one is ever shown: the
--           first whose buff nobody else covers. Yours doesn't count toward
--           "covered", so with Kings up and a druid's Mark of the Wild there,
--           it tells you to switch to Might.
local CLASS = {
	DEATHKNIGHT = {
		{ spell = 48263, kind = "stance", specs = { 1 } }, -- Blood Presence
		{ spell = 48266, kind = "stance", specs = { 2 } }, -- Frost Presence
		{ spell = 48265, kind = "stance", specs = { 3 } }, -- Unholy Presence
		{ spell = 57330, cats = { "ap" } }, -- Horn of Winter
		{ spell = 46584, kind = "pet", specs = { 3 } }, -- Raise Dead (ghoul)
	},
	DRUID = {
		{ spell = 1126, cats = { "stats" } }, -- Mark of the Wild
		{ spell = 24858, kind = "stance", specs = { 1 }, combat = true }, -- Moonkin Form
	},
	HUNTER = {
		{ spell = 13165, alt = { 109260 } }, -- Aspect of the Hawk / Iron Hawk
		{ spell = 883, kind = "pet" }, -- Call Pet 1
	},
	MAGE = {
		{ spell = 1459, alt = { 61316 }, cats = { "sp", "crit" } }, -- Arcane / Dalaran Brilliance
		{ spell = 6117, alt = { 30482, 7302 }, specs = { 1 } }, -- Mage Armor (Arcane)
		{ spell = 30482, alt = { 6117, 7302 }, specs = { 2 } }, -- Molten Armor (Fire)
		{ spell = 7302, alt = { 6117, 30482 }, specs = { 3 } }, -- Frost Armor (Frost)
	},
	MONK = {
		{ spell = 115921, cats = { "stats" } }, -- Legacy of the Emperor
		{ spell = 116781, cats = { "crit" }, specs = { 3 } }, -- Legacy of the White Tiger
		{ spell = 115069, kind = "stance", specs = { 1 } }, -- Stance of the Sturdy Ox
		{ spell = 115070, kind = "stance", specs = { 2 } }, -- Stance of the Wise Serpent
		{ spell = 103985, kind = "stance", specs = { 3 } }, -- Stance of the Fierce Tiger
	},
	PALADIN = {
		{ spell = 20165, kind = "seal", specs = { 1 } }, -- Seal of Insight (Holy)
		{ spell = 31801, kind = "seal", specs = { 2, 3 } }, -- Seal of Truth (Prot, Ret)
		-- one blessing per paladin: Kings, or Might when someone else covers stats
		{ kind = "choice", spell = 20217, choose = { { spell = 20217, cats = { "stats" } }, { spell = 19740, cats = { "mastery" } } } },
		{ spell = 25780, specs = { 2 } }, -- Righteous Fury
	},
	PRIEST = {
		{ spell = 21562, cats = { "stamina" } }, -- Power Word: Fortitude
		{ spell = 588, alt = { 73413 } }, -- Inner Fire / Inner Will
		{ spell = 15473, kind = "stance", specs = { 3 } }, -- Shadowform
	},
	ROGUE = {
		{ spell = 2823, alt = { 8679 } }, -- Deadly Poison / Wound Poison
		{ spell = 3408, alt = { 5761, 108211, 108215 } }, -- Crippling / Mind-numbing / Leeching / Paralytic
	},
	SHAMAN = {
		{ spell = 324, specs = { 1, 2 } }, -- Lightning Shield
		{ spell = 52127, specs = { 3 } }, -- Water Shield
		{ spell = 8024, kind = "imbue", hand = "main", specs = { 1 } }, -- Flametongue Weapon
		{ spell = 8232, kind = "imbue", hand = "main", specs = { 2 } }, -- Windfury Weapon
		{ spell = 8024, kind = "imbue", hand = "off", specs = { 2 } }, -- Flametongue Weapon (off hand)
		{ spell = 51730, kind = "imbue", hand = "main", specs = { 3 } }, -- Earthliving Weapon
	},
	WARLOCK = {
		{ spell = 109773, cats = { "sp" } }, -- Dark Intent
		{ spell = 691, kind = "pet", specs = { 1 } }, -- Summon Felhunter
		{ spell = 30146, kind = "pet", specs = { 2 } }, -- Summon Felguard
		{ spell = 688, kind = "pet", specs = { 3 } }, -- Summon Imp
	},
	WARRIOR = {
		-- one shout per warrior: Battle Shout, or Commanding when someone else covers attack power
		{ kind = "choice", spell = 6673, choose = { { spell = 6673, cats = { "ap" } }, { spell = 469, cats = { "stamina" } } } },
	},
}
Buffs.CLASS = CLASS

local GRIMOIRE_OF_SACRIFICE = 108503

-- ------------------------------------------------------------------ checks
local function auraUp(id)
	if ns.Sim and ns.Sim.AuraUp then
		return ns.Sim.AuraUp(id, "player")
	end
	return false
end

local function anyUp(list)
	for _, id in ipairs(list or {}) do
		if auraUp(id) then
			return true
		end
	end
	return false
end

-- Is this raid buff category covered, by anyone?
local trayCache
function Buffs.CategoryUp(cat)
	local index = CATEGORY[cat]
	if index and GetRaidBuffTrayAuraInfo then
		trayCache = trayCache or {}
		if trayCache[cat] == nil then
			trayCache[cat] = call(GetRaidBuffTrayAuraInfo, index) ~= nil
		end
		if trayCache[cat] then
			return true
		end
	end
	return anyUp(EQUIVALENT[cat])
end

local function known(id)
	return ns.API and ns.API.Resolve and ns.API.Resolve(id) ~= nil
end

local function forSpec(entry, spec)
	if not entry.specs then
		return true
	end
	for _, s in ipairs(entry.specs) do
		if s == spec then
			return true
		end
	end
	return false
end

local function stanceUp(id)
	local slots = ns.Sim and ns.Sim.StanceSlots and ns.Sim.StanceSlots()
	if slots and slots.active then
		return slots.active == id or (ns.API.Resolve and slots.active == ns.API.Resolve(id))
	end
	-- Some forms (Shadowform, Moonkin) also show as an aura.
	return auraUp(id)
end

local function anySeal()
	local slots = ns.Sim and ns.Sim.StanceSlots and ns.Sim.StanceSlots()
	return slots and (slots.index or 0) > 0
end

local function imbueUp(hand)
	local hasMain, _, _, _, hasOff = call(GetWeaponEnchantInfo)
	if hand == "off" then
		-- no off-hand weapon: nothing to remind
		if GetInventoryItemID and not call(GetInventoryItemID, "player", 17) then
			return true
		end
		return hasOff and true or false
	end
	return hasMain and true or false
end

local function petUp()
	return (call(UnitExists, "pet") and not call(UnitIsDead, "pet")) and true or false
end

-- ------------------------------------------------------------------ group
-- In a party or raid, your raid buff also has to be on everyone near you.
-- Members who are out of range, offline, dead or out of sight don't count
-- (you couldn't buff them anyway). A member counts as covered when they have
-- your buff or the same kind of buff from anyone. Checked about once a second.
local GROUP_EVERY = 1
local groupAt, groupCache = 0, {}
Buffs.who = {}

local function groupUnits()
	local out = {}
	if call(IsInRaid) then
		for i = 1, (call(GetNumGroupMembers) or 0) do
			out[#out + 1] = "raid" .. i
		end
	elseif call(IsInGroup) then
		for i = 1, (call(GetNumSubgroupMembers) or 0) do
			out[#out + 1] = "party" .. i
		end
	end
	return out
end

local function reachable(unit)
	if not call(UnitExists, unit) or call(UnitIsUnit, unit, "player") then
		return false
	end
	if call(UnitIsConnected, unit) == false or call(UnitIsDeadOrGhost, unit) then
		return false
	end
	if UnitIsVisible and not call(UnitIsVisible, unit) then
		return false
	end
	if UnitInRange then
		local inRange, checked = call(UnitInRange, unit)
		if checked and not inRange then
			return false
		end
	end
	return true
end

local function unitHasAny(unit, list)
	if not (ns.Sim and ns.Sim.AuraUp) then
		return true
	end
	for _, id in ipairs(list or {}) do
		if ns.Sim.AuraUp(id, unit) then
			return true
		end
	end
	return false
end

local function memberCovered(unit, entry)
	if unitHasAny(unit, { entry.spell }) or unitHasAny(unit, entry.alt) then
		return true
	end
	for _, cat in ipairs(entry.cats) do
		if not unitHasAny(unit, EQUIVALENT[cat]) then
			return false
		end
	end
	return true
end

-- The first group member near you who lacks this buff (name), or nil.
local function groupMissing(entry)
	local key = entry.spell
	if groupCache[key] ~= nil then
		return groupCache[key] or nil
	end
	local who = false
	for _, unit in ipairs(groupUnits()) do
		if reachable(unit) and not memberCovered(unit, entry) then
			who = call(UnitName, unit) or unit
			break
		end
	end
	groupCache[key] = who
	return who or nil
end

local function myAura(id, unit)
	return ns.Sim and ns.Sim.MyAuraUp and ns.Sim.MyAuraUp(id, unit or "player") or false
end

-- Is this category covered on you by someone else's buff? Your own buff from
-- the choice set doesn't count.
local function othersCover(cat, entry)
	local anyMine = false
	for _, opt in ipairs(entry.choose) do
		if myAura(opt.spell) then
			anyMine = true
		end
	end
	-- the game's buff tray says it's covered and none of it is yours
	if not anyMine and CATEGORY[cat] and GetRaidBuffTrayAuraInfo and call(GetRaidBuffTrayAuraInfo, CATEGORY[cat]) ~= nil then
		return true
	end
	for _, id in ipairs(EQUIVALENT[cat] or {}) do
		if auraUp(id) then
			local yours = false
			for _, opt in ipairs(entry.choose) do
				if opt.spell == id and myAura(id) then
					yours = true
				end
			end
			if not yours then
				return true
			end
		end
	end
	return false
end

-- The one option from a choice set you should keep up (nil = all covered).
local function pickChoice(entry)
	for _, opt in ipairs(entry.choose) do
		if known(opt.spell) then
			local needed = false
			for _, cat in ipairs(opt.cats) do
				if not othersCover(cat, entry) then
					needed = true
				end
			end
			if needed then
				return opt
			end
		end
	end
	return nil
end

local function missingChoice(entry)
	local opt = pickChoice(entry)
	if not opt then
		return false
	end
	if not myAura(opt.spell) then
		return true, nil, opt.spell
	end
	if ns.db and ns.db.buffGroup ~= false then
		local who = groupMissing({ spell = opt.spell, cats = opt.cats })
		if who then
			return true, who, opt.spell
		end
	end
	return false
end

local function missing(entry)
	local kind = entry.kind or "aura"
	if kind == "choice" then
		return missingChoice(entry)
	end
	if kind == "stance" then
		return not stanceUp(entry.spell)
	elseif kind == "seal" then
		return not anySeal()
	elseif kind == "pet" then
		if petUp() then
			return false
		end
		if ns.CLASSTOKEN == "WARLOCK" and auraUp(GRIMOIRE_OF_SACRIFICE) then
			return false
		end
		return true
	elseif kind == "imbue" then
		return not imbueUp(entry.hand)
	end
	if entry.needs and not Buffs.CategoryUp(entry.needs) then
		-- e.g. Blessing of Might only after Kings/stats is covered
		return false
	end
	local selfHas = auraUp(entry.spell) or anyUp(entry.alt)
	if not selfHas then
		if not entry.cats then
			return true
		end
		for _, cat in ipairs(entry.cats) do
			if not Buffs.CategoryUp(cat) then
				return true
			end
		end
	end
	-- raid buffs: someone near you in the group still needs it
	if entry.cats and ns.db and ns.db.buffGroup ~= false then
		local who = groupMissing(entry)
		if who then
			return true, who
		end
	end
	return false
end

-- Should reminders show at all right now?
local function active()
	if ns.GAME ~= "mists" then
		return false
	end
	if ns.db and ns.db.showBuffs == false then
		return false
	end
	if call(UnitIsDeadOrGhost, "player") then
		return false
	end
	if call(UnitInVehicle, "player") or call(UnitOnTaxi, "player") or call(IsMounted) then
		return false
	end
	return true
end

-- The spells to remind about, most important first (at most 4).
function Buffs.Missing()
	trayCache = nil
	if not active() then
		return {}
	end
	local token = ns.ClassToken and ns.ClassToken()
	ns.CLASSTOKEN = token
	local list = CLASS[token]
	if not list then
		return {}
	end
	local spec = ns.Sim and ns.Sim.Spec and ns.Sim.Spec() or 0
	local inCombat = call(UnitAffectingCombat, "player")
	if ns.Sim and ns.Sim.BeginPass then
		ns.Sim.BeginPass() -- fresh aura scan
	end
	local t = call(GetTime) or 0
	if t - groupAt >= GROUP_EVERY or t < groupAt then
		groupAt = t
		for k in pairs(groupCache) do
			groupCache[k] = nil
		end
	end
	local out, seen, who = {}, {}, {}
	for _, entry in ipairs(list) do
		if #out >= 4 then
			break
		end
		if forSpec(entry, spec) and (not entry.combat or inCombat) and (entry.choose or known(entry.spell)) and not seen[entry.spell] then
			local miss, name, pick = missing(entry)
			if miss then
				local id = ns.API.Resolve(pick or entry.spell) or pick or entry.spell
				out[#out + 1] = id
				who[id] = name
				seen[entry.spell] = true
			end
		end
	end
	Buffs.who = who
	return out
end
