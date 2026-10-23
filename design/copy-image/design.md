# Uniboard — Copy Image from keyboard preview

23 Oct 2026 · user190, product192/197. Focused addendum; separate from font and dragging implementation. Source: Keyboard/KeyboardViewController.swift textPreviewRow (around1690) and refreshTextPreview (around157).

## Scope and correction
The requested surface is the keyboard's existing text-preview strip above its controls, not the app's single-character detail or font-comparison screen. Source currently supplies at most48 characters before and48 after the cursor and visually truncates those again. Product197 requires ONLY the actually VISIBLE text, never hidden context or the whole document. This supersedes any interpretation of 'all nearby text'. Existing plain-text copying elsewhere and normal typing remain untouched. No new permission for typing, account, network upload, Photos permission, automatic insertion or new settings page.

## Placement and hierarchy
- Preserve preview-row height, rounded8 surface, font selection and current layout. Add a trailing44pt-wide button inside that row; SF Symbol ellipsis.circle,18pt medium, existing KeyboardPalette.accent. Accessibility label 'Preview actions'. Minimum44pt touch height via existing row height/hit area; if compact metrics are below44, use non-overlapping expanded target or existing host layout constraints rather than overlapping typing keys.
- This button opens a compact action panel WITHIN the keyboard's bounds, overlaying existing key content rather than increasing keyboard height or taking over the host app. Reuse existing keyboard inspection presentation machinery if practical. No full-screen system sheet. Dismiss on outside tap within keyboard or explicit Close xmark44pt at top trailing. Preserve host text/cursor, search query and input mode throughout.
- Panel width min(available keyboard width-16,360), radius16, native semantic opaque secondarySystemGroupedBackground if material cannot guarantee legibility. Padding16; vertical spacing12. At larger text sizes scroll panel contents within current keyboard bounds; Close remains reachable. Native system type, no new accent.
- Header 'Text preview' headline17 semibold; Close at trailing.
- Image thumbnail below, full available width, intrinsic aspect ratio, minimum48pt height, maximum96pt before scrolling. It shows exactly the frozen export crop. No caret, ellipsis button, glass or surrounding keys. Empty areas outside the crop use a neutral container; do not scale down to illegibility: allow horizontal scroll when needed rather than changing image content.
- Under thumbnail: footnote13 secondary copywriter explanation of visible-text-only and supported-image-paste limits. It must remain visible before the copy action; no hidden help-only disclosure.
- Primary 'Copy Image' Label with SF Symbol photo.on.rectangle,17pt semibold; native borderedProminent, minimum44pt height, full width. No additional text-copy command is introduced to this strip: existing normal text-copy actions elsewhere remain as-is.
- Final wording belongs to Camo; the labels provided by user/product ('Copy Image') are fixed. Other strings in mockup are provisional pending copy handoff.

## Exactly what is copied
1. At opening the action panel, freeze the current preview's VISIBLE rendered text region after reserving the actions-button space. Capture only text visible at that moment, not the underlying before/after buffers. Keep the thumbnail frozen so the user can inspect the exact result before copying; later host edits require closing/reopening rather than silently changing what gets copied.
2. Use the SAME font runs/glyph shaping/size/line order shown in that viewport, including supported PUA glyphs, combining sequences and color emoji. Never substitute a default font during image rendering. Do not render the source buffers at unconstrained width because that would reveal hidden text. If the renderer cannot reliably reproduce the visible range, block the action with the copywriter's error rather than exporting extra text.
3. Render only text, removing caret, control icons, material/glass, border, selection markers and key chrome. Use a plain opaque canvas with8 logical pt padding on all sides of the visible glyph bounds. Keep the preview text's resolved foreground and a matching solid systemBackground (white in light, black in dark) for legibility; color emoji keep their colors. Do not export glass translucency, a screenshot of the host, wallpaper or shadows. No watermark or font metadata in pixels.
4. Match viewport clipping/truncation: if an ellipsis is actually displayed as truncation, retain it in the image as an honest indicator of an excerpt. Never use an ellipsis to claim the full text was copied. Do not introduce any additional truncation. Ensure glyph ink (including combining marks/descenders) is not clipped by the output padding. Preserve the visible crop rather than revealing partially hidden glyphs.
5. PNG raster, scale3x logical points for crisp paste, lossless and opaque. Clipboard only on explicit final tap; no auto-save/download or pasteboard read. Developer chooses bounded renderer implementation appropriate to extension memory; fail safely if limits exceeded, do not silently reduce the visible text.
6. Copying replaces clipboard image only on successful rendering/write. Never erase existing clipboard on failure or change host text. Do not automatically paste or send anything to the host. TextDocumentProxy insertion cannot insert an image; user pastes in an image-capable app themselves.

