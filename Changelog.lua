-- Generated from VERSION.txt by tools/changelog_lua.py. Don't edit by hand.
local addonName, ns = ...
ns.CHANGELOG = {
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
	{
		version = "1.5.4",
		items = {
			"WoW Forever: proper rotations for every class, built in. RCRotations now includes the WoWSims Forever rotations (31 of them: Retribution with Unsealed Wrath, Shockadin, Protection, Affliction, Demonology, Destruction, SM/Ruin, Arcane, Fire, Frost, Frostfire, Beast Mastery, Marksmanship, Survival, Arms, Fury, Protection, Balance, Feral Cat and Bear, Rogue, Shadow, Smite, Elemental, Enhancement...), updated automatically as WoWSims updates them.",
			"WoW Forever: Auto picks the rotation for you (the default). Below level 20 it uses a simple starter rotation for your class; from 20 on, the rotation for your playstyle whose talent build is closest to yours. Respec, level up or change playstyle and it follows (chat says so). Healing playstyles keep the built-in heal lists.",
			"WoW Forever Paladins: a seal you already have isn't asked for again. The addon now reads your seal (and how long seals last) whenever your buffs are visible, so one cast before a login or /reload counts, and it no longer assumes you have no seal when it can't tell.",
			"Spells you haven't learned (talents like Blessing of Kings) are no longer suggested. Right after login the addon could count a spell as known just because the game recognised its name.",
			"Choose a rotation yourself any time with /rcr apl: Auto is first, then every rotation for your class. A rotation you made in the Workshop app is used ahead of the built-in ones.",
			"WoW Forever Paladins: two new playstyles, picked with the playstyle button (or /rcr role). - Seal Twist, for Retribution with Unsealed Wrath: each swing stores an Echo of your seal (up to 3), and a hit with a different seal spends them. Same as the WoWSims Forever rotation: 3 swings on Seal of Command, swap to Seal of Righteousness for 1 swing, swap back, with Judgement, Hammer of Wrath, Holy Strike, Consecration and Exorcism around it. - Shockadin, for Holy Shock builds: Seal of Righteousness, Divine Favor into Holy Shock, Light's Vigil on the enemy (your next Holy Shock skips its cooldown), Judgement, Consecration, Holy Strike. - A damage Paladin with Unsealed Wrath is switched to Seal Twist once, with Holy Shock to Shockadin; pick Damage again and it stays.",
			"WoW Forever: rotations imported from WoWSims' Forever sim work. They used to show only Auto Attack: swing timing, \"spell in range\" and \"talent known\" weren't understood, so most lines were dropped. Your seal and Unsealed Wrath echoes are followed in combat (where the game hides your buffs), the first seal is suggested when you have none, and Hammer of Wrath (below 20%) and Exorcism (Undead and Demons) only show when they can be used.",
			"WoW Forever Paladin spell fixes: Holy Strike, Seal of Righteousness, Seal of Fury and Holy Shock use Forever's spell IDs, and Crusader Strike (not in Forever) is gone from the lists.",
			"When there's nothing to press (low levels, or everything on cooldown), melee characters now see Auto Attack instead of the empty skull. It flashes on your bar until you start swinging, then stays on the HUD without flashing, so you don't click Attack again and stop your swings. This covers Paladins, Warriors, Rogues, tanks, Enhancement Shamans, melee Hunters, and Druids in Cat or Bear Form.",
			"WoW Forever: multi-target spells work in fights again. Forever doesn't let addons check how close enemies are during combat, so spells that need several enemies within a few yards (Consecration, Whirlwind, Swipe, your own \"enemies within X yards\" rules...) counted none and never showed. The enemy count now uses your enemy nameplates in the fight when the distance can't be checked, and it also works when Forever hides whether a unit is hostile or in combat. Enemy nameplates have to be turned on, but they can be invisible (shrunk to nothing or hidden): the addon only needs them to exist, not to be seen.",
			"Enemy names only (/rcr plates) works on WoW Forever's new nameplates. They showed the whole plate (health bar, level, health number, icons). Now only the enemy's name shows, above the character, and it stays that way when the game updates the plate. Quest and loot icons sit right beside the name instead of far out at the ends of the hidden bar (Blizzard and ElvUI nameplates).",
			"WoW Forever: missing buff reminders above the main icon stay up in combat. Forever hides your buffs from addons during a fight, so they used to vanish. Now the ones missing when the fight started stay, and each goes away as soon as you cast it.",
		},
	},
}
