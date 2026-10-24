import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class EditorReorderTests: XCTestCase {
    typealias Position = SymbolPageLayout.Position
    typealias Layout = SymbolPageLayout
    typealias Arrangement = MainKeyboardArrangement

    private func p(_ row: Int, _ index: Int) -> Position { Position(row: row, index: index) }

    // MARK: Generic rows

    func testMovesBeforeTheTargetWithinARowInBothDirections() {
        let rows = [["a", "b", "c", "d"]]
        XCTAssertEqual(EditorReorder.move(rows, from: p(0, 0), to: p(0, 2), removesEmptyRows: true), [["b", "a", "c", "d"]])
        XCTAssertEqual(EditorReorder.move(rows, from: p(0, 3), to: p(0, 1), removesEmptyRows: true), [["a", "d", "b", "c"]])
        XCTAssertEqual(EditorReorder.move(rows, from: p(0, 0), to: p(0, 4), removesEmptyRows: true), [["b", "c", "d", "a"]],
                       "The row's count is its end")
        XCTAssertEqual(EditorReorder.move(rows, from: p(0, 3), to: p(0, 0), removesEmptyRows: true), [["d", "a", "b", "c"]])
        XCTAssertEqual(EditorReorder.landing(from: p(0, 0), to: p(0, 2), rowCounts: [4], removesEmptyRows: true), p(0, 1))
        XCTAssertEqual(EditorReorder.landing(from: p(0, 3), to: p(0, 1), rowCounts: [4], removesEmptyRows: true), p(0, 1))
    }

    func testMovesAcrossRowsAndDropsOnlyRowsItEmpties() {
        let rows = [["a"], ["b", "c"]]
        XCTAssertEqual(EditorReorder.move(rows, from: p(0, 0), to: p(1, 1), removesEmptyRows: true), [["b", "a", "c"]])
        XCTAssertEqual(EditorReorder.landing(from: p(0, 0), to: p(1, 1), rowCounts: [1, 2], removesEmptyRows: true), p(0, 1),
                       "The emptied row goes, so the next row takes its place")
        XCTAssertEqual(EditorReorder.move(rows, from: p(0, 0), to: p(1, 1), removesEmptyRows: false), [[], ["b", "a", "c"]])
        XCTAssertEqual(EditorReorder.landing(from: p(0, 0), to: p(1, 1), rowCounts: [1, 2], removesEmptyRows: false), p(1, 1))
        XCTAssertEqual(EditorReorder.move(rows, from: p(1, 1), to: p(0, 0), removesEmptyRows: true), [["c", "a"], ["b"]])
        XCTAssertEqual(EditorReorder.move([[], ["x"]], from: p(1, 0), to: p(0, 0), removesEmptyRows: false), [["x"], []],
                       "An empty row takes an item at its start")
    }

    func testRefusesPlacesOutsideTheRows() {
        let rows = [["a", "b"], ["c"]]
        for (source, destination) in [(p(0, 2), p(0, 0)), (p(0, -1), p(0, 0)), (p(2, 0), p(0, 0)), (p(-1, 0), p(0, 0)),
                                      (p(0, 0), p(0, 3)), (p(0, 0), p(1, 2)), (p(0, 0), p(2, 0)), (p(0, 0), p(0, -1))] {
            XCTAssertNil(EditorReorder.move(rows, from: source, to: destination, removesEmptyRows: true), "\(source) → \(destination)")
        }
        XCTAssertNil(EditorReorder.move([[String]](), from: p(0, 0), to: p(0, 0), removesEmptyRows: true))
    }

    /// Every possible move keeps every item exactly once, and the moved item
    /// sits where `landing` says.
    func testEveryMoveNeitherDuplicatesNorLosesItems() {
        let shapes: [[[String]]] = [[["a", "b", "c"], ["d"], ["e", "f"]], [["a"]], [["a", "b"], [], ["c"]]]
        for rows in shapes {
            let counts = rows.map(\.count)
            for removes in [true, false] {
                for (row, items) in rows.enumerated() {
                    for index in items.indices {
                        for target in rows.indices {
                            for place in 0...rows[target].count {
                                let source = p(row, index), destination = p(target, place)
                                guard let moved = EditorReorder.move(rows, from: source, to: destination, removesEmptyRows: removes) else {
                                    XCTFail("\(source) → \(destination) is a valid place"); continue
                                }
                                XCTAssertEqual(moved.flatMap { $0 }.sorted(), rows.flatMap { $0 }.sorted())
                                let landing = EditorReorder.landing(from: source, to: destination, rowCounts: counts, removesEmptyRows: removes)
                                XCTAssertEqual(moved[landing.row][landing.index], rows[row][index], "\(source) → \(destination)")
                                if !removes { XCTAssertEqual(moved.count, rows.count) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Pages

    func testPageMoveReordersKeysWithTheirSlotsAndLandsWhereTheKeyIs() throws {
        let layout = try XCTUnwrap(Layout("kgk/hkk"))
        let move = try XCTUnwrap(EditorReorder.page(layout, from: p(0, 0), to: p(1, 3)))
        XCTAssertTrue(move.changesValue)
        XCTAssertEqual(move.value.layout.text, "gk/hkkk")
        XCTAssertEqual(move.value.keyMove, .init(from: 0, to: 3))
        XCTAssertEqual(move.landing, p(1, 3))
        XCTAssertEqual(move.value.layout.keyIndex(at: move.landing), 3)
        XCTAssertEqual(layout.text, "kgk/hkk", "The proposal never changes the arrangement it was computed from")

        let gap = try XCTUnwrap(EditorReorder.page(layout, from: p(0, 1), to: p(0, 0)))
        XCTAssertEqual(gap.value.layout.text, "gkk/hkk")
        XCTAssertNil(gap.value.keyMove, "Gaps move without reordering keys")
    }

    func testPageMoveIntoAnEarlierRowFromARowOfItsOwnRemovesThatRow() throws {
        let layout = try XCTUnwrap(Layout("kk/k/kk"))
        let move = try XCTUnwrap(EditorReorder.page(layout, from: p(1, 0), to: p(2, 1)))
        XCTAssertEqual(move.value.layout.text, "kk/kkk")
        XCTAssertEqual(move.landing, p(1, 1))
        XCTAssertEqual(move.value.layout.item(at: move.landing), .key)
        XCTAssertEqual(move.value.keyMove, .init(from: 2, to: 3), "It now follows the key it was dropped after")
        XCTAssertEqual(move.value.layout.keyIndex(at: move.landing), 3)
    }

    func testPageSelfDropAndAlikeSlotsAreNotChanges() throws {
        let layout = try XCTUnwrap(Layout("kkk"))
        for destination in [p(0, 1), p(0, 2)] {
            let move = try XCTUnwrap(EditorReorder.page(layout, from: p(0, 1), to: destination))
            XCTAssertFalse(move.changesValue, "Dropping a key just before or after itself saves nothing")
            XCTAssertEqual(move.landing, p(0, 1))
        }
        let swap = try XCTUnwrap(EditorReorder.page(layout, from: p(0, 0), to: p(0, 2)))
        XCTAssertTrue(swap.changesValue, "Same text, but the keys still reorder")
        XCTAssertEqual(swap.value.keyMove, .init(from: 0, to: 1))
    }

    func testPageRefusesOverfullRowsAndMissingPlaces() throws {
        let layout = try XCTUnwrap(Layout(String(repeating: "k", count: 16) + "/kk"))
        XCTAssertNil(EditorReorder.page(layout, from: p(1, 0), to: p(0, 0)), "A full row takes no more")
        XCTAssertNotNil(EditorReorder.page(layout, from: p(0, 0), to: p(1, 0)))
        XCTAssertNil(EditorReorder.page(layout, from: p(1, 2), to: p(0, 0)))
        XCTAssertNil(EditorReorder.page(layout, from: p(1, 0), to: p(1, 3)))
        XCTAssertNil(EditorReorder.page(layout, from: p(1, 0), to: p(2, 0)))
    }

    func testPageRefusesMovesWhoseGapsTheKeyboardWouldDrop() throws {
        let trailing = try XCTUnwrap(Layout("kgk"))
        XCTAssertNil(EditorReorder.page(trailing, from: p(0, 1), to: p(0, 3)),
                     "A gap after the last key would be saved as \"kkg\" but shown as \"kk\"")
        XCTAssertEqual(EditorReorder.page(trailing, from: p(0, 1), to: p(0, 0))?.value.layout.text, "gkk")

        let gapRow = try XCTUnwrap(Layout("kk/gk"))
        for place in 0...2 {
            XCTAssertNil(EditorReorder.page(gapRow, from: p(1, 1), to: p(0, place)),
                         "Taking the last key leaves a row of only a gap, which would vanish")
        }
        XCTAssertEqual(EditorReorder.page(gapRow, from: p(1, 0), to: p(0, 1))?.value.layout.text, "kgk/k",
                       "The gap itself may still move up")
        XCTAssertNil(EditorReorder.page(try XCTUnwrap(Layout("k/gk/k")), from: p(1, 1), to: p(0, 1)),
                     "Nor a row of gaps between rows of keys")
    }

    /// Every accepted page move saves exactly what the keyboard then draws,
    /// keeps its key slots, and moves tile identities to the same shape.
    func testEveryAcceptedPageMoveIsKeptAsSaved() throws {
        for text in ["kgk/hkk", "kk/gk", "kkk/kgk", "hk/gkg/k", "k/hgk", "gkh/k"] {
            let layout = try XCTUnwrap(Layout(text))
            XCTAssertTrue(EditorReorder.isStable(layout, keyCount: layout.keySlots), text)
            for row in layout.rows.indices {
                for index in layout.rows[row].indices {
                    for target in layout.rows.indices {
                        for place in 0...layout.rows[target].count {
                            guard let move = EditorReorder.page(layout, from: p(row, index), to: p(target, place)) else { continue }
                            let next = move.value.layout
                            XCTAssertEqual(next.fitted(keyCount: next.keySlots), next, "\(text): \(p(row, index)) → \(p(target, place))")
                            XCTAssertEqual(next.keySlots, layout.keySlots)
                            var ids = EditorTileIdentities(rowCounts: layout.rows.map(\.count))
                            XCTAssertTrue(ids.move(from: move.source, to: move.destination, removesEmptyRows: true))
                            XCTAssertEqual(ids.rows.map(\.count), next.rows.map(\.count), "Identities match the saved rows")
                        }
                    }
                }
            }
        }
    }

    /// "kkk/kgk" with the gap selected, then that row's keys dragged out one
    /// by one: the selection follows the gap while it is kept, and the move
    /// that would make the row vanish is refused, so nothing points past it.
    func testDraggingARowsKeysOutNeverLeavesTheSelectionPastItsRow() throws {
        var layout = try XCTUnwrap(Layout("kkk/kgk"))
        var ids = EditorTileIdentities(rowCounts: layout.rows.map(\.count))
        var selection: Position? = p(1, 1)
        func drag(_ source: Position, to destination: Position) -> Bool {
            guard let move = EditorReorder.page(layout, from: source, to: destination), move.changesValue else { return false }
            let kept = selection.flatMap(ids.id(at:))
            layout = move.value.layout
            ids.move(from: move.source, to: move.destination, removesEmptyRows: true)
            selection = EditorReorder.selection(kept.flatMap(ids.position(of:)), in: layout)
            return true
        }

        XCTAssertTrue(drag(p(1, 0), to: p(0, 3)))
        XCTAssertEqual(layout.text, "kkkk/gk")
        XCTAssertEqual(selection, p(1, 0), "The selection follows the gap")
        XCTAssertEqual(layout.item(at: try XCTUnwrap(selection)), .gap)

        for place in 0...4 { XCTAssertFalse(drag(p(1, 1), to: p(0, place)), "The row's last key keeps its gap on screen") }
        XCTAssertEqual(layout.text, "kkkk/gk", "A refused drop saves nothing")
        let selected = try XCTUnwrap(selection)
        XCTAssertNotNil(layout.item(at: selected))
        XCTAssertLessThan(selected.index, layout.rows[selected.row].count, "Move Right reads the selected row safely")
    }

    func testASelectionIsKeptOnlyOnAnItem() throws {
        let layout = try XCTUnwrap(Layout("kkkkk/gk"))
        XCTAssertEqual(EditorReorder.selection(p(1, 1), in: layout), p(1, 1))
        XCTAssertNil(EditorReorder.selection(p(1, 2), in: layout), "Past the row's end")
        XCTAssertNil(EditorReorder.selection(p(2, 0), in: layout), "A row that is gone")
        XCTAssertNil(EditorReorder.selection(p(0, -1), in: layout))
        XCTAssertNil(EditorReorder.selection(nil, in: layout))
    }

    // MARK: Main keyboard

    private func keyRows(_ arrangement: Arrangement) -> [[String]] {
        arrangement.rows.map { $0.compactMap { if case .key(let key) = $0 { return key }; return nil } }
    }

    func testMainKeyboardMovesDigitsLikeAnyOtherKeyWithinFourRows() throws {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.standard(for: english)
        // A digit drags down among the letters, and the number row keeps the rest.
        let down = try XCTUnwrap(EditorReorder.mainKeyboard(standard, from: p(0, 0), to: p(1, 0), alphabet: english))
        XCTAssertEqual(keyRows(down.value)[0].first, "2")
        XCTAssertEqual(keyRows(down.value)[1].prefix(2), ["1", "q"])
        XCTAssertTrue(down.value.isValid(for: english))
        // A letter can join the number row.
        let up = try XCTUnwrap(EditorReorder.mainKeyboard(standard, from: p(1, 0), to: p(0, 10), alphabet: english))
        XCTAssertEqual(keyRows(up.value)[0].last, "q")
        // Every move keeps four rows at most and each digit once.
        let places = try XCTUnwrap(standard.places)
        for target in places.rows.indices {
            for place in 0...places.rows[target].count {
                guard let move = EditorReorder.mainKeyboard(standard, from: p(0, 3), to: p(target, place), alphabet: english) else { continue }
                XCTAssertLessThanOrEqual(move.value.places?.rows.count ?? 9, Arrangement.maximumRows)
                XCTAssertEqual(move.value.keys.filter(Arrangement.isDigit).sorted(), Arrangement.digits.sorted())
            }
        }
    }

    func testMainKeyboardMovesKeysAndKeepsAValidKeyboard() throws {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.letters(for: english)
        let move = try XCTUnwrap(EditorReorder.mainKeyboard(standard, from: p(0, 0), to: p(0, 2), alphabet: english))
        XCTAssertEqual(keyRows(move.value)[0].prefix(3), ["w", "q", "e"])
        XCTAssertEqual(move.landing, p(0, 1))
        XCTAssertTrue(move.value.isValid(for: english))

        let across = try XCTUnwrap(EditorReorder.mainKeyboard(standard, from: p(2, 0), to: p(0, 10), alphabet: english))
        XCTAssertEqual(keyRows(across.value)[0].last, Arrangement.shift, "Shift moves to the end of the first row")
        XCTAssertEqual(across.value.layout, "kkkkkkkkkkk/kkkkkkkkk/kkkkkkkk")

        let same = try XCTUnwrap(EditorReorder.mainKeyboard(standard, from: p(1, 4), to: p(1, 5), alphabet: english))
        XCTAssertFalse(same.changesValue)
        XCTAssertEqual(same.value, standard)
    }

    func testMainKeyboardDragsOnlyKeysAndRefusesBrokenArrangements() throws {
        let english = KeyboardAlphabet.english
        var gapped = Arrangement.letters(for: english)
        gapped.layout = "g" + gapped.layout
        XCTAssertTrue(gapped.isValid(for: english))
        XCTAssertFalse(EditorReorder.canDragMainKeyboardItem(at: p(0, 0), in: gapped))
        XCTAssertTrue(EditorReorder.canDragMainKeyboardItem(at: p(0, 1), in: gapped))
        XCTAssertFalse(EditorReorder.canDragMainKeyboardItem(at: p(5, 0), in: gapped))

        var broken = Arrangement.letters(for: english)
        broken.keys.removeLast()
        XCTAssertNil(EditorReorder.mainKeyboard(broken, from: p(0, 0), to: p(0, 2), alphabet: english), "A keyboard missing a key is not moved")
        XCTAssertNil(EditorReorder.mainKeyboard(Arrangement.letters(for: english), from: p(0, 10), to: p(0, 0), alphabet: english))
    }

    func testEveryMainKeyboardMoveKeepsEveryKeyOnce() throws {
        let english = KeyboardAlphabet.english
        var standard = Arrangement.letters(for: english)
        standard.keys.insert(Arrangement.tab, at: 0)
        standard.layout = "kh" + standard.layout
        XCTAssertTrue(standard.isValid(for: english))
        let places = try XCTUnwrap(standard.places)
        var accepted = 0
        for row in places.rows.indices {
            for index in places.rows[row].indices where places.rows[row][index] == .key {
                let key = keyRows(standard)[row][places.rows[row].prefix(index).filter { $0 == .key }.count]
                for target in places.rows.indices {
                    for place in 0...places.rows[target].count {
                        guard let move = EditorReorder.mainKeyboard(standard, from: p(row, index), to: p(target, place), alphabet: english) else { continue }
                        accepted += 1
                        XCTAssertTrue(move.value.isValid(for: english))
                        XCTAssertEqual(move.value.keys.sorted(), standard.keys.sorted())
                        let landed = try XCTUnwrap(move.value.places?.keyIndex(at: move.landing))
                        XCTAssertEqual(move.value.keys[landed], key, "\(key) lands where its line was")
                    }
                }
            }
        }
        XCTAssertGreaterThan(accepted, 500)
    }

    // MARK: Layer choices

    func testChoicesMoveWithinAndBetweenLayersWithoutDuplicates() throws {
        let rows = [["Q"], ["1", "2", "3"], ["a"], []]
        let within = try XCTUnwrap(EditorReorder.choices(rows, from: p(1, 2), to: p(1, 0), locked: [0], maximum: 16))
        XCTAssertEqual(within.value[1], ["3", "1", "2"])
        let across = try XCTUnwrap(EditorReorder.choices(rows, from: p(1, 0), to: p(2, 1), locked: [0], maximum: 16))
        XCTAssertEqual(across.value, [["Q"], ["2", "3"], ["a", "1"], []])
        XCTAssertEqual(across.landing, p(2, 1))
        let empty = try XCTUnwrap(EditorReorder.choices(rows, from: p(2, 0), to: p(3, 0), locked: [0], maximum: 16))
        XCTAssertEqual(empty.value, [["Q"], ["1", "2", "3"], [], ["a"]], "An emptied layer stays, turned off")

        XCTAssertNil(EditorReorder.choices([["a", "b"], ["a"]], from: p(0, 0), to: p(1, 0), maximum: 16),
                     "A layer refuses a choice it already has, leaving both unchanged")
        XCTAssertNil(EditorReorder.choices(rows, from: p(0, 0), to: p(1, 0), locked: [0], maximum: 16), "The key's own output does not drag")
        XCTAssertNil(EditorReorder.choices(rows, from: p(1, 0), to: p(0, 1), locked: [0], maximum: 16), "Nor take a choice")
        XCTAssertNil(EditorReorder.choices([["x"], ["a", "b"]], from: p(0, 0), to: p(1, 0), maximum: 2), "A full layer takes no more")
        XCTAssertNotNil(EditorReorder.choices([["a", "b"]], from: p(0, 0), to: p(0, 2), maximum: 2), "Within a full layer it still moves")
        XCTAssertNil(EditorReorder.choices(rows, from: p(1, 3), to: p(2, 0), locked: [0], maximum: 16))
        XCTAssertNil(EditorReorder.choices(rows, from: p(1, 0), to: p(2, 2), locked: [0], maximum: 16))
        let still = try XCTUnwrap(EditorReorder.choices(rows, from: p(1, 1), to: p(1, 2), locked: [0], maximum: 16))
        XCTAssertFalse(still.changesValue)
    }

    // MARK: Drag sessions

    func testHoverMarksOnlyValidPlacesAndNeverChangesAnything() {
        var state = EditorDragState()
        let token = UUID()
        XCTAssertEqual(state.begin(at: p(0, 1), fingerprint: "v1", token: token), token)
        XCTAssertNil(state.begin(at: p(0, 2), fingerprint: "v1"), "One drag at a time")
        XCTAssertEqual(state.source, p(0, 1))

        XCTAssertTrue(state.hover(p(0, 3), token: token, fingerprint: "v1") { $0 == p(0, 1) })
        XCTAssertEqual(state.target, p(0, 3))
        XCTAssertTrue(state.hover(p(1, 0), token: token, fingerprint: "v1") { _ in true })
        XCTAssertEqual(state.target, p(1, 0), "The line jumps to the new place")
        XCTAssertFalse(state.hover(p(1, 0), token: token, fingerprint: "v1") { _ in false })
        XCTAssertNil(state.target, "An invalid place shows no line")
        XCTAssertFalse(state.hover(p(0, 0), token: UUID(), fingerprint: "v1") { _ in true }, "Another drag's item")
        XCTAssertFalse(state.hover(p(0, 0), token: nil, fingerprint: "v1") { _ in true }, "An external item")
        XCTAssertFalse(state.hover(p(0, 0), token: token, fingerprint: "v2") { _ in true }, "The arrangement changed under the drag")
        XCTAssertNil(state.target)

        XCTAssertTrue(state.hover(p(0, 0), token: token, fingerprint: "v1") { _ in true })
        state.leave(p(1, 1))
        XCTAssertEqual(state.target, p(0, 0), "Leaving another place keeps this line")
        state.leave(p(0, 0))
        XCTAssertNil(state.target)
    }

    func testCancelRestoresIdleAndADropIsCommittedOnce() throws {
        var state = EditorDragState()
        let token = try XCTUnwrap(state.begin(at: p(0, 0), fingerprint: "v1"))
        state.hover(p(0, 2), token: token, fingerprint: "v1") { _ in true }
        state.cancel()
        XCTAssertEqual(state, EditorDragState(), "Nothing of a cancelled drag lingers")
        XCTAssertNil(state.finish(token: token, fingerprint: "v1"), "A cancelled drag cannot drop")

        let second = try XCTUnwrap(state.begin(at: p(0, 0), fingerprint: "v1"))
        XCTAssertEqual(state.finish(token: second, fingerprint: "v1"), p(0, 0))
        XCTAssertNil(state.finish(token: second, fingerprint: "v1"), "A drop is accepted once")
        XCTAssertFalse(state.isActive)

        let stale = try XCTUnwrap(state.begin(at: p(0, 0), fingerprint: "v1"))
        XCTAssertNil(state.finish(token: stale, fingerprint: "v2"), "A stale drop is refused")
        XCTAssertFalse(state.isActive, "and still ends the drag")
    }

    /// An editor wired as the views are: a store written only by a committed,
    /// changing drop. Cancelled, invalid, stale, foreign and self drops leave
    /// the saved text exactly as it was.
    func testOnlyACommittedDropWritesAndThenOnlyOnce() throws {
        var saved = "kgk/hkk"
        var writes = 0
        var state = EditorDragState()
        var proposals = 0
        func drop(_ token: UUID?, on destination: Position, fingerprint: String? = nil) {
            let layout = Layout(saved)!
            let move = state.drop(on: destination, token: token, fingerprint: fingerprint ?? saved) { source, destination in
                proposals += 1
                return EditorReorder.page(layout, from: source, to: destination)
            }
            if let move, move.changesValue { saved = move.value.layout.text; writes += 1 }
        }
        let original = saved

        var token = state.begin(at: p(0, 0), fingerprint: saved)
        for place in [p(0, 2), p(1, 0), p(1, 3), p(0, 1)] { state.hover(place, token: token, fingerprint: saved) { _ in true } }
        state.cancel()
        drop(token, on: p(1, 3))
        XCTAssertEqual(saved, original); XCTAssertEqual(writes, 0); XCTAssertEqual(proposals, 0)

        token = state.begin(at: p(0, 0), fingerprint: saved)
        drop(token, on: p(9, 0))
        XCTAssertEqual(saved, original, "An invalid place writes nothing"); XCTAssertEqual(writes, 0)

        token = state.begin(at: p(0, 0), fingerprint: saved)
        drop(UUID(), on: p(1, 3))
        XCTAssertEqual(saved, original, "Another editor's item writes nothing"); XCTAssertFalse(state.isActive)

        token = state.begin(at: p(0, 0), fingerprint: saved)
        drop(token, on: p(1, 3), fingerprint: "changed")
        XCTAssertEqual(saved, original, "A stale drop writes nothing")

        token = state.begin(at: p(0, 0), fingerprint: saved)
        drop(token, on: p(0, 1))
        XCTAssertEqual(saved, original, "Dropping on itself writes nothing"); XCTAssertEqual(writes, 0)

        token = state.begin(at: p(0, 0), fingerprint: saved)
        drop(token, on: p(1, 3))
        drop(token, on: p(1, 3))
        XCTAssertEqual(saved, "gk/hkkk"); XCTAssertEqual(writes, 1, "A drop is committed exactly once")
    }

    // MARK: Identities

    func testIdentitiesFollowMovesAndStayUnique() throws {
        var ids = EditorTileIdentities(rowCounts: [3, 1])
        let all = ids.rows.flatMap { $0 }
        XCTAssertEqual(Set(all).count, 4)
        let moving = try XCTUnwrap(ids.id(at: p(1, 0)))
        XCTAssertTrue(ids.move(from: p(1, 0), to: p(0, 1), removesEmptyRows: true))
        XCTAssertEqual(ids.rows.map(\.count), [4])
        XCTAssertEqual(ids.position(of: moving), p(0, 1))
        XCTAssertEqual(ids.rows.flatMap { $0 }.sorted(), all.sorted(), "No identity is duplicated or lost")
        let before = ids.rows
        ids.fit(rowCounts: [4])
        XCTAssertEqual(ids.rows, before, "The same shape keeps its identities")
        ids.fit(rowCounts: [2, 2])
        XCTAssertTrue(Set(ids.rows.flatMap { $0 }).isDisjoint(with: all), "A new shape gets new identities")
        XCTAssertFalse(ids.move(from: p(2, 0), to: p(0, 0), removesEmptyRows: true))
        XCTAssertNil(ids.id(at: p(0, 2)))
    }
}
