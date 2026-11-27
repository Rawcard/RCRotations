-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.27",
		items = {
			"Seal twist tracker: it now tracks the echoes of whatever seal you have up, not just Command and Righteousness. Seal of Wisdom, Light, Justice (and Fury) show their stored echoes out of 3 in their own color, with SWAP once all 3 are stored (a hit with any other seal spends them, each with that seal's chance to go off: a burst of mana from Wisdom, healing from Light). Seal of the Crusader stores no echoes, so the tracker says so.",
		},
	},
	{
		version = "1.5.26",
		items = {
			"WoW Forever: a buff reminder (and its bar flash) now goes away as soon as you cast that buff in combat. The game hides the spell from addons in combat; the addon now reads it from the cast itself, and any rank of the spell counts.",
			"Tracking reminders and their bar flash stay off in combat however the game reports it.",
			"Paladin damage: the built-in lists no longer suggest Seal of Fury (the tank seal); it's Command, then Righteousness. Protection still uses Fury.",
			"Seal Twist: with no seal up, the addon now asks for Seal of Command (or Righteousness), not Seal of Fury. The WoWSims twist rotation lists Fury for a rare swap and the addon was opening on it.",
			"Paladin damage rotations never suggest Seal of Fury at all now (Protection still does). `/rcr why` marks its line \"OFF (tank seal)\".",
			"Seal of Fury could still come back after a fresh login (not after a /reload): right after login the game can give no name for it, and the addon then didn't recognise it as a seal. It's now recognised by its spell ID as well, so it stays off.",
			"Questie tooltips: when WoW Forever hides a mob from Questie (in combat, in dungeons, mobs you've tagged), the quest lines (mobs to kill, items they drop) were missing. The addon now asks Questie for them by the mob's name and adds them. `/rcr questie` turns this off.",
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
}
