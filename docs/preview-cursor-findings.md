# Preview cursor findings: `adjustTextPosition(byCharacterOffset:)` across hosts

Status: investigation only. Nothing here is shipped. This is groundwork for making `textPreviewRow` / `KeyboardTextPreviewLayout` in `Keyboard/KeyboardViewController.swift` tappable.

## How this was measured

- A DEBUG-only probe (`KeyboardCursorProbe`, under `#if DEBUG` in `Keyboard/KeyboardViewController.swift`) runs scripted proxy calls from inside the keyboard: `seed` (insertText), `move(n)` (`adjustTextPosition`), `mark` (insert `|`), `unmark` (deleteBackward), `insert`, `deleteBackward`, rapid/paced/burst sequences. After each call it logs:
  - the synchronous proxy context;
  - the context after one run-loop turn, 60 ms and 300 ms;
  - `selectionDidChange` / `textDidChange` callback counts and their latency.
- The UI test `UniboardUITests.testCursorProbeMapsAdjustTextPositionInHosts` drives three hosts and reads the host's own value as ground truth. This is the "host value after" column; `|` is where the caret was, because `mark` inserts a literal `|`:
  - a UITextView and a UITextField in the Uniboard app;
  - a `<textarea>` in Safari.
- Device: iPhone 18 Pro simulator.
- Runs:
  - **run1** `bb27286d-66f3-4040-8c32-bdd3be84ac93`: first script. UITextView and UITextField are complete. The Safari phase failed after 6 rows.
  - **run2** `a2dcf136-9a13-4e3a-afda-c90a8bb03e98`: follow-up script (from-start walks, overshoot, coalescing) for all three hosts, then the first script for Safari. The test passed.
- Test strings: `x😀y` (astral), `x👩‍💻y` (ZWJ), `x🇯🇵y` (flag), `x👍🏽y` (skin tone), `xe\u{301}y` (combining), `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` (niqqud: bet with dagesh, resh, alef), `abc אבג def` (mixed bidi), `wwwwwwww world` (selection), and 80 lines of `Lnn the quick brown fox jumps over.` (2880 UTF-16 units in textview/Safari; 1440 in textfield, where the newlines are spaces).

### Caveats in the raw data

