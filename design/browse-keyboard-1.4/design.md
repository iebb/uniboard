# Uniboard 1.4 — Emoji categories and size, block sorting, Main Keyboard consolidation, new layouts

Design spec rev. 4 · Colo (@design) · 25 Oct 2026 (rev. 4: number row on ABC only, §6.3, user msg949 / Ato msg950; §7.3 hold callout center-out, msg919. rev. 3: Ato msg812 — Armenian deferred; Arabic diacritics key in Shift's slot; layout-only punctuation hold choices; Camo addendum msg814 + msg819. rev. 2: Camo msg797 strings; Explore's navigator follows Explore's order, Ato msg799)
Inputs: user msg781 · Ato brief msg789 + decisions msg792 · Pluso audit msg790 (uniboard-1.4-audit.md) · Camo final strings msg794 (browsing-keyboard-1.4-copy.md, "Confirmed scope and final strings") + msg797 addendum (browsing-keyboard-1.4-copy-addendum.md).
Base: master d3f76b0 (1.3 build 52). 1.4 work only; nothing here touches the 1.3 submission.
The font styles grid is a separate spec (styles-grid-1.4/design.md rev. 3).

Visual language is unchanged: system semantic colors, system blue accent, SF Pro + SF Symbols, 16 pt screen margins, 12 pt card radius, 8 pt grid spacing, inset grouped lists. No new assets. Every string in "quotes" is Camo's final wording.

---

## 1. Emoji screen

### 1.1 Toolbar (trailing, left to right)
1. **Emoji Categories button**: SF Symbol `line.3.horizontal.decrease.circle`. When any category is hidden it becomes `line.3.horizontal.decrease.circle.fill`, so the filtered state shows even when scrolled. Tap opens the Emoji Categories sheet (§2).
   Accessibility label "Emoji Categories"; value "All categories shown" / "{shown} of {total} categories shown" (locale-aware numbers; total from the catalog). id `emojiCategories`.
2. **View options menu** (replaces the 1.3 Order menu; its icon changes from `arrow.up.arrow.down` to `ellipsis.circle`, because the menu now holds size as well as order). Accessibility label "View Options", id `emojiViewOptions` (keep `emojiOrder` on the picker).
   - Section 1, header "Emoji Size": a `ControlGroup` labelled "Emoji Size". iOS draws it as two side-by-side buttons at the top of the menu: "Smaller" (`minus.magnifyingglass`) and "Larger" (`plus.magnifyingglass`). Add `.menuActionDismissBehavior(.disabled)` to both, so the menu stays open and the grid visibly resizes behind it. Disable each button at its limit. VoiceOver labels: "Decrease emoji size" and "Increase emoji size".
   - Section 2: the existing "Order" picker (Newest first / Oldest first / Code point), inline, unchanged.
   Why the visible control: pinch can't be seen, and people using Switch Control or Voice Control can't pinch. The menu gives everyone the same steps.

### 1.2 Content order (ScrollView, VStack spacing 16, unchanged padding)
Search bar → Unicode version control (unchanged) → **filter row (only when ≥ 1 category is hidden)** → grid / empty state → the existing footnote, now opening with "Pinch to change emoji size." (§9).

### 1.3 Filter row (visible active-filter state)
- Card: `Color.groupedSurface` (white in light mode, #1C1C1E in dark), radius 12 continuous, padding 12 horizontal, minimum height 44.
- HStack spacing 8:
  - Leading button, which opens the sheet: `line.3.horizontal.decrease.circle.fill` (subheadline, accent), then "{shown} of {total} categories shown" (subheadline, `.primary`).
  - Spacer(minLength 8).
  - Trailing button: "Show All" (subheadline semibold, accent, borderless), with a 44 × 44 hit area.
- At accessibility text sizes, use ViewThatFits: the text wraps, and "Show All" moves to its own line below it, leading-aligned.
- VoiceOver: two elements. "{shown} of {total} categories shown" with the hint "Opens Emoji Categories", then "Show All".

### 1.4 Grid states
| State | What shows |
|---|---|
| All shown, browsing or search with results | grid exactly as today (no filter row) |
| Some hidden, browsing | filter row + grid of visible categories only |
| Some hidden, search with results | filter row + only matches from visible categories |
| Some hidden, search with no visible matches | filter row + `ContentUnavailableView`: symbol `face.smiling`, "No matching emoji in the categories shown" / "Try another search or show more categories." + button "Choose Categories" (`.bordered`, opens the sheet) |
| Nothing hidden, search with no matches | today's "No Matching Emoji" copy, unchanged |
| All hidden, browsing or searching | filter row ("0 of 9…") + `ContentUnavailableView`: symbol `line.3.horizontal.decrease.circle`, "No emoji categories shown" / "Choose at least one category to see emoji." + button "Choose Categories" |
| Catalog failed to load | unchanged from 1.3 |

Filtering happens **inside** the catalog query (`entries(limit:order:)` and `search(_:limit:order:)`), before paging. That way a page of 120 is always 120 visible emoji, and the end-of-grid trigger keeps firing. Never filter a page after it is fetched.

### 1.5 What the category setting affects
- **Affected:** the Emoji tab grid and its search; the keyboard's Emojis section grid and its emoji search (§4).
- **Not affected:** Saved/Favorites, keyboard pages, Recent, What's New, emoji detail, configuration export of favorites. Hidden emoji stay saved and stay insertable from those places.

---

## 2. Emoji Categories sheet

- `.sheet` with a NavigationStack, `presentationDetents([.large])`, visible drag indicator.
- Inline title "Emoji Categories". Trailing `confirmationAction` button "Done" (bold).
- **Changes apply immediately** (each switch writes the shared preference at once, and the grid behind updates live). Done and swipe-down both just close the sheet. There's no Apply, no Cancel and no staged copy: every change is one tap to undo, and live feedback is the point.

List, `.insetGrouped`:

**Section 1: one row per category**, in the catalog's CLDR group order (as stored in the JSON). Today that is Smileys & Emotion, People & Body, Animals & Nature, Food & Drink, Travel & Places, Activities, Objects, Symbols, Flags. Rows come from the catalog, never from a hard-coded list, so a future group appears automatically (shown by default).
- Row, minimum height 52: HStack spacing 12:
  - Sample tile: 36 × 36, radius 8, `tertiarySystemFill`, emoji at 22 pt. This matches the Blocks list rows.
  - VStack(alignment .leading, spacing 2):
    - category name (body)
    - "{n} emoji" ("1 emoji", "0 emoji"; footnote, secondary, monospaced digits; counts entries/sequences, not code points). The count is for the selected Unicode version, so it's what the grid would show.
  - Spacer, then a `Toggle`. Leave it untinted: the system green is the native switch.
- Sample emoji (fixed, all Emoji 1.0, so present in every edition):
  - 😀 U+1F600 Smileys & Emotion
  - 👋 U+1F44B People & Body
  - 🐶 U+1F436 Animals & Nature
  - 🍎 U+1F34E Food & Drink
  - 🚗 U+1F697 Travel & Places
  - ⚽ U+26BD Activities
  - 💡 U+1F4A1 Objects
  - 🔣 U+1F523 Symbols
  - 🏁 U+1F3C1 Flags
  - Any other group uses its first entry in catalog order.
  - Why these and not the CLDR first entries: 🏧 and 👓 don't read as their category.
- Footer: "Choose which categories appear in the app and keyboard, including emoji search." Then on a new line "Hidden categories aren't deleted from your saved pages or favorites.", **only once Pluso has verified it**.
- VoiceOver: each toggle reads "{name}, {n} emoji", with the hint "Show this category" and the system On/Off value. The sample tile is hidden from VoiceOver.

**Section 2: bulk actions.** Two plain button rows, accent text, 44 pt rows, no icons:
- "Show All", disabled when everything is shown.
- "Hide All", disabled when everything is hidden. It isn't destructive (one tap on Show All brings everything back), so it isn't red.

Storage: save the set of **hidden** group names, not the shown ones, so new groups default to visible. Keep it in the App Group, readable by the keyboard. Add it to the configuration file next to `emoji_sort_order` (Pluso names the key, round trip + diff tests).

---

## 3. Emoji size (pinch)

Reuses the character grid's pinch. It's a separate remembered value, because emoji tiles carry names and are wider.

- Stored `emojiColumns: Int`, where 0 means **Automatic**. Automatic is today's layout: `floor((W + 8) / (96 + 8))` columns, minimum 2. Until someone pinches or taps Smaller/Larger, nothing changes for anyone.
- Effective columns: `TileGridLayout.columns(stored:in:)`, i.e. minimum 2 columns and tiles never narrower than 32 pt (the same limits as character tiles).
- Pinch: exactly like `CharacterGrid`. Spreading past 1.15 gives one column fewer (larger); pinching under 0.87 gives one column more (smaller). One step per gesture. `.snappy` animation on the column count, and no animation when Reduce Motion is on. The first step from Automatic starts from the automatic count.
- Smaller/Larger in the menu (§1.1) step by one column, the same as a pinch.
- Tile width: `w = (W − (c − 1) · 8) / c`.
- Glyph size: linear between these points and clamped, rounded to a whole point:

| w (pt) | 34 | 54 | 80 | 118 | 181 | ≥ 250 |
|---|---|---|---|---|---|---|
| glyph (pt) | 20 | 28 | 32 | 34 | 64 | 96 |

  At the default width (118) this stays at today's 34 pt. Glyph size never shrinks as tiles get bigger.
- Name: shown when w ≥ 80. Caption2 medium below 150 pt; footnote medium at 150 pt or wider. Two lines, centered.
- Tile height:
  - Glyph only (w < 80): square, `h = w`.
  - Named: 8 + (glyph + 10) + 3 + (two lines of the name font at the current text size) + 8. Default size = 91 pt (today 92).
- Corner radius 12 at every size, as character tiles.
- Version ribbon: labeled at 80 pt or wider, otherwise the 18 pt corner triangle (`TileGridLayout.labeledRibbonMinimumWidth`, `VersionRibbon.triangleSide(cornerRadius: 12)`).
- Favorite star: 9 pt, padding 7 (padding 4 under 44 pt).
- The glyph keeps `lineLimit(1)` and `minimumScaleFactor(0.55)`, so a ZWJ sequence that falls back to several glyphs shrinks to fit.
- Display only: copy, insert, Save and Scratchpad use the unchanged sequence.

Resulting sizes, iPhone 17 Pro (402 pt wide, grid width 370):

| columns | 2 | 3 (Automatic) | 4 | 5 | 6 | 7 | 8 | 9 (max) |
|---|---|---|---|---|---|---|---|---|
| tile w | 181 | 118 | 86.5 | 67.2 | 55 | 46 | 39.3 | 34.0 |
| glyph | 64 | 34 | 32 | 30 | 28 | 25 | 22 | 20 |
| name | ✓ footnote | ✓ | ✓ | – | – | – | – | – |

iPad (grid width 748): Automatic = 7 columns (w 100, glyph 33), up to 18 columns.

The keyboard's emoji grid keeps its fixed size; zoom is in the app only.

Accessibility: every emoji tile gets the custom actions "Increase emoji size" and "Decrease emoji size" (leave out whichever is at its limit). They do the same as one pinch step. The tile's label and value are unchanged.

---

## 4. Keyboard: Emojis section

- The discovery grid and emoji search use the same hidden set. They read it whenever the section appears and when the app changes it (App Group notification or re-read on appear, Pluso's choice).
- There's no category control inside the keyboard; the app is the one place to change it.
- All hidden: the existing `emptyState`, with icon `line.3.horizontal.decrease.circle`, title "No emoji categories shown", detail "Choose categories in the Uniboard app." No button (the keyboard can't open the app).
- Search, no visible matches: title "No matching emoji in the categories shown", detail "Try another search, or show more categories in the Uniboard app."
- Recent, pages and favorites are unaffected.

---

## 5. Blocks: sort both ways

- **Toolbar** (Blocks list, trailing; it has no toolbar today): `Menu("Sort Blocks")` with icon `arrow.up.arrow.down`, containing an inline Picker:
  - "Code Point: Low to High", `arrow.down`, tag false (default)
  - "Code Point: High to Low", `arrow.up`, tag true

  The icons match Explore's existing Order picker. Accessibility label "Sort Blocks", value = the selected option. id `blockSort`.
- Stored `blocksDescending: Bool` (AppStorage), and in the configuration file (Pluso names the key).
- High to Low reverses the list of blocks only. Characters inside a block keep code-point order.
- Search keeps the chosen order and never resets it. The "{n} of {total} blocks" header is unchanged.
- **Block detail follows the order of the list it was opened from.** The ⌃/⌄ buttons step to the row above/below in that list. The block navigator sheet opened from the title lists blocks in the same order.
  - Opened from Blocks: Blocks' order.
  - Opened from Explore: Explore's existing Order (`exploreDescending`).
  - So "Next block" always means the next row the person saw. VoiceOver labels already name the block.
- **Explore's block navigator** (the `list.bullet.indent` button in Explore's toolbar, id `exploreBlockNavigator`) also follows Explore's Order (Ato msg799, consistency fix).
- The keyboard's Blocks section is unchanged in 1.4.

---

## 6. Keyboard tab and Main Keyboard

### 6.1 Keyboard tab
- First group: **Main Keyboard only**. The Symbol Keys row is removed.
- The Main Keyboard row gets a subtitle, so people who used Symbol Keys in 1.3 find it: "Letters, numbers and symbol keys". Subheadline, secondary, under the title.
- Second group (Favorites, Symbols, custom pages) is unchanged. The Symbols page is untouched.
- Read-error text (KeyboardKeyPreferences.swift:91) becomes: "Couldn’t read your saved keyboard keys. Try again. To reset all key actions and arrangements, open Main Keyboard in Keyboard, then choose Restore All Key Defaults from the More menu. This replaces your saved key settings." (Main Keyboard's ⋯ keeps accessibility label "More".)

### 6.2 Main Keyboard header (top of the scroll content, padding 16, spacing 12)
1. **Section switch**: segmented Picker, full width, three segments:

| Segment | Visible label | VoiceOver label |
|---|---|---|
| 1 | the title the keyboard's own letters key shows for this layout (today "ABC" for every layout; if Pluso gives a layout a native title on the keyboard, the segment uses the same text) | "Letters" |
| 2 | "123" | "Numbers and Symbols" |
| 3 | "#+=" | "More Symbols" |

   - id `mainKeyboard.section`. Opens on ABC. The choice isn't remembered between visits (the screen is about letters first).
2. **Helper**: "Choose letters, numbers or symbols to edit their keys." Footnote, secondary, directly under the switch.
3. **Layout row**: ABC only, and only with 2+ layouts. HStack: "Layout" (subheadline, secondary), Spacer, then a `.menu` Picker showing the layout's native name with ⌃⌄ (subheadline, accent).
   - This replaces 1.3's segmented Layout picker. Two stacked segmented controls read as one control, and up to 8 layouts (more likely now) don't fit as segments.
   - Same id `mainKeyboard.layout`.
4. **Canvas**: the existing rounded keyboard well.
5. Under the canvas, when a key is selected:
   - the existing layers panel (Key / Swipe up / Hold / Swipe down)
   - **then a per-key restore row** (§6.4)
6. Error line (existing).

Bottom control bar (Move / Gap / New Row / Remove): **ABC only.** It's hidden on 123 and #+=, whose keys can't be moved.

### 6.3 Canvas on 123 and #+=
Drawn as the keyboard draws that layer on this device. iPhone:

| Row | 123 | #+= |
|---|---|---|
| 1 | 1 2 3 4 5 6 7 8 9 0 | [ ] { } # % ^ * + = |
| 2 | - / : ; ( ) $ & @ " | _ \ \| ~ < > € £ ¥ • |
| 3 | [#+=] . , ? ! ' [⌫] | [123] . , ? ! ' [⌫] |

- **Key widths:**
  - Rows 1–2 use the existing `keyWidth`.
  - In row 3, the switch key and ⌫ use the Shift/Delete width.
  - The five punctuation keys share the remaining width equally, as on the real keyboard.
- **Function keys:**
  - Drawn in `Color.functionKey`.
  - The **#+= / 123 key switches the section**, mirroring the keyboard. VoiceOver: "Switch to More Symbols" / "Switch to Numbers and Symbols".
  - ⌫ is drawn but inert, and hidden from VoiceOver.
- **Symbol and digit keys:**
  - Tapping selects, with the existing selection border, and shows the same layers panel as letters, with the same editors.
  - Digits are the same settings as the number row on ABC.
  - . , ? ! ' are one key each, shared by both layers.
- No dragging and no Move/Gap controls on these layers.
- **Number row (rev. 4, user msg949 / Ato msg950):** the extra 1–0 row is on ABC only. 123 and #+= are always the stock three rows above (table), whether or not ABC has the number row; the digits on 123 are the same keys and settings as ABC's number row. The [ ] { } # % ^ * + = row is never added to 123.
- **Height, keyboard:** 123 and #+= keep ABC's content height (no change to the keyboard's outer height, no blank strip). Row spacing stays 4 pt (iPad 6 pt); the three rows share the rest: key height = (ABC content height − 2 × row spacing) / 3. iPhone with ABC at 41.4 pt keys + number row: content 177.6 pt → 56.5 pt keys. Glyph sizes don't change; glyphs stay centered. The bottom row (globe, space, return…) is unchanged. Without the number row, nothing changes (3 rows at 41.4 pt). Floor: 123/#+= keys are never shorter than the stock key height; a two-row ABC layout keeps its 1.3 height (the three-row height); only four-row ABC stretches 123/#+= (msg956). Hold callouts use the taller key frames.
- **Height, editor canvas:** the same rule, so the canvas doesn't jump when switching segments: 123/#+= tile height = (ABC canvas rows × 44 + (rows − 1) × 6 − 2 × 6) / 3 → 60.7 pt when ABC has 4 rows, 44 pt otherwise. Glyph 22 pt, centered. A saved two-row ABC layout reserves the three-row canvas height (144 pt) with its two 44 pt rows centered vertically, as the keyboard centers them (msg958).
- **Wide iPad (full hardware-style layout):** 123 is stock as above. #+= keeps its § ± × ÷ ° © ® ™ … · top row (not a digit row; with 123 stock nothing repeats, and removing it would drop 10 keys), so it has 4 rows at the normal height while 123's 3 rows stretch.
- **iPad:** draw the iPad 123/#+= layers, including iPad-only keys. Any symbol key that isn't drawn on any canvas must still be reachable through Find a key (§6.5).
  - Pass condition: the number of symbol keys reachable = the number the 1.3 Symbol Keys grid listed.
- **Customized dot**, kept from the 1.3 Symbol Keys grid and applied on all three sections, letters too:
  - A key with any saved choice shows a 4 × 4 pt accent dot, centered horizontally, 4 pt above the key's bottom edge.
  - The key's VoiceOver value is "Customized" (otherwise none).

### 6.4 Per-key restore (all sections)
- Under the layers panel: a card row matching the layer rows (`secondarySystemGroupedBackground`, radius 12, minimum height 52, padding 12), containing a leading-aligned destructive Button "Restore this key's defaults" (the 1.3 string).
- Disabled, with the text in `.tertiary`, when the key has no saved choices.
- Confirmation is the 1.3 dialog, anchored on this row: "Restore this key's defaults?" with destructive "Restore defaults" + Cancel.
- This keeps the per-key reset Symbol Keys had, and gives letters the same reset (audit item 6.2) with no extra UI.

### 6.5 Find a key
- `.searchable(text:, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Find a key")`: pull down to reveal it, as in 1.3.
- **Scope: all three sections** (ABC uses the current layout's letters). The match rule is 1.3's (title or id contains the query, case-insensitive).
- While the query is non-empty:
  - The header, canvas, layers panel and bottom bar give way to results.
  - Results sit in groups headed "ABC", "123", "#+=" (subheadline semibold, secondary). VoiceOver reads the headers as "Letters", "Numbers and Symbols", "More Symbols".
  - Each group is the 1.3 key grid: adaptive minimum 46, spacing 8; tiles `tertiarySystemFill`, radius 8, minimum height 46, glyph title3, 4 pt dot.
  - Keys on both 123 and #+= appear once, under 123.
- **Tap a result:**
  - the search ends (query cleared, drawer dismissed)
  - the section switches to that key's section
  - that key is selected
  - the scroll returns to top, so the key and its panel are on screen.
- No results: `ContentUnavailableView` symbol `magnifyingglass`, "No matching keys" / "Try another search."

### 6.6 ⋯ menu and Restore All
- ABC: the 1.3 items unchanged (Add/Remove Tab, Add/Remove Caps Lock, Add Number Row / Missing Digits, Standard Layout). Then a **separate Section** containing the destructive "Restore All Key Defaults" (`arrow.counterclockwise.circle`).
- 123 / #+=: only that destructive Section. The letter-arrangement items are hidden, because they don't apply there.
- Subtitle under the item: "Resets letters, numbers and symbols, and every layout's arrangement." Use it only if the menu shows it in full on iPhone at the default text size; otherwise leave it out (the confirmation carries the full scope).
- Disabled under the same condition as 1.3 (no overrides, no arrangements, no save error).
- Confirmation: `.confirmationDialog` attached to the ⋯ toolbar button, so the iOS 26 popover arrow points at ⋯.
  - Title visible: "Restore all key defaults?"
  - Message: "This resets all letter, number and symbol key actions, including taps, and restores the standard key arrangement and number row for every layout. Your symbol pages, favorites, enabled layouts and other settings are kept."
  - Buttons: destructive "Restore All Key Defaults", then "Cancel".
- After restoring, the selection clears and the canvas shows the stock layer.

No data migration: Symbol Keys data ("symbol.XXXX" overrides) is read and written exactly as before.

---

## 7. New layouts: Hebrew, Arabic

Armenian is deferred (Ato msg812): no Add Layout row, no catalog entry, no mention.
Show Hebrew and Arabic only once Pluso's checks pass: the layout checks, plus the mixed-direction
and combining-mark checks (cursor, deletion, punctuation, marks).

Mockups: 13 (Add Layout), 16 (Arabic in Main Keyboard), 17 (hold callout), 18 (Arabic Diacritics panel), 19 (123 Hold row note).

### 7.1 Add Layout sheet
- New script sections after Latin, Greek and Cyrillic, in this order: "Hebrew", "Arabic".
- Rows use the existing LayoutRow: native name, then the English name in secondary:
  - עברית / Hebrew
  - العربية / Arabic

  Pluso verifies the native names in the catalog.
- The row stays leading-aligned in the left-to-right UI; the Hebrew or Arabic name renders right-to-left within its own text.
- No generic caveat footer. Use a script-specific note only if a verified limitation needs one.
- **Suggested** (device-language match) works for them like any other layout.
- A newly added layout starts with the stock 1–0 number row (1.3 rule).

### 7.2 Letter rows
- Rows in visual left-to-right order, exactly as in Pluso's notes (`uniboard-1.4-scripts.md` §1, §2):
  - Hebrew 8 / 10 / 9: ק ר א ט ו ן ם פ · ש ד ג כ ע י ח ל ך ף · ז ס ב ה נ מ צ ת ץ
  - Arabic 11 / 11 / 9: ض ص ث ق ف غ ع ه خ ح ج · ش س ي ب ل ا ت ن م ك ة · ء ظ ط ذ د ز ر و ى
- Letter key width: the existing rule (the widest row fills the width; other rows center).
- **Row 3, Hebrew:** no Shift, nothing in its place: 9 letters + ⌫. ⌫ takes the width left over (never less than a letter key).
- **Row 3, Arabic:** Arabic Diacritics key (§7.3) + 9 letters + ⌫. The two function keys split the width left over equally. On iPhone 17 Pro that makes them as wide as a letter key (about 30 pt); never narrower than a letter key. The Shift/Delete width rule doesn't apply to this row.
- Hebrew keys show final forms where iOS does (ך ם ן ף ץ); Arabic keys show isolated forms.
- Hold choices on letters: Pluso's verified lists only (Hebrew §1, Arabic §2 minus the unverified ones he flagged).
- Key glyphs: same size as other letters (22 pt in the editor canvas, the keyboard's letter size in the keyboard).
- The letters segment and the 123 page's letters key stay "ABC" (§6.2.1; the 123 pages are shared).
- Text preview: natural alignment, so the first strong character decides direction (already supported).

### 7.3 Arabic Diacritics key (Arabic only, in Shift's slot)
- **Look:** function-key surface (same gray as Shift), radius 7, same height as letter keys. Face: "◌َ" (dotted circle + fatha) at the letter font size. The ◌ is only a display aid (the existing `symbolBoardPreview` rule); it is never inserted or copied.
- **Marks** (inventory and order; Pluso adjusts the order only to match a verified iOS order):
  1 Fatha U+064E · 2 Damma U+064F · 3 Kasra U+0650 · 4 Sukun U+0652 · 5 Shadda U+0651 · 6 Fathatan U+064B · 7 Dammatan U+064C · 8 Kasratan U+064D.
  Names are the Unicode names in title case. Superscript alef and others: only if verified, then after these.
- **Touch and hold** (as iOS): the existing hold callout opens with the 8 marks, each drawn on ◌. Slide to one, lift → that mark is inserted. Lift outside → nothing. *Revised 25 Oct (review msg919):* 1.4 uses the shared center-out callout rule, so Fatha is preselected in the 4th cell rather than opening toward the trailing side from the key; a plain lift types Fatha and all 8 fit within the keyboard width. Placing an edge key's primary choice next to the key belongs to the hold-callout follow-up (Ato msg912).
- **Tap** (and VoiceOver activation): opens the Arabic Diacritics panel (§7.4). Nothing is typed.
- **Inserted text:** exactly one scalar, the mark, at the cursor, with no normalization and no ◌. It combines with whatever precedes it; at the start of a field or after a space the host shows it standalone (allowed, not blocked).
- Shift-related behaviour doesn't exist on Arabic: no caps, no double-tap, no shift-slide.
- **Main Keyboard canvas (Arabic):** the key is drawn in Shift's slot with the same face, inert and not selectable, like Shift on other layouts. It can't be moved or removed. Hidden from VoiceOver like ⌫ in the canvas.
- **VoiceOver:** label "Arabic Diacritics", trait button, hint "Choose a mark to add to the text." Activation opens the panel. Custom action "Choose Arabic Diacritic" does the same (Camo; also reachable from Switch Control and Voice Control menus).
- No new setting, no customization of this key in 1.4.

### 7.4 Arabic Diacritics panel (in the keyboard)
- **Where:** replaces the number row and the three letter rows, at their combined height. The preview row above and the bottom row below stay as they are. The keyboard's height doesn't change.
- **Header** (height 36): leading title "Arabic Diacritics" (13 pt semibold, secondary label, header trait); trailing close key: function-key surface, 44 × 32 pt, SF Symbol `xmark` 15 pt semibold, label "Close".
- **Tiles:** iPhone 2 rows × 4; iPad 1 row × 8. Gaps 6 pt (the key gap). Each tile: letter-key surface (white / dark key color), radius 7, height fills the remaining area evenly (about 64 pt on iPhone 17 Pro; minimum 48). Content centered: the mark on ◌ at 28 pt, then its name in 11 pt secondary label ("Fatha"), one line, `minimumScaleFactor(0.8)`.
- **Tap a tile:** inserts that mark (same rule as §7.3), key click + haptic as a letter key, then closes the panel back to the Arabic letters.
- **Close:** the close key, or any bottom-row key (which also does its own action, e.g. space types a space). Switching layout or leaving the keyboard closes it too. The panel never stays open across keyboard launches.
- **VoiceOver:** on open, focus moves to the title. Tiles: label = the name only ("Fatha"), trait button, no hint; the mark itself isn't read as a glyph. Close: "Close". On close, focus returns to the Arabic Diacritics key.
- **Large text:** the keyboard doesn't scale with Dynamic Type (system behaviour); names use `minimumScaleFactor`. Large Content Viewer on tiles (long press with accessibility sizes) shows the mark on ◌ and the name.
- Light/dark: system key colors as the other keys; no new colors.
- **Deletion:** ⌫ is the keyboard's existing ⌫. Pluso checks and reports what one ⌫ removes after "بَ" (mark only, or letter + mark) in Notes, Messages and the app's Try Uniboard field. No special handling unless a check fails.

### 7.5 Layout-only punctuation hold choices (shared 123 pages)
- While the **Arabic** layout is the active letters layout: the 123 page's "," key offers "،" (U+060C), "?" offers "؟" (U+061F), ";" offers "؛" (U+061B).
- While **Hebrew** is active: the "$" key offers "₪" (U+20AA).
- Placement: the first hold choice (nearest the key), before the key's default choices. Tap output is unchanged.
- **Saved choices win:** if the key has any saved hold choices, the saved list is used exactly, in every layout, and nothing is added. Existing settings are never rewritten.
- Other layouts: unchanged. The #+= page keys are unchanged, except "," and "?" in its row 3, which are the same keys as on 123 (§6.3) and get the same addition.
- **Main Keyboard editor (123 section):** when the selected key has such an addition and no saved hold choices, its Hold row shows one extra line under the chips: caption 12 pt, secondary label, "When using Arabic: ؟" (or ، / ؛) and "When using Hebrew: ₪" (Camo msg819, final). The symbol is its own `Text`, isolated from the English label (concatenate the label and a separate symbol `Text` in an `HStack`, or wrap the symbol in U+2068…U+2069), at 15 pt in the primary label color, so right-to-left punctuation can't reorder it. VoiceOver reads the line as "When using Arabic: Arabic question mark" (the symbol's Unicode name, title case). The line is not a chip and can't be edited or removed on its own. It shows only while the default applies: once any hold choices are saved, the line disappears and the saved list is shown as it already is.
- Arabic-Indic digits stay deferred (Ato msg799).

## 8. Accessibility and appearance
- Every new control has a hit area of at least 44 × 44 pt (the filter row buttons, Show All/Hide All, the sort menu, segments, the per-key restore row).
- Dynamic Type:
  - The filter row reflows (§1.3).
  - Category rows grow, and the count wraps under the name.
  - Emoji tile names use two lines of the scaled font (tile height grows with it).
  - The segmented switch uses the system's large-content viewer for its labels.
- VoiceOver: labels, values and actions as given in each section. State lives in values ("Customized", "{n} of {total} shown", the selected sort), never in color alone.
- Contrast: system semantic colors only. Accent text on `groupedSurface` is the platform button contrast (light 4.0:1, dark 5.2:1). The customized dot is decorative; its meaning is also in the VoiceOver value.
- Light and dark: no fixed colors anywhere in this spec.
- Reduce Motion: zoom steps and the section switch change without animation.

---

## 9. Strings
All final (Camo msg794 + msg797 + msg814 addendum: "Arabic Diacritics", "Choose a mark to add to the text.", "Choose Arabic Diacritic"; mark names are the Unicode names). Camo msg819: "When using Arabic: {symbol}" / "When using Hebrew: {symbol}" (§7.5).

---

## 10. Review checks (screenshots from Pluso; iPhone 17 Pro unless noted)
1. Emoji default: 3 columns, tile 118 × 91 ± 1 pt, glyph 34 pt; looks like 1.3.
2. Larger ×1 → 2 columns, glyph 64, footnote-size names. Smaller from default → 4 (named) → 5 (glyph only, square, 30 pt) … → 9 columns (34 pt tiles, 20 pt glyph). The size survives relaunch.
3. 👩🏽‍🚀 and 🏳️‍🌈 copied at 2 and 9 columns paste with the same code points as at default.
4. Hide Flags: the grid has no Flags-group emoji; the filter row reads 8 of 9; the toolbar icon is filled; the keyboard Emojis section and its search show no flags.
5. Hide All → the all-hidden state in the app and the keyboard; Show All restores. "Choose Categories" opens the sheet.
6. A saved flag stays in Saved and on its page while Flags is hidden.
7. Blocks High to Low: the first row is the highest block; search "latin" keeps the order; relaunch keeps it; in block detail ⌄ goes to the row below in the list.
8. The Keyboard tab first group has one row with the subtitle.
9. Main Keyboard 123 and #+= canvases match the keyboard. Edit $ swipe up → it works on the real keyboard and the dot appears; per-key restore clears it. Find a key "€" → one result under #+= → tap → #+= selected with € selected.
10. ⋯ → Restore All Key Defaults on each section; the popover arrow touches ⋯; the strings are exact; it resets as 1.3 did.
11. Reachable symbol key count equals the 1.3 Symbol Keys count (iPhone and iPad).
12. Add Layout shows Hebrew and Arabic sections only (no Armenian anywhere). Hebrew row 3 is 9 letters + ⌫ with no Shift; Arabic row 3 is the Arabic Diacritics key + 9 letters + ⌫, the two function keys at least as wide as a letter key. Pluso's mixed-direction checks pass before either is listed.
13. Dark mode + AX3 screenshots of the filter row, the categories sheet and the Main Keyboard header.
14. Arabic marks: type ب, hold the diacritics key, slide to Fatha, lift → the text is U+0628 U+064E (no U+25CC). Tap the key → the panel shows "Arabic Diacritics" + 8 named tiles + close; tap Shadda → U+0651 is inserted and the letters return. Space while the panel is open types a space and closes it.
15. VoiceOver: the key reads "Arabic Diacritics, button" + hint; activating it opens the panel and focus lands on the title; tiles read their names only; Close returns focus to the key. The "Choose Arabic Diacritic" action works.
16. ⌫ after a mark: Pluso reports what one ⌫ removes in Notes, Messages and Try Uniboard.
17. Punctuation: Arabic active → hold , ? ; on 123 shows ، ؟ ؛ first; Hebrew active → hold $ shows ₪ first; English active → neither. A key with saved hold choices shows exactly its saved list in every layout. The editor's Hold row shows "When using Arabic: ؟" (or Hebrew: ₪) only while the default applies, with the symbol in its place after the colon.

---

## 11. Proposals: Ato's decisions (msg799)
- Accepted: Explore's block navigator follows Explore's Order (now in §5).
- Deferred, not in 1.4: skin-tone variant switch; "Category" emoji order; Arabic-Indic digit hold choices.
- Ato msg812: Armenian deferred (iOS 27 layout has 4 letter rows, unverified); Arabic diacritics key in Shift's slot (accepted, §7.3–7.4); layout-only punctuation hold choices (accepted, §7.5).
