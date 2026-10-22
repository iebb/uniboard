# Validation and failure behavior

The `Quality checks` workflow runs on pushes and pull requests to `master`.
It runs the offline Python and Ruby suites, validates all bundled font hashes
and licenses, runs Swift core tests, enforces shipped-code line coverage, and
runs the native iOS unit target with an `.xcresult` and coverage artifact.
The monthly catalog refresh and Xcode Cloud pre-build also run the core and
generator checks. Tests do not contact App Store Connect or send typing data.

## Boundary matrix

| Area | Required boundaries | Evidence |
| --- | --- | --- |
| Shared app settings | Latest release default, four slots with exact historical version IDs, strict bounded v1/v2/v3 schema, Boolean font/collapse preferences and validated iPad layout/mapping enums, no-follow read-only keyboard path, app-only atomic writer, unavailable/corrupt data fallback and failed-save preservation | `UnicodeEditionSettingsTests` plus app/keyboard selection UI cases |
| Custom key settings | App-only atomic writes, bounded strict schema, stable physical key IDs, independent tap/shifted tap/hold/up/down slots, nil/default versus disabled/empty versus custom choices, exact UTF-16 identity, one tap output or 16 gesture choices with 64-scalar limits, no-follow regular-file reads, failed-save preservation and optimistic editing conflicts | `KeyboardKeySettingsTests`, `KeyboardKeyPreferencesTests` plus real settings/keyboard cases |
| Binary Unicode resources | Missing/truncated data, invalid scalar domains, reversed/overlapping/unsorted records, algorithmic ranges, edition mismatches | `UnicodeCatalogTests` |
| Character search | Code-point syntax and bounds, 4 KiB UTF-8 limit, repeated AND terms, Unicode word boundaries, complete-word tier before substring tier, ascending defaults, preserved explicit sort, names/aliases/blocks, Suzhou/Hangzhou terminology, numeric age order, global pagination, cancellation | `UnicodeCatalogTests` |
| Complete emoji | Exact scalar sequence and ID, VS16/ZWJ/flags/keycaps/tones, duplicate IDs/text, malformed queries, ordering before limits | `EmojiCatalogTests` |
| Background work | Normal results, cancellation before start and during a detached scan, no stale UI results | `CatalogWorkerTests` plus UI revision guards |
| Data generation | Four-edition atomic generation, rolling historical release slots, official historical emoji URLs, partial download/retry failure, malformed ranges/duplicates, edition identity, failed publication retaining prior artifacts | `Scripts/tests/test_generate_unicode.py` |
| Local collections | Wrong preference types, negative/fractional/overflow values, surrogates, duplicate IDs, order, 60-item recents, reset scope, sandbox separation | `CharacterStoreTests` |
| Optional font preferences | Absent/corrupt/non-Boolean values stay off; app-only selection reaches the read-only keyboard | `LocalPreferencePolicyTests`, `UnicodeFontSupportTests` |
| Height policy | Fixed row count, portrait/landscape/iPad, scene caps, fractional and nonfinite dimensions; search reserves full typing-height rows and a separate result strip or side pane | `KeyboardInteractionPolicyTests`, `KeyboardTypingLayoutPolicyTests` |
| Query editing | Empty/start/middle/end, extreme integer offsets, whole graphemes, combining marks, ZWJ, flags, RTL, insertion limits, clipped viewport and pixel alignment | `KeyboardInteractionPolicyTests` and native query cases |
| Query touch routing | Original physical touch and UTF-16 text, owned search activation, field/mode/bounds changes, delayed callbacks, detach and fresh accessibility actions | `KeyboardQueryInteractionTests` and native query cases |
| English typing | QWERTY/page membership, one-shot Shift, timed Caps Lock, manual capitalization overrides, field/context capitalization, Unicode word boundaries, guarded double-Space replacement, query isolation | `KeyboardTypingPolicyTests`, `KeyboardEnglishInputPolicyTests`, native typing cases |
| Adaptive English rows | Fixed keycap height, exact row thresholds, fractional/nonfinite and constrained dimensions, number-row validation, saved-symbol capacity | `KeyboardTypingLayoutPolicyTests` and native typing cases |
| Pages | Stock board, bounded schema and migration, independent preferred Star target defaulting to Favorites, deletion fallback, exact UTF-16 identity, malformed-data preservation, failed persistence, board CRUD/variants, save target selection, glyph-only scrolling keys, configuration without host insertion | `SymbolBoardStoreTests` plus native board cases |
| Variant interaction | English diacritics and symbol variants, captured case/context, slide/release, cancellation, reentrant callbacks, popup geometry and accessibility | `KeyboardVariantPolicyTests`, `KeyboardVariantControlTests` plus native board/typing cases |
| Fixed keyboard template | Always-visible number row, 15% taller equal caps, one optional symbol/search bar, exact viewport containment, settings persistence | `KeyboardTypingLayoutPolicyTests`, `UnicodeEditionSettingsTests`, native fixed-layout cases |
| Held deletion | Original query/host scope and document, pre-render mode changes, stale timers, repeated down, release/cancel/detach and callback reentrancy; raw touch completion without a terminal control event releases timers and permits the next tap | `KeyboardRepeatingDeleteControlTests` |
| Document connection | Missing or invalid early UIKit identifiers cannot crash the keyboard or authorize host edits; valid public identifiers retain their exact value | `KeyboardDocumentIdentityTests`, real extension startup |
| Optional fonts | Default off, no global registration, actual missing-glyph outlines, native emoji preservation, malformed metadata/ranges, invalid sizes and paths | `UnicodeFontSupportTests`, `Scripts/validate_fonts.py` |
| Packaged privacy manifests | App and embedded keyboard both declare no collection/tracking and the required preferences/elapsed-timing API reasons | `PrivacyManifestTests` |
| Real keyboard behavior | Host text/focus preservation, local search/caret editing, complete insertion, retained results, fixed layout, page swipes, restored scroll position and rotation | Opt-in `UniboardUITests` plus original simulator recordings |
| Publication tools | Identity/build/archive/locale guards, rejected operations, offline-only test transport | `Scripts/tests/test_app_store_release.rb` |

