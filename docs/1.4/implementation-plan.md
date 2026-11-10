# Uniboard 1.4 — implementation plan (Pluso)

Contract: docs/1.4/brief.md (Ato, authoritative), design/browse-keyboard-1.4/design.md (Colo rev 2),
docs/1.4/browsing-keyboard-1.4-copy.md + docs/1.4/browsing-keyboard-1.4-copy-addendum.md (Camo; addendum wins),
design/styles-grid-1.4/design.md (Colo, font grid) + docs/styles-grid-1.4-copy.md (Camo).
Audit with file:line facts: docs/1.4/audit.md.

Font decision (brief): option B pinned gstatic instances; NO automatic removal/replacement of single downloads
when a shared file is added (ignore styles-grid design §8 replacement text; never ship it); keep 16-file cap.

## Work streams (one subagent each, shared worktree — stay inside your files)
| Stream | Owns | Must not edit |
|---|---|---|
| browse14 | Emoji categories (app + keyboard emoji grid/search), emoji size, block sort, block detail/Explore navigator order, configuration keys for these | Main Keyboard editor, KeyboardAlphabet, font files |
| mainkbd14 | Main Keyboard ABC/123/#+= merge, Symbol Keys row removal, per-key restore, Find a key, Restore All in ⋯, read-error copy | Emoji/Blocks, keyboard emoji code, font files |
| fonts14 | Google font catalog schema 2 + generator instances, download coordinator, StyleGrid width columns, FontFaceDetailView/StyleGridView | everything else |
| scripts14 (later) | Armenian/Hebrew/Arabic layouts, caseless Shift removal, per-key ids for caseless keys | starts after mainkbd14 lands the canvas |

Shared files touched by more than one stream (KeyboardViewController.swift, project.pbxproj, ConfigurationCodec.swift):
make small, local edits; re-read the file right before editing; never reformat or revert others' hunks.

## Machine rules
- One runtest/runbuild at a time across all streams: always run them as
  `flock /tmp/uniboard-runner.lock runtest ...` / `flock /tmp/uniboard-runner.lock runbuild ...` (background bash; 30-min cap).
- Simulator (shared iPhone 18 Pro preview): wrap capture sessions in `flock /tmp/uniboard-sim.lock sh -c '...'` or keep them short.
  Never touch the iPhone 18 Pro Max simulator.
- Tests: `runtest --script core` (swift package, 100% coverage gate on listed files) and
  `runtest --script app --additional-options "-only-testing:UniboardTests/<Class>"` or a single UI test with
  `UNIBOARD_KEYBOARD_INTEGRATION=1 -only-testing:UniboardUITests/<Class>/<test>`. Never the full UI suite.
- No git commits, no pushes. Never touch .airbuild/.
- Copy simulator screenshots to a new .jpg name before reading them. Shell is BusyBox.
