# Uniboard 1.5.1 — notice when an enabled language can't be read

Camo, 10 November 2026. Task task.63594a55-6a70-42f4-96d6-126650bc9224, Ato msg1834. Placement is Colo's; these are the strings. Keyboard only.

## When it shows

A language is turned on in Uniboard (Use in Keyboard), but the keyboard can't read its settings or files. Today it silently drops out and only English is offered. Show the notice instead.

Don't show it for a language that is simply not downloaded or not turned on; the existing "Download required. Open Uniboard to manage languages." covers missing downloads.

Two causes, two messages. Pick by what the keyboard actually knows (`hasFullAccess`), not by guessing.

## 1. Full Access is off

This is the common case. Reuse the established Full Access wording so the keyboard says one thing, not two.

- Title: **Full Access required**  (existing)
- Body, one language: **{Language} needs Full Access. Allow Full Access for Uniboard in your keyboard settings to use it. Direct Typing is still available.**
- Body, several: **{Language list} need Full Access. Allow Full Access for Uniboard in your keyboard settings to use them. Direct Typing is still available.**
- Compact, one line (shelf status row or under the space-bar picker): **Allow Full Access to use {Language}.** / several: **Allow Full Access to use downloaded languages.**

## 2. Full Access is on, but the files still can't be read

- Title: **Couldn't load {Language}**  / several: **Couldn't load your languages**
- Body: **The keyboard couldn't read {Language} from Uniboard. Open Uniboard to check it in Languages. Direct Typing is still available.**  / several: **…couldn't read {Language list} from Uniboard. Open Uniboard to check them in Languages. …**
- Compact: **Couldn't load {Language}. Open Uniboard to check it.**  / several: **Couldn't load some languages. Open Uniboard to check them.**

No "switch keyboards and back" line: Pluso msg1837 confirmed the fix re-checks the shared files every time the keyboard opens or settings change. 

## Rules

- {Language} is the same label the keyboard already shows for that mode in its picker (`keyboardModeLabel`: 日本語, 拼音, Two-Set Hangul), so people recognise it. A list uses the system's list formatting (ListFormatter), never hand-joined commas.
- No raw errors, file paths, error codes or the words "container" or "App Group".
- The notice never removes the language from the user's settings and never re-enables, downloads or switches anything.
- "Direct Typing" is the established term for plain typing; don't write "English only".
- VoiceOver reads the visible text. Announce it once when the keyboard appears, not on every refresh.
- Placement (Colo design-unreadable-language rev 1.0, msg1838): the compact line is the VoiceOver hint on the language in the space-bar list, with value **Needs Full Access** or **Couldn't load**. The title and long body go in the existing recovery panel (single-language strings only). In the Full Access state the old "Full Access required" subheadline and two footnotes are dropped so nothing is said twice. Switch to Direct Typing updates the remembered language; the list marking keeps the problem visible, which satisfies "returns while the problem remains".
- The panel title for the Full Access state is the existing **Full Access required**; for the other state, **Couldn't load {Language}**.

No code or tests were changed by naming.
