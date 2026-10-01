# Verification

## Automated checks

Run `./ci/Build.ps1`. The harness reads the actual game assembly, resolves every Harmony target and named argument, audits contamination writers, transforms their IL, compiles a representative field-store replacement, and exercises the production boundary hooks in isolation.

Checks include current and legacy serialized inventory/item formats, unknown prefabs and custom data, preserved non-cheat bits, malformed/future-format rejection without partial changes, existing inventory flags, entity/queue writes, cooking-slot precision, item-stand data, legacy base64 containers, unloaded save snapshots, load/network hooks, command scope exception cleanup, and preservation of ordinary stat/difficulty methods.

These are **not** live Unity/Mono patch-installation, gameplay, multiplayer, or Steam achievement tests.

## In-game checklist — pending

Use a disposable local character/world first; back up before testing. Install on all participants for multiplayer tests. Keep an unmodified backup with tainted items/entities/queues for testing cleanup of existing flags. The user elected to perform live tests themselves; nothing has been installed or cleaned by this task.

1. Start with BepInEx logging visible. Confirm `Odin looked away` appears and no patch-installation/unknown-payload errors occur. Review the achievement screen: no cheat-disqualification warning.
2. Enable `devcommands`, run `god`, `ghost`, and repeated `spawn Wood 10` commands. Confirm no repeated confirmation prompts. Run `confirmcheats` and confirm the neutral mod message. Check that `m_usedCheats` is false and `PlayerStatType.Cheats` has not increased; an old historical count need not be zero.
3. Spawn, craft, build, dismantle, split, and merge items; transfer them between player inventory, a chest, and item/armor stands. Check the actual `m_cheated` fields, not only tooltip visibility. Test a weapon exceeding 10,000 damage loading into an inventory: damage should remain unchanged, while the cheat flag is false.
4. Mine a `MineRock5` vein, break a `TreeLog`, kill an enemy while using dev-command modes, and inspect all drops and entity records. Test old contaminated equipment as well as newly spawned equipment.
5. Load pre-existing contaminated character/container items and entity records. Check cooking slots, a fermenter mid-process, and a smelter queue; collect outputs and confirm clean flags. Include an empty cooking-slot record with a stale flag.
6. Place a contaminated chest/entity far outside the currently loaded area in the backup world. Load with this mod, save without visiting that area, quit, reload, and inspect the saved records: entity/queue markers must be absent and serialized item cheat bits must be zero. Confirm quantities, durability, quality, crafter information, custom data, and unrelated ZDO fields are unchanged.
7. Test host/client and dedicated-server ownership changes with all participants patched. Also test receipt of contaminated data from an unpatched client as a boundary test; that client's own progress and persistence cannot be controlled by this mod.
8. Choose an **ordinary, still-incomplete achievement objective** at the appropriate difficulty. Record its achievement-specific statistic, perform a qualifying action after using several dev commands, and confirm a real stat-progress event or legitimate unlock on Steam. Do not use a synthetic progress/unlock command as evidence. Repeat save/reload and confirm retained progress.
9. Remove the mod and restore the test character/world backup using `ci/Rollback.ps1 -RestoreSaves`. Confirm original tainted flags return and the mod DLL is removed/restored as appropriate.

Achievement support must remain labeled **unverified in-game** until step 8 succeeds. Keep the before/after statistic, relevant log lines, game version, difficulty, and any Steam confirmation as evidence. Past disqualified progress is not reconstructed.
