#!/usr/bin/env python3
"""Generate/check the original, data-only Uniboard two-set mapping pack offline.

Run from any directory:
    python3 Scripts/generate_hangul_resources.py
    python3 Scripts/generate_hangul_resources.py --check

Only docs/language-resources/hangul-2set/1/ is written. Nothing is bundled,
installed, uploaded, or fetched. --check does not write. Fixed USTAR metadata
and gzip mtime zero produce a reproducible archive for the existing bounded
tar.gz extractor. The manifest is a complete LanguagePackDescriptor.
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import string
import tarfile


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs/language-resources/hangul-2set/1"
URL = "https://uniboard.ieb.app/data/korean/hangul-2set/1/hangul-2set.tar.gz"
ARCHIVE_ROOT = "hangul-2set-1"
MAX_MAPPING_BYTES = 16_384
MAX_ARCHIVE_BYTES = 65_536
ROWS = (
    ("qwertyuiop", "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ"),
    ("asdfghjkl", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ"),
    ("zxcvbnm", "ㅋㅌㅊㅍㅠㅜㅡ"),
)
SHIFT = dict(zip("QWERTOP", "ㅃㅉㄸㄲㅆㅒㅖ"))
SOURCE_NOTICE = """Uniboard Korean Two-Set Hangul Mapping, version 1
Copyright (c) 2026 Kitta Ltd.

Original Uniboard JSON encoding of factual modern Korean two-set key
assignments. The encoding and accompanying original notices are released under
the MIT License in LICENSE.txt. No third-party code, dictionary, font, vendor
text, or vendor-specific input extensions are included.

The lowercase ASCII key IDs represent the QWERTY positions in these rows:
qwertyuiop -> ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ
asdfghjkl  -> ㅁㄴㅇㄹㅎㅗㅓㅏㅣ
zxcvbnm   -> ㅋㅌㅊㅍㅠㅜㅡ
Uppercase IDs represent Shift. Q W E R T O P produce ㅃ ㅉ ㄸ ㄲ ㅆ ㅒ ㅖ;
the other uppercase IDs produce the same jamo as their lowercase positions.

Reference links supplied and reviewed for this release on 2026-10-31:
- Typing Derby, Korean Keyboard Layout:
  https://typingderby.com/en/korean-keyboard-layout
  Reference for the complete key-position rows and shifted forms.
- Hancom Office help, Korean keyboard:
  https://help.hancom.com/hoffice/multi/ko_kr/show/insert/keyboard/keyboard(korea).htm
  Reference identifying the KS X 5002 two-set keyboard standard.

These references identify the factual keyboard positions; no vendor content is
redistributed and no endorsement, certification, or broader standards-compliance
claim is made. Vendor-specific extensions such as double-tap behavior are not
part of this mapping.

Schema: mapping.json contains schemaVersion 1 and exactly 52 key/jamo entries.
It is declarative key data only, not executable rules or a downloaded engine.
Modern L/V/T composition and compound handling are implemented by the separately
shipped native Uniboard engine with ABI uniboard-hangul-1. This resource contains
no romaja spelling grammar, Hanja, prediction, correction, or word corpus.

