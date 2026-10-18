# Uniboard

A native, offline English keyboard with full Unicode search and browsing for iPhone and iPad. The containing app is `ad.neko.uniboard`; the system keyboard extension is `ad.neko.uniboard.keyboard`. Requires iOS 17 or later.

Search by character name, descriptive annotation, alias, block name, hexadecimal code point (`U+1F680`, `0x1F680`, `1F680`), explicit decimal code point (`decimal:128640`), or a literal character in the app. Browse every block or all assigned characters in ascending code point order by default. The order menu also offers newest and oldest first by official Unicode Age; saved sort choices remain intact. Complete-word matches precede mid-word matches, with the selected order applied within each tier. Bare hexadecimal searches need a numeric digit; use `U+FACE` for a letters-only code point so the word “face” can find names.

Choose the Unicode edition **only in the app’s Settings tab**: **Unicode 18.0.0**, the latest release and default; previous releases **17.0.0** and **16.0.0**; or **Unicode 19.0.0 DRAFT**, available by explicit choice. All four character/property and fully qualified emoji catalogs are bundled offline. Edition, optional preview fonts and the optional collapse key are set only in app Settings; reopen the keyboard to read them. Full Access remains off. Sort order and saved collections remain separate in the app and keyboard.

The **Emojis** tab searches and browses complete official fully qualified entries, including ZWJ sequences, variation selectors, flags, keycaps and skin tones. Copying or keyboard insertion preserves the entire sequence. Emoji version ordering uses Emoji introduction version; component Unicode ages are shown separately. Favorite and recent emoji are stored alongside scalar collections, locally and separately in the app and keyboard.

Hold a Unicode browse character or emoji key, or keep a pointer over it, to open a scrollable properties panel without inserting text. Read the official name, descriptions, typed aliases, NamesList section and notes, related characters, historical Unicode 1.0 name, numeric value/type and simple case mappings when present, alongside Unicode age, block, category, script, bidirectional class, combining class, decomposition and encoding bytes. Formal name corrections remain distinct from informative aliases and annotations. Emoji details show each component's name and code point. Names and properties remain readable when an iOS font shows a missing glyph or renders a sequence as separate symbols. Tap, hold or hover a tile in the containing app to inspect it, then copy or add its original text to the scratchpad.

NamesList section titles and notes are searchable. For example, `suzhou numerals` finds the characters whose stable official names contain `HANGZHOU NUMERAL`; their details retain the Suzhou heading and Unicode's explanation of the misnomer. Additional Suzhou numerals are included as well. Official Unicode names are never silently renamed.

The keyboard starts with literal English QWERTY typing into the receiving app, without autocorrect or word suggestions. Shift capitalizes one letter; double-tapping locks capitals, and another tap unlocks them. Number and symbol pages provide everyday punctuation. English keycaps keep a fixed height as the keyboard grows. On iPhone, a number row appears when four key rows fit; glyph-only saved-symbol rows can appear above it when five fit, with horizontal scrolling for overflow. Automatic capitalization follows the receiving field, and two deliberate Space taps after a word can insert a period and space. URL/email fields keep literal input. The star immediately left of the smaller Space key opens Favorites by default; its back arrow returns to QWERTY. A stock Symbols board is included. Long-press the star/back control to switch or manage boards and choose a preferred Star target. Temporary board selection does not change that preference; deleting its custom board falls back to Favorites. Saving a browse character or emoji asks which board to use; existing favorites are migrated without discarding their original data. Hold an English letter for accented variants, or a symbol-board key for variants, Inspect and Edit. App Settings → Customize keyboard keys configures letter, number and symbol keys’ long-press, swipe-up and swipe-down choices. Space, Shift, Backspace, Return and other function keys keep their standard behavior. Earlier beta function-key overrides are ignored without losing character-key settings. Up on a letter selects the opposite case and its accented choices by default without changing Shift; slide horizontally before lifting to choose. Each gesture supports default, disabled or an ordered set of up to 16 literal choices. Custom choices retain exact case, combining sequences and whole emoji. The iOS globe and query keys retain their normal behavior. The variant editor can select complete text from Unicode search without typing it into the receiving document. Backspace is available beside the typing/query keys and at the top right for browsing. On wide iPad QWERTY layouts, Tab and Delete flank the first letter row, Caps Lock and Return flank the second, and both Shift keys flank a third row with comma and period. Narrow or floating layouts retain the compact arrangement. Return appears once; its footer space is given to Space on the wide layout. The native globe and return action remain available.

