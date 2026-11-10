# Uniboard — language input and dictionary copy draft

For product/design/developer, msg1023. Uniboard name retained. Scope: local conversion, on-demand resources, custom dictionaries, optional reversible English autocorrection. This is draft UI copy, not a claim that engines, resources or licenses are ready. Exact formats, correction triggers and accepted input spellings follow the final brief.

## Consistent terms
- **Input Mode**: how letter-key input becomes text. Not a different physical keyboard layout.
- **Language Downloads**: resources required for a conversion mode. Do not call all resources a dictionary if they include an engine/model.
- **Custom Dictionaries**: user-added mappings, separate from downloaded language resources and optional autocorrection.
- **Entry**: one typed form and its output.
- **English Autocorrection**: optional automatic English replacements, not Japanese/Chinese conversion choices.
- Say **choices** in general help, not candidates. Retain technical dictionary format details in dedicated import help.

## Mode labels and help
- **Direct Typing** — **Type characters without language conversion.**
- **Japanese — Romaji** — **Use letter keys to enter Japanese and choose a conversion.**
- **Chinese — Pinyin** — **Use pinyin to enter Chinese and choose a conversion.** Specify Simplified/Traditional only after actual resource/output scope is chosen.
- **Korean — Romanized** — **Use letter keys to enter Korean.** Add a **Typing Guide** showing the supported scheme; do not promise every romanization works.
- **Input Mode**, **Typing Guide**, **Choose a Language**.
- Distinguish enabled, downloaded and active. Do not call a merely downloaded mode selected.

## Conversion strip
- Accessible container label: **Conversion Choices**.
- Action for each output: **Insert {choice}**; avoid speaking internal score/rank.
- Optional **More Choices**, **Keep Typed Text**, **Cancel Conversion** only where those operations are implemented unambiguously.
- Empty: **No matching conversion** / **Try another spelling or keep the typed text.** Offer that alternative only if it truly preserves the typed text.
- Preserve unfinished input through downloads/errors; do not label automatic loss as cancellation success.

## Language downloads
- Screen: **Language Downloads**; detail uses actual language/mode name.
- Actions: **Download**, **Cancel Download**, **Try Again**, **Remove Download**.
- Size: **{size} download**; show installed size separately if known. Never imply compressed download size is the space required.
- States: **Not downloaded**, **Downloading… {percent}%**, **Checking download…**, **Ready to use**, **Download failed**.
- Missing resources: **Download required** / **Download this language in the Uniboard app to use it here.**
- Failure: **Couldn’t download this language. Try again when you have an internet connection.** Use only for network failure; other causes need specific text.
- Invalid resource: **This download couldn’t be verified. It hasn’t been enabled.**
- Insufficient space: **Not enough storage for this download. Free some space and try again.**
- Do not promise file deletion or reclaimed storage on Remove until verified. State exactly which input modes stop working and whether custom entries remain.
- Download permissions note, if relevant: **Downloads need an internet connection. Language conversion runs on this device.** Do not promise keyboard operation without Full Access until engineering confirms shared-resource access.

## English autocorrection
- Setting: **English Autocorrection**. Default **Off**.
- Helper: **Automatically correct English words as you type. You can undo a correction.**
- Distinction: **This setting doesn’t control Japanese, Chinese or Korean conversion choices.**
- Correction indication: **Changed “{original}” to “{replacement}”**.
- Action/accessibility label: **Undo Correction**.
- Restored indication: **Original text restored**.
- Do not claim an undo succeeded if the host text has changed and it cannot safely restore the original.
- Exact activation/commit trigger and available undo window follow the brief; no promise of personalized learning or cloud sync.

## Custom dictionaries
- Screen: **Custom Dictionaries**.
- Actions: **Add Dictionary**, **Import Dictionary**, **Add Entry**, **Edit Entry**, **Save**, **Cancel**, **Remove Dictionary**.
- Empty: **No custom dictionaries yet** / **Add words and phrases you want to use, or import a dictionary.**
- Entry fields: **Typed Text**, **Output Text**, **Input Mode**. Replace Typed Text with a specific reading term only if the chosen format requires it.
- Empty fields: **Enter the text you’ll type.** / **Enter the text to insert.**
- Unsupported mode: **This entry isn’t supported by the selected input mode.**
- Preview title: **Review Dictionary Import**.
- Intro: **Review the entries before importing. Your dictionaries haven’t changed.**
- Counts: **{n} entries**, **{n} warnings**, **{n} errors**, with localized singular forms.
- Invalid line: **Line {line}: {reason}**. Show line only when known. Do not log personal dictionary contents or treat pasted text as executable instructions.
- Format help: **Use a tab-separated text file in Uniboard’s dictionary format.** Add exact column order, encoding, escaping, limits, duplicate rules and a downloadable example only after the schema is settled.
- Primary: **Import Dictionary** if it creates/adds as promised; use **Replace Dictionary** and an explicit replacement warning only if replacement is the actual operation.
- Failure: **Couldn’t import dictionary** / **Your dictionaries haven’t changed.** Assert unchanged only with atomic validation/write behavior confirmed.
- Success: **Dictionary imported**.
- Distinguish disabled from removed; do not claim removing a custom dictionary uninstalls a language engine.

## Privacy and readiness
Proposed factual helper: **Language conversion and English autocorrection run on this device. Your typing isn’t sent to a server.** Requires engineering verification for each engine and request path. Downloads may contact external hosts; the download disclosure must name verified sources separately. Do not broaden this into “no network access”.

Pending the brief: correction trigger/undo rules; TSV columns, Unicode/encoding rules, duplicate/merge policy and limits; per-mode input schemes; resource removal effects; exact download hosts and licenses. These are behavior decisions, not decisions for copy to invent.
