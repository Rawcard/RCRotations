local addonName, ns = ...
local S = ns.Spell
local D, P, W, H, R, Pr, Sh, M, L = S.Druid, S.Paladin, S.Warrior, S.Hunter, S.Rogue, S.Priest, S.Shaman, S.Mage, S.Warlock

local function step(key, id, opt, enabled)
	return { key = key, id = id, opt = opt or {}, on = enabled ~= false }
end

local mageArmors = { M.MageArmor, M.IceArmor, M.FrostArmor }
local lockSkins = { L.DemonArmor, L.DemonSkin }
local palaSeals = { P.SealCommand, P.SealFury, P.SealRighteousness, P.SealCrusader, P.SealLight, P.SealWisdom, P.SealJustice }
local palaAuras = {
	P.DevotionAura,
	P.RetributionAura,
	P.ConcentrationAura,
	P.SanctityAura,
	P.FireResistAura,
	P.FrostResistAura,
	P.ShadowResistAura,
}
local palaBlessings = {
	P.BlessingMight,
	P.BlessingKings,
	P.BlessingWisdom,
	P.BlessingSalvation,
	P.BlessingLight,
	P.BlessingSanctuary,
}
local hunterAspects = { H.AspectHawk, H.AspectMonkey, H.AspectWild, H.AspectCheetah, H.AspectPack, H.AspectBeast }
local hunterStings = { H.SerpentSting, H.ViperSting, H.ScorpidSting }
local lockCurses = { L.CurseofAgony, L.CurseofElements, L.CurseofShadow, L.BaneofHavoc }
-- Bleeds / armor DoTs ConROC skips on these creature types.
local bleedCreatures = { "mechanical", "elemental", "undead" }
local undeadDemon = { "undead", "demon" }

-- Noyau combat Era (ConROC Classic), 1–60. Auto = liste mono. Pas de SoD / Midnight.
-- Rotation lists are no longer bundled: RCRotations only uses WoWSims
-- rotations (SimData_*.lua, generated) and ones imported in game (SimImport.lua).
-- These stay as empty tables so older code paths find nothing.
ns.APLDefaults = {}
ns.APLModes = {}

