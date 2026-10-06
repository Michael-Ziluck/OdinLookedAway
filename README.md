# OdinLookedAway

Odin saw nothing. Your achievements still count.

OdinLookedAway is a BepInEx/Harmony mod for Valheim 1.0. It prevents cheat flags, cleans existing flags as character and world data pass through the patched methods, and keeps achievements eligible while preserving their objectives and difficulty requirements.

See [the mod-page README](README.thunderstore.md) for installation, multiplayer requirements, limitations, and troubleshooting. The maintainer has verified gameplay and achievement behavior. [The verification checklist](VERIFICATION.md) separates automated coverage from live regression tests.

Local builds produce a Thunderstore ZIP. The GitHub Actions build workflow also saves the ZIP as a `package` artifact. Approved releases can be published to Thunderstore and Hexium using the scripts in `ci`.

## Build

```powershell
./ci/Build.ps1
# Or supply another compatible Valheim installation:
./ci/Build.ps1 -GamePath 'E:/Games/SteamLibrary/steamapps/common/Valheim'
```

Run from the repository root on Windows using PowerShell 7 (`pwsh`), with the .NET 8 SDK and runtime installed. `GamePath` must point to a Valheim installation containing `valheim_Data/Managed` and `BepInEx/core`; the declared package dependency is BepInExPack Valheim 5.4.2350. The default path is `E:/Games/SteamLibrary/steamapps/common/Valheim`. Compatibility checks target Valheim 1.0.16; other game versions need fresh checks.

The build compiles the mod, runs serialized-data and patch-target checks, verifies assembly member references, and tests backup/deployment/rollback scripts against disposable fixtures. It writes `bin/Release/net48/OdinLookedAway.dll` and `artifacts/OdinLookedAway-1.0.0-Thunderstore.zip`. Packaging uses `README.thunderstore.md` as the ZIP's `README.md`; game/framework DLLs and test dependencies are excluded.

The production DLL targets net48 for Unity/Mono. The test harness uses .NET 8 and test-only HarmonyX 2.16.1 because the installed game's default interface methods cannot be loaded by the Windows .NET Framework CLR, and its HarmonyX 2.9 cannot initialize on .NET 8. Tests inspect actual game metadata and exercise isolated hooks/transpiler IL; they do not install all detours into Unity or test Steam achievements.

## Deployment and rollback

Do not deploy into a running game. Use a disposable character/world for the first live tests. Save cleanup is permanent on the next save unless you restore backups.

```powershell
# Preview; use your Gale profile folder and all relevant local or Steam save folders.
./ci/Deploy.ps1 -ProfilePath '<Gale profile folder>' -SavePaths "$env:USERPROFILE/AppData/LocalLow/IronGate/Valheim" -WhatIf
# Install after closing the game. This first hash-verifies a save/plugin backup.
./ci/Deploy.ps1 -ProfilePath '<existing profile>' -SavePaths '<save root>', '<additional Steam save root>'
# Restore the previous DLL (or remove this mod if it was not previously installed):
./ci/Rollback.ps1 -BackupDirectory '<directory printed by Deploy.ps1>'
# Also restore the backed-up save files, with the game closed:
./ci/Rollback.ps1 -BackupDirectory '<directory printed by Deploy.ps1>' -RestoreSaves
```

The backup manifest is local and ignored by Git. Save backups include hidden files and reject junctions, symbolic links, and other reparse points in source or destination paths before creating the backup. Supply ordinary folders with no linked ancestors. Restore character and world backups together when reversing a cleanup. The scripts never edit the original game DLL.

`Deploy.ps1` uses the existing DLL location, or creates `BepInEx/plugins/OdinLookedAway/OdinLookedAway.dll` for a new install. It refuses multiple installed copies. Pass `-Build` to build first, and `-GamePath` if that build needs a different installation. Rollbacks are stored under `.local/rollback`; keep that directory if you need to undo the deployment.

`-SavePaths` must include every local or Steam Cloud cache folder you want backed up. The script copies files from disk; it does not fetch remote Steam Cloud saves. `-RestoreSaves` overwrites backed-up files at their original paths and does not delete files created after the backup. A rollback without that switch changes only the mod DLL.

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

## Publication

GitHub Actions builds and verifies pushes to `main`, pull requests targeting `main`, and manual runs. Thunderstore and Hexium uploads and GitHub releases run when their publication variables are enabled. When enabled, each registry skips versions it already has. See [CI documentation](ci/README.md) for release settings and local commands.

MIT licensed. [Reference and artwork attribution](ATTRIBUTION.md).

## Check out my other mods

- [AnimalFeedGuard](https://thunderstore.io/c/valheim/p/DocZee/AnimalFeedGuard/)
- [RanchingAddon](https://github.com/Michael-Ziluck/RanchingAddon)
- [HenEggPickup](https://thunderstore.io/c/valheim/p/DocZee/HenEggPickup/)

Optional support: [Ko-fi](https://ko-fi.com/doczee).
