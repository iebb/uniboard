#!/usr/bin/env python3
"""Enforce coverage of shipped core logic, excluding test code from the totals."""
import json
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MINIMUMS = {
    "CompanionAppRoute.swift": 1.0,
    "UnicodeCatalog.swift": 1.0,
    "UnicodeFontAssets.swift": 1.0,
    "UnicodeEditionSettings.swift": 1.0,
    "KeyboardKeySettings.swift": 1.0,
    "EmojiCatalog.swift": 1.0,
    "CharacterStore.swift": 1.0,
    "SymbolBoardStore.swift": 1.0,
    "FavoriteSync.swift": 1.0,
    "KeyboardVariantPolicy.swift": 1.0,
    "KeyboardFooterLayoutPolicy.swift": 1.0,
    "KeyboardInteractionPolicy.swift": 1.0,
    "KeyboardTypingPolicy.swift": 1.0,
    "KeyboardTypingLayoutPolicy.swift": 1.0,
    "KeyboardEnglishInputPolicy.swift": 1.0,
    "LocalPreferencePolicy.swift": 1.0,
    "CatalogWorker.swift": 1.0,
    "KeyboardAlphabet.swift": 1.0,
    "SymbolPageLayout.swift": 1.0,
    "UCSUR.swift": 1.0,
    "MainKeyboardArrangement.swift": 1.0,
}


def evaluate(report, root=ROOT):
    if not isinstance(report, dict) or not isinstance(report.get("data"), list):
        raise ValueError("Expected llvm-cov JSON data")
    records = {}
    for datum in report["data"]:
        if not isinstance(datum, dict) or not isinstance(datum.get("files"), list):
            raise ValueError("Expected coverage file records")
        for file in datum["files"]:
            if not isinstance(file, dict) or not isinstance(file.get("filename"), str):
                raise ValueError("Invalid coverage file identity")
            path = pathlib.Path(file["filename"]).resolve()
            if path.parent != (root / "Shared").resolve() or path.name not in MINIMUMS:
                continue
            if path.name in records:
                raise ValueError(f"Duplicate coverage record: {path.name}")
            summary = file.get("summary")
            if not isinstance(summary, dict) or not isinstance(summary.get("lines"), dict):
                raise ValueError(f"Missing line coverage: {path.name}")
            lines = summary["lines"]
            count, covered = lines.get("count"), lines.get("covered")
            if (type(count) is not int or type(covered) is not int
                    or count <= 0 or not 0 <= covered <= count):
                raise ValueError(f"Invalid or empty coverage: {path.name}")
            records[path.name] = (covered, count)
    missing = MINIMUMS.keys() - records.keys()
    if missing:
        raise ValueError("Missing shipped-code coverage: " + ", ".join(sorted(missing)))
    failures = []
    output = []
    for name, minimum in MINIMUMS.items():
        covered, count = records[name]
        ratio = covered / count
        if not math.isfinite(ratio) or ratio + 1e-12 < minimum:
            failures.append(name)
        output.append(f"{name}: {covered}/{count} lines ({ratio:.1%}); required {minimum:.0%}")
    return output, failures


def main(argv):
    if len(argv) != 1:
        raise ValueError("Expected one llvm-cov JSON report path")
    output, failures = evaluate(json.loads(pathlib.Path(argv[0]).read_text()))
    print("\n".join(output))
    if failures:
        raise ValueError("Coverage below the required floor: " + ", ".join(failures))


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"Core coverage check failed: {error}", file=sys.stderr)
        sys.exit(1)