## Coverage gates

`Scripts/check_swift_coverage.py` checks the actual `Shared` source paths from
llvm-cov JSON. Test files cannot increase the reported shipped-code coverage.
Every listed core file must reach 100% executable-line coverage. Missing,
duplicate, empty or malformed coverage records fail the check. This is a line
coverage gate, not proof of every possible path, OS behavior or absence of bugs.

| Shipped source | Minimum line coverage |
| --- | ---: |
| `CompanionAppRoute.swift` | 100% |
| `UnicodeCatalog.swift` | 100% |
| `UnicodeEditionSettings.swift` | 100% |
| `KeyboardKeySettings.swift` | 100% |
| `EmojiCatalog.swift` | 100% |
| `CharacterStore.swift` | 100% |
| `SymbolBoardStore.swift` | 100% |
| `KeyboardVariantPolicy.swift` | 100% |
| `KeyboardFooterLayoutPolicy.swift` | 100% |
| `KeyboardInteractionPolicy.swift` | 100% |
| `KeyboardTypingPolicy.swift` | 100% |
| `KeyboardTypingLayoutPolicy.swift` | 100% |
| `KeyboardEnglishInputPolicy.swift` | 100% |
| `LocalPreferencePolicy.swift` | 100% |
| `CatalogWorker.swift` | 100% |

Run the core gates locally:

```sh
python3 -m unittest discover -s Scripts/tests
ruby Scripts/tests/test_app_store_release.rb
python3 Scripts/validate_fonts.py
swift test --enable-code-coverage
python3 Scripts/check_swift_coverage.py "$(swift test --show-codecov-path)"
```

Run native unit tests on an explicitly selected QA simulator:

```sh
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'platform=iOS Simulator,id=YOUR_QA_SIMULATOR_UUID' \
  -only-testing:UniboardTests -enableCodeCoverage YES \
  CODE_SIGNING_ALLOWED=NO test
```

The CI destination selector is intended for an ephemeral GitHub runner. Local
device work targets iOS 27 and always names an owned QA simulator explicitly.
The old iOS 18.5 Uniboard devices are retired; do not recreate them for QA.