-- Defense / long-buff reminders (not rotations).
ns.DefDefaults = {
	DRUID = {
		damage = {
			step("MarkoftheWild", D.MarkoftheWild, { nobuff = true }),
			step("Thorns", D.Thorns, { nobuff = true }),
			step("Moonkin", D.Moonkin, { nobuff = true }),
			step("Barkskin", D.Barkskin, { combat = true, hp = 50 }),
			step("NaturesGrasp", D.NaturesGrasp, { combat = true, hp = 40 }),
		},
		tank = {
			step("MarkoftheWild", D.MarkoftheWild, { nobuff = true }),
			step("Thorns", D.Thorns, { nobuff = true }),
			step("Barkskin", D.Barkskin, { combat = true, hp = 60 }),
			step("FrenziedRegen", D.FrenziedRegen, { combat = true, hp = 40 }),
			step("NaturesGrasp", D.NaturesGrasp, { combat = true, hp = 40 }),
		},
		heal = {
			step("MarkoftheWild", D.MarkoftheWild, { nobuff = true }),
			step("Thorns", D.Thorns, { nobuff = true }),
			step("Barkskin", D.Barkskin, { combat = true, hp = 50 }),
			step("Innervate", D.Innervate, { combat = true, hp = 35 }),
		},
		cat = {
			step("MarkoftheWild", D.MarkoftheWild, { nobuff = true }),
			step("Thorns", D.Thorns, { nobuff = true }),
			step("Barkskin", D.Barkskin, { combat = true, hp = 50 }),
		},
		bear = {
			step("MarkoftheWild", D.MarkoftheWild, { nobuff = true }),
			step("Thorns", D.Thorns, { nobuff = true }),
			step("Barkskin", D.Barkskin, { combat = true, hp = 60 }),
			step("FrenziedRegen", D.FrenziedRegen, { combat = true, hp = 40 }),
		},
	},
	PALADIN = {
		damage = {
			step("DevotionAura", P.DevotionAura, { nobuff = true, anybuff = palaAuras }),
			step("RetributionAura", P.RetributionAura, { nobuff = true, anybuff = palaAuras }),
			step("SanctityAura", P.SanctityAura, { nobuff = true, anybuff = palaAuras }),
			step("ConcentrationAura", P.ConcentrationAura, { nobuff = true, anybuff = palaAuras }),
			step("FireResistAura", P.FireResistAura, { nobuff = true, anybuff = palaAuras }),
			step("FrostResistAura", P.FrostResistAura, { nobuff = true, anybuff = palaAuras }),
			step("ShadowResistAura", P.ShadowResistAura, { nobuff = true, anybuff = palaAuras }),
			step("BlessingMight", P.BlessingMight, { nobuff = true, anybuff = palaBlessings }),
			step("BlessingKings", P.BlessingKings, { nobuff = true, anybuff = palaBlessings }),
			step("BlessingWisdom", P.BlessingWisdom, { nobuff = true, anybuff = palaBlessings }),
			step("VoiceOfTruth", P.VoiceOfTruth, { combat = true, hp = 50 }),
			step("DivineProtection", P.DivineProtection, { combat = true, hp = 40 }),
			step("DivineShield", P.DivineShield, { combat = true, hp = 25 }),
			step("LayonHands", P.LayonHands, { combat = true, hp = 15 }),
		},
		tank = {
			step("RighteousFury", P.RighteousFury, { nobuff = true }),
			step("DevotionAura", P.DevotionAura, { nobuff = true, anybuff = palaAuras }),
			step("RetributionAura", P.RetributionAura, { nobuff = true, anybuff = palaAuras }),
			step("SanctityAura", P.SanctityAura, { nobuff = true, anybuff = palaAuras }),
			step("ConcentrationAura", P.ConcentrationAura, { nobuff = true, anybuff = palaAuras }),
			step("BlessingKings", P.BlessingKings, { nobuff = true, anybuff = palaBlessings }),
			step("BlessingMight", P.BlessingMight, { nobuff = true, anybuff = palaBlessings }),
			step("HolyShield", P.HolyShield, { combat = true, hp = 80 }),
			step("TemplarsBulwark", P.TemplarsBulwark, { combat = true, hp = 60 }),
			step("VoiceOfTruth", P.VoiceOfTruth, { combat = true, hp = 50 }),
			step("DivineProtection", P.DivineProtection, { combat = true, hp = 40 }),
			step("DivineShield", P.DivineShield, { combat = true, hp = 25 }),
			step("LayonHands", P.LayonHands, { combat = true, hp = 15 }),
		},
		heal = {
			step("DevotionAura", P.DevotionAura, { nobuff = true, anybuff = palaAuras }),
			step("ConcentrationAura", P.ConcentrationAura, { nobuff = true, anybuff = palaAuras }),
			step("RetributionAura", P.RetributionAura, { nobuff = true, anybuff = palaAuras }),
			step("BlessingWisdom", P.BlessingWisdom, { nobuff = true, anybuff = palaBlessings }),
			step("BlessingKings", P.BlessingKings, { nobuff = true, anybuff = palaBlessings }),
			step("VoiceOfTruth", P.VoiceOfTruth, { combat = true, hp = 50 }),
			step("DivineProtection", P.DivineProtection, { combat = true, hp = 40 }),
			step("DivineShield", P.DivineShield, { combat = true, hp = 25 }),
			step("LayonHands", P.LayonHands, { combat = true, hp = 15 }),
		},
	},
	WARRIOR = {
		damage = {
			step("BattleShout", W.BattleShout, { nobuff = true }),
			step("BerserkerRage", W.BerserkerRage, { combat = true, hp = 60 }),
			step("LastStand", W.LastStand, { combat = true, hp = 35 }),
			step("ShieldWall", W.ShieldWall, { combat = true, hp = 25 }),
			step("Retaliation", W.Retaliation, { combat = true, hp = 40 }),
		},
		tank = {
			step("BattleShout", W.BattleShout, { nobuff = true }),
			step("ShieldBlock", W.ShieldBlock, { combat = true, hp = 70 }),
			step("LastStand", W.LastStand, { combat = true, hp = 35 }),
			step("ShieldWall", W.ShieldWall, { combat = true, hp = 25 }),
		},
	},
	HUNTER = {
		damage = {
			step("AspectHawk", H.AspectHawk, { nobuff = true, anybuff = hunterAspects }),
			step("AspectMonkey", H.AspectMonkey, { nobuff = true, anybuff = hunterAspects }),
			step("AspectWild", H.AspectWild, { nobuff = true, anybuff = hunterAspects }),
			step("TrueshotAura", H.TrueshotAura, { nobuff = true }),
			step("Deterrence", H.Deterrence, { combat = true, hp = 40 }),
			step("FeignDeath", H.FeignDeath, { combat = true, hp = 25 }),
			step("Disengage", H.Disengage, { combat = true, hp = 35 }),
		},
	},
	ROGUE = {
		damage = {
			step("Preparation", R.Preparation, { combat = true }),
			step("Evasion", R.Evasion, { combat = true, hp = 40 }),
			step("Vanish", R.Vanish, { combat = true, hp = 20 }),
			step("Sprint", R.Sprint, { combat = true, hp = 25 }),
			step("Feint", R.Feint, { combat = true, hp = 50 }),
		},
	},
	PRIEST = {
		damage = {
			step("InnerFire", Pr.InnerFire, { nobuff = true }),
			step("PowerWordFortitude", Pr.PowerWordFortitude, { nobuff = true }),
			step("Shadowform", Pr.Shadowform, { nobuff = true }),
			step("VampiricEmbrace", Pr.VampiricEmbrace, { nobuff = true }),
			step("ShadowProtection", Pr.ShadowProtection, { nobuff = true }),
			step("PowerWordShield", Pr.PowerWordShield, { combat = true, hp = 70, nobuff = true, nodebuff = Pr.WeakenedSoul }),
			step("DarkSacrifice", Pr.DarkSacrifice, { combat = true, hp = 40 }, false),
			step("Fade", Pr.Fade, { combat = true, hp = 50 }),
		},
		heal = {
			step("InnerFire", Pr.InnerFire, { nobuff = true }),
			step("PowerWordFortitude", Pr.PowerWordFortitude, { nobuff = true }),
			step("DivineSpirit", Pr.DivineSpirit, { nobuff = true }),
			step("ShadowProtection", Pr.ShadowProtection, { nobuff = true }),
			step("PowerWordShield", Pr.PowerWordShield, { combat = true, hp = 70, nobuff = true, nodebuff = Pr.WeakenedSoul }),
			step("Fade", Pr.Fade, { combat = true, hp = 50 }),
		},
	},
	SHAMAN = {
		damage = {
			step("LightningShield", Sh.LightningShield, { nobuff = true }),
			step("WaterShield", Sh.WaterShield, { nobuff = true }),
			step("CalloftheElements", Sh.CalloftheElements, { combat = true }, false),
			step("CalloftheAncestors", Sh.CalloftheAncestors, { combat = true }, false),
			step("CalloftheSpirits", Sh.CalloftheSpirits, { combat = true }, false),
			step("TotemicRecall", Sh.TotemicRecall, { combat = true }, false),
			step("TotemicProjection", Sh.TotemicProjection, { combat = true }, false),
			step("Stoneclaw", Sh.Stoneclaw, { combat = true, hp = 50 }),
			step("GroundingTotem", Sh.GroundingTotem, { combat = true, hp = 60 }),
			step("TremorTotem", Sh.TremorTotem, { combat = true, hp = 70 }),
		},
		heal = {
			step("WaterShield", Sh.WaterShield, { nobuff = true }),
			step("LightningShield", Sh.LightningShield, { nobuff = true }),
			step("TotemicProjection", Sh.TotemicProjection, { combat = true }, false),
			step("GroundingTotem", Sh.GroundingTotem, { combat = true, hp = 60 }),
			step("Stoneclaw", Sh.Stoneclaw, { combat = true, hp = 40 }),
			step("HealingStream", Sh.HealingStream, { combat = true, hp = 80 }),
		},
	},
	MAGE = {
		damage = {
			step("ArcaneIntellect", M.ArcaneIntellect, { nobuff = true }),
			step("MageArmor", M.MageArmor, { nobuff = true, anybuff = mageArmors }),
			step("IceArmor", M.IceArmor, { nobuff = true, anybuff = mageArmors }),
			step("FrostArmor", M.FrostArmor, { nobuff = true, anybuff = mageArmors }),
			step("AmplifyMagic", M.AmplifyMagic, { nobuff = true }),
			step("ManaShield", M.ManaShield, { combat = true, hp = 55 }),
			step("IceBarrier", M.IceBarrier, { combat = true, hp = 80 }),
			step("FireWard", M.FireWard, { combat = true, hp = 70 }),
			step("FrostWard", M.FrostWard, { combat = true, hp = 70 }),
			step("IceBlock", M.IceBlock, { combat = true, hp = 30 }),
			step("Blink", M.Blink, { combat = true, hp = 25 }),
		},
	},
	WARLOCK = {
		damage = {
			step("DemonArmor", L.DemonArmor, { nobuff = true, anybuff = lockSkins }),
			step("DemonSkin", L.DemonSkin, { nobuff = true, anybuff = lockSkins }),
			step("UnendingBreath", L.UnendingBreath, { nobuff = true }),
			step("ShadowWard", L.ShadowWard, { combat = true, hp = 60 }),
			step("HowlofTerror", L.HowlofTerror, { combat = true, hp = 35 }),
		},
	},
}

-- Alias de rôles pour le fallback éditeur / spec.
ns.DefDefaults.DRUID.hybrid = ns.DefDefaults.DRUID.damage
ns.DefDefaults.HUNTER.range = ns.DefDefaults.HUNTER.damage
ns.DefDefaults.HUNTER.melee = ns.DefDefaults.HUNTER.damage
ns.DefDefaults.SHAMAN.caster = ns.DefDefaults.SHAMAN.damage
ns.DefDefaults.SHAMAN.melee = ns.DefDefaults.SHAMAN.damage

local function stripMaintFromApl(node)
	if type(node) ~= "table" then
		return
	end
	if node[1] and type(node[1]) == "table" and node[1].key then
		for i = #node, 1, -1 do
			local id = node[i].id
			if id and ns.MAINTENANCE_BUFF_IDS and ns.MAINTENANCE_BUFF_IDS[id] then
				table.remove(node, i)
			end
		end
		return
	end
	for _, child in pairs(node) do
		if type(child) == "table" then
			stripMaintFromApl(child)
		end
	end
end
stripMaintFromApl(ns.APLDefaults)
stripMaintFromApl(ns.APLModes)
