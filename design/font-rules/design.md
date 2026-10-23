# Uniboard — Font Rules and portable Configuration (design spec)

23 Oct 2026 · user msg272, product brief `font-rules-brief.md` (msg278),
product decision msg284, copy `docs/font-rules-copy.md` (Camo msg280 + added
labels msg285 — all strings below in "quotes"
are Camo's exact wording; anything marked [design] is a non-copy label I set).
Next increment, separate from the current TestFlight. Implementation and
testing: Pluso. Mockups: artifact "Uniboard — Font Rules & Configuration" (illustrative,
sample fonts); phone screenshots in screens/ beside this file:
1 character detail, 2 font picker, 3 Font Rules, 4 rule editor, 5
Configuration, 6 Review Import, 7 import error. Where a screenshot and this
text disagree, this text wins.

Style stays exactly the app's current native look: system font, semantic
colors, system blue accent, insetGrouped Forms/Lists, 16 pt margins,
12 pt card radius, 44 pt minimum rows. No new accent, no custom type.
Status: `exclamationmark.triangle.fill` in systemOrange next to secondary-label
words = "saved but not applied / resets"; systemRed = blocks an action.
Never color alone.

## 0. Facts this design is built on (source audit)
- Nothing picks a font per character today: `UnicodeFontSupport.choice(for:)`
  takes the first asset that covers the text, behind the global Extra Unicode
  Fonts switch. FontFaceDetailView's Styles choice is inspection only.
- Known faces = CustomFontStore entries (imported, installed, Google
  downloads; face IDs like `google:<fileID>:<styleID>`) + preview packs.
- Only Pages has import/export (JSON). No TOML library, no UTType.
- Settings → Preview Fonts holds Extra Unicode Fonts, PUA, UCSUR, Font
  Downloads, Font Licenses.

## 1. Behavior decisions that shape the UI
1. Extra Unicode Fonts is the master switch (product msg284). Off pauses
   rules without deleting them; the screens show a notice row "Rules apply
   only when Extra Unicode Fonts is on." with a "Turn On" button (accessible
   label "Turn on Extra Unicode Fonts"). Adding, editing or importing rules
   never turns it on by itself. Only a reviewed and confirmed configuration
   import may change it, and the review shows that change (§6a).
   Font-comparison samples (View Fonts, face detail) always show the face
   being inspected, switch or not.
2. Picking a font saves on tap (iOS Settings pattern) from character detail;
   the rule editor sheet uses Cancel / "Save".
3. Only fonts already in Uniboard are offered; the picker links to Font
   Downloads as a separate explicit step. Nothing downloads from a rule or an
   import.
4. The list shows rules in their SAVED order in every section (Camo: sorting
   must not suggest another precedence). Reorder handles in Edit mode, all
   sections; order only matters for equal-width ranges.

## 2. Character detail — preferred font card
Placement: directly ABOVE the existing "View Fonts" card, same style
(groupedSurface, radius 12, padding 16, chevron), i.e. after the Copy
Character / Save / Scratchpad buttons. Only CharacterDetailView
(single code point); emoji detail gets nothing (no sequence rules).
- Headline 17 semibold: "Set Preferred Font" when this code point has no rule
  of its own, "Change Preferred Font" when it does.
- Caption 12 secondary under it, one of:
  "Using {font name}" or "Using default fonts" — followed on the same line by
  the rule it comes from, using the Try Text captions: " · Code point rule",
  " · Range rule U+2190–U+21FF", " · Unicode block rule Runic". No rule →
  "Using default fonts" alone.
- Not applied: orange triangle + "Font unavailable" or "Font can’t display
  this text", then the line "Using the next matching font." / "Using default
  fonts". The big glyph above always shows the font really used.
- Tap → Font Picker for this code point (§4).
- Existing "Preview font" property row unchanged (font really used).
- VoiceOver: one button; label = headline; value = caption text.

## 3. Settings → Font Rules
Entry: NavigationLink "Font Rules" in the **Preview Fonts** section right
after "Font Downloads"; trailing value = rule count, "None" when 0.

Screen: List .insetGrouped, inline title "Font Rules". Toolbar: Edit (only
when rules exist) and `plus` Menu titled "Add Rule" with "Code Point",
"Range", "Unicode Block".

Top header text (footnote secondary, above first section): "Choose how text
looks in Uniboard. Other apps still choose how inserted text looks."

Sections, in priority order:
1. Notice (only if Extra Unicode Fonts is off): orange triangle + "Rules
   apply only when Extra Unicode Fonts is on." + trailing borderless "Turn
   On" (accessible label "Turn on Extra Unicode Fonts"). Rows below stay
   fully editable.