App-to-keyboard delivery UI checks require the App Group entitlement on the
installed simulator binaries. Build that QA product with simulator ad-hoc
signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
CODE_SIGNING_REQUIRED=NO`), then read back its registered group containers.
An unsigned test host can cover unavailable-container fallbacks, but cannot
prove successful shared-setting delivery. Do not weaken save-error handling
or enable Full Access to conceal a missing QA entitlement.

## Edition and privacy boundaries

The Unicode edition selector exists only in the app’s Settings tab. Latest
release 18 is the default; 16 and 17 are historical releases and 19 is an
explicit draft choice. All four character and emoji catalogs are offline. The
keyboard reads the bounded App Group snapshot without Full Access and never
writes it. Edition and Boolean font/collapse preferences use one bounded file;
explicitly configured per-key gesture choices use a separate bounded file.
Version-1 edition-only files default both flags off; v1/v2 files default to ANSI-with-numbers and standard symbol mapping. Version 3 validates all six keys and preserves every field when another preference changes; malformed snapshots
fall back safely. Only app Settings changes these choices. The keyboard … menu
contains only Order; sort, recents and custom boards remain local. Explicit Favorites share a separate bounded file. An unavailable or malformed setting falls back
to the latest release; tests must distinguish that fallback from successful
non-default app-to-keyboard delivery. Settings labels and preference resolution
read only bounded small manifests, not all four full catalogs.

The app navigation includes Settings → Customize Keys, Settings →
Try Your Keyboard and Settings → Font Licenses. Privacy declarations remain
Data Not Collected. Only choices explicitly entered in the key editor enter
the key settings file; document typing and search queries never enter it.

## Native keyboard checks

Keyboard UI tests require `UNIBOARD_KEYBOARD_INTEGRATION=1` and a compatible runtime exposing the remote keyboard. Setup uses the actual Settings/globe flow on owned QA simulators. The fixed template has four character rows (one number row plus three letter rows) and a matching footer. App Settings selects an optional symbol strip or its search-bar replacement; only one top bar is mounted. Verify 41.4-point phone keys and 59.8-point wide iPad keys, full viewport containment, consistent digit/letter/footer sizes and unchanged height between the two top-bar contents. A host's genuine scene constraint may reduce all keys uniformly. Geometry checks observe the owning UIInputView, rather than SwiftUI’s content bounds. The companion test pad keeps a visible single editing line and an inline Back action in compact landscape.

Simulator UI tests that exercise shared settings need an ad hoc signed build: `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO`. An unsigned compile can succeed while the simulated App Group is unavailable. For rotation, the extension may report a portrait scene after its real input view becomes wider; validate the rendered width against that window’s own display before selecting ANSI, and retain the stock layout for portrait or narrow windows.

The retired resize handle, session policies, preview/triangle views, saved-height storage and dragging tests have been removed. Verify their accessibility identifiers are absent. Keep typing, literal Unicode, query-caret, settings persistence, popup, symbol-board and public UIKit fitting tests. Check that horizontal symbol scrolling never inserts, and that iOS 26 scroll-edge effects do not mask the row.

Coverage and passing tests provide evidence for the checked cases. Physical
devices, receiving apps, OS font coverage and remote UIKit behavior still need
TestFlight validation before public release.

## Flexible iPad layout acceptance

Wide iPad always has a number row and three letter rows; landscape offers iPad, compact ANSI and full ANSI presets in app Settings. Full ANSI is the default. Check actual window width rather than screen orientation alone: below 980 points of content width, ANSI is unavailable. All rendered rows and the footer have equal key height. Manual Shift changes ANSI punctuation; automatic capitalization and Caps Lock do not shift digits. Both symbol pages omit redundant digits in the four-row preset. Return is present exactly once on every page. Numbers/Symbols and Hide Keyboard appear after Space in both portrait and landscape.

App-only swipe-up mapping offers the standard symbol page, iPad hints, macOS U.S. Option symbols and Off; per-key custom choices override all presets. Default taps and function keys remain standard; explicit tap mappings change only character keys. Verify saved layout/mapping after relaunch and a real keyboard switch with Full Access off, then rotate back to portrait.

Tap-map schema 2 reads schema-1 gesture files without changing their contents. Version 1 cannot smuggle new tap fields, including nulls. Tap and shifted tap each accept one exact output or Off; long press/up/down remain independent. Default shifted single letters uppercase the remapped letter, bounded to 64 scalars; snippets and symbols stay literal. Explicit Shifted tap is exact. Physical IDs persist across pages and ANSI Shift. Disabled tap must not insert an original letter, and its independent gestures must still work. A visible number row replaces Q–P default up-flick digits with the same ten symbols used by the expanded symbol page; explicit overrides and iPad mapping Off win. Default down flicks offer presentation forms of the same letter, digit or + − = ( ), never the other case.

iPad modifier content positions are tested separately from hit targets: finite corner geometry and clamped insets, actual UIButton title rectangles, unchanged actions, and native light/dark screenshots. Left and right Shift/Delete use stock-style text while accessibility identifiers and repeat deletion stay intact.

The macOS preset and symbol-flick candidates use Apple’s U.S. ANSI Option and Shift–Option layers. A macOS core test independently compares all 47 physical keys and their shifted aliases to the installed `com.apple.keylayout.US` through `UCKeyTranslate`; no input-source selection is changed. Dead keys are literal spacing accents, exact duplicates are removed, and private-use outputs remain exact. Native tests check limits, accents, independent case flicks, per-key overrides and visible-digit-row priority. Keyboard integration exercises both Option-Q variants, case down-flicks and the app-only preset.

## Favorites sync and touch feedback

Saved and the built-in Favorites page use the same store within each process. Migrate the union of the two sandboxes without dropping exact scalar sequences, custom boards, key variants or preferred Star target. Shared writes require Full Access only in the extension; test app-to-keyboard delivery with it OFF and reverse delivery with it ON. Granting/revoking this permission may restart the app and extension, so reacquire the editor through real navigation. Restore OFF on the owned QA simulator after testing.

Cover pending edits across relaunch, remote additions/deletions, reorder, exact composed/decomposed text, supplementary scalars, emoji, arbitrary saved text, invalid/oversized schemas, unreadable or unwritable storage, nonblocking lock contention, concurrent writers, links and non-regular files. An unavailable shared document must not overwrite original bytes or discard local favorites. The three-way baseline is persisted with local board state. Only explicit favorite text crosses the App Group boundary; recents, documents and queries do not. The file-type check uses fstat, declared with C617.1 for app/App Group metadata in both shipped manifests.

Pressed overlays never receive touches or change geometry. Verify physical down/up, cancellation on scrolling, disabled/reconfigured keys, long-hold inspection, stale contexts, detach and reentrant actions. Delete repeats keep their original cadence and do not create repeat haptics. Confirm visual feedback in native controls; simulator success cannot establish physical Taptic feedback. Keep App Store v1.1 held until device acceptance.

Shared settings schema 4 preserves schemas 1–3 and defaults to the symbol bar. Both top-bar switches require JSON Booleans; malformed/unknown fields fail closed. Toggling the symbol bar off retains the saved search replacement preference without displaying it. Failed writes keep previous UI/settings values. The bounded payload limit is 512 bytes.

Gesture candidate resolution reserves explicit custom choices, then primary defaults, then unused alternatives. Assert exact UTF-16 uniqueness across Hold/Up/Down for every physical character key, layout, Shift state and mapping. After a hold opens, vertical motion can switch to either flick group. Reversal switches again after the movement threshold, without crossing the original key. Sideways choice selection must retain its group. Verify one bounded popup after each switch, one insertion on release, disabled groups, presentation failure, stale context and reentrant dismissal. Do not normalize composed/decomposed sequences. Stock currency holds keep their family; Q–P mapped currency hints remain distinct. Shift-origin sliding commits exactly once in its original document; cancellation, stale context, geometry changes, detachment and release over non-character controls must not type or toggle Shift.

## Symbol pages

All saved pages and Recent appear in a horizontal pager. A swipe advances one page without inserting a key; taps and held choices are authorized only for the currently selected page and input context. Preserve U/search visibility when opening Star or editing pages, including the Unicode picker round trip. Check page creation, rename, reorder, deletion of the visible page, empty pages, first/last boundaries and the preferred Star target. A failed selection write must leave the old page selected. Page names, keys, storage IDs and exact Unicode strings remain compatible with previous builds.

The page list exposes Earlier/Later controls, disabled at the corresponding boundary and during read-only recovery. Reordering must persist without changing the active page, preferred Star target or key contents. Wide iPad and compact ANSI character actions must capture the rendered auxiliary-row flag, just like compact phone keys; a mismatched flag correctly rejects a stale action, so do not hard-code it to false for wide rows. Verify literal taps and both flick directions in every iPad preset.

The naming pad and its Add/Save action stay inside the extension. App search has no accessory toolbar; its in-keyboard Done key dismisses without changing the query. The keyboard menu appears only with the Unicode character picker, and shows the three sort choices directly under Character order, with no app-opening action or denial guidance. Verify actual selections and dismissal in portrait and landscape. VoiceOver next/previous uses the same guarded page selection as physical swipes.

Popup choices read 7,5,3,1,2,4,6 for seven candidates. Primary output stays under its original key where screen bounds permit; wrapped rows and Inspect/Edit retain an exact logical index mapping. Both left and right travel can select alternatives, while an ordinary vertical flick retains the primary. Cover every supported count, edge clamping, malformed geometry, command slots and nonfinite movement.


## Search touch acceptance

Search reserves four rows at the same key height as ordinary typing. Portrait adds one horizontal result row; compact phone and wide iPad layouts put results alongside the keys. The scene cap still bounds the complete template. Empty, loading and no-result messages must not compress the input rows. Keep the query, caret and results when returning to English; the fixed daily template resumes at its normal height.

Both Delete controls edit before the local query caret while search is active. Cover beginning/middle/end, repeated taps, held deletion and release, inspection round trips, and returning to host Delete without changing the retained query. Raw touch cancellation/completion must clear the native press latch even when no terminal UIControl event arrives; queued repeat callbacks must stay inert and the next tap must work.

Properties uses a 76×44pt native Save key. Verify physical taps at its center and both corners, repeat opening/cancelling the target panel, and save an existing key without duplicate insertion or changes to receiving text. The same header serves scalar, emoji and arbitrary sequence inspection. Context/document guards remain authoritative during a held press. Horizontal result scrolling must move the strip without inserting or shrinking query keys.

The local core suite has 293 tests and 100% executable-line coverage across the 16 enforced core files; the native unit target has 512 tests. This is line coverage of those core files, not proof of every UIKit path or physical-device behavior. Public v1.1 remains held for device acceptance.
