-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.1",
		items = {
			"No flashing on your action bars while you're mounted. The HUD still shows what's next; the flashes come back as soon as you dismount. Missing buff reminders also wait until you dismount.",
			"All action-button flashes pulse in step: the red missing-buff flash pulses together with the rotation flash, so you can pick at a glance whether to attack or buff.",
			"In a party or raid, your raid buff (Fortitude, Kings, Mark of the Wild, Brilliance, Dark Intent, shouts, Horn of Winter...) is also checked on everyone near you. If someone in range is missing it (and has no equivalent buff), the reminder shows; hover it to see who.",
			"Paladin blessings and Warrior shouts: you can only keep one of your own up, so only one is ever reminded and flashed. Kings (or Battle Shout) by default; Might (or Commanding Shout) when someone else already covers stats (or attack power), including telling you to switch if you cast the one that's now doubled up.",
			"A \"What's new\" window at login with these notes and a button to copy the Workshop app link. Tick \"Don't show again for this version\" at the bottom to stop it until the next update. Open it anytime with /rcr news or the \"What's new\" button in the menu.",
			"A big \"Get the Workshop app\" button at the top of the menu, and a \"Copy app link\" button on the Rotation page. Press Ctrl+C in the box that opens, then paste the link into your web browser.",
			"RCRotations windows open side by side instead of on top of each other: the rotation picker, import, What's new and copy-link boxes line up to the right of the menu (the row shrinks a little if it wouldn't fit on your screen). Drag any of them to move the whole row. Closing the menu closes them all.",
		},
	},
	{
		version = "1.5.0",
		items = {
			"Missing buff reminders and name-only nameplates.",
			"Missing buffs show as a red-edged bar just above the main HUD icon, as wide as the icon and split between the missing buffs, and their buttons on your action bars flash bright red. A reminder goes away as soon as you have the buff, or the same kind of buff from someone else (Mark of the Wild, Blessing of Kings and Legacy of the Emperor all count as the stats buff, Battle Shout and Trueshot Aura count as Horn of Winter...). On MoP the game's own raid buff tracking decides what's covered. Hover an icon for its name.",
			"Every MoP class: raid buffs you provide, plus Death Knight presence, Druid Moonkin Form (in combat), Hunter aspect and pet, Mage armor, Monk stance, Paladin seal and Righteous Fury, Priest Inner Fire and Shadowform, Rogue poisons, Shaman shield and weapon imbues, Warlock pet (not with Grimoire of Sacrifice) and Warrior shouts.",
			"Seal, presence, Horn of Winter and Inner Fire moved out of the rotation into these reminders.",
			"Turn them off with /rcr buffs or Options > General > HUD.",
			"Name-only enemy nameplates: RCRotations counts enemies for AoE through enemy nameplates, so with nameplates off it always thinks there's one target. The new option (Options > Extra, or /rcr plates) turns enemy nameplates on and hides their health bars: you still see enemy names and cast bars. Works with Blizzard's nameplates and with ElvUI's (there the name stays centered, and the health %, level, target glow and highlight hide with the bar). Your old setting comes back when you turn it off. If nameplates are off, you get a one-time tip about it.",
		},
	},
	{
		version = "1.4.3",
		items = {
			"Locking the HUD sticks: once you lock it, it stays locked on every login and on all your characters, and they all share the same HUD position. Unlock it with the new \"Unlock HUD\" button at the top of the menu (/rcr), next to Role.",
		},
	},
}
