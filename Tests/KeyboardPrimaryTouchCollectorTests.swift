#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardPrimaryTouchCollectorTests: XCTestCase {
    private struct Sample: Equatable {
        let y: Double
        let timestamp: Double
        let window: Int
    }
    private final class Touch: NSObject {
        var sample: Sample
        var sampleReads = 0
        init(y: Double, timestamp: Double = 1, window: Int = 11) {
            sample = Sample(y: y, timestamp: timestamp, window: window)
        }
        func snapshot() -> Sample { sampleReads += 1; return sample }
    }

    func testForeignBeganMovedEndedAndCancelledNeverOverwritePrimarySample() {
        let collector = KeyboardPrimaryTouchCollector<Sample>()
        let primary = Touch(y: 10), foreign = Touch(y: 999, window: 99)
        XCTAssertTrue(collector.capture([primary], phase: .began) { $0.snapshot() })
        let initial = collector.initialSample
        for phase in [KeyboardPrimaryTouchCollector<Sample>.Phase.began, .moved, .ended, .cancelled] {
            XCTAssertFalse(collector.capture([foreign], phase: phase) { $0.snapshot() })
            XCTAssertEqual(collector.initialSample, initial)
            XCTAssertEqual(collector.latestSample, initial)
        }
        XCTAssertEqual(foreign.sampleReads, 0, "The foreign sample getter must never run before superclass rejection")
        XCTAssertEqual(primary.sampleReads, 1)
    }

    func testMixedCollectionSelectsOriginalOwnerRegardlessOfForeignPosition() {
        let collector = KeyboardPrimaryTouchCollector<Sample>()
        let primary = Touch(y: 10), foreign = Touch(y: 999)
        XCTAssertTrue(collector.capture([primary], phase: .began) { $0.snapshot() })
        primary.sample = Sample(y: 20, timestamp: 2, window: 11)
        XCTAssertTrue(collector.capture([foreign, primary], phase: .moved) { $0.snapshot() })
        XCTAssertEqual(collector.latestSample, primary.sample)
        primary.sample = Sample(y: 30, timestamp: 3, window: 11)
        XCTAssertTrue(collector.capture([primary, foreign], phase: .moved) { $0.snapshot() })
        XCTAssertEqual(collector.latestSample, primary.sample)
        XCTAssertEqual(collector.initialSample?.y, 10)
        XCTAssertEqual(foreign.sampleReads, 0)
    }

    func testMovedOrTerminalTouchesCannotStartAnUnboundCollector() {
        let collector = KeyboardPrimaryTouchCollector<Sample>(), touch = Touch(y: 50)
        for phase in [KeyboardPrimaryTouchCollector<Sample>.Phase.moved, .ended, .cancelled] {
            XCTAssertFalse(collector.capture([touch], phase: phase) { $0.snapshot() })
            XCTAssertNil(collector.initialSample)
            XCTAssertNil(collector.latestSample)
        }
        XCTAssertFalse(collector.capture([Touch](), phase: .began) { $0.snapshot() })
        XCTAssertEqual(touch.sampleReads, 0)
        XCTAssertTrue(collector.capture([touch], phase: .began) { $0.snapshot() })
    }

    func testMissingInitialWindowStillBindsTheFirstFingerUntilReset() {
        let collector = KeyboardPrimaryTouchCollector<Sample>()
        let primary = Touch(y: 10), foreign = Touch(y: 999)
        XCTAssertFalse(collector.capture([primary], phase: .began) { _ in nil })
        XCTAssertFalse(collector.capture([foreign], phase: .began) { $0.snapshot() })
        XCTAssertNil(collector.latestSample)
        XCTAssertTrue(collector.capture([primary], phase: .moved) { $0.snapshot() })
        XCTAssertEqual(collector.initialSample, primary.sample)
        XCTAssertEqual(collector.latestSample, primary.sample)
        XCTAssertEqual(foreign.sampleReads, 0)
    }

    func testOwnTerminalSamplePreservesOwnershipUntilRecognizerReset() {
        for phase in [KeyboardPrimaryTouchCollector<Sample>.Phase.ended, .cancelled] {
            let collector = KeyboardPrimaryTouchCollector<Sample>()
            let primary = Touch(y: 10), foreign = Touch(y: 999)
            XCTAssertTrue(collector.capture([primary], phase: .began) { $0.snapshot() })
            primary.sample = Sample(y: 45, timestamp: 5, window: 11)
            XCTAssertTrue(collector.capture([primary], phase: phase) { $0.snapshot() })
            XCTAssertEqual(collector.latestSample, primary.sample)
            XCTAssertFalse(collector.capture([foreign], phase: .began) { $0.snapshot() })
            XCTAssertEqual(collector.latestSample, primary.sample)
        }
    }

    func testResetClearsSamplesAndLetsANewFingerOwnTheNextSequence() {
        let collector = KeyboardPrimaryTouchCollector<Sample>()
        let old = Touch(y: 10), next = Touch(y: 80, window: 22)
        XCTAssertTrue(collector.capture([old], phase: .began) { $0.snapshot() })
        collector.reset()
        XCTAssertNil(collector.initialSample)
        XCTAssertNil(collector.latestSample)
        XCTAssertFalse(collector.capture([old], phase: .moved) { $0.snapshot() })
        XCTAssertTrue(collector.capture([next], phase: .began) { $0.snapshot() })
        XCTAssertFalse(collector.capture([old], phase: .cancelled) { $0.snapshot() })
        XCTAssertEqual(collector.initialSample, next.sample)
        XCTAssertEqual(collector.latestSample, next.sample)
    }

    func testResetDuringSampleCaptureCannotPublishTheOldResult() {
        let collector = KeyboardPrimaryTouchCollector<Sample>(), touch = Touch(y: 10)
        XCTAssertFalse(collector.capture([touch], phase: .began) { current in
            let result = current.snapshot()
            collector.reset()
            return result
        })
        XCTAssertNil(collector.initialSample)
        XCTAssertNil(collector.latestSample)
    }

    func testReentrantResetAndNewFingerCannotBeOverwrittenByOldCallback() {
        let collector = KeyboardPrimaryTouchCollector<Sample>()
        let old = Touch(y: 10), next = Touch(y: 80, window: 22)
        XCTAssertFalse(collector.capture([old], phase: .began) { current in
            let result = current.snapshot()
            collector.reset()
            XCTAssertTrue(collector.capture([next], phase: .began) { $0.snapshot() })
            return result
        })
        XCTAssertEqual(collector.initialSample, next.sample)
        XCTAssertEqual(collector.latestSample, next.sample)
    }

    func testReentrantNewerSampleForSameFingerWinsOverOlderCapture() {
        let collector = KeyboardPrimaryTouchCollector<Sample>(), touch = Touch(y: 10)
        XCTAssertFalse(collector.capture([touch], phase: .began) { current in
            let old = current.snapshot()
            current.sample = Sample(y: 20, timestamp: 2, window: 11)
            XCTAssertTrue(collector.capture([current], phase: .moved) { $0.snapshot() })
            return old
        })
        XCTAssertEqual(collector.latestSample, touch.sample)
        XCTAssertEqual(collector.initialSample, touch.sample)
    }

    func testCollectorStoresOnlyIdentityAndSampleWithoutRetainingTouchObjects() {
        let collector = KeyboardPrimaryTouchCollector<Sample>()
        weak var released: Touch?
        do {
            let touch = Touch(y: 10)
            released = touch
            XCTAssertTrue(collector.capture([touch], phase: .began) { $0.snapshot() })
        }
        XCTAssertNil(released)
        XCTAssertEqual(collector.latestSample?.y, 10)
        // A vanished weak owner never authorizes address-reuse/new ownership
        // before reset, even if another finger starts a new touch sequence.
        let next = Touch(y: 99)
        XCTAssertNil(collector.ownedTouch(in: [next]))
        XCTAssertFalse(collector.capture([next], phase: .began) { $0.snapshot() })
        XCTAssertEqual(next.sampleReads, 0)
        collector.reset()
        XCTAssertTrue(collector.capture([next], phase: .began) { $0.snapshot() })
        XCTAssertEqual(collector.latestSample, next.sample)
    }
}
#endif
