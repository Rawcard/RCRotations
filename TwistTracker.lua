local addonName, ns = ...

-- Seal twist tracker (WoW Forever Paladin): pops up once you have Unsealed
-- Wrath. Shows the seal you have, the echoes it has stored (from your swings),
-- and "SWAP" on the swing to change seal. It has its own lock bar: unlocked,
-- drag it by the bar and change the twist pattern; locked, only the tracker
-- shows. /rcr twist turns it off and on.
ns.Twist = ns.Twist or {}
local W = ns.Twist

local UNSEALED_WRATH = 1310735
local ECHO_OF_SEAL = { SealCommand = 1311703, SealRighteousness = 1311704 }
local OTHER = { SealCommand = "SealRighteousness", SealRighteousness = "SealCommand" }
local SEAL_LABEL = { SealCommand = "Command", SealRighteousness = "Righteousness" }

local function call(fn, ...)
	if not fn then
		return nil
	end
	local ok, a, b = pcall(fn, ...)
	if ok then
		return a, b
	end
	return nil
end

function W.Specced()
	if ns.CLASSTOKEN ~= "PALADIN" or ns.GAME ~= "forever" then
		return false
	end
	if IsPlayerSpell and call(IsPlayerSpell, UNSEALED_WRATH) == true then
		return true
	end
	return ns.API and ns.API.Known and ns.API.Known(UNSEALED_WRATH) == true or false
end

function W.Enabled()
	return not (ns.db and ns.db.showTwist == false)
end

local frame

local function seal(key)
	return ns.Spell and ns.Spell.Paladin and ns.Spell.Paladin[key]
end

local function savePos()
	local point, _, rel, x, y = frame:GetPoint(1)
	ns.db.twistPos = { point or "CENTER", rel or "CENTER", x or 0, y or 0 }
end

local function placeFromDb()
	frame:ClearAllPoints()
	local p = ns.db and ns.db.twistPos
	if type(p) == "table" then
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
end

local function applyLock()
	local locked = ns.db.twistLocked ~= false
	frame.bar:SetShown(not locked)
	frame.lockText:SetText(locked and "Unlock" or "Lock")
end

local function build()
	local f = CreateFrame("Frame", "RCRotationsTwist", UIParent, "BackdropTemplate")
	f:SetSize(176, 46)
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	f:SetBackdropColor(0, 0, 0, 0.55)
	f:SetBackdropBorderColor(0.8, 0.62, 0.15, 0.9)

	-- the seal you have
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(38, 38)
	icon:SetPoint("LEFT", 4, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon = icon

	local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
	f.name = name

	-- three echo pips
	f.pips = {}
	for i = 1, 3 do
		local p = f:CreateTexture(nil, "ARTWORK")
		p:SetSize(16, 10)
		p:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6 + (i - 1) * 20, 2)
		p:SetColorTexture(0.25, 0.25, 0.25, 1)
		f.pips[i] = p
	end

	local swap = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	swap:SetPoint("RIGHT", -8, 0)
	swap:SetTextColor(0.3, 1, 0.3)
	f.swap = swap

	local pattern = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	pattern:SetPoint("BOTTOMRIGHT", -6, 3)
	pattern:SetTextColor(0.7, 0.7, 0.7)
	f.pattern = pattern

	-- the lock bar: drag handle + pattern + lock button, shown while unlocked
	local bar = CreateFrame("Frame", nil, f, "BackdropTemplate")
	bar:SetHeight(18)
	bar:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 2)
	bar:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 2)
	bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	bar:SetBackdropColor(0.12, 0.1, 0.06, 0.95)
	bar:SetBackdropBorderColor(0.8, 0.62, 0.15, 1)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		f:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		savePos()
	end)
	local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	title:SetPoint("LEFT", 6, 0)
	title:SetText("Seal twist")
	f.bar = bar

	local function smallButton(text, w)
		local b = CreateFrame("Button", nil, bar)
		b:SetSize(w, 16)
		local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("CENTER")
		fs:SetText(text)
		b.text = fs
		return b
	end
	local lock = smallButton("Lock", 44)
	lock:SetPoint("RIGHT", -4, 0)
	lock:SetScript("OnClick", function()
		ns.db.twistLocked = not (ns.db.twistLocked ~= false)
		applyLock()
	end)
	f.lockText = lock.text
	local pat = smallButton("3/1", 34)
	pat:SetPoint("RIGHT", lock, "LEFT", -4, 0)
	pat:SetScript("OnClick", function()
		W.CyclePattern()
	end)
	f.patButton = pat

	f:Hide()
	return f
