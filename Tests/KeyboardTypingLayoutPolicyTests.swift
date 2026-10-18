import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardTypingLayoutPolicyTests: XCTestCase {
    func testWidePadRowsFitExactlyAtTheThresholdAndAcrossPortraitLandscapeAndHugeFiniteWidths() throws {
        for width: CGFloat in [650, 724, 752, 1008, 1350] {
            let pad = try XCTUnwrap(KeyboardTypingLayoutPolicy.padPlan(availableWidth: width, isPad: true, layout: .letters))
            XCTAssertGreaterThanOrEqual(pad.characterWidth, 44)
            XCTAssertEqual(12 * pad.characterWidth + 11 * pad.keySpacing, width, accuracy: 0.000001)
            XCTAssertEqual(9 * pad.characterWidth + pad.capsWidth + pad.returnWidth + 10 * pad.keySpacing, width, accuracy: 0.000001)
            XCTAssertEqual(9 * pad.characterWidth + 2 * pad.shiftWidth + 10 * pad.keySpacing, width, accuracy: 0.000001)
            XCTAssertGreaterThan(pad.returnWidth, pad.capsWidth)
        }
        let huge = try XCTUnwrap(KeyboardTypingLayoutPolicy.padPlan(availableWidth: .greatestFiniteMagnitude, isPad: true, layout: .letters))
        XCTAssertTrue([huge.characterWidth, huge.capsWidth, huge.returnWidth, huge.shiftWidth].allSatisfy { $0.isFinite && $0 > 0 })
    }

    func testPadFunctionsRequireActualPadLettersAndSufficientFiniteWindowWidth() {
        for width: CGFloat in [.nan, .infinity, -.infinity, -1, 0, 320, 402, 649, CGFloat(650).nextDown] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.padPlan(availableWidth: width, isPad: true, layout: .letters))
        }
        for layout in KeyboardTypingLayout.allCases {
            XCTAssertNil(KeyboardTypingLayoutPolicy.padPlan(availableWidth: 1008, isPad: false, layout: layout))
        }
        for layout in [KeyboardTypingLayout.numbers, .symbols] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.padPlan(availableWidth: 1008, isPad: true, layout: layout))
            for auxiliary in [false, true] {
                XCTAssertEqual(KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: auxiliary, widePad: true),
                               KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: auxiliary))
            }
        }
    }

    func testPadPunctuationHasExplicitMembershipAndNeverBroadensCompactLettersOrAuxiliaryDigits() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        for auxiliary in [false, true] {
            let rows = KeyboardTypingLayoutPolicy.rows(for: .letters, hasAuxiliaryRow: auxiliary, widePad: true)
            XCTAssertEqual(Array(rows.prefix(2)), Array(KeyboardTypingLayout.letters.rows.prefix(2)))
            XCTAssertEqual(rows[2].joined(), "zxcvbnm,.")
            XCTAssertEqual(Set(rows.flatMap { $0 }).count, 28)
            for punctuation in [",", "."] {
                XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: punctuation, state: state, hasAuxiliaryRow: auxiliary))
                XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: punctuation, state: state, hasAuxiliaryRow: auxiliary, widePad: true), punctuation)
                XCTAssertNotNil(KeyboardKeySettings.identifier(forCharacter: punctuation))
            }
            for invalid in ["1", "0", "..", "\t", "\n", "A", "é", ".\u{FE0F}"] {
                XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: invalid, state: state, hasAuxiliaryRow: auxiliary, widePad: true))
            }
            XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "q", state: state, hasAuxiliaryRow: auxiliary, widePad: true), "Q")
            XCTAssertEqual(state.shift, .uppercase)
        }
    }

    func testPadKeepsExactlyThreeRowsAcrossAllPagesHeightsAndSavedCounts() throws {
        for layout in KeyboardTypingLayout.allCases {
            for width: CGFloat in [220, 649, 650, 768, 1350, .greatestFiniteMagnitude] {
                for height: CGFloat in [8.1, 12, 12.1, 80, 116, 168, 500, .greatestFiniteMagnitude] {
                    for count in [0, 1, 40, Int.max] {
                        let value = try plan(height, width: width, page: layout, favorites: count, isPad: true)
                        XCTAssertEqual(value.rowCount, 3)
                        XCTAssertEqual(value.numberRowCount, 0)
                        XCTAssertEqual(value.favoriteRowsCount, 0)
                        XCTAssertGreaterThan(value.keyHeight, 0)
                        XCTAssertLessThanOrEqual(value.contentHeight, height + 0.00001)
                        XCTAssertLessThanOrEqual(value.keyHeight, width >= 650 ? 52 : 36)
                    }
                }
            }
        }
        for width: CGFloat in [.nan, .infinity, -.infinity, 0, 649] {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.typingKeyHeight(availableWidth: width, isPad: true), 36)
        }
        XCTAssertEqual(KeyboardTypingLayoutPolicy.typingKeyHeight(availableWidth: 1000, isPad: false), 36)
    }

    private func plan(_ height: CGFloat, width: CGFloat = 402, compact: Bool = false,
                      page: KeyboardTypingLayout = .letters, favorites: Int = 64,
                      isPad: Bool = false, threshold: Int = 5) throws -> KeyboardTypingLayoutPlan {
        try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: height, availableWidth: width,
            compact: compact, layout: page, favoriteCount: favorites, isPad: isPad, favoriteThreshold: threshold))
    }

    func testNonfiniteOrUnusableDimensionsAreRejected() {
        let invalid: [CGFloat] = [.nan, .infinity, -.infinity, 0, -1]
        for isPad in [false, true] {
            for value in invalid {
                XCTAssertNil(KeyboardTypingLayoutPolicy.plan(availableHeight: value, availableWidth: 402,
                    compact: false, layout: .letters, favoriteCount: 1, isPad: isPad))
                XCTAssertNil(KeyboardTypingLayoutPolicy.plan(availableHeight: 300, availableWidth: value,
                    compact: false, layout: .letters, favoriteCount: 1, isPad: isPad))
            }
        }
        for height: CGFloat in [CGFloat.leastNonzeroMagnitude, 1, 7.999, 8] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.plan(availableHeight: height, availableWidth: 402,
                compact: false, layout: .letters, favoriteCount: 0))
        }
    }

    func testNormalRowsAppearOnlyAtTheirFullFixedHeightThreshold() throws {
        // 36-point caps and four-point vertical gaps need 40*n - 4 points.
        for rows in 4...8 {
            let height = CGFloat(rows * 40 - 4)
            let before = try plan(height.nextDown)
            let exact = try plan(height)
            let after = try plan(height.nextUp)
            XCTAssertEqual(before.rowCapacity, rows - 1)
            XCTAssertEqual(exact.rowCapacity, rows)
            XCTAssertEqual(after.rowCapacity, rows)
            XCTAssertEqual(exact.keyHeight, 36)
            XCTAssertEqual(exact.rowSpacing, 4)
            XCTAssertLessThanOrEqual(exact.contentHeight, height)
        }
    }

    func testThreeRowsKeepTheirSizeAndExtraSpaceNeverStretchesCaps() throws {
        for height: CGFloat in [116, 140, 155, 156, 196, 220, 316, 420, 1_000] {
            let value = try plan(height, favorites: 0)
            XCTAssertEqual(value.keyHeight, 36)
            XCTAssertEqual(value.rowSpacing, 4)
            XCTAssertEqual(value.favoriteRowsCount, 0)
            XCTAssertEqual(value.rowCount, height >= 156 ? 4 : 3)
            XCTAssertEqual(value.contentHeight, height >= 156 ? 156 : 116)
        }
    }

    func testOnlyAConstrainedThreeRowPaneShrinksCaps() throws {
        for height: CGFloat in [8.5, 9, 40, 80, 115.5] {
            let value = try plan(height)
            XCTAssertEqual(value.rowCount, 3)
            XCTAssertEqual(value.numberRowCount, 0)
            XCTAssertEqual(value.favoriteRowsCount, 0)
            XCTAssertGreaterThan(value.keyHeight, 0)
            XCTAssertLessThan(value.keyHeight, 36)
            XCTAssertEqual(value.rowSpacing, 4)
            XCTAssertLessThanOrEqual(value.contentHeight, height + 0.000_001)
        }
        XCTAssertEqual(try plan(116).keyHeight, 36)
    }

    func testCompactUsesTheSameSmallCapAndExactRowThresholds() throws {
        for rows in 4...8 {
            let height = CGFloat(rows * 40 - 4)
            XCTAssertEqual(try plan(height.nextDown, compact: true).rowCapacity, rows - 1)
            let value = try plan(height, compact: true)
            XCTAssertEqual(value.rowCapacity, rows)
            XCTAssertEqual(value.keyHeight, 36)
            XCTAssertEqual(value.rowSpacing, 4)
        }
        XCTAssertEqual(try plan(116, compact: true).keyHeight, 36)
        XCTAssertLessThan(try plan(115, compact: true).keyHeight, 36)
        XCTAssertEqual(try plan(1_000, compact: true, favorites: 0).contentHeight, 156)
    }

    func testNumberRowNeedsFourRowsAndFavoritesNeedFive() throws {
        let three = try plan(155.999)
        XCTAssertEqual(three.numberRowCount, 0)
        XCTAssertEqual(three.favoriteRowsCount, 0)
        let four = try plan(156)
        XCTAssertEqual(four.numberRowCount, 1)
        XCTAssertEqual(four.favoriteRowsCount, 0)
        let five = try plan(196)
        XCTAssertEqual(five.numberRowCount, 1)
        XCTAssertEqual(five.favoriteRowsCount, 1)
        XCTAssertEqual(five.topRowsCount, 2)
        XCTAssertEqual(five.rowCount, 5)
    }

    func testExplicitSixRowFavoriteThresholdDoesNotChangeNumberThreshold() throws {
        let five = try plan(196, threshold: 6)
        XCTAssertEqual(five.rowCapacity, 5)
        XCTAssertEqual(five.numberRowCount, 1)
        XCTAssertEqual(five.favoriteRowsCount, 0)
        XCTAssertEqual(five.rowCount, 4)
        let six = try plan(236, threshold: 6)
        XCTAssertEqual(six.numberRowCount, 1)
        XCTAssertEqual(six.favoriteRowsCount, 2)
        XCTAssertEqual(six.rowCount, 6)
    }

    func testEmptyNegativeAndLimitedFavoritesNeverCreateFillerRows() throws {
        for count in [-10, -1, 0] {
            let value = try plan(316, favorites: count)
            XCTAssertEqual(value.favoriteRowsCount, 0)
            XCTAssertEqual(value.rowCount, 4)
            XCTAssertEqual(value.contentHeight, 156)
        }
        for count in [1, 5, 10] {
            let value = try plan(316, width: 244, favorites: count)
            XCTAssertEqual(value.favoritesPerRow, 10)
            XCTAssertEqual(value.favoriteRowsCount, 1)
            XCTAssertEqual(value.rowCount, 5)
            XCTAssertEqual(value.contentHeight, 196)
        }
        XCTAssertEqual(try plan(316, width: 244, favorites: 11).favoriteRowsCount, 2)
    }

    func testFavoritesAreLimitedByRealCapacityAndMaximumFourRows() throws {
        XCTAssertEqual(try plan(196, favorites: Int.max).favoriteRowsCount, 1)
        XCTAssertEqual(try plan(236, favorites: Int.max).favoriteRowsCount, 2)
        let huge = try plan(10_000, favorites: Int.max)
        XCTAssertEqual(huge.rowCapacity, 8)
        XCTAssertEqual(huge.favoriteRowsCount, 4)
        XCTAssertEqual(huge.rowCount, 8)
        XCTAssertEqual(huge.contentHeight, 316)
    }

    func testTenPositiveWidthColumnsRequireMoreThanTheirNumberRowGapBudget() throws {
        for isPad in [false, true] {
            let minimum: CGFloat = isPad ? 63 : 45
            for width: CGFloat in [CGFloat.leastNonzeroMagnitude, 0.1, 1, minimum.nextDown, minimum] {
                XCTAssertNil(KeyboardTypingLayoutPolicy.plan(availableHeight: 378, availableWidth: width,
                    compact: false, layout: .letters, favoriteCount: Int.max, isPad: isPad))
            }
            for width: CGFloat in [minimum.nextUp, 220, 320, 390, 768, CGFloat.greatestFiniteMagnitude] {
                let value = try plan(378, width: width, favorites: Int.max, isPad: isPad)
                XCTAssertEqual(value.favoritesPerRow, 10)
                XCTAssertTrue(value.favoriteKeyWidth.isFinite)
                XCTAssertGreaterThan(value.favoriteKeyWidth, 0)
                XCTAssertTrue(value.contentHeight.isFinite)
                XCTAssertEqual(value.favoriteRowsCount, isPad ? 0 : 4)
            }
        }
    }

    func testExpandedNumberPageHasTwentyDistinctExtraSymbolsAndZeroDigits() throws {
        let digits = Array("1234567890").map(String.init)
        let symbols = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
        for page in [KeyboardTypingLayout.numbers, .symbols] {
            for compact in [false, true] {
                let value = try plan(1_000, compact: compact, page: page, favorites: Int.max)
                XCTAssertEqual(value.numberRowCount, 1)
                XCTAssertEqual(value.favoriteRowsCount, 0)
                XCTAssertEqual(value.topRowsCount, 1)
                XCTAssertEqual(value.rowCount, 4)
                XCTAssertEqual(value.keyHeight, 36)
                XCTAssertEqual(value.contentHeight, 156)
                let auxiliary = KeyboardTypingLayoutPolicy.auxiliaryRow(for: page)
                XCTAssertEqual(auxiliary, page == .numbers ? symbols : digits)
                let rows = [auxiliary] + KeyboardTypingLayoutPolicy.rows(for: page, hasAuxiliaryRow: true)
                if page == .numbers {
                    XCTAssertEqual(rows[1], ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
                    XCTAssertEqual(Set(rows.prefix(2).flatMap { $0 }).count, 20)
                    XCTAssertFalse(rows.flatMap { $0 }.contains { $0.unicodeScalars.contains { (48...57).contains($0.value) } })
                } else {
                    XCTAssertEqual(rows.filter { $0 == digits }.count, 1)
                    XCTAssertEqual(rows.flatMap { $0 }.filter { digits.contains($0) }.count, 10)
                }
            }
        }
    }

    func testThreeRowPagesKeepTheirCompleteOriginalRowsAndLiteralDigitMembership() {
        for page in KeyboardTypingLayout.allCases {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.rows(for: page, hasAuxiliaryRow: false), page.rows)
            var state = KeyboardTypingState()
            state.selectLayout(page)
            for key in page.rows.flatMap({ $0 }) {
                XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: false), key)
            }
        }
        var numbers = KeyboardTypingState()
        numbers.selectLayout(.numbers)
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "1", state: numbers, hasAuxiliaryRow: false), "1")
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "1", state: numbers, hasAuxiliaryRow: true))
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "_", state: numbers, hasAuxiliaryRow: false))
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "_", state: numbers, hasAuxiliaryRow: true), "_")
        XCTAssertNil(numbers.output(for: "_"), "The base three-row state remains unchanged")
    }

    func testExpandedCoreOutputRejectsAuxiliaryStaleAndNonliteralKeysWithoutConsumingShift() {
        var state = KeyboardTypingState()
        state.pressShift(at: 1)
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "a", state: state, hasAuxiliaryRow: true), "A")
        XCTAssertEqual(state.shift, .uppercase)
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "1", state: state, hasAuxiliaryRow: true))
        state.selectLayout(.numbers)
        for key in KeyboardTypingLayoutPolicy.rows(for: .numbers, hasAuxiliaryRow: true).flatMap({ $0 }) {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: true), key)
        }
        for key in ["", "1", "0", "[", "]", "01", "a", "A", "€ ", "€\u{FE0F}", "１", "١", "\\\\", "\n"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: true), key)
        }
    }

    func testAuxiliaryThresholdAndFooterEntryAreConsistentAcrossAllPages() throws {
        for compact in [false, true] {
            let threshold: CGFloat = 156
            for page in KeyboardTypingLayout.allCases {
                let three = try plan(threshold.nextDown, compact: compact, page: page)
                let four = try plan(threshold, compact: compact, page: page)
                XCTAssertEqual(three.numberRowCount, 0)
                XCTAssertEqual(four.numberRowCount, 1)
                XCTAssertEqual(three.rowCount, 3)
                XCTAssertEqual(four.rowCount, 4)
                XCTAssertEqual(KeyboardTypingLayoutPolicy.entryTitle(auxiliaryRowVisible: three.numberRowCount > 0), "123")
                XCTAssertEqual(KeyboardTypingLayoutPolicy.entryTitle(auxiliaryRowVisible: four.numberRowCount > 0), "#+=")
                XCTAssertEqual(KeyboardTypingLayoutPolicy.auxiliaryRow(for: page).count, 10)
            }
        }
        XCTAssertEqual(KeyboardTypingLayoutPolicy.auxiliaryRow(for: .letters), Array("1234567890").map(String.init))
    }

    func testAuxiliaryOutputAcceptsOnlyTheCurrentPagesExactLiteralKeys() {
        for page in KeyboardTypingLayout.allCases {
            for key in KeyboardTypingLayoutPolicy.auxiliaryRow(for: page) {
                XCTAssertEqual(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: key, layout: page), key)
            }
            for invalid in ["", "01", "1 ", " 1", "a", "\n", "１", "١", "1\u{FE0F}", "1\u{20E3}", "[\u{FE0F}", "[]"] {
                XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: invalid, layout: page), invalid)
            }
        }
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "1", layout: .numbers))
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "[", layout: .letters))
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "[", layout: .symbols))
    }

    func testFavoriteCapsMatchTheNumberRowWidthAndSpacingOnPhoneAndPad() throws {
        for (width, isPad, spacing, expected): (CGFloat, Bool, CGFloat, CGFloat) in [
            (320, false, 5, 27.5), (390, false, 5, 34.5), (768, true, 7, 70.5),
            (220, false, 5, 17.5), (220, true, 7, 15.7)
        ] {
            for compact in [false, true] {
                let value = try plan(378, width: width, compact: compact, isPad: isPad)
                XCTAssertEqual(value.keySpacing, spacing)
                XCTAssertEqual(value.favoritesPerRow, 10)
                XCTAssertEqual(value.favoriteKeyWidth, expected, accuracy: 0.000_001)
                XCTAssertEqual(value.keyHeight, isPad && width >= 650 ? 52 : 36)
                XCTAssertEqual(value.favoriteKeyWidth * 10 + spacing * 9, width, accuracy: 0.000_001)
            }
        }
    }

    func testFixedColumnCapacityDependsOnFavoriteCountRatherThanDeviceWidth() throws {
        for isPad in [false, true] {
            for width: CGFloat in [220, 320, 390, 768] {
                for (count, expectedRows) in [(0, 0), (1, 1), (10, 1), (11, 2), (20, 2), (21, 3), (31, 4), (41, 4)] {
                    let value = try plan(316, width: width, favorites: count, isPad: isPad)
                    XCTAssertEqual(value.favoritesPerRow, 10)
                    XCTAssertEqual(value.favoriteRowsCount, isPad ? 0 : expectedRows)
                    XCTAssertEqual(value.rowCount, isPad ? 3 : 4 + expectedRows)
                }
            }
        }
    }

    func testDedicatedNumberRowAcceptsOnlyOneLiteralASCIIDigit() {
        for digit in "1234567890" {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.numberRowOutput(for: String(digit)), String(digit))
        }
        for value in ["", "01", "1 ", " 1", "a", "+", "\n", "１", "١", "1\u{FE0F}", "1\u{20E3}"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.numberRowOutput(for: value))
        }
    }

    func testGreatestFiniteHeightCannotOverflowRowCountOrStretchKeys() throws {
        let value = try plan(CGFloat.greatestFiniteMagnitude, width: CGFloat.greatestFiniteMagnitude,
                             favorites: Int.max)
        XCTAssertEqual(value.rowCapacity, 8)
        XCTAssertEqual(value.rowCount, 8)
        XCTAssertEqual(value.keyHeight, 36)
        XCTAssertEqual(value.contentHeight, 316)
    }

    func testFinitePlansStayWithinTheirBudgetAcrossPagesAndFavoriteCounts() throws {
        let heights: [CGFloat] = [9, 80, 115.5, 116, 140, 155.5, 156, 180, 196, 220, 236, 316, 420]
        for height in heights {
            for compact in [false, true] {
                for page in KeyboardTypingLayout.allCases {
                    for count in [-1, 0, 1, 8, 9, Int.max] {
                        let value = try plan(height, compact: compact, page: page, favorites: count)
                        XCTAssertTrue(value.keyHeight.isFinite)
                        XCTAssertGreaterThan(value.keyHeight, 0)
                        XCTAssertLessThanOrEqual(value.keyHeight, 36)
                        XCTAssertTrue((3...8).contains(value.rowCount))
                        XCTAssertLessThanOrEqual(value.rowCount, value.rowCapacity)
                        XCTAssertEqual(value.topRowsCount, value.numberRowCount + value.favoriteRowsCount)
                        XCTAssertEqual(value.rowCount, 3 + value.topRowsCount)
                        XCTAssertLessThanOrEqual(value.contentHeight, height + 0.000_001)
                    }
                }
            }
        }
    }
}
