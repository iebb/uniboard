import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class KeyboardResizeStepPolicyTests: XCTestCase {
    private let range: ClosedRange<CGFloat> = 220...420

    private func target(_ delta: CGFloat, start: CGFloat = 300, compact: Bool = false,
                        range: ClosedRange<CGFloat> = 220...420, threshold: CGFloat = 12) -> CGFloat? {
        KeyboardResizeStepPolicy.target(startHeight: start, deltaY: delta, range: range,
            compact: compact, minimumTranslation: threshold)
    }

    func testRowStrideMatchesFixedEnglishKeycapsAndGap() {
        XCTAssertEqual(KeyboardResizeStepPolicy.rowStride(compact: false), 40)
        XCTAssertEqual(KeyboardResizeStepPolicy.rowStride(compact: true), 40)
        XCTAssertEqual(KeyboardResizeStepPolicy.rowStride(compact: false),
                       KeyboardTypingLayoutPolicy.regularKeyHeight + KeyboardTypingLayoutPolicy.rowSpacing)
        XCTAssertEqual(KeyboardResizeStepPolicy.minimumTranslation, 12)
    }

    func testFeedbackHasNoInventedDirectionBeforeTheReleaseThreshold() {
        for delta: CGFloat in [0, -0.0, 1, -1, CGFloat(12).nextDown, -CGFloat(12).nextDown] {
            XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: delta, range: range, compact: false))
        }
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: -12, range: range, compact: false),
                       .init(direction: .up))
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: 12, range: range, compact: false),
                       .init(direction: .down))
    }

    func testFeedbackChangesOnlyWithDirectionOrWhetherTheBoundAllowsAStep() {
        let up = KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: -12, range: range, compact: false)
        for delta: CGFloat in [-13, -48, -1_000, -.greatestFiniteMagnitude] {
            XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: delta, range: range, compact: false), up)
        }
        let down = KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: 12, range: range, compact: true)
        XCTAssertNotEqual(up, down)
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: 120, range: range, compact: true), down)
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: 0, range: range, compact: false))
    }

    func testFeedbackIsAbsentForOutwardSwipesAndVisibleForPartialRows() {
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 420, deltaY: -120, range: range, compact: false))
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 220, deltaY: 120, range: range, compact: false))
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: -12, range: 220...312.4, compact: false),
                       .init(direction: .up))
        for compact in [false, true] {
            for delta: CGFloat in [-CGFloat.greatestFiniteMagnitude, -120, -12, 12, 120, CGFloat.greatestFiniteMagnitude] {
                XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 312.4, deltaY: delta,
                    range: 312.4...312.4, compact: compact))
            }
        }
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 312.4, deltaY: 12, range: 220...312.4, compact: false),
                       .init(direction: .down))
        let tiny: ClosedRange<CGFloat> = 220...CGFloat(220).nextUp
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: tiny.lowerBound, deltaY: -12, range: tiny, compact: false),
                       .init(direction: .up))
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: tiny.upperBound, deltaY: -12, range: tiny, compact: false))
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: tiny.upperBound, deltaY: 12, range: tiny, compact: false),
                       .init(direction: .down))
    }

    func testSameSwipeRestoresFeedbackOnlyAfterReversingInwardAndCommitsOneRow() throws {
        for compact in [false, true] {
            for (start, outward, inward, end, direction): (CGFloat, CGFloat, CGFloat, CGFloat, KeyboardResizeStepPolicy.Direction) in [
                (420, -120, 120, 380, .down), (220, 120, -120, 260, .up)
            ] {
                var session = try XCTUnwrap(KeyboardResizeStepSession(startHeight: start, range: range, compact: compact))
                XCTAssertTrue(session.update(deltaY: outward))
                XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: start, deltaY: outward, range: range, compact: compact))
                XCTAssertTrue(session.update(deltaY: 0))
                XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: start, deltaY: 0, range: range, compact: compact))
                XCTAssertTrue(session.update(deltaY: inward))
                XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: start, deltaY: inward, range: range, compact: compact),
                               .init(direction: direction))
                XCTAssertEqual(session.initialHeight, start)
                XCTAssertEqual(session.finish(commit: true), end)
                XCTAssertNil(session.finish(commit: true))
            }
        }
    }

    func testFeedbackCannotInventMovementOutsideClampedOrUnrepresentableRanges() {
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 500, deltaY: -12, range: range, compact: false))
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 500, deltaY: 12, range: range, compact: false),
                       .init(direction: .down))
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 100, deltaY: 12, range: range, compact: false))
        XCTAssertEqual(KeyboardResizeStepPolicy.feedback(startHeight: 100, deltaY: -12, range: range, compact: false),
                       .init(direction: .up))
        let enormous: ClosedRange<CGFloat> = CGFloat.leastNonzeroMagnitude...CGFloat.greatestFiniteMagnitude
        for delta: CGFloat in [-12, 12] {
            XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: .greatestFiniteMagnitude,
                deltaY: delta, range: enormous, compact: false))
        }
    }

    func testFeedbackRejectsInvalidSamplesAndInvalidSizingDomains() {
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: value, range: range, compact: false))
            XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: value, deltaY: -12, range: range, compact: false))
        }
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 0, deltaY: -12, range: range, compact: false))
        XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: -12, range: 0...420, compact: false))
        for range: ClosedRange<CGFloat> in [220...CGFloat.infinity, -CGFloat.infinity...420] {
            XCTAssertNil(KeyboardResizeStepPolicy.feedback(startHeight: 300, deltaY: -12, range: range, compact: false))
        }
    }

    func testRegularSwipesChooseOneRowRegardlessOfTheirDistance() {
        for distance: CGFloat in [12, 48, 96, 1_000, CGFloat.greatestFiniteMagnitude] {
            XCTAssertEqual(target(-distance), 340)
            XCTAssertEqual(target(distance), 260)
        }
    }

    func testCompactSwipesUseExactlyOneCompactRow() {
        for distance: CGFloat in [12, 42, 420, CGFloat.greatestFiniteMagnitude] {
            XCTAssertEqual(target(-distance, compact: true), 340)
            XCTAssertEqual(target(distance, compact: true), 260)
        }
    }

    func testThresholdIsInclusiveAndTinyNetMovementDoesNothing() {
        for delta: CGFloat in [0, -0.0, 1, -1, CGFloat(12).nextDown, -CGFloat(12).nextDown] {
            XCTAssertNil(target(delta))
        }
        XCTAssertEqual(target(-12), 340)
        XCTAssertEqual(target(12), 260)
        XCTAssertEqual(target(-1, threshold: 1), 340)
        XCTAssertNil(target(12, threshold: 13))
    }

    func testDirectionMustBePredominantlyVerticalWithoutATapAction() {
        for (x, y): (CGFloat, CGFloat) in [(0, 0), (0, 11.99), (40, 20), (12, 12), (-30, -12), (-12, 12)] {
            XCTAssertFalse(KeyboardResizeStepPolicy.isVerticalSwipe(deltaX: x, deltaY: y))
        }
        for (x, y): (CGFloat, CGFloat) in [(0, -12), (0, 12), (11, -12), (-11, 12), (12, 13)] {
            XCTAssertTrue(KeyboardResizeStepPolicy.isVerticalSwipe(deltaX: x, deltaY: y))
        }
    }

    func testNonfiniteDirectionsAndInvalidThresholdsFailClosed() {
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(target(value))
            XCTAssertFalse(KeyboardResizeStepPolicy.isVerticalSwipe(deltaX: value, deltaY: 20))
            XCTAssertFalse(KeyboardResizeStepPolicy.isVerticalSwipe(deltaX: 0, deltaY: value))
        }
        for threshold: CGFloat in [.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(target(-20, threshold: threshold))
            XCTAssertFalse(KeyboardResizeStepPolicy.isVerticalSwipe(deltaX: 0, deltaY: -20, minimumTranslation: threshold))
            XCTAssertNil(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false, minimumTranslation: threshold))
        }
    }

    func testInvalidStartAndRangeCannotAuthorizeAHeight() {
        for value: CGFloat in [.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(target(-20, start: value))
            XCTAssertNil(KeyboardResizeStepSession(startHeight: value, range: range, compact: false))
        }
        for invalidRange: ClosedRange<CGFloat> in [-1...420, 0...420, 220...CGFloat.infinity, -CGFloat.infinity...420] {
            XCTAssertNil(target(-20, range: invalidRange))
            XCTAssertNil(KeyboardResizeStepSession(startHeight: 300, range: invalidRange, compact: false))
        }
    }

    func testOutOfRangePositiveStartUsesTheCurrentModeCap() {
        XCTAssertEqual(target(-20, start: 100), 260)
        XCTAssertNil(target(20, start: 100))
        XCTAssertEqual(target(20, start: 500), 380)
        XCTAssertNil(target(-20, start: 500))
        XCTAssertEqual(target(-20, start: 300, range: 340...420), 380)
        XCTAssertNil(target(20, start: 300, range: 340...420))
    }

    func testBoundsPermitAPartialRowAndAnUnchangedEndpointIsANoop() {
        XCTAssertEqual(target(-20, start: 400), 420)
        XCTAssertEqual(target(20, start: 240), 220)
        XCTAssertNil(target(-20, start: 420))
        XCTAssertNil(target(20, start: 220))
        XCTAssertNil(target(-20, range: 312.4...312.4))
        XCTAssertNil(target(20, range: 312.4...312.4))
    }

    func testFractionalCapsAndStridesRemainExactWithoutPointRounding() throws {
        let cap: ClosedRange<CGFloat> = 220...312.4
        XCTAssertEqual(target(-20, range: cap), 312.4)
        XCTAssertEqual(try XCTUnwrap(target(20, start: 312.4, range: cap)), 272.4, accuracy: 0.000_000_001)
        let tiny: ClosedRange<CGFloat> = 220...CGFloat(220).nextUp
        XCTAssertEqual(target(-20, start: 220, range: tiny), tiny.upperBound)
        XCTAssertEqual(target(20, start: tiny.upperBound, range: tiny), tiny.lowerBound)
    }

    func testExtremeFiniteValuesRemainBoundedAndDoNotInventPrecision() {
        let enormous: ClosedRange<CGFloat> = CGFloat.leastNonzeroMagnitude...CGFloat.greatestFiniteMagnitude
        XCTAssertNil(target(-20, start: .greatestFiniteMagnitude, range: enormous))
        XCTAssertNil(target(20, start: .greatestFiniteMagnitude, range: enormous))
        XCTAssertEqual(target(-20, start: .leastNonzeroMagnitude, range: enormous), 40)
        XCTAssertNil(target(20, start: .leastNonzeroMagnitude, range: enormous))
    }

    func testSessionKeepsItsStartAndReturnsOnlyOneHeightAtRelease() throws {
        var session = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
        for delta: CGFloat in [-12, -24, -48, -120, -300] {
            XCTAssertTrue(session.update(deltaY: delta))
            XCTAssertEqual(session.initialHeight, 300)
        }
        XCTAssertEqual(session.finish(commit: true), 340)
        XCTAssertNil(session.finish(commit: true))
        XCTAssertNil(session.finish(commit: false))
        XCTAssertFalse(session.update(deltaY: 20))
    }

    func testReversalUsesFinalNetDirectionInsteadOfAccumulatingSteps() throws {
        var session = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
        for delta: CGFloat in [-120, -48, -12, 0, 12, 120] { XCTAssertTrue(session.update(deltaY: delta)) }
        XCTAssertEqual(session.finish(commit: true), 260)
        var returned = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
        XCTAssertTrue(returned.update(deltaY: -120))
        XCTAssertTrue(returned.update(deltaY: 0))
        XCTAssertNil(returned.finish(commit: true))
    }

    func testCancellationNoMovementAndAtBoundCannotProduceAPersistableHeight() throws {
        var cancelled = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
        XCTAssertTrue(cancelled.update(deltaY: -120))
        XCTAssertNil(cancelled.finish(commit: false))
        XCTAssertNil(cancelled.finish(commit: true))
        var still = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
        XCTAssertNil(still.finish(commit: true))
        var capped = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 420, range: range, compact: false))
        XCTAssertTrue(capped.update(deltaY: -120))
        XCTAssertNil(capped.finish(commit: true))
    }

    func testInvalidUpdatePoisonsTheGestureRatherThanCommittingAnOlderDelta() throws {
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            var session = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
            XCTAssertTrue(session.update(deltaY: -120))
            XCTAssertFalse(session.update(deltaY: invalid))
            XCTAssertFalse(session.update(deltaY: -20))
            XCTAssertNil(session.finish(commit: true))
        }
    }

    func testSeparateGesturesCanStepAgainAndNeverShareCompletionState() throws {
        var first = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: false))
        XCTAssertTrue(first.update(deltaY: -200))
        let height = try XCTUnwrap(first.finish(commit: true))
        var second = try XCTUnwrap(KeyboardResizeStepSession(startHeight: height, range: range, compact: false))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(second.update(deltaY: -20))
        XCTAssertEqual(second.finish(commit: true), 380)
        XCTAssertNil(first.finish(commit: true))
        var compact = try XCTUnwrap(KeyboardResizeStepSession(startHeight: 300, range: range, compact: true))
        XCTAssertTrue(compact.update(deltaY: -20))
        XCTAssertEqual(compact.finish(commit: true), 340)
    }

    func testFixedCanvasMotionRejectsAnyGeometryRebaseInsteadOfCompensating() throws {
        let bounds = CGRect(x: 8, y: 12, width: 402, height: 420)
        let motion = try XCTUnwrap(KeyboardFixedCanvasResizeMotion(touchY: 130, bounds: bounds))
        XCTAssertEqual(motion.delta(touchY: 10, bounds: bounds), -120)
        XCTAssertEqual(motion.delta(touchY: 250, bounds: bounds), 120)
        for changed in [CGRect(x: 8, y: 13, width: 402, height: 420), CGRect(x: 8, y: 12, width: 402, height: 421),
                        CGRect(x: 8, y: 12, width: 874, height: 420),
                        CGRect(x: 8, y: 12, width: -402, height: 420),
                        CGRect(x: 8, y: 12, width: 402, height: -420)] {
            XCTAssertNil(motion.delta(touchY: 10, bounds: changed))
        }
        XCTAssertNil(motion.delta(touchY: .nan, bounds: bounds))
        XCTAssertNil(KeyboardFixedCanvasResizeMotion(touchY: 130, bounds: .zero))
        let overflowing = try XCTUnwrap(KeyboardFixedCanvasResizeMotion(
            touchY: -.greatestFiniteMagnitude, bounds: bounds))
        XCTAssertNil(overflowing.delta(touchY: .greatestFiniteMagnitude, bounds: bounds))
    }
}
