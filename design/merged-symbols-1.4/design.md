# Uniboard 1.4: one #+= page when ABC has the numbers (PROPOSAL, not approved)

Colo, 2026-10-25. Task task.e38c710d. Source: user msg966, Ato msg967, Pluso audit msg973 (merged-symbols-feasibility.md).
Mockups: artifact 4DD3C4E7-8A48-47F6-BA34-32E3DC7F34F0 (figures A, B are build screenshots; 1–5 are mockups, attached as PNG).
**Nothing changes in the app until Ato approves.** 1.3 (build 52) is untouched by this.

## 0. Summary
When ABC already types all ten digits at normal key size, 123's top row only repeats them. Then 123 and #+= become one page, still called **#+=**, with four rows at ABC's key size. Every symbol, every key ID and every saved choice stays. In any other case, today's 123 and #+= stay exactly as they are.

## 1. When the merge applies (all three must hold)
Evaluate from the effective saved settings for the **current layout** and the current keyboard geometry. Re-evaluate on settings, layout, width, rotation, floating or Split View changes, never on a momentary Shift (Pluso audit).
1. **Phone-style typing layout.** This means iPhone, or an iPad keyboard narrower than 650 pt (floating, narrow Split View). Wide iPad keyboards of 650 pt and up are unchanged. Their ANSI #+= has 10 extra symbols (§ ± × ÷ ° © ® ™ … ·), 45 in all, which don't fit four rows of 10.
2. **ABC is drawn with four rows at its normal height.** This is the number row plus three, the four-row content budget (`keyRows ≥ 4`). A three-row ABC is unchanged, even one that holds all ten digits, for example the older `1234qwertyuiop / 5678asdfghjkl / ⇧90zxcvbnm⌫`. Four rows in its height would be (3×41.4 + 2×4 − 3×4)/4 ≈ 30.05 pt, far below the stock 41.4.
3. **Each digit 0–9 is typed by a plain, unshifted tap on a key drawn on ABC**, after saved tap choices and routing. Hold and swipe choices don't count. Labels and IDs alone don't count.

If any condition fails, today's 123 and #+= pages, the leading 123/#+= key and the three editor sections stay pixel-for-pixel as they are now.

Caveat (unchanged behavior): digit keys share their IDs and saved choices with 123. If a user changed what a digit types, today's 123 shows the same change. The fallback does not restore a literal digit, and we never overwrite a user's choice.

## 2. Keyboard, merged state (figures 1 and 2)
- **ABC page:** unchanged except the page key (footer, between U and ★). Its title is **"#+="** instead of "123", because the page it opens has no numbers. It uses the same 13 pt title size and modifier grey as today.
- **Merged page, top to bottom.** Spacing matches ABC: key gap 5, row gap 4.
  1. `[ ] { } # % ^ * + =` (10 keys)
  2. `_ \ | ~ < > € £ ¥ •` (10 keys)
  3. `- / : ; ( ) $ & @ "` (10 keys)
  4. `. , ? ! '` then ⌫
- Why this order: the 123 row, by far the most used, stays directly above the punctuation, where thumbs find it today. The two #+= rows keep their current order above it.
- **Widths:** rows 1–3 use ABC's letter width (33.5 pt on iPhone 18 Pro, 402 pt). In row 4, ⌫ keeps its width on today's symbol pages (41.2 pt measured). The five punctuation keys split the rest equally, (W − ⌫ − 5×5)/5, which is **63.2 pt** on iPhone 18 Pro (53.8 today). No leading 123/#+= key is drawn, because there is no second page.
- **Height:** four rows. Key height = (ABC content height − 3×4)/4, which equals ABC's key height (41.4 pt stock). Today's symbol keys are 56.5 pt only because three rows stretch to fill four. The total keyboard height is unchanged. Keys are never shorter than 41.4.
- **Footer on the merged page:** the page key reads "ABC", as it does today.
- **Page identity:** the merged page takes the place of #+=. If eligibility changes while the keyboard is open, a 123 page maps to the merged page and the merged page maps to today's #+=. The keyboard never shows a page that no longer exists.

