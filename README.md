# RCRotations

Rotation helper for **WoW Forever** (Classic Era combat on the camelot client, interface `16001`).

It shows the next three abilities on a small HUD, flashes the matching action-bar button, and also tracks heals, long defense buffs, interrupts, purges, cleanses, and weapon imbues. It does **not** cast spells for you.

Maintained by **Rob** · Version **1.0.0**

## Credits

RCRotations is a fork of **[Forever Rotation](https://github.com/ssablon/ForeverRotation)** by **Vohnka** ([wow-forever.fr](https://wow-forever.fr)), released under the MIT license. The original copyright notice is kept in `LICENSE`. Please report RCRotations problems to Rob, not to the original project.

## Requirements

One folder works on every Classic client:

| Client | AddOns folder |
| --- | --- |
| Classic Era | `World of Warcraft\_classic_era_\Interface\AddOns` |
| TBC Anniversary | `World of Warcraft\_anniversary_\Interface\AddOns` |
| MoP Classic | `World of Warcraft\_classic_\Interface\AddOns` |
| WoW Forever | `World of Warcraft\_classic_beta_\Interface\AddOns` |

Retail is not supported: since Midnight, combat state is hidden from addons, so a rotation helper can't make decisions there.

RCRotations only uses **WoWSims** rotations. On **MoP Classic** they come bundled from [WoWSims](https://github.com/wowsims/mop) (MIT): every class, every DPS and tank spec, plus Holy Priest, picked from your current specialization, and they update with the addon. On other clients (Era, TBC, Forever), and for MoP specs WoWSims doesn't cover, you import the rotation you want from wowsims.com; on first login with nothing to use, a window offers the import. There are no built-in rotation lists. Spells resolve by **name + spellbook**, so ranks and remapped IDs still match.

## WoWSims rotations

- `tools/wowsims_convert.py` turns WoWSims' rotation files into `SimData_Mists.lua` (generated; don't edit by hand). The file header records the WoWSims commit it came from.
- `Sim.lua` evaluates those rotations live each tick and fills the HUD with the first three castable spells.
- A GitHub Action (`Sync WoWSims rotations`) runs daily. When WoWSims changes a rotation it either releases automatically or opens a pull request with an import report (what converted, what was approximated, anything unsupported).
- **Automatic releases:** set the repository variable `AUTO_RELEASE` to `true` (Settings → Secrets and variables → Actions → Variables). Then a rotation update that passes the safety check (tests pass, no rotation removed, nothing unsupported) is committed, the patch version is bumped, and a release is published to GitHub and, when configured, CurseForge/Wago. Anything that fails the check still arrives as a pull request.
- Your own rotations: export one from wowsims.com (Rotation tab → Export → JSON) and save it as `rotations/mists/<class>/<spec>/<name>.json`. Pushing it starts the sync job, which opens a PR adding it next to the WoWSims ones (shown as "(custom)" in the picker). See `rotations/mists/README.md`.
- Import in game: Options → Rotation → **Import WoWSims** (or `/rcr import`). Paste a rotation exported from wowsims.com; it's converted in game (same rules as the Python converter, checked by the tests) and saved account-wide for the current spec.
- Never-suggest list: spells WoWSims uses for simulation value but a player saves (defensives, raid cooldowns) are skipped by default; right-click a HUD spell to add more, `/rcr unblock <spell>` to undo. Applied on top of every rotation, so WoWSims updates don't undo it.
- In game: when your spec has more than one WoWSims rotation (for example Frost DK "Obliterate" vs "Masterfrost"), a picker opens on login or spec change. The choice is saved per character and spec. `/rcr apl` reopens the picker.
- Tests: `pip install lupa && python3 tools/test_sim.py`.


## Install

1. Copy the `RCRotations` folder into the AddOns folder of each client you play (table above).
2. Restart the client or type `/reload`.
3. Enable **RCRotations** in the add-on list.

The folder must contain both `.toc` files, the `.lua` files, and the `images/` directory.

## Releases

Pushing a version tag (for example `v1.2.0`) to GitHub builds the addon zip with the BigWigs packager and attaches it to a GitHub release. Once a CurseForge project ID is in the TOC (`## X-Curse-Project-ID`) and the `CF_API_KEY` secret is set, the same run uploads to CurseForge (and Wago with `WAGO_API_TOKEN` / `## X-Wago-ID`).

## What it does

| Surface | Role |
| --- | --- |
| **Rotation HUD** | Next 3 combat abilities from your WoWSims rotation |
| **Defense** | Missing long buffs / auras, plus emergency buttons when health is low |
| **Weapon** | Missing weapon imbue (shaman / rogue poisons, etc.) |
| **Interrupt / Purge / Cleanse** | Target interrupt, enemy magic purge, dispellable debuffs |
| **Spellflash** | Skull overlay on the action-bar button |
| **Classic timing** | White-hit swing (main + off-hand), hunter auto-shot clip, energy tick |

### Spellflash colors

| Color | Meaning |
| --- | --- |
| White skull | Next damage / utility spell |
| Green skull | Heal (only when someone actually needs healing) |
| Blue skull | Defense buff |
| Red skull | Weapon imbue |
| Red bar tint | Out of range (action bars only, not the HUD) |

### Combat list vs defense

- **Rotation** = short combat spells (strikes, shocks, heals, judgements…).
- **Defense** = buffs that last more than one minute, auras, and long self-buffs (Blessing of Might, Devotion Aura, Mark of the Wild, Inner Fire, aspects, Battle Shout, armors…). Those never enter the combat queue.
- Unchecked spells stay in the editor but are ignored in combat.
- Custom spells are added from the cursor (spellbook drag). Test / OLD spells are rejected.

### Heals

Heals are suggested from the **friendly unit that needs them** (mouseover, friendly target, then you / party if you are attacking a mob).

Examples (paladin):

- Holy Shock / Holy Light around **80%**
- Flash of Light around **70%**
- Lay on Hands around **20%**

Full health → no heal suggestion, damage rotation stays visible. Same idea for Priest, Shaman, and Druid (fast heal vs big heal vs HoT).

### Profiles

Four profiles, all saved independently:

| Profile | Slash | Typical use |
| --- | --- | --- |
| Base | `/rcr base` | Default / shared |
| PvE | `/rcr jce` or `/rcr pve` | PvE |
| PvP | `/rcr jcj` or `/rcr pvp` | PvP |
| Customs | `/rcr custom` | Experiments |

Switch from the options window or the class-colored HUD button. **Reset** only wipes the **selected** profile. You can export / import a profile as text. Optional auto-switch uses PvE or PvP from the instance type.

### Combat modes

`Auto` / `Single` / `AoE` / `Burst`. Add, remove, and reorder are **per mode**. Auto uses the single-target list until enough enemies are nearby (default: 3).

### Roles

Per class: damage, tank, heal, and the extra Classic styles (hunter range/melee, shaman caster/melee, druid hybrid / cat / bear). The HUD role button cycles the styles that exist for your class.

### Extra options

- Hide the HUD when dead, mounted, eating, or in town
- Only suggest spells that are on your action bars
- Auto PvE / PvP profile
- Group dispel limited to types your class can remove
- Classic combat timing (white hits, dual wield, auto-shot, energy)
- Overlay colors and alert volume

## Slash commands

`/rcr`, `/rcrot`, or `/rcrotations`

| Command | Action |
| --- | --- |
| *(no argument)* | Print help |
| `lock` / `unlock` | Lock or move the HUD |
| `reset` | Reset HUD positions |
| `resetall` | Reset the **current** profile lists |
| `role` | Cycle playstyle |
| `mode` | Cycle combat mode |
| `profile` | Cycle profile |
| `base` / `jce` / `jcj` / `custom` | Jump to that profile |
| `menu` / `options` | Open the configuration window |

Open options with `/rcr options` or a left-click on the minimap button. Right-click the minimap button to lock or unlock the windows.

When locked, the mouse clicks through the HUD. The padlock stays clickable.

## Files

```
RCRotations.toc              # standard load
RCRotations_Camelot.toc      # camelot / Forever load
Credits.lua
Locale.lua                     # enUS + 10 locales
API.lua                        # spell resolve, auras, ready, heals
Data.lua                       # IDs, racials, interrupts, cleanse
Physics.lua                    # swing / auto-shot / energy timing
Lists.lua                      # default APLs and defense lists
APL.lua                        # saved lists, merge, add/remove
Share.lua                      # profile import / export
UI.lua                         # HUD
Options.lua                    # configuration
Glow.lua                       # action-bar skull flash
Rotations.lua                  # queue builders
Core.lua                       # profiles, events, slash
images/                        # skull, roles, lock, minimap
```

Saved variables: `RCRotationsDB`, `RCRotationsCharDB`, `RCRotationsCreditDB` (login credit line toggle).

## Notes

- This is a **helper**, not a bot. You still press the keys.
- Racials appear in the editor (off by default). Air Walk is never put in the combat list.
- Do not overwrite Blizzard spell APIs from other add-ons; this one reads `C_Spell` / `C_SpellBook` and never patches them.

## Original project

RCRotations is based on Forever Rotation by Vohnka. The original project, for reference:

- Source: [https://github.com/ssablon/ForeverRotation](https://github.com/ssablon/ForeverRotation)
- CurseForge: [https://www.curseforge.com/wow/addons/forever-rot](https://www.curseforge.com/wow/addons/forever-rot)
- Website: [https://wow-forever.fr](https://wow-forever.fr)

Report RCRotations problems to Rob, not to the original project.

## License

[MIT](LICENSE). Original work © Vohnka / wow-forever.fr; RCRotations modifications © Rob. Free to use, modify, fork, and redistribute, as long as the copyright notices and license are kept.
