local addonName, ns = ...

-- ---------------------------------------------------------------------------
-- In-game import of WoWSims rotations.
--
-- Paste a rotation exported from wowsims.com (Rotation tab -> Export -> JSON,
-- either the rotation alone or a full settings export). It's converted here
-- with the same rules as tools/wowsims_convert.py and saved account-wide in
-- RCRotationsDB.simImports["CLASS:spec"], then shown in the rotation picker
-- as "(imported)". tools/test_sim.py checks this converter gives the same
-- result as the Python one for every WoWSims rotation.
-- ---------------------------------------------------------------------------

local Sim = ns.Sim
if not Sim then
	return
end

-- ------------------------------------------------------------------ JSON
local function jsonDecode(text)
	local pos = 1
	local len = #text
	local function err(msg)
		error({ json = msg .. " at character " .. pos }, 0)
	end
	local function skip()
		while pos <= len do
			local c = text:byte(pos)
			if c == 32 or c == 9 or c == 10 or c == 13 then
				pos = pos + 1
			else
				break
			end
		end
	end
	local value
	local function utf8(code)
		if code < 0x80 then
			return string.char(code)
		elseif code < 0x800 then
			return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
		end
		return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
	local function str()
		pos = pos + 1
		local out = {}
		while true do
			local s, e = text:find('[\\"]', pos)
			if not s then
				err("unterminated string")
			end
			out[#out + 1] = text:sub(pos, s - 1)
			if text:sub(s, s) == '"' then
				pos = s + 1
				return table.concat(out)
			end
			local c = text:sub(s + 1, s + 1)
			if c == "u" then
				local hex = text:sub(s + 2, s + 5)
				local code = tonumber(hex, 16)
				if not code then
					err("bad \\u escape")
				end
				out[#out + 1] = utf8(code)
				pos = s + 6
			elseif ESC[c] then
				out[#out + 1] = ESC[c]
				pos = s + 2
			else
				err("bad escape")
			end
		end
	end
	local function number()
		local s, e = text:find("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
		if not s then
			err("bad number")
		end
		local n = tonumber(text:sub(s, e))
		if not n then
			err("bad number")
		end
		pos = e + 1
		return n
	end
	function value()
		skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local obj = {}
			skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while true do
				skip()
				if text:sub(pos, pos) ~= '"' then
					err("expected a key")
				end
				local k = str()
				skip()
				if text:sub(pos, pos) ~= ":" then
					err("expected ':'")
				end
				pos = pos + 1
				obj[k] = value()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return obj
				elseif d ~= "," then
					err("expected ',' or '}'")
				end
			end
		elseif c == "[" then
			pos = pos + 1
			local arr = {}
			skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while true do
				arr[#arr + 1] = value()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return arr
				elseif d ~= "," then
					err("expected ',' or ']'")
				end
			end
		elseif c == '"' then
			return str()
		elseif c == "-" or c:match("%d") then
			return number()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		end
		err("unexpected '" .. c .. "'")
	end
	local ok, res = pcall(value)
	if not ok then
		return nil, type(res) == "table" and res.json or tostring(res)
	end
	return res
end
Sim.JSONDecode = jsonDecode

-- ------------------------------------------------------------------ converter
-- Mirrors tools/wowsims_convert.py. Keep the two in step.
local STRUCTURAL = { ["and"] = true, ["or"] = true, ["not"] = true, cmp = true, math = true, max = true, min = true }

local STAND_IN = {
	bossSpellTimeToReady = 999, bossSpellIsCasting = false, bossSpellIsKnown = false,
	bossSpellCastTimeRemaining = 0, unitDistance = 5, autoTimeToNext = 1, spellTravelTime = 0.5,
	spellCpm = 0, spellChanneledTicks = 0, spellInFlight = false, auraInternalCooldown = 0,
	auraIcdIsReady = true, allTrinketStatProcsActive = false, anyTrinketStatProcsActive = false,
	anyTrinketStatProcsAvailable = false, trinketProcsMinRemainingTime = 0,
	trinketProcsMaxRemainingIcd = 0, numEquippedStatProcTrinkets = 0, numStatBuffCooldowns = 0,
	anyStatBuffCooldownsActive = false, anyStatBuffCooldownsMinDuration = 0, dotTimeToNextTick = 1,
	dotBaseDuration = 0, dotPercentIncrease = 0, dotCritPercentIncrease = 0,
	dotTickRatePercentIncrease = 0, sequenceIsComplete = false, sequenceIsReady = true,
	sequenceTimeToReady = 0, channelClipDelay = 0, inputDelay = 0.1, frontOfTarget = false,
	catExcessEnergy = 0, catNewSavageRoarDuration = 0, warlockHandOfGuldanInFlight = false,
	warlockHauntInFlight = false, mageCurrentCombustionDotEstimate = 0,
	shamanFireElementalDuration = 60, protectionPaladinDamageTakenLastGlobal = 0,
	afflictionCurrentSnapshot = 0, afflictionExhaleWindow = false, actionGroupUsed = false,
	activeItemSwapSet = false, auraIcdIsReadyWithReactionTime = true,
}
local ALIASES = { auraIsActiveWithReactionTime = "auraIsActive", auraIsInactiveWithReactionTime = "auraIsInactive" }
local CAST_ACTIONS = { castSpell = true, castFriendlySpell = true, channelSpell = true, multidot = true,
	strictMultidot = true, multishield = true }
local DROPPED_ACTIONS = {
	autocastOtherCooldowns = true, castAllStatBuffCooldowns = true, cancelSpellCast = true, changeTarget = true,
	activateAura = true, activateAuraWithStacks = true, activateAllStatBuffProcAuras = true, cancelAura = true,
	triggerIcd = true, itemSwap = true, move = true, moveDuration = true, damageAmplifier = true,
	resetSequence = true, customRotation = true, warlockNextExhaleTarget = true,
	catOptimalRotationAction = true, guardianHotwDpsRotation = true,
}
local OPS = { OpEq = "==", OpNe = "~=", OpLt = "<", OpLe = "<=", OpGt = ">", OpGe = ">=" }
local MATH = { OpAdd = "+", OpSub = "-", OpMul = "*", OpDiv = "/" }
local EXECUTE = { E20 = 0.20, E25 = 0.25, E35 = 0.35, E45 = 0.45, E90 = 0.90 }
local RUNE_TYPE = { RuneBlood = "blood", RuneFrost = "frost", RuneUnholy = "unholy", RuneDeath = "death" }
local RUNE_SLOT = { SlotLeftBlood = 1, SlotRightBlood = 2, SlotLeftUnholy = 3, SlotRightUnholy = 4,
	SlotLeftFrost = 5, SlotRightFrost = 6 }
local UNIT = { Self = "player", Player = "player", Target = "target", CurrentTarget = "target", Pet = "pet",
	PreviousTarget = "target", NextTarget = "target" }
local ECLIPSE = { NeutralPhase = "neutral", SolarPhase = "solar", LunarPhase = "lunar" }
local TOTEM = { Earth = 2, Air = 4, Fire = 1, Water = 3 }
local HEALTH_UNIT_KINDS = { currentHealth = true, currentHealthPercent = true, currentMana = true,
	currentManaPercent = true, unitIsMoving = true }

local function unsupported(what)
	error({ unsupported = what }, 0)
end

local function supported(kind)
	return Sim.HANDLERS[kind] ~= nil and not STRUCTURAL[kind]
end

local function parseConst(val)
	local v = tostring(val or "0"):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "true" then
		return true
	elseif v == "false" then
		return false
	end
	local n, unit = v:match("^(%-?[%d%.]+)%s*(%a*%%?)$")
	n = tonumber(n)
	if not n or (unit ~= "" and unit ~= "s" and unit ~= "ms" and unit ~= "%") then
		unsupported("const:" .. v)
	end
	if unit == "ms" then
		n = n / 1000
	elseif unit == "%" then
		n = n / 100
	end
	return n
end

local function actionId(aid)
	if type(aid) ~= "table" then
		return nil
	end
	local sid = tonumber(aid.spellId)
	if sid and sid ~= 0 then
		return sid
	end
	return nil
end

local function unitOf(ref, default)
	if type(ref) ~= "table" or not ref.type then
		return default
	end
	return UNIT[ref.type] or default
end

local function firstKey(node)
	-- WoWSims nodes have one meaningful key (plus an optional uuid).
	local key
	for k in pairs(node) do
		if k ~= "uuid" then
			key = key and (k < key and k or key) or k
		end
	end
	return key
end

local function nonEmpty(node)
	return type(node) == "table" and firstKey(node) ~= nil
end

local function newReport()
	return { approximated = {}, dropped = {}, unsupported = {} }
end

local function bump(t, k)
	t[k] = (t[k] or 0) + 1
end

local convertValue

convertValue = function(node, ctx, rep)
	if type(node) ~= "table" then
		unsupported("empty-value")
	end
	local kind = firstKey(node)
	if not kind then
		unsupported("empty-value")
	end
	local body = type(node[kind]) == "table" and node[kind] or {}
	kind = ALIASES[kind] or kind

	if kind == "const" then
		return parseConst(body.val)
	elseif kind == "variableRef" or kind == "variablePlaceholder" then
		local name = body.name
		if ctx.placeholders[name] ~= nil then
			return ctx.placeholders[name]
		end
		if kind == "variableRef" and ctx.variables[name] then
			return convertValue(ctx.variables[name], ctx, rep)
		end
		unsupported(kind .. ":" .. tostring(name))
	elseif kind == "and" or kind == "or" then
		local vals = {}
		for _, v in ipairs(body.vals or {}) do
			if nonEmpty(v) then
				vals[#vals + 1] = convertValue(v, ctx, rep)
			end
		end
		return { k = kind, v = vals }
	elseif kind == "not" then
		return { k = "not", v = { convertValue(body.val, ctx, rep) } }
	elseif kind == "max" or kind == "min" then
		local vals = {}
		for _, v in ipairs(body.vals or {}) do
			vals[#vals + 1] = convertValue(v, ctx, rep)
		end
		return { k = kind, v = vals }
	elseif kind == "cmp" then
		local op = OPS[body.op]
		if not op then
			unsupported("cmp-op")
		end
		return { k = "cmp", op = op, v = { convertValue(body.lhs, ctx, rep), convertValue(body.rhs, ctx, rep) } }
	elseif kind == "math" then
		local op = MATH[body.op]
		if not op then
			unsupported("math-op")
		end
		return { k = "math", op = op, v = { convertValue(body.lhs, ctx, rep), convertValue(body.rhs, ctx, rep) } }
	end

	if STAND_IN[kind] ~= nil and not supported(kind) then
		bump(rep.approximated, kind)
		return STAND_IN[kind]
	end
	if not supported(kind) then
		unsupported(kind)
	end

	local out = { k = kind }
	if body.spellId ~= nil then
		local sid = actionId(body.spellId)
		if not sid then
			bump(rep.approximated, kind .. "(item)")
			if kind:find("^spellIs") or kind:find("^spellCan") or kind:find("^aura") or kind:find("^dot") then
				return false
			end
			return 0
		end
		out.id = sid
	end
	if body.auraId ~= nil then
		local aid = actionId(body.auraId)
		if not aid then
			bump(rep.approximated, kind .. "(item)")
			if kind == "auraIsActive" or kind == "auraIsKnown" then
				return false
			elseif kind == "auraIsInactive" then
				return true
			end
			return 0
		end
		out.id = aid
	end
	if kind:find("^aura") then
		out.unit = unitOf(body.sourceUnit, "player")
	end
	if kind:find("^dot") then
		out.unit = unitOf(body.targetUnit, "target")
	end
	if HEALTH_UNIT_KINDS[kind] then
		out.unit = unitOf(body.sourceUnit, "player")
	end
	if kind == "isExecutePhase" then
		out.pct = EXECUTE[body.threshold] or 0.2
	end
	if body.runeType ~= nil then
		out.rune = RUNE_TYPE[body.runeType] or "blood"
	end
	if body.runeSlot ~= nil then
		out.slot = RUNE_SLOT[body.runeSlot] or 1
	end
	if kind == "auraShouldRefresh" then
		out.overlap = nonEmpty(body.maxOverlap) and convertValue(body.maxOverlap, ctx, rep) or 0
	end
	if kind == "energyTimeToTarget" or kind == "focusTimeToTarget" then
		local tgt = body.targetEnergy or body.targetFocus
		out.target = nonEmpty(tgt) and convertValue(tgt, ctx, rep) or 0
	end
	if kind == "druidCurrentEclipsePhase" then
		out.phase = ECLIPSE[body.eclipsePhase] or "neutral"
	end
	if kind == "totemRemainingTime" then
		out.slot = TOTEM[(tostring(body.totemType or "")):gsub("TotemType", "")] or 1
	end
	return out
end

local convertAction

local function andCond(cond, extra)
	if cond == nil then
		return extra
	end
	if extra == nil then
		return cond
	end
	return { k = "and", v = { cond, extra } }
end

local function attach(items, cond, out)
	for _, it in ipairs(items) do
		if cond ~= nil then
			if it.c ~= nil then
				it.c = andCond(cond, it.c)
			else
				it.c = cond
			end
		end
		out[#out + 1] = it
	end
end

convertAction = function(act, ctx, out, rep)
	if type(act) ~= "table" then
		return
	end
	local cond
	if nonEmpty(act.condition) then
		cond = convertValue(act.condition, ctx, rep)
	end
	local kind
	for k in pairs(act) do
		if k ~= "condition" and k ~= "uuid" then
			kind = kind and (k < kind and k or kind) or k
		end
	end
	if not kind then
		return
	end
	local body = type(act[kind]) == "table" and act[kind] or {}

	if CAST_ACTIONS[kind] then
		local sid = actionId(body.spellId)
		if not sid then
			bump(rep.dropped, "item/potion cast")
			return
		end
		local item = { id = sid }
		local c = cond
		if kind == "multidot" or kind == "strictMultidot" then
			local overlap = nonEmpty(body.maxOverlap) and convertValue(body.maxOverlap, ctx, rep) or 0
			c = andCond(cond, { k = "auraShouldRefresh", id = sid, unit = "target", overlap = overlap })
		end
		if kind == "channelSpell" then
			item.ch = true
		end
		if c ~= nil then
			item.c = c
		end
		out[#out + 1] = item
		return
	elseif kind == "groupReference" then
		local group = ctx.groups[body.groupName]
		if not group then
			bump(rep.unsupported, "groupReference:" .. tostring(body.groupName))
			return
		end
		local placeholders = {}
		for k, v in pairs(ctx.placeholders) do
			placeholders[k] = v
		end
		for _, var in ipairs(group.variables or {}) do
			placeholders[var.name] = convertValue(var.value, ctx, rep)
		end
		for _, var in ipairs(body.variables or {}) do
			placeholders[var.name] = convertValue(var.value, ctx, rep)
		end
		local sub = { variables = ctx.variables, groups = ctx.groups, placeholders = placeholders }
		local inner = {}
		for _, li in ipairs(group.actions or {}) do
			if not li.hide then
				local ok, e = pcall(convertAction, li.action, sub, inner, rep)
				if not ok then
					bump(rep.unsupported, type(e) == "table" and e.unsupported or tostring(e))
				end
			end
		end
		attach(inner, cond, out)
		return
	elseif kind == "schedule" then
		bump(rep.approximated, "schedule")
		local inner = {}
		convertAction(body.innerAction, ctx, inner, rep)
		attach(inner, cond, out)
		return
	elseif kind == "sequence" or kind == "strictSequence" then
		bump(rep.approximated, kind)
		for _, subAct in ipairs(body.actions or {}) do
			local inner = {}
			convertAction(subAct, ctx, inner, rep)
			if inner[1] then
				attach({ inner[1] }, cond, out)
				break
			end
		end
		return
	elseif kind == "wait" or kind == "waitUntil" then
		local hold = cond
		if kind == "waitUntil" and nonEmpty(body.condition) then
			hold = andCond(cond, { k = "not", v = { convertValue(body.condition, ctx, rep) } })
		end
		if hold ~= nil then
			out[#out + 1] = { hold = true, c = hold }
		end
		return
	elseif DROPPED_ACTIONS[kind] then
		bump(rep.dropped, kind)
		return
	end
	bump(rep.unsupported, "action:" .. kind)
end

-- Accept a bare rotation export or a full WoWSims settings export.
local function findRotation(raw)
	if type(raw) ~= "table" then
		return nil
	end
	if raw.priorityList then
		return raw
	end
	local paths = { { "rotation" }, { "player", "rotation" }, { "settings", "player", "rotation" } }
	for _, path in ipairs(paths) do
		local node = raw
		for _, key in ipairs(path) do
			node = type(node) == "table" and node[key] or nil
		end
		if type(node) == "table" and node.priorityList then
			return node
		end
	end
	return nil
end
Sim.FindRotation = findRotation

-- Convert a decoded WoWSims rotation. Returns list, report.
function Sim.ConvertRotation(raw)
	local rep = newReport()
	local variables, groups = {}, {}
	for _, v in ipairs(raw.valueVariables or {}) do
		variables[v.name] = v.value
	end
	for _, g in ipairs(raw.groups or {}) do
		groups[g.name] = g
	end
	local ctx = { variables = variables, groups = groups, placeholders = {} }
	local out = {}
	for _, li in ipairs(raw.priorityList or {}) do
		if not li.hide then
			local ok, e = pcall(convertAction, li.action, ctx, out, rep)
			if not ok then
				bump(rep.unsupported, type(e) == "table" and e.unsupported or tostring(e))
			end
		end
	end
	return out, rep
end

-- ------------------------------------------------------------------ storage
local function store()
	RCRotationsDB = RCRotationsDB or {}
	RCRotationsDB.simImports = RCRotationsDB.simImports or {}
	return RCRotationsDB.simImports
end

function Sim.Imported(token, spec)
	if not token or not spec then
		return {}
	end
	return store()[token .. ":" .. spec] or {}
end

local function countKeys(t)
	local n = 0
	for _, c in pairs(t) do
		n = n + c
	end
	return n
end

-- Import pasted text for the current class/spec. Returns ok, message, rot.
function Sim.ImportText(text, name)
	local _, token, spec = Sim.Rotations()
	if not token or not spec or spec == 0 then
		return false, ns.T("SIM_IMPORT_NOSPEC")
	end
	text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return false, ns.T("SIM_IMPORT_EMPTY")
	end
	local raw, jerr = jsonDecode(text)
	if raw == nil then
		return false, ns.T("SIM_IMPORT_BADJSON"):format(jerr or "?")
	end
	local rot = findRotation(raw)
	if not rot then
		return false, ns.T("SIM_IMPORT_NOROT")
	end
	local list, rep = Sim.ConvertRotation(rot)
	local casts = 0
	for _, it in ipairs(list) do
		if it.id then
			casts = casts + 1
		end
	end
	if casts == 0 then
		return false, ns.T("SIM_IMPORT_NOCASTS")
	end
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" then
		name = ns.T("SIM_IMPORT_DEFAULTNAME")
	end
	local bucket = store()[token .. ":" .. spec] or {}
	store()[token .. ":" .. spec] = bucket
	local file = "import/" .. name:lower():gsub("[^%w]+", "_")
	local entry = { name = name .. " " .. ns.T("SIM_IMPORT_TAG"), file = file, list = list, imported = true,
		at = time and time() or 0 }
	local replaced = false
	for i, old in ipairs(bucket) do
		if old.file == file then
			bucket[i] = entry
			replaced = true
		end
	end
	if not replaced then
		bucket[#bucket + 1] = entry
	end
	ns.db.simPick = ns.db.simPick or {}
	ns.db.simPick[token .. ":" .. spec] = file
	local msg = ns.T("SIM_IMPORT_OK"):format(name, casts, countKeys(rep.approximated), countKeys(rep.unsupported))
	if ns.InvalidateTick then
		ns.InvalidateTick()
	end
	return true, msg, entry
end

function Sim.RemoveImport(token, spec, file)
	local bucket = store()[token .. ":" .. spec]
	if not bucket then
		return false
	end
	for i, rot in ipairs(bucket) do
		if rot.file == file then
			table.remove(bucket, i)
			if ns.db.simPick and ns.db.simPick[token .. ":" .. spec] == file then
				ns.db.simPick[token .. ":" .. spec] = nil
			end
			if ns.InvalidateTick then
				ns.InvalidateTick()
			end
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------ window
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

local function goldButton(parent, width, label)
	local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
	btn:SetSize(width, 24)
	btn:SetBackdrop(BTN_BACKDROP)
	btn:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
	btn:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
	local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("CENTER", 0, 0)
	text:SetText(label)
	btn.label = text
	btn:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(1, 0.82, 0.2, 1)
	end)
	btn:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0.55, 0.45, 0.18, 1)
	end)
	return btn
end
Sim.GoldButton = goldButton

local win

local function specLabel(spec)
	if GetSpecializationInfo then
		local ok, _, name = pcall(GetSpecializationInfo, spec)
		if ok and type(name) == "string" then
			return name
		end
	end
	return "?"
end

local function ensureWindow()
	if win then
		return win
	end
	win = CreateFrame("Frame", "RCRotationsImport", UIParent, "BackdropTemplate")
	win:SetSize(520, 380)
	win:SetPoint("CENTER", 0, 40)
	win:SetFrameStrata("DIALOG")
	win:SetBackdrop(BACKDROP)
	win:SetBackdropColor(0, 0, 0, 0.92)
	win:SetBackdropBorderColor(0.83, 0.63, 0.09, 0.9)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", win.StopMovingOrSizing)
	win:SetClampedToScreen(true)

	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOP", 0, -14)
	title:SetText("|cff66ccffRC|r|cffd4a017Rotations|r — " .. ns.T("SIM_IMPORT_TITLE"))

	local sub = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", 16, -36)
	sub:SetPoint("RIGHT", -16, 0)
	sub:SetJustifyH("LEFT")
	sub:SetTextColor(0.8, 0.8, 0.8)
	win.sub = sub

	local nameLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	nameLabel:SetPoint("TOPLEFT", 16, -82)
	nameLabel:SetText(ns.T("SIM_IMPORT_NAME"))
	local nameBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
	nameBox:SetSize(220, 20)
	nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
	nameBox:SetAutoFocus(false)
	nameBox:SetMaxLetters(40)
	win.nameBox = nameBox

	local scroll = CreateFrame("ScrollFrame", "RCRotationsImportScroll", win, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 16, -108)
	scroll:SetPoint("BOTTOMRIGHT", -36, 74)
	local bg = win:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", scroll, -4, 4)
	bg:SetPoint("BOTTOMRIGHT", scroll, 24, -4)
	bg:SetTexture("Interface\\Buttons\\WHITE8x8")
	bg:SetVertexColor(0.08, 0.08, 0.08, 0.9)
	local edit = CreateFrame("EditBox", "RCRotationsImportEdit", scroll)
	edit:SetMultiLine(true)
	edit:SetFontObject("ChatFontSmall")
	edit:SetWidth(450)
	edit:SetHeight(200)
	edit:SetAutoFocus(false)
	edit:EnableMouse(true)
	edit:SetMaxLetters(0)
	edit:SetTextInsets(4, 4, 4, 4)
	edit:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	scroll:SetScrollChild(edit)
	scroll:EnableMouse(true)
	scroll:SetScript("OnMouseDown", function()
		edit:SetFocus()
	end)
	win.edit = edit

	local status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", 16, 46)
	status:SetPoint("RIGHT", -16, 0)
	status:SetJustifyH("LEFT")
	win.status = status

	local importBtn = goldButton(win, 140, ns.T("SIM_IMPORT_BUTTON"))
	importBtn:SetPoint("BOTTOMLEFT", 16, 14)
	importBtn:SetScript("OnClick", function()
		local ok, msg = Sim.ImportText(edit:GetText(), nameBox:GetText())
		if ok then
			status:SetTextColor(0.4, 1, 0.4)
			status:SetText(msg)
			if ns.Print then
				ns.Print(msg)
			end
			edit:SetText("")
			if Sim.ShowPicker then
				win:Hide()
				Sim.ShowPicker(true)
			end
		else
			status:SetTextColor(1, 0.35, 0.35)
			status:SetText(msg)
		end
	end)
	win.importBtn = importBtn

	local cancel = goldButton(win, 100, ns.T("SIM_IMPORT_CANCEL"))
	cancel:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
	cancel:SetScript("OnClick", function()
		win:Hide()
	end)

	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	win:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "RCRotationsImport")
	end
	return win
end

function Sim.ShowImport()
	local _, token, spec = Sim.Rotations()
	if not token or not spec or spec == 0 then
		if ns.Print then
			ns.Print(ns.T("SIM_IMPORT_NOSPEC"))
		end
		return false
	end
	ensureWindow()
	win.sub:SetText(ns.T("SIM_IMPORT_HELP"):format(specLabel(spec)))
	win.status:SetText("")
	win.nameBox:SetText("")
	win:Show()
	win.edit:SetFocus()
	return true
end
