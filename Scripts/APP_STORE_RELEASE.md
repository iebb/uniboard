# App Store release helper

`app_store_release.rb` is GET-only by default. Set `ASC_KEY_ID` and use the existing local issuer/private-key files; optional `ASC_ISSUER_ID` and `ASC_KEY_PATH` override their locations. It never prints credentials or review contact values. It verifies the exact Kitta app, successful signed Cloud Archive, source commit, build number, iOS marketing version, `VALID`, App Store eligibility and export compliance before a write. An unrelated external TestFlight post-action can still be awaiting beta review while the signed archive is usable for public review.

Run `ruby Scripts/tests/test_app_store_release.rb` before using it. Supply the new icon build's exact run ID, SHA and number. Do not infer those from the current checkout or a previous successful build.

For the initial release's factual settings, `--readiness` performs a GET-only plan without requiring a binary or listing files. `--apply-readiness` applies that same scoped plan and verifies its readback. It declares licensed third-party Unicode content; sets Utilities/Reference categories; answers the age questionnaire with occasional mild alcohol/tobacco, weapon and crude-gesture references from Unicode pictograms, all other content frequencies NONE and unsupported functionality booleans false; selects the exact free USA price point; and enables all current and future App Store territories without pre-order. Apple derives the final age rating. Existing paid prices or territory restrictions cause a stop before any write. This mode never publishes App Privacy, changes review contacts, attaches a build or submits for review.

```sh
ruby Scripts/app_store_release.rb \
  --version 1.0.0 --build-number BUILD_NUMBER \
  --ci-build-run-id CLOUD_RUN_UUID --source-commit FULL_COMMIT_SHA \
  --review-notes PATH_TO_REVIEW_INSTRUCTIONS \
  --support-url VERIFIED_PUBLIC_SUPPORT_URL \
  --privacy-url VERIFIED_PUBLIC_PRIVACY_POLICY_URL \
  --marketing-url VERIFIED_PUBLIC_MARKETING_URL \
  --copyright '2026 Kitta Ltd' \
  --reuse-beta-review-contact \
  --screenshots-manifest PATH_TO_SCREENSHOT_MANIFEST
```

The standard deliver files under `fastlane/metadata/{en-US,ja}` are the source of listing copy. The initial blank version `1.0` is renamed to `1.0.0`; initial releases skip What's New. Utilities and Reference are the categories. Existing nonempty review contacts are preserved; the explicit reuse flag fills missing contacts from the app's already approved beta review contact, with app-specific instructions and no demo account.

Screenshot manifest format:

```json
[
  {"locale":"en-US","displayType":"APP_IPHONE_67","files":["iphone/01-keyboard.png","iphone/00-explore.png"]},
  {"locale":"en-US","displayType":"APP_IPAD_PRO_3GEN_129","files":["ipad/00-explore.png"]},
  {"locale":"ja","displayType":"APP_IPHONE_67","files":["iphone/01-keyboard.png","iphone/00-explore.png"]},
  {"locale":"ja","displayType":"APP_IPAD_PRO_3GEN_129","files":["ipad/00-explore.png"]}
]
```

Paths are relative to the manifest. Screenshots must be 8-bit PNG without an alpha channel and have accepted iPhone 6.9/6.5-inch or iPad 13-inch dimensions. The helper reserves each asset, uploads Apple's instructed byte ranges without forwarding the API JWT, commits the MD5 checksum, waits for `COMPLETE` and verifies screenshot order. Existing matching filenames/checksums are reused. Different or incomplete uploads cause a stop; the helper never deletes screenshots. Processing waits are bounded by `--asset-wait-seconds` (default 180).

After reviewing the dry run, `--apply` writes listing metadata, categories, review detail and screenshots, then verifies the readback. Before adding `--submit --privacy-published`, independently verify the published App Privacy answers, reachable policy/support URLs, age rating, content rights, free pricing and territory availability. App Privacy questionnaire responses are not exposed by the public API. The helper also checks API-visible submission requirements. The final step creates/reuses a narrowly scoped `reviewSubmissions` resource, adds the exact `reviewSubmissionItems` version and sets `submitted=true`, then verifies the exact version/build and Apple's submission state.

No POST/PATCH or binary upload is retried automatically. A timeout after a write is an unknown outcome: re-query App Store Connect before retrying. Errors print resource paths/status codes rather than server details that could contain private contact values. This helper does not cancel existing submissions, resolve rejected items, alter unrelated review contents, invite testers or release an approved app manually.

Official references: [submission workflow](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app), [review resources](https://developer.apple.com/documentation/appstoreconnectapi/review-submissions), [asset uploads](https://developer.apple.com/documentation/appstoreconnectapi/uploading-assets-to-app-store-connect), [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/), [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).
