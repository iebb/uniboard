import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardInteractionPolicyTests: XCTestCase {
    func testSearchKeepsNormalKeyHeightAndReservesResultsInsteadOfSqueezingKeys() {
        for pad in [false, true] {
            for width: CGFloat in [320, 402, 535, 536, 665, 666, 1032, 1376] {
                for compact in [false, true] {
                    for bar in [false, true] {
                        let metrics = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil, sceneHeight: 1400,
                            isPad: pad, compactVertical: compact, showsSymbolBar: bar, searching: true)
                        let side = KeyboardLayoutPolicy.searchUsesSideResults(availableWidth: width - 16, isPad: pad, isCompact: metrics.isCompactLayout)
                        let key = KeyboardTypingLayoutPolicy.typingKeyHeight(availableWidth: width - 16, isPad: pad)
                        XCTAssertEqual(metrics.typingKeyHeight, key, accuracy: 0.000001)
                        XCTAssertEqual(metrics.height, key * (side ? 6 : 7) + (side ? 30 : 34), accuracy: 0.000001)
                    }
                }
            }
        }
        for width: CGFloat in [.nan, .infinity, -.infinity, -1, 0, 519, 520] {
            XCTAssertEqual(KeyboardLayoutPolicy.searchUsesSideResults(availableWidth: width, isPad: true, isCompact: false), width == 520)
            XCTAssertFalse(KeyboardLayoutPolicy.searchUsesSideResults(availableWidth: width, isPad: false, isCompact: false))
            XCTAssertTrue(KeyboardLayoutPolicy.searchUsesSideResults(availableWidth: width, isPad: false, isCompact: true))
            for scene: CGFloat in [.nan, .infinity, -.infinity, -1, 0, 10, 200] {
                let result = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil, sceneHeight: scene,
                    isPad: true, compactVertical: false, showsSymbolBar: false, searching: true)
                XCTAssertTrue(result.height.isFinite); XCTAssertGreaterThan(result.height, 0)
                XCTAssertTrue(result.typingKeyHeight.isFinite); XCTAssertGreaterThan(result.typingKeyHeight, 0)
            }
        }
        let capped = KeyboardLayoutPolicy.metrics(viewWidth: 402, displaySize: nil, sceneHeight: 200,
            isPad: false, compactVertical: false, showsSymbolBar: false, searching: true)
        XCTAssertEqual(capped.height, 170)
        XCTAssertEqual(capped.typingKeyHeight * 7 + 34, capped.height, accuracy: 0.000001)
    }

    func testFixedTemplateHasFiveRowsAndAtMostOneOptionalBar() {
        XCTAssertEqual(KeyboardLayoutPolicy.defaultHeight, 278.4, accuracy: 0.000001)
        for pad in [false, true] {
            for width: CGFloat in [320, 402, 665, 666, 834, 1194] {
                for bar in [false, true] {
                    let result = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil, sceneHeight: 1200,
                        isPad: pad, compactVertical: false, showsSymbolBar: bar)
                    let key: CGFloat = pad && width >= 666 ? 52 * 1.15 : 36 * 1.15
                    let gap: CGFloat = pad && width >= 666 ? 6 : 4
                    XCTAssertEqual(result.typingKeyHeight, key, accuracy: 0.000001)
                    XCTAssertEqual(result.height, key * (bar ? 6 : 5) + gap * 3 + 18, accuracy: 0.000001)
                    let browsing = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil, sceneHeight: 1200,
                        isPad: pad, compactVertical: false, showsSymbolBar: bar, browsing: true)
                    XCTAssertEqual(browsing.height - result.height, key * 2, accuracy: 0.000001, "Browsing shows two more rows")
                    XCTAssertEqual(browsing.typingKeyHeight, key, accuracy: 0.000001)
                }
            }
        }
    }
    func testHidingTheNumberRowRemovesOneRowAndOneGapButNotFromSearch() {
        for pad in [false, true] {
            for width: CGFloat in [320, 402, 834] {
                for bar in [false, true] {
                    let shown = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil, sceneHeight: 1200,
                        isPad: pad, compactVertical: false, showsSymbolBar: bar)
                    let hidden = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil, sceneHeight: 1200,
                        isPad: pad, compactVertical: false, showsSymbolBar: bar, showsNumberRow: false)
                    let gap: CGFloat = pad && width >= 666 ? 6 : 4
                    XCTAssertEqual(hidden.typingKeyHeight, shown.typingKeyHeight, accuracy: 0.000001)
                    XCTAssertEqual(shown.height - hidden.height, shown.typingKeyHeight + gap, accuracy: 0.000001)
                    let searching = { (numbers: Bool) in KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: nil,
                        sceneHeight: 1200, isPad: pad, compactVertical: false, showsSymbolBar: bar,
                        showsNumberRow: numbers, searching: true).height }
                    XCTAssertEqual(searching(false), searching(true), accuracy: 0.000001)
                }
            }
        }
    }
    func testFixedTemplateRotationWidthAndInvalidSceneValuesFailSafely() {
        let phone = CGSize(width: 402, height: 874)
        for width: CGFloat in [402, 430, 874, .nan, .infinity] {
            for compact in [false, true] {
                let result = KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: phone, sceneHeight: nil,
                    isPad: false, compactVertical: compact, showsSymbolBar: true)
                XCTAssertEqual(result.isCompactLayout, width.isFinite ? width == 874 : compact)
                XCTAssertTrue(result.height.isFinite); XCTAssertGreaterThan(result.height, 0)
            }
        }
        for size in [CGSize(width: CGFloat.nan, height: 874), CGSize(width: 0, height: 874), CGSize(width: 402, height: CGFloat.infinity)] {
            XCTAssertTrue(KeyboardLayoutPolicy.metrics(viewWidth: 874, displaySize: size, sceneHeight: nil,
                isPad: false, compactVertical: true, showsSymbolBar: false).isCompactLayout)
        }
        for scene: CGFloat in [.nan, .infinity, -.infinity, 0, -1, 10, 200] {
            let result = KeyboardLayoutPolicy.metrics(viewWidth: 402, displaySize: nil, sceneHeight: scene,
                isPad: false, compactVertical: true, showsSymbolBar: true)
            XCTAssertTrue(result.height.isFinite); XCTAssertGreaterThan(result.typingKeyHeight, 0)
            XCTAssertLessThanOrEqual(result.typingKeyHeight, 36 * 1.15)
        }
    }

    func testUTF16BoundariesIncludeWholeEmojiAndCombiningCharacters() {
        XCTAssertEqual(KeyboardQueryPolicy.utf16Boundaries(in: ""), [0])
        XCTAssertEqual(KeyboardQueryPolicy.utf16Boundaries(in: "A🚀e\u{301}👩‍💻🇯🇵1️⃣"), [0, 1, 3, 5, 10, 14, 17])
        XCTAssertEqual(KeyboardQueryPolicy.normalizedUTF16Offset(2, in: "A🚀B"), 1) // Equal distances prefer the earlier boundary.
        XCTAssertEqual(KeyboardQueryPolicy.normalizedUTF16Offset(3, in: "A🚀B"), 3)
    }

    func testExtremeCaretOffsetsClampBeforeDistanceArithmetic() {
        for text in ["", "abc", "🚀", "e\u{301}", "🙂‍↔️", "العربية עברית"] {
            XCTAssertEqual(KeyboardQueryPolicy.normalizedUTF16Offset(Int.min, in: text), 0)
            XCTAssertEqual(KeyboardQueryPolicy.normalizedUTF16Offset(Int.max, in: text), text.utf16.count)
            XCTAssertEqual(KeyboardQueryPolicy.utf16Offset(forCharacterOffset: Int.min, in: text), 0)
            XCTAssertEqual(KeyboardQueryPolicy.utf16Offset(forCharacterOffset: Int.max, in: text), text.utf16.count)
        }
    }

    func testEveryNormalizedOffsetIsAGraphemeBoundary() {
        for text in ["A🚀e\u{301}👩‍💻🇯🇵1️⃣", "क्‍ष العربية עברית", String(repeating: "a\u{301}🚀", count: 300)] {
            let boundaries = KeyboardQueryPolicy.utf16Boundaries(in: text)
            for offset in -2...(text.utf16.count + 2) {
                let normalized = KeyboardQueryPolicy.normalizedUTF16Offset(offset, in: text)
                XCTAssertTrue(boundaries.contains(normalized))
                let character = KeyboardQueryPolicy.characterOffset(forUTF16Offset: offset, in: text)
                XCTAssertEqual(KeyboardQueryPolicy.utf16Offset(forCharacterOffset: character, in: text), normalized)
            }
        }
    }

    func testMiddleInsertionAndDeletionKeepLocalCaret() {
        let inserted = KeyboardQueryPolicy.inserting("arrow ", into: "cat", caretUTF16Offset: 0)
        XCTAssertEqual(inserted.text, "arrow cat")
        XCTAssertEqual(inserted.caretUTF16Offset, 6)
        let deleted = KeyboardQueryPolicy.deletingBackward(from: inserted.text, caretUTF16Offset: inserted.caretUTF16Offset)
        XCTAssertEqual(deleted.text, "arrowcat")
        XCTAssertEqual(deleted.caretUTF16Offset, 5)
    }

    func testCombiningAndZWJInsertionLandAfterTheMergedGrapheme() {
        let acute = KeyboardQueryPolicy.inserting("\u{301}", into: "ab", caretUTF16Offset: 1)
        XCTAssertEqual(acute.text, "a\u{301}b")
        XCTAssertEqual(acute.caretCharacterOffset, 1)
        XCTAssertEqual(acute.caretUTF16Offset, 2)
        let joined = KeyboardQueryPolicy.inserting("\u{200D}", into: "👩💻", caretUTF16Offset: 2)
        XCTAssertEqual(joined.text, "👩‍💻")
        XCTAssertEqual(joined.caretCharacterOffset, 1)
        XCTAssertEqual(joined.caretUTF16Offset, 5)
    }

    func testDeletionRemovesWholeQualifiedEmojiAndHandlesNeighborMerges() {
        let deleted = KeyboardQueryPolicy.deletingBackward(from: "A🙂‍↔️B", caretUTF16Offset: 6)
        XCTAssertEqual(deleted.text, "AB")
        XCTAssertEqual(deleted.caretUTF16Offset, 1)
        let merged = KeyboardQueryPolicy.deletingBackward(from: "🇦x🇧", caretUTF16Offset: 3)
        XCTAssertEqual(merged.text, "🇦🇧")
        XCTAssertEqual(merged.caretCharacterOffset, 1)
        XCTAssertEqual(merged.caretUTF16Offset, 4)
    }

    func testInsertionLimitNeverSplitsAnExtendedGrapheme() {
        let original = String(repeating: "a", count: 99)
        let inserted = KeyboardQueryPolicy.inserting("👩🏽‍💻🚀z", into: original, caretUTF16Offset: 99)
        XCTAssertEqual(inserted.text, original + "👩🏽‍💻")
        XCTAssertEqual(inserted.text.count, 100)
        XCTAssertEqual(inserted.caretUTF16Offset, inserted.text.utf16.count)
        let atLimit = String(repeating: "a", count: 100)
        XCTAssertEqual(KeyboardQueryPolicy.inserting("b", into: atLimit, caretUTF16Offset: 50).text, atLimit)
        XCTAssertEqual(KeyboardQueryPolicy.inserting("\u{301}", into: atLimit, caretUTF16Offset: 50).text, atLimit)
    }

    func testLimitWithNeighborMergesAndInvalidLimitsPreservesExistingText() {
        let original = String(repeating: "a", count: 99)
        let merged = KeyboardQueryPolicy.inserting("\u{301}z", into: original, caretUTF16Offset: 99)
        XCTAssertEqual(merged.text, original + "\u{301}")
        XCTAssertEqual(merged.text.count, 99)
        let joined = KeyboardQueryPolicy.inserting("\u{200D}z", into: String(repeating: "a", count: 97) + "👩💻", caretUTF16Offset: 99)
        XCTAssertEqual(joined.text, String(repeating: "a", count: 97) + "👩‍💻")
        XCTAssertEqual(joined.text.count, 98)
        for limit in [Int.min, -1, 0, 2] {
            XCTAssertEqual(KeyboardQueryPolicy.inserting("xyz", into: "abc", caretUTF16Offset: Int.max, maximumCharacters: limit).text, "abc")
        }
        XCTAssertEqual(KeyboardQueryPolicy.inserting("xyz", into: "abc", caretUTF16Offset: Int.max, maximumCharacters: Int.max).text, "abcxyz")
    }

    func testEmptyEditsAndOutOfRangeCaretsAreSafe() {
        XCTAssertEqual(KeyboardQueryPolicy.inserting("", into: "abc", caretUTF16Offset: Int.min).caretUTF16Offset, 0)
        XCTAssertEqual(KeyboardQueryPolicy.inserting("🚀", into: "", caretUTF16Offset: Int.max).text, "🚀")
        XCTAssertEqual(KeyboardQueryPolicy.deletingBackward(from: "", caretUTF16Offset: Int.max).text, "")
        XCTAssertEqual(KeyboardQueryPolicy.deletingBackward(from: "abc", caretUTF16Offset: Int.min).text, "abc")
        XCTAssertEqual(KeyboardQueryPolicy.deletingBackward(from: "abc", caretUTF16Offset: Int.max).text, "ab")
    }

    func testLongRTLQueryEditsPreserveExactTextAndWholeCharacters() {
        let text = String(repeating: "العربية עברית a\u{301}🚀 ", count: 100)
        let inserted = KeyboardQueryPolicy.inserting("👩‍💻", into: text, caretUTF16Offset: Int.max, maximumCharacters: Int.max)
        XCTAssertEqual(inserted.text, text + "👩‍💻")
        XCTAssertEqual(inserted.caretUTF16Offset, inserted.text.utf16.count)
        XCTAssertEqual(KeyboardQueryPolicy.deletingBackward(from: inserted.text, caretUTF16Offset: inserted.caretUTF16Offset).text, text)
    }

    func testVisualCaretHitTestingRespectsRTLAndMixedRunEdges() {
        XCTAssertEqual(KeyboardQueryPolicy.nearestVisualBoundary(to: .nan, boundaries: []) { _ in 0 }, 0)
        let rtl: [Int: CGFloat] = [0: 30, 1: 20, 2: 10, 3: 0]
        XCTAssertEqual(KeyboardQueryPolicy.nearestVisualBoundary(to: -100, boundaries: [0, 1, 2, 3]) { rtl[$0]! }, 3)
        XCTAssertEqual(KeyboardQueryPolicy.nearestVisualBoundary(to: 100, boundaries: [0, 1, 2, 3]) { rtl[$0]! }, 0)
        XCTAssertEqual(KeyboardQueryPolicy.nearestVisualBoundary(to: 9, boundaries: [1, 2]) { rtl[$0]! }, 2)
        XCTAssertEqual(KeyboardQueryPolicy.nearestVisualBoundary(to: .nan, boundaries: [0, 3]) { rtl[$0]! }, 0)
        XCTAssertEqual(KeyboardQueryPolicy.nearestVisualBoundary(to: 10, boundaries: []) { _ in .nan }, 0)
    }

    func testPixelAlignmentHandlesDifferentDisplaysAndInvalidNumbers() {
        XCTAssertEqual(KeyboardQueryViewportPolicy.pixelAligned(1.26, scale: 2), 1.5)
        XCTAssertEqual(KeyboardQueryViewportPolicy.pixelAligned(1.26, scale: 3), 4.0 / 3.0)
        XCTAssertEqual(KeyboardQueryViewportPolicy.pixelAligned(1.01, scale: 3, rule: .up), 4.0 / 3.0)
        let values: [CGFloat] = [.nan, .infinity, -.infinity, -1, 0, .leastNonzeroMagnitude, 1.26, .greatestFiniteMagnitude]
        for value in values {
            for scale in values {
                XCTAssertTrue(KeyboardQueryViewportPolicy.pixelAligned(value, scale: scale).isFinite)
            }
        }
    }

    func testCaretViewportRevealsBothEndsAndAdaptsToWidthChanges() {
        XCTAssertEqual(KeyboardQueryViewportPolicy.horizontalOffset(caretX: 280, previousOffset: 0, viewportWidth: 100, contentWidth: 300, scale: 2), 190)
        XCTAssertEqual(KeyboardQueryViewportPolicy.horizontalOffset(caretX: 10, previousOffset: 190, viewportWidth: 100, contentWidth: 300, scale: 2), 2)
        XCTAssertEqual(KeyboardQueryViewportPolicy.horizontalOffset(caretX: 0, previousOffset: 190, viewportWidth: 100, contentWidth: 300, scale: 2), 0)
        XCTAssertEqual(KeyboardQueryViewportPolicy.horizontalOffset(caretX: 298, previousOffset: 0, viewportWidth: 100, contentWidth: 300, scale: 3), 200)
        XCTAssertEqual(KeyboardQueryViewportPolicy.horizontalOffset(caretX: 280, previousOffset: 190, viewportWidth: 500, contentWidth: 500, scale: 3), 0)
    }

    func testViewportNumericBoundaryMatrixAlwaysReturnsABoundedFiniteOffset() {
        let values: [CGFloat] = [.nan, .infinity, -.infinity, -1, 0, .leastNonzeroMagnitude, 1, 50, 300, .greatestFiniteMagnitude]
        for caret in values {
            for width in values {
                for content in values {
                    let offset = KeyboardQueryViewportPolicy.horizontalOffset(caretX: caret, previousOffset: caret,
                        viewportWidth: width, contentWidth: content, scale: width)
                    XCTAssertTrue(offset.isFinite)
                    XCTAssertGreaterThanOrEqual(offset, 0)
                    if width.isFinite && width > 0 && content.isFinite && content >= 0 {
                        XCTAssertLessThanOrEqual(offset, max(0, content - width))
                    }
                }
            }
        }
    }
    func testSymbolPagingRoundsClampsAndAdvancesOnlyOneNeighbor() {
        for (offset, expected) in [(CGFloat(-100), 0), (0, 0), (49, 0), (50, 1), (150, 2), (10000, 16)] {
            XCTAssertEqual(KeyboardSymbolPagePolicy.index(offset: offset, width: 100, count: 17), expected)
        }
        XCTAssertEqual(KeyboardSymbolPagePolicy.index(offset: 10000, width: 100, count: 17, startingAt: 8), 9)
        XCTAssertEqual(KeyboardSymbolPagePolicy.index(offset: -10000, width: 100, count: 17, startingAt: 8), 7)
        XCTAssertEqual(KeyboardSymbolPagePolicy.index(offset: 10000, width: 100, count: 1, startingAt: 0), 0)
    }
    func testSymbolPagingRejectsInvalidCountsTravelWidthsAndStarts() {
        for count in [Int.min, -1, 0, 18, Int.max] {
            XCTAssertNil(KeyboardSymbolPagePolicy.index(offset: 0, width: 100, count: count))
        }
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardSymbolPagePolicy.index(offset: value, width: 100, count: 3))
        }
        for width: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardSymbolPagePolicy.index(offset: 0, width: width, count: 3))
        }
        for start in [Int.min, -1, 3, Int.max] {
            XCTAssertNil(KeyboardSymbolPagePolicy.index(offset: 0, width: 100, count: 3, startingAt: start))
        }
        XCTAssertNil(KeyboardSymbolPagePolicy.index(offset: .greatestFiniteMagnitude, width: .leastNonzeroMagnitude, count: 3))
    }

}
