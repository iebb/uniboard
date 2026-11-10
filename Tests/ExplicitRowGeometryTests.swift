import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class ExplicitRowGeometryTests: XCTestCase {
    typealias Row = KeyboardRow<String>
    typealias Position = SymbolPageLayout.Position
    private func row(_ text: String, _ alignment: KeyboardRowAlignment = .left) -> Row {
        Row(alignment: alignment, cells: text.map { .key(String($0)) })
    }
    func testPhysicalAlignmentsPreserveWidthsAndRoundOnlyOrigins() {
        let widths: [CGFloat] = [27.25, 27.25, 27.25, 27.25]
        let left = ExplicitRowGeometry.origins(widths: widths, available: 350, spacing: 5, alignment: .left, scale: 3)
        let center = ExplicitRowGeometry.origins(widths: widths, available: 350, spacing: 5, alignment: .center, scale: 3)
        let right = ExplicitRowGeometry.origins(widths: widths, available: 350, spacing: 5, alignment: .right, scale: 3)
        let spread = ExplicitRowGeometry.origins(widths: widths, available: 350, spacing: 5, alignment: .spaced, scale: 3)
        XCTAssertEqual(left[0], 0)
        XCTAssertEqual(center[0] + (center[3] + widths[3]), 350, accuracy: 1 / 3)
        XCTAssertEqual(right[3] + widths[3], 350, accuracy: 1 / 3)
        XCTAssertEqual(spread[0], 0)
        XCTAssertEqual(spread[3] + widths[3], 350, accuracy: 1 / 3)
        XCTAssertEqual(spread[1] - spread[0], spread[2] - spread[1], accuracy: 1 / 3)
        for x in left + center + right + spread { XCTAssertEqual(x * 3, (x * 3).rounded(), accuracy: 0.0001) }
    }
    func testSpreadIncludesGapCellsAndCentersSingleton() {
        let widths: [CGFloat] = [30, 12.5, 30, 30]
        let xs = ExplicitRowGeometry.origins(widths: widths, available: 350, spacing: 5, alignment: .spaced, scale: 2)
        let gaps = (1..<xs.count).map { xs[$0] - xs[$0 - 1] - widths[$0 - 1] }
        XCTAssertEqual(gaps[0], gaps[1], accuracy: 0.5)
        XCTAssertEqual(gaps[1], gaps[2], accuracy: 0.5)
        XCTAssertEqual(xs.last! + 30, 350, accuracy: 0.5)
        XCTAssertEqual(ExplicitRowGeometry.origins(widths: [30], available: 350, spacing: 5, alignment: .spaced, scale: 3), [160])
        XCTAssertEqual(ExplicitRowGeometry.origins(widths: [], available: 350, spacing: 5, alignment: .center, scale: 3), [])
    }
    func testFullRowsHaveIdenticalGeometryAndNoSpareWidthShrinksCells() {
        let widths: [CGFloat] = [30, 30, 30]
        let expected: [CGFloat] = [0, 35, 70]
        for alignment in KeyboardRowAlignment.allCases {
            XCTAssertEqual(ExplicitRowGeometry.origins(widths: widths, available: 100, spacing: 5, alignment: alignment, scale: 3), expected)
        }
    }
    func testSavedPhoneRowsKeepMembershipAndPhysicalEdgesAtIPadWidth() throws {
        let alignments: [KeyboardRowAlignment] = [.left, .center, .right, .spaced]
        let savedRows: [SymbolBoard.Row] = zip(["abc", "def", "ghi", "jkl"], alignments).map { text, alignment in
            let keys = text.map { SymbolBoardKey(id: String($0), text: String($0), variants: []) }
            return .init(alignment: alignment, cells: [.key(keys[0]), .halfGap, .key(keys[1]), .key(keys[2])])
        }
        let encoded = try JSONEncoder().encode(SymbolBoard(id: "phone-page", name: "Phone page", rows: savedRows))
        let saved = try JSONDecoder().decode(SymbolBoard.self, from: encoded)
        let rows = try XCTUnwrap(saved.explicitRows)
        XCTAssertEqual(rows, savedRows)
        let shapes: [[SymbolPageLayout.Cell]] = rows.map { row in
            row.cells.map { $0 == .halfGap ? .halfGap : .key(0) }
        }
        // Render exactly the persisted iPhone rows at an iPad keyboard width:
        // no ANSI/wide-layout projection or automatic row fitting is involved.
        let viewports: [(CGFloat, CGFloat, CGFloat)] = [(386, 5, 3), (1008, 7, 2)]
        for (available, spacing, scale) in viewports {
            let keyWidth = SymbolPageLayout.keyWidth(for: shapes, available: available, spacing: spacing)
            for (index, row) in rows.enumerated() {
                let widths = shapes[index].map { SymbolPageLayout.gapWidth($0, keyWidth: keyWidth, spacing: spacing) }
                let origins = ExplicitRowGeometry.origins(widths: widths, available: available, spacing: spacing, alignment: row.alignment, scale: scale)
                XCTAssertEqual(origins.count, row.cells.count)
                XCTAssertEqual(row.cells.compactMap(\.key).map(\.id), savedRows[index].cells.compactMap(\.key).map(\.id))
                let first = try XCTUnwrap(origins.first), last = try XCTUnwrap(origins.last) + widths.last!
                switch row.alignment {
                case .left: XCTAssertEqual(first, 0, accuracy: 1 / scale)
                case .center: XCTAssertEqual(first + last, available, accuracy: 1 / scale)
                case .right: XCTAssertEqual(last, available, accuracy: 1 / scale)
                case .spaced:
                    XCTAssertEqual(first, 0, accuracy: 1 / scale)
                    XCTAssertEqual(last, available, accuracy: 1 / scale)
                }
                XCTAssertEqual(widths[0], widths[2], accuracy: 0.0001)
                XCTAssertEqual(widths[2], widths[3], accuracy: 0.0001)
            }
        }
        XCTAssertEqual(saved.explicitRows, savedRows, "Geometry never rewrites saved membership or alignment")
    }
    func testSplitInheritsAndJoinKeepsUpperAlignment() throws {
        let rows = [row("abcd", .right), row("ef", .center)]
        let split = try XCTUnwrap(ExplicitRowEditing.applying(.split(.init(row: 0, index: 2)), to: rows, maximumRows: 64, keyUnits: { _ in 1 }))
        XCTAssertEqual(split.map(\.alignment), [.right, .right, .center])
        let joined = try XCTUnwrap(ExplicitRowEditing.applying(.join(2), to: split, maximumRows: 64, keyUnits: { _ in 1 }))
        XCTAssertEqual(joined.map(\.alignment), [.right, .right])
        XCTAssertEqual(joined[1].cells.compactMap(\.key), ["c", "d", "e", "f"])
    }
    func testMovingLastCellRemovesOnlyItsRowAndKeepsDestinationAlignment() throws {
        let rows = [row("a", .right), row("bc", .spaced), row("d", .center)]
        let next = try XCTUnwrap(ExplicitRowEditing.move(rows, from: .init(row: 0, index: 0), to: .init(row: 1, index: 1), keyUnits: { _ in 1 }))
        XCTAssertEqual(next.map(\.alignment), [.spaced, .center])
        XCTAssertEqual(next[0].cells.compactMap(\.key), ["b", "a", "c"])
    }
    func testWeightedLimitRefusesMovesGapAndJoinWithoutReflow() {
        let full = row("abcdefghijkl")
        let rows = [full, row("x")]
        XCTAssertNil(ExplicitRowEditing.move(rows, from: .init(row: 1, index: 0), to: .init(row: 0, index: 12), keyUnits: { _ in 1 }))
        XCTAssertNil(ExplicitRowEditing.applying(.halfGap(.init(row: 0, index: 0)), to: rows, maximumRows: 64, keyUnits: { _ in 1 }))
        XCTAssertNil(ExplicitRowEditing.applying(.join(1), to: rows, maximumRows: 64, keyUnits: { _ in 1 }))
        let main = Row(cells: [.key(MainKeyboardArrangement.shift), .key(MainKeyboardArrangement.delete)] + Array(repeating: .key("a"), count: 9))
        XCTAssertEqual(ExplicitRowEditing.units(main, keyUnits: ExplicitRowEditing.mainUnits), 12)
        XCTAssertNil(ExplicitRowEditing.applying(.gap(.init(row: 0, index: 0)), to: [main], maximumRows: 4, keyUnits: ExplicitRowEditing.mainUnits))
    }
    func testLegacyRepairStaysLegacyUntilAllRowsFit() throws {
        let keys = (0..<15).map { SymbolBoardKey(id: "k\($0)", text: "\($0)", variants: []) }
        let old = SymbolBoard(id: "old", name: "Old", keys: keys, layout: "kkkkkkkkkkkkkk/k")
        let first = try XCTUnwrap(EditorReorder.explicitPage(old, from: .init(row: 0, index: 0), to: .init(row: 1, index: 0)))
        XCTAssertTrue(first.value.isLegacy)
        XCTAssertEqual(first.value.resolvedRows.map { $0.cells.count }, [13, 2])
        XCTAssertEqual(first.value.keys.map(\.id), Array(keys.dropFirst().prefix(13)).map(\.id) + [keys[0].id, keys[14].id], "Intermediate repair keeps the complete moved key payload/order")
        let second = try XCTUnwrap(EditorReorder.explicitPage(first.value, from: .init(row: 0, index: 0), to: .init(row: 1, index: 0)))
        XCTAssertFalse(second.value.isLegacy)
        XCTAssertEqual(second.value.resolvedRows.map { $0.cells.count }, [12, 3])
        XCTAssertEqual(Set(second.value.keys.map(\.id)), Set(keys.map(\.id)))
    }
    func testUnchangedMoveDoesNotConvertLegacy() throws {
        let board = SymbolBoard(id: "old", name: "Old", keys: [.init(id: "a", text: "a", variants: [])], layout: nil)
        let move = try XCTUnwrap(EditorReorder.explicitPage(board, from: .init(row: 0, index: 0), to: .init(row: 0, index: 1)))
        XCTAssertFalse(move.changesValue)
    }
    func testLegacyPageRepairRejectsMoveWhoseTrailingGapWouldTrimAndLoseKeyOrder() throws {
        let texts = (0..<14).map { "long\($0)" } + ["X", "A", "B"]
        let keys = texts.enumerated().map { SymbolBoardKey(id: "k\($0.offset)", text: $0.element, variants: []) }
        let board = SymbolBoard(id: "repair", name: "Repair", keys: keys, layout: "kkkkkkkkkkkkkk/k/kgk")
        let source = Position(row: 2, index: 2), target = Position(row: 1, index: 1)
        XCTAssertNil(EditorReorder.explicitPage(board, from: source, to: target), "Legacy repair may not expose a trailing gap that its renderer would discard")
        XCTAssertEqual(board.keys.map(\.text), texts, "Refused move preserves complete key order")
        // The identical trailing-gap shape is valid once all rows fit and the
        // result is explicit: explicit rendering must not trim the gap.
        let fixed = SymbolBoard(id: "fixed", name: "Fixed", keys: Array(keys.suffix(3)), layout: "k/kgk")
        let explicit = try XCTUnwrap(EditorReorder.explicitPage(fixed, from: .init(row: 1, index: 2), to: .init(row: 0, index: 1)))
        XCTAssertFalse(explicit.value.isLegacy)
        XCTAssertEqual(explicit.value.explicitRows?.last?.cells.last, .gap)
        XCTAssertEqual(explicit.value.keys.map(\.text), ["X", "B", "A"])
    }
    func testLegacyMainRepairRejectsGapAtFinalRowEndButExplicitKeepsIt() throws {
        let letters = MainKeyboardArrangement.letters(for: .english)
        let old = MainKeyboardArrangement(keys: letters.keys, layout: "kkkkkkkkkkkkk/gkkkkkk/kkkkkkkkk")
        XCTAssertTrue(old.isValid(for: .english))
        XCTAssertNil(EditorReorder.explicitMainKeyboard(old, from: .init(row: 1, index: 0), to: .init(row: 2, index: 9), alphabet: .english), "Do not save a legacy gap that immediately vanishes")
        let repaired = MainKeyboardArrangement(keys: letters.keys, layout: "kkkkkkkkkk/gkkkkkkkkk/kkkkkkkkk")
        let move = try XCTUnwrap(EditorReorder.explicitMainKeyboard(repaired, from: .init(row: 1, index: 0), to: .init(row: 2, index: 9), alphabet: .english))
        XCTAssertFalse(move.value.isLegacy)
        XCTAssertEqual(move.value.explicitRows?.last?.cells.last, .gap)
    }

}
