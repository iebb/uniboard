# Uniboard — App Intents opportunities

## Existing App Intents inventory

**Uniboard declares 0 App Intents actions.** No Shortcuts, App Shortcuts, Spotlight, Siri, widget or control entry points are declared, and nothing adopts an Apple Intelligence schema.

| Business action | Intent / shortcut / entity / query evidence | Wiring today | Evidence limits |
| --- | --- | --- | --- |
| None declared | The 2026-10-24 inventory searched all 103 then-present Swift files in `App/`, `Shared/` and `Keyboard/`, plus `Tests/`, `UITests/`, `Uniboard.xcodeproj/`, `project.yml` and `Package.swift`. Patterns: `AppIntent`, `AppShortcut`, `AppShortcutsProvider`, `AppEntity`, `EntityQuery`, `AppEnum`, `IntentParameter`, `@AssistantIntent`/`@AssistantEntity`, `@AppIntent(`/`@AppEntity(`, `INIntent`, `import Intents`, `intentdefinition`, `WidgetKit`, `ControlWidget`. No matches. `App/Info.plist`, `Keyboard/Info.plist` and `project.yml` have no `NSUserActivityTypes` or document types. The app also has no `CoreSpotlight` or `NSUserActivity` code. | Ordinary app UI and the keyboard extension only. The only external route is `uniboard://settings`: `Shared/CompanionAppRoute.swift`, `isSettings(_:)`, handled by `ContentView.onOpenURL`. In DEBUG, `onOpenURL` also accepts test fixture URLs. | This is a static source inventory, not a check of what the installed system shows. The project has no widget or control target. |

## Historical baseline — 2026-10-24

The following baseline and API evidence describe the prior assessment. The 2026-10-25 reassessment below supersedes changed action and project facts; unchanged evidence keeps its original verification date.

## Project and scope

- **Project:** Uniboard, an imported iOS app: a Unicode keyboard extension plus its companion app. Release 1.3.0 is being prepared (`MARKETING_VERSION: "1.3"`).
- **Analysis date:** 2026-10-24, read-only. The code was a live, shared working tree that other agents were editing during the analysis.
- **Baseline:** branch `master`, HEAD `26d9cd060a81aac93b02833df6f03f47d098788c` (committed 2026-10-23 10:56 UTC). The previous report used `be61e58`; commit `26d9cd0` added that report.
- **Working tree:** dirty. 47 tracked files are modified (+5354/−919), and about 33 source files are new and untracked. New app files include `ConfigurationFile`, `ConfigurationImportModel`, `ConfigurationView`, `ReviewImportView`, `FontRule*Views`, `FontRulePreferences`, `FontRangeCoverage` and `StyleGridView`. New shared files include `AutoCapitalizationSetting`, `Configuration{Codec,Diff,Model}`, `FontPickerCatalog`, `FontRule{Editing,FaceLoader,Store}`, `FontRules`, `ImageColorSettings`, `KeyboardPreviewCursor*`, `KeyboardQueryHold*`, `SharedConfigurationLocation`, `StyleGrid`, `TOMLDocument`, `TextInspection` and `UnicodeSearchIndex*`. `Keyboard/KeyboardSearchTimingProbe.swift` is also new.
- **Reason for this update:** the 1.3.0 feature set changed substantially since the previous report (2026-10-23 06:27, `be61e58`). New features: font rules, TOML configuration import/export, Inspect Text in the keyboard, Copy Image scale and colors, a font picker over all accessible fonts, a style grid with per-file downloads, a movable preview cursor, an auto-capitalization setting, and search in landscape. `docs/store-copy-1.3.0.md` says the cursor and the expanded font picker were unfinished when it was drafted. I treat those two as in-progress code.
- **Read for this update:**
  - Briefs: `docs/font-rules-brief.md` and `docs/inspection-capitalization-brief.md`.
  - Settings: `project.yml` and `.pbxproj` source phases.
  - Code: the function bodies and callers listed under each action below. Prior action chains were rechecked for continued existence.
  - Not done: no app launch, build, test, simulator run, git state change or business operation.
- **Tools available:** this shell has no `xcodebuild`, `xcrun` or `swift`, and there is no `/Applications` directory. Apple's online documentation was reachable (DocC JSON, HTTP 200).

| Target / configuration | Relevant sources | Deployment target | SDK / toolchain evidence | Unknowns |
| --- | --- | --- | --- | --- |
| `Uniboard` app, Debug/Release (source phase `E17E8EA272032DA22C8E9942`) | `App/` + all of `Shared/` (it contains `TextInspection.swift`, `KeyboardPreviewImageExport.swift`, `ConfigurationCodec.swift`, `FontRules.swift`, `StyleGrid.swift`) | iOS 17.0 (project setting; no target override found) | `SDKROOT=iphoneos`, `SWIFT_VERSION=5.0`. `project.yml` asks for `xcodeVersion: "27.0"`. | Selected SDK, compiler and build result were not inspected. |
| `UniboardKeyboard` extension (phase `403420D087165E9E66B28DEE`) | `Keyboard/` + `Shared/`, minus the TOML, configuration-codec and font-rule-editing files | iOS 17.0 | `APPLICATION_EXTENSION_API_ONLY=YES` | Proposed intents belong in the app, not the extension. |
| `UniboardTests`, `UniboardUITests` | `Tests/` (includes `TextInspectionTests`, `ConfigurationCodecTests`), `UITests/` | iOS 17.0 | Same base settings | No tests were run. |
| `UniboardCore` Swift package | Explicit subset of `Shared/`/`Tests/` | Declares macOS 13 | tools 5.9 | Does not ship an Intent. |

Both shipping targets declare the App Group `group.ad.neko.uniboard`. Keep the iOS 17 target and the existing behavior unchanged.

## Decision summary

**Ready first batch: three background, value-returning actions.** None needs app routing, a foreground launch or entities. Each one's essential APIs are verified (iOS 16.0 floor, below the iOS 17 target) in Apple documentation and in an iOS 17.0 SDK interface (evidence A1–A14).

| Order | Action | Verdict | Why first / rough cost | Evidence |
| --- | --- | --- | --- | --- |
| 1 | **8. Inspect Unicode text**: get a normalized form, code points, or UTF-8/UTF-16 hex | **Recommended** | Distinctive 1.3 capability. The logic is pure and already in the app target. Text goes in, text comes out, and nothing is stored. **S.** | A1–A3, A5–A12, A14 |
| 2 | **9. Export Uniboard configuration**: get the current settings as a `.toml` file | **Recommended (product decision on privacy wording)** | Enables automated backups and transfers. Reuses the existing capture and encode functions without a share sheet. **S–M.** | A1–A3, A8–A10, A13, A14 |
| 3 | **2. Get exact Unicode text**: code point or emoji ID → text | **Recommended (the API part, previously pending, is now verified)** | Complements #1. Uses the edition-aware catalog. **S–M.** Needs a new guard against unassigned code points (proposal). | A1–A3, A5–A10, A14 |

- **Pending, needs verification (not counted in the batch):**
  - 10. Make image of Unicode text (Copy Image).
  - 1. Search Unicode in Uniboard.
  - 4. Compare fonts for Unicode text.
  - 5. Search Google Fonts.
  - 6. Open a font detail.
  - 11. Set a preferred font rule.
  - 3. Add Unicode text to Favorites.
  - 7. Download a Google font style.
- **What blocks them:** the foreground handoff needs a deprecated-API strategy plus new routing (G3). Font and image actions need entity or rendering-lifecycle work (G5). Favorites needs a decision on what a persistence and sync result reports.
- **Not recommended:** 12. Import/replace configuration and Undo Last Configuration Change, plus everything in the exclusion table.
- **Shared limits for the batch:** App Shortcut tiles, Siri phrases, Spotlight indexing and schema enhancements are outside the ready scope (G2, G4). The ready scope means user-composed Shortcuts actions only. Ranking is qualitative; no usage data was available.

## Assessed actions

Numbering keeps the identities 1–7 from the previous report. Actions 8–12 are new.

### 8. Inspect Unicode text — new first-batch item #1

- **Business state: logic implemented; new input source proposed.** `Shared/TextInspection.swift` holds the logic:
  - `TextNormalizationForm.normalize(_:)` maps NFC/NFD/NFKC/NFKD to Foundation's `precomposed…`/`decomposed…Mapping`.
  - `TextEncodingResult.init(form:text:)` gives uppercase hex, space-separated, with no BOM or prefix.
  - `TextInspection.codePointSequence` gives `U+XXXX` labels.
  - `TextInspection.analyze(before:after:catalogVersion:lookup:systemAssigns:)` sets a normalization status to `.unavailable` (`canCopy == false`) when the catalog assigns a scalar that this OS's Unicode data does not.
  - `copyValue(for:)` returns exactly what the panel copies.
  - Today the only UI entry is the keyboard: `Keyboard/KeyboardViewController.swift`, `openTextInspection(excerpt:)` → `TextInspectionState.inspect(...)` (refuses secure fields; `maximumScalars = 1024`) → `copyTextInspection(_:)`, which writes the pasteboard and needs Full Access. The app has no screen for this. The brief defers in-app inspection of pasted text ("can follow later"). The file is a member of the app's source phase, and `Tests/TextInspectionTests.swift` exists.
