# Uniboard 1.3 — configuration editor copy

Minimal addition requested in msg697; product name unchanged. Exact English UI strings for Colo and Pluso. Does not authorize any scope beyond the current configuration editor, validation and protected apply.

## Entry and screen
- Configuration entry: **Edit Configuration**
- Screen title: **Edit Configuration**
- Editor accessibility label: **Configuration text**
- Helper: **Edit your configuration in TOML. Validate checks your edits without changing your settings. Apply saves them.**
- Actions: **Cancel**, **Validate**, **Apply**

## Validation
- Running: **Checking configuration…**
- Valid: **Configuration is valid. Your settings haven’t changed.**
- Valid with warnings: **Configuration is valid. Review the warnings before applying.**
- Changed since last check: **Edits haven’t been checked.** Clear any earlier valid indication when text changes.
- Invalid title: **Fix these errors before applying**
- Supporting text: **Your settings haven’t changed.**
- Error location: **Check line {line}, column {column}: {reason}**; reuse the checker’s existing full message in both import and editor, without adding a second location prefix. Omit unavailable location components, never guess.
- Reuse plain-language schema, field, range, duplicate and syntax errors from docs/font-rules-copy.md. Do not replace an actionable reason with only “Invalid TOML”.
- Empty editor: **Enter a configuration before validating or applying.** Do not interpret empty text as a request to reset everything.

Apply must validate the current text again; an earlier success must not authorize later edits. If Apply is disabled until validation, keep Validate available after changes. Validation must not write settings or recovery data.

## Apply and review
- Reuse the existing replacement review if needed for warnings, missing sections or changed settings; use **Review Changes** as the editor-specific review title and **Apply** as its primary action.
- Intro: **These edits will replace your current configuration.**
- Reset warning: **Sections missing from this configuration will reset to defaults.**
- Retain existing precise changes, unavailable-font warnings and reset disclosures. Do not introduce a second generic confirmation when the existing review already covers them.
- Recovery note, only with verified retention: **Your previous configuration will be kept so you can undo these changes.**
- In progress: **Applying configuration…**
- Success: **Configuration applied**
- Identical content: **No changes to apply**
- Failure title: **Couldn’t apply configuration**
- Failure body, only if unchanged/recovered: **Your previous configuration is still in use. Your edits are still here.** Preserve the draft on failure; if implementation does not, do not use this sentence.
- Concurrent change title: **Your configuration changed**
- Body: **Settings changed while you were editing. Review the changes again before applying.**
- Action: **Review Again**. Never overwrite newer settings on a stale validation result.

## Cancel after edits
- Title: **Discard edits?**
- Body: **Your edits haven’t been applied.**
- Destructive: **Discard Edits**
- Cancel: **Keep Editing**
No prompt when unchanged. Dismissing must not apply edits.

## Recovery terminology
Use **Undo Last Configuration Change** for the shared recovery entry if it now covers both imports and editor applies. Keep existing protection, do not create a second recovery history.
- Confirmation: **Undo last configuration change?**
- Body: **Restore your previous configuration. Changes made since then will also be replaced.**
- Primary: **Restore Previous Configuration**
- Secondary: **Cancel**
- Success: **Previous configuration restored**
- Recovery-row caption for an editor apply: **Applied {date, time}**, e.g. **Applied today at 18:40**. This is the successful apply time, not validation or draft-edit time. Keep **Imported {date, time}** for imports. If the source is not recorded reliably, use **Changed {date, time}** for either source rather than guessing.

## Listing follow-up, only after verification
No need to expand the short release notes yet. Once the replacement build is verified, add the following small line to the existing configuration description, if Ampo elects to update it:
EN: **Edit your configuration in the app and validate changes before applying them.**
JA: **アプリ内で設定を直接編集し、適用前に内容を検証できます。**
These are conditional proposed listing additions, not claims of completed implementation.