1. **The probe's own marker can change the text.** When `mark` lands inside a cluster, inserting `|` splits it; the table shows `\u{FFFD}` where a surrogate pair was split. The `unmark` that follows (deleteBackward) can then delete a neighbouring scalar, for example the ZWJ, the 🏽 modifier or the ◌́. Rows after a mid-cluster mark therefore walk a slightly mutated string. The per-step *delta* is still valid.
2. **Run1 `jump-50 → fwd*` rows are invalid** as forward walks. `move(-50)` overshoots, and the host ignores it (see Q2), so the walk starts at the end. The run2 follow-up script replaces them with `toStart → fwd*`.
3. **Safari first-script rows (run2 #79–#248) run on accumulated text.** The probe's "clear field" helper moves by `after.utf16.count`. In Safari, which counts graphemes, that overshoots and is dropped, so the text was never cleared. Each step's delta is still readable from the marker. The Safari *follow-up* rows (#1–#78) use a fresh string every time and are clean.
4. **The run2 Safari follow-up `toStart` rows also overshoot.** They move by the UTF-16 length. For every non-BMP string that overshoots in Safari, the move is dropped, and the forward walk stays at the end. This is itself the evidence for Q1. For the clean Safari walks, read the first-script `back*` / `fwd*` rows (#80–#218).

## Conclusions

### Q1 — Offset unit

The unit depends on the host:

| host | unit of `byCharacterOffset` | evidence |
|---|---|---|
| UITextView | **UTF-16 code units** | `x😀y` from the start: +1 steps land at UTF-16 positions 1, 2, 3, 4. Step 2 lands between the surrogates (`x\u{FFFD}\|\u{FFFD}y`, run2 #3). The ZWJ, flag, skin and combining strings behave the same way. |
| UITextField | **UTF-16 code units** | Identical to UITextView in every walk (run2 #1–#72). |
| Safari `<textarea>` (WebKit) | **grapheme clusters** | One `move(-1)` crosses a whole `👩‍💻` (5 units, run2 #97), `🇯🇵` (4, #119), `👍🏽` (4, #139), `e\u{301}` (2, #159) or `בּ` (2, #177). `move(-len.utf16)` on a non-BMP string overshoots and is ignored (#1, #9, #20, #30, #40, #48). ASCII and Hebrew without marks step one at a time (#58–#69). |

`documentContextBefore/AfterInput` is a Swift `String`. Its `.utf16.count` matches the UIKit hosts and its `.count` (Characters) matches Safari. Neither the proxy nor the trait collection tells you which kind of host you are in.

### Q2 — Moves into the middle of a surrogate pair or cluster

- **UIKit hosts accept any UTF-16 offset**, including one between the two halves of a surrogate pair or inside a ZWJ, flag, skin-tone or combining sequence. Nothing snaps the caret. What happens next:
  - *insertText* there splits the scalar or cluster. You get lone surrogates (`x👍\u{FFFD}Z\u{FFFD}y`, run1 skin `end-2 insertZ`) or a detached mark (`xeZ\u{301}y`).
  - *deleteBackward* there removes the whole preceding cluster: `x👍🏽y` with the caret inside 🏽 → `xy`, and `xe|\u{301}y` → `xy`. Deleting `|` after a ZWJ or modifier also ate that scalar (caveat 1).
- **Safari never lands inside a cluster**, because its unit is the cluster.
- **Overshoot, all hosts:** a move whose target lies outside `[0, documentLength]` is **ignored entirely**, not clamped.
  - `move(-5)` on a 4-unit string from the end leaves the caret at the end (run2 `overshootStart`, every host).
  - `move(-1); move(+2)` at the end leaves the caret 1 before the end (`overshootEnd`).
  - `move(±100000)` in the long text is a no-op (#164/#166, Safari #242/#244).
  - Single −1 / +1 steps at either edge are no-ops too, which looks like clamping but is the same rule.

### Q3 — RTL and bidi: logical, not visual

- **Offsets are logical (storage order) in every host.** Walking `abc אבג def` forward by +1 visits `abc |אבג`, `abc א|בג`, `abc אב|ג`, `abc אבג|` (run2 #62–#65, same in UIKit). The caret moves through the Hebrew run in storage order, which is right-to-left on screen, and no host converts the offset to visual order.
- **In-keyboard layout** (`bidi layout` row, CTLine over `abc אבג def`, LTR paragraph):
  - Tap x → string index: x36→6, x42→6, x48→5, x54→5, x60→7. Across the Hebrew run, moving right gives *smaller* indexes.
  - Logical index 4, the LTR→RTL boundary, has **two caret positions** (x≈32.4 and x≈59.4). ג (logical 6) is drawn leftmost in the run.
  - A paragraph that starts with Hebrew (`שלום abc`) gets an RTL base direction unless the direction is forced.
- **The current preview** forces `.leftToRight` and renders the before-caret and after-caret text as separate `Text` runs. A Hebrew run that crosses the caret is reordered *per half*, so the preview's glyph order differs from how the host would lay out the same paragraph. Tap mapping must therefore use the preview's own laid-out line, not a guess about the host.

### Q4 — Timing of context updates and chunking

- `selectionDidChange` **never fired** for proxy-initiated moves in any host (0 out of 238, 238 and 662 operations).
- `textDidChange` fires **after** a move: once in UIKit, twice in Safari. Typical latency is 3–14 ms, and about 60 ms for jumps of more than 1000 units. In Safari it **also fires for moves that were dropped** (e.g. run2 #2), so it shows that the host processed a call, not that the caret moved.
- **The synchronous context right after `adjustTextPosition` is a local prediction.** In UIKit it is computed in UTF-16 and can be wrong around surrogates. After big jumps it is often `nil^…` or a short slice, and Safari's prediction ignores the drop. Re-read only after `textDidChange`, or one run-loop turn plus about 60 ms. The 60 ms and 300 ms reads always matched the host.
- **Coalescing.** Calls made in one run-loop turn are summed and applied as one move (run2 `coalesce` rows, identical in all three hosts):
  - 8 × −1 from 15 → 7.
  - 12 × −1 from 7 (sum overshoots by 5) → **nothing moves**.
  - The same 12 × −1 *paced* (one per turn) → steps until 0; the steps that would overshoot are dropped individually.
  - A burst of +3, −1, +3 → net +5. A burst of +1 ×3 followed by `insertText` in the same turn inserts at the summed position (`01234567Q89…`).
  - Long text: rapid 12 × −100 → exactly −1200, fine. Textfield rapid 40 × −1 from 28 → dropped as a whole (overshoot).

### Q5 — Context length and behavior at its edge

- **Before-context:**
  - UITextView and UITextField: about 57–81 UTF-16 units in the long text. It follows sentence/line boundaries: the current sentence or line plus the previous one (60 at `…brown fox|`, 72 at the end of a line).
  - Safari: about 48–53, not sentence-aligned.
  - At document start it is shorter or `nil`.
- **After-context:** it ends at the end of the current line or sentence (12–31 units, e.g. ` jumps over.`) and is `nil` at document end.
- **Moving past the exposed context works.** With 71 units exposed (51 in Safari), `move(-111)` / `move(-91)` landed exactly (#163, #241), and −300, −1200 and +1200 all landed exactly. The host uses the full document; only *visibility* is limited.
- **The document length is not knowable from the proxy,** so there is no way to know whether a move will overshoot. An overshoot is silently ignored (Q2). There is no clamp and no error.

### Q6 — Behavior with a selection

- **UITextView:** a move collapses the selection and is measured from the **end** of the selection:
  - `wwwwwwww` selected, +3 → `wwwwwwww wo|rld`; −3 → `wwwww|www world`.
  - `move(0)` also collapses, to the selection end.
- **UITextField:** ± moves are the same as UITextView. **`move(0)` does not collapse**, so the following `insertText("|")` replaced the selection (`| world`).
- **Safari:** with `world` selected at document end, `move(+3)` overshot, was dropped and left the selection intact. The next insert replaced it. `move(0)` + insert likewise replaced the selection. Safari −3 with a selection gave an unexplained 6 (#228), so treat it as inconclusive.
- **All hosts:**
  - `insertText` and `deleteBackward` with a selection act on the selection.
  - `documentContextBefore/AfterInput` *exclude* the selected text. `selectedText` reports the selection in all three hosts (UIKit `selected="wwwwwwww"`, `beforeLen=nil` with the selection at document start; Safari `sel="world"`).

## Recommendations for an interactive preview

1. **Unit: do not assume one.** Compute a target in grapheme clusters *and* in UTF-16, and choose per host:
   - Detect the unit empirically by probing once per field. Do it on the first tap and cache it per `textDocumentProxy` / document identifier: when the caret is next to a non-BMP character, issue `move(-1)` and see whether the before-context lost 1 or 2 UTF-16 units after `textDidChange`.
   - Fallback when there is no non-BMP nearby: the units are equivalent, so either works.
   - Never send `before.utf16.count` blindly. That is precisely the overshoot that Safari drops.
2. **Grapheme snapping:** snap every tap to a `Character` boundary of the before/after strings first. Then convert to UTF-16 for UIKit hosts (`String.Index.utf16Offset`). With that, UIKit hosts can never be put inside a cluster, and we never trigger the split-cluster insert/delete behavior from Q2.
3. **Tap x → offset in bidi text:**
   - Lay out the preview line with Core Text (or TextKit 2) using the **same paragraph direction as the rendered preview**.
   - Hit-test with `CTLineGetStringIndexForPosition`, then snap to a grapheme boundary.
   - At a direction boundary (dual caret), choose the index whose primary caret offset (`CTLineGetOffsetForStringIndex`) is nearest the tap.
   - The offset to send is the **logical** difference `targetIndex − caretIndex`. Never derive it from the visual distance.
   - Render the preview as one attributed line with the caret drawn as an overlay. Do not split it into before/after `Text` runs, because the split changes bidi reordering. Use natural or first-strong direction instead of forcing `.leftToRight`, at least for hit-testing.
4. **Chunking and pacing:**
   - Issue at most **one** `adjustTextPosition` per run-loop turn, or a single summed call.
   - Wait for `textDidChange` (with a timeout of about 100 ms; use about 300 ms after jumps over 1000 units) before reading context or issuing the next move. Then re-sync the preview from the new context.
   - Never rely on `selectionDidChange`.
   - For drags, coalesce to the latest target and send one delta per turn. Compute each delta from the *confirmed* context, never from the predicted one.
5. **Context-edge policy:**
   - Taps can only target text we can see in `before + after`, so every target is inside the document by construction and can't overshoot.
   - For a "jump to start/end" gesture, move in chunks bounded by the visible context: move by `before.count` (Safari) or `before.utf16.count` (UIKit), wait for `textDidChange`, and repeat until `before` is nil or empty.
   - Treat an unchanged context after a move as "dropped". Stop; don't retry with a larger number.
6. **Promises we can't make:**
   - We can't show or address text beyond about 50–80 units before the caret or past the end of the current line.
   - Tap positions won't match the host's own on-screen layout: different font, width and line wrapping.
   - We can't guarantee unit detection is right without a non-BMP probe character nearby.
   - We can't know the document length, so overshoots are silent no-ops.
   - Behavior with a selection differs by host (`move(0)` collapses in UITextView but not UITextField). Before mapping a tap, collapse explicitly with a nonzero move and its inverse (e.g. `+1` then `-1` in separate run-loop turns, since a same-turn pair coalesces to 0; avoid the edges), or disable tap-to-move while `selectedText != nil`.
   - We can't promise visual-order caret motion in RTL or mixed text: the host moves logically.
   - Hosts other than these three (third-party web views, custom `UITextInput` hosts) are untested.

---

## Appendix A — run1 (`bb27286d-…`): UITextView and UITextField, first script

Columns: the proxy calls issued in the step; the host's real value afterwards with `|` at the caret; the UTF-16 index of `|`.

**textview — astral**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 1 | astral seed | seed | `x\u{1F600}y` | – |
| 2 | astral back1 | move(-1) → mark | `x\u{1F600}\|y` | 3 |
| 3 | astral back2 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}y` | 2 |
| 4 | astral back3 | unmark → move(-1) → mark | `x\|\u{1F600}y` | 1 |
| 5 | astral back4 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 6 | astral back5 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 7 | astral jump-50 | unmark → seed → move(-50) → mark | `x\u{1F600}y\|` | 4 |
| 8 | astral fwd1 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 9 | astral fwd2 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 10 | astral fwd3 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 11 | astral fwd4 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 12 | astral fwd5 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 13 | astral end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{FFFD}Z\u{FFFD}y` | – |
| 14 | astral end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 15 | astral end-3 mark | seed → move(-3) → mark | `x\|\u{1F600}y` | 1 |
| 16 | astral end-3 delete | unmark → deleteBackward | `\u{1F600}y` | – |

**textview — zwj**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 17 | zwj seed | seed | `x\u{1F469}\u{200D}\u{1F4BB}y` | – |
| 18 | zwj back1 | move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}\|y` | 6 |
| 19 | zwj back2 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{FFFD}\|\u{FFFD}y` | 5 |
| 20 | zwj back3 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\|\u{1F4BB}y` | 4 |
| 21 | zwj back4 | unmark → move(-1) → mark | `x\u{1F469}\|\u{200D}\u{1F4BB}y` | 3 |
| 22 | zwj back5 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F4BB}y` | 2 |
| 23 | zwj back6 | unmark → move(-1) → mark | `x\|\u{1F469}\u{1F4BB}y` | 1 |
| 24 | zwj back7 | unmark → move(-1) → mark | `\|x\u{1F469}\u{1F4BB}y` | 0 |
| 25 | zwj back8 | unmark → move(-1) → mark | `\|x\u{1F469}\u{1F4BB}y` | 0 |
| 26 | zwj jump-50 | unmark → seed → move(-50) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 27 | zwj fwd1 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 28 | zwj fwd2 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 29 | zwj fwd3 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 30 | zwj fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 31 | zwj fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 32 | zwj fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 33 | zwj fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 34 | zwj fwd8 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 35 | zwj end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F469}\u{200D}\u{FFFD}Z\u{FFFD}y` | – |
| 36 | zwj end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 37 | zwj end-6 mark | seed → move(-6) → mark | `x\|\u{1F469}\u{200D}\u{1F4BB}y` | 1 |
| 38 | zwj end-6 delete | unmark → deleteBackward | `\u{1F469}\u{200D}\u{1F4BB}y` | – |

**textview — flag**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 39 | flag seed | seed | `x\u{1F1EF}\u{1F1F5}y` | – |
| 40 | flag back1 | move(-1) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 41 | flag back2 | unmark → move(-1) → mark | `x\u{1F1EF}\u{FFFD}\|\u{FFFD}y` | 4 |
| 42 | flag back3 | unmark → move(-1) → mark | `x\u{1F1EF}\|\u{1F1F5}y` | 3 |
| 43 | flag back4 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F1F5}y` | 2 |
| 44 | flag back5 | unmark → move(-1) → mark | `x\|\u{1F1EF}\u{1F1F5}y` | 1 |
| 45 | flag back6 | unmark → move(-1) → mark | `\|x\u{1F1EF}\u{1F1F5}y` | 0 |
| 46 | flag back7 | unmark → move(-1) → mark | `\|x\u{1F1EF}\u{1F1F5}y` | 0 |
| 47 | flag jump-50 | unmark → seed → move(-50) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 48 | flag fwd1 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 49 | flag fwd2 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 50 | flag fwd3 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 51 | flag fwd4 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 52 | flag fwd5 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 53 | flag fwd6 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 54 | flag fwd7 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 55 | flag end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F1EF}\u{FFFD}Z\u{FFFD}y` | – |
| 56 | flag end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 57 | flag end-5 mark | seed → move(-5) → mark | `x\|\u{1F1EF}\u{1F1F5}y` | 1 |
| 58 | flag end-5 delete | unmark → deleteBackward | `\u{1F1EF}\u{1F1F5}y` | – |

**textview — skin**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 59 | skin seed | seed | `x\u{1F44D}\u{1F3FD}y` | – |
| 60 | skin back1 | move(-1) → mark | `x\u{1F44D}\u{1F3FD}\|y` | 5 |
| 61 | skin back2 | unmark → move(-1) → mark | `x\u{1F44D}\u{FFFD}\|\u{FFFD}y` | 4 |
| 62 | skin back3 | unmark → move(-1) → mark | `x\u{1F44D}\|\u{1F3FD}y` | 3 |
| 63 | skin back4 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}y` | 2 |
| 64 | skin back5 | unmark → move(-1) → mark | `x\|\u{1F44D}y` | 1 |
| 65 | skin back6 | unmark → move(-1) → mark | `\|x\u{1F44D}y` | 0 |
| 66 | skin back7 | unmark → move(-1) → mark | `\|x\u{1F44D}y` | 0 |
| 67 | skin jump-50 | unmark → seed → move(-50) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 68 | skin fwd1 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 69 | skin fwd2 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 70 | skin fwd3 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 71 | skin fwd4 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 72 | skin fwd5 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 73 | skin fwd6 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 74 | skin fwd7 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 75 | skin end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F44D}\u{FFFD}Z\u{FFFD}y` | – |
| 76 | skin end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 77 | skin end-5 mark | seed → move(-5) → mark | `x\|\u{1F44D}\u{1F3FD}y` | 1 |
| 78 | skin end-5 delete | unmark → deleteBackward | `\u{1F44D}\u{1F3FD}y` | – |

**textview — combining**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 79 | combining seed | seed | `xe\u{301}y` | – |
| 80 | combining back1 | move(-1) → mark | `xe\u{301}\|y` | 3 |
| 81 | combining back2 | unmark → move(-1) → mark | `xe\|\u{301}y` | 2 |
| 82 | combining back3 | unmark → move(-1) → mark | `x\|ey` | 1 |
| 83 | combining back4 | unmark → move(-1) → mark | `\|xey` | 0 |
| 84 | combining back5 | unmark → move(-1) → mark | `\|xey` | 0 |
| 85 | combining jump-50 | unmark → seed → move(-50) → mark | `xe\u{301}y\|` | 4 |
| 86 | combining fwd1 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 87 | combining fwd2 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 88 | combining fwd3 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 89 | combining fwd4 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 90 | combining fwd5 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 91 | combining end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `xeZ\u{301}y` | – |
| 92 | combining end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 93 | combining end-3 mark | seed → move(-3) → mark | `x\|e\u{301}y` | 1 |
| 94 | combining end-3 delete | unmark → deleteBackward | `e\u{301}y` | – |

**textview — niqqud**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 95 | niqqud seed | seed | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | – |
| 96 | niqqud back1 | move(-1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 97 | niqqud back2 | unmark → move(-1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\|\u{5D0}y` | 4 |
| 98 | niqqud back3 | unmark → move(-1) → mark | `x\u{5D1}\u{5BC}\|\u{5E8}\u{5D0}y` | 3 |
| 99 | niqqud back4 | unmark → move(-1) → mark | `x\u{5D1}\|\u{5BC}\u{5E8}\u{5D0}y` | 2 |
| 100 | niqqud back5 | unmark → move(-1) → mark | `x\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 1 |
| 101 | niqqud back6 | unmark → move(-1) → mark | `\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 0 |
| 102 | niqqud back7 | unmark → move(-1) → mark | `\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 0 |
| 103 | niqqud jump-50 | unmark → seed → move(-50) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 104 | niqqud fwd1 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 105 | niqqud fwd2 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 106 | niqqud fwd3 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 107 | niqqud fwd4 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 108 | niqqud fwd5 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 109 | niqqud fwd6 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 110 | niqqud fwd7 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 111 | niqqud end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{5D1}\u{5BC}\u{5E8}Z\u{5D0}y` | – |
| 112 | niqqud end-2 delete | seed → move(-2) → deleteBackward | `x\u{5D1}\u{5BC}\u{5D0}y` | – |
| 113 | niqqud end-5 mark | seed → move(-5) → mark | `x\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 1 |
| 114 | niqqud end-5 delete | unmark → deleteBackward | `\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | – |

**textview — mixed**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 115 | mixed seed | seed | `abc \u{5D0}\u{5D1}\u{5D2} def` | – |
| 116 | mixed back1 | move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 117 | mixed back2 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} d\|ef` | 9 |
| 118 | mixed back3 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} \|def` | 8 |
| 119 | mixed back4 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2}\| def` | 7 |
| 120 | mixed back5 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\|\u{5D2} def` | 6 |
| 121 | mixed back6 | unmark → move(-1) → mark | `abc \u{5D0}\|\u{5D1}\u{5D2} def` | 5 |
| 122 | mixed back7 | unmark → move(-1) → mark | `abc \|\u{5D0}\u{5D1}\u{5D2} def` | 4 |
| 123 | mixed back8 | unmark → move(-1) → mark | `abc\| \u{5D0}\u{5D1}\u{5D2} def` | 3 |
| 124 | mixed back9 | unmark → move(-1) → mark | `ab\|c \u{5D0}\u{5D1}\u{5D2} def` | 2 |
| 125 | mixed back10 | unmark → move(-1) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 126 | mixed back11 | unmark → move(-1) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 127 | mixed back12 | unmark → move(-1) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 128 | mixed jump-50 | unmark → seed → move(-50) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 129 | mixed fwd1 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 130 | mixed fwd2 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 131 | mixed fwd3 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 132 | mixed fwd4 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 133 | mixed fwd5 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 134 | mixed fwd6 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 135 | mixed fwd7 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 136 | mixed fwd8 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 137 | mixed fwd9 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 138 | mixed fwd10 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 139 | mixed fwd11 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 140 | mixed fwd12 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 141 | mixed end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `abc \u{5D0}\u{5D1}\u{5D2} dZef` | – |
| 142 | mixed end-2 delete | seed → move(-2) → deleteBackward | `abc \u{5D0}\u{5D1}\u{5D2} ef` | – |
| 143 | mixed end-10 mark | seed → move(-10) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 144 | mixed end-10 delete | unmark → deleteBackward | `bc \u{5D0}\u{5D1}\u{5D2} def` | – |

**textview — bidi**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 145 | bidi layout |  | `bc \u{5D0}\u{5D1}\u{5D2} def` | – |

**textview — sel**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 146 | sel seed | seed | `wwwwwwww world` | – |
| 147 | sel report | report | `wwwwwwww world` | – |
| 148 | sel +3 | move(3) → mark | `wwwwwwww wo\|rld` | 11 |
| 149 | sel unmark | unmark | `wwwwwwww world` | – |
| 150 | sel -3 | move(-3) → mark | `wwwww\|www world` | 5 |
| 151 | sel unmark | unmark | `wwwwwwww world` | – |
| 152 | sel 0 | move(0) → mark | `wwwwwwww\| world` | 8 |
| 153 | sel reseed | seed | `wwwwwwww world` | – |
| 154 | sel insert | insert(\|) | `\| world` | 0 |
| 155 | sel reseed | seed | `wwwwwwww world` | – |
| 156 | sel delete | deleteBackward | `world` | – |

**textview — long**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 157 | long seed | seed → report | host[u16=2879 ch=2879 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 158 | long -300 | move(-300) → mark | u16=2880 ch=2880 marks=[2579] fromEnd=300 around `uick brown fox\| jumps over.\nL` | – |
| 159 | long +300 | unmark → move(300) → mark | u16=2880 ch=2880 marks=[2879] fromEnd=0 around `ox jumps over.\|` | – |
| 160 | long -1200 | unmark → move(-1200) → mark | u16=2880 ch=2880 marks=[1679] fromEnd=1200 around `uick brown fox\| jumps over.\nL` | – |
| 161 | long mid report | unmark → report | host[u16=2879 ch=2879 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 162 | long +1200 | move(1200) → mark | u16=2880 ch=2880 marks=[2879] fromEnd=0 around `ox jumps over.\|` | – |
| 163 | long beyond-context | unmark → beyond(exposed=71 move -111) → mark | u16=2880 ch=2880 marks=[2768] fromEnd=111 around `n fox jumps ov\|er.\nL78 the qu` | – |
| 164 | long -100000 | unmark → move(-100000) → mark | u16=2880 ch=2880 marks=[2768] fromEnd=111 around `n fox jumps ov\|er.\nL78 the qu` | – |
| 165 | long start report | unmark → report | host[u16=2879 ch=2879 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 166 | long +100000 | move(100000) → mark | u16=2880 ch=2880 marks=[2768] fromEnd=111 around `n fox jumps ov\|er.\nL78 the qu` | – |
| 167 | long rapid 12x-100 | unmark → rapid(12x-100) → mark | u16=2880 ch=2880 marks=[1568] fromEnd=1311 around `e quick brown \|fox jumps over` | – |
| 168 | long to end | unmark → move(100000) → mark | u16=2880 ch=2880 marks=[1568] fromEnd=1311 around `e quick brown \|fox jumps over` | – |
| 169 | long paced 12x-100 | unmark → paced(12x-100) → mark | u16=2880 ch=2880 marks=[368] fromEnd=2511 around `over.\nL11 the \|quick brown fo` | – |
| 170 | long rapid 40x-1 | unmark → rapid(40x-1) → mark | u16=2880 ch=2880 marks=[328] fromEnd=2551 around `mps over.\nL10 \|the quick brow` | – |

**textfield — astral**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 1 | astral seed | seed | `x\u{1F600}y` | – |
| 2 | astral back1 | move(-1) → mark | `x\u{1F600}\|y` | 3 |
| 3 | astral back2 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}y` | 2 |
| 4 | astral back3 | unmark → move(-1) → mark | `x\|\u{1F600}y` | 1 |
| 5 | astral back4 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 6 | astral back5 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 7 | astral jump-50 | unmark → seed → move(-50) → mark | `x\u{1F600}y\|` | 4 |
| 8 | astral fwd1 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 9 | astral fwd2 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 10 | astral fwd3 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 11 | astral fwd4 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 12 | astral fwd5 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 13 | astral end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{FFFD}Z\u{FFFD}y` | – |
| 14 | astral end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 15 | astral end-3 mark | seed → move(-3) → mark | `x\|\u{1F600}y` | 1 |
| 16 | astral end-3 delete | unmark → deleteBackward | `\u{1F600}y` | – |

**textfield — zwj**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 17 | zwj seed | seed | `x\u{1F469}\u{200D}\u{1F4BB}y` | – |
| 18 | zwj back1 | move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}\|y` | 6 |
| 19 | zwj back2 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{FFFD}\|\u{FFFD}y` | 5 |
| 20 | zwj back3 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\|\u{1F4BB}y` | 4 |
| 21 | zwj back4 | unmark → move(-1) → mark | `x\u{1F469}\|\u{200D}\u{1F4BB}y` | 3 |
| 22 | zwj back5 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F4BB}y` | 2 |
| 23 | zwj back6 | unmark → move(-1) → mark | `x\|\u{1F469}\u{1F4BB}y` | 1 |
| 24 | zwj back7 | unmark → move(-1) → mark | `\|x\u{1F469}\u{1F4BB}y` | 0 |
| 25 | zwj back8 | unmark → move(-1) → mark | `\|x\u{1F469}\u{1F4BB}y` | 0 |
| 26 | zwj jump-50 | unmark → seed → move(-50) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 27 | zwj fwd1 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 28 | zwj fwd2 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 29 | zwj fwd3 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 30 | zwj fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 31 | zwj fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 32 | zwj fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 33 | zwj fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 34 | zwj fwd8 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 35 | zwj end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F469}\u{200D}\u{FFFD}Z\u{FFFD}y` | – |
| 36 | zwj end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 37 | zwj end-6 mark | seed → move(-6) → mark | `x\|\u{1F469}\u{200D}\u{1F4BB}y` | 1 |
| 38 | zwj end-6 delete | unmark → deleteBackward | `\u{1F469}\u{200D}\u{1F4BB}y` | – |

**textfield — flag**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 39 | flag seed | seed | `x\u{1F1EF}\u{1F1F5}y` | – |
| 40 | flag back1 | move(-1) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 41 | flag back2 | unmark → move(-1) → mark | `x\u{1F1EF}\u{FFFD}\|\u{FFFD}y` | 4 |
| 42 | flag back3 | unmark → move(-1) → mark | `x\u{1F1EF}\|\u{1F1F5}y` | 3 |
| 43 | flag back4 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F1F5}y` | 2 |
| 44 | flag back5 | unmark → move(-1) → mark | `x\|\u{1F1EF}\u{1F1F5}y` | 1 |
| 45 | flag back6 | unmark → move(-1) → mark | `\|x\u{1F1EF}\u{1F1F5}y` | 0 |
| 46 | flag back7 | unmark → move(-1) → mark | `\|x\u{1F1EF}\u{1F1F5}y` | 0 |
| 47 | flag jump-50 | unmark → seed → move(-50) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 48 | flag fwd1 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 49 | flag fwd2 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 50 | flag fwd3 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 51 | flag fwd4 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 52 | flag fwd5 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 53 | flag fwd6 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 54 | flag fwd7 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 55 | flag end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F1EF}\u{FFFD}Z\u{FFFD}y` | – |
| 56 | flag end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 57 | flag end-5 mark | seed → move(-5) → mark | `x\|\u{1F1EF}\u{1F1F5}y` | 1 |
| 58 | flag end-5 delete | unmark → deleteBackward | `\u{1F1EF}\u{1F1F5}y` | – |

**textfield — skin**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 59 | skin seed | seed | `x\u{1F44D}\u{1F3FD}y` | – |
| 60 | skin back1 | move(-1) → mark | `x\u{1F44D}\u{1F3FD}\|y` | 5 |
| 61 | skin back2 | unmark → move(-1) → mark | `x\u{1F44D}\u{FFFD}\|\u{FFFD}y` | 4 |
| 62 | skin back3 | unmark → move(-1) → mark | `x\u{1F44D}\|\u{1F3FD}y` | 3 |
| 63 | skin back4 | unmark → move(-1) → mark | `x\u{FFFD}\|\u{FFFD}y` | 2 |
| 64 | skin back5 | unmark → move(-1) → mark | `x\|\u{1F44D}y` | 1 |
| 65 | skin back6 | unmark → move(-1) → mark | `\|x\u{1F44D}y` | 0 |
| 66 | skin back7 | unmark → move(-1) → mark | `\|x\u{1F44D}y` | 0 |
| 67 | skin jump-50 | unmark → seed → move(-50) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 68 | skin fwd1 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 69 | skin fwd2 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 70 | skin fwd3 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 71 | skin fwd4 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 72 | skin fwd5 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 73 | skin fwd6 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 74 | skin fwd7 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 75 | skin end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F44D}\u{FFFD}Z\u{FFFD}y` | – |
| 76 | skin end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 77 | skin end-5 mark | seed → move(-5) → mark | `x\|\u{1F44D}\u{1F3FD}y` | 1 |
| 78 | skin end-5 delete | unmark → deleteBackward | `\u{1F44D}\u{1F3FD}y` | – |

**textfield — combining**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 79 | combining seed | seed | `xe\u{301}y` | – |
| 80 | combining back1 | move(-1) → mark | `xe\u{301}\|y` | 3 |
| 81 | combining back2 | unmark → move(-1) → mark | `xe\|\u{301}y` | 2 |
| 82 | combining back3 | unmark → move(-1) → mark | `x\|ey` | 1 |
| 83 | combining back4 | unmark → move(-1) → mark | `\|xey` | 0 |
| 84 | combining back5 | unmark → move(-1) → mark | `\|xey` | 0 |
| 85 | combining jump-50 | unmark → seed → move(-50) → mark | `xe\u{301}y\|` | 4 |
| 86 | combining fwd1 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 87 | combining fwd2 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 88 | combining fwd3 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 89 | combining fwd4 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 90 | combining fwd5 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 91 | combining end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `xeZ\u{301}y` | – |
| 92 | combining end-2 delete | seed → move(-2) → deleteBackward | `xy` | – |
| 93 | combining end-3 mark | seed → move(-3) → mark | `x\|e\u{301}y` | 1 |
| 94 | combining end-3 delete | unmark → deleteBackward | `e\u{301}y` | – |

**textfield — niqqud**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 95 | niqqud seed | seed | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | – |
| 96 | niqqud back1 | move(-1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 97 | niqqud back2 | unmark → move(-1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\|\u{5D0}y` | 4 |
| 98 | niqqud back3 | unmark → move(-1) → mark | `x\u{5D1}\u{5BC}\|\u{5E8}\u{5D0}y` | 3 |
| 99 | niqqud back4 | unmark → move(-1) → mark | `x\u{5D1}\|\u{5BC}\u{5E8}\u{5D0}y` | 2 |
| 100 | niqqud back5 | unmark → move(-1) → mark | `x\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 1 |
| 101 | niqqud back6 | unmark → move(-1) → mark | `\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 0 |
| 102 | niqqud back7 | unmark → move(-1) → mark | `\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 0 |
| 103 | niqqud jump-50 | unmark → seed → move(-50) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 104 | niqqud fwd1 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 105 | niqqud fwd2 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 106 | niqqud fwd3 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 107 | niqqud fwd4 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 108 | niqqud fwd5 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 109 | niqqud fwd6 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 110 | niqqud fwd7 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 111 | niqqud end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{5D1}\u{5BC}\u{5E8}Z\u{5D0}y` | – |
| 112 | niqqud end-2 delete | seed → move(-2) → deleteBackward | `x\u{5D1}\u{5BC}\u{5D0}y` | – |
| 113 | niqqud end-5 mark | seed → move(-5) → mark | `x\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 1 |
| 114 | niqqud end-5 delete | unmark → deleteBackward | `\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | – |

**textfield — mixed**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 115 | mixed seed | seed | `abc \u{5D0}\u{5D1}\u{5D2} def` | – |
| 116 | mixed back1 | move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 117 | mixed back2 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} d\|ef` | 9 |
| 118 | mixed back3 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} \|def` | 8 |
| 119 | mixed back4 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\u{5D2}\| def` | 7 |
| 120 | mixed back5 | unmark → move(-1) → mark | `abc \u{5D0}\u{5D1}\|\u{5D2} def` | 6 |
| 121 | mixed back6 | unmark → move(-1) → mark | `abc \u{5D0}\|\u{5D1}\u{5D2} def` | 5 |
| 122 | mixed back7 | unmark → move(-1) → mark | `abc \|\u{5D0}\u{5D1}\u{5D2} def` | 4 |
| 123 | mixed back8 | unmark → move(-1) → mark | `abc\| \u{5D0}\u{5D1}\u{5D2} def` | 3 |
| 124 | mixed back9 | unmark → move(-1) → mark | `ab\|c \u{5D0}\u{5D1}\u{5D2} def` | 2 |
| 125 | mixed back10 | unmark → move(-1) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 126 | mixed back11 | unmark → move(-1) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 127 | mixed back12 | unmark → move(-1) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 128 | mixed jump-50 | unmark → seed → move(-50) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 129 | mixed fwd1 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 130 | mixed fwd2 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 131 | mixed fwd3 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 132 | mixed fwd4 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 133 | mixed fwd5 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 134 | mixed fwd6 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 135 | mixed fwd7 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 136 | mixed fwd8 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 137 | mixed fwd9 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 138 | mixed fwd10 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 139 | mixed fwd11 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 140 | mixed fwd12 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 141 | mixed end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `abc \u{5D0}\u{5D1}\u{5D2} dZef` | – |
| 142 | mixed end-2 delete | seed → move(-2) → deleteBackward | `abc \u{5D0}\u{5D1}\u{5D2} ef` | – |
| 143 | mixed end-10 mark | seed → move(-10) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 144 | mixed end-10 delete | unmark → deleteBackward | `bc \u{5D0}\u{5D1}\u{5D2} def` | – |

**textfield — bidi**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 145 | bidi layout |  | `bc \u{5D0}\u{5D1}\u{5D2} def` | – |

**textfield — sel**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 146 | sel seed | seed | `wwwwwwww world` | – |
| 147 | sel report | report | `wwwwwwww world` | – |
| 148 | sel +3 | move(3) → mark | `wwwwwwww wo\|rld` | 11 |
| 149 | sel unmark | unmark | `wwwwwwww world` | – |
| 150 | sel -3 | move(-3) → mark | `wwwww\|www world` | 5 |
| 151 | sel unmark | unmark | `wwwwwwww world` | – |
| 152 | sel 0 | move(0) → mark | `\| world` | 0 |
| 153 | sel reseed | seed | `wwwwwwww world` | – |
| 154 | sel insert | insert(\|) | `\| world` | 0 |
| 155 | sel reseed | seed | `wwwwwwww world` | – |
| 156 | sel delete | deleteBackward | ` world` | – |

**textfield — long**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 157 | long seed | seed → report | host[u16=1439 ch=1439 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 158 | long -300 | move(-300) → mark | u16=1440 ch=1440 marks=[1139] fromEnd=300 around `uick brown fox\| jumps over. L` | – |
| 159 | long +300 | unmark → move(300) → mark | u16=1440 ch=1440 marks=[1439] fromEnd=0 around `ox jumps over.\|` | – |
| 160 | long -1200 | unmark → move(-1200) → mark | u16=1440 ch=1440 marks=[239] fromEnd=1200 around `uick brown fox\| jumps over. L` | – |
| 161 | long mid report | unmark → report | host[u16=1439 ch=1439 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 162 | long +1200 | move(1200) → mark | u16=1440 ch=1440 marks=[1439] fromEnd=0 around `ox jumps over.\|` | – |
| 163 | long beyond-context | unmark → beyond(exposed=71 move -111) → mark | u16=1440 ch=1440 marks=[1328] fromEnd=111 around `n fox jumps ov\|er. L38 the qu` | – |
| 164 | long -100000 | unmark → move(-100000) → mark | u16=1440 ch=1440 marks=[1328] fromEnd=111 around `n fox jumps ov\|er. L38 the qu` | – |
| 165 | long start report | unmark → report | host[u16=1439 ch=1439 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 166 | long +100000 | move(100000) → mark | u16=1440 ch=1440 marks=[1328] fromEnd=111 around `n fox jumps ov\|er. L38 the qu` | – |
| 167 | long rapid 12x-100 | unmark → rapid(12x-100) → mark | u16=1440 ch=1440 marks=[128] fromEnd=1311 around `e quick brown \|fox jumps over` | – |
| 168 | long to end | unmark → move(100000) → mark | u16=1440 ch=1440 marks=[128] fromEnd=1311 around `e quick brown \|fox jumps over` | – |
| 169 | long paced 12x-100 | unmark → paced(12x-100) → mark | u16=1440 ch=1440 marks=[28] fromEnd=1411 around `brown fox jump\|s over. L02 th` | – |
| 170 | long rapid 40x-1 | unmark → rapid(40x-1) → mark | u16=1440 ch=1440 marks=[28] fromEnd=1411 around `brown fox jump\|s over. L02 th` | – |

---

## Appendix B — run2 (`a2dcf136-…`): follow-up script for all hosts (#1–#78), then Safari first script (#79–#248, accumulated text, see caveat 3)

**textview — astral**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 1 | astral toStart | seed → move(-4) → mark | `\|x\u{1F600}y` | 0 |
| 2 | astral fwd1 | unmark → move(1) → mark | `x\|\u{1F600}y` | 1 |
| 3 | astral fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}y` | 2 |
| 4 | astral fwd3 | unmark → move(1) → mark | `x\u{1F600}\|y` | 3 |
| 5 | astral fwd4 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 6 | astral fwd5 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 7 | astral overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F600}\|y` | 3 |
| 8 | astral overshootStart | unmark → seed → move(-5) → mark | `x\u{1F600}y\|` | 4 |

**textview — zwj**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 9 | zwj toStart | unmark → seed → move(-7) → mark | `\|x\u{1F469}\u{200D}\u{1F4BB}y` | 0 |
| 10 | zwj fwd1 | unmark → move(1) → mark | `x\|\u{1F469}\u{200D}\u{1F4BB}y` | 1 |
| 11 | zwj fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}\u{200D}\u{1F4BB}y` | 2 |
| 12 | zwj fwd3 | unmark → move(1) → mark | `x\u{1F469}\|\u{200D}\u{1F4BB}y` | 3 |
| 13 | zwj fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{FFFD}\|\u{FFFD}y` | 4 |
| 14 | zwj fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}\|y` | 5 |
| 15 | zwj fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}y\|` | 6 |
| 16 | zwj fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}y\|` | 6 |
| 17 | zwj fwd8 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}y\|` | 6 |
| 18 | zwj overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F469}\u{200D}\u{1F4BB}\|y` | 6 |
| 19 | zwj overshootStart | unmark → seed → move(-8) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |

**textview — flag**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 20 | flag toStart | unmark → seed → move(-6) → mark | `\|x\u{1F1EF}\u{1F1F5}y` | 0 |
| 21 | flag fwd1 | unmark → move(1) → mark | `x\|\u{1F1EF}\u{1F1F5}y` | 1 |
| 22 | flag fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F1F5}y` | 2 |
| 23 | flag fwd3 | unmark → move(1) → mark | `x\u{1F1EF}\|\u{1F1F5}y` | 3 |
| 24 | flag fwd4 | unmark → move(1) → mark | `x\u{1F1EF}\u{FFFD}\|\u{FFFD}y` | 4 |
| 25 | flag fwd5 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 26 | flag fwd6 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 27 | flag fwd7 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 28 | flag overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 29 | flag overshootStart | unmark → seed → move(-7) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |

**textview — skin**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 30 | skin toStart | unmark → seed → move(-6) → mark | `\|x\u{1F44D}\u{1F3FD}y` | 0 |
| 31 | skin fwd1 | unmark → move(1) → mark | `x\|\u{1F44D}\u{1F3FD}y` | 1 |
| 32 | skin fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F3FD}y` | 2 |
| 33 | skin fwd3 | unmark → move(1) → mark | `x\u{1F44D}\|\u{1F3FD}y` | 3 |
| 34 | skin fwd4 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 35 | skin fwd5 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 36 | skin fwd6 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 37 | skin fwd7 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 38 | skin overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F44D}\u{1F3FD}\|y` | 5 |
| 39 | skin overshootStart | unmark → seed → move(-7) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |

