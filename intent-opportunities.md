# Uniboard — App Intents opportunities

## Existing App Intents inventory

**Uniboard declares 0 App Intents actions.** No Shortcuts, App Shortcuts, Spotlight, Siri, widget or control entry points are declared, and nothing adopts an Apple Intelligence schema.

| Business action | Intent / shortcut / entity / query evidence | Wiring today | Evidence limits |
| --- | --- | --- | --- |
| None declared | I searched all 103 Swift files in `App/`, `Shared/` and `Keyboard/`, plus `Tests/`, `UITests/`, `Uniboard.xcodeproj/`, `project.yml` and `Package.swift`. Patterns: `AppIntent`, `AppShortcut`, `AppShortcutsProvider`, `AppEntity`, `EntityQuery`, `AppEnum`, `IntentParameter`, `@AssistantIntent`/`@AssistantEntity`, `@AppIntent(`/`@AppEntity(`, `INIntent`, `import Intents`, `intentdefinition`, `WidgetKit`, `ControlWidget`. No matches. `App/Info.plist`, `Keyboard/Info.plist` and `project.yml` have no `NSUserActivityTypes` or document types. The app also has no `CoreSpotlight` or `NSUserActivity` code. | Ordinary app UI and the keyboard extension only. The only external route is `uniboard://settings`: `Shared/CompanionAppRoute.swift`, `isSettings(_:)`, handled by `ContentView.onOpenURL`. In DEBUG, `onOpenURL` also accepts test fixture URLs. | This is a static source inventory, not a check of what the installed system shows. The project has no widget or control target. |

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
- **Not recommended:** 12. Import/replace configuration and Undo Last Import, plus everything in the exclusion table.
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
  - `encode` produces deterministic UTF-8 TOML. It returns nil (never truncated) above `TOMLLimits.maximumBytes` (4,000,000).
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
- **Open a font detail:** `App/FontFaceDetailView.swift`. Version 1.3 adds `StyleGridView`: a weight × italic grid with a Width/Variant menu, built in `Shared/StyleGrid.swift`.
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

### 12. Import / replace configuration · Undo Last Import — not recommended (new)

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
