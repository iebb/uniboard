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

    private func fixture() -> (UIWindow, ResizeHandleButton) {
        // Attaching to a real window exercises willMove(toWindow:) and window
        // lookup without making it key or taking the host's first responder.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        let handle = ResizeHandleButton(backgroundColor: UIColor.systemBackground.withAlphaComponent(0.02))
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
        handle.handlePan(pan)
        pan.phase = .changed
        pan.vector.y = -120
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

    func testNoWindowOrNoBeginCannotProducePreviewOrCommitCallbacks() {
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

    func testInvalidChangedAndTerminalVectorsNeverEscapeToPreview() {
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
        pan.vector.y = -40
        handle.handlePan(pan)
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            pan.vector.y = invalid
            handle.handlePan(pan)
        }
        pan.phase = .ended
        handle.handlePan(pan)
        XCTAssertEqual(changes, [0, -40])
        XCTAssertEqual(ends, [true]) // Release keeps the last valid preview.
    }

    func testButtonAndAccessibilityActionsKeepTheSameCallbacks() {
        let handle = ResizeHandleButton(backgroundColor: .clear)
        var toggles = 0
        var steps: [CGFloat] = []
        handle.toggle = { toggles += 1 }
        handle.step = { steps.append($0) }
        handle.sendActions(for: .touchUpInside)
        XCTAssertTrue(handle.accessibilityActivate())
        handle.accessibilityIncrement()
        handle.accessibilityDecrement()
        XCTAssertEqual(toggles, 2)
        XCTAssertEqual(steps, [40, -40])
        XCTAssertEqual(handle.accessibilityIdentifier, "keyboard.resize")
        XCTAssertTrue(handle.accessibilityTraits.contains(.button))
        XCTAssertTrue(handle.accessibilityTraits.contains(.adjustable))
        XCTAssertEqual(handle.intrinsicContentSize.height, 18)
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
