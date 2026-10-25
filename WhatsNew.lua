-- "What's new" popup at login (changelog + Workshop app link) and the
-- copy-the-link dialog used by the menu.
--
-- WoW can't open web pages or write to the clipboard for addons, so the link
-- is shown in a box that's already selected: press Ctrl+C, then paste it in a
-- web browser. The dialog closes itself after Ctrl+C.
--
-- The popup shows at every login until "Don't show again for this version" is
-- ticked; it comes back for the next update (not for the automatic nightly
-- rotation updates). /rcr news opens it anytime.
local addonName, ns = ...

local PANEL = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local GOLD = { 1, 0.82, 0.2 }

local function currentVersion()
	local log = ns.CHANGELOG
	return type(log) == "table" and log[1] and log[1].version or "?"
end

local function db()
	if type(RCRotationsDB) ~= "table" then
		RCRotationsDB = {}
	end
	return RCRotationsDB
end

local function inCombat()
	return InCombatLockdown and InCombatLockdown()
end

local function goldButton(parent, w, h, text, big)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h)
	b:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 10,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	b:SetBackdropColor(0.28, 0.20, 0.04, 0.95)
	b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
	local fs = b:CreateFontString(nil, "OVERLAY", big and "GameFontNormal" or "GameFontNormalSmall")
	fs:SetPoint("CENTER", 0, 0)
	fs:SetText(text)
	fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	b.label = fs
	b:SetScript("OnEnter", function(self)
		self:SetBackdropColor(0.40, 0.29, 0.06, 0.95)
		self.label:SetTextColor(1, 1, 1)
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropColor(0.28, 0.20, 0.04, 0.95)
		self.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	end)
	return b
end
ns.WhatsNewButton = goldButton

local function panel(name, w, h, title)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	f:SetSize(w, h)
	f:SetPoint("CENTER", 0, 60)
	f:SetFrameStrata("DIALOG")
	f:SetBackdrop(PANEL)
	f:SetBackdropColor(0.03, 0.03, 0.03, 0.97)
	f:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetClampedToScreen(true)
	local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	t:SetPoint("TOP", 0, -14)
	t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	t:SetText(title)
	f.title = t
	local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	x:SetPoint("TOPRIGHT", -2, -2)
	if UISpecialFrames and name then
		tinsert(UISpecialFrames, name)
	end
	f:Hide()
	if ns.RegisterWindow then
		ns.RegisterWindow(f)
	end
	return f
end

-- ------------------------------------------------------------ copy dialog
local copy
function ns.ShowCopyLink(url, titleText)
	url = url or ns.WORKSHOP_URL
	if not copy then
		copy = panel("RCRotationsCopyLink", 480, 128, "")
		local box = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
		box:SetSize(420, 24)
		box:SetPoint("TOP", 0, -46)
		box:SetAutoFocus(false)
		box:SetFontObject("GameFontHighlight")
		box:SetScript("OnTextChanged", function(self, user)
			if user then
				self:SetText(copy.url)
				self:HighlightText()
			end
		end)
		box:SetScript("OnEditFocusGained", function(self)
			self:HighlightText()
		end)
		box:SetScript("OnEscapePressed", function()
			copy:Hide()
		end)
		box:SetScript("OnKeyDown", function(self, key)
			if key == "C" and IsControlKeyDown and IsControlKeyDown() then
				local function done()
					copy:Hide()
					if ns.Print then
						ns.Print(ns.T("NEWS_COPIED"))
					end
				end
				if C_Timer and C_Timer.After then
					C_Timer.After(0.1, done)
				else
					done()
				end
			end
		end)
		copy.box = box
		local hint = copy:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		hint:SetPoint("TOP", box, "BOTTOM", 0, -10)
		hint:SetText(ns.T("NEWS_COPY_HINT"))
		copy:SetScript("OnShow", function(self)
			self.box:SetText(self.url or "")
			self.box:SetCursorPosition(0)
			self.box:SetFocus()
			self.box:HighlightText()
		end)
		copy:SetScript("OnHide", function(self)
			self.box:ClearFocus()
		end)
	end
	copy.url = url
	copy.title:SetText(titleText or ns.T("NEWS_COPY_TITLE"))
	if copy:IsShown() then
		copy:Hide()
	end
	copy:Show()
	return copy
end

-- ------------------------------------------------------------ what's new
local news

