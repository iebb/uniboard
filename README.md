# Uniboard

A native, offline Unicode keyboard for iPhone and iPad. The containing app is `ad.neko.uniboard`; the system keyboard extension is `ad.neko.uniboard.keyboard`. Requires iOS 17 or later.

Search by character name, descriptive annotation, alias, block name, hexadecimal code point (`U+1F680`, `0x1F680`, `1F680`), explicit decimal code point (`decimal:128640`), or a literal character in the app. Browse every block or all assigned characters, ordered globally by official Unicode Age with newest first by default. The order menu also offers oldest first and code point order. Bare hexadecimal searches need a numeric digit; use `U+FACE` for a letters-only code point so the word “face” can find names.

Switch between **Unicode 18.0.0**, the latest official release, and **Unicode 19.0.0 draft**, selected by default. Both catalogs are bundled offline. The current snapshots contain the same 310,341 assigned scalars and 3,963 fully qualified emoji each; selecting the draft does not imply an entry was introduced in Unicode 19. The app and keyboard persist their own edition and order choices.

The **Emojis** tab searches and browses complete official fully qualified entries, including ZWJ sequences, variation selectors, flags, keycaps and skin tones. Copying or keyboard insertion preserves the entire sequence. Emoji version ordering uses Emoji introduction version; component Unicode ages are shown separately. Favorite and recent emoji are stored alongside scalar collections, locally and separately in the app and keyboard.

Hold a character or emoji key, or keep a pointer over it, to open a scrollable properties panel without inserting text. Read the official name, available description, code points, Unicode age, block, category, script, bidirectional class, combining class, decomposition and UTF-8 bytes as applicable. Emoji details show each component's name and code point. Names and properties remain readable when an iOS font shows a missing glyph or renders a sequence as separate symbols. Tap, hold or hover a tile in the containing app to inspect it, then copy or add its original text to the scratchpad.

The keyboard inserts the selected scalar or complete emoji at the host app’s cursor. It includes its own search keys, the native globe menu, space, return and a persistent top-right repeating backspace. Search keys, space and backspace edit only the query while search is open; close the search keys to type into the host document. No network or Full Access is required at runtime.

## Run locally

Open `Uniboard.xcodeproj` and run the **Uniboard** scheme. Both targets use automatic signing with the Kitta Ltd team. For a different account, select the same team for the application and keyboard extension. The committed Xcode project can build without XcodeGen. After changes to `project.yml`, run `xcodegen generate`.

Both bundle IDs are registered to Kitta Ltd, team **7P8CLHDH5G**. A Release device archive has been built and its app and embedded keyboard signatures independently verified against that team. To create a signed local archive with the configured Xcode account:

```sh
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/QA/Uniboard-Kitta.xcarchive \
  -allowProvisioningUpdates archive
```

Enable the system keyboard in **Settings → General → Keyboard → Keyboards → Add New Keyboard → Uniboard**. In the app’s Setup tab, open **Try your keyboard**, tap the editor, hold the globe key, and select Uniboard. iOS uses the system keyboard in secure and phone-number fields; host apps may disallow custom keyboards.

