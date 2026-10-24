# Uniboard 1.3 — Font styles grid (Google font page)

Task: task.8fdc99c3. Rev. 2: Camo's final strings (msg541), §4 §6 §7 §10.
Asks: user msg481 (styles as icons in a grid; a variable
font shows a single download), user msg494 (Normal and Italic columns, one row
per weight), Ato msg482 (show only real combinations, never fake bold or
italic; one download control per actual file).
Mockups: artifact D92C7863 (7 screens, attached as PNGs 1–7). Reference:
the user's screenshot of today's Styles list (ABeeZee).

Scope: only the Styles section of `CatalogFontFaceDetail`
(`App/FontFaceDetailView.swift`, `Section("Styles")` ~L108). The download
controls move up into that section (§6). Info, Preview, License and Remove
Download stay as they are. `LocalFontFaceDetail`, the catalog file and
the download coordinator don't change. No catalog regeneration.

Mood: the same native inset-grouped list, system blue accent, semantic
colors, SF Pro. The grid is one list row inside the Styles card.

---------------------------------------------------------------------------
## 1. Sorting styles into cells (pure function + unit tests)

Add `StyleGrid.make(family:catalog:downloadedFileIDs:) -> StyleGrid`. It
derives `weight`, `italic`, `width` and a `setKey` for every style. The
catalog has no weight or italic fields, and some names are wrong (Abhaya
Libre calls its ExtraBold file "Regular"), so follow these rules in order:

Name words: split the style name on spaces after joining "Extra Bold",
"Semi Bold", "Extra Light", "Ultra Light", "Demi Bold", "Ultra Bold" and
"Extra Black" into one word and turning "BoldItalic" into "Bold Italic".
- Weight words: Thin/Hairline 100 · ExtraLight/UltraLight 200 · Light 300 ·
  Regular/Book/Normal 400 · Medium 500 · SemiBold/DemiBold 600 · Bold 700 ·
  ExtraBold/UltraBold 800 · Black/Heavy 900 · ExtraBlack 1000.
- Width words: UltraCondensed 50 · ExtraCondensed 62.5 · Condensed 75 ·
  SemiCondensed 87.5 · none 100 · SemiExpanded 112.5 · Expanded 125 ·
  ExtraExpanded 150 · UltraExpanded 200.
- Italic words: Italic, Oblique, any word ending in "Kursiv".
- PostScript suffix: the text after the first "-" in `postScriptName`.
  Split it greedily into the same weight, width and Italic/Oblique words
  (CamelCase, longest match first). Use it only if it splits completely.

Derived values:
- weight: `variationInstance["wght"]`, rounded, if present. Otherwise the
  name's weight word, unless that word is Regular, Book or Normal or there
  is none; then the PostScript suffix's weight word; otherwise 400.
- italic, variable file: `ital` ≥ 1, `slnt` ≠ 0, or an italic name word.
  Static file: the PostScript suffix decides if it splits completely
  (it contains Italic or Oblique); otherwise the name words decide.
- width: `wdth` if present, else the name's width word, else the PostScript
  suffix's width word, else 100.
- Exact duplicates (same `fileID` and same `variationInstance`): keep the
  first and drop the rest.
- setKey = width + (variable files) the values of every axis other than
  wght/wdth/ital/slnt. Leave out any axis whose value only follows
  upright vs italic in this family (CRSV in Recursive, Bitcount, Geologica).
  For static files, add the leftover name words (those that aren't weight,
  width or italic words).
- Cell = (setKey, weight, italic). When several styles land in one cell,
  show one, chosen in this order: a style whose file is downloaded, then
  one from a variable file, then one whose path isn't under `/static/`. The
  others are the same face in another file and are not shown.

I checked this against the bundled catalog (snapshot 2026-10-23: 2,065
families, 9,293 styles). Every style lands in a cell and no two styles
collide. 2,032 families have one set and 33 have several (up to 17, in
Decovar Alpha). The most rows any set has is 10 (Hepta Slab). Of the
multi-style files, 817 cover exactly one column and 23 cover both columns;
none covers any other shape.

Test fixtures, with the expected result:
- ABeeZee: 1 row (400), 2 single-style files.
- Lato: 9 rows × 2 columns, 18 single-style files.
- Roboto: sets 100 and 75. In each set, the upright file covers Normal and
  the italic file covers Italic.
- Commissioner: 9 × 2, and one file covers both columns.
- Oswald: 6 rows, Normal only, one file.
- Abhaya Libre: rows 400, 500, 600, 700 and 800, all Normal. The names say
  "Regular"; the PostScript names fix them.
