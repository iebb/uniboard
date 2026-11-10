# Explicit rows UI/renderer integration (1.4)

## Geometry and representation

`Shared/ExplicitKeyboardRow.swift` is the full-width SwiftUI `Layout` shared by the app editors and the real keyboard's **explicit** rows. `ExplicitRowGeometry.origins` in `Shared/EditorReorder.swift` is the platform-independent placement calculation: unchanged cell widths, minimum existing spacing, physical Left/Right independent of RTL, centered Center and Spread singletons, spare width between *all* cells for Spread. Only origins are rounded to the environment display scale; widths are not. Page key width remains `SymbolPageLayout.keyWidth`, main key width remains `MainKeyboardArrangement.keyWidth`; half-gap/function sizing uses the corresponding existing width helpers. Trailing explicit gaps are included, not passed through the legacy fitter.

Editor canvas width is the entire well inner width (screen minus 16-point outer and 8-point inner side padding). End-row drag targets are overlays, never layout children. The selected-row band spans that width and hides while dragging. Reduce Motion uses the existing editor animation policy.

`Keyboard/KeyboardViewController.swift` leaves legacy page/stock/custom row drawing branches intact. Only explicit page rows use the new layout. Only explicit **letters** bypass wide-iPad/ANSI projections; 123/#+= remain fixed. Explicit main rows determine row count on wide iPad too. Keyboard font/input/action guards and Favorites dynamic content are unchanged.

## Editing/store APIs

`RowAlignmentCard` is shared by both editors. No selection means All Rows; selected key or gap means Row n. Optional picker selection represents Mixed without a fifth segment. The four image segments have stable `arrange.alignment.left|center|right|spread` identifiers and spoken names. Page alignment saves one complete row array through `SymbolBoardStore.setExplicitRows`; main alignment saves one `MainKeyboardArrangement(rows:)` through `KeyboardKeyPreferences.saveArrangement`. Failure leaves the old value; no tap-selection conversion occurs. Standard Layout/Restore All still reset to nil/default legacy arrangements.

`ExplicitRowEditing` performs operations directly on nested rows. Split copies source alignment; join keeps upper alignment; moving the final cell removes only its source row, preserving every other row's alignment. Main optional function/digit insertion uses nested rows too. Capacity is 12 standard-key widths (main functions 1.5, full gap1, half gap0.5). Destination overflow disables buttons and refuses hover (no insertion mark). Existing rows never silently wrap.

Legacy repair follows the core-approved API contract: any remaining overlong row keeps the whole arrangement legacy; successful shorten/split edits use the old setter while >12 remains, and convert only once every row fits. Alignment controls are disabled until repair is complete. Keyboard appearance stays legacy during intermediate repair. Width warnings use final Camo wording, localized row lists, and `Row too wide` VoiceOver suffixes. New explicit formats never contain >12-unit rows.

Favorites never receives explicit rows, add actions or alignment controls. Its reordering still uses the existing template/stability helper and keyMove store path. When Favorites owns ★ its switch is on and disabled; otherwise it is off/enabled to reclaim ★. Its footer is Favorites-specific.

## Symbols redesign and copy

Static-page helper; two full-width add actions in one card; one-line titles through AX2, up to two at AX3+; existing action identifiers/sheets retained. Matching 52-point-minimum rows, title-inset separator, full-page footer, empty well, separate ★ card/footer. Selected items replace the add/star options with row alignment and key layers (gap selections have no layers). Rows of Ten uses the explicit visible label `Rows of Ten, Align Left` rather than risking a truncated subtitle. Final strings follow `docs/symbols-row-alignment-copy.md` and design rev2.

Measured installed baseline in dark mode: tile RGB(28,27,29), well RGB(28,27,31). Evidence `notes/1.4/rows-ui/baseline-dark.png/.jpg`. The nearly identical colors justify `.systemGray3` for dark editor tiles only; light unchanged. Both editors use `Color.editorKeyTile`.

## Verification/deviations

Focused new tests: `Tests/ExplicitRowGeometryTests.swift`, `UITests/ExplicitRowsUITests.swift`. Explicit row SwiftUI file excluded from Foundation-only Swift Package; existing shared models and editor rule helper remain package members. New app/shared/test/UI files have Xcode memberships; project.yml directory sources naturally include them.

No core-owned model/codec/store files or their tests changed by UI stream. No commits/pushes or .airbuild changes. Build/test/simulator results and unexecuted checks are recorded in `/run/airbuild/team/state/team/developer/notes/1.4/rows-ui-result.md`.

### Runtime evidence update
First green preview build `113b9dff-729f-475f-9c23-e8249abf0ee2` installed/launched iPhone18Pro. Scoped native app102tests/1skip/0fail, all10row tests passed. Initial focused UI automation stalled and was cloud-cancelled at parent request; no UI pass claimed. Manual installed-preview evidence verifies Spread fixed widths/edges, Mixed with no selected segment, split/join, real extension★saved row plus exact ad insertion, ABC-only control exposure, Favorites no add/alignment and disabled-on★after fixture removal. Fresh JPEGs `notes/1.4/rows-ui/NEW-*.jpg` (AX5-diagnostic explicitly pre-fix).
Manual AX5 revealed scroll intrinsic-width overflow and oversized decorative icons. PageArrangeView now constrains scroll content to its existing measured viewport and holds decorative icons20pt in24pt column; focused bounds regression added. Final preview and six-case retry queued. No iPad/VoiceOver/reduce-motion/legacy14 warning screenshot is claimed runtime-verified; pure helper tests cover repair/overflow rules.

## Final measured corrections and verification

The editor ScrollViews require `.frame(maxWidth: .infinity)` before viewport measurement: short centered rows otherwise shrinkwrapped the full editor. At accessibility sizes, four bordered controls also had a445.33pt intrinsic minimum. Both editor `control()` helpers now constrain **only those control buttons** through xxxLarge Dynamic Type. Their AX labels/54pt targets/Large Content Viewer remain; Add/header/helper text still scale fully through AX5. Final installed402pt-screen cards measured x16,width370 at default, AX2 and AX5; AX5 Add rows146.67pt, control edges12…390. Reviewer approved fixes.

Final preview build `bd4d8ba9-2cb3-4377-843e-c8d1ada508d5` launched successfully. Native run `ace97c73-bcd9-4713-9941-2ef2fac9a4c5` passed36/0/0 (11row geometry/edit+25StyleGrid), including persisted-phone→iPad-width JSON roundtrip membership/edge test. Last viewport/control-cap fixes compiled in preview and were manually checked, not rerun as a UI suite. The automated rows shard stalled before completing its first case in app-idle waits, cause unknown; parent-requested cancellation confirmed. **No completed automated rows UI or iPad runtime pass**.

Final actual-keyboard captures establish legacy14+3 retention and equal saved2×2membership under Center/Right:34pt keys, Centerx164.33/203.67; Rightx320.67/360, finaledge394 on402pt screen. MainABC Row3Left actual a startsx8; selected-editor band/card agrees. Final captures inventory and complete test caveats: `/run/airbuild/team/state/team/developer/notes/1.4/rows-ui-result.md`.

Normal Undo restored exact2603-byte pre-capture TOML, independently re-exported/compared. English(US), Light/Large, clipboard and stock Symbols restored. All child tasks ended; simulator released to parent.
