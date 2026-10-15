# Your own MoP rotations

Rotations in this folder are added next to the WoWSims ones every time the converter runs
(the nightly sync and any manual run). They show up in the in-game picker with "(custom)".

Put each file at:

    rotations/mists/<class>/<spec>/<name>.json

Class and spec folder names match WoWSims: `death_knight/frost`, `monk/windwalker`,
`paladin/retribution`, `warlock/destruction`, and so on.

To make one: open the class sim on wowsims.com (MoP), go to the **Rotation** tab, switch to
APL, edit it, then use **Export → JSON** and save the file here. Both a rotation-only export
and a full settings export work.
