-- Keeps the addon's windows side by side instead of on top of each other.
--
-- The main menu (/rcr) is the "root". Any other RCRotations window opened while
-- it's up (rotation picker, import, What's new, copy link) lines up to its right,
-- top edges level, in the order they were opened. If the whole row doesn't fit
-- on the screen, the row slides left and, if needed, everything is scaled down a
-- little until it fits. Closing a window closes the gap; closing the main menu
-- closes them all. Dragging any window in the row moves the whole row.
--
-- Without the main menu open, the first window shown is the root (What's new at
-- login, for example) and works the same way.
local addonName, ns = ...

local GAP, MARGIN = 8, 8

local menu -- the main options frame
local root -- the window everything lines up beside
local kids = {} -- docked windows, in the order they were opened
local registered = {}
local laying = false

local function shown(f)
	return f and f.IsShown and f:IsShown()
end

local function indexOf(f)
	for i, k in ipairs(kids) do
		if k == f then
			return i
		end
	end
end

local function base(f)
	return f.rcrBaseScale or 1
end

local function uiScale()
	return UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
end

-- position of a frame's top-left corner in UIParent units
local function topLeft(f)
	local l, t = f.GetLeft and f:GetLeft(), f.GetTop and f:GetTop()
	if not l or not t then
		return nil
	end
	local k = (f.GetEffectiveScale and f:GetEffectiveScale() or 1) / uiScale()
	return l * k, t * k
end

local function layout()
	if laying or not shown(root) then
		return
	end
	laying = true
	local row = { root }
	for _, k in ipairs(kids) do
		if shown(k) then
			row[#row + 1] = k
		end
	end
	local screenW = UIParent:GetWidth() or 1024
	local screenH = UIParent:GetHeight() or 768
	local totalW, maxH = GAP * (#row - 1), 0
	for _, f in ipairs(row) do
		totalW = totalW + (f:GetWidth() or 0) * base(f)
		maxH = math.max(maxH, (f:GetHeight() or 0) * base(f))
	end
	local s = 1
	if totalW > 0 then
		s = math.min(s, (screenW - 2 * MARGIN) / totalW)
	end
	if maxH > 0 then
		s = math.min(s, (screenH - 2 * MARGIN) / maxH)
	end
	s = math.max(0.4, s)

	local left, top = topLeft(root)
	if not left then
		left = (screenW - totalW * s) / 2
		top = (screenH + maxH * s) / 2
	end
	if left + totalW * s > screenW - MARGIN then
		left = screenW - MARGIN - totalW * s
	end
	if left < MARGIN then
		left = MARGIN
	end
	if top > screenH - MARGIN then
		top = screenH - MARGIN
	end
	if top - maxH * s < MARGIN then
		top = MARGIN + maxH * s
	end

	local rs = base(root) * s
	root:SetScale(rs)
	root:ClearAllPoints()
	root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / rs, top / rs)
	local prev = root
	for i = 2, #row do
		local f = row[i]
		local fs = base(f) * s
		f:SetScale(fs)
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", prev, "TOPRIGHT", GAP / fs, 0)
		prev = f
	end
	laying = false
end
ns.WindowsLayout = layout

local function undock(f)
	local i = indexOf(f)
	if i then
		table.remove(kids, i)
	end
	if f.SetScale then
		f:SetScale(base(f))
	end
end

-- A window was shown: line it up.
local function onShow(f)
	if f == menu then
		-- the menu takes over: whatever was open lines up beside it
		local adopt = {}
		if shown(root) and root ~= menu then
			adopt[#adopt + 1] = root
		end
		for _, k in ipairs(kids) do
			if shown(k) and k ~= menu then
				adopt[#adopt + 1] = k
			end
		end
		root, kids = menu, adopt
		layout()
		return
	end
	if not shown(root) or root == f then
		root = f
		layout()
		return
	end
	if not indexOf(f) then
		kids[#kids + 1] = f
	end
	layout()
end

local function onHide(f)
	if f == root then
		-- closing the main window closes everything beside it
		local list = kids
		kids = {}
		root = nil
		for _, k in ipairs(list) do
			if shown(k) then
				k:Hide()
			end
			if k.SetScale then
				k:SetScale(base(k))
			end
		end
		if f.SetScale then
			f:SetScale(base(f))
		end
		return
	end
	undock(f)
	layout()
end

local function hook(f)
	if registered[f] then
		return
	end
	registered[f] = true
	f.rcrBaseScale = f.GetScale and f:GetScale() or 1
	f:HookScript("OnShow", onShow)
	f:HookScript("OnHide", onHide)
	-- dragging any window in the row moves the whole row
	if f.RegisterForDrag then
		f:SetScript("OnDragStart", function(self)
			local mover = (self ~= root and indexOf(self) and shown(root)) and root or self
			self.rcrMover = mover
			mover:StartMoving()
		end)
		f:SetScript("OnDragStop", function(self)
			local mover = self.rcrMover or self
			self.rcrMover = nil
			mover:StopMovingOrSizing()
		end)
	end
	if hooksecurefunc then
		hooksecurefunc(f, "StopMovingOrSizing", function()
			layout()
		end)
	end
	if shown(f) then
		onShow(f)
	end
end

function ns.RegisterMenu(f)
	if not f then
		return
	end
	menu = f
	hook(f)
end

function ns.RegisterWindow(f)
	if f then
		hook(f)
	end
end
