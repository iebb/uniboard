# iOS 27 Unicode preview font coverage

Measured on 2026-10-22 using an iPhone 17 Pro **simulator**, iOS 27.0 (24A5390f), and Uniboard's bundled Unicode 18.0.0 release catalog. The user-supplied `blocks.md` (survey 2026-10-20, 353 blocks) was a starting inventory, not an exhaustive font search or proof of native rendering.

| Native measurement | Visible scalar previews |
| --- | ---: |
| Tested assigned L/M/N/P/S characters | 172,351 |
| Missing using stock UIKit/Core Text fallback | 100,502 |
| Recovered by the original three bundled fonts | 14,285 |
| Recovered by build 36 with its optional fonts installed | 83,735 |
| Still missing in build 36 | 16,767 |
| Recovered by this completed optional font set | 100,502 |
| Still missing with all five packs installed | **0** |

This closes **every measured stock gap** for visible assigned scalar previews in this catalog on the tested runtime. It does not certify arbitrary-language spelling/shaping, every emoji sequence, physical-device parity, future Unicode drafts, or fonts in receiving apps. Inserted Unicode text is unchanged. This font update does not change the build already submitted to App Store review.

## The 16,767 gaps from build 36

| Block | Previously missing | Added source |
| --- | ---: | --- |
| Seal | 11,328 | Seal Sans, original unmodified AGPL-3.0 font |
| Egyptian Hieroglyphs Extended-A | 3,995 | NewGardiner: 3,427; UniHieroglyphica: 568 |
| Jurchen | 914 | UFS Tangut and Jurchen preview subset |
| Jurchen Radicals | 51 | UFS Tangut and Jurchen preview subset |
| Tangut | 8 | UFS Tangut and Jurchen preview subset |
| Tangut Supplement | 24 | UFS Tangut and Jurchen preview subset |
| Tangut Components Supplement | 115 | UFS Tangut and Jurchen preview subset |
| Archaic Cuneiform Numerals | 311 | Robin Leroy's Archaic Cuneiform Numerals |
| Cuneiform Numbers and Punctuation | 12 | Noto Sans Cuneiform Egg |
| Transport and Map Symbols | 1 | Noto Color Emoji, COLR subset |
| Symbols and Pictographs Extended-A | 8 | Noto Color Emoji, COLR subset |

Every scalar and its Unicode name, block and new font is listed in [build36-missing-characters.tsv](build36-missing-characters.tsv). The build 36 audit remains in [ios27-expanded.json](ios27-expanded.json); the completed production-resolver audit is [ios27-complete.json](ios27-complete.json). Stock evidence is [ios27-stock.json](ios27-stock.json).

The earlier omission was a source-selection limit, not proof that no font existed. The follow-up found real, OFL-licensed Egyptian outlines from NewGardiner and UniHieroglyphica, OFL-licensed Tangut/Jurchen outlines in Unicodia, Robin Leroy's cuneiform sources, and current Noto COLR emoji. Egyptology Extended is unnecessary and was not selected: the tested file's embedded notice mentions AI-generated supplemental glyphs and differs from the repository README's license description. Seal Sans is separately licensed and distributed unchanged with its full license and editable corresponding source.

## Minimal additions and optional packs

Only measured missing scalar ranges are advertised. The seven additions total **9,013,532 bytes**. Splitting Egyptian coverage between NewGardiner and a residual UniHieroglyphica subset saves about 1.4 MB compared with using UniHieroglyphica alone. The nine emoji require just **31,848 bytes**. No downloaded font is included in the app or keyboard binary; the four existing bundled fonts remain 11,706,408 bytes.

| Optional pack | Faces | Download bytes |
| --- | ---: | ---: |
| Historic scripts & symbols | 64 | 13,912,784 |
| Rare Han: B–F & I | 1 | 30,903,504 |
| Rare Han: G, H & J | 1 | 7,450,532 |
| Seal script | 1 | 5,793,816 |
| Latest emoji previews | 1 | 31,848 |
| Total | 68 | 58,092,484 |

