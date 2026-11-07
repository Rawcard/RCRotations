local addonName, ns = ...

-- Range detector: how many yards to the target, as a band ("20-25 yd").
-- WoW never hands addons the exact distance to an enemy, so the band comes
-- from yes/no checks the game does answer: "is this spell in range?" for
-- every ranged spell in the spellbook, a few range-check items, and the
-- inspect / trade / duel distances. Each answer narrows the band.
ns.Range = ns.Range or {}
local R = ns.Range

local MELEE = 5

-- Items whose use range is fixed (the set LibRangeCheck uses). The game
-- answers for an item you don't own; items this client doesn't have are
-- just skipped. More checkpoints = a tighter range.
local HARM_ITEMS = {
	{ 37727, 2 }, -- Ruby Acorn
	{ 42732, 3 }, -- Everfrost Razor
	{ 129055, 4 }, -- Shoe Shine Kit
	{ 8149, 5 }, -- Voodoo Charm
	{ 63427, 5 }, -- Worgsaw
	{ 61323, 7 }, -- Ruby Seeds
	{ 34368, 8 }, -- Attuned Crystal Cores
	{ 33278, 8 }, -- Burning Torch
	{ 32321, 10 }, -- Sparrowhawk Net
	{ 33069, 15 }, -- Sturdy Rope
	{ 10645, 20 }, -- Gnomish Death Ray
	{ 24268, 25 }, -- Netherweave Net
	{ 41509, 25 }, -- Frostweave Net
	{ 835, 30 }, -- Large Rope Net
	{ 7734, 30 }, -- Six Demon Bag
	{ 34191, 30 }, -- Handful of Snowflakes
	{ 24269, 35 }, -- Heavy Netherweave Net
	{ 18904, 35 }, -- Zorbin's Ultra-Shrinker
	{ 140786, 38 }, -- Ley Spider Eggs
	{ 28767, 40 }, -- The Decapitator
	{ 23836, 45 }, -- Goblin Rocket Launcher
	{ 116139, 50 }, -- Haunting Memento
	{ 74637, 55 }, -- Kiryn's Poison Vial
	{ 32825, 60 }, -- Soul Cannon
	{ 37887, 60 }, -- Seeds of Nature's Wrath
	{ 41265, 70 }, -- Eyesore Blaster
	{ 35278, 80 }, -- Reinforced Net
	{ 133925, 90 }, -- Fel Lash
	{ 33119, 100 }, -- Malister's Frost Wand
}
local HELP_ITEMS = {
	{ 37727, 5 }, -- Ruby Acorn
	{ 34368, 8 }, -- Attuned Crystal Cores
	{ 32321, 10 }, -- Sparrowhawk Net
	{ 1251, 15 }, -- Linen Bandage
	{ 21519, 20 }, -- Mistletoe
	{ 31463, 25 }, -- Zezzak's Shard
	{ 1180, 30 }, -- Scroll of Stamina
	{ 18904, 35 }, -- Zorbin's Ultra-Shrinker
	{ 34471, 40 }, -- Vial of the Sunwell
	{ 32698, 45 }, -- Wrangling Rope
	{ 116139, 50 }, -- Haunting Memento
	{ 32825, 60 }, -- Soul Cannon
	{ 41265, 70 }, -- Eyesore Blaster
	{ 35278, 80 }, -- Reinforced Net
}

R.HARM_ITEMS, R.HELP_ITEMS = HARM_ITEMS, HELP_ITEMS

-- Text colors: green = melee, yellow = within your spell range,
-- red = further than any of your spells reach.
local GREEN = { 0.3, 1, 0.3 }
local YELLOW = { 1, 0.85, 0.15 }
local RED = { 1, 0.3, 0.3 }
local WHITE = { 1, 1, 1 }

local function flag(v)
	if v == nil then
		return nil
	end
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	if v == true or v == 1 then
		return true
	end
	if v == false or v == 0 then
		return false
	end
	return nil
end

local function num(v)
	if v == nil or (issecretvalue and issecretvalue(v)) then
		return nil
	end
	return tonumber(v)
end

local function call(fn, ...)
	if not fn then
		return nil
	end
	local ok, a = pcall(fn, ...)
	if ok then
		return a
	end
	return nil
end

-- spellbook ---------------------------------------------------------------

local spells = { harm = {}, help = {} }
local builtAt

