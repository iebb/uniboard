# Uniboard — Movable cursor in the text preview (design spec, rev. 4)

Rev. 4, 24 Oct (build review msg590, Pluso msg588): the 24 pt margin is measured
from the inner edge of a "…" cap, not from the text area edge, so whole
letters show before the caret after a drag (§2, §3, §4, checks 3 and 4).
Known 1.3.0 limit: a ~2 pt stub of an overhanging italic glyph may show
at a cap (§1).

Rev. 3, 24 Oct: the caret blinks like a normal insertion cursor (user msg483,
Ato msg484) — §1a and check 14. Nothing else changed.

Rev. 2, 24 Oct: updated from Pluso's host findings (msg440) and Ato msg442 —
natural direction + RTL mirroring (§1–4), logical bidi mapping, exposed-
context limits, one-move-at-a-time pacing, calibration only on user moves,
no moves while the app has a selection (§6), checks 9–13.

Asked by: user msg387 ("make the textDocumentProxy inspector cursor movable,
act like an exact same input while with font rendering"); scope Ato msg388.
Task: task.26b50590. Builds on design/inspect/design.md §1/§1a (preview row,
icons) and design/copy-image/larger-panel (Copy Image).
Mockups: artifact "Uniboard — Cursor in the text preview" (illustrative;
this text wins over a picture). Screens in ./screens/.

## 0. What this is, and the iOS limits it respects
- The preview row already shows the app's text around the cursor in
  Uniboard's fonts, and typing/deleting already happen at the real cursor.
  New: tapping or dragging inside the preview moves the REAL cursor in the
  app (`textDocumentProxy.adjustTextPosition(byCharacterOffset:)`), and the
  preview redraws from the real context.
- A keyboard cannot: select text, draw above its own area (no loupe), read
  more than the app exposes, or move to another line except by offsets
  through the newline. So: no selection, no edit menu, no loupe; the
  preview edits only the cursor's current line (see §6).
- Mood: nothing new to look at. The row keeps its surface, height, radius,
  font size (18 pt), caret (2 × 22 pt accent) and the two grey icons. It
  simply starts behaving like a one-line text field.

## 1. Rendering: one shaped line + an overlaid caret (CHANGE)
Today the row draws `before | caret | after` as two separate texts with a
2 pt caret between them. That splits an RTL word in two reversed halves
when the cursor is inside it, and makes text reflow as the cursor moves,
which would make dragging jitter. New, the same way KeyboardQueryControl
(the search field) and UITextField draw:
- Line = the cursor's line from the context the app exposes: text after the
  last newline in `before` + text up to the first newline in `after`.
  Shaped as ONE CTLine with the per-character fonts
  (`KeyboardTextPreviewLayout.attributedText`), `.byClipping` (as the
  search field). Base writing direction = the line's first strong
  character (natural, as a UITextField does); no strong character → LTR.
  LTR-base lines are left-aligned in the text area; RTL-base lines (the
  line starts with Hebrew/Arabic) are right-aligned, and every left/right
  rule in §2–§4 is mirrored for them. (Rev. 2, Pluso msg440 findings: the
  old forced-LTR + split rendering reordered Hebrew per half.)
- Caret: 2 × 22 pt, `KeyboardPalette.accent`, corner radius 1, overlaid
  (takes no width) at `CTLineGetOffsetForStringIndex(line, utf16(beforeLine))`
  primary offset, minus 1 pt so it centers on the boundary. Vertically
  centered in the row. Blinks while idle — see §1a (rev. 3; was "no
  blink").
- Context read: up to 96 characters before and 96 after
  (was `suffix(48)` / `prefix(24)`), so both sides can fill the row
  after the cursor moves left. Only the cursor's line is drawn.
- Hidden text markers: when text the app has exposed lies beyond the left
  or right edge of the text area (same line, or another line), that edge
  shows "…". Never guess: apps expose only ~50–80 characters before the
  cursor and stop the after-text at the end of the sentence or line, so
  more may exist with no "…"; it appears as the cursor moves there. "…" (18 pt
  system, `.secondaryLabel`) on an 18 pt-wide cap filled with the row's
  surface color, so part-glyphs never show through. (1.3.0 limit, rev. 4:
  when two overhanging italic glyphs overlap across the cut, a stub of up
  to 2 pt may remain; removing it needs a slanted clip, deferred.) Whole characters only
  count as "visible" (see §7).
- Text area = row width − 10 pt leading padding − 88 pt icons (unchanged).


### 1a. Caret blink (rev. 3, user msg483, Ato msg484)
Like UITextField's insertion point, so the row reads as live text:
- Cycle 1.0 s, repeating: fully visible 0.5 s → fade out 0.1 s → hidden
  0.3 s → fade in 0.1 s (opacity 1 ↔ 0, easeInOut). Only the caret's
  opacity animates: it is an overlay, so the shaped line is never redrawn
  for the blink.
- Solid (opacity 1, no animation) while anything is happening, and for
  0.5 s after the last of: finger down in the preview, dragging,
  edge-stepping, a key press (typing, delete, return, space, emoji/character
  insert), a VoiceOver move, or any context change from the app (the
  cursor moved, text changed). The blink then restarts from "fully
  visible", so the caret never disappears right after a tap or keystroke.
- Blinks only while the preview is live: keyboard visible and no Copy Image
  or Inspect panel open. Stop the animation (caret solid, nothing running)
  when the keyboard disappears or a panel opens; restart on return.
- Prefer Non-Blinking Cursor (Settings › Accessibility › Motion; iOS 18+
  `AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator`, observe
  its change notification): caret always solid. iOS 17 has no such setting:
  blink. Reduce Motion on: same timing but hard on/off (no 0.1 s fades).
- Not blinking anywhere else: the Inspect sample's caret stays solid (it is a
  frozen snapshot, not the live cursor), and Copy Image pictures never
  contain a caret (unchanged).
- Accessibility: the blink is decorative; the element's label, value and
  announcements don't change. Colour, size and contrast unchanged.
- Tests: a UI-test launch argument may freeze the caret visible so
  screenshots are deterministic; check 14 runs without it.

## 2. Where the line sits (horizontal scroll)
Let W = text area width, m = 24 pt edge margin, c = 18 pt cap width.
Margin lines (rev. 4): on a side that shows a "…" cap, m inside the cap's
inner edge, so c + m = 42 pt from the text area edge (L = 42, R = W − 42).
On a side with no cap the limit is the edge itself (L = 1, R = W − 1).
Why: measured from the text area edge, the 18 pt cap left 6 pt before the
caret, never a whole letter, so a drag ended at "…|fox" with no context.
- Line fits in W: left-aligned at x 0, never scrolls.
- Line wider than W: the line keeps its current x; it scrolls only as much
  as needed to keep the cursor inside [L, R]. On a side with no more
  text the limit is the edge itself (cursor may reach x 1 or W − 1).
  Never scroll more than that, never re-center.
- Typing at the end: the cursor walks right to R (W − 1 when nothing
  follows), then the text slides left by each new character's width —
  the same feel as today.
- The app changed the cursor or text itself (the user tapped in the app,
  switched fields, the keyboard appeared, undo, autocorrect by the app):
  reset to today's placement — as much text before the cursor as fits,
  cursor at min(width(before), W − min(width(after), width("…"))).
  The keyboard's own typing, deleting and preview moves never reset.

## 3. Tap — place the cursor
- Touch-up with < 10 pt movement inside the text area: move the cursor to
  the character boundary nearest the touch x, using the search field's
  bidi-aware hit test (`CTLineGetStringIndexForPosition` + nearest
  grapheme boundary, `KeyboardQueryPolicy.nearestVisualBoundary`). Never
  inside a grapheme cluster (emoji ZWJ sequences, base + marks, Hangul).
- Tap past the visual end of the drawn text → the boundary at that visual
  end (in an LTR line: after the last exposed character on the right; in
  an RTL line: mirrored). That is the end of what the app has exposed, which
  may be mid-line; after the move the app exposes more and the line grows.
- Bidi (Hebrew, Arabic, mixed): the tap is hit-tested on the preview's own
  laid-out line, giving a LOGICAL (reading-order) position; the move sent
  to the app is the logical difference between that position and the
  cursor's, never a visual distance. At a direction boundary (two possible
  caret spots) choose the index whose primary caret x is nearest the tap.
  Hebrew is stored in reading order, not backwards (Ato msg442).
