#!/usr/bin/env python3
"""Audit an extracted shipping .app without mutating it; resource bytes != RAM."""
import argparse
import hashlib
import json
import pathlib
import plistlib


def sha(data):
    return hashlib.sha256(data).hexdigest()


def audit(app, source, version, build):
    vendor = source / 'Vendor/AzooKeyKanaKanjiConverter/Sources/EfficientNGram/tokenizer'
    forbidden = {sha(f.read_bytes()): f.name for f in vendor.rglob('*') if f.is_file()}
    maps = source / 'Shared/Resources/LanguageData/OpenCC'
    forbidden.update({sha(f.read_bytes()): f.name for f in maps.glob('*.txt')})
    descriptor = json.loads((source / 'App/Resources/LanguagePacks/japanese-pack-v1.json').read_text())
    for f in descriptor['files']:
        if f['byteCount'] > 0 and not any(word in f['path'].lower() for word in ['license', 'notice', 'readme']):
            forbidden.setdefault(f['sha256'], 'Japanese payload: ' + f['path'])
    failures = []
    files = []
    notices = []
    metadata = {}
    for bundle in [app, *app.glob('PlugIns/*.appex')]:
        info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        metadata[str(bundle.relative_to(app))] = {k: info.get(k) for k in ['CFBundleIdentifier', 'CFBundleShortVersionString', 'CFBundleVersion', 'DTXcode', 'DTSDKName']}
        if info.get('CFBundleShortVersionString') != version or info.get('CFBundleVersion') != build:
            failures.append('Wrong release identity: ' + str(bundle.relative_to(app)))
    if len(metadata) != 2:
        failures.append('Expected containing app and one keyboard extension')
    for f in sorted(app.rglob('*')):
        if not f.is_file():
            continue
        rel = f.relative_to(app).as_posix()
        data = f.read_bytes()
        digest = sha(data)
        row = {'path': rel, 'bytes': len(data), 'sha256': digest}
        files.append(row)
        if digest in forbidden:
            failures.append('Forbidden payload: ' + rel + ' (' + forbidden[digest] + ')')
        if any(t in rel.lower() for t in ['efficientngram', 'tokenizer.json', 'tokenizer_config.json', 'tscharacters.txt', 'tsphrases.txt', 'cjk_compatibility_ideographs.txt']):
            failures.append('Forbidden resource name: ' + rel)
        if rel.lower().endswith(('.sqlite', '.dict.yaml', '.louds', '.louds3', '/mm.binary')):
            failures.append('Bundled language dictionary: ' + rel)
        if 'license' in f.name.lower() or 'notice' in f.name.lower():
            notices.append(row)
    expected_notices = source / 'App/Resources/LanguagePacks'
    for f in expected_notices.glob('*.txt'):
        target = app / 'LanguagePacks' / f.name
        if not target.is_file() or target.read_bytes() != f.read_bytes():
            failures.append('Notice missing or changed: ' + f.name)
    keyboard_files = [r for r in files if r['path'].startswith('PlugIns/')]
    return {
        'app': app.name, 'metadata': metadata,
        'total_file_bytes': sum(r['bytes'] for r in files),
        'keyboard_file_bytes': sum(r['bytes'] for r in keyboard_files),
        'size_caveat': 'Uncompressed file bytes, including binaries/signatures. Not App Store compressed download size or runtime RAM.',
        'forbidden_matches': failures, 'notice_inventory': notices, 'files': files,
        'pass': not failures,
    }


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('app', type=pathlib.Path)
    p.add_argument('--source', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
    p.add_argument('--version', default='1.4')
    p.add_argument('--build', default='53')
    p.add_argument('--output', required=True, type=pathlib.Path)
    a = p.parse_args()
    result = audit(a.app, a.source, a.version, a.build)
    a.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ['files', 'notice_inventory']}, indent=2))
    raise SystemExit(0 if result['pass'] else 1)
