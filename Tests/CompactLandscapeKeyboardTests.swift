import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class CompactLandscapeKeyboardTests: XCTestCase {
    private typealias Arrangement = MainKeyboardArrangement
    private typealias Row = MainKeyboardArrangement.Row
    private let conversionModes: [LanguageInputMode] = [.mandarinPinyin, .japaneseRomaji, .koreanRomaja]

    private func presentation(_ arrangement: Arrangement = .standard(for: .english),
                              mode: LanguageInputMode = .mandarinPinyin,
                              phone: Bool = true, compact: Bool = true, typing: Bool = true) -> KeyboardTypingPresentation {
        .init(arrangement: arrangement, mode: mode, isPhone: phone, isCompactLayout: compact, isTyping: typing)
    }

    func testStockLegacyProjectsToStockLettersWithoutMutatingSavedRepresentation() throws {
        let saved = Arrangement.standard(for: .english)
        let bytes = try JSONEncoder().encode(saved)
        let projected = presentation(saved)
        XCTAssertEqual(projected.arrangement, .letters(for: .english))
        XCTAssertTrue(projected.arrangement.isLegacy)
        XCTAssertEqual(projected.arrangement.typingRowCount, 3)
        XCTAssertEqual(projected.widthBasis, saved)
        XCTAssertEqual(try JSONDecoder().decode(Arrangement.self, from: bytes), saved)
        XCTAssertEqual(saved.typingRowCount, 4)
        for value in [saved, projected.arrangement] {
            let rendering = KeyboardABCRendering(alphabet: .english, arrangement: value,
                availableWidth: 858, isPad: false, isLandscape: false, padLayout: .stock)
            XCTAssertFalse(rendering.arranged, "Stock legacy must keep its stock row renderer")
        }
    }

    func testExplicitProjectionPreservesCellsGapsOrderAndAlignmentExactly() {
        let digits = Row(alignment: .right, cells: [.halfGap, .key("9"), .gap, .key("2"), .halfGap])
        let letters = Row(alignment: .left, cells: [.gap, .key("q"), .key(Arrangement.tab), .halfGap])
        let functions = Row(alignment: .right, cells: [.key(Arrangement.shift), .gap, .key(Arrangement.delete)])
        let saved = Arrangement(rows: [letters, digits, functions])
        let result = presentation(saved).arrangement
        XCTAssertEqual(result.explicitRows, [letters, functions])
        XCTAssertFalse(result.isLegacy)
        XCTAssertEqual(saved.explicitRows, [letters, digits, functions])
        XCTAssertEqual(saved.digitRowKinds, [.none, .digitsOnly, .none])
    }

    func testLegacySubsetAndMovedRowsRetainOriginalSlotsAndTrailingGaps() {
        let saved = Arrangement(keys: ["q", Arrangement.tab, "8", "0", "a", Arrangement.delete],
                                layout: "gkkh/hkgkh/kkg")
        let result = presentation(saved).arrangement
        XCTAssertTrue(result.isLegacy)
        XCTAssertEqual(result.layout, "gkkh/kkg")
        XCTAssertEqual(result.keys, ["q", Arrangement.tab, "a", Arrangement.delete])
        XCTAssertEqual(saved.layout, "gkkh/hkgkh/kkg")
        XCTAssertEqual(saved.digitRowKinds, [.none, .digitsOnly, .none])
    }

    func testEveryPureDigitRowIsRemovedAtAnyPositionAndAnySubset() {
        for digit in Arrangement.digits {
            for position in 0...2 {
                var rows = [Row(cells: [.key("a")]), Row(cells: [.key("b")])]
                rows.insert(Row(cells: [.gap, .key(digit), .halfGap]), at: position)
                let saved = Arrangement(rows: rows)
                XCTAssertEqual(presentation(saved).arrangement.explicitRows,
                               [Row(cells: [.key("a")]), Row(cells: [.key("b")])])
            }
        }
        let saved = Arrangement(rows: [Row(cells: [.key("1")]), Row(cells: [.key("q")]), Row(cells: [.key("9")])])
        XCTAssertEqual(presentation(saved).arrangement.explicitRows, [Row(cells: [.key("q")])])
    }

    func testMixedLettersAndEveryFunctionKeepTheirWholeRowsAndTallerBudget() {
        for extra in ["q"] + Arrangement.functionKeys {
            let mixed = Row(alignment: .right, cells: [.halfGap, .key("1"), .gap, .key(extra), .key("0")])
            let saved = Arrangement(rows: [mixed] + Arrangement.letters(for: .english).resolvedRows)
            let result = presentation(saved)
            XCTAssertEqual(result.arrangement, saved)
            XCTAssertEqual(result.arrangement.typingRowCount, 4)
            XCTAssertEqual(saved.landscapeNumberRowNote, .mixed)
            XCTAssertTrue(result.isCompactConversion, "The shelf remains compact even with no dropped rows")
            XCTAssertFalse(result.allowsMergedSymbols)
        }
    }

    func testNonASCIIDigitsAndEmptyGapOnlyRowsCannotQualify() {
        for keys in [[], ["١"], ["１"], ["1️⃣"], ["12"], [Arrangement.shift]] as [[String]] {
            XCTAssertEqual(Arrangement.DigitRowKind.classify(keys: keys), .none)
        }
        for key in ["١", "１", "1️⃣", "12"] {
            XCTAssertEqual(Arrangement.DigitRowKind.classify(keys: ["1", key]), .mixed)
        }
        let empty = Row(alignment: .right, cells: [])
        let gaps = Row(alignment: .left, cells: [.gap, .halfGap])
        let saved = Arrangement(rows: [empty, Row(cells: [.key("3")]), gaps, Row(cells: [.key("a")])])
        XCTAssertEqual(presentation(saved).arrangement.explicitRows, [empty, gaps, Row(cells: [.key("a")])])
        XCTAssertEqual(Arrangement(keys: ["1", "a"], layout: "k/g/k").hidingPureDigitRows.layout, "g/k")
    }

    func testNoDropReturnsUnchangedValueIncludingLegacyAndInvalidLayouts() {
        let values = [Arrangement.letters(for: .english),
                      Arrangement(keys: ["1", "q"], layout: "hkkg"),
                      Arrangement(keys: ["1"], layout: "invalid"),
                      Arrangement(keys: ["1", "q"], layout: "k"),
                      Arrangement(rows: [Row(alignment: .right, cells: [.key("q"), .gap])])]
        for value in values {
            XCTAssertEqual(value.hidingPureDigitRows, value)
            XCTAssertEqual(value.hidingPureDigitRows.isLegacy, value.isLegacy)
        }
    }

    func testRemovedWidestRowRetainsOriginalKeyWidthsEvenWhenRemainingLettersLookStock() {
        let letters = Arrangement.letters(for: .english)
        let legacy = Arrangement(keys: Arrangement.digits + letters.keys,
                                 layout: "gkkkkkkkkkkg/" + letters.layout)
        let explicit = Arrangement(rows: [Row(cells: [.gap] + Arrangement.digits.map { .key($0) } + [.gap])]
                                  + letters.resolvedRows)
        for saved in [legacy, explicit] {
            let result = presentation(saved)
            for available: CGFloat in [320, 858] {
                let original = Arrangement.keyWidth(for: saved.rows, available: available, spacing: 5)
                let projected = Arrangement.keyWidth(for: result.widthBasis.rows, available: available, spacing: 5)
                let incorrectlyWidened = Arrangement.keyWidth(for: result.arrangement.rows, available: available, spacing: 5)
                XCTAssertEqual(projected, original)
                XCTAssertLessThan(projected, incorrectlyWidened)
                for cell in result.arrangement.rows.flatMap({ $0 }) {
                    XCTAssertEqual(Arrangement.width(of: cell, keyWidth: projected, spacing: 5),
                                   Arrangement.width(of: cell, keyWidth: original, spacing: 5))
                }
            }
            let renderer = KeyboardABCRendering(alphabet: .english, arrangement: result.widthBasis,
                availableWidth: 858, isPad: false, isLandscape: false, padLayout: .stock)
            XCTAssertTrue(renderer.arranged, "Do not switch a custom legacy row renderer to stock after projection")
        }
        XCTAssertEqual(presentation(legacy).arrangement, letters)
    }

    func testModeIdiomCompactAndTypingScopeMatrix() {
        let saved = Arrangement.standard(for: .english)
        for mode in LanguageInputMode.allCases {
            for phone in [false, true] {
                for compact in [false, true] {
                    for typing in [false, true] {
                        let active = phone && compact && typing && conversionModes.contains(mode)
                        let value = presentation(saved, mode: mode, phone: phone, compact: compact, typing: typing)
                        XCTAssertEqual(value.isCompactConversion, active)
                        XCTAssertEqual(value.allowsMergedSymbols, !active)
                        XCTAssertEqual(value.arrangement, active ? .letters(for: .english) : saved)
                        XCTAssertEqual(value.widthBasis, saved)
                    }
                }
            }
        }
    }

    func testFreshMetricsDetermineProjectionBeforeFinalHeightAndReserve44Plus4() {
        let saved = Arrangement.standard(for: .english)
        for mode in conversionModes {
            for composing in [false, true] {
                // Composition content intentionally is not an input to geometry.
                let input = composing ? "ni" : ""
                let fresh = KeyboardLayoutPolicy.metrics(viewWidth: 874, displaySize: CGSize(width: 402, height: 874),
                    sceneHeight: nil, isPad: false, compactVertical: false)
                XCTAssertTrue(fresh.isCompactLayout)
                let value = presentation(saved, mode: mode, compact: fresh.isCompactLayout)
                let baseline = KeyboardLayoutPolicy.metrics(viewWidth: 874, displaySize: CGSize(width: 402, height: 874),
                    sceneHeight: nil, isPad: false, compactVertical: false, keyRows: value.arrangement.typingRowCount)
                let plan = KeyboardCompositionLayoutPolicy.plan(baselineHeight: baseline.height,
                    baselineKeyHeight: baseline.typingKeyHeight, sceneHeight: 402,
                    conversionEnabled: true, surfaceAvailable: true, baselineKeyRows: value.arrangement.typingRowCount,
                    prefersCompactShelf: value.isCompactConversion)
                XCTAssertEqual(plan.shelfHeight, 44, input)
                XCTAssertEqual(plan.compositionChromeHeight, 48)
                XCTAssertEqual(plan.typingKeyHeight, 41.4, accuracy: 0.0001)
                XCTAssertEqual(plan.requestedHeight, baseline.height + 48, accuracy: 0.0001)
                XCTAssertEqual(fresh.height + 78 - plan.requestedHeight, 75.4, accuracy: 0.0001)
                // System-owned bottom band is intentionally not guessed here.
                XCTAssertEqual(plan.requestedHeight, 239.6, accuracy: 0.0001)
            }
        }
    }

    func testMixedAllTenDigitArrangementKeepsCompactShelfAndNormal123ThenRestoresPortraitMerge() throws {
        var saved = Arrangement.standard(for: .english)
        saved.keys.swapAt(10, 20) // Keep four rows and all ten digits; make the first letter row custom.
        var rows = saved.resolvedRows
        let letter = rows[1].cells.removeFirst()
        rows[0].cells.append(letter) // All ten digits plus a letter: never hide this row.
        saved = Arrangement(rows: rows)
        let settings = KeyboardKeySettings.Snapshot(arrangements: ["en": saved])
        XCTAssertTrue(saved.isValid(for: .english))
        let ordinaryMerge = KeyboardMergedSymbolsPolicy.isEligible(settings: settings, alphabet: .english,
            availableWidth: 858, isPad: false, normalKeyHeight: 41.4)
        XCTAssertTrue(ordinaryMerge)
        for mode in conversionModes {
            for compact in [false, true, false] {
                let value = presentation(saved, mode: mode, compact: compact)
                XCTAssertEqual(value.arrangement, saved)
                let merged = value.allowsMergedSymbols && ordinaryMerge
                XCTAssertEqual(merged, !compact)
                XCTAssertEqual(KeyboardMergedSymbolsPolicy.page(.numbers, merged: merged), compact ? .numbers : .symbols)
                if compact {
                    let metrics = KeyboardLayoutPolicy.metrics(viewWidth: 874, displaySize: nil, sceneHeight: nil,
                        isPad: false, compactVertical: true, keyRows: value.arrangement.typingRowCount)
                    let plan = KeyboardCompositionLayoutPolicy.plan(baselineHeight: metrics.height,
                        baselineKeyHeight: metrics.typingKeyHeight, sceneHeight: 402, conversionEnabled: true,
                        surfaceAvailable: true, baselineKeyRows: 4, prefersCompactShelf: value.isCompactConversion)
                    XCTAssertEqual(plan.shelfHeight, 44)
                    XCTAssertEqual(plan.compositionChromeHeight, 48)
                    XCTAssertEqual(plan.requestedHeight, 285, accuracy: 0.0001)
                }
            }
        }
        XCTAssertEqual(settings.arrangement(for: "en"), saved)
    }

    func testSavedDigitTapHoldAndSwipeOverridesRemainSharedWith123AfterProjection() throws {
        let saved = Arrangement.standard(for: .english)
        var overrides: [String: KeyboardKeySettings.Overrides] = [:]
        for digit in Arrangement.digits {
            overrides["digit.\(digit)"] = .init(tap: ["tap-\(digit)"], shiftedTap: ["shift-\(digit)"],
                longPress: ["hold-\(digit)"], swipeUp: ["up-\(digit)"], swipeDown: ["down-\(digit)"])
        }
        let settings = KeyboardKeySettings.Snapshot(overrides: overrides, arrangements: ["en": saved])
        let before = settings
        let value = presentation(settings.effectiveArrangement(for: .english))
        let numbers = try XCTUnwrap(MainKeyboardSymbolLayer(section: .numbers, arrangement: value.arrangement, isPad: false))
        let abc = KeyboardTypingState()
        var digits = abc
        digits.selectLayout(.numbers)
        for digit in Arrangement.digits {
            let id = try XCTUnwrap(KeyboardKeySettings.identifier(forCharacter: digit))
            XCTAssertEqual(id, "digit.\(digit)")
            XCTAssertTrue(numbers.keyIDs.contains(id))
            XCTAssertFalse(value.arrangement.keys.contains(digit))
            for (state, arrangement, auxiliary) in [(abc, saved, true), (digits, value.arrangement, false)] {
                let routed = try XCTUnwrap(KeyboardTypingLayoutPolicy.routedOutput(for: digit, state: state,
                    hasAuxiliaryRow: auxiliary, isAuxiliaryKey: auxiliary, widePad: false, ansiPad: false,
                    padLayout: .stock, arrangement: arrangement, mergedSymbols: false))
                XCTAssertEqual(routed, digit)
                XCTAssertEqual(settings.tapOutput(for: id, defaultText: routed, shifted: false), "tap-\(digit)")
                XCTAssertEqual(settings.tapOutput(for: id, defaultText: routed, shifted: true), "shift-\(digit)")
                let gestures = KeyboardVariantPolicy.gestureCandidates(for: digit, original: routed, state: state, settings: settings)
                XCTAssertEqual(gestures.longPress, ["hold-\(digit)"])
                XCTAssertEqual(gestures.swipeUp, ["up-\(digit)"])
                XCTAssertEqual(gestures.swipeDown, ["down-\(digit)"])
            }
        }
        XCTAssertEqual(settings, before)
        XCTAssertEqual(KeyboardKeySettings.decode(try XCTUnwrap(KeyboardKeySettings.encode(settings))), settings)
        XCTAssertEqual(presentation(saved, compact: false).arrangement, saved)
    }

    func testEditorClassifierPrefersMixedNoteAndOmitsNoteWithoutAnyASCIIDigitRow() {
        XCTAssertEqual(Arrangement.letters(for: .english).landscapeNumberRowNote, .none)
        XCTAssertEqual(Arrangement.standard(for: .english).landscapeNumberRowNote, .digitsOnly)
        XCTAssertEqual(Arrangement(rows: [Row(cells: [.gap, .key("7"), .halfGap])]).landscapeNumberRowNote, .digitsOnly)
        let both = Arrangement(rows: [Row(cells: [.key("1")]), Row(cells: [.key("2"), .key(Arrangement.shift)])])
        XCTAssertEqual(both.landscapeNumberRowNote, .mixed)
        XCTAssertEqual(both.hidingPureDigitRows.explicitRows, [both.resolvedRows[1]])
    }
}