- Every target lies inside the text the app exposed, so a move can never
  overshoot (apps silently ignore overshoots).
- Tap on a "…" cap → the boundary at that edge of the visible text; then
  §2 scrolls the line so the cursor sits on the margin line (42 pt from
  that edge) to reveal more, animated 0.15 s
  easeOut (no animation with Reduce Motion).
- The text does not move under a tap that lands inside [L, R].

## 4. Drag — slide the cursor
- A pan that starts in the text area and moves ≥ 10 pt (same recognizers
  as the search field: tap requires the pan to fail, 1 touch).
- The cursor follows the finger: on every change it goes to the boundary
  nearest the finger x (absolute, like a text field and the search field).
  The line does not move while the finger is inside [L, R].
- Edge zone (rev. 4): from the text area edge to the margin line on a
  capped side (42 pt, cap included), or within m (24 pt) of the edge on an
  uncapped side. Matching the zone to the margin line keeps the caret from
  jumping back as the line scrolls.
- Edge auto-scroll: while the finger is in the edge zone and more exposed
  text exists that way on this line, the cursor steps one character (grapheme) every
  80 ms in reading order toward that side (LTR line: left edge = previous,
  right edge = next; RTL line mirrored). Inside an embedded run of the other
  direction the caret may step visually the "wrong" way for a few
  characters; that is how the app itself moves and is accepted. The line
  scrolls so the cursor stays on the margin line; after 1.0 s of continuous
  stepping, every 40 ms (never faster than the app confirms, §4 host
  updates). Stops when the finger leaves the edge zone, at the
  start or end of the line (never crosses a newline), or when the app
  exposes no more text.