- **Direction (proposal):** an action named "Inspect Unicode Text".
  - Parameters: required `text: String`, and required `representation`, a proposed `AppEnum` with NFC, NFD, NFKC, NFKD, Code Points, UTF-8 Hex and UTF-16 Hex.
  - Result: a `String` value equal to `TextInspection.analyze(before: text, after: "", …).copyValue(for:)`.
  - The text is used exactly as given: no trimming, because whitespace and invisible characters are significant.
  - Proposed guards:
    - Reject empty input.
    - Reject input over 1024 scalars, reusing the existing bound unless product chooses a different bound for intents.
    - For a normalized form whose status is `.unavailable`, throw a clear error instead of returning a possibly wrong result. This mirrors `canCopy`. Code points and hex are always available.
  - Calls are deterministic for the same OS Unicode data. There is no clipboard, host text, persistence or logging.
- **Access and safety:** no login, account or permission is involved, and no Full Access, because the app process is not the keyboard. The user's text may be sensitive. Keep the existing promise that inspected text is never stored, and add no donation or logging of parameters (proposal). No confirmation is needed; the action is read-only.
- **Ordinary path: recommended.**
  - Background execution: the default, with no `openAppWhenRun` or `supportedModes`.
  - Parameters: `@Parameter` String (A6) and an AppEnum parameter (A11, A12).
  - Result: `ReturnsValue<String>` via `.result(value:)` (A9, A10).
  - `lookup` needs `UnicodeCatalog.shared` loaded in the intent process. Cold-launch cost has not been measured (G5).
- **Schema enhancement:** none determined. No Unicode or text-transform domain appears in the reference's domain list (a guide lead, not proof), and the schema database was not readable (G4). Do not force this into `wordProcessor` or `notes`.
- **Entry points:**
  - Shortcuts action: yes (proposed).
  - App Shortcut or Siri phrase: not in scope (G2). Spoken output also fits poorly for hex or invisible characters.
  - Spotlight and Apple Intelligence: not evaluated, and not implied.
- **Priority and cost:** #1. **S:** one intent, one enum, and a thin adapter over the existing function. Next: compile against the selected Xcode 27 SDK. Then check metadata extraction and run in Shortcuts with decomposed accents, ZWJ emoji, a supplementary scalar, an empty string, 1025 scalars, and a scalar newer than the OS.

### 9. Export Uniboard configuration — new first-batch item #2

- **Business state: implemented.** The chain is `App/ConfigurationView.swift`, `export()` → `App/ConfigurationFile.swift`, `ConfigurationService.current()` (`@MainActor`) → `ConfigurationCodec.encode(_:inLibrary:)` → `ConfigurationService.writeExport` → `ConfigurationShareSheet.present`.
  - `current()` first calls `SymbolBoardStore.shared.refreshFavorites()`, which may merge and persist favorites. Export already has this side effect today.
  - `encode` produces deterministic UTF-8 TOML. It returns nil (never truncated) for invalid explicit rows/arrangements or output above `TOMLLimits.maximumBytes` (4,000,000).
  - Filename: `ConfigurationCodec.exportFilename(date:)` gives `Uniboard-Configuration-YYYY-MM-DD.toml`.
  - Type: `UTType.uniboardConfiguration` (`App/ConfigurationFile.swift`).