The bottom-left U key shows or hides the Unicode toolbar, which starts hidden. Hiding it returns literal typing to the host while retaining the local query and caret. Tap Unicode in that toolbar to browse Symbols, Emojis, Blocks or Saved; The … menu contains only character order and Open companion app. Edition and font selection live in the app’s Settings tab. Tapping a tile inserts its original scalar or complete emoji at the host app’s cursor. Glyph tiles show the character and code point; full names, ages and properties remain available by holding a key. Focusing Unicode search opens its local query keys. These keys, space and backspace edit only the query, with literal spaces; Done returns English typing while preserving the Unicode query and results. Host typing never changes that query. Held delete stops when released, when resizing or search mode changes, or when the receiving document changes. No network or Full Access is required at runtime.

On iOS 26 and later, toolbar controls use native Liquid Glass above the system keyboard backdrop. Controls handle presses directly; the glass surface remains noninteractive to keep native menu rows tappable in the remote keyboard scene. Older iOS versions use semantic system surfaces, with an opaque fallback for Reduce Transparency. Phone portrait typing/browsing starts at 220 points; an explicitly saved height remains in use. The grip occupies 14 points without extra padding above it. Phone letter, number, symbol-board and footer keycaps use 36-point heights with 4-point row gaps, so the hidden-toolbar baseline fits three letter rows, one digit row and the footer without a blank spacer. The optional collapse key is hidden by default and can be enabled in app Settings. Swipe the top grip up to add one key row or down to remove one. Each accepted swipe applies a single row step on release, within the 220–420-point browsing range and available display limits. While swiping, the character area shows only an up/down direction arrow when that step can change the height; outward swipes at either limit show no arrow. There are no height numbers, gauge or preview. Swipe distance does not select an arbitrary height; taps and cancelled gestures leave the height unchanged. The browsing preference is saved locally and restored after search, inspection or rotation. Search keys expand to at least 340 points. Done returns to English typing while preserving the query and filtered results; tap Unicode to browse them, tap the search field to edit again, or Clear to return to the full catalog. The cursor follows the text and supports tap/drag positioning, insertion and whole-character backspace in the middle of a query. Phone landscape stays at 220 points. Wide iPad typing uses three 52-point character rows, 6-point gaps and a matching footer (238 points; 36 more with the toolbar). Narrow iPad typing uses 36-point keys (170 points); Unicode browsing/search retains 340/380 points. All heights are capped for the available scene. The same query, caret and scroll state remain intact when height changes. Search text uses a clipped native foreground on a quiet key surface outside the glass compositor, without a nested scroll view; adjacent toolbar controls retain Liquid Glass. When the normal keyboard already has a digit row, #+= opens a full symbol layout with no digits: the two ten-key rows contain complementary common symbols. At shorter heights, 123 retains its normal digit page. Saved and Recent keys match the digit keys’ widths, heights, rounded surfaces and spacing; inline overflow scrolls horizontally. Board configuration uses an opaque, bounded editor with scrolling so controls do not overlap the keyboard. These are extension-content heights; iOS controls its separate bottom globe/dictation area and the receiving app’s editor layout.

**Extra Unicode fonts** is optional and **off by default**. Enable it only in the app's Settings tab; the keyboard reads the same choice locally without Full Access. Bundled Noto Sans Symbols 2 and GNU Unifont improve some missing character previews while keeping supported system glyphs and emoji unchanged. They cannot change fonts in receiving apps or display every new Unicode 18/19 character. Full font licenses are available in Settings → Font licenses. See [font sources, verified coverage and update policy](docs/font-pack.md).

Wide iPad QWERTY defaults to three letter rows without extra digit or favorite strips. Tab, Caps Lock, both Shift keys and Delete use tinted gray keycaps; Return uses system blue. Each letter shows its default down-flick digit or symbol above the primary glyph, while up-flick still chooses the opposite case. Custom down choices replace the hint; Off removes it. Narrow panes retain the compact layout.

## Run locally

Build with Xcode 26 or later for the Liquid Glass APIs; the deployment target remains iOS 17. The monthly GitHub workflow explicitly selects Xcode 26.3 on its macOS 15 runner.

Open `Uniboard.xcodeproj` and run the **Uniboard** scheme. Both targets use automatic signing with the Kitta Ltd team. For a different account, select the same team for the application and keyboard extension. The committed Xcode project can build without XcodeGen. After changes to `project.yml`, run `xcodegen generate`.

