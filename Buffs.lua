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
		{ spell = 20217, cats = { "stats" } }, -- Blessing of Kings
		{ spell = 19740, cats = { "mastery" }, needs = "stats" }, -- Blessing of Might, once stats are covered
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
		{ spell = 6673, cats = { "ap" } }, -- Battle Shout
		{ spell = 469, cats = { "stamina" }, needs = "ap" }, -- Commanding Shout, once attack power is covered
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

local function missing(entry)
	local kind = entry.kind or "aura"
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
	if auraUp(entry.spell) or anyUp(entry.alt) then
		return false
	end
	if entry.needs and not Buffs.CategoryUp(entry.needs) then
		-- e.g. Blessing of Might only after Kings/stats is covered
		return false
	end
	if entry.cats then
		for _, cat in ipairs(entry.cats) do
			if not Buffs.CategoryUp(cat) then
				return true
			end
		end
		return false
	end
	return true
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
	local out, seen = {}, {}
	for _, entry in ipairs(list) do
		if #out >= 4 then
			break
		end
		if forSpec(entry, spec) and (not entry.combat or inCombat) and known(entry.spell) and not seen[entry.spell] and missing(entry) then
			local id = ns.API.Resolve(entry.spell) or entry.spell
			out[#out + 1] = id
			seen[entry.spell] = true
		end
	end
	return out
end
