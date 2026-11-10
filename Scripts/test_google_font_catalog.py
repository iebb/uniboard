import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('generator', Path(__file__).with_name('generate-google-font-catalog.py'))
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


def fixture_font(ps='Fixture-Regular', cmap=(65,), revision=1.0, weight=400, variable=False):
    from fontTools.fontBuilder import FontBuilder
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    from fontTools.ttLib import newTable
    from fontTools.ttLib.tables._f_v_a_r import Axis, NamedInstance
    builder = FontBuilder(1000, isTTF=True)
    names = ['.notdef'] + ['g%d' % c for c in cmap]
    builder.setupGlyphOrder(names)
    builder.setupCharacterMap({c: 'g%d' % c for c in cmap})
    glyph = TTGlyphPen(None).glyph()
    builder.setupGlyf({n: glyph for n in names})
    builder.setupHorizontalMetrics({n: (500, 0) for n in names})
    builder.setupHorizontalHeader(ascent=800, descent=-200)
    builder.setupNameTable({'familyName': 'Fixture', 'styleName': 'Regular', 'psName': ps})
    builder.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200, usWeightClass=weight)
    builder.setupPost(); builder.setupMaxp(); builder.setupHead(fontRevision=revision)
    if variable:
        axis = Axis(); axis.axisTag = 'wght'; axis.minValue = 100; axis.defaultValue = 400; axis.maxValue = 900; axis.flags = 0; axis.axisNameID = 256
        instance = NamedInstance(); instance.subfamilyNameID = 257; instance.coordinates = {'wght': 700}; instance.postscriptNameID = 65535
        builder.font['name'].setName('Bold', 257, 3, 1, 0x409)
        table = newTable('fvar'); table.axes = [axis]; table.instances = [instance]; builder.font['fvar'] = table
    data = io.BytesIO(); builder.save(data); return data.getvalue()

class FakeResponse:
    def __init__(self, status, text='', content=b''):
        self.status_code = status; self.text = text; self.content = content; self.headers = {'content-length': str(len(content))} if content else {}

class FakeSession:
    """Answers CSS2 and gstatic requests from dictionaries; records every URL."""
    def __init__(self, css, fonts):
        self.css = css; self.fonts = fonts; self.requests = []
    def get(self, url, headers=None, timeout=None, allow_redirects=True):
        self.requests.append((url, dict(headers or {}), allow_redirects))
        if url.startswith(generator.CSS2):
            answer = self.css.get(url, 400)
            return FakeResponse(answer, '') if isinstance(answer, int) else FakeResponse(200, answer)
        path = url[len(generator.GSTATIC):]
        return FakeResponse(200, content=self.fonts[path]) if path in self.fonts else FakeResponse(404)

