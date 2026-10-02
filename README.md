# Uniboard

A native, offline Unicode keyboard for iPhone and iPad. The containing app is `ad.neko.uniboard`; the system keyboard extension is `ad.neko.uniboard.keyboard`. Requires iOS 17 or later.

Search by character name, descriptive annotation, alias, block name, hexadecimal code point (`U+1F680`, `0x1F680`, `1F680`), explicit decimal code point (`decimal:128640`), or a literal character in the app. Browse the complete block list and scroll through paginated character grids. Character details show the scalar, name, block, annotations, decimal value, and UTF-8 bytes. Copy a character, save it, or collect text in the app’s scratchpad.

Bare hexadecimal searches need a numeric digit; use `U+FACE` for a letters-only code point so the word “face” can find characters by name.

The keyboard inserts the actual Unicode scalar at the host app’s cursor. It includes its own letter and numeric keys for searching, a globe menu, space, return, and repeating delete. Hold a character to inspect and save it. Favorites and recent characters are stored separately in the app and keyboard. No network or Full Access is required at runtime.

## Run locally

Open `Uniboard.xcodeproj` and run the **Uniboard** scheme. Both targets use automatic signing with the Kitta Ltd team. For a different account, select the same team for the application and keyboard extension. The committed Xcode project can build without XcodeGen. After changes to `project.yml`, run `xcodegen generate`.

Enable the system keyboard in **Settings → General → Keyboard → Keyboards → Add New Keyboard → Uniboard**. In the app’s Setup tab, open **Try your keyboard**, tap the editor, hold the globe key, and select Uniboard. iOS uses the system keyboard in secure and phone-number fields; host apps may disallow custom keyboards.

```sh
swift test
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Uniboard.xcodeproj -scheme Uniboard \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO test
```

## Latest Unicode draft

The generator uses the latest official Unicode development data and records its provenance in `Shared/Resources/UnicodeSources.json`. It pins each fetch to one immutable upstream revision and records source hashes. It does not silently replace a failed draft fetch with the stable release. The complete catalog uses a small memory-mapped binary rather than materializing hundreds of thousands of Swift objects in the keyboard process. Algorithmic names cover Hangul and ideographic ranges.

```sh
python3 Scripts/generate_unicode.py --source draft --refresh
swift test
```

Draft assignments and names can change. A character’s ability to display depends on the fonts included in the user’s iOS version. Dotted circles and invisible-character markers are preview aids; only the original scalar is copied or inserted. Surrogates are not valid Unicode scalars and are not insertable. Unicode data is distributed under the bundled Unicode License v3.

## Monthly refresh and Xcode Cloud

`.github/workflows/unicode-monthly.yml` runs on the first of every month at **03:17 UTC / 12:17 Japan time**, and supports manual dispatch. It fetches the latest draft, runs catalog tests, builds the app and embedded keyboard for the iOS simulator, and commits validated data and provenance to `master`. The repository’s default branch must be `master`.

Xcode Cloud uses the committed **Uniboard.xcodeproj** and shared **Uniboard** scheme, with `master` as its source branch. Executable hooks in `ci_scripts` check prerequisites after cloning and regenerate the latest draft immediately before building. A failed download or catalog test fails the build. XcodeGen, Homebrew, and third-party package managers are not needed in Xcode Cloud.

Apple’s initial Xcode Cloud onboarding must connect the app, signing team, and GitHub repository. Use **Product → Xcode Cloud → Create Workflow** in Xcode, grant access to `iebb/uniboard`, and set a branch-change trigger for `master`. Configure an iOS archive action to produce signed builds; TestFlight distribution is configured in the Apple workflow. A committed CI script alone does not register or activate an Apple workflow.

Apple documentation: [custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), [first workflow setup](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow/).
