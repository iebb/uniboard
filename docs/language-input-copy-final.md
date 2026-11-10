# Uniboard — finalized language input copy contract

Supersedes terminology and unresolved-format alternatives in language-input-copy.md. Based on product brief msg1027. Strings describe intended behavior; availability, privacy and Full Access claims require verification. Name remains Uniboard. No release date/version claim.

## Screens and terms
**Languages**: downloadable language resources and mode settings.
**My Words**: manual entries and imported collections.
**Input Mode**: conversion behavior, not the physical layout.
**Dictionary**: one independently enabled/removable collection of custom entries within My Words.
**Entry**: a reading and output, optionally weighted.
**Reading**, **Output**, **Weight**: exact editor fields. Reading helper: **The spelling you type to find this entry.** Output helper: **The text offered as a choice.** Weight helper: **Higher values rank this entry ahead of lower-weight entries with the same reading.** Use this last helper only if engine ranking actually guarantees it; otherwise **A ranking preference from 0 to 10000.**

## Mode names
**Direct Typing** — **Type characters without language conversion.**
**Japanese — Romaji** — **Type romaji, then choose Japanese text.**
**Mandarin Chinese — Pinyin** — **Type pinyin, then choose Chinese text.**
**Korean — Romanized** — **Type Korean using the spellings in the Typing Guide.**
**Typing Guide** must document the actual supported scheme; examples cannot be invented by copy. Chinese output controls **Simplified**, **Traditional** only where verified resources support them. Japanese choices **Hiragana**, **Katakana**, **Keep Roman Letters**. Do not label kana-only output kanji conversion or Korean output Hanja.

## Choices and correction
Accessible strip title **Conversion Choices**. **More Choices**, **Fewer Choices**, **Keep Typed Text**, **Cancel Conversion** where implemented. Choice action **Insert {output}**; announce selected state separately.
**English Autocorrection** (Off initially). Helper: **Correct English words automatically when you finish a word. Press Backspace immediately after a correction to restore your spelling.**
Supporting text: **Language conversion choices are separate from English autocorrection.**
Correction announcement: **Changed “{original}” to “{replacement}”.** Undo action **Undo Correction**; success **Original spelling restored**.
If context changes, remove the stale Undo action rather than promise a restoration it cannot safely perform. Do not log announcement contents. Custom outputs are choices, not forced automatic replacements.
Optional marked typo-tolerant choice: **Suggested spelling: {reading}**; show only if the engine actually identifies an alternative reading.

## Downloads
Actions **Download**, **Cancel Download**, **Try Again**, **Enable**, **Disable**, **Remove Download**. Enable is not Download or Select.
States **Not downloaded**, **Downloading… {percent}%**, **Checking download…**, **Ready to use**, **Download failed**.
Metadata **Download Size**, **Installed Size**, **Source**, **License**. Unknown size: **Size unavailable**, not zero. Show required information before download.
Missing: **Language download required** / **Download this language in Languages in the Uniboard app. You can still use Direct Typing.**
Verification failure: **This download couldn’t be verified. Your current language download hasn’t changed.** Use second sentence only when a current version exists; otherwise **It hasn’t been enabled.**
Removal title **Remove this language download?** Body **This input mode won’t be available until you download its resources again. Your words in My Words will be kept.** Adjust for shared-resource modes if one download supports several. Do not promise immediate complete byte deletion; engineering must verify safe removal of active files.
Full Access fallback, ONLY if verified required: **Full Access is needed to let the keyboard read this downloaded language from the app. Typing is processed on this device, not sent to a server. Direct Typing still works without Full Access.** Do not show this for unrelated errors or before both permission states are tested.

## My Words
Empty **No custom words yet** / **Add an entry or import a dictionary.**
Actions **Add Entry**, **Edit Entry**, **Import Dictionary**, **Export Dictionary**, **Enable Dictionary**, **Disable Dictionary**, **Remove Dictionary**.
Manual actions **Save**, **Cancel**, **Delete Entry**.
Removal title **Remove this dictionary?** Body **Its entries will no longer appear as choices. Export it first if you want to keep a copy. Language downloads won’t be removed.** Do not say recoverable unless a separate recovery flow exists.
English reading helper **Enter a word or shortcut.** Japanese **Enter kana or supported romaji.** Mandarin **Enter full pinyin using the spellings in the Typing Guide.** Korean **Use the romanized spelling shown in the Typing Guide.**
Output is preserved exactly; do not normalize accents, compatibility characters or sequences on save/export.

