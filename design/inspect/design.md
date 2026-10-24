# Uniboard — Inspect Text (keyboard) and Auto-Capitalization (design spec)

23 Oct 2026 · user msg293, product addendum `inspection-capitalization-brief.md`
(msg297), copy `docs/inspection-capitalization-copy.md` (Camo msg298). Strings
in "quotes" are Camo's exact wording; [design] marks a label I set that
@naming should confirm. Next increment (with font rules + TOML), not the
current TestFlight. Implementation/testing: Pluso. Mockups (v7, 23 Oct icon restyle): artifact
"Uniboard — Inspect Text & Auto-Capitalization" (illustrative); phone
screenshots in screens/ beside this file. Where a screenshot and this text
disagree, this text wins.

References: the user's two images (references/ beside this file): a compact
message bar, and a desktop inspector with NFC/NFKC/NFD/NFKD badges and a
Pos/Grapheme/Char/UTF-16/Name/Category/Script/Block table. I keep its
content (badges, totals, per-code-point metadata) and drop its table form: a
7-column table can't fit ~360 pt, so each grapheme cluster becomes one card
with its code points stacked inside it.

## 0. Facts from the code (audit 23 Oct)
- Preview row: `UnicodeKeyboardView.textPreviewRow` (KeyboardViewController
  ~L1992). Height = typingKeyHeight (41.4 pt iPhone), leading pad 10, key
  surface 55 %, radius 8, 18 pt text, 2 pt accent caret, forced LTR. Text =
  48 characters before + 24 after the caret (`refreshTextPreview`), fitted to
  width by `KeyboardTextPreviewLayout.excerpt`, which adds "…" where cut.
  One trailing 44 pt button `ellipsis.circle` ("Preview actions") opens the
  Copy Image overlay.
- Copy Image overlay (`previewImagePanel`): full keyboard height, dim
  backdrop 18 % black (tap closes), card ≤360 wide,
  secondarySystemGroupedBackground, radius 16, 16 pt sides/bottom, header
  44 pt with title + xmark Close, body in ViewThatFits/ScrollView, pinned
  footer. Keys get no hits while it's open.
- Lookup inside the keyboard: `model.catalog.character(at:)` → name,
  category, categoryName, blockName, script, age, displayText. Names are the
  official uppercase Unicode names.
- Auto-capitalization today follows `proxy.autocapitalizationType` through
  `synchronizeHostTraits` + `KeyboardEnglishInputPolicy.shouldCapitalize`;
  it's off when `!permitsEnglishAssistance` (URL/email/password/OTP,
  non-default keyboard types). Settings → Keyboard rows: Layouts, Customize
  Keys, Top Row, Number Row, Text Preview, Hide Keyboard Key. Top Row and
  Number Row are being removed (user msg318, Pluso msg320); the list becomes
  Layouts, Customize Keys, Auto-Capitalization, Text Preview, Hide Keyboard
  Key. Screenshot 7 still shows the old rows: ignore them.
- Container: §2 sizes are replaced by the full-keyboard container in
  design/copy-image/larger-panel/design.md §1 (and §3: the keyboard grows 96 pt while open, user msg328).

## 1. Entry — Inspect button in the preview row
- Add a second 44 × row-height button IMMEDIATELY LEFT of the existing
  `ellipsis.circle`: SF Symbol `text.magnifyingglass`.
  Accessibility label "Inspect preview text", identifier
  `keyboard.textPreview.inspect`. Text width = row width − 88.

### 1a. Icon style — Telegram message-field look (user msg306, Ato msg308)
Both trailing icons (Inspect and the existing ⋯) restyle together, in the
next update with Inspect. They read as part of the field, like Telegram's
text-format and sticker icons, not as separate buttons:
- Glyphs: `text.magnifyingglass` and `ellipsis.circle`,
  `.font(.system(size: 19, weight: .regular))`, drawn in a 22 × 22 frame,
  `.symbolRenderingMode(.monochrome)`. No fill, no circle/capsule
  background, no border, no accent.