end

function W.CyclePattern()
	local list = ns.API.TWIST_PATTERNS
	local _, _, now = ns.API.TwistPattern()
	local nextOne = list[1]
	for i, p in ipairs(list) do
		if p == now then
			nextOne = list[i % #list + 1]
		end
	end
	ns.db.twistPattern = nextOne
	if ns.Print then
		ns.Print("seal twist pattern: " .. nextOne .. " (Command swings / Righteousness swings)")
	end
	if ns.InvalidateTick then
		ns.InvalidateTick()
	end
	W.Refresh()
end

function W.Unlock()
	if not frame then
		return
	end
	ns.db.twistLocked = false
	applyLock()
end

function W.Refresh()
	if not (ns.db and ns.API) then
		return
	end
	local want = W.Enabled() and (W.Specced() or W.preview)
	if not want then
		if frame then
			frame:Hide()
		end
		return
	end
	if not frame then
		frame = build()
		placeFromDb()
		applyLock()
	end
	frame:Show()
	applyLock()
	local cmd, sor, name = ns.API.TwistPattern()
	frame.pattern:SetText(name)
	frame.patButton.text:SetText(name)
	local current = ns.API.CurrentSeal and ns.API.CurrentSeal()
	if W.preview and not W.Specced() then
		-- preview before you have Unsealed Wrath: a made-up moment, so you can
		-- place and look at the tracker (2 Command echoes, then SWAP flashing)
		local t = GetTime and GetTime() or 0
		local phase = math.floor(t / 1.5) % 4
		frame.icon:SetTexture(seal("SealCommand") and C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, seal("SealCommand")) or 134400)
		frame.icon:SetDesaturated(false)
		frame.name:SetText("Command (preview)")
		for i, p in ipairs(frame.pips) do
			p:SetShown(i <= cmd)
			p:SetColorTexture(i <= phase and 0.35 or 0.25, i <= phase and 0.65 or 0.25, i <= phase and 1 or 0.25, 1)
		end
		frame.swap:SetText(phase >= cmd and "SWAP" or "")
		return
	end
	local id = current and seal(current)
	if id then
		local tex = C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, id)
		frame.icon:SetTexture(tex or 134400)
		frame.icon:SetDesaturated(false)
		frame.name:SetText(SEAL_LABEL[current] or (ns.API.SpellName(id) or ""))
	else
		frame.icon:SetTexture(seal("SealCommand") and C_Spell and C_Spell.GetSpellTexture and call(C_Spell.GetSpellTexture, seal("SealCommand")) or 134400)
		frame.icon:SetDesaturated(true)
		frame.name:SetText("No seal")
	end
	-- echoes stored, out of the swings the pattern wants on this seal
	local echoId = current and ECHO_OF_SEAL[current]
	local stacks = echoId and ns.API.EchoStacks(echoId) or 0
	local goal = current == "SealRighteousness" and sor or cmd
	for i, p in ipairs(frame.pips) do
		p:SetShown(i <= math.max(goal, 1))
		if i <= stacks then
			if current == "SealRighteousness" then
				p:SetColorTexture(1, 0.85, 0.2, 1)
			else
				p:SetColorTexture(0.35, 0.65, 1, 1)
			end
		else
			p:SetColorTexture(0.25, 0.25, 0.25, 1)
		end
	end
	-- the swing to change seal
	local other = current and OTHER[current]
	local ready = other and seal(other) and ns.API.TwistReady and ns.API.TwistReady(seal(other))
	frame.swap:SetText(ready and "SWAP" or "")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "PLAYER_TALENT_UPDATE")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_SKILL_LINE")
pcall(ev.RegisterEvent, ev, "CHARACTER_POINTS_CHANGED")
ev:SetScript("OnEvent", function()
	pcall(W.Refresh)
end)
local since = 0
ev:SetScript("OnUpdate", function(_, elapsed)
	since = since + (elapsed or 0)
	if since >= 0.1 then
		since = 0
		pcall(W.Refresh)
	end
end)
