# OdinLookedAway

Odin saw nothing. Your achievements still count.

Disables Valheim's cheat contamination and cheat-based achievement disqualification while keeping ordinary achievement objectives and difficulty requirements intact.

## Features

- Dev commands no longer mark the character or add to its cheat counter.
- Spawned, crafted, stacked, transferred, and dropped items stay free of cheat flags, including the damage-based marking path.
- Clears existing item flags when inventories/items load or pass through their normal boundaries.
- Cleans entity flags, cooking-slot flags, and production queues.
- Cleans serialized world records, including inventories and item stands outside loaded areas, before saving or sending them.
- Keeps future achievement-specific statistics eligible even with mods, dev commands, or cheated world modifiers.
- Avoids repeated `confirmcheats` prompts and removes the achievement disqualification message.

This does not unlock achievements automatically, reconstruct lost progress, reset historical cheat counts, alter item damage, change world modifiers, or bypass difficulty requirements. Ordinary command permissions and server administration rules still apply.

## Installation and multiplayer

Requires BepInExPack Valheim. Copy the included `BepInEx` folder into your game or mod-manager profile while the game is closed. Remove other mods that override the same cheat/achievement methods before testing.

For complete coverage, install on **every participating client and the host/dedicated server**. Each client controls its own achievement eligibility and character data; the server and owning clients control entity writes and world persistence. An unpatched participant can still create/send contaminated data. A patched receiver cleans the known data it receives, but cannot prevent writes or saves on an unpatched process.

No settings, server sync, Jotunn, or configuration manager are required. The behavior is enabled whenever this mod is loaded, including on dedicated servers.

## Backups and testing

**Back up your character and world before first use.** Cleared flags stay cleared when you save. Removing the DLL alone does not restore them; restoring the corresponding character/world backup does.

This is an **unpublished build**. Installed-assembly checks pass, but gameplay and actual Steam achievement progress/unlocks have not yet been verified. Test on a disposable character/world first. Unknown or malformed serialized item formats are preserved with an error in the log, rather than risking lost items.

The local source includes build, verification, and save-aware rollback scripts. A public source link will be added when publication is authorized.

## Check out my other mods

- [AnimalFeedGuard](https://thunderstore.io/c/valheim/p/DocZee/AnimalFeedGuard/): leave suitable animal food where your tamed animals can eat it.
- [RanchingChickAddon](https://thunderstore.io/c/valheim/p/DocZee/Ranching_Chick_Addon/): configurable chick growth and growth-progress tooltips for Ranching.
- [HenEggPickup](https://thunderstore.io/c/valheim/p/DocZee/HenEggPickup/): automatically pick up eggs when enough adult hens are nearby.

If you find my mods useful, you can [buy me a coffee](https://ko-fi.com/doczee).
