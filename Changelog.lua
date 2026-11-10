-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.13",
		items = {
			"Smoother HUD on WoW Forever: when nothing is ready, the main icon shows the next spell to come off cooldown (dimmed, with its countdown) instead of going blank, however long the wait.",
			"Enemy names on nameplates show the mob's level to the left, colored by difficulty like the quest log (\"??\" for far above you, \"+\" for elites). /rcr platelevel turns it off and on.",
			"Questie: with name-only nameplates, hovering the invisible plate around a name gave the game's nameplate tooltip, which Questie can't read on WoW Forever, so its quest lines went missing on and off. That tooltip is now swapped for the mob's normal one. Names stay clickable (through walls too); /rcr plateclick makes the hidden plates click-through instead.",
			"A blank lasting under half a second keeps the last suggestion, so the icon doesn't blink empty between updates.",
		},
	},
	{
		version = "1.5.9",
		items = {
			"Range detector: the main HUD icon shows how far your target is, top left (\"20-25 yd\", or \"melee\"), and the same distance shows just above each enemy's name. WoW doesn't tell addons the exact distance to an enemy, so it's worked out from which of your spells (and a list of range-check items) can reach; out of combat it's often within 5 yards, in combat only your spells can be asked so the range gets wider. An enemy with a nameplate is always shown as within 60 yards (the game only makes nameplates that close), in combat too.",
			"Past your spell range it reads the distance off the nameplate's size (\"~47 yd\"): the game shrinks nameplates with distance, so the addon sets them to shrink evenly from 10 to 60 yards. It learns a nameplate's full size the first time you fight something in melee range.",
			"Colors: green = in melee range, yellow = within reach of your spells, red = further than any of your spells reach.",
			"Fixed (WoW Forever): the rotation stopped in combat. Forever hides a mob's creature type in combat, and the \"undead and demons only\" check for Exorcism errored on it. The type seen before the fight is used now.",
			"Fixed (WoW Forever): mana read as 0 in combat (the game hides it), so lines that need mana (Consecration, Exorcism) were never suggested in a fight. The last mana value seen is used.",
			"WoW Forever Seal Twist rotation: until you learn Unsealed Wrath there's no twist to protect, so Consecration and Exorcism no longer wait for the gap right after a swing.",
			"/rcr why lists only the bar buttons you can see.",
			"Spells cast from a macro (/startattack + /cast Judgement) flash on their button again.",
			"A rotation line that errors no longer empties the whole HUD (it's skipped, Auto Attack still shows), and /rcr why lists each rotation line with what stopped it, plus any errors.",
			"Forever Paladin: with no seal up, the first seal the rotation uses that you actually know is suggested (Seal of Righteousness before you have the Seal of Command talent).",
			"Fixed: a spell learned mid-session (Consecration at level 20) wasn't suggested until a /reload when the rotation names a different rank of it.",
			"Turn it off in Options > General > HUD (\"Yards: main icon and enemy names\"). /rcr range lists what the game answered.",
		},
	},
	{
		version = "1.5.6",
		items = {
			"Enemy names only (/rcr plates): names show from further away (the game's longest nameplate distance; your own setting comes back when you turn the option off), so you see them, and the addon counts them for multi-target, sooner.",
			"A mob someone else has tagged now has a purple name instead of grey, since grey looks dead.",
		},
	},
}
