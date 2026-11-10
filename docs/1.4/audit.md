# Uniboard 1.4 — developer audit (code facts for scope)

Read-only audit of master @ d3f76b0 (1.3 build 52). File:line refs for the builder.

## 1. Symbol Keys vs the "Symbols" page — not the same thing
- "Symbols" (3rd row) is a stock symbol PAGE: 24 fixed keys (! ? @ # $ % & * ( ) + − = < > / ° © • → ✓ § _ |), saved with the pages (SymbolBoardStore, "keyboard.symbolBoards.v1"). Editing it changes that page's keys and their swipe/hold choices.
- "Symbol Keys" (2nd row) edits the keyboard's own 123 and #+= keys (and iPad extra rows) — saved as key settings ("symbol.XXXX" overrides), like letters in Main Keyboard.
- Some characters appear in both, but each keeps its own data. Editing "!" on the Symbols page does not change "!" on the 123 keyboard, and vice versa.
- Removing the Symbol Keys row today would lose, with no other route in the app: swipe/hold editing of 123/#+= keys, the customised dot, per-key restore, the key search, and Restore All Key Defaults (the only place it exists; it also resets letters, digits and every layout's arrangement). Saved data would stay and keep working (also editable via Settings → Configuration).

Recommendation (pick one; design decides placement):
- A (recommended): fold it into Main Keyboard. Main Keyboard gets an "ABC / 123 / #+=" switch at the top, mirroring the real keyboard. 123 and #+= show those keys, tap a key → same layer editor. Restore All Key Defaults moves to Main Keyboard's ⋯ menu (next to Standard Layout) with the 1.3 confirmation text unchanged. Search stays (pull-down on 123/#+=). Nothing lost, one row fewer, and it matches where people see those keys.
- B: fold it into the Symbols page. Not recommended: that page is a different keyboard page with its own keys; merging would blur which "!" you are editing.
- Either way: no data migration; the read-error text (KeyboardKeyPreferences.swift:91, names "Keyboard → Symbol Keys") must be reworded.

## 2. Emoji categories
- Each emoji already carries its Unicode/CLDR group and subgroup (e.g. "Smileys & Emotion", "People & Body", … 9 groups incl. Component). Today groups are used only for search text and the detail sentence. The grid is flat, sorted by the existing "emoji sort order" menu (newest / oldest / code point). The load re-sorts by code point, so CLDR group order is not kept.
- The keyboard's emoji section is also a flat grid; no categories shown there either.
- No visibility/filter preference exists anywhere.
- To add show/hide per group: group list (+ CLDR order) in EmojiCatalog; a preference shared with the keyboard (App Group, not app-only); filter in the app grid AND the keyboard's emoji grid + search; add `settings.browse` key in the configuration file (next to emoji_sort_order) + diff/round-trip tests.
- Scope question for design/copy: one preference for both app and keyboard is easy and consistent; recommend it applies to both, and that search respects it (with the "categories shown" empty state + Show All). Favorites/pages are unaffected.

## 3. Emoji zoom
- Character grids (Explore, block detail) already have pinch-to-zoom: pinch steps the column count ±1, remembered, and already saved in the configuration file (`settings.browse.tile_columns`). Blocks detail also has a density menu.
- Emoji grid has fixed columns and a fixed 34pt glyph; no zoom. Emoji detail shows a fixed 92pt glyph.
- Reuse: same pinch + column steps for the emoji grid, with glyphs scaling to tile size. Recommend its own remembered value (emoji tiles are wider) and a config-file key. Display only; inserted/copied text unchanged.
- Optional: larger glyph in the emoji detail sheet ("Enlarge").

## 4. Block sorting
- Blocks list is in code-point order (as loaded); there is no sort option today.
- Values already on each block and shown on the block card: start code point, size (range length), assigned character count, first Unicode version.
- "High to low / low to high" is ambiguous — recommend a Sort menu with key + direction: Code Point (default), Characters (assigned count), Unicode Version; each Low→High / High→Low. Minimum for Natun's ask: Code Point both ways. Assigned count must be cached before sorting (computed per call today). Remember choice; search keeps the sort.

## 5. Scripts — current and proposed
Current: Latin ×15 (en de fr es it pt sv fi nb da pl cs hu ro tr), Greek, Cyrillic ×4 (ru uk bg sr). Model: Apple stock iOS arrangements, 3 rows of ≤12 keys, one character per key, long-press variants, capitals via uppercase (no separate shifted layer), no composition/marked-text engine.

Direct entry (one key = one character; fits the model):
1. Armenian — Apple iOS Armenian layout. Cased (Shift works as today). 38 letters vs 36 slots → 2 on long-press. Easiest.
2. Hebrew — Apple iOS Hebrew (SI-1452 based; rows 8/10/9). Caseless, right-to-left text.
3. Arabic — Apple iOS Arabic. Caseless, RTL; letter joining is done by iOS, no keyboard logic. Exact rows to be verified against iOS before building.
Engineering notes for these: Shift key does nothing for caseless scripts (hide or disable it); caseless keys currently get no per-key IDs, so their swipe/hold choices can't be customised until the ID scheme is extended (in-scope work); key grid stays left-to-right like iOS; text preview already handles RTL; mixed-direction checks needed.

Needs a shifted layer (not in model yet): Georgian (also Shift would produce Mtavruli capitals), Thai Kedmanee, Devanagari InScript.
Needs a composition engine (separate project): Korean Hangul (jamo → syllables), Japanese kana/kanji.

## 6. Other small, related improvements (ranked)
1. Emoji grid order: keep CLDR group order when sorted "by category" (fits the category feature).
2. Per-key "Restore defaults" in Main Keyboard (only per-layer reset there today).
3. Block sort by assigned count / version (values already shown).
No TODO/FIXME markers in the code.
