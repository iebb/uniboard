#!/usr/bin/env python3
"""Reproduce the iOS-measured optional font subsets; never update them on a catalog refresh.

Install Scripts/requirements-fonts.txt. Sources and scalar ranges are pinned in
 docs/font-audit/font-subset-inputs.json. Default mode verifies the shipped
 catalog; --update-catalog is an explicit metadata update after reviewing inputs.
"""
import argparse
import hashlib
import io
import json
import logging
from pathlib import Path
import re
import urllib.request
import zipfile
import fontTools
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
logging.getLogger("fontTools").setLevel(logging.ERROR)
PACKS = {
    "historic-symbols": ("Historic scripts & symbols", "Noto-first previews for Tangut, Nushu, Khitan, music, historic scripts and symbols, with compact open-font fallbacks."),
    "han-supplementary": ("Rare Han: B–F & I", "Missing ideographs from CJK extensions B, C, D, E, F and I, plus compatibility characters. Uses a Jigmo subset."),
    "han-latest": ("Rare Han: G, H & J", "Missing ideographs from newer CJK extensions G, H and J. Uses a Jigmo subset."),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def source_font(entry, cache):
    checksum = entry["sourceFontSha256"]
    target = cache / (checksum + entry["sourceExtension"])
    if target.exists() and digest(target.read_bytes()) == checksum:
        return target
    request = urllib.request.Request(entry["sourceURL"], headers={"User-Agent": "Uniboard-font-subset-builder/1.1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(100 * 1024 * 1024 + 1)
    if len(data) > 100 * 1024 * 1024 or digest(data) != entry["sourceDownloadSha256"]:
        raise ValueError("Upstream font size or SHA-256 mismatch")
    if entry["archiveEntry"]:
        # Read exactly the pinned member; never extract archive-controlled paths.
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            data = archive.read(entry["archiveEntry"])
    if digest(data) != checksum:
        raise ValueError("Pinned font member SHA-256 mismatch")
    cache.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    return target


def build(entry, source, output):
    filename = entry["filename"]
    if Path(filename).name != filename or not re.fullmatch(r"UniboardCoverage\d{3}-Regular\.(ttf|otf)", filename):
        raise ValueError("Unexpected subset filename")
    number = re.search(r"Coverage(\d+)", filename)[1]
    family = f"Uniboard Coverage {number}"
    ps = entry["postScriptName"]
    points = {cp for start, end in entry["ranges"] for cp in range(start, end + 1)}
    support = set(entry["supportPoints"])
    font = TTFont(source, recalcTimestamp=False)
    if not points <= set(font.getBestCmap()):
        raise ValueError("Measured scalar missing from original cmap")
    options = subset.Options()
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    options.notdef_outline = True
    options.recalc_timestamp = False
    options.hinting = False
    sub = subset.Subsetter(options=options)
    sub.populate(unicodes=points | support)
    sub.subset(font)
    names = {1: family, 2: "Regular", 3: f"Uniboard-Coverage-{number}-1.1", 4: family + " Regular", 6: ps,
             16: family, 17: "Regular", 18: family + " Regular", 20: ps, 21: family, 22: "Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding(), errors="replace")
    if entry["family"].startswith("Noto"):
        body = (ROOT / "Fonts/NotoSymbols2-OFL.txt").read_text()
        body = body[body.index("-----------------------------------------------------------"):]
        notice = entry["copyright"] + "\n\nModified for Uniboard: renamed preview subset.\n\n" + body
    else:
        notice = (ROOT / "Fonts" / entry["licenseFilename"]).read_text()
    # Every individually downloadable font carries its own full license notice.
    font["name"].setName(notice, 13, 3, 1, 0x409)
    font["name"].setName(notice, 13, 0, 4, 0)
    if "CFF " in font:
        cff = font["CFF "].cff
        cff.fontNames = [ps]
        for top in cff.topDictIndex:
            top.FullName = family + " Regular"
            top.FamilyName = family
            if hasattr(top, "FDArray"):
                for index, fd in enumerate(top.FDArray):
                    fd.FontName = ps + f"-FD{index}"
    target = output / filename
    font.recalcTimestamp = False
    font.save(target)
    font.close()
    data = target.read_bytes()
    check = TTFont(target)
    if not points <= set(check.getBestCmap()) or check["name"].getDebugName(6) != ps:
        raise ValueError("Subset lost a required scalar or unreserved identity")
    if "SIL OPEN FONT LICENSE" not in check["name"].getDebugName(13) and "CC0 1.0 Universal" not in check["name"].getDebugName(13):
        raise ValueError("Subset license notice missing")
    check.close()
    return len(data), digest(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "build/font-downloads")
    parser.add_argument("--cache", type=Path, default=ROOT / "build/font-source-cache")
    parser.add_argument("--update-catalog", action="store_true")
    args = parser.parse_args()
    spec = json.loads((ROOT / "docs/font-audit/font-subset-inputs.json").read_text())
    if fontTools.__version__ != spec["fontToolsVersion"]:
        raise ValueError("Install the pinned Scripts/requirements-fonts.txt before reproducing assets")
    args.output.mkdir(parents=True, exist_ok=True)
    packs = {}
    for entry in spec["fonts"]:
        length, checksum = build(entry, source_font(entry, args.cache), args.output)
        asset = {"filename": entry["filename"], "displayName": entry["family"] + " (preview subset)",
                 "postScriptName": entry["postScriptName"], "sha256": checksum, "sourceURL": entry["sourceURL"],
                 "licenseFilename": entry["licenseFilename"], "ranges": entry["ranges"]}
        packs.setdefault(entry["packId"], []).append({"asset": asset, "bytes": length,
            "downloadURL": spec["downloadBase"] + entry["filename"]})
        print(entry["family"], length, checksum, flush=True)
    catalog = {"schemaVersion": 1, "unicodeVersion": spec["unicodeVersion"], "stockIOS": spec["baselineIOS"],
        "packs": [{"id": key, "title": PACKS[key][0], "detail": PACKS[key][1], "fonts": fonts} for key, fonts in packs.items()]}
    target = ROOT / "Fonts/DownloadableFonts.json"
    if args.update_catalog:
        target.write_text(json.dumps(catalog, indent=2) + "\n")
    elif json.loads(target.read_text()) != catalog:
        raise ValueError("Reproduced files differ from the reviewed font catalog")
    (args.output / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")
    print("Verified", sum(len(p["fonts"]) for p in catalog["packs"]), "reproducible licensed preview subsets")


if __name__ == "__main__":
    main()