The original 61 asset identities, hashes and URLs are unchanged. The seven new files use the separate [completion asset release](https://github.com/iebb/uniboard/releases/tag/fonts-1.1-20261022-complete); the [original asset release](https://github.com/iebb/uniboard/releases/tag/fonts-1.1-20261022) remains intact. Source commits, SHA-256 digests, advertised ranges, licenses, and the Seal source-archive hash are pinned in [font-subset-inputs.json](font-subset-inputs.json).

Noto is preferred where available. The completed downloads comprise 59 Noto faces, three Jigmo faces, one Fairfax HD face, one Archaic Cuneiform Numerals face, NewGardiner, UniHieroglyphica, a UFS preview face, and original Seal Sans. All modified OFL faces have unreserved Uniboard names and complete notices in every existing license name record. Seal Sans is copied byte-for-byte; its AGPL notice and 54,113,630-byte original editable source archive are provided alongside the download. Source archives do not count toward or need to be downloaded with runtime font packs.

Packs are explicit, app-only, off by default, removable, and usable offline in the keyboard without Full Access. The 64 MB aggregate download budget, 40 MB per-file limit, SHA verification, trusted release URLs, four-font LRU and bounded text-choice cache are unchanged.

## Emoji behavior

Only the nine missing standalone emoji, optionally followed by VS16, may use the new color subset: U+1F6D9, U+1FA8B, U+1FA8C, U+1FA8D, U+1FACC, U+1FADD, U+1FAEB, U+1FAF9, U+1FAFA. A system glyph still wins whenever available. Joined, modifier, flag and other supported emoji retain the system font. COLR glyphs are recognized as layered color artwork rather than rejected for lacking a base outline.

Current Noto's CBDT font could not be opened as a CGFont on the tested iOS runtime; its COLR font worked, including the final subset. A cmap claim alone would have missed that distinction. The native test retains a color bitmap of all nine final subset glyphs and checks both unqualified and VS16 forms, native controls, disabled behavior and cache limits. App emoji tiles/details and keyboard emoji keys/property previews use the same resolver.

## Native verification and reproduction

`Tests/UnicodeStockCoverageAuditTests.swift` walks every assigned visible graphic scalar and shapes exact production `displayText`, including dotted circles. Zero glyphs and LastResort runs count as missing. Invisible/default-ignorable characters and Braille blank are excluded. No font is registered globally or installed as a system font.

The final iOS 27 run passed all **21 font tests**, including the complete 172,351-scalar audit and actual SHA-verified installation of all 68 font files. The audit asserts zero remaining scalar gaps when all packs are installed. Unit checks also preserve enabled/disabled native emoji bitmaps and the four-face cache bound. The app UI redesign was in progress elsewhere; font validation used a clean copy of the existing v1.1 app plus only these font changes.

To reproduce, install `Scripts/requirements-fonts.txt` and run:

```sh
python3 Scripts/build_preview_font_downloads.py --cache /tmp/uniboard-font-sources --output /tmp/uniboard-font-subsets
python3 Scripts/build_combining_preview_font.py --cache /tmp/uniboard-font-sources --output /tmp/UniboardCombiningPreviews-Regular.ttf
python3 Scripts/validate_fonts.py
```

Two independent builder processes reproduced all 68 font files byte-for-byte. Normal builders verify committed hashes; catalog/manifest changes require explicit update flags. For the native complete audit, copy the 68 verified fonts to the app's `Documents/FontAuditAssets`, set `UNIBOARD_FONT_AUDIT=complete` and `UNIBOARD_FONT_AUDIT_INSTALL=1`, and run the opt-in test on iOS 27.

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
| Cuneiform Numbers and Punctuation | 128 | 12 | 12 | 0 |
| Archaic Cuneiform Numerals | 311 | 311 | 311 | 0 |
| Cypro-Minoan | 99 | 99 | 99 | 0 |
| Egyptian Hieroglyphs | 1,072 | 1 | 1 | 0 |
| Egyptian Hieroglyph Format Controls | 22 | 22 | 22 | 0 |
| Egyptian Hieroglyphs Extended-A | 3,995 | 3,995 | 3,995 | 0 |
| Anatolian Hieroglyphs | 583 | 583 | 583 | 0 |
| Gurung Khema | 58 | 58 | 58 | 0 |
| Tangsa | 89 | 89 | 89 | 0 |
| Kirat Rai | 58 | 58 | 58 | 0 |
| Medefaidrin | 91 | 91 | 91 | 0 |
| Beria Erfe | 50 | 50 | 50 | 0 |
| Ideographic Symbols and Punctuation | 12 | 12 | 12 | 0 |
| Tangut | 6,144 | 6,144 | 6,144 | 0 |
| Tangut Components | 768 | 768 | 768 | 0 |
| Khitan Small Script | 476 | 476 | 476 | 0 |
| Tangut Supplement | 33 | 33 | 33 | 0 |
| Tangut Components Supplement | 115 | 115 | 115 | 0 |
| Jurchen | 914 | 914 | 914 | 0 |
| Jurchen Radicals | 51 | 51 | 51 | 0 |
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
| Transport and Map Symbols | 120 | 14 | 14 | 0 |
| Alchemical Symbols | 128 | 12 | 12 | 0 |
| Geometric Shapes Extended | 120 | 107 | 107 | 0 |
| Supplemental Arrows-C | 171 | 171 | 171 | 0 |
| Supplemental Symbols and Pictographs | 256 | 14 | 14 | 0 |
| Chess Symbols | 102 | 102 | 102 | 0 |
| Symbols and Pictographs Extended-A | 128 | 8 | 8 | 0 |
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
| Seal | 11,328 | 11,328 | 11,328 | 0 |
