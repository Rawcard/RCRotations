local addonName, ns = ...

-- Client detection. RCRotations runs on Classic Era, TBC Anniversary, Wrath,
-- Cata, MoP Classic and WoW Forever (camelot). Retail is excluded: since
-- Midnight, combat state is hidden from addons, so a rotation helper can't decide.
local toc = 0
if GetBuildInfo then
	local ok, _, _, _, interface = pcall(GetBuildInfo)
	if ok then
		toc = tonumber(interface) or 0
	end
end

local game
if toc >= 16000 and toc < 17000 then
	game = "forever"
elseif toc < 20000 then
	game = "vanilla"
elseif toc < 30000 then
	game = "tbc"
elseif toc < 40000 then
	game = "wrath"
elseif toc < 50000 then
	game = "cata"
elseif toc < 60000 then
	game = "mists"
else
	game = "standard"
end

ns.TOC = toc
ns.GAME = game
ns.GAME_LABEL = ({
	forever = "WoW Forever",
	vanilla = "Classic Era",
	tbc = "TBC Classic",
	wrath = "Wrath Classic",
	cata = "Cata Classic",
	mists = "MoP Classic",
	standard = "Retail",
})[game]

-- 2-second energy ticks and swing/auto-shot clipping only exist before Wrath.
ns.CLASSIC_TIMING = (game == "vanilla" or game == "tbc" or game == "forever")

function ns.IsGame(...)
	for i = 1, select("#", ...) do
		if select(i, ...) == game then
			return true
		end
	end
	return false
end

-- Where to download the RCRotations Workshop desktop app (Windows).
ns.WORKSHOP_URL = "https://github.com/Rawcard/RCRotations/releases/tag/workshop"
