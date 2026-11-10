# Uniboard 1.4 brief — implementation handoff

Status: 2026-10-25. User message 781 starts 1.4. Developer audit and browsing design/copy integrated below; ready to implement. Existing Uniboard name remains. 1.3 build 52 is submitted, Waiting for Review, automatic release after approval; do not alter that submission.

## Audience and delivery
For Unicode explorers and multilingual writers who want less browsing clutter and configurable direct-entry keyboards. Deliver a Simulator demo and focused checks first; later TestFlight/App Store distribution requires release direction. No new accounts, backend, analytics, AI or payments. Preserve existing storage/sync behavior; new view preferences default to local persistence unless an existing settings mechanism already covers them. No new AirBuild services needed. Support Us stays in 1.5.

## Three existing surfaces
1. Browse: emoji category visibility and zoom; Unicode block sorting.
2. Keyboard: remove the separate Symbol Keys entry, retaining its capabilities in an appropriate existing destination; additional established direct-entry script layouts, selected after audit.
3. Font detail: previously requested width columns and per-weight downloads with honest shared-file fallback.

## Proposed behavior and observable checks
### Emoji
- Use the existing catalog's Unicode/CLDR categories, not a new hand-curated taxonomy or a silent Unicode-version upgrade. Show all categories by default; allow individual visibility switches and Show All reset.
- Category filters affect emoji browsing and its scoped search, not deletion of saved favorites or custom keyboard content. Show a clear filtered/empty state with a reset action, including when every category is hidden.
- Zoom should reuse the established character-grid size control/gesture where possible. It changes display size, not the inserted/copied sequence. Persist the choice; verify text/emoji presentation, modifiers and ZWJ sequences remain exact.
- Audit app and keyboard emoji surfaces before finalizing whether one visibility preference applies to both; do not claim a shared control before implementation is confirmed.
### Blocks
- Provide explicit ascending/descending direction for the existing sort key. Initial assumption: numeric block starting code point, not popularity or character count. If the app already exposes several sort keys, preserve them and apply direction consistently.
- Direction reverses the same set of blocks without reversing characters inside each block; scoped search does not silently reset it. Persist and test relaunch.
### Keyboard cleanup and scripts
- User identifies the second Symbol Keys row as redundant with the third Symbols page. These were not equivalent in 1.3: Symbol Keys edits 123/#+= gestures; Symbols edits a custom page. Audit and consolidate before deleting the entry; retain symbol-key editing, search and per-key reset in a discoverable existing destination.
- Preserve every saved key override, page, favorite, layout and existing configuration field. Restore All must retain explicit scope and destructive confirmation.
- Choose at most three new direct-entry scripts using established layouts and sources. No predictive text, transliteration or candidate/composition engine in this increment. Do not market direct entry as full language support.
- Verify case/uncased behavior, digits, punctuation, combining marks, insertion/deletion and preview direction; RTL candidates require explicit mixed-direction checks. New layouts start with stock 1–0 row; never copy another layout's customized number row. Existing layouts remain untouched.
### Font grid — decision on prior research
- Adopt developer research option B: pre-resolved, versioned, hash-pinned individual TTF instances where version and character coverage match the original file. No runtime CSS calls or embedded API key. Retain original source for static families; unmatched instances fall back to whole-file downloads.
- Widths appear as columns under Normal/Italic, Standard first; only actual supported weights/styles appear. Use the existing 1.4 design with no Width selector.
- Display exact download scope, size and file count before downloading. Keep the 16-file limit pending measured reasons to change it.
- Adding a shared file does NOT automatically remove existing individual files. Never silently rewrite configuration font references. Deduplicate display where appropriate without deleting files. At capacity, explain manual management rather than evicting fonts.
- Validate downloaded identity, coverage, license and app/keyboard rendering. Existing rules and exports keep working. Update Privacy/Support to disclose new font host before shipping it; publication availability is a dependency, not assumed complete.

## Additional improvement budget
Only closely related usability fixes: Show All/reset for filters, visible active-filter state, remembered sort/zoom, and clear distinction between custom symbol pages and symbol-key actions. Developer/design may propose a ranked shortlist, not silently expand scope.

