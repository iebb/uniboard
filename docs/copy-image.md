# Uniboard — Copy Image copy

For @design and @developer. Scope from product messages 192/197: keyboard preview only, text visibly shown only; never hidden context or whole document. Image contains rendered text, not surrounding glass/controls. Preserve existing ordinary text-copy behavior. These strings do not assert that any permission or implementation has been verified.

## Exact strings

- Action: **Copy Image**
- Short explanation beside action: **Copies only the text shown here as a picture.**
- Destination limitation, shown in the same explanatory area: **Paste into apps that accept images. The text in the picture isn’t editable.**
- Optional font benefit, if space allows: **The picture keeps this appearance, even without the font.** This describes an image, not editable text formatting.
- In progress, only if noticeable: **Creating image…**
- Success: **Image copied**
- Success supporting line, if needed: **Paste it into an app that accepts images.**
- Failure title: **Couldn’t copy image**
- Failure body, no known cause: **Try again. Your text hasn’t changed.**
- Retry action: **Try Again**
- Dismiss action: **OK**
- Empty preview hint: **Show some text in the preview to copy an image.** Disable Copy Image when there is no renderable visible text; do not copy an empty image and report success.

Accessible action label: **Copy preview as image**.
Accessible action hint: **Copies only the text shown in this preview, not the whole document.**
Announce **Image copied** only after the image has been placed on the clipboard. Creating/rendering it alone is not success. Do not announce that it was pasted, sent or saved to Photos.

## Clipboard restriction

Use this neutral fallback when access is known to be restricted but the cause or remedy is not verified:

Title: **Image copying unavailable**
Body: **iOS isn’t allowing this keyboard to copy an image. You can still type normally.**
Action: **OK**

Do not show this for a generic rendering error, missing font or memory failure.

Only if developer verification establishes that enabling the iOS keyboard's Full Access setting is the required remedy, replace the body with:

**To copy images, allow Full Access for Uniboard in your keyboard settings. You can still type without it.**

Optional separate setup action: **How to Enable Full Access**, only if that help exists. Use **Open Settings** only if the implemented action really opens Settings; do not promise it opens the exact keyboard toggle unless verified. Keep **Not Now** as the dismissal if presenting an optional setup prompt.

Do not state that Full Access is required for ordinary typing, font appearance, or text insertion. Do not invent a clipboard-specific permission switch, claim this is Apple's own permission dialog, or add unverified data-privacy promises.

## Integration notes

- Use both the short explanation and the image-only destination limitation; one does not replace the other. The helper text can be presented compactly in two sentences.
- Copy Image does not change ordinary Copy Character / Copy Text actions elsewhere; those still copy Unicode text without a preview font.
- Never say “Copy all”, “Copy document” or “Copy formatted text”.
- No fixed character count in UI: the actual visible preview is the boundary, not the maximum context iOS supplied.
- Truncated/hidden surrounding text must not appear in the output. Do not claim the cursor or truncation controls are text to be exported.
- If export cannot match the visible preview, fail rather than quietly export more text or a substituted font.
- On failure preserve typed text, preview, and existing clipboard content where technically possible. The failure wording above promises unchanged text, not an unchanged clipboard unless that is verified.
