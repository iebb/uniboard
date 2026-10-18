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
| Binary Unicode resources | Missing/truncated data, invalid scalar domains, reversed/overlapping/unsorted records, algorithmic ranges, edition mismatches | `UnicodeCatalogTests` |
| Character search | Code-point syntax and bounds, 4 KiB UTF-8 limit, repeated AND terms, Unicode names/aliases/blocks, Suzhou/Hangzhou terminology, numeric age order, global pagination, cancellation | `UnicodeCatalogTests` |
| Complete emoji | Exact scalar sequence and ID, VS16/ZWJ/flags/keycaps/tones, duplicate IDs/text, malformed queries, ordering before limits | `EmojiCatalogTests` |
| Background work | Normal results, cancellation before start and during a detached scan, no stale UI results | `CatalogWorkerTests` plus UI revision guards |
| Data generation | Partial download/retry failure, malformed ranges/duplicates, edition identity, failed publication retaining prior artifacts | `Scripts/tests/test_generate_unicode.py` |
| Local collections | Wrong preference types, negative/fractional/overflow values, surrogates, duplicate IDs, order, 60-item recents, reset scope, sandbox separation | `CharacterStoreTests` |
| Optional preferences | Absent/corrupt/non-Boolean values stay off; app/keyboard remain independent | `LocalPreferencePolicyTests`, `UnicodeFontSupportTests` |
| Height policy | Portrait/landscape/iPad, scene caps, fractional limits, NaN/infinity, extreme dimensions, drag overflow | `KeyboardInteractionPolicyTests` |
| Query editing | Empty/start/middle/end, extreme integer offsets, whole graphemes, combining marks, ZWJ, flags, RTL, insertion limits, clipped viewport and pixel alignment | `KeyboardInteractionPolicyTests` and native query cases |
| UIKit resize lifecycle | Release commits; cancel/failure/detachment discard; callback cleanup occurs once | `KeyboardResizeHandleControlTests` |
| Optional fonts | Default off, no global registration, actual missing-glyph outlines, native emoji preservation, malformed metadata/ranges, invalid sizes and paths | `UnicodeFontSupportTests`, `Scripts/validate_fonts.py` |
| Real keyboard behavior | Host text/focus preservation, local search/caret editing, complete insertion, folded results, slow/fast drag previews, actual release height, persisted height and rotation | Opt-in `UniboardUITests` plus original simulator recordings |
| Publication tools | Identity/build/archive/locale guards, rejected operations, offline-only test transport | `Scripts/tests/test_app_store_release.rb` |

## Coverage gates

`Scripts/check_swift_coverage.py` checks the actual `Shared` source paths from
llvm-cov JSON. Test files cannot increase the reported shipped-code coverage.
Missing, duplicate, empty or malformed coverage records fail the check.

| Shipped source | Minimum line coverage |
| --- | ---: |
| `UnicodeCatalog.swift` | 90% |
| `EmojiCatalog.swift` | 90% |
| `CharacterStore.swift` | 95% |
| `KeyboardInteractionPolicy.swift` | 95% |
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

## Native keyboard checks

Keyboard UI tests require `UNIBOARD_KEYBOARD_INTEGRATION=1` and a compatible
runtime exposing the remote keyboard's accessibility elements. Their setup
uses the actual Settings/globe flow. Cases that require a baseline normalize
height through the visible grip rather than modifying extension preferences.
The iOS 27 remote keyboard currently requires manual CUA visual verification
where accessibility elements are absent.

During a drag the window stays fixed and a target-height badge updates. Release
applies one height change. Original recordings and DEBUG-only local numeric
metrics distinguish the preview, actual keyboard geometry and host text;
the release build contains no resize logging or metric-file writer.

Coverage and passing tests provide evidence for the checked cases. Physical
devices, receiving apps, OS font coverage and remote UIKit behavior still need
TestFlight validation before public release.
