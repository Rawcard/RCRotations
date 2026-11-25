-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.26",
		items = {
			"WoW Forever: a buff reminder (and its bar flash) now goes away as soon as you cast that buff in combat. The game hides the spell from addons in combat; the addon now reads it from the cast itself, and any rank of the spell counts.",
			"Tracking reminders and their bar flash stay off in combat however the game reports it.",
			"Paladin damage: the built-in lists no longer suggest Seal of Fury (the tank seal); it's Command, then Righteousness. Protection still uses Fury.",
			"Seal Twist: with no seal up, the addon now asks for Seal of Command (or Righteousness), not Seal of Fury. The WoWSims twist rotation lists Fury for a rare swap and the addon was opening on it.",
		},
	},
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
}