## 3. Main Keyboard editor, merged state (figure 3)
- **Section switch:** two segments, **ABC | #+=**, for the layout chosen in the Layout row. If it isn't eligible, it shows the three segments as today. If 123 was selected when it disappears (for example after changing the Layout row), select #+=.
- **Help line:** "Choose letters or symbols to edit their keys." (draft, Camo)
- **Canvas:** the same four rows and order as the keyboard, and punctuation widths by the same formula. Tiles match ABC's tile height, and the well is the same height as ABC's, so switching segments doesn't shift the panel. ⌫ is drawn and inert, as today. There is no Move/Gap bar, as today.
- **Footnote** under the canvas, on merged #+= only. Use 13 pt, secondary label colour, 4 pt side inset, 8 pt above. Text: "Numbers are on ABC, so 123 and #+= share this page. If a number key leaves ABC, 123 comes back." (draft, Camo)
- **Selecting a key:** shows the existing Key / Swipe up / Hold / Swipe down panel and the per-key restore row, unchanged. Dots mark saved choices as today.
- **Key search:** symbols that were grouped under 123 are grouped under #+=. Digits stay under ABC. Symbols that no canvas draws on this device are still listed under #+=.

## 4. Fallback (figures 4 and 5)
- **A digit is missing from ABC** (removed, or its tap types something else): 123 is back in the editor and on the keyboard, exactly as today. Putting the digit back merges the pages again. Saved choices are untouched both ways.
- **Three-row ABC, or wide iPad:** today's pages.

## 5. Unchanged
- All key IDs (digit.0…9, symbol.002E, and so on) and every saved tap, shifted tap, hold, swipe up and swipe down.
- The dots, per-key restore, and Find a key.
- The Arabic and Hebrew additions on shared keys (? → ؟, , → ،, ; → ؛, $ → ₪).
- The five punctuation keys were already the same keys on both pages; they're simply shown once.
- No migration and nothing is deleted. The number row on ABC (signed off msg963) and the Symbols-page rules (msg880) still apply.

## 6. Accessibility
- **ABC page key:** VoiceOver label "Symbols" while merged ("Numbers" otherwise). The value is unchanged.
- **Merged page key:** label "Letters", unchanged.
- **Editor segments:** "Letters", "Symbols" while merged. Today's three ("Letters", "Numbers and Symbols", "More Symbols") otherwise.
- No new colours. The existing key, footnote and secondary contrast already pass. The footnote uses Dynamic Type (footnote style) and wraps.

## 7. Strings for Camo
1. Help line while merged: "Choose letters or symbols to edit their keys."
2. Footnote: "Numbers are on ABC, so 123 and #+= share this page. If a number key leaves ABC, 123 comes back."
3. VoiceOver "Symbols" for the ABC page key and the merged editor segment.

## 8. Checks once built (measurable)
1. iPhone 18 Pro, English, standard four-row ABC:
   - The page key reads #+=.
   - The merged page has 4 rows of 10/10/10/5+⌫.
   - Key height is 41.4 ±0.5 pt, punctuation keys are 63.2 ±0.5 pt, and the keyboard is the same height as ABC (±0.5).
2. All 35 symbols type. A key with saved choices keeps them, for example $ swipe up and hold.
3. Remove 0 from ABC: the 123 section and the keyboard's 123 page return. Put it back: they merge again.
4. Change digit 5's tap to another character: today's pages.
5. The three-row legacy ABC from §1.2: today's pages.
6. Wide iPad in landscape: unchanged, including the § ± × … row. iPad floating keyboard: merged.
7. Arabic layout: holding ? on the merged page shows ؟ first.
8. VoiceOver labels as in §6. The editor doesn't shift height when switching ABC ↔ #+=.

## 9. Tradeoffs for Ato
- **Gains:** every symbol is one tap from ABC instead of up to two. 123's repeated digit row goes away. The punctuation keys get about 17% wider (63.2 vs 53.8 pt).
- **Costs:**
  - Habit: the 123 key now reads #+=, and the #+= rows move up one row.
  - Symbol keys go back to ABC's size (41.4 pt) from today's stretched 56.5 pt.
  - The page set depends on the current ABC; the footnote explains this.
- **My picks, open to change:**
  - The label is "#+=", not "123", because there are no numbers on that page.
  - The merge is automatic, with no setting, as Ato framed it.
  - The 123 row sits directly above the punctuation.
