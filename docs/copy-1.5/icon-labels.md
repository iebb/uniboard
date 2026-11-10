# Uniboard 1.5 — final app-icon labels

Camo, 31 October 2026. Applies to Colo’s artwork in msg1592. Already integrated into `docs/copy-1.5/copy.md`, revision 2.2. This finalizes UI labels, not a new product name, purchase terms or release readiness.

## Names and spoken controls

Keep this order; do not rename the supplied asset sets.

| Visible name | Preview control | Apply control | Existing asset set |
| --- | --- | --- | --- |
| Original | Preview Original icon | Use Original Icon | Existing primary icon; unchanged |
| Night | Preview Night icon | Use Night icon | AppIcon-Night |
| Paper | Preview Paper icon | Use Paper icon | AppIcon-Paper |
| Hangul | Preview Hangul icon | Use Hangul icon | AppIcon-Hangul |
| Sunrise | Preview Sunrise icon | Use Sunrise icon | AppIcon-Sunrise |

Night fits the dark keyboard and orange accent. Paper fits the cream-and-red Light art. Hangul identifies the Korean syllable on its accent key. Sunrise fits the orange-and-yellow Light art. The same name persists in every appearance.

**Hangul** is only an icon choice, not a language purchase or input-mode selector. If explanatory copy is needed: **Changing the app icon doesn’t change your keyboard or input mode.**

Keep the existing visible **Use This Icon** and **Use Original Icon** actions, **Current Icon** badge/value, **View Support Options** navigation for a locked icon and all purchase/apply state strings. A selected preview is not the current icon until application succeeds.

## Preview appearances

Alternate icons: **Light**, **Dark**, **Tinted**. Accessible picker label: **Preview Appearance**. Hint: **Changes only the preview.**

Original: show its existing Light artwork and hide the appearance picker. This matches Colo’s msg1592 and supersedes the archive README’s earlier “shows Light only” line. Do not add a disabled picker or invent Dark/Tinted artwork for Original.

Keep: **Previewing an icon doesn’t buy or apply it.**

For a static preview image, use the complete localizable template matching the actual appearance:

- **{icon name} icon, light appearance**
- **{icon name} icon, dark appearance**
- **{icon name} icon, tinted appearance**

For a preview control, use the control label in the table. Combine its thumbnail and text into one accessible element; do not announce the same name twice.

## Accuracy and decision boundaries

Night, Paper and Sunrise have byte-identical supplied Tinted artwork. There are four alternate icon choices, not twelve different designs; do not promise that all choices remain visually distinct in every appearance. This observation does not request an artwork change.

Original remains free. Korean typing and language downloads remain free. The open support-option decision is not resolved by these labels; do not add a yearly promise or future-icon entitlement.

Artwork files were inspected for naming. No app code/catalog, purchase setting or release metadata was changed. On-device/system rendering and icon-switch success still require engineering verification.
