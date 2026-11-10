import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class MainKeyboardArrangementTests: XCTestCase {
    typealias Arrangement = MainKeyboardArrangement

    func testStandardRowsStartWithTheNumberRowAndPutShiftAndDeleteAroundTheLastRow() throws {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.standard(for: english)
        XCTAssertTrue(standard.isValid(for: english))
        XCTAssertEqual(standard.layout, "kkkkkkkkkk/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk")
        XCTAssertEqual(Array(standard.keys.prefix(10)), Array("1234567890").map(String.init))
        XCTAssertEqual(standard.typingRowCount, 4)
        XCTAssertEqual(standard.firstLetterRow, 1)
        XCTAssertTrue(standard.missingDigits.isEmpty)
        XCTAssertFalse(standard.isLetterOnly)
        let letters = Arrangement.letters(for: english)
        XCTAssertEqual(letters.layout, "kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk")
        XCTAssertEqual(letters.typingRowCount, 3)
        XCTAssertEqual(letters.firstLetterRow, 0)
        XCTAssertTrue(letters.isLetterOnly)
        XCTAssertEqual(letters.letterRows, standard.letterRows, "The number row is not a row of letters")
        XCTAssertEqual(standard.rows.last?.first, .key(Arrangement.shift))
        XCTAssertEqual(standard.rows.last?.last, .key(Arrangement.delete))
        XCTAssertEqual(standard.letterRows, english.rows)
        XCTAssertEqual(english.arranged(standard.letterRows).rows, english.rows)
        XCTAssertEqual(english.arranged([["q"]]).rows, english.rows, "Anything but all the letters keeps the standard rows")
        XCTAssertEqual(english.arranged(nil).rows, english.rows)
    }

    func testOnlyCompleteArrangementsInThreeRowsAreValid() {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.letters(for: english)
        var tab = standard
        tab.keys.insert(Arrangement.tab, at: 0)
        tab.layout = "k" + tab.layout
        XCTAssertTrue(tab.isValid(for: english))
        var twice = tab
        twice.keys[1] = Arrangement.tab
        XCTAssertFalse(twice.isValid(for: english), "Tab at most once, every letter once")
        var noShift = standard
        noShift.keys[noShift.keys.firstIndex(of: Arrangement.shift)!] = Arrangement.caps
        XCTAssertFalse(noShift.isValid(for: english), "Shift stays")
        // A fifth row is one too many: the number row takes the fourth.
        for layout in ["kkkkkkkkkk/kkkkkkkkk/kkkkkkkk", "kkkkkkkkkk/kkkkkkkkk/kkkk/kkk/kk", "kkkkkkkkkk/kkkkkkkkk/g/kkkkkkkkk", "x"] {
            var bad = standard
            bad.layout = layout
            XCTAssertFalse(bad.isValid(for: english), layout)
        }
        var fourRows = standard
        fourRows.layout = "kkkkkkkkkk/kkkkkkkkk/kkkk/kkkkk"
        XCTAssertTrue(fourRows.isValid(for: english), "Four rows fit, with or without digits")
        var twoRows = standard
        twoRows.layout = "kkkkkkkkkkkkkk/kkkkkkkkkkkkkk"
        XCTAssertTrue(twoRows.isValid(for: english))
        XCTAssertEqual(twoRows.letterRows.count, 3, "Typing always gets three rows")
        XCTAssertTrue(twoRows.letterRows[2].isEmpty)
        var invalid = standard
        invalid.layout = ""
        XCTAssertTrue(invalid.rows.isEmpty)
    }

    func testCaselessLayoutsHaveNoShiftOrCapsLockAndArabicKeepsItsDiacriticsPlace() throws {
        let hebrew = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "he"))
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        let he = Arrangement.standard(for: hebrew), ar = Arrangement.standard(for: arabic)
        XCTAssertEqual(he.layout, "kkkkkkkkkk/kkkkkkkk/kkkkkkkkkk/kkkkkkkkkk", "Row 3: nine letters and Delete")
        XCTAssertFalse(he.keys.contains(Arrangement.shift))
        XCTAssertEqual(he.rows.last?.last, .key(Arrangement.delete))
        XCTAssertEqual(ar.layout, "kkkkkkkkkk/kkkkkkkkkkk/kkkkkkkkkkk/kkkkkkkkkkk", "Row 3: Arabic Diacritics, nine letters and Delete")
        XCTAssertEqual(ar.rows.last?.first, .key(Arrangement.shift))
        XCTAssertEqual(Array(he.keys.prefix(10)), Arrangement.digits, "The stock number row")
        XCTAssertEqual(he.letterRows, hebrew.rows)
        XCTAssertEqual(ar.letterRows, arabic.rows)
        for (alphabet, standard) in [(hebrew, he), (arabic, ar)] {
            XCTAssertTrue(standard.isValid(for: alphabet))
            XCTAssertTrue(Arrangement.letters(for: alphabet).isValid(for: alphabet))
            var caps = standard
            caps.keys.append(Arrangement.caps); caps.layout += "k"
            XCTAssertFalse(caps.isValid(for: alphabet), "No Caps Lock without capitals: \(alphabet.id)")
        }
        var shifted = he
        shifted.keys.insert(Arrangement.shift, at: 28); shifted.layout = "kkkkkkkkkk/kkkkkkkk/kkkkkkkkkk/kkkkkkkkkkk"
        XCTAssertFalse(shifted.isValid(for: hebrew), "Hebrew has no Shift")
        var unshifted = ar
        unshifted.keys.removeAll { $0 == Arrangement.shift }; unshifted.layout = "kkkkkkkkkk/kkkkkkkkkkk/kkkkkkkkkkk/kkkkkkkkkk"
        XCTAssertFalse(unshifted.isValid(for: arabic), "Arabic keeps its Diacritics key")
        // Another layout's arrangement never fits these letters.
        XCTAssertFalse(Arrangement.standard(for: .english).isValid(for: hebrew))
        XCTAssertFalse(he.isValid(for: arabic))
        // A Tab is still allowed, and the number row can move like any other layout's.
        var tab = he
        tab.keys.append(Arrangement.tab); tab.layout += "k"
        XCTAssertTrue(tab.isValid(for: hebrew))
        XCTAssertEqual(he.withStockNumberRow(), he)
    }

    #if os(macOS)
    /// Source integration guard: UIKit itself is not executed by core tests.
    /// Cache-before-set makes unchanged notifications and synchronous setter
    /// reentry no-ops without suppressing real language/layout transitions.
    func testPrimaryLanguageCachesBeforeUIKitSetterAndRetainsModeTransitions() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Keyboard/KeyboardViewController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "    private func applyPrimaryLanguage() {"))
        let end = try XCTUnwrap(source.range(of: "\n    }", range: start.upperBound..<source.endIndex))
        let method = String(source[start.upperBound..<end.lowerBound])
        XCTAssertTrue(source.contains("private var lastAppliedPrimaryLanguage: String?"))
        let guardRange = try XCTUnwrap(method.range(of: "guard lastAppliedPrimaryLanguage != desired else { return }"))
        let cacheRange = try XCTUnwrap(method.range(of: "lastAppliedPrimaryLanguage = desired"))
        let setterRange = try XCTUnwrap(method.range(of: "primaryLanguage = desired"))
        XCTAssertLessThan(guardRange.lowerBound, cacheRange.lowerBound)
        XCTAssertLessThan(cacheRange.lowerBound, setterRange.lowerBound)
        XCTAssertEqual(method.components(separatedBy: "primaryLanguage =").count - 1, 1)
        for mapping in ["case .japaneseRomaji: desired = \"ja-JP\"",
                        "case .mandarinPinyin: desired = \"zh-Hans\"",
                        "case .koreanRomaja, .koreanTwoSetHangul: desired = \"ko-KR\"",
                        "case .direct: desired = alphabet == .english ? \"en-US\" : alphabet.id"] {
            XCTAssertTrue(method.contains(mapping), "Real mode and direct-alphabet transitions remain supported")
        }
    }

    /// Source-level integration protection also runs in UniboardCore, where
    /// the iOS SwiftUI editor itself is intentionally not compiled.
    func testCanvasDiacriticsCapBypassesButtonsDragSurfacesAndAccessibility() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/MainKeyboardEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "        if alphabet.isCaseless && !alphabet.diacritics.isEmpty && cell == .key(Arrangement.shift) {"))
        let end = try XCTUnwrap(source.range(of: "        } else {", range: start.upperBound..<source.endIndex))
        let cap = String(source[start.upperBound..<end.lowerBound])
        XCTAssertTrue(source.contains("alphabet.isCaseless && !alphabet.diacritics.isEmpty"))
        XCTAssertTrue(source.contains("hasDiacriticsPlaceholder && key(at: position) == Arrangement.shift"))
        XCTAssertTrue(cap.contains("functionCap(width: entry.width)"))
        XCTAssertTrue(cap.contains("Text(symbolKeyPreview(alphabet.diacritics[0].mark))"))
        XCTAssertTrue(cap.contains(".font(.system(size: 22))"))
        XCTAssertTrue(cap.contains(".allowsHitTesting(false)"))
        XCTAssertTrue(cap.contains(".accessibilityHidden(true)"))
        for forbidden in ["Button(", "EditorDragSurface(", "tile(", "selection =", "accessibilityLabel("] {
            XCTAssertFalse(cap.contains(forbidden), "Display-only cap must not contain \(forbidden)")
        }
        XCTAssertTrue(source.contains("selection, !isDiacriticsPlaceholder(position)"), "Stale selection must not expose movement controls")
        XCTAssertTrue(source.contains(".fill(Color.functionKey)"), "Reuse the same gray function surface")
    }

    /// Structural integration regression for the retained SwiftUI/drag-host
    /// builders. This fails the former live-index pattern; it is not evidence
    /// that an iOS render/removal sequence has executed without a crash.
    func testCanvasRetainedBuildersRenderCapturedRowsAndCellsAndRejectStaleActions() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/MainKeyboardEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let canvasStart = try XCTUnwrap(source.range(of: "    private var canvas: some View {"))
        let canvasEnd = try XCTUnwrap(source.range(of: "    /// The 123 or #+= page:", range: canvasStart.upperBound..<source.endIndex))
        let canvas = String(source[canvasStart.lowerBound..<canvasEnd.lowerBound])
        let placeStart = try XCTUnwrap(source.range(of: "    @ViewBuilder private func place("))
        let placeEnd = try XCTUnwrap(source.range(of: "    /// A key as the keyboard draws it:", range: placeStart.upperBound..<source.endIndex))
        let place = String(source[placeStart.lowerBound..<placeEnd.lowerBound])
        let symbols = String(source[canvasEnd.lowerBound..<placeStart.lowerBound])

        // One arrangement feeds alignment, cells, geometry, identities and end
        // targets, even when removing 0 makes the live keyboard shrink 4 -> 3.
        for captured in ["let current = keys.snapshot.effectiveArrangement(for: currentAlphabet)",
                         "let fingerprint = Self.fingerprint(current, alphabet: currentAlphabet)",
                         "let resolvedRows = current.resolvedRows", "let rows = resolvedRows.enumerated().map",
                         "let cells = value.cells.enumerated().map", "CanvasCell(id: id, position: position, cell: cell, width: cellWidth)",
                         "CanvasRow(id: row, alignment: value.alignment, cells: cells",
                         "ForEach(rows)", "ExplicitKeyboardRow(alignment: row.alignment", "ForEach(row.cells)",
                         "place(entry, current: current, alphabet: currentAlphabet, fingerprint: fingerprint)",
                         ".matchedGeometryEffect(id: entry.id, in: motion)", "let end = row.end"] {
            XCTAssertTrue(canvas.contains(captured), "Canvas must capture rather than re-resolve: \(captured)")
        }
        XCTAssertTrue(source.contains("var end: Layout.Position { .init(row: id, index: cells.count) }"))
        XCTAssertTrue(canvas.contains("item.key.map { \"key:\" + $0 } ?? drag.tileID(position)"),
                      "Key and tracked-gap animation identities must come from the captured cell")
        for builder in [canvas, place] {
            for forbidden in ["places.rows[", "arrangement.resolvedRows[", "key(at:", "tileIdentity("] {
                XCTAssertFalse(builder.contains(forbidden), "Retained builder cannot re-read live indices: \(forbidden)")
            }
            XCTAssertTrue(builder.contains("fingerprint: fingerprint"))
            XCTAssertTrue(builder.contains("currentFingerprint: { dragFingerprint }"))
            XCTAssertTrue(builder.contains("accepts: { dragFingerprint == fingerprint && Self.canvasMove(current"))
            XCTAssertTrue(builder.contains("commit: { guard dragFingerprint == fingerprint else { return }; drop("))
        }
        XCTAssertTrue(place.contains("let cell = entry.cell"))
        XCTAssertTrue(place.contains("if case .key(let key) = cell"))
        XCTAssertTrue(place.contains("width: entry.width"))
        XCTAssertEqual(place.components(separatedBy: "guard section == .letters, dragFingerprint == fingerprint, !drag.isDragging").count - 1, 2,
                       "Both key and gap taps must refuse an outgoing generation")
        XCTAssertTrue(source.contains("parent.draggable && isEnabled && (parent.currentFingerprint?() ?? parent.fingerprint) == parent.fingerprint"),
                      "An outgoing surface cannot lift a different live item at its former position")
        XCTAssertTrue(source.contains("guard section == .letters, dragFingerprint == fingerprint else { return }"),
                      "Position-based control actions must also refuse an outgoing generation")
        XCTAssertTrue(symbols.contains("ForEach(Array(layer.rows.enumerated()), id: \\.offset)"))
        XCTAssertTrue(symbols.contains("symbolCell(entry.element, width: fixedWidth(of: entry.element) ?? shared,"))
        XCTAssertTrue(symbols.contains("height: layer.canvasKeyHeight, switchTitle: layer.switchKeyTitle,"))
        for forbidden in ["layer.rows[", "cells[index]"] {
            XCTAssertFalse(symbols.contains(forbidden), "Symbol builders also receive captured elements")
        }
    }

    func testCanvasRoutesStockCaselessWidthsAndAllMovesThroughItsLocalGuards() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("App/MainKeyboardEditorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("guard alphabet.isCaseless, current.isLegacy,"))
        XCTAssertTrue(source.contains("current == .standard(for: alphabet) || current == .letters(for: alphabet)"))
        XCTAssertTrue(source.contains("KeyboardTypingLayoutPolicy.caselessKeyWidths(for: alphabet, available: available, spacing: spacing)"))
        XCTAssertTrue(source.contains("caselessWidths?.letter ?? Arrangement.keyWidth("))
        XCTAssertTrue(source.contains("key == Arrangement.shift || key == Arrangement.delete { cellWidth = widths.function }"))
        XCTAssertEqual(source.components(separatedBy: "EditorReorder.explicitMainKeyboard(").count - 1, 1,
                       "Only canvasMove may call the shared membership-only reorder policy")
        for call in ["Self.canvasMove(current, from: $0, to: end", "Self.canvasMove(current, from: $0, to: position",
                     "Self.canvasMove(arrangement, from: source, to: destination"] {
            XCTAssertTrue(source.contains(call), "Hover, arrows and drop must use the fixed-slot guard")
        }
        XCTAssertTrue(source.contains("source == diacriticsPosition(in: current)"))
        XCTAssertTrue(source.contains("return fixed == diacriticsPosition(in: next, ignoringDigitRows: true)"))
        XCTAssertTrue(source.contains("ignoringDigitRows && !cells.isEmpty && cells.allSatisfy"))
        XCTAssertTrue(source.contains("if case .key(let key) = cell { return Arrangement.isDigit(key) }"))
        XCTAssertTrue(source.contains("guard Self.preservesDiacriticsPlace(move.value, in: arrangement, alphabet: alphabet) else { return false }"))
        XCTAssertTrue(source.contains("guard Self.preservesDiacriticsPlace(next, in: arrangement, alphabet: alphabet) else { return }"),
                      "Gap, split, join and removal saves cannot displace the cap indirectly")
    }
    #endif

    #if !canImport(UniboardCore)
    @MainActor func testCanvasFixedSlotRejectsDirectAndIndirectMovesButAllowsOtherLettersAndNumberRow() throws {
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        let current = Arrangement.standard(for: arabic)
        typealias Canvas = MainKeyboardEditorView
        XCTAssertNil(Canvas.canvasMove(current, from: .init(row: 3, index: 0), to: .init(row: 3, index: 2), alphabet: arabic))
        // A different key inserted before the inert cap would push it right.
        XCTAssertNotNil(EditorReorder.explicitMainKeyboard(current, from: .init(row: 3, index: 1), to: .init(row: 3, index: 0), alphabet: arabic))
        XCTAssertNil(Canvas.canvasMove(current, from: .init(row: 3, index: 1), to: .init(row: 3, index: 0), alphabet: arabic))
        XCTAssertNotNil(Canvas.canvasMove(current, from: .init(row: 3, index: 1), to: .init(row: 3, index: 3), alphabet: arabic))
        var shifted = current
        shifted.layout = "kkkkkkkkkk/kkkkkkkkkkk/kkkkkkkkkkk/hkkkkkkkkkkk"
        XCTAssertFalse(Canvas.preservesDiacriticsPlace(shifted, in: current, alphabet: arabic), "A gap cannot push the cap right")
        let letters = Arrangement.letters(for: arabic)
        XCTAssertTrue(Canvas.preservesDiacriticsPlace(letters, in: current, alphabet: arabic),
                      "Removing a digit-only row keeps the cap within the letter canvas")
        XCTAssertTrue(Canvas.preservesDiacriticsPlace(current, in: letters, alphabet: arabic), "Add Number Row remains available")
        let splitRows = try XCTUnwrap(ExplicitRowEditing.applying(.split(.init(row: 0, index: 1)),
            to: letters.resolvedRows, maximumRows: Arrangement.maximumRows, keyUnits: ExplicitRowEditing.mainUnits))
        XCTAssertFalse(Canvas.preservesDiacriticsPlace(ExplicitRowEditing.main(letters, rows: splitRows), in: letters, alphabet: arabic),
                       "An unrelated letter-row split must not shift the cap's row")
        XCTAssertTrue(Canvas.preservesDiacriticsPlace(shifted, in: current, alphabet: .english), "Latin editing is unaffected")
    }

    @MainActor func testCanvasFinalDigitRemovalAndDragCanRemoveTheDigitOnlyRow() throws {
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        var current = Arrangement.standard(for: arabic)
        // Match the actual editor path: remove 1–9, leaving only 0 on top.
        for _ in 1...9 {
            let rows = try XCTUnwrap(ExplicitRowEditing.applying(.remove(.init(row: 0, index: 0)),
                to: current.resolvedRows, maximumRows: Arrangement.maximumRows, keyUnits: ExplicitRowEditing.mainUnits))
            let next = ExplicitRowEditing.main(current, rows: rows)
            XCTAssertTrue(MainKeyboardEditorView.preservesDiacriticsPlace(next, in: current, alphabet: arabic))
            current = next
        }
        XCTAssertEqual(current.rows[0], [.key("0")])
        let rows = try XCTUnwrap(ExplicitRowEditing.applying(.remove(.init(row: 0, index: 0)),
            to: current.resolvedRows, maximumRows: Arrangement.maximumRows, keyUnits: ExplicitRowEditing.mainUnits))
        let removed = ExplicitRowEditing.main(current, rows: rows)
        XCTAssertEqual(removed.rows, Arrangement.letters(for: arabic).rows)
        XCTAssertTrue(MainKeyboardEditorView.preservesDiacriticsPlace(removed, in: current, alphabet: arabic),
                      "Remove 0 must save, not silently reject deletion of the empty number row")
        XCTAssertNotNil(MainKeyboardEditorView.canvasMove(current, from: .init(row: 0, index: 0),
            to: .init(row: 1, index: current.rows[1].count), alphabet: arabic),
                        "Dragging the final digit into a letter row may also remove its empty source row")
        var gapped = current
        gapped.layout = "kh/kkkkkkkkkkk/kkkkkkkkkkk/kkkkkkkkkkk"
        XCTAssertFalse(MainKeyboardEditorView.preservesDiacriticsPlace(removed, in: gapped, alphabet: arabic),
                       "A digit-plus-gap row is not a digit-only row")
    }

    @MainActor func testCanvasCaselessWidthsAreStockLegacyOnlyAndEveryStockRowFits() throws {
        for id in ["ar", "he"] {
            let alphabet = try XCTUnwrap(KeyboardAlphabet.alphabet(id: id))
            for current in [Arrangement.standard(for: alphabet), .letters(for: alphabet)] {
                for spacing: CGFloat in [5, 7] {
                    let widths = try XCTUnwrap(MainKeyboardEditorView.caselessCanvasWidths(for: current, alphabet: alphabet, available: 386, spacing: spacing))
                    XCTAssertEqual(widths.function, widths.letter, accuracy: 0.0001)
                    for row in current.rows {
                        let total = row.reduce(CGFloat(0)) { total, cell in
                            if case .key(let key) = cell, Arrangement.isFunction(key) { return total + widths.function }
                            return total + widths.letter
                        } + spacing * CGFloat(row.count - 1)
                        XCTAssertLessThanOrEqual(total, 386.0001)
                    }
                }
                XCTAssertNil(MainKeyboardEditorView.caselessCanvasWidths(for: Arrangement(rows: current.resolvedRows), alphabet: alphabet, available: 386, spacing: 5))
                var custom = current
                custom.keys.swapAt(0, 1)
                XCTAssertNil(MainKeyboardEditorView.caselessCanvasWidths(for: custom, alphabet: alphabet, available: 386, spacing: 5))
            }
        }
        XCTAssertNil(MainKeyboardEditorView.caselessCanvasWidths(for: .standard(for: .english), alphabet: .english, available: 386, spacing: 5))
    }
    #endif

    func testDigitsAreOrdinaryKeysEachAtMostOnceInAtMostFourRows() throws {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.standard(for: english)
        var twice = standard
        twice.keys[1] = "1"
        XCTAssertFalse(twice.isValid(for: english), "Each digit at most once")
        var five = standard
        five.layout = "kkkkk/kkkkk/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertFalse(five.isValid(for: english), "At most four rows")
        // Some digits gone: still valid, and typing keeps three rows of letters.
        var some = standard
        some.keys.removeFirst(3)
        some.layout = "kkkkkkk/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertTrue(some.isValid(for: english))
        XCTAssertEqual(some.missingDigits, ["1", "2", "3"])
        XCTAssertEqual(some.letterRows, english.rows)
        // Digits among the letters in three rows.
        var mixed = Arrangement.letters(for: english)
        mixed.keys.insert("5", at: 3)
        mixed.layout = "kkkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertTrue(mixed.isValid(for: english))
        XCTAssertEqual(mixed.typingRowCount, 3)
        XCTAssertEqual(mixed.letterRows, english.rows)
        XCTAssertFalse(mixed.isLetterOnly)
        // Four rows of letters type as three: the last two join.
        var split = Arrangement.letters(for: english)
        split.layout = "kkkkk/kkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertTrue(split.isValid(for: english))
        XCTAssertEqual(split.letterRows.count, 3)
        XCTAssertEqual(split.letterRows.flatMap { $0 }, english.rows.flatMap { $0 })
        XCTAssertEqual(split.typingRowCount, 4)
        XCTAssertEqual(split.keyRows(widePad: true), 3, "A wide iPad draws a number row only with digits")
        XCTAssertEqual(standard.keyRows(widePad: true), 4)
        XCTAssertEqual(mixed.keyRows(widePad: true), 4)
        XCTAssertEqual(mixed.keyRows(widePad: false), 3)
    }

    func testGapsAndUnreadableLayoutsCountRowsWithoutLetters() {
        let english = KeyboardAlphabet.english
        // A gap before the letters is not a letter: the first letter row is still found.
        var gapped = Arrangement.letters(for: english)
        gapped.layout = "gkkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertTrue(gapped.isValid(for: english))
        XCTAssertEqual(gapped.firstLetterRow, 0)
        XCTAssertEqual(gapped.rows[0].first, .gap)
        XCTAssertEqual(gapped.letterRows, english.rows, "Gaps are not letters")
        // An unreadable layout still leaves the keyboard three rows tall.
        var unreadable = gapped
        unreadable.layout = "x"
        XCTAssertNil(unreadable.places)
        XCTAssertEqual(unreadable.typingRowCount, 3)
        XCTAssertTrue(unreadable.isLetterOnly)
        XCTAssertNil(unreadable.firstLetterRow)
        XCTAssertNil(unreadable.addingDigits())
    }

    func testAddingDigitsPutsTheNumberRowBackOrAppendsTheMissingOnes() throws {
        let english = KeyboardAlphabet.english
        let letters = Arrangement.letters(for: english)
        XCTAssertEqual(letters.addingDigits(), .standard(for: english), "No digits: the whole number row on top")
        XCTAssertNil(Arrangement.standard(for: english).addingDigits(), "Nothing is missing")
        var some = Arrangement.standard(for: english)
        some.keys.removeAll { $0 == "3" || $0 == "7" }
        some.layout = "kkkkkkkk/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        let added = try XCTUnwrap(some.addingDigits())
        XCTAssertTrue(added.isValid(for: english))
        XCTAssertEqual(Array(added.keys.prefix(10)), ["1", "2", "4", "5", "6", "8", "9", "0", "3", "7"])
        XCTAssertEqual(added.layout, "kkkkkkkkkk/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk")
        // Four rows of letters leave no room for a fifth.
        var split = letters
        split.layout = "kkkkk/kkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertNil(split.addingDigits())
        // A digit left at the end of the last row takes the rest there, while it fits.
        var last = letters
        last.keys.append("0")
        last.layout = "kkkkkkkkkk/kkkkkkkkk/kkkkkkkkkk"
        XCTAssertNil(last.addingDigits(), "Nine more keys do not fit in that row")
        var short = Arrangement.letters(for: english)
        short.keys.insert("0", at: 0)
        short.layout = "k/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        let joined = try XCTUnwrap(short.addingDigits())
        XCTAssertEqual(Array(joined.keys.prefix(10)), ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"])
        XCTAssertEqual(joined.layout, "kkkkkkkkkk/kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk")
    }

    func testStockNumberRowTakesEveryDigitOutAndPutsTheStandardRowOnTop() throws {
        let english = KeyboardAlphabet.english
        // A customized number row: 2 before 1, a gap, and 0 moved after p.
        var custom = Arrangement.standard(for: english)
        custom.keys.swapAt(0, 1)
        let zero = custom.keys.remove(at: 9)
        custom.keys.insert(zero, at: 19)
        custom.layout = "kkkkgkkkkk/kkkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertTrue(custom.isValid(for: english))
        XCTAssertEqual(custom.withStockNumberRow(), .standard(for: english))
        XCTAssertEqual(Arrangement.standard(for: english).withStockNumberRow(), .standard(for: english))
        XCTAssertEqual(Arrangement.letters(for: english).withStockNumberRow(), .standard(for: english))
        // Rearranged letters and gaps stay where they are.
        var letters = Arrangement.letters(for: english)
        letters.keys.swapAt(0, 1)
        letters.layout = "hkkkkkkkkkk/kkkkkkkkk/kkkkkkkkk"
        var digits = letters.prependingNumberRow
        digits.keys.swapAt(3, 8)
        let stock = try XCTUnwrap(digits.withStockNumberRow())
        XCTAssertEqual(stock, letters.prependingNumberRow)
        XCTAssertEqual(Array(stock.keys.prefix(10)), Arrangement.digits)
        XCTAssertTrue(stock.isValid(for: english))
        // Four rows of letters leave no room on top; an unreadable layout has nothing to keep.
        var split = Arrangement.letters(for: english)
        split.layout = "kkkkk/kkkkk/kkkkkkkkk/kkkkkkkkk"
        XCTAssertNil(split.withStockNumberRow())
        var unreadable = custom
        unreadable.layout = "x"
        XCTAssertNil(unreadable.withStockNumberRow())
    }

    func testFunctionKeysAreWiderAndEveryRowFits() {
        let standard = Arrangement.standard(for: .english)
        XCTAssertEqual(standard.rows.count, 4)
        let width = Arrangement.keyWidth(for: standard.rows, available: 390, spacing: 5)
        XCTAssertEqual(width, (390 - 45) / 10, accuracy: 0.001, "Ten letters fill a row")
        for row in standard.rows {
            let total = row.reduce(0) { $0 + Arrangement.width(of: $1, keyWidth: width, spacing: 5) } + 5 * CGFloat(row.count - 1)
            XCTAssertLessThanOrEqual(total, 390.001)
        }
        XCTAssertEqual(Arrangement.width(of: .key(Arrangement.shift), keyWidth: 30, spacing: 4), 47)
        XCTAssertEqual(Arrangement.width(of: .halfGap, keyWidth: 30, spacing: 4), 13)
        XCTAssertEqual(Arrangement.width(of: .gap, keyWidth: 30, spacing: 4), 30)
        let wide: [[Arrangement.Cell]] = [Array(repeating: .key("a"), count: 11) + [.halfGap, .gap]]
        XCTAssertLessThan(Arrangement.keyWidth(for: wide, available: 390, spacing: 5), (390 - 45) / 10)
        XCTAssertEqual(Arrangement.keyWidth(for: [], available: .nan, spacing: 5), 0)
        XCTAssertEqual(Arrangement.keyWidth(for: [[]], available: 390, spacing: 5), (390 - 45) / 10)
    }

    func testInsertingAKeySlotAtTheStartOfARow() throws {
        var layout = try XCTUnwrap(SymbolPageLayout("kk/hkk"))
        XCTAssertEqual(layout.insertKeySlot(atStartOf: 1), 2)
        XCTAssertEqual(layout.text, "kk/khkk")
        XCTAssertNil(layout.insertKeySlot(atStartOf: 2))
        var full = try XCTUnwrap(SymbolPageLayout(String(repeating: "k", count: 16)))
        XCTAssertNil(full.insertKeySlot(atStartOf: 0))
    }

    // MARK: Main Keyboard sections (1.4)

    func testSectionsShowTheKeyboardsOwnTitlesAndSpeakTheirMeaning() {
        XCTAssertEqual(MainKeyboardSection.allCases, [.letters, .numbers, .symbols])
        for alphabet in KeyboardAlphabet.catalog {
            XCTAssertEqual(MainKeyboardSection.letters.title(for: alphabet), alphabet.lettersKeyTitle)
            XCTAssertEqual(alphabet.lettersKeyTitle, "ABC")
        }
        XCTAssertEqual(MainKeyboardSection.numbers.title(for: .english), "123")
        XCTAssertEqual(MainKeyboardSection.symbols.title(for: .english), "#+=")
        XCTAssertEqual(MainKeyboardSection.allCases.map(\.accessibilityLabel), ["Letters", "Numbers and Symbols", "More Symbols"])
        XCTAssertEqual(MainKeyboardSection.allCases.map(\.layout), [.letters, .numbers, .symbols])
        XCTAssertEqual(MainKeyboardSymbolLayer.switchTitle(to: .symbols, isPad: false), "#+=")
        XCTAssertEqual(MainKeyboardSymbolLayer.switchTitle(to: .symbols, isPad: true), "#+=")
        XCTAssertEqual(MainKeyboardSymbolLayer.switchTitle(to: .numbers, isPad: false), "123")
        XCTAssertEqual(MainKeyboardSymbolLayer.switchTitle(to: .numbers, isPad: true), ".?123")
        XCTAssertEqual(MainKeyboardSymbolLayer.switchLabel(to: .symbols), "Switch to More Symbols")
        XCTAssertEqual(MainKeyboardSymbolLayer.switchLabel(to: .numbers), "Switch to Numbers and Symbols")
    }

    func testSymbolCanvasesDrawThePagesAsTheKeyboardDoes() throws {
        typealias Layer = MainKeyboardSymbolLayer
        let english = KeyboardAlphabet.english
        func texts(_ layer: Layer?) throws -> [[String]] {
            try XCTUnwrap(layer).rows.map { $0.map { cell in
                switch cell {
                case .key(let text): return text
                case .switchKey(let target): return "→" + target.rawValue
                case .delete: return "⌫"
                case .returnKey: return "⏎"
                }
            } }
        }
        func row(_ text: String) -> [String] { text.map(String.init) }
        let digits = row("1234567890"), brackets = row("[]{}#%^*+="), numbers = row("-/:;()$&@\""), symbols = row("_\\|~<>€£¥•")
        let punctuation = row(".,?!'")
        XCTAssertNil(Layer(section: .letters, arrangement: .standard(for: english), isPad: false), "The arrangement draws the letters")
        // Without a number row: the iPhone pages, three rows each.
        let letters = Arrangement.letters(for: english)
        XCTAssertEqual(try texts(Layer(section: .numbers, arrangement: letters, isPad: false)),
                       [digits, numbers, ["→symbols"] + punctuation + ["⌫"]])
        XCTAssertEqual(try texts(Layer(section: .symbols, arrangement: letters, isPad: false)),
                       [brackets, symbols, ["→numbers"] + punctuation + ["⌫"]])
        // ABC's number row never adds digits or brackets to the symbol pages.
        let standard = Arrangement.standard(for: english)
        XCTAssertEqual(try texts(Layer(section: .numbers, arrangement: standard, isPad: false)),
                       [digits, numbers, ["→symbols"] + punctuation + ["⌫"]])
        XCTAssertEqual(try texts(Layer(section: .symbols, arrangement: standard, isPad: false)),
                       [brackets, symbols, ["→numbers"] + punctuation + ["⌫"]])
        // Return depends on actual width, not just iPad idiom.
        XCTAssertEqual(try texts(Layer(section: .symbols, arrangement: standard, isPad: true, availableWidth: 1008)),
                       [brackets, symbols, ["→numbers"] + punctuation + ["⌫", "⏎"]])
        XCTAssertEqual(try texts(Layer(section: .numbers, arrangement: letters, isPad: true, availableWidth: 1008)),
                       [digits, numbers, ["→symbols"] + punctuation + ["⌫", "⏎"]])
        let oneDigit = Arrangement(keys: ["1"] + letters.keys, layout: "k" + letters.layout)
        XCTAssertEqual(try texts(Layer(section: .numbers, arrangement: oneDigit, isPad: false)).count, 3, "Three rows on iPhone")
        XCTAssertEqual(try texts(Layer(section: .numbers, arrangement: oneDigit, isPad: true)).first, digits, "123 keeps its own digits regardless of ABC")
        // Each key once, by its settings identifier; digits are the number row's keys.
        let ids = try XCTUnwrap(Layer(section: .numbers, arrangement: standard, isPad: false)).keyIDs
        XCTAssertEqual(ids.count, 25)
        XCTAssertEqual(Array(ids.prefix(3)), ["digit.1", "digit.2", "digit.3"])
        XCTAssertTrue(ids.contains("symbol.0024"), "$ is on the 123 page")
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testFindAKeyReachesEveryLegacySymbolKeyOnceOnIPhoneAndIPad() throws {
        typealias Search = MainKeyboardKeySearch
        let legacy = KeyboardKeySettings.descriptors.filter { $0.kind == .character }.map(\.id)
        XCTAssertEqual(legacy.count, 46, "The 1.3 Symbol Keys grid")
        // Only the wide iPad's landscape layouts draw these: listed last under #+=, in code point order.
        let wide = Set("`§±×÷°©®™…·".compactMap { KeyboardKeySettings.identifier(forCharacter: String($0)) })
        XCTAssertEqual(wide.count, 11)
        let offCanvas = legacy.filter(wide.contains)
        for isPad in [false, true] {
            for alphabet in KeyboardAlphabet.catalog {
                for arrangement in [Arrangement.standard(for: alphabet), .letters(for: alphabet)] {
                    let groups = Search.groups(alphabet: alphabet, arrangement: arrangement, isPad: isPad)
                    let context = "\(alphabet.id) pad \(isPad) rows \(arrangement.typingRowCount)"
                    XCTAssertEqual(groups.map(\.section), [.letters, .numbers, .symbols], context)
                    let ids = groups.flatMap { $0.keys.map(\.id) }
                    XCTAssertEqual(Set(ids).count, ids.count, "Every key is listed once: \(context)")
                    // Reachable on a canvas or through Find a key: as many as 1.3 listed.
                    let drawn = MainKeyboardSection.allCases.compactMap {
                        MainKeyboardSymbolLayer(section: $0, arrangement: arrangement, isPad: isPad)
                    }.flatMap(\.keyIDs)
                    let reachable = Set(ids).union(drawn).intersection(legacy)
                    XCTAssertEqual(reachable.count, legacy.count, context)
                    XCTAssertEqual(Set(drawn).intersection(legacy).count, 35, "Symbol keys on the canvases: \(context)")
                    XCTAssertTrue(Set(drawn).isSubset(of: ids), "Every drawn key is searchable: \(context)")
                    XCTAssertEqual(Array(groups[2].keys.map(\.id).suffix(offCanvas.count)), offCanvas,
                                   "Keys no canvas draws are listed last under #+=: \(context)")
                    // The letters are the layout's own; digits are under 123.
                    let letters = alphabet.keys.compactMap(KeyboardKeySettings.identifier(forCharacter:))
                        .filter { KeyboardKeySettings.descriptor(for: $0)?.kind == .letter }
                    XCTAssertEqual(Set(groups[0].keys.map(\.id)), Set(letters), context)
                    XCTAssertTrue(groups[0].keys.allSatisfy { $0.kind == .letter })
                    XCTAssertEqual(groups[1].keys.filter { $0.kind == .digit }.count, 10, context)
                    XCTAssertFalse(groups[2].keys.contains { $0.kind != .character }, context)
                }
            }
        }
        // Brackets are only on #+=; shared punctuation is listed under 123.
        let english = KeyboardAlphabet.english
        let standard = Search.groups(alphabet: english, arrangement: .standard(for: english), isPad: false)
        XCTAssertFalse(standard[1].keys.contains { $0.id == "symbol.005B" }, "123 never repeats the bracket row")
        XCTAssertTrue(standard[2].keys.contains { $0.id == "symbol.005B" })
        XCTAssertFalse(standard[2].keys.contains { $0.id == "symbol.002E" }, ". is on both pages, listed under 123")
        let letters = Search.groups(alphabet: english, arrangement: .letters(for: english), isPad: false)
        XCTAssertTrue(letters[2].keys.contains { $0.id == "symbol.005B" }, "[ is only on #+= without the number row")
        XCTAssertEqual(standard[0].keys.map(\.title), "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init), "English lists A to Z")
        let greek = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "el"))
        let greekLetters = Search.groups(alphabet: greek, arrangement: .standard(for: greek), isPad: false)[0].keys
        XCTAssertEqual(greekLetters.first?.title, "Σ", "Other layouts list their letters in keyboard order, after ;")
    }

    func testFindAKeyMatchesTitlesAndIdentifiersAcrossSections() {
        typealias Search = MainKeyboardKeySearch
        let english = KeyboardAlphabet.english, standard = Arrangement.standard(for: english)
        func search(_ query: String) -> [MainKeyboardKeySearch.Group] {
            Search.search(query, alphabet: english, arrangement: standard, isPad: false)
        }
        let euro = search("€")
        XCTAssertEqual(euro.map(\.section), [.symbols])
        XCTAssertEqual(euro.first?.keys.map(\.id), ["symbol.20AC"], "One result, under #+=")
        XCTAssertEqual(search("q").map(\.section), [.letters])
        XCTAssertEqual(search("q").first?.keys.map(\.title), ["Q"])
        XCTAssertEqual(search("DIGIT.1").first?.keys.map(\.id), ["digit.1"], "Identifiers match, ignoring case")
        XCTAssertEqual(search("$").map(\.section), [.numbers])
        XCTAssertTrue(search("no such key").isEmpty)
        XCTAssertEqual(search(""), Search.groups(alphabet: english, arrangement: standard, isPad: false))
        XCTAssertTrue(Search.matches(KeyboardKeySettings.descriptors[0], query: ""))
    }
}

