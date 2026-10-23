# Uniboard — character font exploration design

23 October 2026. Colo. Implements `docs/brief.md` three-screen increment; exact copy in `docs/font-copy.md` is authoritative. Keep existing name, five tabs, native app, keyboard, storage and fixed font packs. No new accounts, backend, analytics or IME. This is an implementation-ready SwiftUI spec, not a claim of shipped features.

## Direction and references

Extend `App/Design.swift`: native semantic grouped surfaces, system typography, current system tint. Do not port PrepaGo's branding or colors into Uniboard. Source review of CharacterDetailView, FontPackDownloadsView, SetupView and ContentView establishes current navigation; repository marketing captures are historical styled composites, not evidence of the current simulator. Studied https://fonts.google.com/ in a browser with identical preview text across families: borrow comparable specimens, explicit family/style names and searchable catalog, not its desktop sidebar. Attach the reference capture. Google Fonts lookup/catalog technology follows product/developer decisions, not the HTML mockup.

Key reasons: a two-column grid compares glyphs without making names illegible; exact face attribution prevents misleading fallback matches; downloads stay separate from locally available previews so browsing does not imply supported or installed. Font specimens in the artifact use actual Noto Sans, Noto Serif, Roboto and Lora files with license notices. Availability, counts and progress are illustrative, not the user's device inventory.

## Design tokens

Prefer existing semantic UIKit colors through SwiftUI. Expected default light/dark values below are visual baselines, not overrides of Increased Contrast:
- Background `.systemGroupedBackground`: #F2F2F7 / #000000.
- Cards `.secondarySystemGroupedBackground`: #FFFFFF / #1C1C1E.
- Search/control fill `.tertiarySystemFill` equivalent: #E5E5EA / #2C2C2E.
- `.primary` labels #1C1C1E / #FFFFFF; `.secondary` #636366 / #AEAEB2.
- Preserve app's single system-blue accent. Links use system `.tint`; rendered normal text must meet 4.5:1. For custom small text on plain white, contrast-safe blue #0066CC / #6CB5FF; native control appearances may use their accessibility-aware system tint. No new brand accent. Filled custom CTA uses #0066CC + white (light) or #6CB5FF + #001A33 (dark).
- Error semantic #B42318 / #FFB4AB. Successful availability uses checkmark + text, not a new decorative green. Never use red to mean a font does not contain a character: absent coverage is not a system error.
- Preserve existing missing-glyph and ConScript semantics in original character preview; do not tint every comparison tile red because the stock font cannot draw it.
- 16-point screen inset, 20 between major groups, 12 grid gap, 12 tile padding, 8 between title/style/source, 4 between related metadata. Card/tile radius 12; large existing character hero radius 16; no shadows/gradients.
- System text styles: screen `.title2` 22 semibold (long title can wrap); native navigation inline `.headline` 17 semibold; section `.title3` 20 semibold; font name `.subheadline` 15 semibold; body 17 regular; explanatory text `.footnote` 13 regular; style/source `.caption` 12–13 regular; codepoints body/footnote monospaced. Mockup 28-point title is illustrative; in production use Dynamic Type `.title2` for the long grid title.
- Glyph comparison: 64-point actual face Regular unless the tile itself represents another style, baseline area at least 96 high. Use natural font ascent/descent and 12-point clear padding; no outline clipping. The glyph is not UI text, but scales with preview size and accessibility appropriately. Native labels use system font, never the specimen font.
- Minimum 44×44 actions; row >=52 high. No forced tile height at large type. Body/text sizes are Dynamic Type, not fixed frames.

## Navigation and scope

Existing Character sheet's NavigationStack gains a `View Fonts` navigation row after Copy/Save/Scratchpad and before notes/properties. Existing actions and text/emoji variants remain untouched. Row title View Fonts, subtitle “Compare fonts available to Uniboard.” Whole row is tappable; chevron. It pushes the grid within that sheet; Back returns without resetting scroll or original actions; Done dismisses the sheet as before.

Keep current Settings → Preview Fonts → Font Downloads. Add Browse Google Fonts as a leading navigation row in the existing downloads screen; keep Extra Unicode Fonts, curated packs, Your Fonts, Add Font File, Use Installed Font and licenses. Do not replace a functioning store with a new isolated one. From grid, Browse Google Fonts opens the same catalog with the selected text held locally as inspection context, NOT transmitted to a query or server. No sixth tab.

Font detail is reused from grid tile or Google catalog row. Grid route starts with local supported face; catalog route starts with selected family's style list. Keep back state/query. Downloads only in containing app. Do not introduce network download UI inside the keyboard extension. If an existing keyboard inspector links to this destination, use “Open Uniboard to Download Fonts”; preserve host/open-URL limitations and do not promise a link works until developer verifies it.

