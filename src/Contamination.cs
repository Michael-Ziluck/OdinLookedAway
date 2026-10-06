using System.Collections.Generic;
using System.IO;
using System.Text;

namespace OdinLookedAway;

// Edit only the cheat bit, preserving prefab hashes, custom data, durability,
// unknown flag bits, and the original save format. Never instantiate prefabs
// to clean an unloaded inventory: that can lose items from unavailable mods.
internal static class Contamination
{
    internal static readonly int EntityKey = "cheated".GetStableHashCode();
    internal static readonly int QueueKey = "cheatedQueued".GetStableHashCode();
    internal static readonly int InventoryKey = "items".GetStableHashCode();
    internal static readonly int ItemKey = "itemData".GetStableHashCode();
    private static readonly HashSet<int> IndexedItemKeys = MakeIndexedItemKeys();
    private static HashSet<int> MakeIndexedItemKeys()
    {
        var keys = new HashSet<int>();
        // Current item/inventory indices are represented by a ushort. Includes
        // every vanilla armor-stand slot and the old inventory migration slots.
        for (int i = 0; i <= ushort.MaxValue; i++) keys.Add((i + "_itemData").GetStableHashCode());
        return keys;
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
        var cheatOffsets = new List<int>();
        int version = inventory ? reader.ReadInt32() : reader.ReadByte();
        if (version < 101 || version > 109) throw new InvalidDataException($"Unsupported item version {version}.");
        int count = inventory ? (version >= 108 ? reader.ReadUInt16() : reader.ReadInt32()) : 1;
        if (count < 0 || count > ushort.MaxValue) throw new InvalidDataException("Invalid inventory size.");
        for (int i = 0; i < count; i++)
        {
            if (!inventory || version >= 108)
                ReadPackedItem(reader, version, cheatOffsets);
            else
                ReadLegacyItem(reader, version, cheatOffsets);
        }
        if (stream.Position != stream.Length) throw new InvalidDataException("Unexpected trailing item data.");
        byte[]? cleaned = null;
        foreach (int offset in cheatOffsets)
        {
            if ((original[offset] & 1) == 0) continue;
            cleaned ??= (byte[])original.Clone();
            cleaned[offset] &= 0xfe;
        }
        return cleaned ?? original;
    }

    private static void ReadPackedItem(BinaryReader reader, int version, List<int> cheatOffsets)
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
        if (version == 107 || version >= 109)
        {
            cheatOffsets.Add(checked((int)reader.BaseStream.Position));
            reader.ReadByte();
        }
    }

    private static void ReadLegacyItem(BinaryReader reader, int version, List<int> cheatOffsets)
    {
        reader.ReadString();
        reader.ReadInt32();
        reader.ReadSingle();
        reader.ReadInt32();
        reader.ReadInt32();
        reader.ReadBoolean();
        reader.ReadInt32();
        if (version >= 102) reader.ReadInt32();
        if (version >= 103) { reader.ReadInt64(); reader.ReadString(); }
        if (version >= 104) ReadCustomData(reader, reader.ReadInt32());
        if (version >= 105) reader.ReadInt32();
        if (version >= 106) reader.ReadBoolean();
        if (version == 107)
        {
            cheatOffsets.Add(checked((int)reader.BaseStream.Position));
            reader.ReadBoolean();
        }
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