2. Section "Try Text": TextField, placeholder "Type or paste text", leading
   `magnifyingglass`; input trimmed to 32 characters (grapheme clusters).
   Results, one row per character in typed order (a joined character or
   emoji = one row): 44×44 tile drawn as Uniboard draws it, then "Using {font
   name}" / "Using default fonts" (body) and the source caption: "Code point
   rule", "Range rule {range}", "Unicode block rule {block}", or "Default
   fonts". If all characters share one result, show a single row instead. If
   they differ, a first summary row (secondary) reads "Multiple fonts used",
   then the per-character rows. Never name one font for mixed input. For
   joined characters show footnote: "Joined characters and emoji stay
   together. Their first main character determines the rule, and the font
   must support the whole sequence." Nothing typed is stored or exported.
3. "Code Point" rules — section header "Code Points".
4. "Range" rules — header "Ranges". Footer: "For overlapping ranges, the
   narrower range wins. If they are equally wide, the later rule wins."
   In Edit mode add caption under header: "Later rules win equal-width ties."
5. "Unicode Block" rules — header "Unicode Blocks".
6. Last footer: "Code point rules take priority over ranges, then blocks,
   then the default font." + new line "If a font is missing or can’t display
   the text, Uniboard tries the next matching rule, then its default fonts."

Rule row, min 60 pt:
- Leading 44×44 tile, radius 8, previewSurface: code point → its glyph at
  28 pt; range/block → its first assigned character; drawn in the chosen face
  when available, else the system rendering at 40 % opacity.
- Title (body): code point → character name; range → "U+2190–U+21FF"
  monospaced; block → block name.
- Subtitle (caption secondary): code point → "U+16A0"; range →
  "1 code point" / "{n} code points" (valid scalars only, surrogates not
  counted); block → "U+16A0–U+16FF".
- Trailing (subheadline secondary, ≤45 % width, truncate middle): font name.
- Status line replacing the subtitle when not applied: orange triangle +
  "Font unavailable" or "Font can’t display this text". For a range/block a
  font that draws only some characters is not an error; no status.
- Tap → Rule editor (Edit Rule). Swipe → "Remove Rule" (no confirmation; post
  VoiceOver announcement "Rule removed").
- VoiceOver: one element; label "{title}, {subtitle}", value "{font},
  {status}", hint "Edit rule".
- In the rule editor (Edit Rule), when a higher-priority rule covers some of
  this rule's code points, show caption under the selector: "Another rule
  takes priority for 1 code point." / "Another rule takes priority for {n}
  code points." (one localized sentence) — no navigation needed.

Empty state (no rules, below Try Text): centered, `textformat.alt`
44 pt secondary, title "No font rules yet", text "Choose a preferred font for
a code point, range or Unicode block.", button "Add Rule" (same menu).

## 4. Font Picker (from character detail, and "Preferred font" in the editor)
Pushed screen, inline title "Preferred Font". `.searchable` prompt "Search
fonts".
- Sample header (not a row): single code point → glyph 64 pt centered in a
  96 pt previewSurface box, radius 12, drawn in the highlighted choice. Range
  or block → first 12 assigned characters at 28 pt, one line, horizontal
  scroll.
- Notice row when Extra Unicode Fonts is off (same as §3.1).
- Font sections in this order, each only if non-empty:
  "Your Fonts" (imported + installed), "Google Fonts" (downloaded faces),
  "Preview Fonts" (packs). Within each: faces that can draw it first, then
  alphabetical.
