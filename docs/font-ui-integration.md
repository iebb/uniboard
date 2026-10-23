# Font exploration UI integration

## Owned new files
- `App/CharacterFontsView.swift` — local scan model, grid, shared exact preview disclaimer/source labels and refresh notification.
- `App/GoogleFontsView.swift` — asynchronous bundled metadata load, local family search and shared live download coordinator.
- `App/FontFaceDetailView.swift` — local/Google detail, selected style/file actions, verified specimens, license text and removal confirmation.
- `Tests/FontExplorationViewModelTests.swift` — Apple-platform unit tests; no screenshot fixtures or rendering-success claims.

Add all three UI Swift files to the containing app target only. Add the tests to the app unit-test target. They require the catalog, coordinator, library contracts/store, comparison engine and VerifiedFontPreview implementations. Do not add these screens to the keyboard extension.

## Existing navigation insertions (parent-owned)

Inside the existing Character detail NavigationStack, after its actions and before notes/properties:

```swift
NavigationLink {
    CharacterFontsView(text: exactSelectedText, characterName: character.name)
} label: {
    VStack(alignment: .leading, spacing: 4) {
        Text("View Fonts")
        Text("Compare fonts available to Uniboard.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
```

`exactSelectedText` is the existing detail's actual selected sequence, including its existing Text/Emoji variation selector, not a display placeholder/dotted-circle scaffold. No normalization or global font-selection write occurs. Initial presentation is Original. The Text/Emoji chooser appears only when `inspection.canChoosePresentation` is true (one emoji-capable scalar, optionally followed by VS15/16). Explicit presentation replaces/adds that final selector in the preview only; Original restores the exact input and the original sequence remains unchanged. Complex sequences never receive selector surgery.

At the beginning of existing FontPackDownloadsView (retain every pack/import/install/management row):

```swift
NavigationLink("Browse Google Fonts") {
    GoogleFontsView()
}
```

Both destinations use the caller's navigation stack. Grid also offers `GoogleFontsView(text: inspection.previewText)`; this text stays local and is not included in a catalog search or network request.

## Live ownership and refresh

Each grid owns a real `FontComparisonEngine`, not the shared singleton (a detail scan must not supersede a grid scan). `.task(id:)` cancellation stops the consuming scan on departure/refresh. Grid refreshes on foreground, public Core Text registered-font notification, UserDefaults changes and `.fontExplorationLibraryChanged`. Returning to the screen starts its task again. Query remains in the screen-owned model. Library changes can also be announced by existing app operations with:

```swift
NotificationCenter.default.post(name: .fontExplorationLibraryChanged, object: nil)
```

The Google browser constructs `GoogleFontDownloadCoordinator(catalog: loaded.snapshot)` once after offline `GoogleFontCatalog.load()`. Detail observes its FILE-keyed published states and invokes the real async throwing `download(styleID:)`, `cancel(fileID:)`, `remove(fileID:)`. No download occurs on browsing/search/preview/selection. Download Tasks intentionally survive navigation; the coordinator continues publishing and cancellation is explicit.

Google persisted face IDs are `google:{fileID}:{styleID}`; `assetID` is a stored binary filename, NOT fileID. Inventory aliases may deduplicate to a different representative. Downloaded specimens match `PublicFontInventory.identity` for the requested file SHA-256/index zero/canonical axes, not the representative navigation ID. Local management resolves candidate files against one cached throwing library read (receipt hash and asset-path mapping), then exact physical identity. Exact persisted style ID wins; otherwise matching family/style wins, then stable family/style ID order. The selected catalog style never changes when its preview uses an equivalent representative. Shared variable-file styles expose their shared download/removal scope. Default selection is Regular when present, otherwise first catalog style. Selection never changes global preferences.

Actual font preview is exclusively `VerifiedFontPreview`, which re-verifies and renders the same CTLine. Unknown is shown separately from unsupported. Complete counts count verified faces, regardless of name filtering; partial counts remain checked/total. Invisible controls receive an explicit not-applicable explanation rather than placeholder coverage. Complex shaping remains conservatively unknown per engine contract.

## Management and limits

One selected file per action; unknown/known progress, queued/cancelled/preparing/downloaded, typed failure copy and retry are distinct. The 16-entry and 40 MiB limits are visible with instructions to remove downloads/manage Your Fonts. Unavailable files remain in style choices with their reason but cannot download. Removal is confirmed and only exposed for coordinator-managed downloaded files; System/Included have no delete action. Local Google faces link to Manage Download with exact style retained. Curated pack removal remains in existing Font Downloads. Full retained receipt license text takes priority over bundled catalog license text, both selectable offline.

