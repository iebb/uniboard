# Uniboard — inspection and auto-capitalization copy

Exact English copy for product addendum msg297. Next update only. Keep existing name. Read-only inspection of frozen visible preview, no whole-document access or app-opening dependency. This handoff defines wording, not verified implementation.

## Inspector

Entry action: **Inspect**. Accessibility label: **Inspect preview text**.
Panel title: **Inspect Text**. Close: **Close**. Back within panel: **Back**.
Scope helper: **Only the text shown in the preview is inspected. Your text won’t be changed.**
Frozen-text helper if needed: **This is a snapshot of the preview. Reopen Inspect to check updated text.**

Totals use localized singular/plural forms, never “chars”:
- **1 code point** / **{n} code points**
- **1 grapheme cluster** / **{n} grapheme clusters**
- **1 UTF-16 code unit** / **{n} UTF-16 code units**

Compact explanation available beside totals or in an expandable help row:
**A grapheme cluster groups code points that form one text unit, such as a letter with an accent or a joined emoji. UTF-16 code units measure how the text is encoded.**
Do not call grapheme counts a guarantee of rendered glyph count or describe all text units as visible.

Group accessibility label: **Grapheme cluster {index}, {count} code points** (singular when one).
Section title: **Code Points**.
Metadata labels: **Code point**, **Name**, **Category**, **Unicode block**, **Script** (only if metadata supported).
Show actual Unicode names and U+ identifiers; preserve original logical scalar order, not display order for right-to-left text.
- Unassigned in selected catalog edition: **Unassigned in Unicode {version}**.
- Missing name/metadata without that conclusion: **Not available**.
- An assigned scalar with no block: **No Unicode block**, only when established.
- Placeholder helper: **Markers for invisible characters and combining marks are shown only in the preview.**
- Do not replace unavailable metadata with “Unknown character” or label the text invalid solely because the catalog lacks it.

Actions: **Copy Text** (exact original frozen excerpt), **Copy Code Points** (U+ sequence).
Success: **Text copied** / **Code points copied**.
Failure: **Couldn’t copy text** / **Couldn’t copy code points**.
Supporting failure line: **Try again. Your text hasn’t changed.**
Copy Code Points accessibility hint: **Copies the code point sequence, not the original text.**
Never include dotted circles, placeholder labels, group numbers, or inspector controls in copied text. Copy Code Points uses the actual original scalars, not normalized output.

## Normalization (read-only)

Section: **Normalization**.
Keep form labels **NFC**, **NFD**, **NFKC**, **NFKD**; these are standard technical names, not actions.
Each form has one status:
- **Already in this form**
- **Differs from this form**
- **Not available**

Helper: **Normalization can change how text is represented. These checks don’t change your text.**
Expanded form descriptions if space allows:
- NFC: **Canonical composition**
- NFD: **Canonical decomposition**
- NFKC: **Compatibility composition**
- NFKD: **Compatibility decomposition**

Accessible value example: **NFC, already in this form**.
Do not say “Valid”, “Invalid”, “Correct”, “Needs fixing” or “Normalize” for a comparison status. Different normalized representations are not automatically errors.
Version note, if catalog and system Unicode data differ: **Character details use Unicode {catalog version}. Grouping and normalization use this version of iOS.** Do not invent the OS Unicode version if unavailable.

## Empty and unavailable states

- Known empty visible excerpt: **No text to inspect** / **Show some text in the preview, then choose Inspect.**
- Host provides no usable text context: **Preview text unavailable** / **This app hasn’t made text available to the keyboard.**
- Known restricted field: **Inspection unavailable here** / **This field doesn’t share text with the keyboard.**
- Cannot inspect due to internal processing failure: **Couldn’t inspect this text** / **Close and try again. Your text hasn’t changed.**

Action: **Close**. Do not offer “Allow Full Access”, “Read Clipboard” or “Open App” as speculative remedies. Do not treat unavailable context as proof the document is empty, or claim that a secure field is the cause when not known.

## Auto-capitalization

Settings row and screen title: **Auto-Capitalization**.
Header helper: **Choose when letter keys use capitals automatically. This affects new typing, not existing text.**

| Mode | Description |
|---|---|
| **Follow App** | **Use the typing app’s capitalization preference.** |
| **Off** | **Use capitals only when you choose Shift or Caps Lock.** |
| **Sentences** | **Start detected sentences with a capital letter.** |
| **Words** | **Start detected words with a capital letter.** |
| **All Characters** | **Use capitals for letter keys that support them.** |

Footer: **Some fields turn off automatic capitals. Languages without capital letters are unchanged.**
Additional explanation if needed: **Custom key text, pasted text and symbols stay exactly as entered.**
Do not promise all-language sentence/word detection, rewrite existing host text, imply forced uppercase of arbitrary custom keys, or conflate this with autocorrection. Manual Shift/Caps Lock remains explicit; Off is not a ban on capitals.

For TOML import preview, show a change under Settings as:
**Auto-Capitalization: {old mode} → {new mode}**.
Validation error: **Auto-Capitalization must be Follow App, Off, Sentences, Words or All Characters.** Technical field paths can accompany this in file errors; exact serialized enum values remain developer's schema contract. If the file uses different tokens, the error must list accepted file tokens rather than suggest UI labels are valid TOML values.

## Acceptance copy checks

Visible excerpt only; exact copied text; explicit totals; original scalar order; missing metadata distinct from unassigned; neutral normalization statuses; no Full Access dependency for inspection; no automatic text mutation; mode persisted and visible in import preview. Existing Copy Image stays separate and continues to paste as a picture, not editable text.
