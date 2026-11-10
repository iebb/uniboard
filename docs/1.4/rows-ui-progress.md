# Rows UI progress / coordination

UI stream active. Read required skills/spec/API, existing editors and drag helper. Final copy already present in `docs/symbols-row-alignment-copy.md`; using it.

## API request for rows-core / parent

- UI will edit `Shared/EditorReorder.swift` (existing shared membership) to add explicit-row move helpers + shared pixel geometry. Existing legacy helpers remain for Favorites/legacy tests.
- Core currently validates explicit units against legacy 16 and counts main functions as 1. Need new 12 weighted units and gradual legacy repair solution. If legacy row14 → move1 leaves13, cannot save that as invalid explicit. Proposed core representation: keep legacy while any overlong rows remain; UI saves legacy slot updates (appearance preserved), converts only when all rows fit. This means alignment changes on an overlong layout must be refused until repaired (otherwise no valid representation). Please confirm/provide if different.
- Need `add` and remove/layer edits on static legacy pages to convert only on successful deliberate edit; static explicit additions use capacity12 and inherit last alignment. Core owns these store paths.

No core-owned files edited. No build/test launched yet.

## First build diagnostic — parent action needed
Build `898e78a7-de3e-4efe-b9f6-8bfa729acff6` failed before UI diagnostics on unrelated existing `App/StyleGridView.swift:638:51`: `Expected '{' to start setter definition`. I have NOT edited/reverted that file. Parent please repair/coordinate that existing font-stream syntax, then tell UI to rerun.

Implemented so far: full-width Symbols add/star/empty cards with final copy, shared alignment card, physical shared SwiftUI row layout + pixel origins, nested row operations/inheritance/12-unit edit refusal with gradual legacy repair, explicit ABC/page keyboard rendering and explicit-only iPad projection bypass. New focused geometry/edit tests added. No core-owned files changed. Updated new source memberships in project.pbxproj and excluded SwiftUI row from pure core package.

## Reviewer repair paths fixed
UI stream edited only its shared drag helper `Shared/EditorReorder.swift` (not core models). Added legacy-only `EditorReorder.isStable` checks to both explicitPage and explicitMainKeyboard proposals. Intermediate legacy values now refuse moves whose trailing gaps the old fitter would trim; valid explicit trailing gaps remain supported. Page commit additionally requires a successful legacy keyMove/layout pair before saving any legacy move—there is no layout-only fallback. Added two exact reproduction tests to own `ExplicitRowGeometryTests`.

Own core run started: runID `375f012c-a564-4b0a-87b7-e963ff08d1fc`, buildID `c73f6cf5-6069-4255-b414-19033fb6f941`; was queued behind core stream, now waiting for builder. Full final source may require followup focused app test after existing StyleGrid syntax fix. Baseline JPEG conversion/measurement done with ffmpeg (Pillow unavailable); no installed dependency/source snapshots.

Parent fixed unrelated StyleGrid syntax. Queued ONE app-targeted compile/test after existing core slot(s), no new core rerun: `-only-testing:UniboardTests/ExplicitRowGeometryTests -only-testing:UniboardUITests/ExplicitRowsUITests`. Following that result, will fix owned compile/test diagnostics and runbuild once for iPhone18Pro screenshot verification. Current UI test integration method is opt-in and will report skipped if runner does not pass UNIBOARD_KEYBOARD_INTEGRATION=1; manual preview keyboard verification remains planned.

## Completed core result (do not retry from UI)
Run `375f012c-a564-4b0a-87b7-e963ff08d1fc`, build `c73f6cf5-6069-4255-b414-19033fb6f941`: **653 tests, 1 skipped, zero failures**. All then-uploaded 8 ExplicitRowGeometryTests passed; two later reviewer regression tests await newer upload. Recipe exit1 was coverage-only: SymbolBoardStore708/710 lines335,388; SymbolPageLayout348/349 line360; ConfigurationCodec796/798 lines526,558; FontRules322/373 (86.3%). Coverage JSON output not copied due failing gate. Parent/core/font owners should handle their coverage; UI has not queued any further core run.

Parent added focused §7.5 punctuation Hold note task: adding read-only Arabic/Hebrew notes under Hold chips via existing KeyboardPunctuationChoice helpers, independent symbols and VoiceOver names. No runtime saved semantics changed.

§7.5 punctuation explanation is now wired: `MainKeyboardEditorView` passes existing editorNotes(default/saved Hold) into `KeyLayersPanel`; notes render below Hold chips within the card, label caption/secondary + separate FSI/PDI-isolated subheadline/primary symbol, stable `layers.holdNote.arabic|hebrew`, combined Unicode-name spoken label, no tap/drag affordance. Other layer callers default to no notes. Focused UI test covers Arabic/Hebrew default presence and suppression with saved choices. No runtime policy/model changes. `git diff --check` passes.

## Focused app compile blocker #2
Targeted app run `dab919a7-fb43-40b6-b3e2-9c7eecb25cc0`, build `a87377e0-7965-4344-883d-ea806fb7fef2`, failed exit65 BEFORE tests: `App/GoogleFontDownloadCoordinator.swift:34:51: cannot call value of non-function type 'URL'`. Parameter `url` shadows static factory in `isPinned`; owner likely needs `Self.url(commit:...)`. File untouched by UI. Row app/shared/keyboard compilation emitted no errors. Punctuation-note edits were made while this run was queued/in progress and may postdate upload; do not claim their compilation or tests yet. Test binary did not build/run. Please parent/font owner repair then UI can runbuild for actual new screenshots. No repeated core test queued.

