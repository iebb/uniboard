# Uniboard 1.3 — Configuration editor (minimal)

Owner: Colo (design) · rev. 4, 2026-10-24 · For: Pluso (build). Scope: user msg692, Ato msg697.
Wording: Camo msg702 (`config-editor-copy.md`) is final; this file only places it.
Mockups: artifact B241781E ("Uniboard 1.3 — Edit Configuration"), screenshots 1–7 attached.
Base: font-rules spec §6 (Configuration page and Review Import). Everything not mentioned here is
unchanged.

Principle: the editor is the Import flow with a text box in front of it. Validate and Apply call
the same check as Import (`ConfigurationImportModel.check(data)`), and Apply goes through the
same review, Replace and recovery path. No new review screen, no second recovery history.

---------------------------------------------------------------------------
## 1. Entry (Settings → Configuration)

Section 1 rows become, in order:
1. Export Configuration `square.and.arrow.up` (unchanged)
2. Import Configuration `square.and.arrow.down` (unchanged)
3. **Edit Configuration** `square.and.pencil` (new, same row style: tint symbol, 44 pt, no
   caption)
4. Undo row (unchanged layout; title "Undo Last Configuration Change", since the one recovery
   entry now covers both imports and editor applies). Caption (Camo msg707): "Imported today at
   18:40" after an import, "Applied today at 18:40" after an editor apply, "Changed…" if the
   source isn't recorded. Same date forms as the existing importedAt.

Header and footers unchanged. Reason for the position: Edit sits with the other two ways a
configuration gets in, and Undo stays last because it undoes any of them.

---------------------------------------------------------------------------
## 2. Editor sheet

- `.sheet`, `.presentationDetents([.large])`, own `NavigationStack`, inline title
  "Edit Configuration".
