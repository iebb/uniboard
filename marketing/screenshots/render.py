#!/usr/bin/env python3
"""Compose App Store artwork around untouched, real application captures.

Run from this folder: python3 render.py
Only captured source files are exported. No UI is synthesized or relabeled.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
FOREST = "#29332C"
IVORY = "#F7F5F0"
TERRACOTTA = "#B94D2C"
MUTED = "#6C736A"
SANS = "/System/Library/Fonts/Avenir Next.ttc"
SERIF = "/System/Library/Fonts/Supplemental/Georgia.ttf"
MONO = "/System/Library/Fonts/SFNSMono.ttf"
ICON = ROOT.parents[1] / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

SHOTS = [
    ("00-explore", "Unicode.\nWithin reach.", "Find a symbol, letter or little detail.", "A WORLD OF CHARACTERS", True),
    ("01-keyboard", "Type the\nunexpected.", "Search a symbol. Tap to type.", "TYPE WITH UNIBOARD", True),
    ("02-search", "Find it.\nBy name or code.", "Code points, names and descriptions.", "FIND YOUR CHARACTER", False),
    ("03-blocks", "Browse the\nworld of Unicode.", "Explore blocks, one character at a time.", "TAKE THE SCENIC ROUTE", False),
    ("04-details", "The details.\nMade clear.", "Names, codes and copy in one place.", "LOOK A LITTLE CLOSER", True),
    ("05-saved", "Your favorites.\nAlways handy.", "Keep the characters you come back to.", "MAKE IT YOURS", False),
    ("06-private", "Private.\nBy design.", "Offline search. No Full Access required.", "BUILT FOR YOUR PRIVACY", True),
]


def font(path, size):
    return ImageFont.truetype(path, int(size))


def tracked(draw, xy, text, face, color, spacing):
    x, y = xy
    for glyph in text:
        draw.text((x, y), glyph, font=face, fill=color)
        x += draw.textlength(glyph, font=face) + spacing


def composite(source, device, headline, subtitle, eyebrow, dark):
    width, height = (1320, 2868) if device == "iphone" else (2064, 2752)
    bg, ink = (FOREST, IVORY) if dark else (IVORY, FOREST)
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
        tracked(draw, (margin, 522), eyebrow, font(SANS, 23), TERRACOTTA if not dark else "#F39A73", 3.1)
        card_top, screen_width, border = 612, 994, 17
    else:
        title = headline.replace("\n", " ")
        title_size = 126
        while draw.textlength(title, font=font(SERIF, title_size)) > width - 2 * margin:
            title_size -= 1
        draw.text((margin, 225), title, font=font(SERIF, title_size), fill=ink)
        draw.text((margin, 387), subtitle, font=font(SANS, 53), fill=ink)
        tracked(draw, (margin, 473), eyebrow, font(SANS, 28), TERRACOTTA if not dark else "#F39A73", 4)
        card_top, screen_width, border = 572, 1548, 20
    screenshot = Image.open(source).convert("RGB")
    screen_height = round(screenshot.height * screen_width / screenshot.width)
    screenshot = screenshot.resize((screen_width, screen_height), Image.Resampling.LANCZOS)
    screen_left = (width - screen_width) // 2
    rect = (screen_left - border, card_top - border, screen_left + screen_width + border, card_top + screen_height + border)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle((rect[0] - 5, rect[1] + 20, rect[2] + 5, rect[3] + 24), radius=52, fill=(0, 0, 0, 60 if dark else 30))
    shadow = shadow.filter(ImageFilter.GaussianBlur(35))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB")
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(rect, radius=48 if device == "iphone" else 40, fill="#171D19", outline="#536056", width=2)
    # Only round the outermost physical screen corners. The real image is otherwise
    # copied whole, with one uniform resize; all app UI/content remains unchanged.
    mask = Image.new("L", screenshot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_width, screen_height), radius=31 if device == "iphone" else 22, fill=255)
    canvas.paste(screenshot, (screen_left, card_top), mask)
    return canvas


def main():
    records = []
    exports = []
    for device in ("iphone", "ipad"):
        (ROOT / device).mkdir(exist_ok=True)
        for slug, headline, subtitle, eyebrow, dark in SHOTS:
            source = ROOT / "source" / device / (slug + ".png")
            if not source.exists():
                continue
            output = ROOT / device / (slug + ".png")
            artwork = composite(source, device, headline, subtitle, eyebrow, dark)
            artwork.save(output, optimize=True)
            exports.append(output)
            records.append({"export": str(output.relative_to(ROOT)), "source": str(source.relative_to(ROOT)), "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "size": list(artwork.size), "mode": artwork.mode, "headline": headline, "subtitle": subtitle, "composition": "Full actual screenshot, uniformly resized, inside decorative frame. No app UI relabeling or generation."})
    (ROOT / "manifest.json").write_text(json.dumps({"apple_size_reference": "https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications", "approved_icon_sha256": hashlib.sha256(ICON.read_bytes()).hexdigest(), "screenshots": records}, indent=2) + "\n")
    if exports:
        tiles = []
        for output in exports:
            im = Image.open(output)
            im.thumbnail((320, 680))
            tile = Image.new("RGB", (340, 730), "#E6E4DC")
            tile.paste(im, ((340 - im.width) // 2, 16))
            ImageDraw.Draw(tile).text((12, 701), output.parent.name + " / " + output.stem, font=font(SANS, 15), fill=FOREST)
            tiles.append(tile)
        cols = min(6, len(tiles))
        rows = (len(tiles) + cols - 1) // cols
        sheet = Image.new("RGB", (340 * cols, 730 * rows), "#E6E4DC")
        for index, tile in enumerate(tiles):
            sheet.paste(tile, ((index % cols) * 340, (index // cols) * 730))
        sheet.save(ROOT / "qa" / "contact-sheet.jpg", quality=94)
    print(f"Exported {len(records)} real-capture screenshots")


if __name__ == "__main__":
    main()
