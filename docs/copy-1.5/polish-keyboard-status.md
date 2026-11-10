# Uniboard 1.5 polish — replacing "Keyboard Unverified"

Camo, 5 November 2026, revision 1.1. Polish pass task.e1f50353-20e9-4c7b-8ed1-a4e12be4e054, Ato msg1669 fix A. Strings for the slots Colo marked [Camo] in design-polish-1.md rev 1.0 (msg1671), which owns layout and treatment. Folded into `docs/copy-1.5/copy.md` revision 2.3, item 19.

## Strings

Font file detail screen, File section, `LabeledContent("Keyboard", value: …)`:

| State | Value | Section footer |
| --- | --- | --- |
| Not checked (`.unverified`) | **Not Checked Yet** | **Uniboard checks this font the next time its keyboard opens. It already works here in the app.** |
| Confirmed unavailable (`.appOnly`) | **App Only** | Keep the existing App Only footer. |
| Available (`.available`) | Hide the row | No footer. |

VoiceOver: **Keyboard, Not checked yet** / **Keyboard, App only, not on the keyboard** (existing App Only text).

The footer sits beside the existing **Fonts change the preview here. Other apps choose how inserted text looks.** Keep that line; put the keyboard sentence first.

Font list rows and the font rule picker: per Colo, nothing for the unconfirmed state. **App Only** and its footer stay exactly as they are. With no unconfirmed tag left in the picker, the old picker footer (`keyboardUnverifiedFooter`) has nowhere to appear; retire it rather than reword it.

Why: "Not Checked Yet" says what is true — nothing has gone wrong, no check has happened yet — and "Yet" tells people it is temporary. The footer says when it changes and that nothing is broken in the meantime.

## Resolved (msg1675)

Pluso confirmed the keyboard records its font check only with Full Access on. Final unverified footer: **Uniboard checks this font when its keyboard opens with Full Access. It already works here in the app.** Downloaded and added files show no Keyboard row; installed fonts use their recorded status. Colo confirmed layout (msg1673).

## Gate on the footer's first sentence (history)

"Uniboard checks this font the next time its keyboard opens" is only true if the keyboard actually writes its font record in the state the person is in. The keyboard writes `keyboard-fonts-v1.json` to the App Group; a keyboard without Full Access may not be able to write there. @developer please confirm with Full Access off.

- If it records with Full Access off: use the footer above.
- If it needs Full Access: use **Uniboard checks this font when its keyboard opens with Full Access. It already works here in the app.** Don't add a Full Access button or request here.
- If it isn't reliably recorded at all: use **The keyboard hasn’t checked this font yet. It already works here in the app.**

## Which fonts can show this state — please check

`KeyboardFontEvidence.status` in `Shared/FontPickerCatalog.swift` treats `.imported` and `.downloaded` faces (files in the App Group) as always `.available`. Only installed fonts and other device fonts can be unconfirmed. But `FontFileDetailView.swift` currently hard-codes "Keyboard Unverified" for every file row (line 218) and every detail screen (line 90).

So the new Keyboard row should come from the computed `KeyboardFontStatus`, not a fixed string. If the code is right, Google Fonts downloads and added files show no Keyboard row at all, and "Not Checked Yet" appears only for installed fonts. If downloaded files really can be unavailable to the keyboard, the status logic is wrong instead; tell me and I'll adjust.

"On this version of iOS": evidence from another iOS build doesn't count, so an installed font can go back to Not Checked Yet after an iOS update. The wording covers that without saying so.

## Engineering notes

- `Tests/FontPickerCatalogTests.swift` lines 37, 39, 86–88 assert the old strings; update them with the copy.
- Renaming Swift identifiers is optional; only visible text changes.
- No code, catalog or tests were changed by naming.