- **Direction (proposal):** an action named "Export Uniboard Configuration". It takes no parameters and returns `IntentFile(data:filename:type: .uniboardConfiguration)` with the encoded bytes, with no temporary folder and no share sheet. An encode failure throws an error. Repeated calls return the current configuration each time. Other than the existing favorites sync, nothing is mutated.
- **Access and safety:** the file includes favorites and custom key text. `ConfigurationCopy.privacy` already warns: "may be personal". The intent description should carry the same warning (proposal). Product must accept that a personal automation could run the export unattended; data leaves the device only if the shortcut sends it somewhere. Existing limitation: Copy Image colors chosen in the keyboard without Full Access are not included (`ConfigurationCopy.keyboardColors`). No login is involved. App Group access while the device is locked has not been verified (G5).
- **Ordinary path: recommended.** Background mode, with `perform` on the main actor because `ConfigurationService` is `@MainActor`. Result: `ReturnsValue<IntentFile>` (A9, A10, A13).
- **Schema:** the reference lists a `files` domain, but its semantics (an app's file library) were not verified to fit a settings export (G4). Not determined.
- **Entry points:** Shortcuts action only. No Spotlight indexing of configuration content.
- **Priority and cost:** #2, **S–M**. Next: compile, then verify that the exported file round-trips through the existing Import review. Test before migration (no shared location yet), with favorites sync unavailable, and with the device locked.

### 2. Get exact Unicode text — supply a character or full emoji to another step (first-batch item #3)

- **Business state: lookup implemented; result adapter proposed.** Unchanged chain:
  - Copy actions: `App/CharacterDetailView.swift`, `actions`/`copyFormButton` (pasteboard plus `recordUse`).
  - Lookup: `Shared/UnicodeCatalog.swift`, `character(at:)`.
  - Emoji: `Shared/EmojiCatalog.swift`, `UnicodeEmojiEntry.text` (keeps variation selectors and ZWJ).
  - The catalog does not depend on any view. The edition comes from the persisted preference (`App/CatalogPreferences.swift`).
- **Direction (proposal), unchanged:**
  - Input: a required exact identifier, either `U+XXXX` or a canonical hyphen-separated emoji sequence ID, under the current edition.
  - Result: the original text as a `String`, not the preview/dotted-circle text.
  - Reject free-text names, invalid or surrogate scalars, unknown sequences and unassigned (`Cn`) code points. This is a new guard: `character(at:)` returns an unassigned placeholder.
  - No clipboard, recents or scratchpad. The same input and edition give the same output.
- **Access and safety:** public catalog data. The result may be an invisible or combining character, so a name and code-point description should come with it (proposal).
- **Ordinary path: recommended (changed from needs verification).** The previous gaps (G1: the String parameter initializer and `result(value:)` for String) are now closed by A6, A7 and A10. Background execution.
- **Schema:** none determined. **Entry points:** Shortcuts only.
- **Priority and cost:** #3, **S–M**. Product decision: use the current edition only, or add an optional edition parameter later. Next: compile, then test draft versus release membership, variation selectors/ZWJ, invalid and unassigned input, and a cold launch.

### 10. Make image of Unicode text (Copy Image) — needs verification

- **Business state: implemented in the keyboard only.**
  - Entry: `Keyboard/KeyboardViewController.swift`, `copyPreviewImage()` writes a frozen PNG via `KeyboardPreviewClipboard.write` (needs Full Access).
  - Renderer: `Shared/KeyboardPreviewImageExport.swift`, `KeyboardPreviewImageRenderer.render(_:availableWidth:visibleHeight:colors:scale:font:)` (`@MainActor`). It draws a `KeyboardPreviewExcerpt` and clips it to the row window. It fails with `.empty`, `.tooLarge` or `.encodingFailed`.
  - Limits: 4800×1200 px and 2.4 MP (`KeyboardImageCanvas` in `Shared/ImageColorSettings.swift`).
  - Options: scale `KeyboardImageScale` (x1/x2/x3) and colors `KeyboardImageColorPreset` (black on white, black on transparent, white on black, white on transparent, custom).
  - Fonts: through `UnicodeFontSupport.font(for:size:enabled:)`, which applies font rules via the static `ruleSet`.
  - The file is in the app's source phase.
- **Why pending:** the renderer is designed for a bounded keyboard-row excerpt. An app action needs a new layout policy: compute the width from the text, decide on single versus multiple lines, and report over-limit input truthfully. It also needs to confirm that font rules (`UnicodeFontSupport.ruleSet`) and downloaded fonts are loaded in a cold background launch (G5).
- **Proposed shape:** text plus preset and scale enums → `IntentFile` PNG (A13). Reject empty input and input that is too large. **M.** This has high sharing value (it shows rare glyphs to recipients who lack the fonts), so it is the first pending item to verify.

### 1. Search Unicode in Uniboard — needs verification (unchanged)

- **Chain:** `App/ContentView.swift`, `ExploreView` → `CatalogSearch.update(_:catalog:limit:)` → `CatalogWorker.run` → `UnicodeCatalog.search(_:limit:order:indexStore:)`. Search now uses the persisted `UnicodeSearchIndexStore` (App Group caches) and falls back to scanning.
- **Missing link:** `ContentView.selectedTab` and `ExploreView.query` are still private `@State`. The only route is Settings. Delivering a query, including on a cold launch, is new work.
- **API:** the String parameter is now verified (A6). The foreground path is not:
  - `openAppWhenRun` is iOS 16.0 but deprecated in 26.0 (A4).
  - `supportedModes` is iOS 26.0 (A4b).
  - Combining both for an iOS 17 target, and the runtime behavior on iOS 26+, are unverified (G3).
- **Cost and next step:** **M.** It remains the most valuable foreground action once G3 and routing are designed.

### 4. Compare fonts for Unicode text · 5. Search Google Fonts · 6. Open a font detail — needs verification (unchanged chains)

- **Compare fonts:** `CharacterFontsView` → `FontExplorationViewModel.scan` → `App/FontComparisonEngine.swift`.
- **Search Google Fonts:** `GoogleFontsView` → `GoogleFontCatalog.search`.
- **Open a font detail:** `App/FontFaceDetailView.swift`. Version 1.3 adds `StyleGridView`: width columns under Normal/Italic, Standard first, with a Variant grouping where needed, built in `Shared/StyleGrid.swift`.
- **What blocks all three:** each is a foreground destination behind private view state, with no external route (G3). A font face or family entity would additionally need `AppEntity`/`EntityQuery` evidence, which was not read for this update. The previous verdicts and cost estimates (M–L, M, M) still stand.

### 11. Set a preferred font rule — needs verification (new)

- **Business state: implemented.**
  - Character detail: `preferredFontCard` → `FontRulePickerView` → `App/FontRulePreferences.swift`, `setFace(_:forCodePoint:)` → `FontRuleOrdering.settingFace`. This is a *set* operation, so repeating it is idempotent. `clear(codePoint:)` is also available.
  - Settings rule editor: `App/FontRuleEditorView.swift`, `save()` → `FontRulePreferences.save` → `Shared/FontRuleStore.swift`, `save(_:blocks:)`. It validates, refuses rather than repairs, and atomically replaces `font-rules-v1.json` in the current configuration generation. The keyboard reads it via `FontRuleSnapshotReader`.
  - Selectors are code point, inclusive range, or Unicode **block** (`FontRuleKind`). **No script-based selector exists.**
  - Saving never turns on Extra Unicode Fonts.
- **Why pending:**
  - It needs a font face entity over the picker catalog (`Shared/FontPickerCatalog.swift`, sections yours/google/preview/system/other), with `FontFaceReference` identity.
  - The picker marks fonts as "App Only" or "Keyboard Unverified" (`KeyboardFontStatus`). An action result would have to state that the keyboard may fall back.
  - Entity and query APIs were not verified, and value is moderate: rules are configured once, not used every day. **L.**

### 3. Add Unicode text to Favorites — needs verification (unchanged)

- **Chain:** `SymbolBoardStore.add(text:to:)` is an idempotent add, unlike `CharacterStore.toggleFavorite`. `FavoriteSync` shares favorites through the App Group.
- **What has changed:** the API evidence is now verified (A6).
- **What still blocks it:** the result must truthfully report local versus shared-sync outcomes (`syncStatus`), and protected-data behavior on a locked device must be defined. Configuration import (action 12) can now replace favorites wholesale, so an add racing with an import also needs a policy. **M.**

### 7. Download a Google font style — needs verification (unchanged; per-file grid added)

- **Chain:** the 1.3 style grid offers "Download File (n Styles)". The download still goes through `FontFaceDetailView` → `GoogleFontDownloadCoordinator.download(styleID:)`, which resolves the style's file. One download affects every style that shares that file.
- **What blocks it:** network, storage and lifecycle checks, plus result semantics. These are unchanged from the previous report. **L.**

### 12. Import / replace configuration · Undo Last Configuration Change — not recommended (new)

- **Business state: implemented.**
  - Import: `ConfigurationView` `fileImporter` → `ConfigurationImportModel.load` → `check` (validates and diffs, no writes) → the user reviews the diff in `ReviewImportView` → `replace()`.
  - Writing: `replace()` calls `SharedConfigurationLocation.apply(_:expecting:currentPresentation:)`, a fingerprint-checked, generation-switched write. It also sets up undo.
  - Undo: `ConfigurationUndo.run`.
- **Reason:** both actions replace favorites, key layouts and rules wholesale. The design depends on the user seeing a review diff and confirming it, and on a generation-conflict alert. A system action would bypass or duplicate that safeguard. The app also declares no document types, so a Files "Open in Uniboard" handoff does not exist either.
- **What would change the decision:** a foreground handoff that opens the existing review screen, after a separate safety assessment.

## API and availability evidence

All rows were verified on **2026-10-24**.

- **Docs:** Apple DocC JSON at `https://developer.apple.com/tutorials/data/documentation/<path>.json`. Responses carry Last-Modified 2026-10-08, the LocalizedStringResource pages 2026-10-08 15:4x. The docs record each symbol's own declaration and iOS platform metadata.
- **SDK17:** `iPhoneOS17.0.sdk/.../AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface` (Swift 5.9, `-target arm64e-apple-ios17.0`). Source: the third-party mirror `raw.githubusercontent.com/xybp888/iOS-SDKs/master/…`. Line numbers below refer to that file. It shows the declarations existed in the iOS 17.0 SDK. It is **not** the selected Xcode 27 SDK.
- **Selected SDK:** not inspected. A compile check is the remaining step.

| ID | Exact symbol | Documented iOS min | Evidence (docs path · SDK17) | Gap / next check |
| --- | --- | --- | --- | --- |
| A1 | `protocol AppIntent : PersistentlyIdentifiable, _SupportsAppDependencies, Sendable` | 16.0 | `appintents/appintent` · l.185 | Compile on the selected SDK |
| A2 | `AppIntent.perform() async throws -> Self.PerformResult` | 16.0 | `appintents/appintent/perform()` | — |
| A3 | `static var title: LocalizedStringResource`; `LocalizedStringResource.init(stringLiteral:)` | 16.0; 16.0 | `appintents/appintent/title` · l.187; `foundation/localizedstringresource/init(stringliteral:)` | — |
| A4 | `static var openAppWhenRun: Bool` | 16.0, deprecated 26.0 | `appintents/appintent/openappwhenrun` · l.188 | Foreground strategy for an iOS 17 target on iOS 26+ (G3). Not used by the ready batch. |
| A4b | `static var supportedModes: IntentModes` | 26.0 | `appintents/appintent/supportedmodes` | Above the target; would need runtime gating (G3) |
| A5 | `@propertyWrapper final class IntentParameter<Value> where Value: _IntentValue, Sendable` | 16.0 | `appintents/intentparameter` | — |
| A6 | `IntentParameter.init(title:description:default:inputOptions:requestValueDialog:inputConnectionBehavior:)`, constrained to `Value.ValueType == String` | 16.0 | `appintents/intentparameter/init(title:description:default:inputoptions:requestvaluedialog:inputconnectionbehavior:)` · l.3176 in `extension IntentParameter where Value.ValueType == Swift.String` (iOS 16.0) | — |
| A7 | `extension Swift.String : AppIntents._IntentValue` | 16.0 (SDK17 annotation) | No Apple page (underscored protocol) · SDK17 l.2630 | Shown only in SDK17; confirm on the selected SDK |
| A8 | `protocol IntentResult : Sendable`; `struct IntentResultContainer<Value, OpensAppIntent, Snippet, Dialog>` | 16.0; 16.0 | `appintents/intentresult`, `appintents/intentresultcontainer` · l.1934 | — |
| A9 | `protocol ReturnsValue<Value> : IntentResult`; `extension IntentResultContainer : ReturnsValue` | 16.0 | `appintents/returnsvalue` · l.1917, l.1940 | — |
| A10 | `static func result<Value>(value: Value) -> Self where Self == IntentResultContainer<Value, Never, Never, Never>, Value: _IntentValue` | 16.0 | `appintents/intentresult/result(value:)` · l.1957 | — |
| A11 | `protocol AppEnum : AppValue, StaticDisplayRepresentable, RawRepresentable`; `AppValue`; `CaseDisplayRepresentable.caseDisplayRepresentations`; `TypeDisplayRepresentable.typeDisplayRepresentation`; `DisplayRepresentation`/`TypeDisplayRepresentation : ExpressibleByStringLiteral` | all 16.0 | `appintents/appenum`, `/appvalue`, `/casedisplayrepresentable/casedisplayrepresentations`, `/typedisplayrepresentable/typedisplayrepresentation`, `/displayrepresentation`, `/typedisplayrepresentation` · l.2469, 948, 460, 432, 2274, 435 | — |
| A12 | `IntentParameter.init(title:description:default:requestValueDialog:requestDisambiguationDialog:inputConnectionBehavior:supportedValues:)` where `Value.ValueType: AppEnum` (the `-2wsgy` overload; the AppEntity & AppEnum variant `-9lv7y` is deprecated in 18.0) | 16.0 | `appintents/intentparameter/init(…supportedvalues:)-2wsgy` · l.3422–3423 | — |
| A13 | `struct IntentFile : Sendable`; `init(data: Data, filename: String, type: UTType? = nil)`; `extension IntentFile : _IntentValue` | 16.0 | `appintents/intentfile`, `appintents/intentfile/init(data:filename:type:)` · l.17, 34, 59 | The custom `UTType(importedAs:)` already exists in the app; compile status unknown |
| A14 | `static var description: IntentDescription?`; `struct IntentDescription : ExpressibleByStringLiteral` | 16.0 | `appintents/appintent/description`, `appintents/intentdescription` · l.527 | — |
| A15 | `protocol AppShortcutsProvider` | 16.0 | `appintents/appshortcutsprovider` · l.1315 | Protocol only. `AppShortcut` initializer and phrase tokens unread (G2). Not in the ready scope. |

### Remaining gaps

| ID | Missing evidence | Next check |
| --- | --- | --- |
| G1 | Selected Xcode 27 SDK declarations; App Intents metadata extraction; Swift 5 mode / strict-concurrency diagnostics for the proposed types | Build the app target with the batch intents (separate task) |
| G2 | `AppShortcut` initializer, phrase/application-name token, Spotlight action discovery | Read the exact symbol docs before adding tiles or Siri phrases; optional |
| G3 | Foreground mode strategy (A4 vs A4b) for iOS 17–26+, plus query/destination routing (none exists) | Read the `IntentModes` member docs, design `ContentView` routing, then test cold and warm launch |
| G4 | Schema fit (domain/member, required entities); the toolchain schema database could not be read here | Only after product picks a schema-worthy task; do not assign versions |
| G5 | Cold background launch in the app process: `UnicodeCatalog.shared` load time, App Group/protected-data access while locked, font-rule and download state for rendering | Device run of each intent with the device locked and unlocked |

No compilation, metadata visibility check, Shortcuts/Siri/Spotlight run, simulator run or real-device run was done.

## Planned, uncertain and excluded features

| Feature / user task | Business state and evidence | Verdict / reason | What would change it |
| --- | --- | --- | --- |
| Preview cursor (drag/move caret in the preview) | `Shared/KeyboardPreviewCursorControl.swift`, `KeyboardPreviewCursorPolicy.swift`. Store copy calls it unfinished. | **Excluded:** keyboard-only interaction with a live host | — |
| Auto-capitalization setting | `Shared/AutoCapitalizationSetting.swift` (`save` is app-only, read by the keyboard), set via `CatalogPreferences` | **Excluded:** one-time setup toggle. A set-to-value intent would be possible but fills a quota. | Real automation demand |
| Landscape search, query hold, search index | `Keyboard/` and `Shared/KeyboardQueryHold*`, `UnicodeSearchIndex*` | **Excluded:** keyboard layout and performance work; the index serves action 1 | — |
| Inspect Text copy / Copy Image inside the keyboard | `KeyboardViewController.copyTextInspection`, `copyPreviewImage` | Covered by app-side actions 8 and 10. The keyboard's own pasteboard flow cannot be called from a system action. | — |
| Type directly into another app | `KeyboardViewController.insertHostText(_:literalToken:)` via `textDocumentProxy` | **Not recommended:** needs an active keyboard host | — |
| Scratchpad append/clear; open/create/import/export/delete pages; remove downloaded font | Unchanged from the previous report (`CharacterDetailView`, `PagesView`, `SymbolBoardStore`, `CustomFontStore.removeGoogleFont`) | **Not recommended initially:** duplicate appends, destructive effects, file handling | Explicit workflow demand plus a confirmation policy |
| Clear a font rule / reorder rules | `FontRulePreferences.clear(codePoint:)`, `remove(id:)`, `move(...)` | **Not recommended:** destructive or ordering edits belong in the rule list UI | Considered with action 11 |
| Enable keyboard / Full Access | OS Settings; companion Settings route only | **Not recommended:** a user permission decision | At most a foreground setup destination |
| Script-based font rules | No script selector exists (`FontRuleKind` = codePoint/range/block) | **Not implemented**, not a candidate | Implement first |
| Schema-enhanced Siri / Apple Intelligence | No schema declarations; no verified fit | **Needs verification**, optional (G4) | — |

## Product handoff

**Proposed first batch (in order):**
1. **Inspect Unicode Text**
2. **Export Uniboard Configuration**
3. **Get exact Unicode text**

All three are ordinary background Shortcuts actions in the `Uniboard` app target. Each is a thin adapter over existing code, and their APIs are verified from iOS 16.0 (A1–A14). The iOS 17 deployment target stays unchanged.

**Decisions needed before implementation:**
- Inspect: the input bound (keep 1024 scalars?) and erroring when the OS normalization data is older than the catalog.
- Export: the privacy wording, and whether unattended automation of a file containing personal favorites is acceptable.
- Exact text: current edition only, and the unassigned-code-point guard.

**Next to verify:**
1. Make image of Unicode text (layout policy, G5).
2. Search Unicode and the font destinations (foreground strategy and routing, G3).
3. Font rule entity, Favorites result semantics, and font download. These are lower priority.

App Shortcut phrases, Spotlight and schema work stay optional and are deferred (G2, G4).

This analysis changed only `intent-opportunities.md`. It made no app or configuration edits, no git state changes, no builds or tests, and no business operations. Integration, compilation and device acceptance are separate tasks after product approval.


## 2026-10-25 reassessment — 1.4 browsing, downloads and explicit rows

### Current inventory and project facts

**The current source declares 0 App Intents actions, no App Shortcuts provider, no entities/queries and no Apple Intelligence schemas.** The ready first batch remains Inspect Unicode Text, Export Configuration (privacy/product decision still required), and Get Exact Unicode Text. A new read-only Validate Configuration opportunity is recommended for a later batch, not silently added to the first three.

- Imported app, branch `master`, HEAD `d3f76b0f297479a3915cededbec4572dcf3bd651`; 81 modified/untracked status entries at this live working-tree snapshot. Other agents are actively finishing implementation and verification; this is not a release checkpoint.
- Scope: `docs/1.4/brief.md`, `docs/1.4/rows-api.md`, current implementation and source phases. 1.3 build52 remains submitted/Waiting for Review; no 1.4 submission authorization. Source marketing version still 1.3/build1 and was not changed by this assessment.
- Search over App, Shared, Keyboard, Tests, UITests and package/scripts for AppIntent, AppShortcut, AppShortcutsProvider, AppEntity, EntityQuery, AppEnum, IntentParameter, assistant/schema macro spellings, INIntent, Intents imports, WidgetKit and ControlWidget found no declarations. Plists and project source phases have no widget/control/intent-definition/document/activity entry points.
- Production external route remains `uniboard://settings` (`CompanionAppRoute.isSettings`, `ContentView.onOpenURL`); DEBUG fixtures are not app routes for automation.

| Target | Checked current membership and settings | Limits |
| --- | --- | --- |
| Uniboard app | `project.yml` and `.pbxproj` source phase E17E8EA272032DA22C8E9942 contain configuration editor/codec/model/diff, text inspection, catalogs and row renderer/editor | iOS17.0, Swift language5.0, SDKROOT iphoneos; project.yml requests Xcode27.0 |
| UniboardKeyboard | Phase403420D087165E9E66B28DEE has shared rows/pages/alphabet/catalog and ExplicitKeyboardRow, excludes TOML/configuration codec/model/diff and FontRuleEditing | iOS17.0, APPLICATION_EXTENSION_API_ONLY YES; proposed actions belong in app |
| Tests/UI tests | Separate test phases include editor/codec/row tests | iOS17.0; assessment itself ran no tests |
| UniboardCore | Explicit shared subset, excludes SwiftUI ExplicitKeyboardRow | macOS13, tools5.9; not an Intent host |

Selected compiler/SDK and preview runtime were not queried as part of this discovery. Existing Apple evidence A1–A14 remains dated 2026-10-24, with its original provenance/freshness limits; this reassessment made no network claims or new API availability assertions. Implementation builds and simulator checks performed elsewhere do not verify these unimplemented Intents.

### Changed business-action assessment

| Existing action | Rechecked chain and decision delta |
| --- | --- |
| 8 Inspect Unicode Text | `Shared/TextInspection.swift` remains app+keyboard member. Retain explicit text input, proposed1024-scalar guard, unavailable-normalization error and no clipboard/storage/recents. Recommended unchanged. G1/G5 remain. |
| 9 Export Configuration | `ConfigurationView.export` → `ConfigurationService.current` → `UniboardConfiguration.capture` → `ConfigurationCodec.encode`. Current still refreshes/possibly merges favorites, so not strictly side-effect-free. Capture now includes hidden emoji groups, emoji columns, block direction and exact explicit rows/alignment/gaps/payloads. Codec emits TOML2 when any saved page/arrangement is explicit, otherwise1; decoder accepts1/2. Return the codec bytes rather than reconstruct/downgrade. Invalid rows as well as size can fail encoding. Recommended S–M, subject to existing unattended-export/privacy decision; add schema1/2/legacy round-trip tests. |
| 2 Get Exact Unicode Text | `UnicodeCatalog.character(at:)` still returns Cn placeholders for unassigned/noncharacters; proposed guard remains. `UnicodeEmojiEntry.text` preserves exact scalars. Exact-ID resolution must use the selected edition’s full catalog, not a filtered browse result. Hidden groups are visibility preferences, not authorization/deletion. Recommended unchanged. |
| 7 Download Google font style | `FontFaceDetailView.perform` → `GoogleFontDownloadCoordinator.download(styleID:scope:)` now distinguishes instance/file. Trusted pinned single-style instances and original/shared files are distinct. Existing bytes may produce already-downloaded success, jobs deduplicate by downloadID, absent bytes need repair. Result must truthfully state instance/shared-file scope. No old downloads are automatically removed. Same candidate, still needs verification/L: identity, capacity, hosts/privacy, cancellation and background lifecycle. |
| 4 Compare fonts / 6 Open font detail | `StyleGrid`/`StyleGridView` derive width columns under Normal/Italic, Standard first and actual style coverage. This improves existing destinations; width/weight selection is not another action. Foreground route/API and entity gaps remain. |
| 12 Replace Configuration / Undo | `ConfigurationView.openEditor` → `ConfigurationEditorModel.live`; Apply uses review/replace. `ConfigurationImportModel.replace` compiles and fingerprint-checks before generation apply/adoption. Undo Last Configuration Change now covers editor apply and imports. Background replacement still not recommended. A future foreground review handoff needs production routing/document/safety design. |

### 13 Validate Uniboard Configuration — recommended next wave

**Business implementation: implemented; adapter/report proposed.** Scenario: validate authored/generated TOML without applying it or accessing personal current configuration.

Evidence chain: Settings → `ConfigurationView.openEditor` → `ConfigurationEditorView` Validate → `ConfigurationEditorModel.validate/check` → `ConfigurationImportModel.check` → `ConfigurationCodec.decode`. The app-member codec enforces the4,000,000-byte bound, parses TOML schema1/2, validates settings/keys/pages/rules, returns metadata or bounded-count diagnostics. `readRows` checks alignment, cells, mixed/legacy representations, explicit width and Favorites restrictions.

Proposed action: required TOML text String → String report; `Data(text.utf8)` → codec decode directly. Preserve the exact input, no trim/rewrite/normalization. New report adapter returns invalid diagnostics or “valid format; not applied”, schema version, missing-section/default-reset and retired-setting warnings. Never claim safe to apply, installed fonts available, or equivalence to current settings. UI check also captures/diffs current settings and can refresh favorites; deliberately exclude that environment path. Do not compile/apply/write generations/start import/initialize Undo. Same input and bundled catalog/app version gives the same result.

No account, keyboard Full Access, clipboard/file permission, entity lookup or confirmation is needed for this proposed String-only read action. TOML may contain personal text; do not log/donate/index it. Diagnostics may expose input-derived page names/IDs/font references: no whole-input echo and no false claim that reports contain no personal text.

Ordinary background String→String path reuses dated A1–A3/A5–A10/A14 (recorded iOS16 APIs below app’s iOS17 target). Proposed S–M, useful to configuration authors but lower reach than the original three; recommended next wave only. No new file-input API is asserted. Shortcuts user-composed action only; Siri phrases/App Shortcut tiles deferred G2, no Spotlight indexing, schema fit undetermined G4. Cold background execution is architecture-supported, not runtime-proven. Selected-SDK metadata/build and G5 remain unverified.

After product approval, test valid1/2, malformed line/column, mixed rows/legacy fields, >12 explicit versus preserved legacy rows, decomposed/ZWJ text, missing/ignored sections, blank/>4MB input, bounded diagnostics and no writes. This discovery performed none of those actions.

### New exclusions and scope boundaries

| Feature | Implemented evidence | Verdict |
| --- | --- | --- |
| Alignment, split/join/reorder | RowAlignmentCard → MainKeyboardEditorView.align/editRows → KeyboardKeyPreferences.saveArrangement; PageArrangeView.alignmentCard → SymbolBoardStore.setExplicitRows. Explicit <=12 weighted units, legacy16 adapter, physical Left/Right/Center/Spread, Favorites dynamic; ExplicitKeyboardRow shared renderer | Visual authoring with conversion/repair implications, not standalone automation. Row identity is positional; stale row-number mutations need new policy. Export/Validate cover portability. |
| Emoji groups/zoom/block order | EmojisView/CatalogPreferences/EmojiCategorySetting; shared hidden names filter keyboard before pagination; columns/direction app presentation capture | Setup/presentation, not independent actions. Filters do not constrain exact-ID lookup. Zoom app-only. Future browse Search should preserve visible scope. |
| Hebrew/Arabic and consolidated Main Keyboard | KeyboardAlphabet catalog/isCaseless/diacritics/punctuation; useStockNumberRow; editor Letters/123/#+= | Setup, not system host typing/switching. Armenian was deferred by product msg812; old brief wording is not implementation authorization. Native-reader/device checks not done by discovery. |
| Versioned rows | Shared pages1/2, local state1/2/3, PageFile1/2, settings1–5, TOML1/2; generation pointer stays1; Shared/ExplicitKeyboardRow is a separate renderer with app+keyboard membership | Strengthens Export/Validate, not automatic migration/import intents. |

### Current handoff and limits

No Intents are implemented. Keep identities1–12; add13 as the next-wave read-only candidate. First batch still Inspect Unicode Text, Export Configuration (privacy decision), Get Exact Unicode Text. Preserve G1–G5 and dated API evidence. Ordinary core recommendations do not include unverified tiles/phrases/Spotlight/schema surfaces. No compiler, metadata extraction, Siri/Shortcuts/Spotlight/device execution was performed by this reassessment. Integration remains a separate authorized task.


## 2026-10-25 follow-up 1.4 — shared-page save results and compact font companion

**Decision unchanged:** 0 declared Intents; first batch remains **8 Inspect Unicode Text**, **9 Export Uniboard Configuration** (privacy/product decision), and **2 Get Exact Unicode Text**. Preserve identities1–13 and the preceding 1.4 reassessment, including13 Validate Configuration as next wave only. Save-page/row authoring remains excluded, not a new recommendation;3 Favorites still needs its separate local/shared-sync and locked-device result policy.

### Static source snapshot and scope

Read at **2026-10-25 17:32 UTC**, shared dirty `master`, HEAD `d3f76b0f297479a3915cededbec4572dcf3bd651`;89 modified/untracked status entries at the inventory snapshot. Re-ran declaration/integration searches across192 Swift files plus plists, project/scheme, package and script inputs (211 files total in App/Shared/Keyboard/Tests/UITests/Scripts/Uniboard.xcodeproj plus project.yml/Package.swift): AppIntent, AppShortcut/Provider, AppEntity, EntityQuery, AppEnum, IntentParameter, assistant/entity/intent macros, INIntent/Intents imports, intentdefinition, WidgetKit/ControlWidget, CoreSpotlight and NSUserActivity returned no matches. Plists/project.yml still declare no document/activity handoff; production routing remains Settings only. This is source evidence, not installed-system visibility.

Re-read `project.yml`, `.pbxproj` target/source/resource phases and `Package.swift`: Uniboard app and UniboardKeyboard remain iOS17.0, Swift5.0, SDKROOT iphoneos; keyboard is extension-API-only. Test/UI-test targets inherit iOS17.0. UniboardCore remains macOS13/tools5.9, not an Intent host. App+keyboard share SymbolBoardStore, FontLibraryContracts/Storage, TextInspection and ExplicitKeyboardRow; configuration codec/model/diff remain app-only among shipping targets. GoogleFonts remains an app resource folder. Xcode27.0 is the generation-input request, not a newly observed compiler/SDK/runtime. **Apple evidence A1–A15 remains verified on2026-10-24 only**, with original provenance and limits; no new Apple/API availability claims or network verification were made. G1–G5 remain.

### Save acceptance is not a two-store transaction

The historical `notes/1.4/save-risk-result.md` investigation (outside the project) reproduced the old false-after-shared-publication behavior; its passing characterization tests are **not final-fix acceptance evidence**. The now-authorized direction is visible in current `Shared/SymbolBoardStore.swift`, `commit`: after validation/encoding, a changed shared page/preferred-star snapshot must successfully pass `SymbolPageSettings.save`; that publication is the page mutation's commit point. If secondary `persist(data)` acknowledgement fails, `publishedPages || localSaved` still accepts the mutation, adopts boards/active/preferred state and exposes `localCopyWarning`/`localCopyWarningID`. Shared-save rejection returns before the local attempt. **Local-only operations retain their acknowledgement-required failure behavior**; Favorites sync remains separate, not implied by an accepted page edit. No durable-disk or atomic two-store guarantee follows from Bool/readback.

`App/PageArrangeView.swift` observes the adopted store, keeps the existing rejected-save error for actual failure, and currently presents/announces: “Your change is saved and available to the keyboard, but the app couldn’t update its local copy.” Warning presentation can be dismissed independently of cache health; a no-op must not claim repair. Current store code schedules **no delayed retry or replay of an older snapshot**. Any future cache repair must use current authoritative state, not stale edits. This is an in-progress source snapshot: store/UI are still being finalized, and final wording, warning lifecycle and acceptance require parent review. In particular, **corrupt/unsupported/oversized local-cache recovery is not established by this change**: the inspected initializer still sets `loadIssue`, and `refreshPages` requires `canEdit`; verify the final corrupt-cache policy before claiming shared pages always recover/reopen successfully. Configuration generation Apply/Undo is a separate path, unchanged by this result assessment.

### Compact font companion is not an action

`Shared/FontLibraryContracts.swift`, `FontCatalogEquivalenceIndex.bundled`, now selects basename **equivalences.json** under GoogleFonts rather than the full browser catalog for its read-only identity projection. `decode` still checks the pinned schema/repository and exact content-hash/face-index/variation identities; missing/invalid input falls back to empty. `Shared/FontLibraryStorage.swift` enriches face records using this bundled index without a new business operation. The containing-app resource lookup is not a new automation entry point. `App/GoogleFontCatalog.swift` still loads **catalog.json** for the full app browser; it is not replaced by the companion. Action7 Download Google Font Style remains the same needs-verification candidate with instance/shared-file identity and lifecycle/result gaps, not a new entry point. No RSS or measured memory/performance claim is made.

Only this report was edited in the project for the discovery follow-up. No Intents/code/configuration implementation or business actions were performed by the discovery agent; the parent’s app implementation and verification are separate.

### Parent final-source review — 2026-10-25 17:47 UTC

Re-read final `SymbolBoardStore.commit`, `refreshPages`, initialization guards and warning dismissal, and the compact `FontCatalogEquivalenceIndex.bundled` path. The preceding acceptance/Favorites/current-state/no-replay analysis remains accurate. Corrupt, unsupported and oversized local payloads remain locked with original bytes preserved; this fix deliberately does not introduce universal cache recovery. Cosmetic dismissal clears only the presentation UUID; pending warning remains until actual successful current persistence. No new action or integration recommendation follows from the UI-only filtered-emoji guidance.

Parent verification, not Intent execution: final Store/core sources passed675core tests (1optional benchmark skipped), all38coverage gates100%, and114scoped native tests (1environment-specific OS-alias skipped). Final preview archive4604a120-8c17-4f2a-92b3-8c3068acceb6 succeeded on **Xcode27.1 RC27A9275 / iPhoneSimulator27.1 SDK**; both shipped app and extension plists retain minimumiOS17.0. The native test run used Xcode27.0/iOS27.0. Built compact/full resources match the recorded source hashes, with the compact resource present only in the containing app. These results do not verify a proposed Intent’s metadata, Shortcuts visibility, Siri/Spotlight, locked-device behavior or physical extension memory. No Intents were added. First batch and all dated Apple API evidence/limits remain unchanged.


## 2026-10-28 reassessment — language downloads and My Words

### Existing integration, scope and environment

**Uniboard still declares 0 App Intents actions: no Shortcuts/App Shortcuts, Spotlight, Siri, widget/control entry points or Apple Intelligence schemas are integrated.**

| Inventory | Current evidence | Limit |
| --- | --- | --- |
| No declared actions, providers, entities or queries | Re-searched project Swift sources, including App, Keyboard, Shared, Tests and UITests, for AppIntent, AppShortcut/Provider, AppEntity, EntityQuery, AppEnum, IntentParameter, assistant macros, Intents imports/INIntent, CoreSpotlight, NSUserActivity and WidgetKit/ControlWidget; no matches. Read both shipping plists, `project.yml` and current `.pbxproj` target/source phases. | Static inventory, not installed-system visibility. `UTImportedTypeDeclarations` for TOML is not a document-opening route. |
| Settings URL only | `Shared/CompanionAppRoute.swift`, `isSettings(_:)` → `App/ContentView.swift`, `onOpenURL`; rejects embedded query/fragment data. Settings → `App/SetupView.swift` → `LanguagesView` → `MyWordsView` is ordinary navigation. | No production language, dictionary or import-review route. DEBUG fixtures are not an integration. |

- Imported app; **2026-10-28**, shared **dirty master, HEAD `d3f76b0f297479a3915cededbec4572dcf3bd651`** (parent-provided baseline; no git commands run). Snapshot is the files read, not a counted/frozen working-tree or release checkpoint. Preserve all earlier reports/action identities; this section supersedes only changed facts.
- Read the authoritative product handoff `/run/airbuild/team/state/team/product/handoffs/uniboard-language-input/brief.md` (including msg1043 and the unanswered Korean spelling card), `docs/language-input-configuration.md`, current Languages/My Words/store/parser/downloader/environment bodies, and the existing first-batch chains. Language implementation is authorized elsewhere; **this task authorizes discovery/report only**.
- Business logic and UI wiring now exist for Japanese/Mandarin resources, independent English options, custom collections, manual entries, reviewed TSV import, export and one-step dictionary Undo. Final source reread confirms the shared `MandarinPinyinReading.canonicalCustomReading` is wired into both app dictionary rules and keyboard conversion. Parent-reported integrated build/tests and Simulator results below supersede the earlier source-only uncertainty; they do **not** verify any proposed Intent.

| Target / configuration | Current membership checked in `project.yml` and `Uniboard.xcodeproj/project.pbxproj` | Deployment / toolchain distinction |
| --- | --- | --- |
| Uniboard app, Debug/Release, source phase E17E8EA272032DA22C8E9942 | App + Shared: Languages/MyWords UI and models, LanguageInputEnvironment, LanguagePackCatalog/Downloader/Archive/Store, MandarinDictionaryCompiler/Index/Reading, JapaneseInputReading, custom dictionary store/index, configuration codec/model/diff and TextInspection. LanguagePacks metadata/notices are app resources. | iOS17.0; source Swift language5.0; SDKROOT iphoneos. `xcodeVersion: 27.0` is the generator request, not the measured selected compiler. |
| UniboardKeyboard, phase403420D087165E9E66B28DEE | Keyboard + shared language settings/composition, pack contracts/store, custom dictionary model/store/index and shared reading/index types. Japanese/Mandarin converters and coordinator are keyboard sources. Archive/compiler, configuration codec/model/diff/TOML and FontRuleEditing excluded. AzooKey product dependency is keyboard-only. | iOS17.0, extension-API-only YES. Shared source membership does **not** authorize full custom JSON decoding/writing or resource downloads inside the keyboard. Proposed actions belong in the app. |
| UniboardTests / UniboardUITests; UniboardCore package | Separate native test phases; Package.swift explicitly lists shared language/store/compiler/parser tests and resources, tools5.9/macOS13. | No Intent host or language-feature runtime proof follows from package membership. |

**Observed environment, not a new build:** actual recorded Japanese smoke `.../.airbuild/worktree/japanese-smoke/final-run/results/environment.log` reports **macos-xcode-beta, Xcode27.1 build27A9275, Apple Swift6.4 (swiftlang-6.4.0.34.1), iPhoneSimulator27.1 SDK**, macOS27.0.1. `notes/1.4/japanese-engine-smoke.md` records run0befbef6-e1db-4aa7-a64c-e5dff457f135/buildafdbd1ce-a1fb-45b6-8e38-1a4288698c4b: isolated Swift5 consumer/Swift6 engine and generic arm64 iOS17 Simulator compilation passed, plus real dictionary macOS smoke. This is **not** compilation of the integrated app/extension or an iOS17 runtime test. Separately read Mandarin isolated `.../.airbuild/worktree/mandarin-validation/remote/command-output/results/{environment.txt,tests.log,report.json}`: Xcode27.0/27A266a, Swift6.4, 12 tests passed and deterministic full-corpus compilation; do not relabel that run as beta27.1. Neither isolated record alone verifies the integrated UI, canonical-reading change, Intent metadata or device behavior. This assessment executed no commands/builds/tests.

**Parent final integrated evidence — 2026-10-28 (reported by parent, not executed by this discovery agent):** real Japanese and Mandarin downloads were verified installed on Simulator, with neither download auto-enabling its language. Actual keyboard checks passed `nihongo` → `日本語`, `nihao` → `你好`, and exact UTF-8 custom output containing `👩🏽‍💻` plus `e` + combining acute accent (decomposed, U+0065 U+0301). Parent reports **72 Release native tests passing across five classes**, not Intent tests. Final run build **`bdfdad1c` succeeded on Xcode27.1 RC; installation of that final build remains pending** at this handoff. Do not attribute the earlier Simulator/manual results to that not-yet-installed build, extrapolate to physical-device/locked-state coverage, or count these results as Shortcuts/Siri/Spotlight/API acceptance.

### First batch retained; changed existing actions

**First batch remains, in order: 8 Inspect Unicode Text → 9 Export Uniboard Configuration (privacy/product approval required) → 2 Get Exact Unicode Text, as ordinary app-side background value-returning actions for user-composed Shortcuts only; none is implemented.** The dated A1–A14 evidence below the historical report's API heading remains the basis, not a new claim of SDK27 verification.

| Identity | Current chain / delta | Retained scope and guards |
| --- | --- | --- |
| 8 Inspect Unicode Text | `Shared/TextInspection.swift`, `analyze`, `copyValue(for:)`, normalization/encoding bodies still app members. Existing keyboard Inspect/Copy is not the proposed input route. | Explicit caller-supplied String + representation enum → String. Proposed empty/>1024-scalar errors, unavailable-normalization error, no trimming/clipboard/history/host access. A1–A3/A5–A12/A14. |
| 9 Export Uniboard Configuration | `ConfigurationView.export` → `ConfigurationService.current` (still refreshes/possibly merges Favorites) → `UniboardConfiguration.capture` → `ConfigurationCodec.encode`. **Now emits schema3 for nondefault language preferences/pins; otherwise schema2 explicit rows or schema1.** Capture includes separate English flags and enabled-mode/pinned identities, **not pack bytes, My Words collections or unfinished input**. | No parameters → IntentFile of actual codec bytes, not a reconstructed schema1/2 downgrade. Not wholly side-effect-free because of existing Favorites refresh. Proposed privacy wording must distinguish a settings backup from a dictionary backup. Reject encode failure; preserve existing personal-favorites/custom-key warning and unattended-export decision. A1–A3/A8–A10/A13/A14. |
| 2 Get Exact Unicode Text | `UnicodeCatalog.character(at:)` still makes Cn placeholders; `UnicodeEmojiEntry.text` constructs exact full scalar sequences. | Exact scalar/emoji ID in selected edition → String, no browse-filter resolution or phonetic conversion. Proposed invalid/surrogate/unknown/unassigned guard remains; no recents/pasteboard. A1–A3/A5–A10/A14. |
| 13 Validate Configuration | `ConfigurationCodec.decode` accepts schemas1/2/3, including strict language preference/pin validation. | Next wave unchanged: explicit TOML String → bounded String report, decode only, never capture/diff/apply/download. Add schema3/defaults/invalid pins to future checks. Same dated String API evidence; not added to first three. |
| 12 Replace Configuration / configuration Undo | Configuration model compile/capture and `ConfigurationService.refreshAfterReplacement` now reload language preferences through `LanguageInputEnvironment.reloadConfiguration`. | Existing reviewed generation replacement remains excluded from unattended automation. It may change preference flags/pins, but does not install/select/download/delete packs or import/delete My Words. **Dictionary Undo below is a different action/history.** |

G1–G5 remain: selected SDK symbol/metadata checks, cold-launch/protected storage, optional exposure and foreground routing are not closed by unrelated package tests. Other actions1–7/10–11 keep their prior verdicts; this update does not promote font downloads or destructive configuration editing.

### New opportunities — ranking, not another ready batch

Qualitative ranking uses task value, system-entry benefit, actual service readiness and privacy/recovery risk; no usage statistics are available. **All parameter/result types and new safeguards below are proposals, not existing Intents. No new language action enters the ready first batch.**

| New identity / order | User task / business state | Integration verdict and cost |
| --- | --- | --- |
| 14 / 1 | Export one My Words dictionary for explicit backup/transfer — implemented source | **Needs verification; highest-value new candidate. M**: persistent selection, personal-data policy and lossless multipart result. Complements, not duplicates,9. |
| 15 / 2 | Add a reading→exact output to an existing dictionary — implemented source | **Needs verification. M**: safe repeated calls, shared parser acceptance and saved-versus-index-published result. Useful capture from a deliberate Shortcuts input, never from host typing. |
| 16 / 3 | Review an imported dictionary in the app — implemented review/apply source, handoff absent | **Needs verification. M–L**: file access, new production route/foreground delivery and preservation of review/confirmation. Unattended bulk Apply is **not recommended**. |
| 17 / 4 | Obtain a verified Japanese/Mandarin language download — production size wired; parent verified Simulator installs | **Needs verification. L**: long transfer/compilation, lifecycle, progress/cancel, capacity and truthful completion. Prefer existing app detail flow until those gates close. |
| 18 | Set language availability for keyboard use | **Not recommended initially. M**: actual set operation exists but mostly setup, not active keyboard switching; no demonstrated automation demand. |
| 19 | Remove a language download | **Not recommended initially. M**: occasional destructive storage management; keep explicit app confirmation and deferred-reclamation explanation. |
| 20 | Undo last My Words import | **Not recommended unattended; foreground review needs verification. M**: recovery is useful, but generic “last” selection has stale-target risk. Keep in app with verified target/revision. |

#### Shared access and identity policy for14–20

`App/LanguageInputEnvironment.swift` resolves the real App Group `group.ad.neko.uniboard` (matching both entitlements): `LanguagePacks/` and `MyWords/` sit **outside** configuration generations; preferences use `LanguageInputSettings` in the current generation. There is no account/login/remote owner service in these paths. App Group entitlement is a storage boundary, **not device authentication or user consent**. File-provider access for import is another distinct permission. Existing UI confirmations are not automatic authorization for system-triggered writes/exports.

Proposed dictionary lookup uses persisted `CustomInputDictionaryCollection.id` UUID, reloaded at query **and** execution; names are display/search labels, not unique keys. Never fall back from a missing UUID to a same-name collection. A future picker must disambiguate with mode/name/ID and avoid exposing readings/outputs in suggestions. A String UUID parameter is a possible smaller ordinary path using A6; entity/query APIs are not newly verified. No stale positional entry indexes as system identifiers. Recheck selected collection's mode and actual allowed parser, missing storage and revision before mutation; fail closed on corrupt/unreadable data rather than creating a replacement store.

My Words is personal explicit user data. **Proposed** unlock/authentication policy and export consent need product selection and exact Apple API verification (L1 below), including query visibility when locked. No logs/donations/Spotlight indexing of readings, outputs, dictionaries or input files; no whole-input echo or spoken content by default. User-directed file output may subsequently be shared by another Shortcut step: unlike the keyboard's local processing, an exported result is not a promise of permanent on-device confinement. No keyboard Full Access prompt is needed to edit/export app data, but keyboard read access with Full Access OFF/ON, locked-device protection and actual index adoption remain device checks, not promises.

#### 14 Export a My Words dictionary

- **Chain:** Settings → Languages → `MyWordsView.swift`, `WordsCollectionView` Export Dictionary → `MyWordsModel.export(id:)` → fresh `CustomInputDictionaryStore.snapshot` → `CustomInputDictionaryExport.tsvParts` → temporary share files/cleanup. Store also offers `exportCollectionParts(id:weights:)`. UI rejects empty collections; full source reading is off-main on `MyWordsExecutor`, not in the keyboard.
- **Proposal:** required collection UUID (or later verified entity) → **all** UTF-8 TSV parts, deterministic order, safe filenames and default-weight omission as today. Preserve exact output bytes, including canonically distinct sequences. No temporary share sheet in the Intent adapter; construct returned files from data. `tsvParts` splits at entry boundaries to satisfy both1MiB and10,000-entry-line limits. **Do not return only the first part or describe an unbounded `tsv` as universally reimportable.** A later import of each part creates a separate collection; names/mode/enabled state are not encoded by TSV, so do not promise a complete metadata/one-collection restore.
- **Safety/result:** read-only apart from temporary export files, no index mutation. Repeated runs export current bytes, not a frozen backup. Reject missing/empty collection as UI does (adapter guard proposed); consent and locked-state checks above apply. M, candidate14 first among new tasks; **not ready** until multipart `[IntentFile]` result/conformance and privacy/auth policy are verified. A13 verifies only one IntentFile data initializer/value conformance; it does not verify the array result. Test multipart maximum-size/exact-output/relaunch/stale-ID/denied storage and cleanup separately after approval.

#### 15 Add a My Words entry

- **Chain:** `MyWordsView.swift`, `WordsEntryEditor` validation/save → `MyWordsModel.validate` / `saveEntry(index:nil,revision:)` → `CustomInputDictionaryStore.addEntry` → rules.validate → revision-checked coordinated atomic JSON write. `MyWordsModel.mutate` then calls `didMutate` → `LanguageInputIndexWorker.rebuild` → `CustomInputDictionaryIndexCompiler.compile`, followed by a payload-free keyboard invalidation. A compile failure leaves words **committed** and sets `needsIndexRetry`; it is not a failed save.
- **Proposal:** required collection UUID, reading, output; optional weight default100 (0–10000). String-based parameters/summary result can use dated A6/A9/A10; a native Int parameter overload needs its own check. Infer mode from the selected collection, never a conflicting second mode parameter. Use the production rules, preserve output without Unicode normalization/trimming, enforce nonempty fields, <=256 scalars/no Tab/newline/NUL and total50,000 entries. Reject Korean. Creating/enabling a collection, installing/enabling a language or selecting active keyboard mode is **not** part of Add.
- **Repeated calls:** current `addEntry` rejects duplicate **normalized reading + exact UTF-8 output**, irrespective of weight. Proposed adapter may report “already present” only for an identical stored weight after exact lookup; a different weight is a conflict, **not** an update/max merge. Make that decision under the existing revision check; a conflict asks retry/review, never blind replay. The incoming-file highest-weight combine rule does not apply to this action. No auto-creation or name fallback.
- **Parser gate:** current `LanguageInputEnvironment.dictionaryRules` uses English ASCII-word validation, `JapaneseInputReading.normalizedCustomReading`, and newly added `MandarinPinyinReading.canonicalCustomReading`; keyboard coordinator also calls the latter. Canonical Mandarin requires complete supported-syllable segmentation, preserves hard apostrophes/ü distinction, and converts tone marks to digits only when the syllable end is unambiguous; otherwise it retains the mark rather than guessing. It is not the permissive incremental-runtime parser. **Parent integrated evidence is recorded above; no separate Intent parser is warranted.**
- **Proposed String result:** saved/already-present + collection ID + dictionary-enabled state + index-publication success/pending, without echoing personal entry text. Do not say “ready in keyboard” merely because JSON saved: pack/mode/collection availability and physical sharing are separate. Reject unknown publication outcome; expose recovery rather than a second append. M, pending L1 and Intent-specific index/relaunch/concurrency checks beyond the parent’s integrated results. Changing entries can invalidate import Undo; disclose this before authorization. Rebuilding an already-present entry's index, if offered, is explicit recovery, not another add.

#### 16 Review a dictionary import

- **Chain:** `WordsImportView.fileImporter` → `MyWordsModel.review` (only.tsv/.txt, scoped URL access lifetime) → `store.preview(fileURL:modeID:)` / `CustomInputDictionaryParser.preview` → counts/problems/exact preview → explicit Apply → `MyWordsModel.apply` → `store.apply(preview,name:enabled:)`, revalidation and base-revision check. Invalid rows block all Apply; Cancel writes nothing. New collection does not replace existing words. UI starts imported collection Off unless deliberately enabled; core `apply` defaults true, so a future adapter **must explicitly pass false unless reviewed consent says otherwise**.
- **Proposal:** selected file + explicit supported mode + optional display name → bring app to **existing review**, not import-success. File-input API/access-lifetime and new cold/warm navigation are unverified (L2/G3); retain a private bounded copy if handoff outlives scoped access (new design), never an arbitrary URL/network download. Keep1MiB/10,000-line/50,000-total/1,024-collection limits, capped line errors and duplicate/combined counts. Fresh review is required after revision conflict. Exact output remains untouched. Repeated Apply of equivalent bytes creates another independent UUID collection today; do not label it idempotent. Any replay token/dedup policy would be **new business work**, not a parser feature.
- **Verdict:** foreground review worth investigating, unattended Apply not recommended. M–L; validate file replacement/revoked scope/relaunch/no-write Cancel/duplicate inputs and committed-but-index-pending outcomes after product approval. No API/schema claim makes current review navigation exist.

#### 17 Obtain a language download; 18 set availability; 19 remove download

- **Common chain:** `LanguagesView.swift`, `LanguageModeDetailView` → `LanguageManagementModel` → private actor `LanguageManagementWorker`; `LanguagePackCatalog` loads **bundled pinned** descriptors/notices. `LanguagePackDownloader.download` uses ephemeral non-background sessions, HTTPS allowlisted hosts/redirects, no cookies/credential store/custom auth headers, streaming size/hash verification and cancellation. Japanese requests `codeload.github.com`; Mandarin fetches only jichu+zi from `raw.githubusercontent.com` (**49,085,918 network bytes**) and verifies three bundled OpenCC mappings before app-side compilation. Remote hosts necessarily observe the resource request/IP; no typed/custom text is part of that request. TLS trust is not app login or user consent. Arbitrary user URL/manifest/header/engine-code parameters are excluded.
- **17 proposal:** fixed Japanese/Mandarin choice resolving current audited catalog pin → verified installed identity/version and **actual unchanged enabled state**. `downloadJapanese` / `downloadMandarin` stage and call `LanguagePackStore.install(expectedRevision:)`; archive extraction is bounded, activation swaps the pointer only after checks. No auto-enable/select; `activating` means resource publication, not active keyboard selection. Current UI Task-starting methods return no awaitable durable result and have silent guard exits: propose a reusable throwing/awaitable app service plus busy/conflict/cancel result, not polling a view or returning “installed” when Task was merely started. Repeated downloads can create fresh revisions; an “already current” no-op requires a **new full pinned-identity/verified-payload guard**. Mandarin's measured size is now wired in production: `LanguageManagementModel.init` defaults to `LanguagePackCatalog.measuredMandarinDatabaseBytes` (**155,074,560 bytes**), guarded by the exact compiler/corpus/mapping pins; `LanguageInputEnvironment` uses that default. `configureMandarinDatabaseBytes` is not a missing required caller. Installation checks actual size; this disk measurement is not keyboard memory usage. Parent verified both real resource installs on Simulator without auto-enable. No general background transfer/resumption exists (`configuration.identifier` is rejected). L: foreground detail/progress first; long-running App Intent APIs are unverified optional leads, not an iOS17-ready solution. Show sizes/licenses/hosts, obtain download consent, check staging/compilation capacity without deleting other packs, preserve old data on pre-publication failure, and test interruption/lifecycle/races.
- **18 implemented:** Use in Keyboard → `setEnabled(_:for:)` → worker.save reloads fresh settings, resolves installed ABI-validated pack when enabling, pins its ID/version/archive hash and saves. It is **set-to-value**, not toggle; Direct cannot be disabled and Korean is rejected at model layer. Proposed input mode + desired enabled value → saved preference + verified resource availability, never “keyboard switched.” Do not bypass these guards by calling lower-level `LanguageInputSettings.Value.setEnabled`, which alone does not check installed packs or Korean readiness. Selection in app is session-only, independent of keyboard. Same-value UI calls may still save/pin; a true no-write no-op would need a new comparison. Keep setup in app initially; would also need serialized configuration-generation/concurrent-write policy and L1/G5 checks.
- **19 implemented:** app destructive confirmation → `LanguageManagementModel.remove` saves disabled preference first, then worker.remove → `LanguagePackStore.remove(expectedRevision:)` deactivates pointer and reclaims only unleased revisions. Custom words are kept; leased data may remain until readers release, so **no immediate bytes-freed guarantee**. A failure can leave preference Off; deactivation may precede cleanup failure. Proposal if demand arises: exact mode + reviewed installed revision → disabled/deactivated/cleanup-pending result, explicit confirmation, recheck revision after confirmation, absent target no-op guard. Restoring removed resources requires re-download; no pack-removal Undo exists. Keep in app initially; don't convert a generic store mode string into arbitrary deletion authority.

#### 20 Undo last My Words import

`MyWordsView` confirmation → `recoverLastImportUndo` / `undoImport` → `CustomInputDictionaryStore.undoLastImport(expectedRevision:)` removes **only the collection recorded by its persisted one-step marker**, then rebuilds/publishes index. Marker survives restart; any later modifying revision conflicts, including enable/rename/add/import. Second Undo fails/no eligible import; it must never undo a newer import after an automatic retry. UI `canUndoImport` is session-derived; the persisted target is not exposed in snapshot.

If later selected, propose **foreground review of an exact import token/collection UUID and revision**, explicit confirmation, then return removed collection ID + publication state. This requires a **new read-only eligibility/target API and expected-target guard** in addition to existing revision checks; a bare no-parameter background Undo is not safe. Do not infer target from collection order/name or confuse it with configuration Undo12. Recovery is important but in-app UX already serves it: no unattended recommendation, M pending L1/L2 and stale/relaunch/cancel/index-failure tests.

### API evidence reuse, surfaces and next verification

No fresh Apple web/SDK-symbol verification was performed; no network outage is alleged. Reused **2026-10-24 Apple DocC + third-party mirrored iOS17 interface evidence A1–A14**, with exact source URLs/declarations, symbol-specific availability and original freshness limits retained above. Reading the skills is guidance, not current selected-SDK declaration evidence. The beta27.1 environment record proves a compiler environment, **not** that each proposed API/schema/member was read or compiled there. Ordinary first batch uses those recorded String/enum/single-IntentFile paths below iOS17; no target bump, Intents extension or permission/configuration change is proposed.

| Gap | Exact evidence still needed / effect on verdict |
| --- | --- |
| L1 personal data and lookup | Exact `AppIntent.authenticationPolicy` and chosen `IntentAuthenticationPolicy` member, confirmation overload if selected, `AppEntity`/`EntityQuery` requirements if a picker is chosen, and numeric parameter overload if used. Symbol-specific min OS/selected SDK declarations **not verified here**; no availability assigned from guide memory. Product must choose authentication versus confirmation versus export consent separately; exercise queries and perform while locked/unlocked. Keeps14/15 and any future mutation out of ready scope. |
| L2 file/foreground/result | Exact IntentFile **input/access** and multipart `[IntentFile]` result conformance/overload; A13 covers single output only. Foreground execution/routing for iOS17 and newer (G3), scoped file lifetime, import-review delivery and target-specific Undo confirmation. Verify declarations before recommending those concrete paths as ready. |
| L3 resource lifecycle | No verified `LongRunningIntent` / `performBackgroundTask` / cancellation-member path for17. Guide-only leads are not SDK evidence or a reason to raise iOS17. Verify exact newer symbols/SDK/runtime conditions only if needed; ordinary app progress remains fallback. Production Mandarin size wiring is resolved; awaitable business-service results remain unresolved. |
| G1–G5 retained | Parent integrated build/canonical-reading evidence is recorded above; final build installation remains pending. Intent metadata extraction and cold/protected storage; exact AppShortcut initializer **and phrase token**, Spotlight indexing/exposure and foreground strategy; exact schema fit if ever selected remain distinct checks. |

**Surfaces:** proposed ordinary first batch is user-composed **Shortcuts** only. The new14–17 pending paths would start there if selected after gates; no ready tiles/provider. **Siri** phrases and confirmations need separate G2/API/device work; do not speak personal My Words data by default. **Spotlight** has no index here; do not index personal dictionaries or export content. **Apple Intelligence/schema enhancement** remains undetermined, outside every ready path: no exact matching domain/member/required entities/facet verified; do not force custom lexicons into notes/files or describe language conversion as model integration. No OS/hardware/language/region coverage promise is made for optional AI surfaces. Source declaration, metadata/visibility, direct logic tests and execution from Shortcuts/Siri/Spotlight on a signed device are separate evidence levels.

### Planned/excluded features and product handoff

| Feature | Current state / decision |
| --- | --- |
| Korean — Romanized | **Planned / pending user's spelling-scheme decision** (strict syllable-separated versus continuous); UI/model/rules explicitly unavailable. No Korean parser/resource/Intent/typing-guide promise; shared enum presence is not implementation. Traditional Mandarin likewise unavailable; conservative Simplified subset is not full OpenCC t2s. |
| Active host mode switch, candidate commit/cancel, correction undo, selection/field reads | Live keyboard-only interactions, not independent system tasks. **No keylogging, learned typing history, external-host text extraction/insertion or automatic capture into My Words is proposed.**15 accepts only explicit Shortcut parameters. |
| English Suggestions / Autocorrection; collection enable/rename/delete | Independent opt-in options and dictionary management exist; not separate first-wave actions merely because toggles/buttons exist. Direct Typing remains fallback and autocorrection starts Off. Destructive edits remain in reviewable UI. |
| Open Languages/My Words or show download status | Valuable destinations already exist, but no new route/Intent exists. They may support16/17 handoff later; don't inflate the batch with generic navigation/status-only tiles. |

**Handoff:** keep **8 Inspect Unicode Text / 9 Export Uniboard Configuration (privacy decision) / 2 Get Exact Unicode Text** as the first batch;13 Validate Configuration stays next wave. For language work, investigate **14 Export My Words, then15 Add Entry, then16 reviewed import**, with17 download below those due lifecycle/readiness cost.18/19 and unattended20 are not initial recommendations. Resolve personal-data/auth policy, exact symbol gaps, multipart/no-truncation output, saved-versus-index-published semantics and Intent-specific cold-launch/device checks before promoting any of them. Parent integrated parser/build/Simulator evidence above does not close those API and system-entry gaps. This reassessment appended only `intent-opportunities.md`; no implementation, command execution, build/test, simulator/business operation, git/config/code change or release action was performed. Parent work/tests remain separate and are not represented as verified integrated Intent behavior.
