# Uniboard 1.4 — Styles grid: widths as columns, single-style downloads

Owner: Colo (design) · Status: rev. 3, 2026-10-25 (rev. 3: Ato's font decisions msg784 + final 1.4 brief msg799: option B, and adding a shared file never removes existing downloads; Camo's amendment msg794. rev. 2: Camo's 1.4 wording, msg674) · For: Pluso (build), Ato (scope), Camo (strings)
Release: **1.4 only.** Nothing here touches the 1.3 build or its review.
Base: the 1.3 spec `deliverables/uniboard/styles-grid/design.md` (rev. 2). Everything this file
does not mention stays exactly as in 1.3 (colors, fonts, cell size, selection, samples, states).
Inputs: user msg652, Ato msg653, Pluso's research msg658 (`uniboard-1.4-weight-downloads.md`),
Ato msg784 + final brief msg799 (font section), Camo msg794 "Font policy amendment".
Mockups: artifact "Uniboard 1.4 — styles grid with widths as columns"
(https://airbuild.page/7d1f561f-d707-4212-92b9-ed09acc577e2), screens 1–6 attached as PNGs.
Screens are drawn at 402 pt (iPhone 17 Pro).

Screens:
1. Roboto, light: 2 files, 4 columns, fit without scrolling; Bold downloaded on its own; Condensed Bold selected.
2. Inconsolata, light: 9 widths, columns scroll; every style also has its own file.
3. Noto Sans Display, dark: 8 columns, scroll; the selected style only comes in the shared file.
4. Lato, light: one width (1.3 layout); all 16 font-file spaces in use.
5. Roboto at AX2: stacked layout.
6. Roboto, light (new in rev. 3): the upright shared file downloaded while the separate Bold file
   was already there; both kept, Bold selected.

---------------------------------------------------------------------------
## 0. What changes from 1.3 (one line each)

1. The Width menu is removed. Every width becomes a column (§2).
2. Rows are the weights that exist in any visible column (§3).
3. Too many columns scroll sideways; weight names stay pinned (§4).
4. Tiles lose the "not downloaded" arrow; the arrow stays only on a shared file's line (§5).
5. A style with a file of its own downloads alone; a shared file is always labeled as a file (§6).
6. The section footer says how many more font files fit (§7).
7. Downloading a shared file never removes separate downloads. Both stay, and the style is
   shown once with both files listed (§8, decided by Ato msg784).

**Download source: option B (decided, Ato msg784 / brief msg799).** A style gets a
"Download {name}" button only when there is a pinned, verified single-style file whose
version and character coverage match the shared file. Static families keep their original
files (also "own files"). Any style without a verified own file behaves like screen 3:
only "Download File ({n} Styles)". The layout does not change either way.

---------------------------------------------------------------------------
## 1. Words used here

- **Group:** Normal (upright) or Italic. Same headers as 1.3.
- **Width column:** one width inside a group (Standard, Condensed, …).
- **Own file:** a file that holds only this one style (a static file, or a single-style
  download from option B).
- **Shared file:** a file that holds more than one style (variable files, 6 legacy VF statics).
- **{n} styles:** the number of distinct cells the file fills, after the 1.3 duplicate rule
  (same file + same instance coordinates = one). Inconsolata's variable file has 74 named
  instances but 2 repeat (Regular, Bold), so {n} = 72, not 74. This changes the 1.3 count,
  which counted raw catalog styles.

---------------------------------------------------------------------------
## 2. Columns

- **Top level = group** (Normal, then Italic). Reason: Google splits files by slope, never by
  width, so one file's container stays one unbroken block (Roboto, Noto Sans Display).
- **Inside each group, one column per width** that group has, in this order: Standard
  (wdth 100) first, then narrowest to widest. Reason: the width people use most sits next to
  the weight names and is never scrolled away; it is also the 1.3 menu order the user knows.
  - Inconsolata: Standard, Ultra Condensed, Extra Condensed, Condensed, Semi Condensed,
    Semi Expanded, Expanded, Extra Expanded, Ultra Expanded.
- A group appears only if it has at least one cell; a width column only if that group has at
  least one cell in that width. The two groups may have different column counts.
- No italics anywhere in the family: Italic group hidden, plus the 1.3 caption
  "No italic styles in this family." under the grid (screen 2).
- **Header rows**, top to bottom:
  - A. Group title "Normal" / "Italic": footnote 13 pt semibold, `.secondary`. Height 22 pt.
  - B. File line, only if at least one group is covered by a shared file: badge + size,
    caption 12 pt, `.secondary`. Height 18 pt. (1.3 §4 content, unchanged.)
  - C. Width name, only when the visible set has more than one width: caption2 11 pt
    semibold, **Color(.label)**, centered over its column, max 2 lines, the break before the
    last word ("Semi⏎Condensed", "Ultra⏎Expanded"; one-word names stay on one line).
    Height 32 pt. `minimumScaleFactor(0.85)`. Reason for full label color: it is the only
    on-screen cue for which width a column is, and 11 pt text needs 4.5:1; `.secondary`
    measures 3.3:1 on the container.
  - Width name text: 1.3 `widthName` ("Semi Condensed"). wdth 100 is "Standard"
    (placeholder, Camo to confirm, see §11).
- **Single-width families** (most of the catalog) get no row C, so their grid is the 1.3 grid.
- **Variant menu:** kept only for families whose sets differ by something other than width
  (Recursive's Mono/Sans and Linear/Casual, optical sizes). Title "Variant"; the options
  never contain width words; inside each option, widths are columns as above. If sets differ
  only by width there is no menu. The title "Width" is no longer used.

---------------------------------------------------------------------------
## 3. Rows

- One row per weight that has a cell in **any** visible column, lightest first. A weight that
  exists only in Condensed still gets a row; its Standard slot stays empty.
- Empty slot: no tile, no text, no VoiceOver element (1.3 rule).
- Row label column, 48 pt row height, 6 pt row spacing: unchanged from 1.3.

---------------------------------------------------------------------------
## 4. Fit or scroll

Let A = row width − 24 (12 pt insets) − 84 (label column) − 8 (gap).
n = number of width columns across both groups; g = number of groups (1 or 2).

- **Fit** when n × 60 + (g − 1) × 8 ≤ A. Columns share A equally (screen 1).
  - 402 pt screen: A = 254. Roboto (n 4, g 2) needs 248 → fits, columns 61.5 pt.
  - 440 pt screen: A = 292. Five columns would need 308 → scroll.
  - 375 pt screen (SE): A = 227. Roboto needs 248 → scrolls (about 21 pt hidden).
  - n = 2 (every 1.3 family): unchanged, 123 pt columns on 402 pt.
- **Scroll** otherwise (screens 2, 3):
  - The label column is pinned, outside the scroll view. The columns sit in a horizontal
    `ScrollView` that starts 8 pt after the labels and runs to the card's trailing edge
    (no trailing inset), so the next column visibly peeks in.
  - Every column is 60 pt wide. 8 pt between groups, 0 between columns of a container
    group, 6 pt between tile columns (groups with no container).
  - Fade: a 22 pt linear mask on the trailing edge while more content lies there, and on
    the leading edge once scrolled. Horizontal indicator `.visible`.
  - Group title and file line: leading-aligned with a 10 pt inset, and pinned to the
    visible leading edge of their group while any of the group is visible, so the file state
    never scrolls away. iOS 17 target: read the group's frame with a GeometryReader in a
    named coordinate space of the ScrollView; x-offset = clamp(−groupMinX, 0,
    groupWidth − titleWidth − 10). In fit mode they are centered (1.3).
  - Opening: if the selected cell's column isn't fully visible, scroll it to the center,
    without animation, on first appearance only. Never move the scroll when the selection
    changes by tap.
  - Scrolling is horizontal only; the list keeps vertical scrolling. Use
    `.scrollBounceBehavior(.basedOnSize, axes: .horizontal)`.

---------------------------------------------------------------------------
## 5. Files, containers and badges

- **Containers (1.3 §4) span all width columns of the group a shared file covers.**
  - A file covering one group → one container over that group's columns (Roboto: two).
  - A file covering both groups (Commissioner, Encode Sans) → one container over both, with
    the 1.3 strip "1 file · {n} styles · {size}"; in scroll mode the strip is pinned like
    the titles.
  - A file covering some other shape (legacy VF files): no container; §6 text explains it.
  - Cells inside a container have no fill; side inset 2 pt (was 4) because columns can be
    60 pt.
- **Tile corner badge — new rule:** a cell shows a corner badge only for its **own file**, and
  only when that file is:
  - downloading: `ProgressView().controlSize(.small)`, tint, 13 pt;
  - downloaded: `checkmark.circle.fill`, tint, 15 pt;
  - unavailable: `exclamationmark.circle`, secondaryLabel, 15 pt.
  - Not downloaded (and failed, cancelled): **no badge**. Reason: with up to 8 columns an
    arrow on every tile is noise, and the plain placeholder icon already says "not
    downloaded". The arrow stays on the file line, where it marks one download that covers
    many styles. This also applies to single-width families (Lato loses its arrows, screen 4).
- A cell can have both: its own downloaded file (corner check) inside a container whose
  shared file is not downloaded (Roboto Bold, screen 1).
- **Sample:** "Ag" in the real face when either its own file or a covering shared file is
  downloaded (1.3 §5 rules; same face either way). Otherwise the placeholder.
- Badge inset 4 pt from the tile's top-trailing corner; in a container the cell's frame is the
  tile.

---------------------------------------------------------------------------
## 6. Selected style block (under the grid)

**Row 1:**
- Name: width name (not for Standard) + weight name + " Italic"; "Regular Italic" → "Italic".
  Examples: "Condensed Bold", "Semi Condensed SemiBold", "Bold Italic". Body, label.
- Line 2: "{file name} · {size}" of the smallest file that gives this style: its own file
  if it has one, else the shared file. Caption 12 pt, secondaryLabel, selectable.
- Line 3, only when the style has **no** own file and its file is shared: footnote 13 pt,
  secondaryLabel: "This style is available here in a file containing {n} styles.
  Downloading or removing the file affects them all." (screen 3)

**Action rows** (one list row each, 44 pt min). Title in tint, body 17 pt; size trailing in
body, secondaryLabel, `.monospacedDigit()`. The trailing size is part of the button's hit area.

| Case | Rows |
|---|---|
| A. Own file, not downloaded, also in a shared file (screens 1, 2) | 1. "Download {name}" · own size. 2. "Download File ({n} Styles)" · shared size, with a caption under the title: "Includes {n} styles in one file." followed by " Existing downloads are kept." when at least one style the file covers already has its own downloaded file (screens 1, 2); and, when the file spans more than one width, a second line naming its coverage: "Normal styles in Standard and Condensed widths." |
| A2. Own file only (static family, screen 4) | "Download {name}" · size. |
| B. Shared file only (screen 3) | "Download File ({n} Styles)" · size. Never the style's name. |
| C. Downloading | 1.3 progress row + Cancel. The progress text names what downloads: "Downloading Condensed Bold… 64%" or "Downloading file ({n} styles)… 64%". |
| D. Downloaded via own file | 1.3 downloaded rows (keep the 1.3 App Only / Keyboard Unverified rule; never say "Available in the app only" just because the keyboard hasn't confirmed it), then "Remove Download" (destructive, 1.3 action; the confirmation names the style). If a shared file also covers it, the "Download File ({n} Styles)" row stays. |
| E. Downloaded via shared file only | 1.3 downloaded rows; Remove uses the 1.3 shared-file dialog. No single download offered (it would add a file and show nothing new). |
| G. Own file and shared file both downloaded (screen 6) | Line 2 lists both files, smallest first, one per line: "{file} · {size}". 1.3 downloaded rows once (not per file). Then "Remove Download" · own size (removes the separate file only) and "Remove File ({n} Styles)" · shared size (removes the shared file only). Both destructive, 1.3 confirmation style; each confirmation uses Camo's "This removes the downloaded file. Styles available from other files will stay available." because the other file still supplies the style. |
| F. No room for another font file | All Download rows `.disabled(true)` (title and size go tertiaryLabel); footer changes (§7). Remove rows stay enabled. Nothing is ever removed to make room. |

- Order is always: the single style first (it is what was tapped), the whole file second.
- Every Download row downloads exactly one file, and shows before the tap what it covers (its
  title and caption), its exact size (trailing) and that it is one file (single style: one
  style = one file; shared: "…in one file."). The footer shows how many file spaces remain.
- Unavailable, failed, cancelled, Try Again: as 1.3.

---------------------------------------------------------------------------
## 7. Font file capacity footer

The Styles section footer (replacing the 1.3 limits text there):
- Free > 1: "Room for {free} more font files. Each file counts once, whether it contains one
  style or several."
- Free = 1: "Room for 1 more font file. Each file counts once, whether it contains one style
  or several."
- Free = 0: "All 16 font-file spaces are in use. Remove a font file here or in Font Downloads
  to make room." The limit stays 16 (Ato msg784). No file is removed automatically.
- Keep the 1.3 sentence about the 40 MiB per-file limit after it.
- {free} counts imported, installed and downloaded files, exactly the existing 16-file check.
  If the limit changes, the 16 in the copy follows it.
- Reason: once single styles can be downloaded, the file count is the real cost of each
  choice, so it is shown where the choice is made.

---------------------------------------------------------------------------
## 8. Overlapping files (decided, Ato msg784 and brief msg799)

- Downloading a shared file **never** removes, replaces or rewrites separate downloads it
  covers, and a separate download never removes a shared file. Both stay until the person
  removes one.
- The capacity check counts the shared file as +1, always. If there is no room, Download is
  disabled and the footer explains how to make room (§7); nothing is evicted.
- **Shown once:** a style supplied by two downloaded files is one cell in the grid (own-file
  corner check + the group's file-line check), one entry in the font picker and rule picker,
  and one set of downloaded rows (case G). Font Downloads still lists each file, since each
  takes a space.
- Which file draws it: the own file (smaller, loads faster). Option B guarantees the same
  face. Removing either file leaves the style available from the other, with no change to
  font rules or the configuration file: saved references are never rewritten. (Pluso: if a
  reference can point at a specific file, it must keep resolving to the remaining file.)
- No replacement or "frees space" wording anywhere (Camo msg794).

---------------------------------------------------------------------------
## 9. Accessibility

- **VoiceOver cell:** label = the §6 name ("Condensed Bold Italic"). Value = state, then
  ", Separate file, {size}" or ", File contains {n} styles". Selected cell: `.isSelected`;
  the download state stays in the value, independent of selection.
- Order: group header elements first (each title + file line is one element: "Normal styles
  file, not downloaded, 489 KB"), then row by row, left to right (Normal columns, then
  Italic columns), then the selected block. File line element: "{group} styles, 1 file, {n}
  styles, {size}" ("Shared styles file, …" when it crosses groups). Width headers are hidden
  (the cell labels carry width); if they are ever exposed, read them as "Standard width,
  Normal" / "Condensed width, Italic". Row labels are hidden as in 1.3.
- In scroll mode, moving VoiceOver focus to an off-screen cell scrolls it into view (system
  ScrollView behavior; check it works with the pinned labels).
- **AX1 and larger (screen 5):** no horizontal scrolling.
  - The file lines go first, one per shared file: badge + "{group} styles: 1 file · {n}
    styles · {size}" (body, secondaryLabel).
  - Then each weight on its own line (title3 name, body number, 1.3), and its cells below,
    two per line, in column order (Standard, Condensed, Standard Italic, Condensed Italic …).
  - Each tile shows its column name inside, top-leading (subheadline semibold,
    secondaryLabel), above the sample, because there are no column headers.
  - Every cell is a tile (no containers), about 100 pt tall at AX2 via the 1.3 scaled
    metrics.
- **Contrast:** width names (label color) 18:1 light, 13:1 dark on the container. Everything
  else uses the 1.3 semantic colors and values. Dark mode needs no new colors (screen 3).
- Hit area: every cell at least 48 × 48 pt; at 60 pt columns the cell is 56 × 48.

---------------------------------------------------------------------------
## 10. Review checks (I'll measure your screenshots against these)

1. Roboto on 402 pt: 4 columns, no horizontal scroll; order Standard, Condensed under each group.
2. Roboto on a 375 pt simulator: scrolls; the weight names don't move.
3. Inconsolata: 9 columns, Standard first, the next column visibly cut at the trailing edge,
   "Normal" and the file size stay visible while scrolling.
4. No arrow on any tile in any family; arrows only on file lines.
5. Roboto Condensed Bold (option B): "Download Condensed Bold" first, "Download File (18
   Styles)" second; Noto Sans Display Semi Condensed SemiBold: one row "Download File (36
   Styles)". No button anywhere names a style whose bytes come from a shared file, and no
   button says "Download All".
6. Inconsolata's file says 72 styles, not 74.
7. Footer "Room for {free} more font files" matches the real 16-file check (singular at 1); at 0 all Download rows are disabled.
8. Single-width families (Lato, ABeeZee, Oswald) match their 1.3 screenshots except the
   missing arrows and the footer.
9. AX2: no horizontal scroll, column names inside tiles.
10. Dark mode: width names white, tint buttons #0A84FF (system).
11. Roboto with Bold downloaded alone, then the upright file downloaded: Bold's own file is
    still there, the footer drops by exactly 1, Bold shows once with both files listed and two
    Remove rows (screen 6). Remove either: Bold still draws in the grid, app and keyboard, and
    the configuration file and font rules are byte-for-byte unchanged.
12. With 15 of 16 spaces used and Bold downloaded alone, "Download File (18 Styles)" works and
    leaves 0 free; nothing is removed. At 16 it is disabled.

---------------------------------------------------------------------------
## 11. Strings (final, Camo msg674 — `styles-grid-1.4-copy.md` — plus her msg794 amendment)

Camo's file is the source; this list is the part the screens use.
- Groups "Normal" / "Italic" (1.3); widths "Standard" (wdth 100), "Condensed",
  "Semi Condensed", … (1.3 `widthName`). "Variant" kept for non-width sets. "Width" dropped.
- Single-style file: "Download {name}" ({name} includes width, weight and italic).
- Shared file (primary or secondary): "Download File ({n} Styles)". Never "Download All".
- Caption under the shared-file row: "Includes {n} styles in one file." + " Existing downloads
  are kept." when a covered style already has its own download (Camo msg794) + optional line
  "{group} styles in {widths} widths." (e.g. "Normal styles in Standard and Condensed widths.").
- No single-style download: "This style is available here in a file containing {n} styles.
  Downloading or removing the file affects them all."
- Progress: "Downloading {name}… {p}%" / "Downloading file ({n} styles)… {p}%".
- Remove: "Remove Download" (1.3). Shared confirmation: "This removes all {n} styles in this
  file from Uniboard. You can download it again later." If other kept files still supply some
  of them: "This removes the downloaded file. Styles available from other files will stay
  available."
- Capacity: "Room for {free} more font files. Each file counts once, whether it contains one
  style or several." / singular "Room for 1 more font file. …" / full "All 16 font-file
  spaces are in use. Remove a font file here or in Font Downloads to make room."
- File line (visible): "1 file · {n} styles · {size}" (1.3). AX file line: "{group} styles:
  1 file · {n} styles · {size}".
- VoiceOver: "Separate file, {size}" / "File contains {n} styles" / "{group} styles, 1 file,
  {n} styles, {size}" / "Shared styles file".
- Remove the shared file while an own file also exists (case G): "Remove File ({n} Styles)"
  (placeholder, Camo to confirm; matches "Download File ({n} Styles)").
- No replacement or freeing-space wording (Camo msg794).
- Kept from 1.3: "No italic styles in this family.", the 1.3 remove dialog title.

---------------------------------------------------------------------------
## 12. Where it lands in code (from Pluso's research; not prescriptive)

- `Shared/StyleGrid.swift`: `Row` holds cells per (width, italic); sets lose width from their
  key; `menuTitle` only for non-width variants; {n} counts distinct cells.
- `App/StyleGridView.swift`: fit/scroll layout, pinned labels and group titles, containers
  over width spans, new badge rule, AX layout.
- `App/FontFaceDetailView.swift`: remove the Width picker; the action rows in §6; footer §7.
- Download and storage follow option B: pinned, versioned, hash-checked single-style files
  only where version and coverage match; otherwise the shared file. No runtime CSS API call,
  no embedded key. Privacy/Support must name the new font host before shipping (Leto).
