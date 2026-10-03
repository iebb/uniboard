#!/usr/bin/env python3
"""Compose App Store artwork around untouched, real application captures.

Run from this folder: python3 render.py
Use --preview while replacing captures; it leaves upload files untouched.
Only captured source files are exported. No UI is synthesized or relabeled.
"""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
FOREST = "#29332C"
WHITE = "#FFFFFF"
IVORY = "#F7F5F0"
TERRACOTTA = "#B94D2C"
MUTED = "#6C736A"
SANS = "/System/Library/Fonts/Avenir Next.ttc"
SERIF = "/System/Library/Fonts/Supplemental/Georgia.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
ICON = ROOT.parents[1] / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

SHOTS = [
    ("00-explore", "The newest.\nFirst.", "Characters sorted by Unicode introduction.", "A WORLD OF CHARACTERS", WHITE),
    ("01-keyboard", "Every character.\nIn your keyboard.", "Search, hold for details, tap to type.", "TYPE WITH UNIBOARD", WHITE),
    ("02-search", "A name.\nA code. A match.", "Find names, descriptions and code points.", "FIND YOUR CHARACTER", IVORY),
    ("03-blocks", "A whole block.\nWorth exploring.", "Browse scripts, symbols and writing systems.", "BROWSE UNICODE BLOCKS", WHITE),
    ("04-details", "A glyph.\nAnd its meaning.", "Hold for names, descriptions and properties.", "LOOK A LITTLE CLOSER", IVORY),
    ("05-saved", "Your favorites.\nWithin reach.", "Save complete characters and emoji sequences.", "MAKE IT YOURS", WHITE),
    ("06-private", "Private.\nBy design.", "Offline search. No Full Access required.", "BUILT FOR YOUR PRIVACY", IVORY),
    ("07-emoji", "One emoji.\nEvery code point.", "Joiners, variation selectors and all.", "COMPLETE EMOJI SEQUENCES", WHITE),
    ("08-editions", "Latest release.\nLatest draft.", "Unicode 18 and 19 draft, bundled offline.", "SWITCH YOUR CATALOG", IVORY),
    ("09-properties", "Unicode properties.\nIn your keyboard.", "Script, direction, combining class and more.", "HOLD TO INSPECT", WHITE),
]
UPLOAD_ORDER = ["01-keyboard", "00-explore", "07-emoji", "04-details", "09-properties", "08-editions", "02-search", "03-blocks", "05-saved", "06-private"]


def font(path, size):
    return ImageFont.truetype(path, int(size))


def tracked(draw, xy, text, face, color, spacing):
    x, y = xy
    for glyph in text:
        draw.text((x, y), glyph, font=face, fill=color)
        x += draw.textlength(glyph, font=face) + spacing


def composite(source, device, headline, subtitle, eyebrow, background):
    width, height = (1320, 2868) if device == "iphone" else (2064, 2752)
    bg, ink = background, FOREST
    canvas = Image.new("RGB", (width, height), bg)
    draw = ImageDraw.Draw(canvas)
    margin = 100 if device == "iphone" else 142
    logo_y = 80 if device == "iphone" else 92
    icon = Image.open(ICON).convert("RGB").resize((72, 72), Image.Resampling.LANCZOS)
    icon_mask = Image.new("L", (72, 72), 0)
    ImageDraw.Draw(icon_mask).rounded_rectangle((0, 0, 72, 72), radius=17, fill=255)
    canvas.paste(icon, (margin, logo_y), icon_mask)
    draw.text((margin + 98, logo_y + 5), "uniboard", font=font(SANS, 42), fill=ink)
    if device == "iphone":
        title_y, title_size, line_height = 185, 108, 125
        title_size = min(title_size, int(1120 / max(draw.textlength(t, font=font(SERIF, 1_000)) / 1_000 for t in headline.split("\n"))))
        for index, line in enumerate(headline.split("\n")):
            draw.text((margin, title_y + index * line_height), line, font=font(SERIF, title_size), fill=ink)
        draw.text((margin, 456), subtitle, font=font(SANS, 37), fill=ink)
        tracked(draw, (margin, 522), eyebrow, font(SANS, 23), TERRACOTTA, 3.1)
        card_top, screen_width, border = 612, 994, 17
    else:
        title = headline.replace("\n", " ")
        title_size = 126
        while draw.textlength(title, font=font(SERIF, title_size)) > width - 2 * margin:
            title_size -= 1
        draw.text((margin, 225), title, font=font(SERIF, title_size), fill=ink)
        draw.text((margin, 387), subtitle, font=font(SANS, 53), fill=ink)
        tracked(draw, (margin, 473), eyebrow, font(SANS, 28), TERRACOTTA, 4)
        card_top, screen_width, border = 572, 1548, 20
    with Image.open(source) as capture:
        if capture.format != "PNG" or capture.width >= capture.height:
            raise ValueError(f"Expected a complete portrait PNG capture: {source}")
        if "A" in capture.getbands() and capture.getchannel("A").getextrema() != (255, 255):
            raise ValueError(f"The source capture must be opaque: {source}")
        screenshot = capture.convert("RGB")
    # Preserve the full capture with one uniform scale even if its device has
    # a different aspect ratio. Never stretch or crop UI to fill the frame.
    screen_width = min(screen_width, round(screenshot.width * (height - card_top - 80 - border) / screenshot.height))
    screen_height = round(screenshot.height * screen_width / screenshot.width)
    screenshot = screenshot.resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    screen_left = (width - screen_width) // 2
    rect = (screen_left - border, card_top - border, screen_left + screen_width + border, card_top + screen_height + border)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((rect[0] - 5, rect[1] + 20, rect[2] + 5, rect[3] + 24), radius=52, fill=(41, 51, 44, 27))
    shadow = shadow.filter(ImageFilter.GaussianBlur(35))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(rect, radius=48 if device == "iphone" else 40, fill="#EAE8E1", outline="#C9CDC3", width=2)
    # Only round the outermost physical screen corners. The real image is otherwise
    # copied whole, with one uniform resize; all app UI/content remains unchanged.
    mask = Image.new("L", screenshot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_width, screen_height), radius=31 if device == "iphone" else 22, fill=255)
    canvas.paste(screenshot, (screen_left, card_top), mask)
    return canvas


