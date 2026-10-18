#!/usr/bin/env python3
"""Build UniBoard's compact, reproducible offline Unicode catalog.

Run: python3 Scripts/generate_unicode.py --source all --refresh
All character properties/names come from UnicodeData and DerivedName. NamesList
supplies informative prose only, never normative properties. The keyboard maps
the generated file on demand; algorithmic names remain compact ranges.
"""
from __future__ import annotations

import argparse
import bisect
import datetime
import hashlib
import http.client
import json
import os
import re
import shutil
import struct
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.request
from pathlib import Path

FILES = ["ReadMe.txt", "UnicodeData.txt", "Blocks.txt", "NamesList.txt", "NameAliases.txt",
         "extracted/DerivedName.txt", "DerivedCoreProperties.txt", "DerivedAge.txt", "Scripts.txt"]
CATEGORIES = "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn".split()
BIDI_CLASSES = "L R AL EN ES ET AN CS NSM BN B S WS ON LRE LRO RLE RLO PDF LRI RLI FSI PDI".split()
ROOT = Path(__file__).resolve().parent.parent
FETCH_ATTEMPTS = 3
MAX_RETRY_DELAY = 5


def fetch(url: str) -> bytes:
    """Retry idempotent downloads without returning or caching partial content."""
    for attempt in range(FETCH_ATTEMPTS):
        delay = min(2 ** attempt, MAX_RETRY_DELAY)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "UniBoard-Unicode-Catalog/1"})
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            # HTTPError owns the response stream too; release it before retrying
            # or propagating a permanent failure.
            error.close()
            if error.code != 429 and not 500 <= error.code < 600:
                raise
            if error.headers is not None:
                try:
                    delay = max(delay, min(int(error.headers.get("Retry-After", "0")), MAX_RETRY_DELAY))
                except (TypeError, ValueError):
                    pass
            if attempt + 1 == FETCH_ATTEMPTS:
                raise
        except (urllib.error.URLError, http.client.IncompleteRead,
                http.client.RemoteDisconnected, OSError):
            if attempt + 1 == FETCH_ATTEMPTS:
                raise
        print(f"Download interrupted; retrying {url} "
              f"({attempt + 2}/{FETCH_ATTEMPTS}) in {delay}s", file=sys.stderr)
        time.sleep(delay)
    raise AssertionError("Download retry loop did not return or raise")


def resolve_source(source: str) -> tuple[str, dict]:
    if source == "latest":
        readme = fetch("https://www.unicode.org/Public/UCD/latest/ucd/ReadMe.txt").decode("utf-8")
        match = re.search(r"final data files for version ([0-9]+\.[0-9]+\.[0-9]+)", readme)
        if match is None:
            raise ValueError("Latest Unicode source is not an official final release")
        source = match[1]
    base = f"https://www.unicode.org/Public/{source}/ucd/"
    if source != "draft":
        return base, {"sourceKind": "unicode-release"}
    # Unicode's public draft directory is empty between review cycles, and its
    # release-review snapshots can lag ongoing development. The official dev
    # repository consistently supplies the newest draft throughout both phases.
    # Pin one commit so every file in this generation is the same snapshot.
    # Default-branch HEAD also includes emoji-only changes after the last UCD
    # change. Both development directories must come from this one snapshot.
    api = "https://api.github.com/repos/unicode-org/unicodetools/commits?per_page=1"
    commit = json.loads(fetch(api))[0]
    sha = commit["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", sha):
        raise ValueError("Invalid upstream development commit")
    return (f"https://raw.githubusercontent.com/unicode-org/unicodetools/{sha}/unicodetools/data/ucd/dev/",
            {"sourceKind": "unicode-development-draft", "sourceCommit": sha,
             "sourceCommitDate": commit["commit"]["committer"]["date"],
             "sourceRepository": "https://github.com/unicode-org/unicodetools"})


