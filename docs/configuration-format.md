# Uniboard configuration file — format v1

Status: specification for the font rules + TOML configuration increment
(`docs/font-rules-brief.md`, `docs/inspection-capitalization-brief.md`).
Batch B1 implements only the TOML codec (`Shared/TOMLDocument.swift`) and the
font rule engine (`Shared/FontRules.swift`). Nothing here changes app or
keyboard behavior until later batches wire the configuration in. The size
bound in §3 is fixed **before** the import code exists, as the brief requires.

## 1. Principles

- One portable, user-editable TOML file holds the whole user configuration.
  The app writes and reads it; the keyboard **never parses TOML**. The keyboard
  reads compiled JSON snapshots that are derived from the same validated
  configuration.
- Import parses and validates the **whole** file before anything is written.
  Errors are reported with a line and column (syntax) or a field path
  (schema). An invalid file changes nothing.
- Missing sections mean **factory defaults** (§5). The import preview shows
  them as resets. Nothing is silently merged.
- No font binaries, file system paths, URLs, downloads, typing history or
  bookkeeping are ever written (§8). Import never fetches anything.

## 2. TOML dialect

The file is TOML 1.0 (https://toml.io/en/v1.0.0) encoded as UTF-8, read by
`TOMLDocument.parse` and written by `TOMLDocument.write`. The parser is a
recursive-descent parser over Unicode scalars. It does not split lines.

Accepted:

- Comments, blank lines, LF and CRLF line endings, and an optional leading
  UTF-8 byte order mark.
- Bare, quoted (basic and literal) and dotted keys. Keys are compared by
  their exact Unicode scalars, never by canonical equivalence: `"é"` (U+00E9)
  and `"é"` (U+0065 U+0301) are different keys.
- Basic strings with every TOML 1.0 escape: `\b \t \n \f \r \" \\ \uXXXX
  \UXXXXXXXX`. Escapes that name a surrogate or a value above U+10FFFF are
  errors. Literal strings and both multiline forms are accepted, including
  the line-ending backslash and one or two quotes before a closing delimiter.
  A CRLF inside a multiline string reads as one LF.
- Integers: decimal, `0x` hex, `0o` octal, `0b` binary, with underscores
  between digits. Values outside 64-bit signed range are errors, not
  truncations.
- Floats, including exponents, `inf`, `nan` and signs. The parser accepts
  them; the schema below has no float fields except font axis values, and
  those must be finite.
- Booleans, arrays (multiline, trailing comma, mixed types), inline tables,
  `[table]` and `[[array.of.tables]]`.

Rejected, with a line and column:

- **Dates and times** (offset date-time, local date-time, local date, local
  time). They are recognized and rejected with "Dates and times aren't used
  in Uniboard configurations." They are not kept as strings.
- Invalid UTF-8, raw control characters (other than tab) in strings or
  comments, and a bare CR.
- Duplicate keys, a table defined twice, `[table]` redefining a table created
  by dotted keys, dotted keys extending a table defined with a header or
  implicitly by one, additions to an inline table, and mixing a static array
  with `[[array.of.tables]]`.
- Anything over the limits in §3. Limits are errors, never truncation.

Error messages are in the form "Check line {line}, column {column}: {reason}."
Columns count Unicode scalars from 1. A CRLF counts as one line break.

## 3. Limits

| Limit | Value | Where enforced |
|---|---|---|
| Whole file | **4,000,000 bytes ("4 MB")** | `TOMLLimits.maximumBytes`, checked before decoding |
| Nesting (tables and arrays around a value) | 16 levels | parser |
| One key | 256 UTF-8 bytes | parser |
| One string | 65,536 UTF-8 bytes | parser |
| One array or array of tables | 8,192 elements | parser |
| All values in the file | 500,000 | parser |
| Symbol pages (boards) | 16 | schema (`SymbolBoardStore.maximumBoards`) |
| Keys per page | 256 | schema (`SymbolBoardStore.maximumKeys`) |
| Variants / swipe choices per key | 16 | schema (`SymbolBoardStore.maximumVariants`) |
| Unicode scalars per key text or favorite | 64 | schema (`SymbolBoardStore.maximumTextScalars`) |
| Favorites | 4,096 | schema (`FavoriteSync.maximumCount`) |
| Enabled layouts | 1–8 | schema (`UnicodeEditionSettings.maximumLayouts`) |
| Font rules, all kinds | 1,024 | `FontRuleLimits.maximumRules` |
| Range rules | 256 | `FontRuleLimits.maximumRangeRules` |
| Distinct font faces referenced by rules | 256 | `FontRuleLimits.maximumFaces` |

Besides these, every compiled snapshot must still fit its existing store cap
(512 bytes edition settings, 256 KiB keys, 512 KiB pages, 512 KiB favorites,
1 MiB saved font rules, 1 KiB image colors, 256 bytes auto-capitalization).
The stores remain the authority on their own sizes.

**Why 4 MB.** Today's JSON stores together hold at most about 1.3 MB:
512 KiB pages + 512 KiB favorites + 256 KiB key mappings + 512 bytes of
settings. TOML spells structure out a little more than JSON (table headers
for each page and key), and the writer escapes invisible characters for
readability (§7). The worst case is a store full of tag characters
(U+E0020–U+E007F), 4 bytes each in UTF-8 and 10 bytes each as `\UXXXXXXXX`,
so 2.5 times larger: about 3.3 MB. Font rules add at most about 150 KB
(1,024 rules) and face references about 80 KB (256 faces). That is under
3.6 MB, so everything Uniboard can export also imports. A unit test in the
codec batch must build a maximal configuration and check that its export stays
within 4,000,000 bytes. Export refuses (it never truncates) if it somehow
doesn't. A 4 MB file also keeps the parsed tree well within the app's memory
budget: about 4 bytes per scalar plus bounded value counts. Import reads at
most 4,000,001 bytes and shows "This file exceeds the 4 MB import limit." for
anything larger.

## 4. Schema v1

Top level:

```toml
schema_version = 1        # required integer; anything else → unsupported
```

A missing `schema_version` is "The file is missing its configuration
version." Any value other than `1` is "This configuration version isn't
supported by this version of Uniboard." An unknown key anywhere is "Unrecognized
setting: {dotted.path}." Wrong types or ranges are "Check {field}: {expected}."
Duplicate ids or selectors are "{x} appears more than once."

Sections, with their preview category (the five rows in Review Import):

### 4.1 `[settings]` — Settings

| Key | Type | Default | Notes |
|---|---|---|---|
| `unicode_edition` | string | `"latest"` | `"latest"`, `"draft"`, or a bundled final version label (e.g. `"17.0.0"`) |
| `extra_unicode_fonts` | bool | `false` | Master switch. Also pauses or resumes font rules. Changes only through a confirmed import, and the preview lists it first |
| `private_use_area` | bool | `false` | Explore shows Private Use |
| `conscript` | bool | `false` | ConScript (CSUR) shown |
| `prefer_conscript` | bool | `false` | Private Use reads as ConScript |
| `text_preview` | bool | `false` | |
| `hide_keyboard_key` | bool | `false` | |
| `ipad_landscape_layout` | string | `"ansiNumbers"` | `stock` \| `ansi` \| `ansiNumbers` |
| `ipad_symbol_mapping` | string | `"standard"` | `standard` \| `iPad` \| `macOS` \| `none` |
| `auto_capitalization` | string | `"follow_app"` | **Reserved for the auto-capitalization addendum.** `follow_app` \| `off` \| `sentences` \| `words` \| `all_characters`. Any other value is an error. Until that feature ships, export writes `follow_app` and import accepts only the listed values |

Retired keys (the Top Row and Number Row switches the editable keyboard
layout replaced): `top_row`, `symbol_bar`, `search_instead_of_symbols` and
`number_row`. Export never writes them. Import accepts them with any value but
never reads or applies them, and they never count as a change: Review Import
lists each under "Ignored settings" (former name, then the key as written,
e.g. `settings.number_row`), and a file that differs only in them still shows
"No changes to import". The stored values stay as they are.

`[settings.browse]`:

| Key | Type | Default | Notes |
|---|---|---|---|
| `explore_grid_density` | int | `3` | 3 \| 8 \| 16 \| 32 |
| `block_grid_density` | int | `3` | 3 \| 8 \| 16 \| 32 |
| `tile_columns` | int | `3` | 2…256; the grid shows at most what fits its width |
| `explore_plane` | int | `-1` | −1 (all) or 0…16 |
| `explore_descending` | bool | `false` | |
| `emoji_sort_order` | string | `"codePoint"` | `newestFirst` \| `oldestFirst` \| `codePoint` |

### 4.2 `[keyboard]` — Layouts and Keys

```toml
[keyboard]
layouts = ["en"]               # 1…8 known, unique layout ids; the first is the default

[[keyboard.key]]               # one entry per changed key; ids unique
id = "letter.a"                # a KeyboardKeySettings key descriptor id
tap = ["á"]                    # absent = default; [] = explicitly disabled
shifted_tap = ["Á"]
long_press = []
swipe_up = ["ä"]
swipe_down = ["à"]

[[keyboard.arrangement]]       # per alphabet; layout ids unique
layout = "en"
keys = ["q", "w", "…"]
places = "kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
```

An **absent** gesture key means the default mapping. An **empty array** means
the gesture is explicitly disabled. Export keeps this distinction, and the
round trip preserves it exactly.

### 4.3 `[pages]` — Layouts and Keys

```toml
[pages]
star_page = "migrated-favorites"   # id of the page the star key opens

[[pages.page]]                     # display order; ≤ 16 pages
id = "stock-symbols"               # stable id, preserved exactly
name = "Symbols"
layout = "kkkkkkkkkk/…"            # optional SymbolPageLayout text

[[pages.page.key]]                 # ≤ 256 per page; not allowed under migrated-favorites
id = "stock.0"
text = "!"
variants = ["¡", "‼"]              # ≤ 16
up = ["…"]                         # optional; absent = off
down = ["…"]
```

`stock-symbols` and `migrated-favorites` must both be present. The Favorites
page's keys come from `[favorites]`. The last-used page is not configuration
and is never written.

### 4.4 `[favorites]` — Favorites

```toml
[favorites]
texts = ["★", "👩\u200D💻"]    # exact sequences in order; ≤ 4,096; ≤ 64 scalars each; unique by exact scalars
```

### 4.5 `[[fonts.face]]` and `[[font_rules.rule]]` — Font Choices and Rules

```toml
[[fonts.face]]
ref = "font-1"                 # [a-z0-9._-]{1,64}, unique within the file
source = "downloaded"          # included | downloaded | imported | installed
family = "Roboto"              # display only
style = "Bold"                 # display only
postscript_name = "Roboto-Bold"
sha256 = "…64 lowercase hex…"  # file identity; required unless installed
face_index = 0                 # 0…65535; with sha256
variations = { wght = 700.0 }  # 4-character OpenType axis tags, finite values
google_face = "google:<fileID>:<styleID>"   # optional hint, never trusted alone
in_library = true              # informational; import never adds or removes library fonts

[[font_rules.rule]]            # array order = saved order = equal-span tie-break
code_point = "U+16A0"          # exactly one of code_point | range | block
# range = ["U+2190", "U+21FF"] # inclusive
# block = "Runic"
# block_range = ["U+16A0", "U+16FF"]   # written on export; checked on import if present
# block_unicode_version = "19.0.0 draft"  # informational, written on export
font = "font-1"                # a fonts.face ref
```

A face reference is the font library's existing identity
(`FontFaceRecord.locator` in `Shared/FontLibraryContracts.swift`) without its
device-local `relativePath`:

- File faces (imported, downloaded, pack, included): `sha256` + `face_index`
  + `variations`.
- Installed faces (registered in the process): `postscript_name` +
  `variations`.

Filenames are never part of the identity. A file whose name matches but whose
SHA-256 differs is a different font. In code this is `FontFaceReference`
(`Shared/FontRules.swift`). Numeric CoreText axis identifiers are converted to
their 4-character tags so the reference is portable.

A malformed reference (bad hex, negative index, bad tag, non-finite value) is
an **error**: "The font reference in {field} isn't valid." A well-formed
reference to a font this device doesn't have is a **warning**. The rule is
kept and starts applying when the font is added. Import never downloads.

### 4.6 `[image_colors]` — Copy Image

The Copy Image colors and scale. The Review Import row and the Configuration
page call this section "Copy Image"; the table keeps the name `image_colors`
so existing files stay valid.

| Key | Type | Default | Notes |
|---|---|---|---|
| `preset` | string | `"blackOnWhite"` | `blackOnWhite` \| `blackOnClear` \| `whiteOnBlack` \| `whiteOnClear` \| `custom` |
| `custom_text` | string | `"#000000"` | `#RRGGBB` |
| `custom_background` | string | `"#FFFFFF"` | `#RRGGBB` or `transparent` |
| `image_scale` | integer | `3` | Copy Image resolution in pixels per point: `1`, `2` or `3`. Any other value (including `3.0` or `"3"`) is "Check image_colors.image_scale: 1, 2 or 3." Changes only the copied picture's pixel size and DPI (72 × scale), never its layout. A file without the key means `3`; the diff line reads "Image scale: 3× → 2×". Only the scale is stored; the pixel size the keyboard shows is never exported |

## 5. Factory defaults and absent keys

| Section missing | Result shown in the preview as a reset |
|---|---|
| `[settings]` / `[settings.browse]` | The defaults in §4.1 (Extra Unicode Fonts **off**, auto-capitalization Follow App) |
| `[keyboard]` | English only, no key overrides, stock arrangements |
| `[pages]` | The stock Symbols page plus Favorites; star opens Favorites |
| `[favorites]` | No favorites |
| `[[fonts.face]]` / `[[font_rules.rule]]` | No font rules (face entries alone carry no rules) |
| `[image_colors]` | Black on White, custom colors black / white, image scale 3 |

Inside a present section, an absent key means its default, and the diff lists
that change. The only exceptions are the per-gesture keys of
`[[keyboard.key]]` and the optional `up` / `down` / `layout` of a page key,
where absent means "default / off", as in today's stores.

## 6. Font rules

### Selectors

- **Code point**: one Unicode scalar value, U+0000…U+10FFFF excluding the
  surrogates U+D800…U+DFFF.
- **Range**: inclusive `[first, last]`. Both endpoints must be valid scalars
  (not surrogates), and `first ≤ last`. A range may *cross* the surrogate area.
  It then applies only to the valid scalars on either side.
- **Unicode block**: the stable block **name** from the base block table
  `Shared/Resources/Blocks.json` (`UnicodeCatalog.shared.blocks`, the draft,
  which includes every supported edition's blocks with identical bounds). It
  never matches the ConScript (CSUR) split of Private Use. The rule records the
  bounds and the block table's Unicode version. Validation requires an exact
  name match **and** identical bounds. Otherwise the result is "The Unicode
  block {name} isn't recognized." The version is informational, because a
  named block's bounds don't change between versions. Blocks made only of
  surrogates can't be used.
- Exact duplicate selectors (same code point, same range, same block name)
  are rejected, never hidden.

### Resolution

For each grapheme cluster, the **anchor** scalar picks the rules:

1. A code point rule for the anchor.
2. Every range containing the anchor, **smallest span first**. Span is the
   count of **valid scalars** in the range (surrogates excluded, so it matches
   the "{n} code points" shown in the editor). Equal spans: the **later** rule
   in the array wins.
3. The block rule for the block containing the anchor.
4. Otherwise, the existing default font behavior.

`FontRuleSet.candidates(for:)` returns the whole ordered list rather than one
winner. A caller tries each candidate's face in turn. If the face is missing,
or can't draw the **whole** cluster, it moves to the next one, and finally to
the default fonts. Rules for unavailable fonts are kept, so a font added later
activates them. `FontRuleSet` is compiled once from the rule list into an exact
dictionary plus sorted non-overlapping segments with precomputed candidate
lists. A lookup is one hash probe and one binary search, with no parsing or
allocation of rule data per keystroke.

### Grapheme anchor (limitation)

Rules are per scalar, but text is drawn per grapheme cluster, and clusters are
never split. The anchor of a cluster is its first scalar that is not a
combining mark (general category Mn, Mc or Me), not ZWJ/ZWNJ (U+200D/U+200C),
and not a variation selector (U+FE00–FE0F, U+E0100–E01EF, U+180B–180D,
U+180F). If there is no such scalar, the anchor is the first scalar. Mark
categories come from the OS's Unicode data, so a mark newer than the device's
Unicode version reads as a base. Consequences:

- `e` + U+0301 follows the rule for `e`. A rule for U+0301 alone applies only
  where U+0301 is the anchor, for example a mark with no base.
- `👩‍💻` follows the rule for U+1F469. VS16 and skin tone modifiers don't select
  rules.
- There are no sequence rules in v1. A face must support the whole cluster,
  otherwise the next candidate is used. Joining across clusters drawn in
  different fonts (for example cursive scripts with mixed rules) is not
  guaranteed.

## 7. Export

- Deterministic. Equal configurations produce byte-identical files. Keys are in
  schema order; array entries keep their saved order (pages, keys, favorites,
  rules).
- Strings are written as basic strings. `"` and `\` are escaped, and so are
  all C0/C1 controls and U+007F. For readability, invisible or confusable
  scalars are written as `\uXXXX` / `\UXXXXXXXX` escapes rather than raw:
  U+00AD, U+061C, U+180B–180F, U+200B–200F, U+2028–202E, U+2060–2064,
  U+2066–206F, U+FEFF, the variation selectors U+FE00–FE0F and
  U+E0100–E01EF, and the tags U+E0000–E007F. Every other scalar, including
  emoji, CJK and supplementary characters, is written as itself. Re-reading
  restores the exact scalar sequence, including ZWJ and variation selectors.
- Integers are decimal. Floats use the shortest form that round-trips and
  always include `.` or an exponent.
- Comments and formatting of an imported file are not preserved.

## 8. Never written

Scratchpad, recents and typing history, host text, search and caret state,
the last-used keyboard layout and page (`keyboardLayout`, `activeBoardID`),
download progress and state, tokens, device paths and filenames, caches, logs,
generation, lock and sync bookkeeping, and font binaries, licenses and
receipts. Favorites and custom key strings **are** exported and may be
personal. The Configuration screen says so before sharing.

## 9. On-device storage

The TOML file is only the exchange format. On the device each part is a
JSON snapshot in the App Group, in a versioned configuration location
(`Shared/SharedConfigurationLocation.swift`):

```
<group>/Configuration-v1/current.json   pointer: {schemaVersion:1, generation, directory, previous?, importFingerprint?}
<group>/Configuration-v1/g-000001/      one complete generation: the store files plus generation.json
<group>/Configuration-v1/staging-<uuid>/ an apply in progress
<group>/favorites-v1.lock               the single writer lock (also used by favorites sync)
```

A generation holds `unicode-edition-v1.json`, `keyboard-keys-v1.json`,
`symbol-pages-v1.json`, `favorites-v1.json`, `font-rules-v1.json`,
`image-colors-v1.json`, `auto-capitalization-v1.json` and
`app-presentation-v1.json` (the app's own browse preferences; the keyboard
never reads it). A missing file means the store's default, as before.
`image-colors-v1.json` (schema 1) carries the Copy Image preset, the two
Custom colors and `scale` (1, 2 or 3; absent in older files, meaning 3). The
keyboard keeps its own copy in its defaults (`copyImage.colors.*`,
`copyImage.scale`), adopts a new shared revision when the panel opens, and
writes the shared file only with Full Access, so a scale chosen without Full
Access stays in the keyboard, like its colors.

- **Readers** (app and keyboard) resolve the current directory through the
  pointer, once per refresh, and read every file from that directory. Before
  migration there is no pointer and they read the group root.
- **Migration** runs once, in the app at launch, under the lock. It copies the
  root files byte for byte (bounded by each store's own read limit, so an
  oversized file stays oversized) into `g-000001`. A root entry that isn't a
  readable regular file becomes an empty directory, so it stays unreadable
  instead of becoming "missing". Nothing is reset or repaired, and the root
  files are left untouched. An older build would still read them, but it
  would not see edits made after migration.
- **Apply** (import) takes the lock without waiting (busy: try again), checks
  that the configuration's fingerprint still matches the preview (SHA-256 over
  the generation number, every file's bytes and the live app preferences),
  stores the live app preferences in the current generation so it is a
  complete backup, writes and flushes a staging directory, reads every file
  back, renames it to the next generation and finally replaces the pointer
  atomically. That rename is the moment the keyboard sees the change. An
  interruption at any earlier step leaves the last good generation current.
- **Undo Last Import** is available while the pointer names a `previous`
  generation. It copies that backup into a new generation, so both processes
  notice: favorites get a new replacement id (they are adopted wholesale, not
  merged) and image colors a new revision. If anything changed after the
  import, the fingerprint differs and the app warns that those changes are
  replaced too.
- **Recovery** runs in the app at launch: it deletes staging directories,
  temporary pointers and generations other than the current one and the Undo
  backup. A damaged pointer is rebuilt from the newest complete generation
  (one whose `generation.json` lists only present files), or removed so
  migration starts again from the untouched root files. A pointer with a newer
  schema is never touched. The app then re-applies the generation's app
  preferences if it stopped before adopting them.
- **The keyboard** never migrates, applies or repairs. It writes only
  favorites (the existing sync) and image colors, only with Full Access, and
  always under the lock; image colors only after migration.
  Without Full Access, a color or scale chosen in the keyboard stays local and
  isn't exported (the Configuration page says so: "Copy Image colors and scale
  chosen in the keyboard without Full Access aren’t included in this file.");
  an imported color or scale still reaches it when the Copy Image panel opens.

