-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
	{
		version = "1.5.3",
		items = {
			"WoW Forever Paladins: two new playstyles, picked with the playstyle button (or /rcr role). - Seal Twist, for Retribution with Twist of Light: keeps a seal up, then swaps between Seal of Command and Seal of Righteousness once per swing, so every swing gets both seals (the replaced seal's Echo). It waits until your last swing has used the Echo, and stops twisting below 20% mana. Judgement, Hammer of Wrath, Holy Strike and the rest fit around it. - Shockadin, for Holy Shock builds: Seal of Righteousness, Divine Favor into Holy Shock, Light's Vigil on the enemy (your next Holy Shock skips its cooldown), Judgement, Consecration, Holy Strike. A damage Paladin who knows Holy Shock is switched to Shockadin once; pick Damage again and it stays.",
			"When there's nothing to press (low levels, or everything on cooldown), melee characters now see Auto Attack instead of the empty skull. It flashes on your bar until you start swinging, then stays on the HUD without flashing, so you don't click Attack again and stop your swings. This covers Paladins, Warriors, Rogues, tanks, Enhancement Shamans, melee Hunters, and Druids in Cat or Bear Form.",
			"WoW Forever: multi-target spells work in fights again. Forever doesn't let addons check how close enemies are during combat, so spells that need several enemies within a few yards (Consecration, Whirlwind, Swipe, your own \"enemies within X yards\" rules...) counted none and never showed. The enemy count now uses your enemy nameplates in the fight when the distance can't be checked, and it also works when Forever hides whether a unit is hostile or in combat. Enemy nameplates have to be turned on, but they can be invisible (shrunk to nothing or hidden): the addon only needs them to exist, not to be seen.",
			"Enemy names only (/rcr plates) works on WoW Forever's new nameplates. They showed the whole plate (health bar, level, health number, icons). Now only the enemy's name shows, above the character, and it stays that way when the game updates the plate. Quest and loot icons sit right beside the name instead of far out at the ends of the hidden bar (Blizzard and ElvUI nameplates).",
			"WoW Forever: missing buff reminders above the main icon stay up in combat. Forever hides your buffs from addons during a fight, so they used to vanish. Now the ones missing when the fight started stay, and each goes away as soon as you cast it.",
		},
	},
	{
		version = "1.5.2",
		items = {
			"Wrath Titan Reforged (client 3.80) is listed as supported, so CurseForge offers RCRotations to Titan Reforged players. It works there like on Wrath Classic: import a rotation from wowsims.com or make one in the Workshop app.",
			"The GitHub release and test jobs use GitHub's newer Node 24 actions (no more Node.js 20 warning).",
		},
	},
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
			"WoW Forever: a new test runs the whole addon on a simulated Forever client for all nine classes and every role, through fights where the game hides combat data from addons (secret values), and checks a spell is always suggested and flashed. It runs on every update.",
			"WoW Forever: a few more checks (is the target alive, hostile, targeting you) now treat a hidden value as unknown instead of risking an error.",
			"WoW Forever: name-only nameplates work when the game hides whether a plate is an enemy in combat (the bar fades through the game's own secret-safe call).",
			"WoW Forever: the menu, picker, import and What's new windows no longer measure wrapped text. The original Forever Rotation found that this can freeze the Forever client.",
			"WoW Forever: missing buff reminders, with a Forever buff list for every class: Mark of the Wild and Thorns (bear), Fortitude, Inner Fire, Divine Spirit and Shadowform, Arcane Intellect and an armor, a paladin blessing and aura (any of yours or another paladin's counts, Greater ones too) and Righteous Fury (tank), hunter aspect, Trueshot Aura and pet, shaman shield and weapon imbue, rogue poisons, warlock armor and demon (the one you summoned last), Battle Shout. Group buffs (Gift of the Wild, Prayer of Fortitude, Arcane Brilliance) count, and in a group your Mark, Fortitude, Intellect and Spirit are checked on everyone near you. Reminders show out of combat only: Forever hides buffs from addons in combat, and the bar stays empty whenever it can't read them.",
			"The addon's owner is now listed as Raw Card.",
		},
	},
}
