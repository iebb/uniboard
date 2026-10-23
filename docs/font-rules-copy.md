# Uniboard — font rules and configuration copy

Final English copy handoff for product brief msg278. Next increment only; not the currently finishing TestFlight. Existing product name retained. Scope/implementation contract remains in font-rules-brief.md. These are exact UI strings, not implementation or verification claims.

## Terms and titles

Settings entries and page titles: **Font Rules**, **Configuration**.
Use **Preferred font** for a requested rendering choice, **Font rule** for a selector plus choice, and **Configuration** for the complete portable settings collection (including layouts, favorites and colors). Do not call a configuration a font pack or a backup of everything.
Selector types: **Code Point**, **Range**, **Unicode Block**. A code point is not necessarily an entire visible character; preserve this distinction in this advanced editor. Range endpoints: **From**, **To**. Font field: **Preferred font**. Block field: **Unicode block**.

Actions: **Add Rule**, **Edit Rule**, **Save**, **Cancel**, **Remove Rule**.
Character/detail entry: **Set Preferred Font**; existing rule: **Change Preferred Font** and **Clear Preference**.
Clearing a preference removes that rule, not its downloaded font.

## Explanation and priority

Page helper: **Choose how text looks in Uniboard. Other apps still choose how inserted text looks.**
Priority helper: **Code point rules take priority over ranges, then blocks, then the default font.**
Range helper: **For overlapping ranges, the narrower range wins. If they are equally wide, the later rule wins.**
Fallback helper: **If a font is missing or can’t display the text, Uniboard tries the next matching rule, then its default fonts.**
Advanced sequence note: **Joined characters and emoji stay together. Their first main character determines the rule, and the font must support the whole sequence.**
Expanded help, where needed: **The first code point that isn’t a combining mark, joiner or variation selector determines the rule. If there isn’t one, the first code point does.**
Range bounds helper: **Includes both endpoints.**
Rule order caption: **Later rules win equal-width ties.** Preserve the actual saved order; sorting must not suggest a different precedence.
Comparison-view note, if necessary: **This preview shows the selected font, not your font rules.**

## Font rules states

| State | Exact wording | Action |
|---|---|---|
| Empty list | **No font rules yet** / **Choose a preferred font for a code point, range or Unicode block.** | Add Rule |
| Applied choice | **Using {font name}** | None |
| Font asset missing | **Font unavailable** / **This rule is saved. It will apply when the font is available and supports the text.** | Existing explicit font-library/download route only |
| Font lacks required support | **Font can’t display this text** / **Using the next matching font.** | Edit Rule |
| Earlier/higher-priority rule applies | **Another rule takes priority** | View Rule, only if navigable |
| Rule removed | **Rule removed** | None |

Only show “Using…” when the actual effective font is known. If the choice falls all the way to default, say **Using default fonts** instead of inventing a named substitute. Do not use “Installed” for a merely referenced font. Never download fonts automatically to make a rule work.

Remove confirmation if the design uses one: **Remove this font rule?** / **Uniboard will use the next matching rule or its default fonts. The font itself won’t be removed.** Actions: **Remove Rule**, **Cancel**.

## Editor validation

- Invalid scalar: **Enter a valid Unicode code point, such as U+0041.**
- Surrogate scalar/endpoint: **Surrogate code points can’t be used here.**
- Reversed range: **The end of the range must come after or equal the start.**
- Exact duplicate selector: **A rule for this code point already exists.** / **A rule for this range already exists.** / **A rule for this block already exists.** Use matching variant.
- Unknown block: **This Unicode block isn’t recognized.**
- Missing selection: **Choose a font.**

Do not imply all numbers between 0 and 10FFFF are valid scalars. Ranges that cross surrogate space skip it per the brief, not silently reject valid endpoints.

## Configuration page

Actions: **Export Configuration**, **Import Configuration**, **Undo Last Import** (only when a recoverable previous configuration exists).
Description: **Save your settings, layouts, favorites, font rules and image colors in a TOML file, or import a configuration from Files.**
Privacy note before sharing: **Favorites and custom key text are included and may be personal. Typing history, scratchpad text and font files aren’t included.**
Portability note: **Fonts aren’t included or downloaded automatically. Some font choices may need fonts added on the other device.**

Export in progress: **Preparing configuration…**
Export prepared: **Configuration ready to share**. Do not say exported/saved until the destination flow confirms it; opening a share sheet is not proof of saving.
Failure: **Couldn’t export configuration** / **Try again. Your configuration hasn’t changed.** / **Try Again**.

## Import review

Page title: **Review Import**.
Intro: **This will replace your current configuration. Review the changes before continuing.**
Missing-section warning: **Sections missing from this file will reset to defaults.**
Section labels: **Settings**, **Layouts and Keys**, **Favorites**, **Font Choices and Rules**, **Image Colors**. Expand categories where actual inventory requires it; don’t omit changes hidden under a generic total.
Change labels: **Will change**, **Will reset to defaults**, **Unchanged**.
Explicit overwrite note: **Your current favorites and custom key layouts will be replaced.** Show when those categories change/reset, not on an identical import.
Font warning: **{count} fonts unavailable**; singular **1 font unavailable**. Supporting text: **Their rules will be kept. Other fonts will be used until these fonts are available. Nothing will be downloaded.**
Backup note: **Your previous configuration will be kept so you can undo this import.** Only show once that retention path exists.
Primary action: **Replace Configuration**. Secondary: **Cancel**. No “Merge” action in this increment.
Progress: **Replacing configuration…**
Success: **Configuration imported**.