**textview — combining**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 40 | combining toStart | unmark → seed → move(-4) → mark | `\|xe\u{301}y` | 0 |
| 41 | combining fwd1 | unmark → move(1) → mark | `x\|e\u{301}y` | 1 |
| 42 | combining fwd2 | unmark → move(1) → mark | `xe\|\u{301}y` | 2 |
| 43 | combining fwd3 | unmark → move(1) → mark | `xey\|` | 3 |
| 44 | combining fwd4 | unmark → move(1) → mark | `xey\|` | 3 |
| 45 | combining fwd5 | unmark → move(1) → mark | `xey\|` | 3 |
| 46 | combining overshootEnd | unmark → seed → move(-1) → move(2) → mark | `xe\u{301}\|y` | 3 |
| 47 | combining overshootStart | unmark → seed → move(-5) → mark | `xe\u{301}y\|` | 4 |

**textview — niqqud**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 48 | niqqud toStart | unmark → seed → move(-6) → mark | `\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 0 |
| 49 | niqqud fwd1 | unmark → move(1) → mark | `x\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 1 |
| 50 | niqqud fwd2 | unmark → move(1) → mark | `x\u{5D1}\|\u{5BC}\u{5E8}\u{5D0}y` | 2 |
| 51 | niqqud fwd3 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\|\u{5E8}\u{5D0}y` | 3 |
| 52 | niqqud fwd4 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\|\u{5D0}y` | 4 |
| 53 | niqqud fwd5 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 54 | niqqud fwd6 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 55 | niqqud fwd7 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 56 | niqqud overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 57 | niqqud overshootStart | unmark → seed → move(-7) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |

