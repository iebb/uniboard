# Merged #+= page — review 1 (Colo, 2026-10-25)

Captures: Pluso msg992, installed preview, iPhone 18 Pro (1206×2622 px, pt = px/3). Measured from pixel columns and rows. White-run widths lose about 1 px of antialiasing at each edge.

## Passes (vs design.md §2, §3, §8)
1. **ABC page key** reads "#+=" at the same size and grey as the fallback's leading #+= key (03).
2. **Merged page rows** are 10/10/10/5+⌫, in the specified order. There is no leading switch key (04).
3. **Row positions match ABC exactly.**
   - Row tops at y = 1714 / 1850 / 1984–1986 / 2120–2121 px on both ABC and merged.
   - Row pitch is 136 px (45.3 pt = 41.4 + 4). The footer stays at y = 2256 on ABC, merged and fallback, so the keyboard height is unchanged.
4. **Merged widths.**
   - Rows 1–3 keys are identical to ABC's digit row (x 26…1180, same edges).
   - The punctuation keys measure 62.3–62.7 pt white with a 206 px (68.7 pt) pitch, which gives about 63.2 pt per key (spec 63.2 ±0.5).
   - ⌫ is about 40.7 pt grey (spec 41.2). The row spans x 26…1180, aligned with row 1.
5. **Fallback after removing 0** (11) matches today's 123: three rows of 54 pt white (the stretched 56.5 pt rule), the #+= leading key, and ABC in the footer.
6. **Editor (06).**
   - Two segments ABC | #+= and Camo's helper line.
   - The four-row canvas has tiles 40.7–41.0 pt, 150 px pitch, and 9.3 pt row gap, the same gap as before.
   - The well spans y 635–1247 px (204 pt). That is identical to the previous 123 canvas (02, signed off as equal to ABC), so switching sections won't shift the canvas height.
   - The punctuation tiles are 55.3 pt, matching (352 − 49 − 5×5)/5 = 55.6. ⌫ is 48.7 pt grey, the same as the old 123 editor's function keys (49 pt), and drawn inert.
   - The footnote is Camo's final text: footnote style (17.8 pt line pitch), about 4 pt inset, and about 8 pt below the canvas.

## No corrections

## Still needed before sign-off
- A. Editor capture after removing 0, showing three segments (ABC | 123 | #+=) and today's helper line.
- B. Pluso's open checks:
  - restoring 0 merges again;
  - a customized digit tap brings back two pages and keeps the custom choice;
  - all 35 symbols type;
  - a key with saved choices keeps them on the merged page.
- C. Arabic layout: holding ? on the merged page shows ؟ first.
- D. A code or test confirmation that VoiceOver labels are "Symbols" on the ABC page key and the merged section, and "Letters" on the merged page key. Also that the wide iPad, the three-row legacy ABC and the short-landscape cases keep both pages.
