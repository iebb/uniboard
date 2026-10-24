# UI test runs

UI tests are grouped by feature area: one XCTestCase class per area, all
subclasses of `UniboardUITestCase` (shared setUp and helpers in
`UITests/UniboardUITests.swift`). Keyboard tests skip unless
`UNIBOARD_KEYBOARD_INTEGRATION=1` is passed, so every command below passes it.
`P` is the project id, `ccadf99c-a2ff-4476-93be-fbe43192a9e7`.

## 1. Default: smoke (about 10 min with the build)

The app launches and browses, search works, Settings opens; the keyboard
switches in, types English, inserts a search result and a page key.

```
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/SmokeUITests -only-testing:UniboardUITests/AppBrowsingUITests/testBrowseUnicodeBlockAndOpenCharacter -only-testing:UniboardUITests/AppBrowsingUITests/testSearchByCharacterNameAndLiteral -only-testing:UniboardUITests/FontSettingsUITests/testOptionalFontDownloadCatalogIsOnlyInAppSettings'
```

## 2. Per change: the area classes

Run the area for what changed (and the smoke if the change is wide).

| Changed source | Area: classes | Est. min |
|---|---|---|
| App: ContentView, BlocksView, CodeChart, EmojisView, CharacterDetailView, AppSearchField, NewInEditionView; Shared: UnicodeCatalog, EmojiCatalog, CharacterStore, UnicodeEditionSettings | Browsing: AppBrowsingUITests | 10 |
| App: FontPackDownloadsView, VerifiedFontPreview, CharacterFontsView, Font*, GoogleFont*, StyleGridView; Shared: UnicodeFont*, Font*, CustomFontStore, StyleGrid, UCSUR | Fonts: FontSettingsUITests, FontRulesUITests, FontExplorationUITests, StyleGridUITests | 25 |
| App: KeyboardLayoutsView, KeyboardKeySettingsView, KeyboardKeyPreferences, MainKeyboardEditorView, KeyLayersPanel; Shared: KeyboardAlphabet, KeyboardKeySettings, MainKeyboardArrangement, KeyboardTypingLayoutPolicy, KeyboardFooterLayoutPolicy, KeyboardVariant*, KeyboardTouch* | Layouts: KeyboardLayoutUITests | 30 |
| App: PagesView, PageArrangeView, SavedView; Keyboard: SymbolBoardPanel; Shared: SymbolBoardStore, SymbolPage*, KeyboardSymbolPagesPager, FavoriteSync, EditorReorder | Pages: PagesUITests | 25 |
| Shared: KeyboardEnglishInputPolicy, KeyboardTypingPolicy, AutoCapitalizationSetting, KeyboardHostInputTraits, KeyboardInteractionPolicy, KeyboardSelfSizingInputView | Typing: KeyboardTypingUITests | 25 |
| Keyboard: KeyboardQueryField; Shared: KeyboardQuery*, KeyboardRepeatingDeleteControl, UnicodeSearchIndex*, CatalogWorker | Search: KeyboardSearchUITests | 22 |
| Shared: TextInspection, KeyboardInspectableInteraction | Inspect: KeyboardInspectUITests, TextPreviewUITests | 30 |
| Shared: KeyboardPreviewCursor*, KeyboardPreviewImageExport, ImageColorSettings | Preview: TextPreviewUITests | 22 |
| App: ConfigurationFile, ConfigurationImportModel, ConfigurationView, ReviewImportView; Shared: Configuration*, TOMLDocument | Configuration: ConfigurationUITests | 8 |
| Keyboard: KeyboardViewController; App: UniboardApp, SetupView, CatalogPreferences; Shared: SharedConfigurationLocation, CompanionAppRoute | smoke, then the area of the feature touched | |

Times are estimates for the test run alone; add about 8 min of build.

```
# Browsing
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/AppBrowsingUITests'
# Fonts
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/FontSettingsUITests -only-testing:UniboardUITests/FontRulesUITests -only-testing:UniboardUITests/FontExplorationUITests -only-testing:UniboardUITests/StyleGridUITests'
# Layouts
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/KeyboardLayoutUITests'
# Pages
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/PagesUITests'
# Typing
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/KeyboardTypingUITests'
# Search
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/KeyboardSearchUITests'
# Inspect
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/KeyboardInspectUITests -only-testing:UniboardUITests/TextPreviewUITests'
# Preview
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/TextPreviewUITests'
# Configuration
runtest P --script app --additional-options 'UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/ConfigurationUITests'
```

## 3. Full run: GitHub only

The full suite runs only on GitHub: Actions › **UI full** (manual,
`.github/workflows/ui-full.yml`). It runs the area groups as parallel jobs,
each under an hour, and uploads each `.xcresult`. There is no full run on
AirBuild.

`KeyboardSearchBenchmarkUITests` (search timings) is in no run; select it by
name when you want numbers.