**textview — mixed**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 58 | mixed toStart | unmark → seed → move(-11) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 59 | mixed fwd1 | unmark → move(1) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 60 | mixed fwd2 | unmark → move(1) → mark | `ab\|c \u{5D0}\u{5D1}\u{5D2} def` | 2 |
| 61 | mixed fwd3 | unmark → move(1) → mark | `abc\| \u{5D0}\u{5D1}\u{5D2} def` | 3 |
| 62 | mixed fwd4 | unmark → move(1) → mark | `abc \|\u{5D0}\u{5D1}\u{5D2} def` | 4 |
| 63 | mixed fwd5 | unmark → move(1) → mark | `abc \u{5D0}\|\u{5D1}\u{5D2} def` | 5 |
| 64 | mixed fwd6 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\|\u{5D2} def` | 6 |
| 65 | mixed fwd7 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2}\| def` | 7 |
| 66 | mixed fwd8 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} \|def` | 8 |
| 67 | mixed fwd9 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} d\|ef` | 9 |
| 68 | mixed fwd10 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 69 | mixed fwd11 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 70 | mixed fwd12 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 71 | mixed overshootEnd | unmark → seed → move(-1) → move(2) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 72 | mixed overshootStart | unmark → seed → move(-12) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |

**textview — coalesce**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 73 | coalesce seed at 15 | unmark → seed → move(-5) → mark | `0123456789abcde\|fghij` | 15 |
| 74 | coalesce rapid 8x-1 in range | unmark → rapid(8x-1) → mark | `0123456\|789abcdefghij` | 7 |
| 75 | coalesce rapid 12x-1 sum overshoots by 5 | unmark → rapid(12x-1) → mark | `0123456\|789abcdefghij` | 7 |
| 76 | coalesce paced 12x-1 overshoots by 5 | unmark → paced(12x-1) → mark | `\|0123456789abcdefghij` | 0 |
| 77 | coalesce burst +3,-1,+3 | unmark → burst([3, -1, 3]) → mark | `01234\|56789abcdefghij` | 5 |
| 78 | coalesce burst +3 then insert at once | unmark → burst([1, 1, 1])+insert(Q) → report | `01234567Q89abcdefghij` | – |

