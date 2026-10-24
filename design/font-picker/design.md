# Uniboard — Preferred Font picker: every font Uniboard can use, with search

24 Oct 2026 · user msg475 ("since app can read all fonts installed and all
these extra fonts, make them as selection and add a basic search to
filter"), Ato msg476 (every font the app can access — system, installed,
bundled, downloaded; search by family or style; keep the selected font
visible; don't limit the list to saved favorites; fonts only the app can use
are labeled clearly, never promised to work on the keyboard).
Task: task.9e503146. Rev. 3 (build review msg578): §2 representative
face and style-row indent. Rev. 2 (Camo msg526): two keyboard tags, final
footers, search prompt casing, VoiceOver counts families. Replaces `design/font-rules/design.md` §4 (Font Picker)
where they differ; the sample header, the Extra Unicode Fonts notice, the
"representative characters" rule, save-on-tap and the 0.25 s pop are
unchanged. Code: `App/FontRulePickerView.swift` (one screen, used from
character detail and from the rule editor).

Mockups: artifact "Uniboard — Preferred Font picker" (illustrative fonts,
web stand-ins for iOS fonts; Roboto Medium Italic is the chosen font).
Screenshots beside this file: `1-picker.png`, `2-expanded.png`,
`3-search.png`, `4-block-checking.png`, `5-end-of-list.png`,
`6-no-results.png`. Dashed orange only marks what's new. Where a picture
and this text disagree, this text wins.

## 0. What's in the list (from the source audit)
Today the picker drops `.system` and `.available` faces
(`FontRulePickerModel.Group.init`), so only Your Fonts / Google Fonts /
Preview Fonts show. And the search field is in the navigation bar drawer,
which is hidden until you pull the list down — that's why it reads as
"no search". Both change.

Sections, in this order, each only when it has rows:

| Section header | FontSource | Keyboard can draw it? |
|---|---|---|
| Your Fonts | `.imported` | yes (file in the shared container) |
| Your Fonts | `.installed` (chosen in the iOS font list) | tag unless confirmed (§4) |
| Google Fonts | `.downloaded`, not `pack:` | yes |
| Preview Fonts | `.included` + `.downloaded` `pack:` | yes |
| System Fonts — NEW | `.system` (/System/Library/Fonts) | yes |
| Other Device Fonts — NEW | `.available` | tag unless confirmed (§4) |

Never list: PostScript names starting with "." (private system UI faces,
e.g. `.SFUI-Regular`; the iOS system font is what "default fonts" means) and
`LastResort` (it draws a placeholder box for every code point, so it would
"support" everything). Nothing new is downloaded; not-yet-downloaded Google
Fonts stay in Font Downloads.

## 1. Screen, top to bottom
List `.insetGrouped`, inline title "Preferred Font" (unchanged).

1. Search field, always visible:
   `.searchable(text:, placement: .navigationBarDrawer(displayMode: .always),
   prompt: "Search family or style")`, `.autocorrectionDisabled()`,
   `.textInputAutocapitalization(.never)`.
2. Sample header (unchanged: 96 pt box with the 64 pt glyph for a code
   point; 64 pt strip for a range/block).
3. Notice when Extra Unicode Fonts is off (unchanged).
4. **Selected** section — only when a font is chosen (§3). Always shown,
   whatever the search says, so the chosen font never scrolls or filters out
   of sight.
5. Checking row while support is being checked (§5).
6. The font sections from §0, as **family rows** (§2).
7. "Show {n} Unsupported Fonts" disclosure (§5).
8. Last section, unchanged: header "If a font is missing or can’t display
   the text, Uniboard tries the next matching rule, then its default fonts."
   + NavigationLink "Font Downloads" (`arrow.down.circle`).

"Clear Preference" moves out of the last section into the Selected section
(§3): with a few hundred families the end of the list is far away.

## 2. Family rows and style rows
Faces are grouped into families by (section, `record.family` exact). The list
shows one row per family, not per face — downloaded Roboto alone is 36 faces.

