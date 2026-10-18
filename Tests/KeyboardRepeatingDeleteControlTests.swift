#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardRepeatingDeleteControlTests: XCTestCase {
    private final class Clock {
        struct Job {
            let interval: TimeInterval
            let repeats: Bool
            let timer: Timer
            let action: (Timer) -> Void
        }
        var jobs: [Job] = []
        func schedule(_ interval: TimeInterval, _ repeats: Bool, _ action: @escaping (Timer) -> Void) -> Timer {
            // The clock delivers the recorded callback explicitly; this Timer
            // supplies the real validity/invalidation behavior without a run loop.
            let timer = Timer(timeInterval: interval, repeats: repeats) { _ in }
            jobs.append(Job(interval: interval, repeats: repeats, timer: timer, action: action))
            return timer
        }
        // Deliver even invalidated jobs to model callbacks already queued when
        // cancellation happened. Our token guard, not Timer itself, must stop them.
        func deliver(_ index: Int) {
            let job = jobs[index]
            job.action(job.timer)
            // A real run-loop expiry invalidates a one-shot timer after its
            // callback. Still deliver explicitly queued jobs above validity.
            if !job.repeats { job.timer.invalidate() }
        }
    }

    private final class Route {
        var isQuery: Bool
        var modeIdentifier = UUID()
        var documentIdentifier = UUID()
        var queryDeletes = 0
        var hostDeletes = 0
        var factories = 0
        init(isQuery: Bool) { self.isQuery = isQuery }
        var context: KeyboardDeleteContext { .init(modeIdentifier: modeIdentifier, isQuery: isQuery, documentIdentifier: documentIdentifier) }
        func action(renderedMode: UUID, renderedIsQuery: Bool) -> RepeatingDeleteButton.DeleteAction {
            factories += 1
            let bound = KeyboardDeleteContext(modeIdentifier: renderedMode, isQuery: renderedIsQuery, documentIdentifier: documentIdentifier)
            return bound.guardedAction(currentContext: { [weak self] in self?.context }, delete: { [weak self] in
                if renderedIsQuery { self?.queryDeletes += 1 }
                else { self?.hostDeletes += 1 }
            })
        }
    }

    private func configure(_ button: RepeatingDeleteButton, route: Route, renderedIsQuery: Bool) {
        let renderedMode = route.modeIdentifier
        button.configure(isQuery: renderedIsQuery) { route.action(renderedMode: renderedMode, renderedIsQuery: renderedIsQuery) }
    }

    func testNormalHoldUsesOneFactoryAndKeepsRepeatCadence() {
        let clock = Clock(), route = Route(isQuery: true)
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        configure(button, route: route, renderedIsQuery: true)
        button.sendActions(for: .touchDown)
        XCTAssertEqual(route.queryDeletes, 1)
        XCTAssertEqual(route.factories, 1)
        XCTAssertEqual(clock.jobs[0].interval, 0.4)
        XCTAssertFalse(clock.jobs[0].repeats)
        clock.deliver(0)
        XCTAssertEqual(route.queryDeletes, 2)
        XCTAssertEqual(clock.jobs[1].interval, 0.085)
        XCTAssertTrue(clock.jobs[1].repeats)
        clock.deliver(1)
        clock.deliver(1)
        XCTAssertEqual(route.queryDeletes, 4)
        XCTAssertEqual(route.hostDeletes, 0)
        XCTAssertEqual(route.factories, 1)
        button.sendActions(for: .touchUpInside)
        XCTAssertFalse(clock.jobs[1].timer.isValid)
    }

    func testHiddenHeaderDeleteIsAbsentFromAccessibilityAndCannotResumeItsHeldStream() {
        let clock = Clock(), route = Route(isQuery: false)
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        let mode = route.modeIdentifier
        let factory = { route.action(renderedMode: mode, renderedIsQuery: false) }
        button.configure(isQuery: false, actionFactory: factory)
        button.sendActions(for: .touchDown)
        clock.deliver(0)
        XCTAssertEqual(route.hostDeletes, 2)
        button.configure(isQuery: false, enabled: false, actionFactory: factory)
        XCTAssertFalse(button.isEnabled)
        XCTAssertFalse(button.isUserInteractionEnabled)
        XCTAssertFalse(button.isAccessibilityElement)
        XCTAssertTrue(button.accessibilityElementsHidden)
        XCTAssertTrue(button.isHidden)
        clock.deliver(1)
        button.sendActions(for: .touchDown)
        XCTAssertFalse(button.accessibilityActivate())
        XCTAssertEqual(route.hostDeletes, 2)
        button.configure(isQuery: false, enabled: true, actionFactory: factory)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.isAccessibilityElement)
        XCTAssertFalse(button.accessibilityElementsHidden)
        XCTAssertFalse(button.isHidden)
        clock.deliver(0); clock.deliver(1)
        XCTAssertEqual(route.hostDeletes, 2)
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchDown)
        XCTAssertEqual(route.hostDeletes, 3)
        button.sendActions(for: .touchUpInside)
    }

    func testConfiguredScopeTransitionsStopBothDirectionsAndQueuedCallbacks() {
        for initial in [true, false] {
            let clock = Clock(), route = Route(isQuery: initial)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            configure(button, route: route, renderedIsQuery: initial)
            button.sendActions(for: .touchDown)
            clock.deliver(0)
            let before = (route.queryDeletes, route.hostDeletes)
            route.isQuery = !initial
            configure(button, route: route, renderedIsQuery: !initial)
            XCTAssertFalse(clock.jobs[1].timer.isValid)
            clock.deliver(1)
            clock.deliver(0)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.queryDeletes, before.0)
            XCTAssertEqual(route.hostDeletes, before.1)
            XCTAssertEqual(route.factories, 1)
            button.sendActions(for: .touchUpInside)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.factories, 2)
            XCTAssertEqual(route.queryDeletes, before.0 + (initial ? 0 : 1))
            XCTAssertEqual(route.hostDeletes, before.1 + (initial ? 1 : 0))
            button.sendActions(for: .touchCancel)
        }
    }

    func testPreRenderScopeChangeCannotRerouteAnExistingPress() {
        for initial in [true, false] {
            let clock = Clock(), route = Route(isQuery: initial)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            configure(button, route: route, renderedIsQuery: initial)
            button.sendActions(for: .touchDown)
            let before = (route.queryDeletes, route.hostDeletes)
            route.isQuery = !initial // SwiftUI has not called configure yet.
            clock.deliver(0)
            XCTAssertEqual(route.queryDeletes, before.0)
            XCTAssertEqual(route.hostDeletes, before.1)
            XCTAssertEqual(clock.jobs.count, 1)
            route.isQuery = initial
            clock.deliver(0)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.factories, 1)
            XCTAssertEqual(route.queryDeletes, before.0)
            XCTAssertEqual(route.hostDeletes, before.1)
            button.sendActions(for: .touchCancel)
        }
    }

    func testStaleRenderedScopeIsRejectedBeforeTheFirstDelete() {
        for current in [true, false] {
            let clock = Clock(), route = Route(isQuery: current)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            configure(button, route: route, renderedIsQuery: !current)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.queryDeletes, 0)
            XCTAssertEqual(route.hostDeletes, 0)
            XCTAssertTrue(clock.jobs.isEmpty)
            XCTAssertEqual(route.factories, 1)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.factories, 1)
            button.sendActions(for: .touchCancel)
        }
    }

    func testDocumentChangeStopsAQueryOrHostPressBeforeAnyFurtherDelete() {
        for scope in [true, false] {
            let clock = Clock(), route = Route(isQuery: scope)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            configure(button, route: route, renderedIsQuery: scope)
            button.sendActions(for: .touchDown)
            clock.deliver(0)
            let before = (route.queryDeletes, route.hostDeletes)
            route.documentIdentifier = UUID()
            clock.deliver(1)
            XCTAssertFalse(clock.jobs[1].timer.isValid)
            clock.deliver(1)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.queryDeletes, before.0)
            XCTAssertEqual(route.hostDeletes, before.1)
            XCTAssertEqual(route.factories, 1)
            button.sendActions(for: .touchUpInside)
            button.sendActions(for: .touchDown) // A new press may bind the new document.
            XCTAssertEqual(route.factories, 2)
            button.sendActions(for: .touchCancel)
        }
    }

    func testModeChangesStopDelayAndRepeatsAndCannotReviveWhenReturning() {
        for scope in [true, false] {
            for alreadyRepeating in [false, true] {
                let clock = Clock(), route = Route(isQuery: scope)
                let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
                let originalMode = route.modeIdentifier, originalDocument = route.documentIdentifier
                configure(button, route: route, renderedIsQuery: scope)
                button.sendActions(for: .touchDown)
                if alreadyRepeating { clock.deliver(0) }
                let pending = alreadyRepeating ? 1 : 0
                let before = (route.queryDeletes, route.hostDeletes)
                let jobCount = clock.jobs.count
                route.modeIdentifier = UUID() // Panel/page/section changed, not document or query scope.
                XCTAssertEqual(route.documentIdentifier, originalDocument)
                XCTAssertEqual(route.isQuery, scope)
                clock.deliver(pending)
                XCTAssertFalse(clock.jobs[pending].timer.isValid)
                XCTAssertEqual(clock.jobs.count, jobCount)
                route.modeIdentifier = originalMode // Even exact old identity must not revive this held press.
                configure(button, route: route, renderedIsQuery: scope)
                for index in clock.jobs.indices { clock.deliver(index) }
                button.sendActions(for: .touchDown)
                XCTAssertEqual(route.queryDeletes, before.0)
                XCTAssertEqual(route.hostDeletes, before.1)
                XCTAssertEqual(route.factories, 1)
                XCTAssertEqual(clock.jobs.count, jobCount)
                button.sendActions(for: .touchUpInside)
                button.sendActions(for: .touchDown)
                XCTAssertEqual(route.queryDeletes, before.0 + (scope ? 1 : 0))
                XCTAssertEqual(route.hostDeletes, before.1 + (scope ? 0 : 1))
                XCTAssertEqual(route.factories, 2)
                button.sendActions(for: .touchCancel)
            }
        }
    }

    func testStaleRenderedModeRejectsTheFirstDeleteWithoutScheduling() {
        for scope in [true, false] {
            let clock = Clock(), route = Route(isQuery: scope)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            configure(button, route: route, renderedIsQuery: scope)
            route.modeIdentifier = UUID() // Model changed before the rendered factory updated.
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.queryDeletes, 0)
            XCTAssertEqual(route.hostDeletes, 0)
            XCTAssertEqual(route.factories, 1)
            XCTAssertTrue(clock.jobs.isEmpty)
            configure(button, route: route, renderedIsQuery: scope)
            button.sendActions(for: .touchDown) // Updating the future factory cannot restart a rejected hold.
            XCTAssertEqual(route.factories, 1)
            XCTAssertTrue(clock.jobs.isEmpty)
            button.sendActions(for: .touchUpInside)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.queryDeletes, scope ? 1 : 0)
            XCTAssertEqual(route.hostDeletes, scope ? 0 : 1)
            XCTAssertEqual(route.factories, 2)
            XCTAssertEqual(clock.jobs.count, 1)
            button.sendActions(for: .touchCancel)
        }
    }

    func testMissingCurrentDocumentRejectsTheAction() {
        let context = KeyboardDeleteContext(modeIdentifier: UUID(), isQuery: false, documentIdentifier: UUID())
        var deletes = 0
        let action = context.guardedAction(currentContext: { nil }, delete: { deletes += 1 })
        XCTAssertFalse(action())
        XCTAssertEqual(deletes, 0)
    }

    func testDuplicateDownAndSameScopeUpdatesDoNotReplaceTheBoundAction() {
        let clock = Clock(), route = Route(isQuery: false)
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        configure(button, route: route, renderedIsQuery: false)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchDown)
        var replacementCalls = 0
        button.configure(isQuery: false) { { replacementCalls += 1; return true } }
        clock.deliver(0)
        clock.deliver(1)
        XCTAssertEqual(route.hostDeletes, 3)
        XCTAssertEqual(route.factories, 1)
        XCTAssertEqual(replacementCalls, 0)
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchDown)
        XCTAssertEqual(replacementCalls, 1)
        button.sendActions(for: .touchCancel)
    }

    func testAllTerminalEventsCancelQueuedRepeatsAndAllowANewPress() {
        for event in [UIControl.Event.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
            let clock = Clock(), route = Route(isQuery: false)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            configure(button, route: route, renderedIsQuery: false)
            button.sendActions(for: .touchDown)
            clock.deliver(0)
            button.sendActions(for: event)
            clock.deliver(1)
            XCTAssertEqual(route.hostDeletes, 2)
            button.sendActions(for: .touchDown)
            XCTAssertEqual(route.hostDeletes, 3)
            button.sendActions(for: .touchCancel)
        }
    }

    func testDetachAndMoveToAnotherWindowCancelWithoutRestarting() {
        for reparent in [false, true] {
            let clock = Clock(), route = Route(isQuery: false)
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            let first = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            let second = UIWindow(frame: first.frame)
            defer { withExtendedLifetime(first) {}; withExtendedLifetime(second) {} }
            first.addSubview(button)
            configure(button, route: route, renderedIsQuery: false)
            button.sendActions(for: .touchDown)
            clock.deliver(0)
            if reparent { second.addSubview(button) }
            else { button.removeFromSuperview() }
            clock.deliver(1)
            XCTAssertEqual(route.hostDeletes, 2)
            XCTAssertFalse(clock.jobs[1].timer.isValid)
        }
    }

    func testSynchronousScopeChangeInsideActionCannotScheduleANewTimer() {
        let clock = Clock()
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        var deletes = 0
        button.configure(isQuery: true) { [weak button] in
            { deletes += 1; button?.configure(isQuery: false) { { true } }; return true }
        }
        button.sendActions(for: .touchDown)
        XCTAssertEqual(deletes, 1)
        XCTAssertTrue(clock.jobs.isEmpty)
        button.sendActions(for: .touchCancel)
    }

    func testRejectedOldActionCannotCancelAReentrantNewPress() {
        let clock = Clock()
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        var oldDeletes = 0, newDeletes = 0
        button.configure(isQuery: true) { [weak button] in
            {
                oldDeletes += 1
                button?.sendActions(for: .touchUpInside)
                button?.configure(isQuery: false) { { newDeletes += 1; return true } }
                button?.sendActions(for: .touchDown)
                return false
            }
        }
        button.sendActions(for: .touchDown)
        XCTAssertEqual(oldDeletes, 1)
        XCTAssertEqual(newDeletes, 1)
        XCTAssertEqual(clock.jobs.count, 1, "Only the new press may schedule a delay")
        XCTAssertTrue(clock.jobs[0].timer.isValid)
        clock.deliver(0)
        XCTAssertEqual(newDeletes, 2)
        XCTAssertEqual(clock.jobs.count, 2)
        clock.deliver(1)
        XCTAssertEqual(newDeletes, 3)
        XCTAssertEqual(oldDeletes, 1)
        button.sendActions(for: .touchCancel)
    }

    func testOldFactoryCannotOverwriteAReentrantNewPressAction() {
        let clock = Clock()
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        var oldDeletes = 0, newDeletes = 0
        button.configure(isQuery: true) { [weak button] in
            button?.sendActions(for: .touchUpInside)
            button?.configure(isQuery: false) { { newDeletes += 1; return true } }
            button?.sendActions(for: .touchDown)
            return { oldDeletes += 1; return true }
        }
        button.sendActions(for: .touchDown)
        XCTAssertEqual(oldDeletes, 0)
        XCTAssertEqual(newDeletes, 1)
        XCTAssertEqual(clock.jobs.count, 1, "Only the new press may schedule a delay")
        clock.deliver(0)
        clock.deliver(1)
        XCTAssertEqual(oldDeletes, 0)
        XCTAssertEqual(newDeletes, 3)
        XCTAssertEqual(clock.jobs.count, 2)
        button.sendActions(for: .touchCancel)
    }

    func testAccessibilityIsImmediateScopedAndDoesNotLeaveRepeatTimers() {
        let clock = Clock(), route = Route(isQuery: true)
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        XCTAssertFalse(button.accessibilityActivate())
        configure(button, route: route, renderedIsQuery: true)
        XCTAssertTrue(button.accessibilityActivate())
        XCTAssertEqual(route.queryDeletes, 1)
        XCTAssertTrue(clock.jobs.isEmpty)
        route.isQuery = false
        XCTAssertFalse(button.accessibilityActivate())
        XCTAssertEqual(route.hostDeletes, 0)
        XCTAssertEqual(button.accessibilityIdentifier, "keyboard.delete")
        XCTAssertEqual(button.accessibilityLabel, "Delete search character")
        configure(button, route: route, renderedIsQuery: false)
        XCTAssertEqual(button.accessibilityLabel, "Delete backward")
        button.sendActions(for: .touchDown)
        XCTAssertTrue(button.accessibilityActivate())
        clock.deliver(0)
        XCTAssertEqual(route.hostDeletes, 2)
    }

    func testAccessibilityFactoryCannotDeleteAfterHidingEvenIfShownAgainBeforeReturning() {
        for showAgain in [false, true] {
            let clock = Clock()
            let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
            var oldDeletes = 0, newDeletes = 0
            let replacement: RepeatingDeleteButton.ActionFactory = { { newDeletes += 1; return true } }
            button.configure(isQuery: false) { [weak button] in
                button?.configure(isQuery: false, enabled: false, actionFactory: replacement)
                if showAgain { button?.configure(isQuery: false, enabled: true, actionFactory: replacement) }
                return { oldDeletes += 1; return true }
            }
            XCTAssertFalse(button.accessibilityActivate())
            XCTAssertEqual(oldDeletes, 0)
            XCTAssertEqual(newDeletes, 0)
            XCTAssertTrue(clock.jobs.isEmpty)
            button.configure(isQuery: false, enabled: true, actionFactory: replacement)
            XCTAssertTrue(button.accessibilityActivate())
            XCTAssertEqual(newDeletes, 1)
            XCTAssertTrue(clock.jobs.isEmpty)
        }
    }

    func testOldAccessibilityFactoryCannotExecuteOrCancelAReplacementPhysicalPress() {
        let clock = Clock()
        let button = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        var oldDeletes = 0, newDeletes = 0
        button.configure(isQuery: false) { [weak button] in
            button?.configure(isQuery: false) { { newDeletes += 1; return true } }
            button?.sendActions(for: .touchDown)
            return { oldDeletes += 1; return true }
        }
        XCTAssertFalse(button.accessibilityActivate())
        XCTAssertEqual(oldDeletes, 0)
        XCTAssertEqual(newDeletes, 1)
        XCTAssertEqual(clock.jobs.count, 1)
        clock.deliver(0)
        clock.deliver(1)
        XCTAssertEqual(newDeletes, 3)
        XCTAssertEqual(oldDeletes, 0)
        button.sendActions(for: .touchCancel)
    }

    func testDeinitializationInvalidatesTimersAndQueuedJobsAreHarmless() {
        let clock = Clock()
        var button: RepeatingDeleteButton? = RepeatingDeleteButton(scheduleTimer: clock.schedule)
        weak var weakButton: RepeatingDeleteButton?
        weakButton = button
        button?.configure(isQuery: false) { { true } }
        button?.sendActions(for: .touchDown)
        button = nil
        XCTAssertNil(weakButton)
        XCTAssertFalse(clock.jobs[0].timer.isValid)
        clock.deliver(0)
    }
}
#endif
