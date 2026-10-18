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
| Shared app settings | Latest release default, four slots with exact historical version IDs, strict bounded v1/v2 schema, Boolean font/collapse preferences, no-follow read-only keyboard path, app-only atomic writer, unavailable/corrupt data fallback and failed-save preservation | `UnicodeEditionSettingsTests` plus app/keyboard selection UI cases |
| Custom key settings | App-only atomic writes, bounded strict schema, stable physical key IDs, nil/default versus disabled/empty versus custom choices, exact UTF-16 identity, 16-choice/64-scalar limits, no-follow regular-file reads, failed-save preservation and optimistic editing conflicts | `KeyboardKeySettingsTests`, `KeyboardKeyPreferencesTests` plus real settings/keyboard cases |
| Binary Unicode resources | Missing/truncated data, invalid scalar domains, reversed/overlapping/unsorted records, algorithmic ranges, edition mismatches | `UnicodeCatalogTests` |
| Character search | Code-point syntax and bounds, 4 KiB UTF-8 limit, repeated AND terms, Unicode word boundaries, complete-word tier before substring tier, ascending defaults, preserved explicit sort, names/aliases/blocks, Suzhou/Hangzhou terminology, numeric age order, global pagination, cancellation | `UnicodeCatalogTests` |
| Complete emoji | Exact scalar sequence and ID, VS16/ZWJ/flags/keycaps/tones, duplicate IDs/text, malformed queries, ordering before limits | `EmojiCatalogTests` |
| Background work | Normal results, cancellation before start and during a detached scan, no stale UI results | `CatalogWorkerTests` plus UI revision guards |
| Data generation | Four-edition atomic generation, rolling historical release slots, official historical emoji URLs, partial download/retry failure, malformed ranges/duplicates, edition identity, failed publication retaining prior artifacts | `Scripts/tests/test_generate_unicode.py` |
| Local collections | Wrong preference types, negative/fractional/overflow values, surrogates, duplicate IDs, order, 60-item recents, reset scope, sandbox separation | `CharacterStoreTests` |
| Optional font preferences | Absent/corrupt/non-Boolean values stay off; app-only selection reaches the read-only keyboard | `LocalPreferencePolicyTests`, `UnicodeFontSupportTests` |
| Height policy | Portrait/landscape/iPad, scene caps, fractional limits, NaN/infinity, extreme dimensions, one-row swipe direction and clamping | `KeyboardInteractionPolicyTests`, `KeyboardResizeStepPolicyTests` |
| Query editing | Empty/start/middle/end, extreme integer offsets, whole graphemes, combining marks, ZWJ, flags, RTL, insertion limits, clipped viewport and pixel alignment | `KeyboardInteractionPolicyTests` and native query cases |
| Query touch routing | Original physical touch and UTF-16 text, owned search activation, field/mode/resize changes, delayed callbacks, detach and fresh accessibility actions | `KeyboardQueryInteractionTests` and native query cases |
| English typing | QWERTY/page membership, one-shot Shift, timed Caps Lock, manual capitalization overrides, field/context capitalization, Unicode word boundaries, guarded double-Space replacement, query isolation | `KeyboardTypingPolicyTests`, `KeyboardEnglishInputPolicyTests`, native typing cases |
| Adaptive English rows | Fixed keycap height, exact row thresholds, fractional/nonfinite and constrained dimensions, number-row validation, saved-symbol capacity | `KeyboardTypingLayoutPolicyTests` and native typing cases |
| Symbol boards | Stock board, bounded schema and migration, independent preferred Star target defaulting to Favorites, deletion fallback, exact UTF-16 identity, malformed-data preservation, failed persistence, board CRUD/variants, save target selection, glyph-only scrolling keys, configuration without host insertion | `SymbolBoardStoreTests` plus native board cases |
| Variant interaction | English diacritics and symbol variants, captured case/context, slide/release, cancellation, reentrant callbacks, popup geometry and accessibility | `KeyboardVariantPolicyTests`, `KeyboardVariantControlTests` plus native board/typing cases |
| UIKit resize lifecycle | One-row up/down swipe on release, unchanged allocation during the gesture, tap/cancel/failure/detachment without saving, callback cleanup once | `KeyboardResizeHandleControlTests` |
| Held deletion | Original query/host scope and document, pre-render mode changes, stale timers, repeated down, release/cancel/detach and callback reentrancy | `KeyboardRepeatingDeleteControlTests` |
| Document connection | Missing or invalid early UIKit identifiers cannot crash the keyboard or authorize host edits; valid public identifiers retain their exact value | `KeyboardDocumentIdentityTests`, real extension startup |
| Optional fonts | Default off, no global registration, actual missing-glyph outlines, native emoji preservation, malformed metadata/ranges, invalid sizes and paths | `UnicodeFontSupportTests`, `Scripts/validate_fonts.py` |
| Packaged privacy manifests | App and embedded keyboard both declare no collection/tracking and the required preferences/elapsed-timing API reasons | `PrivacyManifestTests` |
| Real keyboard behavior | Host text/focus preservation, local search/caret editing, complete insertion, folded results, one-row height swipes, restored results/scroll position, persisted height and rotation | Opt-in `UniboardUITests` plus original simulator recordings |
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
| `KeyboardResizeStepPolicy.swift` | 100% |
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
device work always names the owned QA simulator explicitly.

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
Version-1 edition-only files migrate with both flags off; malformed snapshots
fall back safely. Only app Settings changes these choices. The keyboard … menu
contains Order and Open companion app; sort and collections remain separate. An unavailable or malformed setting falls back
to the latest release; tests must distinguish that fallback from successful
non-default app-to-keyboard delivery. Settings labels and preference resolution
read only bounded small manifests, not all four full catalogs.

