# Uniboard 1.4: explicit rows — compatibility assessment

For Ato and Colo, responding to user822 / product823. Read-only assessment of the current uncommitted 1.4 tree. No storage changes or tests run for this assessment.

## Recommendation

Use explicit ordered rows for new/edited key arrangements, with each row carrying its ordered cells and alignment. Continue accepting all old formats through a legacy adapter. Do not rewrite data on load, Validate, or preview. Conversion happens only through an explicit successful edit/Apply; Undo must restore old bytes and old rendering.

Example conceptual model (not yet a frozen external format):

```
rows: [
  { alignment: "left", cells: [keyA, keyB, halfGap, keyC] },
  { alignment: "center", cells: [keyD, keyE] }
]
```

A page key retains its ID, exact text, hold/up/down actions. Main keyboard keys retain semantic identities (letters, digits, function tokens) and the existing separately stored overrides. Typed gaps must survive. There must be one authoritative ordering, not a flat key list and a nested array that can disagree. Explicit row membership must not wrap just because screen width changes.

Proposed alignment names: left, right, center, distributed (UI wording belongs to Camo/Colo). Left/right are physical edges, not language-dependent leading/trailing. Recommended distributed behavior: keep key widths, distribute remaining width between cells, center a singleton. Designer must specify minimum spacing/overflow and whether gaps participate; do not stretch glyphs/keys silently.

## What old input actually means

Saved Symbols/custom pages: Shared/SymbolBoardStore.swift:7–34 stores keys plus optional `layout`. Shared/SymbolPageLayout.swift:4–118 interprets k=key, h=half gap, g=full gap, /=new row. Missing layout means rows of ten, not width-dependent wrapping. Too few slots appends remaining keys in rows of ten; too many drops empty slots/rows and final trailing gaps. Both editor and keyboard left-align these rows. Preserve these rules for old inputs instead of retroactively rejecting them.

Main Keyboard: Shared/MainKeyboardArrangement.swift:9–160 stores flat semantic keys plus slot text. Stock arrangement, custom arrangement, wide-iPad projection and ANSI landscape have different sizing behavior. App/MainKeyboardEditorView.swift:160–214,508–680 and Keyboard/KeyboardViewController.swift:4037–4240 are the main renderer/editor touchpoints. Existing stock rows are not equivalent to centered fixed-width custom rows. Retain a legacy rendering mode, not merely an inferred center alignment.

Wide iPad (>=650 available width) currently projects letters into three rows, dropping customized gaps/function placement and adding iPad-specific keys. English landscape >=980 can use fixed ANSI rows. Recommendation: old inputs retain those substitutions; new explicitly edited rows honor the saved rows/alignment instead of silently projecting them. This is a product-visible boundary for Ato/Colo to confirm before implementation.

## Favorites is a separate contract

Favorites texts/order sync independently of their stored row slots (SymbolBoardStore.swift:394–463). The shared page entry intentionally contains no keys. Binding its persistent rows to today's Favorite IDs would freeze or lose later additions.

Recommendation: keep Favorites dynamic, with its current slot/automatic behavior for legacy data. If per-row alignment is required on Favorites in this increment, keep a row-template representation with key slots resolved against live favorites; overflow retains current rows-of-ten behavior. Do not serialize a fixed copy of favorites inside page rows. New static custom-page rows and dynamic Favorites templates should be explicitly distinguished.

## Versioning and transaction safety

Current formats:
- Shared pages: symbol-pages-v1.json, schema 1 (SymbolPageSettings.swift:13–76).
- Local page state: keyboard.symbolBoards.v1, State version 1/2 (SymbolBoardStore.swift:49–143).
- Separate JSON custom-page import/export: PageFile schema 1 (SymbolBoardStore.swift:264–301). This is distinct from the complete TOML configuration and must also be upgraded.
- Shared key settings: keyboard-keys-v1.json, schema 4, decodes 1–4 (KeyboardKeySettings.swift:83–212).
- Complete TOML configuration: schema_version 1, strict fields; arrangement keys+places, page key entries+layout (ConfigurationCodec.swift:79–113,183–199,398–523).

Recommend new envelope versions for new row semantics (pages/shared PageFile 2, local state 3, keyboard settings 5, TOML exchange 2; exact numbers to freeze during implementation). Keep all old readers in the new app. Do not add new fields under an old schema that older code can silently ignore, and never downgrade a new alignment on export without an explicit loss warning. Legacy-only exports may remain v1 if faithfully representable; new-row exports must identify the new format. Old-app forward compatibility is not promised; safe rejection is preferable to silently moving keys.

No generation-pointer schema change is needed. Extend ConfigurationModel.capture/compile/equality (:124–188), ConfigurationDiff (:117–148), codec, review/editor, and generation validation together. SharedConfigurationLocation.swift:251–322,361–402 already stages/verifies/publishes atomically and restores old payload bytes on Undo. Do not write migrations while capturing/reviewing because that changes conflict fingerprints. Keep existing Number Row migration ordering intact.

## Required focused checks before delivery

- Old shared schemas, local state, JSON PageFile and TOML still load; reading/Validate/export doesn't mutate stored bytes.
- Underflow/overflow slots, half/full gaps, key IDs, exact Unicode (including decomposed/ZWJ), variants and disabled-vs-default actions survive conversion.
- Legacy stock/custom/caseless/ANSI appearances unchanged at phone, iPad, portrait/landscape sizes.
- Four alignments, singleton/long row, spacing limits; editor agrees with keyboard; new explicit rows don't auto-wrap.
- Dynamic Favorites after adding/removing/reordering/sync; slot templates don't freeze membership.
- A standard-looking explicit arrangement with a non-default alignment must not be discarded as an implicit stock default.
- Round trip, diff/review, Apply, stale-save conflicts, failed-save atomicity and Undo for old and new inputs.

Existing baselines: SymbolPageLayoutTests; SymbolBoardStoreTests; MainKeyboardArrangementTests; KeyboardKeySettingsTests; ConfigurationCodecTests; SharedConfigurationLocationTests. No full local UI regression required.

## Design handoff

The user's image is the saved Symbols page, not the 123/#+= editor. Colo owns making its add actions fit without wrapping and specifying the row controls. Please confirm the new-row wide-iPad behavior and whether Favorites receives new alignment controls now; storage implementation can then follow this contract.

App Intents assessment skipped for this read-only format/design assessment: no implemented feature or permissions changed. The app currently has no App Intents.