- Tuffy: 400 and 700 rows, both columns. Both 400 files are named
  "MagerKursiv"; the PostScript name keeps Regular in Normal.
- Open Sans Hebrew: "Extra Bold" lands in the 800 row.
- Inconsolata: 9 widths. The static copies don't appear because the
  variable file covers them.
- Recursive: 4 sets (Mono Linear, Mono Casual, Sans Linear, Sans Casual),
  each 8 × 2. Italic stays in the same set as upright.
- Jaro: 5 sets (opsz 6/14/24/48/72), one cell each.
- Rokkitt: row numbers 198, 267, … (the real values).

---------------------------------------------------------------------------
## 2. Width / Variant menu (only when the family has more than one set)

- Make it the first row of the Styles section: `Picker(label, selection:)`
  with `.pickerStyle(.menu)` and the value trailing in secondaryLabel. This
  is the native menu with a leading checkmark (screen 4).
- Label: "Width" when the sets differ only in width; otherwise "Variant".
- Options, sorted by width and then catalog order:
  - Width only: "Normal" for 100. Other widths use their word, split at
    each capital ("Semi Condensed", "Ultra Expanded").
  - Variant: the leftover name words if the sets have distinct ones
    ("Mono Linear"). Otherwise the differing axis values: "Optical Size 14"
    for opsz, and "{TAG} {value}" for others ("NEGA −1", "SOFT 100").
    Put the width word first when widths differ too.
- The menu opens on the selected style's set. When you switch sets, keep
  the same weight/italic cell if it exists in the new set; otherwise select
  the set's 400 upright cell, or failing that its first cell.
- Switching sets doesn't download anything. Files keep their state; the
  Roboto upright file also covers Condensed.

---------------------------------------------------------------------------
## 3. Grid layout (screens 1–6)

- One list row with `.listRowInsets(EdgeInsets(top: 12, leading: 12,
  bottom: 12, trailing: 12))`. Use either `Grid(horizontalSpacing: 8,
  verticalSpacing: 6)` or columns of VStacks, but match these numbers.
- Columns: a weight label column 84 pt wide, then Normal and Italic sharing
  the rest equally (about 113 pt each on a 390 pt screen).
  - Show the Italic column only if the set has at least one italic cell.
    Without it, Normal takes the whole width. If the whole family has no
    italics, add a caption under the grid: "No italic styles in this
    family." (footnote, secondaryLabel, 12 pt side padding, 12 pt bottom).
  - A set with only italics (Fraunces SOFT 100 is the only one) shows only
    the Italic column, with no caption.
- Column headers "Normal" and "Italic": footnote 13 pt semibold,
  secondaryLabel, centered, row height 24 pt.
- Rows: one per weight in the set, lightest first. Never add a row the set
  doesn't have.
  - Row label: the weight name in subheadline 15 pt, Color(.label), above
    the number in caption 12 pt, secondaryLabel, leading-aligned and
    vertically centered.
  - The name is the style's own weight word when it has one; otherwise the
    standard name of the nearest standard weight. The number is the real
    rounded weight.
- Cell: 48 pt tall (`@ScaledMetric(relativeTo: .body)`), RoundedRectangle
  with corner radius 10 and `.continuous` style.
- Missing combination: leave the slot empty, with no tile, text or
  VoiceOver element. Never draw a stand-in.

---------------------------------------------------------------------------
## 4. One download state per file

For each file, look at the cells it covers in the visible set:
- **One cell (static file; screens 1 and 2):** the cell is its own tile,
  filled with `Color(.tertiarySystemFill)`. The file's badge sits in the
  tile's top-trailing corner, inset 4 pt.
- **Every cell of one column (screens 3 and 6):** draw one container, a
  RoundedRectangle with radius 12 filled with `tertiarySystemFill`,
  covering the header and all rows of that column.
  - The column title moves inside the container's top, with a second line
    under it: badge + file size (caption 12 pt, secondaryLabel). The header
    row grows to 44 pt.
  - Cells inside have no fill of their own and a 4 pt side inset.
- **Every cell in both columns (screen 5):** one container across both
  columns.
  - Its top has a 28 pt strip: badge + "1 file · {n} styles · {size}"
    (caption 12 pt, secondaryLabel), centered. The column titles sit below
    it.
- **Anything else** (it can't happen with today's catalog; it could if the
  user already downloaded a static duplicate): every cell of that file gets
  its own tile and corner badge. The text in §6 explains that they share a
  file.

