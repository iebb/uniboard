# Uniboard — Keyboard customization drag design

23 Oct 2026 · User174, product180 · Focused addendum to existing design/design.md. No font feature changes, new navigation, or editing-rule changes.

## Direction and scope
Native, precise, quiet. Lift the key itself, clearly mark the insertion location, and settle once on drop. Do not redesign the keyboard or add live rearranging on hover: fixed destinations make short dense rows easier to aim at and avoid mutating saved state mid-drag.

Applies to MainKeyboardEditorView, PageArrangeView (keys and existing draggable gaps), and KeyLayersPanel choice chips. Preserve non-draggable number row, tap layer and any currently non-draggable main-keyboard gaps. Preserve all validation, key limits, row rules, existing Move Left/Right/Up/Down actions, saved layouts and favorites. Choice list native List.onMove keeps native reorder behavior.

## Current implementation observed
MainKeyboardEditorView.swift and PageArrangeView.swift construct plain Text(...).font(.title2).padding(8) previews instead of keycaps. The main keyboard preview also uses the underlying key rather than the customized displayed output. No targeted-state styling exists. KeyLayersPanel uses padded chips, without consistent target feedback. This is a source inspection, not a claim of recorded simulator behavior.

## Exact shared styling
- Use existing dynamic system semantic colors: canvas tertiarySystemFill, key secondarySystemGroupedBackground, text label, secondary text secondaryLabel; function key uses existing Color.functionKey. One accent: existing system blue/tint, standard light #007AFF and dark #0A84FF. Do not recolor keys or introduce gradients.
- Retain keyboard key height44, exact computed source width (including function/gap width), radius7 continuous, key text22 regular, function SF Symbols18 medium. Existing canvas radius12, padding8, key horizontal gaps5, vertical gaps6, outer margins16 remain unchanged.
- Lifted preview uses SAME displayed glyph, symbolKeyPreview transformation, custom output, typeface, truncation/scale policy, fill, width, height and radius as source. Do not substitute raw key ID or text-only labels. Shift/delete/tab/caps use current SF Symbols. Gap previews retain their dashed border and existing label, not a solid fake key.
- Preview scale1.06 around center; shadow black18%, blur10, x0,y6; optional shadow padding12 outside its visible boundary must not change logical key size/hit testing. Native system lift provides movement/anchoring: do not add a second follower or arbitrary finger offset. If native lift adds elevation/scale already, avoid stacking a second scale/shadow; visual maximum target is1.06.
- Source remains in its original slot at opacity0.35 while an active drag is recognized. It is not removed, duplicated in the layout, or replaced with a zero-width item. The selected border is suppressed on source during dragging; selected state is restored/follows the moved identity when done. Floating preview stays opacity1.
- Valid insertion indicator:2pt vertical tint line, height40 for keyboard keys (2pt inset from44pt); round4pt endpoints at top/bottom. Position in the inter-key gap immediately BEFORE hovered target, consistent with existing drop semantics. Row-end target draws after last item. Draw as overlay, never consume row width. At row start use inset0 inside canvas, avoiding clipping. For choice chips: line height30, same stroke/endpoints.
- No full-target fill that implies replacement/swap. Existing selected border stays distinguishable from insertion line. Invalid destination has NO insertion line and native forbidden cursor/feedback where supported; do not add red flashes or error alerts while hovering.
- Layer-chip preview retains existing30pt minimum width,34pt height,20pt label, radius6 and existing dynamic fill. Lift same1.06 scale/shadow. Empty eligible row shows one insertion line in the existing content area after the layer icon; keep existing Off text until commit, not a fabricated chip.

## Motion and state machine
1. Idle: current editor unchanged; no perpetual animations or instructional overlays.
2. Lift: retain platform long-press recognition; no new immediate drag gesture that steals taps/scrolling. Source fade to0.35 over120ms easeOut. Preview elevation/scale120ms easeOut when not provided by system. Snapshot item identity and original layout in memory.
3. Travel: native preview follows pointer without custom smoothing or lag. Destination insertion line fades in80ms; updates instantly when target changes. Do not slide the line across intervening keys. Target must be validated before the indicator appears.
4. Hover: layout/order unchanged. Only ephemeral drag ID/target and preview state change. No persistence, saves, cloud work or preview-induced writes. Keep other editor controls from changing the layout while a drag is active.
5. Successful drop: validate latest snapshot and destination, compute resulting arrangement once, persist once through existing store. Animate changed key positions using spring response0.24s,dampingFraction0.90,blendDuration0; no visible bounce beyond2pt. Preview lands/disappears with native drop transition, and source opacity returns1; never show two fully opaque copies of the key at rest. Selection follows moved item rather than an obsolete row/index. Remove insertion line within80ms.
6. Self-drop/no-op: no save and no error; source restores over120ms.
7. Cancel/outside/unsupported/malformed drop, destination disappearing, layout picker change, backgrounding/navigation dismissal: clear ephemeral target and source dimming; native return-to-source then opacity120ms. Persisted layout remains byte-for-byte unchanged. Return/cancel animation maximum200ms if app owns it. No stale placeholder after returning to editor.
8. Save failure: restore original arrangement/selection, remove preview/line, show existing inline save error. Do not show a successful reorder followed by silently keeping it. Retry remains the user's normal subsequent move; no new modal is needed.

