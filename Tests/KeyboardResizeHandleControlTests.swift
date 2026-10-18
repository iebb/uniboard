#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

/// Drive our callback/state logic through a public recognizer seam. UIKit's
/// recognition thresholds and the remote host are covered by native UI QA.
@MainActor
final class KeyboardResizeHandleControlTests: XCTestCase {
    private final class Pan: UIPanGestureRecognizer {
        var phase: UIGestureRecognizer.State = .possible
        var vector: CGPoint = .zero
        var position = CGPoint(x: 20, y: 9)
        override var state: UIGestureRecognizer.State {
            get { phase }
            set { phase = newValue }
        }
        override func translation(in view: UIView?) -> CGPoint { vector }
        override func location(in view: UIView?) -> CGPoint { position }
    }

    private func fixture(fallbackTimestamp: @escaping () -> TimeInterval = { CACurrentMediaTime() }) -> (UIWindow, ResizeHandleButton) {
        // Attaching to a real window exercises willMove(toWindow:) and window
        // lookup without making it key or taking the host's first responder.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let handle = ResizeHandleButton(backgroundColor: UIColor.systemBackground.withAlphaComponent(0.02), fallbackTimestamp: fallbackTimestamp)
        handle.frame = CGRect(x: 0, y: 0, width: 402, height: 18)
        window.addSubview(handle)
        XCTAssertTrue(handle.window === window)
        return (window, handle)
    }

    func testSuccessfulReleaseCommitsExactlyOnceAndDoesNotResizeItsWindow() {
        let (window, handle) = fixture()
        let originalFrame = window.frame
        var began = 0
        var changes: [CGFloat] = []
        var ends: [Bool] = []
        handle.begin = { began += 1 }
        handle.change = { changes.append($0) }
        handle.end = { ends.append($0) }
        let pan = Pan()
        pan.phase = .began
        pan.vector.y = -10
        pan.position.y = -1
        handle.handlePan(pan)
        pan.phase = .changed
        pan.vector.y = -120
        pan.position.y = -111
        handle.handlePan(pan)
        XCTAssertEqual(ends, [])
        XCTAssertEqual(window.frame, originalFrame)
        pan.phase = .ended
        handle.handlePan(pan)
        handle.handlePan(pan)
        XCTAssertEqual(began, 1)
        XCTAssertEqual(changes, [-10, -120, -120])
        XCTAssertEqual(ends, [true])
        XCTAssertEqual(window.frame, originalFrame)
    }

    func testCancelledAndFailedPansDiscardExactlyOnce() {
        for terminal in [UIGestureRecognizer.State.cancelled, .failed] {
            let (window, handle) = fixture()
            defer { withExtendedLifetime(window) {} }
            var ends: [Bool] = []
            handle.end = { ends.append($0) }
            let pan = Pan()
            pan.phase = .began
            handle.handlePan(pan)
            pan.phase = .changed
            pan.vector.y = -120
            handle.handlePan(pan)
            pan.phase = terminal
            handle.handlePan(pan)
            pan.phase = .ended
            handle.handlePan(pan)
            XCTAssertEqual(ends, [false])
        }
    }

    func testDetachmentDiscardsAndARecognizerTerminalCannotCommitAfterward() {
        let (window, handle) = fixture()
        var ends: [Bool] = []
        handle.end = { ends.append($0) }
        let pan = Pan()
        pan.phase = .began
        handle.handlePan(pan)
        handle.removeFromSuperview()
        XCTAssertNil(handle.window)
        XCTAssertEqual(ends, [false])
        pan.phase = .ended
        handle.handlePan(pan)
        XCTAssertEqual(ends, [false])
        window.addSubview(handle)
        pan.phase = .began
        handle.handlePan(pan)
        pan.phase = .ended
        pan.position.y = -11
        handle.handlePan(pan)
        XCTAssertEqual(ends, [false, true])
    }

    func testMovingToAnotherWindowCancelsOnlyTheOldSession() {
        let (first, handle) = fixture()
        let second = UIWindow(frame: first.frame)
        defer { withExtendedLifetime(first) {}; withExtendedLifetime(second) {} }
        var ends: [Bool] = []
        handle.end = { ends.append($0) }
        let pan = Pan()
        pan.phase = .began
        handle.handlePan(pan)
        second.addSubview(handle)
        XCTAssertTrue(handle.window === second)
        XCTAssertEqual(ends, [false])
        pan.phase = .ended
        handle.handlePan(pan)
        XCTAssertEqual(ends, [false])
    }

