# Uniboard — larger Copy Image panel (design spec)

23 Oct 2026 · user msg315 ("Make it larger, overcrowded here now", screenshot
of build 48), Ato msg316 (fill the available keyboard area, more vertical
room for colors, targets not smaller, Close + Copy Image always visible,
the rest reachable by scrolling). Supersedes the container and spacing parts
of `copy-image-colors.md` and the panel code at KeyboardViewController
~L2044–2120. Colors, presets, strings, states, VoiceOver and copy behavior
are unchanged. Mockup: artifact "Uniboard — larger Copy Image panel"
(illustrative, dark, 440 pt phone, top row already removed); screenshots
A-fills-keyboard.png and B-keyboard-grows.png beside this file. Where a
screenshot and this text disagree, this text wins.

## What was wrong in build 48 (measured from the user's screenshot, 440 pt phone)
1. Card 360 pt wide on a 440 pt keyboard: 40 pt of dimmed keys show on each
   side, which reads as clutter.
2. The scroll body ends mid-swatch with no scroll cue ("Text" row cut in half).
3. Copy Image button is 58 pt tall (borderedProminent + minHeight 44 label),
   a capsule: 14 pt more than needed, taken from the colors.
4. Chips 8 pt apart, swatch lines 0 gap, sections 12/8/6 pt apart: dense.
5. After the top row is removed (msg318–320) the keyboard gets ~41 pt
   shorter, so the same layout would be even tighter.

## 1. Container
- The panel covers the whole keyboard view: card = keyboard bounds inset
  4 pt on all four sides (the key gutter), radius 16 continuous,
  `secondarySystemGroupedBackground`. No max width on iPhone (portrait or
  landscape). iPad: width min(keyboard width − 8, 640), centered.
- Keys underneath are hidden while it is open (opacity 0, no hits,
  accessibilityHidden), not dimmed. The 18 % black backdrop goes away, and
  so does tap-outside-to-close (there is no outside left); Close is the way
  out, plus VoiceOver escape (`.accessibilityAction(.escape)` → close).
- Open/close: the existing 0.12 s easeOut opacity fade.
- Inspect Text (next update) uses this same container instead of its 360 pt
  card; its §2 sizes are replaced by this section.

## 2. Layout inside the card (top → bottom)
- Header, pinned, 44 pt: "Text preview" `.headline` at 16 pt from the
  leading edge; Close `xmark` 15 pt semibold `.secondary` in a 44 × 44
  target whose trailing edge is 4 pt from the card edge. Unchanged strings
  and identifiers.
- Body: `ScrollView(.vertical)` always (drop the ViewThatFits), indicators
  `.automatic`, `flashScrollIndicators` on open (iOS 17+:
  `.scrollIndicatorsFlash(onAppear: true)`). Content padding 16 pt sides,
  0 top, 12 pt bottom. VStack spacing 12:
  1. Thumbnail: full width, height clamp 48–96 (unchanged), radius 10,
     `tertiarySystemFill` behind.
  2. Colors caption (footnote, secondary, unchanged text), 6 pt, then the
     chip row: 44 × 44 chips, radius 10, **12 pt apart** (was 8), 4 pt ring
     clearance on every side (unchanged). Five chips need 268 pt, so the row
     never scrolls on iPhone at default text size; keep the horizontal
     ScrollView for very large text.
  3. Custom only, 8 pt below the chips: the Text and Background lines,
     4 pt apart. Each line: label (footnote, secondary) in a fixed 84 pt
     leading column, then the swatches in a horizontal ScrollView.
     Swatch circle **30 pt** (was 28) centered in its 44 × 44 tap area, hairline
     separator border, selection ring 2 pt accent at 38 pt diameter. Line
     height 52 (44 + 4 clearance top and bottom). When a line overflows,
     its trailing 20 pt fades to clear (`.mask` with a linear gradient) so
     the cut-off swatch reads as "more this way".
  4. Explanation footnote (unchanged).
  Readability note (review msg343): when it applies it replaces the caption
  text on the caption line ("Colors · Custom" → exclamationmark.circle +
  note), footnote, .secondary, lineLimit 2; no note row under the swatches.
- No scroll-edge effect on the body (iOS 26): `keyboardUnmaskedScrollEdges()`
  on the ScrollView; header and footer are opaque (review msg343).
- When the user picks Custom, scroll the body so the Background line is
  fully visible (`ScrollViewReader.scrollTo("customLines", anchor:
  .bottom)`, 0.25 s easeInOut; no animation with Reduce Motion). Don't
  scroll on later swatch taps.
- Footer, pinned: 0.5 pt `separator` hairline across the card, then 8 pt,
  then the action, then 12 pt to the card's bottom edge. Any notice keeps
  its place above the action (unchanged rules, 35 % height cap).
  Copy Image / Try Again / OK: **44 pt tall** (was 58), full width,
  rounded rectangle radius 12 (`.buttonBorderShape(.roundedRectangle(radius:
  12))`), 17 pt semibold, `photo.on.rectangle` icon. Labels, hint,
  identifiers and disabled rules unchanged.

Heights on an iPhone in portrait, default text size, top row gone
(typing height 282 pt): card 274 → header 44 + footer 64 + body 166.

## 3. DECIDED: B — keyboard grows while the panel is open (user msg328)
Option A (keep today's height) was not chosen; it survives only as the
fallback below for landscape, iPad and hosts that refuse the height.
- iPhone portrait only (`!isPad && !isCompactLayout`): while the panel is
  open the keyboard is **96 pt taller** (282 → 378 pt). Then the card is
  370 and the body 262, which fits the thumbnail, chips and both Custom
  lines (252 pt) without scrolling; the explanation is reached by scrolling.
- Do it the way search already makes the keyboard taller: add a
  `previewImagePanel: Bool` input to `KeyboardLayoutPolicy.metrics`
  (`target += 96` when true) so the existing scene cap (85 % of the scene
  height) still limits it on short hosts. Key heights must not change: the
  extra height belongs to the panel only.
- Height change animates with the panel fade (0.2 s easeOut); Reduce
  Motion: no height animation. Closing returns to the typing height.
- Landscape, iPad and any host that doesn't honor the new height: behave
  exactly like the fallback: today's height, the panel scrolls, and picking
  Custom scrolls the body so both lines show. Never shrink anything to force a fit.
- The same growth applies to the Inspect panel when it ships.

## 4. Accessibility and checks
- All targets stay ≥ 44 × 44; Close and the action are never inside the
  scroll view. Contrast is unchanged (semantic colors only).
- Larger text (to xxxLarge, the keyboard's cap): header and footer stay
  pinned, the body scrolls, chip/swatch sizes don't scale.
- UI test (iPhone portrait): open the panel, select Custom, assert
  `keyboard.previewImage.background.*` swatches are hittable without
  scrolling, the keyboard is 96 pt taller than when typing, and `keyboard.previewImage.copy`
  frame height == 44.
