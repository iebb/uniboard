# Uniboard App Store screenshots

The artwork uses white and ivory backgrounds, the approved keyboard icon with Omega, hiragana A and infinity character keys, forest text and orange accents. Each screen is an actual app capture, placed whole inside a light decorative frame with one uniform resize. App labels, controls, glyphs, codepoints and results are never generated, translated, relabeled, stretched or replaced. Only the outer physical screen corners are rounded.

The iPhone exports are 1320 × 2868; the iPad exports are 2064 × 2752. Every export is an opaque RGB PNG. These are accepted portrait sizes for Apple's 6.9-inch iPhone and 13-inch iPad screenshot classes. [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

## Capture slots

Place the complete, unmodified screenshot under `source/iphone/` or `source/ipad/` with its slot filename. The renderer exports only files that actually exist.

| Filename | What the real capture should show |
| --- | --- |
| `00-explore.png` | The default Explore screen, newest Unicode ages first, with the selected catalog visible. |
| `01-keyboard.png` | The installed system keyboard with the single top-right delete key and verified character insertion in the host. |
| `02-search.png` | A real name or codepoint query and its character results. |
| `03-blocks.png` | A Unicode block and its actual character grid. |
| `04-details.png` | Character name, description and Unicode properties; a new glyph may be unavailable in the device font. |
| `05-saved.png` | Saved characters or complete emoji sequences. |
| `06-private.png` | The app's offline-search and keyboard setup information. |
| `07-emoji.png` | A complete emoji sequence, its codepoints, or verified ZWJ/variation-selector insertion. |
| `08-editions.png` | The catalog selector showing Unicode 18 latest release and Unicode 19 development draft. |
| `09-properties.png` | The real keyboard inspector, scrolled to script, direction, combining class and decomposition, with the host unchanged. |

The current official Unicode 19 development data can have the same assigned characters and emoji as Unicode 18. The artwork describes the available catalogs and does not claim that the draft has invented extra assignments. Emoji introduction versions and the ages of individual Unicode scalars can differ.

## Reproduce the exports

Run from the repository root:

```sh
python3 marketing/screenshots/render.py --preview
python3 marketing/screenshots/render.py
```

`--preview` writes only `qa/preview/`, including its own manifest and contact sheet. It leaves the upload images and `upload-manifest.json` untouched, so a layout preview made from historical captures cannot replace the current reviewed set accidentally.

The normal command writes `iphone/`, `ipad/`, `manifest.json`, `upload-manifest.json`, and `qa/contact-sheet.jpg`. It uses Pillow and the macOS Avenir Next and Georgia fonts. It validates portrait PNG inputs and rejects transparent captures. Each provenance record includes the original source dimensions and SHA-256, the export SHA-256, exact export dimensions, icon SHA-256, copy and composition. Sources are hashed again after rendering to detect a capture changing mid-run.

`upload-manifest.json` is generated from that run's actual exports. It produces the four `en-US`/`ja` × `APP_IPHONE_67`/`APP_IPAD_PRO_3GEN_129` sets, with the keyboard first, then Explore, complete emoji, properties, editions, search, blocks, Saved and privacy when those captures exist. A missing slot is omitted; an old export lying in an output folder is not silently included. The app UI remains English in both storefronts, as disclosed by the Japanese listing. `qa/` is for review and is not an upload folder.

## Capture provenance and revision QA

Keep the original `xcresulttool` attachment exports and their manifest under `source/` alongside the chosen slot copies. A slot copy must have the same SHA-256 as its source attachment. Retained test screenshots verify actual name/codepoint search, numeric age ordering, catalog selection and persistence, full properties, unsupported glyph names, and whole ZWJ/variation-selector insertion. A fresh default Explore framebuffer can also be captured with `simctl io … screenshot` after installing the exact revised build on the appropriate device.

`source/validation-attachments/` contains the earlier passing `FinalValidation.xcresult` keyboard proof. It remains historical evidence: that earlier rocket screenshot predates the top-right delete, expanded properties, complete emoji and edition-selector revision. The active upload inputs have been replaced with the successful revision captures recorded below.

Review the final contact sheet and full-size exports before release. Check that the complete screen remains in frame, the headline and UI are readable, the shown query and insertion match the test evidence, device layouts are preserved, and the advertised feature is actually visible in its source capture.

## Verified phone app revision captures

The six active phone app slots come from the successful `build/QA/Revision-App-4.xcresult` run on the dedicated iOS27 phone. All nine active app UI cases and 20 core tests passed. The originals and their selected xcresult attachment manifest are retained under `source/revision-app-4-attachments/`; `capture-manifest.json` records exact slot, device, test, attachment name, dimensions and raw hash. Each active slot copy was verified byte-for-byte against its original. No failed run3 screenshot was selected.

