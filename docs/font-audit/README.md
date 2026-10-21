# iOS 27 Unicode preview coverage audit

Measured on 2026-10-22 using an iPhone 17 Pro **simulator**, iOS 27.0 (24A5390f), and Uniboard's bundled Unicode 18.0.0 release catalog. The user-supplied `blocks.md` (survey 2026-10-20, 353 blocks) was used to discover candidate font sources; its cmap union was not treated as proof of iOS rendering.

| Native measurement | Visible scalar previews |
| --- | ---: |
| Tested assigned L/M/N/P/S characters | 172,351 |
| Missing using stock UIKit/Core Text fallback | 100,502 |
| Recovered by the previous three bundled fonts | 14,285 |
| Recovered with the final optional fonts enabled and all packs installed | 83,735 |
| Still unsupported | 16,767 |

The final set recovers 83.3% of the measured stock gaps. This is scalar **preview** coverage on the tested runtime, not a promise of correct arbitrary-language shaping, all emoji sequences, physical-device parity, future drafts or other apps' fonts. The original Unicode text is always inserted unchanged.

## How it was measured

`Tests/UnicodeStockCoverageAuditTests.swift` walks every assigned graphic scalar and shapes the exact production preview (`displayText`), including the dotted circle used for combining marks. A missing glyph is a zero glyph or a LastResort run covering that scalar. Invisible/default-ignorable characters and Braille blank are excluded. Emoji components are identified separately and keep Apple's renderer. No font is registered process-wide or installed as a system font.

Run the opt-in native test on iOS 27 with `UNIBOARD_FONT_AUDIT=stock` or `complete`. For installation through the production SHA-256 store, copy the pinned 61 assets into the app's `Documents/FontAuditAssets`, set `UNIBOARD_FONT_AUDIT_INSTALL=1`, then run complete mode. The test attaches a per-block JSON report and checks the four-font cache bound. Normal CI skips this explicit full-font audit; the core store, fallback fixtures and UI tests remain automated.

Machine-readable evidence: [stock](ios27-stock.json), [expanded](ios27-expanded.json). Lists contain exact scalar values, including every remaining gap.

## Smallest practical additions

Only **measured stock-missing, assigned, non-emoji scalar ranges** are advertised by downloadable subsets. Subsetting retains required glyph/positioning closure; it does not ship every source family's unrelated coverage. Noto is selected first when its real outlines cover the gap. The resulting set has 57 Noto faces, three Jigmo faces and one Fairfax HD face, renamed under unreserved Uniboard identities with the original license notices embedded.

| Optional pack | Faces | Bytes before transport compression |
| --- | ---: | ---: |
| Historic scripts & symbols | 59 | 10,724,916 |
| Supplementary Han | 1 | 30,903,504 |
| Latest Han | 1 | 7,450,532 |
| Total | 61 | 49,078,952 |

The two large Han faces are separate downloads, so someone who needs historic symbols does not download rare Han outlines. All packs are app-only, explicit, removable and usable offline in the keyboard without Full Access. Existing bundled fonts stay available. “Smallest practical” describes measured-gap subsetting and separate packs; it is not a proof of a globally optimal set cover across every available font.

A further **27,528-byte bundled derived face** repairs 86 dotted-circle combining previews that had mark outlines but no font able to shape the complete dotted-circle cluster. It reuses real source mark outlines, centers them for isolated inspection, and supplies the dotted circle; it is not intended as a spelling font for running text. The original three bundled fonts are unchanged. Source hashes, mappings and reproducible builders are committed.

## Remaining gaps and selection limits

Nine emoji scalars remain unsupported by the stock renderer. They deliberately keep Apple's color/sequence behavior. The other gaps are listed below. The supplied font inventory has no selected, verified, appropriately licensed source for every new block. SealSans declares AGPL-3.0 without a font exception and was not selected for this release. Egyptology Extended declares AI-generated supplemental glyphs; those were not used as reliable glyph recovery. This is a selection decision, not a claim that these projects can never be used.

| Block | Remaining previews |
| --- | ---: |
| Cuneiform Numbers and Punctuation | 12 |
| Archaic Cuneiform Numerals | 311 |
| Egyptian Hieroglyphs Extended-A | 3,995 |
| Tangut | 8 |
| Tangut Supplement | 24 |
| Tangut Components Supplement | 115 |
| Jurchen | 914 |
| Jurchen Radicals | 51 |
| Transport and Map Symbols | 1 |
| Symbols and Pictographs Extended-A | 8 |
| Seal | 11,328 |

## Reproduce the assets

Install `Scripts/requirements-fonts.txt`, then run from the repository root:

