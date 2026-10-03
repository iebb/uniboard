# Uniboard storefront copy

Prepared 2026-10-03 for `ad.neko.uniboard`. English (U.S.) remains the primary language. Metadata is in `fastlane/metadata/en-US` and `fastlane/metadata/ja`, using plain UTF-8 text and one trailing newline. Strip that newline before uploading or measuring fields.

The English name stays **Uniboard: Unicode Keyboard**. It keeps the distinctive brand and states the core use. **Symbols, emoji & code points** adds everyday symbol and emoji use alongside precise lookup. Keywords add relevant terms for character maps, mathematics, arrows, Greek and Latin letters, accents, phonetic marks, UTF-8, ZWJ and offline copy/paste. Emoji and code points are already in the subtitle, so they do not consume keyword space. These choices come from implemented functionality; search volume has not been measured.

Apple lists title, subtitle, keywords, category and user behavior among search factors. It advises relevant terms, no duplicate words from the title/subtitle/category, no competitor names, and comma-separated keywords without spaces after commas. Promotional text supports conversion rather than search ranking. [Apple: App Store search](https://developer.apple.com/app-store/search/)

Apple's reference specifies **100 bytes** for keywords, so all locales are validated as UTF-8 bytes. Name/subtitle limits are 30 characters, description is 4,000 characters, and promotional text is 170 characters. Descriptions also inform web search results, so the opening sentence naturally explains Unicode, symbols and the keyboard rather than padding the description with keywords. [Apple: platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/), [Apple: creating your product page](https://developer.apple.com/app-store/product-page/)

| Field | English (U.S.) | Japanese | Limit |
| --- | ---: | ---: | ---: |
| Name | 26 characters | 22 characters | 30 characters |
| Subtitle | 28 characters | 13 characters | 30 characters |
| Keywords | 97 UTF-8 bytes | 99 UTF-8 bytes | 100 UTF-8 bytes |
| Description | 2,819 characters | 1,432 characters | 4,000 characters |
| Promotional text | 167 characters | 103 characters | 170 characters |
| Release notes | 188 characters | 112 characters | 4,000 characters |

Use **Utilities** as the primary category and **Reference** as the secondary category. The keyboard is a character-input utility, while the containing app provides a searchable Unicode catalog with names, blocks and encoding details. Neither category name consumes keyword space. Reassess category choice using actual acquisition and conversion after launch. [Apple: choosing a category](https://developer.apple.com/app-store/categories/)

Japanese storefront copy is useful for a Japanese-speaking audience looking for symbols and code points. It expressly says the interface, Unicode character names/descriptions and name searches are English. Storefront localization does not add a binary language. Keep the app's advertised interface language English. [Apple: localize app information](https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information/)

`release_notes.txt` documents the first release for reuse and internal review. Apple does not offer “What's New” for an initial version; do not upload that field for 1.0.0. [Apple: platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

## Claims and implementation evidence

| Storefront claim | Implementation evidence |
| --- | --- |
| Search names, aliases, informative notes, block names, hex/decimal code points and literal characters | `Shared/UnicodeCatalog.swift`; app search in `App/ContentView.swift` |
| Browse the complete block list and scroll through assigned characters | `App/BlocksView.swift`, keyboard block view and catalog pagination |
| Insert the original scalar or full emoji sequence at the host cursor; hold or sustained pointer hover opens a scrollable properties panel without insertion; top-right repeating backspace | `Keyboard/KeyboardViewController.swift` |
| Favorites, recents and edition/order preferences stay local to the app or keyboard | `Shared/CharacterStore.swift`, `App/CatalogPreferences.swift`, `App/SavedView.swift`, keyboard model |
| Copy characters or complete emoji, combine text in a scratchpad and inspect code points, names, ages, properties and encoding details | `App/CharacterDetailView.swift`, `App/EmojisView.swift` |
| Browse official fully qualified emoji; preserve ZWJ, variation selectors, flags, keycaps and skin-tone sequences | `Shared/EmojiCatalog.swift`, both `EmojiCatalog-*.json` resources, `App/EmojisView.swift`, keyboard emoji grid |
| Default to newest Unicode Age across all assigned characters; offer oldest/code-point order; order emoji by Emoji introduction version | `Shared/UnicodeCatalog.swift` ordered ranges/search and `Shared/EmojiCatalog.swift` |
| Switch offline between Unicode 18 latest release and Unicode 19 draft, remembering choices separately | `UnicodeEdition`, both resource sets, `App/CatalogPreferences.swift`, keyboard model |
| Offline catalog; no account or Full Access needed | `Keyboard/Info.plist` has `RequestsOpenAccess=false`; no networking SDK/runtime requests; `App/SetupView.swift` |
| No typing sent to a server | App/keyboard runtime is local; `Shared/PrivacyInfo.xcprivacy` declares no collected data and no tracking |
| Latest official release and draft at build time; names/assignments and iOS font support may differ | `Scripts/generate_unicode.py`, `Shared/Resources/UnicodeSources.json`, `App/SetupView.swift` |

These references identify implemented behavior. Confirm the new app and system-keyboard flows with runtime QA before submitting the matching binary; SDK typechecking alone is not device proof.

“Code point” is the Unicode term for an integer position in its codespace; it differs from the shape drawn by a font. A block organizes a continuous range and may include unassigned positions. Names and aliases identify characters; descriptive NamesList annotations are informative. The copy therefore avoids claims about supplying fonts, displaying every draft character, inserting surrogate code units, or treating a draft edition label as a character introduction version. The Emojis tab now provides the full official fully qualified emoji set for each bundled snapshot and inserts each entry as a complete sequence. [Unicode glossary](https://www.unicode.org/glossary/), [Unicode Character Database](https://www.unicode.org/reports/tr44/)

## Edition and emoji wording

The bundled snapshots are Unicode **18.0.0 latest release** and **19.0.0 development draft**. At this refresh, each contains 310,341 assigned scalars and 3,963 fully qualified emoji; assigned character lists may match while draft development is in progress. Do not advertise “Unicode 19-only characters” or “Emoji 19”. Catalog edition, a scalar’s official Unicode Age and an emoji’s introduction version describe different facts.

“Newest first” means global ordering of assigned characters by Unicode Age, including outside selected discovery collections. In Emojis it means Emoji introduction version, with component Unicode ages shown separately. A newer catalog does not supply a font. Hold or sustained pointer hover exposes textual names, available descriptions and detailed properties even when iOS renders a missing glyph or splits an emoji sequence. Claims about readable metadata are supported; claims that every glyph renders are not.

Website titles, descriptions, guide and MobileApplication structured data reflect both character lookup and complete emoji input. Keep the guide’s precise lookup examples and public support contact. After changing the inline JSON-LD, regenerate the exact CSP script hash in `website/_headers` before deploying; no executable or analytics script is needed.

## Screenshot order and captions

Use real captured app/keyboard UI with short benefit captions:

1. **Type it where you're writing** — the enabled system keyboard inserting a character or full emoji in the test editor.
2. **Find the character you need** — a useful search with visible names, code points and results.
3. **Explore complete emoji** — genuine joined emoji results and an exact full-sequence insertion.
4. **See what a glyph means** — a real long-hold properties panel for a font-unsupported character, with name, description, age and UTF-8.
5. **Choose your Unicode edition** — the release/draft selector and newest-first character browser.
6. **Browse and save your favorites** — a block grid or populated saved collection.

For Japanese captions: **入力中にそのまま使える**, **欲しい文字をすぐに検索**, **絵文字をシーケンスごと入力**, **表示できない文字も詳しく**, **Unicodeの版を選べる**, **文字を探してお気に入りに**. Keep the captured English interface visible and unchanged.

The first screenshots should prove direct insertion and search. Existing artwork remains sourced from real captures; recapture the revised edition controls, emoji browser and long-hold panel before advertising those visuals. Icons and screenshots should communicate the same real experience; do not use a mock keyboard or promise unsupported features. [Apple: creating your product page](https://developer.apple.com/app-store/product-page/), [Apple: accurate metadata](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata)

After release, compare App Store Search acquisition and product-page conversion for meaningful periods. Test icon or screenshot variants with Apple's product page optimization, then update metadata in a subsequent reviewed version based on observed behavior. This is a first-launch intent strategy, not a measured ranking result. [Apple: creating your product page](https://developer.apple.com/app-store/product-page/)