def upload_manifest(records):
    sets = []
    for locale in ("en-US", "ja"):
        for device, display_type in (("iphone", "APP_IPHONE_67"), ("ipad", "APP_IPAD_PRO_3GEN_129")):
            available = {Path(record["export"]).stem: record["export"] for record in records
                         if Path(record["export"]).parent.name == device}
            files = [available[slug] for slug in UPLOAD_ORDER if slug in available]
            if files:
                sets.append({"locale": locale, "displayType": display_type, "files": files})
    return sets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true", help="Write only qa/preview; leave upload assets unchanged")
    args = parser.parse_args()
    destination = ROOT / "qa" / "preview" if args.preview else ROOT
    records = []
    exports = []
    icon_hash = hashlib.sha256(ICON.read_bytes()).hexdigest()
    source_hashes = {}
    for device in ("iphone", "ipad"):
        (destination / device).mkdir(parents=True, exist_ok=True)
        for slug, headline, subtitle, eyebrow, background in SHOTS:
            source = ROOT / "source" / device / (slug + ".png")
            if not source.exists():
                continue
            source_hashes[source] = hashlib.sha256(source.read_bytes()).hexdigest()
            output = destination / device / (slug + ".png")
            artwork = composite(source, device, headline, subtitle, eyebrow, background)
            artwork.save(output, optimize=True)
            exports.append(output)
            with Image.open(source) as capture:
                source_size = list(capture.size)
            records.append({"export": str(output.relative_to(destination)), "source": str(source.relative_to(ROOT)), "source_sha256": source_hashes[source], "source_size": source_size, "export_sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "size": list(artwork.size), "mode": artwork.mode, "headline": headline, "subtitle": subtitle, "background": background, "composition": "Complete actual screenshot with one uniform resize inside a decorative frame. Only outer physical screen corners are rounded. No app UI relabeling or generation."})
    if not records:
        raise SystemExit("No actual captures found under source/iphone or source/ipad")
    if any(hashlib.sha256(source.read_bytes()).hexdigest() != checksum for source, checksum in source_hashes.items()):
        raise RuntimeError("Source capture changed during rendering; regenerate the outputs")
    if hashlib.sha256(ICON.read_bytes()).hexdigest() != icon_hash:
        raise RuntimeError("Approved icon changed during rendering; regenerate the outputs")
    (destination / "manifest.json").write_text(json.dumps({"apple_size_reference": "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications", "approved_icon_sha256": icon_hash, "preview_only": args.preview, "screenshots": records}, indent=2) + "\n")
    if not args.preview:
        (ROOT / "upload-manifest.json").write_text(json.dumps(upload_manifest(records), indent=2) + "\n")
    tiles = []
    for output in exports:
        with Image.open(output) as artwork:
            im = artwork.copy()
        im.thumbnail((320, 680))
        tile = Image.new("RGB", (340, 730), IVORY)
        tile.paste(im, ((340 - im.width) // 2, 16))
        ImageDraw.Draw(tile).text((12, 701), output.parent.name + " / " + output.stem, font=font(SANS, 15), fill=FOREST)
        tiles.append(tile)
    cols = min(6, len(tiles))
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (340 * cols, 730 * rows), WHITE)
    for index, tile in enumerate(tiles):
        sheet.paste(tile, ((index % cols) * 340, (index // cols) * 730))
    sheet_path = destination / "contact-sheet.jpg" if args.preview else ROOT / "qa" / "contact-sheet.jpg"
    sheet_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(sheet_path, quality=94)
    print(f"Exported {len(records)} real-capture screenshots{' to preview only' if args.preview else ''}")


if __name__ == "__main__":
    main()
