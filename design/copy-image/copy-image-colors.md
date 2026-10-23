# Uniboard — Copy Image color presets (addendum)

23 Oct 2026 · user msg247, product msg248. Extends `copy-image-design.md`;
everything there still holds unless changed here. Surface: the existing
in-keyboard Copy Image panel (`previewImagePanel` in
Keyboard/KeyboardViewController.swift). No new screen, sheet or settings page.

## What changes in the export
- The image is drawn in the chosen **text color** on the chosen **background**,
  instead of the preview's own foreground on systemBackground.
- Background may be **transparent**: then the PNG keeps an alpha channel and
  every non-glyph pixel (including the 8 pt padding) is fully transparent.
  Render glyphs straight onto a clear context with premultiplied alpha — never
  draw on white/black and key it out (that leaves a fringe). Opaque backgrounds
  stay opaque PNGs as before.
- Color emoji and other color glyphs keep their own colors; only monochrome
  glyph ink takes the text color. Same fonts, same visible-only excerpt, same
  padding, 3× scale — unchanged.
- Colors are fixed sRGB values, not semantic/dynamic colors, so the picture
  looks identical whether the keyboard is in light or dark mode.

## Presets (exact values)
| id | label | text | background |
|---|---|---|---|
| blackOnWhite | Black on White | #000000 | #FFFFFF |
| blackOnClear | Black on Transparent | #000000 | transparent |
| whiteOnBlack | White on Black | #FFFFFF | #000000 |
| whiteOnClear | White on Transparent | #FFFFFF | transparent |
| custom | Custom | user pick (default #000000) | user pick (default #FFFFFF) |

Default on first use: Black on White (the user's first-named preset; most
predictable result in any destination). The choice is remembered between
uses — last preset id plus the two custom colors — in the keyboard's own
UserDefaults. Store only those values; never any text. Works without Full
Access; no App Group needed.

## Panel layout (top to bottom)
1. Header "Text preview" + Close — unchanged.
2. Thumbnail — unchanged size rules, but now shows the export in the chosen
   colors (re-render the frozen excerpt on every color change; the text itself
   never re-reads the host). Where the image is transparent, draw a
   checkerboard *behind* it inside the thumbnail container, 8 pt squares, in
   the tone that contrasts with the TEXT color (not the keyboard appearance):
   text relative luminance ≤ 0.5 → light checker #FFFFFF / #E5E5EA;
   > 0.5 → dark checker #2C2C2E / #3A3A3C. So black-on-transparent always
   previews on light squares and white-on-transparent on dark squares, in
   both keyboard appearances. The checkerboard is preview-only and never
   appears in the PNG.
3. **Colors row (new).** Leading caption, footnote 13 secondary:
   "Colors · <selected label>" (e.g. "Colors · White on Transparent"),
   one line, truncates tail. Below it, a horizontal row of 5 chips, spacing 8,
   left-aligned, horizontally scrollable if the width runs out:
   - Each chip 44×44 pt, radius 10 continuous. Content: "Aa", system 17
     semibold, fixed size (doesn't scale with Dynamic Type — the caption above
     carries the name), in the preset's text color on its background; a
     transparent background shows the checkerboard by the same text-luminance
     rule as the thumbnail (Black on Transparent = light squares, White on
     Transparent = dark squares).
   - Hairline border on every chip: 1 px separator color, so white and black
     chips stay visible on the panel in both appearances.
   - Custom chip: SF Symbol `paintpalette`, 17 pt medium, primary label color
     on tertiarySystemFill.
   - Selected chip: 2 pt ring in KeyboardPalette.accent, 2 pt outside the
     chip edge (so the chip's own colors aren't covered). Only one selected.
   - Tap selects immediately and re-renders the thumbnail; no confirm step.
4. **Custom colors (only while Custom is selected)**, directly under the chip
   row, spacing 8 between the two lines:
   - Line "Text": caption footnote 13 secondary, then a horizontal scroll of
     swatches.
   - Line "Background": same, with "Transparent" as the first swatch.
   - Swatch: 28 pt circle centred in a 44×44 hit target, hairline border 1 px
     separator. Selected: 2 pt accent ring outside the circle.
   - Palette (fixed sRGB, both lines): Black #000000, White #FFFFFF,
     Gray #8E8E93, Red #FF3B30, Orange #FF9500, Green #34C759,
     Blue #007AFF, Purple #AF52DE. Background line adds Transparent first
     (checkerboard circle).
   - No system color picker: it would open outside the keyboard's bounds,
     which the base spec forbids.
5. Explanation footnote — unchanged base text, then (final copy, Camo msg256):
   - when the background is transparent, append:
     "Transparent areas show the background where you paste. The checkerboard isn’t copied."
   - when the frozen excerpt contains any color glyph (emoji), append:
     "Emoji keep their original colors."
   Both are sentences in the same footnote paragraph, not separate notices.
6. Notice/error and Copy Image button — unchanged.

Switching colors resets a Success state back to Ready (the copied image no
longer matches the thumbnail). During Generating, chips are disabled.

## Layout fixes (msg269)
- Chip row and swatch lines: 4 pt clearance inside their scroll content on every side so the 2 pt-outset, 2 pt ring is never clipped.
- Copy Image button and its notice are pinned to the panel bottom, outside the scroll, 12 pt below the scrolling part. Header + Close pinned at top. Only thumbnail, colors and explanation scroll.

## Readability guard (custom only; presets always pass)
- Same text and background color: Copy Image disabled; inline footnote in
  secondary color with `exclamationmark.circle`: "Choose different text and
  background colors." (final, Camo msg256).
- Opaque background with contrast ratio below 3:1 (WCAG formula on the two
  sRGB values): copy stays enabled; same-style inline caution:
  "This text may be hard to read." (final, Camo msg256).
- Transparent background: no check (destination unknown).

## Accessibility
- Chip row is one group labelled "Image colors". Each chip: label = preset
  name, trait button, plus selected trait when chosen. Custom chip label
  "Custom colors".
- Swatches: label = color name ("Transparent", "Black" …), with the line in
  the label ("Background, Transparent"). Selected trait when chosen.
- Thumbnail accessibilityValue keeps the visible text; append the colors,
  e.g. "White on Transparent".
- VoiceOver order: title, Close, thumbnail, colors caption + chips, custom
  lines, explanation, notice, Copy Image.
- Reduce Motion: thumbnail swaps without cross-fade; otherwise fade ≤120 ms.
- Large text: the caption and explanation wrap; chips and swatches stay
  44 pt; the panel already scrolls vertically within the keyboard.

## Verification (developer)
- Each preset's PNG: sample a glyph pixel and a padding pixel — exact
  expected RGBA (transparent = alpha 0 in padding, no grey/white fringe on
  glyph edges when pasted over a dark and a light background).
- Light vs dark keyboard produce byte-identical images for the same preset.
- Color emoji unchanged in every preset.
- Choice persists across closing the panel and relaunching the keyboard;
  nothing but the preset id and two colors is stored.
- Custom same-color disables copy; low contrast shows caution only.
- Hidden-buffer sentinel still absent from image and accessibility text.