The app navigation includes Settings → Customize keyboard keys, Settings →
Try your keyboard and Settings → Font licenses. Privacy declarations remain
Data Not Collected. Only choices explicitly entered in the key editor enter
the key settings file; document typing and search queries never enter it.

## Native keyboard checks

Keyboard UI tests require `UNIBOARD_KEYBOARD_INTEGRATION=1` and a compatible
runtime exposing the remote keyboard's accessibility elements. Their setup
uses the actual Settings/globe flow. Cases that require a baseline normalize
height through the visible grip rather than modifying extension preferences.
The iOS 27 remote keyboard currently requires manual CUA visual verification
where accessibility elements are absent.

Where available on iPhone in portrait, the top grip accepts two height
gestures: swipe up adds one key row; swipe down removes one. Each accepted gesture applies one row step on release,
clamped to the available scene and browsing limits. Short and long swipes
must each apply only one step. Taps, cancelled gestures and invalidated
sessions leave the height and saved preference unchanged. The query, caret,
results and scroll position must remain intact. During dragging, an up/down triangle appears only if that direction can change the height. Outward swipes at either bound and a range with only one valid height show none; reversing inward restores feedback. There is no size
gauge, height preview or separate height editor.

The default toolbar is hidden; the bottom-left U control shows/hides it. Hiding
it restores host typing while preserving the query and caret. A fresh portrait
keyboard is 220 points high; saved heights remain in use. All ordinary keycaps
are 36 points with 4-point vertical gaps. The 14-point grip has no top spacer.
The optional collapse control is hidden by default. English keycaps retain
their height as space grows. A number
row appears when four character rows fit; saved-symbol rows appear at five.
When the normal page has digits, the expanded number/symbol page contains no
digits and supplies two complementary ten-symbol rows. Short layouts keep123.
Saved-symbol widths and rounded key surfaces match the digit row exactly.
The footer is separate from those character-row counts. Original recordings and actual layout receipts must verify those row
thresholds, unchanged host input and release-only height application. Earlier
live-window and height-preview trials remain historical evidence, not the
current product contract. DEBUG-only metrics record numeric layout and
lifecycle data. The release build contains no resize logging or metric-file writer.

Coverage and passing tests provide evidence for the checked cases. Physical
devices, receiving apps, OS font coverage and remote UIKit behavior still need
TestFlight validation before public release.
