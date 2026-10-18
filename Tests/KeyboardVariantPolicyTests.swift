import Foundation
import CoreGraphics
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardVariantPolicyTests: XCTestCase {
    func testPadDownFlicksMatchAllPrintedHintsAndRespectDisabledAndCustomChoices() {
        let keys = Array("qwertyuiopasdfghjklzxcvbnm,.").map(String.init)
        let values = Array("1234567890@#¥&*()'\"%-+=/;:!?").map(String.init)
        XCTAssertEqual(keys.count, 28)
        XCTAssertEqual(values.count, keys.count)
        var state = KeyboardTypingState()
        for shift in [KeyboardShiftState.lowercase, .uppercase, .capsLock] {
            state = KeyboardTypingState()
            if shift == .uppercase { state.pressShift(at: 1) }
            if shift == .capsLock { state.toggleCapsLock() }
            for (key, expected) in zip(keys, values) {
                let choices = KeyboardVariantPolicy.defaultSwipeDown(for: key, state: state, widePad: true)
                XCTAssertEqual(choices.first, expected)
                XCTAssertEqual(Set(choices).count, choices.count)
                XCTAssertEqual(choices, KeyboardVariantPolicy.options(text: expected, variants: KeyboardVariantPolicy.stockVariants(for: expected)))
                XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: key, state: state, widePad: false), [])
                XCTAssertEqual(KeyboardVariantPolicy.candidates(override: [], defaults: choices), [])
                XCTAssertEqual(KeyboardVariantPolicy.candidates(override: ["abc"], defaults: choices), ["abc"])
            }
        }
        for invalid in ["", "Q", "é", "qq", "1", "\t", "utility.space"] {
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: invalid, state: state, widePad: true), [])
        }
        for layout in [KeyboardTypingLayout.numbers, .symbols] {
            state.selectLayout(layout)
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "q", state: state, widePad: true), [])
        }
    }

    func testConfiguredCandidatesDistinguishDefaultsDisabledAndLiteralOverrides() {
        let defaults = ["A", "À", "Á"]
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: nil, defaults: defaults), defaults)
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: [], defaults: defaults), [])
        let configured = ["é", "e\u{301}", "👩🏽‍💻", "🙂‍↔️", "\0", "\n", "a"]
        let result = KeyboardVariantPolicy.candidates(override: configured, defaults: defaults)
        XCTAssertEqual(result.map { Array($0.utf16) }, configured.map { Array($0.utf16) })
        XCTAssertFalse(result.contains("A"), "Configured text must not inherit the key's Shift case")
    }

    func testConfiguredCandidateSelectionBoundsSourceBeforeFilteringAndDeduplicatesExactly() {
        let values = ["", "é", "e\u{301}", "é", "👩‍💻", "👩‍💻", String(repeating: "a", count: 65), String(repeating: "😀", count: 64)]
        let expected = ["é", "e\u{301}", "👩‍💻", String(repeating: "😀", count: 64)]
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: values, defaults: ["unused"]).map { Array($0.utf16) }, expected.map { Array($0.utf16) })
        let many = (0..<100).map { "choice-\($0)" }
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: many, defaults: []), Array(many.prefix(16)))
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: nil, defaults: many), Array(many.prefix(17)))
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: Array(repeating: "", count: 16) + ["not scanned"], defaults: ["unused"]), [])
        XCTAssertEqual(KeyboardVariantPolicy.candidates(override: nil, defaults: ["", "x", "x"]), ["x"])
    }

    func testSwipeDirectionRequiresThresholdAndPredominantlyVerticalFiniteTravel() {
        XCTAssertNil(KeyboardVariantPolicy.swipeDirection(delta: .zero))
        for y in [CGFloat(12).nextDown, -CGFloat(12).nextDown] {
            XCTAssertNil(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: 0, y: y)))
        }
        XCTAssertEqual(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: 0, y: -12)), .swipeUp)
        XCTAssertEqual(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: 0, y: 12)), .swipeDown)
        for x: CGFloat in [-12, 12, 50, -50] {
            XCTAssertNil(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: x, y: 12)))
            XCTAssertNil(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: x, y: -12)))
        }
        XCTAssertEqual(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: CGFloat(12).nextDown, y: 12)), .swipeDown)
        XCTAssertEqual(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: 1, y: -CGFloat.greatestFiniteMagnitude)), .swipeUp)
        for value in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: value, y: 20)))
            XCTAssertNil(KeyboardVariantPolicy.swipeDirection(delta: CGPoint(x: 0, y: value)))
        }
    }

    func testHorizontalSelectionStartsAtFirstChoiceRoundsHalfStridesAndClamps() {
        let fixtures: [(CGFloat, Int)] = [(0, 0), (CGFloat(18).nextDown, 0), (18, 1), (36, 1),
                                         (CGFloat(54).nextDown, 1), (54, 2), (-18, 0), (-100, 0), (1000, 3)]
        for (x, expected) in fixtures {
            XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: x, count: 4), expected)
        }
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: 5, count: 3, stride: 10), 1)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: 15, count: 3, stride: 10), 2)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: .greatestFiniteMagnitude, count: 17), 16)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: -.greatestFiniteMagnitude, count: 17), 0)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: .greatestFiniteMagnitude, count: 1), 0)
    }

    func testHorizontalSelectionRejectsMalformedCountsNonfiniteTravelAndDivisionOverflow() {
        for count in [Int.min, -1, 0, 18, Int.max] {
            XCTAssertNil(KeyboardVariantPolicy.horizontalChoice(deltaX: 0, count: count))
        }
        for value in [CGFloat.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardVariantPolicy.horizontalChoice(deltaX: value, count: 2))
        }
        for stride: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardVariantPolicy.horizontalChoice(deltaX: 36, count: 2, stride: stride))
        }
        XCTAssertNil(KeyboardVariantPolicy.horizontalChoice(deltaX: .greatestFiniteMagnitude, count: 2, stride: .leastNonzeroMagnitude))
    }

    func testDefaultSwipeUpOffersOppositeCaseAndDiacriticsWithoutChangingTypingState() {
        var lower = KeyboardTypingState()
        let beforeLower = lower
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "q", state: lower), ["Q"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "a", state: lower), ["A", "À", "Á", "Â", "Ä", "Æ", "Ã", "Å", "Ā"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "s", state: lower), ["S", "ẞ", "Ś", "Š"])
        XCTAssertEqual(lower, beforeLower)
        lower.pressShift(at: 1)
        let beforeUpper = lower
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "a", state: lower), ["a", "à", "á", "â", "ä", "æ", "ã", "å", "ā"])
        XCTAssertEqual(lower, beforeUpper)
        lower.pressShift(at: 1.1)
        XCTAssertEqual(lower.shift, .capsLock)
        let beforeCaps = lower
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "s", state: lower), ["s", "ß", "ś", "š"])
        XCTAssertEqual(lower, beforeCaps)
    }

    func testDefaultSwipeUpAppliesOnlyToBaseASCIILetterKeysOnTheLettersPage() {
        var state = KeyboardTypingState()
        for key in ["", "A", "ab", "é", "e\u{301}", "0", "$", "👩‍💻", " "] {
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: key, state: state), [])
        }
        for layout in [KeyboardTypingLayout.numbers, .symbols] {
            state.selectLayout(layout)
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "a", state: state), [])
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "0", state: state), [])
        }
    }

    func testCommonEnglishKeysHaveLiteralChoicesWithExplicitCapitalSharpS() {
        for key in ["a", "e", "i", "o", "u", "c", "n", "s", "y", "l", "z", "d", "t"] {
            let lower = KeyboardVariantPolicy.englishVariants(for: key, uppercase: false)
            let upper = KeyboardVariantPolicy.englishVariants(for: key, uppercase: true)
            XCTAssertFalse(lower.isEmpty)
            XCTAssertEqual(lower.count, upper.count)
            XCTAssertTrue(upper.allSatisfy { $0.count == 1 })
        }
        XCTAssertTrue(KeyboardVariantPolicy.englishVariants(for: "s", uppercase: true).contains("ẞ"))
        XCTAssertFalse(KeyboardVariantPolicy.englishVariants(for: "s", uppercase: true).contains("SS"))
        XCTAssertEqual(KeyboardVariantPolicy.englishVariants(for: "q", uppercase: false), [])
    }

    func testStockFamiliesExcludeOnlyTheExactOriginalAndRetainUsefulSymbols() {
        XCTAssertTrue(KeyboardVariantPolicy.stockVariants(for: "$").contains("€"))
        XCTAssertTrue(KeyboardVariantPolicy.stockVariants(for: "-").contains("—"))
        XCTAssertTrue(KeyboardVariantPolicy.stockVariants(for: "\"").contains("“"))
        XCTAssertTrue(KeyboardVariantPolicy.stockVariants(for: "=").contains("≠"))
        for text in ["$", "€", "-", "—", "'", "\"", "/", "=", "+", "*", "<", ">", ".", "?", "!", "%", "0"] {
            let choices = KeyboardVariantPolicy.stockVariants(for: text)
            XCTAssertFalse(choices.contains { $0.utf16.elementsEqual(text.utf16) })
            XCTAssertEqual(choices.count, Set(choices.map { Array($0.utf16) }).count)
        }
    }

    func testOptionsDeduplicateExactUTF16WithoutNormalizingCanonicalEquivalents() {
        let nfc = "é", nfd = "e\u{301}"
        let result = KeyboardVariantPolicy.options(text: nfc, variants: [nfc, nfd, nfd, "x"])
        XCTAssertEqual(result.map { Array($0.utf16) }, [nfc, nfd, "x"].map { Array($0.utf16) })
        XCTAssertFalse(KeyboardVariantPolicy.contains(nfd, in: [nfc]))
        XCTAssertTrue(KeyboardVariantPolicy.contains(nfd, in: result))
    }

    func testWholeEmojiCombiningAndControlChoicesRemainExact() {
        let texts = ["🙂\u{200D}↔\u{FE0F}", "👩🏽\u{200D}💻", "\u{301}", "\u{0000}", "\u{200D}", "\n", "𝄞"]
        let options = KeyboardVariantPolicy.options(text: "a", variants: texts)
        XCTAssertEqual(options.dropFirst().map { Array($0.utf16) }, texts.map { Array($0.utf16) })
        XCTAssertTrue(texts.allSatisfy(KeyboardVariantPolicy.validText))
    }

    func testInputBoundsRejectInvalidOriginalAndBoundLargeVariantArrays() {
        XCTAssertEqual(KeyboardVariantPolicy.options(text: "", variants: ["a"]), [])
        XCTAssertFalse(KeyboardVariantPolicy.validText(String(repeating: "a", count: 65)))
        XCTAssertTrue(KeyboardVariantPolicy.validText(String(repeating: "𝄞", count: 64)))
        let result = KeyboardVariantPolicy.options(text: "a", variants: (0..<100).map(String.init))
        XCTAssertEqual(result.count, 17)
        XCTAssertFalse(result.contains("16"))
        XCTAssertEqual(KeyboardVariantPolicy.options(text: "a", variants: ["", String(repeating: "a", count: 65), "b"]), ["a", "b"])
    }

    func testPopupAllChoicesFitInsideKeyboardAtEveryEdgeAndWrapWithoutLoss() throws {
        for width: CGFloat in [160, 220, 320, 402, 874] {
            for height: CGFloat in [220, 300, 420] {
                let container = CGRect(x: 3, y: 7, width: width, height: height)
                for anchor in [CGRect(x: 3, y: 7, width: 32, height: 42),
                               CGRect(x: width - 28, y: height - 28, width: 32, height: 42)] {
                    for count in [1, 2, 9, 14, 19] {
                        let layout = try XCTUnwrap(KeyboardVariantPopupLayout(anchor: anchor, container: container, count: count))
                        XCTAssertGreaterThanOrEqual(layout.frame.minX, container.minX)
                        XCTAssertGreaterThanOrEqual(layout.frame.minY, container.minY)
                        XCTAssertLessThanOrEqual(layout.frame.maxX, container.maxX + 0.0001)
                        XCTAssertLessThanOrEqual(layout.frame.maxY, container.maxY + 0.0001)
                        XCTAssertEqual(layout.cells.count, count)
                        for (index, cell) in layout.cells.enumerated() {
                            XCTAssertEqual(layout.index(at: CGPoint(x: cell.midX, y: cell.midY)), index)
                        }
                    }
                }
            }
        }
    }

    func testPopupRejectsInvalidGeometryCountsAndOutsideSelections() throws {
        let anchor = CGRect(x: 0, y: 0, width: 32, height: 42)
        for count in [Int.min, 0, 20, Int.max] {
            XCTAssertNil(KeyboardVariantPopupLayout(anchor: anchor, container: CGRect(x: 0, y: 0, width: 402, height: 300), count: count))
        }
        for container in [CGRect.zero, CGRect(x: 0, y: 0, width: 23, height: 300),
                          CGRect(x: 0, y: 0, width: CGFloat.nan, height: 300),
                          CGRect(x: CGFloat.infinity, y: 0, width: 402, height: 300)] {
            XCTAssertNil(KeyboardVariantPopupLayout(anchor: anchor, container: container, count: 2))
        }
        let layout = try XCTUnwrap(KeyboardVariantPopupLayout(anchor: anchor, container: CGRect(x: 0, y: 0, width: 402, height: 300), count: 2))
        XCTAssertNil(layout.index(at: CGPoint(x: -1, y: 0)))
        XCTAssertNil(layout.index(at: CGPoint(x: 1, y: CGFloat.nan)))
        XCTAssertNil(layout.index(at: CGPoint(x: 1000, y: 1000)))
    }

    func testMiddleAnchorUsesOnlySpaceOnOneSideSoNoChoiceIsCoveredByOriginalKey() throws {
        let anchor = CGRect(x: 140, y: 90, width: 42, height: 42)
        let layout = try XCTUnwrap(KeyboardVariantPopupLayout(anchor: anchor,
            container: CGRect(x: 0, y: 0, width: 320, height: 220), count: 14))
        XCTAssertTrue(layout.frame.maxY <= anchor.minY - 6 || layout.frame.minY >= anchor.maxY + 6)
        XCTAssertTrue(layout.cells.allSatisfy { $0.height >= 24 && $0.width >= 24 })
        for (index, cell) in layout.cells.enumerated() {
            XCTAssertEqual(layout.index(at: CGPoint(x: cell.midX, y: cell.midY)), index)
        }
        XCTAssertNil(KeyboardVariantPopupLayout(anchor: CGRect(x: 0, y: 4, width: 42, height: 42),
            container: CGRect(x: 0, y: 0, width: 100, height: 52), count: 14))
    }
}
