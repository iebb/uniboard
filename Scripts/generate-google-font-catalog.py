#!/usr/bin/env python3
"""Generate the complete pinned google/fonts family catalog; all caches stay in /tmp.
Requires fonttools==4.67.0, protobuf==7.36.2, requests==2.34.2.

With --instances (or --augment-instances for an existing catalog), each named
instance of a variable repository file is also resolved once, at build time,
to a single static TTF on fonts.gstatic.com through the Google Fonts CSS2 API
with a fixed non-browser User-Agent (schemaVersion 2). An instance is recorded
only when its cmap equals the pinned repository file's cmap, its head
fontRevision matches, it has no fvar table and its OS/2 weight class is the
requested weight (Thin/ExtraLight may read 250-275 for GDI); otherwise the style keeps only its whole-file download.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import time
import uuid
from urllib.parse import quote
from google_font_equivalences import equivalence_bytes
import requests
from fontTools.ttLib import TTFont
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory, text_format

ROOTS = ('ofl', 'apache', 'ufl')
CAP = 40 * 1024 * 1024
CSS2 = 'https://fonts.googleapis.com/css2'
GSTATIC = 'https://fonts.gstatic.com/'
# Fixed and non-browser: the CSS2 API then serves one full-charset static TTF per style.
INSTANCE_USER_AGENT = 'Uniboard-catalog-generator/1.4'
GSTATIC_PATH = re.compile(r'^s/[a-z0-9]+/v[0-9]+/[A-Za-z0-9_-]+\.ttf$')

def metadata_type():
    schema = descriptor_pb2.FileDescriptorProto(name='catalog_metadata.proto', syntax='proto2')
    for name, fields in [('Font', [('name', 1, 9), ('style', 2, 9), ('weight', 3, 5), ('filename', 4, 9), ('post_script_name', 5, 9)]), ('Family', [('name', 1, 9), ('fonts', 6, 11)])]:
        msg = schema.message_type.add(name=name)
        for field, number, kind in fields:
            f = msg.field.add(name=field, number=number, type=kind, label=3 if field == 'fonts' else 1)
            if field == 'fonts': f.type_name = '.Font'
    pool = descriptor_pool.DescriptorPool(); pool.Add(schema)
    return message_factory.GetMessageClass(pool.FindMessageTypeByName('Family'))

Metadata = metadata_type()

def parse_metadata(data):
    return text_format.Parse(data.decode('utf-8'), Metadata(), allow_unknown_field=True)

def blob_sha(data):
    return hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()

def safe_path(path):
    parts = path.split('/')
    return len(parts) >= 3 and parts[0] in ROOTS and all(p not in ('', '.', '..') for p in parts) and not any(c in path for c in '\\?#%\x00')

def fetch(url):
    for attempt in range(6):
        try:
            r = requests.get(url, timeout=(20, 180)); r.raise_for_status(); return r.content
        except requests.RequestException:
            if attempt == 5: raise
            time.sleep(2 ** attempt)

def font_info(data):
    with TTFont(io.BytesIO(data), lazy=True) as font:
        names = font['name']
        ps = names.getDebugName(6)
        if not ps: raise ValueError('Missing PostScript name')
        default = names.getDebugName(17) or names.getDebugName(2) or 'Regular'
        instances = []
        if 'fvar' in font:
            for instance in font['fvar'].instances:
                name = names.getDebugName(instance.subfamilyNameID)
                instance_ps = names.getDebugName(instance.postscriptNameID) if instance.postscriptNameID != 65535 else None
                instances.append((name or default, instance_ps or ps, dict(instance.coordinates)))
        return ps, default, instances, names.getDebugName(16) or names.getDebugName(1)

class PermanentHTTPError(Exception):
    """A 4xx answer other than 408/429: retrying cannot help."""
    def __init__(self, status): super().__init__(f'HTTP {status}'); self.status = status

def fetch_with_retries(session, url, headers=None, attempts=6, sleep=time.sleep):
    for attempt in range(attempts):
        try:
            r = session.get(url, headers=headers or {}, timeout=(20, 180), allow_redirects=False)
            if 400 <= r.status_code < 500 and r.status_code not in (408, 429): raise PermanentHTTPError(r.status_code)
            if r.status_code != 200: raise requests.HTTPError(f'HTTP {r.status_code}')
            return r
        except PermanentHTTPError: raise
        except requests.RequestException:
            if attempt == attempts - 1: raise
            sleep(min(60, 2 ** attempt))

def axis_value(value):
    """CSS2 coordinates: whole numbers without decimals ("75", "87.5", "-10")."""
    value = float(value)
    return str(int(value)) if value.is_integer() else repr(value)

def file_is_italic(path):
    """Google splits variable families by slope: "Roboto-Italic[wdth,wght].ttf"."""
    stem = PurePosixPath(path).name.split('[')[0].rsplit('.', 1)[0]
    return 'italic' in stem.lower()

def instance_request(family, coordinates, italic):
    """The CSS2 URL for exactly one named instance, or None when it can't be expressed."""
    axes = {tag: float(value) for tag, value in coordinates.items()}
    if 'ital' not in axes and italic: axes['ital'] = 1.0
    if not axes or any(not re.fullmatch(r'[A-Za-z0-9]{4}', tag) for tag in axes): return None
    # Lowercase (registered) axes first, then custom ones, each alphabetically.
    tags = sorted(axes, key=lambda tag: (not tag.islower(), tag))
    spec = ','.join(tags) + '@' + ','.join(axis_value(axes[tag]) for tag in tags)
    return CSS2 + '?family=' + quote(family, safe='').replace('%20', '+') + ':' + spec + '&display=block'