Reduce Motion: no app-added scaling, bounce or positional spring; update layout immediately at commit, use100ms opacity transitions only. Respect native platform drag motion rather than replacing its tracking. No haptics required by this scope; never repeat feedback on every pointer update.

## Stable identity and correctness requirements for engineering
- Current row/index ForEach IDs describe positions, not moving items; ensure animated tiles track stable item identity so the glyph itself moves instead of morphing into its neighbor. Stable unique identities are essential for duplicate symbols and gaps; do not use displayed text as identity.
- Keep source position plus stable ID and local-session origin. Current String row/index payloads must not accept arbitrary cross-editor/external text that could move an unrelated key. Validate source exists and belongs to this editor/session before showing a target or committing.
- Keep insertion-before-target semantics and existing index adjustment for moves within a row. Do not accidentally implement swap. Append only where existing row-end destination supports it; do not introduce extra rows or new allowed moves.
- Layer drag preserves existing duplicate prevention, tap-layer exclusion and maximum counts. No hover mutation. A rejected duplicate target shows no valid indicator and leaves both rows unchanged.
- Preview shares the key renderer but never recursively attaches drag/drop/buttons to itself. Preserve existing app labels and state; delegate API implementation choices to developer.

## Accessibility and appearance
Keep native keyboard style in light/dark. Lifted key must remain opaque enough for readable text. Semantic tint/label must adapt to Increase Contrast; destination is spatial line+endpoints, not color alone. Preserve source accessibility label and selected traits. Existing non-drag movement buttons are the VoiceOver/Switch Control alternative and remain enabled according to existing move validation. Do not announce every hover. After successful alternative move, announce item and destination row/place once; cancellation is not an error. At large text sizes keep keyboard's intrinsic key metrics but allow surrounding labels/controls to wrap; do not widen the canvas offscreen. No new settings, account flow or screen is introduced.

## Acceptance checks (developer supplies simulator recording)
1. Move a customized-output main key: preview matches on-screen output and cap size, not raw default key.
2. Function-key drag preserves symbol and special width; number row still cannot drag.
3. Move left/right and across existing rows: final order correct, all item counts/identities preserved, no duplicate/lost keys.
4. Page keys, full/half gaps, row end: indicator predicts insertion accurately, no premature row collapse.
5. Choice within row, between rows, empty row, duplicate rejection and tap exclusion.
6. Cancel after entering a valid target, release outside canvas, background/return: no save, source and selection restored, no lingering dim key.
7. Invalid/external drag and repeated rapid moves safely rejected or committed once; no crash.
8. Save failure reverts actual data and appearance; relaunch confirms only successfully committed order.
9. Dark mode, narrow display, long/multi-scalar custom text, Reduce Motion, VoiceOver movement alternative. Test existing scroll/tap unchanged.
10. Record lift → target → successful drop, and lift → cancel. Still images alone cannot verify timing or cancellation.

## Reference and handoff boundaries
Primary source is the existing Uniboard native keyboard editor, not another app's visual skin. Apple HIG drag-and-drop page: https://developer.apple.com/design/human-interface-guidelines/drag-and-drop . External search/fetch services were unavailable, but the Apple page was read successfully in the browser and its reference screenshot is attached. Its guidance supports clear destination insertion feedback, alternative move controls, failed-drop return feedback and selection continuity. Native neutral surfaces/system type remain Uniboard's own palette; the Apple page's orange editorial illustration is not an app color reference. The exact motion values above are design decisions, not Apple mandates.

Storyboard is illustrative and does not prove native animation performance. Engineer owns implementation/build/testing. This document is sufficient to begin without waiting for the font-fix work.
