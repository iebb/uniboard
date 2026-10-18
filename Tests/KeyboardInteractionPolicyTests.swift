import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardInteractionPolicyTests: XCTestCase {
    private func metrics(width: CGFloat = 402, display: CGSize? = CGSize(width: 402, height: 874),
                         sceneHeight: CGFloat? = 874, pad: Bool = false, compact: Bool = false,
                         search: Bool = false, inspect: Bool = false, browse: CGFloat = 300,
                         expanded: CGFloat = 340) -> KeyboardLayoutPolicy.Metrics {
        KeyboardLayoutPolicy.metrics(viewWidth: width, displaySize: display, sceneHeight: sceneHeight,
            isPad: pad, compactVertical: compact, isSearching: search, isInspecting: inspect,
            portraitBrowseHeight: browse, portraitExpandedHeight: expanded)
    }

    func testPortraitDefaultsAndIndependentExpandedModes() {
        XCTAssertEqual(metrics().height, 300)
        XCTAssertEqual(metrics(search: true).height, 340)
        XCTAssertEqual(metrics(inspect: true).height, 340)
        XCTAssertEqual(metrics(search: true, inspect: true).height, 340)
        XCTAssertEqual(metrics(browse: 260, expanded: 390).height, 260)
        XCTAssertEqual(metrics(search: true, browse: 260, expanded: 390).height, 390)
        XCTAssertEqual(metrics().portraitResizeRange, 220...420)
        XCTAssertEqual(metrics(search: true).portraitResizeRange, 340...420)
    }

    func testActualWidthWinsOverStalePhoneTraitsAndSceneOrientation() {
        let landscape = metrics(width: 874, sceneHeight: 874, compact: false, search: true)
        XCTAssertTrue(landscape.isCompactLayout)
        XCTAssertEqual(landscape.height, 220)
        XCTAssertNil(landscape.portraitResizeRange)
        let portraitAgain = metrics(width: 402, display: CGSize(width: 874, height: 402), sceneHeight: 402, compact: true)
        XCTAssertFalse(portraitAgain.isCompactLayout)
        XCTAssertEqual(portraitAgain.height, 300)
        XCTAssertEqual(portraitAgain.portraitResizeRange, 220...420)
    }

    func testOrientationThresholdAndMissingGeometryFallback() {
        let display = CGSize(width: 400, height: 800)
        XCTAssertFalse(metrics(width: 440, display: display).isCompactLayout)
        XCTAssertTrue(metrics(width: 440.1, display: display).isCompactLayout)
        XCTAssertTrue(metrics(width: .nan, display: display, compact: true).isCompactLayout)
        XCTAssertTrue(metrics(display: nil, compact: true).isCompactLayout)
        XCTAssertFalse(metrics(display: nil, compact: false).isCompactLayout)
        XCTAssertFalse(metrics(width: .greatestFiniteMagnitude, display: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).isCompactLayout)
    }

    func testSceneCapsAndFractionalSingletonResizeRange() {
        let phone = metrics(width: 320, display: CGSize(width: 320, height: 568), search: true)
        XCTAssertEqual(phone.height, 568 * 0.55, accuracy: 0.0001)
        XCTAssertEqual(phone.portraitResizeRange?.lowerBound, phone.height)
        XCTAssertEqual(phone.portraitResizeRange?.upperBound, phone.height)
        XCTAssertEqual(metrics(width: 568, display: CGSize(width: 320, height: 568)).height, 192)
        for expanded in [false, true] {
            let pad = metrics(sceneHeight: 600, pad: true, search: expanded)
            XCTAssertEqual(pad.height, 300)
            XCTAssertFalse(pad.isCompactLayout)
            XCTAssertNil(pad.portraitResizeRange)
        }
        XCTAssertEqual(metrics(pad: true).height, 340)
        XCTAssertEqual(metrics(pad: true, search: true).height, 380)
    }

    func testStoredHeightsAreFiniteAndBounded() {
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(metrics(browse: invalid).height, 300)
            XCTAssertEqual(metrics(search: true, expanded: invalid).height, 340)
        }
        XCTAssertEqual(metrics(browse: -1).height, 220)
        XCTAssertEqual(metrics(browse: .greatestFiniteMagnitude).height, 420)
        XCTAssertEqual(metrics(search: true, expanded: -1).height, 340)
        XCTAssertEqual(metrics(search: true, expanded: .greatestFiniteMagnitude).height, 420)
    }

    func testLayoutBoundaryMatrixNeverProducesNonfiniteOrNegativeGeometry() {
        let values: [CGFloat] = [.nan, .infinity, -.infinity, -1, 0, .leastNonzeroMagnitude, 1, 402, 874, .greatestFiniteMagnitude]
        let displays: [CGSize?] = [nil, CGSize(width: 402, height: 874), CGSize(width: 874, height: 402),
            CGSize(width: CGFloat.nan, height: 874), CGSize(width: 402, height: CGFloat.infinity),
            CGSize(width: -1, height: 874), CGSize(width: 0, height: 874),
            CGSize(width: CGFloat.leastNonzeroMagnitude, height: CGFloat.leastNonzeroMagnitude),
            CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)]
        for width in values {
            for display in displays {
                for scene in values {
                    for pad in [false, true] {
                        for expanded in [false, true] {
                            let result = metrics(width: width, display: display, sceneHeight: scene, pad: pad,
                                compact: true, search: expanded, browse: width, expanded: scene)
                            XCTAssertTrue(result.height.isFinite)
                            XCTAssertGreaterThan(result.height, 0)
                            XCTAssertLessThanOrEqual(result.height, 420)
                            if let range = result.portraitResizeRange {
                                XCTAssertTrue(range.lowerBound.isFinite && range.upperBound.isFinite)
                                XCTAssertGreaterThan(range.lowerBound, 0)
                                XCTAssertTrue(range.contains(result.height))
                            }
                        }
                    }
                }
            }
        }
    }

    func testResizeTargetsMatchTheFourNativeEndpointFixtures() {
        let range: ClosedRange<CGFloat> = 220...420
        for (start, delta, expected): (CGFloat, CGFloat, CGFloat) in [(300, -120, 420), (420, 120, 300), (300, -100, 400), (400, 100, 300)] {
            XCTAssertEqual(KeyboardResizePolicy.target(startHeight: start, translationY: delta, in: range), expected)
        }
    }

    func testResizeRoundingStaysInsideFractionalCaps() {
        for range: ClosedRange<CGFloat> in [312.4...312.4, 220.6...300.2, 340.2...340.4] {
            for value: CGFloat in [-1000, 0, 220.4, 300.9, 340.3, 1000] {
                let height = KeyboardResizePolicy.clampedHeight(value, in: range)
                XCTAssertNotNil(height)
                XCTAssertTrue(range.contains(height!))
            }
        }
        XCTAssertEqual(KeyboardResizePolicy.clampedHeight(220.4, in: 220...420), 220)
        XCTAssertEqual(KeyboardResizePolicy.clampedHeight(220.5, in: 220...420), 221)
    }

    func testBrowseToggleUsesTheAvailableRangeMidpoint() {
        for (range, compact, expanded): (ClosedRange<CGFloat>, CGFloat, CGFloat) in [
            (220...420, 220, 420), (220...312.4, 220, 312.4)] {
            XCTAssertEqual(KeyboardResizePolicy.toggledHeight(current: compact, range: range), expanded)
            XCTAssertEqual(KeyboardResizePolicy.toggledHeight(current: expanded, range: range), compact)
            XCTAssertEqual(KeyboardResizePolicy.toggledHeight(current: compact + (expanded - compact) / 2, range: range), compact)
        }
        XCTAssertEqual(KeyboardResizePolicy.toggledHeight(current: 300, range: 220...420), 420)
        XCTAssertEqual(KeyboardResizePolicy.toggledHeight(current: 300, range: 220...312.4), 220)
        XCTAssertEqual(KeyboardResizePolicy.toggledHeight(current: 312.4, range: 312.4...312.4), 312.4)
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardResizePolicy.toggledHeight(current: invalid, range: 220...420))
        }
    }

    func testResizeRejectsInvalidNumbersAndSaturatesFiniteOverflow() {
        let range: ClosedRange<CGFloat> = 220...420
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardResizePolicy.target(startHeight: 300, translationY: invalid, in: range))
            XCTAssertNil(KeyboardResizePolicy.target(startHeight: invalid, translationY: 0, in: range))
            XCTAssertNil(KeyboardResizePolicy.clampedHeight(invalid, in: range))
        }
        XCTAssertEqual(KeyboardResizePolicy.target(startHeight: 300, translationY: -.greatestFiniteMagnitude, in: range), 420)
        XCTAssertEqual(KeyboardResizePolicy.target(startHeight: 300, translationY: .greatestFiniteMagnitude, in: range), 220)
        XCTAssertNil(KeyboardResizePolicy.clampedHeight(100, in: 0...420))
        XCTAssertNil(KeyboardResizePolicy.clampedHeight(100, in: 1...CGFloat.infinity))
    }

    func testPanCorrectionIncludesOnlyTheInitialRecognitionSlop() {
        let correction = KeyboardResizePolicy.initialPanCorrection(currentY: 20, touchDownY: 30, translationY: -2)
        XCTAssertEqual(correction, -8)
        XCTAssertEqual(KeyboardResizePolicy.panDelta(translationY: -2, initialCorrection: correction!), -10)
        XCTAssertEqual(KeyboardResizePolicy.panDelta(translationY: -112, initialCorrection: correction!), -120)
        XCTAssertEqual(KeyboardResizePolicy.initialPanCorrection(currentY: 20, touchDownY: nil, translationY: -2), 0)
    }

    func testCancelledCappedSceneDragPreservesTheLargerSavedPreference() throws {
        let capped: ClosedRange<CGFloat> = 220...312.4
        var session = try XCTUnwrap(KeyboardResizeSession(preferredHeight: 420, visibleHeight: 312.4, fallbackHeight: 300, range: capped))
        XCTAssertEqual(session.startHeight, 312.4)
        XCTAssertEqual(session.preferredHeight, 420)
        XCTAssertEqual(session.target(translationY: 40, range: capped), 272)
        XCTAssertNil(session.finish(commitHeight: nil, range: capped))
        XCTAssertEqual(session.preferredHeight, 420)
        XCTAssertEqual(metrics(browse: session.preferredHeight).height, 420)
        XCTAssertNil(session.target(translationY: 0, range: capped))
        XCTAssertNil(session.finish(commitHeight: 250, range: capped))
    }

    func testSuccessfulCappedSceneDragCommitsOnlyItsFinalTarget() throws {
        let capped: ClosedRange<CGFloat> = 220...312.4
        var session = try XCTUnwrap(KeyboardResizeSession(preferredHeight: 420, visibleHeight: 312.4, fallbackHeight: 300, range: capped))
        XCTAssertEqual(session.preferredHeight, 420)
        let target = try XCTUnwrap(session.target(translationY: 12.4, range: capped))
        XCTAssertEqual(target, 300)
        XCTAssertEqual(session.preferredHeight, 420)
        XCTAssertEqual(session.finish(commitHeight: target, range: capped), 300)
        XCTAssertEqual(session.preferredHeight, 300)
        XCTAssertEqual(metrics(browse: session.preferredHeight).height, 300)
        XCTAssertNil(session.finish(commitHeight: 250, range: capped))
    }

    func testResizeSessionInvalidValuesCannotChangeItsPreference() throws {
        for invalid: CGFloat in [.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(KeyboardResizeSession(preferredHeight: invalid, visibleHeight: 300, fallbackHeight: 300, range: 220...420))
        }
        var session = try XCTUnwrap(KeyboardResizeSession(preferredHeight: 420, visibleHeight: .nan, fallbackHeight: 300, range: 220...420))
        XCTAssertEqual(session.startHeight, 300)
        XCTAssertNil(session.finish(commitHeight: .nan, range: 220...420))
        XCTAssertEqual(session.preferredHeight, 420)
        XCTAssertNil(session.finish(commitHeight: 300, range: 220...420))
    }

    func testPanRejectsNonfiniteInputsAndArithmeticOverflow() {
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardResizePolicy.initialPanCorrection(currentY: invalid, touchDownY: 0, translationY: 0))
            XCTAssertNil(KeyboardResizePolicy.initialPanCorrection(currentY: 0, touchDownY: invalid, translationY: 0))
            XCTAssertNil(KeyboardResizePolicy.initialPanCorrection(currentY: 0, touchDownY: 0, translationY: invalid))
            XCTAssertNil(KeyboardResizePolicy.panDelta(translationY: invalid, initialCorrection: 0))
            XCTAssertNil(KeyboardResizePolicy.panDelta(translationY: 0, initialCorrection: invalid))
        }
        XCTAssertNil(KeyboardResizePolicy.initialPanCorrection(currentY: .greatestFiniteMagnitude, touchDownY: -.greatestFiniteMagnitude, translationY: 0))
        XCTAssertNil(KeyboardResizePolicy.panDelta(translationY: .greatestFiniteMagnitude, initialCorrection: .greatestFiniteMagnitude))
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
}
