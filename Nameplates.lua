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
local unpack = unpack or table.unpack
ns.Plates = Plates

local HIDDEN = {
	nameplateShowEnemies = "1",
	-- see enemy names (and count them for multi-target) from further away;
	-- the game caps it at its own maximum
	nameplateMaxDistance = "60",
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

-- Name color: red for hostile, yellow for neutral, and purple once someone
-- else has tagged it (Blizzard uses grey, which reads as dead).
local TAPPED = { 0.72, 0.45, 1 }
Plates.TAPPED = TAPPED
local function nameColor(unit)
	if unit then
		local ok, denied = pcall(UnitIsTapDenied or function() end, unit)
		if ok and not secret(denied) and denied then
			return TAPPED[1], TAPPED[2], TAPPED[3]
		end
		if UnitSelectionColor then
			local ok2, r, g, b = pcall(UnitSelectionColor, unit)
			if ok2 and type(r) == "number" and not secret(r) and not secret(g) and not secret(b) then
				-- the game's grey for a tagged mob
				if math.abs(r - g) < 0.05 and math.abs(g - b) < 0.05 and r > 0.3 and r < 0.7 then
					return TAPPED[1], TAPPED[2], TAPPED[3]
				end
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

Plates.NameColor = nameColor

-- ElvUI places its name at the left end of its own health bar, and keeps
-- putting it back there. So while bars are hidden its name is faded out and
-- RCRotations shows the same name, in the same font with Blizzard's name color, centered on the
-- game's nameplate frame, which always sits right above the character.
-- Icons that stay visible on a faded plate (WoW Forever's quest objective and
-- loot icons ignore the plate's alpha). They sit at the ends of the health bar,
-- which is hidden, so they'd float far from the name: tuck them in beside our
-- name instead, and put them back when the option is off.
local function iconCandidates(plate, uf)
	local out, seen = {}, {}
	local function addRegions(f)
		if f.GetRegions then
			local ok, regions = pcall(function() return { f:GetRegions() } end)
			for _, r in ipairs(ok and regions or {}) do
				if not seen[r] then
					seen[r] = true
					out[#out + 1] = r
				end
			end
		end
	end
	local function walk(f, depth)
		if type(f) ~= "table" or not f.GetChildren then
			return
		end
		local ok, kids = pcall(function() return { f:GetChildren() } end)
		for _, k in ipairs(ok and kids or {}) do
			if type(k) == "table" and not seen[k] and k ~= uf and not (plate.rcrName and k == plate.rcrName.holder) then
				seen[k] = true
				out[#out + 1] = k
				addRegions(k)
				if depth < 2 then
					walk(k, depth + 1)
				end
			end
		end
	end
	walk(uf, 1)
	walk(plate, 2)
	-- ElvUI's quest icons (uf.QuestIcons: Default "!", Item, Loot, Skull, Chat)
	-- are laid out from the plate's edges; they go beside the name too
	-- and the game's loot / interact marker (SoftTargetFrame). Their side is
	-- fixed: items and loot on the left, the quest "!" and the rest on the right.
	local forced = {}
	local function force(r, side)
		if type(r) == "table" and r.SetPoint then
			forced[r] = side
			if not seen[r] then
				seen[r] = true
				out[#out + 1] = r
			end
		end
	end
	local q = type(uf.QuestIcons) == "table" and uf.QuestIcons or nil
	if q then
		force(q.Item, "left")
		force(q.Loot, "left")
		force(q.Default, "right")
		force(q.Skull, "right")
		force(q.Chat, "right")
	end
	force(uf.SoftTargetFrame, "left")
	if type(plate.UnitFrame) == "table" and plate.UnitFrame ~= uf then
		force(plate.UnitFrame.SoftTargetFrame, "left")
	end
	return out, forced
end

local function ignoresParentAlpha(r)
	if not r.IsIgnoringParentAlpha then
		return false
	end
	local ok, yes = pcall(r.IsIgnoringParentAlpha, r)
	-- can be hidden from addons on WoW Forever: comparing it is an error
	if not ok or secret(yes) then
		return false
	end
	return yes == true
end

-- which side of the plate an icon belongs on, from where the game put it
local function iconSide(plate, r, points, byCenter)
	if byCenter then
		local ok1, x = pcall(r.GetCenter, r)
		local ok2, px = pcall(plate.GetCenter, plate)
		if ok1 and ok2 and type(x) == "number" and type(px) == "number" and not secret(x) and not secret(px) then
			return x < px and "left" or "right"
		end
	end
	local p = points[1]
	if p then
		local rel = tostring(p[3] or "")
		if rel:find("LEFT") then
			return "left"
		elseif rel:find("RIGHT") then
			return "right"
		end
	end
	local ok1, x = pcall(r.GetCenter, r)
	local ok2, px = pcall(plate.GetCenter, plate)
	if ok1 and ok2 and type(x) == "number" and type(px) == "number" and not secret(x) and not secret(px) then
		return x < px and "left" or "right"
	end
	return "right"
end

-- line the icons up beside the name: left ones going left, right ones going
-- right, each next to the one before (only the icons showing take a place)
local function layoutIcons(plate, mine)
	local prev = { left = mine, right = mine }
	for _, r in ipairs(plate.rcrIcons or {}) do
		if r.rcrTucked then
			local side = r.rcrSide == "left" and "left" or "right"
			r.rcrTucking = true
			pcall(r.ClearAllPoints, r)
			if side == "left" then
				pcall(r.SetPoint, r, "RIGHT", prev.left, "LEFT", -3, 0)
			else
				pcall(r.SetPoint, r, "LEFT", prev.right, "RIGHT", 3, 0)
			end
			r.rcrTucking = nil
			local okS, shown = pcall(r.IsShown, r)
			if not okS or secret(shown) or shown ~= false then
				prev[side] = r
			end
		end
	end
end

local function tuckIcons(plate, uf, mine, hide)
	local list = plate.rcrIcons
	if hide then
		list = list or {}
		local candidates, forced = iconCandidates(plate, uf)
		for _, r in ipairs(candidates) do
			if not r.rcrSide and (forced[r] or ignoresParentAlpha(r)) and r.ClearAllPoints and r.SetPoint then
				-- where the game put it, to put it back later (may be unreadable)
				local points = {}
				local okN, n = pcall(r.GetNumPoints, r)
				if okN and not secret(n) and type(n) == "number" then
					for i = 1, n do
						local okP, a, b, c, d, e = pcall(r.GetPoint, r, i)
						if okP and not (secret(a) or secret(b) or secret(c) or secret(d) or secret(e)) then
							points[#points + 1] = { a, b, c, d, e }
						end
					end
				end
				r.rcrPoints = points
				r.rcrHome = r.GetParent and r:GetParent() or nil
				r.rcrSide = forced[r] or iconSide(plate, r, points)
				list[#list + 1] = r
				-- the game moves them back now and then: tuck them in again
				if hooksecurefunc then
					-- an icon appearing or going away: close up the row
					for _, m in ipairs({ "Show", "Hide" }) do
						if r[m] then
							hooksecurefunc(r, m, function()
								if r.rcrTucked and plate.rcrName and not plate.rcrLaying then
									plate.rcrLaying = true
									pcall(layoutIcons, plate, plate.rcrName)
									plate.rcrLaying = nil
								end
							end)
						end
					end
					hooksecurefunc(r, "SetPoint", function(self)
						if not self.rcrTucking and self.rcrTucked and plate.rcrName and not plate.rcrLaying then
							plate.rcrLaying = true
							pcall(layoutIcons, plate, plate.rcrName)
							plate.rcrLaying = nil
						end
					end)
				end
			end
		end
		plate.rcrIcons = list
		for _, r in ipairs(list) do
			r.rcrTucked = true
		end
		plate.rcrLaying = true
		pcall(layoutIcons, plate, mine)
		plate.rcrLaying = nil
	elseif list then
		for _, r in ipairs(list) do
			if r.rcrTucked then
				r.rcrTucked = nil
				r.rcrTucking = true
				pcall(r.ClearAllPoints, r)
				local points = r.rcrPoints or {}
				for _, p in ipairs(points) do
					pcall(r.SetPoint, r, unpack(p))
				end
				if #points == 0 and r.rcrHome then
					-- couldn't read where it was: center it on its own frame;
					-- the plate addon lays it out again on its next update
					pcall(r.SetPoint, r, "CENTER", r.rcrHome, "CENTER", 0, 0)
				end
				r.rcrTucking = nil
			end
		end
	end
end

local function ownName(plate, uf, hide, unit)
	local theirs = (type(uf.Name) == "table" and uf.Name) or (type(uf.name) == "table" and uf.name) or nil
	local mine = plate.rcrName
	if not secret(hide) and not hide then
		if mine then
			mine:Hide()
		end
		fade(theirs, false)
		tuckIcons(plate, uf, mine, false)
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
	-- the name can be hidden from addons in combat; SetText still takes it
	local text
	if unit and UnitName then
		local okN, n = pcall(UnitName, unit)
		if okN then
			text = n
		end
	end
	if rawequal(text, nil) and theirs and theirs.GetText then
		local okT, t = pcall(theirs.GetText, theirs)
		if okT then
			text = t
		end
	end
	if rawequal(text, nil) then
		text = ""
	end
	if not pcall(mine.SetText, mine, text) then
		mine:SetText("")
	end
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
	local okT, errT = pcall(tuckIcons, plate, uf, mine, true)
	if not okT then
		Plates.lastError = tostring(errT)
	end
end

-- Blizzard may set the plate's alpha again (range, target changes): put ours back.
local function keepFaded(uf)
	if uf.rcrHooked or not hooksecurefunc or not uf.SetAlpha then
		return
	end
	uf.rcrHooked = true
	hooksecurefunc(uf, "SetAlpha", function(self)
		if self.rcrSetting then
			return
		end
		local h = self.rcrHide
		if rawequal(h, nil) or (not secret(h) and not h) then
			return
		end
		self.rcrSetting = true
		fade(self, h)
		self.rcrSetting = nil
	end)
end

local function styleBar(plate, hide, unit)
	if type(plate) ~= "table" then
		return
	end
	local blizz = plate.UnitFrame
	local uf = plate.unitFrame
	if type(uf) == "table" and uf ~= blizz then
		-- a nameplate addon (ElvUI, Plater...) draws on top of the plate
		for _, bar in ipairs(healthBars(plate)) do
			fade(bar, hide)
		end
		for _, t in ipairs(addonExtras(uf)) do
			fade(t, hide)
		end
		ownName(plate, uf, hide, unit)
		return
	end
	if type(blizz) == "table" then
		-- Blizzard's plate: the whole thing fades (bar, level, health text, icons,
		-- whatever layout this client uses) and RCRotations shows the name
		-- above the character instead.
		blizz.rcrHide = hide
		keepFaded(blizz)
		blizz.rcrSetting = true
		fade(blizz, hide)
		blizz.rcrSetting = nil
		ownName(plate, blizz, hide, unit)
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
		pcall(styleBar, plate, on() and unit and hostileUnit(unit), unit)
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
		ns.db.plateBackup = ns.db.plateBackup or {}
		-- remember your own value of each setting first (also ones added later)
		for name in pairs(HIDDEN) do
			if ns.db.plateBackup[name] == nil then
				ns.db.plateBackup[name] = getCVar(name)
			end
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

-- /rcr platecheck: what the addon sees on your target's nameplate (for fixing
-- nameplate layouts it doesn't know yet)
function Plates.Check()
	local say = ns.Print or print
	local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, "target")
	if not ok or type(plate) ~= "table" then
		plate = nil
		-- no plate for the target: use a nearby one, preferring one with quest icons
		local okL, plates = pcall(C_NamePlate.GetNamePlates)
		local first
		for _, p in ipairs(okL and type(plates) == "table" and plates or {}) do
			first = first or p
			local f = (type(p.unitFrame) == "table" and p.unitFrame) or p.UnitFrame
			local q = type(f) == "table" and f.QuestIcons
			local okS, shown = pcall(function() return q and q:IsShown() end)
			if okS and shown then
				plate = p
				break
			end
		end
		plate = plate or first
		say(("platecheck: no plate for your target, checking a nearby one (%d nameplates around)"):format(okL and type(plates) == "table" and #plates or 0))
		if not plate then
			say("platecheck: no nameplates around at all. Stand near some enemies and try again.")
			return
		end
	end
	local function nameOf(f)
		if type(f) ~= "table" then
			return tostring(f)
		end
		local okN, n = pcall(f.GetName, f)
		if okN and n then
			return n
		end
		local okD, d = pcall(f.GetDebugName, f)
		return okD and d or "?"
	end
	local function where(r)
		local okP, p1, rel, p2, x, y = pcall(r.GetPoint, r, 1)
		if not okP or rawequal(p1, nil) then
			return "no anchor"
		end
		if secret(p1) or secret(rel) or secret(x) then
			return "hidden"
		end
		return ("%s %s %s %s %s"):format(tostring(p1), nameOf(rel), tostring(p2), tostring(x), tostring(y))
	end
	local uf = plate.unitFrame
	local blizz = plate.UnitFrame
	local ver = "?"
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		local okV, v = pcall(C_AddOns.GetAddOnMetadata, addonName, "Version")
		if okV and v then
			ver = v
		end
	end
	say(("platecheck (RCRotations %s): option %s, plate %s, addon frame %s, our name %s, icons tucked %d"):format(
		ver, on() and "ON" or "off", nameOf(plate), type(uf) == "table" and uf ~= blizz and nameOf(uf) or "none (Blizzard)",
		plate.rcrName and (plate.rcrName:IsShown() and "shown" or "hidden") or "none", plate.rcrIcons and #plate.rcrIcons or 0))
	local frame = (type(uf) == "table" and uf ~= blizz) and uf or blizz
	local q = type(frame) == "table" and frame.QuestIcons
	if type(q) == "table" then
		say("QuestIcons: " .. where(q))
		for _, k in ipairs({ "Default", "Item", "Loot", "Skull", "Chat" }) do
			local r = q[k]
			if type(r) == "table" then
				local okS, shown = pcall(r.IsShown, r)
				say(("  %s: %s, side %s, tucked %s, at %s"):format(k, okS and (shown and "shown" or "hidden") or "?",
					tostring(r.rcrSide), tostring(r.rcrTucked), where(r)))
			end
		end
	else
		say("no QuestIcons on this plate")
	end
	if type(frame) == "table" then
		local okK, kids = pcall(function() return { frame:GetChildren() } end)
		local names = {}
		for _, k in ipairs(okK and kids or {}) do
			local okS, shown = pcall(k.IsShown, k)
			if okS and shown then
				names[#names + 1] = nameOf(k)
			end
		end
		say("shown parts: " .. table.concat(names, ", "))
	end
	say("last error: " .. tostring(Plates.lastError or "none"))
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
				pcall(styleBar, plate, on() and hostileUnit(unit), unit)
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
