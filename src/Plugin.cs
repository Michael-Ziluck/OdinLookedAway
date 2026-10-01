using System;
using System.Collections.Generic;
using System.Linq;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;
using System.Collections.Concurrent;
using BepInEx;
using BepInEx.Logging;
using HarmonyLib;

namespace OdinLookedAway;

[BepInPlugin(Guid, "OdinLookedAway", "1.0.0")]
public sealed class Plugin : BaseUnityPlugin
{
    public const string Guid = "com.ziluck.valheim.odinlookedaway";
    internal static ManualLogSource Log = null!;
    [ThreadStatic] internal static int CommandDepth;
    private Harmony? harmony;
    private static readonly ConcurrentDictionary<int, byte> ReportedPayloadErrors = new ConcurrentDictionary<int, byte>();
    private void Awake()
    {
        Log = Logger;
        try
        {
            harmony = new Harmony(Guid);
            harmony.PatchAll(typeof(Plugin).Assembly);
            Logger.LogInfo("Odin looked away. Cheat contamination and achievement disqualification are disabled on this process. Original objectives and difficulty requirements remain in force.");
        }
        catch (Exception error)
        {
            harmony?.UnpatchSelf();
            Logger.LogError($"OdinLookedAway could not install every required patch; all its patches were removed: {error}");
            enabled = false;
        }
    }
    private void OnDestroy() => harmony?.UnpatchSelf();

    internal static void CleanInventory(Inventory inventory)
    {
        foreach (var item in inventory.GetAllItems()) item.m_cheated = false;
    }
    internal static byte[] CleanBytes(int hash, byte[] bytes)
    {
        if (bytes == null) return bytes!;
        try { return Contamination.CleanPayload(hash, bytes); }
        catch (Exception e) when (e is IOException || e is InvalidDataException || e is ArgumentException || e is OverflowException || e is FormatException)
        {
            if (ReportedPayloadErrors.TryAdd(hash, 0))
                Log.LogError($"Preserving an unrecognized item payload at ZDO key {hash}: {e.Message}. It has not been cleaned. Further payload errors for this key will be suppressed for this session.");
            return bytes;
        }
    }
    internal static bool IsMarker(ZDOID zid, int hash)
    {
        if (hash == Contamination.EntityKey || hash == Contamination.QueueKey) return true;
        int slot = unchecked(hash - Contamination.QueueKey);
        // Cooking slot markers are an arithmetic offset, not a string hash.
        // Match the actual slot record, so unrelated integer keys are untouched.
        return slot > 0 && ZDOExtraData.GetString(zid, Contamination.StableHash("slot" + slot), null) != null;
    }
    internal static string CleanString(int hash, string text)
    {
        if (hash != Contamination.InventoryKey || string.IsNullOrEmpty(text)) return text;
        try
        {
            byte[] data = Convert.FromBase64String(text);
            byte[] clean = CleanBytes(hash, data);
            return ReferenceEquals(data, clean) ? text : Convert.ToBase64String(clean);
        }
        catch (FormatException e)
        {
            if (ReportedPayloadErrors.TryAdd(hash, 0))
                Log.LogError($"Preserving an unrecognized legacy container payload: {e.Message}. Further payload errors for this key will be suppressed for this session.");
            return text;
        }
    }
    internal static void CleanRecord(ZDO zdo)
    {
        ZDOExtraData.GetData(zdo.m_uid, out _, out _, out _, out var ints, out _, out var strings, out var bytes, out _);
        foreach (var pair in ints.ToArray())
            if (IsMarker(zdo.m_uid, pair.Key)) ZDOExtraData.RemoveInt(zdo.m_uid, pair.Key);
        foreach (var pair in bytes.ToArray())
        {
            byte[] clean = CleanBytes(pair.Key, pair.Value);
            if (!ReferenceEquals(clean, pair.Value)) ZDOExtraData.Set(zdo.m_uid, pair.Key, clean);
        }
        foreach (var pair in strings.ToArray())
        {
            string clean = CleanString(pair.Key, pair.Value);
            if (clean != pair.Value) ZDOExtraData.Set(zdo.m_uid, pair.Key, clean);
        }
    }