#if os(macOS)
final class CompactLandscapeKeyboardSourceTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func section(_ text: String, from: String, to: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: from))
        let end = try XCTUnwrap(text.range(of: to, range: start.upperBound..<text.endIndex))
        return String(text[start.lowerBound..<end.lowerBound])
    }

    func testFreshGeometryPrecedesProjectedRowCountAndAllConsumersSharePresentation() throws {
        let controller = try source("Keyboard/KeyboardViewController.swift")
        let height = try section(controller, from: "    private func updateKeyboardHeight(", to: "    private func applyKeyboardHeight(")
        let geometry = try XCTUnwrap(height.range(of: "let geometryMetrics = KeyboardLayoutPolicy.metrics("))
        let publish = try XCTUnwrap(height.range(of: "model.updateTypingLayoutContext("))
        let rows = try XCTUnwrap(height.range(of: "let rows = model.typingArrangement.keyRows("))
        let metrics = try XCTUnwrap(height.range(of: "let metrics = KeyboardLayoutPolicy.metrics("))
        XCTAssertLessThan(geometry.lowerBound, publish.lowerBound)
        XCTAssertLessThan(publish.lowerBound, rows.lowerBound)
        XCTAssertLessThan(rows.lowerBound, metrics.lowerBound)
        XCTAssertTrue(height.contains("compact: geometryMetrics.isCompactLayout"))
        XCTAssertTrue(height.contains("model.typingPresentation.isCompactConversion"))
        XCTAssertTrue(height.contains("prefersCompactShelf: prefersCompactShelf"))
        for content in ["language.rawInput", "language.preedit", "language.candidates"] {
            XCTAssertFalse(height.contains(content), "Idle/typing content must never change the row budget")
        }
        XCTAssertTrue(controller.contains("var typingArrangement: MainKeyboardArrangement { typingPresentation.arrangement }"))
        XCTAssertTrue(controller.contains("presentation: model.typingPresentation,"))
        let view = try section(controller, from: "private struct KeyboardTypingView: View {", to: "    private func padRows(")
        XCTAssertTrue(view.contains("private var arrangement: MainKeyboardArrangement { presentation.arrangement }"))
        XCTAssertTrue(view.contains("arrangement: presentation.widthBasis,"))
        XCTAssertTrue(view.contains("MainKeyboardArrangement.keyWidth(for: presentation.widthBasis.rows,"))
        XCTAssertFalse(view.contains("keySettings.effectiveArrangement("))
        XCTAssertTrue(controller.contains("padLayout: padLayout, arrangement: model.typingArrangement, mergedSymbols: model.mergesSymbols)"))
    }

    func testRotationRevokesGesturesButNeverCancelsLanguageOrWritesSettingsOrEditWarnings() throws {
        let controller = try source("Keyboard/KeyboardViewController.swift")
        let context = try section(controller, from: "    func updateTypingLayoutContext(", to: "    func updateTypingGeometry(")
        XCTAssertTrue(context.contains("compactChanged || previous != typingPresentation"))
        XCTAssertTrue(context.contains("invalidateInputMode()"))
        let height = try section(controller, from: "    private func updateKeyboardHeight(", to: "    private func applyKeyboardHeight(")
        for code in [context, height] {
            for forbidden in ["invalidateComposition(", "language.cancel", "language.select", "transitionMessage(", "updatingArrangement(", "save("] {
                XCTAssertFalse(code.contains(forbidden), forbidden)
            }
        }
        let callback = try section(controller, from: "        model.inputModeChanged =", to: "    override func viewWillAppear(")
        XCTAssertTrue(callback.contains("KeyboardVariantButton.cancelInteractions(in: self.view)"))
        XCTAssertFalse(callback.contains("invalidateComposition("))
        XCTAssertTrue(controller.contains("typingPresentation.allowsMergedSymbols"))
        XCTAssertTrue(controller.contains("let layout = KeyboardMergedSymbolsPolicy.page(requested, merged: mergesSymbols)"))
        XCTAssertTrue(controller.contains("letters ? model.typingState.alphabet.lettersKeyTitle : model.mergesSymbols ? \"#+=\" : \"123\""))
    }

    func testRuntimeDigitActionsStillApplySavedOverridesAfterRouting() throws {
        let controller = try source("Keyboard/KeyboardViewController.swift")
        let actions = try section(controller, from: "    private func makeTypingVariantActions(", to: "    private func makeHangulKeyActions(")
        let routing = try XCTUnwrap(actions.range(of: "let original = KeyboardTypingLayoutPolicy.routedOutput("))
        let override = try XCTUnwrap(actions.range(of: "let tapText = settings.tapOutput(for: keyID, defaultText: original,"))
        XCTAssertLessThan(routing.lowerBound, override.lowerBound)
        XCTAssertTrue(actions.contains("KeyboardKeySettings.identifier(forCharacter: key)"))
        XCTAssertTrue(actions.contains("KeyboardVariantPolicy.gestureCandidates(for: key, original: original, state: captured, settings: settings)"))
        XCTAssertTrue(actions.contains("longPressOptions: gestures.longPress, swipeUp: gestures.swipeUp, swipeDown: gestures.swipeDown"))
        XCTAssertTrue(actions.contains("return insertOrdinary(tapText, normal)"))
    }

    func testEditorFootnoteIsIPhoneEnglishLettersOnlyAfterWidthNoteAndUsesExactApprovedCopy() throws {
        let editor = try source("App/MainKeyboardEditorView.swift")
        XCTAssertTrue(editor.contains("if section == .letters {\n            EditorRowWidthNote(rows: wideRows)\n            if UIDevice.current.userInterfaceIdiom == .phone && alphabet.id == KeyboardAlphabet.english.id {\n                landscapeNumberRowNote"))
        let note = try section(editor, from: "    @ViewBuilder private var landscapeNumberRowNote:", to: "    /// Switches section,")
        XCTAssertTrue(note.contains("switch arrangement.landscapeNumberRowNote"))
        XCTAssertTrue(note.contains("case .none:\n                EmptyView()"))
        XCTAssertTrue(note.contains(".font(.footnote).foregroundStyle(.secondary)"))
        let copy = try source("docs/copy-1.5/landscape-number-row-note.md")
        for text in [
            "In landscape on iPhone, Mandarin and Japanese hide the number row so you can see what you're typing. Use the 123 key for digits there. Your arrangement doesn't change.",
            "In landscape on iPhone, Mandarin and Japanese hide the number row only when it holds nothing but digits. Your number row has other keys, so it stays, and there's less room to see your text."
        ] {
            XCTAssertTrue(note.contains("Text(\"\(text)\")"))
            XCTAssertTrue(copy.contains(text))
        }
        XCTAssertFalse(note.contains("Romaja"))
    }
}
#endif