```sh
swift test
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

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

The generator refreshes both the latest official final release and the latest official Unicode development data, including the fully qualified emoji sets and Unicode property data. It records provenance in `Shared/Resources/UnicodeSources-latest.json` and `Shared/Resources/UnicodeSources.json`. It pins each fetch to one immutable upstream revision and records source hashes. Transient download failures, including truncated responses, retry up to three times with bounded delays. An exhausted or invalid draft fetch fails without replacing the existing catalog with a stable release. Both CI paths run the download recovery regression tests before refreshing. The complete catalog uses a small memory-mapped binary rather than materializing hundreds of thousands of Swift objects in the keyboard process. Algorithmic names cover Hangul and ideographic ranges.

```sh
python3 Scripts/generate_unicode.py --source all --refresh
swift test
```

Draft assignments and names can change. A character’s ability to display depends on the fonts included in the user’s iOS version. Dotted circles and invisible-character markers are preview aids; only the original scalar or complete emoji sequence is copied or inserted. A missing glyph does not hide the official name, description or properties. Surrogates are not valid Unicode scalars and are not insertable. Unicode data is distributed under the bundled Unicode License v3.

## Monthly refresh and Xcode Cloud

`.github/workflows/unicode-monthly.yml` runs on the first of every month at **03:17 UTC / 12:17 Japan time**, and supports manual dispatch. It fetches the latest release and draft data, runs catalog tests, builds the app and embedded keyboard for the iOS simulator, and commits validated data and provenance to `master`. The repository’s default branch must be `master`.

Each refresh records `refreshedAt` in the provenance manifest, creating a validated monthly commit even when upstream Unicode data is unchanged. This also triggers an Xcode Cloud workflow configured to build on pushes to `master`.

Xcode Cloud uses the committed **Uniboard.xcodeproj** and shared **Uniboard** scheme, with `master` as its source branch. Executable hooks in `ci_scripts` check prerequisites after cloning and regenerate both offline editions and their emoji catalogs immediately before building. A failed download or catalog test fails the build. XcodeGen, Homebrew, and third-party package managers are not needed in Xcode Cloud.

The repository is connected to the active [**Uniboard iOS** Xcode Cloud workflow](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/001084ae-fa0b-491c-b14a-2f03ad794f84/workflows). It uses the latest release environment and archives iOS for **TestFlight and App Store** on pushes to `master`. Each monthly validated data commit therefore triggers a signed archive with fresh Unicode release and draft data. The pre-build hook runs download recovery and catalog/emoji regression tests. Automatic Cloud build **1.0.0 (7)** refreshed the draft, recovered a real interrupted download, passed those checks, uploaded successfully and became **Ready to Test**.

The [App Store Connect record](https://appstoreconnect.apple.com/apps/6818750518/distribution/info) is registered under **Kitta Ltd** as **Uniboard: Unicode Keyboard**, Apple ID **6818750518**, bundle ID and SKU **ad.neko.uniboard**, with English (U.S.) as its primary language. The device display name remains Uniboard. Public review, external beta review and public App Store availability are separate Apple states; check App Store Connect for the current status.

The primary workflow starts automatically from `master` branch changes and has no manual start condition. Editing is restricted to admins and app managers, and builds use a clean environment. Its internal and external TestFlight post-actions deliver to **Internal Testers** and **External Testers**, respectively. The redundant setup workflow remains disabled and has no manual start condition.

Both tester groups are created, and Cloud build **1.0.0 (8)** was delivered to **Internal Testers**. No individual testers or public invitation links have been added. The approved Kitta review contact and feedback email from Mithka are configured, along with Uniboard-specific keyboard review instructions. External distribution remains subject to Apple's beta review. `TestFlight/WhatToTest.en-US.txt` supplies tester instructions automatically with each Cloud upload.

Apple documentation: [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [first workflow setup](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/), [automatic tester notes](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app), [external beta review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

## Branding and public release

The approved icon master and generation prompt are in `marketing/icon`; run `swift Scripts/generate_icon.swift` to produce the opaque 1024-pixel iOS asset. Real simulator screenshots, provenance and reproducible artwork exports are in `marketing/screenshots`. `upload-manifest.json` defines the English and Japanese iPhone/iPad screenshot order. Storefront copy lives in `fastlane/metadata/{en-US,ja}`; the Japanese listing explicitly discloses the English interface and catalog names. See `docs/aso-strategy.md` for metadata limits and search positioning.

The [public website](https://uniboard-dxm.pages.dev/), [support page](https://uniboard-dxm.pages.dev/support/) and [privacy policy](https://uniboard-dxm.pages.dev/privacy/) are served from the curated `website` directory through Cloudflare Pages. The private application repository is not published. The static site has no analytics scripts or external fonts and explains the website host separately from the offline app. The support address is Kitta's existing customer-feedback address.

`Scripts/app_store_release.rb` prepares or submits only this app's exact verified Xcode Cloud archive. It is GET-only by default, with separate flags for factual readiness settings, listing preparation and review submission. See `Scripts/APP_STORE_RELEASE.md` for credentials, guards and usage. `AppStore/ReviewNotes.en-US.txt` supplies the reviewer's keyboard test instructions. App Privacy publication must be verified separately before submitting.

### Publish website updates

The website workflow validates changes on `master`; deployment uses the existing Cloudflare login locally so broad account credentials are not stored in GitHub. The Pages project is `uniboard` in Kitta Labs, with production branch `master`.

```sh
python3 Scripts/validate_website.py
CLOUDFLARE_ACCOUNT_ID=58c982b69079141dd49d99076dd845b1 \
  wrangler pages deploy website --project-name uniboard --branch master
```

Deploy only `website`, then verify the public pages and assets before updating App Store URLs. GitHub Pages cannot publish this private repository on its current plan.
