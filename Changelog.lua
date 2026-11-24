-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.24",
		items = {
			"Seal twist tracker: an \"Unlock twist tracker\" button in Options > General > Windows to move or resize it again after locking it (click again to lock). It also unlocks and locks along with the HUD's Unlock / Lock button. /rcr twist unlock still works too.",
			"Seal twist: recasting the seal you already have no longer restarts the echo count (the game keeps the echoes), and when the game shows your real Echo stacks the tracker and rotation use those instead of counting swings.",
			"Seal twist tracker: click the pattern in its corner (3/1) to switch between 3/1 (WoWSims), 3/3 (levelling) and 2/1 (end game), locked or not; the rotation follows it.",
			"Name-only enemy nameplates: the quest, elite and loot / interact icons now sit in a row above the enemy's name (above the yards readout when it shows) instead of beside it.",
			"Name-only enemy nameplates: names (and their yards) stay fully visible far away and behind walls; the game's own distance / line-of-sight fade made them vanish around 30-40 yards.",
		},
	},
	{
		version = "1.5.20",
		items = {
			"WoW Forever rotations updated from WoWSims. WoWSims dropped the Hunter Beast Mastery and Marksmanship melee-weave builds, so those two rotations are gone (Auto picks another), and the Shaman Elemental and Enhancement rotations now come from WoWSims' default builds.",
			"Rotations that check how long the target has left work again (those lines were skipped).",
		},
	},
	{
		version = "1.5.19",
		items = {
			"Seal twist tracker (WoW Forever Paladin): pops up once you have Unsealed Wrath. Shows your seal, the echoes it has stored (counted from your swings, since the game hides them in combat) and SWAP on the swing to change seal. It has its own lock bar: /rcr twist unlock, drag it by the bar, click Lock. The bar also switches the twist pattern: 3/1 (WoWSims, the default), 3/3 or 2/1 swings on Command / Righteousness; the rotation follows the pattern you pick. Turn it off in Options > General > Windows (\"Seal twist tracker\"), or with /rcr twist. /rcr twist preview shows it before you have the talent, so you can put it where you want it now. While unlocked, drag its bottom-right corner to resize it.",
		},
	},
}
