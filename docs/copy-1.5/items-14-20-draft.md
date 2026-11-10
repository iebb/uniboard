## 14. Reset emoji size

Keep **Emoji Size**, **Smaller**, and **Larger**. Add **Automatic** beside those choices, selected when size follows the available width.

- Accessible label: **Automatic emoji size**
- Hint: **Fits emoji to the available width.**
- Optional helper: **Only the emoji size changes. Your categories, sorting and saved emoji stay the same.**

Use Automatic rather than a broad Reset action. This is app-only; it does not resize keyboard keys.

## 15. Hide repeated skin-tone variants while browsing

- Control/section: **Skin-Tone Variants**
- Choices: **All Variants** / **Fewer Variants**
- Default: **All Variants**
- Helper: **Show fewer repeated skin-tone variants while browsing. Saved emoji stay the same, and specific variants still appear when you search for them.**
- If a visible reset action is offered: **Show All Variants**
- Accessible value: the selected choice, not “On” for an unspecified filter.

Do not call a skin tone “normal,” replace a chosen emoji with a different tone, or imply that this changes the person's preferred tone. Whole sequences remain exact, including multi-person emoji. The helper requires the explicit-variant search exception in item 15; do not ship it before that behavior works. This preference applies to browsing in the app and keyboard, not saved entries.

## 16. Undo the last row arrangement change

- Visible action: **Undo Arrangement**
- Accessible hint: **Restores the arrangement before your last change on this page.**
- Success, if feedback is needed: **Arrangement restored**
- Safely invalidated undo: **Undo Arrangement is no longer available because the page changed. Your later changes have been kept.**
- Save failure: **Couldn’t restore the arrangement. Try again.** Only add **Your arrangement hasn’t changed.** if the write is known to be atomic.

The action is one step, not an edit history. Do not imply that page changes, later conflicting edits, text entry or configuration imports can be undone here. Keep **Undo Last Configuration Change** separate and unchanged. Hide/disable a nonexistent undo rather than showing an error on every page.

Keep the existing partial local-copy notice exactly when the shared save succeeds:

**Your change is saved and available to the keyboard, but the app couldn’t update its local copy.**

A successful shared restore with a secondary local-copy failure is not “Couldn’t restore.”

## 17. Select rows directly

- Scope control: **Rows**
- Scope choices: **All Rows** / **Row {n}**
- Scope helper replacing “Select a key to align only its row”: **Choose a row to change its alignment without editing a key.**
- Direct row selector accessible label: **Select row {n}**
- Selected value/trait: **Selected**
- Alignment accessible label remains **Alignment for all rows** / **Alignment for row {n}**.

Retain **Left**, **Center**, **Right**, **Spread**, and the read-only **Mixed** state. Retain width-limit warnings, physical left/right meanings, and **Rows of Ten, Align Left**. Row numbers are one-based. Favorites has no row-alignment scope.

Existing key instruction remains **Tap a key to change its choices. Drag a key to move it.** The new row instruction should sit with the row control, not imply that a key tap is now required for alignment.

## 18. Explain symbol-page changes

Show one nonblocking message after the relevant edit, only when the merged/split state changes. Use the actual reason supplied by layout calculation, not a guess from key count. Do not replay on launch.

- Merged: **Symbols now fit on one page because ABC types all ten digits. Your key actions are unchanged.**
- Split because digits are missing/remapped: **123 and #+= are separate again because ABC no longer types all ten digits. Your key actions are unchanged.**
- Split because of space: **123 and #+= are separate again because the symbols no longer fit on one page. Your key actions are unchanged.**

These messages do not rename the saved Symbols page or imply that any layout was reset. Show the digit reason first if both conditions fail; do not claim only one underlying condition failed. If the merge algorithm uses labels beyond ABC/123/#+=, substitute the visible labels consistently. Announce the message once for accessibility without taking focus from the edit.

## 19. Font files, styles and capacity

Keep screen **Font Downloads**. Within the file-management portion:

- Section: **Your Fonts**. Separate groups **Font Files** and **Installed Fonts**; installed-font references carry **Installed on This Device**. File Size is shown only for real downloaded/imported files.
- Capacity label: **Font Capacity**
- Capacity value: **{used} of 16**
- Capacity helper: **Each added font file or installed font counts once. A file can contain several styles.**
- Remaining: **You can add {free} more font files or installed fonts.** / **You can add 1 more font file or installed font.**
- Full: **The limit of 16 has been reached. Remove an added font to make room.**
- Empty: **No fonts added**
- Empty helper: **Browse Google Fonts or add a font file.**
- Existing actions: **Browse Google Fonts**, **Add Font File**, **Use Installed Font** where currently available.

Source audit: `CustomFontStore.maximumFonts` is 16 and both `add` and `addInstalled` use `fonts.count`. The counter must include added installed-font references, not mislabel them as downloaded files. Bundled/system fonts not explicitly added here and separate Unicode packs are outside this counter. Each actual shared downloaded file still counts once, not once per style. An installed-font reference has no copied file-size value: show **Installed on This Device**, not “0 bytes.” No storage-policy change is requested by this copy.

Per file:

- **File Size** — verified local size; unknown **Size unavailable**.
- **Styles** — actual names, including Normal/Italic/width/weight where applicable.
- Shared-file helper: **Includes {n} styles in one file.**
- Compact line: **1 file · {n} styles · {size}**; correct singular **1 style**.
- **Used by Font Rules** — show actual rules referencing styles in this file.
- Empty references: **No font rules use this file.** Only after the reference check completes.

