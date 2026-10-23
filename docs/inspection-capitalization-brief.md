# Addendum: glass text inspection and auto-capitalization

User request293, product294: next increment alongside font rules/TOML, NOT current TestFlight. Supplement docs/font-rules-brief.md; same local-only/privacy/service boundaries. Design owner Colo, implementation Pluso, wording Camo.

## Reference and decision
Reviewed both supplied images: first is a compact message entry bar; second a desktop Unicode inspector with normalization badges, escaped text and scalar metadata table. Adapt the inspection to the keyboard rather than squeeze a desktop table into it. MVP is an in-keyboard read-only inspector; opening the containing app is not a dependency and must not use unsupported keyboard-extension launch tricks. Larger pasted-text inspection in the app can follow later, not necessary for this request's first working increment.

## Glass preview → Inspect
- Add an Inspect action beside existing Copy/Copy Image actions, preserving those flows. Freeze exactly the excerpt visibly previewed when tapped; no extra hidden context or claim to inspect the whole host document. Current bounded context remains (up to 48 characters on either side, subject to host availability); developer verifies actual extraction boundaries. Do not persist the inspected text or include it in TOML/history/analytics.
- Panel stays within keyboard: fixed header/back/close, compact text sample and totals, vertically scrollable rows grouped by extended grapheme cluster. Each group has its visible display plus ordered scalar entries with U+XXXX (up to six digits), Unicode name, category and block; script if supported by current metadata. Disclose missing/unassigned/version-specific data instead of guessing. Row details can expand inline.
- Totals explicitly distinguish code points, grapheme clusters and UTF-16 code units. No ambiguous “chars”. Order is original logical scalar order even for RTL; keep identifiers/numbers LTR, sample shaping natural. Dotted-circle/visible control placeholders are explanatory only, never inserted/copied as content.
- Show NFC/NFD/NFKC/NFKD status read-only (already in that form / differs / unavailable if applicable). Do not normalize or replace host text. Copy Code Points produces explicit U+… sequence; optional escape-format selector/desktop table is out of initial scope. Existing Copy Text remains exact original excerpt.
- Empty/unavailable host context has an explicit state. Secure fields may not expose keyboard or text. No clipboard read, full-document access, silent app handoff, or extra permission for inspection. Dismiss does not alter text/caret/shift and editing the host does not mutate the frozen inspection; reopening takes a fresh excerpt.

## Auto-capitalization configuration
- Existing Settings → Keyboard gains Auto-Capitalization: Follow App (default preserving existing host-trait behavior), Off, Sentences, Words, All Characters. Include selected mode in TOML schema/import preview/export/migration and shared keyboard snapshot.
- Current code follows textDocumentProxy.autocapitalizationType and disables English assistance for some contexts. Preserve existing safety/context exclusions and supported-language limitations; no promise of universal sentence detection. Keep email/URL/credential-like contexts free of forced automatic capitalization. Explain that some fields disable it.
- Override changes upcoming keyboard letter/shift behavior, never rewrites existing host text. Manual shift/caps lock remains explicit and respected; don't uppercase arbitrary literal custom keys, Unicode symbols, pasted text, emoji or sequences. Don't silently change auto-correction/punctuation settings as part of this request.
- Sentence mode: beginning of editable input when known, after sentence terminator plus separating whitespace, and appropriate newline behavior under existing engine; test abbreviation/decimal ambiguities and document conservative behavior. When context is unavailable/truncated do not invent a sentence boundary. Words mode follows supported word boundaries; scripts without case unchanged.

## Acceptance additions
1. Inspect Latin, decomposed accent, joined emoji, supplementary scalar, Hebrew combining text from reference, RTL/mixed text, newline/control/invisible and unassigned codepoints. Counts and row order match exact original scalar sequence; no mutation or placeholders in copied data.
2. Grapheme grouping and normalization statuses use tested Unicode APIs/version; identify any difference from the catalog's newer Unicode edition rather than invent names/segmentation guarantees.
3. With long document, inspection copies/exposes only frozen visible excerpt. No text retained after dismissal/relaunch or included in configuration export/logs. Keyboard access unavailable and empty states verified.
4. Keyboard panel remains usable with long names, large text and VoiceOver; no offscreen close/action. Test light/dark and ordinary typing after dismissal. No Full Access requirement added.
5. All capitalization modes tested at text start, after punctuation/spaces/newline, word boundary, cursor move, deletion, manual shift/caps lock, unavailable context, email/URL fields and noncased script. Follow App preserves baseline; Off prevents auto-shift but not manual shift. Typing remains exact for literal keys.
6. Mode persists/reloads between app and keyboard and TOML round-trips. Import validation rejects unknown mode; default migration does not change existing behavior. Existing Copy Image/font rules/drag remain regression gates.

## Implementation handoff
Developer should report unsupported host traits or API limits before promising app-opening or broad-language behavior. Designer returns keyboard-native inspection spec and Settings row; copywriter confirms count/normalization/limitation wording. This addendum sets behavior; it does not require an additional product name or services.
