local addonName, ns = ...

-- Gathering / treasure tracking reminders: an icon left of the main HUD icon
-- for each kind of tracking you have but haven't turned on (Find Minerals or
-- Find Herbs, and the Dwarf's Find Treasure). Click an icon to turn it on.
-- Only one of Minerals / Herbs can be on at a time, so they share a reminder.
ns.Tracking = ns.Tracking or {}
local T = ns.Tracking

local GROUPS = {
	{ key = "gather", spells = { 2580, 2383 } }, -- Find Minerals, Find Herbs
	{ key = "treasure", spells = { 2481 } }, -- Find Treasure (Dwarf)
}

local SIZE = 25 -- two stacked = the main icon's height (50)

local function secret(v)
	return issecretvalue and issecretvalue(v)
end

local function call(fn, ...)
	if not fn then
		return nil
	end
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
	return nil
end

local function known(id)
	if IsPlayerSpell and call(IsPlayerSpell, id) == true then
		return true
	end
	if IsSpellKnown and call(IsSpellKnown, id) == true then
		return true
	end
	return false
end

local function spellName(id)
	local n = C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, id)
	if not n and GetSpellInfo then
		n = call(GetSpellInfo, id)
	end
	if type(n) == "string" and not secret(n) then
		return n
	end
	return nil
end

local function spellIcon(id)
	local t = C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, id)
	if not t and GetSpellTexture then
		t = call(GetSpellTexture, id)
	end
	return t or 134400
end

-- the names of the tracking types that are on right now
local function activeTracking()
	local on = {}
	local M = C_Minimap
	if type(M) == "table" and M.GetNumTrackingTypes and M.GetTrackingInfo then
		local n = call(M.GetNumTrackingTypes) or 0
		if secret(n) then
			return nil
		end
		for i = 1, n do
			local info = call(M.GetTrackingInfo, i)
			if type(info) == "table" then
				if not secret(info.active) and info.active and type(info.name) == "string" and not secret(info.name) then
					on[info.name] = true
				end
				if info.spellID and not secret(info.spellID) and not secret(info.active) and info.active then
					on[info.spellID] = true
				end
			else
				-- older form: name, texture, active, ...
				local name, _, active = call(M.GetTrackingInfo, i)
				if type(name) == "string" and not secret(name) and not secret(active) and active then
					on[name] = true
				end
			end
		end
		return on
	end
	if GetTrackingTexture then
		local tex = call(GetTrackingTexture)
		if tex and not secret(tex) then
			on.texture = tex
		end
		return on
	end
	return nil
end