**textfield — astral**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 1 | astral toStart | seed → move(-4) → mark | `\|x\u{1F600}y` | 0 |
| 2 | astral fwd1 | unmark → move(1) → mark | `x\|\u{1F600}y` | 1 |
| 3 | astral fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}y` | 2 |
| 4 | astral fwd3 | unmark → move(1) → mark | `x\u{1F600}\|y` | 3 |
| 5 | astral fwd4 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 6 | astral fwd5 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 7 | astral overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F600}\|y` | 3 |
| 8 | astral overshootStart | unmark → seed → move(-5) → mark | `x\u{1F600}y\|` | 4 |

**textfield — zwj**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 9 | zwj toStart | unmark → seed → move(-7) → mark | `\|x\u{1F469}\u{200D}\u{1F4BB}y` | 0 |
| 10 | zwj fwd1 | unmark → move(1) → mark | `x\|\u{1F469}\u{200D}\u{1F4BB}y` | 1 |
| 11 | zwj fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}\u{200D}\u{1F4BB}y` | 2 |
| 12 | zwj fwd3 | unmark → move(1) → mark | `x\u{1F469}\|\u{200D}\u{1F4BB}y` | 3 |
| 13 | zwj fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{FFFD}\|\u{FFFD}y` | 4 |
| 14 | zwj fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}\|y` | 5 |
| 15 | zwj fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}y\|` | 6 |
| 16 | zwj fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}y\|` | 6 |
| 17 | zwj fwd8 | unmark → move(1) → mark | `x\u{1F469}\u{1F4BB}y\|` | 6 |
| 18 | zwj overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F469}\u{200D}\u{1F4BB}\|y` | 6 |
| 19 | zwj overshootStart | unmark → seed → move(-8) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |

**textfield — flag**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 20 | flag toStart | unmark → seed → move(-6) → mark | `\|x\u{1F1EF}\u{1F1F5}y` | 0 |
| 21 | flag fwd1 | unmark → move(1) → mark | `x\|\u{1F1EF}\u{1F1F5}y` | 1 |
| 22 | flag fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F1F5}y` | 2 |
| 23 | flag fwd3 | unmark → move(1) → mark | `x\u{1F1EF}\|\u{1F1F5}y` | 3 |
| 24 | flag fwd4 | unmark → move(1) → mark | `x\u{1F1EF}\u{FFFD}\|\u{FFFD}y` | 4 |
| 25 | flag fwd5 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 26 | flag fwd6 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 27 | flag fwd7 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 28 | flag overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 29 | flag overshootStart | unmark → seed → move(-7) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |

**textfield — skin**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 30 | skin toStart | unmark → seed → move(-6) → mark | `\|x\u{1F44D}\u{1F3FD}y` | 0 |
| 31 | skin fwd1 | unmark → move(1) → mark | `x\|\u{1F44D}\u{1F3FD}y` | 1 |
| 32 | skin fwd2 | unmark → move(1) → mark | `x\u{FFFD}\|\u{FFFD}\u{1F3FD}y` | 2 |
| 33 | skin fwd3 | unmark → move(1) → mark | `x\u{1F44D}\|\u{1F3FD}y` | 3 |
| 34 | skin fwd4 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 35 | skin fwd5 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 36 | skin fwd6 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 37 | skin fwd7 | unmark → move(1) → mark | `x\u{1F44D}y\|` | 4 |
| 38 | skin overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F44D}\u{1F3FD}\|y` | 5 |
| 39 | skin overshootStart | unmark → seed → move(-7) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |

**textfield — combining**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 40 | combining toStart | unmark → seed → move(-4) → mark | `\|xe\u{301}y` | 0 |
| 41 | combining fwd1 | unmark → move(1) → mark | `x\|e\u{301}y` | 1 |
| 42 | combining fwd2 | unmark → move(1) → mark | `xe\|\u{301}y` | 2 |
| 43 | combining fwd3 | unmark → move(1) → mark | `xey\|` | 3 |
| 44 | combining fwd4 | unmark → move(1) → mark | `xey\|` | 3 |
| 45 | combining fwd5 | unmark → move(1) → mark | `xey\|` | 3 |
| 46 | combining overshootEnd | unmark → seed → move(-1) → move(2) → mark | `xe\u{301}\|y` | 3 |
| 47 | combining overshootStart | unmark → seed → move(-5) → mark | `xe\u{301}y\|` | 4 |

**textfield — niqqud**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 48 | niqqud toStart | unmark → seed → move(-6) → mark | `\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 0 |
| 49 | niqqud fwd1 | unmark → move(1) → mark | `x\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | 1 |
| 50 | niqqud fwd2 | unmark → move(1) → mark | `x\u{5D1}\|\u{5BC}\u{5E8}\u{5D0}y` | 2 |
| 51 | niqqud fwd3 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\|\u{5E8}\u{5D0}y` | 3 |
| 52 | niqqud fwd4 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\|\u{5D0}y` | 4 |
| 53 | niqqud fwd5 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 54 | niqqud fwd6 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 55 | niqqud fwd7 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 56 | niqqud overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 57 | niqqud overshootStart | unmark → seed → move(-7) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |

