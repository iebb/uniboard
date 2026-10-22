#!/usr/bin/env python3
"""Validate the offline font pack without third-party build dependencies."""
import hashlib
import json
from pathlib import Path
import re


def validate_downloads(directory: Path) -> None:
    root = directory.parent
    catalog = json.loads((directory / "DownloadableFonts.json").read_text())
    inputs = json.loads((root / "docs/font-audit/font-subset-inputs.json").read_text())
    baseline = root / "docs/font-audit/ios27-stock.json"
    assert hashlib.sha256(baseline.read_bytes()).hexdigest() == inputs["baselineSha256"]
    stock = json.loads(baseline.read_text())
    targets = {cp for block in stock["blocks"] for cp in block["stockMissing"]}
    protected_emoji = {cp for block in stock["blocks"] for cp in block["emojiMissing"]}
    assert catalog["schemaVersion"] == inputs["schemaVersion"] == 1
    assert catalog["unicodeVersion"] == inputs["unicodeVersion"] == "18.0.0"
    assert [pack["id"] for pack in catalog["packs"]] == ["preview-basics", "historic-symbols", "han-supplementary", "han-latest", "seal", "emoji", "ucsur"]
    validate_ucsur(catalog["packs"][-1], inputs, directory)
    # Preview basics are the unchanged manifest fonts, checked in validate();
    # the UCSUR pack draws Private Use characters, outside the measured audit.
    fonts = [font for pack in catalog["packs"][1:-1] for font in pack["fonts"]]
    assert len(fonts) == len(inputs["fonts"]) == 68
    by_name = {entry["filename"]: entry for entry in inputs["fonts"]}
    assert len(by_name) == len(fonts)
    assert len({font["asset"]["postScriptName"] for font in fonts}) == len(fonts)
    total, points = 0, set()
    for font in fonts:
        asset = font["asset"]
        filename = asset["filename"]
        source = by_name[filename]
        runtime_emoji = source.get("coverage") == "runtime-emoji"
        if runtime_emoji:
            # The sbix Noto rebuild is a complete runtime fallback: the app
            # renders with stock fonts first and uses it only for emoji that tofu.
            assert source.get("distribution") == "verbatim" and source["packId"] == "emoji"
            assert filename == "noto.ttf" and asset["licenseFilename"] == "NotoEmoji-OFL.txt"
            assert asset["sha256"] == source["sourceFontSha256"] == source["sourceDownloadSha256"]
            assert re.fullmatch(r"https://github\.com/iebb/emojifonts/releases/download/\d{4}\.\d{2}(\.\d{2})?/", source["downloadBase"])
            assert asset["sourceURL"] == source["downloadBase"] + filename
        elif source.get("distribution") == "verbatim":
            assert filename == "SealSans-Regular_v1.otf"
            assert asset["licenseFilename"] == "SealSans-AGPL.txt"
            assert asset["sha256"] == source["sourceFontSha256"]
            assert source["sourceArchiveURL"].startswith(inputs["completionDownloadBase"])
            assert re.fullmatch(r"[a-f0-9]{64}", source["sourceArchiveSha256"])
        else:
            assert re.fullmatch(r"UniboardCoverage\d{3}-Regular\.(ttf|otf)", filename)
        assert re.fullmatch(r"[a-f0-9]{64}", asset["sha256"])
        assert font["downloadURL"] == source.get("downloadBase", inputs["downloadBase"]) + filename
        assert type(font["bytes"]) is int and 0 < font["bytes"] <= 40 * 1024 * 1024
        total += font["bytes"]
        assert asset["sourceURL"] == source["sourceURL"]
        assert asset["postScriptName"] == source["postScriptName"]
        assert asset["ranges"] == source["ranges"]
        for key in ["sourceDownloadSha256", "sourceFontSha256"]:
            assert re.fullmatch(r"[a-f0-9]{64}", source[key])
        assert Path(asset["licenseFilename"]).name == asset["licenseFilename"]
        notice = (directory / asset["licenseFilename"]).read_text()
        assert "SIL OPEN FONT LICENSE" in notice or "CC0 1.0 Universal" in notice or (
            source.get("distribution") == "verbatim" and "GNU AFFERO GENERAL PUBLIC LICENSE" in notice)
        previous = -1
        for lo, hi in asset["ranges"]:
            assert type(lo) is int and type(hi) is int and 0 <= lo <= hi <= 0x10FFFF and lo > previous
            covered = set(range(lo, hi + 1))
            previous = hi
            if runtime_emoji:
                continue
            assert covered <= targets
            if source["packId"] == "emoji":
                assert covered <= protected_emoji, "Only audited missing emoji may use the color preview pack"
            else:
                assert covered.isdisjoint(protected_emoji)
            assert covered.isdisjoint(points), "Each download must contribute unique measured preview coverage"
            points.update(covered)
        assert not (directory / filename).exists(), "Download assets must not enlarge the initial app/keyboard bundles"
    total += sum(font["bytes"] for pack in (catalog["packs"][0], catalog["packs"][-1]) for font in pack["fonts"])
    assert total <= 96 * 1024 * 1024
    print(f"Validated {len(catalog['packs'])} optional packs: {len(fonts)} pinned fonts, {total:,} download bytes, {len(points):,} iOS-measured scalars.")