Badge: today's `StyleFileStatus` icons at 15 pt
(`@ScaledMetric(relativeTo: .body)`, base 15).
- Not downloaded: `arrow.down.circle`, tint.
- Downloading: `ProgressView().controlSize(.small)`, tint, 13 pt.
- Downloaded: `checkmark.circle.fill`, tint.
- Unavailable: `exclamationmark.circle`, secondaryLabel.
- Failed or cancelled shows Not downloaded, as today.
- Badges are decorative (`accessibilityHidden`). Each cell's
  accessibilityValue carries the state (§7).

Size uses `ByteCountFormatter` with `.file`, as today. {n} is the number
of catalog styles in the file across all sets, so it is 18 for Roboto's
upright file.

---------------------------------------------------------------------------
## 5. Cell content and selection

- **Downloaded file:** draw the sample "Ag" in that exact face: the file,
  its instance coordinates and face index 0, the same identity as
  `FontDetailIdentity.matches`.
  - Size 22 pt (`@ScaledMetric(relativeTo: .title2)`), Color(.label).
  - No fallback font: use a CTFont with an empty cascade list, and draw
    only if `CTFontGetGlyphsForCharacters` finds a glyph for every
    character.
  - If the screen was opened for a character (`text` is set), use that
    text when the face covers it; otherwise "Ag". If the face covers
    neither, show the placeholder in Color(.secondaryLabel).
  - Load sample faces off the main thread, only for downloaded files.
    Cache them per (fileID, coordinates). Show the placeholder while one
    loads, with no spinner.
- **Not downloaded or downloading:** SF Symbol `textformat`, 17 pt
  semibold, Color(.tertiaryLabel). Unavailable: the same in
  Color(.quaternaryLabel).
- Never draw a sample with the system font, synthetic bold or synthetic
  italic.
- **Selected (exactly one cell):** fill `Color.accentColor.opacity(0.14)`
  (0.22 in dark mode) and a 2 pt accentColor stroke inside the radius-10
  shape. Add the `.isSelected` trait and remove the plain checkmark from
  the old list.
- Tapping a cell selects it, exactly like today's row button (it resets
  `operationError`, `verifiedFace` and `previewRevision`). It's disabled
  while `operationRunning`. The whole cell is the hit area, at least
  48 × 48 pt.

---------------------------------------------------------------------------
## 6. Selected style and download, right under the grid

These rows go in the same section, after the grid (and after the caption,
if there is one):
- Row 1, in order:
  - The name: the set option when it isn't "Normal", then the weight name,
    then " Italic". "Regular Italic" becomes "Italic". Examples:
    "Bold Italic", "Condensed Medium". Body, label color. Use this derived
    name, not the catalog's, so Abhaya Libre reads "ExtraBold".
  - "{file name} · {size}": caption 12 pt, secondaryLabel,
    `.textSelection(.enabled)`. The file name is the last path component.
    This replaces the "File: path" row.
  - Only when the file holds more than one style, a sentence in footnote
    13 pt, secondaryLabel: "This file contains {n} styles. Downloading or
    removing it affects them all." If the file covers more than one set:
    "This file contains {n} styles across {sets}. Downloading or removing
    it affects them all." Here {sets} is every set option the file covers,
    joined as "Normal and Condensed" or "A, B and C". This replaces
    "These styles share one font file…".
- Then today's `downloadControls`, `operationError` and the unavailable
  reason lines, moved here unchanged except for the button label:
  - "Download Style" when the file has one style.
  - "Download File ({n} Styles)" when it has more.
  - "Try Again" stays as it is.
- Remove dialog for a shared file: title "Remove {family} {derived name}?"
  as today. The message becomes "This removes all {n} styles in this file
  from Uniboard. You can download it again later." Single-style files keep
  today's message.
- The limits text ("Up to 16 imported…") becomes the Styles section
  footer, and the section that held it is removed.
  - The library failure text shows above the controls.
  - Note: the limit counts files, so all 18 Lato styles can't be
    downloaded, while Roboto takes 2 slots. No change to the limit; this is
    just so nobody is surprised in testing.

---------------------------------------------------------------------------
## 7. Accessibility

- VoiceOver
  - Each cell is a Button. Its label is the derived name (for example
    "Bold Italic").
  - Its value is the file state: "Not downloaded", "Downloading",
    "Downloaded" or the unavailable reason. Add ", File contains {n}
    styles" when the file has more than one style.
  - A selected cell gets the `.isSelected` trait.
