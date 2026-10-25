-- Name-only enemy nameplates.
--
-- RCRotations counts enemies around you through enemy nameplates (for AoE
-- choices in rotations). With nameplates off it always sees one target. This
-- option turns enemy nameplates on but hides their health bars, so you still
-- see enemy names (and cast bars) while the addon counts the enemies.
--
-- It turns on the game's "show enemy nameplates" setting (your old value is
-- saved and put back when you turn the option off; the game doesn't allow
-- that during combat, so it waits until combat ends) and fades out the health
-- bar of each enemy plate as it appears.
local addonName, ns = ...
local Plates = {}
ns.Plates = Plates

local HIDDEN = {
	nameplateShowEnemies = "1",
}

local pending

local function getCVar(name)
	if type(C_CVar) == "table" and C_CVar.GetCVar then
		local ok, v = pcall(C_CVar.GetCVar, name)
		if ok then
			return v
		end
	end
	if GetCVar then
		local ok, v = pcall(GetCVar, name)
		if ok then
			return v
		end
	end
	return nil
end

local function setCVar(name, value)
	if value == nil then
		return
	end
	if type(C_CVar) == "table" and C_CVar.SetCVar then
		pcall(C_CVar.SetCVar, name, value)
	elseif SetCVar then
		pcall(SetCVar, name, value)
	end
end

local function inCombat()
	return InCombatLockdown and InCombatLockdown()
end

local function on()
	return ns.db and ns.db.hidePlates == true
end

-- WoW Forever (like retail Midnight) can hand addons "secret" values in
-- combat: they can be passed to some widget functions but not tested or
-- compared. Whether a plate is hostile may be one, so hiding goes through
-- SetAlphaFromBoolean when it is.
local function secret(v)
	return issecretvalue and issecretvalue(v) or false
end

-- alpha = hidden (0) when hide is true, shown (1) when false; hide may be secret
local function fade(region, hide, hiddenAlpha, shownAlpha)
	if not region or not region.SetAlpha then
		return
	end
	hiddenAlpha, shownAlpha = hiddenAlpha or 0, shownAlpha or 1
	if secret(hide) then
		if region.SetAlphaFromBoolean and pcall(region.SetAlphaFromBoolean, region, hide, hiddenAlpha, shownAlpha) then
			return
		end
		hide = true -- can't tell: enemy plates are what this option shows
	end
	pcall(region.SetAlpha, region, hide and hiddenAlpha or shownAlpha)
end