- Release: nothing else happens. No snap, no re-centering, no menu.
- Visual: caret unchanged while dragging. No haptics (iOS's own cursor
  drag and the search field have none). The app's own cursor moves live
  above the keyboard — that is the confirmation your finger doesn't cover.
- Host updates: the preview caret moves at once; the app gets one move at
  a time — the next is sent only after the app confirms the previous one
  (its text-change callback) or 100 ms pass, always computed from the
  confirmed context, coalesced to the latest finger target. The final
  position is always sent on release. On release it re-reads the context
  after confirmation and again 300 ms later, and shows where the cursor
  really is. If the app put it elsewhere or ignored the move, the preview
  simply shows the real position — no message, and never a cursor the app
  doesn't have.
- How the app counts (UTF-16 units vs whole characters, e.g. Safari) is
  learned only from a move the user asked for (Ato msg442): never on focus,
  keyboard appearance or while typing. During that move the preview caret
  stays on the user's target (no flicker back and forth). If the check
  shows the app landed elsewhere, at most ONE correction to the nearest
  whole character it can confirm; if it can't confirm, stop and show the
  real position. Never leave the app's cursor inside an emoji or accent
  cluster, and never block typing. The result is remembered per field.

## 5. Typing protection
The row sits directly above the number row; a stray hit must never move
the cursor mid-word.
- The text area ignores a touch that begins within 300 ms after the last
  key touch-up, or while any key is held down.
- Hit area = exactly the text area (W × row height); not extended below the
  row into the gap above the keys. The two icon targets are unchanged.
- Disabled while the Inspect or Copy Image panel is open (they cover it).
  Works the same while Unicode search is open (the row shows above the
  search field there): it moves the app's cursor, never the search
  field's cursor, which keeps its own tap/drag.