- VoiceOver order is the menu, then row by row (Normal before Italic), then
  the selected block.
  - Hide the row labels from VoiceOver; the cell labels already name the
    weight.
  - A container's header or strip is one static element: "Normal styles
    file" / "Italic styles file" (column container) or "Shared styles
    file" (both columns), then ", {state}, {size}".
- Dynamic Type at `.accessibility1` and up (screen 7):
  - The label column goes away. Each weight label sits on its own line,
    leading-aligned (title3 for the name, body for the number), with its
    two cells side by side at half width below it. The headers sit at the
    top over the two columns.
  - Containers aren't drawn; every cell becomes a tile.
  - Single-style files keep their corner badge. For a multi-style file, the
    badge and size move into its column header, or into a strip line above
    the headers when the file covers both columns.
  - Cells, samples and badges scale through their `@ScaledMetric`s. Cells
    are about 76 pt tall at AX2.
- Contrast:
  - Label text on a tile: 18.3:1 light, 12.8:1 dark. On the selected
    fill: 15.5:1 light, 10.0:1 dark.
  - The tint ring against the tile or container: 3.5:1 in both modes,
    above the 3:1 needed for non-text elements.
  - Placeholders are decorative; the state is in the badge and the
    VoiceOver value.
- Colors are all semantic, so dark mode needs no extra values (screen 6).

---------------------------------------------------------------------------
## 8. States

- **Not downloaded:** placeholders and arrow badges (screens 1–3), with the
  Download button.
- **Downloading:** a spinner badge (Lato Light in screen 2, the strip in
  screen 5). Cells keep their placeholders; the controls show progress
  and Cancel, as today.
- **Downloaded:** real "Ag" samples and a check badge (screens 2, 3, 6).
  The controls show Downloaded and "Available in the app only", as today.
- **Unavailable:** a grey badge and faint placeholders. The button is
  disabled, and the reason plus "Choose another style or file." show
  under it.
- **Failed:** the badge goes back to the arrow. The error text shows under
  the button, with Try Again.
- **Cancelled:** "Download cancelled" and the Download button, as today.
- **No styles** (not in the catalog; guard only): hide the grid and show
  "No styles available." in footnote.

---------------------------------------------------------------------------
## 9. Review checks (I'll measure your screenshots against these)

1. Lato shows 9 rows × 2 tiles, each with its own corner badge. ABeeZee
   shows 1 row × 2 tiles.
2. Roboto shows exactly 2 badges (one per column header) and none in the
   cells. Commissioner shows exactly 1 badge, in the top strip.
3. Oswald shows one column, no empty Italic column, and the caption.
4. Downloaded cells draw "Ag" in the real face; you can see the weights get
   heavier down the rows. Cells that aren't downloaded show the textformat
   icon, never a system-font "Ag".
5. No synthetic styles: a family without Black shows no Black row; a
   missing italic leaves its slot empty.
6. Tapping a cell moves the ring and updates the name, file line, Download
   button and Preview below. Only one cell is ever selected.
7. Downloading the Roboto italic file turns every cell in that column to
   real samples together, and the button reads "Download File
   (18 Styles)".
8. Width menu: Roboto shows Normal and Condensed; switching keeps the same
   weight/italic. Recursive shows 4 variants with italics in the same set.
9. The fixtures in §1 pass as unit tests.
10. At AX2, weight names sit on their own line, nothing truncates and
    nothing scrolls sideways.
11. In dark mode, tiles and containers show and the ring is visible.
12. VoiceOver reads "Bold Italic, Not downloaded, selected"-style
    announcements, and skips empty slots and row labels.

---------------------------------------------------------------------------
## 10. Strings (final, Camo msg541)

- "Width", "Variant", "Normal", "Italic"
- "No italic styles in this family."
- "No styles available."
- File line in containers: "1 file · {n} styles · {size}"
- Shared-file sentence: "This file contains {n} styles. Downloading or
  removing it affects them all." Across sets: "This file contains {n}
  styles across {sets}. Downloading or removing it affects them all."
- "Download Style" (unchanged) / "Download File ({n} Styles)"
- Remove message for a shared file: "This removes all {n} styles in this
  file from Uniboard. You can download it again later."
- VoiceOver: "Not downloaded", "Downloading", "Downloaded" (unchanged);
  "File contains {n} styles"; "Normal styles file", "Italic styles file",
  "Shared styles file"
- Existing download states unchanged.
