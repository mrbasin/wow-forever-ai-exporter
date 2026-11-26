import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zlib

import cbor2

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('inspect_export', ROOT / 'tools/inspect_export.py')
decoder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(decoder)


def envelope(layout, raw=False):
    encoder = zlib.compressobj(wbits=-15 if raw else 15)
    return b'1|' + base64.b64encode(encoder.compress(layout) + encoder.flush())


def wrap(payload, prefix='EXP1', raw=False, byte_string=False, array=False):
    a = b = 0
    for value in payload.encode('utf-8'):
        a = (a + value) % 255
        b = (b + a) % 255
    marker = f'{prefix}:{b * 256 + a:04X}:{payload}'
    if byte_string:
        marker = marker.encode('utf-8')
    if array:
        layout = [5] + [None] * 125 + [marker]
    else:
        layout = {1: 5, 2: {'unrelated': 123}, 127: marker}
    return envelope(cbor2.dumps(layout), raw)


class WireTests(unittest.TestCase):
    def fixture(self):
        return {'schemaVersion': 1, 'sourceAddon': 'Exporter', 'capturedAt': 1000,
                'character': {'guid': 'Player-fictional', 'name': 'Héro "test"'},
                'activeQuests': [], 'talents': {'capturedAt': 900, 'pendingChanges': True}}

    def test_roundtrip_unicode_and_original_timestamps(self):
        obj = self.fixture()
        for raw in (False, True):
            for byte_string in (False, True):
                self.assertEqual(decoder.decode_export(wrap(json.dumps(obj, ensure_ascii=False), raw=raw, byte_string=byte_string)), obj)

    def compact_fixture(self):
        return {'schemaVersion': 3, 'sourceAddon': 'Exporter', 'addonVersion': '1.0.0',
                'capturedAt': 1000, 'captureSequence': 2, 'character': {'guid': 'Player-fictional'},
                'basic': {'name': 'Héro "test"', 'className': 'Priest'},
                'equipment': {'slots': [{'slotID': 16, 'empty': False, 'itemID': 100, 'stats': {}}]},
                'talents': {'capturedAt': 900, 'pendingChanges': True, 'selectedTalents': []},
                'spellbook': {'scanComplete': False, 'entries': [
                    {'spellID': 100, 'baseCooldownMs': 0, 'isPassive': False, 'powerCosts': [],
                     'tooltipLines': [{'left': 'Readable effect'}], 'incompleteFields': ['tooltipLines']}]},
                'items': {'scanComplete': True, 'totalsComplete': True, 'itemCount': 0,
                          'entries': [{'bagID': 0, 'slotID': 1, 'empty': True}]}}

    def test_compact_schema_preserves_missing_and_known_values(self):
        obj = self.compact_fixture()
        for raw in (False, True):
            decoded = decoder.decode_export(wrap(json.dumps(obj, ensure_ascii=False), raw=raw, byte_string=True))
            self.assertEqual(decoded, obj)
            self.assertNotIn('level', decoded['basic'])
            self.assertNotIn('questLog', decoded)
            self.assertNotIn('capturedAt', decoded['basic'])
            self.assertEqual(decoded['talents']['capturedAt'], 900)
            self.assertEqual(decoded['spellbook']['entries'][0]['baseCooldownMs'], 0)
            self.assertIs(decoded['spellbook']['entries'][0]['isPassive'], False)
            self.assertEqual(decoded['spellbook']['entries'][0]['powerCosts'], [])
            self.assertEqual(decoded['equipment']['slots'][0]['stats'], {})

    def test_schema_four_effective_stats_and_legacy_three(self):
        obj = self.compact_fixture()
        obj['characterStats'] = {'capturedAt': 950,
                                 'general': {'health': {'maximum': 500}},
                                 'primaryAttributes': {'strength': {'current': 10, 'effective': 12}}}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj.update(schemaVersion=4, addonVersion='1.0.0')
        obj['characterStats'] = {
            'capturedAt': 950, 'maxHealth': 500, 'maxMana': 0,
            'movementSpeedYardsPerSecond': {'current': 0, 'run': 7},
            'attributes': {'strength': 12, 'intellect': 80},
            'weapons': {'mainHand': {'minimumDamage': 10.25, 'maximumDamage': 20.5,
                                     'speedSeconds': 2.5, 'estimatedDps': 6.15},
                        'attackPower': {'melee': 25}},
            'critPercent': {'melee': 3.5, 'spell': {'holy': 4.25}},
            'hastePercent': {'spell': -1.25},
            'spellDamageBonus': {'holy': 0.004}, 'spellHealingBonus': 0,
            'defense': {'armor': 100, 'skill': 80, 'dodgePercent': 2.75},
            'resistances': {'fire': 0, 'shadow': 5}}
        for raw in (False, True):
            decoded = decoder.decode_export(wrap(json.dumps(obj), raw=raw, byte_string=True))
            self.assertEqual(decoded, obj)
            stats = decoded['characterStats']
            self.assertEqual(stats['capturedAt'], 950)
            self.assertEqual(stats['maxMana'], 0)
            self.assertEqual(stats['hastePercent']['spell'], -1.25)
            self.assertEqual(stats['spellDamageBonus']['holy'], 0.004)
            self.assertNotIn('agility', stats['attributes'])
            self.assertNotIn('ranged', stats['weapons'])
            self.assertIs(decoded['spellbook']['scanComplete'], False)

    def test_schema_five_equipment_and_legacy_four(self):
        obj = self.compact_fixture()
        obj.update(schemaVersion=4, addonVersion='1.0.0')
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj.update(schemaVersion=5, addonVersion='1.0.0')
        obj['equipment'] = {'capturedAt': 950, 'scanComplete': False, 'bySlot': {
            'head': False, 'neck': {}, 'mainHand': {'itemID': 100, 'link': 'item:100:7:8',
                'stats': {'intellect': 9, 'UNKNOWN_TOKEN': 0},
                'tooltipLines': ['Équip: exact effect', {'left': 'Damage', 'right': 'Speed'}, {'right': 'Only right'}],
                'enhancements': {'enchantID': 0, 'sockets': [], 'emptySockets': {}},
                'incompleteFields': ['tooltipLines']}}}
        obj['spellbook'] = {'scanComplete': False, 'entries': {
            'columns': ['spellID', 'castTimeMs', 'isPassive', 'powerCosts', 'stats', 'tooltipLines'],
            'rows': [[1, 0, False, [], {}, ['Exact effect']], [2, None, True, None, {}, []]]}}
        obj['talents'] = {'capturedAt': 900, 'trees': [{'nodes': {
            'columns': ['id', 'entries'], 'rows': [[1, []], [2, {'columns': ['id','selected'], 'rows': [[10,False]]}]]}}]}
        for raw in (False, True):
            for byte_string in (False, True):
                decoded = decoder.decode_export(wrap(json.dumps(obj, ensure_ascii=False), raw=raw, byte_string=byte_string))
                self.assertEqual(decoded, obj)
                self.assertIs(decoded['equipment']['bySlot']['head'], False)
                self.assertEqual(decoded['equipment']['bySlot']['neck'], {})
                self.assertEqual(decoded['equipment']['capturedAt'], 950)
                self.assertIsNone(decoded['spellbook']['entries']['rows'][1][1])
                self.assertEqual(decoded['spellbook']['entries']['rows'][0][3], [])
                self.assertEqual(decoded['spellbook']['entries']['rows'][0][4], {})

    def test_gameplay_context_schema_five(self):
        original = self.compact_fixture()
        original.update(schemaVersion=5, addonVersion='1.0.0')
        for entries in ([], [{'skillLineID': 356, 'name': 'Fishing', 'category': 'secondary',
                              'rank': 0, 'maxRank': 75, 'modifier': -2, 'tempPoints': 0}],
                        {'columns': ['category', 'maxRank', 'modifier', 'name', 'rank', 'skillLineID', 'tempPoints'],
                         'rows': [['secondary', 75, None, 'Pêche', 0, 356, 0]]}):
            obj = json.loads(json.dumps(original))
            obj['basic'].update(moneyCopper=0, xp={'current': 0, 'levelTotal': 0, 'disabled': False})
            obj['professions'] = {'scanComplete': True, 'entries': entries}
            for raw in (False, True):
                decoded = decoder.decode_export(wrap(json.dumps(obj, ensure_ascii=False), raw=raw, byte_string=True))
                self.assertEqual(decoded, obj)
                self.assertNotIn('rested', decoded['basic']['xp'])
                self.assertIs(decoded['basic']['xp']['disabled'], False)
                for key in ('equipment', 'talents', 'spellbook', 'items'):
                    self.assertEqual(decoded[key], original[key])
        del obj['professions']
        del obj['basic']['xp']
        del obj['basic']['moneyCopper']
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)

    def test_cli_compact_default_and_pretty_roundtrip(self):
        obj = self.compact_fixture()
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory) / 'cache.txt'
            output = Path(directory) / 'decoded.json'
            cache.write_bytes(wrap(json.dumps(obj, ensure_ascii=False), byte_string=True))
            original = cache.read_bytes()
            command = [sys.executable, str(ROOT / 'tools/inspect_export.py'), str(cache), '--output', str(output)]
            subprocess.run(command, check=True, capture_output=True, text=True)
            compact = output.read_text(encoding='utf-8')
            self.assertEqual(compact, json.dumps(obj, ensure_ascii=False, separators=(',', ':')) + '\n')
            subprocess.run(command + ['--pretty'], check=True, capture_output=True, text=True)
            pretty = output.read_text(encoding='utf-8')
            self.assertEqual(json.loads(compact), json.loads(pretty))
            self.assertGreater(len(pretty), len(compact))
            self.assertIn('\n  "schemaVersion": 3', pretty)
            self.assertEqual(cache.read_bytes(), original)

    def test_eight_category_schema(self):
        obj = {'schemaVersion': 2, 'sourceAddon': 'Exporter', 'capturedAt': 1000,
               'character': {'guid': 'Player-fictional'},
               'basic': {'available': False, 'status': 'disabled'},
               'location': {'available': False, 'status': 'disabled'},
               'characterStats': {'available': True, 'capturedAt': 1000,
                                  'general': {'health': {'maximum': 500}, 'mana': {'maximum': 800}}},
               'equipment': {'available': True, 'status': 'available', 'capturedAt': 1000,
                             'slots': [{'slotID': 16, 'empty': False, 'itemID': 100,
                                        'stats': {'ITEM_MOD_INTELLECT_SHORT': 4},
                                        'tooltipLines': [], 'enhancements': {'sockets': []}}]},
               'talents': {'available': True, 'status': 'pending_changes', 'capturedAt': 900,
                           'configID': 1, 'pendingChanges': True, 'selectedTalents': [], 'currencies': [],
                           'trees': [{'id': 10, 'groups': [], 'nodes': [], 'currencies': []}]},
               'spellbook': {'available': True, 'status': 'available', 'capturedAt': 1000,
                            'skillLines': [], 'entries': [
                                {'spellID': 100, 'rank': 1, 'highestLearnedRank': 2,
                                 'powerCosts': [], 'tooltipLines': []},
                                {'spellID': 101, 'rank': 2, 'highestLearnedRank': 2,
                                 'powerCosts': [{'type': 1, 'cost': 10}], 'baseCooldownMs': 0}]},
               'questLog': {'available': True, 'status': 'partial', 'capturedAt': 1000,
                            'active': {'available': True, 'scanComplete': True, 'headers': [],
                                       'entries': [{'questID': 10, 'title': 'Quête', 'objectives': [],
                                                    'rewards': {'xp': 0, 'money': 0, 'items': [],
                                                                'choices': [], 'currencies': [], 'spells': [],
                                                                'majorFactionReputation': []}}]},
                            'completedHistory': {'available': True, 'scanComplete': True,
                                                 'questIDs': [1, 10, 999], 'titlesByQuestID': {'1': 'First quest'},
                                                 'pendingTitleIDs': [10], 'unavailableTitleIDs': [999]}},
               'items': {'available': True, 'status': 'available', 'capturedAt': 1000, 'scope': 'carried_bags',
                         'scanComplete': True, 'bags': [{'bagID': 0, 'numSlots': 3}],
                         'totalSlots': 3, 'freeSlots': 1, 'occupiedSlots': 2, 'itemCount': 7,
                         'entries': [{'bagID': 0, 'slotID': 1, 'empty': False, 'itemID': 500,
                                      'link': 'item:500:1', 'count': 3, 'name': 'Étoffe', 'stats': {},
                                      'tooltipLines': [], 'enhancements': {'sockets': [], 'emptySockets': {}}},
                                     {'bagID': 0, 'slotID': 2, 'empty': False, 'itemID': 500,
                                      'link': 'item:500:2', 'count': 4},
                                     {'bagID': 0, 'slotID': 3, 'empty': True, 'status': 'empty'}]}}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj), byte_string=True)), obj)
        obj['items'] = {'available': False, 'status': 'disabled'}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['items'] = {'available': True, 'status': 'available', 'bags': [], 'entries': [],
                        'totalSlots': 0, 'occupiedSlots': 0, 'freeSlots': 0, 'itemCount': 0}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        del obj['items']  # Seven-category schema-2 exports remain readable.
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['questLog'] = {'available': False, 'status': 'disabled'}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['questLog'] = {'available': True, 'active': {'entries': [], 'headers': []},
                          'completedHistory': {'questIDs': [], 'titlesByQuestID': {},
                                               'pendingTitleIDs': [], 'unavailableTitleIDs': []}}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        del obj['questLog']  # Six-category schema-2 exports remain readable.
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['spellbook'] = {'available': False, 'status': 'disabled'}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['spellbook'] = {'available': True, 'status': 'available', 'skillLines': [], 'entries': []}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        del obj['spellbook']  # Five-category schema-2 exports remain readable.
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['talents'] = {'available': False, 'status': 'disabled'}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        del obj['talents']  # Four-category schema-2 exports remain readable.
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        obj['equipment'] = {'available': False, 'status': 'disabled'}
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)
        del obj['equipment']  # Earlier schema-2 exports remain readable.
        self.assertEqual(decoder.decode_export(wrap(json.dumps(obj))), obj)

    def test_layout_without_marker_and_invalid_utf8(self):
        for layout in ([5, [], [], []], {1: 5, 127: b'OTHER1:foreign'}):
            self.assertIsNone(decoder.decode_export(b'1|' + base64.b64encode(zlib.compress(cbor2.dumps(layout)))))
        with self.assertRaises(ValueError):
            decoder.decode_export(b'1|' + base64.b64encode(zlib.compress(cbor2.dumps({1: 5, 127: b'EXP1:0000:\xff'}))))

    def test_other_exporters_are_not_exporter_data(self):
        self.assertIsNone(decoder.decode_export(wrap(json.dumps(self.fixture()), prefix='OTHER1')))

    def test_corrupt_checksum_and_invalid_snapshot(self):
        wire = wrap(json.dumps(self.fixture()))
        packed = cbor2.loads(zlib.decompress(base64.b64decode(wire[2:])))
        packed[127] += 'changed'
        with self.assertRaises(ValueError):
            decoder.decode_export(b'1|' + base64.b64encode(zlib.compress(cbor2.dumps(packed))))
        for obj in ({}, {'sourceAddon': 'Exporter', 'schemaVersion': 99}):
            with self.assertRaises(ValueError):
                decoder.decode_export(wrap(json.dumps(obj)))

    def test_bounded_decompression_and_trailing_data(self):
        for body in (zlib.compress(b'x' * (decoder.MAX_SIZE + 1)), zlib.compress(b'junk') + b'trailing'):
            with self.assertRaises(ValueError):
                decoder.decode_export(b'1|' + base64.b64encode(body))

    def test_clean_package_has_no_private_path_hints(self):
        hints = (ROOT / 'addon/Exporter/LocalPaths.lua').read_text(encoding='utf-8')
        self.assertIn('ExporterLocalPaths = {}', hints)
        self.assertNotIn('WTF', hints)
        toc = (ROOT / 'addon/Exporter/Exporter.toc').read_text(encoding='utf-8')
        self.assertIn('SavedVariablesPerCharacter: ExporterSnapshotJSON', toc)
        self.assertNotIn('Dependencies:', toc)
        self.assertIn('CharacterStats.lua', toc)
        self.assertIn('Equipment.lua', toc)
        self.assertIn('Talents.lua', toc)
        self.assertIn('Spellbook.lua', toc)
        self.assertIn('QuestLog.lua', toc)
        self.assertIn('Items.lua', toc)
        self.assertIn('Professions.lua', toc)


