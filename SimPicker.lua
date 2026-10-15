local addonName, ns = ...

-- ---------------------------------------------------------------------------
-- Rotation picker. When a spec has more than one WoWSims rotation (Frost DK:
-- Obliterate / Masterfrost, ...), ask once on login or spec change, then keep
-- the choice per character and spec in ns.db.simPick until it's changed
-- (/rcr apl, or the options menu later). Closing without a choice uses the
-- first rotation for now and asks again next login.
-- ---------------------------------------------------------------------------

local Sim = ns.Sim
if not Sim then
	return
end

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 8,
	edgeSize = 14,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BTN_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 8,
	edgeSize = 10,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local frame
local pendingAfterCombat = false

local function T(key, fallback)
	local text = ns.T and ns.T(key)
	if not text or text == key then
		return fallback
	end
	return text
end

local function specName(spec)
	if Sim.SpecName and Sim.SpecName(spec) then
		return Sim.SpecName(spec)
	end
	if GetSpecializationInfo then
		local ok, _, name = pcall(GetSpecializationInfo, spec)
		if ok and type(name) == "string" and name ~= "" then
			return name
		end
	end
	return nil
end

local function pickKey(token, spec)
	return token .. ":" .. spec
end

local function savedPick(token, spec)
	return ns.db and ns.db.simPick and ns.db.simPick[pickKey(token, spec)]
end

local function choose(rot, token, spec)
	ns.db.simPick = ns.db.simPick or {}
	ns.db.simPick[pickKey(token, spec)] = rot.file
	if ns.Print then
		ns.Print(T("SIM_CHOSEN", "Rotation set to %s. Change it any time with /rcr apl."):format(rot.name))
	end
	if ns.InvalidateTick then
		ns.InvalidateTick()
	end
	if ns.Tick then
		pcall(ns.Tick)
	end
end

local function styleButton(btn, selected)
	if selected then
		btn:SetBackdropColor(0.28, 0.20, 0.04, 0.95)
		btn:SetBackdropBorderColor(1, 0.82, 0.2, 1)
		btn.label:SetTextColor(1, 0.82, 0.2)
	else
		btn:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
		btn:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
		btn.label:SetTextColor(0.92, 0.92, 0.92)
	end
end

local function ensureFrame()
	if frame then
		return frame
	end
	frame = CreateFrame("Frame", "RCRotationsPicker", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, 0.88)
	frame:SetBackdropBorderColor(0.83, 0.63, 0.09, 0.9)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:SetClampedToScreen(true)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -14)
	title:SetText("|cff66ccffRC|r|cffd4a017Rotations|r")
	frame.title = title

	local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	sub:SetPoint("TOP", title, "BOTTOM", 0, -6)
	sub:SetPoint("LEFT", 16, 0)
	sub:SetPoint("RIGHT", -16, 0)
	sub:SetJustifyH("CENTER")
	frame.sub = sub

	local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("BOTTOM", 0, 14)
	hint:SetPoint("LEFT", 16, 0)
	hint:SetPoint("RIGHT", -16, 0)
	hint:SetJustifyH("CENTER")
	hint:SetTextColor(0.65, 0.65, 0.65)
	frame.hint = hint

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)
	frame.close = close

	frame.buttons = {}
	frame:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "RCRotationsPicker")
	end
	return frame
end

local function buttonAt(i)
	local btn = frame.buttons[i]
	if btn then
		return btn
	end
	btn = CreateFrame("Button", nil, frame, "BackdropTemplate")
	btn:SetHeight(26)
	btn:SetBackdrop(BTN_BACKDROP)
	local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("CENTER", 0, 0)
	btn.label = label
	btn:SetScript("OnEnter", function(self)
		if not self.selected then
			self:SetBackdropBorderColor(1, 0.82, 0.2, 1)
		end
	end)
	btn:SetScript("OnLeave", function(self)
		styleButton(self, self.selected)
	end)
	frame.buttons[i] = btn
	return btn
end

