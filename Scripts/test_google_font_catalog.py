import importlib.util
import json
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('generator', Path(__file__).with_name('generate-google-font-catalog.py'))
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)

class CatalogGeneratorTests(unittest.TestCase):
    def test_textproto_parsing_handles_escapes_and_unknown_fields(self):
        m = generator.parse_metadata(b'name: "A \\"Font\\""\n designer: "Other"\n fonts { name: "A" style: "normal" weight: 400 filename: "A[wght].ttf" post_script_name: "A-Regular" }\n axes { tag: "wght" min_value: 100 max_value: 900 }')
        self.assertEqual(m.name, 'A "Font"')
        self.assertEqual(m.fonts[0].filename, 'A[wght].ttf')
    def test_blob_integrity_is_git_blob_not_plain_sha1(self):
        self.assertEqual(generator.blob_sha(b'hello\n'), 'ce013625030ba8dba906f756967f9e9ca394464a')
    def test_paths_are_repository_relative(self):
        self.assertTrue(generator.safe_path('ofl/a/A[wght].ttf'))
        for path in ('/ofl/a/A.ttf', 'ofl/../A.ttf', 'ofl/a/%2e.ttf', 'ofl/a/A.ttf?x=1', 'https://evil/a.ttf'):
            self.assertFalse(generator.safe_path(path))
    def test_invalid_font_rejected(self):
        with self.assertRaises(Exception): generator.font_info(b'not a font')
    def test_variable_instances_share_the_original_binary(self):
        from fontTools.fontBuilder import FontBuilder
        from fontTools.pens.ttGlyphPen import TTGlyphPen
        from fontTools.ttLib import newTable
        from fontTools.ttLib.tables._f_v_a_r import Axis, NamedInstance
        import io
        builder = FontBuilder(1000, isTTF=True)
        builder.setupGlyphOrder(['.notdef', 'A'])
        builder.setupCharacterMap({65: 'A'})
        pen = TTGlyphPen(None)
        glyph = pen.glyph()
        builder.setupGlyf({'.notdef': glyph, 'A': glyph})
        builder.setupHorizontalMetrics({'.notdef': (500, 0), 'A': (500, 0)})
        builder.setupHorizontalHeader(ascent=800, descent=-200)
        builder.setupNameTable({'familyName': 'Fixture', 'styleName': 'Regular', 'psName': 'Fixture-Regular'})
        builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
        builder.setupPost(); builder.setupMaxp()
        axis = Axis(); axis.axisTag = 'wght'; axis.minValue = 100; axis.defaultValue = 400; axis.maxValue = 900; axis.flags = 0; axis.axisNameID = 256
        instance = NamedInstance(); instance.subfamilyNameID = 257; instance.coordinates = {'wght': 700}; instance.postscriptNameID = 65535
        builder.font['name'].setName('Bold', 257, 3, 1, 0x409)
        table = newTable('fvar'); table.axes = [axis]; table.instances = [instance]; builder.font['fvar'] = table
        data = io.BytesIO(); builder.save(data)
        ps, style, instances, family = generator.font_info(data.getvalue())
        self.assertEqual(ps, 'Fixture-Regular')
        self.assertEqual(instances, [('Bold', 'Fixture-Regular', {'wght': 700.0})])
        self.assertEqual(family, 'Fixture')

    def test_bundled_coverage(self):
        root = Path(__file__).resolve().parents[1] / 'App/Resources/GoogleFonts'
        if not (root/'catalog.json').exists(): self.skipTest('Generate catalog first')
        catalog = json.loads((root/'catalog.json').read_text())
        report = json.loads((root/'coverage.json').read_text())
        self.assertFalse(report['treeTruncated'])
        self.assertEqual(len(catalog['families']), report['metadataFamilies'] + len(report['missingFamilyMetadata']))
        self.assertGreater(len(catalog['families']), 2000)
        self.assertEqual(report['missingFaceMetadata'], [])
        self.assertEqual(report['repositoryFontsNotIncluded'], [])
        files = {f['id']: f for f in catalog['files']}
        self.assertEqual(len(files), len(catalog['files']))
        for family in catalog['families']:
            self.assertTrue(family['styles'])
            for style in family['styles']: self.assertIn(style['fileID'], files)
        for license in catalog['licenses']:
            self.assertEqual(generator.hashlib.sha256(license['text'].encode()).hexdigest(), license['sha256'])
        for file in files.values():
            self.assertEqual(len(file['sha256']), 64)
            self.assertGreater(file['bytes'], 0)
            self.assertTrue(file['expectedPostScriptNames'])
            if not file['licenseIDs']: self.assertTrue(file['unavailableReason'])
            if file['bytes'] > generator.CAP: self.assertTrue(file['unavailableReason'])

if __name__ == '__main__': unittest.main()
