# OdinLookedAway

Odin saw nothing. Your achievements still count.

Local, unpublished Valheim 1.0 BepInEx/Harmony mod. See [the package README](README.thunderstore.md) for features and multiplayer requirements, and [the verification checklist](VERIFICATION.md) for the remaining live tests.

## Build

```powershell
./ci/Build.ps1
# Or supply another compatible Valheim installation:
./ci/Build.ps1 -GamePath 'E:/Games/SteamLibrary/steamapps/common/Valheim'
```

Requires the .NET SDK 8 or newer, Valheim 1.0, and BepInEx. The build compiles the production mod, runs serialized-data and patch-target checks, verifies assembly member references, and creates `artifacts/OdinLookedAway-1.0.0-Thunderstore.zip` using `README.thunderstore.md` as the packaged `README.md`. Game/framework DLLs and test dependencies are not packaged or committed.

The production DLL targets net48 for Unity/Mono. The test harness uses .NET 8 and test-only HarmonyX 2.16.1 because the installed game's default interface methods cannot be loaded by the Windows .NET Framework CLR, and its HarmonyX 2.9 cannot initialize on .NET 8. Tests inspect actual game metadata and exercise isolated hooks/transpiler IL; they do not install all detours into Unity or test Steam achievements.

## Deployment and rollback

Do not deploy into a running game. Use a disposable character/world for the first live tests. Save cleanup is permanent on the next save unless you restore backups.

```powershell
# Preview; specify all relevant local or Steam save folders.
./ci/Deploy.ps1 -ProfilePath "$env:APPDATA/r2modmanPlus-local/Valheim/profiles/UpdatedDefault" -SavePaths "$env:USERPROFILE/AppData/LocalLow/IronGate/Valheim" -WhatIf
# Install after closing the game. This first hash-verifies a save/plugin backup.
./ci/Deploy.ps1 -ProfilePath '<existing profile>' -SavePaths '<save root>', '<additional Steam save root>'
# Restore the previous DLL (or remove this mod if it was not previously installed):
./ci/Rollback.ps1 -BackupDirectory '<directory printed by Deploy.ps1>'
# Also restore the backed-up save files, with the game closed:
./ci/Rollback.ps1 -BackupDirectory '<directory printed by Deploy.ps1>' -RestoreSaves
```

The backup manifest is local and ignored by Git. Restore character and world backups together when reversing a cleanup. The scripts never edit the original game DLL.

## Implementation

The audited installed assembly is Valheim `1.0.16`, SHA-256 `96CFC004F7F4A6F30D070BEF39EAFD79C466A137121C4665A2F19FB9C15C6127`.

- Prefix the read-only `PlayerProfile.s_bypassCheatChecks` getter and `Achievements.CanGetAchievements(bool)` independently.
- Replace values at all 13 audited stores to item/drop/profile contamination fields, preserving the rest of each method. This includes the private inventory-loading damage threshold.
- Clear inventories and item objects at load/add/transfer/read/clone/save/tooltip boundaries.
- Normalize integer and serialized-item writes in `ZDOExtraData`; clean complete ZDO records after old/current world loads and network deserialization and before network serialization.
- Filter save snapshots, covering unloaded records without changing live dictionaries on the background save thread.
- Change only the cheat bit in recognized inventory/item payload formats, preserving unknown prefabs, custom data, future flag bits, and byte layout. Supports current and legacy inventory formats 101–109; indexed item data covers the ushort index range used by current inventory/stand formats. Unsupported formats are preserved and reported.
- Recognize arithmetic cooking-slot markers using the matching slot string record, avoiding blanket filtering of nearby integer hashes.
- Scope the confirmation bypass to `ConsoleCommand.RunAction`, restore it with an exception finalizer, and block only `PlayerStatType.Cheats` increments. Existing historical counts are left intact.
- Do not globally falsify `IsCheatedAtAll()`, clear `Game.isModded`, change world modifiers, or patch objective/difficulty evaluation.

All clients and the host/server need the mod for complete session-wide coverage. There is no server-synced configuration.

## Publication

**Do not publish this build yet.** No remote repository or listing has been created. The established GitHub Actions build/CodeQL/Dependabot scaffolding is included locally; publication jobs require explicit repository variables and the publication scripts also contain hard guards. A later authorized release must add the source URL and explicitly remove those guards. Do not add service tokens to this repository.

MIT licensed. [Reference and artwork attribution](ATTRIBUTION.md).

## Check out my other mods

- [AnimalFeedGuard](https://thunderstore.io/c/valheim/p/DocZee/AnimalFeedGuard/)
- [RanchingChickAddon](https://thunderstore.io/c/valheim/p/DocZee/Ranching_Chick_Addon/)
- [HenEggPickup](https://thunderstore.io/c/valheim/p/DocZee/HenEggPickup/)

Optional support: [Ko-fi](https://ko-fi.com/doczee).
