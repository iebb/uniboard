import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardTypingLayoutPolicyTests: XCTestCase {
    func testLandscapeContextUsesSceneGeometryAndFallsBackToTheInputWindowsDisplay() {
        let portrait = CGSize(width: 1032, height: 1376), landscape = CGSize(width: 1376, height: 1032)
        XCTAssertTrue(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1376, sceneSize: portrait,
            displaySize: nil, orientationIsLandscape: true))
        XCTAssertTrue(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1000, sceneSize: landscape, displaySize: nil))
        XCTAssertFalse(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1032, sceneSize: portrait, displaySize: landscape))
        XCTAssertTrue(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1376, sceneSize: portrait, displaySize: landscape),
                      "A stale portrait scene must not override the rendered landscape keyboard width")
        for display in [portrait, landscape] {
            for (width, expected) in [(CGFloat(1032), false), (1033, false), (CGFloat(1033).nextUp, true),
                                      (1376, true), (1377, true), (CGFloat(1377).nextUp, false)] {
                XCTAssertEqual(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: width, sceneSize: nil,
                    displaySize: display), expected)
            }
        }
    }

    func testLandscapeContextRejectsInvalidGeometryAndDoesNotInventAnOrientation() {
        let display = CGSize(width: 1032, height: 1376)
        let invalid: [CGFloat] = [0, -1, .nan, .infinity, -.infinity]
        for value in invalid {
            XCTAssertFalse(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: value, sceneSize: display,
                displaySize: display, orientationIsLandscape: true))
            for size in [CGSize(width: value, height: 1376), CGSize(width: 1032, height: value)] {
                XCTAssertTrue(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1376, sceneSize: size, displaySize: display))
                XCTAssertFalse(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1376, sceneSize: nil, displaySize: size))
            }
        }
        XCTAssertFalse(KeyboardTypingLayoutPolicy.isLandscapeContext(viewWidth: 1376, sceneSize: nil, displaySize: nil))
    }

    func testCaselessRowsGiveEveryLetterOneWidthAndRowThreesFunctionKeysTheRest() throws {
        let hebrew = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "he"))
        let arabic = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "ar"))
        // iPhone 17 Pro: Hebrew's widest rows hold ten keys, so Delete is one letter wide.
        let he = try XCTUnwrap(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: hebrew, available: 386, spacing: 5))
        XCTAssertEqual(he.letter, 34.1, accuracy: 0.0001)
        XCTAssertEqual(he.function, he.letter, accuracy: 0.0001)
        // Arabic: eleven keys a row; Arabic Diacritics and Delete split what nine letters leave.
        let ar = try XCTUnwrap(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: arabic, available: 386, spacing: 5))
        XCTAssertEqual(ar.letter, 336.0 / 11, accuracy: 0.0001)
        XCTAssertEqual(ar.function, ar.letter, accuracy: 0.0001)
        for width: CGFloat in [320, 386, 430, 640] {
            for alphabet in [hebrew, arabic] {
                let value = try XCTUnwrap(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: alphabet, available: width, spacing: 5))
                let functions = CGFloat(alphabet.hasShiftSlot ? 2 : 1)
                let last = CGFloat(alphabet.rows[2].count) * value.letter + functions * value.function
                    + 5 * (CGFloat(alphabet.rows[2].count) + functions - 1)
                XCTAssertEqual(last, width, accuracy: 0.0001, "Row 3 fills the width: \(alphabet.id)")
                XCTAssertGreaterThanOrEqual(value.function, value.letter)
                for row in alphabet.rows.prefix(2) {
                    XCTAssertLessThanOrEqual(CGFloat(row.count) * value.letter + 5 * CGFloat(row.count - 1), width + 0.0001)
                }
            }
        }
        XCTAssertNil(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: .english, available: 386, spacing: 5), "Cased layouts keep Shift")
        XCTAssertNil(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: hebrew, available: .infinity, spacing: 5))
        XCTAssertNil(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: hebrew, available: 386, spacing: .nan))
        XCTAssertNil(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: hebrew, available: 386, spacing: -1))
        XCTAssertNil(KeyboardTypingLayoutPolicy.caselessKeyWidths(for: arabic, available: 40, spacing: 5))
    }

    func testShiftedTapFollowsLettersAndManualANSIShiftButNeverSentenceDigitsOrOtherPages() {
        var state = KeyboardTypingState()
        XCTAssertFalse(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "q", state: state, ansiPad: true))
        state.synchronizeAutomaticCapitalization(true)
        XCTAssertTrue(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "q", state: state, ansiPad: false))
        for key in ["1", "[", "", "qq", "é"] { XCTAssertFalse(KeyboardTypingLayoutPolicy.usesShiftedTap(for: key, state: state, ansiPad: true)) }
        state.pressShift(at: 1); state.pressShift(at: 2)
        XCTAssertTrue(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "1", state: state, ansiPad: true))
        XCTAssertFalse(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "1", state: state, ansiPad: false))
        state.toggleCapsLock()
        XCTAssertTrue(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "q", state: state, ansiPad: true))
        XCTAssertFalse(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "1", state: state, ansiPad: true))
        state.selectLayout(.numbers)
        XCTAssertFalse(KeyboardTypingLayoutPolicy.usesShiftedTap(for: "q", state: state, ansiPad: true))
    }

    func testANSIShiftSymbolsAreExactAndCapsLockDoesNotShiftNumbersOrPunctuation() {
        let keys = Array("`1234567890-=[]\\;',./").map(String.init)
        let shifted = Array("~!@#$%^&*()_+{}|:\"<>?").map(String.init)
        XCTAssertEqual(keys.count, shifted.count)
        var state = KeyboardTypingState()
        for (key, expected) in zip(keys, shifted) {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), key)
            XCTAssertNotEqual(key, expected)
        }
        state.pressShift(at: 1)
        for (key, expected) in zip(keys, shifted) {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), expected)
        }
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "a", state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), "A")
        state.toggleCapsLock()
        for key in keys { XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), key) }
        for invalid in ["", "aa", "A", "é", "\t", "\n", "11"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: invalid, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true))
        }
        state.selectLayout(.numbers)
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "`", state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true))
        XCTAssertEqual(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "§", layout: .symbols, ansiPad: true), "§")
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "1", layout: .symbols, ansiPad: true))
    }

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

    func testWidePadRowsOfEveryLayoutFitTheirFunctionKeys() throws {
        for alphabet in KeyboardAlphabet.catalog {
            for width: CGFloat in [650, 1008, 1350] {
                let pad = try XCTUnwrap(KeyboardTypingLayoutPolicy.padPlan(availableWidth: width, isPad: true, layout: .letters, alphabet: alphabet))
                let rows = KeyboardTypingLayoutPolicy.rows(for: .letters, hasAuxiliaryRow: false, widePad: true, alphabet: alphabet)
                func rowWidth(_ keys: Int, _ functions: CGFloat) -> CGFloat {
                    CGFloat(keys) * pad.characterWidth + functions + CGFloat(keys + 1) * pad.keySpacing
                }
                XCTAssertLessThanOrEqual(rowWidth(rows[0].count, pad.tabWidth + pad.deleteWidth), width + 0.000001, alphabet.id)
                XCTAssertLessThanOrEqual(rowWidth(rows[1].count, pad.capsWidth + pad.returnWidth), width + 0.000001, alphabet.id)
                XCTAssertLessThanOrEqual(rowWidth(rows[2].count, 2 * pad.shiftWidth), width + 0.000001, alphabet.id)
                XCTAssertGreaterThanOrEqual(pad.characterWidth, 36, alphabet.id)
            }
        }
        let hungarian = try XCTUnwrap(KeyboardAlphabet.alphabet(id: "hu"))
        let narrow = try XCTUnwrap(KeyboardTypingLayoutPolicy.padPlan(availableWidth: 1008, isPad: true, layout: .letters, alphabet: hungarian))
        let english = try XCTUnwrap(KeyboardTypingLayoutPolicy.padPlan(availableWidth: 1008, isPad: true, layout: .letters))
        XCTAssertLessThan(narrow.characterWidth, english.characterWidth, "Twelve-key rows narrow every key")
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
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "1", state: numbers, hasAuxiliaryRow: true), "1")
        // A stale auxiliary preference must not replace the stock 123 digits.
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "[", state: numbers, hasAuxiliaryRow: false))
        XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: "[", state: numbers, hasAuxiliaryRow: true))
        XCTAssertNil(numbers.output(for: "["), "The base three-row state remains unchanged")
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
        for key in ["", "[", "]", "_", "~", "01", "a", "A", "€ ", "€\u{FE0F}", "１", "١", "\\\\", "\n"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: true), key)
        }
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
        XCTAssertEqual(KeyboardTypingLayoutPolicy.auxiliaryRow(for: .letters), Array("1234567890").map(String.init))
        XCTAssertTrue(KeyboardTypingLayoutPolicy.auxiliaryRow(for: .numbers).isEmpty)
        XCTAssertTrue(KeyboardTypingLayoutPolicy.auxiliaryRow(for: .symbols).isEmpty)
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "1", layout: .numbers))
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "[", layout: .numbers))
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "[", layout: .letters))
        XCTAssertNil(KeyboardTypingLayoutPolicy.auxiliaryRowOutput(for: "[", layout: .symbols))
    }

    func testDedicatedNumberRowAcceptsOnlyOneLiteralASCIIDigit() {
        for digit in "1234567890" {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.numberRowOutput(for: String(digit)), String(digit))
        }
        for value in ["", "01", "1 ", " 1", "a", "+", "\n", "１", "١", "1\u{FE0F}", "1\u{20E3}"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.numberRowOutput(for: value))
        }
    }
    func testANSIKeySpansFitRealLandscapeWidthsForBothPresets() throws {
        for preset in [KeyboardPadLayout.ansi, .ansiNumbers] {
            for width: CGFloat in [980, 1008, 1194, 1350] {
                let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.padPlan(availableWidth: width, isPad: true,
                    layout: .letters, isLandscape: true, padLayout: preset))
                XCTAssertTrue(plan.isANSI)
                XCTAssertEqual(plan.hasNumberRow, preset == .ansiNumbers)
                let k = plan.characterWidth, g = plan.keySpacing
                if preset == .ansiNumbers {
                    XCTAssertEqual(k * 13 + plan.deleteWidth + g * 13, width, accuracy: 0.000001)
                    XCTAssertEqual(k * 12 + plan.tabWidth + plan.backslashWidth + g * 13, width, accuracy: 0.000001)
                } else {
                    XCTAssertEqual(k * 12 + plan.tabWidth + plan.deleteWidth + g * 13, width, accuracy: 0.000001)
                }
                XCTAssertEqual(k * 11 + plan.capsWidth + plan.returnWidth + g * 12, width, accuracy: 0.000001)
            }
        }
    }

    func testLettersKeepFourRowsWhileSymbolPagesRespectStockAndANSIPresets() throws {
        for pad in [false, true] {
            for width: CGFloat in [64, 320, 649, 650, 752, 980, 1194] {
                for compact in [false, true] {
                    for preset in KeyboardPadLayout.allCases {
                        for layout in KeyboardTypingLayout.allCases {
                            let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 500,
                                availableWidth: width, compact: compact, layout: layout, isPad: pad,
                                isLandscape: true, padLayout: preset))
                            let ansi = KeyboardTypingLayoutPolicy.usesANSI(availableWidth: width, isPad: pad,
                                isLandscape: true, padLayout: preset)
                            let expectedRows = layout == .letters || layout == .symbols && ansi ? 4 : 3
                            XCTAssertEqual(plan.rowCount, expectedRows)
                            let ideal: CGFloat = pad && width >= 650 ? 52 * 1.15 : 36 * 1.15
                            let abcHeight = 4 * ideal + 3 * plan.rowSpacing
                            XCTAssertEqual(plan.contentHeight, abcHeight, accuracy: 0.000001)
                            XCTAssertEqual(plan.keyHeight, (abcHeight - CGFloat(expectedRows - 1) * plan.rowSpacing) / CGFloat(expectedRows), accuracy: 0.000001)
                            XCTAssertEqual(plan.numberRowCount > 0, layout == .letters && !(ansi && preset == .ansiNumbers))
                            XCTAssertEqual(plan.extraSymbolRowCount > 0, layout == .symbols && ansi)
                            let wide = pad && width >= 650 && layout == .letters
                            let core = KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: plan.numberRowCount > 0,
                                widePad: wide, ansiPad: ansi, padLayout: preset)
                            XCTAssertEqual(core.count, plan.mainRowsCount)
                            let all = core.flatMap { $0 } + (plan.auxiliaryRowCount > 0 ? KeyboardTypingLayoutPolicy.auxiliaryRow(for: layout, ansiPad: ansi) : [])
                            // The digits are on the letters and 123 pages exactly once.
                            for digit in "0123456789" {
                                XCTAssertEqual(all.filter { $0 == String(digit) }.count, layout == .symbols ? 0 : 1, "\(layout)")
                            }
                            XCTAssertEqual(Set(all).count, all.count, "No duplicate keys on a page")
                        }
                    }
                }
            }
        }
    }
    func testAThreeRowArrangementLeavesThreeRowsWithStockDigitPagesButKeepsFullANSIDigits() throws {
        let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 500, availableWidth: 402,
            compact: false, layout: .letters, keyRows: 3))
        XCTAssertEqual(plan.numberRowCount, 0)
        XCTAssertEqual(plan.rowCount, 3)
        XCTAssertEqual(plan.keyHeight, 36 * 1.15)
        let tight = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 98, availableWidth: 402,
            compact: false, layout: .letters, keyRows: 3))
        XCTAssertEqual(tight.contentHeight, 98, accuracy: 0.000001, "Three rows share the whole height")
        // The 123 page falls back to its stock rows, which start with the digits.
        XCTAssertEqual(KeyboardTypingLayoutPolicy.rows(for: .numbers, hasAuxiliaryRow: false)[0],
                       Array("1234567890").map(String.init))
        let ansi = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 500, availableWidth: 1194,
            compact: false, layout: .letters, isPad: true, isLandscape: true, padLayout: .ansiNumbers, keyRows: 3))
        XCTAssertEqual(ansi.rowCount, 4, "Full ANSI keeps its own digit row")
        // Arrangement row counts never add auxiliary digits to 123.
        for rows in [4, 5] {
            let four = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 500, availableWidth: 402,
                compact: false, layout: .numbers, keyRows: rows))
            XCTAssertEqual(four.numberRowCount, 0); XCTAssertEqual(four.rowCount, 3)
        }
        for rows in [0, 1, 3] {
            XCTAssertEqual(try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 500, availableWidth: 402,
                compact: false, layout: .symbols, keyRows: rows)).rowCount, 3)
        }
    }
    func testFixedTemplateRejectsInvalidDimensionsAndShrinksAllRowsOnlyIfConstrained() throws {
        for pad in [false, true] {
            for invalid: CGFloat in [.nan, .infinity, -.infinity, 0, -1, 12] {
                XCTAssertNil(KeyboardTypingLayoutPolicy.plan(availableHeight: invalid, availableWidth: 402,
                    compact: false, layout: .letters, isPad: pad))
                XCTAssertNil(KeyboardTypingLayoutPolicy.plan(availableHeight: 500, availableWidth: invalid,
                    compact: false, layout: .letters, isPad: pad))
            }
            for height: CGFloat in [18.01, 20, 80, 180, 500, .greatestFiniteMagnitude] {
                let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: height, availableWidth: 1008,
                    compact: false, layout: .letters, isPad: pad))
                XCTAssertEqual(plan.rowCount, 4)
                XCTAssertTrue(plan.keyHeight.isFinite); XCTAssertGreaterThan(plan.keyHeight, 0)
                XCTAssertLessThanOrEqual(plan.contentHeight, height + 0.000001)
            }
        }
    }
}

