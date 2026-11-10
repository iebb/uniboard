# Uniboard 1.4 — Symbols page and row alignment copy

Final copy for design rev. 1 §7 / msg833. Engineering owns the exact limits and compatibility; substitute actual verified capacity for {limit}. Current design proposes 12 standard-key widths, not 12 keys.

## Page controls
- Helper: **Tap a key to change its choices. Drag a key to move it.**
- Add rows: **Add from Unicode**, **Add Text**.
- Full page: **This page is full. Remove a key to add another.**
- Empty page title: **No keys yet**.
- Empty page helper: **Choose characters from Unicode or add your own text.**
- Favorites empty helper: **Save characters to add them here.**
- Toggle: **Opens with ★**. Accessible label: **Open this page with the star key**.
- Custom/Symbols page footer: **When on, the ★ key opens this page instead of Favorites.**
- Favorites footer: **When on, the ★ key opens Favorites.** Never say instead of Favorites on Favorites itself. Match actual toggle behavior; if it is permanently true there, avoid presenting a nonfunctional switch.

## Alignment
- Card: **All Rows**, **Row {n}**, **Mixed**.
- Segments: **Left**, **Center**, **Right**, **Spread**.
- All-rows helper: **Select a key to align only its row.**
- Accessible picker label: **Alignment for all rows** / **Alignment for row {n}**.
- Optional accessible hints: Left — **Aligns to the left edge**; Right — **Aligns to the right edge**; Center — **Centers the row**; Spread — **Distributes extra space between keys and gaps**.
- Expanded help if needed: **Left and Right use the same edges in every language. Spread keeps key widths and distributes extra space between keys and gaps. A row with one key is centered.**
- Mixed is a state, not a fifth alignment.

## Row-width warnings
Do not use “more than 12 keys” or “12 that fit on every iPhone”. Capacity is weighted by key and gap widths; device-independent fit is a verification claim, not an established fact in copy.

One legacy row:
**Row {n} is wider than the current limit of {limit} standard-key widths. Its saved arrangement is kept. Move keys or remove gaps to shorten the row.**
Multiple legacy rows:
**Rows {row list} are wider than the current limit of {limit} standard-key widths. Their saved arrangements are kept. Move keys or remove gaps to shorten them.**
Use a localized list formatter for row numbers. Do not imply an edit already happened merely because the warning is visible.

Optional explanatory line:
**Wide keys and gaps count toward the limit.**
VoiceOver value suffix: **Row too wide**.
Rejected edit, if an explanation accompanies disabled controls:
**This would make the row too wide. Move keys or remove gaps first.**

New-format validation error:
**{page name}, row {n}: This row exceeds the limit of {limit} standard-key widths. Move keys or remove gaps before applying.**
For Main Keyboard use **{layout name}, row {n}** rather than pretending it is a saved symbol page. Preserve existing parser field paths alongside human labels where useful. Treat user page names as literal text.
Old-format rows must not get rejected by a new-format-only error. The legacy adapter preserves them per product's decision.

## Reset and export terminology
**Rows of Ten** can remain the compact action name, but it now also resets alignment. Add a visible explanation where the action is offered: **Arranges keys in rows of ten and aligns all rows left.** If there is no place for that explanation, use the explicit label **Rows of Ten, Align Left**. Do not hide the new alignment reset behind the old label without disclosure.

Compatibility note when exporting new row semantics, if a note is needed:
**This configuration uses saved rows and alignment. Import it with a version of Uniboard that supports this format.**
Do not assert a minimum version number until the schema/version contract is implemented. Old configurations remain readable; exported new-format files must not silently appear compatible with older apps.

Favorites stays dynamic and has no alignment controls in 1.4. Do not describe it as a fixed row arrangement. Saved edited rows retain their membership and alignment across devices; do not promise identical physical key sizes.