The UI says Available in the app only. It makes no keyboard-registration claim. All five tabs, existing global preferences, packs, favorites and layouts are untouched by these files.

## Verification status and remaining checks

No remote build/test or simulator invocation was performed by the UI agent (parent owns those runs). Unit tests exercise scan partial/final/error counts, query filtering, stable style/file identity, limit copy, exact sequences, and a live bundled-catalog model load. Test streams are confined to tests. Parent must add target membership and run native compilation/tests; Linux cannot validate SwiftUI/CoreText here.

Still require device/simulator verification: actual all-inventory scan cancellation/responsiveness, normal/AX column layout, long names/light/dark/VoiceOver, download/progress/cancel/retry/removal round trips, offline receipt display and app/keyboard registration separately. No screenshots/mockups count as test evidence. Existing catalog-license navigation uses a selectable native pushed license page rather than a sheet. Local imported/pack files continue to be removed through existing Font Downloads rather than adding a second removal API.

## Storage audit and UI automation follow-up

Removed every `receipt(fileID:)` read from SwiftUI body evaluation. `FontReceiptViewModel` now uses the throwing `readLibraryState()` once off-main per requested receipt; views render cached receipt values. It preserves a read error separately from missing receipt. Google browser/detail explicitly observe `coordinator.libraryFailure`, so corrupt/unreadable storage is not presented as an empty download library. Coordinator initialization was separately fixed by the storage owner to decode once.

Added `UITests/FontExplorationUITests.swift` (parent adds UI-test target membership). Real UI tests cover local Roboto catalog search and character-grid inspection; a live selected-file download/verified comparison/removal flow is gated by `UNIBOARD_GOOGLE_FONT_DOWNLOAD_INTEGRATION=1`. It retains a preexisting download and removes only the test's newly acquired file on successful completion. A failed test can leave that file downloaded; use Font Downloads to remove it. No test was executed here, and accessibility existence alone does not certify actual glyph rendering. New accessibility identifiers are on real family/style/grid/download/preview controls, not fixture paths.

### Physical alias regression coverage
`FontDetailIdentity` tests cover OpenType wght versus its decimal Core Text axis ID, physically equivalent style aliases, stable alias resolution, preservation of exact persisted style, rejection of different coordinates and absent receipts. Local management resolves/caches selection when the screen loads, not during body rendering. The live UI test no longer assumes the representative's ID begins with google. No native tests executed by UI agent.

### Native navigation/search diagnosis (23 October)
Targeted run `08b2749c-43a0-4d0a-8fd2-e073aa684f43` compiled both screens. Catalog test passed; local-inspection return assertion failed. Exported actual accessibility attachment `93499033-A75B-4BB7-B61B-DE0888B53B02.txt` proves Back DID return to the correct Fonts for This Character sheet: its bar contained Search available fonts = Helvetica and a Close button. Active native search hid the ordinary Back/Done toolbar; the underlying Explore navigation bar was still exposed, explaining why global firstMatch tapped Jump to block in earlier runs. This was not an actual pop to Explore.

Both font search fields now explicitly request an always-visible navigation-bar drawer, rather than automatic placement, and `.searchPresentationToolbarBehavior(.avoidHidingContent)` retains navigation controls while search is active. The grid inspection route is now screen-owned item navigation outside the lazy grid, so scan refresh/removal of a cell cannot own the inspector lifetime. The UI test scopes real Back controls, requires the original Character copy action to be hittable/enabled, confirms U+0041, executes it and waits for Copied. Catalog UI test now explicitly requires the field hittable before any pull-down/search gesture. Follow-up targeted verification is reported in agent handoff; no keyboard or live-network tests were invoked here.

Follow-up native run `7f3a5a42-c0d7-4774-915e-4f24453bdd82` PASSED both targeted UI tests (2 executed, 0 failures): Character font inspection → Back → Character → actual Copy Character/Copied; Settings → Font Downloads → Google Fonts search visible/hittable without pull-down → Roboto local family detail. Command: `runtest ccadf99c-a2ff-4476-93be-fbe43192a9e7 --script app --additional-options '-only-testing:UniboardUITests/FontExplorationUITests/testCharacterFontsInspectWithoutChangingCopyAction -only-testing:UniboardUITests/FontExplorationUITests/testGoogleCatalogSearchIsLocalAndOpensExactFamily'`. Artifact `/tmp/airbuild-result-7f3a5a42-56f5bb/command-output.tar.gz`. The toolbar-preservation modifier is availability-gated to iOS 17.1+; iOS 17.0 retains the standard Close-search affordance. No live font download or keyboard tests were included in this run. Shared Team simulator was not touched.