| Slot | Passing UI test | Original attachment | Raw SHA-256 |
| --- | --- | --- | --- |
| `00-explore.png` | `testDefaultNewestFirstUsesNumericUnicodeAges()` | `09DD1C36-D738-4350-A441-6B59BE8078B6.png` | `c0ad9695b132ac035cdcdd8edf25160513284c9db94ef42b93e17619bb806060` |
| `02-search.png` | `testSearchBySupplementaryCodepointAndAlias()` | `02D14FC8-F751-40C1-910E-853F07C05F4D.png` | `19a5d35f18b4fcac137aef5c5d589ae2df498c3bd2c9545630fe92d6053d5cba` |
| `03-blocks.png` | `testBrowseUnicodeBlockAndOpenCharacter()` | `5418AED6-9AC3-4817-A5F4-F8E668EE53E2.png` | `3bebb72551ac2dca62682268fa6a7c221326a1d3b64d18a2ceb128d01ceea071` |
| `04-details.png` | `testUnsupportedGlyphStillShowsNameDescriptionAndProperties()` | `08C1B6E1-7EBE-4F10-AA42-CCDD5ADDA984.png` | `2bd9155b0988c0f6073877f1c017d28158a13c1962cda909f7b9d8277ca9122f` |
| `07-emoji.png` | `testEmojiDetailsAndScratchpadPreserveWholeZWJSequence()` | `343AD1B6-CDD1-4E28-BF10-CC3B2801234C.png` | `1c3bba3f116b542d3145d69fadaa78def3809f584cd6031c73aca1741513588b` |
| `08-editions.png` | `testCatalogSelectionPreservesLookupStatusAndLocalChoice()` | `B9527280-E86C-466F-91BC-5D1BF80B64E4.png` | `0e52388de90e9fbd21153d639ab1475d9a6e09312228fbc2750381e8691d5e59` |

The active phone inputs were replaced with this successful app capture set and the revised real keyboard capture set below.

## Verified real system keyboard revision captures

All five real system keyboard cases passed in `build/QA/Revision-Keyboard-2.xcresult` on the dedicated iPhone16Pro/iOS18.5 device. This exercises the installed extension and the real host text document, including exact Unicode insertion, space/delete, complete ZWJ+VS16 insertion/deletion, inspection without insertion, and independent catalog persistence. The successful source attachments and selected export manifest are retained under `source/revision-keyboard-2-attachments/`. The following active slot copies match their originals byte-for-byte.

| Slot | Passing UI test | Original attachment | Raw SHA-256 |
| --- | --- | --- | --- |
| `09-properties.png` | `testSystemKeyboardLongPressShowsPropertiesWithoutInsertion()` | `FA94531A-76E8-4D39-AD3E-0C58E9053252.png` | `0b5c570878d9cc487d14d3576572b823ec1bfcb346bd29eb8d07fff01093b088` |
| `01-keyboard.png` | `testSystemKeyboardSearchAndInsertion()` | `FF698BE7-E439-4911-BCC3-33F507F65EFE.png` | `7994cc431a97f7aaa4db3eb350d1bf435733844f814431594822a896d9643b61` |

The supporting `D47F7686-1192-41AF-9CE8-69868E0EE270.png` attachment from `testSystemKeyboardInsertsWholeZWJEmojiAndVariationSelectorWithoutLeakingQuery()` shows the exact `🙂‍↔️` sequence inserted into the host. The test verified all four scalars `[1F642, 200D, 2194, FE0F]` and no search-query leakage; raw SHA-256: `966b8b9d34b5dfb83e1db1bc70fa5c748626a78f5d46cf1c45eb7b83921acda8`.

The follow-up unchanged-query tab-switch regression also passed in `build/QA/Revision-Keyboard-Regression.xcresult`. It verifies that reopening the same `u+1f680` query after switching Symbols → Emojis → Symbols refreshes the result type and preserves the host document.

## Verified iPad revision captures

All three revised iPad cases passed in `build/QA/Revision-iPad-2.xcresult` on `Uniboard App Store iPad` / iPadOS27. The selected originals, Apple attachment manifest and raw capture provenance are retained under `source/revision-ipad-2-attachments/`; no canceled or failed earlier iPad capture was used.

| Slot | Passing UI test | Original attachment | Raw SHA-256 |
| --- | --- | --- | --- |
| `03-blocks.png` | `testBrowseUnicodeBlockAndOpenCharacter()` | `C6633DC4-6B77-40FA-AB6D-B9F62A8B5E3D.png` | `93d170b01ea14cc2712e68c15ea5edb6f3305b42bad3bafeeb7940bcbb13f542` |
| `04-details.png` | `testUnsupportedGlyphStillShowsNameDescriptionAndProperties()` | `BCCE0E4B-816B-42F3-A112-173FBD2ED8D7.png` | `5d1b4d66298f404ed8727c5e60b610cc091e3a4395dc366cd1001a4844cd3a68` |
| `07-emoji.png` | `testEmojiDetailsAndScratchpadPreserveWholeZWJSequence()` | `CC209AA2-5967-4E2B-AD38-F9A84FF07FE4.png` | `19a99d38d2489029ced89207f667f33a88764fc64c8ae4557d50c4cf0d4670d8` |

`source/ipad/00-explore.png` is a settled, complete 2064×2752 simulator framebuffer from the installed `build/QA/FinalReleaseBuild/Build/Products/Release-iphonesimulator/Uniboard.app` on device `CB0142AB-D811-4694-84FE-FA4B3DA6A779`, launched as `ad.neko.uniboard --uitesting`. The settled frame shows Unicode 19 draft, newest-first ordering, and readable names for Unicode 18 characters whose glyphs are unavailable. The unmodified original is retained as `source/revision-ipad-2-attachments/00-explore-framebuffer.png`; raw SHA-256: `69057e6af8caddab4244b3aa74ab8a12e708039ed7e7cb716fab0cf999c328f9`.

## Final export verification

The final manifest contains 12 reviewed exports: eight iPhone screenshots, including the optional keyboard-properties capture, and four iPad screenshots. Each locale receives the same real English UI captures in four explicit locale/device upload sets. Source/original byte equality, source/export/icon SHA-256, accepted dimensions, complete screen composition, RGB mode and PNG opacity were verified. The contact sheet and representative full-size keyboard, emoji and iPad exports were reviewed for readability and clipping. Preview artwork remains outside Git under ignored `build/QA/Artwork-White-Preview/`.