Style order inside a family (also used to pick the representative):
width (normal first, then narrower → wider), then weight 100 → 900, then
upright before italic — so each italic follows its upright: Thin, Thin
Italic, … Regular, Italic, Medium, Medium Italic … (same rows as the
coming styles grid). Weight = `wght` variation if set, else `kCTFontWeightTrait` mapped to
100–900; width = `wdth` or `kCTFontWidthTrait`; italic = `kCTFontItalicTrait`,
an `ital`/`slnt` instance, or a style name containing "Italic"/"Oblique".
**Representative face** (rev. 3, review msg578) = the face with the
lowest (normal width ? 0 : 1, italic ? 1 : 0, |weight − 400|, weight).
So normal width beats other widths, upright beats italic, then the weight
closest to 400 (ties → the lighter). A family with only italics shows
Regular Italic, never Thin Italic, whose hairline glyph looks like a
dimmed (unsupported) row.

### Family row (min height 56, HStack spacing 12)
- Leading 44×44 tile, radius 8, existing `FontRuleTile` /
  `FontRuleFaceTile`, drawn in the representative face (same rules as today:
  single code point → that character; range/block → first representative
  character the face draws, else the system rendering at 40 %).
- VStack(leading, spacing 2):
  - Family name, body 17 `.primary`, up to 2 lines.
  - Subtitle, caption 12 `.secondary`: one face → its style name
    ("Regular" when empty); several → "{n} styles"; while searching and only
    some faces match → "{k} of {n} styles".
  - Range/block only: coverage caption of the representative face
    ("Supports {n} of {m} code points"; small ProgressView until known).
  - Keyboard tag (§4) when every face in the family has the same one.
- Trailing: checkmark (`checkmark`, semibold, accent) when the selected face
  is in this family — also while collapsed; then, for several faces, the
  disclosure chevron.
- One face: the row is the face — tap chooses it (save / return, pop after
  0.25 s, at once with Reduce Motion; unchanged).
- Several faces: `DisclosureGroup` (native chevron + VoiceOver
  expanded/collapsed). Tap anywhere on the row expands/collapses; it never
  chooses. Collapsed by default, including the family holding the selection
  (the Selected section already names it). Expansion is remembered while the
  picker is open.

### Style row (inside an expanded family; min height 48)
- The style tile starts 20 pt right of the family tile. DisclosureGroup
  in an inset-grouped List already indents children by that much, so add
  no padding of your own (rev. 3: the build measured 40 pt).
- 36×36 tile, radius 8, 22 pt glyph, drawn in THIS face.
- Title: style name, body 17. Caption lines as the family row (coverage for
  range/block; "Can’t display this character" for a single code point when
  this face is verified unable; keyboard tag only if the family row has none).
- Trailing checkmark when chosen. Tap chooses.
- Two faces with the same style name in one family (different files): add
  the PostScript name to the caption, monospaced 12, `.secondary`.

