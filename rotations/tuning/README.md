# Tuning: fixes on top of WoWSims rotations

WoWSims rotations are built for a simulator. Sometimes a line needs a human fix: a spell that
needs a condition the sim doesn't model, one that should come earlier, or one a player saves for
later. Put those fixes in `mists.json` here. They're applied in game to **every** rotation for
the spec, bundled or imported, so you write a fix once and it survives every WoWSims update.

After you edit the file, the sync job rebuilds the addon data (and releases it if
`AUTO_RELEASE` is on). A typo in the file stops the build with a clear message instead of
shipping a broken fix.

## Where a fix applies

| Key | Applies to |
| --- | --- |
| `"*"` | every class and spec |
| `"death_knight/unholy"` | every Unholy DK rotation |
| `"death_knight/frost/obliterate"` | only that one rotation (WoWSims file name) |

Class and spec names match WoWSims: `death_knight/frost`, `paladin/retribution`,
`monk/windwalker`, `warlock/destruction`, and so on.

## The four rules

```json
{
  "death_knight/unholy": {
    "require": [ { "spell": 63560, "when": "pet.buff(91342).stacks >= 5",
                   "why": "Dark Transformation needs 5 Shadow Infusion" } ],
    "block":   [ { "spell": 42650, "why": "Army is a pre-pull cooldown" } ],
    "move":    [ { "spell": 49206, "before": 77575 } ],
    "add":     [ { "spell": 47568, "when": "runes.blood == 0 and runes.frost == 0",
                   "before": 85948, "why": "Empower Rune Weapon when out of runes" } ]
  }
}
```

- **require**: only suggest the spell when `when` is true (on top of the rotation's own condition).
- **block**: never suggest the spell for this spec. Players can still turn it back on with
  `/rcr unblock <spell>`.
- **move**: put the spell `"before"` another spell, or `"to": "top"` / `"bottom"`.
- **add**: a new line, placed `"before"` a spell or `"at": "top"` / `"bottom"` (default bottom),
  with an optional `when`.

`why` is just a note for people reading the file. Spell IDs are the numbers in Wowhead URLs
(`wowhead.com/mop-classic/spell=63560`).

## Condition syntax (`when`)

| Write | Means |
| --- | --- |
| `buff(51124)` / `buff(51124).down` | you have / don't have the aura |
| `buff(51124).remains`, `.stacks`, `.known` | seconds left, stack count, talent known |
| `pet.buff(91342).stacks`, `target.buff(...)` | same, on your pet or target |
| `debuff(55095)` / `.down` / `.remains` / `.stacks` | your DoT/debuff on the target |
| `cooldown(49020).ready`, `.remains`, `.charges` | cooldown state |
| `spell(49020).usable`, `.known`, `.cast_time` | castable now, learned, cast time |
| `health.pct`, `target.health.pct`, `mana`, `mana.pct` | health and mana |
| `rage energy focus runic_power combo_points chi` | resources |
| `holy_power shadow_orbs soul_shards demonic_fury burning_embers` | class resource |
| `runes.blood runes.frost runes.unholy runes.death` | ready runes |
| `targets combat_time time_to_die execute(20) moving gcd.ready` | fight state |

Numbers: `5`, `2.5s`, `500ms`, `35%`, `true`, `false`. Operators: `and or not`,
`== != < <= > >=`, `+ - * /`, parentheses.

Examples:

- `debuff(55095).remains < 3s and targets >= 3`
- `not buff(51124) or target.health.pct < 35%`
- `runic_power >= 80 or cooldown(49020).remains > 2s`