def parse_stylesheet(text):
    """Every src URL in a CSS2 answer, in order."""
    return re.findall(r'src:\s*url\(([^)]+)\)', text)

def gstatic_path(url):
    """The pinned path of a fonts.gstatic.com TTF URL, else None."""
    if not url.startswith(GSTATIC): return None
    path = url[len(GSTATIC):]
    return path if GSTATIC_PATH.match(path) else None

def face_summary(data):
    """What instance validation compares: cmap, revision, identity, weight class."""
    with TTFont(io.BytesIO(data), lazy=True) as font:
        cmap = font.getBestCmap() or {}
        return dict(cmap=sorted(cmap), revision=round(font['head'].fontRevision, 3),
                    postScriptName=font['name'].getDebugName(6), variable='fvar' in font,
                    weightClass=font['OS/2'].usWeightClass if 'OS/2' in font else None)

def instance_rejection(base, instance, coordinates):
    """None when a static instance may stand in for the named instance, else the reason."""
    if instance.get('variable'): return 'not_static'
    if not instance.get('postScriptName'): return 'missing_postscript_name'
    if instance['revision'] != base['revision']: return 'version_mismatch'
    if instance['cmap'] != base['cmap']: return 'cmap_mismatch'
    wght = coordinates.get('wght')
    if wght is not None and float(wght).is_integer() and 1 <= wght <= 1000:
        # Thin/ExtraLight builds raise usWeightClass to 250 (or 275) for GDI; any other difference means a snapped instance.
        allowed = range(int(wght), 276) if wght < 250 else (int(wght),)
        if instance['weightClass'] not in allowed: return 'weight_mismatch'
    return None

