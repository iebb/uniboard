# Uniboard — Inspect Text: copy each form, UTF-8 and UTF-16 (addendum)

24 Oct 2026 · user msg489 ("for 4 decomposition forms, add a copy icon, and
use small text to show codepoints if it differs, and add display of utf8 and
utf16 (also add copy)"), Ato msg493 (copy icon on NFC/NFD/NFKC/NFKD, small
code point text when the form differs, each copies that form's text without
changing the input; UTF-8 bytes and UTF-16 code units as clearly labeled hex,
each with its own copy, from the same inspected excerpt).
Task: task.86bcdd2f. Extends `design/inspect/design.md` §3f (Normalization
section) and §4 (copy actions); everything there still holds unless changed
here. The chips at the top (§3c), the cluster cards and the footer (Copy Text /
Copy Code Points) are unchanged.

Mockups: artifact "Uniboard — Inspect Text & Auto-Capitalization" v9, screens
9–11 under "New for 1.3.0" (illustrative; the panel is drawn at the grown
keyboard height). Screenshots beside this file: `9-forms-copy.png`,
`10-encodings.png`, `11-long-text.png`. Dashed orange only marks what's new.
Where a picture and this text disagree, this text wins.

"The excerpt" below = exactly what Copy Text copies today: the frozen
before + after text, no "…", no markers.

## 1. Normalization rows (replaces the §3f row layout)
Section title, helper footnote and 0.5 pt separators unchanged. Each row,
min height 44, 5 pt top/bottom padding, HStack(alignment: .top, spacing 8):