extension KeyboardTypingLayoutPolicyTests {
    func testStockSymbolContentsAndMembershipIgnoreStaleAuxiliaryWideAndANSIPreferences() {
        let expected: [KeyboardTypingLayout: [String]] = [
            .numbers: ["1234567890", "-/:;()$&@\"", ".,?!'"],
            .symbols: ["[]{}#%^*+=", "_\\|~<>€£¥•", ".,?!'"]
        ]
        for (page, texts) in expected {
            var state = KeyboardTypingState()
            state.pressShift(at: 1)
            state.selectLayout(page)
            for auxiliary in [false, true] {
                for wide in [false, true] {
                    for ansi in [false, true] {
                        for preset in KeyboardPadLayout.allCases {
                            let rows = KeyboardTypingLayoutPolicy.rows(for: page, hasAuxiliaryRow: auxiliary,
                                widePad: wide, ansiPad: ansi, padLayout: preset)
                            XCTAssertEqual(rows.map { $0.joined() }, texts)
                            XCTAssertEqual(Set(rows.flatMap { $0 }).count, 25)
                            for key in rows.flatMap({ $0 }) {
                                XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state,
                                    hasAuxiliaryRow: auxiliary, widePad: wide, ansiPad: ansi, padLayout: preset), key)
                            }
                            for key in page == .numbers ? ["[", "]", "§", "a"] : ["1", "0", "-", "§", "a"] {
                                XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: key, state: state,
                                    hasAuxiliaryRow: auxiliary, widePad: wide, ansiPad: ansi, padLayout: preset))
                            }
                        }
                    }
                }
            }
        }
    }

    func testSymbolRowsKeepABCContentHeightAndSpacingWithNoBlankFourthRow() throws {
        for pad in [false, true] {
            for width: CGFloat in [386, 649, 650, 1008] {
                for preset in KeyboardPadLayout.allCases {
                    for landscape in [false, true] {
                        for count in [0, 3, 4, 5] {
                            for available: CGFloat in [18.01, 98, 177.6, 257.2, 500, .greatestFiniteMagnitude] {
                                let abc = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: available,
                                    availableWidth: width, compact: false, layout: .letters, isPad: pad,
                                    isLandscape: landscape, padLayout: preset, keyRows: count))
                                for page in [KeyboardTypingLayout.numbers, .symbols] {
                                    let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: available,
                                        availableWidth: width, compact: false, layout: page, isPad: pad,
                                        isLandscape: landscape, padLayout: preset, keyRows: count))
                                    XCTAssertEqual(plan.numberRowCount, 0)
                                    XCTAssertEqual(plan.contentHeight, abc.contentHeight, accuracy: 0.000001)
                                    XCTAssertEqual(plan.rowSpacing, abc.rowSpacing)
                                    XCTAssertEqual(plan.keySpacing, abc.keySpacing)
                                    XCTAssertTrue(plan.keyHeight.isFinite)
                                    XCTAssertGreaterThan(plan.keyHeight, 0)
                                }
                            }
                        }
                    }
                }
            }
        }
        let phone = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 177.6, availableWidth: 386,
            compact: false, layout: .numbers))
        XCTAssertEqual(phone.keyHeight, 169.6 / 3, accuracy: 0.000001)
        let three = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 132.2, availableWidth: 386,
            compact: false, layout: .symbols, keyRows: 3))
        XCTAssertEqual(three.keyHeight, 41.4, accuracy: 0.000001)
    }

    func testEveryAuxiliaryRouteRequiresItsVisiblePageAndKeepsCustomABCDigits() {
        let standard = MainKeyboardArrangement.standard(for: .english)
        let letters = MainKeyboardArrangement.letters(for: .english)
        var state = KeyboardTypingState()
        func routed(_ key: String, auxiliary: Bool = true, isAuxiliaryKey: Bool = true,
                    ansi: Bool = false, preset: KeyboardPadLayout = .ansiNumbers,
                    arrangement: MainKeyboardArrangement = .standard(for: .english)) -> String? {
            KeyboardTypingLayoutPolicy.routedOutput(for: key, state: state, hasAuxiliaryRow: auxiliary,
                isAuxiliaryKey: isAuxiliaryKey, widePad: ansi, ansiPad: ansi,
                padLayout: preset, arrangement: arrangement)
        }
        XCTAssertEqual(routed("a", isAuxiliaryKey: false), "a")
        for digit in MainKeyboardArrangement.digits {
            XCTAssertEqual(routed(digit), digit)
            XCTAssertEqual(routed(digit, auxiliary: false, arrangement: standard), digit, "Embedded ABC digits still work")
            XCTAssertNil(routed(digit, auxiliary: false, arrangement: letters))
            XCTAssertNil(routed(digit, isAuxiliaryKey: false))
        }
        XCTAssertNil(routed("a"))
        XCTAssertNil(routed("§", ansi: true))
        for page in [KeyboardTypingLayout.numbers, .symbols] {
            state.selectLayout(page)
            for ansi in [false, true] {
                for auxiliary in [false, true] {
                    for digit in MainKeyboardArrangement.digits {
                        XCTAssertNil(routed(digit, auxiliary: auxiliary, ansi: ansi), "Invisible auxiliary digit refused")
                        XCTAssertEqual(routed(digit, auxiliary: auxiliary, isAuxiliaryKey: false, ansi: ansi), page == .numbers ? digit : nil)
                    }
                    for key in KeyboardTypingLayoutPolicy.auxiliaryRow(for: .symbols, ansiPad: true) {
                        XCTAssertEqual(routed(key, auxiliary: auxiliary, ansi: ansi), page == .symbols && auxiliary && ansi ? key : nil)
                        XCTAssertNil(routed(key, auxiliary: auxiliary, isAuxiliaryKey: false, ansi: ansi))
                        XCTAssertNil(routed(key, auxiliary: auxiliary, ansi: ansi, preset: .stock))
                        XCTAssertNil(routed(key, auxiliary: auxiliary, ansi: ansi, arrangement: letters))
                    }
                }
            }
        }
    }

    func testSymbolReturnAndBackSwitchUseMeasuredWidthAndActiveANSIStyle() {
        for width: CGFloat in [.nan, .infinity, -.infinity, -1, 0, 320, 649, CGFloat(650).nextDown, 650, 980, 1008] {
            for pad in [false, true] {
                XCTAssertEqual(KeyboardTypingLayoutPolicy.showsSymbolReturn(availableWidth: width, isPad: pad),
                               pad && width.isFinite && width >= 650)
            }
        }
        for pad in [false, true] {
            for ansi in [false, true] {
                for preset in KeyboardPadLayout.allCases {
                    XCTAssertEqual(KeyboardTypingLayoutPolicy.symbolSwitchTitle(to: .symbols, isPad: pad,
                        ansiPad: ansi, padLayout: preset), "#+=")
                    XCTAssertEqual(KeyboardTypingLayoutPolicy.symbolSwitchTitle(to: .numbers, isPad: pad,
                        ansiPad: ansi, padLayout: preset), ansi && preset == .ansiNumbers ? "=<>" : pad ? ".?123" : "123")
                }
            }
        }
    }
}