extension MainKeyboardArrangementTests {
    func testExplicitStandardIsNotElidedAndPreservesAlignmentThroughAdapters() throws {
        let standard = MainKeyboardArrangement.standard(for: .english)
        XCTAssertTrue(standard.isLegacy)
        var rows = standard.resolvedRows
        rows[0].alignment = .right
        var explicit = MainKeyboardArrangement(rows: rows)
        XCTAssertTrue(explicit.isValid(for: .english))
        XCTAssertNotEqual(explicit, standard)
        let snapshot = try XCTUnwrap(KeyboardKeySettings.Snapshot.defaults.updatingArrangement(explicit, for: "en"))
        let data = try XCTUnwrap(KeyboardKeySettings.encode(snapshot))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 5)
        XCTAssertEqual(KeyboardKeySettings.decode(data), snapshot)
        XCTAssertNil(KeyboardKeySettings.decode(Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":5", with: "\"schemaVersion\":4").utf8)))
        XCTAssertEqual(explicit.keyRows(widePad: true), explicit.typingRowCount)
        explicit.keys.swapAt(0, 1)
        XCTAssertEqual(explicit.explicitRows?.first?.alignment, .right)
        let projectedLayout = explicit.layout
        explicit.layout = projectedLayout
        XCTAssertEqual(explicit.explicitRows?.first?.alignment, .right)
        XCTAssertFalse(explicit.isLegacy)
        XCTAssertEqual(try JSONDecoder().decode(MainKeyboardArrangement.self, from: JSONEncoder().encode(explicit)), explicit)
        XCTAssertFalse(explicit.setExplicitRows([]))
        XCTAssertFalse(explicit.setExplicitRows(Array(repeating: rows[0], count: 5)))
        var legacy = standard
        XCTAssertTrue(legacy.convertToExplicitRows())
        XCTAssertFalse(legacy.isLegacy)
    }

    func testExplicitDigitEditsKeepSurvivingRowsAndTrailingGaps() throws {
        var letters = MainKeyboardArrangement.letters(for: .english)
        XCTAssertTrue(letters.convertToExplicitRows())
        var rows = letters.resolvedRows
        rows[0].alignment = .spaced
        rows[2].cells.append(.halfGap)
        XCTAssertTrue(letters.setExplicitRows(rows))
        XCTAssertEqual(letters.rows.last?.last, .halfGap)
        let numbered = try XCTUnwrap(letters.addingDigits())
        XCTAssertEqual(numbered.explicitRows?[1].alignment, .spaced)
        XCTAssertEqual(numbered.withStockNumberRow()?.explicitRows?[1].alignment, .spaced)
        var partial = numbered
        partial.keys.removeFirst()
        XCTAssertEqual(partial.addingDigits()?.explicitRows?.first?.alignment, .center)
        XCTAssertTrue(partial.addingDigits()?.isValid(for: .english) == true)
        for bad in [#"{"rows":[],"keys":[],"layout":"k"}"#, #"{"rows":[]}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(MainKeyboardArrangement.self, from: Data(bad.utf8)))
        }
    }
}

