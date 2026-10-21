#!/usr/bin/env python3
"""Build the tiny OFL preview font that keeps dotted-circle clusters in one face."""
import argparse
import hashlib
import json
from pathlib import Path
import fontTools
from fontTools.fontBuilder import FontBuilder
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.feaLib.builder import addOpenTypeFeaturesFromString
from build_preview_font_downloads import source_font
ROOT = Path(__file__).resolve().parent.parent


def build(output, cache):
    spec = json.loads((ROOT / "docs/font-audit/combining-preview-inputs.json").read_text())
    if fontTools.__version__ != spec["fontToolsVersion"]:
        raise ValueError("Install the pinned Scripts/requirements-fonts.txt before reproducing assets")
    fonts = {}
    copyright = []
    for entry in spec["sources"]:
        path = ROOT / entry["path"] if entry["kind"] == "bundled" else source_font(entry, cache)
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["sourceFontSha256"]:
            raise ValueError("Pinned combining source font SHA-256 mismatch")
        f = TTFont(path)
        fonts[entry["sourceFontSha256"]] = f
        copyright.append(f["name"].getDebugName(0))
    glyphs, metrics, cmap = {}, {}, {}
    order = [".notdef", "space", "dottedcircle"] + [f"u{item['point']:05X}" for item in spec["marks"]]
    for name in [".notdef", "space"]:
        glyphs[name] = TTGlyphPen(None).glyph()
        metrics[name] = (500, 0)
    def import_glyph(font, cp, name, is_dot=False):
        source = font.getGlyphSet()
        glyph = source[font.getBestCmap()[cp]]
        bounds = BoundsPen(source)
        glyph.draw(bounds)
        if bounds.bounds is None:
            raise ValueError("A combining-preview source glyph has no outline")
        scale = 1000 / font["head"].unitsPerEm
        center = (bounds.bounds[0] + bounds.bounds[2]) * scale / 2
        # A single visible specimen: center the real mark above/below the dot,
        # retaining its source vertical coordinates. No text is rewritten.
        x = (500 if is_dot else -500) - center
        recording = DecomposingRecordingPen(source)
        glyph.draw(recording)
        pen = TTGlyphPen(None)
        recording.replay(TransformPen(Cu2QuPen(pen, max_err=0.5, reverse_direction=False), (scale, 0, 0, scale, x, 0)))
        result = pen.glyph()
        result.recalcBounds({})
        glyphs[name] = result
        metrics[name] = (1000 if is_dot else 0, result.xMin)
        cmap[cp] = name
    import_glyph(fonts[spec["dotSource"]], 0x25CC, "dottedcircle", True)
    for item in spec["marks"]:
        import_glyph(fonts[item["source"]], item["point"], f"u{item['point']:05X}")
    cmap[0x20] = "space"
    fb = FontBuilder(1000, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    ascent = max(1000, max(getattr(g, "yMax", 0) for g in glyphs.values()))
    descent = min(-250, min(getattr(g, "yMin", 0) for g in glyphs.values()))
    fb.setupHorizontalHeader(ascent=ascent, descent=descent)
    fb.setupOS2(sTypoAscender=ascent, sTypoDescender=descent, usWinAscent=ascent, usWinDescent=-descent)
    license_body = (ROOT / "Fonts/NotoSymbols2-OFL.txt").read_text()
    license_body = license_body[license_body.index("-----------------------------------------------------------"):]
    notice = "\n\n".join(sorted(set(copyright))) + "\n\nModified for Uniboard: isolated mark specimens, normalized positioning and an unreserved family name.\n\n" + license_body
    fb.setupNameTable({"familyName": "Uniboard Combining Previews", "styleName": "Regular",
        "uniqueFontIdentifier": "Uniboard-Combining-Previews-1.1", "fullName": "Uniboard Combining Previews Regular",
        "psName": "UniboardCombiningPreviews-Regular", "version": "Version 1.100", "copyright": "\n\n".join(sorted(set(copyright))),
        "licenseDescription": notice, "licenseInfoURL": "https://openfontlicense.org"})
    fb.setupPost()
    addOpenTypeFeaturesFromString(fb.font, "languagesystem DFLT dflt; table GDEF { GlyphClassDef [dottedcircle], [], [" + " ".join(order[3:]) + "], []; } GDEF;")
    fb.font["head"].created = fb.font["head"].modified = 3_800_000_000
    fb.font.recalcTimestamp = False
    output.parent.mkdir(parents=True, exist_ok=True)
    fb.save(output)
    for f in fonts.values():
        f.close()
    return notice


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/combining-previews.ttf")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/font-source-cache")
    parser.add_argument("--update-manifest", action="store_true")
    args = parser.parse_args()
    notice = build(args.output, args.cache)
    data = args.output.read_bytes()
    if args.update_manifest:
        target = ROOT / "Fonts/UniboardCombiningPreviews-Regular.ttf"
        target.write_bytes(data)
        (ROOT / "Fonts/CombiningPreviews-OFL.txt").write_text(notice)
        manifest_path = ROOT / "Fonts/manifest.json"
        manifest = json.loads(manifest_path.read_text())
        spec = json.loads((ROOT / "docs/font-audit/combining-preview-inputs.json").read_text())
        points = sorted(item["point"] for item in spec["marks"])
        ranges = []
        for cp in points:
            if ranges and cp == ranges[-1][1] + 1:
                ranges[-1][1] = cp
            else:
                ranges.append([cp, cp])
        entry = {"filename": target.name, "displayName": "Noto & Unifont combining previews",
            "postScriptName": "UniboardCombiningPreviews-Regular", "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data), "sourceURL": "https://github.com/iebb/uniboard/blob/master/docs/font-audit/combining-preview-inputs.json",
            "licenseFilename": "CombiningPreviews-OFL.txt", "ranges": ranges, "rangeCount": len(ranges),
            "usefulScalarCount": len(points), "modified": True, "coverageNote": spec["purpose"]}
        manifest["fonts"] = [f for f in manifest["fonts"] if f["postScriptName"] != entry["postScriptName"]]
        manifest["fonts"].insert(1, entry)
        union = {cp for f in manifest["fonts"] for lo,hi in f["ranges"] for cp in range(lo,hi+1)}
        manifest["usefulUnionScalarCount"] = len(union)
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    else:
        manifest = json.loads((ROOT / "Fonts/manifest.json").read_text())
        expected = next(f for f in manifest["fonts"] if f["postScriptName"] == "UniboardCombiningPreviews-Regular")
        if len(data) != expected["bytes"] or hashlib.sha256(data).hexdigest() != expected["sha256"]:
            raise ValueError("Reproduced combining font differs from the reviewed manifest")
        if notice != (ROOT / "Fonts/CombiningPreviews-OFL.txt").read_text():
            raise ValueError("Reproduced combining license differs from the reviewed notice")
    print("Verified combining-preview font:", args.output.stat().st_size, "bytes")


if __name__ == "__main__":
    main()