- Font row, min 56: leading 44×44 tile with the first character in that face
  at 28 pt; title = face name (body); subtitle = style · source (caption,
  e.g. "Bold Italic · Google Fonts"); trailing checkmark (accent) when chosen.
  Range/block mode adds a caption with coverage of the NAMED face (never a
  fallback): "Supports {n} of {m} code points" when the whole range/block was
  checked (preferred; compute off the main thread, show a small ProgressView
  in the caption's place until done), or "Supports {n} of {m} preview
  characters" if only the 12 sample characters were checked.
  Single code point: faces verified unable to draw it are hidden behind a
  last row "Show 1 Unsupported Font" / "Show {n} Unsupported Fonts"; when
  expanded, footnote "These fonts can’t display this character." and the
  faces disabled at 40 %. Faces still being checked or whose file is missing
  are never counted as unsupported. Range/block: faces supporting 0 are
  listed disabled at the end with "Supports 0 of {m} code points".
- Footer under fonts: "If a font is missing or can’t display the text,
  Uniboard tries the next matching rule, then its default fonts." then a
  NavigationLink row "Font Downloads" (`arrow.down.circle`).
- Character-detail mode only, when this code point has its own rule: a last
  section with one centered button "Clear Preference" (accent, not
  destructive — the font stays). Under it, caption: what then applies, e.g.
  "Using Noto Sans Runic · Unicode block rule Runic" or "Using default
  fonts".
- Tap a font = save (character-detail mode) or return the choice (editor
  mode); pop after 0.25 s so the checkmark is seen; Reduce Motion: pop
  immediately.
- Rows are buttons with isSelected trait; coverage in the value.

## 5. Rule editor (sheet)
From the Add Rule menu or a row. NavigationStack; inline title "Add Rule" or
"Edit Rule". Toolbar: "Cancel" (leading), "Save" (trailing, bold, disabled
until valid). Unsaved changes + dismiss → system "Discard Changes?".
Form:
- Section "Applies To": segmented Picker "Code Point" / "Range" /
  "Unicode Block" (only when adding; fixed when editing).
- Code Point: TextField placeholder "U+0041 or a character", accepts one
  pasted character or hex with/without "U+". Live result row: tile + name +
  U+code. Errors as footnote systemRed with `exclamationmark.circle` under
  the field: "Enter a valid Unicode code point, such as U+0041." /
  "Surrogate code points can’t be used here." / pasted text with more than
  one CODE POINT (count scalars, not visible characters — one joined emoji
  or accented letter can be several): "Enter one code point. This text
  contains more than one." — never silently take the first.
- Range: TextFields "From" and "To" (monospaced, ASCII keyboard, characters
  autocap). Footer "Includes both endpoints." Live summary row: title
  "U+2190–U+21FF", caption "1 code point" / "{n} code points". Errors: "The end of the range must come after or equal
  the start." / "Surrogate code points can’t be used here." (endpoints only;
  a range that crosses the surrogate area is fine).
- Unicode Block: NavigationLink "Unicode block" → searchable list of blocks
  of the selected edition (glyph tile, name, range, checkmark). Error if an
  edited rule's block no longer exists: "This Unicode block isn’t recognized."
- Font: NavigationLink "Preferred font", value = chosen font or accent
  "Choose" → Font Picker (editor mode). Range/block: footer under it shows
  the chosen face's coverage, same wording as §4 ("Supports {n} of {m} code
  points"). Missing → on Save attempt
  footnote "Choose a font." (Save stays disabled; show the hint under the row
  once the selector is valid.)
- Duplicate: footnote red "A rule for this code point already exists." /
  "…range…" / "…block…" + borderless "Edit Rule" switching to it.
- Edit mode: last section, centered destructive "Remove Rule" (no
  confirmation needed since swipe has none; if Pluso prefers one, use Camo's
  "Remove this font rule?" dialog).

## 6. Settings → Configuration
Entry: new Settings section right BEFORE "About", single NavigationLink
"Configuration" (no header).

Configuration page, Form, inline title "Configuration":
- Section 1 rows (leading SF Symbols in accent, 44 pt):
  "Export Configuration" `square.and.arrow.up`;
  "Import Configuration" `square.and.arrow.down`;
  "Undo Last Import" `arrow.uturn.backward` — only when a recoverable
  previous configuration exists; subtitle caption "Imported {date, time}"
  (time of the successful local import, not the file's date).
  Header text: "Save your settings, layouts, favorites, font rules and image
  colors in a TOML file, or import a configuration from Files."
  Footer, two paragraphs, always visible before tapping Export:
  "Favorites and custom key text are included and may be personal. Typing
  history, scratchpad text and font files aren’t included."
  "Fonts aren’t included or downloaded automatically. Some font choices may
  need fonts added on the other device."
- Export: tap → row trailing ProgressView + caption "Preparing
  configuration…" → system share sheet with the file (Save to Files, AirDrop,
  …), suggested file name "Uniboard-Configuration-{YYYY-MM-DD}.toml" (local
  date; nothing personal in the name; the system handles collisions). When the
  sheet opens, caption becomes "Configuration ready to share" for 3 s. Never
  claim "exported/saved". Failure: alert "Couldn’t export configuration" /
  "Try again. Your configuration hasn’t changed." / "Try Again", "Cancel".
- Import: fileImporter (.toml + plain text) → Review Import sheet.

### 6a. Review Import (large sheet, NavigationStack, title "Review Import")
1. Checking: centered ProgressView + "Checking {file name}…";
   toolbar "Cancel". No writes.
2. Error: `xmark.octagon` 44 pt systemRed; title "Couldn’t import
   configuration"; body "Your current configuration hasn’t changed."; then the
   FIRST cause as a card in Camo's format (e.g. "Check line 14, column 3:
   expected a value after =."). If more problems: DisclosureGroup "1 More
   Problem" / "{n} More Problems" listing the rest, same format, monospaced field names.
   Never echo file contents or custom key strings. Toolbar "Done".