extension MainKeyboardArrangementTests {
    func testExplicitFunctionWidthsUseTwelveUnitsWithoutChangingLegacySixteenSlotPolicy() throws {
        typealias Row = MainKeyboardArrangement.Row
        let exact = Row(cells: Array(repeating: .key("a"), count: 9) + [.key(MainKeyboardArrangement.shift), .key(MainKeyboardArrangement.delete)])
        XCTAssertEqual(exact.units, 12)
        XCTAssertTrue(Row.valid([exact]))
        let over = Row(cells: exact.cells + [.halfGap])
        XCTAssertEqual(over.units, 12.5)
        XCTAssertFalse(Row.valid([over]))
        XCTAssertThrowsError(try JSONDecoder().decode(Row.self, from: JSONEncoder().encode(over)))
        XCTAssertNotNil(SymbolPageLayout(String(repeating: "k", count: 16)))
        XCTAssertNil(SymbolPageLayout(String(repeating: "k", count: 17)))
        let invalid = MainKeyboardArrangement(rows: [over])
        XCTAssertNil(KeyboardKeySettings.encode(.init(arrangements: ["en": invalid])))
        let explicit = MainKeyboardArrangement(rows: MainKeyboardArrangement.letters(for: .english).resolvedRows)
        let premigration = KeyboardKeySettings.Snapshot(arrangements: ["en": explicit], arrangesNumberRow: false)
        XCTAssertNil(premigration.updatingArrangement(explicit, for: "en"))
        XCTAssertNil(KeyboardKeySettings.encode(premigration))
        XCTAssertThrowsError(try JSONEncoder().encode(invalid))
    }
}

