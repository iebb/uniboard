import Foundation
import CoreGraphics
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardVariantPolicyTests: XCTestCase {
    func testUpOffersModifierFormsAndDownStyledFormsWithoutSymbols() {
        var state = KeyboardTypingState()
        let a = KeyboardVariantPolicy.gestureCandidates(for: "a", original: "a", state: state, settings: .defaults)
        XCTAssertEqual(a.swipeUp, ["ᵃ", "ₐ"])
        XCTAssertEqual(a.swipeDown, ["𝐚", "𝑎", "𝒂", "𝒶", "𝓪", "𝔞", "𝕒", "𝗮", "𝚊", "ⓐ", "⒜", "ａ", "ᴀ"])
        XCTAssertEqual(a.longPress.first, "a")
        // No letter flicks to a symbol or digit, with or without the number row.
        for key in "qwertyuiopasdfghjklzxcvbnm".map(String.init) {
            let value = KeyboardVariantPolicy.gestureCandidates(for: key, original: key, state: state, settings: .defaults)
            XCTAssertTrue((value.swipeUp + value.swipeDown).allSatisfy { !$0.unicodeScalars.allSatisfy(\.isASCII) }, key)
        }
        XCTAssertTrue(KeyboardVariantPolicy.gestureCandidates(for: "q", original: "q", state: state, settings: .defaults).swipeUp.isEmpty,
                      "Q has no superscript or subscript")
        state.pressShift(at: 1)
        let upper = KeyboardVariantPolicy.gestureCandidates(for: "a", original: "A", state: state, settings: .defaults)
        XCTAssertEqual(upper.swipeUp, ["ᴬ"])
        XCTAssertEqual(upper.swipeDown.first, "𝐀")
    }

    func testResolvedGestureChoosersAreDisjointForEveryKeyAndPage() {
        for layout in KeyboardTypingLayout.allCases {
            for shifted in [false, true] {
                var state = KeyboardTypingState(); state.selectLayout(layout)
                if shifted { state.pressShift(at: 1) }
                for key in KeyboardKeySettings.descriptors.compactMap(\.text) {
                    let value = KeyboardVariantPolicy.gestureCandidates(for: key, original: state.label(for: key), state: state,
                                                                        settings: .defaults)
                    let all = value.longPress + value.swipeDown + value.swipeUp
                    XCTAssertEqual(Set(all.map { Array($0.utf16) }).count, all.count, key)
                    XCTAssertTrue(all.allSatisfy(KeyboardVariantPolicy.validText))
                    XCTAssertLessThanOrEqual(value.longPress.count, 17)
                    XCTAssertLessThanOrEqual(value.swipeDown.count, 16)
                    XCTAssertLessThanOrEqual(value.swipeUp.count, 16)
                    XCTAssertFalse((value.swipeUp + value.swipeDown).contains { $0 != key && $0.lowercased() == key.lowercased() },
                                   "Swipes never switch case")
                }
            }
        }
    }

    func testCurrencyKeysKeepCompleteHoldFamiliesAndHaveNoDefaultSwipes() {
        var state = KeyboardTypingState(); state.selectLayout(.symbols)
        for key in ["$", "€", "£", "¥"] {
            let value = KeyboardVariantPolicy.gestureCandidates(for: key, original: key, state: state, settings: .defaults)
            XCTAssertEqual(value.longPress, KeyboardVariantPolicy.options(text: key, variants: KeyboardVariantPolicy.stockVariants(for: key)))
            XCTAssertTrue(value.swipeUp.isEmpty)
            XCTAssertTrue(value.swipeDown.isEmpty)
        }
        XCTAssertTrue(KeyboardVariantPolicy.stockVariants(for: "£").contains("¥"), "Actual currency keys retain their currency family")
    }

    func testExplicitGestureChoicesWinWithoutMutatingSettingsOrNormalizingUnicode() throws {
        let keyID = try XCTUnwrap(KeyboardKeySettings.identifier(forCharacter: "a"))
        let exact = ["é", "e\u{301}", "A", "1"]
        let settings = KeyboardKeySettings.Snapshot(overrides: [keyID: .init(longPress: exact, swipeUp: ["A", "↑", "é"], swipeDown: ["1", "↓", "↑"])])
        let value = KeyboardVariantPolicy.gestureCandidates(for: "a", original: "a", state: .init(), settings: settings)
        XCTAssertEqual(value.longPress.map { Array($0.utf16) }, exact.map { Array($0.utf16) })
        XCTAssertEqual(value.swipeUp, ["↑"])
        XCTAssertEqual(value.swipeDown, ["↓"])
        XCTAssertEqual(settings.candidates(for: keyID, gesture: .swipeUp), ["A", "↑", "é"])
        let disabled = KeyboardKeySettings.Snapshot(overrides: [keyID: .init(longPress: [], swipeUp: [], swipeDown: [])])
        let none = KeyboardVariantPolicy.gestureCandidates(for: "a", original: "a", state: .init(), settings: disabled)
        XCTAssertTrue((none.longPress + none.swipeUp + none.swipeDown).isEmpty)
        let invalid = KeyboardVariantPolicy.gestureCandidates(for: "", original: "", state: .init(), settings: .defaults)
        XCTAssertTrue((invalid.longPress + invalid.swipeUp + invalid.swipeDown).isEmpty)
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

    func testHorizontalSelectionStartsInCenterAlternatesSidesAndClamps() {
        let fixtures: [(CGFloat, Int)] = [(0, 0), (CGFloat(18).nextDown, 0), (18, 1), (36, 1),
                                         (CGFloat(54).nextDown, 1), (54, 3), (-18, 2), (-100, 2), (1000, 3)]
        for (x, expected) in fixtures {
            XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: x, count: 4), expected)
        }
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: 5, count: 3, stride: 10), 1)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: -5, count: 3, stride: 10), 2)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: .greatestFiniteMagnitude, count: 17), 15)
        XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: -.greatestFiniteMagnitude, count: 17), 16)
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

    func testDefaultFormsFollowTheCurrentCaseWithoutChangingTypingState() {
        var lower = KeyboardTypingState()
        let beforeLower = lower
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "a", state: lower), ["ᵃ", "ₐ"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "a", state: lower),
                       ["𝐚", "𝑎", "𝒂", "𝒶", "𝓪", "𝔞", "𝕒", "𝗮", "𝚊", "ⓐ", "⒜", "ａ", "ᴀ"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "q", state: lower), [], "Q has no modifier letter")
        // Holes in the mathematical styles use the Letterlike Symbols encoded earlier.
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "q", state: lower).first, "𝐪")
        XCTAssertTrue(KeyboardVariantPolicy.defaultSwipeDown(for: "h", state: lower).contains("ℎ"))
        XCTAssertTrue(KeyboardVariantPolicy.defaultSwipeDown(for: "e", state: lower).contains("ℯ"))
        XCTAssertEqual(lower, beforeLower)
        lower.pressShift(at: 1)
        let beforeUpper = lower
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "a", state: lower), ["ᴬ"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "a", state: lower),
                       ["𝐀", "𝐴", "𝑨", "𝒜", "𝓐", "𝔄", "𝔸", "𝗔", "𝙰", "Ⓐ", "Ａ"])
        XCTAssertTrue(["ℛ", "ℜ", "ℝ"].allSatisfy(KeyboardVariantPolicy.defaultSwipeDown(for: "r", state: lower).contains))
        XCTAssertEqual(lower, beforeUpper)
        lower.pressShift(at: 1.1)
        XCTAssertEqual(lower.shift, .capsLock)
        for key in "abcdefghijklmnopqrstuvwxyz".map(String.init) {
            for state in [KeyboardTypingState(), lower] {
                let up = KeyboardVariantPolicy.defaultSwipeUp(for: key, state: state)
                let down = KeyboardVariantPolicy.defaultSwipeDown(for: key, state: state)
                XCTAssertGreaterThanOrEqual(down.count, 11, key)
                XCTAssertLessThanOrEqual(up.count, 2, key)
                XCTAssertFalse((up + down).contains { $0.lowercased() == key }, "Swipes never switch case: \(key)")
                XCTAssertTrue((up + down).allSatisfy { $0.unicodeScalars.count == 1 }, key)
            }
        }
    }

    func testDigitAndSymbolFormsSplitIntoModifiersAndStylesOnEveryPage() {
        var state = KeyboardTypingState()
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "2", state: state), ["²", "₂"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "2", state: state), ["𝟐", "𝟚", "𝟮", "𝟸", "②", "❷", "⑵", "⒉", "２"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "0", state: state), ["⁰", "₀"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "0", state: state), ["𝟎", "𝟘", "𝟬", "𝟶", "⓪", "⓿", "０"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "+", state: state), ["⁺", "₊"])
        XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "+", state: state), ["＋"])
        for key in ["", "A", "ab", "é", "e\u{301}", "$", "👩‍💻", " "] {
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: key, state: state), [])
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: key, state: state), [])
        }
        for layout in [KeyboardTypingLayout.numbers, .symbols] {
            state.selectLayout(layout)
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeDown(for: "a", state: state), [], "Letter forms stay on the letters page")
            XCTAssertEqual(KeyboardVariantPolicy.defaultSwipeUp(for: "0", state: state).first, "⁰")
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
    func testCenterOutOrderIsExactCompleteAndBounded() {
        XCTAssertEqual(KeyboardVariantPolicy.centerOutIndices(count: 7), [6, 4, 2, 0, 1, 3, 5])
        XCTAssertEqual(KeyboardVariantPolicy.centerOutIndices(count: 6), [4, 2, 0, 1, 3, 5])
        for count in 1...19 {
            let order = KeyboardVariantPolicy.centerOutIndices(count: count)
            XCTAssertEqual(order.sorted(), Array(0..<count))
            XCTAssertEqual(order[(count - 1) / 2], 0)
            if count <= 17 {
                for (position, logical) in order.enumerated() {
                    let delta = CGFloat(position - (count - 1) / 2) * 36
                    XCTAssertEqual(KeyboardVariantPolicy.horizontalChoice(deltaX: delta, count: count), logical)
                }
            }
        }
        for count in [Int.min, -1, 0, 20, Int.max] {
            XCTAssertEqual(KeyboardVariantPolicy.centerOutIndices(count: count), [])
        }
    }

    func testCenteredPopupMapsVisualCellsBackToExactChoicesAndKeepsCommandsTrailing() throws {
        let container = CGRect(x: 0, y: 0, width: 700, height: 400)
        let anchor = CGRect(x: 329, y: 220, width: 42, height: 42)
        let layout = try XCTUnwrap(KeyboardVariantPopupLayout(anchor: anchor, container: container, count: 9, choiceCount: 7))
        let order = layout.cells.indices.sorted { layout.cells[$0].minX < layout.cells[$1].minX }
        XCTAssertEqual(order, [6, 4, 2, 0, 1, 3, 5, 7, 8])
        XCTAssertEqual(layout.frame.minX + layout.cells[0].midX, anchor.midX, accuracy: 0.001)
        for (logical, frame) in layout.cells.enumerated() {
            XCTAssertEqual(layout.index(at: CGPoint(x: frame.midX, y: frame.midY)), logical)
        }
        for choices in [Int.min, -1, 0, 10, Int.max] {
            XCTAssertNil(KeyboardVariantPopupLayout(anchor: anchor, container: container, count: 9, choiceCount: choices))
        }
        for width: CGFloat in [100, 220, 402] {
            let wrapped = try XCTUnwrap(KeyboardVariantPopupLayout(anchor: CGRect(x: 24, y: 240, width: 42, height: 42),
                container: CGRect(x: 0, y: 0, width: width, height: 400), count: 19, choiceCount: 17))
            XCTAssertEqual(Set(wrapped.cells.map { "\($0.midX),\($0.midY)" }).count, 19)
            for (logical, frame) in wrapped.cells.enumerated() {
                XCTAssertEqual(wrapped.index(at: CGPoint(x: frame.midX, y: frame.midY)), logical)
            }
        }
    }

}