def css_for(*paths):
    return ''.join("@font-face {\\n  font-family: 'Fixture';\\n  src: url(https://fonts.gstatic.com/%s) format('truetype');\\n}\\n" % p for p in paths)

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


    # MARK: Pinned gstatic instances (schemaVersion 2)

    def test_instance_request_sorts_axes_and_adds_ital_for_italic_files(self):
        url = generator.instance_request('Open Sans', {'wght': 700.0, 'wdth': 87.5}, False)
        self.assertEqual(url, generator.CSS2 + '?family=Open+Sans:wdth,wght@87.5,700&display=block')
        url = generator.instance_request('Roboto', {'wght': 700.0, 'wdth': 75.0}, True)
        self.assertTrue(url.endswith('family=Roboto:ital,wdth,wght@1,75,700&display=block'))
        url = generator.instance_request('Recursive', {'slnt': -15.0, 'CASL': 0.5, 'wght': 300.0}, False)
        self.assertIn(':slnt,wght,CASL@-15,300,0.5', url)
        self.assertIsNone(generator.instance_request('X', {}, False))
        self.assertIsNone(generator.instance_request('X', {'wg ht': 1}, False))
        self.assertTrue(generator.file_is_italic('ofl/roboto/Roboto-Italic[wdth,wght].ttf'))
        self.assertFalse(generator.file_is_italic('ofl/roboto/Roboto[wdth,wght].ttf'))

    def test_stylesheet_and_url_pinning(self):
        css = css_for('s/roboto/v51/KFOM-a_b.ttf', 's/roboto/v51/Other.ttf')
        self.assertEqual(generator.parse_stylesheet(css), ['https://fonts.gstatic.com/s/roboto/v51/KFOM-a_b.ttf', 'https://fonts.gstatic.com/s/roboto/v51/Other.ttf'])
        self.assertEqual(generator.gstatic_path('https://fonts.gstatic.com/s/roboto/v51/KFOM-a_b.ttf'), 's/roboto/v51/KFOM-a_b.ttf')
        for url in ('http://fonts.gstatic.com/s/a/v1/x.ttf', 'https://fonts.gstatic.com/l/font?kit=x', 'https://fonts.gstatic.com/s/a/v1/x.woff2',
                    'https://evil.example/s/a/v1/x.ttf', 'https://fonts.gstatic.com/s/a/v1/../x.ttf', 'https://fonts.gstatic.com/s/a/v1/x.ttf?y'):
            self.assertIsNone(generator.gstatic_path(url), url)

    def test_instance_rejection_reasons(self):
        base = dict(cmap=[65, 66], revision=3.015, postScriptName='Roboto-Regular', variable=True, weightClass=400)
        good = dict(cmap=[65, 66], revision=3.015, postScriptName='Roboto-Bold', variable=False, weightClass=700)
        self.assertIsNone(generator.instance_rejection(base, good, {'wght': 700.0}))
        self.assertEqual(generator.instance_rejection(base, {**good, 'variable': True}, {'wght': 700.0}), 'not_static')
        self.assertEqual(generator.instance_rejection(base, {**good, 'postScriptName': None}, {'wght': 700.0}), 'missing_postscript_name')
        self.assertEqual(generator.instance_rejection(base, {**good, 'revision': 1.104}, {'wght': 700.0}), 'version_mismatch')
        self.assertEqual(generator.instance_rejection(base, {**good, 'cmap': [65]}, {'wght': 700.0}), 'cmap_mismatch')
        self.assertEqual(generator.instance_rejection(base, good, {'wght': 900.0}), 'weight_mismatch')
        # GDI-compatible Thin/ExtraLight weight classes.
        self.assertIsNone(generator.instance_rejection(base, {**good, 'weightClass': 250}, {'wght': 100.0}))
        self.assertIsNone(generator.instance_rejection(base, {**good, 'weightClass': 250}, {'wght': 200.0}))
        self.assertEqual(generator.instance_rejection(base, {**good, 'weightClass': 300}, {'wght': 200.0}), 'weight_mismatch')
        self.assertIsNone(generator.instance_rejection(base, {**good, 'weightClass': 5}, {'wght': 350.5}))

    def test_retries_transient_but_not_permanent_errors(self):
        class Flaky:
            def __init__(self, statuses): self.statuses = list(statuses); self.calls = 0
            def get(self, url, headers=None, timeout=None, allow_redirects=True):
                self.calls += 1; self.allow_redirects = allow_redirects; return FakeResponse(self.statuses.pop(0), 'ok')
        sleeps = []
        flaky = Flaky([503, 429, 200])
        self.assertEqual(generator.fetch_with_retries(flaky, 'https://x', sleep=sleeps.append).text, 'ok')
        self.assertEqual((flaky.calls, sleeps, flaky.allow_redirects), (3, [1, 2], False))
        rejected = Flaky([400])
        with self.assertRaises(generator.PermanentHTTPError): generator.fetch_with_retries(rejected, 'https://x', sleep=sleeps.append)
        self.assertEqual(rejected.calls, 1)
        failing = Flaky([500] * 3)
        with self.assertRaises(generator.requests.RequestException): generator.fetch_with_retries(failing, 'https://x', attempts=3, sleep=lambda _: None)
        redirect = Flaky([302, 302])
        with self.assertRaises(generator.requests.RequestException): generator.fetch_with_retries(redirect, 'https://x', attempts=2, sleep=lambda _: None)

    def resolver_fixture(self, cache):
        variable = fixture_font('Fixture-Regular', cmap=(65, 66), revision=2.0, variable=True)
        bold = fixture_font('Fixture-Bold', cmap=(65, 66), revision=2.0, weight=700)
        old = fixture_font('Fixture-Light', cmap=(65, 66), revision=1.0, weight=300)
        subset = fixture_font('Fixture-Medium', cmap=(65,), revision=2.0, weight=500)
        black = fixture_font('Fixture-Black', cmap=(65, 66), revision=2.0, weight=700)
        q = lambda w: generator.instance_request('Fixture', {'wght': w}, False)
        css = {q(700): css_for('s/fixture/v1/bold.ttf'), q(300): css_for('s/fixture/v1/light.ttf'), q(500): css_for('s/fixture/v1/medium.ttf'),
               q(900): css_for('s/fixture/v1/black.ttf'), q(100): '', q(600): css_for('s/fixture/v1/a.ttf', 's/fixture/v1/b.ttf'),
               q(800): css_for('https://evil/x.ttf'.replace('https://', '')).replace('fonts.gstatic.com/evil', 'evil'), q(250): css_for('s/fixture/v1/missing.ttf')}
        fonts = {'s/fixture/v1/bold.ttf': bold, 's/fixture/v1/light.ttf': old, 's/fixture/v1/medium.ttf': subset, 's/fixture/v1/black.ttf': black}
        file = dict(id='ofl/fixture/Fixture[wght].ttf', repositoryPath='ofl/fixture/Fixture[wght].ttf', bytes=len(variable),
                    sha256=generator.hashlib.sha256(variable).hexdigest(), licenseIDs=['ofl/fixture/OFL.txt'])
        weights = [700, 300, 500, 900, 100, 600, 800, 250, 400]
        styles = [dict(id=f'{file["id"]}#{i}', name=str(w), fileID=file['id'], postScriptName='Fixture-Regular', variationInstance={'wght': float(w)}) for i, w in enumerate(weights)]
        styles[-1]['variationInstance'] = {'wght': 400.0}
        static = dict(id='ofl/fixture/Static.ttf', repositoryPath='ofl/fixture/Static.ttf', bytes=1, sha256='0' * 64, licenseIDs=[])
        snapshot = dict(schemaVersion=1, families=[dict(id='ofl/fixture', name='Fixture', styles=styles + [dict(id='ofl/fixture/Static.ttf#0', name='Regular', fileID=static['id'], postScriptName='Static')])],
                        files=[file, static])
        session = FakeSession(css, fonts)
        loads = []
        def repo(f): loads.append(f['id']); return variable
        return snapshot, generator.InstanceResolver(cache, repo, session=session, sleep=lambda _: None), session, loads

    def test_resolve_instances_accepts_only_matching_static_files_and_reports_reasons(self):
        with tempfile.TemporaryDirectory() as cache:
            snapshot, resolver, session, loads = self.resolver_fixture(cache)
            report = generator.resolve_instances(snapshot, resolver, workers=2, log=lambda *a, **k: None)
            styles = {s['name']: s for s in snapshot['families'][0]['styles']}
            self.assertEqual(styles['700']['instance']['postScriptName'], 'Fixture-Bold')
            self.assertEqual(styles['700']['instance']['path'], 's/fixture/v1/bold.ttf')
            self.assertEqual(len(styles['700']['instance']['sha256']), 64)
            for name in ('300', '500', '900', '100', '600', '800', '250', '400', 'Regular'):
                self.assertNotIn('instance', styles[name], name)
            self.assertEqual(report['accepted'], 1)
            self.assertEqual(report['rejectedByReason'], {'api_empty': 1, 'api_multiple_files': 1, 'api_rejected': 1, 'cmap_mismatch': 1,
                                                          'download_failed': 1, 'unpinnable_url': 1, 'version_mismatch': 1, 'weight_mismatch': 1})
            self.assertEqual((report['variableStyles'], report['notAttempted'], report['complete']), (9, 0, True))
            self.assertTrue(all(h['User-Agent'] == generator.INSTANCE_USER_AGENT and r is False for _, h, r in session.requests))
            # A rerun is served from the /tmp cache: no repository file and no network request.
            count = len(session.requests)
            snapshot2, resolver2, session2, loads2 = self.resolver_fixture(cache)
            again = generator.resolve_instances(snapshot2, resolver2, workers=1, log=lambda *a, **k: None)
            self.assertEqual(again['accepted'], 1)
            self.assertEqual(loads2, [])
            # Only the uncached 404 font is requested again.
            self.assertEqual([u for u, _, _ in session2.requests], [generator.GSTATIC + 's/fixture/v1/missing.ttf'])
            self.assertEqual(count, len(session.requests))
            subset = generator.resolve_instances(snapshot2, resolver2, families={'Other'}, log=lambda *a, **k: None)
            self.assertEqual((subset['complete'], subset['accepted'], subset['notAttempted']), (False, 0, 9))
            self.assertNotIn('instance', snapshot2['families'][0]['styles'][0])

    def test_unavailable_and_failing_repository_files(self):
        with tempfile.TemporaryDirectory() as cache:
            snapshot, resolver, _, _ = self.resolver_fixture(cache)
            snapshot['files'][0]['unavailableReason'] = 'Too large'
            report = generator.resolve_instances(snapshot, resolver, log=lambda *a, **k: None)
            self.assertEqual(report['rejectedByReason'], {'file_unavailable': 9})
        with tempfile.TemporaryDirectory() as cache:
            snapshot, _, session, _ = self.resolver_fixture(cache)
            def broken(_): raise ValueError('integrity')
            report = generator.resolve_instances(snapshot, generator.InstanceResolver(cache, broken, session=session), log=lambda *a, **k: None)
            self.assertEqual(report['rejectedByReason'], {'repository_file_failed: ValueError': 9})

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
        instances = [s['instance'] for f in catalog['families'] for s in f['styles'] if 'instance' in s]
        self.assertEqual(catalog['schemaVersion'], 2 if 'instances' in report else 1)
        if 'instances' in report:
            section = report['instances']
            self.assertEqual(len(instances), section['accepted'])
            self.assertEqual(section['variableStyles'], section['accepted'] + sum(section['rejectedByReason'].values()) + section['notAttempted'])
            self.assertEqual(sum(i['bytes'] for i in instances), section['totalInstanceBytes'])
        for family in catalog['families']:
            for style in family['styles']:
                if 'instance' not in style: continue
                instance = style['instance']
                self.assertIsNotNone(style.get('variationInstance'))
                self.assertFalse(files[style['fileID']].get('unavailableReason'))
                self.assertRegex(instance['path'], generator.GSTATIC_PATH)
                self.assertEqual(len(instance['sha256']), 64)
                self.assertTrue(0 < instance['bytes'] <= generator.CAP)
                self.assertTrue(instance['postScriptName'])

if __name__ == '__main__': unittest.main()