def generation_plan(source: str) -> list[tuple[str, str, tuple[str, dict] | None]]:
    """Resolve the rolling release slots once, before any catalog is generated.

    Since Unicode 16, final major editions are annual. Pin the latest final's
    immutable directory, and independently validate the two preceding finals.
    A missing historical source fails the entire transaction; it never reuses
    a different edition in a historical slot.
    """
    if source not in {"all", "previous", "older"}:
        return [(source, "draft" if source == "draft" else "latest", None)]
    latest = resolve_source("latest")
    match = re.fullmatch(r"https://www\.unicode\.org/Public/([0-9]+)\.([0-9]+)\.([0-9]+)/ucd/", latest[0])
    if match is None or int(match[1]) < 3:
        raise ValueError("Cannot determine the preceding final Unicode releases")
    major = int(match[1])
    releases = [("latest", "latest", latest), (f"{major - 1}.0.0", "previous", None),
                (f"{major - 2}.0.0", "older", None)]
    return releases + [("draft", "draft", None)] if source == "all" else [
        item for item in releases if item[1] == source]


def emoji_source_base(base: str, provenance: dict) -> str:
    if provenance["sourceKind"] == "unicode-development-draft":
        return base.replace("/ucd/dev/", "/emoji/dev/")
    match = re.fullmatch(r"https://www\.unicode\.org/Public/([0-9]+)\.([0-9]+)\.([0-9]+)/ucd/", base)
    if match is None:
        raise ValueError("Unrecognized official final Unicode directory")
    # Emoji 16 and earlier used a separate versioned archive. From 17 onward,
    # emoji-test.txt is published beside that release's UCD directory.
    if int(match[1]) <= 16:
        return f"https://www.unicode.org/Public/emoji/{match[1]}.{match[2]}/"
    return base.removesuffix("ucd/") + "emoji/"


def fold(value: str) -> str:
    value = "".join(c for c in unicodedata.normalize("NFKD", value.lower())
                    if not unicodedata.combining(c))
    return " ".join(re.sub(r"[^\w]+", " ", value, flags=re.UNICODE).split())


def span(value: str) -> tuple[int, int]:
    text = value.strip()
    if not re.fullmatch(r"[0-9A-Fa-f]{1,6}(?:\.\.[0-9A-Fa-f]{1,6})?", text):
        raise ValueError(f"Invalid Unicode code-point range: {text}")
    bits = text.split("..")
    start, end = int(bits[0], 16), int(bits[-1], 16)
    if not 0 <= start <= end <= 0x10FFFF:
        raise ValueError(f"Invalid Unicode code-point range: {text}")
    return start, end


def version_key(value: str) -> int:
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}(?: draft)?", value):
        raise ValueError(f"Invalid Unicode version: {value}")
    parts = value.removesuffix(" draft").split(".")
    major, minor = int(parts[0]), int(parts[1]) if len(parts) > 1 else 0
    if minor >= 100 or major > (sys.maxsize - minor) // 100:
        raise ValueError(f"Unsupported Unicode version: {value}")
    return major * 100 + minor


def unicode_data_rows(source_lines: list[str]):
    """Validate UnicodeData before its rows can form compressed lookup ranges.

    Reject duplicates, truncated records and mismatched First/Last pairs even
    under python -O. A partial parse is never returned as a complete catalog.
    """
    previous, pending = -1, None
    count = 0
    for line in source_lines:
        fields = line.split(";")
        if len(fields) != 15 or not re.fullmatch(r"[0-9A-F]{4,6}", fields[0]):
            raise ValueError("Malformed UnicodeData record")
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        if cp <= previous or cp > 0x10FFFF:
            raise ValueError("UnicodeData code points must be valid, unique and increasing")
        if not name or category not in CATEGORIES or fields[4] not in BIDI_CLASSES:
            raise ValueError("Invalid UnicodeData name/category/bidirectional class")
        if (0xD800 <= cp <= 0xDFFF) != (category == "Cs"):
            raise ValueError("UnicodeData surrogate/category mismatch")
        if not re.fullmatch(r"[0-9]{1,3}", fields[3]) or int(fields[3]) > 255:
            raise ValueError("Invalid UnicodeData combining class")
        for mapping in fields[12:15]:
            if mapping and (not re.fullmatch(r"[0-9A-F]{4,6}", mapping)
                            or int(mapping, 16) > 0x10FFFF or 0xD800 <= int(mapping, 16) <= 0xDFFF):
                raise ValueError("Invalid UnicodeData simple case mapping")
        decomposition = re.sub(r"^<[A-Za-z]+> ", "", fields[5])
        if decomposition:
            for point in decomposition.split(" "):
                if (not re.fullmatch(r"[0-9A-F]{4,6}", point) or int(point, 16) > 0x10FFFF
                        or 0xD800 <= int(point, 16) <= 0xDFFF):
                    raise ValueError("Invalid UnicodeData decomposition")
        if name.endswith(", First>"):
            if pending is not None:
                raise ValueError("Nested UnicodeData First range")
            pending = (name.removesuffix(", First>"), category, fields[3], fields[4])
        elif name.endswith(", Last>"):
            if pending != (name.removesuffix(", Last>"), category, fields[3], fields[4]):
                raise ValueError("Unmatched UnicodeData Last range")
            pending = None
        elif pending is not None:
            raise ValueError("UnicodeData First range has no matching Last")
        previous, count = cp, count + 1
        yield fields
    if pending is not None or count == 0:
        raise ValueError("UnicodeData is empty or has an unterminated First range")