## 6. Not possible, by design (say nothing in the UI)
- No selection: double-tap and long-press do nothing extra (a press that
  then moves is a drag; a press that doesn't is a tap on release).
- No edit menu, no loupe.
- Other lines: reached by tapping in the app; the preview stays on the
  cursor's line.
- Text the app doesn't share (empty context, secure fields): the row shows
  what it shows today and taps do nothing.
- If the app has text selected (non-empty selectedText): taps, drags,
  edge-stepping and the VoiceOver adjustable actions do nothing, and the
  row looks as it does today. Reason (Pluso msg440): apps disagree — one
  collapses the selection, another keeps it and the next key replaces it —
  so a stray tap must never set up a replace. The user taps in the app to
  clear the selection; the preview works again at once.
- Text beyond what the app exposes (~50–80 characters before the cursor,
  after-text to the end of the sentence or line): unreachable in one tap.
  Edge-stepping walks there, since each step exposes more.

## 7. Copy Image and Inspect keep "exactly what is drawn"
- The frozen excerpt = the characters fully visible between the left and
  right edges (or caps), split at the cursor into before/after, with the
  same truncation flags as today ("…" shown ⇒ truncated on that side).
- Copy Image picture = the same single shaped line (no 2 pt gap at the
  cursor any more; the picture never contained a caret). For text without
  RTL characters the picture is otherwise unchanged.
- Inspect sample (§3a there) draws the same single line with the overlaid
  caret.

## 8. Accessibility
- The preview text element becomes adjustable, like the search field:
  label "Text preview"; value = the line's text; traits adjustable;
  hint "Tap or drag in the text to move the cursor. Swipe up or down to
  move by one character."
- Swipe up = next character (logical order), swipe down = previous.
  Custom actions: "Move to beginning of line", "Move to end of line".
  These may need several moves when the line is longer than what the app
  exposes: move by the exposed text, wait for confirmation, repeat until a
  newline or the start/end; stop on any unconfirmed move. Unavailable while
  the app has a selection (§6).
- Announce after each move: "Beginning of line", "End of line", or
  "Cursor after {character}" (character as VoiceOver speaks it).
  @naming confirms these strings.
- Contrast unchanged (caret accent on the key surface ≥ 3:1). Dynamic
  Type: row text stays 18 pt as today.

## 9. Acceptance checks (screenshots or a short video)
1. "Café בּרא 👩‍💻": tap between ר and א → the Hebrew word stays intact
   and the caret sits on that boundary; the app's cursor is there too.
2. Tap inside 👩‍💻 or after é (e + U+0301) → caret lands before/after the
   whole cluster, never inside it.
3. A line longer than the row: tap mid-line → nothing slides; drag to the
   left edge and hold → steady stepping, then faster after 1 s; release →
   no jump, and whole letters fill the 24 pt between "…" and the caret.
4. Type at the end of a long line → caret stops 24 pt inside the right
   "…" cap (42 pt from the text area edge) only when text follows, else
   at the edge; text slides left.
5. Type quickly on the number row → no cursor moves from the preview.
6. Tap in the app's text elsewhere → preview resets to "as much before
   text as fits".
7. VoiceOver: swipe up/down moves one character and announces it.
8. Copy Image after a mid-line tap → the picture equals the visible text.
9. Same as 1 and 2 in a Safari text area and in a Notes-style text view:
   caret lands on the same whole-character boundary in both; no split emoji
   (no "?" boxes) after typing there.
10. "שלום abc": the line is right-aligned; tap between ל and ו → the app's
    cursor is between them (reading order), typed text appears there.
11. Select a word in the app, then tap/drag in the preview → nothing moves,
    nothing replaced; deselect in the app → tapping works again.
12. Focus a field and type for 10 s without touching the preview → the
    app's cursor never moves on its own.
13. Long line whose after-text the app cuts at a sentence end: tap past the
    end → cursor at the last exposed character; more text then appears.
14. Blink: leave the keyboard idle for 2 s → caret blinks (1.0 s cycle,
    0.5 s visible). Drag in the preview or type → caret solid throughout and
    for 0.5 s after, then blinking resumes from visible. Open Copy Image or
    Inspect → no blinking behind or inside the panel; the copied picture has
    no caret. Turn on Prefer Non-Blinking Cursor (iOS 18+) → caret stays
    solid without reopening the keyboard.
