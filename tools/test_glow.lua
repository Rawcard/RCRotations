-- Flash targeting tests (run by tools/test_sim.py, or: luajit tools/test_glow.lua from the repo root).
-- Hidden Blizzard button vs visible RCDiabloUI button carrying the same spell.
local function newRegion()
	local r = { shown = false, alpha = 1 }
	function r:Show() self.shown = true end
	function r:Hide() self.shown = false end
	function r:IsShown() return self.shown end
	function r:SetAlpha(a) self.alpha = a end
	function r:SetVertexColor(r_, g, b) self.color = { r_, g, b } end
	for _, m in ipairs({ "SetAllPoints", "SetPoint", "SetSize", "SetWidth", "SetHeight", "SetTexture", "SetBlendMode",
		"SetFrameStrata", "SetDrawLayer", "ClearAllPoints" }) do r[m] = function() end end
	return r
end
ALL_FRAMES = {}
function EnumerateFrames(prev)
	if not prev then return ALL_FRAMES[1] end
	for i, f in ipairs(ALL_FRAMES) do if f == prev then return ALL_FRAMES[i + 1] end end
end
function CreateFrame(kind, name)
	local f = newRegion()
	ALL_FRAMES[#ALL_FRAMES + 1] = f
	f.GetObjectType = function() return kind end
	f.level = 4
	function f:SetFrameLevel(l) self.level = l end
	function f:GetFrameLevel() return self.level end
	function f:CreateTexture() return newRegion() end
	function f:SetScript(ev, fn) self["on" .. ev] = fn end
	if name then _G[name] = f end
	return f
end
UIParent = CreateFrame("Frame")
function GetTime() return 100 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
C_Timer = { After = function(_, fn) fn() end }
C_AddOns = { IsAddOnLoaded = function() return false end }
C_Spell = { GetSpellInfo = function(id) return { spellID = id, name = "Spell" .. id, iconID = id } end, GetSpellTexture = function(id) return id end }
function HasAction(slot) return slot == 6 or slot == 18 end
function GetActionInfo(slot) if slot == 6 or slot == 18 then return "spell", 20271, nil, 20271 end end
function GetActionTexture() return 20271 end
function GetNumShapeshiftForms() return 0 end
local function button(name, slot, visible)
	local b = CreateFrame("Button", name)
	b.GetAttribute = function(_, k) if k == "action" then return slot end if k == "type" then return "action" end end
	b.GetName = function() return name end
	b.IsVisible = function() return visible end
	b.GetWidth = function() return 36 end
	b.GetHeight = function() return 36 end
	return b
end
local function labButton(name, slot, visible)
	local b = CreateFrame("CheckButton", name)
	b._state_type, b._state_action = "action", slot
	b.GetAttribute = function() return nil end
	b.GetName = function() return name end
	b.IsVisible = function() return visible end
	b.GetWidth = function() return 36 end
	b.GetHeight = function() return 36 end
	return b
end
local fails = 0
local function check(c, m) print((c and "PASS " or "FAIL ") .. m) if not c then fails = fails + 1 end end
local function setup(blizzVisible, rcuiVisible, other)
	for k in pairs(_G) do if type(k) == "string" and (k:match("^ActionButton") or k:match("^RCUI32") or k:match("^SomeBars")) then _G[k] = nil end end
	ALL_FRAMES = {}
	button("ActionButton6", 6, blizzVisible)
	if other then
		labButton("SomeBarsButton6", 18, true)
	else
		button("RCUI32_bar2Button6", 18, rcuiVisible)
	end
	local ns = { db = {} }
	ns.API = { Resolve = function(id) return id end, SpellInfo = function(id) return { spellID = id, name = "Spell" .. id } end, IsHealSpell = function() return false end }
	function ns.Color() return 1, 1, 1 end
	ns.queueHeal = {}
	assert(loadfile(GLOW_PATH or "Glow.lua"))("RCRotations", ns)
	ns.GlowFetch(true)
	ns.GlowSpell(20271)
	return ns
end
local function flashing(name)
	local b = _G[name]
	return b.RCRFlash and b.RCRFlash.next and b.RCRFlash.next.shown or false
end
setup(false, true)
check(flashing("RCUI32_bar2Button6") and not flashing("ActionButton6"), "RCDiabloUI visible, Blizzard hidden -> only the RCDiabloUI button flashes")
setup(false, false)
check(not flashing("RCUI32_bar2Button6") and not flashing("ActionButton6"), "every button hidden -> nothing flashes (no stray flash on the screen)")
setup(true, false)
check(flashing("ActionButton6") and not flashing("RCUI32_bar2Button6"), "plain Blizzard UI -> Blizzard button flashes")
local ns = setup(false, true)
local out = ns.GlowDebug(20271)
check(#out == 2 and table.concat(out, ","):find("%*RCUI32_bar2Button6") ~= nil and not table.concat(out, ","):find("%*ActionButton6"), "/rcr why marks only the flashed button: " .. table.concat(out, ", "))
local nsv = setup(false, true)
local b = _G["RCUI32_bar2Button6"]
b.IsVisible = function() return false end
local fl = b.RCRFlash.next
fl.onOnUpdate(fl, 0.1)
check(fl.alpha == 0, "button hides after flashing (bar fade) -> flash goes invisible too")
b.IsVisible = function() return true end
fl.onOnUpdate(fl, 0.1)
check(fl.alpha == 1, "button shows again -> flash comes back")
setup(false, nil, true)
check(flashing("SomeBarsButton6") and not flashing("ActionButton6"), "unknown bar addon (LibActionButton) found by the generic scan and flashed")
print(fails == 0 and "ALL PASS" or (fails .. " FAILED"))