- Color: `Color(uiColor: .secondaryLabel)` (light grey: dark mode
  rgba(235,235,245,0.6), light mode rgba(60,60,67,0.6)). Pressed:
  `.tertiaryLabel`. Disabled (the other panel open): `.quaternaryLabel`.
  No tint change on the ⋯ while its panel is open.
- Position inside the row (row-height tall, 88 pt trailing area, no change
  to the row's surface, radius or height):
  - Inspect button = left 44 pt; its glyph trailing-aligned
    (`.frame(width: 44, height: rowHeight, alignment: .trailing)`), so the
    glyph spans x 22–44 of the 88 pt area.
  - ⋯ button = right 44 pt; glyph leading-aligned with 8 pt inset
    (`alignment: .leading` + `.padding(.leading, 8)`), glyph x 52–74.
  - Result: glyph centers 30 pt apart with an 8 pt gap (Telegram's spacing
    in the reference), and the ⋯ glyph ends 14 pt inside the row's right
    edge. Both vertically centered on the text line.
- Touch targets unchanged: each button keeps its full 44 × row-height hit
  area (`.contentShape(Rectangle())` on the 44 pt frame); the two areas
  meet at x 44 and do not overlap.
- Accessibility unchanged: "Inspect preview text" and "Preview actions",
  identifiers as today; Increase Contrast → `.label` at 0.75 opacity so
  glyph contrast on the key surface stays ≥ 3:1.
- Mockup: close-up "0" at the top of the artifact, beside the user's
  Telegram screenshot; screens/0-preview-icons.png.
  Why a button and not "tap the text": the row sits right above the keys and
  stray taps while typing must not open a panel; the Copy Image panel stays
  one tap away as today.
- `KeyboardTextPreviewLayout.actionsButtonWidth` becomes the 88 pt pair, so
  the excerpt Copy Image freezes still equals the visible text.
- Tap → freeze the excerpt exactly as drawn at that moment (before + after
  strings WITHOUT the "…" marks) and open the Inspect panel. Disabled while
  the Copy Image panel is open, and ellipsis disabled while Inspect is open.
- Always enabled otherwise (an empty preview opens the explicit empty state).

## 2. Inspect panel — container
Same overlay container as Copy Image so both feel like one family:
- Dim backdrop 18 % black over the whole keyboard; tap = Close.
- Card: width min(keyboard width − 16, 360) on iPhone; on iPad
  min(width − 32, 560). Height = keyboard height − 8 (4 pt top/bottom).
  Background secondarySystemGroupedBackground, radius 16, padding 16 sides,
  4 top, 12 bottom. Keys disabled underneath.
- Header, pinned, 44 pt: title "Inspect Text" (headline, isHeader) leading;
  trailing `xmark` 15 pt semibold secondary in a 44 × 44 target, label
  "Close". No Back button is needed (details expand inline).
- Body: vertical ScrollView, indicators visible.
- Footer, pinned, 12 pt above the card bottom: two equal buttons side by side,
  44 pt high, `.bordered` tinted accent, radius 10, 8 pt gap:
  "Copy Text" (`doc.on.doc`) and "Copy Code Points" (`number`), hint on the
  latter "Copies the code point sequence, not the original text."
  At accessibility text sizes (ViewThatFits): stack vertically; if the
  scroll area would drop below 88 pt, the footer moves to the END of the
  scroll content (header + Close stay pinned).
- Light/dark: semantic colors only; no new accent. Opening/closing: 0.2 s
  opacity fade; Reduce Motion: none.
- Dismiss (Close / backdrop / switching keyboards) restores typing with caret,
  shift and text untouched. Nothing inspected is stored.

## 3. Inspect panel — body (top to bottom, 12 pt spacing)
a) Sample. The frozen excerpt drawn exactly like the preview row (same
   per-character fonts, 18 pt, LTR before|caret|after, 2 pt accent caret),
   wrapping to at most 3 lines, inside a box: tertiarySystemFill, radius 10,
   padding 10, min height 44. Cut-off ends show the preview's "…" in
   secondary color; they are not text (not counted, listed or copied).
   Accessibility: label "Text preview", value = the excerpt.
