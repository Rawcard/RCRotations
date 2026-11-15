local addonName, ns = ...

-- Flash colors window (/rcr colors, or the button on Options > Extra > Colors):
-- pick the color of each kind of action-bar flash, or apply a preset scheme.
ns.ColorMenu = ns.ColorMenu or {}
local M = ns.ColorMenu

local ROWS = {
	{ key = "next", label = "Main spell" },
	{ key = "second", label = "Second spell" },
	{ key = "track", label = "Tracking (mining, herbs, treasure)" },
	{ key = "buff", label = "Missing buff" },
	{ key = "def", label = "Defensive" },
	{ key = "kick", label = "Interrupt" },
	{ key = "purge", label = "Purge" },
}

-- Schemes from RC-SpellFlash (main / second / tracking); "Default" puts every
-- color back.
local PRESETS = {
	{ name = "Default" },
	{ name = "Fire & Ice", next = { 1, 0, 0 }, second = { 0, 0.5, 1 }, track = { 1, 0.5, 0 } },
	{ name = "Classic NAG", next = { 0, 1, 0 }, second = { 0, 0.9, 1 }, track = { 1, 1, 0 } },
	{ name = "RGB", next = { 1, 0, 0 }, second = { 0, 1, 0 }, track = { 0, 0.5, 1 } },
}

local frame

local function redraw()
	-- drop every flash so the next update redraws them in the new colors
	if ns.GlowClearAllStyles then
		pcall(ns.GlowClearAllStyles)
	end
	if frame and frame:IsShown() then
		M.Refresh()
	end
end

local function setColor(key, r, g, b)
	ns.db.flashColors = ns.db.flashColors or {}
	ns.db.flashColors[key] = { r, g, b }
	redraw()
end

local function pick(key)
	local r, g, b = ns.FlashColor(key)
	local function apply(nr, ng, nb)
		setColor(key, nr, ng, nb)
	end
	local CP = ColorPickerFrame
	if not CP then
		return
	end
	if CP.SetupColorPickerAndShow then
		CP:SetupColorPickerAndShow({
			r = r,
			g = g,
			b = b,
			hasOpacity = false,
			swatchFunc = function()
				apply(CP:GetColorRGB())
			end,
			cancelFunc = function()
				apply(r, g, b)
			end,
		})
	else
		CP.func = function()
			apply(CP:GetColorRGB())
		end
		CP.cancelFunc = function()
			apply(r, g, b)
		end
		if CP.SetColorRGB then
			CP:SetColorRGB(r, g, b)
		end
		CP:Show()
	end
end

function M.ApplyPreset(preset)
	if preset.name == "Default" then
		ns.db.flashColors = nil
	else
		ns.db.flashColors = ns.db.flashColors or {}
		for _, k in ipairs({ "next", "second", "track" }) do
			if preset[k] then
				ns.db.flashColors[k] = { preset[k][1], preset[k][2], preset[k][3] }
			end
		end
	end
	redraw()
end

local function button(parent, w, h, text)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h)
	b:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	b:SetBackdropColor(0.12, 0.1, 0.06, 0.95)
	b:SetBackdropBorderColor(0.8, 0.62, 0.15, 1)
	local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("CENTER")
	fs:SetText(text)
	b.label = fs
	b:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(1, 0.85, 0.3, 1)
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0.8, 0.62, 0.15, 1)
	end)
	return b
end

local function build()
	local f = CreateFrame("Frame", "RCRotationsColorMenu", UIParent, "BackdropTemplate")
	f:SetSize(330, 74 + #ROWS * 26 + 96)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	f:SetBackdropColor(0.04, 0.04, 0.05, 0.96)
	f:SetBackdropBorderColor(0.8, 0.62, 0.15, 1)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	table.insert(UISpecialFrames, "RCRotationsColorMenu") -- Esc closes it

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Flash colors")
	local close = button(f, 22, 22, "X")
	close:SetPoint("TOPRIGHT", -8, -8)
	close:SetScript("OnClick", function()
		f:Hide()
	end)

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 14, -38)
	hint:SetPoint("RIGHT", -14, 0)
	hint:SetJustifyH("LEFT")
	hint:SetTextColor(0.7, 0.7, 0.7)
	hint:SetText("Click a color to change how that flash looks on your bars.")

	f.swatches = {}
	for i, row in ipairs(ROWS) do
		local y = -60 - (i - 1) * 26
		local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		label:SetPoint("TOPLEFT", 14, y - 4)
		label:SetText(row.label)
		local sw = CreateFrame("Button", nil, f, "BackdropTemplate")
		sw:SetSize(40, 20)
		sw:SetPoint("TOPRIGHT", -14, y)
		sw:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Buttons\\WHITE8x8",
			edgeSize = 1,
		})
		sw:SetBackdropBorderColor(0.9, 0.9, 0.9, 1)
		sw:SetScript("OnClick", function()
			pick(row.key)
		end)
		f.swatches[row.key] = sw
	end

	local y = -60 - #ROWS * 26 - 6
	local second = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	second:SetSize(24, 24)
	second:SetPoint("TOPLEFT", 10, y)
	local secondText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	secondText:SetPoint("LEFT", second, "RIGHT", 2, 0)
	secondText:SetText("Flash the second spell too")
	second:SetScript("OnClick", function(self)
		ns.db.flashSecond = self:GetChecked() and true or false
		redraw()
	end)
	f.secondCheck = second

	local pt = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pt:SetPoint("TOPLEFT", 14, y - 32)
	pt:SetText("Presets")
	for i, preset in ipairs(PRESETS) do
		local b = button(f, 72, 22, preset.name)
		b:SetPoint("TOPLEFT", 14 + (i - 1) * 76, y - 52)
		b:SetScript("OnClick", function()
			M.ApplyPreset(preset)
		end)
	end
	f:Hide()
	return f
end

function M.Refresh()
	if not frame then
		return
	end
	for key, sw in pairs(frame.swatches) do
		local r, g, b = ns.FlashColor(key)
		sw:SetBackdropColor(r or 1, g or 1, b or 1, 1)
	end
	frame.secondCheck:SetChecked(ns.db.flashSecond ~= false)
end

function M.Toggle()
	frame = frame or build()
	if frame:IsShown() then
		frame:Hide()
	else
		M.Refresh()
		frame:Show()
	end
end
