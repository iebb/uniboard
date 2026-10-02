#!/usr/bin/env python3
"""Build UniBoard's compact, reproducible offline Unicode catalog.

Run: python3 Scripts/generate_unicode.py --source draft --refresh
All character properties/names come from UnicodeData and DerivedName. NamesList
supplies informative prose only, never normative properties. The keyboard maps
the generated file on demand; algorithmic names remain compact ranges.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import re
import struct
import unicodedata
import urllib.request
from pathlib import Path

FILES = ["ReadMe.txt", "UnicodeData.txt", "Blocks.txt", "NamesList.txt", "NameAliases.txt",
         "extracted/DerivedName.txt", "DerivedCoreProperties.txt"]
CATEGORIES = "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn".split()
ROOT = Path(__file__).resolve().parent.parent


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "UniBoard-Unicode-Catalog/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        content = response.read()
    return content


def resolve_source(source: str) -> tuple[str, dict]:
    base = f"https://www.unicode.org/Public/{source}/ucd/"
    if source != "draft":
        return base, {"sourceKind": "unicode-release"}
    # Unicode's public draft directory is empty between review cycles, and its
    # release-review snapshots can lag ongoing development. The official dev
    # repository consistently supplies the newest draft throughout both phases.
    # Pin one commit so every file in this generation is the same snapshot.
    api = "https://api.github.com/repos/unicode-org/unicodetools/commits?path=unicodetools/data/ucd/dev&per_page=1"
    commit = json.loads(fetch(api))[0]
    sha = commit["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("Invalid upstream development commit")
    return (f"https://raw.githubusercontent.com/unicode-org/unicodetools/{sha}/unicodetools/data/ucd/dev/",
            {"sourceKind": "unicode-development-draft", "sourceCommit": sha,
             "sourceCommitDate": commit["commit"]["committer"]["date"],
             "sourceRepository": "https://github.com/unicode-org/unicodetools"})


def fold(value: str) -> str:
    value = "".join(c for c in unicodedata.normalize("NFKD", value.lower())
                    if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w]+", " ", value, flags=re.UNICODE).split())


def span(value: str) -> tuple[int, int]:
    bits = value.strip().split("..")
    return int(bits[0], 16), int(bits[-1], 16)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="draft", help="Official Unicode source: draft (default), or a version such as 17.0.0")
    parser.add_argument("--cache-dir", "--cache", dest="cache", type=Path)
    parser.add_argument("--refresh", action="store_true", help="Fetch every source again; required for live draft CI builds")
    args = parser.parse_args()
    if args.source != "draft" and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.source):
        parser.error("--source must be draft or a Unicode version (for example 17.0.0)")
    base, provenance = resolve_source(args.source)
    args.cache = args.cache or ROOT / ".unicode-cache" / args.source
    args.cache.mkdir(parents=True, exist_ok=True)
    cache_source = args.cache / "source-url.txt"
    same_source = cache_source.exists() and cache_source.read_text() == base
    timestamp_file = args.cache / "refreshed-at.txt"
    if args.refresh or not same_source or not timestamp_file.exists():
        timestamp_file.write_text(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"))
    sources = {}
    for filename in FILES:
        path = args.cache / Path(filename).name
        if args.refresh or not same_source or not path.exists():
            content = fetch(base + filename)
            if content.lstrip().startswith(b"<"):
                raise ValueError(f"Expected Unicode text data, received HTML: {base + filename}")
            path.write_bytes(content)
        source_text = path.read_text("utf-8")
        source_date = re.search(r"(?:# Date:|Generation Date:)\s*([^\n]+)", source_text)
        sources[filename] = {"url": base + filename,
                             "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        if source_date:
            sources[filename]["sourceDate"] = source_date[1].strip()
        source_version = re.search(r"(?:-[Vv]?|Unicode Standard )([0-9]+\.[0-9]+\.[0-9]+)", source_text[:1500])
        if source_version:
            sources[filename]["declaredVersion"] = source_version[1]
    cache_source.write_text(base)

    def lines(filename: str):
        return (args.cache / Path(filename).name).read_text("utf-8").splitlines()

    readme = "\n".join(lines("ReadMe.txt"))
    version_match = re.search(r"[Vv]ersion\s+([0-9]+\.[0-9]+\.[0-9]+)", readme)
    development = provenance["sourceKind"] == "unicode-development-draft"
    if development:
        version_match = re.search(r"Blocks-([0-9]+\.[0-9]+\.[0-9]+)", lines("Blocks.txt")[0])
    if not version_match:
        raise ValueError("Could not determine the official Unicode source version")
    version = version_match[1]
    is_draft = development or "draft data files" in readme.lower()
    if args.source != "draft" and version != args.source:
        raise ValueError(f"Source version mismatch: requested {args.source}, received {version}")
    version_label = version + (" draft" if is_draft else "")
    for filename in ["Blocks.txt", "NameAliases.txt", "extracted/DerivedName.txt", "DerivedCoreProperties.txt"]:
        first = lines(filename)[0]
        if version not in first and not development:
            raise ValueError(f"Mixed Unicode versions: {filename} does not declare {version}")

    blocks = []
    for line in lines("Blocks.txt"):
        line = line.split("#")[0].strip()
        if line:
            extent, name = line.split(";", 1)
            start, end = span(extent)
            blocks.append({"name": name.strip(), "start": start, "end": end})

    def block_name(cp: int) -> str:
        for block in blocks:
            if block["start"] <= cp <= block["end"]:
                return block["name"]
        return "No Block"

    records = {}
    ranges = []
    pending = None
    patterns = []
    for line in lines("extracted/DerivedName.txt"):
        line = line.split("#")[0].strip()
        if line:
            extent, name = (part.strip() for part in line.split(";", 1))
            if "*" in name:
                patterns.append((*span(extent), name.removesuffix("*")))
    for line in lines("UnicodeData.txt"):
        fields = line.split(";")
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        if name.endswith(", First>"):
            pending = (cp, name, category)
        elif name.endswith(", Last>"):
            assert pending is not None and pending[2] == category
            if category == "Co":
                ranges.append((pending[0], cp, "PRIVATE USE-", category, 2))
            elif pending[1].startswith("<Hangul"):
                ranges.append((pending[0], cp, "HANGUL SYLLABLE ", category, 1))
            elif pending[1].startswith("<CJK"):
                ranges.append((pending[0], cp, "CJK UNIFIED IDEOGRAPH-", category, 0))
            elif pending[1].startswith("<Tangut"):
                ranges.append((pending[0], cp, "TANGUT IDEOGRAPH-", category, 0))
            elif category != "Cs":
                pattern = next((prefix for start, end, prefix in patterns
                                if start <= pending[0] and end >= cp), None)
                if pattern is None:
                    raise ValueError(f"Unsupported new algorithmic naming range: {pending[1]}")
                ranges.append((pending[0], cp, pattern, category, 0))
            # Surrogates are code units, not Unicode scalars, and cannot be text.
            pending = None
        else:
            records[cp] = {"name": name, "category": category, "aliases": [], "notes": []}

    for line in lines("extracted/DerivedName.txt"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        extent, name = (part.strip() for part in line.split(";", 1))
        if "*" not in name:
            continue
        start, end = span(extent)
        if any(existing[0] <= end and existing[1] >= start for existing in ranges):
            # UnicodeData provides the current assignment boundaries, including
            # new development ranges not yet present in generated DerivedName.
            continue
        if not all(cp in records for cp in range(start, end + 1)):
            raise ValueError(f"Derived name range disagrees with authoritative UnicodeData: {extent}")
        ranges.append((start, end, name.removesuffix("*"), "Lo", 0))
        for cp in range(start, end + 1):
            records.pop(cp, None)
    ranges.sort()
    assert all(left[1] < right[0] for left, right in zip(ranges, ranges[1:]))

    for line in lines("NameAliases.txt"):
        line = line.split("#")[0].strip()
        if line:
            code, alias, kind = line.split(";")
            record = records.get(int(code, 16))
            if record is not None:
                record["aliases"].append(alias)
                if record["name"] == "<control>" and kind == "control":
                    record["name"] = alias

    current = None
    for line in lines("NamesList.txt"):
        match = re.match(r"^([0-9A-F]{4,6})\t", line)
        if match:
            current = records.get(int(match[1], 16))
        elif line.startswith("@"):
            current = None
        elif current is not None and line.startswith("\t"):
            content = line.strip()
            if content.startswith(("= ", "% ")):
                current["aliases"].append(content[2:])
            elif content.startswith("* "):
                current["notes"].append(content[2:].replace("\\", ""))

    invisible = set()
    for line in lines("DerivedCoreProperties.txt"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        extent, property_name = (part.strip() for part in line.split(";", 1))
        if property_name == "Default_Ignorable_Code_Point":
            start, end = span(extent)
            invisible.update(range(start, end + 1))

    pool = bytearray()
    strings = {}

    def string(value: str) -> tuple[int, int]:
        if value not in strings:
            encoded = value.encode("utf-8")
            strings[value] = (len(pool), len(encoded))
            pool.extend(encoded)
        return strings[value]

    version_offset, version_length = string(version_label)
    record_data = bytearray()
    for cp, record in sorted(records.items()):
        aliases = list(dict.fromkeys(record["aliases"]))
        notes = list(dict.fromkeys(record["notes"]))
        detail = "\n".join((["Also called: " + "; ".join(aliases)] if aliases else []) + notes)
        name_offset, name_length = string(record["name"])
        detail_offset, detail_length = string(detail)
        search_offset, search_length = string(fold(record["name"] + " " + detail + " " + block_name(cp)))
        flags = int(cp in invisible or record["category"] in {"Cc", "Cf", "Zs", "Zl", "Zp"})
        assert name_length <= 65535 and detail_length <= 65535
        record_data.extend(struct.pack("<IIHHIIIBBH", cp, name_offset, name_length,
                                       detail_length, detail_offset, search_offset,
                                       search_length, CATEGORIES.index(record["category"]), flags, 0))

    range_data = bytearray()
    for start, end, prefix, category, kind in ranges:
        offset, length = string(prefix)
        range_data.extend(struct.pack("<IIIHBB", start, end, offset, length,
                                      CATEGORIES.index(category), kind))
    record_offset = 48
    range_offset = record_offset + len(record_data)
    pool_offset = range_offset + len(range_data)
    assigned_count = len(records) + sum(end - start + 1 for start, end, *_ in ranges)
    header = struct.pack("<8s10I", b"UBOARD17", len(records), record_offset,
                         len(ranges), range_offset, pool_offset, len(pool),
                         version_offset, version_length, assigned_count, 1)
    output = ROOT / "Shared" / "Resources"
    output.mkdir(parents=True, exist_ok=True)
    (output / "UnicodeCatalog.ucd").write_bytes(header + record_data + range_data + pool)
    (output / "Blocks.json").write_text(json.dumps(blocks, ensure_ascii=False,
                                                   separators=(",", ":")) + "\n")
    source_dates = [value["sourceDate"] for value in sources.values() if "sourceDate" in value]
    manifest = {"unicodeVersion": version, "versionLabel": version_label, "isDraft": is_draft,
                "source": args.source, "sourceLastModified": max(source_dates) if source_dates else None,
                "refreshedAt": timestamp_file.read_text(),
                **provenance,
                "formatVersion": 1, "blocks": len(blocks),
                "explicitRecords": len(records), "algorithmicRanges": len(ranges),
                "assignedScalarsIncludingPrivateUse": assigned_count,
                "catalogBytes": len(header + record_data + range_data + pool),
                "sources": sources,
                "notes": "NamesList annotations are informative prose. Algorithmic names use DerivedName and the normative Hangul syllable naming algorithm. Surrogates are excluded; direct scalar lookup labels reserved and noncharacter code points."}
    (output / "UnicodeSources.json").write_text(json.dumps(manifest, indent=2) + "\n")
    license_path = output / "Unicode-LICENSE.txt"
    if not license_path.exists():
        with urllib.request.urlopen("https://www.unicode.org/license.txt", timeout=60) as response:
            license_path.write_bytes(response.read())
    print(json.dumps({k: v for k, v in manifest.items() if k not in {"sources", "notes"}}, indent=2))


if __name__ == "__main__":
    main()