Both bundle IDs are registered to Kitta Ltd, team **7P8CLHDH5G**. A Release device archive has been built and its app and embedded keyboard signatures independently verified against that team. To create a signed local archive with the configured Xcode account:

```sh
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/QA/Uniboard-Kitta.xcarchive \
  -allowProvisioningUpdates archive
```

Enable the system keyboard in **Settings → General → Keyboard → Keyboards → Add New Keyboard → Uniboard**. In the app’s Settings tab, open **Try your keyboard**, tap the editor, hold the globe key, and select Uniboard. iOS uses the system keyboard in secure and phone-number fields; host apps may disallow custom keyboards.

```sh
swift test
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

Quality checks run the core and native iOS unit suites on every push and pull request to `master`, enforce per-file coverage floors, and preserve result bundles. See the [boundary matrix and validation commands](docs/quality.md). Searches accept at most 4 KiB of UTF-8 input; repeated name-search terms are deduplicated without changing their AND semantics.

The ordinary UI tests cover name, code point, literal-character and block searches, block browsing, favorites, edition persistence, numeric age ordering, complete emoji details and unsupported-glyph properties. The system-keyboard integration test is opt-in because it changes the simulator’s enabled keyboards. Use a dedicated QA simulator with its software keyboard visible. In Xcode 27’s Device Hub, **Controls → Toggle Software Keyboard** shows or hides the software keyboard; disable **Device → Simulate Hardware Keyboard** when necessary.

```sh
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  UNIBOARD_KEYBOARD_INTEGRATION=1 \
  -only-testing:UniboardUITests/UniboardUITests/testSystemKeyboardSearchAndInsertion test
