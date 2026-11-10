"""Dependency-free, offline consistency checks discovered by Scripts/tests CI."""
import ast
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'Scripts/google_font_equivalences.py'
SPEC = importlib.util.spec_from_file_location('google_font_equivalences', SCRIPT)
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


def fixture():
    return dict(schemaVersion=2, repositoryCommit='e7db6ca603fd4862010383ff17ffd6cc4ffac1c0',
                files=[dict(id='variable', sha256='a' * 64), dict(id='unused', sha256='b' * 64)],
                families=[dict(name='Fixture', styles=[dict(fileID='variable',
                    variationInstance={'wdth': 87.5, 'wght': 700},
                    instance=dict(path='s/fixture/v1/Ab_c-1.ttf', sha256='c' * 64))]),
                    dict(styles=[dict(fileID='unused')])])


def encode(value):
    return helper.compact_json(value)


class ProjectionTests(unittest.TestCase):
    def test_exact_projection_keeps_complete_coordinates_and_no_display_metadata(self):
        source = fixture()
        before = copy.deepcopy(source)
        raw = encode(source)
        self.assertEqual(helper.project(raw), dict(schemaVersion=2,
            repositoryCommit=source['repositoryCommit'], catalogSHA256=hashlib.sha256(raw).hexdigest(),
            files=[dict(id='variable', sha256='a' * 64)], families=[dict(styles=[dict(
                fileID='variable', variationInstance={'wdth': 87.5, 'wght': 700},
                instance=dict(path='s/fixture/v1/Ab_c-1.ttf', sha256='c' * 64))])]))
        self.assertEqual(source, before)

    def test_deterministic_bytes_and_exact_source_digest(self):
        raw = encode(fixture())
        self.assertEqual(helper.equivalence_bytes(raw), helper.equivalence_bytes(raw))
        self.assertTrue(helper.equivalence_bytes(raw).endswith(b'\n'))
        whitespace = raw + b' '
        self.assertNotEqual(helper.equivalence_bytes(raw), helper.equivalence_bytes(whitespace))
        self.assertEqual(helper.project(whitespace)['catalogSHA256'], hashlib.sha256(whitespace).hexdigest())

    def test_check_rejects_missing_stale_digest_and_edited_projection_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            catalog = Path(directory) / 'catalog.json'
            output = Path(directory) / 'equivalences.json'
            raw = encode(fixture())
            catalog.write_bytes(raw)
            with self.assertRaises(ValueError):
                helper.emit(catalog, output, check=True)
            expected = helper.emit(catalog, output)
            helper.emit(catalog, output, check=True)
            for key in ('catalogSHA256', 'families'):
                edited = json.loads(expected)
                edited[key] = '0' * 64 if key == 'catalogSHA256' else []
                output.write_bytes(encode(edited))
                before = output.read_bytes()
                with self.assertRaises(ValueError):
                    helper.emit(catalog, output, check=True)
                self.assertEqual(output.read_bytes(), before)
            output.write_bytes(expected)
            catalog.write_bytes(raw + b' ')
            with self.assertRaises(ValueError):
                helper.emit(catalog, output, check=True)
            self.assertEqual(output.read_bytes(), expected)
            with self.assertRaises(ValueError):
                helper.emit(catalog, catalog)
            self.assertEqual(catalog.read_bytes(), raw + b' ')

    def test_malformed_unavailable_hash_path_axis_and_unresolved_fields_fail_closed(self):
        changes = [lambda c: c.update(schemaVersion=3),
                   lambda c: c.update(repositoryCommit='main'),
                   lambda c: c['files'].append(c['files'][0]),
                   lambda c: c['files'][0].update(unavailableReason='disabled'),
                   lambda c: c['files'][0].update(unavailableReason=''),
                   lambda c: c['files'][0].update(sha256='A' * 64),
                   lambda c: c['files'][0].update(sha256='c' * 64),
                   lambda c: c['families'][0]['styles'][0]['instance'].update(sha256='bad'),
                   lambda c: c['families'][0]['styles'][0].update(fileID='missing'),
                   lambda c: c['families'][0]['styles'][0].pop('variationInstance')]
        for change in changes:
            source = fixture()
            change(source)
            with self.subTest(source=source), self.assertRaises(ValueError):
                helper.project(encode(source))
        for path in ('../x.ttf', 's/Fixture/v1/a.ttf', 's/fixture/v1/a.ttf?x',
                     'https://fonts.gstatic.com/s/fixture/v1/a.ttf', 's/fixture/v1/a.woff2'):
            source = fixture()
            source['families'][0]['styles'][0]['instance']['path'] = path
            with self.subTest(path=path), self.assertRaises(ValueError):
                helper.project(encode(source))
        for axes in (None, {}, {'bad': 700}, {'1234': 700}, {'éght': 700},
                     {'wght': True}, {'wght': '700'}, {'wght': float('inf')}, {'wght': float('nan')}):
            source = fixture()
            source['families'][0]['styles'][0]['variationInstance'] = axes
            with self.subTest(axes=axes), self.assertRaises(ValueError):
                helper.project(json.dumps(source).encode())
        for raw in (b'{}', b'[]', b'null', b'{', b'{"files": null}'):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                helper.project(raw)

    def test_repeated_static_identity_keeps_every_style_and_distinct_axes(self):
        source = fixture()
        style = copy.deepcopy(source['families'][0]['styles'][0])
        style['variationInstance']['wght'] = 900
        source['families'][0]['styles'].append(style)
        styles = helper.project(encode(source))['families'][0]['styles']
        self.assertEqual(len(styles), 2)
        self.assertEqual(styles[0]['instance'], styles[1]['instance'])
        self.assertNotEqual(styles[0]['variationInstance'], styles[1]['variationInstance'])
        style['instance']['sha256'] = 'd' * 64
        with self.assertRaises(ValueError):
            helper.project(encode(source))

    def test_schema_one_regular_generator_emits_empty_schema_two_projection(self):
        source = fixture()
        source['schemaVersion'] = 1
        with self.assertRaises(ValueError):
            helper.project(encode(source))
        source['families'][0]['styles'][0].pop('instance')
        projected = helper.project(encode(source))
        self.assertEqual(projected['schemaVersion'], 2)
        self.assertEqual(projected['files'], [])
        self.assertEqual(projected['families'], [])

    def test_generation_preserves_new_pin_without_expanding_runtime_trust(self):
        source = fixture()
        source['repositoryCommit'] = 'b' * 40
        self.assertEqual(helper.project(encode(source))['repositoryCommit'], 'b' * 40)
        source['repositoryCommit'] = 'main'
        with self.assertRaises(ValueError):
            helper.project(encode(source))

    def test_regular_and_augment_shared_writer_emits_companion_without_changing_catalog_format(self):
        # Extract only the shared writer: routine CI must not import its optional
        # network/font inspection dependencies just to test resource emission.
        tree = ast.parse((ROOT / 'Scripts/generate-google-font-catalog.py').read_text())
        writer = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'write_catalog')
        namespace = dict(Path=Path, json=json, equivalence_bytes=helper.equivalence_bytes)
        exec(compile(ast.Module(body=[writer], type_ignores=[]), '<catalog writer>', 'exec'), namespace)
        for schema in (1, 2):
            source = fixture()
            source['schemaVersion'] = schema
            if schema == 1:
                source['families'][0]['styles'][0].pop('instance')
            with self.subTest(schema=schema), tempfile.TemporaryDirectory() as directory:
                namespace['write_catalog'](directory, source, {'complete': True})
                catalog = (Path(directory) / 'catalog.json').read_bytes()
                self.assertEqual(catalog, encode(source))
                self.assertEqual((Path(directory) / 'equivalences.json').read_bytes(), helper.equivalence_bytes(catalog))
        for name in ('main', 'augment'):
            function = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == name)
            self.assertTrue(any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                                and node.func.id == 'write_catalog' for node in ast.walk(function)))

    def test_cli_runs_without_site_packages_and_check_is_offline(self):
        result = subprocess.run([sys.executable, '-S', str(SCRIPT), '--check'],
                                capture_output=True, text=True, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('5439 styles', result.stdout)

    def test_byte_budget_is_enforced(self):
        source = fixture()
        source['families'][0]['styles'] *= 12000
        with self.assertRaisesRegex(ValueError, '2 MiB'):
            helper.equivalence_bytes(encode(source))

    def test_shipped_resource_exact_projection_counts_provenance_and_budget(self):
        directory = ROOT / 'App/Resources/GoogleFonts'
        raw = (directory / 'catalog.json').read_bytes()
        actual = (directory / 'equivalences.json').read_bytes()  # Missing is a failure.
        self.assertEqual(actual, helper.equivalence_bytes(raw))
        projected = json.loads(actual)
        self.assertEqual(projected['catalogSHA256'], hashlib.sha256(raw).hexdigest())
        self.assertEqual(len(projected['files']), 730)
        self.assertEqual(len(projected['families']), 552)
        styles = [s for f in projected['families'] for s in f['styles']]
        self.assertEqual(len(styles), 5439)
        self.assertEqual(len({s['instance']['path'] for s in styles}), 5437)
        self.assertLessEqual(len(actual), 2 * 1024 * 1024)
        self.assertLess(len(actual), len(raw) // 8)
        # Independent projection, not merely the generator checking itself.
        source = json.loads(raw)
        accepted = [[s for s in f['styles'] if s.get('instance') is not None] for f in source['families']]
        accepted = [styles for styles in accepted if styles]
        self.assertEqual(projected['families'], [dict(styles=[dict(fileID=s['fileID'],
            variationInstance=s['variationInstance'], instance={k: s['instance'][k] for k in ('path', 'sha256')})
            for s in styles]) for styles in accepted])
        referenced = {s['fileID'] for styles in accepted for s in styles}
        self.assertEqual(projected['files'], [{k: f[k] for k in ('id', 'sha256')}
            for f in source['files'] if f['id'] in referenced])


if __name__ == '__main__':
    unittest.main()
