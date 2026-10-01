using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.Serialization;
using System.Text;
using BepInEx.Logging;
using HarmonyLib;
using Mono.Cecil;
using OdinLookedAway;

internal static class Program
{
    private static int assertions;
    private static int Main(string[] args)
    {
        string game = args[0];
        AppDomain.CurrentDomain.AssemblyResolve += (_, e) => {
            string name = new AssemblyName(e.Name).Name + ".dll";
            foreach (string dir in new[] { "valheim_Data/Managed", "BepInEx/core" })
            {
                string path = Path.Combine(game, dir, name);
                if (File.Exists(path)) return Assembly.LoadFrom(path);
            }
            return null;
        };
        try { Run(game); return 0; }
        catch (Exception e) { System.Console.Error.WriteLine(e); return 1; }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void Run(string game)
    {
        Plugin.Log = new ManualLogSource("OdinLookedAway checks");
        PayloadChecks();
        AuditWriters(Path.Combine(game, "valheim_Data/Managed/assembly_valheim.dll"));
        PatchTargetChecks();
        ItemChecks();
        ZdoChecks();
        ProfileChecks();
        CommandChecks();
        System.Console.WriteLine($"PASS: {assertions} assertions using the installed game assembly. Coverage: patch targets and transpiler IL, isolated boundary hooks, serialized items and save snapshots. Unity/Mono patch installation and in-game/Steam achievement verification are NOT tested.");
    }

    private static void Assert([System.Diagnostics.CodeAnalysis.DoesNotReturnIf(false)] bool condition, string message)
    {
        assertions++;
        if (!condition) throw new InvalidOperationException(message);
    }
    private static void AuditWriters(string gameAssembly)
    {
        using var game = ModuleDefinition.ReadModule(gameAssembly);
        var patch = typeof(Plugin).GetNestedType("FieldWritesPatch", BindingFlags.NonPublic)!;
        var supported = ((Type[])patch.GetField("WriterTypes", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!)
            .Select(t => t.FullName!.Replace('+', '/')).ToHashSet();
        int writers = 0;
        foreach (var type in AllTypes(game.Types))
        foreach (var method in type.Methods.Where(m => m.HasBody))
        foreach (var instruction in method.Body.Instructions)
        {
            if (instruction.OpCode.Code != Mono.Cecil.Cil.Code.Stfld || !(instruction.Operand is FieldReference field)) continue;
            if (!((field.Name == "m_cheated" && (field.DeclaringType.FullName == "ItemDrop/ItemData" || field.DeclaringType.FullName == "CharacterDrop")) ||
                  (field.Name == "m_usedCheats" && field.DeclaringType.FullName == "PlayerProfile"))) continue;
            writers++;
            Assert(supported.Contains(type.FullName), "New uncovered contamination writer: " + method.FullName);
        }
        Assert(writers >= 13, "all expected cheat-field stores exist");
        System.Console.WriteLine($"Audited {writers} item, entity-drop, and character cheat-field stores; every writer type is covered.");
    }
    private static IEnumerable<TypeDefinition> AllTypes(IEnumerable<TypeDefinition> types)
    {
        foreach (var type in types)
        {
            yield return type;
            foreach (var nested in AllTypes(type.NestedTypes)) yield return nested;
        }
    }

    private static (byte[] bytes, List<int> flags) Fixture(bool inventory, int version, int count = 2)
    {
        using var stream = new MemoryStream();
        using var w = new BinaryWriter(stream, Encoding.UTF8, true);
        var offsets = new List<int>();
        if (inventory)
        {
            w.Write(version);
            if (version >= 108) w.Write((ushort)count); else w.Write(count);
        }
        else { w.Write((byte)version); count = 1; }
        for (int i = 0; i < count; i++)
        {
            if (!inventory || version >= 108)
            {
                w.Write(123456); w.Write((byte)3); w.Write((byte)4); w.Write((byte)2);
                w.Write((byte)255); w.Write((ushort)4); w.Write((ushort)17); w.Write(3);
                w.Write(987654321L); w.Write("Crafter Ω"); w.Write(0x12345678);
                w.Write((byte)130); w.Write((byte)0); // 512 custom entries, extended count
                for (int j = 0; j < 512; j++) { w.Write("key" + j); w.Write("value♡" + j); }
                if (version == 107 || version >= 109) { offsets.Add((int)stream.Position); w.Write((byte)0x81); }
            }
            else
            {
                w.Write("UnknownModdedPrefab"); w.Write(17); w.Write(15.125f);
                w.Write(3); w.Write(4); w.Write(true); w.Write(4);
                if (version >= 102) w.Write(3);
                if (version >= 103) { w.Write(987654321L); w.Write("Crafter Ω"); }
                if (version >= 104) { w.Write(1); w.Write("external-mod"); w.Write("preserved♡"); }
                if (version >= 105) w.Write(2);
                if (version >= 106) w.Write(true);
                if (version == 107) { offsets.Add((int)stream.Position); w.Write(true); }
            }
        }
        return (stream.ToArray(), offsets);
    }
    private static void PayloadChecks()
    {
        foreach (int version in Enumerable.Range(101, 9))
        foreach (bool inventory in new[] { false, true })
        {
            var fixture = Fixture(inventory, version);
            byte[] before = (byte[])fixture.bytes.Clone();
            byte[] cleaned = Contamination.CleanPayload(fixture.bytes, inventory);
            Assert(before.SequenceEqual(fixture.bytes), "cleanup never mutates the caller's byte array");
            Assert(cleaned.Length == before.Length, "payload length is preserved");
            for (int i = 0; i < before.Length; i++)
                Assert(cleaned[i] == (fixture.flags.Contains(i) ? (byte)(before[i] & 0xfe) : before[i]), "only cheat bits are changed");
            Assert(ReferenceEquals(cleaned, Contamination.CleanPayload(cleaned, inventory)), "cleaning is idempotent");
        }
        byte[] invalid = { 109, 0, 0, 0, 1, 0, 5 };
        Assert(ReferenceEquals(invalid, Plugin.CleanBytes(Contamination.InventoryKey, invalid)), "truncated data is preserved");
        byte[] future = { 110, 0, 0, 0, 0, 0 };
        Assert(ReferenceEquals(future, Plugin.CleanBytes(Contamination.InventoryKey, future)), "unknown future formats are preserved");
        Assert(ReferenceEquals(invalid, Plugin.CleanBytes(123, invalid)), "unrelated byte-array keys are untouched");
        var bytes = Fixture(true, 109).bytes;
        Assert(!Plugin.CleanBytes(Contamination.InventoryKey, bytes).SequenceEqual(bytes), "container bytes clean");
        Assert(!Plugin.CleanBytes(Contamination.StableHash("7_itemData"), Fixture(false, 109).bytes).SequenceEqual(Fixture(false, 109).bytes), "indexed item-stand bytes clean");
        string legacy = Convert.ToBase64String(Fixture(true, 107).bytes);
        Assert(Plugin.CleanString(Contamination.InventoryKey, legacy) != legacy, "legacy base64 containers clean");
    }

    private static void ItemChecks()
    {
        var item = new ItemDrop.ItemData { m_cheated = true };
        Hook("ItemBoundaryPatch", "Prefix").Invoke(null, new object[] { item });
        ItemDrop.ItemData copy = item.Clone();
        Assert(!item.m_cheated && !copy.m_cheated, "cloning clears pre-existing contamination");
        var inventory = new Inventory(false);
        inventory.GetAllItems().Add(new ItemDrop.ItemData { m_cheated = true });
        Hook("InventoryBoundaryPatch", "Prefix").Invoke(null, new object[] { inventory, new object[0] });
        Assert(!inventory.GetAllItems().Any(i => i.m_cheated), "inventory reads clear existing flags");
        inventory.GetAllItems().Add(new ItemDrop.ItemData { m_cheated = true });
        Hook("InventoryBoundaryPatch", "Postfix").Invoke(null, new object[] { inventory });
        Assert(inventory.GetAllItems().All(i => !i.m_cheated), "inventory boundaries clear transferred flags");
        // Compile the production field-store transpiler into a minimal writer.
        // Both true and false inputs must store false without invalidating IL.
        var field = typeof(ItemDrop.ItemData).GetField("m_cheated")!;
        var instructions = new[] { new CodeInstruction(System.Reflection.Emit.OpCodes.Ldarg_0),
            new CodeInstruction(System.Reflection.Emit.OpCodes.Ldarg_1),
            new CodeInstruction(System.Reflection.Emit.OpCodes.Stfld, field),
            new CodeInstruction(System.Reflection.Emit.OpCodes.Ret) };
        var modified = (IEnumerable<CodeInstruction>)Hook("FieldWritesPatch", "Transpiler").Invoke(null, new object[] { instructions })!;
        var writer = new System.Reflection.Emit.DynamicMethod("store", typeof(void), new[] { typeof(ItemDrop.ItemData), typeof(bool) });
        var il = writer.GetILGenerator();
        foreach (var instruction in modified)
        {
            if (instruction.operand is FieldInfo target) il.Emit(instruction.opcode, target);
            else il.Emit(instruction.opcode);
        }
        var action = (Action<ItemDrop.ItemData, bool>)writer.CreateDelegate(typeof(Action<ItemDrop.ItemData, bool>));
        item.m_cheated = true; action(item, true);
        Assert(!item.m_cheated, "compiled item-field transpiler suppresses true writes");
        item.m_cheated = true; action(item, false);
        Assert(!item.m_cheated, "compiled item-field transpiler preserves false writes");
    }

    private static void ZdoChecks()
    {
        ZDOExtraData.Reset();
        var id = new ZDOID(42L, 1);
        SetInt(id, Contamination.EntityKey, 1);
        SetInt(id, Contamination.QueueKey, 1);
        Assert(ZDOExtraData.GetInt(id, Contamination.EntityKey, -1) == 0, "entity marking suppressed");
        Assert(ZDOExtraData.GetInt(id, Contamination.QueueKey, -1) == 0, "production marking suppressed");
        ZDOExtraData.Set(id, Contamination.StableHash("slot3"), "RawMeat");
        SetInt(id, Contamination.QueueKey + 3, 1);
        Assert(ZDOExtraData.GetInt(id, Contamination.QueueKey + 3, -1) == 0, "cooking slot marking suppressed");
        ZDOExtraData.Set(id, 123, 7);
        Assert(ZDOExtraData.GetInt(id, 123, -1) == 7, "ordinary entity metadata preserved");
        var fixture = Fixture(true, 109).bytes;
        object[] payloadArgs = { Contamination.InventoryKey, fixture };
        Hook("PayloadWritePatch", "Prefix").Invoke(null, payloadArgs);
        ZDOExtraData.Set(id, Contamination.InventoryKey, (byte[])payloadArgs[1]);
        Assert(!fixture.SequenceEqual(ZDOExtraData.GetByteArray(id, Contamination.InventoryKey)), "container write normalizes serialized flags");
        // Seed existing contamination through unpatched storage to represent
        // an old world or data received from an unpatched peer.
        ZDOExtraData.Set(id, Contamination.EntityKey, 1);
        ZDOExtraData.Set(id, Contamination.QueueKey + 3, 1);
        ZDOExtraData.Set(id, Contamination.QueueKey + 4, 9); // Not a cooking slot
        ZDOExtraData.Set(id, Contamination.InventoryKey, fixture);
        ZDOExtraData.Set(id, Contamination.ItemKey, Fixture(false, 109).bytes);
        ZDOExtraData.Set(id, Contamination.StableHash("7_itemData"), Fixture(false, 109).bytes);
        ZDOExtraData.Set(id, Contamination.InventoryKey, Convert.ToBase64String(Fixture(true, 107).bytes));
        ZDOExtraData.PrepareSave();
        try
        {
            ZDOExtraData.GetSaveData(id, out _, out _, out _, out var ints, out _, out var strings, out var bytes, out _);
            object[] saveArgs = { id, ints, bytes, strings };
            Hook("PersistencePatch", "Postfix").Invoke(null, saveArgs);
            ints = (List<KeyValuePair<int, int>>)saveArgs[1];
            bytes = (List<KeyValuePair<int, byte[]>>)saveArgs[2];
            strings = (List<KeyValuePair<int, string>>)saveArgs[3];
            Assert(!ints.Any(p => p.Key == Contamination.EntityKey || p.Key == Contamination.QueueKey || p.Key == Contamination.QueueKey + 3), "save snapshot omits entity/queue flags");
            Assert(ints.Any(p => p.Key == 123 && p.Value == 7), "save snapshot preserves unrelated ints");
            Assert(ints.Any(p => p.Key == Contamination.QueueKey + 4 && p.Value == 9), "unrelated queue-offset integer preserved");
            Assert(bytes.All(p => ReferenceEquals(p.Value, Contamination.CleanPayload(p.Key, p.Value))), "all unloaded item/container save payloads are clean");
            Assert(strings.All(p => p.Value == Plugin.CleanString(p.Key, p.Value)), "legacy container save payloads are clean");
            Assert(ZDOExtraData.GetInt(id, Contamination.EntityKey) == 1, "background snapshot cleanup does not mutate live dictionaries");
        }
        finally { ZDOExtraData.ClearSave(); }
        // No Unity scene object is needed: emulate an unloaded world record.
        var zdo = (ZDO)RuntimeHelpers.GetUninitializedObject(typeof(ZDO));
        AccessTools.Field(typeof(ZDO), "m_uid").SetValue(zdo, id);
        Plugin.CleanRecord(zdo);
        Assert(ZDOExtraData.GetInt(id, Contamination.EntityKey, -1) == -1, "record cleanup removes the persisted marker");
        Assert(ZDOExtraData.GetInt(id, Contamination.QueueKey + 3, -1) == -1, "record cleanup removes cooking queue markers");
        Assert(ZDOExtraData.GetInt(id, Contamination.QueueKey + 4) == 9, "record cleanup preserves unrelated integers");
        foreach (int key in new[] { Contamination.InventoryKey, Contamination.ItemKey, Contamination.StableHash("7_itemData") })
        {
            byte[] stored = ZDOExtraData.GetByteArray(id, key);
            Assert(ReferenceEquals(stored, Contamination.CleanPayload(key, stored)), "existing unloaded item bytes are cleaned");
        }
        string saved = ZDOExtraData.GetString(id, Contamination.InventoryKey);
        Assert(saved == Plugin.CleanString(Contamination.InventoryKey, saved), "existing unloaded base64 inventory cleaned");
        foreach (string boundary in new[] { "RecordLoadPatch", "NetworkBoundaryPatch" })
        {
            ZDOExtraData.Set(id, Contamination.EntityKey, 1);
            ZDOExtraData.Set(id, Contamination.InventoryKey, fixture);
            Hook(boundary, boundary == "RecordLoadPatch" ? "Postfix" : "Prefix").Invoke(null, new object[] { zdo });
            Assert(ZDOExtraData.GetInt(id, Contamination.EntityKey, -1) == -1, boundary + " removes received/persisted markers");
            byte[] stored = ZDOExtraData.GetByteArray(id, Contamination.InventoryKey);
            Assert(ReferenceEquals(stored, Contamination.CleanPayload(stored, true)), boundary + " normalizes item bytes");
        }
    }
    private static void ProfileChecks()
    {
        var profile = (PlayerProfile)RuntimeHelpers.GetUninitializedObject(typeof(PlayerProfile));
        // A null stats array would throw if the counter patch allowed execution.
        Assert(!(bool)Hook("CheatCounterPatch", "Prefix").Invoke(null, new object[] { PlayerStatType.Cheats })!, "cheat counter increments are blocked");
        Assert((bool)Hook("CheatCounterPatch", "Prefix").Invoke(null, new object[] { PlayerStatType.MineHits })!, "ordinary objective increments are allowed");
        Assert(profile.m_usedCheats == false, "cheat counter is blocked before touching stats");
        var patch = typeof(Plugin).GetNestedType("ProfileBoundaryPatch", BindingFlags.NonPublic)!;
        var prefix = patch.GetMethod("Prefix", BindingFlags.Static | BindingFlags.NonPublic)!;
        profile.m_usedCheats = true;
        prefix.Invoke(null, new object[] { profile });
        Assert(!profile.m_usedCheats, "existing character cheat flag is cleared");
    }
    private static void CommandChecks()
    {
        // Exercise the production scope hooks, not Unity's native command body.
        var command = new Terminal.ConsoleCommand("odincheck", "", (Terminal.ConsoleEvent)(_ => { }), isCheat: true);
        var args = new Terminal.ConsoleEventArgs("odincheck", null, command);
        for (int i = 0; i < 2; i++)
        {
            object[] scope = { command, args, false };
            Assert((bool)Hook("CommandScopePatch", "Prefix").Invoke(null, scope)!, "cheat command action remains enabled");
            object[] check = { false };
            Assert(!(bool)Hook("CommandConfirmationPatch", "Prefix").Invoke(null, check)! && (bool)check[0], "command scope suppresses confirmation");
            var exception = new InvalidOperationException("expected");
            Assert(ReferenceEquals(exception, Hook("CommandScopePatch", "Finalizer").Invoke(null, new object[] { exception, scope[2] })), "command exceptions are preserved");
            Assert(Plugin.CommandDepth == 0, "command scope restores after exceptions");
        }
        object[] outside = { false };
        Assert((bool)Hook("CommandConfirmationPatch", "Prefix").Invoke(null, outside)!, "ordinary cheat check remains unchanged outside commands");
        var confirm = new Terminal.ConsoleCommand("confirmcheats", "", (Terminal.ConsoleEvent)(_ => { }), isCheat: true);
        object[] confirmScope = { confirm, new Terminal.ConsoleEventArgs("confirmcheats", null, confirm), false };
        Assert(!(bool)Hook("CommandScopePatch", "Prefix").Invoke(null, confirmScope)!, "confirmcheats action is replaced");
        Hook("CommandScopePatch", "Finalizer").Invoke(null, new object?[] { null, confirmScope[2] });
        Assert(Plugin.CommandDepth == 0, "confirmcheats scope restores");
    }
    private static MethodInfo Hook(string patch, string method) => typeof(Plugin).GetNestedType(patch, BindingFlags.NonPublic)!
        .GetMethod(method, BindingFlags.Static | BindingFlags.NonPublic)!;
    private static void SetInt(ZDOID id, int key, int value)
    {
        object[] args = { id, key, value };
        Hook("IntegerWritePatch", "Prefix").Invoke(null, args);
        ZDOExtraData.Set(id, key, (int)args[2]);
    }
    private static void PatchTargetChecks()
    {
        int methods = 0;
        var targets = new HashSet<MethodBase>();
        foreach (var patch in typeof(Plugin).GetNestedTypes(BindingFlags.NonPublic).Where(t => t.GetCustomAttributes(typeof(HarmonyPatch), false).Any()))
        {
            var finder = patch.GetMethod("TargetMethods", BindingFlags.Static | BindingFlags.NonPublic);
            IEnumerable<MethodBase> originals;
            if (finder != null) originals = (IEnumerable<MethodBase>)finder.Invoke(null, null)!;
            else
            {
                var attribute = (HarmonyPatch)patch.GetCustomAttributes(typeof(HarmonyPatch), false).Single();
                originals = new[] { AccessTools.Method(attribute.info.declaringType, attribute.info.methodName, attribute.info.argumentTypes) };
            }
            foreach (var original in originals)
            {
                Assert(original != null, "missing patch target: " + patch.Name);
                methods++;
                targets.Add(original);
                foreach (var hook in patch.GetMethods(BindingFlags.Static | BindingFlags.NonPublic).Where(m => m.Name == "Prefix" || m.Name == "Postfix" || m.Name == "Finalizer"))
                foreach (var parameter in hook.GetParameters().Where(p => !p.Name!.StartsWith("__")))
                {
                    var actual = original.GetParameters().SingleOrDefault(p => p.Name == parameter.Name);
                    Assert(actual != null, $"{patch.Name}.{hook.Name}: argument {parameter.Name} not present on {original}");
                    Type hookType = parameter.ParameterType.IsByRef ? parameter.ParameterType.GetElementType()! : parameter.ParameterType;
                    Type originalType = actual.ParameterType.IsByRef ? actual.ParameterType.GetElementType()! : actual.ParameterType;
                    Assert(hookType == originalType, "Harmony hook argument type mismatch");
                }
                if (patch.Name == "FieldWritesPatch")
                {
                    var originalIl = PatchProcessor.GetOriginalInstructions(original);
                    var replacement = ((IEnumerable<CodeInstruction>)Hook("FieldWritesPatch", "Transpiler").Invoke(null, new object[] { originalIl })!).ToList();
                    Assert(replacement.Count > originalIl.Count, "each audited field writer is transformed");
                }
            }
        }
        Assert(methods >= 40, "all expected patch boundaries exist");
        Assert(!targets.Contains(AccessTools.Method(typeof(Achievements), "GetCurrentAchievementDifficulty")), "difficulty selection remains intact");
        Assert(!targets.Any(m => m.DeclaringType == typeof(Achievements) && m.Name == "AchievementStatIncrementEvent"), "achievement objectives and events remain intact");
        System.Console.WriteLine($"Resolved {methods} Harmony patch targets and checked hook signatures against actual game metadata.");
    }
}