## Import format help
Title **Dictionary File Format**.
**Use a UTF-8 .tsv or .txt file. Each entry has a reading and output separated by a tab. You can add a third column for weight, from 0 to 10000. If omitted, the weight is 100.**
**Don’t include a header row. Blank lines and lines starting with # are ignored. Choose the input mode before importing.**
**This is Uniboard’s format. Rime files, binary dictionaries and archives aren’t supported.**
**Each file can be up to 1 MiB and contain 10,000 entries. My Words can contain 50,000 entries in total. Each reading and output can contain up to 256 Unicode code points. Tabs, line breaks and the null character aren’t allowed inside a reading or output.**
Engineering note: the limit is Unicode scalars, not grapheme clusters/UTF-16 units; error-count implementation must match the brief. Optional BOM and LF/CRLF accepted. The example file must contain real tab bytes and no header.
Example download action **Download Example**; example content should be mode-specific and parser-verified before handing it to the user.

## Preview and validation
Title **Review Dictionary Import**.
Intro **This creates a separate dictionary. Your existing words won’t be replaced.**
Labels **Input Mode**, **Valid Entries**, **Invalid Entries**, **Duplicate Entries**.
Duplicate helper **Exact duplicates are kept once. Different outputs for the same reading remain separate choices.**
Primary **Import Dictionary** (blocked while invalid rows remain); secondary **Cancel**.
Invalid helper **Fix the invalid entries before importing. Your words haven’t changed.**
Line error template **Line {line}: {reason}**:
- **Use a tab between the reading and output.**
- **Use two columns, or three when including a weight.**
- **Enter a reading.** / **Enter an output.**
- **Weight must be a whole number from 0 to 10000.**
- **This reading isn’t supported by the selected input mode.**
- **The reading exceeds 256 Unicode code points.** / **The output exceeds 256 Unicode code points.**
- **The reading or output contains a character that isn’t allowed.** Show the cause name where known, not a raw control character.
File errors **Choose a UTF-8 text file.**, **This file exceeds the 1 MiB limit.**, **This file exceeds the 10,000-entry limit.**, **This import would exceed the 50,000-entry limit in My Words.**
Empty/comment-only input **No entries to import**.
Do not silently skip invalid rows or partially apply. Exact duplicate counting must be consistent between preview and import.
Success **Dictionary imported**. Action **Undo Import**. Confirmation **Undo this dictionary import?** / **This removes the dictionary created by the last import.** Only if that matches the implemented undo boundary; later manual edits require explicit protection rather than a misleading claim to restore everything.
Failure **Couldn’t import dictionary** / **Your words haven’t changed.** Confirm atomic behavior before asserting unchanged.

## Configuration and privacy
Configuration helper **Language download references are included, but language files and unfinished text aren’t. Missing downloads won’t be fetched automatically.** Do not imply custom entries are included in the general configuration unless implemented; use dictionary export for their user-controlled backup.
Verified-only privacy line **Language conversion and English autocorrection run on this device. Your typing and custom words aren’t sent to a server.** External download hosts and license disclosures remain separate and must match real requests. No cloud learning/account/sync or reinstall-recovery claim.

## Remaining implementation-specific details
Only the audited Korean scheme, pinyin tone/boundary rules, actual language resources/licenses, exact choice confirmation gestures, import Undo behavior after newer edits and verified Full Access outcomes remain to fill. These are not naming decisions and must not be guessed.

## Superseding presentation updates — msgs1083,1121,1154
- Unusable English suggestions: **Suggestions unavailable here.** Optional explanation: **This app doesn’t provide enough text context to replace words safely.** Omit unusable chips; Direct Typing remains available.
- Current downloaded-language access requirement: **Full Access required** / **Allow Full Access so the keyboard can read downloaded language files shared by the app. Your typing stays on this device. Direct Typing works without Full Access.** Short recovery: **Allow Full Access to use downloaded languages. Direct Typing is still available.** Keep resource Ready/enabled/selected separate from permission state.
- Literal choices now display verbatim typed text, e.g. **nihongo**, with no Keep Roman Letters label, no added quotes and no normalization. Same rule for expanded choices. Typing Guide: **To insert exactly what you typed without conversion, tap that spelling in the choices. For example, tap nihongo to insert nihongo.** Accessibility label: **Insert exactly as typed: {text}**. Generic Finish Conversion recovery action names stay unchanged. This supersedes earlier visible literal-action wording, not the recovery flow.