local function eachBookSpell(fn)
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookItemInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		local lines = num(call(C_SpellBook.GetNumSpellBookSkillLines)) or 0
		for line = 1, lines do
			local info = call(C_SpellBook.GetSpellBookSkillLineInfo, line)
			if type(info) == "table" and not info.shouldHide and not info.offSpecID then
				local first = (num(info.itemIndexOffset) or 0) + 1
				local last = first + (num(info.numSpellBookItems) or 0) - 1
				for i = first, last do
					local item = call(C_SpellBook.GetSpellBookItemInfo, i, bank)
					-- itemType 1 = a learned spell (2 = not learned yet, 4 = flyout)
					if type(item) == "table" and item.itemType == 1 and not item.isPassive and not item.isOffSpec and item.spellID then
						fn(item.spellID)
					end
				end
			end
		end
		return
	end
	if GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		for tab = 1, (num(call(GetNumSpellTabs)) or 0) do
			local ok, _, _, offset, count = pcall(GetSpellTabInfo, tab)
			if ok and offset and count then
				for i = offset + 1, offset + count do
					local ok2, kind, id = pcall(GetSpellBookItemInfo, i, "spell")
					local passive = IsPassiveSpell and call(IsPassiveSpell, i, "spell")
					if ok2 and kind == "SPELL" and id and not passive then
						fn(id)
					end
				end
			end
		end
	end
end

local function spellRange(id)
	if C_Spell and C_Spell.GetSpellInfo then
		local info = call(C_Spell.GetSpellInfo, id)
		if type(info) == "table" then
			return num(info.minRange) or 0, num(info.maxRange) or 0
		end
	end
	if GetSpellInfo then
		local ok, _, _, _, _, minR, maxR = pcall(GetSpellInfo, id)
		if ok then
			return num(minR) or 0, num(maxR) or 0
		end
	end
	return nil
end

local function isHarmful(id)
	if C_Spell and C_Spell.IsSpellHarmful then
		local f = flag(call(C_Spell.IsSpellHarmful, id))
		if f ~= nil then
			return f
		end
	end
	if IsHarmfulSpell and GetSpellInfo then
		local name = call(GetSpellInfo, id)
		if name then
			return flag(call(IsHarmfulSpell, name)) == true
		end
	end
	return false
end

local function isHelpful(id)
	if C_Spell and C_Spell.IsSpellHelpful then
		local f = flag(call(C_Spell.IsSpellHelpful, id))
		if f ~= nil then
			return f
		end
	end
	if IsHelpfulSpell and GetSpellInfo then
		local name = call(GetSpellInfo, id)
		if name then
			return flag(call(IsHelpfulSpell, name)) == true
		end
	end
	return false
end