extension MainKeyboardArrangementTests {
    func testExplicitProjectionAndAddingDigitsRetainTheFinalTypedGaps() throws {
        let legacy = MainKeyboardArrangement.letters(for: .english)
        var explicit = MainKeyboardArrangement(rows: legacy.resolvedRows)
        var rows = try XCTUnwrap(explicit.explicitRows)
        rows[0].cells.insert(.key("1"), at: 0)
        rows[0].alignment = .right
        rows[2].cells += [.halfGap, .gap]
        explicit = .init(rows: rows)
        let projected = explicit.layout
        explicit.layout = projected
        XCTAssertEqual(explicit.explicitRows, rows)
        // Leave room for missing digits while retaining every English key:
        // move the first row's remaining letters into a fourth saved row.
        let moved = Array(rows[0].cells.dropFirst(2))
        rows[0].cells = [.key("1"), .halfGap, .key("q")]
        rows.insert(.init(alignment: .left, cells: moved), at: 1)
        explicit = .init(rows: rows)
        XCTAssertTrue(explicit.isValid(for: .english))
        let added = try XCTUnwrap(explicit.addingDigits())
        XCTAssertTrue(added.isValid(for: .english))
        XCTAssertEqual(added.explicitRows?.last, rows.last)
        XCTAssertEqual(added.explicitRows?.first?.alignment, .right)
        XCTAssertEqual(added.missingDigits, [])
    }
}

