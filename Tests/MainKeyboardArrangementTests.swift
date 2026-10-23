import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class MainKeyboardArrangementTests: XCTestCase {
    typealias Arrangement = MainKeyboardArrangement

    func testStandardRowsPutShiftAndDeleteAroundTheLastRow() throws {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.standard(for: english)
        XCTAssertTrue(standard.isValid(for: english))
        XCTAssertEqual(standard.layout, "kkkkkkkkkk/kkkkkkkkk/kkkkkkkkk")
        XCTAssertEqual(standard.rows.last?.first, .key(Arrangement.shift))
        XCTAssertEqual(standard.rows.last?.last, .key(Arrangement.delete))
        XCTAssertEqual(standard.letterRows, english.rows)
        XCTAssertEqual(english.arranged(standard.letterRows).rows, english.rows)
        XCTAssertEqual(english.arranged([["q"]]).rows, english.rows, "Anything but all the letters keeps the standard rows")
        XCTAssertEqual(english.arranged(nil).rows, english.rows)
    }

    func testOnlyCompleteArrangementsInThreeRowsAreValid() {
        let english = KeyboardAlphabet.english
        let standard = Arrangement.standard(for: english)
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
        for layout in ["kkkkkkkkkk/kkkkkkkkk/kkkkkkkk", "kkkkkkkkkk/kkkkkkkkk/kkkk/kkkkk", "kkkkkkkkkk/kkkkkkkkk/g/kkkkkkkkk", "x"] {
            var bad = standard
            bad.layout = layout
            XCTAssertFalse(bad.isValid(for: english), layout)
        }
        var twoRows = standard
        twoRows.layout = "kkkkkkkkkkkkkk/kkkkkkkkkkkkkk"
        XCTAssertTrue(twoRows.isValid(for: english))
        XCTAssertEqual(twoRows.letterRows.count, 3, "Typing always gets three rows")
        XCTAssertTrue(twoRows.letterRows[2].isEmpty)
        var invalid = standard
        invalid.layout = ""
        XCTAssertTrue(invalid.rows.isEmpty)
    }

    func testFunctionKeysAreWiderAndEveryRowFits() {
        let standard = Arrangement.standard(for: .english)
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
}
