# Uniboard — Copy Image size choice (addendum)

24 Oct 2026 · user msg424 ("text-to-image can choose scale"), Ato msg425
(1×, 2×, 3×; 3× default; show the resulting dimensions; scale changes the
exported resolution only, never text or layout; remembered; in configuration
import/export). Extends `copy-large/design.md` (panel container, layout,
growth) and `copy-image-colors.md` (chips, rings, states); everything there
still holds unless changed here. Placement first sent in msg429.

Mockup: artifact "Uniboard — Copy Image size choice"
(58BAD18E-4305-4CCF-9AB3-7F5AE9FD1264, illustrative, dark, 440 pt phone,
keyboard grown 96 pt). Screenshots beside this file: `1-preset-3x.png`,
`2-custom-2x-scrolled.png`. The dashed orange outline in the mockup only marks
the new block. Where a screenshot and this text disagree, this text wins.

## 1. Placement
- New block "Size" in the scrolling body, after the Colors block (after the
  Custom Text/Background lines when Custom is selected), before the
  explanation footnote. Body VStack spacing 12 is unchanged, so 12 pt above
  and below it.
- Not in the pinned footer and not in the header: Close and Copy Image keep
  their places. The +96 pt keyboard growth (iPhone portrait) is unchanged.
- Reason: colors change per use; size is set once and remembered, so it takes
  the lower slot and doesn't push the color controls down.
- Fit, iPhone portrait, grown body 262 pt, default text size, 48 pt thumbnail:
  with a preset, thumbnail + Colors + Size = 224 pt, so Size is visible
  without scrolling (explanation starts below). With Custom open the body is
  ~402 pt and scrolls; the existing "scroll to the Background line" on picking
  Custom is unchanged (do NOT scroll further to Size). Landscape / iPad /
  hosts without growth: same order, body scrolls (fallback rules unchanged).

## 2. The block
1. Caption line, same style and spacing as the Colors caption: footnote 13,
   `.secondary`, one line, truncates tail at default size, wraps at large text.
   Text: "Size · {width} × {height} pixels" (final, Camo msg432).
   - {width}/{height} = the PNG's actual pixel size for the current excerpt
     and chosen scale (Pluso's `KeyboardImagePixelSize`, computed without
     rendering). Never a "points" size, never an estimate.
   - Numbers: locale-formatted integers with grouping (1,260), separator
     " × " (U+00D7 with spaces), `.monospacedDigit()` so the line doesn't
     jitter when switching.
   - No size available (nothing to copy / canvas empty): caption reads "Size"
     alone; the chips still work and the choice is still saved.
   - Requested scale reduced to fit the canvas limits: the caption still shows
     the real copied size. Checked against the limits (4800 × 1200 px,
     2.4 MP): a one-line preview row on any current iPhone or iPad (widest
     1376 pt) stays under them at 3×, so no extra UI. If it ever happens,
     append Camo's short note (proposed " · reduced to fit") — no alert.
2. 6 pt below: chip row, left-aligned, three chips "1×" "2×" "3×":
   - 44 × 44, radius 10 continuous, fill `tertiarySystemFill`, hairline 1 px
     `separator` border (same as the Custom chip), label system 17 semibold
     `.primary`, monospaced digits, fixed size (no Dynamic Type scaling).
   - 12 pt apart, 4 pt ring clearance on every side (row height 52).
   - Selected: the same 2 pt accent ring, 2 pt outside the chip edge. Exactly
     one selected. Default 3× (today's output).
   - Not a segmented control: the panel keeps one selection style, and every
     target stays 44 pt.

## 3. Behavior
- Tap selects immediately and saves; no confirm. The caption updates in the
  same frame. The thumbnail does NOT change (same canvas, text, fonts and
  layout at every scale; only pixel count and DPI metadata 72 × scale change).
- Like a color change: a Success state goes back to Ready (the copied image
  no longer matches the choice). During Generating the chips are disabled.
- Remembered with the image colors (same storage, survives closing the panel
  and relaunching the keyboard). Nothing else is stored.
- Feedback: same haptic/sound behaviour as the color chips (none extra).

## 4. Configuration file and Review Import
- The scale travels in the image section (`image_scale`, 1/2/3); missing key
  → 3×. That's Pluso's codec, already in place.
- Review Import: the section row is renamed "Copy Image" (was "Image
  Colors"; keep `paintpalette`, same position, same status words). Its change
  list gets one line when the scale differs, same plain format as the other
  lines: "Image scale: 3× → 2×" (final, Camo msg432).
- Configuration page header (final, Camo msg434): "Save your settings,
  layouts, favorites, font rules and Copy Image options in a TOML file, or
  import a configuration from Files." Elsewhere, where the contents are
  spelled out, use "Copy Image colors and scale" (Camo msg432). Third footer, final: "Copy Image colors and scale
  chosen in the keyboard without Full Access aren’t included in this file."
  The caption's pixel size is never stored or exported, only the scale.

## 5. Accessibility
- Chip row is one group, label "Image size". Each chip: label "1 times scale",
  "2 times scale", "3 times scale" (final, Camo msg432), trait button, selected trait when chosen; value = the resulting
  size when it's the selected one ("318 by 114 pixels").
- Caption: accessibilityLabel "Size, {w} by {h} pixels".
- VoiceOver order: … colors caption + chips, custom lines, size caption +
  size chips, explanation, notice, Copy Image.
- Contrast: semantic colors only, same as the color chips. Targets ≥ 44 pt.

## 6. Checks (developer)
- PNG pixel size equals the caption numbers for 1×, 2×, 3×; DPI = 72 × scale.
- Text, glyph positions and padding are identical across scales after
  downsampling (same canvas in points).
- Choice persists across panel close and keyboard relaunch; exported file
  carries it; importing a file with a different scale lists the change and
  applies it; a file without the key → 3×.
- UI test (iPhone portrait, preset selected): the three size chips are
  hittable without scrolling and each is 44 × 44.