-- Show the picker for the current spec. force = open even if already chosen.
function Sim.ShowPicker(force)
	local list, token, spec = Sim.Rotations()
	list = list or {}
	if not token or not spec or spec == 0 then
		if force and ns.Print then
			ns.Print(Sim.NoSpecMessage and Sim.NoSpecMessage() or T("SIM_IMPORT_NOSPEC", "Rotations need a specialization."))
		end
		return false
	end
	if not force and #list < 2 then
		return false
	end
	if not force and savedPick(token, spec) then
		return false
	end
	if InCombatLockdown and InCombatLockdown() then
		pendingAfterCombat = true
		return false
	end
	ensureFrame()
	local current = Sim.Current()
	local name = specName(spec)
	frame.sub:SetText(name and T("SIM_PICK_TITLE", "Choose your %s rotation"):format(name) or T("SIM_PICK_TITLE_GENERIC", "Choose your rotation"))
	frame.hint:SetText(T("SIM_PICK_HINT", "Saved for this character. Change it any time with /rcr apl."))
	local width = 300
	for i, rot in ipairs(list) do
		local btn = buttonAt(i)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -58 - (i - 1) * 32)
		btn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", rot.imported and -48 or -20, -58 - (i - 1) * 32)
		if rot.imported then
			local rm = btn.remove
			if not rm then
				rm = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
				rm:SetSize(24, 24)
				btn.remove = rm
			end
			rm:ClearAllPoints()
			rm:SetPoint("LEFT", btn, "RIGHT", 2, 0)
			rm:SetScript("OnClick", function()
				if Sim.RemoveImport(token, spec, rot.file) and ns.Print then
					ns.Print(T("SIM_IMPORT_REMOVED", "Removed %s."):format(rot.name))
				end
				Sim.ShowPicker(true)
			end)
			rm:Show()
		elseif btn.remove then
			btn.remove:Hide()
		end
		local label = rot.name
		if i == 1 then
			label = label .. "  |cff888888" .. T("SIM_PICK_DEFAULT", "(default)") .. "|r"
		end
		btn.label:SetText(label)
		btn.selected = (rot == current) and (savedPick(token, spec) ~= nil or #list == 1)
		styleButton(btn, btn.selected)
		btn:SetScript("OnClick", function()
			choose(rot, token, spec)
			frame:Hide()
		end)
		btn:Show()
	end
	for i = #list + 1, #frame.buttons do
		frame.buttons[i]:Hide()
		if frame.buttons[i].remove then
			frame.buttons[i].remove:Hide()
		end
	end
	if not frame.importBtn and Sim.GoldButton then
		frame.importBtn = Sim.GoldButton(frame, 180, T("SIM_IMPORT_OPEN", "Import a rotation..."))
		frame.importBtn:SetScript("OnClick", function()
			frame:Hide()
			if Sim.ShowImport then
				Sim.ShowImport()
			end
		end)
	end
	if frame.importBtn then
		frame.importBtn:ClearAllPoints()
		frame.importBtn:SetPoint("TOP", frame, "TOP", 0, -58 - #list * 32 - 4)
	end
	if #list == 0 then
		frame.sub:SetText(T("SIM_PICK_EMPTY", "No WoWSims rotation for this spec yet. Import one:"))
	end
	frame:SetSize(width, 58 + #list * 32 + 36 + 40)
	frame:Show()
	return true
end

-- ------------------------------------------------------------------ events
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "PLAYER_SPECIALIZATION_CHANGED")
pcall(events.RegisterEvent, events, "ACTIVE_TALENT_GROUP_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PLAYER_ENTERING_WORLD" then
		-- Login or /reload only, not every zone change. Wait a moment so the
		-- spec and spellbook are ready.
		if arg1 or arg2 then
			if C_Timer and C_Timer.After then
				C_Timer.After(3, function()
					Sim.ShowPicker(false)
				end)
			else
				Sim.ShowPicker(false)
			end
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingAfterCombat then
			pendingAfterCombat = false
			Sim.ShowPicker(false)
		end
	elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
		if arg1 == nil or arg1 == "player" then
			if C_Timer and C_Timer.After then
				C_Timer.After(1, function()
					Sim.ShowPicker(false)
				end)
			else
				Sim.ShowPicker(false)
			end
		end
	elseif event == "ACTIVE_TALENT_GROUP_CHANGED" then
		if C_Timer and C_Timer.After then
			C_Timer.After(1, function()
				Sim.ShowPicker(false)
			end)
		end
	end
end)