final class KeyboardPhonePortraitGeometryTests: XCTestCase {
    func testExactSpecFramesAtAllFourPhoneWidths() throws {
        let cases: [(CGFloat, CGFloat)] = [(440, 35.2), (402, 31.4), (393, 30.5), (375, 28.7)]
        for (width, k) in cases {
            let geometry = try XCTUnwrap(KeyboardPhonePortraitGeometry(width: width))
            let pitch = k + 8
            XCTAssertEqual(geometry.keyWidth, k, accuracy: 0.00001)
            let q = geometry.characterRow(count: 10)
            let a = geometry.characterRow(count: 9)
            let z = geometry.lastLetterRow(letters: 7)
            for i in 0..<10 {
                XCTAssertEqual(q[i].x, 8 + CGFloat(i) * pitch, accuracy: 0.00001)
                XCTAssertEqual(q[i].width, k, accuracy: 0.00001)
            }
            for i in 0..<9 {
                XCTAssertEqual(a[i].x, 8 + pitch / 2 + CGFloat(i) * pitch, accuracy: 0.00001)
                XCTAssertEqual(a[i].width, k, accuracy: 0.00001)
            }
            for i in 0..<7 {
                XCTAssertEqual(z.letters[i].x, 8 + 1.5 * pitch + CGFloat(i) * pitch, accuracy: 0.00001)
                XCTAssertEqual(z.letters[i].width, k, accuracy: 0.00001)
            }
            XCTAssertEqual(try XCTUnwrap(z.leading).x, 8)
            XCTAssertEqual(try XCTUnwrap(z.leading).width, 1.5 * pitch - 16, accuracy: 0.00001)
            XCTAssertEqual(z.trailing.maxX, width - 8, accuracy: 0.00001)
            XCTAssertEqual(z.trailing.x - z.letters.last!.maxX, 16, accuracy: 0.00001)
            let bottom = geometry.bottomRow(smallKeys: 3)
            for i in 0..<3 {
                XCTAssertEqual(bottom.small[i].x, 8 + CGFloat(i) * pitch, accuracy: 0.00001)
                XCTAssertEqual(bottom.small[i].width, k, accuracy: 0.00001)
            }
            XCTAssertEqual(bottom.space.x, 8 + 3 * pitch, accuracy: 0.00001)
            XCTAssertEqual(bottom.space.maxX, 7.5 * pitch, accuracy: 0.00001)
            XCTAssertEqual(try XCTUnwrap(bottom.returnKey).x, 8 + 7.5 * pitch, accuracy: 0.00001)
            XCTAssertEqual(try XCTUnwrap(bottom.returnKey).maxX, width - 8, accuracy: 0.00001)
        }
        let geometry = try XCTUnwrap(KeyboardPhonePortraitGeometry(width: 440))
        let z = geometry.lastLetterRow(letters: 7)
        XCTAssertEqual(try XCTUnwrap(z.leading).width, 48.8, accuracy: 0.00001)
        XCTAssertEqual(z.trailing.x, 383.2, accuracy: 0.00001)
        let bottom = geometry.bottomRow(smallKeys: 3)
        XCTAssertEqual(bottom.space.x, 137.6, accuracy: 0.00001)
        XCTAssertEqual(bottom.space.maxX, 324, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(bottom.returnKey).x, 332, accuracy: 0.00001)
    }