b) Totals: one footnote line, wrapping, monospaced digits:
   "{n} code points · {n} grapheme clusters · {n} UTF-16 code units"
   (each part Camo's singular/plural form). Trailing `info.circle` 44 × 44
   (secondary) toggles, inline below, footnote secondary: "A grapheme
   cluster groups code points that form one text unit, such as a letter with
   an accent or a joined emoji. UTF-16 code units measure how the text is
   encoded."
c) Normalization chips: one row of 4 equal chips (2 × 2 at accessibility
   sizes), 32 pt high, radius 8, tertiarySystemFill, 8 pt gaps. Each: form
   name ("NFC", "NFD", "NFKC", "NFKD") footnote semibold + status symbol:
   `equal` = "Already in this form", `notequal` = "Differs from this form",
   `minus` = "Not available". Symbols and text in label/secondary colors —
   never green/red, these are facts, not errors. Tap any chip → scrolls to the
   Normalization section (f). VoiceOver per chip: "NFC, already in this form".
d) Section title "Code Points" (footnote semibold secondary, isHeader).
e) Grapheme cluster cards, original logical order (also for RTL), 8 pt apart.
   Card: tertiarySystemFill, radius 12, padding 8, HStack(top, 10):
   - Tile 44 × 44, secondarySystemGroupedBackground, radius 8: the cluster
     shaped naturally at 26 pt in the font Uniboard previews it with. Marks
     alone get the catalog's dotted-circle display; invisible/control code
     points get the catalog's placeholder display. Tile is decorative
     (accessibilityHidden).
   - Right column: one row per code point, in order, 0.5 pt separators
     (separator color) between rows; each row is a button ≥44 pt:
     line 1: "U+05D1" (13 pt semibold monospaced, LTR) then the name (13 pt,
       wraps, LTR, as the catalog spells it);
     line 2 (11 pt secondary): "{categoryName} ({cat}) · {blockName}".
     Trailing `chevron.down` 11 pt tertiary; rotates to up when open.
     Unassigned in the catalog edition: name slot reads "Unassigned in
       Unicode {version}" (secondary), line 2 shows only "{blockName}" if
       known.
     Metadata missing without that conclusion: "Not available" in the
       missing slot; never "Unknown character".
   - Expanded (inline, under its row, 6 pt top): label/value pairs in the
     keyboard's existing `property()` style (10 pt caps secondary label, 13
     pt value): "Code point" (U+XXXX, monospaced), "Name", "Category"
     ("Letter (Lo)" — the catalog's category names, as on the app's
     character pages; review msg369), "Unicode block" (or "No Unicode block" only when
     established), "Script" (only when metadata supports it). One row open at
     a time; opening another closes the first.
   - VoiceOver: card = container, label "Grapheme cluster {index}, {count}
     code points"; row label "U+05D1, HEBREW LETTER BET", value "{category},
     {block}", trait button, value adds "expanded"/"collapsed".
f) Section "Normalization": helper footnote "Normalization can change how
   text is represented. These checks don’t change your text." then 4 rows
   (min 44): form name (body semibold) + description beneath (footnote
   secondary: "Canonical composition", "Canonical decomposition",
   "Compatibility composition", "Compatibility decomposition"); trailing
   status words with the same symbol as the chip.
g) Footnotes (11 pt secondary), only those that apply:
   "Only the text shown in the preview is inspected. Your text won’t be
   changed." (always); "Markers for invisible characters and combining marks
   are shown only in the preview." (when a marker is drawn); "This is a
   snapshot of the preview. Reopen Inspect to check updated text." (always);
   "Character details use Unicode {catalog version}. Grouping and
   normalization use this version of iOS." (only when established).

## 4. Copy actions
- "Copy Text" copies the exact frozen excerpt (before + after, no "…", no
  markers). "Copy Code Points" copies the original scalars as
  "U+05D1 U+05BC …" (space-separated, 4–6 hex digits) — never normalized.
- Success: the tapped button's label becomes `checkmark` + "Text copied" /
  "Code points copied" for 1.5 s; VoiceOver announces it.