## 1. Fonts for This Character

Header: compact selected-character panel, name and exact codepoints; panel glyph 44, with name 17 semibold and codepoints 13 monospaced. Long names wrap. The display sample must preserve original text and current Text/Emoji choice. Retain special explanations for invisible/combining/control characters. Screen heading Fonts for This Character (use narrower Fonts With This Character only if implementation establishes scalar coverage, not actual shaping).

Persistent note immediately below heading: “Fonts change the preview here. Other apps choose how inserted text looks.” Then native searchable field “Search available fonts”. This searches only locally available/registered face names, case-insensitive; changing text does not trigger font-file download. Search remains usable during scanning. No filter chips or sort menu necessary: stable family name then style then unique PostScript identifier order.

Scanning: spinner and Checking available fonts… above partial grid; append verified faces in stable order. Do not display a final-looking total until complete. Progress may say “{checked} of {total} checked” only if actual inventory/checked counts exist. On completion “1 font available” / “{count} fonts available”; count FACES, not families. All enumerated public process-visible faces are examined, not first 16 saved/imported preferences. Pagination/lazy view is presentation only, not inventory truncation. Keep scan work off the main UI thread and cancellable when navigating away.

Grid uses `LazyVGrid`: 2 columns when usable width >=320, 1 below or Dynamic Type accessibility sizes; on wide screens adaptive minimum 160 with 12 spacing and maximum content width 960 (normally 3–5 columns). Original character sheet max width 620 remains for its original content; font comparison can use available width without changing the surrounding app navigation. Each tile is a single Button with actual glyph, family 15 semibold (wrap), style 13, source 12: System, Included or Downloaded. Deduplicate face identities; do not show duplicate rows for aliases. Distinct styles appear as distinct tiles. An installed/imported source should not be mislabeled Included; use existing verified provenance, or neutral “Available” when source is unknown rather than inventing it.

Font rendering MUST use the named face, with final attributed run verification. A fallback glyph must never qualify its requested face. Coverage metadata is just a prefilter. Do not apply `UnicodeFontSupport.font(for:)` as the tile renderer since it chooses fallback. Glyph outlines are not required for a legitimate blank/space or color glyph. No simplistic “nonempty bitmap” validation. Developers own exact technical method, design requires truthful matches.

Tap tile → font detail with enlarged preview and source. Do not select a global font or alter keyboard text by tapping. No checkmarks indicating global preview selection. Local compare is not persistent user configuration unless existing action explicitly changes preferences.

Below grid: Browse Google Fonts row. It is a navigation option, never “Find guaranteed support”. Preserve query and original character when returning; after successful registration/removal invalidate affected matches and rescan without losing other app state.

### Special text handling

- Exact original sequence is the inspected content. Copy/insert never silently normalizes it.
- Combining mark: use dotted circle only as visible scaffold. The scaffold can use a fallback, but the tested mark must be supplied by the named face; label this explicitly, and do not include the circle in copy.
- Invisible/control characters: show neutral dotted placeholder and exact name/codepoint, keeping existing “This character is invisible…” explanation. Do not imply every font supports a control just because its placeholder appears. An honest not-applicable/unknown preview is distinct from no matching visible glyph.
- Text/Emoji presentation: retain selected variation selector; user switching presentation starts a separately keyed check. Never count support for one as support for the other.
- Shaping sequences/ZWJ: eligibility is for exact inspected sequence, not individual scalar union. Where complete rendering cannot be established, do not include false positives; offer “Couldn’t check font support” only for a real check failure, otherwise explicitly scope the coverage claim. No claim about the whole language.
- RTL/mixed script: glyph preview uses natural script direction; family names and codepoints remain direction-isolated; do not reorder Unicode data. VoiceOver order follows the logical UI.

## 2. Google Fonts catalog

Native pushed screen titled Google Fonts. Searchable field Search fonts by name. Intro “Find a font and download it when you need it.” Scope note “Downloaded fonts are for use in Uniboard. They aren’t installed for other apps.” Always visible near top, not hidden solely in a tooltip. Show actual catalog snapshot date below note; this is the versioned bundled/cached complete catalog from product brief, not a fresh API request on every keystroke.

Use grouped list of family names, each row >=64 with name 17 semibold, available style count or selected style 13 secondary, trailing chevron/status. A family tap opens font detail; explicit Download control may exist when selected style is already unambiguous. No downloading binary files merely to draw catalog samples. Prefer text names and existing metadata before download; specimen only if an already local face or a bundled/licensed preview is available. Never display system fallback under a remote family name as though it is that family's sample.