extension MainKeyboardArrangementTests {
    func testSymbolCanvasKeepsABCHeightAndUsesActualNarrowWideAndANSIContext() throws {
        for arrangement in [Arrangement.standard(for: .english), .letters(for: .english)] {
            for pad in [false, true] {
                for width: CGFloat in [.nan, .infinity, -1, 0, 386, 649, 650, 979, 980, 1008] {
                    for landscape in [false, true] {
                        for preset in KeyboardPadLayout.allCases {
                            for section in [MainKeyboardSection.numbers, .symbols] {
                                let layer = try XCTUnwrap(MainKeyboardSymbolLayer(section: section, arrangement: arrangement,
                                    isPad: pad, availableWidth: width, isLandscape: landscape, padLayout: preset))
                                let ansi = KeyboardTypingLayoutPolicy.usesANSI(availableWidth: width, isPad: pad,
                                    isLandscape: landscape, padLayout: preset)
                                let extra = section == .symbols && ansi && arrangement.typingRowCount == 4
                                XCTAssertEqual(layer.rows.count, extra ? 4 : 3)
                                XCTAssertEqual(layer.rows.last?.contains(.returnKey), pad && width.isFinite && width >= 650)
                                XCTAssertEqual(layer.switchKeyTitle, section == .numbers ? "#+=" : ansi && preset == .ansiNumbers ? "=<>" : pad ? ".?123" : "123")
                                let count = CGFloat(layer.rows.count)
                                XCTAssertEqual(count * layer.canvasKeyHeight + (count - 1) * 6,
                                    CGFloat(arrangement.rows.count) * 44 + CGFloat(arrangement.rows.count - 1) * 6, accuracy: 0.000001)
                                if extra {
                                    XCTAssertEqual(layer.rows[0], "§±×÷°©®™…·".map { .key(String($0)) })
                                    XCTAssertEqual(layer.rows[1], "[]{}#%^*+=".map { .key(String($0)) })
                                    XCTAssertEqual(layer.canvasKeyHeight, 44)
                                } else {
                                    XCTAssertEqual(layer.canvasKeyHeight, arrangement.typingRowCount == 4 ? 182.0 / 3 : 44, accuracy: 0.000001)
                                }
                                let characters = layer.rows.flatMap { $0 }.compactMap { cell -> String? in
                                    if case .key(let value) = cell { return value }; return nil
                                }
                                XCTAssertEqual(characters.count, Set(characters).count)
                                XCTAssertEqual(characters.filter(Arrangement.isDigit).count, section == .numbers ? 10 : 0)
                            }
                        }
                    }
                }
            }
        }
    }

    func testTwoRowLegacySymbolCanvasKeepsTheReservedABCCanvasBudget() throws {
        var arrangement = Arrangement.letters(for: .english)
        arrangement.layout = "kkkkkkkkkkkkkk/kkkkkkkkkkkkkk"
        XCTAssertTrue(arrangement.isValid(for: .english))
        XCTAssertTrue(arrangement.isLegacy)
        XCTAssertEqual(arrangement.rows.count, 2)
        XCTAssertEqual(arrangement.typingRowCount, 3, "Extension height remains its independent three-row minimum")
        let saved = arrangement
        let abcHeight = CGFloat(arrangement.rows.count) * 44 + CGFloat(arrangement.rows.count - 1) * 6
        XCTAssertEqual(abcHeight, 94)
        let abcRows = CGFloat(max(3, arrangement.rows.count))
        let canvasHeight = abcRows * 44 + (abcRows - 1) * 6
        XCTAssertEqual(canvasHeight, 144)
        XCTAssertEqual((canvasHeight - abcHeight) / 2, 25, "Center the unchanged ABC tiles in the reserved canvas")
        for pad in [false, true] {
            for width: CGFloat in [386, 1008] {
                for preset in KeyboardPadLayout.allCases {
                    for section in [MainKeyboardSection.numbers, .symbols] {
                        let layer = try XCTUnwrap(MainKeyboardSymbolLayer(section: section, arrangement: arrangement,
                            isPad: pad, availableWidth: width, isLandscape: true, padLayout: preset))
                        XCTAssertEqual(layer.rows.count, 3)
                        XCTAssertEqual(layer.canvasKeyHeight, 44)
                        XCTAssertEqual(CGFloat(layer.rows.count) * layer.canvasKeyHeight
                            + CGFloat(layer.rows.count - 1) * 6, canvasHeight, accuracy: 0.000001)
                    }
                }
            }
        }
        XCTAssertEqual(arrangement, saved, "No ABC geometry or arrangement rewrite")
        var oneRow = arrangement
        oneRow.layout = String(repeating: "k", count: oneRow.keys.count)
        XCTAssertFalse(oneRow.isValid(for: .english), "One English row exceeds the existing legacy 16-slot limit")
    }

