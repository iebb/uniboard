# Uniboard 1.5 follow-up — landscape number-row note

Camo, 5 November 2026. Task task.16456b0b-ed4f-497e-960a-1d0048403d00, Ato msg1721, Colo design-landscape-compact.md rev 1.0. Folded into `docs/copy-1.5/copy.md` revision 2.4.

## Where it goes

There is no Number Row switch any more: the retired setting became part of the saved arrangement, edited in **Main Keyboard → Letters** (`MainKeyboardEditorView`, with **Add Number Row** / **Add Missing Digits**). So the note belongs in that editor's Letters section, as a footnote in Secondary below the canvas, beside the existing row-width note.

Show it only:
- on iPhone (iPad is unaffected),
- in the Letters section,
- when the arrangement actually has a number row (the row the landscape rule hides). If the person removed it, there's nothing to explain.

Plain text, no icon, no link. Not shown inside the keyboard.

## Exact copy

Until Romaja ships (it waits on Natun's spelling answer):

**In landscape on iPhone, Mandarin and Japanese hide the number row so you can see what you're typing. Use the 123 key for digits there. Your arrangement doesn't change.**

Once Romaja exists and follows the same rule:

**In landscape on iPhone, Mandarin, Japanese and Korean Romaja hide the number row so you can see what you're typing. Use the 123 key for digits there. Your arrangement doesn't change.**

Only name a mode the rule actually applies to in the build. Two-Set Hangul is not listed: it never had the number row in landscape.

VoiceOver reads the visible text; no separate label.

## Fits with existing copy

- Keep the merged-symbols footnote unchanged ("ABC already types all ten digits, so the symbols fit on one page…"). It describes the saved arrangement, which is still true in portrait. The new note sits after it and explains the landscape exception.
- The item 18 split/merge message is triggered by edits only. Rotating into landscape must not show it, because nothing about the saved arrangement changed.
- "Number row" stays lowercase in prose, matching **Add Number Row** as the only title-case use.

## Customized number row (Ato msg1724, revision 1.1)

Landscape hides the row only when it holds just the digits 1–0. A row with any other key stays, and the keyboard is taller.

- Row holds just the digits: show the note above, unchanged.
- Row has other keys too: show instead
  **In landscape on iPhone, Mandarin and Japanese hide the number row only when it holds nothing but digits. Your number row has other keys, so it stays, and there's less room to see your text.**
  (Becomes **Mandarin, Japanese and Korean Romaja** once Romaja follows the rule.)
- No number row: no note.

The second note is only needed if Pluso confirms the case exists. If people can't put other keys in that row, ship only the first note.

Colo rev 1.1 (msg1726) hides a row whose keys are all digits, any subset of 0–9, so the note says "nothing but digits", not "the digits 1 to 0". Don't tell people to remove their keys; it was their choice.

No code, catalog or tests were changed by naming.