- Toolbar: leading "Cancel" (`.cancellationAction`); trailing "Apply" (`.confirmationAction`,
  so it's bold).
- `.interactiveDismissDisabled(isEdited)`. If the swipe-down attempt can be caught cheaply
  (`presentationControllerDidAttemptToDismiss`), show the discard dialog (§6); if not, leave it
  as a disabled swipe.

**Loading:** on open, encode the current configuration exactly as Export does. While it runs:
centered `ProgressView` + "Preparing configuration…" (existing string). The text then appears
with the cursor at the start and **no keyboard raised** (so the helper text is read first).
Load failure: centered `xmark.octagon` 44 pt systemRed + the existing export-failure title and
body, toolbar Cancel only (Camo to confirm strings if this case is real).

**Text view** (fills the sheet; `UIViewRepresentable` around `UITextView`, because SwiftUI's
`TextEditor` on iOS 17 can't turn off smart quotes, which would turn `"` into `”` and break the
file):
- Font: `UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)` through
  `UIFontMetrics(forTextStyle: .body)`, `adjustsFontForContentSizeCategory = true`.
- Colors: text `.label`, background `.systemBackground` (a plain document, not the grouped
  background). Tint = app accent.
- Insets: `textContainerInset` top 12, bottom 12; `lineFragmentPadding` 16 (16 pt sides).
- Lines wrap (no horizontal scrolling).
- Off: autocorrection, autocapitalization, spell checking, smart quotes, smart dashes, smart
  insert/delete, data detectors, rich text. Keyboard type default (the file may hold any
  character).
- `keyboardDismissMode = .interactive`; `isFindInteractionEnabled = true` (system Find, free).
- System undo/redo of typing stays as UITextView gives it.
- accessibilityLabel "Configuration text".

---------------------------------------------------------------------------
## 3. Status bar (bottom, above the keyboard)

`.safeAreaInset(edge: .bottom)` so it rides on top of the keyboard:
- 0.5 pt separator on top, background `.bar` material.
- Padding 16 pt sides, 10 pt top/bottom.
- `HStack(alignment: .center, spacing: 12)`: status on the leading side (icon 17 pt + text,
  footnote 13 pt), `Spacer(minLength: 8)`, then **Validate** (`.bordered`, `.controlSize(.regular)`,
  hit area at least 44 pt tall).
- The status area is at most 40% of the space between the nav bar and the keyboard; beyond that
  it scrolls inside itself.
- Large text (accessibility sizes): `ViewThatFits` → Validate moves under the status, full width.

| State | Icon | Text |
|---|---|---|
| Opened, not edited | none | Helper, `.secondary`: "Edit your configuration in TOML. Validate checks your edits without changing your settings. Apply saves them." |
| Edited since last check | none | "Edits haven’t been checked." `.secondary`. Any earlier result is cleared on the first keystroke after it. |
| Checking | `ProgressView` (small) | "Checking configuration…" `.secondary`. Validate and Apply disabled. |
| Valid | `checkmark.circle.fill` systemGreen | "Configuration is valid. Your settings haven’t changed." `.primary` |
| Valid with warnings | `exclamationmark.triangle.fill` systemOrange | "Configuration is valid. Review the warnings before applying." then one line per warning (missing sections → "Sections missing from this configuration will reset to defaults.", unavailable fonts → existing fonts line), `.secondary` |
| Invalid | `xmark.octagon.fill` systemRed | Order (rev. 4, all sizes): title semibold `.primary` "Fix these errors before applying" → the first error → "{n} More Problems" → `.secondary` "Your settings haven’t changed." last. The error must never be the part pushed below the 40% cap. |
| Empty text | `exclamationmark.triangle.fill` systemOrange | "Enter a configuration before validating or applying." |

**Errors (invalid state):**
- The first error is always shown, exactly as the checker writes it: "Check line {line}, column
  {column}: {reason}" (Camo msg707; no extra prefix; omit parts with no location).
- More errors: the existing "1 More Problem" / "{n} More Problems" as a tint text button under
  it; tapping shows the rest in the same list (scrolls within the 40% cap).
- **Each error with a location is a button:** it places the cursor at that line and column,
  scrolls it into view (`scrollRangeToVisible`), and raises the keyboard. The checker counts
  columns in Unicode scalars from 1 (configuration-format.md §2) and UITextView uses UTF-16
  offsets: convert, and test with `あ` and an emoji earlier on the same line. No line
  highlighting, no gutter.
- Errors without a location (missing version, unsupported version, "Check {field}: …",
  "Unrecognized setting: …", duplicates) are plain text, not buttons. Never guess a line for them.
- Error text `.primary`, footnote; the location part stays plain text (no monospace needed).
- No inserted hyphens (rev. 4): field paths such as `settings.browse.explore_grid_density` wrap
  without a hyphen being added (the build of msg721 showed "explore_grid_densi-ty", which
  reads as a different name). Turn hyphenation off for error text and let paths break after "."
  (a display-only U+200B after each dot is fine; copied or spoken text must not contain it).

---------------------------------------------------------------------------
## 4. Validate and Apply rules

- **Validate** runs the import check on the current text. It never writes settings or recovery
  data. Disabled while checking; enabled otherwise, including when nothing was edited.
- **Apply** is enabled when the text differs from what was loaded, isn't empty, and nothing is
  checking. Apply always checks the current text again (an earlier "valid" never counts).
  - Invalid → stay in the editor, show the invalid state; nothing is pushed.
  - Valid → push **Review Changes** (§5).
- After Validate or Apply, post a VoiceOver announcement with the status's first line.

---------------------------------------------------------------------------
## 5. Review Changes (pushed inside the editor sheet)

The existing Review Import content (`ReviewList`), pushed onto the editor's NavigationStack:
- Title "Review Changes"; system back button returns to the editor with the text untouched.
  No Cancel in this screen (the back button is the way out; Cancel would be a second exit).
- Intro: "These edits will replace your current configuration." The file-name line and the
  "{size} · Format version {n}" caption are hidden (there is no file).
- Changes, Ignored settings, missing-sections footer, overwrite card, fonts card: unchanged.
- Recovery note only with verified retention: "Your previous configuration will be kept so you
  can undo these changes." It sits in the review's existing footer position under Changes
  (accepted in build review, rev. 4).
- Bottom bar unchanged (pinned, 50 pt, borderedProminent), label **Apply**.
- Applying: the button shows `ProgressView` + "Applying configuration…"; back and all controls
  disabled.
- Success: the existing success layout with "Configuration applied"; toolbar "Done" closes the
  whole sheet; the Configuration page then shows the Undo row.
- Identical content (e.g. only spaces or comments changed): "No changes to apply" in place of
  the intro, primary button "Done", which closes the sheet.
- Settings changed while editing: the existing alert, with "Your configuration changed" /
  "Settings changed while you were editing. Review the changes again before applying." /
  "Review Again", "Cancel".
- Apply failed with verified previous state: alert "Couldn’t apply configuration" / "Your
  previous configuration is still in use. Your edits are still here." OK → back on the review;
  the editor text is kept. If the draft isn't kept, don't use that body (Camo's rule).

---------------------------------------------------------------------------
## 6. Cancel with edits

- Cancel when the text differs from what was loaded: `confirmationDialog` attached to the
  Cancel button: title "Discard edits?", message "Your edits haven’t been applied.",
  "Discard Edits" (destructive), "Keep Editing" (cancel). On iPhone with iOS 26 the system shows
  it as a popover from Cancel with no visible Keep Editing; tapping outside keeps editing.
  Accepted as platform behavior (same as the Undo dialog, msg406). The keyboard hides while it
  is open (prevents taps reaching the text).
- Not edited: Cancel closes immediately, no dialog.
- Closing never applies anything.

---------------------------------------------------------------------------
## 7. Accessibility and appearance

- All colors are system/semantic; dark mode needs nothing extra.
- Status icons are decorative (hidden); the text carries the state. Error buttons: label = the
  error line; hint "Moves the cursor to this line." (Camo to confirm).
- Contrast: everything you must act on (results, errors, the invalid title) is `.primary`.
  `.secondary` is only used for the helper and reassurance lines, the same style as iOS form
  footers (about 3.5:1 on `.bar`), matching the rest of the Configuration page.
- Every control at least 44 × 44 pt.
- Dynamic Type: the editor font and the status bar scale; at accessibility sizes Validate stacks
  under the status (§3).

---------------------------------------------------------------------------
## 8. Review checks (I'll measure your screenshots against these)

1. Configuration page: Edit Configuration is the 3rd row, same style as Export/Import.
2. Editor opens without the keyboard, helper text in the bottom bar, monospaced text.
3. Typing `"` with the system keyboard gives a straight quote.
4. Introduce an error at line ≥ 10: Validate shows red state + "Check line …, column …: …"; tapping it
   puts the cursor there. Settings unchanged (check another screen).
5. Typing after a valid check shows "Edits haven’t been checked."
6. Apply with an error stays in the editor; Apply with a valid edit pushes Review Changes with
   the edit listed, no file-name line.
7. Apply → success → Done closes the sheet; Undo row appears; Undo restores.
8. Cancel after editing shows the discard dialog; unchanged Cancel closes directly.
9. Keyboard up: the status bar sits on the keyboard, the text above it still scrolls.
10. Dark mode and AX3 screenshots of the editor with an error.
