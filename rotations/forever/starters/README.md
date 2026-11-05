# Starter rotations (WoW Forever, levels 1-19)

One file per class, in WoWSims APL JSON (the same format as a WoWSims rotation
export). `tools/forever_convert.py` bundles them into `SimData_Forever.lua` as
"Starter (levels 1-19)". With the rotation set to Auto, the addon uses the
starter below level 20, then the WoWSims rotation closest to your talents.

Keep them to spells a low-level character has and that the game reports
reliably: reactive abilities (Overpower, Revenge, Riposte...) are left out,
because WoW Forever marks every spell unusable during the global cooldown and
the addon can't tell when they're really available.
