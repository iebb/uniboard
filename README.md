# Uniboard

A native, offline English keyboard with full Unicode search and browsing for iPhone and iPad. The containing app is `ad.neko.uniboard`; the system keyboard extension is `ad.neko.uniboard.keyboard`. Requires iOS 17 or later.

Search by character name, descriptive annotation, alias, block name, hexadecimal code point (`U+1F680`, `0x1F680`, `1F680`), explicit decimal code point (`decimal:128640`), or a literal character in the app. Browse every block or all assigned characters, always from the lowest code point. Explore shows 3, 8 or 16 characters per row; at 8 and 16 it is a code chart of every block, with each block’s name and hex column digits pinned while its rows scroll, hex row labels, and gaps for unassigned code points. Jump to Block opens any block by name or range, and the chart scrolls freely in both directions from there. The View menu can limit Explore to one plane. Supplementary Private Use Areas A and B (planes 15 and 16) are hidden unless Show Supplementary Private Use is on. What’s New lists the emoji and characters the selected edition adds over the previous one. Character names are shown exactly as Unicode publishes them. Each tile carries a corner ribbon colored by the Unicode or Emoji version that added it. Complete-word matches precede mid-word matches, each in code point order. Bare hexadecimal searches need a numeric digit; use `U+FACE` for a letters-only code point so the word “face” can find names.

Choose the Unicode edition **only in the app’s Settings tab**: **Unicode 18.0.0**, the latest release and default; previous releases **17.0.0** and **16.0.0**; or **Unicode 19.0.0 DRAFT**, available by explicit choice. All four character/property and fully qualified emoji catalogs are bundled offline. Edition, optional preview fonts and the optional collapse key are set only in app Settings; reopen the keyboard to read them. These settings work with Full Access off. Pages are set up in the app and reach the keyboard the same way; Recently Used stays local. The app's Favorites and the keyboard's Favorites page share explicit favorites on-device; keyboard-to-app writes require optional Full Access.

The **Emoji** tab searches and browses complete official fully qualified entries, including ZWJ sequences, variation selectors, flags, keycaps and skin tones. Copying or keyboard insertion preserves the entire sequence. Emoji version ordering uses Emoji introduction version; component Unicode ages are shown separately. Favorite scalar and emoji text shares the same exact Favorites collection; recents remain local to each sandbox.

Hold a Unicode browse character or emoji key, or keep a pointer over it, to open a scrollable properties panel without inserting text. Read the official name, descriptions, typed aliases, NamesList section and notes, related characters, historical Unicode 1.0 name, numeric value/type and simple case mappings when present, alongside Unicode age, block, category, script, bidirectional class, combining class, decomposition and encoding bytes. Formal name corrections remain distinct from informative aliases and annotations. Emoji details show each component's name and code point. Names and properties remain readable when an iOS font shows a missing glyph or renders a sequence as separate symbols. Tap, hold or hover a tile in the containing app to inspect it, then copy or add its original text to the scratchpad.

NamesList section titles and notes are searchable. For example, `suzhou numerals` finds the characters whose stable official names contain `HANGZHOU NUMERAL`; their details retain the Suzhou heading and Unicode's explanation of the misnomer. Additional Suzhou numerals are included as well. Official Unicode names are never silently renamed.