    func testNumberPageAndABCUseOneDigitSettingsIdentityWithoutLosingAnySavedKeys() throws {
        typealias Settings = KeyboardKeySettings
        var custom = Arrangement.standard(for: .english)
        custom.keys.swapAt(0, 1)
        custom.keys.swapAt(10, 11)
        var snapshot = try XCTUnwrap(Settings.Snapshot.defaults.updatingArrangement(custom, for: "en"))
        snapshot = try XCTUnwrap(snapshot.updating(["one"], for: "digit.1", gesture: .tap))
        snapshot = try XCTUnwrap(snapshot.updating(["¹"], for: "digit.1", gesture: .swipeUp))
        snapshot = try XCTUnwrap(snapshot.updating(["section"], for: "symbol.00A7", gesture: .tap))
        let before = snapshot
        let layer = try XCTUnwrap(MainKeyboardSymbolLayer(section: .numbers, arrangement: custom, isPad: false))
        XCTAssertEqual(layer.keyIDs.filter { $0 == "digit.1" }.count, 1)
        XCTAssertTrue(custom.keys.contains("1"))
        let id = try XCTUnwrap(Settings.identifier(forCharacter: "1"))
        XCTAssertEqual(id, "digit.1")
        XCTAssertEqual(snapshot.tapOutput(for: id, defaultText: "1", shifted: false), "one")
        XCTAssertEqual(snapshot.candidates(for: layer.keyIDs[0], gesture: .swipeUp), ["¹"])
        XCTAssertEqual(snapshot, before, "Rendering and switching pages never rewrites settings")
        XCTAssertEqual(Settings.decode(try XCTUnwrap(Settings.encode(snapshot))), snapshot)
        XCTAssertEqual(snapshot.effectiveArrangement(for: .english), custom)
        XCTAssertEqual(Settings.descriptors.filter { $0.kind == .character }.count, 46, "Keep all legacy symbol IDs, even off-canvas")
    }
}

#if os(macOS)
extension MainKeyboardArrangementTests {
    /// Source integration only: native frame/callout behavior still requires
    /// the parent's actual editor and extension captures.
    func testSymbolPageIntegrationKeepsOuterBudgetFooterAndQueryIndependentOfPageRows() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let controller = try String(contentsOf: root.appendingPathComponent("Keyboard/KeyboardViewController.swift"), encoding: .utf8)
        let editor = try String(contentsOf: root.appendingPathComponent("App/MainKeyboardEditorView.swift"), encoding: .utf8)
        let heightStart = try XCTUnwrap(controller.range(of: "    private func updateKeyboardHeight(animated: Bool = false) {"))
        let heightEnd = try XCTUnwrap(controller.range(of: "    private func applyKeyboardHeight(", range: heightStart.upperBound..<controller.endIndex))
        let height = String(controller[heightStart.lowerBound..<heightEnd.lowerBound])
        XCTAssertTrue(height.contains("model.typingArrangement.keyRows(widePad:"))
        XCTAssertTrue(height.contains("keyRows: keyRows"))
        XCTAssertFalse(height.contains("typingState.layout"), "Page changes cannot resize the outer keyboard")
        let footerStart = try XCTUnwrap(controller.range(of: "    private func footerPageKey("))
        let footerEnd = try XCTUnwrap(controller.range(of: "private struct KeyboardTypingView:", range: footerStart.upperBound..<controller.endIndex))
        let footer = String(controller[footerStart.lowerBound..<footerEnd.lowerBound])
        XCTAssertTrue(footer.contains("letters ? model.typingState.alphabet.lettersKeyTitle : model.mergesSymbols ? \"#+=\" : \"123\""))
        XCTAssertFalse(footer.contains("typingAuxiliaryRowVisible"), "123 means the same stock page with or without ABC digits")
        XCTAssertTrue(controller.contains("if plan.auxiliaryRowCount > 0 && !arranged { auxiliaryRow("))
        XCTAssertTrue(controller.contains("value: plan.auxiliaryRowCount > 0"))
        XCTAssertTrue(controller.contains("KeyboardTypingLayoutPolicy.routedOutput(for: key, state: captured,"))
        XCTAssertTrue(controller.contains("self?.model.typingState.layout == captured.layout"))
        XCTAssertTrue(controller.contains("let rows = KeyboardQueryHoldPolicy.rows"))
        XCTAssertTrue(controller.contains("action(mode, .queryHold(key))"))
        XCTAssertTrue(controller.contains("action(mode, .query(key))"))
        XCTAssertTrue(editor.contains(".onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }"))
        XCTAssertTrue(editor.contains("availableWidth: max(0, containerSize.width - 16)"))
        XCTAssertTrue(editor.contains("isLandscape: containerSize.width > containerSize.height"))
        XCTAssertTrue(editor.contains("padLayout: alphabet == .english ? preferences.padLayout : .stock"))
        XCTAssertFalse(editor.contains("UIScreen.main"))
        XCTAssertTrue(editor.contains("let canvasRows = CGFloat(max(3, rows.count))"))
        XCTAssertTrue(editor.contains(".frame(minHeight: canvasRows * 44 + (canvasRows - 1) * 6, alignment: .center)\n        .padding(8)"),
            "Reserve the ABC minimum inside the existing outer padding, keeping shorter arrangements centered")
        XCTAssertTrue(editor.contains("height: layer.canvasKeyHeight, switchTitle: layer.switchKeyTitle,"))
        XCTAssertTrue(editor.contains("Text(symbolKeyPreview(shown)).font(.system(size: 22))"), "Taller tiles keep their existing glyph size")
    }
}
#endif

final class MergedSymbolsTests: XCTestCase {
    private typealias Settings = KeyboardKeySettings
    private typealias Arrangement = MainKeyboardArrangement

    private func eligible(_ settings: Settings.Snapshot = .defaults, alphabet: KeyboardAlphabet = .english,
                          width: CGFloat = 386, pad: Bool = false, landscape: Bool = false,
                          preset: KeyboardPadLayout = .stock) -> Bool {
        KeyboardMergedSymbolsPolicy.isEligible(settings: settings, alphabet: alphabet,
            availableWidth: width, isPad: pad, isLandscape: landscape, padLayout: preset)
    }

    private func snapshot(_ arrangement: Arrangement) -> Settings.Snapshot {
        Settings.Snapshot(arrangements: ["en": arrangement])
    }

    private func removing(_ digit: String) -> Arrangement {
        let stock = Arrangement.standard(for: .english)
        return Arrangement(rows: stock.resolvedRows.map { row in
            Arrangement.Row(alignment: row.alignment, cells: row.cells.filter { $0.key != digit })
        })
    }

    func testEligibilityUsesEffectiveSettingsCurrentGeometryAndAllLayouts() throws {
        XCTAssertTrue(eligible())
        for height: CGFloat in [30, 41.3, .nan, .infinity, -.infinity] {
            XCTAssertFalse(KeyboardMergedSymbolsPolicy.isEligible(settings: .defaults, alphabet: .english,
                availableWidth: 386, isPad: false, normalKeyHeight: height))
        }
        XCTAssertTrue(KeyboardMergedSymbolsPolicy.isEligible(settings: .defaults, alphabet: .english,
            availableWidth: 386, isPad: false, normalKeyHeight: 41.4))
        for alphabet in KeyboardAlphabet.catalog {
            XCTAssertTrue(eligible(alphabet: alphabet), alphabet.id)
        }
        for preset in KeyboardPadLayout.allCases {
            for landscape in [false, true] {
                XCTAssertTrue(eligible(width: 649.999, pad: true, landscape: landscape, preset: preset))
                for width: CGFloat in [650, 980, 1360] {
                    XCTAssertFalse(eligible(width: width, pad: true, landscape: landscape, preset: preset))
                }
                XCTAssertTrue(eligible(width: 1000, landscape: landscape, preset: preset), "A wide phone is still phone-style")
            }
        }
        for width: CGFloat in [0, -1, .nan, .infinity, -.infinity, 45] { XCTAssertFalse(eligible(width: width)) }
        XCTAssertFalse(eligible(width: 63, pad: true))
        XCTAssertTrue(eligible(width: 64, pad: true))
        let invalid = Arrangement(keys: ["not-a-key"], layout: "k")
        XCTAssertFalse(invalid.isValid(for: .english))
        XCTAssertTrue(eligible(snapshot(invalid)), "Eligibility uses the effective fallback, not malformed saved IDs")
        XCTAssertFalse(eligible(snapshot(.letters(for: .english))))
    }

    func testRemovedOrCustomizedDigitsRestoreFallbackWithoutChangingAnySettings() throws {
        let stock = Settings.Snapshot.defaults
        for digit in Arrangement.digits {
            let removed = removing(digit)
            XCTAssertTrue(removed.isValid(for: .english))
            XCTAssertFalse(eligible(snapshot(removed)), digit)
            let changed = try XCTUnwrap(stock.updating(["🙂"], for: "digit." + digit, gesture: .tap))
            XCTAssertFalse(eligible(changed), digit)
            let restored = changed.removingOverride(for: "digit." + digit)
            XCTAssertTrue(eligible(restored))
            XCTAssertEqual(restored, stock)
            // Hold and swipe cannot replace a missing direct tap.
            for gesture in Settings.Gesture.customizable {
                let holdOnly = try XCTUnwrap(changed.updating([digit], for: "digit." + digit, gesture: gesture))
                XCTAssertFalse(eligible(holdOnly))
            }
        }
        for text in ["５", "55", "5\u{FE0F}", "5 "] {
            XCTAssertFalse(eligible(try XCTUnwrap(stock.updating([text], for: "digit.5", gesture: .tap))))
        }
        var gestures = stock
        for gesture in Settings.Gesture.customizable + [.shiftedTap] {
            gestures = try XCTUnwrap(gestures.updating(["★"], for: "digit.5", gesture: gesture))
            XCTAssertTrue(eligible(gestures), "Only stable unshifted taps count")
        }
        let sameTap = try XCTUnwrap(gestures.updating(["5"], for: "digit.5", gesture: .tap))
        XCTAssertTrue(eligible(sameTap))
        let before = sameTap
        _ = eligible(sameTap)
        XCTAssertEqual(sameTap, before)
        XCTAssertEqual(Settings.decode(try XCTUnwrap(Settings.encode(sameTap))), before)
    }

    func testAvailabilityCountsActualTapOutputsNotDigitIDsOrOtherGestures() throws {
        let missing = snapshot(removing("0"))
        XCTAssertFalse(eligible(missing))
        let routedDigit = try XCTUnwrap(missing.updating(["0"], for: "letter.q", gesture: .tap))
        XCTAssertTrue(eligible(routedDigit), "A drawn key that directly types 0 satisfies the actual-output condition")
        let onlyHold = try XCTUnwrap(missing.updating(["0"], for: "letter.q", gesture: .longPress))
        XCTAssertFalse(eligible(onlyHold))
        // A digit ID alone is insufficient: changing 0 to 1 leaves no direct 0.
        XCTAssertFalse(eligible(try XCTUnwrap(Settings.Snapshot.defaults.updating(["1"], for: "digit.0", gesture: .tap))))
    }