```sh
python3 Scripts/build_preview_font_downloads.py --cache /tmp/uniboard-font-sources --output /tmp/uniboard-font-subsets
python3 Scripts/build_combining_preview_font.py --cache /tmp/uniboard-font-sources --output /tmp/UniboardCombiningPreviews-Regular.ttf
python3 Scripts/validate_fonts.py
```

The default builders verify the committed output hashes. Updating the catalog or bundled manifest requires an explicit update flag. Source commits/releases and source hashes are pinned in [font-subset-inputs.json](font-subset-inputs.json) and [combining-preview-inputs.json](combining-preview-inputs.json). Timestamp recalculation is disabled, and independent repeated builds reproduced all 61 downloads plus the derived face byte-for-byte.

The [public font asset release](https://github.com/iebb/uniboard/releases/tag/fonts-1.1-20261022) contains fonts and license/provenance files, not an app binary. All 61 GitHub asset sizes and SHA-256 digests were read back against `Fonts/DownloadableFonts.json`; a public unauthenticated download was also checked. Downloads have no cookies or user-content parameters and are size/hash verified before Core Text sees them.

## All blocks with stock gaps

| Block | Tested | Stock missing | Recovered | Remaining |
| --- | ---: | ---: | ---: | ---: |
| Armenian | 94 | 5 | 5 | 0 |
| Hebrew | 90 | 3 | 3 | 0 |
| Syriac Supplement | 11 | 11 | 11 | 0 |
| Arabic Extended-B | 41 | 41 | 41 | 0 |
| Arabic Extended-A | 95 | 28 | 28 | 0 |
| Bengali | 96 | 2 | 2 | 0 |
| Oriya | 93 | 2 | 2 | 0 |
| Telugu | 101 | 1 | 1 | 0 |
| Kannada | 92 | 2 | 2 | 0 |
| Sinhala | 91 | 11 | 11 | 0 |
| Lao | 83 | 18 | 18 | 0 |
| Tibetan | 211 | 6 | 6 | 0 |
| Georgian | 88 | 2 | 2 | 0 |
| Hangul Jamo | 254 | 185 | 185 | 0 |
| Runic | 89 | 8 | 8 | 0 |
| Combining Diacritical Marks Extended | 65 | 65 | 65 | 0 |
| Balinese | 127 | 6 | 6 | 0 |
| Cyrillic Extended-C | 11 | 11 | 11 | 0 |
| Vedic Extensions | 43 | 28 | 28 | 0 |
| Combining Diacritical Marks Supplement | 64 | 48 | 48 | 0 |
| Superscripts and Subscripts | 46 | 3 | 3 | 0 |
| Currency Symbols | 37 | 4 | 4 | 0 |
| Combining Diacritical Marks for Symbols | 33 | 1 | 1 | 0 |
| Number Forms | 60 | 6 | 6 | 0 |
| Control Pictures | 42 | 3 | 3 | 0 |
| Dingbats | 192 | 3 | 3 | 0 |
| Miscellaneous Mathematical Symbols-A | 48 | 2 | 2 | 0 |
| Miscellaneous Symbols and Arrows | 254 | 159 | 159 | 0 |
| Glagolitic | 96 | 2 | 2 | 0 |
| Latin Extended-C | 32 | 6 | 6 | 0 |
| Georgian Supplement | 40 | 40 | 40 | 0 |
| Supplemental Punctuation | 98 | 62 | 62 | 0 |
| Ideographic Description Characters | 16 | 4 | 4 | 0 |
| CJK Symbols and Punctuation | 63 | 13 | 13 | 0 |
| Bopomofo Extended | 32 | 4 | 4 | 0 |
| CJK Strokes | 39 | 1 | 1 | 0 |
| Enclosed CJK Letters and Months | 255 | 10 | 10 | 0 |
| CJK Compatibility | 256 | 14 | 14 | 0 |
| Latin Extended-D | 206 | 187 | 187 | 0 |
| Devanagari Extended | 32 | 29 | 29 | 0 |
| Hangul Jamo Extended-A | 29 | 29 | 29 | 0 |
| Latin Extended-E | 62 | 61 | 61 | 0 |
| Hangul Jamo Extended-B | 72 | 72 | 72 | 0 |
| CJK Compatibility Ideographs | 472 | 108 | 108 | 0 |
| Arabic Presentation Forms-A | 656 | 45 | 45 | 0 |
| Halfwidth and Fullwidth Forms | 224 | 48 | 48 | 0 |
| Ancient Greek Numbers | 79 | 13 | 13 | 0 |
| Ancient Symbols | 14 | 14 | 14 | 0 |
| Phaistos Disc | 46 | 46 | 46 | 0 |
| Vithkuqi | 70 | 70 | 70 | 0 |
| Todhri | 52 | 52 | 52 | 0 |
| Latin Extended-F | 62 | 62 | 62 | 0 |
| Sidetic | 26 | 26 | 26 | 0 |
| Kharoshthi | 68 | 3 | 3 | 0 |
| Garay | 69 | 69 | 69 | 0 |
| Rumi Numeral Symbols | 31 | 31 | 31 | 0 |
| Arabic Extended-C | 60 | 60 | 60 | 0 |
| Old Sogdian | 40 | 40 | 40 | 0 |
| Sogdian | 42 | 42 | 42 | 0 |
| Old Uyghur | 26 | 26 | 26 | 0 |
| Chorasmian | 28 | 28 | 28 | 0 |
| Elymaic | 23 | 23 | 23 | 0 |
| Kaithi | 66 | 1 | 1 | 0 |
| Chakma | 71 | 1 | 1 | 0 |
| Sharada | 96 | 2 | 2 | 0 |
| Sinhala Archaic Numbers | 20 | 20 | 20 | 0 |
| Khojki | 65 | 3 | 3 | 0 |
| Tulu-Tigalari | 80 | 80 | 80 | 0 |
| Newa | 97 | 3 | 3 | 0 |
| Takri | 68 | 1 | 1 | 0 |
| Myanmar Extended-C | 20 | 20 | 20 | 0 |
| Ahom | 65 | 7 | 7 | 0 |
| Dogra | 60 | 60 | 60 | 0 |
| Dives Akuru | 72 | 72 | 72 | 0 |
| Nandinagari | 65 | 65 | 65 | 0 |
| Zanabazar Square | 72 | 72 | 72 | 0 |
| Soyombo | 83 | 83 | 83 | 0 |
| Devanagari Extended-A | 11 | 11 | 11 | 0 |
| Sharada Supplement | 8 | 8 | 8 | 0 |
| Tolong Siki | 54 | 54 | 54 | 0 |
| Bengali Supplement | 2 | 2 | 2 | 0 |
| Makasar | 25 | 25 | 25 | 0 |
| Kawi | 87 | 87 | 87 | 0 |
| Lisu Supplement | 1 | 1 | 1 | 0 |
| Cuneiform Numbers and Punctuation | 128 | 12 | 0 | 12 |
| Archaic Cuneiform Numerals | 311 | 311 | 0 | 311 |
| Cypro-Minoan | 99 | 99 | 99 | 0 |
| Egyptian Hieroglyphs | 1,072 | 1 | 1 | 0 |
| Egyptian Hieroglyph Format Controls | 22 | 22 | 22 | 0 |
| Egyptian Hieroglyphs Extended-A | 3,995 | 3,995 | 0 | 3,995 |
| Anatolian Hieroglyphs | 583 | 583 | 583 | 0 |
| Gurung Khema | 58 | 58 | 58 | 0 |
| Tangsa | 89 | 89 | 89 | 0 |
| Kirat Rai | 58 | 58 | 58 | 0 |
| Medefaidrin | 91 | 91 | 91 | 0 |
| Beria Erfe | 50 | 50 | 50 | 0 |
| Ideographic Symbols and Punctuation | 12 | 12 | 12 | 0 |
| Tangut | 6,144 | 6,144 | 6,136 | 8 |
| Tangut Components | 768 | 768 | 768 | 0 |
| Khitan Small Script | 476 | 476 | 476 | 0 |
| Tangut Supplement | 33 | 33 | 9 | 24 |
| Tangut Components Supplement | 115 | 115 | 0 | 115 |
| Jurchen | 914 | 914 | 0 | 914 |
| Jurchen Radicals | 51 | 51 | 0 | 51 |
| Kana Extended-B | 13 | 13 | 13 | 0 |
| Kana Supplement | 256 | 256 | 256 | 0 |
| Kana Extended-A | 41 | 41 | 41 | 0 |
| Small Kana Extension | 10 | 10 | 10 | 0 |
| Nushu | 396 | 396 | 396 | 0 |
| Symbols for Legacy Computing Supplement | 695 | 695 | 695 | 0 |
| Miscellaneous Symbols Supplement | 53 | 53 | 53 | 0 |
| Znamenny Musical Notation | 185 | 185 | 185 | 0 |
| Byzantine Musical Symbols | 246 | 246 | 246 | 0 |
| Musical Symbols | 248 | 218 | 218 | 0 |
| Ancient Greek Musical Notation | 70 | 70 | 70 | 0 |
| Musical Symbols Supplement | 50 | 50 | 50 | 0 |
| Kaktovik Numerals | 20 | 20 | 20 | 0 |
| Mayan Numerals | 20 | 20 | 20 | 0 |
| Counting Rod Numerals | 25 | 7 | 7 | 0 |
| Mathematical Alphanumeric Symbols | 997 | 1 | 1 | 0 |
| Sutton SignWriting | 672 | 672 | 672 | 0 |
| Miscellaneous Symbols and Arrows Extended | 29 | 29 | 29 | 0 |
| Latin Extended-G | 188 | 188 | 188 | 0 |
| Cyrillic Extended-D | 63 | 63 | 63 | 0 |
| Toto | 31 | 31 | 31 | 0 |
| Ol Onal | 44 | 44 | 44 | 0 |
| Tai Yo | 55 | 55 | 55 | 0 |
| Ethiopic Extended-B | 28 | 28 | 28 | 0 |
| Indic Siyaq Numbers | 68 | 68 | 68 | 0 |
| Ottoman Siyaq Numbers | 61 | 61 | 61 | 0 |
| Arabic Mathematical Alphabetic Symbols | 143 | 141 | 141 | 0 |
| Playing Cards | 82 | 23 | 23 | 0 |
| Enclosed Alphanumeric Supplement | 201 | 43 | 43 | 0 |
| Enclosed Ideographic Supplement | 64 | 10 | 10 | 0 |
| Miscellaneous Symbols and Pictographs | 768 | 131 | 131 | 0 |
| Ornamental Dingbats | 48 | 48 | 48 | 0 |
| Transport and Map Symbols | 120 | 14 | 13 | 1 |
| Alchemical Symbols | 128 | 12 | 12 | 0 |
| Geometric Shapes Extended | 120 | 107 | 107 | 0 |
| Supplemental Arrows-C | 171 | 171 | 171 | 0 |
| Supplemental Symbols and Pictographs | 256 | 14 | 14 | 0 |
| Chess Symbols | 102 | 102 | 102 | 0 |
| Symbols and Pictographs Extended-A | 128 | 8 | 0 | 8 |
| Symbols for Legacy Computing | 250 | 250 | 250 | 0 |
| CJK Unified Ideographs Extension B | 42,720 | 36,207 | 36,207 | 0 |
| CJK Unified Ideographs Extension C | 4,160 | 4,078 | 4,078 | 0 |
| CJK Unified Ideographs Extension D | 223 | 175 | 175 | 0 |
| CJK Unified Ideographs Extension E | 5,774 | 5,601 | 5,601 | 0 |
| CJK Unified Ideographs Extension F | 7,473 | 7,447 | 7,447 | 0 |
| CJK Unified Ideographs Extension I | 622 | 621 | 621 | 0 |
| CJK Compatibility Ideographs Supplement | 542 | 477 | 477 | 0 |
| CJK Unified Ideographs Extension G | 4,939 | 4,925 | 4,925 | 0 |
| CJK Unified Ideographs Extension H | 4,192 | 4,188 | 4,188 | 0 |
| CJK Unified Ideographs Extension J | 4,298 | 4,297 | 4,297 | 0 |
| Seal | 11,328 | 11,328 | 0 | 11,328 |

## Release validation (1.1)

- 301 Swift core tests passed; all 17 gated core modules have 100% executable-line coverage, including the new bounded font store/catalog. This does not claim 100% of app/UI code or all possible behavior.
- 521 regular native iOS 27 tests passed. The one opt-in whole-catalog audit is skipped during a normal run and passed separately with all exact final font assets installed.
- 35 Python generator/quality tests and 29 offline release-guard tests (228 assertions) passed; bundled/downloadable font validation passed.
- The installed keyboard extension on the iOS 27 iPhone simulator accepted cancel/retry, navigation during download, app-only controls and all three live downloads. Noto Tangsa and both large Jigmo subsets were inspected without insertion, then inserted as exact original supplementary scalars with Full Access off. Repeated switching between the large Han subsets kept the extension responsive.
- The app-only download page also passed on the dedicated iPadOS 27 simulator. Fresh phone Save-corner, landscape scalar/emoji and daily-keyboard captures passed. Native emoji on/off bitmap equality remains covered.
- Both font builders reproduced their reviewed outputs. All 61 published asset sizes and digests matched the app's pinned catalog. The canonical privacy page was published and read back from `https://docs.kitta.co/uniboard/`.

The local retained evidence is under ignored `build/QA/FontAudit/`: `Final-Units-Complete-iOS27.xcresult`, `Final-Code-Audit-iOS27.xcresult`, `Final-All-Packs-iOS27.xcresult`, `Final-Pad-Settings-iOS27.xcresult`, `Final-Captures-iOS27.xcresult`, and the core coverage report. App Store/Xcode Cloud status is checked separately from these local results.