The keyboard starts with literal English QWERTY typing into the receiving app, without autocorrect or word suggestions. Shift capitalizes one letter; double-tapping locks capitals, and another tap unlocks them. Number and symbol pages provide everyday punctuation. A number row sits above the letters; App Settings can turn it off for a shorter keyboard, and the 123 page and Unicode search keep their digits. Digits, letters and footer share fixed keycaps, 15% taller than the earlier template. App Settings chooses one optional symbol bar or its search-bar replacement; there is no resizing gesture. Automatic capitalization follows the receiving field, and two deliberate Space taps after a word can insert a period and space. URL/email fields keep literal input. The star immediately left of the smaller Space key opens Favorites by default; its back arrow returns to QWERTY. A stock Symbols page is included. Swipe horizontally to move one page at a time through every symbol page and Recent, or use the scrolling page tabs. Pages are created, ordered and edited in the app's Pages tab, which also picks the page ★ opens; long-press the star/back control in the keyboard for a simple list of pages to open. Opening pages preserves the U/search-bar state. Opening another page does not change the ★ page; deleting that page in the app falls back to Favorites. Pages made inside earlier keyboards are not carried over. Save in the keyboard's details adds to Favorites, or removes from it. Hold an English letter for accented variants, or a symbol-page key for its variants and Inspect. App Settings → Customize Keys gives every letter, number and symbol key three layers: swipe up, swipe down and long press, each with its own ordered candidate list. A tap always types the key itself; tap remappings saved by earlier versions are ignored. Space, Shift, Backspace, Return and other function keys keep their standard behavior. Earlier beta function-key overrides are ignored without losing character-key settings. Letter keys show no symbol hints. By default Up offers the modifier forms of the same character (superscript, then subscript) and Down its styled forms: mathematical bold, italic, script, fraktur, double-struck, sans-serif and monospace, then circled, parenthesized, fullwidth and small-capital letters, or the matching digit forms. Letters follow the current case and Shift is unchanged; slide horizontally before lifting to choose. An open chooser keeps its group until you lift. Each layer’s editor is one ordered list that starts with the default choices: add up to 16 literal choices, remove or reorder them, remove all to turn the layer off, or reset to the defaults. Custom choices retain exact case, combining sequences and whole emoji. The iOS globe and query keys retain their normal behavior. The variant editor can select complete text from Unicode search without typing it into the receiving document. Backspace is available beside the typing/query keys and at the top right for browsing. On wide iPad QWERTY layouts, Tab and Delete flank the first letter row, Caps Lock and Return flank the second, and both Shift keys flank a third row with comma and period. Narrow or floating layouts retain the compact arrangement. Return appears once, inline on wide iPad. The native globe and return action remain available.

The bottom-left U key shows or hides the Unicode toolbar, which starts hidden. Hiding it returns literal typing to the host while retaining the local query and caret. Tap Unicode in that toolbar to browse Symbols, Emojis, Blocks or Pages. Results are always listed from the lowest code point. Edition and font selection live in the app’s Settings tab. Tapping a tile inserts its original scalar or complete emoji at the host app’s cursor. Glyph tiles show the character and code point; full names, ages and properties remain available by holding a key. Focusing Unicode search opens four rows of local query keys at the normal typing-key height. Portrait results scroll horizontally above them; wide layouts put results alongside them. Both backspace keys edit before the local query caret. These keys and space edit only the query, with literal spaces; Done returns English typing while preserving the Unicode query and results. Properties use a 76×44pt Save key with a full native touch target. Host typing never changes that query. Held delete stops when released, when resizing or search mode changes, or when the receiving document changes. Typing, search and app-to-keyboard favorites work without network or Full Access. Optional Full Access permits favorites saved in the keyboard to reach the app and light haptics on supported iPhones; it does not enable any network requests.

The keyboard uses a fixed template: a number row, three character rows and a matching footer. Phone/narrow keys are 41.4 points and wide iPad keys 59.8 points, 15% taller than their previous sizes. App Settings → Top Row chooses Off, Symbols or Search. The optional top row is one horizontal strip with normal keycaps, or a search toolbar of the same height. U opens Unicode browsing and returns to English. There is no drag handle, height picker, triangle feedback or saved height preference. The app and keyboard keep the exact query/caret when changing panels. Saved/Recent use rounded keycaps without code-point captions. Board editing stays in an opaque, bounded scrollable panel. iOS owns the separate bottom system controls and host editor.

**Extra Unicode fonts** is optional and **off by default**. Enable it only in the app's Settings tab; the keyboard reads the same choice locally without Full Access. Bundled Noto Sans Symbols 2 and GNU Unifont improve some missing character previews while keeping supported system glyphs and emoji unchanged. Previews are checked at runtime: anything the stock fonts draw as tofu, or an emoji sequence they draw as separate pieces, uses a fallback font when one draws it, including Noto Color Emoji from the optional emoji pack. A preview that is still missing gets a red-tinted background. They cannot change fonts in receiving apps or display every new Unicode 18/19 character. Full font licenses are available in Settings → Font Licenses. See [font sources, verified coverage and update policy](docs/font-pack.md).