    func testShortLandscapeSceneAndPreviewMustFitFourNormalRowsBeforeMerging() {
        let display = CGSize(width: 393, height: 852)
        let preview = KeyboardLayoutPolicy.metrics(viewWidth: 852, displaySize: display,
            sceneHeight: 320, isPad: false, compactVertical: true, showsTextPreview: true)
        XCTAssertEqual(preview.height, 272, accuracy: 0.0001)
        XCTAssertEqual(preview.typingKeyHeight, 39.6666666667, accuracy: 0.0001)
        XCTAssertFalse(KeyboardMergedSymbolsPolicy.isEligible(settings: .defaults, alphabet: .english,
            availableWidth: 836, isPad: false, normalKeyHeight: preview.typingKeyHeight),
            "Width and four saved rows alone must not squeeze merged symbol keys")
        for metrics in [
            KeyboardLayoutPolicy.metrics(viewWidth: 852, displaySize: display, sceneHeight: 320,
                isPad: false, compactVertical: true, showsTextPreview: false),
            KeyboardLayoutPolicy.metrics(viewWidth: 852, displaySize: display, sceneHeight: 400,
                isPad: false, compactVertical: true, showsTextPreview: true)
        ] {
            XCTAssertTrue(KeyboardMergedSymbolsPolicy.isEligible(settings: .defaults, alphabet: .english,
                availableWidth: 836, isPad: false, normalKeyHeight: metrics.typingKeyHeight),
                "Removing the preview or restoring height re-enables the merge")
        }
    }

    func testLegacyThreeRowsWithAllTenDigitsStillLackFourNormalRows() throws {
        let first: [String] = "1234qwertyuiop".map { String($0) }
        let second: [String] = "5678asdfghjkl".map { String($0) }
        let thirdCharacters: [String] = "90zxcvbnm".map { String($0) }
        let third: [String] = [Arrangement.shift] + thirdCharacters + [Arrangement.delete]
        let rows: [[String]] = [first, second, third]
        let legacy = Arrangement(keys: rows.flatMap { $0 }, layout: rows.map { String(repeating: "k", count: $0.count) }.joined(separator: "/"))
        XCTAssertTrue(legacy.isValid(for: .english), "Keep the legacy 16-unit compatibility contract")
        XCTAssertTrue(legacy.missingDigits.isEmpty)
        let rendering = KeyboardABCRendering(alphabet: .english, arrangement: legacy,
            availableWidth: 386, isPad: false, isLandscape: false, padLayout: .stock)
        XCTAssertTrue(rendering.arranged)
        XCTAssertEqual(rendering.rowCount, 3)
        XCTAssertTrue(Set(Arrangement.digits).isSubset(of: rendering.plainTapOutputs(settings: snapshot(legacy), padLayout: .stock)))
        XCTAssertFalse(eligible(snapshot(legacy)))
        let compacted = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 132.2, availableWidth: 386,
            compact: false, layout: .symbols, keyRows: 3, mergedSymbols: true))
        XCTAssertLessThan(compacted.keyHeight, KeyboardTypingLayoutPolicy.regularKeyHeight,
                          "This hypothetical invalid merge is why eligibility independently requires four rows")
    }

    func testExplicitRowsGapsAndFunctionKeysKeepAllTenDigitRoutes() throws {
        var rows = Arrangement.standard(for: .english).resolvedRows
        rows[0] = Arrangement.Row(alignment: .left, cells: [.halfGap] + rows[0].cells + [.gap])
        let custom = Arrangement(rows: rows)
        XCTAssertTrue(custom.isValid(for: .english))
        let rendering = KeyboardABCRendering(alphabet: .english, arrangement: custom,
            availableWidth: 386, isPad: false, isLandscape: false, padLayout: .ansiNumbers)
        XCTAssertTrue(rendering.arranged)
        XCTAssertFalse(rendering.ansiPad)
        XCTAssertFalse(rendering.widePad)
        XCTAssertEqual(rendering.rowCount, 4)
        XCTAssertTrue(eligible(snapshot(custom), preset: .ansiNumbers))
        // Raw rendering defensively rejects keys lacking IDs or valid routes.
        let malformed = Arrangement(keys: ["unknown", "§"], layout: "kk")
        let rejected = KeyboardABCRendering(alphabet: .english, arrangement: malformed,
            availableWidth: 386, isPad: false, isLandscape: false, padLayout: .stock)
        XCTAssertTrue(rejected.plainTapOutputs(settings: .defaults, padLayout: .stock).isEmpty)
    }

    func testActualANSIBranchesProjectDigitsUnlikeSavedArrangementMembership() throws {
        let letters = Arrangement.letters(for: .english)
        XCTAssertEqual(letters.missingDigits.count, 10)
        let full = KeyboardABCRendering(alphabet: .english, arrangement: letters,
            availableWidth: 1200, isPad: true, isLandscape: true, padLayout: .ansiNumbers)
        XCTAssertTrue(full.ansiPad)
        XCTAssertTrue(full.widePad)
        XCTAssertFalse(full.arranged)
        XCTAssertFalse(full.hasAuxiliaryRow)
        XCTAssertEqual(full.rows, KeyboardTypingLayoutPolicy.ansiRows)
        XCTAssertEqual(full.rowCount, 4)
        XCTAssertTrue(Set(Arrangement.digits).isSubset(of: full.plainTapOutputs(settings: snapshot(letters), padLayout: .ansiNumbers)))
        XCTAssertFalse(eligible(snapshot(letters), width: 1200, pad: true, landscape: true, preset: .ansiNumbers))
        let changed = try XCTUnwrap(snapshot(letters).updating(["x"], for: "digit.0", gesture: .tap))
        XCTAssertFalse(full.plainTapOutputs(settings: changed, padLayout: .ansiNumbers).contains("0"))
        let compact = KeyboardABCRendering(alphabet: .english, arrangement: letters,
            availableWidth: 1200, isPad: true, isLandscape: true, padLayout: .ansi)
        XCTAssertEqual(compact.rowCount, 3)
        XCTAssertEqual(compact.rows, KeyboardTypingLayoutPolicy.compactANSIRows)
        XCTAssertFalse(compact.plainTapOutputs(settings: .defaults, padLayout: .ansi).contains("0"))
        // A legacy wide layout projects the complete auxiliary row if any digit remains.
        let oneDigit = Arrangement(keys: ["1"] + letters.keys, layout: "k/" + letters.layout)
        XCTAssertTrue(oneDigit.isValid(for: .english))
        for preset in KeyboardPadLayout.allCases {
            let projected = KeyboardABCRendering(alphabet: .english, arrangement: oneDigit,
                availableWidth: 1200, isPad: true, isLandscape: true, padLayout: preset)
            XCTAssertEqual(projected.rowCount, 4)
            XCTAssertTrue(Set(Arrangement.digits).isSubset(of: projected.plainTapOutputs(settings: .defaults, padLayout: preset)))
        }
        let explicit = Arrangement(rows: letters.resolvedRows)
        let explicitWide = KeyboardABCRendering(alphabet: .english, arrangement: explicit,
            availableWidth: 1200, isPad: true, isLandscape: true, padLayout: .ansiNumbers)
        XCTAssertFalse(explicitWide.ansiPad)
        XCTAssertTrue(explicitWide.arranged)
        XCTAssertEqual(explicitWide.rowCount, 3)
        XCTAssertFalse(explicitWide.plainTapOutputs(settings: .defaults, padLayout: .ansiNumbers).contains("0"))
    }

    func testMergedInventoryRoutingAndPageIdentityPreserveEverySymbolID() throws {
        let rows = KeyboardMergedSymbolsPolicy.rows
        let expected: [[String]] = ["[]{}#%^*+=", "_\\|~<>€£¥•", "-/:;()$&@\"", ".,?!'"].map { row in
            row.map { String($0) }
        }
        XCTAssertEqual(rows, expected)
        XCTAssertEqual(rows.map(\.count), [10, 10, 10, 5])
        let symbols = rows.flatMap { $0 }
        XCTAssertEqual(Set(symbols).count, 35)
        let oldUnion = Set((KeyboardTypingLayout.numbers.rows + KeyboardTypingLayout.symbols.rows).flatMap { $0 })
            .subtracting(Arrangement.digits)
        XCTAssertEqual(Set(symbols), oldUnion)
        let ids = symbols.compactMap(Settings.identifier(forCharacter:))
        XCTAssertEqual(Set(ids).count, 35)
        for page in KeyboardTypingLayout.allCases {
            XCTAssertEqual(KeyboardMergedSymbolsPolicy.page(page, merged: false), page)
            XCTAssertEqual(KeyboardMergedSymbolsPolicy.page(page, merged: true), page == .numbers ? .symbols : page)
        }
        var state = KeyboardTypingState()
        state.selectLayout(.symbols)
        for text in symbols {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.routedOutput(for: text, state: state, hasAuxiliaryRow: false,
                isAuxiliaryKey: false, widePad: false, ansiPad: false, padLayout: .stock,
                arrangement: .standard(for: .english), mergedSymbols: true), text)
        }
        for absent in Arrangement.digits + ["§", "`", "🙂"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: absent, state: state, hasAuxiliaryRow: true, mergedSymbols: true))
        }
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "$", state: state, hasAuxiliaryRow: false), "Fallback #+= remains unchanged")
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "$", state: state, hasAuxiliaryRow: false, mergedSymbols: true), "$")
    }

    func testMergedGeometrySharesABCNormalHeightAndWidensPunctuation() throws {
        for pad in [false, true] {
            for width: CGFloat in [320, 386, 649] {
                let abc = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 400, availableWidth: width,
                    compact: false, layout: .letters, isPad: pad))
                let merged = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 400, availableWidth: width,
                    compact: false, layout: .symbols, isPad: pad, mergedSymbols: true))
                let fallback = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 400, availableWidth: width,
                    compact: false, layout: .symbols, isPad: pad))
                XCTAssertEqual(merged.rowCount, 4)
                XCTAssertEqual(merged.auxiliaryRowCount, 0)
                XCTAssertEqual(merged.contentHeight, abc.contentHeight, accuracy: 0.00001)
                XCTAssertEqual(merged.keyHeight, abc.keyHeight, accuracy: 0.00001)
                XCTAssertEqual(merged.keyHeight, 41.4, accuracy: 0.00001)
                XCTAssertEqual(fallback.rowCount, 3)
                XCTAssertGreaterThan(fallback.keyHeight, merged.keyHeight)
                let gap: CGFloat = pad ? 7 : 5, delete: CGFloat = pad ? 64 : 42
                let punctuation = KeyboardMergedSymbolsPolicy.punctuationWidth(available: width, spacing: gap, deleteWidth: delete)
                XCTAssertEqual(punctuation * 5 + gap * 5 + delete, width, accuracy: 0.00001)
                XCTAssertGreaterThan(punctuation, (width - delete * 2 - gap * 6) / 5)
            }
        }
        XCTAssertEqual(KeyboardMergedSymbolsPolicy.punctuationWidth(available: 386, spacing: 5, deleteWidth: 42), 63.8, accuracy: 0.00001)
        XCTAssertEqual(KeyboardMergedSymbolsPolicy.punctuationWidth(available: 0, spacing: 5, deleteWidth: 42), 0)
    }

    func testEditorCanvasAndSearchUseTheSameMergedInventoryAndKeepUndrawnKeys() throws {
        let arrangement = Arrangement.standard(for: .english)
        XCTAssertNil(MainKeyboardSymbolLayer(section: .letters, arrangement: arrangement, isPad: false, mergedSymbols: true))
        for section in [MainKeyboardSection.numbers, .symbols] {
            let layer = try XCTUnwrap(MainKeyboardSymbolLayer(section: section, arrangement: arrangement, isPad: false, mergedSymbols: true))
            XCTAssertEqual(layer.section, .symbols)
            XCTAssertEqual(layer.rows.map(\.count), [10, 10, 10, 6])
            XCTAssertEqual(layer.rows.last?.last, .delete)
            XCTAssertEqual(layer.canvasKeyHeight, 44)
            XCTAssertEqual(layer.switchKeyTitle, "")
            XCTAssertFalse(layer.rows.flatMap { $0 }.contains { if case .switchKey = $0 { return true }; return false })
            XCTAssertEqual(layer.keyIDs, KeyboardMergedSymbolsPolicy.rows.flatMap { $0 }.compactMap(Settings.identifier(forCharacter:)))
        }
        for alphabet in KeyboardAlphabet.catalog {
            let groups = MainKeyboardKeySearch.groups(alphabet: alphabet, arrangement: .standard(for: alphabet), isPad: false, mergedSymbols: true)
            XCTAssertEqual(groups.map(\.section), [.letters, .symbols])
            XCTAssertEqual(Set(groups[0].keys.filter { $0.kind == .digit }.map(\.id)), Set(Arrangement.digits.map { "digit." + $0 }))
            XCTAssertTrue(groups[1].keys.allSatisfy { $0.kind == .character })
            let expectedSymbols = Set(Settings.descriptors.filter { $0.kind == .character }.map(\.id))
            XCTAssertEqual(Set(groups[1].keys.map(\.id)), expectedSymbols)
            let allIDs = groups.flatMap { $0.keys.map(\.id) }
            XCTAssertEqual(Set(allIDs).count, allIDs.count)
            XCTAssertEqual(MainKeyboardKeySearch.search("digit.5", alphabet: alphabet, arrangement: .standard(for: alphabet), isPad: false, mergedSymbols: true).map(\.section), [.letters])
            XCTAssertEqual(MainKeyboardKeySearch.search("$", alphabet: alphabet, arrangement: .standard(for: alphabet), isPad: false, mergedSymbols: true).map(\.section), [.symbols])
            XCTAssertEqual(MainKeyboardKeySearch.search("§", alphabet: alphabet, arrangement: .standard(for: alphabet), isPad: false, mergedSymbols: true).map(\.section), [.symbols])
            XCTAssertTrue(MainKeyboardKeySearch.search("no-such-key", alphabet: alphabet, arrangement: .standard(for: alphabet), isPad: false, mergedSymbols: true).isEmpty)
        }
        let fallback = MainKeyboardKeySearch.groups(alphabet: .english, arrangement: arrangement, isPad: false)
        XCTAssertEqual(fallback.map(\.section), [.letters, .numbers, .symbols])
    }

    func testCustomizedSymbolGesturesAndScriptAdditionsSurvivePresentationOnlyMerge() throws {
        var settings = Settings.Snapshot.defaults
        let id = try XCTUnwrap(Settings.identifier(forCharacter: "$"))
        for gesture in Settings.Gesture.allCases {
            settings = try XCTUnwrap(settings.updating(["★"], for: id, gesture: gesture))
        }
        let before = settings
        XCTAssertTrue(eligible(settings))
        for merged in [true, false, true] {
            _ = MainKeyboardSymbolLayer(section: .symbols, arrangement: .standard(for: .english), isPad: false, mergedSymbols: merged)
            _ = MainKeyboardKeySearch.groups(alphabet: .english, arrangement: .standard(for: .english), isPad: false, mergedSymbols: merged)
            for gesture in Settings.Gesture.allCases { XCTAssertEqual(settings.candidates(for: id, gesture: gesture), ["★"]) }
        }
        XCTAssertEqual(settings, before)
        for (layout, key, expected) in [("ar", "?", "؟"), ("ar", ",", "،"), ("ar", ";", "؛"), ("he", "$", "₪")] {
            var state = KeyboardTypingState()
            state.selectAlphabet(try XCTUnwrap(KeyboardAlphabet.alphabet(id: layout)))
            state.selectLayout(.symbols)
            XCTAssertEqual(KeyboardVariantPolicy.holdVariants(for: key, state: state).first, expected)
        }
    }
}

