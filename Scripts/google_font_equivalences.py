#!/usr/bin/env python3
"""Emit/check the bundled identity-only projection, offline with the Python stdlib.

Source order (including repeated static identities) and full axis coordinates are
preserved. catalogSHA256 covers the exact source bytes, not reserialized JSON.
Emission/check enforce a 2 MiB resource budget; neither requires site packages.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re

DEFAULT_DIRECTORY = Path(__file__).resolve().parents[1] / 'App/Resources/GoogleFonts'
MAX_BYTES = 2 * 1024 * 1024
HASH = re.compile(r'[0-9a-f]{64}')
INSTANCE_PATH = re.compile(r's/[a-z0-9]+/v[0-9]+/[A-Za-z0-9_-]+\.ttf')


def compact_json(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode('utf-8')


def project(catalog_bytes):
    """Validate accepted equivalences and retain only fields the shared decoder reads."""
    try:
        catalog = json.loads(catalog_bytes)
        if catalog['schemaVersion'] not in (1, 2):
            raise ValueError('Unsupported catalog schema')
        pin = catalog['repositoryCommit']
        if not isinstance(pin, str) or not re.fullmatch(r'[0-9a-f]{40}', pin):
            raise ValueError('Invalid repository commit')
        files = {}
        for file in catalog['files']:
            identifier = file['id']
            if not isinstance(identifier, str) or not identifier or identifier in files:
                raise ValueError('Invalid or duplicate file ID')
            files[identifier] = file
        families = []
        referenced = set()
        paths = {}
        for family in catalog['families']:
            styles = []
            for style in family['styles']:
                instance = style.get('instance')
                if instance is None:
                    continue
                if catalog['schemaVersion'] != 2:
                    raise ValueError('Instances require schema 2')
                file = files[style['fileID']]
                if file.get('unavailableReason') is not None:
                    raise ValueError('Instance references unavailable file')
                for digest in (file['sha256'], instance['sha256']):
                    if not isinstance(digest, str) or not HASH.fullmatch(digest):
                        raise ValueError('Invalid SHA-256')
                if file['sha256'] == instance['sha256']:
                    raise ValueError('Instance must differ from variable file')
                path = instance['path']
                if not isinstance(path, str) or not INSTANCE_PATH.fullmatch(path):
                    raise ValueError('Invalid instance path')
                if path in paths and paths[path] != instance['sha256']:
                    raise ValueError('Conflicting instance path hash')
                paths[path] = instance['sha256']
                axes = style['variationInstance']
                if not isinstance(axes, dict) or not axes:
                    raise ValueError('Missing full variation instance')
                for tag, value in axes.items():
                    # Numeric keys would be interpreted as Core Text axis IDs by
                    # FontFaceReference.tags, not preserved as four-byte tags.
                    if (not re.fullmatch(r'[\x20-\x7e]{4}', tag) or tag.isdecimal()
                            or isinstance(value, bool) or not isinstance(value, (int, float))
                            or not math.isfinite(value)):
                        raise ValueError('Invalid variation axis')
                styles.append(dict(fileID=style['fileID'], variationInstance=dict(axes),
                                   instance=dict(path=path, sha256=instance['sha256'])))
                referenced.add(style['fileID'])
            if styles:
                families.append(dict(styles=styles))
        return dict(schemaVersion=2, repositoryCommit=pin,
                    catalogSHA256=hashlib.sha256(catalog_bytes).hexdigest(),
                    files=[dict(id=f['id'], sha256=f['sha256']) for f in catalog['files'] if f['id'] in referenced],
                    families=families)
    except (KeyError, TypeError, OverflowError) as error:
        raise ValueError('Malformed catalog equivalence fields') from error


def equivalence_bytes(catalog_bytes):
    data = compact_json(project(catalog_bytes))
    if len(data) > MAX_BYTES:
        raise ValueError('Equivalence resource exceeds 2 MiB budget')
    return data


def emit(catalog_path, output_path, check=False):
    catalog_path, output_path = Path(catalog_path), Path(output_path)
    if catalog_path.resolve() == output_path.resolve():
        raise ValueError('Output must not overwrite the catalog')
    expected = equivalence_bytes(catalog_path.read_bytes())
    if check:
        if not output_path.exists() or output_path.read_bytes() != expected:
            raise ValueError('Stale or missing equivalences.json; regenerate from catalog.json')
    else:
        output_path.write_bytes(expected)
    return expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=DEFAULT_DIRECTORY / 'catalog.json')
    parser.add_argument('--output', type=Path, default=DEFAULT_DIRECTORY / 'equivalences.json')
    parser.add_argument('--check', action='store_true', help='Fail if bytes/provenance are stale; write nothing')
    args = parser.parse_args()
    try:
        data = emit(args.catalog, args.output, args.check)
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    projection = json.loads(data)
    print(f"{'Checked' if args.check else 'Wrote'} {len(data)} bytes: "
          f"{len(projection['files'])} files, {len(projection['families'])} families, "
          f"{sum(len(f['styles']) for f in projection['families'])} styles")


if __name__ == '__main__':
    main()