class InstanceResolver:
    """Resolves and caches CSS2 answers and gstatic TTFs under a /tmp cache, so reruns are cheap."""
    def __init__(self, cache, repo_bytes, session=None, sleep=time.sleep):
        self.cache = Path(cache); self.repo_bytes = repo_bytes
        self.session = session or requests.Session(); self.sleep = sleep
        for sub in ('css', 'ttf', 'summary'): (self.cache / sub).mkdir(parents=True, exist_ok=True)

    def _store(self, path, data):
        temporary = path.with_name(path.name + '.' + uuid.uuid4().hex + '.tmp'); temporary.write_bytes(data); temporary.replace(path)

    def stylesheet(self, url):
        key = hashlib.sha256(url.encode()).hexdigest(); path = self.cache / 'css' / key
        if path.exists():
            cached = json.loads(path.read_text())
            if cached.get('status') == 200: return cached['text']
            raise PermanentHTTPError(cached['status'])
        try:
            text = fetch_with_retries(self.session, url, {'User-Agent': INSTANCE_USER_AGENT}, sleep=self.sleep).text
        except PermanentHTTPError as error:
            self._store(path, json.dumps(dict(status=error.status)).encode()); raise
        self._store(path, json.dumps(dict(status=200, text=text)).encode())
        return text

    def font(self, path):
        cached = self.cache / 'ttf' / hashlib.sha256(path.encode()).hexdigest()
        if cached.exists(): return cached.read_bytes()
        response = fetch_with_retries(self.session, GSTATIC + path, {'User-Agent': INSTANCE_USER_AGENT, 'Accept-Encoding': 'identity'}, sleep=self.sleep)
        data = response.content
        if response.headers.get('content-length') and int(response.headers['content-length']) != len(data): raise ValueError('Truncated ' + path)
        self._store(cached, data)
        return data

    def summary(self, sha, load):
        path = self.cache / 'summary' / sha
        if path.exists(): return json.loads(path.read_text())
        value = face_summary(load()); self._store(path, json.dumps(value).encode())
        return value

    def resolve_file(self, family, file, styles):
        """[(style, instance record or None, reason or None)] for one variable repository file."""
        base = self.summary(file['sha256'], lambda: self.repo_bytes(file))
        italic = file_is_italic(file['repositoryPath'])
        results = []
        for style in styles:
            coordinates = style['variationInstance']
            url = instance_request(family['name'], coordinates, italic)
            if url is None: results.append((style, None, 'unexpressible_axes')); continue
            try: sources = parse_stylesheet(self.stylesheet(url))
            except PermanentHTTPError: results.append((style, None, 'api_rejected')); continue
            except requests.RequestException: results.append((style, None, 'api_unreachable')); continue
            if not sources: results.append((style, None, 'api_empty')); continue
            if len(sources) != 1: results.append((style, None, 'api_multiple_files')); continue
            path = gstatic_path(sources[0])
            if path is None: results.append((style, None, 'unpinnable_url')); continue
            try: data = self.font(path)
            except (requests.RequestException, PermanentHTTPError, ValueError): results.append((style, None, 'download_failed')); continue
            if len(data) > CAP: results.append((style, None, 'too_large')); continue
            if data[:4] not in (b'\x00\x01\x00\x00', b'true'): results.append((style, None, 'not_truetype')); continue
            sha = hashlib.sha256(data).hexdigest()
            try: summary = self.summary(sha, lambda: data)
            except Exception: results.append((style, None, 'unreadable')); continue
            reason = instance_rejection(base, summary, coordinates)
            if reason: results.append((style, None, reason)); continue
            results.append((style, dict(path=path, bytes=len(data), sha256=sha, postScriptName=summary['postScriptName']), None))
        return results