Compile-ready forwarded by parent. Resumed ONE `runbuild ... --simulator iphone-18-pro` with both runner/simulator locks (`bg_1229beee`), no core run. Scheme now has UNIBOARD_KEYBOARD_INTEGRATION build-setting environment expansion; subsequent scoped app tests will pass `UNIBOARD_KEYBOARD_INTEGRATION=1` to exercise real keyboard parity, not skip it. Will notify parent immediately upon first successful preview installation.

Resumed runbuild `643ed165-1574-48a3-bc69-4852c41aba8a` failed exit65 on a NEW active font-owner compile blocker: `App/StyleGridView.swift:482:28: escaping closure captures non-escaping parameter 'content'` (glyph preview helper content closure needs escaping if stored by verified preview). No row-source errors. Parent notified immediately; no unrelated-source edits or repeated build queued. Await repair notice before retrying.

## Green preview + scoped native result
Build `113b9dff-729f-475f-9c23-e8249abf0ee2` succeeded, installed and launched on iPhone18Pro; parent notified immediately. Scoped app run `44086543-e29f-4ff7-ada2-64802f77216f` native portion: **102 tests, 1 platform-alias skip, 0 failures**, including all 10 row geometry tests and all requested font classes. Six focused ExplicitRowsUITests now executing, integration opt-in enabled. No additional core/full UI run.
New default/dark/AX2/AX5 Symbols screenshots captured; dark tile contrast looks clear. Manual AX5 found scroll content intrinsic-width overflow (413.33 points on 402-point screen). Constrained scroll content to measured viewport and added bounds assertions; this followup postdates current upload and needs final verification. Initial AX5 evidence is diagnostic, not approved.

Manual actual-keyboard Spread parity PASS: 34pt keys x8/125.33/242.67/360, final394=402−8; a+d inserted exactly ad. Fresh JPEGs under notes/1.4/rows-ui/NEW-real-pageSpread*.jpg. Disposable page deleted; ★ restored to Favorites, English restored. Main ABC versus fixed123/More Symbols and dynamic Favorites verified with fresh screenshots. Initial scoped UI runner stalled after Create; parent requested cloud cancellation, confirmed successful. Native102/1skip/0fail retained; no completed UI case claimed. One already-queued final build and rows-only retry remain, no more queued.

## Final source ready / bounded verification queue
Three final design corrections are present in both editors/shared alignment card: icon-only alignment at accessibility sizes without changing spoken labels or Large Content Viewer behavior; Add decorative icons use the requested scaled 24pt column with title font clamped; helper/footer and row-width explanations use matching 16pt horizontal insets. Parent read-only review reports no concrete high/medium issues.

Added `testSavedPhoneRowsKeepMembershipAndPhysicalEdgesAtIPadWidth`: persisted SymbolBoard JSON roundtrip, identical saved four aligned rows including half gaps, phone386pt/3x and iPad1008pt/2x geometry, physical edges/center and unchanged membership. This substitutes focused geometry coverage for unavailable iPad capture, not an iPad runtime claim.

Queued exactly one final scoped retry (`bg_4bcc1162`) behind parent browser/UI and existing final preview (`bg_48b5853f`): ExplicitRowsUITests + ExplicitRowGeometryTests + native StyleGridTests with keyboard integration enabled and per-test180s timeout. Timeout flags checked in xcodebuild help before queueing. Prior queued bash replaced only while it had no remote run. No additional runner/core/full UI queued. Parent final core independently passed664tests/1skip/0fail with all38gatedfiles at100%; retained as parent-owned evidence. `git diff --check` passes. Refreshed screenshots and final scoped results still pending.

## Final UI handoff — 2026-10-25

Final installed iPhone18Pro preview: build `bd4d8ba9-2cb3-4377-843e-c8d1ada508d5`, run `3b5ef474-3cef-47a8-8e45-6b407b783d9c`, successful. Corrects measured full-width ScrollView/shrinkwrap and AX5 control intrinsic-width defects; control-local xxxLarge Dynamic Type cap only, not global text. Final cards x16,width370 at default/AX2/AX5 on402pt screen; AX5 Add heights146.67 and controls54pt. Parent/Colo approved corrected empty/AX2/AX5/Row2 captures. No further build/UI runner needed.

Scoped native run `ace97c73-bcd9-4713-9941-2ef2fac9a4c5`: **36tests/0skips/0failures** (11 ExplicitRowGeometryTests +25 StyleGridTests). Includes saved-phone-row JSON roundtrip membership/physical edges at iPad width; this is not iPad runtime coverage. Final viewport/control-cap sources compiled in final preview and verified manually; tightened UI assertions were not rerun. UI shard first test remained stuck in animation/event-loop idle without assertions despite180s timeout settings; remote cancelled per parent, runner exit130, **zero completed UI cases**, app-v-runner cause unknown. No automated rows UI pass claimed.

Final screenshot batch includes real legacy14 keyboard; MainABC Row3Left editor+keyboard; identical saved2×2rows Center and Right editor+keyboard; Row2/Mixed; reset menu; clean Favorites; empty; final stock light/dark. All JPEGs in `/run/airbuild/team/state/team/developer/notes/1.4/rows-ui/`, `FINAL-` prefix; full inventory and limitations in sibling `rows-ui-result.md`.

**Exact cleanup verified**: normal Undo restored pre-capture config byte-for-byte (2603UTF8bytes), exported `manual-restored.toml` equals `manual-base.toml`. Fixture pages/Main edits/star changes gone; English(US), Large+Light, cleared clipboard, clean stock Symbols. All UI child tasks terminal/cancel-confirmed; no runner/simlock held. **Simulator ownership released to parent**; no additional UI actions planned. No iPad runtime/screenshot, VoiceOver interaction, Reduce Motion or completed automated rows UI pass claimed.