## Testing policy
Quick usability checks plus changed-feature groups. Full regression is entirely optional, manually started on GitHub CI only, never a local or release requirement. Test migration, relaunch and configuration round trip for new persisted preferences; preserve old files and Undo. Report executed, skipped and blocked checks distinctly. Include large text, VoiceOver, light/dark and representative device sizes. No blanket claim of native language validation without it.

## Research informing scope
- UniChar's published feature list offers curated category selection, full Unicode blocks and font rendering; category control is established palette UX, not evidence of full language input: https://apps.apple.com/us/app/unichar-unicode-keyboard/id880811847 (read 2026-10-25).
- Unicode's emoji chart uses CLDR ordering and names, distinguishes multi-code-point sequences, and directs production use to versioned data files: https://www.unicode.org/emoji/charts/full-emoji-list.html (read 2026-10-25). Reuse bundled data rather than scraping charts.
- Developer attachment 8799b700-4d65-4548-925f-22fffed9c394 documents Google Fonts source/version skew, pinned instance option B, file capacity and identity hazards. Product chooses B with retained downloads; no automatic replacement.

## Integrated decisions — authoritative over draft assumptions above
- Audit: Pluso message790, attachment51333537-afd5-4f17-b98b-fd267d269725. Symbols is a 24-key custom page, not the symbol-layer editor. Keep that page; move all symbol editing into Main Keyboard with Letters / 123 / #+= switch, cross-section key search and per-key reset. Restore All moves to its More menu with its unchanged explicit all-layout scope. Reachability of every legacy symbol key must be preserved on iPhone and iPad; no saved-data migration needed.
- Emoji visibility: one hidden-category preference in the App Group affects app and keyboard emoji browsing/search, not Saved, Recent, pages or What's New. Apply immediately; Done dismisses. Filter before pagination. Persist hidden groups so new groups default visible; include in configuration review, export/import and Undo.
- Emoji zoom: app only, separately persisted; keyboard grid remains fixed. Reuse pinch steps, provide Smaller/Larger menu and accessibility actions. Preserve the 1.3 default appearance and exact sequence insertion. Include preference in configuration round trip.
- Blocks: starting-code-point ascending/descending only. Detail navigation follows the list order; the Explore block navigator should likewise follow Explore's existing order. This is a consistency fix, not another sort mode.
- Scripts selected: Armenian, Hebrew, Arabic, based on documented established layouts. Armenian cased; Hebrew/Arabic uncased, no disabled fake Shift. Native labels and letter-switch labels reflect script where practical; accessible section label is Letters. Developer verifies layouts against Apple reference. Verify mixed-direction cursor, deletion, punctuation and combining text for RTL; disclose any unverified real-device/native-reader limits. Do not silently substitute a different script if checks fail: report and resolve scope.
- Design: message796 attachment a2896714-f55f-4319-87cf-8a2d473620a6, browsing/keyboard spec rev1, sections1–10 integrated. Mockups are references, not a prerequisite to coding this settled interaction. Font grid uses separate styles-grid-1.4/design.md with no-auto-removal revision; existing 1.4 width-column design stands subject to pinned-instance decision above.
- Copy: message794 attachment62701a63-fa85-429f-afe1-7cdd29cf537a, plus message797 attachment31402254-5f2d-4569-a3b3-023f7cf9867d. Addendum wins over placeholders in design. Existing name means no naming choice is outstanding.
- Ranked extra proposals: defer skin-tone variant hiding and a new Category sort mode; these require additional independent filter/search rules and are not in this implementation. Defer new Arabic-Indic hold defaults until layout verification demonstrates the appropriate bindings; do not overwrite customized digit actions. Accept only block navigator order consistency already described above.
- New state must have backward-compatible defaults and reviewable configuration diffs. All screen/API source identifiers unrelated to this change remain compatible.
- Delivery remains Simulator demo and focused evidence first. Full suite is manual GitHub CI only. No 1.4 submission authorized yet, and no change to the submitted 1.3 candidate.