Left column, fills, VStack(leading, spacing 2):
- Line 1: HStack(firstTextBaseline, spacing 8): form name ("NFD", body 17
  semibold, `.primary`) + status: SF Symbol (`equal` / `notequal` /
  `minus`, as today) + words ("Already in this form" / "Differs from this
  form" / "Not available"), footnote 13, `.secondary`. The status moves from
  the trailing edge to here to make room for the copy button. At
  accessibility text sizes (ViewThatFits) the status wraps under the name.
- Line 2: description, footnote 13 `.secondary` (unchanged).
- Changes — only when the status is Differs. 4 pt below line 2, one line per
  changed grapheme cluster, caption2 11 pt, `.secondary`, LTR:
  `{cluster}  U+0065 U+0301 → U+00E9`
  - {cluster} = the original cluster drawn at 11 pt in the regular system
    font, `.primary`, with the catalog's dotted-circle / placeholder display
    for marks and invisible characters (same as the cluster tiles). Then two
    spaces, then the original code points, " → " (U+2192 with spaces), the
    normalized code points. Code points use the app's "U+XXXX" format
    (4–6 hex digits), monospaced, single spaces. Wraps only between code
    points.
  - Computed per original grapheme cluster: normalize the cluster alone and
    compare scalars. Order = first appearance. Identical changes (same
    before and after) are listed once, with " ×3" (secondary) appended when
    the change happens more than once.
  - At most 4 lines. More distinct changes → a 5th line "+{n} more"
    (n = distinct changes not shown). No expansion: copy always gives the
    whole result.
  - Safety: if joining the per-cluster results doesn't equal normalizing the
    whole excerpt (rare reordering across cluster boundaries), show no change
    lines at all. The status still says Differs. Never show a change that
    isn't exact.
  - Why only the changes: the excerpt can be 60+ code points, which would be
    10 lines per row × 4 rows. The changes point at exactly what differs and
    keep each row to 1–3 lines.

Trailing: copy button, 44 × 44 target, borderless, `doc.on.doc` 17 pt
regular, accent tint. Its top aligns with the row top, so the glyph centers on
line 1. Disabled look: `.tertiaryLabel`.
- Enabled for Already and Differs (Already copies text equal to Copy Text;
  kept so the four rows behave the same). Disabled for Not available, where
  iOS's Unicode is older than the catalog and the result could be wrong.
- Copies `form.normalize(excerpt)` as plain text. Never touches the app's
  text, never changes what the panel shows.
- Success: the glyph becomes `checkmark` (accent, same size) for 1.5 s, the
  same timing as the footer buttons. VoiceOver announces "{form} text copied".
  One confirmation at a time: any other copy in the panel ends the previous
  checkmark.
- Failure or blocked: the same notice row above the footer buttons as §4
  (orange triangle + footnote). When copying is known to be blocked (Full
  Access), every copy button in the panel is disabled together with the
  footer buttons.

Accessibility: the left column is one element: label "NFD, canonical
decomposition", value "differs from this form" plus, when shown, each change
line as written. The copy button is its own element, label "Copy NFD text",
trait button. The chips at the top keep their labels.

## 2. New section "Encodings" (after Normalization, before the footnotes)
- Title "Encodings": footnote semibold `.secondary`, isHeader, 12 pt above
  it (body spacing as today). No helper line.
- Two rows, same row model as §1 (min 44, separators, HStack top, trailing
  44 × 44 copy button):
  - Line 1: "UTF-8" (body 17 semibold) + "{n} bytes · hex" (footnote
    `.secondary`). UTF-16 row: "UTF-16" + "{n} code units · hex".
    Singular "1 byte · hex" / "1 code unit · hex".
  - Value, 4 pt below: footnote 13 monospaced, `.primary`, LTR, uppercase
    hex, no prefix. UTF-8 = 2 digits per byte. UTF-16 = 4 digits per code
    unit (the Swift String's `utf16` view, the same count as the totals
    line, no byte-order mark, surrogates shown as their own units, e.g.
    "D83D DE04"). Values separated by single spaces. Wraps only between
    values, never inside one.
  - Collapsed by default: at most 3 lines. Cut only between values (rev.
    2, review msg600): the value is monospaced, so compute how many whole
    values fit in 3 lines with room for " …", show those, then " …". Never
    end on part of a value ("00…" reads as a real byte). Only when it's
    actually truncated, a "Show All" text button appears under the value: footnote
    semibold, accent, leading, 32 pt tall visually inside a 44 pt hit area.
    It expands the value fully, and the label becomes "Show Less". Each row
    expands on its own. Not remembered (the panel is a snapshot).
  - Copy copies the full value as shown when expanded: single spaces, no
    line breaks, no "…", no label. Same success, failure and blocked
    behaviour as §1. Announcements: "UTF-8 hex copied", "UTF-16 hex
    copied" (§4).
- Width check (iPhone, 328 pt inner card width, 276 pt for the value): 13 pt
  monospaced ≈ 7.8 pt per character → 11 bytes or 7 code units per line, so
  3 lines hold 33 bytes or 21 units. The sample "Café 👩🏽‍💻 x²" (26 bytes,
  16 units) fits uncollapsed. Longer excerpts get Show All.
- Accessibility: left column = one element, label "UTF-8, 26 bytes, hex",
  value = the full hex string (whether or not it's collapsed). Show All
  button label "Show all UTF-8 bytes" / "Show fewer UTF-8 bytes". Copy button
  label "Copy UTF-8 hex" / "Copy UTF-16 hex" (§4).
- Empty excerpt: the panel's existing empty state; the section isn't shown.

## 3. Unchanged
- Totals line, chips, cluster cards, footnotes, footer buttons, container,
  panel height and scrolling. The body simply gets taller and scrolls.
- Nothing is normalized, stored or logged; inspection never needs Full
  Access, copying does (§4).

## 4. Strings (final, Camo msg504)
Visible: "Encodings" · "{n} bytes · hex" / "1 byte · hex" · "{n} code units
· hex" / "1 code unit · hex" · "Show All" / "Show Less" · "+{n} more" ·
"×{n}".
VoiceOver: copy buttons "Copy NFC text" (…NFD, NFKC, NFKD), "Copy UTF-8
hex", "Copy UTF-16 hex"; hint on the two encoding buttons "Copies the full
hexadecimal value". Announcements "NFC text copied" (…), "UTF-8 hex
copied", "UTF-16 hex copied". Show buttons "Show all UTF-8 bytes" / "Show
fewer UTF-8 bytes" (same for UTF-16). "+{n} more" is read as "{n} more
changes"; "×{n}" as "{n} occurrences".
Failures (notice row): "Couldn’t copy {form} text" / "Couldn’t copy UTF-8
hex" / "Couldn’t copy UTF-16 hex", then "Try again. Your text hasn’t
changed."
Verified Full Access restriction (replaces the old sentence for the whole
panel): "To copy from the inspector, allow Full Access for Uniboard in your
keyboard settings. You can still inspect text and type without it." Cause
not confirmed: keep the neutral sentence as today.

## 5. Checks (developer)
1. Host "Café 👩🏽‍💻 x²" typed with e + U+0301: NFC row shows
   "é  U+0065 U+0301 → U+00E9". NFD says Already, with no change lines.
   NFKC shows that line plus "²  U+00B2 → U+0032". NFKD shows only the ²
   line.
2. Copy on NFC, then paste into the app's Explore search: the é is U+00E9.
   The host text is still e + U+0301 afterwards.
3. UTF-8 for that sample = "43 61 66 65 CC 81 20 F0 9F 91 A9 F0 9F 8F BD
   E2 80 8D F0 9F 92 BB 20 78 C2 B2" (26 bytes). UTF-16 = "0043 0061 0066
   0065 0301 0020 D83D DC69 D83C DFFD 200D D83D DCBB 0020 0078 00B2"
   (16 units). Copy gives exactly those strings.
4. An excerpt over 33 bytes / 21 units, e.g. "“So far so good,” she said
   😄 and left" (44 bytes, 38 units) when the row shows all of it: both
   values show 3 lines + Show All. Copy gives every value. Show All
   expands, Show Less collapses.
5. Five decomposed é's in the excerpt → one NFC change line ending " ×5".
   Seven distinct changes → 4 lines + "+3 more".
6. Without Full Access: the notice shows and every copy button is disabled.
   Inspecting still works.
7. Largest accessibility text size: status wraps under the form name, every
   target stays 44 × 44, and nothing is clipped (the body scrolls).
