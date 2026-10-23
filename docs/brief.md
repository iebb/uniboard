# Uniboard — multilingual gaps and font exploration brief

Status: implementation handoff, 2026-10-23. Existing name, native app, keyboard and storage retained. Final design and copy integrated below; ready for developer implementation.

## Decision and audience
For multilingual writers, linguists and people exploring Unicode: deliver truthful character/font comparison and on-demand Google Fonts discovery first. Do not market this increment as a keyboard for every language. No new sign-in, backend, sync or analytics. User preferences and downloads remain on-device under existing storage behavior; reinstallation is not promised to restore them. Network is used for explicit catalog/font retrieval only, never typed text. No AirBuild service integration required for this increment. Google Fonts is explicitly requested by the user; retain existing pinned font-pack sources.

Delivery: working Simulator demo plus repeatable tests. No TestFlight or App Store submission authorized by this request.

## What exists (read-only source audit)
- Offline Unicode palette and customizable literal keyboard. `Shared/KeyboardAlphabet.swift` supplies Latin/Greek/Cyrillic base layouts for 20 languages. `Keyboard/KeyboardViewController.swift` inserts strings, not styled text or full IME conversions.
- Unicode 18 default, 17/16 historical and 19 draft editions documented. Scalar search and separate sequence-aware emoji catalog; this is not whole-language typing coverage.
- `App/FontPackDownloadsView.swift` already has an iOS font picker and curated downloads. `Shared/CustomFontStore.swift` limits selected/imported fonts to 16; this preference/import limit must not silently limit enumeration in the new comparison grid.
- `App/CharacterDetailView.swift` displays one resolved preview or text/emoji pair, not the requested all-matching-font comparison grid.
- `Shared/UnicodeFontSupport.swift` already checks coverage, missing glyphs, outlines and some emoji sequences. Reuse where sound; scalar coverage is not proof of contextual shaping.
- Download metadata in `Fonts/DownloadableFonts.json`; existing sources are pinned iebb/uniboard and iebb/emojifonts GitHub releases, with checksum validation, queue/progress/cancel/retry. No Google Fonts family-name catalog currently.
- Historical `docs/font-pack.md` audit reports 16,767 visible scalar preview gaps even with optional packs. This is a historical result, not a newly run test or a current-device total.

## What is missing for broad world-language support
1. Input methods: language-specific layouts, dead keys, transliteration, composition/conversion and candidate selection (e.g. Chinese/Japanese/Korean/Indic), plus language-aware correction and word boundaries. A character palette is useful but not a daily typing IME.
2. RTL and mixed-direction editing: Arabic/Hebrew, punctuation, numbers, cursor/deletion behavior; contextual shaping and combining-mark placement.
3. Whole user-perceived characters: combining sequences, variation selectors, emoji joiners, Indic conjuncts; preserve exact text and test deletion/insertion without corrupting sequences. Do not equate code points with characters or silently normalize entered text.
4. Language/script discovery and customization: language-aware search aliases, script groupings, reusable custom layouts and later validated language packs.
5. Coverage governance: explicit Unicode versions, draft labels, verified device/font coverage and accessible previews. Some writing systems/characters lack suitable encoded text or available fonts; no literal all-world-language guarantee.
6. Real language validation: representative script samples, native-reader review and target-app/device testing. Fonts and screenshots alone cannot validate an input method.

Only font exploration below is implementation scope now. Language engines are roadmap work requiring separate prioritization, not hidden inside this feature.

## Three-screen increment
1. Existing Character detail → Fonts for This Character: retain existing metadata/actions and add a paged/lazy comparison grid. Each tile shows the same exact selected text in one verified font face, family/style and source (System, Included, Downloaded). Count faces consistently. Search local names, stable sorting and loading/no-match/error states. Enumerate every face visible to this process through supported public APIs, not just the 16 saved choices. Never claim access to every private/device font.
2. Google Fonts: searchable family names, style selection and download status. Cached catalog remains usable offline; explicit download only. No bulk or preview-triggered downloads. Prefer Noto/script information for discovery but do not infer character support from a family name or Google subset metadata.
3. Font detail/management: style/sample, source/license, download size where known, progress/cancel/retry and Remove Download for user-downloaded files only. Merge with existing download management where practical rather than duplicating stores.

## Data and platform constraints
- Choose a versioned, complete Google Fonts catalog generated from Google's public fonts repository and metadata, with pinned file locations/license records. Name search is local against that catalog; show snapshot date and a reproducible refresh path. Do not scrape undocumented endpoints or add an API credential dependency silently. Google's official Developer API requires an API key; that remains an alternative only if later justified.
- Download compatible font files over HTTPS, enforce size bounds, validate expected identity/integrity where available, and retain license notices. Reject malformed files without breaking existing fonts. Extend existing verified-download pipeline where possible.
- Process-visible font enumeration is not system-wide install permission. App-local downloads are not fonts installed for arbitrary other apps.
- Keyboard inserts Unicode text; receiving app controls typography. Use Camo's persistent note: “Fonts change the preview here. Other apps choose how inserted text looks.”
- Verify font's own face actually supplies the preview. Fallback rendering must never appear as a match for the named face. Treat invisible controls, combining marks and text/emoji presentations explicitly; sample scaffolding such as a dotted circle must not be copied.
- Downloads occur in containing app. Verify registration separately in app and keyboard using existing sharing path; do not promise keyboard availability solely from app registration. Preserve existing Full Access behavior, do not introduce a new permission requirement for basic typing.
- Enumeration, coverage checks and previews are lazy, cancellable and cached by text/font identity/catalog generation. Download/removal invalidates relevant coverage. Never load the complete worldwide font collection into the keyboard process.

