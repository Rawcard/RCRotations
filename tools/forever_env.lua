-- WoW Forever environment for tools/test_forever.py: the addon's real files on
-- the camelot client, with the retail-style API Forever uses and secret values
-- in combat. Base widget stubs are permissive (any unknown widget method is a
-- no-op), game APIs are not: a removed API is simply missing.
-- Globals provided by the runner: ADDON_DIR, TOC_FILE, BUILD_TOC, CLASS_FILE, CLASS_ID
local unpack = unpack or table.unpack

local function perm(name)
	local o = { __name = name, shown = false, scripts = {}, hooks = {}, level = 1, w = 36, h = 36, scale = 1, pts = {} }
	local function fire(s, e, ...)
		if s.scripts[e] then s.scripts[e](s, ...) end
		for _, fn in ipairs(s.hooks[e] or {}) do fn(s, ...) end
	end
	local known = {
		Show = function(s) local was = s.shown; s.shown = true; if not was then fire(s, "OnShow") end end,
		Hide = function(s) local was = s.shown; s.shown = false; if was then fire(s, "OnHide") end end,
		SetScale = function(s, v) s.scale = v end,
		ClearAllPoints = function(s) s.pts = {} end,
		SetPoint = function(s, ...) s.pts[#s.pts + 1] = { ... } end,
		IsShown = function(s) return s.shown end,
		IsVisible = function(s) return s.shown end,
		SetShown = function(s, v) s.shown = v and true or false end,
		GetWidth = function(s) return s.w end,
		GetHeight = function(s) return s.h end,
		GetSize = function(s) return s.w, s.h end,
		SetWidth = function(s, v) s.w = v end,
		SetHeight = function(s, v) s.h = v end,
		SetSize = function(s, w, h) s.w, s.h = w, h end,
		GetFrameLevel = function(s) return s.level end,
		SetFrameLevel = function(s, v) s.level = v end,
		GetScale = function(s) return s.scale end,
		GetEffectiveScale = function() return 1 end,
		GetName = function(s) return s.__gname end,
		GetParent = function() return UIParent end,
		GetScript = function(s, e) return s.scripts[e] end,
		SetScript = function(s, e, f) s.scripts[e] = f end,
		HookScript = function(s, e, fn) s.hooks[e] = s.hooks[e] or {}; table.insert(s.hooks[e], fn) end,
		GetText = function(s) return s.text or "" end,
		SetText = function(s, t) s.text = t end,
		GetStringWidth = function() return 50 end,
		GetStringHeight = function() return 12 end,
		GetNumPoints = function() return 0 end,
		GetPoint = function() return "CENTER", UIParent, "CENTER", 0, 0 end,
		GetCenter = function() return 500, 400 end,
		GetLeft = function() return 100 end,
		GetTop = function() return 500 end,
		GetRight = function() return 300 end,
		GetBottom = function() return 100 end,
		GetAttribute = function() return nil end,
		GetChildren = function() return end,
		GetRegions = function() return end,
		IsMouseOver = function() return false end,
		GetChecked = function(s) return s.checked end,
		SetChecked = function(s, v) s.checked = v end,
		GetValue = function(s) return s.value or 0 end,
		SetValue = function(s, v) s.value = v end,
		GetMinMaxValues = function() return 0, 100 end,
		GetTexture = function(s) return s.tex end,
		SetTexture = function(s, t) s.tex = t end,
		GetVerticalScroll = function() return 0 end,
		GetVerticalScrollRange = function() return 0 end,
		GetObjectType = function() return "Frame" end,
		IsObjectType = function() return true end,
		GetAlpha = function() return 1 end,
		GetNumLines = function() return 0 end,
		GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end,
		CreateAnimationGroup = function() return perm("anim") end,
		GetFrameStrata = function() return "MEDIUM" end,
	}
	setmetatable(o, { __index = function(t, k)
		if known[k] then return known[k] end
		if type(k) == "string" and (k:match("^Create") ) then
			return function() return perm(k) end
		end
		if type(k) ~= "string" or not k:match("^%u") or k:match("^WFR") or k:match("^RCR") then
			return nil -- plain fields are nil on real frames
		end
		return function() return nil end
	end })
	return o
end

ALLFRAMES = {}
function CreateFrame(kind, gname, parent, template)
	local f = perm(kind)
	ALLFRAMES[#ALLFRAMES + 1] = f
	if gname then f.__gname = gname; _G[gname] = f end
	return f
end
UIParent = perm("UIParent"); UIParent.w, UIParent.h = 1365, 768
Minimap = perm("Minimap")
GameTooltip = perm("GameTooltip")
GameFontNormal, GameFontHighlight, GameFontHighlightSmall = perm("f"), perm("f"), perm("f")
DEFAULT_CHAT_FRAME = perm("chat")
ChatFrame1EditBox = perm("edit")
Settings = nil
InterfaceOptions_AddCategory = function() end
StaticPopupDialogs = {}
StaticPopup_Show = function() end
SlashCmdList = {}
UISpecialFrames = {}
RAID_CLASS_COLORS = {}
issecretvalue = nil
canaccessvalue = nil

PRINTED = {}
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end PRINTED[#PRINTED + 1] = table.concat(t, " ") end
function GetBuildInfo() return "x", "1", "Oct 1 2026", BUILD_TOC end
function GetLocale() return "enUS" end
function GetTime() return NOW or 100 end
function GetServerTime() return 1000 end
function time() return 1000 end
function date() return "2026-10-14" end
function debugprofilestop() return 0 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, strupper, strsub, strfind, strmatch, format, tinsert, tremove = string.lower, string.upper, string.sub, string.find, string.match, string.format, table.insert, table.remove
function tContains(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
function hooksecurefunc(t, m, fn)
	if type(t) == "table" and type(m) == "string" and type(fn) == "function" then
		local orig = t[m]
		if type(orig) == "function" then
			t[m] = function(...) local a, b, c, d = orig(...); fn(...); return a, b, c, d end
		end
	elseif type(t) == "string" and type(m) == "function" then
		local orig = _G[t]
		if type(orig) == "function" then
			_G[t] = function(...) local a, b, c, d = orig(...); m(...); return a, b, c, d end
		end
	end
end
function InCombatLockdown() return false end
function UnitClass() return "Class", CLASS_FILE, CLASS_ID end
function UnitClassBase() return CLASS_FILE end
function UnitRace() return "Human", "Human", 1 end
function UnitFactionGroup() return "Alliance" end
function UnitLevel() return 60 end
function UnitExists(u) return u == "player" end
function UnitIsDeadOrGhost() return false end
function UnitAffectingCombat() return false end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function UnitPower() return 50 end
function UnitPowerMax() return 100 end
function UnitPowerType() return 0 end
function UnitGUID(u) return "Player-1" end
function UnitName() return "Rob" end
function UnitCanAttack() return false end
function UnitIsFriend() return true end
function UnitReaction() return 5 end
function UnitInRaid() return nil end
function UnitInParty() return false end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetShapeshiftForm() return 0 end
function GetNumShapeshiftForms() return 0 end
function GetSpecialization() return 1 end
function HasAction() return false end
function IsMounted() return false end
function IsStealthed() return false end
function GetInventoryItemID() return nil end
function GetWeaponEnchantInfo() return false end
function GetComboPoints() return 0 end
function GetCVar() return "0" end
function GetCursorPosition() return 0, 0 end
function PlaySound() end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end, NewTimer = function() return { Cancel = function() end } end }
C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnMetadata = function(_, k) if k == "Version" then return "1.1.0" end end }
C_Spell = setmetatable({}, { __index = function() return function() return nil end end })
C_SpellBook = setmetatable({ GetNumSpellBookSkillLines = function() return 0 end }, { __index = function() return function() return nil end end })
C_UnitAuras = setmetatable({}, { __index = function() return function() return nil end end })
C_TooltipInfo = setmetatable({}, { __index = function() return function() return nil end end })
C_Item = setmetatable({}, { __index = function() return function() return nil end end })
Enum = { PowerType = { Mana = 0, Rage = 1, Energy = 3, RunicPower = 6 } }
LibStub = nil


-- ===================================================================== Forever
-- Registering the combat log errors on Forever (as on Midnight retail).
local realCreateFrame = CreateFrame
function CreateFrame(...)
	local f = realCreateFrame(...)
	f.RegisterEvent = function(self, ev)
		if ev == "COMBAT_LOG_EVENT_UNFILTERED" or ev == "COMBAT_LOG_EVENT" then
			error("Forever: registering " .. ev .. " is not allowed")
		end
		self.events = self.events or {}
		self.events[ev] = true
	end
	f.RegisterUnitEvent = f.RegisterEvent
	f.IsEventRegistered = function(self, ev) return self.events and self.events[ev] or false end
	f.UnregisterEvent = function(self, ev) if self.events then self.events[ev] = nil end end
	return f
end

-- Secret values. Real secrets can be stored, passed around and handed to a
-- few widget setters; arithmetic, comparisons, indexing and calling them is a
-- Lua error. Here a secret is an empty table with a metatable that refuses
-- all of that (comparisons and arithmetic on a table error natively).
local SECRET = {}
SECRET.__index = function() error("Forever: indexed a secret value", 2) end
SECRET.__newindex = function() error("Forever: assigned into a secret value", 2) end
SECRET.__call = function() error("Forever: called a secret value", 2) end
SECRET.__concat = function() return NEWSECRET("") end
SECRET.__tostring = function() return "<secret>" end
SECRET.__metatable = "secret"
local rawtype = type
local SECRET_TYPE = setmetatable({}, { __mode = "k" })
local function secret(v)
	local o = setmetatable({}, SECRET)
	SECRET_TYPE[o] = rawtype(v)
	return o
end
NEWSECRET = secret
function issecretvalue(v) return rawtype(v) == "table" and getmetatable(v) == "secret" end
-- type() of a secret gives its real type, as in the game
function type(v) if issecretvalue(v) then return SECRET_TYPE[v] end return rawtype(v) end
-- string.format and tostring accept secrets in the game (the result is secret)
local rawformat = string.format
string.format = function(fmt, ...)
	for i = 1, select("#", ...) do
		if issecretvalue((select(i, ...))) then return secret("") end
	end
	return rawformat(fmt, ...)
end
format = string.format
function canaccessvalue(v) return not issecretvalue(v) end
function issecrettable() return false end
function canaccesstable() return true end

COMBAT = false
TARGET = false
NO_SECRETS = false
local function S(v) if COMBAT and not NO_SECRETS then return secret(v) end return v end
SECRET_BOOLS = false -- also hide hostility (UnitCanAttack...) as secret booleans in combat
local function SB(v) if COMBAT and SECRET_BOOLS then return secret(v) end return v end

-- APIs retail (and so Forever) removed. Anything here must not be relied on.
local REMOVED = {
	"GetSpellInfo", "UnitAura", "UnitBuff", "UnitDebuff", "GetSpellCooldown", "IsUsableSpell",
	"GetSpellTexture", "GetAddOnMetadata", "IsAddOnLoaded", "GetSpellBookItemName", "GetSpellBookItemInfo",
	"GetNumSpellTabs", "GetSpellTabInfo", "GetSpellCharges", "GetRaidBuffTrayAuraInfo", "IsSpellInRange",
	"CombatLogGetCurrentEventInfo", "GetItemInfo", "GetSpellLink", "GetSpellCount", "IsCurrentSpell",
}
local removed = {}
for _, k in ipairs(REMOVED) do removed[k] = true; _G[k] = nil end
MISSING = {}
setmetatable(_G, { __index = function(t, k)
	if type(k) ~= "string" or removed[k] then return nil end
	if k:match("^[A-Z]") and not k:match("DB$") and not k:match("^RCRotations") and not k:match("^[A-Z_0-9]+$")
		and not k:match("Button%d") and not k:match("^ElvUI") and not k:match("^RCUI") and not k:match("^BT4") and not k:match("^Dominos") then
		MISSING[k] = true
		return function() return nil end
	end
end })

function InCombatLockdown() return COMBAT end
function UnitAffectingCombat(u) return COMBAT and (u == "player" or u == "target") end
local PLATES = { "nameplate1", "nameplate2", "nameplate3" }
local function enemy(u)
	if u == "target" then return TARGET end
	for _, p in ipairs(PLATES) do if u == p then return true end end
	return false
end
PET = false
function UnitExists(u) if u == "pet" then return PET end return u == "player" or enemy(u) end
function UnitIsUnit(a, b) return a == b end
function UnitCanAttack(a, u) if u == "player" then return false end return SB(a == "player" and enemy(u)) end
function UnitIsEnemy(a, u) if u == "player" then return false end return SB(a == "player" and enemy(u)) end
function UnitIsFriend(a, u) return not enemy(u) end
function UnitReaction(a, b) if enemy(a) or enemy(b) then return S(2) end return 5 end
function UnitIsPlayer(u) return u == "player" end
function UnitPlayerControlled(u) return u == "player" end
function UnitIsDeadOrGhost() return false end
function UnitIsDead() return false end
function UnitIsTapDenied() return false end
function UnitClassification() return "normal" end
function UnitCreatureType() return "Humanoid" end
function UnitName(u) if u == "player" then return "Rob" end return S("Bandit") end
function UnitGUID(u) if u == "player" then return "Player-1-0001" end return "Creature-0-1-1-1-1234-0000ABCD" end
function UnitHealth(u) if u == "player" then return 900 end return S(4000) end
function UnitHealthMax(u) if u == "player" then return 1000 end return S(10000) end
function UnitPower() return 60 end
function UnitPowerMax() return 100 end
function UnitAttackSpeed() return 2.4, nil end
function UnitCastingInfo() return nil end
function UnitChannelInfo() return nil end
function UnitSelectionColor(u) if enemy(u) then return S(1), S(0), S(0), 1 end return 0, 1, 0, 1 end
function UnitInRange() return true, true end
function UnitIsVisible() return true end
function UnitIsConnected() return true end
function CheckInteractDistance() return true end
function IsMounted() return false end
function GetTime() return NOW or 100 end

KNOWN = {}
function IsPlayerSpell(id) return KNOWN[id] == true end
function IsSpellKnown(id) return KNOWN[id] == true end
function IsSpellKnownOrOverridesKnown(id) return KNOWN[id] == true end
C_Spell = {
	GetSpellInfo = function(id) if type(id) ~= "number" then return nil end return { name = "Spell" .. id, spellID = id, iconID = 134400, castTime = 0, minRange = 0, maxRange = 30 } end,
	GetSpellName = function(id) return type(id) == "number" and ("Spell" .. id) or nil end,
	GetSpellTexture = function() return 134400 end,
	GetSpellCooldown = function() return { startTime = S(0), duration = S(0), isEnabled = true, modRate = 1 } end,
	GetSpellCharges = function() return nil end,
	IsSpellUsable = function(id) return KNOWN[id] == true, false end,
	IsSpellInRange = function() return true end,
	GetOverrideSpell = function(id) return id end,
	IsCurrentSpell = function() return false end,
	GetSpellPowerCost = function() return {} end,
	SpellHasRange = function() return true end,
	GetSpellLink = function(id) return "|Hspell:" .. tostring(id) .. "|h[Spell]|h" end,
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 0 end,
	IsSpellInSpellBook = function(id) return KNOWN[id] == true end,
	FindSpellBookSlotForSpell = function(id) return KNOWN[id] and 1 or nil end,
}
AURAS = {
	player = { { spellId = 1, name = "Buff" } },
	target = { { spellId = 2, name = "Debuff", harmful = true } },
}
C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i, filter)
		local list = AURAS[unit] or {}
		local harm = type(filter) == "string" and filter:find("HARMFUL")
		local n = 0
		for _, a in ipairs(list) do
			if (a.harmful and true or false) == (harm and true or false) then
				n = n + 1
				if n == i then
					local function SA(v) if AURAS_SECRET and not NO_SECRETS then return secret(v) end return S(v) end
					return { spellId = SA(a.spellId), name = SA(a.name), applications = SA(0), expirationTime = SA(0), duration = SA(0), sourceUnit = SA("player"), isHarmful = a.harmful }
				end
			end
		end
	end,
	GetPlayerAuraBySpellID = function() return nil end,
	GetAuraDataBySpellName = function() return nil end,
	GetAuraDataByAuraInstanceID = function() return nil end,
}
AuraUtil = { FindAuraByName = function() return nil end, ForEachAura = function() end }
C_CVar = { GetCVar = function(k) return CVARS[k] end, SetCVar = function(k, v) CVARS[k] = v end }
CVARS = { nameplateShowEnemies = "0" }
function GetCVar(k) return CVARS[k] end
function SetCVar(k, v) CVARS[k] = v end
C_AddOns = { IsAddOnLoaded = function() return false end, GetAddOnMetadata = function(_, k) if k == "Version" then return "1.5.1" end end }
C_Timer = { After = function(_, fn) TIMERS[#TIMERS + 1] = fn end, NewTicker = function() return { Cancel = function() end } end, NewTimer = function() return { Cancel = function() end } end }
TIMERS = {}

-- action bar: buttons 1-12 hold the class's spells, so flashes have targets
ACTION = {}
function HasAction(slot) return ACTION[slot] ~= nil end
function GetActionInfo(slot) if ACTION[slot] then return "spell", ACTION[slot] end end
function GetActionTexture(slot) return ACTION[slot] and 134400 or nil end
BUTTONS = {}
local slotN = 0
for _, barName in ipairs({ "Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft" }) do
	for i = 1, 12 do
		slotN = slotN + 1
		local b = CreateFrame("CheckButton", barName .. "Button" .. i, UIParent)
		b.action = slotN
		b.shown = true
		b.w, b.h = 36, 36
		local icon = perm("Texture")
		b.icon, b.Icon = icon, icon
		b.HotKey, b.Name, b.Count, b.Border, b.NormalTexture, b.cooldown, b.Cooldown = perm("t"), perm("t"), perm("t"), perm("t"), perm("t"), perm("cd"), perm("cd")
		BUTTONS[slotN] = b
	end
end

-- nameplates (Blizzard style, plus one ElvUI-style)
local function bar()
	local t = perm("bar"); t.shown = true; t.alpha = 1
	t.SetAlpha = function(self, a) self.alpha = a end
	t.SetAlphaFromBoolean = function(self, v, a, b) self.fromBool = (self.fromBool or 0) + 1 end
	return t
end
PLATES_LIST = nil
local plateList = {}
for i, unit in ipairs(PLATES) do
	local p = perm("plate"); p.shown = true; p.namePlateUnitToken = unit
	if i == 3 then
		p.unitFrame = { Health = bar(), Name = perm("name"), TargetIndicator = { Shadow = bar(), Spark = bar() } }
		p.unitFrame.Health.Text = bar()
	else
		p.UnitFrame = { healthBar = bar(), name = perm("name"), unit = unit }
	end
	plateList[i] = p
end
PLATES_LIST = plateList
C_NamePlate = {
	GetNamePlates = function() return plateList end,
	GetNamePlateForUnit = function(u) for _, p in ipairs(plateList) do if p.namePlateUnitToken == u then return p end end end,
}