Search is local over catalog family names; sorted stable A–Z, preserving exact names. Clear search retains scroll appropriately. Catalog provides metadata, not per-character proof. Noto/script hints can appear as secondary metadata, not Supported badges or full-language counts. Online update/loading is explicit if existing refreshed catalog flow requires it, with snapshot date retained for saved results. No automatic downloads from search, navigation, scrolling or preview selection. No Download All for Google catalog; existing curated-pack bulk action remains unchanged.

Rows show distinct state when a specific style is selected: Download; Waiting to download… + Cancel if supported; Downloading… percent + Cancel; Preparing font…; Downloaded. Percent only with known total. Size shown when actual declared byte count exists, else omit; never invent. Downloaded does not mean verified for selected character or registered in the keyboard.

Do not add new accounts, API-key form or system-install permission. Retain license access and existing file validation/limits. No purchase affordance or monetization.

## 3. Font detail and management

Native title actual family name; subtitle selected style and source. If entered from local grid, enlarged specimen uses the verified face, 144-point nominal with 32 padding and min 220 high, naturally growing for tall glyphs. Exact character/sequence codepoints below; persistent preview note. The existing Copy Character action remains on Character detail; no redundant new “apply font” or formatted-copy action.

Catalog entry: Styles group listing exact downloadable faces/variants as radio-style selected rows, default Regular if available, otherwise first named style. Selection changes download target, not global text style. Each row has actual style name and size when known. No implicit whole-family download. Footer button Download Style; if only one style, Download with adjacent explicit style label is acceptable. Do not expose arbitrary variable axes as new controls in this increment; preserve exact downloadable variable-file identity in metadata. If one binary serves several instances, do not pretend selecting each instance downloads a different file.

Before download: Preview group is informational “Download this style to preview it here” (Camo can refine) rather than a false glyph in a system font. If opened with a character context, preserve it locally; do not claim character support before checking installed face. After successful registration: actual specimen or “Preview unavailable” / “This font couldn’t display the character.” A legitimate download that does not contain the character is not a corrupt file and must not be deleted automatically.

License group: Google Fonts source label, actual license name/link and retained full license text in a selectable native sheet. Show font metadata/file size when known; no fake size. File version/catalog snapshot may be secondary. Existing downloaded management can be reused rather than a new storage model.

Download state controls: while active show ProgressView and state, Cancel 44 target. At registration show Preparing font… and no false Downloaded badge. Success Downloaded with checkmark; if keyboard registration is not verified, say Available in the app only, rather than promise keyboard support. Failure is inline with Try Again, preserving selection. Do not block navigation or dismiss unexpectedly when done.

Remove Download exists only for user-downloaded assets. Use destructive text row separated from safe actions by 20. Confirmation: Remove {font name}? / This removes the downloaded font from Uniboard. You can download it again later. / Remove Download, Cancel. Include style in displayed identity when only one style/file is removed. Never offer removal for System/Included. Preserve shared-file references/other styles and existing limits; UI should not suggest removing unrelated fonts. After removal update available grid and return to Download state. Losing availability must not alter user characters, favorites or layouts.

## State matrix

- Local scan loading: Checking available fonts…; partial rows are provisional only in COUNT, each visible tile itself already verified. Do not show 0 as final while work continues.
- Scan complete, no matches: No matching fonts / None of the fonts available here can preview this character. / Browse Google Fonts.
- Search no matches: No matching fonts / Try a different font name. / Clear Search. This is not an unsupported-character conclusion.
- Scan error: Couldn’t check font support / Try again in a moment. / Try Again. Retain verified results if available, clearly mark incomplete scan.
- Preview failure after font removed/unregistered: Preview unavailable / This font couldn’t display the character. Recheck; do not silently show fallback.
- Catalog first load: Loading fonts… only if actual asynchronous load. Saved catalog may render immediately offline; Show saved results with its snapshot date where stale refresh fails. Do not erase usable local fonts/catalog on network failure.
- Catalog no name results: No fonts found / Try a different font name. / Clear Search.
- Catalog unavailable: Couldn’t load Google Fonts / Try again in a moment. / Try Again. Only use No internet connection when confirmed.
- Download ready/queued/progress/preparing/success/cancelled: exact Camo strings. Cancel ends cleanly without deleting already valid fonts.
- Download failure: Couldn’t download this font / Try again in a moment. / Try Again.
- Invalid file/registration failure: Couldn’t use this font / The downloaded file couldn’t be loaded. / Try Again. No invalid face appears available.
- Storage/quota/size limit: actionable message from actual limit, not generic no-fonts state. Current import limit 16 and per-file cap 40 MiB remain unless developer/product explicitly revise. Comparison inventory is NEVER limited to 16.
- No success confetti, toast stack, sign-in state or permission upsell; none is needed for this feature.