## Observable acceptance criteria
1. On the test device, grid's checked set equals the full public process-visible inventory (plus successfully registered included/downloaded faces); no top-N or 16-choice truncation. UI distinguishes checking from complete results and reports face counts consistently.
2. For Latin, Greek, Cyrillic, Arabic, an Indic combining sequence, CJK supplementary-plane text, emoji presentation/ZWJ sequence, combining mark and invisible control, evidence records actual tested coverage and failures. No fallback false-positive tiles. Unsupported/unknown is explicit, not a blank success.
3. Copy/keyboard insertion preserves exact original Unicode sequence regardless of preview face; test at least two host apps. Document host font differences and keyboard-ineligible fields honestly.
4. Search by known Google family name returns catalog results; download a not-yet-present face, register it, and see its verified previews after relaunch and offline. Missing family, unavailable network, cancellation, corrupt download and registration failure have distinct recoverable states.
5. Download/removal refreshes grid without losing favorites/custom layouts or deleting system/bundled fonts. Existing font packs continue to work. Tests cover retained cache and no silent bulk download.
6. Verify downloaded-font use separately in containing app and keyboard, with existing Full Access on/off behavior noted. Basic typing remains functional without network access. No typed text is transmitted.
7. Grid remains scrollable/responsive while scanning; check large text, VoiceOver names, light/dark appearance, keyboard memory behavior and cancellation. Report tested device and measured limitations, not fabricated universal performance guarantees.
8. Preserve current app behavior and storage; run relevant native font tests and distinguish environment-specific assumptions from actual rendering failures before declaring green.

## Copy/design
- Copy: `docs/font-copy.md` (Camo, message 71). Adopt exact state labels subject to this scope; optional actions do not expand it.
- Final design: `design/design.md` (Colo, message 82, attachment c80f6a7a-2c85-46da-94ed-da30d4738d25). Implement this alongside `docs/font-copy.md`. Mockups in `design/mockups/` are illustrative, never test evidence.
- Keep five existing tabs. Character detail pushes View Fonts → local verified face grid; existing Settings → Preview Fonts → Font Downloads gains Browse Google Fonts without replacing curated packs/imports. Shared font detail handles specimen, style selection, license and removal.
- Grid: two columns normally, one at accessibility sizes; adaptive wider layouts, system grouped surfaces/type/tint, full face names and provenance, persistent host-app typography disclaimer. Count faces, deduplicate aliases; partial scan count never appears final. Tapping a tile inspects, never applies a global font.
- Downloads: one explicitly selected style/file per action, no download-all and no file fetch to draw a catalog preview. Preserve actual variable-font file identity; no variable-axis editor. Show snapshot date, license, exact known size, cancel/retry/preparing states and explicit removal confirmation. Existing 16-import preference limit and 40 MiB per-file cap stay for this pass, with an actionable limit message; neither may truncate local font enumeration. If a requested font exceeds a cap, report it instead of silently excluding or promising universal availability.
- Invisible placeholders are not coverage evidence. Preserve text/emoji choice, dotted-circle explanations and original sequences; no fallback false positives. Keyboard availability is separately verified; otherwise label Available in the app only.
- Product scope and acceptance checks above govern; design does not authorize IMEs, new accounts, networking from the keyboard or additional permission requirements.
- No rename or new branding; no new website work in this increment.

## Research shaping decisions
Search/fetch service was unavailable (credit limit); official pages and comparable app were read with browser instead.
- Apple Custom Keyboard guide: custom keyboards insert unattributed text; host restrictions and multilingual input responsibilities. This is an archived guide, so current-device behavior must be verified: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- Google Fonts Developer API: family/style/subset metadata and downloadable file URLs, API key required; subset metadata alone not a per-character support guarantee: https://developers.google.com/fonts/docs/developer_api
- Google Fonts FAQ: commercial redistribution allowed under each font's license, public GitHub downloads, Noto coverage: https://fonts.google.com/faq and https://github.com/google/fonts
- Noto comparison: organized across more than 1,000 languages and 150 writing systems, supporting script-oriented discovery, not a promise of all languages: https://fonts.google.com/noto
- Unicode segmentation: user-perceived grapheme clusters differ from scalar records: https://www.unicode.org/reports/tr29/
- UniChar comparison: character search, categories, favorites and font previews are established palette capabilities; these do not substitute for language-specific typing engines: https://apps.apple.com/us/app/unichar-unicode-keyboard/id880811847
