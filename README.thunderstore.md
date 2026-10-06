# OdinLookedAway

Odin saw nothing. Your achievements still count.

Prevents Valheim's cheat flags, clears existing flags as character and world data load or save, and keeps achievements eligible while preserving their objectives and difficulty requirements. Tested with Valheim 1.0.16.

## Features

- Dev commands do not mark the character or add to its cheat counter.
- Spawned, crafted, stacked, transferred, and dropped items stay free of cheat flags, including the damage-based marking path.
- Clears existing item flags when inventories/items load or pass through their normal boundaries.
- Cleans entity flags, cooking-slot flags, and production queues.
- Cleans serialized world records, including inventories and item stands outside loaded areas, before saving or sending them.
- Keeps achievement-specific statistics eligible with mods, dev commands, or cheated world modifiers.
- Avoids repeated `confirmcheats` prompts and removes the achievement disqualification message.

This does not unlock achievements automatically, reconstruct lost progress, reset historical cheat counts, alter item damage, change world modifiers, or bypass difficulty requirements. Ordinary command permissions and server administration rules still apply.

## Installation and multiplayer

Requires BepInExPack Valheim 5.4.2350. Install the package through your mod manager, or copy the included `BepInEx` folder into your game or mod-manager profile while the game is closed. The DLL belongs at `BepInEx/plugins/OdinLookedAway/OdinLookedAway.dll`; keep only one installed copy.

For complete coverage, install on **every participating client and the host/dedicated server**. Each client controls its own achievement eligibility and character data; the server and owning clients control entity writes and world persistence. An unpatched participant can still create/send contaminated data. A patched receiver cleans the known data it receives, but cannot prevent writes or saves on an unpatched process.

No settings, server sync, Jotunn, or configuration manager are required. The mod works on clients and dedicated servers once its patches install successfully.

## Backups and testing

**Back up your character and world before first use.** Cleared flags stay cleared when you save. Removing the DLL alone does not restore them; restoring the corresponding character/world backup does.

The maintainer has verified gameplay and achievement behavior. Automated compatibility checks target Valheim 1.0.16. Later game updates may change the patched methods or save formats; repeat the checks after an update.

Cleanup runs when data loads, saves, transfers, or passes through other patched methods. It does not edit save files while the game is closed. Unknown or malformed serialized item formats are preserved and logged; those payloads remain uncleaned.

## Troubleshooting and removal

Check `BepInEx/LogOutput.log` in the game or active mod-manager profile. A successful startup logs `Odin looked away`. If it logs `could not install every required patch`, the mod removes all of its patches and disables itself for that process. Check the game version, BepInEx installation, and other mods that patch cheat or achievement methods.

`Preserving an unrecognized item payload` or `Preserving an unrecognized legacy container payload` means that data was left unchanged. Repeated errors for the same data key are suppressed for the session, so one message can represent more than one affected item or container.

To uninstall, close the game and remove `OdinLookedAway.dll`, or uninstall it through your mod manager. To undo saved cleanup, also restore the corresponding character and world backups.

The [GitHub repository](https://github.com/Michael-Ziluck/OdinLookedAway) includes source, build scripts, verification notes, and save-aware rollback tools. [Report issues](https://github.com/Michael-Ziluck/OdinLookedAway/issues) with your game/mod versions, whether you were playing locally or on a server, steps to reproduce, and relevant log lines.

MIT licensed. [Reference and artwork attribution](https://github.com/Michael-Ziluck/OdinLookedAway/blob/main/ATTRIBUTION.md).

## Check out my other mods

- [AnimalFeedGuard](https://thunderstore.io/c/valheim/p/DocZee/AnimalFeedGuard/): leave suitable animal food where your tamed animals can eat it.
- [RanchingAddon](https://github.com/Michael-Ziluck/RanchingAddon): chick and Asksvin growth, plus growth and egg incubation information for Ranching.
- [HenEggPickup](https://thunderstore.io/c/valheim/p/DocZee/HenEggPickup/): automatically pick up eggs when enough adult hens are nearby.

If you find my mods useful, you can [buy me a coffee](https://ko-fi.com/doczee).