    func testNoWindowOrNoBeginCannotProduceChangeOrCommitCallbacks() {
        let handle = ResizeHandleButton(backgroundColor: .clear)
        var callbacks = 0
        handle.begin = { callbacks += 1 }
        handle.change = { _ in callbacks += 1 }
        handle.end = { _ in callbacks += 1 }
        let pan = Pan()
        for state in [UIGestureRecognizer.State.changed, .ended, .cancelled, .failed, .began, .ended] {
            pan.phase = state
            handle.handlePan(pan)
        }
        XCTAssertEqual(callbacks, 0)
    }

    func testInvalidBeginningCoordinatesDoNotStartASession() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        var callbacks = 0
        handle.begin = { callbacks += 1 }
        handle.change = { _ in callbacks += 1 }
        handle.end = { _ in callbacks += 1 }
        let pan = Pan()
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            pan.phase = .began
            pan.position.y = invalid
            pan.vector.y = 0
            handle.handlePan(pan)
            pan.position.y = 9
            pan.vector.y = invalid
            handle.handlePan(pan)
            pan.phase = .ended
            handle.handlePan(pan)
        }
        XCTAssertEqual(callbacks, 0)
    }

    func testInvalidChangedCoordinatesCancelRatherThanCommitAnOlderTarget() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        var changes: [CGFloat] = []
        var ends: [Bool] = []
        handle.change = { changes.append($0) }
        handle.end = { ends.append($0) }
        let pan = Pan()
        pan.phase = .began
        handle.handlePan(pan)
        pan.phase = .changed
        pan.position.y = -31
        handle.handlePan(pan)
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            pan.position.y = invalid
            handle.handlePan(pan)
        }
        pan.phase = .ended
        handle.handlePan(pan)
        XCTAssertEqual(changes, [0, -40])
        XCTAssertEqual(ends, [false])
    }

    func testInvalidTerminalCoordinatesAlwaysDiscardTheSession() {
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            let (window, handle) = fixture()
            defer { withExtendedLifetime(window) {} }
            var ends: [Bool] = []
            handle.end = { ends.append($0) }
            let pan = Pan(); pan.phase = .began
            handle.handlePan(pan)
            pan.phase = .changed; pan.position.y = -31
            handle.handlePan(pan)
            pan.phase = .ended; pan.position.y = invalid
            handle.handlePan(pan)
            pan.position.y = -31; handle.handlePan(pan)
            XCTAssertEqual(ends, [false])
        }
    }

    func testInvalidAndRegressedTerminalTimestampsCannotCommit() {
        for invalid: TimeInterval in [.nan, .infinity, -.infinity, -1, 0.5] {
            var time: TimeInterval = 1
            let (window, handle) = fixture(fallbackTimestamp: { time })
            defer { withExtendedLifetime(window) {} }
            var ends: [Bool] = []
            handle.end = { ends.append($0) }
            let pan = Pan(); pan.phase = .began
            handle.handlePan(pan)
            time = invalid; pan.phase = .ended
            handle.handlePan(pan)
            XCTAssertEqual(ends, [false])
        }
    }

    func testExactDuplicateEventsAreIgnoredButConflictingDuplicatesCancel() {
        var time: TimeInterval = 1
        let (window, handle) = fixture(fallbackTimestamp: { time })
        defer { withExtendedLifetime(window) {} }
        var changes: [CGFloat] = [], ends: [Bool] = []
        handle.change = { changes.append($0) }
        handle.end = { ends.append($0) }
        let pan = Pan(); pan.phase = .began
        handle.handlePan(pan)
        pan.phase = .changed; handle.handlePan(pan)
        XCTAssertEqual(changes, [0])
        time = 2; pan.position.y = -31
        handle.handlePan(pan)
        handle.handlePan(pan)
        XCTAssertEqual(changes, [0, -40])
        pan.position.y = -21
        handle.handlePan(pan)
        pan.phase = .ended; handle.handlePan(pan)
        XCTAssertEqual(changes, [0, -40])
        XCTAssertEqual(ends, [false])
    }

    func testExactDuplicateReleaseCanCommitAVerifiedVerticalSwipe() {
        let (window, handle) = fixture(fallbackTimestamp: { 1 })
        defer { withExtendedLifetime(window) {} }
        var ends: [Bool] = []
        handle.end = { ends.append($0) }
        let pan = Pan(); pan.phase = .began; pan.position.y = -3; pan.vector.y = -12
        handle.handlePan(pan)
        pan.phase = .ended; handle.handlePan(pan)
        XCTAssertEqual(ends, [true])
    }

    func testLateCallbacksFromAnOldRecognizerCannotEndANewRecognizerSession() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        let old = Pan(), replacement = Pan()
        var ends: [Bool] = []
        handle.end = { ends.append($0) }
        old.phase = .began; handle.handlePan(old)
        handle.cancelResize()
        replacement.phase = .began; handle.handlePan(replacement)
        old.phase = .changed; old.position.y = -100; handle.handlePan(old)
        old.phase = .ended; handle.handlePan(old)
        old.phase = .cancelled; handle.handlePan(old)
        XCTAssertEqual(ends, [false])
        replacement.phase = .ended; replacement.position.y = -11; handle.handlePan(replacement)
        XCTAssertEqual(ends, [false, true])
    }

    func testWindowBoundsChangeDiscardsInsteadOfCompensatingTheTouchBasis() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        window.bounds = CGRect(x: 0, y: 0, width: 402, height: 300)
        let localRoot = UIView(frame: window.bounds)
        handle.coordinateView = localRoot
        var changes: [CGFloat] = [], ends: [Bool] = []
        handle.change = { changes.append($0) }
        handle.end = { ends.append($0) }
        let pan = Pan(); pan.phase = .began
        handle.handlePan(pan)
        pan.phase = .changed; pan.position.y = -31
        localRoot.bounds.size.height = 340 // Local unrelated bounds do not enter the fixed-window math.
        handle.handlePan(pan)
        window.bounds.size.height = 340
        pan.position.y = 9
        handle.handlePan(pan)
        pan.phase = .ended; handle.handlePan(pan)
        XCTAssertEqual(changes, [0, -40])
        XCTAssertEqual(ends, [false])
    }

    func testWindowBoundsChangeOnReleaseCannotCommitAnEarlierSelection() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        var ends: [Bool] = []
        handle.end = { ends.append($0) }
        let pan = Pan(); pan.phase = .began; handle.handlePan(pan)
        window.bounds.origin.y += 1
        pan.phase = .ended; handle.handlePan(pan)
        handle.handlePan(pan)
        XCTAssertEqual(ends, [false])
    }

    func testDuplicateBeginAndExplicitCancellationAreIdempotent() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        var begins = 0, changes = 0
        var ends: [Bool] = []
        handle.begin = { begins += 1 }
        handle.change = { _ in changes += 1 }
        handle.end = { ends.append($0) }
        let pan = Pan(); pan.phase = .began
        handle.handlePan(pan)
        handle.handlePan(pan)
        handle.cancelResize()
        handle.cancelResize()
        pan.phase = .changed; handle.handlePan(pan)
        pan.phase = .ended; handle.handlePan(pan)
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(ends, [false])
    }

    func testCancellationInsideBeginDoesNotEmitAStaleChange() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        var changes = 0
        var ends: [Bool] = []
        handle.begin = { [weak handle] in handle?.cancelResize() }
        handle.change = { _ in changes += 1 }
        handle.end = { ends.append($0) }
        let pan = Pan(); pan.phase = .began
        handle.handlePan(pan)
        pan.phase = .ended; handle.handlePan(pan)
        XCTAssertEqual(changes, 0)
        XCTAssertEqual(ends, [false])
    }

    func testOldTerminalCannotEndAReentrantNewSession() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        let old = Pan(), replacement = Pan()
        var ends: [Bool] = []
        var replaced = false
        handle.end = { ends.append($0) }
        handle.change = { [weak handle] _ in
            guard old.phase == .ended, !replaced else { return }
            replaced = true
            handle?.cancelResize()
            replacement.phase = .began
            handle?.handlePan(replacement)
        }
        old.phase = .began; handle.handlePan(old)
        old.phase = .ended; old.position.y = -11; handle.handlePan(old)
        XCTAssertEqual(ends, [false])
        replacement.phase = .ended; replacement.position.y = -11; handle.handlePan(replacement)
        XCTAssertEqual(ends, [false, true])
    }

    func testTapDoesNothingAndAccessibilityStepsUseSemanticRows() {
        let handle = ResizeHandleButton(backgroundColor: .clear)
        var steps: [CGFloat] = []
        handle.step = { steps.append($0) }
        handle.sendActions(for: .touchUpInside)
        XCTAssertFalse(handle.accessibilityActivate())
        XCTAssertTrue(steps.isEmpty)
        XCTAssertNil(handle.actions(forTarget: handle, forControlEvent: .touchUpInside))
        handle.accessibilityIncrement()
        handle.accessibilityDecrement()
        XCTAssertEqual(steps, [1, -1])
        XCTAssertEqual(handle.accessibilityIdentifier, "keyboard.resize")
        XCTAssertFalse(handle.accessibilityTraits.contains(.button))
        XCTAssertTrue(handle.accessibilityTraits.contains(.adjustable))
        XCTAssertEqual(handle.intrinsicContentSize.height, 14)
        XCTAssertEqual(handle.intrinsicContentSize.height, KeyboardLayoutPolicy.resizeHandleHeight)
    }

    func testTinyHorizontalAndDiagonalReleasesCancelWithoutAFinalChange() {
        for (x, y): (CGFloat, CGFloat) in [(0, 0), (0, 11.99), (40, 20), (12, 12), (-30, -12)] {
            let (window, handle) = fixture()
            defer { withExtendedLifetime(window) {} }
            var ends: [Bool] = [], changes: [CGFloat] = []
            handle.end = { ends.append($0) }
            handle.change = { changes.append($0) }
            let pan = Pan(); pan.phase = .began
            handle.handlePan(pan)
            pan.phase = .ended; pan.position = CGPoint(x: 20 + x, y: 9 + y)
            handle.handlePan(pan)
            handle.handlePan(pan)
            XCTAssertEqual(ends, [false])
            XCTAssertEqual(changes, [0], "Rejected release must not submit one more selection")
        }
    }

    func testBothDirectionsRequireThresholdAndPredominantVerticalMotion() {
        for (x, y): (CGFloat, CGFloat) in [(0, -12), (0, 12), (11, -12), (-11, 12), (12, 13)] {
            let (window, handle) = fixture()
            defer { withExtendedLifetime(window) {} }
            var ends: [Bool] = [], changes: [CGFloat] = []
            handle.end = { ends.append($0) }
            handle.change = { changes.append($0) }
            let pan = Pan(); pan.phase = .began
            handle.handlePan(pan)
            pan.phase = .ended; pan.position = CGPoint(x: 20 + x, y: 9 + y)
            handle.handlePan(pan)
            handle.handlePan(pan)
            XCTAssertEqual(ends, [true])
            XCTAssertEqual(changes, [0, y])
        }
    }

    func testEntireGrabAreaRemainsInteractiveAroundTheDecorativePill() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        handle.layoutIfNeeded()
        XCTAssertEqual(handle.backgroundColor?.cgColor.alpha ?? 0, 0.02, accuracy: 0.0001)
        for point in [CGPoint(x: 2, y: 2), CGPoint(x: 201, y: 6), CGPoint(x: 201, y: 9), CGPoint(x: 400, y: 17)] {
            XCTAssertTrue(handle.hitTest(point, with: nil) === handle)
        }
    }

#if DEBUG
    func testDebugSamplesRemainFiniteAndContainNoText() {
        let (window, handle) = fixture()
        defer { withExtendedLifetime(window) {} }
        var samples: [[String: Double]] = []
        handle.debugSample = { samples.append($0) }
        let pan = Pan()
        pan.phase = .began
        handle.handlePan(pan)
        pan.phase = .changed
        pan.vector.y = .nan
        handle.handlePan(pan)
        pan.phase = .cancelled
        handle.handlePan(pan)
        XCTAssertEqual(samples.count, 3)
        XCTAssertTrue(samples.allSatisfy { $0.values.allSatisfy(\.isFinite) })
        XCTAssertFalse(samples.contains { $0.keys.contains("query") || $0.keys.contains("hostText") })
    }
#endif
}
#endif