def resolve_instances(snapshot, resolver, workers=8, families=None, log=print):
    """Adds `instance` to accepted styles in place; returns the coverage report section."""
    files = {f['id']: f for f in snapshot['files']}
    jobs = []; skipped = collections.Counter()
    for family in snapshot['families']:
        for style in family['styles']: style.pop('instance', None)
        if families is not None and family['name'] not in families: continue
        by_file = {}
        for style in family['styles']:
            if style.get('variationInstance') is None: continue
            if files[style['fileID']].get('unavailableReason'): skipped['file_unavailable'] += 1; continue
            by_file.setdefault(style['fileID'], []).append(style)
        jobs += [(family, files[file_id], styles) for file_id, styles in by_file.items()]
    accepted = 0; reasons = collections.Counter(skipped); rejected = []; accepted_families = set(); instance_bytes = 0
    def run(job):
        family, file, styles = job
        try: return job, resolver.resolve_file(family, file, styles)
        except Exception as exc: return job, [(style, None, 'repository_file_failed: ' + type(exc).__name__) for style in styles]
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        for index, ((family, file, _), results) in enumerate(pool.map(run, jobs)):
            for style, record, reason in results:
                if record:
                    style['instance'] = record; accepted += 1; accepted_families.add(family['id']); instance_bytes += record['bytes']
                else:
                    reasons[reason] += 1; rejected.append(dict(style=style['id'], reason=reason))
            if index % 25 == 0: log(f'{index}/{len(jobs)} variable files resolved, {accepted} instances accepted', flush=True)
    candidates = sum(1 for f in snapshot['families'] for s in f['styles'] if s.get('variationInstance') is not None)
    return dict(complete=families is None, userAgent=INSTANCE_USER_AGENT, requestedFamilies=sorted(families) if families is not None else None,
                variableStyles=candidates, variableFilesResolved=len(jobs), accepted=accepted, rejectedByReason=dict(sorted(reasons.items())),
                notAttempted=candidates - accepted - sum(reasons.values()), familiesWithInstances=len(accepted_families),
                totalInstanceBytes=instance_bytes, rejected=sorted(rejected, key=lambda r: r['style']))

def repository_bytes(pin, cache):
    """A pinned repository file by catalog SHA-256, cached under /tmp."""
    def load(file):
        path = Path(cache) / 'repo' / file['sha256']; path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists(): data = path.read_bytes()
        else: data = fetch(f'https://raw.githubusercontent.com/google/fonts/{pin}/{quote(file["repositoryPath"], safe="/")}')
        if len(data) != file['bytes'] or hashlib.sha256(data).hexdigest() != file['sha256']: raise ValueError('Repository integrity: ' + file['id'])
        if not path.exists(): path.write_bytes(data)
        return data
    return load

def write_catalog(output, snapshot, report):
    output = Path(output); output.mkdir(parents=True, exist_ok=True)
    (output/'catalog.json').write_text(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':'))+'\n')
    (output/'coverage.json').write_text(json.dumps(report, indent=2)+'\n')
    (output/'equivalences.json').write_bytes(equivalence_bytes((output/'catalog.json').read_bytes()))