```

This test enables Uniboard through Settings and selects the installed extension from the system globe menu. It verifies that searching `U+1F680` keeps the query out of the host document, inserts 🚀, and handles space and deletion. It saves screenshots in the test results around search and after character insertion. This complete flow passed on an iPhone 16 Pro simulator running iOS 18.5.

## Offline Unicode editions

The generator refreshes the latest official final release, the two preceding major final releases and the latest official development draft, including each edition’s fully qualified emoji set and Unicode properties. Provenance is recorded in `Shared/Resources/UnicodeSources-latest.json`, `UnicodeSources-previous.json`, `UnicodeSources-older.json` and `UnicodeSources.json`. Final editions use immutable official release directories; all draft sources share one pinned official repository commit. Each source has a recorded SHA-256. All four complete editions are fetched and validated before one atomic artifact replacement. Transient download failures, including truncated responses, retry up to three times with bounded delays. An exhausted or invalid draft fetch fails without replacing the existing catalog with a stable release. Both CI paths run the download recovery regression tests before refreshing. Only the selected edition’s catalog is loaded on demand. Settings labels and historical preference resolution read bounded small provenance manifests instead of loading all four character catalogs. Each character catalog uses a memory-mapped binary rather than materializing hundreds of thousands of Swift objects in the keyboard process. Algorithmic names cover Hangul and ideographic ranges.

```sh
python3 Scripts/generate_unicode.py --source all --refresh
swift test
```

The current bundled snapshots contain:

| Edition | Assigned scalars including private use | Fully qualified emoji |
| --- | ---: | ---: |
| Unicode 16.0.0 | 292,531 | 3,781 |
| Unicode 17.0.0 | 297,334 | 3,944 |
| Unicode 18.0.0 | 310,341 | 3,963 |
| Unicode 19.0.0 draft | 310,341 | 3,963 |

The current draft has the same assigned set size as 18; choosing it does not mean every entry is new. Historical selections store their actual version (for example `17.0.0`), while latest/draft follow their tracks. Monthly updates advance the two historical slots. A retired selection or unavailable/malformed shared setting falls back to the latest release. The app writes one bounded settings file for the edition and two Boolean appearance preferences, and a separate bounded file for explicitly configured key gestures, in its App Group. The keyboard opens both read-only. Document typing, searches, favorites and scratchpad never enter these settings files.

Draft assignments and names can change. A character’s ability to display depends on the fonts included in the user’s iOS version. Dotted circles and invisible-character markers are preview aids; only the original scalar or complete emoji sequence is copied or inserted. A missing glyph does not hide the official name, description or properties. Surrogates are not valid Unicode scalars and are not insertable. Unicode data is distributed under the bundled Unicode License v3.

## Monthly refresh and Xcode Cloud

`.github/workflows/unicode-monthly.yml` runs on the first of every month at **03:17 UTC / 12:17 Japan time**, and supports manual dispatch. It fetches the latest release, previous two final releases and draft data, runs catalog tests, builds the app and embedded keyboard for the iOS simulator, and commits validated data and provenance to `master`. The repository’s default branch must be `master`.

Each refresh records `refreshedAt` in the provenance manifest, creating a validated monthly commit even when upstream Unicode data is unchanged. This also triggers an Xcode Cloud workflow configured to build on pushes to `master`.

Xcode Cloud uses the committed **Uniboard.xcodeproj** and shared **Uniboard** scheme, with `master` as its source branch. Executable hooks in `ci_scripts` check prerequisites after cloning and regenerate all four offline editions and their emoji catalogs immediately before building. A failed download or catalog test fails the build. XcodeGen, Homebrew, and third-party package managers are not needed in Xcode Cloud.

The repository is connected to the active [**Uniboard iOS** Xcode Cloud workflow](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/001084ae-fa0b-491c-b14a-2f03ad794f84/workflows). It uses the latest release environment and archives iOS for **TestFlight and App Store** on pushes to `master`. Each monthly validated data commit therefore triggers a signed archive with fresh data for all four Unicode editions. The pre-build hook runs download recovery and catalog/emoji regression tests. Automatic Cloud build **1.0.0 (7)** refreshed the draft, recovered a real interrupted download, passed those checks, uploaded successfully and became **Ready to Test**.

The [App Store Connect record](https://appstoreconnect.apple.com/apps/6818750518/distribution/info) is registered under **Kitta Ltd** as **Uniboard: Unicode Keyboard**, Apple ID **6818750518**, bundle ID and SKU **ad.neko.uniboard**, with English (U.S.) as its primary language. The device display name remains Uniboard. Public review, external beta review and public App Store availability are separate Apple states; check App Store Connect for the current status.

The primary workflow starts automatically from `master` branch changes and has no manual start condition. Editing is restricted to admins and app managers, and builds use a clean environment. Its internal and external TestFlight post-actions deliver to **Internal Testers** and **External Testers**, respectively. The redundant setup workflow remains disabled and has no manual start condition.

Both tester groups are created, and Cloud build **1.0.0 (8)** was delivered to **Internal Testers**. Tester membership and public invitation links are managed in App Store Connect. The approved Kitta review contact and feedback email from Mithka are configured, along with Uniboard-specific keyboard review instructions. External distribution remains subject to Apple's beta review. `TestFlight/WhatToTest.en-US.txt` supplies tester instructions automatically with each Cloud upload.

Apple documentation: [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [first workflow setup](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/), [automatic tester notes](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app), [external beta review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## Branding and public release

The approved icon master and generation prompt are in `marketing/icon`; run `swift Scripts/generate_icon.swift` to produce the opaque 1024-pixel iOS asset. Real simulator screenshots, provenance and reproducible artwork exports are in `marketing/screenshots`. `upload-manifest.json` defines the English and Japanese iPhone/iPad screenshot order. Storefront copy lives in `fastlane/metadata/{en-US,ja}`; the Japanese listing explicitly discloses the English interface and catalog names. See `docs/aso-strategy.md` for metadata limits and search positioning.

The [public website](https://uniboard-dxm.pages.dev/) and [support page](https://uniboard-dxm.pages.dev/support/) are served from the curated `website` directory through Cloudflare Pages. The [privacy policy](https://docs.kitta.co/uniboard/) is published on Kitta's shared docs site. The [application source](https://github.com/iebb/uniboard) is public. The static site has no analytics scripts or external fonts and explains website hosting separately from the offline app. The support address is Kitta's existing customer-feedback address.

`Scripts/app_store_release.rb` prepares or submits only this app's exact verified Xcode Cloud archive. It is GET-only by default, with separate flags for factual readiness settings, listing preparation and review submission. See `Scripts/APP_STORE_RELEASE.md` for credentials, guards and usage. `AppStore/ReviewNotes.en-US.txt` supplies the reviewer's keyboard test instructions. App Privacy publication must be verified separately before submitting.

### Publish website updates

The website workflow validates changes on `master`; deployment uses the existing Cloudflare login locally so broad account credentials are not stored in GitHub. The Pages project is `uniboard` in Kitta Labs, with production branch `master`.

```sh
python3 Scripts/validate_website.py
CLOUDFLARE_ACCOUNT_ID=58c982b69079141dd49d99076dd845b1 \
  wrangler pages deploy website --project-name uniboard --branch master
```

Deploy only `website`, then verify the public pages and assets before updating App Store URLs.