Validation happens before any write. File errors must not partially replace configuration.

## Import errors and conflicts

Generic title: **Couldn’t import configuration**.
Always add, when no changes were committed: **Your current configuration hasn’t changed.**
Use one actionable cause:
- Syntax: **Check line {line}, column {column}: {plain-language reason}.** Only show location if parser provides it.
- Unsupported schema: **This configuration version isn’t supported by this version of Uniboard.**
- Missing schema: **The file is missing its configuration version.**
- Unknown setting: **Unrecognized setting: {key}.**
- Wrong type/range: **Check {field}: {expected value or allowed range}.**
- Duplicate: **{key or selector} appears more than once.**
- Invalid block: **The Unicode block {name} isn’t recognized.**
- Invalid font reference: **The font reference in {field} isn’t valid.** Distinct from a valid reference to a font not present locally, which is only a warning.
- Too large: **This file exceeds the {limit} import limit.** Use the actual documented size, not a guessed limit.
- Section limit: **{section} exceeds the limit of {limit}.**
- Unreadable file: **The file couldn’t be opened. Choose it again in Files.**

Never echo full file contents or custom key strings in an error; use field names and locations. Treat source text as text, not markup.

Changed since review:
Title: **Your configuration changed**.
Body: **Changes were made after this preview. Review the import again before replacing your configuration.**
Action: **Review Again**; secondary **Cancel**. Do not apply stale replacements.

Apply failure with verified intact/recovered state:
**Couldn’t replace configuration** / **Your previous configuration is still in use.**
If recovery itself is not established, do not claim it succeeded; developer must supply the actual recoverable state for accurate copy.

## Undo

Confirmation title: **Undo last import?**
Body: **Restore the configuration you had before the last import.**
When newer edits exist, add: **Changes made since that import will also be replaced.**
Actions: **Restore Previous Configuration**, **Cancel**.
Success: **Previous configuration restored**.
Failure: **Couldn’t restore configuration** / **Your current configuration hasn’t changed.** Only assert no change when verified.

## Acceptance

Check that real implementation uses the same rule priority, includes all declared configuration categories, exposes every reset/replacement, never exports typing history, and does not claim font availability or successful import/export prematurely. No text here adds automatic downloads, merge mode, sequence rules, cloud sync or a new release authorization.

## Added design labels — reviewed after msg283

- Replace **Try a Character** with **Try Text**: the field accepts more than one character. Keep **Type or paste text**. For mixed input, never assign one named font/rule to the entire sample unless all of it really shares that result; use **Multiple fonts used** when applicable, with per-character results if the design supports them.
- Keep **Code point rule**, **Range rule {range}**, **Unicode block rule {block}**. Replace **No rule** with **Default fonts** when that is the actual result; saved but unavailable rules are not absent rules.
- Keep **Code Points**, **Ranges**, **Unicode Blocks**, **Preferred Font**, **Search fonts**, **Applies To**, **Choose**, **None**, **Your Fonts**, **Google Fonts**, **Preview Fonts**, and accessibility hint **Edit rule**.
- Range size: **1 code point** / **{n} code points**. Count valid scalars, not surrogate slots.
- Verified coverage: **Supports {n} of {m} code points**. Counts must cover the full selected range/block, not just the 12 sample characters. If only the sample was checked, say **Supports {n} of {m} preview characters** instead. A glyph count is not proof of correct language shaping.
- Hidden unsupported faces disclosure: **Show 1 Unsupported Font** / **Show {n} Unsupported Fonts**. Helper: **These fonts can’t display this character.** Only use this for verified lack of support, not pending checks or missing files.
- Override count: **Another rule takes priority for 1 code point.** / **Another rule takes priority for {n} code points.** Make it one localized sentence, not concatenated fragments.
- Keep **U+0041 or a character**. If pasted text has multiple scalars, reject it with **Enter one code point. This text contains more than one.** Do not silently take the first scalar or confuse a joined character with a scalar.
- Keep **Checking {file name}…**, **1 More Problem** / **{n} More Problems**, **Changes**, **Imported {date, time}**. Imported time is a successful local import, not the file's modification time.
- Suggested export name: **Uniboard-Configuration-{YYYY-MM-DD}.toml**; local export date, no account identity or custom key text in the filename. Platform handles filename collisions.
- Identical import: **No changes to import** with **Done**. Do not announce **Configuration imported** if nothing was applied.
- Confirmed by product msg284: keep **Turn On** and **Rules apply only when Extra Unicode Fonts is on.** Accessible action label: **Turn on Extra Unicode Fonts**. Off pauses rules without deleting them. Import may change the switch only through an explicitly reviewed and confirmed replacement; show **Extra Unicode Fonts: Off → On** or **Extra Unicode Fonts: On → Off** in the import preview when applicable. Editing/importing rules alone must not silently enable the switch.

Coverage is always based on the named face, not a fallback font. Preserve the brief's saved-but-unavailable rules even if the picker cannot select a missing face. Selecting a face from a rule editor is not an implicit download or permission grant.
