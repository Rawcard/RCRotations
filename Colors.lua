local addonName, ns = ...

-- Flash colors window (/rcr colors, or the button on Options > Extra > Colors):
-- pick a kind of action-bar flash, then a color from the palette or the
-- red / green / blue sliders, or apply a preset scheme.
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

-- the row whose color the palette and sliders change
local selected = "next"

-- a palette of ready colors (RC-SpellFlash's plus a few more)
local PALETTE = {
	{ 1, 1, 0 }, { 1, 0.5, 0 }, { 1, 0, 0 }, { 1, 0.08, 0.5 }, { 1, 0, 1 }, { 0.8, 0, 1 }, { 0.5, 0.2, 1 }, { 0.2, 0.55, 1 },
	{ 0, 0.5, 1 }, { 0, 0.9, 1 }, { 0, 1, 1 }, { 0, 1, 0.6 }, { 0, 1, 0 }, { 0.6, 1, 0.2 }, { 1, 0.85, 0.5 }, { 1, 1, 1 },
}
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
	f:SetSize(330, 74 + #ROWS * 26 + 2 * 26 + 8 + 3 * 22 + 6 + 100)
	f:SetPoint("CENTER", 380, 0)
	-- above the options window, so nothing in it covers these buttons
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetToplevel(true)
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
	hint:SetText("Pick a flash, then click a color below or drag the sliders.")

	f.swatches = {}
	f.highlights = {}
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
			selected = row.key
			M.Refresh()
		end)
		-- clicking the label selects the row too
		local hit = CreateFrame("Button", nil, f)
		hit:SetPoint("TOPLEFT", 10, y + 2)
		hit:SetPoint("RIGHT", sw, "LEFT", -6, 0)
		hit:SetHeight(24)
		hit:SetScript("OnClick", function()
			selected = row.key
			M.Refresh()
		end)
		local hl = f:CreateTexture(nil, "BACKGROUND")
		hl:SetPoint("TOPLEFT", 8, y + 3)
		hl:SetPoint("RIGHT", -8, 0)
		hl:SetHeight(26)
		hl:SetColorTexture(1, 0.82, 0.2, 0.18)
		hl:Hide()
		f.swatches[row.key] = sw
		f.highlights[row.key] = hl
	end

	local y = -60 - #ROWS * 26 - 6
	-- palette
	local SW = 34
	for i, c in ipairs(PALETTE) do
		local col, rowN = (i - 1) % 8, math.floor((i - 1) / 8)
		local p = CreateFrame("Button", nil, f, "BackdropTemplate")
		p:SetSize(SW, 22)
		p:SetPoint("TOPLEFT", 14 + col * (SW + 4), y - rowN * 26)
		p:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		p:SetBackdropColor(c[1], c[2], c[3], 1)
		p:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
		p:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(1, 1, 1, 1) end)
		p:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.15, 0.15, 0.15, 1) end)
		p:SetScript("OnClick", function()
			setColor(selected, c[1], c[2], c[3])
		end)
		f.palette = f.palette or {}
		f.palette[i] = p
	end
	y = y - 2 * 26 - 8
	-- red / green / blue sliders for an exact color
	f.sliders = {}
	for i, name in ipairs({ "Red", "Green", "Blue" }) do
		local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("TOPLEFT", 14, y - (i - 1) * 22 - 3)
		label:SetText(name)
		local sl = CreateFrame("Slider", nil, f, "BackdropTemplate")
		sl:SetOrientation("HORIZONTAL")
		sl:SetSize(200, 12)
		sl:SetPoint("TOPLEFT", 64, y - (i - 1) * 22 - 3)
		sl:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		sl:SetBackdropColor(0.12, 0.12, 0.12, 1)
		sl:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		local thumb = sl:CreateTexture(nil, "OVERLAY")
		thumb:SetSize(8, 16)
		thumb:SetColorTexture(1, 0.82, 0.2, 1)
		sl:SetThumbTexture(thumb)
		sl:SetMinMaxValues(0, 255)
		sl:SetValueStep(1)
		sl:SetObeyStepDuringDrag(true)
		local val = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		val:SetPoint("LEFT", sl, "RIGHT", 8, 0)
		sl.valueText = val
		sl:SetScript("OnValueChanged", function(self, v)
			self.valueText:SetText(math.floor(v + 0.5))
			if f.refreshing then
				return
			end
			local r, g, b = ns.FlashColor(selected)
			local n = (math.floor(v + 0.5)) / 255
			if i == 1 then r = n elseif i == 2 then g = n else b = n end
			setColor(selected, r, g, b)
		end)
		f.sliders[i] = sl
	end
	y = y - 3 * 22 - 6
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
		b:RegisterForClicks("LeftButtonUp")
		b:SetScript("OnClick", function()
			M.ApplyPreset(preset)
			if ns.Print then
				ns.Print("flash colors: " .. preset.name)
			end
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
		frame.highlights[key]:SetShown(key == selected)
		sw:SetBackdropBorderColor(key == selected and 1 or 0.6, key == selected and 0.82 or 0.6, key == selected and 0.2 or 0.6, 1)
	end
	local r, g, b = ns.FlashColor(selected)
	frame.refreshing = true
	for i, v in ipairs({ r or 1, g or 1, b or 1 }) do
		frame.sliders[i]:SetValue(math.floor(v * 255 + 0.5))
		frame.sliders[i].valueText:SetText(math.floor(v * 255 + 0.5))
	end
	frame.refreshing = false
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