iPad portrait keeps three letter rows. App Settings → iPad Keyboard offers three wide-landscape presets: stock three-row iPad, compact three-row ANSI punctuation, and four-row ANSI with dedicated digits (default). Landscape requires at least 980 points of content width; narrower or floating panes retain the compact/stock arrangement. ANSI uses staggered 15-unit rows, punctuation, manual Shift symbol pairs and wider gray modifiers; automatic sentence capitals and Caps Lock never shift digits. In portrait and landscape, Numbers/Symbols and Hide Keyboard sit to the right of a smaller Space; U, globe (when requested by iOS) and Star sit left. Symbol pages complement the dedicated digit row instead of repeating digits. iPad letters use the same Up and Down forms as iPhone, with no symbol hints; symbols come from the 123 and #+= pages. Per-key overrides take precedence, and taps always type the key. All layout settings are app-only and reach the keyboard without Full Access.

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

Enable the system keyboard in **Settings → General → Keyboard → Keyboards → Add New Keyboard → Uniboard**. In the app’s Settings tab, open **Try Your Keyboard**, tap the editor, hold the globe key, and select Uniboard. iOS uses the system keyboard in secure and phone-number fields; host apps may disallow custom keyboards.

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

This test enables Uniboard through Settings and selects the installed extension from the system globe menu. It verifies that searching `U+1F680` keeps the query out of the host document, inserts 🚀, and handles space and deletion. It saves screenshots in the test results around search and after character insertion. Local QA targets iOS 27. Earlier iOS 18.5 fixtures have been retired.

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

The current draft has the same assigned set size as 18; choosing it does not mean every entry is new. Historical selections store their actual version (for example `17.0.0`), while latest/draft follow their tracks. Monthly updates advance the two historical slots. A retired selection or unavailable/malformed shared setting falls back to the latest release. The app writes one bounded settings file for the edition, appearance and top-bar preferences, iPad layout and symbol mapping, and a separate bounded file for explicitly configured key gestures, in its App Group. The keyboard opens both read-only. Document typing, searches, favorites and scratchpad never enter these settings files.

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

Letter flicks never type digits or symbols by default, with or without a number row; custom choices can add them.

iPad modifiers use stock-style bottom corner content: left-side Tab/Caps/Shift and footer controls align lower left, while Delete, Return, right Shift and right footer controls align lower right. Modifier text uses normal weight; character glyphs stay centered. Phone alignment is unchanged.

### Favorites synchronization and touch feedback (1.1 beta)

Saved adapts the built-in Favorites page instead of maintaining an unrelated collection. First use merges both existing collections without discarding custom boards, exact variants or the preferred Star target. Only explicit favorite text enters `favorites-v1.json` in the local App Group; typed documents, query text, scratchpad and recents never enter it. App writes and keyboard writes with Full Access use a nonblocking file lock, re-read the current snapshot, apply a three-way merge and atomically replace one bounded document. Pending additions/removals and the acknowledged baseline stay in local board storage across relaunches. Unrelated concurrent saves survive; removals are not resurrected by a stale cache. Malformed, unavailable, oversized or unwritable data retains local/original bytes and surfaces a sync notice. The app refreshes on foreground/Saved presentation; the keyboard refreshes when presented.

Without Full Access the keyboard reads app favorites and keeps its own edits pending locally. iOS requires Full Access for shared-container writes back to the app. Reopening with access flushes pending edits. This permission is optional; there are no network APIs, servers or accounts. Recent remains separate. Non-emoji multi-scalar favorites appear in Saved text with Copy and Remove actions.

Native letter, digit, symbol, Space, modifier, Delete and configuration keys highlight on touch-down and clear on release, scroll cancellation, context change or detachment without changing key geometry or hit targets. On supported iPhones with Full Access, key-down also provides a light haptic; Delete repeats do not generate a haptic stream. Physical-device haptic behavior still needs device acceptance.

Hold letters for accents in the current case. Up offers modifier forms and Down styled forms of the same character. The default groups are disjoint for each physical key. Explicit choices take priority without rewriting stored settings or normalizing Unicode. Currency-key holds retain full currency families. Once a hold or swipe shows its choices, the press keeps that group: further vertical movement never switches to another. Sideways movement selects within the group; release inserts once. Shift uses one-shot tap, double-tap Caps Lock and touch-then-slide for one shifted character.

The keyboard's page list only opens pages; naming and editing happen in the app. The companion app’s live search uses the keyboard’s Done key without an extra accessory toolbar. Accent and gesture choosers arrange choices around the primary character, alternating right and left; logical Unicode outputs remain exact.