Reproduce offline with Scripts/generate_hangul_resources.py in the Uniboard
repository. Payload filenames and UTF-8/LF text encoding are fixed. The archive
is gzip-compressed USTAR with root hangul-2set-1 and exactly three regular files,
0644 permissions, uid/gid/mtime zero, empty owner/group names, and no extensions.
The gzip header has mtime zero and no original filename; compression level is 9.
"""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def mapping_entries() -> list[dict[str, str]]:
    lower: dict[str, str] = {}
    for keys, jamo in ROWS:
        require(len(keys) == len(jamo), "row length mismatch")
        lower.update(zip(keys, jamo))
    require(set(lower) == set(string.ascii_lowercase), "lowercase coverage")
    require(len(SHIFT) == 7, "shift coverage")
    entries = []
    for key in string.ascii_lowercase:
        entries.append({"key": key, "jamo": lower[key]})
        entries.append({"key": key.upper(), "jamo": SHIFT.get(key.upper(), lower[key])})
    require(len(entries) == 52, "mapping entry count")
    require({entry["key"] for entry in entries} == set(string.ascii_letters), "ASCII key coverage")
    valid_consonants = set("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    valid_vowels = {chr(value) for value in range(0x314F, 0x3164)}
    require(all(len(e["jamo"]) == 1 and e["jamo"] in valid_consonants | valid_vowels
                for e in entries), "invalid modern jamo")
    return entries


def verify_swift_fixture(entries: list[dict[str, str]]) -> None:
    """Compare independently authored row data with every existing XCTest entry."""
    tests = (ROOT / "Tests/KoreanHangulComposerTests.swift").read_text(encoding="utf-8")
    function = re.search(r"private func referenceEntries\(\).*?\n    }", tests, re.S)
    require(function is not None, "cannot find XCTest referenceEntries fixture")
    fixture = function.group(0)
    keys = re.search(r'let keys = Array\("([a-z]+)"\)', fixture)
    values = re.search(r'let values = Array\("([^"\n]+)"\)', fixture)
    shift = re.search(r"let shifted = \[([^\n]+)\]", fixture)
    require(keys is not None and values is not None and shift is not None,
            "cannot decode XCTest mapping fixture; review fixture changes")
    require(len(keys.group(1)) == len(values.group(1)) == 26, "fixture row size")
    shifted = dict(re.findall(r'"([a-z])": "([^"\n]+)"', shift.group(1)))
    require(len(shifted) == 7, "fixture shifted entry count")
    expected = []
    for key, jamo in zip(keys.group(1), values.group(1)):
        expected.append({"key": key, "jamo": jamo})
        expected.append({"key": key.upper(), "jamo": shifted.get(key, jamo)})
    require(entries == expected, "generated mapping differs from the 52-entry XCTest fixture")


def license_bytes() -> bytes:
    text = (ROOT / "LICENSE").read_text(encoding="utf-8")
    # Retain the exact MIT core, excluding the repository-specific scope note
    # about third-party code/fonts (none of which is included in this pack).
    core, separator, _ = text.partition("\nThis license covers Uniboard's own source code.")
    require(bool(separator), "repository MIT scope marker changed; review license")
    require(core.startswith("MIT License\n\nCopyright (c) 2026 Kitta Ltd.\n"),
            "repository MIT copyright changed; review license")
    require(core.rstrip().endswith("SOFTWARE."), "incomplete MIT license text")
    return (core.rstrip() + "\n").encode("utf-8")


def archive_bytes(payloads: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    # USTAR only: no PAX/GNU metadata, links, explicit directories, or extras.
    # The existing Swift extractor creates the necessary implicit root itself.
    with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, data in payloads.items():
            info = tarfile.TarInfo(name=f"{ARCHIVE_ROOT}/{name}")
            info.type = tarfile.REGTYPE
            info.mode = 0o644
            info.uid = info.gid = info.mtime = 0
            info.uname = info.gname = ""
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    tar_bytes = output.getvalue()
    require(len(tar_bytes) <= MAX_ARCHIVE_BYTES, "decoded tar exceeds small-pack bound")
    compressed = io.BytesIO()
    with gzip.GzipFile(filename="", fileobj=compressed, mode="wb",
                       compresslevel=9, mtime=0) as stream:
        stream.write(tar_bytes)
    result = compressed.getvalue()
    require(len(result) <= MAX_ARCHIVE_BYTES, "archive exceeds small-pack bound")
    require(result[:4] == b"\x1f\x8b\x08\x00" and result[4:8] == bytes(4),
            "gzip has flags or a nonzero timestamp")
    require(gzip.decompress(result) == tar_bytes, "gzip integrity failure")
    with tarfile.open(fileobj=io.BytesIO(tar_bytes), mode="r:") as archive:
        expected = [f"{ARCHIVE_ROOT}/{name}" for name in payloads]
        require(archive.getnames() == expected, "unexpected archive members/order")
        for info in archive.getmembers():
            require(info.isreg() and info.mode == 0o644, "nonregular/executable tar member")
            require(info.uid == info.gid == info.mtime == 0 and info.uname == info.gname == "",
                    "nondeterministic tar metadata")
            require(not info.pax_headers and not info.linkname, "tar extensions or links")
            name = info.name.removeprefix(ARCHIVE_ROOT + "/")
            require(info.size == len(payloads[name]), "tar member size mismatch")
            extracted = archive.extractfile(info)
            require(extracted is not None and extracted.read() == payloads[name], "tar payload mismatch")
    # Independently audit the header/padding restrictions of LanguagePackArchive,
    # not merely the more permissive Python tar reader's acceptance.
    offset = 0
    for name, data in payloads.items():
        header = tar_bytes[offset:offset + 512]
        require(header[:100].split(b"\0", 1)[0].decode() == f"{ARCHIVE_ROOT}/{name}", "tar path")
        require(header[156:157] == b"0", "tar entry type")
        require(header[257:265] == b"ustar\x0000", "non-USTAR header")
        require(header[500:512] == bytes(12), "unsupported header padding")
        checksum = int(header[148:156].rstrip(b"\0 "), 8)
        require(checksum == sum(header[:148]) + 8 * 32 + sum(header[156:]), "tar checksum")
        offset += 512 + len(data)
        padding = -len(data) % 512
        require(tar_bytes[offset:offset + padding] == bytes(padding), "nonzero tar payload padding")
        offset += padding
    require(len(tar_bytes) % 512 == 0 and len(tar_bytes) - offset >= 1024,
            "missing two tar end markers")
    require(tar_bytes[offset:] == bytes(len(tar_bytes) - offset), "nonzero trailing tar data")
    return result


def build_artifacts() -> dict[str, bytes]:
    entries = mapping_entries()
    verify_swift_fixture(entries)
    mapping = json_bytes({"schemaVersion": 1, "entries": entries})
    require(len(mapping) <= MAX_MAPPING_BYTES, "mapping exceeds native decoder bound")
    payloads = {
        "mapping.json": mapping,
        "LICENSE.txt": license_bytes(),
        "SOURCE.txt": SOURCE_NOTICE.encode("utf-8"),
    }
    archive = archive_bytes(payloads)
    files = [{"path": name, "byteCount": len(data), "sha256": sha256(data)}
             for name, data in payloads.items()]
    descriptor = {
        "formatVersion": 1,
        "packID": "korean-hangul-2set",
        "version": "1",
        "modeID": "koreanTwoSetHangul",
        "engineABI": "uniboard-hangul-1",
        "sourceURL": URL,
        "allowedHosts": ["uniboard.ieb.app"],
        "archiveByteCount": len(archive),
        "archiveSHA256": sha256(archive),
        "installedBytes": sum(file["byteCount"] for file in files),
        "fileCount": len(files),
        "files": files,
        "licenseNotice": payloads["LICENSE.txt"].decode("utf-8"),
        "sourceNotice": payloads["SOURCE.txt"].decode("utf-8"),
    }
    # Manifest is deliberately NOT inside the tar.gz; the app's trusted catalog
    # pins this descriptor independently of downloaded archive contents.
    return {**payloads, "hangul-2set.tar.gz": archive,
            "descriptor.json": json_bytes(descriptor)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate checked-in artifacts without writing")
    args = parser.parse_args()
    artifacts = build_artifacts()
    require(artifacts == build_artifacts(), "repeat generation differs")
    if args.check:
        for name, expected in artifacts.items():
            path = OUTPUT / name
            require(path.is_file() and path.read_bytes() == expected, f"artifact missing or stale: {path}")
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        for name, data in artifacts.items():
            (OUTPUT / name).write_bytes(data)
    print("Verified all 52 entries against XCTest; repeat generation is byte-identical.")
    print("tar.gz contains only three non-executable regular files; metadata/checksum/payload checks pass.")
    print(f"Pass archiveRoot={ARCHIVE_ROOT!r} to the existing bounded tar.gz extractor.")
    for name, data in artifacts.items():
        print(f"{len(data):6d} bytes  SHA-256 {sha256(data)}  {OUTPUT / name}")
    descriptor = json.loads(artifacts["descriptor.json"])
    print(f"Installed payload total: {descriptor['installedBytes']} bytes")
    print("No networking, app bundling, or deployment performed.")


if __name__ == "__main__":
    main()
