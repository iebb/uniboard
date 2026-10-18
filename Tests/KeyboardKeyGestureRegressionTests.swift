#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardKeyGestureRegressionTests: XCTestCase {
    @MainActor private final class Clock {
        var jobs: [() -> Void] = []
        var intervals: [TimeInterval] = []
        func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> Timer {
            intervals.append(delay)
            jobs.append(action)
            return Timer(timeInterval: delay, repeats: false) { _ in }
        }
        // A queued delivery may arrive even after its Timer was invalidated.
        func deliver(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
            guard jobs.indices.contains(index) else {
                XCTFail("Missing scheduled regression job at index \(index)", file: file, line: line)
                return
            }
            jobs[index]()
        }
    }

    func testOwnerLostBeforeHoldAllowsFreshPressAndOldDeliveryCannotCancelIt() {
        let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        var inserted: [String] = []
        state.configure(context: UUID(), key: "letter.a", text: "a", variants: ["à"], enabled: true) {
            .init(isCurrent: { true }, insert: { inserted.append($0); return true })
        }
        state.show = { _, _, _ in true }
        var oldOwner: NSObject? = NSObject()
        XCTAssertTrue(state.begin(owner: oldOwner!))
        XCTAssertEqual(clock.intervals, [0.4])
        oldOwner = nil
        clock.deliver(0)
        XCTAssertNil(state.token)
        XCTAssertFalse(state.popupVisible)
        XCTAssertTrue(inserted.isEmpty)

        let freshOwner = NSObject()
        XCTAssertTrue(state.begin(owner: freshOwner), "Losing the old touch must not permanently latch a key")
        let freshToken = state.token
        clock.deliver(0)
        XCTAssertEqual(state.token, freshToken, "An old owner-loss callback cannot cancel a newer physical press")
        XCTAssertTrue(state.end(owner: freshOwner, inside: true))
        XCTAssertEqual(inserted, ["a"])
        clock.deliver(1)
        XCTAssertFalse(state.popupVisible)
        XCTAssertEqual(inserted, ["a"])
    }

    func testOwnerLostDuringDeleteRepeatAllowsFreshTapWithoutReleaseDeleteOrStaleRepeat() {
        let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        var taps = 0, deletes = 0
        state.configure(context: UUID(), key: "utility.delete", text: "⌫", variants: [], enabled: true) {
            .init(isCurrent: { true }, insert: { _ in XCTFail("Delete cannot insert its display glyph"); return false },
                  tap: { taps += 1; return true }, repeatOnHold: { deletes += 1; return true })
        }
        var oldOwner: NSObject? = NSObject()
        XCTAssertTrue(state.begin(owner: oldOwner!))
        clock.deliver(0)
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(clock.intervals, [0.4, 0.085])
        oldOwner = nil
        clock.deliver(1)
        XCTAssertNil(state.token)
        XCTAssertEqual(deletes, 1)

        let freshOwner = NSObject()
        XCTAssertTrue(state.begin(owner: freshOwner))
        let freshToken = state.token
        clock.deliver(1)
        XCTAssertEqual(state.token, freshToken)
        XCTAssertTrue(state.end(owner: freshOwner, inside: true))
        XCTAssertFalse(state.end(owner: freshOwner, inside: true))
        clock.deliver(2)
        XCTAssertEqual(taps, 1)
        XCTAssertEqual(deletes, 1, "Neither an orphaned repeat nor a fresh tap's release may add a delete")
    }

    func testDefaultDisabledAndCustomHoldKeepExactChoicesSeparateFromOrdinaryTap() {
        let nfd = "e\u{0301}"
        let specifications: [([String]?, [String])] = [(nil, ["a", "à"]), ([], []), (["é", nfd], ["é", nfd])]
        for (override, expectedPopup) in specifications {
            let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule), owner = NSObject()
            var inserted: [String] = [], shown: [[String]] = []
            state.configure(context: UUID(), key: "letter.a", text: "a", variants: ["à"], enabled: true) {
                .init(isCurrent: { true }, insert: { inserted.append($0); return true }, longPressOptions: override)
            }
            state.show = { values, inspect, edit in
                XCTAssertFalse(inspect || edit)
                shown.append(values)
                return true
            }
            XCTAssertTrue(state.begin(owner: owner))
            XCTAssertTrue(state.end(owner: owner, inside: true))
            XCTAssertEqual(inserted, ["a"], "Neither a custom hold nor Off may replace ordinary tap output")
            XCTAssertTrue(state.begin(owner: owner))
            if expectedPopup.isEmpty {
                XCTAssertTrue(clock.jobs.isEmpty)
                XCTAssertTrue(state.end(owner: owner, inside: true))
                XCTAssertEqual(inserted, ["a", "a"])
            } else {
                clock.deliver(0)
                XCTAssertTrue(shown.isEmpty, "A short tap's stale timer cannot open the later press")
                clock.deliver(1)
                XCTAssertEqual(shown.map { $0.map { Array($0.utf16) } }, [expectedPopup.map { Array($0.utf16) }])
                XCTAssertEqual(inserted, ["a"], "Holding alone never inserts a choice")
                state.move(owner: owner, index: 1, movedBeforeHold: false)
                XCTAssertTrue(state.end(owner: owner, inside: true))
                XCTAssertEqual(inserted.map { Array($0.utf16) }, ["a", expectedPopup[1]].map { Array($0.utf16) })
            }
        }
    }

    func testExplicitDisabledOrCustomUtilityHoldCannotRunDefaultManagerAction() {
        let specifications: [[String]?] = [nil, [], ["xy"]]
        for override in specifications {
            let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule), owner = NSObject()
            var taps = 0, managers = 0, inserted: [String] = []
            state.configure(context: UUID(), key: "utility.favorites", text: "★", variants: [], enabled: true) {
                .init(isCurrent: { true }, insert: { _ in XCTFail("The star glyph is not host text"); return false },
                      hold: { managers += 1; return true }, longPressOptions: override,
                      tap: { taps += 1; return true }, insertGesture: { text, gesture in
                          XCTAssertEqual(gesture, .longPress)
                          inserted.append(text)
                          return true
                      })
            }
            state.show = { _, inspect, edit in XCTAssertFalse(inspect || edit); return true }
            XCTAssertTrue(state.begin(owner: owner))
            XCTAssertTrue(state.end(owner: owner, inside: true))
            XCTAssertEqual(taps, 1)
            XCTAssertTrue(state.begin(owner: owner))
            if override?.isEmpty == true {
                XCTAssertTrue(clock.jobs.isEmpty)
                XCTAssertTrue(state.end(owner: owner, inside: true))
                XCTAssertEqual(taps, 2)
            } else {
                clock.deliver(1)
                if override == nil {
                    XCTAssertEqual(managers, 1)
                    XCTAssertFalse(state.end(owner: owner, inside: true))
                    XCTAssertTrue(inserted.isEmpty)
                } else {
                    XCTAssertEqual(managers, 0)
                    XCTAssertTrue(state.end(owner: owner, inside: true))
                    XCTAssertEqual(inserted, ["xy"])
                }
                XCTAssertEqual(taps, 1, "A completed hold cannot also trigger the ordinary star toggle")
            }
        }
    }

    func testConfiguredDeleteRepeatRejectsChangedNativeGeometryWithoutAPopup() {
        for geometryChange in 0..<4 {
            let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule)
            let button = KeyboardVariantButton(interaction: state), owner = NSObject()
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
            let input = UIInputView(frame: window.bounds, inputViewStyle: .keyboard)
            window.addSubview(input)
            input.addSubview(button)
            button.frame = CGRect(x: 350, y: 180, width: 42, height: 36)
            var deletes = 0, taps = 0
            button.configure(context: UUID(), key: "utility.delete", text: "⌫", variants: [], enabled: true,
                             font: .systemFont(ofSize: 20)) {
                .init(isCurrent: { true }, insert: { _ in XCTFail("Delete cannot insert a glyph"); return false },
                      tap: { taps += 1; return true }, repeatOnHold: { deletes += 1; return true })
            }
            XCTAssertTrue(button.beginPhysicalPress(owner: owner, point: CGPoint(x: 21, y: 18)))
            clock.deliver(0)
            XCTAssertEqual(deletes, 1)
            XCTAssertFalse(state.popupVisible)
            if geometryChange == 1 {
                // Origin-only remapping need not lay out the key itself.
                window.bounds.origin.y = 10
            } else if geometryChange == 0 {
                input.bounds.size.height = 220
                button.setNeedsLayout()
                button.layoutIfNeeded()
            } else if geometryChange == 2 { button.frame.origin.x -= 8 }
            else {
                let unchangedBounds = window.bounds
                window.frame.origin.y += 10
                XCTAssertEqual(window.bounds, unchangedBounds, "Moving the window is distinct from changing its local coordinates")
            }
            clock.deliver(1)
            XCTAssertEqual(deletes, 1, "A queued repeat must not act through a changed native input geometry")
            XCTAssertNil(state.token)
            XCTAssertFalse(state.end(owner: owner, inside: true))
            XCTAssertEqual(taps, 0)
            let freshOwner = NSObject()
            XCTAssertTrue(button.beginPhysicalPress(owner: freshOwner, point: CGPoint(x: 21, y: 18)))
            XCTAssertTrue(state.end(owner: freshOwner, inside: true))
            XCTAssertEqual(taps, 1, "A fresh press can use the newly observed keyboard geometry")
        }
    }
}
#endif