-- The health bar of one Blizzard nameplate: hidden (alpha 0) or shown.
-- Names, cast bars and raid marks are left alone. Changing alpha is allowed
-- in combat; it doesn't touch the protected plate frame itself.
-- Works with Blizzard's plates (plate.UnitFrame.healthBar) and with nameplate
-- addons that hang their own frame on the plate: ElvUI (plate.unitFrame.Health),
-- Plater and others (plate.unitFrame.healthBar).
local function healthBars(plate)
	local out = {}
	local frames = { plate and plate.UnitFrame or false, plate and plate.unitFrame or false }
	for i = 1, 2 do
		local uf = frames[i]
		if type(uf) == "table" then
			for _, key in ipairs({ "healthBar", "HealthBar", "Health", "selectionHighlight" }) do
				local bar = uf[key]
				if type(bar) == "table" and bar.SetAlpha then
					out[#out + 1] = bar
				end
			end
		end
	end
	return out
end

-- Bits of an addon plate (ElvUI) that go with the bar: health % text, level,
-- and the target glow / spark / arrows and mouseover highlight.
local function addonExtras(uf)
	local out = {}
	local function add(t)
		if type(t) == "table" and t.SetAlpha then
			out[#out + 1] = t
		end
	end
	local h = type(uf.Health) == "table" and uf.Health or nil
	if h then
		add(h.Text)
		add(h.value)
		add(h.Highlight)
	end
	add(uf.HealthText)
	add(uf.Level)
	add(uf.Highlight)
	local ti = type(uf.TargetIndicator) == "table" and uf.TargetIndicator or nil
	if ti then
		add(ti)
		for _, k in ipairs({ "Shadow", "Spark", "TopIndicator", "LeftIndicator", "RightIndicator", "Glow" }) do
			add(ti[k])
		end
	end
	add(uf.Glow)
	add(uf.Spark)
	return out
end

-- Name color the way Blizzard's nameplates do it: red for hostile, yellow for
-- neutral, grey once someone else has tagged it.
local function nameColor(unit)
	if unit then
		local ok, denied = pcall(UnitIsTapDenied or function() end, unit)
		if ok and not secret(denied) and denied then
			return 0.5, 0.5, 0.5
		end
		if UnitSelectionColor then
			local ok2, r, g, b = pcall(UnitSelectionColor, unit)
			if ok2 and type(r) == "number" then
				return r, g, b
			end
		end
		local ok3, reaction = pcall(UnitReaction, unit, "player")
		if ok3 and reaction and not secret(reaction) and reaction >= 4 then
			return 1, 1, 0
		end
	end
	return 1, 0, 0
end

-- ElvUI places its name at the left end of its own health bar, and keeps
-- putting it back there. So while bars are hidden its name is faded out and
-- RCRotations shows the same name, in the same font with Blizzard's name color, centered on the
-- game's nameplate frame, which always sits right above the character.
local function ownName(plate, uf, hide, unit)
	local theirs = type(uf.Name) == "table" and uf.Name or nil
	local mine = plate.rcrName
	if not secret(hide) and not hide then
		if mine then
			mine:Hide()
		end
		fade(theirs, false)
		return
	end
	if not mine then
		local ok, holder = pcall(CreateFrame, "Frame", nil, plate)
		if not ok or not holder then
			return
		end
		holder:SetAllPoints(plate)
		if holder.SetFrameLevel and plate.GetFrameLevel then
			pcall(holder.SetFrameLevel, holder, (plate:GetFrameLevel() or 0) + 20)
		end
		mine = holder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		mine:SetPoint("CENTER", plate, "CENTER", 0, 0)
		mine:SetJustifyH("CENTER")
		mine.holder = holder
		plate.rcrName = mine
	end
	if theirs then
		if theirs.GetFont then
			local font, size, flags = theirs:GetFont()
			if font then
				pcall(mine.SetFont, mine, font, size, flags)
			end
		end
		fade(theirs, hide)
	end
	local text = unit and UnitName and UnitName(unit)
	if not text and theirs and theirs.GetText then
		text = theirs:GetText()
	end
	mine:SetText(text or "")
	local r, g, b2 = nameColor(unit)
	if not pcall(mine.SetTextColor, mine, r, g, b2) then
		mine:SetTextColor(1, 0, 0)
	end
	if mine.holder then
		mine.holder:Show()
	end
	mine:Show()
	-- ours shows exactly when theirs is hidden
	fade(mine, hide, 1, 0)
end

local function styleBar(plate, hide, unit)
	for _, bar in ipairs(healthBars(plate)) do
		fade(bar, hide)
	end
	local uf = plate and plate.unitFrame
	if type(uf) == "table" and uf ~= plate.UnitFrame then
		for _, t in ipairs(addonExtras(uf)) do
			fade(t, hide)
		end
		ownName(plate, uf, hide, unit)
	end
end

-- true / false, or a secret boolean on WoW Forever in combat
local function hostileUnit(unit)
	local ok, can = pcall(UnitCanAttack, "player", unit)
	if not ok then
		return false
	end
	if secret(can) then
		return can
	end
	return can and true or false
end

local function forEachPlate(fn)
	if type(C_NamePlate) ~= "table" or not C_NamePlate.GetNamePlates then
		return
	end
	local ok, plates = pcall(C_NamePlate.GetNamePlates)
	for _, plate in ipairs(ok and type(plates) == "table" and plates or {}) do
		fn(plate)
	end
end

local function restyleAll()
	forEachPlate(function(plate)
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		styleBar(plate, on() and unit and hostileUnit(unit), unit)
	end)
end

-- Put the settings in line with ns.db.hidePlates (now, or after combat).
function Plates.Apply()
	if not ns.db then
		return
	end
	restyleAll()
	if inCombat() then
		pending = true
		return
	end
	pending = false
	-- Test builds of 1.5.0 also set the nameplate alpha settings to 0, which hid
	-- names too. Put those back from the saved copy.
	if ns.db.plateBackup then
		for name, value in pairs(ns.db.plateBackup) do
			if HIDDEN[name] == nil then
				setCVar(name, value)
				ns.db.plateBackup[name] = nil
			end
		end
	end
	if on() then
		if not ns.db.plateBackup then
			local backup = {}
			for name in pairs(HIDDEN) do
				backup[name] = getCVar(name)
			end
			ns.db.plateBackup = backup
		end
		for name, value in pairs(HIDDEN) do
			setCVar(name, value)
		end
	elseif ns.db.plateBackup then
		for name, value in pairs(ns.db.plateBackup) do
			setCVar(name, value)
		end
		ns.db.plateBackup = nil
	end
end

function Plates.Set(value)
	ns.db.hidePlates = value and true or false
	Plates.Apply()
	if ns.Print then
		ns.Print(ns.T(value and (inCombat() and "PLATES_ON_LATER" or "PLATES_ON") or (inCombat() and "PLATES_OFF_LATER" or "PLATES_OFF")))
	end
end

-- Enemy nameplates are off and the option isn't on: the addon sees one target.
function Plates.Blind()
	if on() then
		return false
	end
	return getCVar("nameplateShowEnemies") == "0"
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		if type(C_NamePlate) == "table" and C_NamePlate.GetNamePlateForUnit then
			local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
			if ok and plate then
				-- plates are reused, so always set the bar one way or the other
				styleBar(plate, on() and hostileUnit(unit), unit)
			end
		end
		return
	end
	if event == "PLAYER_ENTERING_WORLD" or pending then
		Plates.Apply()
	end
	if event == "PLAYER_ENTERING_WORLD" and ns.db and not ns.db.platesTip and Plates.Blind() and ns.Print then
		ns.db.platesTip = true
		ns.Print(ns.T("PLATES_TIP"))
	end
end)

-- Nameplate addons (ElvUI and the like) style their plates after this event
-- and may reset a bar; check every half second while the option is on.
local elapsedSince, wasOn = 0, false
frame:SetScript("OnUpdate", function(_, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.5 then
		return
	end
	elapsedSince = 0
	local now = on()
	if now or wasOn then
		restyleAll()
	end
	wasOn = now
end)

-- Blizzard's nameplate code can reset a bar's look (target changes, health
-- updates); put the hidden look back right after it does.
if hooksecurefunc and type(CompactUnitFrame_UpdateAll) == "function" then
	hooksecurefunc("CompactUnitFrame_UpdateAll", function(uf)
		if on() and uf and type(uf.unit) == "string" and uf.unit:find("^nameplate") then
			local hostile = hostileUnit(uf.unit)
			if secret(hostile) or hostile then
				fade(uf.healthBar or uf.HealthBar, hostile)
			end
		end
	end)
end
