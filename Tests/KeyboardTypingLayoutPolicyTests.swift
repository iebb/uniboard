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
            XCTAssertEqual(KeyboardTypingLayoutPolicy.ansiAlternateOutput(for: key, state: state), expected)
        }
        state.pressShift(at: 1)
        for (key, expected) in zip(keys, shifted) {
            XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), expected)
            XCTAssertEqual(KeyboardTypingLayoutPolicy.ansiAlternateOutput(for: key, state: state), key)
        }
        XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: "a", state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), "A")
        state.toggleCapsLock()
        for key in keys { XCTAssertEqual(KeyboardTypingLayoutPolicy.output(for: key, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true), key) }
        for invalid in ["", "aa", "A", "é", "\t", "\n", "11"] {
            XCTAssertNil(KeyboardTypingLayoutPolicy.ansiAlternateOutput(for: invalid, state: state))
            XCTAssertNil(KeyboardTypingLayoutPolicy.output(for: invalid, state: state, hasAuxiliaryRow: false, widePad: true, ansiPad: true))
        }
        state.selectLayout(.numbers)
        XCTAssertNil(KeyboardTypingLayoutPolicy.ansiAlternateOutput(for: "1", state: state))
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

    func testFixedFourRowsAlwaysContainDigitsInLettersAndRespectEveryPreset() throws {
        for pad in [false, true] {
            for width: CGFloat in [64, 320, 649, 650, 752, 980, 1194] {
                for compact in [false, true] {
                    for preset in KeyboardPadLayout.allCases {
                        for layout in KeyboardTypingLayout.allCases {
                            let plan = try XCTUnwrap(KeyboardTypingLayoutPolicy.plan(availableHeight: 500,
                                availableWidth: width, compact: compact, layout: layout, isPad: pad,
                                isLandscape: true, padLayout: preset))
                            XCTAssertEqual(plan.rowCount, 4)
                            XCTAssertEqual(plan.keyHeight, pad && width >= 650 ? 52 * 1.15 : 36 * 1.15)
                            let ansi = KeyboardTypingLayoutPolicy.usesANSI(availableWidth: width, isPad: pad,
                                isLandscape: true, padLayout: preset)
                            let wide = pad && width >= 650 && layout == .letters
                            let core = KeyboardTypingLayoutPolicy.rows(for: layout, hasAuxiliaryRow: plan.numberRowCount > 0,
                                widePad: wide, ansiPad: ansi, padLayout: preset)
                            XCTAssertEqual(core.count, plan.mainRowsCount)
                            let all = core.flatMap { $0 } + (plan.numberRowCount > 0 ? KeyboardTypingLayoutPolicy.auxiliaryRow(for: layout, ansiPad: ansi) : [])
                            if layout == .letters {
                                for digit in "0123456789" { XCTAssertEqual(all.filter { $0 == String(digit) }.count, 1) }
                            }
                        }
                    }
                }
            }
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
