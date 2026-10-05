#!/usr/bin/env python3
"""Validate the offline font pack without third-party build dependencies."""
import hashlib
import json
from pathlib import Path


def validate(directory: Path) -> None:
    manifest = json.loads((directory / "manifest.json").read_text())
    assert manifest["schemaVersion"] == 1
    fonts = manifest["fonts"]
    assert [font["postScriptName"] for font in fonts] == [
        "NotoSansSymbols2-Regular", "Unifont", "UnifontUpper"
    ], "Unexpected font priority"
    all_points = set()
    byte_count = 0
    for font in fonts:
        filename = font["filename"]
        assert Path(filename).name == filename, "Font path must stay inside Fonts"
        data = (directory / filename).read_bytes()
        assert data[:4] == b"OTTO", f"Invalid OpenType/CFF header: {filename}"
        assert len(data) == font["bytes"], f"Changed size: {filename}"
        assert hashlib.sha256(data).hexdigest() == font["sha256"], f"Changed font: {filename}"
        byte_count += len(data)
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


if __name__ == "__main__":
    validate(Path(__file__).resolve().parent.parent / "Fonts")
