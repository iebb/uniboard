# Symbols page 1.4 — design review 1 (Pluso msg857)

Colo (@design). Checked against spec rev. 2 (msg837). Captures: symbols-light, symbols-dark, symbols-AX2, page-mixed, real-page-spread-inserted (iPhone 18 Pro, 402 pt wide). Code read: `App/PageArrangeView.swift` as of 16:01.

## Passes (measured)
- Add card: rows 51–52 pt, separator starts at the title (52 pt), both titles on one line at default and AX2, rows equal height at AX2 (95 pt each). ✓
- Spacing: canvas → Add card 17 pt, card → card 16–17 pt, footers about 6 pt under their card. ✓
- Alignment card: "All Rows" + trailing value, four symbol segments, footer "Select a key to align only its row." ✓
- Mixed: no segment selected, value "Mixed". ✓
- Editor geometry: the Spread row puts a and b on the well's inner edges (8 pt each side); the Center row is centered to within 0.5 px. ✓
- Keyboard Spread: a and d have equal 8.4 pt margins, the three spaces between keys are equal (≈ 84 pt), key widths unchanged, taps insert "ad". ✓
- Dark: key tiles ≈ #48474A on the well ≈ #1C1B1F (spec §6 fallback is in), so keys are clearly separate. ✓
- ★ footer wraps as "…instead / of Favorites.": that is iOS keeping a single word off the last line, not a layout bug. ✓
- Favorites ★ switch: the code disables it while Favorites has ★ and ignores turning it off. ✓ (needs a capture, below)

## Corrections (measurable defects)
1. **Control bar labels at AX2.** 6 of 8 labels are cut off ("Move…", "Half…", "New…", "Remo…"), and "Gap" is drawn about 1.4× larger than the others because `minimumScaleFactor(0.7)` shrinks only the long labels. This has been there since 1.3, but it's on this screen. Fix in `control(_:_:id:enabled:action:)`: when `dynamicTypeSize.isAccessibilitySize`, show the icon only. Keep `.accessibilityLabel(title)` and add `.accessibilityShowsLargeContentViewer { Label(title, systemImage: icon) }`, so a long press shows the name the way the tab bar does. Below accessibility sizes, leave it as it is. Pass: no "…" in the bar at AX2 or AX5, all eight buttons the same size, and a long press on any button shows its name.
2. **Add-row icon column at accessibility sizes.** The AX2 capture shows the "Add Text" icon ≈ 32 pt wide in its 24 pt column, so it sticks ≈ 4 pt into the left padding and sits 9 pt from the title instead of 12. The 16:01 code fixes the icon at 20 pt, which stops it overflowing but also stops it growing with the text. Fix: `@ScaledMetric(relativeTo: .body) private var addIconWidth: CGFloat = 24`. Set the icon to `.font(.body)` with `.frame(width: addIconWidth)`, and the Divider's leading inset to `16 + addIconWidth + 12` (52 at the default size). Pass: at AX2 both icons stay inside their column, the gap to the title is 12 pt × the scale, and the separator starts at the titles' x.
3. **Alignment card disabled with no reason.** On a page with a too-wide row the card is disabled (`.disabled(… || !wideRows.isEmpty)`). That's right, because saving alignment would write the wide row in the new format, but nothing says why. Fix: while it's disabled for this reason, swap the footer "Select a key to align only its row." for one line, and use the same line as the picker's VoiceOver hint. Text (Camo msg859): "Shorten rows that exceed the width limit before changing alignment." Pass: the screen-8 capture shows the dimmed card with that line under it.

## Still needed for sign-off (captures)
a. A key selected in row 2: card "Row 2" plus the accent band behind that row (spec screen 3).
b. A legacy page with a 14-key row: orange dashed outline, the "Row 2 is wider than…" note, and the disabled alignment card from correction 3 (screen 8), plus that page in the keyboard looking the same as in 1.3.
c. Favorites: no Add card, no alignment card, switch on and dimmed, footer "When on, the ★ key opens Favorites." (screen 9).
d. An empty custom page (screen 6).
e. Main Keyboard ABC with the alignment card, one row set to Left, and the same row in the keyboard (screen 5, check 9).
f. The ⋯ menu open on a page: "Rows of Ten" with its subtitle not cut off (or "Rows of Ten, Align Left").
g. AX2 scrolled to the alignment card, and AX5 (the bar from correction 1 and the Add rows wrapping to two lines).
h. Keyboard with one row each of Center and Right.
i. iPad: a page edited on iPhone, with the same rows and alignment (check 11), when convenient.
