// Loaded by Decode-Export.ps1 using the C# compiler included with Windows PowerShell.
using System;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace WowForeverAIExporter
{
    public static class ExportWire
    {
        private const int LayoutLimit = 512 * 1024;
        private const int PayloadLimit = 450000;
        private static readonly UTF8Encoding Utf8 = new UTF8Encoding(false, true);

        public static string Read(string path)
        {
            byte[] envelope;
            using (var file = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
            using (var reader = new BinaryReader(file))
            {
                if (file.Length > LayoutLimit) throw new InvalidDataException("Cache exceeds 512 KiB.");
                envelope = reader.ReadBytes(LayoutLimit + 1);
            }
            if (envelope.Length < 3 || envelope.Length > LayoutLimit || envelope[0] != '1' || envelope[1] != '|')
                throw new InvalidDataException("Invalid cache envelope.");
            string base64 = Encoding.ASCII.GetString(envelope, 2, envelope.Length - 2).Trim();
            if (base64.IndexOfAny(new[] { ' ', '\t', '\r', '\n' }) >= 0)
                throw new InvalidDataException("Invalid Base64 in cache.");

            var layout = new LayoutReader(Decompress(Convert.FromBase64String(base64)));
            byte[] marker = layout.ReadMarker();
            if (marker == null || marker.Length < 5 || Encoding.ASCII.GetString(marker, 0, 5) != "EXP1:")
                throw new InvalidDataException("No Exporter snapshot in this cache file.");
            const int payloadStart = 10; // EXP1:HHHH:
            if (marker.Length < payloadStart || marker[9] != ':' || marker.Length - payloadStart > PayloadLimit)
                throw new InvalidDataException("Invalid snapshot marker or payload size.");
            int a = 0, b = 0;
            for (int i = payloadStart; i < marker.Length; i++)
            {
                a = (a + marker[i]) % 255;
                b = (b + a) % 255;
            }
            if ((b * 256 + a).ToString("X4") != Encoding.ASCII.GetString(marker, 5, 4))
                throw new InvalidDataException("Snapshot checksum mismatch.");
            return Utf8.GetString(marker, payloadStart, marker.Length - payloadStart);
        }

        private static byte[] Decompress(byte[] packed)
        {
            // RFC 1950 header: Deflate, supported window, no preset dictionary, valid FCHECK.
            if (packed.Length >= 6 && (packed[0] & 15) == 8 && (packed[0] >> 4) <= 7 &&
                (packed[1] & 32) == 0 && ((packed[0] << 8) + packed[1]) % 31 == 0)
            {
                try
                {
                    int trailer = packed.Length - 4;
                    byte[] bytes = Inflate(packed, 2, trailer - 2);
                    uint a = 1, b = 0;
                    foreach (byte value in bytes)
                    {
                        a = (a + value) % 65521;
                        b = (b + a) % 65521;
                    }
                    uint expected = ((uint)packed[trailer] << 24) | ((uint)packed[trailer + 1] << 16) |
                                    ((uint)packed[trailer + 2] << 8) | packed[trailer + 3];
                    if (((b << 16) | a) == expected) return bytes;
                }
                catch (InvalidDataException) { } // A valid raw stream can also start with these two bytes.
            }
            return Inflate(packed, 0, packed.Length);
        }

        private static byte[] Inflate(byte[] packed, int start, int count)
        {
            using (var source = new DeflateInput(packed, start, count))
            using (var inflater = new DeflateStream(source, CompressionMode.Decompress))
            using (var result = new MemoryStream())
            {
                byte[] buffer = new byte[8192];
                int read;
                while ((read = inflater.Read(buffer, 0, buffer.Length)) != 0)
                {
                    if (result.Length + read > LayoutLimit) throw new InvalidDataException("Layout exceeds 512 KiB.");
                    result.Write(buffer, 0, read);
                }
                if (source.Position != source.Length) throw new InvalidDataException("Trailing compressed data.");
                return result.ToArray();
            }
        }

        // DeflateStream buffers input and treats an underlying EOF as a successful end.
        // Reserve the last byte for a separate read to expose read-ahead past the end
        // marker. A request beyond that byte means the stream never reached its end marker.
        private sealed class DeflateInput : MemoryStream
        {
            public DeflateInput(byte[] bytes, int start, int count) : base(bytes, start, count, false) { }

            public override int Read(byte[] buffer, int offset, int count)
            {
                int remaining = (int)(Length - Position);
                if (remaining == 0) throw new InvalidDataException("Incomplete compressed data.");
                return base.Read(buffer, offset, Math.Min(count, remaining == 1 ? 1 : remaining - 1));
            }
        }

        // Walk one layout, skipping unrelated values structurally. Only retain the
        // string in Lua slot 127 (integer map key or one-based array position).
        private sealed class LayoutReader
        {
            private readonly byte[] bytes;
            private int offset;
            private byte[] marker;

            public LayoutReader(byte[] bytes) { this.bytes = bytes; }

            public byte[] ReadMarker()
            {
                int root = Peek() >> 5;
                if (root != 4 && root != 5) throw new InvalidDataException("Invalid CBOR layout root.");
                ReadItem(0, false);
                if (offset != bytes.Length) throw new InvalidDataException("Trailing CBOR data.");
                return marker;
            }

            private int Peek()
            {
                if (offset >= bytes.Length) throw new InvalidDataException("Incomplete CBOR layout.");
                return bytes[offset];
            }

            private ulong Argument(int info)
            {
                if (info < 24) return (ulong)info;
                if (info > 27) throw new InvalidDataException("Invalid CBOR argument.");
                int count = 1 << (info - 24);
                if (count > bytes.Length - offset) throw new InvalidDataException("Incomplete CBOR argument.");
                ulong value = 0;
                for (int i = 0; i < count; i++) value = (value << 8) | bytes[offset++];
                return value;
            }

            private void ReadItem(int depth, bool selected)
            {
                if (depth > 128) throw new InvalidDataException("CBOR layout nested too deeply.");
                int initial = Peek();
                offset++;
                int type = initial >> 5, info = initial & 31;
                bool indefinite = info == 31;
                if (indefinite && (type < 2 || type > 5)) throw new InvalidDataException("Invalid CBOR item.");
                ulong count = indefinite ? 0 : Argument(info);
                switch (type)
                {
                    case 2: // byte string
                    case 3: // text string
                        ReadString(type, count, indefinite, selected);
                        break;
                    case 4: // array
                    case 5: // map
                        for (ulong index = 0; indefinite ? Peek() != 255 : index < count; index++)
                        {
                            bool slot;
                            if (type == 5 && depth == 0 && (Peek() >> 5) == 0)
                                slot = Argument(bytes[offset++] & 31) == 127;
                            else
                            {
                                if (type == 5) ReadItem(depth + 1, false); // Skip the map key.
                                slot = type == 4 && depth == 0 && index == 126;
                            }
                            if (slot) marker = null;
                            ReadItem(depth + 1, slot);
                        }
                        if (indefinite) offset++; // break
                        break;
                    case 6: // semantic tag around an unrelated value
                        ReadItem(depth + 1, false);
                        break;
                    // Integers, simple values and floats have no bytes after their argument.
                }
            }

            private void ReadString(int type, ulong size, bool indefinite, bool selected)
            {
                using (var value = selected ? new MemoryStream() : null)
                {
                    while (!indefinite || Peek() != 255)
                    {
                        if (indefinite)
                        {
                            int chunk = bytes[offset++];
                            if ((chunk >> 5) != type) throw new InvalidDataException("Invalid CBOR string chunk.");
                            size = Argument(chunk & 31);
                        }
                        if (size > (ulong)(bytes.Length - offset)) throw new InvalidDataException("Incomplete CBOR string.");
                        if (type == 3) Utf8.GetCharCount(bytes, offset, (int)size);
                        if (value != null) value.Write(bytes, offset, (int)size);
                        offset += (int)size;
                        if (!indefinite) break;
                    }
                    if (indefinite) offset++; // break
                    if (value != null) marker = value.ToArray();
                }
            }
        }

        // The native JSON parser validates the payload before formatting. Change
        // whitespace only, preserving numbers, string escapes, order and timestamps.
        public static string FormatJson(string json, bool pretty)
        {
            var result = new StringBuilder(json.Length);
            bool quoted = false;
            char previous = '\0';
            int depth = 0;
            for (int i = 0; i < json.Length; i++)
            {
                char c = json[i];
                if (quoted)
                {
                    result.Append(c);
                    if (c == '\\') result.Append(json[++i]);
                    else if (c == '"') quoted = false;
                    continue;
                }
                if (Char.IsWhiteSpace(c)) continue;
                bool closing = c == '}' || c == ']';
                if (closing) depth--;
                bool afterOpen = previous == '{' || previous == '[';
                if (pretty && (closing ? !afterOpen : afterOpen || previous == ','))
                    result.Append('\n').Append(' ', depth * 2);
                result.Append(c);
                if (pretty && c == ':') result.Append(' ');
                if (c == '[' || c == '{') depth++;
                quoted = c == '"';
                previous = c;
            }
            return result.ToString();
        }

        public static void WriteOutput(string cache, string output, string json)
        {
            string directory = Path.GetDirectoryName(output);
            Directory.CreateDirectory(directory);
            string temporary = Path.Combine(directory, Path.GetRandomFileName());
            var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
            try
            {
                using (file)
                using (var writer = new StreamWriter(file, Utf8))
                {
                    writer.Write(json);
                    writer.Write('\n');
                }
                // Move covers a new destination. Replace publishes a complete revision
                // to an existing one, including if another process created it meanwhile.
                try { File.Move(temporary, output); }
                catch (IOException)
                {
                    if (!File.Exists(output)) throw;
                    // Deny deletion of the input name during Replace, including
                    // paths through a junction. A separate hard link can be replaced
                    // independently. In either case WoW can still read and write.
                    using (File.Open(cache, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
                        File.Replace(temporary, output, null);
                }
            }
            finally { File.Delete(temporary); }
        }
    }
}