local function isOn(on, id)
	if on[id] then
		return true
	end
	local name = spellName(id)
	if name and on[name] then
		return true
	end
	if on.texture and on.texture == spellIcon(id) then
		return true
	end
	-- tracking also shows as a buff on the player
	if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
		local a = call(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if a and not secret(a) then
			return true
		end
	end
	return false
end

-- what to remind about: one entry per group you have tracking for and haven't
-- turned on ({ key, spellID to cast })
function T.Missing()
	local on = activeTracking()
	if not on then
		return {}
	end
	local out = {}
	for _, g in ipairs(GROUPS) do
		local have, anyOn
		for _, id in ipairs(g.spells) do
			if known(id) then
				have = have or id
				if isOn(on, id) then
					anyOn = true
				end
			end
		end
		if have and not anyOn then
			out[#out + 1] = { key = g.key, id = have }
		end
	end
	return out
end

-- icons ---------------------------------------------------------------------

local buttons = {}
local holder

-- in combat by either test; a hidden (secret) answer counts as in combat
local function inCombat()
	local v = InCombatLockdown and call(InCombatLockdown)
	if v ~= nil and secret(v) then
		return true
	end
	if v == true then
		return true
	end
	local c = UnitAffectingCombat and call(UnitAffectingCombat, "player")
	if c ~= nil and secret(c) then
		return true
	end
	return c == true
end

local function makeButton(i)
	local b = CreateFrame("Button", "RCRotationsTracking" .. i, holder, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	b:SetAttribute("type", "spell")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)
	local tex = b:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 2, -2)
	tex:SetPoint("BOTTOMRIGHT", -2, 2)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.texture = tex
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetAllPoints()
	border:SetColorTexture(1, 0.2, 0.2, 0.9)
	border:SetDrawLayer("BORDER")
	b.border = border
	b:SetScript("OnEnter", function(self)
		if not GameTooltip or not self.spellID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText((spellName(self.spellID) or "Tracking") .. " is off", 1, 0.3, 0.3)
		GameTooltip:AddLine("Click to turn it on.", 1, 1, 1)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	b:Hide()
	return b
end

function T.Attach()
	if holder or not (ns.UI and ns.UI.slots and ns.UI.slots[1]) then
		return
	end
	-- a column touching the main icon's left edge, top to bottom
	local slot = ns.UI.slots[1]
	holder = CreateFrame("Frame", "RCRotationsTrackingHolder", UIParent)
	holder:SetSize(SIZE, SIZE * #GROUPS)
	T.Place()
	for i = 1, #GROUPS do
		buttons[i] = makeButton(i)
		buttons[i]:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, -(i - 1) * SIZE)
	end
end

-- spell IDs to flash on your action bars (same flash as missing buffs):
-- the tracking you have turned off, outside combat
function T.FlashIds()
	if not T.Enabled() or inCombat() then
		return {}
	end
	local dead = UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, "player")
	if dead == true then
		return {}
	end
	local out = {}
	for _, m in ipairs(T.Missing()) do
		out[#out + 1] = m.id
	end
	return out
end

function T.Enabled()
	return not (ns.db and ns.db.showTracking == false)
end

-- The reminder buttons are secure (a click casts the tracking spell), and a
-- frame anchored to a secure frame becomes protected itself: the HUD then
-- couldn't be shown or hidden in combat (ADDON_ACTION_BLOCKED). So the column
-- isn't anchored to the HUD; it's placed at the main icon's screen position,
-- out of combat, and follows it when the HUD moves.
function T.Place()
	local slot = ns.UI and ns.UI.slots and ns.UI.slots[1]
	if not holder or not slot or inCombat() then
		return
	end
	local left, top = slot:GetLeft(), slot:GetTop()
	if not left or not top then
		return
	end
	local s = slot:GetEffectiveScale() / UIParent:GetEffectiveScale()
	holder:SetScale(s)
	local x, y = left * slot:GetEffectiveScale() / holder:GetEffectiveScale(), top * slot:GetEffectiveScale() / holder:GetEffectiveScale()
	if holder.placedX == x and holder.placedY == y then
		return
	end
	holder.placedX, holder.placedY = x, y
	holder:ClearAllPoints()
	holder:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x, y)
end

function T.Refresh()
	if not holder then
		return
	end
	pcall(T.Place)
	-- secure buttons can't change in combat: hide them by alpha instead, and
	-- leave the layout until the fight ends
	local dead = UnitIsDeadOrGhost and call(UnitIsDeadOrGhost, "player")
	if inCombat() then
		holder:SetAlpha(0)
		return
	end
	holder:SetAlpha(1)
	local hud = ns.UI and ns.UI.root
	holder:SetShown(not (hud and hud.IsVisible and not hud:IsVisible()))
	local list = (T.Enabled() and not (dead == true)) and T.Missing() or {}
	for i, b in ipairs(buttons) do
		local m = list[i]
		if m then
			local name = spellName(m.id)
			b.spellID = m.id
			b:SetAttribute("spell", name or m.id)
			b.texture:SetTexture(spellIcon(m.id))
			b:Show()
		else
			b.spellID = nil
			b:Hide()
		end
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
pcall(ev.RegisterEvent, ev, "MINIMAP_UPDATE_TRACKING")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(ev.RegisterEvent, ev, "PLAYER_ALIVE")
pcall(ev.RegisterEvent, ev, "PLAYER_UNGHOST")
pcall(ev.RegisterUnitEvent, ev, "UNIT_AURA", "player")
local since = 0
ev:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" then
		pcall(T.Attach)
	end
	pcall(T.Refresh)
end)
-- a slow check as well, in case the game fires no event for a change
ev:SetScript("OnUpdate", function(_, elapsed)
	since = since + (elapsed or 0)
	if since >= 2 then
		since = 0
		pcall(T.Refresh)
	end
end)