3. Review (valid file):
   - Intro (body): "This will replace your current configuration. Review the
     changes before continuing."
   - Under the intro: file name (footnote, primary label), and beneath it
     caption 12 secondary "{size} · Format version {version}" — the file's
     actual size and its configuration format version, never the app
     version (Camo msg287).
   - Section "Changes": five rows, leading SF Symbol
     secondary; title (body) with the status as a second line (footnote) so
     long names never collide; trailing chevron/disclosure when changed:
       "Settings" `gearshape`; "Layouts and Keys" `keyboard`; "Favorites"
       `star`; "Font Choices and Rules" `textformat.alt`; "Image Colors"
       `paintpalette`.
     Status words: "Will change" (accent), "Will reset to defaults" (orange
     triangle + secondary words), "Unchanged" (secondary). Every changed row
     is a DisclosureGroup listing ALL actual changes as plain lines
     (setting name: old → new; "Adds page …"; "Removes 2 favorites") — no
     hidden totals; scroll if long.
   - Extra Unicode Fonts (product msg284): when the file changes the switch,
     the Settings row starts EXPANDED and its first line is "Extra Unicode
     Fonts: Off → On" or "Extra Unicode Fonts: On → Off". This is the only
     way an import can change the switch, and only after Replace
     Configuration is tapped.
   - If any section is missing, footer under Changes: orange triangle +
     "Sections missing from this file will reset to defaults."
   - Overwrite card (when favorites or layouts/keys change or reset):
     "Your current favorites and custom key layouts will be replaced."
   - Fonts card (when referenced fonts are missing): orange triangle + "{n}
     fonts unavailable" / "1 font unavailable", text "Their rules will be
     kept. Other fonts will be used until these fonts are available. Nothing
     will be downloaded." + list of font names.
   - Backup note (caption, only once undo storage exists): "Your previous
     configuration will be kept so you can undo this import."
   - Bottom bar pinned in safe area (bar material, 16 pt padding): full-width
     borderedProminent "Replace Configuration", 50 pt. Toolbar leading
     "Cancel".
   - Identical file: all rows "Unchanged", no overwrite or fonts cards; the
     intro is replaced by "No changes to import" (headline) and the primary
     button becomes "Done". Never show "Configuration imported" when nothing
     was applied.
4. Changed since review (generation check on tap): alert "Your configuration
   changed" / "Changes were made after this preview. Review the import again
   before replacing your configuration." / "Review Again", "Cancel".
5. Replacing: primary shows ProgressView + "Replacing configuration…"; all
   controls and Cancel disabled.
6. Success: `checkmark.circle.fill` 44 pt systemGreen, "Configuration
   imported"; if fonts are missing, NavigationLink row "Font Downloads"
   (explicit). Toolbar "Done".
7. Apply failed with verified intact state: alert "Couldn’t replace
   configuration" / "Your previous configuration is still in use." OK →
   back to review. If recovery isn't verified, Pluso supplies the true state
   and Camo the copy — never claim it.

### 6b. Undo Last Import
confirmationDialog: title "Undo last import?", message "Restore the
configuration you had before the last import." + (if newer edits) " Changes
made since that import will also be replaced."; buttons "Restore Previous
Configuration" (destructive) and "Cancel". Success: row disappears, inline
footer caption "Previous configuration restored" for 3 s. Failure alert
"Couldn’t restore configuration" / "Your current configuration hasn’t
changed." (only when verified).

## 7. Keyboard
No new keyboard UI. Its previews, tiles and Copy Image use the same effective
font choices as the app. Inserted text stays plain. No new Full Access ask.
FontFaceDetailView specimens stay faithful to the chosen face; if needed,
caption "This preview shows the selected font, not your font rules."

## 8. Accessibility & Dynamic Type
- Rows ≥44 pt; glyph tiles decorative where the row label names the character.
- Orange only on symbols; status words in secondary label color (≥4.5:1).
- Accessibility sizes: trailing values stack under titles (ViewThatFits);
  the Review Import bottom bar stays pinned while content scrolls.
- VoiceOver: change rows read "{category}, {status}"; errors read location
  then reason; picker coverage in value.
- Reduce Motion: no custom animation in this feature.

## 9. Not in this increment
No merge import, no sequence (emoji/ZWJ) rules, no rule UI in the keyboard,
no font downloads from rules or imports, no rule editing from the Blocks tab.

## Strings
All UI strings are Camo's (docs/font-rules-copy.md, incl. "Added design
labels — reviewed after msg283", and msg287 for the Review Import file
caption). Nothing open.