**textfield — mixed**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 58 | mixed toStart | unmark → seed → move(-11) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 59 | mixed fwd1 | unmark → move(1) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 60 | mixed fwd2 | unmark → move(1) → mark | `ab\|c \u{5D0}\u{5D1}\u{5D2} def` | 2 |
| 61 | mixed fwd3 | unmark → move(1) → mark | `abc\| \u{5D0}\u{5D1}\u{5D2} def` | 3 |
| 62 | mixed fwd4 | unmark → move(1) → mark | `abc \|\u{5D0}\u{5D1}\u{5D2} def` | 4 |
| 63 | mixed fwd5 | unmark → move(1) → mark | `abc \u{5D0}\|\u{5D1}\u{5D2} def` | 5 |
| 64 | mixed fwd6 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\|\u{5D2} def` | 6 |
| 65 | mixed fwd7 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2}\| def` | 7 |
| 66 | mixed fwd8 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} \|def` | 8 |
| 67 | mixed fwd9 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} d\|ef` | 9 |
| 68 | mixed fwd10 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 69 | mixed fwd11 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 70 | mixed fwd12 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 71 | mixed overshootEnd | unmark → seed → move(-1) → move(2) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 72 | mixed overshootStart | unmark → seed → move(-12) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |

**textfield — coalesce**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 73 | coalesce seed at 15 | unmark → seed → move(-5) → mark | `0123456789abcde\|fghij` | 15 |
| 74 | coalesce rapid 8x-1 in range | unmark → rapid(8x-1) → mark | `0123456\|789abcdefghij` | 7 |
| 75 | coalesce rapid 12x-1 sum overshoots by 5 | unmark → rapid(12x-1) → mark | `0123456\|789abcdefghij` | 7 |
| 76 | coalesce paced 12x-1 overshoots by 5 | unmark → paced(12x-1) → mark | `\|0123456789abcdefghij` | 0 |
| 77 | coalesce burst +3,-1,+3 | unmark → burst([3, -1, 3]) → mark | `01234\|56789abcdefghij` | 5 |
| 78 | coalesce burst +3 then insert at once | unmark → burst([1, 1, 1])+insert(Q) → report | `01234567Q89abcdefghij` | – |

**safari — astral**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 1 | astral toStart | seed → move(-4) → mark | `x\u{1F600}y\|` | 4 |
| 2 | astral fwd1 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 3 | astral fwd2 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 4 | astral fwd3 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 5 | astral fwd4 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 6 | astral fwd5 | unmark → move(1) → mark | `x\u{1F600}y\|` | 4 |
| 7 | astral overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F600}\|y` | 3 |
| 8 | astral overshootStart | unmark → seed → move(-5) → mark | `x\u{1F600}y\|` | 4 |

**safari — zwj**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 9 | zwj toStart | unmark → seed → move(-7) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 10 | zwj fwd1 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 11 | zwj fwd2 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 12 | zwj fwd3 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 13 | zwj fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 14 | zwj fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 15 | zwj fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 16 | zwj fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 17 | zwj fwd8 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |
| 18 | zwj overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F469}\u{200D}\u{1F4BB}\|y` | 6 |
| 19 | zwj overshootStart | unmark → seed → move(-8) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|` | 7 |

**safari — flag**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 20 | flag toStart | unmark → seed → move(-6) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 21 | flag fwd1 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 22 | flag fwd2 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 23 | flag fwd3 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 24 | flag fwd4 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 25 | flag fwd5 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 26 | flag fwd6 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 27 | flag fwd7 | unmark → move(1) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |
| 28 | flag overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F1EF}\u{1F1F5}\|y` | 5 |
| 29 | flag overshootStart | unmark → seed → move(-7) → mark | `x\u{1F1EF}\u{1F1F5}y\|` | 6 |

**safari — skin**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 30 | skin toStart | unmark → seed → move(-6) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 31 | skin fwd1 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 32 | skin fwd2 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 33 | skin fwd3 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 34 | skin fwd4 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 35 | skin fwd5 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 36 | skin fwd6 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 37 | skin fwd7 | unmark → move(1) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |
| 38 | skin overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{1F44D}\u{1F3FD}\|y` | 5 |
| 39 | skin overshootStart | unmark → seed → move(-7) → mark | `x\u{1F44D}\u{1F3FD}y\|` | 6 |

**safari — combining**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 40 | combining toStart | unmark → seed → move(-4) → mark | `xe\u{301}y\|` | 4 |
| 41 | combining fwd1 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 42 | combining fwd2 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 43 | combining fwd3 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 44 | combining fwd4 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 45 | combining fwd5 | unmark → move(1) → mark | `xe\u{301}y\|` | 4 |
| 46 | combining overshootEnd | unmark → seed → move(-1) → move(2) → mark | `xe\u{301}\|y` | 3 |
| 47 | combining overshootStart | unmark → seed → move(-5) → mark | `xe\u{301}y\|` | 4 |

**safari — niqqud**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 48 | niqqud toStart | unmark → seed → move(-6) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 49 | niqqud fwd1 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 50 | niqqud fwd2 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 51 | niqqud fwd3 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 52 | niqqud fwd4 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 53 | niqqud fwd5 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 54 | niqqud fwd6 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 55 | niqqud fwd7 | unmark → move(1) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |
| 56 | niqqud overshootEnd | unmark → seed → move(-1) → move(2) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|y` | 5 |
| 57 | niqqud overshootStart | unmark → seed → move(-7) → mark | `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|` | 6 |

**safari — mixed**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 58 | mixed toStart | unmark → seed → move(-11) → mark | `\|abc \u{5D0}\u{5D1}\u{5D2} def` | 0 |
| 59 | mixed fwd1 | unmark → move(1) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 60 | mixed fwd2 | unmark → move(1) → mark | `ab\|c \u{5D0}\u{5D1}\u{5D2} def` | 2 |
| 61 | mixed fwd3 | unmark → move(1) → mark | `abc\| \u{5D0}\u{5D1}\u{5D2} def` | 3 |
| 62 | mixed fwd4 | unmark → move(1) → mark | `abc \|\u{5D0}\u{5D1}\u{5D2} def` | 4 |
| 63 | mixed fwd5 | unmark → move(1) → mark | `abc \u{5D0}\|\u{5D1}\u{5D2} def` | 5 |
| 64 | mixed fwd6 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\|\u{5D2} def` | 6 |
| 65 | mixed fwd7 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2}\| def` | 7 |
| 66 | mixed fwd8 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} \|def` | 8 |
| 67 | mixed fwd9 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} d\|ef` | 9 |
| 68 | mixed fwd10 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 69 | mixed fwd11 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 70 | mixed fwd12 | unmark → move(1) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |
| 71 | mixed overshootEnd | unmark → seed → move(-1) → move(2) → mark | `abc \u{5D0}\u{5D1}\u{5D2} de\|f` | 10 |
| 72 | mixed overshootStart | unmark → seed → move(-12) → mark | `abc \u{5D0}\u{5D1}\u{5D2} def\|` | 11 |

**safari — coalesce**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 73 | coalesce seed at 15 | unmark → seed → move(-5) → mark | `0123456789abcde\|fghij` | 15 |
| 74 | coalesce rapid 8x-1 in range | unmark → rapid(8x-1) → mark | `0123456\|789abcdefghij` | 7 |
| 75 | coalesce rapid 12x-1 sum overshoots by 5 | unmark → rapid(12x-1) → mark | `0123456\|789abcdefghij` | 7 |
| 76 | coalesce paced 12x-1 overshoots by 5 | unmark → paced(12x-1) → mark | `\|0123456789abcdefghij` | 0 |
| 77 | coalesce burst +3,-1,+3 | unmark → burst([3, -1, 3]) → mark | `01234\|56789abcdefghij` | 5 |
| 78 | coalesce burst +3 then insert at once | unmark → burst([1, 1, 1])+insert(Q) → report | `01234567Q89abcdefghij` | – |

**safari — astral**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 79 | astral seed | seed | `x\u{1F600}y` | – |
| 80 | astral back1 | move(-1) → mark | `x\u{1F600}\|y` | 3 |
| 81 | astral back2 | unmark → move(-1) → mark | `x\|\u{1F600}y` | 1 |
| 82 | astral back3 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 83 | astral back4 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 84 | astral back5 | unmark → move(-1) → mark | `\|x\u{1F600}y` | 0 |
| 85 | astral jump-50 | unmark → seed → move(-50) → mark | `x\u{1F600}y\|x\u{1F600}y` | 4 |
| 86 | astral fwd1 | unmark → move(1) → mark | `x\u{1F600}yx\|\u{1F600}y` | 5 |
| 87 | astral fwd2 | unmark → move(1) → mark | `x\u{1F600}yx\u{1F600}\|y` | 7 |
| 88 | astral fwd3 | unmark → move(1) → mark | `x\u{1F600}yx\u{1F600}y\|` | 8 |
| 89 | astral fwd4 | unmark → move(1) → mark | `x\u{1F600}yx\u{1F600}y\|` | 8 |
| 90 | astral fwd5 | unmark → move(1) → mark | `x\u{1F600}yx\u{1F600}y\|` | 8 |
| 91 | astral end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `xZ\u{1F600}y` | – |
| 92 | astral end-2 delete | seed → move(-2) → deleteBackward | `xZ\u{1F600}y\u{1F600}y` | – |
| 93 | astral end-3 mark | seed → move(-3) → mark | `xZ\|x\u{1F600}y\u{1F600}y\u{1F600}y` | 2 |
| 94 | astral end-3 delete | unmark → deleteBackward | `xx\u{1F600}y\u{1F600}y\u{1F600}y` | – |

**safari — zwj**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 95 | zwj seed | seed | `xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | – |
| 96 | zwj back1 | move(-1) → mark | `xx\u{1F469}\u{200D}\u{1F4BB}\|yx\u{1F600}y\u{1F600}y\u{1F600}y` | 7 |
| 97 | zwj back2 | unmark → move(-1) → mark | `xx\|\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 2 |
| 98 | zwj back3 | unmark → move(-1) → mark | `x\|x\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 1 |
| 99 | zwj back4 | unmark → move(-1) → mark | `\|xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 0 |
| 100 | zwj back5 | unmark → move(-1) → mark | `\|xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 0 |
| 101 | zwj back6 | unmark → move(-1) → mark | `\|xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 0 |
| 102 | zwj back7 | unmark → move(-1) → mark | `\|xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 0 |
| 103 | zwj back8 | unmark → move(-1) → mark | `\|xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 0 |
| 104 | zwj jump-50 | unmark → seed → move(-50) → mark | `x\u{1F469}\u{200D}\u{1F4BB}y\|xx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 7 |
| 105 | zwj fwd1 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yx\|x\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 8 |
| 106 | zwj fwd2 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\|\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}y\u{1F600}y` | 9 |
| 107 | zwj fwd3 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}\|yx\u{1F600}y\u{1F600}y\u{1F600}y` | 14 |
| 108 | zwj fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}y\|x\u{1F600}y\u{1F600}y\u{1F600}y` | 15 |
| 109 | zwj fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\|\u{1F600}y\u{1F600}y\u{1F600}y` | 16 |
| 110 | zwj fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}\|y\u{1F600}y\u{1F600}y` | 18 |
| 111 | zwj fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\|\u{1F600}y\u{1F600}y` | 19 |
| 112 | zwj fwd8 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}\|y\u{1F600}y` | 21 |
| 113 | zwj end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}xZ\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |
| 114 | zwj end-2 delete | seed → move(-2) → deleteBackward | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\u{1F600}xZ\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |
| 115 | zwj end-6 mark | seed → move(-6) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}y\|\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 19 |
| 116 | zwj end-6 delete | unmark → deleteBackward | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |

**safari — flag**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 117 | flag seed | seed | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |
| 118 | flag back1 | move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}\|y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 23 |
| 119 | flag back2 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\|\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 19 |
| 120 | flag back3 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}\|x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 18 |
| 121 | flag back4 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}yx\|\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 16 |
| 122 | flag back5 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}y\|x\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 15 |
| 123 | flag back6 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\u{1F469}\u{200D}\u{1F4BB}\|yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 14 |
| 124 | flag back7 | unmark → move(-1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxx\|\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 9 |
| 125 | flag jump-50 | unmark → seed → move(-50) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\|\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 15 |
| 126 | flag fwd1 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}\|yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 20 |
| 127 | flag fwd2 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}y\|x\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 21 |
| 128 | flag fwd3 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\|\u{1F600}x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 22 |
| 129 | flag fwd4 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}\|x\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 24 |
| 130 | flag fwd5 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\|\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 25 |
| 131 | flag fwd6 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}\|y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 29 |
| 132 | flag fwd7 | unmark → move(1) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\|\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 30 |
| 133 | flag end-2 insertZ | unmark → seed → move(-2) → insert(Z) | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}yxZ\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |
| 134 | flag end-2 delete | seed → move(-2) → deleteBackward | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}yxZ\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |
| 135 | flag end-5 mark | seed → move(-5) → mark | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}y\|xZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | 30 |
| 136 | flag end-5 delete | unmark → deleteBackward | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |

**safari — skin**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 137 | skin seed | seed | `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}y\u{1F469}\u{200D}\u{1F4BB}yy\u{1F600}y` | – |
| 138 | skin back1 | move(-1) → mark | u16=81 ch=40 marks=[34] fromEnd=46 around `yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}\|yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx` | – |
| 139 | skin back2 | unmark → move(-1) → mark | u16=81 ch=40 marks=[30] fromEnd=50 around `\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\|\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZ` | – |
| 140 | skin back3 | unmark → move(-1) → mark | u16=81 ch=40 marks=[29] fromEnd=51 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\u{1F1EF}\u{1F1F5}\|x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}x` | – |
| 141 | skin back4 | unmark → move(-1) → mark | u16=81 ch=40 marks=[25] fromEnd=55 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}x\|\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}` | – |
| 142 | skin back5 | unmark → move(-1) → mark | u16=81 ch=40 marks=[24] fromEnd=56 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F600}\|x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y` | – |
| 143 | skin back6 | unmark → move(-1) → mark | u16=81 ch=40 marks=[22] fromEnd=58 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\|\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}` | – |
| 144 | skin back7 | unmark → move(-1) → mark | u16=81 ch=40 marks=[21] fromEnd=59 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}y\|x\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y` | – |
| 145 | skin jump-50 | unmark → seed → move(-50) → mark | u16=87 ch=43 marks=[27] fromEnd=59 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}y\|x\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y` | – |
| 146 | skin fwd1 | unmark → move(1) → mark | u16=87 ch=43 marks=[28] fromEnd=58 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\|\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}` | – |
| 147 | skin fwd2 | unmark → move(1) → mark | u16=87 ch=43 marks=[30] fromEnd=56 around `\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}\|x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y` | – |
| 148 | skin fwd3 | unmark → move(1) → mark | u16=87 ch=43 marks=[31] fromEnd=55 around `yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\|\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}` | – |
| 149 | skin fwd4 | unmark → move(1) → mark | u16=87 ch=43 marks=[35] fromEnd=51 around `xxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}\|x\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}x` | – |
| 150 | skin fwd5 | unmark → move(1) → mark | u16=87 ch=43 marks=[36] fromEnd=50 around `xx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\|\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZ` | – |
| 151 | skin fwd6 | unmark → move(1) → mark | u16=87 ch=43 marks=[40] fromEnd=46 around `x\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}\|yxZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx` | – |
| 152 | skin fwd7 | unmark → move(1) → mark | u16=87 ch=43 marks=[41] fromEnd=45 around `\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}y\|xZx\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F1EF}\u{1F1F5}y\u{1F600}xZx\u{1F469}\u{200D}\u{1F4BB}` | – |
| 153 | skin end-2 insertZ | unmark → seed → move(-2) → insert(Z) | host[u16=93 ch=46 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D} | – |
| 154 | skin end-2 delete | seed → move(-2) → deleteBackward | host[u16=98 ch=48 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D} | – |
| 155 | skin end-5 mark | seed → move(-5) → mark | u16=105 ch=52 marks=[41] fromEnd=63 around `\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}y\|xZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y` | – |
| 156 | skin end-5 delete | unmark → deleteBackward | host[u16=103 ch=50 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |

**safari — combining**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 157 | combining seed | seed | host[u16=107 ch=53 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |
| 158 | combining back1 | move(-1) → mark | u16=108 ch=54 marks=[43] fromEnd=64 around `y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}xe\u{301}\|yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}` | – |
| 159 | combining back2 | unmark → move(-1) → mark | u16=108 ch=54 marks=[41] fromEnd=66 around `\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}x\|e\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZx` | – |
| 160 | combining back3 | unmark → move(-1) → mark | u16=108 ch=54 marks=[40] fromEnd=67 around `x\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\u{1F44D}\u{1F3FD}\|xe\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZ` | – |
| 161 | combining back4 | unmark → move(-1) → mark | u16=108 ch=54 marks=[36] fromEnd=71 around `xx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x\|\u{1F44D}\u{1F3FD}xe\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yx` | – |
| 162 | combining back5 | unmark → move(-1) → mark | u16=108 ch=54 marks=[35] fromEnd=72 around `xxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}\|x\u{1F44D}\u{1F3FD}xe\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y` | – |
| 163 | combining jump-50 | unmark → seed → move(-50) → mark | u16=112 ch=57 marks=[39] fromEnd=72 around `\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}y\|x\u{1F44D}\u{1F3FD}xe\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y` | – |
| 164 | combining fwd1 | unmark → move(1) → mark | u16=112 ch=57 marks=[40] fromEnd=71 around `y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\|\u{1F44D}\u{1F3FD}xe\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yx` | – |
| 165 | combining fwd2 | unmark → move(1) → mark | u16=112 ch=57 marks=[44] fromEnd=67 around `\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}\|xe\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZ` | – |
| 166 | combining fwd3 | unmark → move(1) → mark | u16=112 ch=57 marks=[45] fromEnd=66 around `yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}x\|e\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZx` | – |
| 167 | combining fwd4 | unmark → move(1) → mark | u16=112 ch=57 marks=[47] fromEnd=64 around `x\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}\|yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}` | – |
| 168 | combining fwd5 | unmark → move(1) → mark | u16=112 ch=57 marks=[48] fromEnd=63 around `\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}y\|xZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}yxZx\u{1F1EF}\u{1F1F5}y` | – |
| 169 | combining end-2 insertZ | unmark → seed → move(-2) → insert(Z) | host[u16=116 ch=60 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |
| 170 | combining end-2 delete | seed → move(-2) → deleteBackward | host[u16=119 ch=62 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |
| 171 | combining end-3 mark | seed → move(-3) → mark | u16=124 ch=66 marks=[50] fromEnd=73 around `x\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}yxZ\|xe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y` | – |
| 172 | combining end-3 delete | unmark → deleteBackward | host[u16=122 ch=64 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |

**safari — niqqud**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 173 | niqqud seed | seed | host[u16=128 ch=69 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |
| 174 | niqqud back1 | move(-1) → mark | u16=129 ch=70 marks=[54] fromEnd=74 around `\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}yxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|yxe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}` | – |
| 175 | niqqud back2 | unmark → move(-1) → mark | u16=129 ch=70 marks=[53] fromEnd=75 around `x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}yxx\u{5D1}\u{5BC}\u{5E8}\|\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}y` | – |
| 176 | niqqud back3 | unmark → move(-1) → mark | u16=129 ch=70 marks=[52] fromEnd=76 around `\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}yxx\u{5D1}\u{5BC}\|\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}` | – |
| 177 | niqqud back4 | unmark → move(-1) → mark | u16=129 ch=70 marks=[50] fromEnd=78 around `x\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}yxx\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZx` | – |
| 178 | niqqud back5 | unmark → move(-1) → mark | u16=129 ch=70 marks=[49] fromEnd=79 around `yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}yx\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZ` | – |
| 179 | niqqud back6 | unmark → move(-1) → mark | u16=129 ch=70 marks=[48] fromEnd=80 around `\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}y\|xx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yx` | – |
| 180 | niqqud back7 | unmark → move(-1) → mark | u16=129 ch=70 marks=[47] fromEnd=81 around `x\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}\|yxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}y` | – |
| 181 | niqqud jump-50 | unmark → seed → move(-50) → mark | u16=135 ch=75 marks=[53] fromEnd=81 around `x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|yxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}y` | – |
| 182 | niqqud fwd1 | unmark → move(1) → mark | u16=135 ch=75 marks=[54] fromEnd=80 around `\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yy\|xx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yx` | – |
| 183 | niqqud fwd2 | unmark → move(1) → mark | u16=135 ch=75 marks=[55] fromEnd=79 around `xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yyx\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZ` | – |
| 184 | niqqud fwd3 | unmark → move(1) → mark | u16=135 ch=75 marks=[56] fromEnd=78 around `e\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yyxx\|\u{5D1}\u{5BC}\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZx` | – |
| 185 | niqqud fwd4 | unmark → move(1) → mark | u16=135 ch=75 marks=[58] fromEnd=76 around `yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yyxx\u{5D1}\u{5BC}\|\u{5E8}\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}` | – |
| 186 | niqqud fwd5 | unmark → move(1) → mark | u16=135 ch=75 marks=[59] fromEnd=75 around `x\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yyxx\u{5D1}\u{5BC}\u{5E8}\|\u{5D0}yxe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}y` | – |
| 187 | niqqud fwd6 | unmark → move(1) → mark | u16=135 ch=75 marks=[60] fromEnd=74 around `\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yyxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}\|yxe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}` | – |
| 188 | niqqud fwd7 | unmark → move(1) → mark | u16=135 ch=75 marks=[61] fromEnd=73 around `xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yyxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\|xe\u{301}ye\u{301}ye\u{301}yxZx\u{1F44D}\u{1F3FD}y\u{1F44D}\u{1F3FD}y` | – |
| 189 | niqqud end-2 insertZ | unmark → seed → move(-2) → insert(Z) | host[u16=141 ch=80 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |
| 190 | niqqud end-2 delete | seed → move(-2) → deleteBackward | host[u16=146 ch=84 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |
| 191 | niqqud end-5 mark | seed → move(-5) → mark | u16=153 ch=90 marks=[69] fromEnd=83 around `yyxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}\u{5BC}\|x\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y\u{5D0}yxe\u{301}ye\u{301}y` | – |
| 192 | niqqud end-5 delete | unmark → deleteBackward | host[u16=151 ch=89 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D | – |

**safari — mixed**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 193 | mixed seed | seed | host[u16=162 ch=100 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44 | – |
| 194 | mixed back1 | move(-1) → mark | host[u16=163 ch=101 marks=[78] fromEnd=84] around="\u{5E8}Zx\u{5D1}abc \u{5D0}\u{5D1}\u{5D2} de\|fx\u{5D1}\u{5BC}\u{5E8} | – |
| 195 | mixed back2 | unmark → move(-1) → mark | u16=163 ch=101 marks=[77] fromEnd=85 around `\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc \u{5D0}\u{5D1}\u{5D2} d\|efx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y\u{5D0}yxe\u{301}y` | – |
| 196 | mixed back3 | unmark → move(-1) → mark | u16=163 ch=101 marks=[76] fromEnd=86 around `x\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc \u{5D0}\u{5D1}\u{5D2} \|defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y\u{5D0}yxe\u{301}` | – |
| 197 | mixed back4 | unmark → move(-1) → mark | u16=163 ch=101 marks=[75] fromEnd=87 around `yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc \u{5D0}\u{5D1}\u{5D2}\| defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y\u{5D0}yx` | – |
| 198 | mixed back5 | unmark → move(-1) → mark | u16=163 ch=101 marks=[74] fromEnd=88 around `\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc \u{5D0}\u{5D1}\|\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y\u{5D0}y` | – |
| 199 | mixed back6 | unmark → move(-1) → mark | u16=163 ch=101 marks=[73] fromEnd=89 around `\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc \u{5D0}\|\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y\u{5D0}` | – |
| 200 | mixed back7 | unmark → move(-1) → mark | u16=163 ch=101 marks=[72] fromEnd=90 around `\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc \|\u{5D0}\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}y` | – |
| 201 | mixed back8 | unmark → move(-1) → mark | u16=163 ch=101 marks=[71] fromEnd=91 around `x\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}abc\| \u{5D0}\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y\u{5D0}` | – |
| 202 | mixed back9 | unmark → move(-1) → mark | u16=163 ch=101 marks=[70] fromEnd=92 around `xx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}ab\|c \u{5D0}\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}y` | – |
| 203 | mixed back10 | unmark → move(-1) → mark | u16=163 ch=101 marks=[69] fromEnd=93 around `yxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}a\|bc \u{5D0}\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}\u{5D0}` | – |
| 204 | mixed back11 | unmark → move(-1) → mark | u16=163 ch=101 marks=[68] fromEnd=94 around `yyxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\u{5D1}\|abc \u{5D0}\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}\u{5E8}` | – |
| 205 | mixed back12 | unmark → move(-1) → mark | u16=163 ch=101 marks=[67] fromEnd=95 around `\u{5D0}yyxx\u{5D1}\u{5BC}\u{5E8}\u{5D0}yx\u{5D1}\u{5BC}\u{5E8}Zx\|\u{5D1}abc \u{5D0}\u{5D1}\u{5D2} defx\u{5D1}\u{5BC}` | – |
| 206 | mixed jump-50 | unmark → seed → move(-50) → mark | u16=174 ch=112 marks=[6] fromEnd=167 around `x\u{1F469}\u{200D}\u{1F4BB}\|yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x` | – |
| 207 | mixed fwd1 | unmark → move(1) → mark | u16=174 ch=112 marks=[7] fromEnd=166 around `x\u{1F469}\u{200D}\u{1F4BB}y\|xxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}` | – |
| 208 | mixed fwd2 | unmark → move(1) → mark | u16=174 ch=112 marks=[8] fromEnd=165 around `x\u{1F469}\u{200D}\u{1F4BB}yx\|xx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}x` | – |
| 209 | mixed fwd3 | unmark → move(1) → mark | u16=174 ch=112 marks=[9] fromEnd=164 around `x\u{1F469}\u{200D}\u{1F4BB}yxx\|x\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}` | – |
| 210 | mixed fwd4 | unmark → move(1) → mark | u16=174 ch=112 marks=[10] fromEnd=163 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\|\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}y` | – |
| 211 | mixed fwd5 | unmark → move(1) → mark | u16=174 ch=112 marks=[14] fromEnd=159 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}\|y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx` | – |
| 212 | mixed fwd6 | unmark → move(1) → mark | u16=174 ch=112 marks=[15] fromEnd=158 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\|\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}` | – |
| 213 | mixed fwd7 | unmark → move(1) → mark | u16=174 ch=112 marks=[20] fromEnd=153 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}\|yx\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}x` | – |
| 214 | mixed fwd8 | unmark → move(1) → mark | u16=174 ch=112 marks=[21] fromEnd=152 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}y\|x\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}` | – |
| 215 | mixed fwd9 | unmark → move(1) → mark | u16=174 ch=112 marks=[22] fromEnd=151 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\|\u{1F44D}\u{1F3FD}yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x` | – |
| 216 | mixed fwd10 | unmark → move(1) → mark | u16=174 ch=112 marks=[26] fromEnd=147 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}\|yx\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}` | – |
| 217 | mixed fwd11 | unmark → move(1) → mark | u16=174 ch=112 marks=[27] fromEnd=146 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}y\|x\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}` | – |
| 218 | mixed fwd12 | unmark → move(1) → mark | u16=174 ch=112 marks=[28] fromEnd=145 around `x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44D}\u{1F3FD}yx\|\u{1F600}x\u{1F1EF}\u{1F1F5}xe\u{301}yx\u{1F44D}\u{1F3FD}xe\u{301}x\u{5D1}\u{5BC}\u{5E8}\u{5D0}` | – |
| 219 | mixed end-2 insertZ | unmark → seed → move(-2) → insert(Z) | host[u16=185 ch=123 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44 | – |
| 220 | mixed end-2 delete | seed → move(-2) → deleteBackward | host[u16=195 ch=133 no-mark] head="x\u{1F469}\u{200D}\u{1F4BB}yxxx\u{1F1EF}\u{1F1F5}y\u{1F469}\u{200D}\u{1F4BB}yx\u{1F44 | – |
| 221 | mixed end-10 mark | seed → move(-10) → mark | `a\|bc \u{5D0}\u{5D1}\u{5D2} def` | 1 |
| 222 | mixed end-10 delete | unmark → deleteBackward | `bc \u{5D0}\u{5D1}\u{5D2} def` | – |

**safari — bidi**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 223 | bidi layout |  | `bc \u{5D0}\u{5D1}\u{5D2} def` | – |

**safari — sel**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 224 | sel seed | seed | `wwwwwwww world` | – |
| 225 | sel report | report | `wwwwwwww world` | – |
| 226 | sel +3 | move(3) → mark | `wwwwwwww \|` | 9 |
| 227 | sel unmark | unmark | `wwwwwwww ` | – |
| 228 | sel -3 | move(-3) → mark | `wwwwww\|ww ` | 6 |
| 229 | sel unmark | unmark | `wwwwwwww ` | – |
| 230 | sel 0 | move(0) → mark | `\|` | 0 |
| 231 | sel reseed | seed | `wwwwwwww world` | – |
| 232 | sel insert | insert(\|) | `wwwwwwww \|` | 9 |
| 233 | sel reseed | seed | `wwwwwwww world` | – |
| 234 | sel delete | deleteBackward | `wwwwwwww` | – |

**safari — long**

| # | step | proxy calls | host value after (ground truth) | marker @ UTF-16 |
|---|---|---|---|---|
| 235 | long seed | seed → report | host[u16=2879 ch=2879 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 236 | long -300 | move(-300) → mark | u16=2880 ch=2880 marks=[2579] fromEnd=300 around `uick brown fox\| jumps over.\nL` | – |
| 237 | long +300 | unmark → move(300) → mark | u16=2880 ch=2880 marks=[2879] fromEnd=0 around `ox jumps over.\|` | – |
| 238 | long -1200 | unmark → move(-1200) → mark | u16=2880 ch=2880 marks=[1679] fromEnd=1200 around `uick brown fox\| jumps over.\nL` | – |
| 239 | long mid report | unmark → report | host[u16=2879 ch=2879 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 240 | long +1200 | move(1200) → mark | u16=2880 ch=2880 marks=[2879] fromEnd=0 around `ox jumps over.\|` | – |
| 241 | long beyond-context | unmark → beyond(exposed=51 move -91) → mark | u16=2880 ch=2880 marks=[2788] fromEnd=91 around `8 the quick br\|own fox jumps ` | – |
| 242 | long -100000 | unmark → move(-100000) → mark | u16=2880 ch=2880 marks=[2788] fromEnd=91 around `8 the quick br\|own fox jumps ` | – |
| 243 | long start report | unmark → report | host[u16=2879 ch=2879 no-mark] head="L01 the quick br" tail=" fox jumps over." | – |
| 244 | long +100000 | move(100000) → mark | u16=2880 ch=2880 marks=[2788] fromEnd=91 around `8 the quick br\|own fox jumps ` | – |
| 245 | long rapid 12x-100 | unmark → rapid(12x-100) → mark | u16=2880 ch=2880 marks=[1588] fromEnd=1291 around `mps over.\nL45 \|the quick brow` | – |
| 246 | long to end | unmark → move(100000) → mark | u16=2880 ch=2880 marks=[1588] fromEnd=1291 around `mps over.\nL45 \|the quick brow` | – |
| 247 | long paced 12x-100 | unmark → paced(12x-100) → mark | u16=2880 ch=2880 marks=[388] fromEnd=2491 around `brown fox jump\|s over.\nL12 th` | – |
| 248 | long rapid 40x-1 | unmark → rapid(40x-1) → mark | u16=2880 ch=2880 marks=[348] fromEnd=2531 around `ick brown fox \|jumps over.\nL1` | – |
