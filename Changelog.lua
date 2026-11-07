-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.9",
		items = {
			"Range detector: the main HUD icon shows how far your target is, top left (\"20-28 yd\", or \"melee\"). WoW doesn't tell addons the exact distance to an enemy, so it's a range worked out from which of your spells can reach. Green means your next spell reaches, red means you're too far for it. Turn it off in Options > General > HUD (\"Yards to target\"). /rcr range lists what the game answered.",
		},
	},
	{
		version = "1.5.6",
		items = {
			"Enemy names only (/rcr plates): names show from further away (the game's longest nameplate distance; your own setting comes back when you turn the option off), so you see them, and the addon counts them for multi-target, sooner.",
			"A mob someone else has tagged now has a purple name instead of grey, since grey looks dead.",
		},
	},
	{
		version = "1.5.5",
		items = {
			"Blessing of Kings (and other talents you didn't take) are no longer suggested. WoW Forever's spellbook lists spells you haven't learned too, greyed out or inside a flyout (the Paladin \"Blessings\" button), and the addon counted those as known.",
			"WoW Forever: in combat, Seal of Righteousness (or a DoT) is no longer asked for again right after you cast it. In a fight the game can give addons no buffs or debuffs at all, which read as \"none\"; now what you cast counts until the fight ends.",
			"/rcr spellcheck <spell>: shows what the game says about whether you know a spell.",
		},
	},
}
