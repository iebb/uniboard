# Uniboard 1.4 — Symbols page and row alignment

Design spec rev. 2 · Colo (@design) · 26 Oct 2026 (rev. 2: Camo's final copy msg835; Favorites ★ toggle behavior; Rows of Ten disclosure)
Source: user msg822 (screenshot of the Symbols page), Ato msg823 + msg830, Pluso's compatibility plan msg829 (`explicit-rows-compatibility.md`).
Mockups: artifact "Uniboard 1.4: Symbols page and row alignment", screens 1–9 (attached as PNGs).
All wording is final (Camo msg835, `symbols-row-alignment-copy.md`); §7 lists it. {limit} = 12.

Scope: (A) the page editor (`App/PageArrangeView.swift`, used by Symbols and every custom page; Favorites as noted), (B) per-row alignment on pages and on Main Keyboard's ABC section, in the editor and the keyboard, (C) the row-length limit and how overflow is handled. Storage, versioning and legacy rendering are Pluso's plan as Ato approved it (msg830); this spec only adds what people see.

---

## 1. Ato's decisions this spec follows (msg830)
- Left and Right are **physical** edges, the same for every language and layout; never leading/trailing.
- Spread keeps key widths and shares the spare width **between cells**; a row with one cell is centered.
- Favorites stays dynamic: **no alignment controls on Favorites in 1.4**. It keeps today's rows.
- Old layouts keep their exact appearance until someone edits them. Edited rows keep their membership and alignment on iPad too.
- Overflow must never wrap silently or make keys unusably small (§5).

---

## 2. Page editor layout (Symbols and custom pages)
Screens 2, 3, 6, 7. Top to bottom inside the existing ScrollView (padding 16, `systemGroupedBackground`):

1. **Helper** (new): "Tap a key to change its choices. Drag a key to move it." — `.footnote`, `.secondary`, 4 pt side inset, 10 pt above the canvas. Hidden when the page has no keys.
2. **Canvas** — the existing well (`tertiarySystemFill`, radius 12, padding 8), with the rows drawn in their alignment (§4.3).
3. **Overflow note**, only when a row is too long (§5.3).
4. **When nothing is selected:**
   - **Add card** (not on Favorites): §2.1.
   - **Alignment card, "All Rows"** (not on Favorites; hidden while the page has no keys): §4.1.
   - **Opens with ★ card** + footer: §2.2.
5. **When a key or gap is selected:**
   - **Alignment card, "Row n"** (not on Favorites): §4.1.
   - The existing `KeyLayersPanel` (swipe up / hold / swipe down), unchanged.
6. Error line (existing, unchanged).

Spacing: 16 pt between the canvas (or overflow note) and the first card, and 16 pt between cards; footers sit 6 pt under their card. The bottom control bar is unchanged.

### 2.1 Add card (fixes the wrapped button)
- Replaces the two side-by-side `.bordered` buttons. One card (`secondarySystemGroupedBackground`, radius 12) with **two full-width rows**:
  1. "Add from Unicode", SF Symbol `character.book.closed`. Opens the same `KeyboardKeyUnicodePicker` sheet.
  2. "Add Text", SF Symbol `character.cursor.ibeam` (was `plus`; this row now says what it adds). Opens the same "Add Text" alert.
- Each row: `Button` with `Label`, `.body`, accent color (icon and title), leading-aligned. Minimum height 52, horizontal padding 16, icon column 24 wide, 12 pt between icon and title. 0.5 pt separator between the rows, starting at the title (inset 52).
- **No wrapping:** `.lineLimit(1)` on both titles. Each row has the full card width (≈ 290 pt for text on iPhone 17 Pro; "Add from Unicode" needs ≈ 135 pt at the default size), so they stay on one line from xSmall through AX2. At AX3 and larger, let the title wrap (`lineLimit(2)`) rather than truncate, as accessibility sizes require. The two rows always share one width, so they can never look different from each other again.
- **Disabled** (store can't save, or 256 keys): both rows use the standard disabled look. At 256 keys, a footer under the card: "This page is full. Remove a key to add another."
- VoiceOver: the titles; identifiers unchanged (`page.addUnicode`, `page.addText`).

### 2.2 Opens with ★
- Same toggle and identifier (`page.star`), now a 52 pt row in its own card (padding 16), so it matches the Add card instead of being a third style. Accessible label: "Open this page with the star key".
- Footer (new), `.footnote`, `.secondary`, inset 16:
  - Symbols and custom pages: "When on, the ★ key opens this page instead of Favorites."
  - Favorites: "When on, the ★ key opens Favorites."
- **Favorites' switch can't be turned off from Favorites** (today turning it off sets Favorites again, so it snaps back). While Favorites is the ★ page, show the switch on and **disabled**, so it never looks like it works and then doesn't. When another page has ★, it's enabled and off; turning it on gives ★ back to Favorites. Other pages keep today's behavior (off gives ★ back to Favorites).

### 2.3 Empty page (screen 6)
- Instead of the bare "No keys yet." text, the canvas well itself holds the empty state at 140 pt tall, centered: "No keys yet" (`.headline`, `.secondary`) and "Choose characters from Unicode or add your own text." (`.subheadline`, `.secondary`).
- Favorites keeps its own line ("Save characters to add them here.") in the same placement.
- The Add card follows directly, then the ★ card. There is no alignment card and no helper line.

### 2.4 Favorites (screen 9)
- Same layout as §2, minus the Add card and the alignment card (Ato: deferred). The ★ card and footer appear as on other pages. Its ⋯ menu and list button are unchanged.

### 2.5 ⋯ menu
- Unchanged items. "Rows of Ten" now also resets every row's alignment to Left; it's enabled when the page has saved rows or any row isn't Left.
- Disclosure (Camo): the item gets a menu subtitle "Arranges keys in rows of ten and aligns all rows left." (`Button { } label: { Text("Rows of Ten"); Text(subtitle) }`). If the subtitle doesn't show in full on iPhone at the default text size, drop it and title the item "Rows of Ten, Align Left" instead.

---

## 3. Alignment values

| Value | Shown name | SF Symbol | Free space goes |
|---|---|---|---|
| left | Left | `align.horizontal.left` | after the last cell |
| center | Center | `align.horizontal.center` | half before the first cell, half after the last |
| right | Right | `align.horizontal.right` | before the first cell |
| spread | Spread | `distribute.horizontal.center` | first cell at the left edge, last at the right edge, the rest shared equally between neighboring cells; a one-cell row is centered |

- A **cell** is anything in the row: a key, a half gap, a full gap, or (Main Keyboard) a function key. Gaps keep their width and count as cells in Spread (screen 4).
- Key widths never change with alignment. The minimum space between cells is today's spacing (5 pt iPhone, 7 pt iPad on pages; Main Keyboard's current spacing). Spread only adds to it.
- A full row (no spare width) looks the same in all four.
- **Defaults** (old data and anything new): page rows **Left** (today's look); Main Keyboard rows **Center** (today's custom look). The stock Main Keyboard arrangement keeps its legacy drawing until an edit makes it explicit (Pluso's plan); the card shows it as "Center".
- New Row: the new row gets the alignment of the row it was split from. Join Rows: the joined row keeps the upper row's alignment. A row that appears because keys were added past the last row gets the alignment of the row above it.

---

## 4. Alignment control

### 4.1 The alignment card (screens 2, 3, 5, 7)
- A card (`secondarySystemGroupedBackground`, radius 12, padding 12):
  - **Header line:** leading title, trailing current value. Title `.subheadline` semibold, primary: "All Rows" when nothing is selected, "Row 3" when an item in row 3 is selected. Value `.subheadline`, `.secondary`: the shown name from §3, or "Mixed" for All Rows when rows differ.
  - **Segmented Picker** (`.pickerStyle(.segmented)`), full width, 8 pt under the header, four segments with the SF Symbols from §3 (images only, `.imageScale(.medium)`).
- **All Rows** (nothing selected): selection = the shared value, or none when rows differ (bind an optional, so no segment is highlighted). Choosing a segment sets every row. Footer: "Select a key to align only its row."
- **Row n** (a key or gap selected): sets only that row. No footer.
- **Applying:** immediately, saved through the same store call as a move, with the existing `.editorReorder` animation (no movement with Reduce Motion). A failed save leaves the old alignment and shows the existing error line. No haptic.
- **VoiceOver:** the Picker label is "Alignment for all rows" / "Alignment for row 3"; each segment's label is its shown name ("Left", "Center", "Right", "Spread"), with hints "Aligns to the left edge", "Centers the row", "Aligns to the right edge", "Distributes extra space between keys and gaps". The selected segment carries the selected trait (system). With "Mixed" no segment is selected; VoiceOver value "Mixed".
- Identifiers: `arrange.alignment` (card), segments `arrange.alignment.left|center|right|spread`.

### 4.2 Selected-row band (screen 3, 5)
- While an item is selected, its row gets a band behind it: `RoundedRectangle(cornerRadius: 10)`, accent at 12% opacity (dark 22%), spanning the well's full inner width, 3 pt above and below the keys. It shows which row "Row n" means and makes its free space visible.
- Hidden while a drag is in progress. Not an accessibility element.

### 4.3 Drawing rows (editor and keyboard alike)
- Rows are aligned within the **full inner width** of the well (editor) or the page area (keyboard), so Center is truly centered.
  - Today the editor reserves a 12 pt end-of-row drop target plus spacing (17 pt) at the right of every row. With alignment that would push Center 8.5 pt left and stop Right short of the edge. Draw that target as an overlay after the row's last cell (or over the well's trailing padding for a full row) so it takes no width.
- Positions are rounded to whole pixels; widths are not.
- Taps in the spare space do nothing (the same as a gap today).
- The keyboard draws exactly what the editor shows: same row membership, order, gaps and alignment.

### 4.4 Main Keyboard (ABC section only, screen 5)
- The same card sits under the canvas: "All Rows" when nothing is selected, "Row n" above the layers panel when a key (letters, Shift, Delete, Tab, Caps) or gap is selected.
- 123 and #+= show no alignment card: their rows are fixed.
- Changing alignment on the stock arrangement saves it as an explicit arrangement, the same way the first move does today. "Standard Layout" and "Restore All Key Defaults" (⋯) also reset alignment to the default.

---

## 5. Row length and overflow (Ato: no silent wrapping, no unusably small keys)

### 5.1 The limit
- A row holds at most **12 key widths**. Counting: key 1, full gap 1, half gap 0.5, Main Keyboard function key 1.5 (as its width rule already counts).
- Why 12: rows are shared between devices, so the narrowest supported keyboard decides. On a 375 pt iPhone (SE, mini), 12 keys with 5 pt spacing are ≈ 26 pt wide. That's the width iOS's own 12-key rows use (for example Ukrainian). At 13 or more they fall below 25 pt, and at today's 16 they are under 20 pt.
- 1.3 allowed 16 per row; the 12 limit applies to edits made in 1.4.

### 5.2 How edits respect it (nothing wraps, ever)
- Moves, drops, gap inserts and Join Rows that would take a row past 12 are **refused**. The control is disabled, and a drag shows no insertion mark there (the existing `accepts` path). Nothing jumps to another row. If the editor explains a refusal (for example as a disabled control's VoiceOver hint), the text is "This would make the row too wide. Move keys or remove gaps first."
- Adding keys keeps today's rule (the last row while it has room, otherwise a new row). A new row is made only by the add action itself, never by re-flowing existing rows.
- New-format imports with a row over 12 are rejected by Validate: "{page name}, row {n}: This row exceeds the limit of 12 standard-key widths. Move keys or remove gaps before applying." (Main Keyboard: "{layout name}, row {n}: …"). Old-format imports keep loading as before (Pluso's legacy adapter) and never get this error.
- Export of the new format, if a note is shown: "This configuration uses saved rows and alignment. Import it with a version of Uniboard that supports this format."

### 5.3 Rows already longer than 12 (only from data saved before 1.4) — screen 8
- **Keyboard:** drawn exactly as before (legacy appearance, per Ato). The keys get narrower, but nothing wraps and nothing is cut off.
- **Editor:**
  - The row gets a 1.5 pt dashed `systemOrange` outline (radius 10, same frame as the selection band).
  - An overflow note goes under the canvas: SF Symbol `exclamationmark.triangle.fill` in `systemOrange`, then `.footnote` `.secondary` text. One row: "Row {n} is wider than the current limit of 12 standard-key widths. Its saved arrangement is kept. Move keys or remove gaps to shorten the row." Several rows: "Rows {row list} are wider than the current limit of 12 standard-key widths. Their saved arrangements are kept. Move keys or remove gaps to shorten them." (row list via `ListFormatter`). Optional second line: "Wide keys and gaps count toward the limit."
  - Edits that shorten that row are allowed; edits that lengthen it are refused (§5.2). The outline and note disappear as soon as every row fits.
  - VoiceOver: the note is read in order after the canvas, and the row's keys get the value suffix "Row too wide".

---

## 6. Dark mode check (existing, measure before shipping)
- If the page key tiles still use `secondarySystemGroupedBackground` on the `tertiarySystemFill` well, in dark they are #1C1C1E on ≈ #1C1C1F and nearly vanish. If the screenshot shows that, use `systemGray3` (#48484A) for page key tiles in dark only; light stays white. Main Keyboard's canvas uses the same tile code, so check it too.

---

## 7. Strings (final, Camo msg835)
The full list, including the optional help text, is in Camo's `symbols-row-alignment-copy.md` (attached to msg835). Every string in this spec is quoted from it, with {limit} = 12. Existing strings are unchanged: "Add from Unicode", "Add Text", "Opens with ★", "Rows of Ten" and "Save characters to add them here."

---

## 8. Review checks (Pluso's screenshots; iPhone 17 Pro unless noted)
1. Symbols, nothing selected, default and AX2: "Add from Unicode" and "Add Text" are each one line in rows of equal height (52 pt); at AX5 they wrap rather than truncate.
2. Symbols, nothing selected: helper, canvas, Add card, All Rows (Left), ★ card + footer, in that order with 16 pt gaps.
3. Select "|" → card reads "Row 3", band behind row 3; tap Center → the four keys sit centered within the well's inner width ±1 pt; the real keyboard's Symbols page matches.
4. Each alignment on a 4-key row matches screen 4: Right touches the inner right edge; Spread puts the first and last keys at the edges with equal spaces ±1 pt; Spread with one key is centered; a full gap counts as a cell.
5. All Rows with mixed rows shows "Mixed" and no segment; choosing one sets every row.
6. New Row / Join Rows / adding a key: alignment is inherited as in §3.
7. A row at 12 widths refuses Move Up/Down into it, gap inserts and drops (controls disabled, no insertion mark).
8. A 1.3 page with a 14-key row: the keyboard looks the same as in 1.3, and the editor shows the orange outline and the "Row 2 is wider than…" note; moving 2 keys out clears both.
9. Main Keyboard ABC: the card appears under the canvas; row 3 Left matches screen 5 in the editor and the keyboard. 123 and #+= have no card. Standard Layout resets alignment.
10. Favorites: no Add card, no alignment card; the ★ card reads "When on, the ★ key opens Favorites.", and its switch is on and disabled while Favorites has ★; saving a new favorite still appears in the keyboard.
11. iPad: a page edited on iPhone shows the same rows and alignment on iPad (Ato msg830).
12. Dark mode screenshots of screens 2 and 3 (and §6 check).
13. VoiceOver: segments read "Left / Center / Right / Spread"; the picker label names the row; the overflow note is reachable after the canvas.
14. ⋯ on a page: "Rows of Ten" shows its subtitle in full (or reads "Rows of Ten, Align Left").
