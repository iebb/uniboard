#!/usr/bin/env python3
"""Generate the complete pinned google/fonts family catalog; all caches stay in /tmp.
Requires fonttools==4.67.0, protobuf==7.36.2, requests==2.34.2.
"""
import argparse
import concurrent.futures
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import time
import uuid
from urllib.parse import quote
import requests
from fontTools.ttLib import TTFont
from google.protobuf import descriptor_pb2, descriptor_pool, message_factory, text_format

ROOTS = ('ofl', 'apache', 'ufl')
CAP = 40 * 1024 * 1024

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

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--commit', default='main'); p.add_argument('--cache', default='/tmp/uniboard-google-fonts')
    p.add_argument('--workers', type=int, default=12)
    p.add_argument('--output', default='App/Resources/GoogleFonts')
    args = p.parse_args()
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
    output = Path(args.output); output.mkdir(parents=True, exist_ok=True)
    (output/'catalog.json').write_text(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':'))+'\n')
    (output/'coverage.json').write_text(json.dumps(report, indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if not isinstance(v,list)}, indent=2), flush=True)

if __name__ == '__main__': main()
