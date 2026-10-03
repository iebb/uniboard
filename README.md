# Uniboard

A native, offline Unicode keyboard for iPhone and iPad. The containing app is `ad.neko.uniboard`; the system keyboard extension is `ad.neko.uniboard.keyboard`. Requires iOS 17 or later.

Search by character name, descriptive annotation, alias, block name, hexadecimal code point (`U+1F680`, `0x1F680`, `1F680`), explicit decimal code point (`decimal:128640`), or a literal character in the app. Browse the complete block list and scroll through paginated character grids. Character details show the scalar, name, block, annotations, decimal value, and UTF-8 bytes. Copy a character, save it, or collect text in the app’s scratchpad.

Bare hexadecimal searches need a numeric digit; use `U+FACE` for a letters-only code point so the word “face” can find characters by name.

The keyboard inserts the actual Unicode scalar at the host app’s cursor. It includes its own letter and numeric keys for searching, a globe menu, space, return, and repeating delete. Hold a character to inspect and save it. Favorites and recent characters are stored separately in the app and keyboard. No network or Full Access is required at runtime.

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

The ordinary UI tests cover name, code point, literal-character and block searches, block browsing, and favorites. The system-keyboard integration test is opt-in because it changes the simulator’s enabled keyboards. Use a dedicated QA simulator with its software keyboard visible. In Xcode 27’s Device Hub, **Controls → Toggle Software Keyboard** shows or hides the software keyboard; disable **Device → Simulate Hardware Keyboard** when necessary.

```sh
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO \
  UNIBOARD_KEYBOARD_INTEGRATION=1 \
  -only-testing:UniboardUITests/UniboardUITests/testSystemKeyboardSearchAndInsertion test
```

This test enables Uniboard through Settings and selects the installed extension from the system globe menu. It verifies that searching `U+1F680` keeps the query out of the host document, inserts 🚀, and handles space and deletion. It saves screenshots in the test results around search and after character insertion. This complete flow passed on an iPhone 16 Pro simulator running iOS 18.5.

## Latest Unicode draft

The generator uses the latest official Unicode development data and records its provenance in `Shared/Resources/UnicodeSources.json`. It pins each fetch to one immutable upstream revision and records source hashes. Transient download failures, including truncated responses, retry up to three times with bounded delays. An exhausted or invalid draft fetch fails without replacing the existing catalog with a stable release. Both CI paths run the download recovery regression tests before refreshing. The complete catalog uses a small memory-mapped binary rather than materializing hundreds of thousands of Swift objects in the keyboard process. Algorithmic names cover Hangul and ideographic ranges.

```sh
python3 Scripts/generate_unicode.py --source draft --refresh
swift test
```

Draft assignments and names can change. A character’s ability to display depends on the fonts included in the user’s iOS version. Dotted circles and invisible-character markers are preview aids; only the original scalar is copied or inserted. Surrogates are not valid Unicode scalars and are not insertable. Unicode data is distributed under the bundled Unicode License v3.

## Monthly refresh and Xcode Cloud

`.github/workflows/unicode-monthly.yml` runs on the first of every month at **03:17 UTC / 12:17 Japan time**, and supports manual dispatch. It fetches the latest draft, runs catalog tests, builds the app and embedded keyboard for the iOS simulator, and commits validated data and provenance to `master`. The repository’s default branch must be `master`.

Each refresh records `refreshedAt` in the provenance manifest, creating a validated monthly commit even when upstream Unicode data is unchanged. This also triggers an Xcode Cloud workflow configured to build on pushes to `master`.

Xcode Cloud uses the committed **Uniboard.xcodeproj** and shared **Uniboard** scheme, with `master` as its source branch. Executable hooks in `ci_scripts` check prerequisites after cloning and regenerate the latest draft immediately before building. A failed download or catalog test fails the build. XcodeGen, Homebrew, and third-party package managers are not needed in Xcode Cloud.

The repository is connected to the active [**Uniboard iOS** Xcode Cloud workflow](https://appstoreconnect.apple.com/teams/cbaca10a-f696-4d2b-959e-0d3fa1b23452/xcode-cloud/products/001084ae-fa0b-491c-b14a-2f03ad794f84/workflows). It uses the latest release environment and archives iOS for **TestFlight and App Store** on pushes to `master`. Each monthly validated data commit therefore triggers a signed archive with a fresh Unicode draft. The pre-build hook runs five download recovery tests and all 11 catalog tests. Automatic Cloud build **1.0.0 (7)** refreshed the draft, recovered a real interrupted download, passed those checks, uploaded successfully and became **Ready to Test**.

The [App Store Connect record](https://appstoreconnect.apple.com/apps/6818750518/distribution/info) is registered under **Kitta Ltd** as **Uniboard: Unicode Keyboard**, Apple ID **6818750518**, bundle ID and SKU **ad.neko.uniboard**, with English (U.S.) as its primary language. The device display name remains Uniboard. No App Store release has been submitted.

The primary workflow starts automatically from `master` branch changes and has no manual start condition. Editing is restricted to admins and app managers, and builds use a clean environment. Its internal and external TestFlight post-actions deliver to **Internal Testers** and **External Testers**, respectively. The redundant setup workflow remains disabled and has no manual start condition.

Both tester groups are created, and Cloud build **1.0.0 (8)** was delivered to **Internal Testers**. No individual testers or public invitation links have been added. The approved Kitta review contact and feedback email from Mithka are configured, along with Uniboard-specific keyboard review instructions. External distribution remains subject to Apple's beta review. `TestFlight/WhatToTest.en-US.txt` supplies tester instructions automatically with each Cloud upload.

Apple documentation: [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [first workflow setup](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/), [automatic tester notes](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app), [external beta review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
