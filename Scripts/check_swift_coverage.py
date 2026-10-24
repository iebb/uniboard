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
    "UnicodeSearchIndex.swift": 1.0,
    "UnicodeSearchIndexStore.swift": 1.0,
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
    "KeyboardQueryHoldPolicy.swift": 1.0,
    "KeyboardPreviewCursorPolicy.swift": 1.0,
    "KeyboardTypingPolicy.swift": 1.0,
    "KeyboardTypingLayoutPolicy.swift": 1.0,
    "KeyboardEnglishInputPolicy.swift": 1.0,
    "LocalPreferencePolicy.swift": 1.0,
    "CatalogWorker.swift": 1.0,
    "KeyboardAlphabet.swift": 1.0,
    "SymbolPageLayout.swift": 1.0,
    "UCSUR.swift": 1.0,
    "MainKeyboardArrangement.swift": 1.0,
    "TOMLDocument.swift": 1.0,
    "FontRules.swift": 1.0,
    "SharedConfigurationLocation.swift": 1.0,
    "FontRuleStore.swift": 1.0,
    "FontRuleEditing.swift": 1.0,
    "ImageColorSettings.swift": 1.0,
    "AutoCapitalizationSetting.swift": 1.0,
    "TextInspection.swift": 1.0,
    "ConfigurationModel.swift": 1.0,
    "ConfigurationCodec.swift": 1.0,
    "ConfigurationDiff.swift": 1.0,
    "FontPickerCatalog.swift": 1.0,
    "StyleGrid.swift": 1.0,
}


def uncovered_lines(segments):
    """Lines llvm-cov counts as executable but never run: a diagnostic only.

    Mirrors llvm's LineCoverageStats over the export's segments
    ([line, column, count, hasCount, isRegionEntry, isGapRegion]; older
    exports omit isGapRegion, which then counts as false)."""
    if not isinstance(segments, list):
        return []
    segments = [list(s[:5]) + [bool(s[5]) if len(s) > 5 else False]
                for s in segments if isinstance(s, list) and len(s) >= 5]
    if not segments:
        return []
    lines, wrapped, index = [], None, 0
    for line in range(segments[0][0], segments[-1][0] + 1):
        current = []
        while index < len(segments) and segments[index][0] == line:
            current.append(segments[index])
            index += 1
        starts = [s for s in current if s[3] and s[4] and not s[5]]
        skipped = bool(current) and not current[0][3] and current[0][4]
        mapped = not skipped and ((wrapped is not None and wrapped[3]) or bool(starts))
        if mapped:
            count = wrapped[2] if wrapped is not None else 0
            if starts:
                count = max([count] + [s[2] for s in starts])
            if count == 0:
                lines.append(line)
        if current:
            wrapped = current[-1]
    return lines[:50]


def function_uncovered_lines(regions):
    """Never-run lines of one function from its export regions
    ([lineStart, columnStart, lineEnd, columnEnd, count, fileID,
    expandedFileID, kind]). llvm-cov sums line coverage per function, so a
    closure or `??` fallback that never runs leaves its line uncovered even
    when the code around it ran."""
    if not isinstance(regions, list):
        return set()
    usable = [r for r in regions if isinstance(r, list) and len(r) >= 8 and r[5] == 0 and r[7] in (0, 3)
              and all(type(v) is int for v in r[:5])]
    lines = set()
    for line in {r[0] for r in usable} | {n for r in usable for n in range(r[0], r[2] + 1)}:
        starts = [r[4] for r in usable if r[0] == line and r[7] == 0]
        active = [r for r in usable if r[0] < line and (r[2] > line or (r[2] == line and r[3] > 1))]
        wrapped = max(active, key=lambda r: (r[0], r[1]), default=None)
        if wrapped is None and not starts:
            continue
        if max(starts + ([wrapped[4]] if wrapped else [])) == 0:
            lines.add(line)
    return lines


def evaluate(report, root=ROOT):
    if not isinstance(report, dict) or not isinstance(report.get("data"), list):
        raise ValueError("Expected llvm-cov JSON data")
    records = {}
    uncovered = {}
    by_function = {}
    for datum in report["data"]:
        for function in datum.get("functions") or [] if isinstance(datum, dict) else []:
            if isinstance(function, dict) and isinstance(function.get("filenames"), list) and function["filenames"]:
                name = pathlib.Path(str(function["filenames"][0])).name
                by_function.setdefault(name, set()).update(function_uncovered_lines(function.get("regions")))
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
            uncovered[path.name] = uncovered_lines(file.get("segments"))
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
        lines = sorted(by_function.get(name, ()))[:50] or uncovered[name]
        if covered < count and lines:
            output.append(f"  never run: lines {', '.join(map(str, lines))}")
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