## Accessibility and symbols

Every comparison tile is one accessibility element/button: “{font name}, {style}, preview of {character name}”; value/source separately if useful. Do not have VoiceOver read a bare unknown glyph or repeated codepoints for each decoration. Keep font name wrapping; no 1-line ellipsis hiding distinction between faces. At accessibility sizes use one column, font names as body size, and natural card height. For unusual sequences expose exact codepoints as selectable/accessible text. Comparison glyph should not be the sole label.

Touch targets >=44. Standard text contrast >=4.5:1, large glyph/text >=3:1, meaningful boundaries >=3:1; verify light/dark and Increased Contrast. System semantic colors follow accessibility. Progress updates announced at meaningful intervals, not each byte; completion once. Reduced Motion disables decorative transitions; no rotating specimen or automatic font cycling. Do not reorder focused rows mid-interaction; append stable sort with maintained element identifiers.

SF Symbols: textformat, square.grid.2x2, magnifyingglass, chevron.right, arrow.down.circle, xmark.circle, checkmark.circle, arrow.clockwise, exclamationmark.triangle, doc.text, trash, eye.slash. Existing Copy/Save/Scratchpad symbols unchanged. Label network buttons so a user can distinguish Download Style from preview or copy. `.searchable`, `List`/`Form`, `NavigationLink`, `LazyVGrid`, `.confirmationDialog`, `ProgressView`, `.accessibilityElement(children: .combine)` are preferred native constructs.

## Handoff and acceptance

Files likely involved: App/CharacterDetailView.swift, App/FontPackDownloadsView.swift, App/SetupView.swift and new local font-grid/detail components; Shared font enumeration/cache/download helpers remain developer-owned. Preserve current full text insertion and existing extra-font preferences. Character grid comparisons can explicitly preview a local face without silently altering global Extra Unicode Fonts toggle; if download preserves existing toggle-enable behavior, use existing truth and do not introduce a second preference.

Required design checks: two-column and AX one-column grid; very long family names; thousands of faces with responsive scan/cancel; no saved-choice truncation; each source label; text/emoji and combining-mark explanations; unsupported sequence and invisible control; dark/contrast; cached catalog offline; explicit single-style download; unknown-size progress; cancel; invalid-file/registration error; no-match after valid download; licensed detail; removal; existing curated downloads and favorites preserved. Font rendering truth and script acceptance come from product/developer test plan, not mockup count or screenshots.

The published mockups illustrate an increment, not a whole-app redesign and not working simulator evidence. All exact availability/counts are hypothetical. Use the written specification and product brief when a mockup abbreviates a state. No real typed text or account data included in the public artifact.

## Keyboard-customization drag follow-up (23 Oct, user174)
See `drag/design.md` for the focused implementation-ready interaction addendum. Keep font work separate; preserve native editor style, rules and saved layouts. Exact-keycap preview, validated insertion indicator, commit-only persistence and Reduce Motion are required.

## Preview-glass Copy Image follow-up (23 Oct, user190)
See `copy-image/design.md`. Only text actually visible in the keyboard preview is exported, never hidden context. Compact in-keyboard action panel shows the exact image before copying. Existing typing/plain-text copy unchanged; native clipboard permission requirements must be verified by developer.

## Styles list icons (23 Oct, user204)
The screenshot shows style rows as plain blue text with the size beneath; no state is visible. Corrections, scoped to the Google Fonts style list (FontFaceDetailView Styles section):
1. Row text uses label colors, not tint: style name 17pt primary, size caption secondary. Only icons carry the accent.
2. Add one trailing status icon per row, SF Symbols 17pt, accent tint, in this exact mapping: not downloaded arrow.down.circle; downloading ProgressView (small, replaces the icon only for the affected file's rows); downloaded checkmark.circle.fill; unavailable (license/size) exclamationmark.circle with secondary tint, row stays tappable to read the reason.
3. Keep the existing plain checkmark for the selected style, leading of the status icon with 12pt spacing. Selection and download state are independent and both visible.
4. Styles sharing one file show the same status icon; during that file's download all its rows show the progress indicator.
5. Icons are decorative to VoiceOver: fold state into the row's accessibilityValue ("Downloaded", "Not downloaded", "Downloading", or the unavailable reason). No icon-only buttons; the row remains the single tap target, and Download/Remove stay where they are.
6. Row minHeight stays 44pt; at accessibility sizes icons keep 17pt base and scale with the text style; name and size wrap rather than truncate.
