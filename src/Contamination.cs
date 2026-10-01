using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace OdinLookedAway;

// Edit only the cheat bit, preserving prefab hashes, custom data, durability,
// unknown flag bits, and the original save format. Never instantiate prefabs
// to clean an unloaded inventory: that can lose items from unavailable mods.
internal static class Contamination
{
    internal static int StableHash(string text)
    {
        unchecked
        {
            int a = 5381, b = a;
            for (int i = 0; i < text.Length && text[i] != '\0'; i += 2)
            {
                a = ((a << 5) + a) ^ text[i];
                if (i == text.Length - 1 || text[i + 1] == '\0') break;
                b = ((b << 5) + b) ^ text[i + 1];
            }
            return a + b * 1566083941;
        }
    }

    internal static readonly int EntityKey = StableHash("cheated");
    internal static readonly int QueueKey = StableHash("cheatedQueued");
    internal static readonly int InventoryKey = StableHash("items");
    internal static readonly int ItemKey = StableHash("itemData");
    private static readonly HashSet<int> IndexedItemKeys = MakeIndexedItemKeys();
    private static HashSet<int> MakeIndexedItemKeys()
    {
        var result = new HashSet<int>();
        // Current item/inventory indices are represented by a ushort. Includes
        // every vanilla armor-stand slot and the old inventory migration slots.
        for (int i = 0; i <= ushort.MaxValue; i++) result.Add(StableHash(i + "_itemData"));
        return result;
    }
    internal static bool IsItemKey(int hash) => hash == ItemKey || IndexedItemKeys.Contains(hash);

    internal static byte[] CleanPayload(int hash, byte[] original)
    {
        if (original == null || (hash != InventoryKey && !IsItemKey(hash))) return original!;
        return CleanPayload(original, hash == InventoryKey);
    }

    internal static byte[] CleanPayload(byte[] original, bool inventory)
    {
        // Validate the complete payload before changing any byte. Unsupported
        // versions or malformed data are left intact and reported by the caller.
        using var stream = new MemoryStream(original, false);
        using var reader = new BinaryReader(stream, Encoding.UTF8, true);
        var flags = new List<int>();
        int version = inventory ? reader.ReadInt32() : reader.ReadByte();
        if (version < 101 || version > 109) throw new InvalidDataException($"Unsupported item version {version}.");
        int count = inventory ? (version >= 108 ? reader.ReadUInt16() : reader.ReadInt32()) : 1;
        if (count < 0 || count > ushort.MaxValue) throw new InvalidDataException("Invalid inventory size.");
        for (int i = 0; i < count; i++)
        {
            if (!inventory || version >= 108)
            {
                reader.ReadInt32(); // Durability * 100
                reader.ReadBytesExact(3); // Grid x/y and world level
                byte header = reader.ReadByte();
                if ((header & 4) != 0) reader.ReadUInt16();
                if ((header & 8) != 0) reader.ReadUInt16();
                if ((header & 16) != 0) reader.ReadInt32();
                if ((header & 32) != 0) { reader.ReadInt64(); reader.ReadString(); }
                if ((header & 64) != 0) reader.ReadInt32(); // Prefab hash
                int customCount = 0;
                if ((header & 128) != 0)
                {
                    customCount = reader.ReadByte();
                    if ((customCount & 128) != 0) customCount = ((customCount & 127) << 8) | reader.ReadByte();
                }
                ReadCustomData(reader, customCount);
                if (version == 107 || version >= 109) flags.Add(checked((int)stream.Position));
                if (version == 107 || version >= 109) reader.ReadByte();
            }
            else
            {
                reader.ReadString(); reader.ReadInt32(); reader.ReadSingle();
                reader.ReadInt32(); reader.ReadInt32(); reader.ReadBoolean();
                if (version >= 101) reader.ReadInt32();
                if (version >= 102) reader.ReadInt32();
                if (version >= 103) { reader.ReadInt64(); reader.ReadString(); }
                if (version >= 104) ReadCustomData(reader, reader.ReadInt32());
                if (version >= 105) reader.ReadInt32();
                if (version >= 106) reader.ReadBoolean();
                if (version == 107) { flags.Add(checked((int)stream.Position)); reader.ReadBoolean(); }
            }
        }
        if (stream.Position != stream.Length) throw new InvalidDataException("Unexpected trailing item data.");
        byte[]? cleaned = null;
        foreach (int offset in flags)
        {
            if ((original[offset] & 1) == 0) continue;
            cleaned ??= (byte[])original.Clone();
            cleaned[offset] &= 0xfe;
        }
        return cleaned ?? original;
    }

    private static void ReadCustomData(BinaryReader reader, int count)
    {
        if (count < 0 || count > 32767) throw new InvalidDataException("Invalid custom-data size.");
        for (int i = 0; i < count; i++) { reader.ReadString(); reader.ReadString(); }
    }
    private static void ReadBytesExact(this BinaryReader reader, int count)
    {
        if (reader.ReadBytes(count).Length != count) throw new EndOfStreamException();
    }
}
