# Uniboard — font rules and portable TOML configuration

Status: product scope, 2026-10-23; next increment AFTER the currently authorized master/TestFlight push (messages272–276). Design: Colo; implementation/testing: Pluso; final copy: Camo. Existing product name and services stay unchanged. No code for this increment should accidentally enter the current release before its own verification.

## Audience, delivery, data
For Unicode users who need predictable preferred rendering and transferable, editable setup. Local-only, no new accounts/cloud sync/backend/analytics or AirBuild service. File import/export is user initiated through the containing app; keyboard consumes a validated shared snapshot. Existing data survives migration. Delivery initially simulator verification; do not assume the current release authorization automatically authorizes another subsequent push/release.

## Three existing-screen extensions
1. Character/font detail: set or clear preferred font for this codepoint; link to rules. Existing comparison grid continues to show actual matching faces, not only preferences.
2. Settings → Font Rules: list/add/edit/remove codepoint, inclusive range, or named Unicode-block rules; show effective choice and unavailable font warning. Select existing known font faces; missing font downloads require a separate explicit action in main app.
3. Settings → Configuration: export .toml; import from Files, validate and preview changed sections, then explicitly Replace Configuration or Cancel. No merge mode in first version.

## Resolution contract
- Extra Unicode Fonts remains the master enable switch (product284). Off pauses rules without deleting them; save/edit/import rules never implicitly enable it. Import of the configuration's explicit switch value may change it only with that change in the confirmed replacement preview. Explicit font-comparison/specimen samples still render the inspected face independently of this switch.
- Priority: exact Unicode scalar > matching range > Unicode block > existing default font behavior. Among overlapping ranges the smallest scalar span wins; equal spans are resolved by later array entry. Make this visible in rule list; export preserves order. Exact duplicate selectors rejected rather than hidden duplicates.
- Accept valid scalars U+0000…U+10FFFF except surrogates. Reject reversed ranges and endpoints in surrogates; ranges crossing surrogate space apply only to valid scalars. Block identity is stable Unicode block name plus validated bounds/version, not localized display name. Unknown blocks are import errors, never silently reinterpreted.
- Preference is not proof of coverage. If a chosen face is unavailable or lacks the glyph, try the next applicable preference/default using existing verified fallback. Keep unavailable rules so installing the font later can activate them; show why not applied.
- Do not split grapheme/emoji sequences just to force conflicting scalar fonts. Preserve shaping and exact input; for a multi-scalar cluster use its first non-mark/non-joiner/non-variation-selector scalar as rule anchor (first scalar if none), require whole-cluster support or use existing fallback. Document/test this limitation; no sequence-rule editor this increment.
- Apply consistently in app tiles/details, keyboard previews and image export. Host apps still receive unstyled original text. No new Full Access requirement for ordinary typing. Explicit single-font comparison/specimen stays faithful to the chosen specimen, not overridden by rules.
- Stable face references reuse existing font-library identity (source, file identity/hash, face index/variation identity or process PostScript name); never serialized filesystem paths as portable identity. No font binaries in TOML, no automatic download or remote URL execution.

## All configuration means
Create one versioned TOML configuration model, serialized by a real bounded TOML parser/writer, not fragile line splitting. Internal keyboard read caches may remain compiled JSON snapshots for compatibility/performance; they must derive from the same validated configuration rather than competing sources of truth.

Include all user-controlled persistent settings: Unicode edition and visibility/rendering preferences; enabled layouts/order and configured default; keyboard key mappings, per-alphabet arrangements and symbol pages/boards/order/star target; explicit favorites; grid/column density, sort and persistent browse preferences; selected/imported font references and the new rules; Copy Image preset/custom colors. Preserve stable board/key IDs, exact Unicode sequences and the distinction between default/unset and explicitly disabled empty mappings. Missing sections in a valid import use documented factory defaults: the preview must clearly show resets, not silently merge.

Exclude scratchpad, recents/typing history, host text, search/caret state, active navigation/last-used board, tokens, device-local paths, caches, logs, download progress, generation/lock/sync bookkeeping and font binaries/licenses receipts. Favorites and custom key strings are deliberately exported configuration and may be personal: explain this before sharing.