@unittest.skipUnless(os.name == 'nt', 'Windows PowerShell CLI tests')
class WindowsDecoderTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.directory = Path(temp.name)
        self.cache = self.directory / 'character [1] cache.txt'
        self.output = self.directory / 'export folder' / 'snapshot.json'
        self.script = ROOT / 'addon/Exporter/Decode-Export.ps1'
        self.snapshot = {
            'schemaVersion': 5, 'sourceAddon': 'Exporter', 'capturedAt': 1000,
            'character': {'guid': 'Player-fictional'},
            'basic': {'name': 'H\u00e9ro \U0001f31f: "One"', 'xp': {'current': 0}},
            'talents': {'capturedAt': 900, 'pendingChanges': False},
            'items': {'entries': {'columns': ['id', 'stats', 'effects'],
                                  'rows': [[1, {}, []], [2, None, ['line\n{two}']]]}},
        }

    def run_cli(self, *args):
        # Launch the Windows inbox host with only Windows tools on PATH.
        system = Path(os.environ['SystemRoot']) / 'System32'
        powershell = system / 'WindowsPowerShell' / 'v1.0' / 'powershell.exe'
        command = [powershell, '-NoLogo', '-NoProfile', '-NonInteractive',
                   '-ExecutionPolicy', 'Bypass', '-File', self.script,
                   '-Path', self.cache, *args]
        env = dict(os.environ, PATH=os.pathsep.join(map(str, [system, powershell.parent])))
        return subprocess.run(command, cwd=self.directory, env=env, capture_output=True, timeout=30)

    def test_stdout_matches_reference_across_wire_variants(self):
        for version, raw, byte_string in [(1, True, False), (2, False, True),
                                          (3, True, True), (4, False, False), (5, False, True)]:
            with self.subTest(version=version, raw=raw, byte_string=byte_string):
                self.snapshot['schemaVersion'] = version
                if version == 5:
                    # A full-size character uses a four-byte CBOR string length.
                    self.snapshot['questLog'] = {'completedHistory': {'questIDs': list(range(20000))}}
                wire = wrap(json.dumps(self.snapshot, ensure_ascii=False), raw=raw,
                            byte_string=byte_string, array=version in (2, 3))
                self.cache.write_bytes(wire)
                result = self.run_cli()
                self.assertEqual(result.returncode, 0, result.stderr)
                output = result.stdout.decode('utf-8')
                self.assertEqual(len(output.splitlines()), 1)
                self.assertEqual(json.dumps(json.loads(output), sort_keys=True),
                                 json.dumps(decoder.decode_export(wire), sort_keys=True))
                self.assertEqual(self.cache.read_bytes(), wire)

    def test_pretty_utf8_file_and_overwrite_protection(self):
        wire = wrap(json.dumps(self.snapshot, ensure_ascii=False), byte_string=True)
        self.cache.write_bytes(wire)
        result = self.run_cli('-Pretty', '-Output', self.output.relative_to(self.directory))
        self.assertEqual(result.returncode, 0, result.stderr)
        output = self.output.read_text(encoding='utf-8')
        self.assertGreater(len(output.splitlines()), 1)
        self.assertEqual(json.loads(output), self.snapshot)
        result = self.run_cli('-Output', self.cache.name)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.cache.read_bytes(), wire)

    def test_installed_decoder_replaces_output_while_cache_open_for_writing(self):
        installed = self.directory / "WoW [Forever]" / 'Interface' / 'AddOns' / 'Exporter'
        installed.mkdir(parents=True)
        shutil.copyfile(self.script.with_name('ExportWire.cs'), installed / 'ExportWire.cs')
        self.script = Path(shutil.copyfile(self.script, installed / self.script.name))
        wire = wrap(json.dumps(self.snapshot), raw=True, byte_string=True)
        self.cache.write_bytes(wire)
        self.output.parent.mkdir()
        self.output.write_text('previous snapshot', encoding='utf-8')

        with self.cache.open('r+b') as game:
            result = self.run_cli('-Output', self.output)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.decode('utf-8').strip()), self.output)
            self.assertEqual(json.loads(self.output.read_text(encoding='utf-8')), self.snapshot)
            self.assertEqual(game.read(), wire)

    def test_rejects_invalid_caches_and_preserves_previous_output(self):
        wire = wrap(json.dumps(self.snapshot))
        compressed = base64.b64decode(wire[2:])
        raw = base64.b64decode(wrap(json.dumps(self.snapshot), raw=True)[2:])
        layout = zlib.decompress(compressed)
        marker = cbor2.loads(layout)[127]
        cases = {
            'bad envelope': b'2|AAAA',
            'bad base64': b'1|!invalid!',
            'missing marker': envelope(cbor2.dumps([5, [], [], []])),
            'marker in unrelated field': envelope(cbor2.dumps({1: {127: marker}, '127': marker})),
            'foreign marker': wrap(json.dumps(self.snapshot), prefix='OTHER1'),
            'bad checksum': envelope(cbor2.dumps({127: marker + 'x'})),
            'bad utf-8': envelope(cbor2.dumps({127: b'EXP1:0000:\xff'})),
            'unsupported schema': wrap(json.dumps(dict(self.snapshot, schemaVersion=6))),
            'foreign source': wrap(json.dumps(dict(self.snapshot, sourceAddon='exporter'))),
            'missing guid': wrap(json.dumps(dict(self.snapshot, character={}))),
            'invalid JSON': wrap('{invalid}'),
            'excessive input': wire.ljust(decoder.MAX_SIZE + 1),
            'excessive expansion': envelope(cbor2.dumps({1: bytes(decoder.MAX_SIZE), 127: marker})),
            'trailing CBOR': envelope(layout + b'\x00'),
            'trailing zlib': b'1|' + base64.b64encode(compressed + b'extra'),
            'trailing deflate': b'1|' + base64.b64encode(raw + b'extra'),
            'truncated zlib': b'1|' + base64.b64encode(compressed[:-1]),
            'truncated deflate': b'1|' + base64.b64encode(raw[:-1]),
        }
        self.output.parent.mkdir()
        self.output.write_bytes(b'previous snapshot')
        for name, cache in cases.items():
            with self.subTest(case=name):
                self.cache.write_bytes(cache)
                result = self.run_cli('-Output', self.output)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(result.stderr.strip(), 'Expected a diagnostic')
                self.assertEqual(self.output.read_bytes(), b'previous snapshot')
                self.assertEqual(self.cache.read_bytes(), cache)
