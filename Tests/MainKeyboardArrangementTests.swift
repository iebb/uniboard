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
}