Existing stores requiring inventory/migration: UnicodeEditionSettings, KeyboardKeySettings, SymbolBoardStore/SymbolPageSettings, FavoriteSync/CharacterStore, app presentation UserDefaults, CustomFontStore/FontLibraryStorage, KeyboardPreviewImageExport colors. Copy Image colors are currently process-local UserDefaults: reconcile through the shared configuration so containing-app export includes the actual keyboard choice.

## Safe import and migration
- Top-level schema_version required; reject unsupported versions, duplicate keys/selectors, invalid scalar/block/font references, unknown settings keys, type/range violations and excessive payloads, with actionable location/field errors. Missing font asset is a warning, not malformed configuration. Use existing section bounds (including 16 boards, 256 ordinary keys per board, 4096 favorites); developer must document a bounded total import size before implementation.
- Parse/validate whole file before any write. Preview changed/reset sections, font availability and overwrite of favorites/custom keys. No external retrieval while parsing. Cancel/error leaves every existing section unchanged.
- Apply atomically from the keyboard's perspective; safe staged snapshot/generation switch and last-good recovery, not independent partial replacements. Coordinate app/keyboard concurrent favorites/settings edits: recheck generation before confirmation and refresh preview if changed. Do not overwrite an edit made after preview silently.
- Migrate existing state once without resetting data. Keep a local pre-import backup for Undo Last Import; undo must not silently overwrite newer edits (confirm changed-state replacement). Export should be deterministic and round-trip semantically, including non-ASCII/control escapes, variation selectors and ZWJ text. TOML comments/formatting need not round-trip.

## Acceptance evidence
1. Exact/range/block/default priority; nested/overlapping/equal-span ranges; clear-rule fallback; supplementary scalars; malformed/reversed/surrogate input; stable block matching across supported editions.
2. Real installed and downloaded faces tested independently in app and keyboard; missing/removed font fallback, install-later activation; no automatic network request on import or rendering. Existing font limits do not silently drop rules or truncate enumeration.
3. Mixed scripts, combining sequences, emoji ZWJ/variation selectors and contextual script shaping preserve exact text; Copy Image renders same effective choices as its visible preview. Record unsupported shaping/coverage honestly.
4. Export → replace → export semantic equivalence across every included category. Custom pages/layouts/favorites/colors survive app and keyboard relaunch, and existing users migrate without loss. Include explicit empty/default distinctions.
5. Invalid, oversized, unknown-schema and partially valid files leave prior config untouched. Cancel, generation conflict and interrupted apply recover last-good state. Undo tested. No scratchpad/recents/host text or device paths in exported fixture.
6. Import on a second installation with missing fonts warns and preserves rules without downloading; filename is not treated as a trusted font identity. Cross-device transfer is by file, not automatic sync.
7. Main app import/export is usable with accessibility text/VoiceOver. Keyboard startup/rendering remains bounded, no full worldwide font loads and no per-keystroke TOML parsing. Regression checks include current drag, tile zoom and Copy Image features.

## Design and copy handoff
- Design: `design/font-rules/design.md`, final Colo message288, attachment7e13c150-0056-4ce1-b69f-2ccc522d36d3, seven mockups in design/font-rules/, artifact66224903-e951-4e34-a101-2a573c65c5d8. Master-switch clarification above governs.
- Copy: `docs/font-rules-copy.md`, Camo messages280/285/287; all supplemental labels settled288. Format version refers to configuration schema, not app version. Scalar editor counts codepoints, not visible characters; range coverage counts actual verified scalars and distinguishes checking from unsupported. Keep current TestFlight source isolated from this next increment; developer289 starts only after current push.

## Research / boundaries
Builds on prior research in docs/brief.md: Apple's custom keyboard guide (unstyled inserted text), Unicode grapheme guidance, Google Fonts redistribution constraints. TOML reference https://toml.io/en/v1.0.0 — fetch blocked by research-service credit limit this session, so parser/version conformance must be verified by implementation, not claimed researched. Existing-source read-only audit confirms no present TOML codec or scalar/range/block preference engine. No new product name or website needed.
