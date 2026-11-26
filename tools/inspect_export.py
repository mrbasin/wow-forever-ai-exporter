"""One-shot QA/reference decoder. Not required to run the addon; no watcher or MCP."""
import argparse
import base64
import io
import json
from pathlib import Path
import re
import zlib

import cbor2

MAX_SIZE = 512 * 1024


def decode_export(raw):
    if len(raw) > MAX_SIZE or not raw.startswith(b'1|'):
        raise ValueError('Invalid cache envelope')
    packed = base64.b64decode(raw[2:].strip(), validate=True)
    decoded = None
    for window in (zlib.MAX_WBITS, -zlib.MAX_WBITS):
        try:
            inflater = zlib.decompressobj(window)
            candidate = inflater.decompress(packed, MAX_SIZE + 1)
            if len(candidate) > MAX_SIZE or not inflater.eof or inflater.unused_data:
                raise ValueError('Oversized, incomplete, or trailing layout data')
            decoded = candidate
            break
        except zlib.error:
            continue
    if decoded is None:
        raise ValueError('Invalid compressed layout')
    stream = io.BytesIO(decoded)
    root = cbor2.CBORDecoder(stream).decode()
    if stream.read(1) or not isinstance(root, (dict, list)):
        raise ValueError('Invalid layout root')
    # WoW serializes Lua strings as CBOR byte strings. A layout without a
    # sparse key can also serialize as an array (Lua indices start at one).
    marker = root.get(127) if isinstance(root, dict) else (root[126] if len(root) >= 127 else None)
    if isinstance(marker, bytes):
        if not marker.startswith(b'EXP1:'):
            return None
        marker = marker.decode('utf-8')
    if not isinstance(marker, str) or not marker.startswith('EXP1:'):
        return None
    _, expected, payload = marker.split(':', 2)
    if not re.fullmatch(r'[0-9A-F]{4}', expected):
        raise ValueError('Invalid checksum format')
    a = b = 0
    for value in payload.encode('utf-8'):
        a = (a + value) % 255
        b = (b + a) % 255
    if expected != f'{b * 256 + a:04X}':
        raise ValueError('Snapshot checksum mismatch')
    data = json.loads(payload)
    if (not isinstance(data, dict) or data.get('sourceAddon') != 'Exporter' or
            data.get('schemaVersion') not in (1, 2, 3, 4, 5) or not data.get('character', {}).get('guid')):
        raise ValueError('Not a supported Exporter snapshot')
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cache_file', type=Path)
    parser.add_argument('--output', type=Path, help='Optional decoded JSON output; original timestamps are preserved')
    parser.add_argument('--pretty', action='store_true', help='Indent JSON for human review; default output is compact for AI use')
    args = parser.parse_args()
    try:
        if args.cache_file.stat().st_size > MAX_SIZE:
            raise ValueError('Cache too large')
        data = decode_export(args.cache_file.read_bytes())
        if data is None:
            raise ValueError('No Exporter snapshot in this cache file')
        encoded = json.dumps(data, ensure_ascii=False, allow_nan=False,
                             indent=2 if args.pretty else None,
                             separators=None if args.pretty else (',', ':')) + '\n'
        if args.output:
            if args.output.resolve() == args.cache_file.resolve():
                raise ValueError('Output cannot overwrite the game cache')
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(encoded, encoding='utf-8')
            print(args.output.resolve())
        else:
            print(encoded, end='')
    except (ValueError, OSError) as exc:
        parser.exit(1, f'{exc}\n')


if __name__ == '__main__':
    main()