#if os(macOS)
extension MergedSymbolsTests {
    /// Source wiring complements the core behavior checks; it is not an iOS
    /// screenshot/gesture execution claim.
    func testRuntimeAndEditorShareEligibilityAndRetainStaleActionAndCanvasGuards() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let runtime = try String(contentsOf: root.appendingPathComponent("Keyboard/KeyboardViewController.swift"), encoding: .utf8)
        let editor = try String(contentsOf: root.appendingPathComponent("App/MainKeyboardEditorView.swift"), encoding: .utf8)
        for source in [runtime, editor] {
            XCTAssertTrue(source.contains("KeyboardMergedSymbolsPolicy.isEligible(settings:"))
            XCTAssertTrue(source.contains("KeyboardMergedSymbolsPolicy.punctuationWidth(available:"))
            XCTAssertFalse(source.contains("UIScreen.main"))
        }
        for required in ["mergedSymbols: model.mergesSymbols", "let mergedSymbols = model.mergesSymbols",
                         "self?.model.mergesSymbols == mergedSymbols", "self?.model.typingState.layout == captured.layout",
                         "self?.model.keySettings == settings", "self?.model.padLayout == padLayout",
                         "self?.model.typingAuxiliaryRowVisible.map", "self?.model.typingWidePadVisible.map",
                         "self?.model.typingANSIPadVisible.map", "KeyboardABCRendering(alphabet: catalogAlphabet",
                         "typing.state.layout == .letters && abc.arranged",
                         "index == 2 && (typing.state.layout == .letters || !mergedSymbols)",
                         "index == (mergedSymbols && typing.state.layout == .symbols ? 3 : 2)",
                         "label: letters ? \"Letters\" : model.mergesSymbols ? \"Symbols\" : \"Numbers\"",
                         "fontSize: 13", "KeyboardMergedSymbolsPolicy.page(requested, merged: mergesSymbols)",
                         "KeyboardMergedSymbolsPolicy.page(typingState.layout, merged: merged)",
                         "normalKeyHeight: conversionVisible ? compositionPlan.mergeNormalKeyHeight : metrics.typingKeyHeight",
                         "KeyboardCompositionLayoutPolicy.plan(", "actualGrantedHeight: view.bounds.height",
                         "if changed { invalidateInputMode() }"] {
            XCTAssertTrue(runtime.contains(required), "Runtime must retain integration: \(required)")
        }
        let refreshStart = try XCTUnwrap(runtime.range(of: "    private func refreshMergedSymbols() {"))
        let refreshEnd = try XCTUnwrap(runtime.range(of: "    @Published var typingKeyHeight:", range: refreshStart.upperBound..<runtime.endIndex))
        let refresh = String(runtime[refreshStart.lowerBound..<refreshEnd.lowerBound])
        XCTAssertFalse(refresh.contains("typingState.shift"), "Momentary Shift cannot change the page set")
        XCTAssertTrue(refresh.contains("invalidateInputMode()"), "Retiring a page cancels held keys")
        for required in ["mergedSymbols ? [.letters, .symbols] : MainKeyboardSection.allCases",
                         "mergedSymbols && section == .symbols ? \"Symbols\" : section.accessibilityLabel",
                         ".onChange(of: mergedSymbols)", "if merged && section == .numbers { show(.symbols) }",
                         "mergedSymbols: mergedSymbols", "ForEach(sections, id:",
                         "guard section == capturedSection, mergedSymbols == merged else { return }",
                         "Choose letters or symbols to edit their keys.",
                         "ABC already types all ten digits, so the symbols fit on one page. Separate 123 and #+= pages return if ABC no longer types every digit or the layout no longer fits. Saved key choices stay unchanged.",
                         ".font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)",
                         "VStack(alignment: .leading, spacing: 8)",
                         "let current = keys.snapshot.effectiveArrangement(for: currentAlphabet)",
                         "let resolvedRows = current.resolvedRows", "place(entry, current: current, alphabet: currentAlphabet, fingerprint: fingerprint)",
                         "currentFingerprint: { dragFingerprint }", "preservesDiacriticsPlace"] {
            XCTAssertTrue(editor.contains(required), "Editor must retain integration: \(required)")
        }
        let heightStart = try XCTUnwrap(runtime.range(of: "    private func updateKeyboardHeight(animated: Bool = false) {"))
        let heightEnd = try XCTUnwrap(runtime.range(of: "    private func applyKeyboardHeight(", range: heightStart.upperBound..<runtime.endIndex))
        let height = String(runtime[heightStart.lowerBound..<heightEnd.lowerBound])
        XCTAssertFalse(height.contains("typingState.layout"), "Switching pages must not change the outer row budget")
    }
}
#endif