def validate_ucsur(pack, inputs, directory: Path) -> None:
    """Fairfax HD, unchanged, for ConScript Unicode Registry Private Use characters."""
    [font] = pack["fonts"]
    asset = font["asset"]
    source = next(entry for entry in inputs["fonts"] if entry.get("family") == "Fairfax HD")
    assert asset["filename"] == "FairfaxHD.ttf" and asset["postScriptName"] == "FairfaxHD"
    assert asset["sha256"] == source["sourceFontSha256"] and asset["sourceURL"] == source["sourceURL"]
    assert asset["licenseFilename"] == "FairfaxHD-OFL.txt" and "SIL OPEN FONT LICENSE" in (directory / asset["licenseFilename"]).read_text()
    assert font["downloadURL"] == inputs["downloadBase"] + asset["filename"]
    assert not (directory / asset["filename"]).exists(), "Download assets must not enlarge the bundles"
    previous = -1
    for lo, hi in asset["ranges"]:
        assert previous < lo <= hi and (0xE000 <= lo and hi <= 0xF8FF or 0xF0000 <= lo and hi <= 0x10FFFD), "UCSUR coverage is Private Use only"
        previous = hi


def validate(directory: Path) -> None:
    manifest = json.loads((directory / "manifest.json").read_text())
    assert manifest["schemaVersion"] == 1
    fonts = manifest["fonts"]
    assert [font["postScriptName"] for font in fonts] == [
        "NotoSansSymbols2-Regular", "UniboardCombiningPreviews-Regular", "Unifont", "UnifontUpper"
    ], "Unexpected font priority"
    # These preview fonts download on demand as the first pack, unchanged.
    basics = json.loads((directory / "DownloadableFonts.json").read_text())["packs"][0]
    assert basics["id"] == "preview-basics" and len(basics["fonts"]) == len(fonts)
    all_points = set()
    byte_count = 0
    for font, download in zip(fonts, basics["fonts"]):
        filename = font["filename"]
        assert Path(filename).name == filename, "Font path must stay inside Fonts"
        assert not (directory / filename).exists(), "Preview fonts download on demand"
        asset = download["asset"]
        for key in ["filename", "displayName", "postScriptName", "sha256", "sourceURL", "licenseFilename", "ranges"]:
            assert asset[key] == font[key], f"Download differs from manifest: {filename} {key}"
        assert download["bytes"] == font["bytes"], f"Changed size: {filename}"
        assert download["downloadURL"] == "https://github.com/iebb/uniboard/releases/download/fonts-1.1-20261022/" + filename
        byte_count += font["bytes"]
        license_name = font["licenseFilename"]
        assert Path(license_name).name == license_name
        license_text = (directory / license_name).read_text()
        assert "Copyright" in license_text and "SIL OPEN FONT LICENSE Version 1.1" in license_text
        assert "TERMINATION" in license_text and "DISCLAIMER" in license_text
        assert font["sourceURL"].startswith("https://")
        previous = -2
        points = set()
        ranges = font["ranges"]
        assert len(ranges) == font["rangeCount"]
        for pair in ranges:
            assert len(pair) == 2 and all(type(point) is int for point in pair)
            start, end = pair
            assert 0 <= start <= end <= 0x10FFFF and start > previous + 1
            assert end < 0xD800 or start > 0xDFFF, "Surrogates are not Unicode scalars"
            points.update(range(start, end + 1))
            previous = end
        assert len(points) == font["usefulScalarCount"]
        all_points.update(points)
    assert len(all_points) == manifest["usefulUnionScalarCount"]
    assert byte_count < 15 * 1024 * 1024, "Review keyboard footprint before enlarging the pack"
    # Regressions that otherwise turn reserved/emoji/blank slots into fake coverage.
    excluded = {0, 0x20, 0x034F, 0x0378, 0x200D, 0x2800, 0xE000, 0xFE0F, 0x1FAEB,
                0x1246F, *range(0x12475, 0x12480), 0x1342F}
    assert all_points.isdisjoint(excluded), "Placeholder, invisible or emoji glyph advertised"
    included = {0x0558, 0x058B, 0x058C, 0x05C8, 0x05C9, 0x1AD3, 0x11DF0, 0x1DB00, 0x1D250}
    assert included <= all_points, "Verified real glyph fixture lost"
    for notice in ["NotoSymbols2-AUTHORS.txt", "NotoSymbols2-CONTRIBUTORS.txt"]:
        assert (directory / notice).stat().st_size > 0
    print(f"Validated {len(fonts)} offline fonts, {byte_count:,} bytes, {len(all_points):,} verified scalar glyphs.")
    validate_downloads(directory)


if __name__ == "__main__":
    validate(Path(__file__).resolve().parent.parent / "Fonts")