local function changelogText()
	local lines = {}
	for i, v in ipairs(ns.CHANGELOG or {}) do
		if i > 1 then
			lines[#lines + 1] = " "
		end
		lines[#lines + 1] = "|cffffd133" .. ns.T("NEWS_VERSION"):format(v.version) .. "|r"
		for _, item in ipairs(v.items or {}) do
			lines[#lines + 1] = "|cffffd133•|r " .. item
		end
	end
	return table.concat(lines, "\n")
end

local function build()
	news = panel("RCRotationsWhatsNew", 560, 470, "")

	-- changelog, scrollable
	local scroll = CreateFrame("ScrollFrame", "RCRotationsWhatsNewScroll", news, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 18, -44)
	scroll:SetPoint("BOTTOMRIGHT", -36, 150)
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(500, 10)
	scroll:SetScrollChild(body)
	local text = body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("TOPLEFT", 0, 0)
	text:SetWidth(500)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetWordWrap(true)
	if text.SetSpacing then
		text:SetSpacing(3)
	end
	news.text, news.body = text, body

	-- Workshop app
	local app = CreateFrame("Frame", nil, news, "BackdropTemplate")
	app:SetPoint("BOTTOMLEFT", 14, 48)
	app:SetPoint("BOTTOMRIGHT", -14, 48)
	app:SetHeight(92)
	app:SetBackdrop(PANEL)
	app:SetBackdropColor(0.08, 0.06, 0.02, 0.95)
	app:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
	local appTitle = app:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	appTitle:SetPoint("TOPLEFT", 14, -12)
	appTitle:SetText(ns.T("OPT_CARD_WORKSHOP"))
	local appText = app:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	-- fixed position and size: the Forever client can freeze when it has to
	-- measure wrapped text (text anchored to text, or auto-height text)
	appText:SetPoint("TOPLEFT", 14, -34)
	appText:SetSize(300, 44)
	appText:SetJustifyH("LEFT")
	appText:SetJustifyV("TOP")
	appText:SetWordWrap(true)
	appText:SetText(ns.T("NEWS_APP_TEXT"))
	local appBtn = goldButton(app, 190, 34, ns.T("NEWS_COPY_APP"), true)
	appBtn:SetPoint("RIGHT", -14, 0)
	appBtn:SetScript("OnClick", function()
		ns.ShowCopyLink(ns.WORKSHOP_URL)
	end)
	news.appBtn = appBtn

	-- bottom: don't show again + close
	local check = CreateFrame("CheckButton", "RCRotationsWhatsNewHide", news, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("BOTTOMLEFT", 14, 14)
	local label = news:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 4, 0)
	label:SetText(ns.T("NEWS_DONT_SHOW"))
	check:SetScript("OnClick", function(self)
		db().newsHidden = self:GetChecked() and currentVersion() or nil
	end)
	news.check = check
	local close = goldButton(news, 100, 26, CLOSE or "Close")
	close:SetPoint("BOTTOMRIGHT", -14, 14)
	close:SetScript("OnClick", function()
		news:Hide()
	end)
end

function ns.ShowWhatsNew()
	if not news then
		build()
	end
	news.title:SetText(ns.T("NEWS_TITLE"))
	news.text:SetText(changelogText())
	-- Estimate the height instead of measuring the text (measuring wrapped
	-- text can freeze the Forever client): ~80 characters per line, 16px a line.
	local lines = 0
	for _, v in ipairs(ns.CHANGELOG or {}) do
		lines = lines + 2
		for _, item in ipairs(v.items or {}) do
			lines = lines + math.max(1, math.ceil(#item / 80))
		end
	end
	local h = lines * 16 + 16
	news.text:SetHeight(h)
	news.body:SetHeight(h)
	news.check:SetChecked(db().newsHidden == currentVersion())
	news:Show()
	return news
end

-- Show at login (never in combat), unless hidden for this version.
local function shouldShow()
	return db().newsHidden ~= currentVersion() and ns.CHANGELOG and ns.CHANGELOG[1] ~= nil
end
ns.WhatsNewDue = shouldShow

local waiter = CreateFrame("Frame")
waiter:RegisterEvent("PLAYER_LOGIN")
waiter:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		local function later()
			if not shouldShow() then
				return
			end
			if inCombat() then
				self:RegisterEvent("PLAYER_REGEN_ENABLED")
				return
			end
			ns.ShowWhatsNew()
		end
		if C_Timer and C_Timer.After then
			C_Timer.After(4, later)
		else
			later()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		if shouldShow() then
			ns.ShowWhatsNew()
		end
	end
end)