    func testRowsStackFromBAndNumberRowAddsOnlyHeight() throws {
        for count in [3, 4] {
            let height = KeyboardPhonePortraitGeometry.height(keyRows: count)
            XCTAssertEqual(height, count == 3 ? 272 : 328)
            let b = height - 7
            for (row, offset) in [45.0, 101, 157, 213, 269].enumerated() {
                XCTAssertEqual(KeyboardPhonePortraitGeometry.rowTop(aboveBottomRow: row, bottom: b), b - offset)
            }
            for page in KeyboardTypingLayout.allCases {
                let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: CGFloat(count) * 45 + CGFloat(count - 1) * 11,
                    availableWidth: 424, compact: false, layout: page, keyRows: count, phonePortrait: true))
                XCTAssertEqual(plan.keyHeight, 45)
                XCTAssertEqual(plan.rowSpacing, 11)
                XCTAssertEqual(plan.keySpacing, 8)
            }
        }
    }

    func testGapMidpointsAndEdgesRouteWithoutChangingVisibleFrames() throws {
        let geometry = try XCTUnwrap(KeyboardPhonePortraitGeometry(width: 440))
        func frames(_ spans: [KeyboardPhonePortraitGeometry.Span], _ y: CGFloat) -> [CGRect] {
            spans.map { CGRect(x: $0.x, y: y, width: $0.width, height: 45) }
        }
        let z = geometry.lastLetterRow(letters: 7)
        let bottom = geometry.bottomRow(smallKeys: 3)
        let rows = [frames(geometry.characterRow(count: 10), 52), frames(geometry.characterRow(count: 9), 108),
                    frames([try XCTUnwrap(z.leading)] + z.letters + [z.trailing], 164),
                    frames(bottom.small + [bottom.space, try XCTUnwrap(bottom.returnKey)], 220)]
        let regions = KeyboardKeyHitRegions.regions(rows: rows, bounds: CGRect(x: 0, y: 0, width: 440, height: 272))
        let samples: [(CGPoint, Int, Int)] = [
            (CGPoint(x: 47.2, y: 74), 0, 1), // Q/W midpoint: tie goes right
            (CGPoint(x: 35, y: 102.5), 1, 0), // Q/A midpoint: tie goes down
            (CGPoint(x: 4, y: 130), 1, 0), // left of A
            (CGPoint(x: 64.8, y: 186), 2, 1), // Shift/Z midpoint
            (CGPoint(x: 0, y: 74), 0, 0),
            (CGPoint(x: 440, y: 271), 3, 4),
            (CGPoint(x: 200, y: 272), 3, 3)]
        for (point, r, i) in samples {
            let key = try XCTUnwrap(KeyboardKeyHitRegions.key(at: point, regions: regions))
            XCTAssertEqual(key.row, r); XCTAssertEqual(key.index, i)
        }
        XCTAssertNil(KeyboardKeyHitRegions.key(at: CGPoint(x: 20, y: 45), regions: regions))
        XCTAssertEqual(rows[0][0], CGRect(x: 8, y: 52, width: 35.2, height: 45))
        // Every point in the key area, including all larger gaps, has a key.
        for y in stride(from: 47.0, through: 272, by: 2) {
            for x in stride(from: 0.0, through: 440, by: 2) {
                XCTAssertNotNil(KeyboardKeyHitRegions.key(at: CGPoint(x: x, y: y), regions: regions))
            }
        }
    }

    /// Spec 1.1 §6: narrower phones use 43-point keys 54 apart, a 51.3-point
    /// band and nothing under the bottom row; 430 and wider keep 440's rows.
    func testNarrowPhonesUseAppleRowsAndWidePhonesKeepTheirs() throws {
        typealias Rows = KeyboardPhonePortraitGeometry.Rows
        for width in [440.0, 430] { XCTAssertEqual(Rows(width: width), .large) }
        for width in [429.0, 420, 402, 393, 375] { XCTAssertEqual(Rows(width: width), .compact) }
        XCTAssertEqual(Rows.large.height(keyRows: 3), 272)
        XCTAssertEqual(Rows.large.height(keyRows: 4), 328)
        let compact = Rows.compact
        XCTAssertEqual(compact.keyHeight, 43)
        XCTAssertEqual(compact.rowPitch, 54)
        XCTAssertEqual(compact.topBand, 51.3, accuracy: 0.00001)
        XCTAssertEqual(compact.bottomPadding, 0)
        XCTAssertEqual(compact.height(keyRows: 3), 256.3, accuracy: 0.00001)
        XCTAssertEqual(compact.height(keyRows: 4), 310.3, accuracy: 0.00001)
        // On 402 the keyboard's bottom edge is 799: rows land 4 points above Apple's 598/652/706/760.
        let bottom: CGFloat = 799
        for (row, appleTop) in [760.0, 706, 652, 598].enumerated() {
            XCTAssertEqual(bottom - compact.bottomPadding - compact.keyHeight - CGFloat(row) * compact.rowPitch, appleTop - 4, accuracy: 0.00001)
        }
        let display = CGSize(width: 402, height: 874)
        for (rows, height) in [(3, 256.3), (4, 310.3)] {
            let metrics = KeyboardLayoutPolicy.metrics(viewWidth: 402, displaySize: display, sceneHeight: 874,
                isPad: false, compactVertical: false, keyRows: rows, stockRows: true)
            XCTAssertEqual(metrics.height, height, accuracy: 0.00001)
            XCTAssertEqual(metrics.typingKeyHeight, 43)
            for page in KeyboardTypingLayout.allCases {
                let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: CGFloat(rows) * 43 + CGFloat(rows - 1) * 11,
                    availableWidth: 386, compact: false, layout: page, keyRows: rows, phonePortrait: true))
                XCTAssertEqual(plan.keyHeight, 43)
                XCTAssertEqual(plan.rowSpacing, 11)
            }
        }
        let wide = KeyboardLayoutPolicy.metrics(viewWidth: 440, displaySize: CGSize(width: 440, height: 956), sceneHeight: 956,
            isPad: false, compactVertical: false, keyRows: 3, stockRows: true)
        XCTAssertEqual(wide.height, 272)
        XCTAssertEqual(wide.typingKeyHeight, 45)
    }

    func testPortraitOptInLeavesLandscapePadAndSavedCustomMetricsUnchanged() throws {
        let display = CGSize(width: 440, height: 956)
        let old = KeyboardLayoutPolicy.metrics(viewWidth: 440, displaySize: display, sceneHeight: 956,
            isPad: false, compactVertical: false)
        XCTAssertEqual(old.height, 237, accuracy: 0.00001)
        XCTAssertEqual(old.typingKeyHeight, 41.4, accuracy: 0.00001)
        let stock = KeyboardLayoutPolicy.metrics(viewWidth: 440, displaySize: display, sceneHeight: 956,
            isPad: false, compactVertical: false, stockRows: true)
        XCTAssertEqual(stock.height, 328)
        XCTAssertEqual(stock.typingKeyHeight, 45)
        for (width, pad) in [(956.0, false), (820.0, true), (320.0, true)] {
            let before = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: display, sceneHeight: 440,
                isPad: pad, compactVertical: true)
            let after = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: display, sceneHeight: 440,
                isPad: pad, compactVertical: true, stockRows: true)
            XCTAssertEqual(after.height, before.height)
            XCTAssertEqual(after.typingKeyHeight, before.typingKeyHeight)
            XCTAssertFalse(after.usesPhonePortraitGeometry)
        }
        // Saving explicit rows forces the arrangement renderer even when
        // the saved order looks like the stock layout.
        var custom = MainKeyboardArrangement.standard(for: .english)
        XCTAssertTrue(custom.convertToExplicitRows())
        let rendering = KeyboardABCRendering(alphabet: .english, arrangement: custom, availableWidth: 424,
            isPad: false, isLandscape: false, padLayout: .stock)
        XCTAssertTrue(rendering.arranged)
        let keyWidth = MainKeyboardArrangement.keyWidth(for: custom.rows, available: 424, spacing: 5)
        XCTAssertEqual(keyWidth, 37.9, accuracy: 0.00001)
        let last = custom.rows.last!
        let widths = last.map { MainKeyboardArrangement.width(of: $0, keyWidth: keyWidth, spacing: 5) }
        XCTAssertEqual(widths.first!, 59.35, accuracy: 0.00001)
        XCTAssertEqual(widths.last!, 59.35, accuracy: 0.00001)
        XCTAssertEqual(widths.reduce(0, +) + CGFloat(last.count - 1) * 5, 424, accuracy: 0.00001)
        let customPlan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 177.6, availableWidth: 424,
            compact: false, layout: .letters))
        XCTAssertEqual(customPlan.keyHeight, 41.4, accuracy: 0.00001)
        XCTAssertEqual(customPlan.rowSpacing, 4)
        XCTAssertEqual(customPlan.keySpacing, 5)
    }

    func testOptionalGlobeAndCollapseKeepReturnAndFitSpace() throws {
        for width: CGFloat in [375, 393, 402, 440] {
            for count in 3...5 {
                let geometry = try XCTUnwrap(KeyboardPhonePortraitGeometry(width: width))
                let row = geometry.bottomRow(smallKeys: count)
                XCTAssertGreaterThanOrEqual(row.space.width, 44)
                XCTAssertEqual(row.returnKey, geometry.bottomRow(smallKeys: 3).returnKey)
                XCTAssertEqual(row.space.x - row.small.last!.maxX, 8, accuracy: 0.00001)
            }
        }
    }
}
