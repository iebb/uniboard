# Uniboard 1.4 — browsing and keyboard wording draft

For Ato, Colo, Pluso; msg784 scope. Name retained. Copy candidates for the interaction spec, not implementation claims. Existing 1.4 font copy remains in styles-grid-1.4-copy.md, with the policy amendment below.

## Emoji visibility
Entry and sheet title: **Emoji Categories**.
Helper: **Choose which categories appear.**
Switch accessibility hint: **Show this category**. On means visible; avoid mixed Show/Hide toggles.
Bulk actions, if present in the design: **Show All**, **Hide All**.
Completion: **Done** if edits apply immediately; use **Apply** only if this screen stages changes until confirmation.
All hidden: **No emoji categories shown** / **Choose at least one category to see emoji.** / **Choose Categories**.
Filtered search empty: **No matching emoji in the categories shown** / **Try another search or show more categories.** / **Choose Categories**.
Use that search copy ONLY if search actually respects category visibility. If it searches all emoji, say **No matching emoji** / **Try another name.**

Use the app’s actual existing category names and Unicode grouping; do not invent a new taxonomy. Developer audit must establish whether hidden categories also disappear from search, keyboard browsing, or only the app’s emoji screen. Explain only the actual scope in the final helper, e.g. **Choose which categories appear in the emoji browser.** Never imply deletion: hidden emoji remain saved wherever they were previously saved.

## Emoji zoom
For grid-size control: **Emoji Size**. Actions where needed: **Smaller**, **Larger**. VoiceOver: **Decrease emoji size**, **Increase emoji size**.
For enlarged single-emoji inspection instead: **Enlarge Emoji**, **Close**; do not call that a grid-size setting. Colo to choose based on the existing zoom interaction and user intent.
Do not imply changing the size in the destination app. The zoom applies to Uniboard’s display.

## Block sorting
Menu: **Sort Blocks**.
If sorting by starting code point, options: **Code Point: Low to High**, **Code Point: High to Low**.
If existing alphabetical sorting remains: **Name: A–Z**, **Name: Z–A**.
Avoid bare Ascending/Descending or High/Low with no stated sort key. Developer audit must confirm the sort field before finalizing labels. Do not conflate code point order with number of characters in a block.

## Keyboard cleanup and scripts
Keep **Keyboard**, **Main Keyboard**, and the user's **Symbols** destination. Removing **Symbol Keys** must not imply removing saved choices or the ability to edit symbols. Exact entry/action wording follows the audit of merged editing controls.
For direct-entry layouts, use **{Script} Keyboard** or the established layout name, with helper **Type {script} characters directly.**
Do not say “full {language} support”, predictive typing, transliteration or composition unless implemented and verified. Where relevant: **This layout enters characters directly; it doesn’t convert phonetic input into words.** Include script-specific caveats only when applicable, not a generic warning for every layout.
Do not add unfamiliar or invented script layouts in copy. Retain native names and established layout names from the verified catalog.

## Font policy amendment — decided msg784
No automatic removal or replacement of single-style downloads when adding a shared file. Keep the current 16-file limit.
Remove all replacement/freeing-space promises from candidate UI. Shared download caption: **Includes {n} styles in one file. Existing downloads are kept.**
At capacity: **All 16 font-file spaces are in use. Remove a font file here or in Font Downloads to make room.**
Only call an action **Download {style name}** when it downloads that style alone from a verified pinned source. Otherwise **Download File ({n} Styles)**, with accurate size and coverage. Pinned source/version details are engineering metadata, not a claim of permanent availability.

## Finalization inputs
Developer: actual emoji grouping/filter scope, zoom behavior, block sort key, merged symbol editing coverage, supported scripts and limitations.
Design: control placement and whether category changes are immediate or staged.
These inputs finalize the strings; no extra user naming decision is needed.

## Confirmed scope and final strings — msg792

This section supersedes the draft alternatives above. No name change.

### Shared emoji categories
- Title/action: **Emoji Categories**.
- Helper: **Choose which categories appear in the app and keyboard, including emoji search.**
- On = shown. Keep existing Unicode category names, not invented groups.
- All-hidden state: **No emoji categories shown** / **Choose at least one category to see emoji.** / **Choose Categories**.
- Search empty: **No matching emoji in the categories shown** / **Try another search or show more categories.** / **Choose Categories**.
- Bulk action labels, if included: **Show All**, **Hide All**. Immediate changes use **Done**, staged changes use **Apply**; match the final interaction rather than introducing a new persistence model.
- Hiding filters browsing/search; it does not remove saved emoji. Optional explanation: **Hidden categories aren’t deleted from your saved pages or favorites.** Use only with that preservation verified.

### Emoji zoom
Reuse grid pinch zoom, not a new single-emoji viewer.
- Hint: **Pinch to change emoji size.**
- Accessible control name: **Emoji Size**.
- Accessible adjustment actions: **Increase emoji size**, **Decrease emoji size**.
- Do not promise insertion-size changes in other apps.

### Blocks
- Menu: **Sort Blocks**.
- Options: **Code Point: Low to High**, **Code Point: High to Low**.
- No name/count/version sorting in 1.4 scope.

### Main Keyboard consolidation
- Destination remains **Main Keyboard**, inside **Keyboard**.
- Segment labels: **ABC**, **123**, **#+=**. Accessible labels respectively: **Letters**, **Numbers and Symbols**, **More Symbols**. Where practical, the letter segment’s visual label follows the active script without changing its accessible meaning.
- Helper: **Choose letters, numbers or symbols to edit their keys.**
- Keep the existing **Symbols** saved page untouched; it is not the 123 or #+= editor.
- Remove the separate **Symbol Keys** row and its screen-specific helper. No saved choices are deleted.
- Menu action: **Restore All Key Defaults**.
- Confirmation title: **Restore all key defaults?**
- Confirmation body: **This resets all letter, number and symbol key actions, including taps, and restores the standard key arrangement and number row for every layout. Your symbol pages, favorites, enabled layouts and other settings are kept.**
- Destructive button: **Restore All Key Defaults**; secondary **Cancel**.
- Optional visible scope caption: **Resets letters, numbers and symbols, and every layout’s arrangement.**
- Search stays **Find a key**. If restricted to the selected segment, no-results copy: **No matching keys in this section** / **Try another search or switch sections.** If it searches all segments, use **No matching keys** / **Try another search.** Search scope remains a design/engineering detail to verify, not a reason to guess.

### Additional scripts
Names: **Armenian**, **Hebrew**, **Arabic**; retain verified native display names from the layout catalog.
- General helper if needed: **These layouts enter characters directly.**
- Do not claim prediction, transliteration, automatic word composition or complete language support.
- Armenian, Hebrew and Arabic are planned direct-entry layouts. Do not announce them as available until implemented and checked; Hebrew/Arabic additionally require mixed-direction cursor, deletion and punctuation verification.

The font policy amendment above stands: keep existing files, preserve the 16-file limit, verified single-style download or explicitly labeled shared-file fallback. No automatic cleanup promise.
