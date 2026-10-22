-- Hidden enemy nameplates.
--
-- RCRotations counts enemies around you through enemy nameplates (for AoE
-- choices in rotations). With nameplates off it always sees one target. This
-- option turns enemy nameplates on but makes them invisible and click-through,
-- so the addon can count enemies while you don't see the plates.
--
-- It only changes the game's nameplate settings (CVars). Your previous values
-- are saved and put back when you turn the option off. The game doesn't allow
-- these changes during combat, so they wait until combat ends.
local addonName, ns = ...
local Plates = {}
ns.Plates = Plates

local HIDDEN = {
	nameplateShowEnemies = "1",
	nameplateMinAlpha = "0",
	nameplateMaxAlpha = "0",
	nameplateSelectedAlpha = "0",
	nameplateOccludedAlphaMult = "0",
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

local function clickThrough(on)
	if type(C_NamePlate) == "table" and C_NamePlate.SetNamePlateEnemyClickThrough then
		pcall(C_NamePlate.SetNamePlateEnemyClickThrough, on and true or false)
	end
end

local function inCombat()
	return InCombatLockdown and InCombatLockdown()
end

-- Put the settings in line with ns.db.hidePlates (now, or after combat).
function Plates.Apply()
	if not ns.db then
		return
	end
	if inCombat() then
		pending = true
		return
	end
	pending = false
	if ns.db.hidePlates == true then
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
		clickThrough(true)
	elseif ns.db.plateBackup then
		for name, value in pairs(ns.db.plateBackup) do
			setCVar(name, value)
		end
		ns.db.plateBackup = nil
		clickThrough(false)
		if type(C_NamePlate) == "table" and C_NamePlate.GetNamePlates then
			local ok, plates = pcall(C_NamePlate.GetNamePlates)
			for _, plate in ipairs(ok and plates or {}) do
				if plate.UnitFrame and plate.UnitFrame.SetAlpha then
					pcall(plate.UnitFrame.SetAlpha, plate.UnitFrame, 1)
				end
			end
		end
	end
end

function Plates.Set(on)
	ns.db.hidePlates = on and true or false
	Plates.Apply()
	if ns.Print then
		ns.Print(ns.T(on and (inCombat() and "PLATES_ON_LATER" or "PLATES_ON") or (inCombat() and "PLATES_OFF_LATER" or "PLATES_OFF")))
	end
end

-- Enemy nameplates are off and the option isn't on: the addon sees one target.
function Plates.Blind()
	if ns.db and ns.db.hidePlates == true then
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
		-- Belt and braces: some clients ignore the alpha settings for the
		-- target's plate. Fade the plate's contents too (not protected).
		if ns.db and ns.db.hidePlates == true and C_NamePlate and C_NamePlate.GetNamePlateForUnit then
			local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
			if ok and plate and plate.UnitFrame and plate.UnitFrame.SetAlpha then
				pcall(plate.UnitFrame.SetAlpha, plate.UnitFrame, 0)
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