- Failure: a notice row above the buttons (`exclamationmark.triangle` orange
  + footnote): "Couldn’t copy text" / "Couldn’t copy code points" + "Try
  again. Your text hasn’t changed."
- Pasteboard restricted: same placement as the failure notice (row above
  the buttons, `exclamationmark.triangle` orange + footnote), buttons stay
  visible but disabled. Wording (Camo msg303):
  Full Access verified as the blocker: "To copy text or code points, allow
  Full Access for Uniboard in your keyboard settings. You can still inspect
  text and type without it."
  Cause not verified: "iOS isn’t allowing this keyboard to copy. You can
  still inspect text and type normally."
  Shown only when the panel knows copying is blocked (or after a tap fails
  for that reason); never blocks opening the inspector. Inspection itself
  never needs Full Access.
  With the notice showing, the cards may scroll (review msg369); the sample
  and totals line must stay visible without scrolling at Large text.

## 5. States (body replaced by a centered block; header + Close remain;
## footer hidden)
- Symbol 34 pt secondary, title headline, text footnote secondary,
  centered, 12 pt spacing; one "Close" bordered button 44 pt.
- Empty excerpt: `text.magnifyingglass` · "No text to inspect" · "Show some
  text in the preview, then choose Inspect."
- No host context: `text.badge.xmark` · "Preview text unavailable" · "This
  app hasn’t made text available to the keyboard."
- Known restricted field: `lock` · "Inspection unavailable here" · "This
  field doesn’t share text with the keyboard."
- Processing failure: `exclamationmark.triangle` · "Couldn’t inspect this
  text" · "Close and try again. Your text hasn’t changed."
- Never offer Full Access, clipboard or Open App as remedies.
- Processing is synchronous-fast for ≤72 characters; if it ever exceeds
  150 ms show a centered ProgressView in the body (no text).

## 6. Settings → Keyboard → Auto-Capitalization
- New row in the Keyboard section right after "Customize Keys":
  NavigationLink, LabeledContent "Auto-Capitalization", value = mode title.
  Identifier `keyboardAutoCapitalization`.
- Screen: List .insetGrouped, inline title "Auto-Capitalization".
  Section header text (sentence case, footnote): "Choose when letter keys use
  capitals automatically. This affects new typing, not existing text."
  Five rows, min 56, title (body) + description (footnote secondary),
  trailing accent checkmark on the selected one; tap = save immediately:
    "Follow App" — "Use the typing app’s capitalization preference." (default)
    "Off" — "Use capitals only when you choose Shift or Caps Lock."
    "Sentences" — "Start detected sentences with a capital letter."
    "Words" — "Start detected words with a capital letter."
    "All Characters" — "Use capitals for letter keys that support them."
  Footer: "Some fields turn off automatic capitals. Languages without
  capital letters are unchanged." + new paragraph "Custom key text, pasted
  text and symbols stay exactly as entered."
- Password/secure fields turn off all automatic English help (capitals,
  corrections, auto-period), matching the system keyboard; the setting
  never overrides this (review msg369).
- Keyboard: no new UI. The shift key shows the resulting state exactly as it
  does today for host-requested capitalization.
- Configuration import (font-rules spec §6a): the Settings disclosure lists
  "Auto-Capitalization: {old mode} → {new mode}" when it changes.
- VoiceOver: rows are buttons with isSelected; label "{title}", value
  "{description}".

## 7. Accessibility checklist
- All targets ≥44 × 44; Close never scrolls away; footer never off-screen.
- Settings header text near the top bar must render at the same color as
  the footer text (measured 1.85:1 vs 3.6:1 in build of msg369).
- Text uses label/secondary label (≥4.5:1 on both card fills, light/dark,
  Increase Contrast honoured by system colors). Status by symbol + words.
- Dynamic Type: all text uses text styles (sizes above are at Large);
  cluster cards switch to VStack (tile above rows) at accessibility sizes.
- RTL text: sample shaped naturally inside the LTR before|caret|after order;
  lists, identifiers and numbers LTR.

## 8. Not in this increment
Open-in-app, escape-format selector, desktop table, inspecting hidden
context or the clipboard, normalizing/replacing text, keyboard UI for
capitalization.
