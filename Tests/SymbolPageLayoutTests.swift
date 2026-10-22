import XCTest
import CoreGraphics
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class SymbolPageLayoutTests: XCTestCase {
    typealias Layout = SymbolPageLayout

    func testTextRoundTripsAndRejectsUnknownEmptyOrOversizedRows() throws {
        let layout = try XCTUnwrap(Layout("kkkkk/hkkkk/gkk"))
        XCTAssertEqual(layout.text, "kkkkk/hkkkk/gkk")
        XCTAssertEqual(layout.rows.count, 3)
        XCTAssertEqual(layout.keySlots, 11)
        XCTAssertEqual(Layout.units(layout.rows[1]), 4.5)
        for invalid in ["", "/", "kk//kk", "kk/", "kkx", "KK", "k k", String(repeating: "k", count: 17),
                        Array(repeating: "k", count: 65).joined(separator: "/"), String(repeating: "k", count: 2049)] {
            XCTAssertNil(Layout(invalid), invalid)
        }
        XCTAssertNotNil(Layout(String(repeating: "k", count: 16)))
        XCTAssertNotNil(Layout(String(repeating: "h", count: 32)), "Sixteen key widths of half gaps fit")
        XCTAssertEqual(Layout.resolved("nonsense", keyCount: 3), .automatic(keyCount: 3))
        XCTAssertEqual(Layout.resolved(nil, keyCount: 23).text, "kkkkkkkkkk/kkkkkkkkkk/kkk")
        XCTAssertEqual(Layout.automatic(keyCount: 0).rows, [])
    }

    func testCellsFillSlotsInOrderAndContinueInRowsOfTen() throws {
        let layout = try XCTUnwrap(Layout("hkkk/gkk"))
        XCTAssertEqual(layout.cells(keyCount: 5), [[.halfGap, .key(0), .key(1), .key(2)], [.gap, .key(3), .key(4)]])
        XCTAssertEqual(layout.cells(keyCount: 2), [[.halfGap, .key(0), .key(1)]], "Unused slots and keyless rows are dropped")
        XCTAssertEqual(layout.cells(keyCount: 3), [[.halfGap, .key(0), .key(1), .key(2)]], "A row of only a gap is not drawn")
        let more = layout.cells(keyCount: 17)
        XCTAssertEqual(more.count, 4)
        XCTAssertEqual(more[2], (5..<15).map(Layout.Cell.key))
        XCTAssertEqual(more[3], [.key(15), .key(16)])
        XCTAssertEqual(try XCTUnwrap(Layout("kkg")).cells(keyCount: 2), [[.key(0), .key(1)]], "Trailing gaps after the last key are dropped")
        XCTAssertEqual(layout.cells(keyCount: 0), [])
        XCTAssertEqual(layout.fitted(keyCount: 3).text, "hkkk")
        XCTAssertEqual(layout.fitted(keyCount: 6).text, "hkkk/gkk/k")
    }

    func testKeyWidthMatchesTenColumnsAndNarrowsForLongerRows() throws {
        let ten = Layout.automatic(keyCount: 10).cells(keyCount: 10)
        XCTAssertEqual(Layout.keyWidth(for: ten, available: 365, spacing: 5), 32, accuracy: 0.0001)
        XCTAssertEqual(Layout.keyWidth(for: [[.key(0)]], available: 365, spacing: 5), 32, accuracy: 0.0001, "Short rows keep ten-column keys")
        let long = try XCTUnwrap(Layout("hkkkkkkkkkkkh")).cells(keyCount: 11)
        let width = Layout.keyWidth(for: long, available: 365, spacing: 5)
        XCTAssertLessThan(width, 32)
        let half = Layout.gapWidth(.halfGap, keyWidth: width, spacing: 5)
        XCTAssertEqual(11 * width + half + 11 * 5, 365, accuracy: 0.0001, "The widest row fills the page exactly")
        XCTAssertEqual(2 * Layout.gapWidth(.halfGap, keyWidth: 30, spacing: 6) + 6, Layout.gapWidth(.gap, keyWidth: 30, spacing: 6),
                       "Two half gaps and their spacing make one full gap")
        for bad: CGFloat in [.nan, .infinity, 0, -5] { XCTAssertEqual(Layout.keyWidth(for: ten, available: bad, spacing: 5), 0) }
    }

    func testGapsAndRowBreaksEditTheArrangementWithoutTouchingKeys() throws {
        var layout = Layout.automatic(keyCount: 6)
        XCTAssertTrue(layout.breakRow(at: .init(row: 0, index: 3)))
        XCTAssertEqual(layout.text, "kkk/kkk")
        XCTAssertFalse(layout.breakRow(at: .init(row: 1, index: 0)), "A row cannot start before its first item")
        XCTAssertTrue(layout.insertGap(.halfGap, at: .init(row: 1, index: 0)))
        XCTAssertTrue(layout.insertGap(.gap, at: .init(row: 0, index: 3)))
        XCTAssertEqual(layout.text, "kkkg/hkkk")
        XCTAssertFalse(layout.insertGap(.key, at: .init(row: 0, index: 0)))
        XCTAssertFalse(layout.removeGap(at: .init(row: 0, index: 0)), "Keys are removed from the page, not the layout")
        XCTAssertTrue(layout.removeGap(at: .init(row: 0, index: 3)))
        XCTAssertFalse(layout.joinRow(0))
        XCTAssertTrue(layout.joinRow(1))
        XCTAssertEqual(layout.text, "kkkhkkk")
        var full = try XCTUnwrap(Layout(String(repeating: "k", count: 16)))
        XCTAssertFalse(full.insertGap(.halfGap, at: .init(row: 0, index: 0)), "Rows stop at sixteen key widths")
        var two = try XCTUnwrap(Layout(String(repeating: "k", count: 10) + "/" + String(repeating: "k", count: 7)))
        XCTAssertFalse(two.joinRow(1))
        XCTAssertEqual(full.keySlots, 16)
    }

    func testMovingAKeyMovesItsSlotAndReportsTheKeyReorder() throws {
        var layout = try XCTUnwrap(Layout("kkk/hkk"))
        var keyMove: Layout.KeyMove?
        XCTAssertTrue(layout.move(from: .init(row: 0, index: 0), to: .init(row: 0, index: 3), keyMove: &keyMove))
        XCTAssertEqual(layout.text, "kkk/hkk", "Alike slots keep the text")
        XCTAssertEqual(keyMove, .init(from: 0, to: 2), "but the key still moves to the end of the row")
        XCTAssertTrue(layout.move(from: .init(row: 1, index: 0), to: .init(row: 1, index: 3), keyMove: &keyMove))
        XCTAssertEqual(layout.text, "kkk/kkh")
        XCTAssertNil(keyMove, "Moving a gap reorders no keys")
        XCTAssertTrue(layout.move(from: .init(row: 1, index: 1), to: .init(row: 0, index: 0), keyMove: &keyMove))
        XCTAssertEqual(layout.text, "kkkk/kh")
        XCTAssertEqual(keyMove, .init(from: 4, to: 0))
        XCTAssertTrue(layout.move(from: .init(row: 1, index: 0), to: .init(row: 0, index: 4), keyMove: &keyMove))
        XCTAssertEqual(layout.text, "kkkkk/h")
        XCTAssertEqual(keyMove, nil, "Joining the last key onto the end keeps its place in order")
        var single = try XCTUnwrap(Layout("kk/k"))
        XCTAssertTrue(single.move(from: .init(row: 1, index: 0), to: .init(row: 0, index: 0), keyMove: &keyMove))
        XCTAssertEqual(single.text, "kkk", "A row emptied by a move goes away")
        XCTAssertEqual(keyMove, .init(from: 2, to: 0))
        XCTAssertFalse(single.move(from: .init(row: 0, index: 5), to: .init(row: 0, index: 0), keyMove: &keyMove))
        XCTAssertFalse(single.move(from: .init(row: 0, index: 0), to: .init(row: 3, index: 0), keyMove: &keyMove))
        var full = try XCTUnwrap(Layout(String(repeating: "k", count: 16) + "/k"))
        XCTAssertFalse(full.move(from: .init(row: 1, index: 0), to: .init(row: 0, index: 0), keyMove: &keyMove))
    }

    func testAddingAndRemovingKeysKeepsTheArrangement() throws {
        var layout = try XCTUnwrap(Layout("hkk/gkk"))
        layout.appendKey()
        XCTAssertEqual(layout.text, "hkk/gkkk")
        layout.removeKeySlot(0)
        XCTAssertEqual(layout.text, "hk/gkkk")
        layout.removeKeySlot(0)
        XCTAssertEqual(layout.text, "gkkk", "A row left without keys goes away")
        layout.removeKeySlot(9)
        XCTAssertEqual(layout.text, "gkkk")
        var full = Layout.automatic(keyCount: 10)
        full.appendKey()
        XCTAssertEqual(full.text, "kkkkkkkkkk/k", "A full row starts a new one")
        XCTAssertEqual(full.keyIndex(at: .init(row: 1, index: 0)), 10)
        XCTAssertNil(try XCTUnwrap(Layout("hk")).keyIndex(at: .init(row: 0, index: 0)))
    }
}