def add_name_aliases(records: dict, source_lines: list[str]) -> None:
    """Only NameAliases supplies authoritative alias types; names stay stable."""
    kinds = {"correction", "control", "alternate", "figment", "abbreviation"}
    for line in source_lines:
        line = line.split("#")[0].strip()
        if not line:
            continue
        code, alias, kind = (part.strip() for part in line.split(";"))
        if kind not in kinds:
            raise ValueError(f"Unsupported formal name alias kind: {kind}")
        if (not alias or not re.fullmatch(r"[0-9A-F]{4,6}", code)
                or int(code, 16) > 0x10FFFF or 0xD800 <= int(code, 16) <= 0xDFFF):
            raise ValueError("Invalid formal name alias")
        record = records.get(int(code, 16))
        if record is not None:
            record.setdefault("aliases", []).append({"name": alias, "kind": kind})
            # Controls have no Name property, only a pseudo-name. Keep the
            # existing useful control label without changing assigned names.
            if record["name"] == "<control>" and kind == "control":
                record["name"] = alias


def add_names_list(records: dict, source_lines: list[str]) -> None:
    """Read editorial prose with its documented character/subhead scope.

    NamesList is never used for normative names, block ranges, properties or
    formal alias types. In particular, @+ notices after a character apply only
    to it; notices after a subhead apply to that informative group.
    https://www.unicode.org/Public/UCD/latest/ucd/NamesList.html
    """
    current = None
    in_character = False
    in_block = False
    section = None
    block_notes, section_notes = [], []
    for line in source_lines:
        match = re.match(r"^([0-9A-F]{4,6})\t", line)
        if match:
            current = records.get(int(match[1], 16))
            in_character = True
            if current is not None:
                current["section"] = section
                current["sectionNotes"] = list(dict.fromkeys(block_notes + section_notes))
            continue
        if re.match(r"^@@\t[0-9A-F]{4,6}\t", line):
            current, in_character, in_block, section = None, False, True, None
            block_notes, section_notes = [], []
        elif line.startswith("@\t"):
            current, in_character = None, False
            section = line[1:].strip() or None
            section_notes = []
        elif line.startswith("@+\t"):
            note = line[2:].strip().removeprefix("* ")
            if note and in_block:
                if in_character:
                    if current is not None:
                        current.setdefault("notes", []).append(note)
                elif section is not None:
                    section_notes.append(note)
                else:
                    block_notes.append(note)
        elif line.startswith("@"):
            current, in_character = None, False
            if line.startswith(("@~", "@@~", "@@@")):
                section, section_notes = None, []
        elif current is not None and line.startswith("\t"):
            content = line.strip()
            aliases = current.setdefault("aliases", [])
            if content.startswith(("= ", "% ")):
                name = content[2:]
                formal = {alias["name"].casefold() for alias in aliases if alias["kind"] != "informal"}
                # Some chart aliases combine already-listed formal abbreviations.
                if name.casefold() not in formal and not all(part.strip().casefold() in formal for part in name.split(",")):
                    aliases.append({"name": name, "kind": "namesListFormal" if content[0] == "%" else "informal"})
            elif content.startswith("x "):
                reference = re.fullmatch(r"x \((.+) - ([0-9A-F]{4,6})\)", content)
                simple = re.fullmatch(r"x ([0-9A-F]{4,6})(?: (.+))?", content)
                if reference or simple:
                    cp = int(reference[2] if reference else simple[1], 16)
                    hint = reference[1] if reference else simple[2] or ""
                    if cp <= 0x10FFFF and not 0xD800 <= cp <= 0xDFFF:
                        name = records.get(cp, {}).get("name") or hint.upper() or f"U+{cp:04X}"
                        current.setdefault("references", []).append({"codePoint": cp, "name": name})
                else:
                    raise ValueError(f"Unsupported NamesList cross reference: {content}")
            elif content.startswith("* "):
                current.setdefault("notes", []).append(content[2:].replace("\\", ""))
            elif content.startswith("~ "):
                current.setdefault("notes", []).append("Variation: " + content[2:])
            elif content and not content.startswith((": ", "# ", ";")):
                current.setdefault("notes", []).append(content.replace("\\", ""))


