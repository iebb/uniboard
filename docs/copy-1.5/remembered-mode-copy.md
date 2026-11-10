# Uniboard 1.5.1 — remembered input mode: Languages copy

Camo, 10 November 2026. Task task.63594a55-6a70-42f4-96d6-126650bc9224, Pluso msg1844. Replaces the session-only wording in `App/LanguagesView.swift` (language detail screen). This supersedes copy.md's "Preserve the current session-only selection explanation" for 1.5.1.

## Two strings change, not one

1. The state label (about line 206), shown with the checkmark when this mode is the selected one:
   - Old: "Selected in this session"
   - New: **Keyboard Opens in This Mode**
   - Keep the checkmark icon. Accessibility reads the visible text.

2. The section footer (about line 217) is now wrong too:
   - Old: "Downloading and enabling are separate choices. Selecting here is session-only; the keyboard’s own mode selection is independent."
   - New: **Downloading and turning on are separate choices. The keyboard opens in the input mode you select here or with the space bar, and the two stay in sync. Without Full Access, it opens in Direct Typing.**

   The last sentence matches Pluso's fix (the keyboard never opens automatically into a mode that needs Full Access). Drop it if that rule changes.

`Tests/KeyboardConversionViewsSourceTests.swift` line 114 asserts the old footer; update it.

## Why not "The keyboard opens in the selected language."

Pluso's line is accurate, but beside a checkmark it reads as a sentence where a state is expected, and "language" isn't this screen's term: the screen calls these input modes (**Select Input Mode**, and Direct Typing isn't a language). "Turning on" matches the **Use in Keyboard** switch better than "enabling".

## Unchanged

- **Select Input Mode** button.
- "Selected" as the accessibility label of the checkmark on the Languages list.
- The keyboard never switches mode while there is unfinished text; no copy needed for that.

No code or tests were changed by naming.