-- One list per kind: { range, minRange, {spellIDs...} }, sorted by range.
local function build()
	local byRange = { harm = {}, help = {} }
	eachBookSpell(function(id)
		local minR, maxR = spellRange(id)
		if not maxR then
			return
		end
		if maxR <= 0 then
			maxR = MELEE
		end
		local kind = (isHarmful(id) and "harm") or (isHelpful(id) and "help") or nil
		if not kind or maxR > 100 then
			return
		end
		local key = maxR .. ":" .. minR
		local entry = byRange[kind][key]
		if not entry then
			entry = { range = maxR, minRange = minR, ids = {} }
			byRange[kind][key] = entry
		end
		if #entry.ids < 3 then
			entry.ids[#entry.ids + 1] = id
		end
	end)
	for kind, map in pairs(byRange) do
		local list = {}
		for _, e in pairs(map) do
			list[#list + 1] = e
		end
		table.sort(list, function(a, b)
			return a.range < b.range
		end)
		spells[kind] = list
	end
	builtAt = GetTime and GetTime() or 0
end

-- Forever fires SPELLS_CHANGED in storms, so the list is rebuilt on a timer.
function R.Invalidate()
	builtAt = nil
end

local function ensure()
	local now = GetTime and GetTime() or 0
	if not builtAt or now - builtAt > 20 then
		build()
	end
end

-- checks ------------------------------------------------------------------

local function spellInRange(id, unit)
	if C_Spell and C_Spell.IsSpellInRange then
		local f = flag(call(C_Spell.IsSpellInRange, id, unit))
		if f ~= nil then
			return f
		end
	end
	if IsSpellInRange and GetSpellInfo then
		local name = call(GetSpellInfo, id)
		if name then
			return flag(call(IsSpellInRange, name, unit))
		end
	end
	return nil
end

-- Item and interact-distance checks are off-limits to addons in combat
-- (calling them there can get the addon blocked), so they only run out of it.
local function restricted()
	return InCombatLockdown and flag(call(InCombatLockdown)) == true
end

local function itemInRange(id, unit)
	if restricted() then
		return nil
	end
	local fn = (C_Item and C_Item.IsItemInRange) or IsItemInRange
	if not fn then
		return nil
	end
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, id)
	end
	return flag(call(fn, id, unit))
end

local function interact(unit, index)
	if not CheckInteractDistance or restricted() then
		return nil
	end
	return flag(call(CheckInteractDistance, unit, index))
end

local function canAttack(unit)
	local f = flag(call(UnitCanAttack, "player", unit))
	if f ~= nil then
		return f
	end
	-- hostility hidden: assume an enemy unless the game says it's a friend
	return flag(call(UnitIsFriend, "player", unit)) ~= true
end

-- Returns lo, hi in yards (hi nil = further than anything we can test),
-- or nil when nothing could be read. trace (optional table) collects the
-- answers for /rcr range.
function R.Band(unit, trace)
	unit = unit or "target"
	if not UnitExists or flag(call(UnitExists, unit)) ~= true then
		return nil
	end
	if flag(call(UnitIsUnit, unit, "player")) == true then
		return 0, 0
	end
	if UnitDistanceSquared then
		local ok, d, checked = pcall(UnitDistanceSquared, unit)
		d = ok and num(d) or nil
		if d and d >= 0 and flag(checked) ~= false then
			local y = math.sqrt(d)
			if trace then
				trace[#trace + 1] = ("exact distance: %.1f yd"):format(y)
			end
			return y, y
		end
	end
	ensure()
	local lo, hi = 0, nil
	local read = false
	local function inside(r, why)
		read = true
		if not hi or r < hi then
			hi = r
		end
		if trace then
			trace[#trace + 1] = ("  in  %3d yd  %s"):format(r, why)
		end
	end
	local function outside(r, why)
		read = true
		if r > lo then
			lo = r
		end
		if trace then
			trace[#trace + 1] = ("  out %3d yd  %s"):format(r, why)
		end
	end
	local hostile = canAttack(unit)
	local list = hostile and spells.harm or spells.help
	for _, e in ipairs(list) do
		for _, id in ipairs(e.ids) do
			local f = spellInRange(id, unit)
			if f ~= nil then
				local name = (C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, id)) or tostring(id)
				if f then
					inside(e.range, name)
					if e.minRange > lo then
						lo = e.minRange
					end
				elseif e.minRange <= 0 then
					-- with a minimum range, "out" can also mean too close
					outside(e.range, name)
				end
				break
			elseif trace then
				trace[#trace + 1] = ("  ?   %3d yd  %s (game won't say)"):format(e.range, tostring(id))
			end
		end
	end
	for _, it in ipairs(hostile and HARM_ITEMS or HELP_ITEMS) do
		local f = itemInRange(it[1], unit)
		if f == true then
			inside(it[2], "item " .. it[1])
		elseif f == false then
			outside(it[2], "item " .. it[1])
		end
	end
	-- 3 = duel (~10 yd), 2 = trade (~11 yd), 1 = inspect (~28 yd);
	-- the edges vary a little by client, so "out" uses the smaller number.
	local duel = interact(unit, 3)
	if duel == true then
		inside(10, "duel distance")
	elseif duel == false then
		outside(7, "duel distance")
	end
	local inspect = interact(unit, 1)
	if inspect == true then
		inside(28, "inspect distance")
	elseif inspect == false then
		outside(28, "inspect distance")
	end
	if not read then
		return nil
	end
	if hi and lo > hi then
		lo = hi
	end
	return lo, hi
end

function R.Text(lo, hi)
	if not lo then
		return nil
	end
	if hi and lo == hi then
		return ("%d yd"):format(math.floor(lo + 0.5))
	end
	if hi and hi <= MELEE then
		return "melee"
	end
	if hi and hi - lo <= 1 then
		return ("%d yd"):format(hi)
	end
	if not hi then
		return ("%d+ yd"):format(lo)
	end
	return ("%d-%d yd"):format(lo, hi)
end

-- display -----------------------------------------------------------------

-- the furthest any of your attack spells reaches (melee only: 5)
function R.SpellReach()
	ensure()
	local reach = MELEE
	for _, e in ipairs(spells.harm) do
		if e.range > reach then
			reach = e.range
		end
	end
	return reach
end

function R.Color(lo, hi)
	if hi and hi <= MELEE then
		return GREEN
	end
	local reach = R.SpellReach()
	if hi and hi <= reach then
		return YELLOW
	end
	if lo and lo >= reach then
		return RED
	end
	return WHITE
end

local function paintText(fs, lo, hi)
	local text = R.Text(lo, hi)
	if not text or (hi == 0 and lo == 0) then
		fs:Hide()
		return
	end
	fs:SetText(text)
	local c = R.Color(lo, hi)
	fs:SetTextColor(c[1], c[2], c[3])
	fs:Show()
end

local label
local elapsedSince = 0

function R.Refresh()
	if not label then
		return
	end
	if not ns.db or ns.db.showYards == false then
		label:Hide()
		return
	end
	paintText(label, R.Band("target"))
end

function R.Attach()
	local slot = ns.UI and ns.UI.slots and ns.UI.slots[1]
	if label or not slot then
		return
	end
	local holder = CreateFrame("Frame", nil, slot)
	holder:SetAllPoints(slot)
	holder:SetFrameLevel(slot:GetFrameLevel() + 6)
	label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", slot, "TOPLEFT", 4, -4)
	label:SetJustifyH("LEFT")
	local font = label:GetFont()
	if font then
		label:SetFont(font, 11, "OUTLINE")
	end
	label:Hide()
	R.label = label
	holder:SetScript("OnUpdate", function(_, elapsed)
		elapsedSince = elapsedSince + (elapsed or 0)
		if elapsedSince < 0.2 then
			return
		end
		elapsedSince = 0
		local ok = pcall(R.Refresh)
		if not ok then
			label:Hide()
		end
	end)
end

-- yards above enemy nameplates ---------------------------------------------

local function plateUnit(plate)
	local u = plate.namePlateUnitToken
	if type(u) ~= "string" and type(plate.UnitFrame) == "table" then
		u = plate.UnitFrame.unit
	end
	if type(u) == "string" and not (issecretvalue and issecretvalue(u)) then
		return u
	end
	return nil
end

local function plateText(plate)
	local fs = plate.rcrYards
	if fs then
		return fs
	end
	local holder = CreateFrame("Frame", nil, plate)
	holder.rcrOwn = true -- the nameplate code leaves it alone
	holder:SetAllPoints(plate)
	if plate.GetFrameLevel then
		pcall(holder.SetFrameLevel, holder, (plate:GetFrameLevel() or 0) + 21)
	end
	fs = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	local font = fs:GetFont()
	if font then
		fs:SetFont(font, 10, "OUTLINE")
	end
	fs.holder = holder
	plate.rcrYards = fs
	return fs
end

local function placeYards(plate, fs)
	local name = plate.rcrName
	local anchor = (name and name:IsShown()) and name or plate
	if fs.rcrAnchor == anchor then
		return
	end
	fs.rcrAnchor = anchor
	fs:ClearAllPoints()
	if anchor == plate then
		fs:SetPoint("BOTTOM", plate, "TOP", 0, 2)
	else
		fs:SetPoint("BOTTOM", name, "TOP", 0, 1)
	end
end

function R.RefreshPlates()
	local plates = C_NamePlate and C_NamePlate.GetNamePlates and call(C_NamePlate.GetNamePlates)
	if type(plates) ~= "table" then
		return
	end
	local on = ns.db and ns.db.showYards ~= false
	for _, plate in ipairs(plates) do
		if type(plate) == "table" then
			local unit = on and plateUnit(plate)
			local hostile = unit and canAttack(unit)
			if hostile then
				local fs = plateText(plate)
				placeYards(plate, fs)
				local ok = pcall(paintText, fs, R.Band(unit))
				if not ok then
					fs:Hide()
				end
			elseif plate.rcrYards then
				plate.rcrYards:Hide()
			end
		end
	end
end

-- /rcr range: what the game answered, so a wrong band can be traced.
function R.Check()
	local trace = {}
	local lo, hi = R.Band("target", trace)
	if lo == nil then
		ns.Print("range: target something first (or the game gave no answers)")
		return
	end
	ns.Print("range: " .. (R.Text(lo, hi) or "?"))
	for _, line in ipairs(trace) do
		print(line)
	end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(ev.RegisterEvent, ev, "LEARNED_SPELL_IN_TAB")
pcall(ev.RegisterEvent, ev, "PLAYER_LEVEL_UP")
pcall(ev.RegisterEvent, ev, "PLAYER_TALENT_UPDATE")
pcall(ev.RegisterEvent, ev, "ACTIVE_TALENT_GROUP_CHANGED")
local plateSince = 0
ev:SetScript("OnUpdate", function(_, elapsed)
	plateSince = plateSince + (elapsed or 0)
	if plateSince < 0.3 then
		return
	end
	plateSince = 0
	pcall(R.RefreshPlates)
end)
ev:SetScript("OnEvent", function(_, event)
	R.Invalidate()
	if event == "PLAYER_ENTERING_WORLD" then
		R.Attach()
	end
end)