## States
- Ready: thumbnail and explanatory text, Copy Image enabled. Font/render availability must be established before this state.
- Empty/whitespace-only/invisible-without-visible-ink: button disabled and copywriter empty message; never claim a blank image was copied. Keep Close. Don't export diagnostic names/boxes in place of actual text unless they were literally visible in the preview; if no usable glyph exists prefer unavailable error.
- Generating: spinner occupies primary button's icon position; label is copywriter progress text. Disable repeated copy taps, retain thumbnail and Close. No typing-blocking global spinner; do not replace unrelated keyboard controls after dismissal.
- Success: primary becomes checkmark + copywriter success text for2 seconds, then returns to Copy Image. Keep panel open and thumbnail unchanged; user's next action may be Close or switch to paste. VoiceOver announces once. Successful image copy never implies destination app accepts images.
- Render failure/font gone: inline error below thumbnail, body/footnote, semantic error color with exclamationmark.triangle and wording; Copy Image becomes retry using the same frozen visible content only if fonts remain available. If that snapshot cannot be retained, require close/reopen. No hidden fallback substitution or blank success.
- Clipboard access denied/unavailable: explain only the missing capability and that normal typing still works. No automatic settings jump or permission enablement. Display Full Access-specific wording ONLY if developer verifies it is the actual required capability for this extension/API. Never show an unverified permission requirement. Existing text copy/typing remain unaffected; Close always works.
- Cancel/dismiss/background: discard transient export/thumbnail and any not-yet-committed result; don't change clipboard after a cancelled operation completes asynchronously. Retain no host text in logs, analytics or saved files.

## Accessibility and appearance
- VoiceOver order: panel title, Close, image ('Image preview of visible text' plus the visible plain-text equivalent where available), explanation, primary action, error. Never expose hidden buffer text through thumbnail/accessibility label.
- Current text-preview accessibilityValue concatenates both buffers; developer must ensure the export UI does not reuse it as the exported text or image's accessibility equivalent. This task does not authorize reading additional host context.
- Main export button44pt minimum and visible text label; preview-actions button uses accessible name rather than icon name. Dark appearance uses semantic controls; raster remains readable on its own opaque backing after pasting into the opposite appearance.
- Reduce Motion: no animated thumbnail zoom; native fade <=120ms. Large type wraps explanation/action, panel scrolls vertically, never pushes host content offscreen. Preserve Unicode logical order and real glyph shaping, especially RTL/mixed direction; no hand-joining isolated glyph bitmaps.

## Verification (developer owns implementation)
- Exact visible viewport versus exported PNG for long truncated text both sides of cursor. Verify a known hidden sentinel in buffer is absent from image AND accompanying accessible text.
- Render PUA font, combining marks, emoji/color, RTL/mixed text and changed fonts with the same appearance as preview; no caret/control/glass in output.
- Clipboard copied image opens/pastes in at least one real image-capable simulator app; recipient font need not exist. Plain-text-only destination is not claimed supported.
- Dark exported image pasted into light app and vice versa remains legible. Screenshot includes none of the host's content outside preview.
- Permission states checked with/without actual extension capability, plus empty/error/cancel/repeated taps; no clipboard changes on failure or cancelled work, no host text changes at any point.
- Ordinary typing, existing plain-text copy, search and top/lower backspace behavior preserved.

## Reference
Primary reference is the existing native preview row and its inspection presentation. Retain system typography/semantic surfaces, existing single accent. Apple native copy convention motivates distinct action labeling, not a new ornamental style. This is a focused engineering handoff; actual export feasibility and permission behavior must be verified, not assumed.