Keep **Keyboard Unverified** for untested keyboard availability and **App Only** only for verified unavailability. Downloading does not install a font for use in other apps. Use **Fonts change the preview here. Other apps choose how inserted text looks.** when that distinction needs explanation.

Removal:

- Shared file action: **Remove File ({n} Styles)**; single style **Remove File**.
- Confirmation: **Stop using this font file?**
- Body: **This file will no longer provide styles in Uniboard. Styles available from other files will stay available.**
- If rules refer to it: **Your font rules will be kept. Other fonts will be used where a referenced style is no longer available.** Show the affected rules before confirming.
- Destructive action: **Remove File**
- Cancel: **Cancel**
- Retained-file explanation when applicable: **Some font files remain stored after you stop using them. Removing a file here may not free device storage immediately.**
- For an installed-font reference, use **Stop Using Font** instead of Remove File, with **This stops using the font in Uniboard. It doesn’t uninstall the font from this device.** Retain affected-rule warnings.

Do not promise freed bytes immediately, delete rules automatically, remove other files without consent, or confuse style count with file capacity. The 40 MiB per-file limit remains as implemented; no cap increase is implied.

## 20. Support Us and app icons

### Commercial decision boundary

The user's one-time icon unlock request is known. Whether yearly remains and what it provides are still open. The strings below cover the one-time option and common purchase/icon states only; they do not decide the yearly option or its benefits. Do not create a subscription promise, cadence, expiry policy, annual price label, or future-icon entitlement from this document. Ato/Natun must settle those, with Ampo's review, before final yearly copy.

Purchases and promotion belong only in the containing app. Nothing here goes in the keyboard. Use StoreKit's actual localized price, never hard-code $3.99 in UI. No new account or purchase-reporting consent is implied.

### Support screen

- Screen/Settings row: **Support Us**
- Heading: **Support Uniboard**
- Body: **Help support Uniboard and unlock extra app icons. Typing, language conversion and language downloads stay free.**
- One-time offer title: **One-Time Support**
- One-time offer detail: **A one-time purchase that permanently unlocks the icons shown here.**
- Price line: **{localized price} once**
- Purchase action: **Unlock Icons — {localized price}**
- Restore: **Restore Purchases**
- Legal links: **Privacy Policy** / **Terms of Use**, pointing to real approved destinations.

“Permanently” describes the non-consumable entitlement, not immunity from refunds/revocation or a promise to include every future icon. Clearly identify the icons included in this purchase. Do not say “donation,” “all future icons,” or “lifetime updates.”

### Purchase states

| State | Exact copy / action |
| --- | --- |
| Loading product details | **Loading purchase options…** |
| Price/product unavailable | **Purchase options aren’t available right now. Try again later.** / **Try Again** |
| No connection detected | **Connect to the internet to load purchase options or restore purchases.** |
| Purchase in progress | **Completing purchase…** |
| Pending approval | **Purchase pending** / **Your purchase is waiting for approval. The icons will unlock after it’s approved and verified.** |
| Explicit user cancellation | Return quietly to the offer; no alarming failure message. |
| Verified success | **Thank you for supporting Uniboard. Your extra icons are unlocked.** / **Choose an Icon** |
| Unverified transaction | **We couldn’t verify this purchase. Try Restore Purchases before buying again.** / **Restore Purchases** |
| Generic purchase failure | **The purchase couldn’t be completed. Try again later.** |
| Restore in progress | **Restoring purchases…** |
| Verified restore | **Your extra icons have been restored.** |
| Successful check, no entitlement | **No icon purchase was found for this App Store account.** |
| Restore/network failure | **Purchases couldn’t be restored. Check your connection and try again.** |
| Already entitled | **Icons Unlocked** / **Choose an Icon**; no duplicate purchase prompt. |

Do not call a failed restore “No purchases found.” Do not assert that Apple charged nothing after a verification/network failure. Existing verified entitlement should not be represented as lost solely because the device is offline; implementation owns that state. Keep errors free of raw server details, identifiers, receipt text or file paths.

### App Icons

- Screen/Settings row: **App Icons**
- Original icon: **Original**
- Current icon badge/value: **Current Icon**
- Preview heading: **Icon Preview**
- Preview helper, where needed: **Previewing an icon doesn’t buy or apply it.**
- Explicit apply action: **Use This Icon**
- Return to original: **Use Original Icon**
- Locked icon action: **View Support Options**; it navigates, not purchases.
- Applying: **Changing icon…**
- Success: **App icon changed**
- Failure: **The app icon couldn’t be changed. Try again.**
- Accessible preview label: **Preview {icon name} icon**
- Accessible apply label: **Use {icon name} icon**

Colo owns the actual collection; do not invent names for unseen artwork. Once designs exist, use short descriptive names that distinguish them and supply spoken labels for their previews. Keep Original available without a purchase. Never announce a changed icon until the platform confirms it. Do not promise all appearances if assets have not been checked.

## Copy-wide implementation checks

- Full templates must be localizable units. Use real plural handling and localized sizes/prices/numbers; never stitch grammar around a translated count.
- User dictionary/page names and exact Unicode outputs are content, not localization keys. Display safely without silently trimming or normalizing them.
- Announcements must describe completed state, never speculative success. Avoid repetitive progress announcements.
- This is a design/implementation copy handoff, not proof that twenty features have shipped. Release copy follows the verified implementation.
