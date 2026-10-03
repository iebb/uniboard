# Uniboard storefront copy

Prepared 2026-10-03 for `ad.neko.uniboard`. English (U.S.) remains the primary language. Metadata is in `fastlane/metadata/en-US` and `fastlane/metadata/ja`, using plain UTF-8 text and one trailing newline. Strip that newline before uploading or measuring fields.

The English name stays **Uniboard: Unicode Keyboard**. It keeps the distinctive brand and states the core use. **Symbols & special characters** adds the everyday need in the subtitle. Keywords add relevant terms for code-point lookup, character maps, emoji, mathematics, arrows, Greek letters, accents, phonetic marks and offline copy/paste. These choices come from shipped functionality; search volume has not been measured.

Apple lists title, subtitle, keywords, category and user behavior among search factors. It advises relevant terms, no duplicate words from the title/subtitle/category, no competitor names, and comma-separated keywords without spaces after commas. Promotional text supports conversion rather than search ranking. [Apple: App Store search](https://developer.apple.com/app-store/search/)

Apple's reference specifies **100 bytes** for keywords, so all locales are validated as UTF-8 bytes. Name/subtitle limits are 30 characters, description is 4,000 characters, and promotional text is 170 characters. Descriptions also inform web search results, so the opening sentence naturally explains Unicode, symbols and the keyboard rather than padding the description with keywords. [Apple: platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/), [Apple: creating your product page](https://developer.apple.com/app-store/product-page/)

| Field | English (U.S.) | Japanese | Limit |
| --- | ---: | ---: | ---: |
| Name | 26 characters | 22 characters | 30 characters |
| Subtitle | 28 characters | 12 characters | 30 characters |
| Keywords | 98 UTF-8 bytes | 96 UTF-8 bytes | 100 UTF-8 bytes |
| Description | 1,720 characters | 938 characters | 4,000 characters |
| Promotional text | 159 characters | 87 characters | 170 characters |
| Release notes | 198 characters | 116 characters | 4,000 characters |

Use **Utilities** as the primary category and **Reference** as the secondary category. The keyboard is a character-input utility, while the containing app provides a searchable Unicode catalog with names, blocks and encoding details. Neither category name consumes keyword space. Reassess category choice using actual acquisition and conversion after launch. [Apple: choosing a category](https://developer.apple.com/app-store/categories/)

Japanese storefront copy is useful for a Japanese-speaking audience looking for symbols and code points. It expressly says the interface, Unicode character names/descriptions and name searches are English. Storefront localization does not add a binary language. Keep the app's advertised interface language English. [Apple: localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)

`release_notes.txt` documents the first release for reuse and internal review. Apple does not offer “What's New” for an initial version; do not upload that field for 1.0.0. [Apple: platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

## Verified claims

| Storefront claim | Implementation evidence |
| --- | --- |
| Search names, aliases, informative notes, block names, hex/decimal code points and literal characters | `Shared/UnicodeCatalog.swift`; app search in `App/ContentView.swift` |
| Browse the complete block list and scroll through assigned characters | `App/BlocksView.swift`, keyboard block view and catalog pagination |
| Insert Unicode at the host app's cursor; hold to inspect/save | `Keyboard/KeyboardViewController.swift` |
| Favorites and recents stay in separate app/keyboard collections | `Shared/CharacterStore.swift`, `App/SavedView.swift` |
| Copy characters, combine text in a scratchpad and inspect decimal/UTF-8 metadata | `App/CharacterDetailView.swift` |
| Offline catalog; no account or Full Access needed | `Keyboard/Info.plist` has `RequestsOpenAccess=false`; no networking SDK/runtime requests; `App/SetupView.swift` |
| No typing sent to a server | App/keyboard runtime is local; `Shared/PrivacyInfo.xcprivacy` declares no collected data and no tracking |
| Latest official draft at build time; names/assignments and iOS font support may differ | `Scripts/generate_unicode.py`, `Shared/Resources/UnicodeSources.json`, `App/SetupView.swift` |

“Code point” is the Unicode term for an integer position in its codespace; it differs from the shape drawn by a font. A block organizes a continuous range and may include unassigned positions. Names and aliases identify characters; descriptive NamesList annotations are informative. The copy therefore avoids claims about supplying fonts, displaying every draft character, inserting surrogate code units, or providing a complete multi-code-point emoji picker. [Unicode glossary](https://www.unicode.org/glossary/), [Unicode Character Database](https://www.unicode.org/reports/tr44/)

## Screenshot order and captions

Use real captured app/keyboard UI with short benefit captions:

1. **Find the character you need** — character search showing a useful query and visible results.
2. **Type it where you're writing** — the enabled system keyboard inserting a character in the app's test editor.
3. **Browse every Unicode block** — the block list and a recognizable arrow/math block.
4. **Keep favorites close** — a populated saved collection.
5. **Get the details** — an informative character detail with name, code point and UTF-8 bytes.

For Japanese captions: **欲しい文字をすぐに検索**, **入力中にそのまま使える**, **Unicodeブロックを一覧で**, **お気に入りを手元に**, **文字の情報を詳しく**. Keep the captured English interface visible and unchanged.

The first screenshots should prove search and direct insertion. Icons and screenshots should communicate the same real experience; do not use a mock keyboard or promise unsupported features. [Apple: creating your product page](https://developer.apple.com/app-store/product-page/), [Apple: accurate metadata](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)

After release, compare App Store Search acquisition and product-page conversion for meaningful periods. Test icon or screenshot variants with Apple's product page optimization, then update metadata in a subsequent reviewed version based on observed behavior. This is a first-launch intent strategy, not a measured ranking result. [Apple: creating your product page](https://developer.apple.com/app-store/product-page/)