    [HarmonyPatch(typeof(PlayerProfile), "get_s_bypassCheatChecks")]
    private static class BypassPatch
    {
        private static bool Prefix(ref bool __result) { __result = true; return false; }
    }
    [HarmonyPatch(typeof(Achievements), nameof(Achievements.CanGetAchievements))]
    private static class EligibilityPatch
    {
        private static bool Prefix(ref bool __result) { __result = true; return false; }
    }
    [HarmonyPatch(typeof(Achievements), nameof(Achievements.IsCheatedAtAll))]
    private static class CommandConfirmationPatch
    {
        // Preserve the ordinary, frame-cached check outside command execution.
        private static bool Prefix(ref bool __result)
        {
            if (CommandDepth == 0) return true;
            __result = true;
            return false;
        }
    }
    [HarmonyPatch(typeof(Terminal.ConsoleCommand), nameof(Terminal.ConsoleCommand.RunAction))]
    private static class CommandScopePatch
    {
        private static bool Prefix(Terminal.ConsoleCommand __instance, Terminal.ConsoleEventArgs args, out bool __state)
        {
            CommandDepth++;
            __state = true;
            if (!string.Equals(__instance.Command, "confirmcheats", StringComparison.OrdinalIgnoreCase)) return true;
            args.Context?.AddString("OdinLookedAway: cheat tracking is disabled; no confirmation is needed.");
            return false;
        }
        private static Exception? Finalizer(Exception? __exception, bool __state)
        {
            if (__state) CommandDepth--;
            return __exception;
        }
    }
    [HarmonyPatch(typeof(PlayerProfile), nameof(PlayerProfile.IncrementStat))]
    private static class CheatCounterPatch
    {
        private static bool Prefix(PlayerStatType stat) => stat != PlayerStatType.Cheats;
    }
    [HarmonyPatch]
    private static class ProfileBoundaryPatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => new[] {
            AccessTools.Method(typeof(PlayerProfile), "SavePlayerToDisk"),
            AccessTools.Method(typeof(PlayerProfile), "LoadPlayerFromDisk"),
            AccessTools.Method(typeof(PlayerProfile), "SavePlayerData"),
            AccessTools.Method(typeof(PlayerProfile), "LoadPlayerData")
        };
        private static void Prefix(PlayerProfile __instance) => __instance.m_usedCheats = false;
        private static void Postfix(PlayerProfile __instance) => __instance.m_usedCheats = false;
    }

    // These are every writer of the three contamination fields in the audited
    // game assembly. Each replacement changes only the stored boolean value.
    [HarmonyPatch]
    private static class FieldWritesPatch
    {
        internal static readonly Type[] WriterTypes = {
            typeof(Character), typeof(CharacterDrop), typeof(Terminal.ConsoleCommand),
            typeof(Inventory), typeof(ItemDrop), typeof(ItemDrop.ItemData),
            typeof(ZDOMan), typeof(PlayerProfile), typeof(Container), typeof(Piece)
        };
        internal static bool IsCheatField(object? operand) => operand is FieldInfo field && (
            (field.DeclaringType == typeof(ItemDrop.ItemData) && field.Name == "m_cheated") ||
            (field.DeclaringType == typeof(CharacterDrop) && field.Name == "m_cheated") ||
            (field.DeclaringType == typeof(PlayerProfile) && field.Name == "m_usedCheats"));
        private static IEnumerable<MethodBase> TargetMethods()
        {
            foreach (Type type in WriterTypes)
            foreach (MethodInfo method in AccessTools.GetDeclaredMethods(type))
                if (method.GetMethodBody() != null && PatchProcessor.GetOriginalInstructions(method).Any(i => i.opcode == OpCodes.Stfld && IsCheatField(i.operand)))
                    yield return method;
        }
        private static IEnumerable<CodeInstruction> Transpiler(IEnumerable<CodeInstruction> instructions)
        {
            foreach (var instruction in instructions)
            {
                if (instruction.opcode == OpCodes.Stfld && IsCheatField(instruction.operand))
                {
                    // Retain labels/exception boundaries at the start of the
                    // replacement so branches cannot skip popping the old value.
                    var pop = new CodeInstruction(OpCodes.Pop);
                    pop.labels.AddRange(instruction.labels); instruction.labels.Clear();
                    pop.blocks.AddRange(instruction.blocks); instruction.blocks.Clear();
                    yield return pop;
                    yield return new CodeInstruction(OpCodes.Ldc_I4_0);
                }
                yield return instruction;
            }
        }
    }

    [HarmonyPatch]
    private static class InventoryBoundaryPatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => AccessTools.GetDeclaredMethods(typeof(Inventory))
            .Where(m => new[] { "AddItem", "Load", "LoadOld", "Save", "OldSave", "MoveItemToThis", "MoveAll", "Changed", "GetAllItems", "CheatedDamagingItemEquipped", "AnyCheatedItem", "ItemCheated" }.Contains(m.Name));
        private static readonly FieldInfo Items = AccessTools.Field(typeof(Inventory), "m_inventory");
        private static void Prefix(Inventory __instance, object[] __args)
        {
            // Use the backing list: GetAllItems itself is one of the boundaries.
            foreach (var item in (List<ItemDrop.ItemData>)Items.GetValue(__instance)) item.m_cheated = false;
            foreach (object arg in __args)
                if (arg is ItemDrop.ItemData item) item.m_cheated = false;
        }
        private static void Postfix(Inventory __instance)
        {
            foreach (var item in (List<ItemDrop.ItemData>)Items.GetValue(__instance)) item.m_cheated = false;
        }
    }
    [HarmonyPatch]
    private static class ItemBoundaryPatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => AccessTools.GetDeclaredMethods(typeof(ItemDrop.ItemData))
            .Where(m => !m.IsStatic && new[] { "Save", "Clone", "GetTooltip" }.Contains(m.Name));
        private static void Prefix(ItemDrop.ItemData __instance) => __instance.m_cheated = false;
    }

    [HarmonyPatch]
    private static class IntegerWritePatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => new[] {
            AccessTools.Method(typeof(ZDOExtraData), "Add", new[] { typeof(ZDOID), typeof(int), typeof(int) }),
            AccessTools.Method(typeof(ZDOExtraData), "Set", new[] { typeof(ZDOID), typeof(int), typeof(int) })
        };
        private static void Prefix(ZDOID zid, int hash, ref int value)
        {
            if (IsMarker(zid, hash)) value = 0;
        }
    }
    [HarmonyPatch]
    private static class PayloadWritePatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => new[] {
            AccessTools.Method(typeof(ZDOExtraData), "Add", new[] { typeof(ZDOID), typeof(int), typeof(byte[]) }),
            AccessTools.Method(typeof(ZDOExtraData), "Set", new[] { typeof(ZDOID), typeof(int), typeof(byte[]) })
        };
        private static void Prefix(int hash, ref byte[] value) => value = CleanBytes(hash, value);
    }
    [HarmonyPatch]
    private static class LegacyPayloadWritePatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => new[] {
            AccessTools.Method(typeof(ZDOExtraData), "Add", new[] { typeof(ZDOID), typeof(int), typeof(string) }),
            AccessTools.Method(typeof(ZDOExtraData), "Set", new[] { typeof(ZDOID), typeof(int), typeof(string) })
        };
        private static void Prefix(int hash, ref string value) => value = CleanString(hash, value);
    }
    [HarmonyPatch]
    private static class RecordLoadPatch
    {
        private static IEnumerable<MethodBase> TargetMethods() => new[] {
            AccessTools.Method(typeof(ZDO), "Load"), AccessTools.Method(typeof(ZDO), "LoadOldFormat"),
            AccessTools.Method(typeof(ZDO), "Deserialize")
        };
        private static void Postfix(ZDO __instance) => CleanRecord(__instance);
    }
    [HarmonyPatch(typeof(ZDO), nameof(ZDO.Serialize))]
    private static class NetworkBoundaryPatch
    {
        private static void Prefix(ZDO __instance) => CleanRecord(__instance);
    }
    [HarmonyPatch(typeof(ZDOExtraData), nameof(ZDOExtraData.GetSaveData))]
    private static class PersistencePatch
    {
        // Operate on the save snapshot, including records with no spawned object.
        // Do not mutate the live dictionaries from the background save thread.
        private static void Postfix(ZDOID zid, ref List<KeyValuePair<int, int>> ints, ref List<KeyValuePair<int, byte[]>> byteArray,
            ref List<KeyValuePair<int, string>> strings)
        {
            var savedStrings = strings;
            bool Marker(KeyValuePair<int, int> p) => p.Key == Contamination.EntityKey || p.Key == Contamination.QueueKey ||
                (unchecked(p.Key - Contamination.QueueKey) > 0 && savedStrings.Any(s => s.Key == Contamination.StableHash("slot" + unchecked(p.Key - Contamination.QueueKey))));
            if (ints.Any(Marker)) ints = ints.Where(p => !Marker(p)).ToList();
            List<KeyValuePair<int, byte[]>>? cleanBytes = null;
            for (int i = 0; i < byteArray.Count; i++)
            {
                var pair = byteArray[i];
                byte[] clean = CleanBytes(pair.Key, pair.Value);
                if (ReferenceEquals(clean, pair.Value)) continue;
                cleanBytes ??= new List<KeyValuePair<int, byte[]>>(byteArray);
                cleanBytes[i] = new KeyValuePair<int, byte[]>(pair.Key, clean);
            }
            if (cleanBytes != null) byteArray = cleanBytes;
            List<KeyValuePair<int, string>>? cleanStrings = null;
            for (int i = 0; i < strings.Count; i++)
            {
                var pair = strings[i];
                string clean = CleanString(pair.Key, pair.Value);
                if (clean == pair.Value) continue;
                cleanStrings ??= new List<KeyValuePair<int, string>>(strings);
                cleanStrings[i] = new KeyValuePair<int, string>(pair.Key, clean);
            }
            if (cleanStrings != null) strings = cleanStrings;
        }
    }
    [HarmonyPatch(typeof(InventoryGui), "UpdateAchievementsList")]
    private static class AchievementWarningPatch
    {
        private static readonly FieldInfo Warning = AccessTools.Field(typeof(InventoryGui), "m_achievementsCheatedText");
        private static void Postfix(InventoryGui __instance)
        {
            object text = Warning.GetValue(__instance);
            if (text != null) AccessTools.Property(text.GetType(), "text").SetValue(text, string.Empty, null);
        }
    }
}