## 3. Selected section
Header "Selected". Rows:
1. The chosen face as one row (not a family): tile in that face, title =
   family name, subtitle = "{style} · {section name}" (e.g. "Bold Italic ·
   Google Fonts"), keyboard tag if it has one, trailing checkmark. Tap =
   choose it again (same as any font row: saves and pops).
   Missing file: tile in system rendering at 40 %, subtitle line 2 = orange
   `exclamationmark.triangle.fill` + "Font unavailable" (existing string).
2. Character-detail mode, when this code point has its own rule:
   "Clear Preference" (accent, leading-aligned, not destructive). Section
   footer = the existing after-clearing caption ("Using Noto Sans Runic ·
   Unicode block rule Runic" / "Using default fonts").
No chosen font → no Selected section at all.

## 4. Keyboard tags: "App Only" and "Keyboard Unverified" (rev. 2, Camo msg526)
Faces from files (Imported, Google, Preview) and System Fonts never get a
tag. Installed and Other Device faces get exactly one of three states:
- confirmed on the keyboard → no tag;
- confirmed NOT on the keyboard → "App Only";
- no evidence either way → "Keyboard Unverified".
Missing confirmation never becomes "App Only".

Confirming (recommended, small): each time the keyboard appears, it writes
the set of PostScript names `CTFontManagerCopyAvailablePostScriptNames()`
returns in the keyboard process, plus the iOS version, to the app group
(skip the write when unchanged). With a report from the current iOS version:
name in the set → no tag; name not in the set → App Only. No report, or one
from another iOS version → Keyboard Unverified. If the report doesn't fit
1.3.0, every Installed / Other Device face is Keyboard Unverified. If your
mapping proves any other source can't be drawn by the keyboard, it gets App
Only.

Tag (both texts, same look): caption2 11 pt semibold, `Color(.label)` on a
Capsule filled with `Color(.tertiarySystemFill)`, padding 6 h / 2 v, on its
own line under the subtitle (never truncates the name). Contrast ≥ 15:1
light, ≥ 12:1 dark. No symbol, no orange: the font works in the app.
A family row shows a tag only when every face in it has that same tag;
otherwise each style row shows its own.

Section footers (each only when that section has at least one such row;
both may appear, App Only first):
- App Only: "These fonts are available in the app, but not the keyboard.
  The keyboard uses the next matching rule or its default fonts."
- Keyboard Unverified: "Available in the app. Keyboard availability hasn’t
  been confirmed."

The same tag appears in Settings › Font Rules on a rule row whose font has
one (under the trailing font name; at accessibility sizes it stacks with
it). Nowhere else.

## 5. Checking support and order
- Inventory: spinner row (unchanged) until faces are listed — target ≤ 1 s
  with ~1,200 faces. Rows render lazily; no font is loaded for off-screen
  rows.
- Then support checks (existing proofs for a code point, existing
  `FontRangeCoverage` for a range/block), in this order: the selected face,
  then faces in display order; while a search is active, matching faces
  first. Coverage for faces sharing one file + instance is computed once.
- While checking: a row right after the Selected section — small
  ProgressView + "Checking Fonts… {checked} of {total}" (footnote 13,
  `.secondary`, numbers formatted). Sections are alphabetical (localized,
  case-insensitive by family) and **don't move**. A row shows its result as
  soon as it is known: coverage caption for a range/block; a face found
  unable (code point) or with 0 coverage dims to 40 % and is disabled in
  place. Everything not yet checked stays enabled.
- When all checks finish, reorder once (List default animation; none with
  Reduce Motion), and the checking row disappears:
  - In each section: families whose best face can draw it first, then
    unknown / missing, alphabetical within each.
  - Families where every face is verified unable (code point) or supports 0
    (range/block) leave their section and go behind the last disclosure
    "Show {n} Unsupported Fonts" (n = families). Expanded footer: code point
    "These fonts can’t display this character." (existing); range/block
    "These fonts can’t display any of these characters." Rows inside are
    disabled at 40 % (unchanged).
  - A verified-unable face inside a family that has other usable faces
    stays in place, disabled at 40 %, with its caption.
  - A face still unknown or whose file is missing is never counted as
    unsupported (unchanged).
- Check failed: the existing "Couldn’t check font support / Try again in a
  moment. Results are incomplete." replaces the checking row; nothing is
  disabled.

## 6. Search
- Split the query on whitespace. Each word must appear in the face's family
  name, style name or PostScript name (`localizedStandardContains`: case-
  and diacritic-insensitive). So "roboto bold" finds Roboto's Bold styles,
  "helvetica" finds Helvetica and Helvetica Neue, "ExtraLight" finds every
  ExtraLight face.
- A family whose name contains every word shows normally (collapsed, all
  styles). Otherwise, a family with matching faces shows **expanded**, with
  only the matching faces, subtitle "{k} of {n} styles". Forced expansion
  doesn't change the remembered expansion; clearing the search restores it.
- Sections and the unsupported disclosure show only matches; empty sections
  hide. The Selected section and the last section always stay.
- No results: one section after Selected with a single row, body
  `.secondary`: "No fonts match “{query}”." The last section (Font Downloads)
  sits right under it.
- Filtering runs on every keystroke from precomputed lowercase keys; it must
  stay under 16 ms for 1,500 faces (no debounce needed). VoiceOver: 0.5 s
  after typing stops, announce "{n} font families" / "1 font family" /
  "No fonts".

## 7. Accessibility
- Family row: one element. Label "{family}". Value, joined with ", ":
  "{n} styles" (or the style for one face), "{style} selected" when the
  chosen face is inside, coverage caption, then the tag: "App only, not
  on the keyboard" or "Keyboard unverified". Expanded/collapsed comes from DisclosureGroup. Tiles hidden.
- Style row and Selected row: label "{family} {style}"; value = coverage /
  "Can’t display this character" / the tag as above;
  `.isSelected` when chosen.
- Checking row: label "Checking fonts, {checked} of {total}"; no per-step
  announcements.
- Dynamic Type to AX5: family names wrap to 2 lines then truncate tail; the
  tag stays on its own line; tiles stay 44 / 36 pt.
- Light and dark use only semantic colors; nothing new is color-only.

## 8. Strings for Camo (all proposed; [design])
- Search prompt: "Search family or style" (was "Search fonts") — Camo ✓
- Headers: "Selected", "System Fonts", "Other Device Fonts"
- "{n} styles", "{k} of {n} styles" (one face shows its style name instead)
- "App Only" / "Keyboard Unverified"; VoiceOver "App only, not on the
  keyboard" / "Keyboard unverified"; "{style} selected"
- Footers: Camo's two sentences in §4 (final)
- "Checking Fonts… {checked} of {total}"; VoiceOver "Checking fonts,
  {checked} of {total}"
- "Can’t display this character"
- "These fonts can’t display any of these characters."
- "No fonts match “{query}”."; VoiceOver "{n} font families" / "1 font
  family" / "No fonts" (Camo: count families, keep style counts separate)
- Unchanged: Your Fonts, Google Fonts, Preview Fonts, Show {n} Unsupported
  Fonts, Font unavailable, Clear Preference, Font Downloads, the fallback
  header, Couldn’t check font support.

## 9. Checks
1. Character detail → Set Preferred Font for Ω U+03A9 on the simulator:
   System Fonts lists Arial, Georgia, Helvetica Neue, Times New Roman among
   others; no name starts with "."; no LastResort.
2. The search field is visible on open without pulling the list.
3. "roboto bold" (with Roboto downloaded): only Roboto, expanded, showing
   only faces with "Bold" in the style (Bold, SemiBold, ExtraBold and their
   italics), subtitle "{k} of 36 styles". "helvetica": Helvetica and
   Helvetica Neue, collapsed.
4. With a font chosen, the Selected row stays at the top through any search,
   including one with no results.
5. A multi-style family is collapsed on open; tapping it expands without
   choosing; tapping a style chooses it, shows the checkmark, pops after
   0.25 s.
6. The family holding the chosen face shows a checkmark while collapsed.
7. Installed and Other Device faces show "Keyboard Unverified" until the
   keyboard has reported; after it has, absent names show "App Only" and
   present names show no tag. Matching footers appear; a Font Rules row
   using such a face shows the same tag. System, Imported, Google and
   Preview faces never show a tag.
8. While checking, the checking row counts up and rows don't move (found-
   unable rows only dim); after it finishes, one reorder; fully unsupported
   families are behind "Show {n} Unsupported Fonts".
9. Greek and Coptic block picker: family rows show coverage captions as they
   finish; families with 0 go behind the disclosure with the range footer.
10. A code point with its own rule: Clear Preference is in the Selected
    section, with the caption under it; it clears and pops as today.
11. ~1,200 faces: list on screen ≤ 1 s after opening; typing 5 characters
    drops no frames.
12. VoiceOver reads a family row as name, style count, selected style, App
    Only, expanded/collapsed; the result count is announced after typing.
13. AX5 and dark mode: no clipped names, tag on its own line, all text
    readable.