def detail_payload(record: dict) -> dict:
    """Compact, lazily decoded per-character metadata in the mapped string pool."""
    fields = {"aliases": list({(item["name"], item["kind"]): item for item in record["aliases"]}.values()),
              "annotations": list(dict.fromkeys(record["notes"])),
              "section": record.get("section"), "sectionAnnotations": record.get("sectionNotes", []),
              "references": list({item["codePoint"]: item for item in record.get("references", [])}.values()),
              "unicode1Name": record.get("unicode1Name"), "numericValue": record.get("numericValue"),
              "numericType": record.get("numericType"),
              **{key: record.get(key) for key in ("simpleUppercase", "simpleLowercase", "simpleTitlecase")}}
    return {key: value for key, value in fields.items() if value is not None and value != [] and value != ""}


def atomic_write(path: Path, content: bytes) -> None:
    """Replace one completed artifact; a failed download never reaches this step."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix="." + path.name, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def replace_artifacts(output: Path, artifacts: dict[str, bytes]) -> None:
    """Stage complete editions and backups before replacement; undo interrupted commits."""
    output.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".unicode-artifacts-", dir=output.parent))
    retain_recovery = False
    try:
        backups = {}
        for filename, content in artifacts.items():
            if Path(filename).name != filename:
                raise ValueError("Artifact filename escapes the resource directory")
            atomic_write(stage / "new" / filename, content)
            target = output / filename
            backup = stage / "old" / filename
            if target.exists():
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, backup)
                backups[filename] = backup
            else:
                backups[filename] = None
        replaced = []
        try:
            for filename in artifacts:
                os.replace(stage / "new" / filename, output / filename)
                replaced.append(filename)
        except BaseException as commit_error:
            # Also restore on KeyboardInterrupt: never knowingly leave editions
            # mixed after a cancelled monthly update or a failed disk operation.
            unrecovered = []
            for filename in reversed(replaced):
                backup = backups[filename]
                try:
                    if backup is None:
                        (output / filename).unlink()
                    else:
                        os.replace(backup, output / filename)
                except BaseException:
                    unrecovered.append(filename)
            if unrecovered:
                # Do not let automatic temporary-directory cleanup destroy the
                # old bytes still needed for manual recovery. Try every restore
                # first, even if an earlier one encountered a second I/O error.
                retain_recovery = True
                recovery = {"unrecoveredTargets": unrecovered,
                            "originallyAbsent": [name for name in unrecovered if backups[name] is None]}
                try:
                    atomic_write(stage / "RECOVERY.json", (json.dumps(recovery, indent=2) + "\n").encode())
                except BaseException:
                    pass  # The original backups are more important than this diagnostic.
                raise RuntimeError(f"Artifact rollback incomplete; recovery files retained at {stage}") from commit_error
            raise
    finally:
        if not retain_recovery:
            shutil.rmtree(stage)


def generate_catalog(source: str, cache: Path | None, refresh: bool, *, slot: str | None = None,
                     resolved_source: tuple[str, dict] | None = None) -> dict[str, bytes]:
    args = argparse.Namespace(source=source, cache=cache, refresh=refresh)
    slot = slot or ("draft" if source == "draft" else "latest")
    if slot not in {"latest", "previous", "older", "draft"} or (slot == "draft") != (source == "draft"):
        raise ValueError("Invalid Unicode edition output slot")
    base, provenance = resolved_source or resolve_source(args.source)
    args.cache = args.cache or ROOT / ".unicode-cache" / args.source
    args.cache.mkdir(parents=True, exist_ok=True)
    cache_source = args.cache / "source-url.txt"
    same_source = cache_source.exists() and cache_source.read_text() == base
    timestamp_file = args.cache / "refreshed-at.txt"
    if args.refresh or not same_source or not timestamp_file.exists():
        timestamp_file.write_text(datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"))
    sources = {}
    emoji_base = emoji_source_base(base, provenance)
    for filename in FILES + ["emoji/emoji-test.txt"]:
        path = args.cache / Path(filename).name
        url = emoji_base + "emoji-test.txt" if filename == "emoji/emoji-test.txt" else base + filename
        if args.refresh or not same_source or not path.exists():
            content = fetch(url)
            if content.lstrip().startswith(b"<"):
                raise ValueError(f"Expected Unicode text data, received HTML: {url}")
            atomic_write(path, content)
        source_text = path.read_text("utf-8")
        source_date = re.search(r"(?:# Date:|Generation Date:)\s*([^\n]+)", source_text)
        sources[filename] = {"url": url,
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
    if not development and (is_draft or "final data files" not in readme.lower()):
        raise ValueError("Pinned Unicode release is not an official final release")
    if args.source not in {"draft", "latest"} and version != args.source:
        raise ValueError(f"Source version mismatch: requested {args.source}, received {version}")
    version_label = version + (" draft" if is_draft else "")
    for filename in ["Blocks.txt", "NameAliases.txt", "extracted/DerivedName.txt", "DerivedCoreProperties.txt", "DerivedAge.txt", "Scripts.txt"]:
        first = lines(filename)[0]
        if version not in first and not development:
            raise ValueError(f"Mixed Unicode versions: {filename} does not declare {version}")

    def property_ranges(filename: str) -> list[dict]:
        result = []
        for line in lines(filename):
            line = line.split("#")[0].strip()
            if line:
                extent, value = (part.strip() for part in line.split(";", 1))
                start, end = span(extent)
                result.append({"start": start, "end": end, "value": value})
        result.sort(key=lambda item: item["start"])
        if any(left["end"] >= right["start"] for left, right in zip(result, result[1:])):
            raise ValueError(f"Overlapping property ranges: {filename}")
        return result

    ages = property_ranges("DerivedAge.txt")
    scripts = property_ranges("Scripts.txt")
    if any(not item["value"] or not 0 < version_key(item["value"]) <= version_key(version) for item in ages):
        raise ValueError("Invalid official Unicode Age interval")
    if any(not item["value"] for item in scripts):
        raise ValueError("Empty official Script value")

    blocks = []
    for line in lines("Blocks.txt"):
        line = line.split("#")[0].strip()
        if line:
            extent, name = line.split(";", 1)
            start, end = span(extent)
            blocks.append({"name": name.strip(), "start": start, "end": end})
    if (not blocks or any(not item["name"] for item in blocks)
            or len({item["name"] for item in blocks}) != len(blocks)
            or any(left["end"] >= right["start"] for left, right in zip(blocks, blocks[1:]))):
        raise ValueError("Unicode blocks must be nonempty, unique and ordered without overlap")

    def block_name(cp: int) -> str:
        for block in blocks:
            if block["start"] <= cp <= block["end"]:
                return block["name"]
        return "No Block"

    records = {}
    decompositions = {}
    ranges = []
    pending = None
    patterns = []
    for line in lines("extracted/DerivedName.txt"):
        line = line.split("#")[0].strip()
        if line:
            extent, name = (part.strip() for part in line.split(";", 1))
            if "*" in name:
                patterns.append((*span(extent), name.removesuffix("*")))
    for fields in unicode_data_rows(lines("UnicodeData.txt")):
        cp, name, category = int(fields[0], 16), fields[1], fields[2]
        combining_class, bidi_class = int(fields[3]), fields[4]
        if name.endswith(", First>"):
            pending = (cp, name, category, combining_class, bidi_class)
        elif name.endswith(", Last>"):
            if pending is None or pending[2] != category:
                raise ValueError("Unmatched UnicodeData range")
            if category != "Cs" and (pending[3:] != (0, "L") or (combining_class, bidi_class) != (0, "L")):
                raise ValueError(f"Unsupported algorithmic range properties: {pending[1]}")
            if category == "Co":
                ranges.append((pending[0], cp, "PRIVATE USE-", category, 2))
            elif pending[1].startswith("<Hangul"):
                if not 0xAC00 <= pending[0] <= cp <= 0xD7A3:
                    raise ValueError("Hangul range is outside the normative syllable domain")
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
            records[cp] = {"name": name, "category": category, "aliases": [], "notes": [],
                           "combiningClass": combining_class, "bidiClass": bidi_class,
                           "decomposition": fields[5], "unicode1Name": fields[10],
                           "numericValue": fields[8],
                           "numericType": "Decimal" if fields[6] else "Digit" if fields[7] else "Numeric" if fields[8] else None,
                           **{key: int(value, 16) if value else None for key, value in zip(
                               ("simpleUppercase", "simpleLowercase", "simpleTitlecase"), fields[12:15])}}
            if fields[5]:
                # Name compression must not discard normative properties on
                # algorithmically named compatibility ideographs.
                decompositions[cp] = fields[5]

    # Preserve original explicit records so annotated algorithmic characters can
    # be exceptions to a compressed range without losing their character notes.
    source_records = dict(records)
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
    if any(left[1] >= right[0] for left, right in zip(ranges, ranges[1:])):
        raise ValueError("Overlapping algorithmic naming ranges")

    # Assigned spans and Age intervals keep global ordering compact, including
    # large algorithmic/private-use ranges, without serializing 300K objects.
    assigned = sorted([(cp, cp) for cp in records] + [(start, end) for start, end, *_ in ranges])
    merged = []
    for start, end in assigned:
        if merged and start <= merged[-1][1] + 1:
            merged[-1] = (merged[-1][0], max(end, merged[-1][1]))
        else:
            merged.append((start, end))
    assigned_spans = []
    age_index = 0
    for start, end in merged:
        cp = start
        while cp <= end:
            while age_index < len(ages) and ages[age_index]["end"] < cp:
                age_index += 1
            age = ages[age_index] if age_index < len(ages) else None
            covered = age is not None and age["start"] <= cp
            last = min(end, age["end"] if covered else (age["start"] - 1 if age else end))
            if not covered and not development:
                raise ValueError(f"Assigned final-release scalar has no official Age: U+{cp:04X}")
            assigned_spans.append({"start": cp, "end": last,
                                   "sortKey": version_key(age["value"] if covered else version),
                                   "draftAddition": not covered})
            cp = last + 1

    age_starts = [item["start"] for item in ages]
    def official_age(cp: int) -> str | None:
        index = bisect.bisect_right(age_starts, cp) - 1
        return ages[index]["value"] if index >= 0 and ages[index]["end"] >= cp else None

    add_name_aliases(source_records, lines("NameAliases.txt"))
    add_names_list(source_records, lines("NamesList.txt"))
    restored = sorted(cp for cp, record in source_records.items() if cp not in records and detail_payload(record))
    for cp in restored:
        records[cp] = source_records[cp]
    if restored:
        split_ranges = []
        for start, end, prefix, category, kind in ranges:
            cursor = start
            for cp in restored[bisect.bisect_left(restored, start):bisect.bisect_right(restored, end)]:
                if cursor < cp:
                    split_ranges.append((cursor, cp - 1, prefix, category, kind))
                cursor = cp + 1
            if cursor <= end:
                split_ranges.append((cursor, end, prefix, category, kind))
        ranges = split_ranges

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
        payload = detail_payload(record)
        context = {key: payload.pop(key) for key in ("section", "sectionAnnotations") if key in payload}
        detail = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) if payload else ""
        context_detail = json.dumps(context, ensure_ascii=False, separators=(",", ":")) if context else ""
        search_parts = [record["name"], block_name(cp), payload.get("unicode1Name", "")]
        search_parts += [item["name"] for item in payload.get("aliases", [])]
        search_parts += payload.get("annotations", [])
        name_offset, name_length = string(record["name"])
        detail_offset, detail_length = string(detail)
        search_offset, search_length = string(fold(" ".join(search_parts)))
        context_offset, context_length = string(context_detail)
        context_search_offset, context_search_length = string(fold(" ".join(
            [context.get("section", "")] + context.get("sectionAnnotations", []))))
        flags = int(cp in invisible or record["category"] in {"Cc", "Cf", "Zs", "Zl", "Zp"})
        if name_length > 65535 or detail_length > 65535:
            raise ValueError("Character name/detail exceeds the catalog field size")
        record_data.extend(struct.pack("<IIHHIIIBBBB", cp, name_offset, name_length,
                                       detail_length, detail_offset, search_offset,
                                       search_length, CATEGORIES.index(record["category"]), flags,
                                       record["combiningClass"], BIDI_CLASSES.index(record["bidiClass"])))
        # Shared subhead/notice blobs and their folded search text are interned
        # once, rather than repeated in thousands of per-character strings.
        record_data.extend(struct.pack("<IIII", context_offset, context_length,
                                       context_search_offset, context_search_length))

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
                         version_offset, version_length, assigned_count, 3)
    properties = {"unicodeVersion": version_label, "ages": ages, "scripts": scripts,
                  "assignedSpans": assigned_spans,
                  "decompositions": [{"codePoint": cp, "value": value}
                                     for cp, value in sorted(decompositions.items())]}

    emoji_lines = lines("emoji/emoji-test.txt")
    emoji_version_match = re.search(r"^# Version:\s*([0-9]+\.[0-9]+)", "\n".join(emoji_lines), re.MULTILINE)
    if emoji_version_match is None:
        raise ValueError("Could not determine official Emoji source version")
    emoji_version = emoji_version_match[1]
    if emoji_version != ".".join(version.split(".")[:2]):
        raise ValueError(f"Mixed Unicode/Emoji editions: Unicode {version}, Emoji {emoji_version}")
    emoji_entries = []
    group = subgroup = None
    for line in emoji_lines:
        if line.startswith("# group: "):
            group = line.removeprefix("# group: ")
        elif line.startswith("# subgroup: "):
            subgroup = line.removeprefix("# subgroup: ")
        elif re.search(r";\s*fully-qualified\b", line):
            match = re.fullmatch(r"([0-9A-F ]+)\s*;\s*fully-qualified\s*#\s*\S+\s+E([0-9]+\.[0-9]+)\s+(.+)", line)
            if match is None or group is None or subgroup is None:
                raise ValueError(f"Invalid fully-qualified emoji record: {line}")
            points = [int(part, 16) for part in match[1].split()]
            if not points or any(cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF for cp in points):
                raise ValueError("Emoji sequence contains an invalid Unicode scalar")
            if any(cp not in records and not any(start <= cp <= end for start, end, *_ in ranges) for cp in points):
                raise ValueError("Emoji sequence contains an unassigned Unicode scalar")
            if (not match[3].strip() or not group.strip() or not subgroup.strip()
                    or not 0 < version_key(match[2]) <= version_key(emoji_version)):
                raise ValueError("Invalid emoji name/group/introduction version")
            component_ages = [official_age(cp) for cp in points]
            unicode_age = (max(component_ages, key=version_key) if all(component_ages)
                           else "Pending draft age")
            if not all(component_ages) and not development:
                raise ValueError("Final emoji sequence component is missing an official Unicode Age")
            emoji_entries.append({"id": "-".join(f"{cp:04X}" for cp in points), "codePoints": points,
                                  "name": match[3], "emojiVersion": match[2], "unicodeVersion": unicode_age,
                                  "group": group, "subgroup": subgroup})
    if not emoji_entries or len({entry["id"] for entry in emoji_entries}) != len(emoji_entries):
        raise ValueError("Emoji catalog is empty or has duplicate fully-qualified sequences")
    emoji = {"version": emoji_version + (" draft" if is_draft else ""), "edition": slot,
             "unicodeVersion": version_label, "entries": emoji_entries}
    source_dates = [value["sourceDate"] for value in sources.values() if "sourceDate" in value]
    manifest = {"unicodeVersion": version, "versionLabel": version_label, "isDraft": is_draft, "edition": slot,
                "source": args.source, "sourceLastModified": max(source_dates) if source_dates else None,
                "refreshedAt": timestamp_file.read_text(),
                **provenance,
                "formatVersion": 3, "blocks": len(blocks),
                "explicitRecords": len(records), "algorithmicRanges": len(ranges),
                "assignedScalarsIncludingPrivateUse": assigned_count,
                "catalogBytes": len(header + record_data + range_data + pool),
                "fullyQualifiedEmoji": len(emoji_entries), "emojiVersion": emoji["version"],
                "assignedScalarsWithPendingDraftAge": sum(item["end"] - item["start"] + 1 for item in assigned_spans if item["draftAddition"]),
                "sources": sources,
                "annotatedCharacters": sum(bool(detail_payload(record)) for record in records.values()),
                "formalAliasRecords": sum(alias["kind"] in {"correction", "control", "alternate", "figment", "abbreviation"} for record in records.values() for alias in detail_payload(record).get("aliases", [])),
                "notes": "Assigned names remain unchanged. Formal name alias types come only from NameAliases.txt. NamesList headings, aliases, notices, variations and cross references are informative prose, not normative properties or corrections. Heading/notice context is searchable, including Suzhou numerals whose immutable names contain HANGZHOU. Numeric values, historical Unicode 1 names and simple case mappings come from UnicodeData.txt. Age and Script retain official generated property values; new draft assignments missing upstream Age have no inferred Age label and use the draft edition only for ordering. Emoji introduction version is distinct from the maximum official Unicode Age of its component scalars. Algorithmic names use DerivedName and the normative Hangul naming algorithm. Surrogates are excluded."}
    suffix = "" if slot == "draft" else "-" + slot
    def json_bytes(value: object) -> bytes:
        return (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    artifacts = {f"UnicodeCatalog{suffix}.ucd": bytes(header + record_data + range_data + pool),
                 f"Blocks{suffix}.json": json_bytes(blocks),
                 f"UnicodeProperties{suffix}.json": json_bytes(properties),
                 f"UnicodeSources{suffix}.json": (json.dumps(manifest, indent=2) + "\n").encode("utf-8"),
                 f"EmojiCatalog-{slot}.json": json_bytes(emoji)}
    print(json.dumps({k: v for k, v in manifest.items() if k not in {"sources", "notes"}}, indent=2))
    return artifacts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="all", help="all (default: latest final, previous two finals, draft), latest, previous, older, draft, or a pinned release such as 18.0.0")
    parser.add_argument("--cache-dir", "--cache", dest="cache", type=Path)
    parser.add_argument("--refresh", action="store_true", help="Fetch every source again; required for live CI builds")
    args = parser.parse_args()
    if args.source not in {"all", "latest", "previous", "older", "draft"} and not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.source):
        parser.error("--source must be all, latest, previous, older, draft or a Unicode version")
    artifacts = {}
    for source, slot, resolved in generation_plan(args.source):
        cache = (args.cache or ROOT / ".unicode-cache") / slot if args.source == "all" else args.cache
        artifacts.update(generate_catalog(source, cache, args.refresh, slot=slot, resolved_source=resolved))
    output = ROOT / "Shared" / "Resources"
    license_path = output / "Unicode-LICENSE.txt"
    if not license_path.exists():
        artifacts["Unicode-LICENSE.txt"] = fetch("https://www.unicode.org/license.txt")
    # Fetch and validate every complete edition before changing any resource.
    replace_artifacts(output, artifacts)


if __name__ == "__main__":
    main()