def augment(args):
    output = Path(args.output)
    snapshot = json.loads((output/'catalog.json').read_text()); report = json.loads((output/'coverage.json').read_text())
    before = len(json.dumps({**snapshot, 'families': [{**f, 'styles': [{k: v for k, v in s.items() if k != 'instance'} for s in f['styles']]} for f in snapshot['families']], 'schemaVersion': 1}, ensure_ascii=False, separators=(',', ':')).encode()) + 1
    families = set(args.instance_families.split('|')) if args.instance_families else None
    resolver = InstanceResolver(args.instance_cache, repository_bytes(snapshot['repositoryCommit'], args.instance_cache))
    section = resolve_instances(snapshot, resolver, workers=args.instance_workers, families=families)
    snapshot['schemaVersion'] = 2
    section['catalogBytesWithoutInstances'] = before
    section['catalogBytes'] = len(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':')).encode()) + 1
    report['instances'] = section
    write_catalog(output, snapshot, report)
    print(json.dumps({k: v for k, v in section.items() if k != 'rejected'}, indent=2), flush=True)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--commit', default='main'); p.add_argument('--cache', default='/tmp/uniboard-google-fonts')
    p.add_argument('--workers', type=int, default=12)
    p.add_argument('--output', default='App/Resources/GoogleFonts')
    p.add_argument('--instances', action='store_true', help='Also resolve pinned gstatic single-style instances (schemaVersion 2)')
    p.add_argument('--augment-instances', action='store_true', help='Resolve instances for the existing catalog in --output only')
    p.add_argument('--instance-families', help='Only these family names, separated by "|" (the report then says complete: false)')
    p.add_argument('--instance-cache', default='/tmp/gf-instances')
    p.add_argument('--instance-workers', type=int, default=8)
    args = p.parse_args()
    if not Path(args.instance_cache).resolve().is_relative_to(Path('/tmp')): p.error('Instance cache must be under /tmp')
    if not 1 <= args.instance_workers <= 16: p.error('instance workers must be 1...16')
    if args.augment_instances: return augment(args)
    cache = Path(args.cache).resolve()
    if not cache.is_relative_to(Path('/tmp')): p.error('Cache must be under /tmp')
    if not 1 <= args.workers <= 24: p.error('workers must be 1...24')
    commit = json.loads(fetch('https://api.github.com/repos/google/fonts/commits/' + quote(args.commit, safe='')))
    pin = commit['sha']; date = commit['commit']['committer']['date'][:10]
    tree = json.loads(fetch(f'https://api.github.com/repos/google/fonts/git/trees/{pin}?recursive=1'))
    if tree.get('truncated'): raise ValueError('Truncated repository tree; refusing partial catalog')
    blobs = {x['path']: x for x in tree['tree'] if x['type'] == 'blob'}
    metas = sorted(x for x in blobs if x.endswith('/METADATA.pb') and x.split('/')[0] in ROOTS)
    cache.mkdir(parents=True, exist_ok=True)
    def get(path):
        entry = blobs[path]; dest = cache / entry['sha']
        data = dest.read_bytes() if dest.exists() else fetch(f'https://raw.githubusercontent.com/google/fonts/{pin}/{quote(path, safe="/")}')
        if len(data) != entry['size'] or blob_sha(data) != entry['sha']: raise ValueError('Blob integrity: ' + path)
        if not dest.exists():
            temporary = cache / (entry['sha'] + '.' + uuid.uuid4().hex + '.tmp')
            temporary.write_bytes(data)
            temporary.replace(dest)
        return data
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        metadata = dict(zip(metas, pool.map(get, metas)))
    families = []; files = {}; licenses = {}; missing = []; missing_licenses = []; referenced = set(); metadata_referenced = set(); font_results = {}
    plans = []
    license_paths_by_directory = {}
    for path in blobs:
        if PurePosixPath(path).name in ('OFL.txt', 'LICENSE.txt', 'UFL.txt', 'LICENCE.txt'):
            license_paths_by_directory.setdefault(str(PurePosixPath(path).parent), []).append(path)
    for path, data in metadata.items():
        m = parse_metadata(data); directory = str(PurePosixPath(path).parent)
        if not m.name or not m.fonts: raise ValueError('Missing family metadata: ' + path)
        paths = sorted({directory + '/' + f.filename for f in m.fonts})
        metadata_referenced.update(paths)
        paths = sorted(set(paths) | {p for p in blobs if p.startswith(directory + '/') and p.lower().endswith(('.ttf', '.otf', '.ttc', '.otc'))})
        for fp in paths:
            if fp not in blobs or not safe_path(fp): raise ValueError('Missing/unsafe file: ' + fp)
        lp = sorted(license_paths_by_directory.get(directory, []))
        if not lp: missing_licenses.append(directory)
        plans.append((directory, m, paths, lp)); referenced.update(paths)
    missing_family_metadata = sorted({ '/'.join(path.split('/')[:2]) for path in blobs if path.split('/')[0] in ROOTS and path.lower().endswith(('.ttf', '.otf')) } - {str(PurePosixPath(path).parent) for path in metas})
    for directory in missing_family_metadata:
        m = Metadata(name=directory.split('/')[-1])
        paths = sorted(path for path in blobs if path.startswith(directory + '/') and path.lower().endswith(('.ttf', '.otf')))
        for path in paths: m.fonts.add(filename=path[len(directory)+1:])
        lp = sorted(directory + '/' + name for name in ('OFL.txt', 'LICENSE.txt', 'UFL.txt', 'LICENCE.txt') if directory + '/' + name in blobs)
        if not lp: missing_licenses.append(directory)
        plans.append((directory, m, paths, lp)); referenced.update(paths)
    all_paths = sorted(referenced | {p for _, _, _, lp in plans for p in lp})
    def process(path):
        data = get(path)
        if path in referenced:
            try: info = font_info(data); error = None
            except Exception as exc: info = None; error = 'Unsupported font metadata: ' + str(exc)
            return path, (len(data), hashlib.sha256(data).hexdigest(), info, error)
        return path, data
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        for index, (path, result) in enumerate(pool.map(process, all_paths)):
            font_results[path] = result
            if index % 100 == 0: print(f'{index}/{len(all_paths)} files verified', flush=True)
    for directory, m, paths, lp in plans:
        for path in lp:
            data = font_results[path]
            licenses[path] = dict(id=path, name={'OFL.txt':'SIL Open Font License 1.1','UFL.txt':'Ubuntu Font Licence 1.0','LICENSE.txt':'Apache License 2.0','LICENCE.txt':'Font license'}[PurePosixPath(path).name], repositoryPath=path, sha256=hashlib.sha256(data).hexdigest(), text=data.decode('utf-8'))
        styles = []
        for path in paths:
            size, sha, info, error = font_results[path]
            declared = [f for f in m.fonts if directory + '/' + f.filename == path]
            if info:
                ps, default, instances, binary_family = info
                if directory in missing_family_metadata and binary_family: m.name = binary_family
                faces = instances or [(default, ps, None)]
                expected = [ps]
            else:
                missing.append(dict(path=path, reason=error)); expected = sorted({f.post_script_name for f in declared if f.post_script_name})
                faces = [(f.style + ' ' + str(f.weight), f.post_script_name, None) for f in declared]
            file = dict(id=path, repositoryPath=path, bytes=size, sha256=sha, expectedPostScriptNames=expected, licenseIDs=lp)
            if not lp: file['unavailableReason'] = 'The pinned repository has no license notice for this family. Choose another font.'
            elif size > CAP: file['unavailableReason'] = 'This font exceeds the 40 MiB per-file limit. Choose another style or font.'
            elif error: file['unavailableReason'] = error
            elif not path.lower().endswith(('.ttf', '.otf')): file['unavailableReason'] = 'This font format is not supported.'
            files[path] = file
            for index, (name, ps, coords) in enumerate(faces):
                style = dict(id=f'{path}#{index}', name=name, fileID=path, postScriptName=ps)
                if coords is not None: style['variationInstance'] = coords
                styles.append(style)
        families.append(dict(id=directory, name=m.name, styles=styles))
    snapshot = dict(schemaVersion=1, repositoryCommit=pin, snapshotDate=date, families=sorted(families, key=lambda f:(f['name'].casefold(),f['id'])), files=[files[k] for k in sorted(files)], licenses=[licenses[k] for k in sorted(licenses)])
    repo_fonts = {p for p in blobs if p.split('/')[0] in ROOTS and p.lower().endswith(('.ttf','.otf','.ttc','.otc'))}
    report = dict(repositoryCommit=pin, snapshotDate=date, treeTruncated=False, metadataFamilies=len(metas), catalogFamilies=len(families), styles=sum(len(f['styles']) for f in families), files=len(files), licenses=len(licenses), totalFontBytes=sum(f['bytes'] for f in files.values()), unavailableFiles=[f['id'] for f in files.values() if f.get('unavailableReason')], missingFamilyMetadata=missing_family_metadata, missingLicenseFamilies=missing_licenses, missingFaceMetadata=missing, repositoryFontsNotReferencedByMetadata=sorted(repo_fonts-metadata_referenced), repositoryFontsNotIncluded=sorted(repo_fonts-referenced))
    if args.instances:
        before = len(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':')).encode()) + 1
        families = set(args.instance_families.split('|')) if args.instance_families else None
        resolver = InstanceResolver(args.instance_cache, lambda file: get(file['repositoryPath']))
        report['instances'] = resolve_instances(snapshot, resolver, workers=args.instance_workers, families=families)
        snapshot['schemaVersion'] = 2
        report['instances']['catalogBytesWithoutInstances'] = before
        report['instances']['catalogBytes'] = len(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':')).encode()) + 1
    write_catalog(args.output, snapshot, report)
    print(json.dumps({k:v for k,v in report.items() if not isinstance(v,(list,dict))}, indent=2), flush=True)

if __name__ == '__main__': main()
