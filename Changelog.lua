-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.19",
		items = {
			"Seal twist tracker (WoW Forever Paladin): pops up once you have Unsealed Wrath. Shows your seal, the echoes it has stored (counted from your swings, since the game hides them in combat) and SWAP on the swing to change seal. It has its own lock bar: /rcr twist unlock, drag it by the bar, click Lock. The bar also switches the twist pattern: 3/1 (WoWSims, the default), 3/3 or 2/1 swings on Command / Righteousness; the rotation follows the pattern you pick. /rcr twist turns the tracker off and on. /rcr twist preview shows it before you have the talent, so you can put it where you want it now. While unlocked, drag its bottom-right corner to resize it.",
		},
	},
	{
		version = "1.5.18",
		items = {
			"Tracking reminders: left of the main HUD icon, an icon shows for each tracking you have but haven't turned on: Find Minerals / Find Herbs, and the Dwarf's Find Treasure (WoW Forever lets that run alongside the others), stacked against its left edge. The tracking spell also flashes on your action bars like a missing buff. Click the icon or the bar button to turn it on. Hidden in combat and while dead. /rcr tracking turns the reminders off and on. (They sit beside the HUD without being attached to it, so the HUD can still show and hide in combat.)",
			"The action-bar scan does at most ~2 ms of work per frame, so WoW Forever doesn't stop it with \"script ran too long\".",
			"Flash colors: the spell after the main one now flashes on your bars too, in its own color (blue), and tracking flashes in its own color. A new Flash colors window (/rcr colors, or the \"Bar flash colors\" button in Options > Extra > Colors) changes the color of every kind of flash, turns the second-spell flash off, and has presets from RC-SpellFlash: Fire & Ice, Classic NAG, RGB, and Default. Pick a flash, then a color from the palette or the red / green / blue sliders. The second color lights the spell after the main one, even while it's still on cooldown, and while the main spell itself is on cooldown (Judgement, say) it lights that, so a button is always lit for what to press next. /rcr why shows what the second-color flash is on.",
			"Options: the General, Extra and Info pages scroll (mouse wheel or scroll bar), so their cards no longer run over each other; the commands list gets the room it needs.",
		},
	},
	{
		version = "1.5.17",
		items = {
			"WoW Forever Paladin: Judgement is only suggested while you have a seal up (it unleashes your seal, so with none it can't be cast). With no seal, the seal comes first.",
			"Smoother HUD on WoW Forever: when nothing is ready, the main icon shows the next spell to come off cooldown (dimmed, with its countdown) instead of going blank, however long the wait.",
			"Enemy names on nameplates show the mob's level to the left, colored by difficulty like the quest log (\"??\" for far above you, \"+\" for elites). /rcr platelevel turns it off and on.",
			"Questie: with name-only nameplates, hovering the invisible plate around a name gave the game's nameplate tooltip, which Questie can't read on WoW Forever, so its quest lines went missing on and off. That tooltip is now swapped for the mob's normal one. Names stay clickable (through walls too); /rcr plateclick makes the hidden plates click-through instead.",
			"A blank lasting under half a second keeps the last suggestion, so the icon doesn't blink empty between updates.",
		},
	},
}
