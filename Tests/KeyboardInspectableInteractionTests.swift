#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardInspectableInteractionTests: XCTestCase {
    private final class Clock {
        struct Job { let interval: TimeInterval; let timer: Timer; let action: () -> Void }
        var jobs: [Job] = []
        func schedule(_ interval: TimeInterval, _ action: @escaping () -> Void) -> Timer {
            let timer = Timer(timeInterval: interval, repeats: false) { _ in }
            jobs.append(.init(interval: interval, timer: timer, action: action))
            return timer
        }
        // Even cancelled callbacks can already be queued. Ownership must guard
        // them independently of the real Timer's validity.
        func deliver(_ index: Int) { jobs[index].action() }
    }
    private final class Route {
        var context: KeyboardInputActionContext? = .init(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        var inserted: [String] = [], inspected: [String] = []
        var factories = 0
        func actions(rendered: UUID, item: String) -> KeyboardInspectableInteraction.Actions? {
            factories += 1
            guard let current = context else { return nil }
            let bound = KeyboardInputActionContext(modeIdentifier: rendered, documentIdentifier: current.documentIdentifier,
                interactionIdentifier: current.interactionIdentifier)
            return .init(insert: bound.guardedAction(currentContext: { self.context }, perform: { self.inserted.append(item); return true }),
                         inspect: bound.guardedAction(currentContext: { self.context }, perform: { self.inspected.append(item); return true }))
        }
        func changeMode() {
            guard let current = context else { return }
            context = .init(modeIdentifier: UUID(), documentIdentifier: current.documentIdentifier,
                interactionIdentifier: current.interactionIdentifier)
        }
    }
    private func configure(_ state: KeyboardInspectableInteraction, route: Route, item: String = "original", enabled: Bool = true) {
        let rendered = route.context!.modeIdentifier
        state.configure(contextIdentifier: rendered, itemIdentifier: item, enabled: enabled) {
            route.actions(rendered: rendered, item: item)
        }
    }

    func testVisibleHoverInspectsExactlyOnceAndNeverInserts() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        configure(state, route: route)
        state.beginHover()
        XCTAssertEqual(clock.jobs[0].interval, 0.65)
        clock.deliver(0); clock.deliver(0)
        XCTAssertEqual(route.inspected, ["original"])
        XCTAssertTrue(route.inserted.isEmpty)
        XCTAssertEqual(route.factories, 1)
    }
    func testHoverThenABCWithDelayedConfigureCannotReopenTheHiddenPicker() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        configure(state, route: route)
        state.beginHover()
        route.changeMode() // The model changed before SwiftUI updated the key.
        clock.deliver(0)
        XCTAssertTrue(route.inspected.isEmpty)
        XCTAssertTrue(route.inserted.isEmpty)
    }
    func testABCAndBackCannotReviveAnOldHoverOrHeldTap() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        configure(state, route: route)
        state.beginHover()
        route.changeMode(); configure(state, route: route, enabled: false)
        route.changeMode(); configure(state, route: route)
        state.beginHover()
        clock.deliver(0)
        XCTAssertTrue(route.inspected.isEmpty)
        clock.deliver(1)
        XCTAssertEqual(route.inspected, ["original"])
        state.beginPress()
        route.changeMode(); configure(state, route: route, enabled: false)
        route.changeMode(); configure(state, route: route)
        state.beginPress() // Duplicate-down while the original finger remains.
        XCTAssertFalse(state.endPress())
        XCTAssertTrue(route.inserted.isEmpty)
        state.beginPress(); XCTAssertTrue(state.endPress())
        XCTAssertEqual(route.inserted, ["original"])
    }
    func testSameContextRendererUpdateNeverRetargetsCapturedItemCallbacks() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        let mode = route.context!.modeIdentifier
        configure(state, route: route)
        state.beginHover()
        state.configure(contextIdentifier: mode, itemIdentifier: "original", enabled: true) {
            route.actions(rendered: mode, item: "replacement")
        }
        clock.deliver(0)
        XCTAssertEqual(route.inspected, ["original"])
        state.beginPress()
        state.configure(contextIdentifier: mode, itemIdentifier: "original", enabled: true) {
            route.actions(rendered: mode, item: "later")
        }
        XCTAssertTrue(state.endPress())
        XCTAssertEqual(route.inserted, ["replacement"])
    }
    func testItemChangeOrDisableCancelsQueuedHoverAndHeldPress() {
        for disabled in [true, false] {
            let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
            configure(state, route: route); state.beginHover()
            configure(state, route: route, item: disabled ? "original" : "new", enabled: !disabled)
            clock.deliver(0)
            XCTAssertTrue(route.inspected.isEmpty)
            configure(state, route: route); state.beginPress()
            configure(state, route: route, item: disabled ? "original" : "new", enabled: !disabled)
            XCTAssertFalse(state.endPress())
            XCTAssertTrue(route.inserted.isEmpty)
        }
    }
    func testPressSnapshotsOnceAndLongHoldInspectsWithoutInsertionEvenAfterRawCancellation() {
        let route = Route(), state = KeyboardInspectableInteraction()
        configure(state, route: route)
        state.beginPress(); state.beginPress()
        state.cancelPress(preserveInspection: true)
        XCTAssertTrue(state.inspectHeldPress())
        XCTAssertFalse(state.inspectHeldPress())
        XCTAssertFalse(state.endPress())
        XCTAssertEqual(route.factories, 1)
        XCTAssertEqual(route.inspected, ["original"])
        XCTAssertTrue(route.inserted.isEmpty)
        state.beginPress(); XCTAssertTrue(state.endPress())
        XCTAssertEqual(route.inserted, ["original"])
    }
    func testModeDocumentMissingIdentityOrResizeInvalidatesBothActionKindsBeforeFire() {
        for kind in 0..<4 {
            for hover in [true, false] {
                let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
                configure(state, route: route)
                if hover { state.beginHover() } else { state.beginPress() }
                let current = route.context!
                switch kind {
                case 0: route.changeMode()
                case 1: route.context = .init(modeIdentifier: current.modeIdentifier, documentIdentifier: UUID(), interactionIdentifier: current.interactionIdentifier)
                case 2: route.context = nil
                default: route.context = .init(modeIdentifier: current.modeIdentifier, documentIdentifier: current.documentIdentifier, interactionIdentifier: UUID())
                }
                if hover { clock.deliver(0) } else { XCTAssertFalse(state.endPress()) }
                XCTAssertTrue(route.inspected.isEmpty)
                XCTAssertTrue(route.inserted.isEmpty)
            }
        }
    }
    func testSameWindowDisappearanceAndReappearanceCannotReviveOldActions() {
        for hover in [true, false] {
            let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
            configure(state, route: route)
            if hover { state.beginHover() } else { state.beginPress() }
            let original = route.context!
            // Mirrors controller viewWillDisappear: same document, mode and
            // mounted key; only the interaction generation is invalidated.
            route.context = .init(modeIdentifier: original.modeIdentifier,
                documentIdentifier: original.documentIdentifier, interactionIdentifier: UUID())
            XCTAssertEqual(route.context?.modeIdentifier, original.modeIdentifier)
            XCTAssertEqual(route.context?.documentIdentifier, original.documentIdentifier)
            if hover { clock.deliver(0) } else { XCTAssertFalse(state.endPress()) }
            XCTAssertTrue(route.inspected.isEmpty)
            XCTAssertTrue(route.inserted.isEmpty)
            // Reappearing can use a fresh snapshot even with unchanged view ID.
            configure(state, route: route)
            if hover {
                state.beginHover(); clock.deliver(1)
                XCTAssertEqual(route.inspected, ["original"])
            } else {
                state.beginPress(); XCTAssertTrue(state.endPress())
                XCTAssertEqual(route.inserted, ["original"])
            }
        }
    }
    func testCancelledTouchHoverExitAndDetachStyleCleanupRejectAlreadyQueuedCallbacks() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        configure(state, route: route)
        state.beginPress(); state.cancelPress()
        XCTAssertFalse(state.endPress())
        state.beginHover(); state.endHover(); clock.deliver(0)
        state.beginHover(); state.cancelAll(); clock.deliver(1)
        XCTAssertTrue(route.inspected.isEmpty)
        XCTAssertTrue(route.inserted.isEmpty)
        state.beginPress(); XCTAssertTrue(state.endPress())
    }
    func testTouchDownCancelsHoverAndItsQueuedCallbackCannotInspectDuringPress() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        configure(state, route: route); state.beginHover(); state.beginPress()
        clock.deliver(0)
        XCTAssertTrue(route.inspected.isEmpty)
        XCTAssertTrue(state.endPress())
        XCTAssertEqual(route.inserted, ["original"])
    }
    func testUnavailableFactoryCannotScheduleAHoverOrInsertOnRelease() {
        let clock = Clock(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        state.configure(contextIdentifier: UUID(), itemIdentifier: "missing", enabled: true) { nil }
        state.beginHover(); state.beginPress()
        XCTAssertTrue(clock.jobs.isEmpty)
        XCTAssertFalse(state.endPress())
        XCTAssertFalse(state.activateInsert())
        XCTAssertFalse(state.activateInspect())
    }
    func testAccessibilityGetsFreshGuardedActionsAndNeverConflatesInsertWithInspect() {
        let route = Route(), state = KeyboardInspectableInteraction()
        configure(state, route: route)
        XCTAssertTrue(state.activateInspect())
        XCTAssertTrue(route.inserted.isEmpty)
        XCTAssertTrue(state.activateInsert())
        XCTAssertEqual(route.inspected, ["original"])
        XCTAssertEqual(route.inserted, ["original"])
        route.changeMode()
        XCTAssertFalse(state.activateInsert())
        XCTAssertFalse(state.activateInspect())
    }
    func testReentrantHoverFactoryCannotReplaceANewerHoverSnapshot() {
        let clock = Clock(), route = Route(), state = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        let mode = route.context!.modeIdentifier
        state.configure(contextIdentifier: mode, itemIdentifier: "original", enabled: true) {
            state.endHover()
            self.configure(state, route: route, item: "new")
            state.beginHover()
            return route.actions(rendered: mode, item: "old")
        }
        state.beginHover()
        XCTAssertEqual(clock.jobs.count, 1)
        clock.deliver(0)
        XCTAssertEqual(route.inspected, ["new"])
    }
    func testReentrantPressFactoryCannotReplaceANewerHeldAction() {
        let route = Route(), state = KeyboardInspectableInteraction()
        let mode = route.context!.modeIdentifier
        state.configure(contextIdentifier: mode, itemIdentifier: "original", enabled: true) {
            state.cancelPress()
            self.configure(state, route: route, item: "new")
            state.beginPress()
            return route.actions(rendered: mode, item: "old")
        }
        state.beginPress()
        XCTAssertTrue(state.endPress())
        XCTAssertEqual(route.inserted, ["new"])
    }
    func testDeinitInvalidatesTimerAndWeakQueuedCallbackCannotInspect() {
        let clock = Clock(), route = Route()
        var state: KeyboardInspectableInteraction? = KeyboardInspectableInteraction(scheduleTimer: clock.schedule)
        weak var weakState: KeyboardInspectableInteraction?
        weakState = state
        configure(state!, route: route)
        state?.beginHover()
        state = nil
        XCTAssertNil(weakState)
        XCTAssertFalse(clock.jobs[0].timer.isValid)
        clock.deliver(0)
        XCTAssertTrue(route.inspected.isEmpty)
    }
}
#endif
