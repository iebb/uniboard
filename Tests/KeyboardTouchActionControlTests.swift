#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardTouchActionControlTests: XCTestCase {
    private final class Route {
        var context = KeyboardInputActionContext(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        var calls = 0
        var factories = 0
        func action(renderedMode: UUID) -> () -> Bool {
            factories += 1
            let bound = KeyboardInputActionContext(modeIdentifier: renderedMode, documentIdentifier: context.documentIdentifier,
                interactionIdentifier: context.interactionIdentifier)
            return bound.guardedAction(currentContext: { self.context }, perform: { self.calls += 1; return true })
        }
    }
    private func configure(_ button: KeyboardTouchActionButton, route: Route) {
        let rendered = route.context.modeIdentifier
        button.configure(contextIdentifier: rendered) { route.action(renderedMode: rendered) }
    }
    private func tap(_ button: KeyboardTouchActionButton) {
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
    }

    func testVisibleFeedbackClearsOnReleaseCancellationContextChangeAndDetach() {
        let button = KeyboardTouchActionButton(), route = Route()
        configure(button, route: route)
        XCTAssertFalse(button.pressFeedback.isPressed)
        for terminal in [UIControl.Event.touchUpInside, .touchCancel, .touchDragExit, .touchUpOutside] {
            button.sendActions(for: .touchDown)
            XCTAssertTrue(button.pressFeedback.isPressed)
            XCTAssertFalse(button.pressFeedback.isUserInteractionEnabled)
            button.sendActions(for: terminal)
            XCTAssertFalse(button.pressFeedback.isPressed)
        }
        button.sendActions(for: .touchDown)
        button.configure(contextIdentifier: UUID()) { { true } }
        XCTAssertFalse(button.pressFeedback.isPressed)
        button.sendActions(for: .touchCancel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.addSubview(button)
        button.sendActions(for: .touchDown)
        XCTAssertTrue(button.pressFeedback.isPressed)
        button.removeFromSuperview()
        XCTAssertFalse(button.pressFeedback.isPressed)
    }

    func testExecutesOnReleaseWithOneFactoryDespiteDuplicateDownAndUpdatedFactory() {
        let route = Route(), button = KeyboardTouchActionButton()
        configure(button, route: route)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchDown)
        XCTAssertEqual(route.calls, 0)
        var replacement = 0
        button.configure(contextIdentifier: route.context.modeIdentifier) { { replacement += 1; return true } }
        button.sendActions(for: .touchUpInside)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(route.calls, 1)
        XCTAssertEqual(route.factories, 1)
        XCTAssertEqual(replacement, 0)
        tap(button)
        XCTAssertEqual(replacement, 1)
    }

    func testPreRenderMismatchRejectsBothAnExistingPressAndAnOldRenderedKey() {
        for pressAlreadyBegan in [true, false] {
            let route = Route(), button = KeyboardTouchActionButton()
            configure(button, route: route)
            if pressAlreadyBegan { button.sendActions(for: .touchDown) }
            route.context = .init(modeIdentifier: UUID(), documentIdentifier: route.context.documentIdentifier,
                interactionIdentifier: route.context.interactionIdentifier)
            if !pressAlreadyBegan { button.sendActions(for: .touchDown) }
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(route.calls, 0)
            configure(button, route: route)
            tap(button)
            XCTAssertEqual(route.calls, 1)
        }
    }

    func testConfiguredContextChangeCancelsHeldPressWithoutAllowingDuplicateDownToRebind() {
        let route = Route(), button = KeyboardTouchActionButton()
        configure(button, route: route)
        button.sendActions(for: .touchDown)
        route.context = .init(modeIdentifier: UUID(), documentIdentifier: route.context.documentIdentifier,
            interactionIdentifier: route.context.interactionIdentifier)
        configure(button, route: route)
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(route.calls, 0)
        XCTAssertEqual(route.factories, 1)
        tap(button)
        XCTAssertEqual(route.calls, 1)
    }

    func testDocumentOrResizeGenerationChangeRejectsPendingHostAction() {
        for documentChanges in [true, false] {
            let route = Route(), button = KeyboardTouchActionButton()
            configure(button, route: route)
            button.sendActions(for: .touchDown)
            route.context = .init(modeIdentifier: route.context.modeIdentifier,
                documentIdentifier: documentChanges ? UUID() : route.context.documentIdentifier,
                interactionIdentifier: documentChanges ? route.context.interactionIdentifier : UUID())
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(route.calls, 0)
        }
    }

    func testMissingContextAndRejectedOperationNeverReportSuccess() {
        let context = KeyboardInputActionContext(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        var calls = 0
        XCTAssertFalse(context.guardedAction(currentContext: { nil }, perform: { calls += 1; return true })())
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(context.guardedAction(currentContext: { context }, perform: { calls += 1; return false })())
        XCTAssertEqual(calls, 1)
    }

    func testAllCancellationEventsDiscardActionAndPermitNextPress() {
        for terminal in [UIControl.Event.touchCancel, .touchUpOutside, .touchDragExit] {
            let route = Route(), button = KeyboardTouchActionButton()
            configure(button, route: route)
            button.sendActions(for: .touchDown)
            button.sendActions(for: terminal)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(route.calls, 0)
            tap(button)
            XCTAssertEqual(route.calls, 1)
        }
    }

    func testDetachingFromARealWindowDiscardsPendingAction() {
        let route = Route(), button = KeyboardTouchActionButton()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        window.addSubview(button)
        configure(button, route: route)
        button.sendActions(for: .touchDown)
        button.removeFromSuperview()
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(route.calls, 0)
        window.addSubview(button)
        tap(button)
        XCTAssertEqual(route.calls, 1)
    }

    func testAccessibilityActivationHasFreshGuardAndNoDelayedDuplicateAction() {
        let route = Route(), button = KeyboardTouchActionButton()
        configure(button, route: route)
        XCTAssertTrue(button.accessibilityActivate())
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(route.calls, 1)
        route.context = .init(modeIdentifier: UUID(), documentIdentifier: route.context.documentIdentifier,
            interactionIdentifier: route.context.interactionIdentifier)
        XCTAssertFalse(button.accessibilityActivate())
        XCTAssertEqual(route.calls, 1)
    }

    func testReentrantFactoryCannotOverwriteNewPress() {
        let button = KeyboardTouchActionButton(), context = UUID()
        var oldCalls = 0, newCalls = 0
        button.configure(contextIdentifier: context) {
            button.sendActions(for: .touchCancel)
            button.configure(contextIdentifier: context) { { newCalls += 1; return true } }
            button.sendActions(for: .touchDown)
            return { oldCalls += 1; return true }
        }
        button.sendActions(for: .touchDown)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
    }

    func testReentrantActionCannotCancelNewPressOnReturn() {
        let button = KeyboardTouchActionButton(), context = UUID()
        var first = 0, second = 0
        button.configure(contextIdentifier: context) {
            {
                first += 1
                button.configure(contextIdentifier: context) { { second += 1; return true } }
                button.sendActions(for: .touchDown)
                return false
            }
        }
        tap(button)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }
    func testRapidChordedKeysRetainTheirTouchDownOutputWhenShiftChanges() {
        let mode = UUID(), document = UUID(), interaction = UUID()
        let context = KeyboardInputActionContext(modeIdentifier: mode, documentIdentifier: document, interactionIdentifier: interaction)
        let first = KeyboardTouchActionButton(), second = KeyboardTouchActionButton()
        var uppercase = true
        var inserted: [String] = []
        for (button, raw) in [(first, "a"), (second, "b")] {
            button.configure(contextIdentifier: mode) {
                let text = uppercase ? raw.uppercased() : raw
                return context.guardedAction(currentContext: { context }, perform: {
                    inserted.append(text)
                    uppercase = false
                    return true
                })
            }
        }
        first.sendActions(for: .touchDown)
        second.sendActions(for: .touchDown)
        first.sendActions(for: .touchUpInside)
        // A same-domain representable update (including extra self-edit
        // notifications) must not replace the second finger's bound output.
        second.configure(contextIdentifier: mode) {
            let refreshed = uppercase ? "B" : "b"
            return context.guardedAction(currentContext: { context }, perform: {
                inserted.append(refreshed); return true
            })
        }
        second.sendActions(for: .touchUpInside)
        XCTAssertEqual(inserted, ["A", "B"])
        tap(second)
        XCTAssertEqual(inserted, ["A", "B", "b"])
    }

    func testReentrantAccessibilityFactoryCannotConsumeANewerPress() {
        let button = KeyboardTouchActionButton(), context = UUID()
        var oldCalls = 0, newCalls = 0
        button.configure(contextIdentifier: context) {
            button.sendActions(for: .touchCancel)
            button.configure(contextIdentifier: context) { { newCalls += 1; return true } }
            button.sendActions(for: .touchDown)
            return { oldCalls += 1; return true }
        }
        XCTAssertFalse(button.accessibilityActivate())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 0)
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(newCalls, 1)
    }
}

@MainActor
final class KeyboardConfigurationTouchViewTests: XCTestCase {
    private func fixture() -> (UIWindow, UIScrollView, KeyboardConfigurationTouchView, CGPoint) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 200, width: 320, height: 220))
        scroll.contentSize = CGSize(width: 320, height: 500)
        let view = KeyboardConfigurationTouchView(frame: CGRect(x: 20, y: 40, width: 60, height: 36))
        window.addSubview(scroll)
        scroll.addSubview(view)
        view.isEnabled = true
        return (window, scroll, view, view.convert(CGPoint(x: 30, y: 18), to: window))
    }

    func testConfigurationFeedbackCancelsAsSoonAsScrollingStarts() {
        let (window, _, view, point) = fixture()
        let owner = NSObject()
        view.configure(contextIdentifier: UUID()) { { true } }
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        XCTAssertTrue(view.pressFeedback.isPressed)
        view.movePhysicalPress(owner: owner, at: CGPoint(x: point.x + 11, y: point.y))
        XCTAssertFalse(view.pressFeedback.isPressed)
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertFalse(view.pressFeedback.isPressed)
        withExtendedLifetime(window) {}
    }
    func testPlainConfigurationSurfaceAllowsThePublicScrollCancellationContract() {
        let (window, scroll, view, _) = fixture()
        withExtendedLifetime(window) {
            XCTAssertFalse((view as UIView) is UIControl)
            XCTAssertTrue(scroll.touchesShouldCancel(in: view))
            XCTAssertFalse(scroll.touchesShouldCancel(in: KeyboardTouchActionButton()))
            XCTAssertTrue(scroll.canCancelContentTouches)
        }
    }

    func testTapSnapshotsOneGuardedActionAndExecutesOnlyOnceOnRelease() {
        let (window, _, view, point) = fixture()
        let owner = NSObject(), context = UUID()
        var factories = 0, first = 0, replacement = 0
        view.configure(contextIdentifier: context) { factories += 1; return { first += 1; return true } }
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        XCTAssertFalse(view.beginPhysicalPress(owner: owner, at: point))
        view.configure(contextIdentifier: context) { { replacement += 1; return true } }
        XCTAssertEqual(first, 0)
        view.endPhysicalPress(owner: owner, at: point)
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(factories, 1)
        XCTAssertEqual(replacement, 0)
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertEqual(replacement, 1)
        withExtendedLifetime(window) {}
    }

    func testDragAndScrollCancellationNeverCommitAndFreshTapRecovers() {
        let (window, _, view, point) = fixture()
        let owner = NSObject()
        var calls = 0
        view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        view.movePhysicalPress(owner: owner, at: CGPoint(x: point.x, y: point.y - 11))
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertEqual(calls, 0, "Moving back into the key cannot revive a cancelled press")
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        view.cancelPhysicalPress()
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(window) {}
    }

    func testStrictContextReconfigurationAndHideShowRejectTheOldRelease() {
        let (window, _, view, point) = fixture()
        let oldOwner = NSObject(), freshOwner = NSObject()
        var calls = 0
        view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        XCTAssertTrue(view.beginPhysicalPress(owner: oldOwner, at: point))
        view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        view.endPhysicalPress(owner: oldOwner, at: point)
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(view.beginPhysicalPress(owner: oldOwner, at: point))
        view.isEnabled = false
        view.isEnabled = true
        XCTAssertTrue(view.beginPhysicalPress(owner: freshOwner, at: point))
        view.endPhysicalPress(owner: oldOwner, at: point)
        XCTAssertEqual(calls, 0)
        view.endPhysicalPress(owner: freshOwner, at: point)
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(window) {}
    }

    func testDocumentGuardStillRejectsAReleaseBeforeTheRepresentableUpdates() {
        let (window, _, view, point) = fixture()
        let owner = NSObject()
        var current = KeyboardInputActionContext(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        let original = current
        var calls = 0
        view.configure(contextIdentifier: original.modeIdentifier) {
            original.guardedAction(currentContext: { current }, perform: { calls += 1; return true })
        }
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        current = .init(modeIdentifier: original.modeIdentifier, documentIdentifier: UUID(), interactionIdentifier: original.interactionIdentifier)
        view.endPhysicalPress(owner: owner, at: point)
        XCTAssertEqual(calls, 0)
        withExtendedLifetime(window) {}
    }

    func testWindowBoundsFrameAnchorAndDetachChangesCancelBeforeRelease() {
        for change in 0..<4 {
            let (window, scroll, view, point) = fixture()
            let owner = NSObject()
            var calls = 0
            view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
            XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
            switch change {
            case 0: window.bounds.origin.y += 1
            case 1: window.frame.origin.x += 1
            case 2: view.frame.origin.y += 1
            default: view.removeFromSuperview()
            }
            view.endPhysicalPress(owner: owner, at: point)
            XCTAssertEqual(calls, 0)
            if view.superview == nil { scroll.addSubview(view) }
            let fresh = view.convert(CGPoint(x: 30, y: 18), to: window)
            XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: fresh))
            view.endPhysicalPress(owner: owner, at: fresh)
            XCTAssertEqual(calls, 1)
            withExtendedLifetime(window) {}
        }
    }

    func testForeignTouchCancelsOriginalWithoutRetargetingAndOrphanCanRecover() {
        let (window, _, view, point) = fixture()
        let first = NSObject(), foreign = NSObject()
        var calls = 0
        view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        XCTAssertTrue(view.beginPhysicalPress(owner: first, at: point))
        XCTAssertFalse(view.beginPhysicalPress(owner: foreign, at: point))
        view.endPhysicalPress(owner: foreign, at: point)
        view.endPhysicalPress(owner: first, at: point)
        XCTAssertEqual(calls, 0)
        var abandoned: NSObject? = NSObject()
        XCTAssertTrue(view.beginPhysicalPress(owner: abandoned!, at: point))
        abandoned = nil
        XCTAssertTrue(view.beginPhysicalPress(owner: foreign, at: point))
        view.endPhysicalPress(owner: foreign, at: point)
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(window) {}
    }

    func testFactoryReentryCannotOverwriteOrCancelTheReplacementPhysicalPress() {
        let (window, _, view, point) = fixture()
        let first = NSObject(), replacement = NSObject()
        var oldCalls = 0, newCalls = 0
        view.configure(contextIdentifier: UUID()) {
            view.cancelPhysicalPress()
            view.configure(contextIdentifier: UUID()) { { newCalls += 1; return true } }
            XCTAssertTrue(view.beginPhysicalPress(owner: replacement, at: point))
            return { oldCalls += 1; return true }
        }
        XCTAssertFalse(view.beginPhysicalPress(owner: first, at: point))
        view.endPhysicalPress(owner: first, at: point)
        view.endPhysicalPress(owner: replacement, at: point)
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
        withExtendedLifetime(window) {}
    }

    func testActionReentryCanStartANewPressEvenWhenOldActionReturnsFalse() {
        let (window, _, view, point) = fixture()
        let first = NSObject(), replacement = NSObject()
        var oldCalls = 0, newCalls = 0
        view.configure(contextIdentifier: UUID()) {
            {
                oldCalls += 1
                view.configure(contextIdentifier: UUID()) { { newCalls += 1; return true } }
                XCTAssertTrue(view.beginPhysicalPress(owner: replacement, at: point))
                return false
            }
        }
        XCTAssertTrue(view.beginPhysicalPress(owner: first, at: point))
        view.endPhysicalPress(owner: first, at: point)
        view.endPhysicalPress(owner: replacement, at: point)
        XCTAssertEqual(oldCalls, 1)
        XCTAssertEqual(newCalls, 1)
        withExtendedLifetime(window) {}
    }

    func testAccessibilityFactoryHideShowCannotExecuteItsObsoleteAction() {
        let (window, _, view, _) = fixture()
        var calls = 0
        view.configure(contextIdentifier: UUID()) {
            view.isEnabled = false
            view.isEnabled = true
            return { calls += 1; return true }
        }
        XCTAssertFalse(view.accessibilityActivate())
        XCTAssertEqual(calls, 0)
        view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        XCTAssertTrue(view.accessibilityActivate())
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(window) {}
    }

    func testInvalidPointsDisabledDetachedAndTenPointBoundaryFailClosed() {
        let (window, scroll, view, point) = fixture()
        let owner = NSObject()
        var calls = 0
        view.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        let invalid = [CGPoint(x: CGFloat.nan, y: point.y), CGPoint(x: point.x, y: CGFloat.infinity),
                       CGPoint(x: CGFloat.greatestFiniteMagnitude, y: point.y), CGPoint(x: -1, y: -1)]
        for bad in invalid {
            XCTAssertFalse(view.beginPhysicalPress(owner: owner, at: bad))
            XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
            view.endPhysicalPress(owner: owner, at: bad)
        }
        XCTAssertEqual(calls, 0)
        for enabledProperty in 0..<2 {
            if enabledProperty == 0 { view.isEnabled = false }
            else { view.isUserInteractionEnabled = false }
            XCTAssertFalse(view.beginPhysicalPress(owner: owner, at: point))
            XCTAssertFalse(view.accessibilityActivate())
            view.isEnabled = true
            view.isUserInteractionEnabled = true
        }
        view.removeFromSuperview()
        XCTAssertFalse(view.beginPhysicalPress(owner: owner, at: point))
        XCTAssertFalse(view.accessibilityActivate())
        scroll.addSubview(view)
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        view.movePhysicalPress(owner: owner, at: CGPoint(x: point.x + 10, y: point.y))
        view.endPhysicalPress(owner: owner, at: CGPoint(x: point.x + 10, y: point.y))
        XCTAssertEqual(calls, 1, "Exactly ten points remains a tap")
        XCTAssertTrue(view.beginPhysicalPress(owner: owner, at: point))
        view.endPhysicalPress(owner: owner, at: CGPoint(x: point.x + 10.01, y: point.y))
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(window) {}
    }

    func testFreshAccessibilityGuardRejectsFactoryGeometryAndInteractionChanges() {
        for change in 0..<2 {
            let (window, _, view, _) = fixture()
            var calls = 0
            view.configure(contextIdentifier: UUID()) {
                if change == 0 { view.frame.origin.x += 1 }
                else { view.isUserInteractionEnabled = false }
                return { calls += 1; return true }
            }
            XCTAssertFalse(view.accessibilityActivate())
            XCTAssertEqual(calls, 0)
            withExtendedLifetime(window) {}
        }
    }
}

@MainActor
final class KeyboardShiftSlideTests: XCTestCase {
    @MainActor private final class Fixture {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let shift = KeyboardShiftTouchButton(frame: CGRect(x: 0, y: 150, width: 44, height: 44))
        let key = KeyboardVariantButton()
        let owner = NSObject()
        let mode = UUID()
        var taps = 0
        var inserted = [String]()
        var accepts = true
        var shiftPoint: CGPoint { CGPoint(x: 22, y: 172) }
        var keyPoint: CGPoint { CGPoint(x: 82, y: 122) }
        init() {
            window.isHidden = false
            window.addSubview(shift); window.addSubview(key)
            key.frame = CGRect(x: 60, y: 100, width: 44, height: 44)
            key.accessibilityIdentifier = "keyboard.typing.key.q"
            shift.configure(contextIdentifier: mode) { [unowned self] in
                { [unowned self] in guard self.accepts else { return false }; self.taps += 1; return true }
            }
            shift.configureSlide(context: mode) { [unowned self] in
                { [unowned self] text in guard self.accepts else { return false }; self.inserted.append(text); return true }
            }
        }
    }
    func testAbandonedPhysicalOwnerCannotLeaveShiftStuck() {
        let f = Fixture()
        defer { f.window.isHidden = true }
        var abandoned: NSObject? = NSObject()
        XCTAssertTrue(f.shift.beginSlide(owner: abandoned!, point: f.shiftPoint))
        abandoned = nil
        XCTAssertTrue(f.shift.beginSlide(owner: f.owner, point: f.shiftPoint))
        XCTAssertTrue(f.shift.endSlide(owner: f.owner, point: f.shiftPoint))
        XCTAssertEqual(f.taps, 1); XCTAssertTrue(f.inserted.isEmpty)
    }

    func testSlideCommitsOneSelectedCharacterOnlyOnReleaseAndClearsFeedback() {
        let f = Fixture()
        defer { f.window.isHidden = true }
        XCTAssertTrue(f.shift.beginSlide(owner: f.owner, point: f.shiftPoint))
        f.shift.moveSlide(owner: f.owner, point: f.keyPoint)
        XCTAssertTrue(f.key.pressFeedback.isPressed)
        XCTAssertTrue(f.inserted.isEmpty)
        XCTAssertTrue(f.shift.endSlide(owner: f.owner, point: f.keyPoint))
        XCTAssertEqual(f.inserted, ["q"]); XCTAssertEqual(f.taps, 0)
        XCTAssertFalse(f.key.pressFeedback.isPressed); XCTAssertFalse(f.shift.pressFeedback.isPressed)
        XCTAssertFalse(f.shift.endSlide(owner: f.owner, point: f.keyPoint))
    }
    func testStationaryLongTouchIsAnOrdinaryShiftTapAndNeverCapsLockShortcut() {
        let f = Fixture()
        defer { f.window.isHidden = true }
        XCTAssertTrue(f.shift.beginSlide(owner: f.owner, point: f.shiftPoint))
        XCTAssertTrue(f.shift.endSlide(owner: f.owner, point: f.shiftPoint))
        XCTAssertEqual(f.taps, 1); XCTAssertTrue(f.inserted.isEmpty)
    }
    func testSlideCancellationStaleDocumentContextGeometryAndOutsideReleaseDoNotType() {
        for reason in 0..<9 {
            let f = Fixture()
            defer { f.window.isHidden = true }
            XCTAssertTrue(f.shift.beginSlide(owner: f.owner, point: f.shiftPoint))
            f.shift.moveSlide(owner: f.owner, point: f.keyPoint)
            switch reason {
            case 0: f.shift.cancelSlide()
            case 1: f.accepts = false
            case 2: f.shift.configureSlide(context: UUID()) { { _ in true } }
            case 3: f.shift.frame.origin.x += 1
            case 4: f.window.bounds.size.width += 1
            case 5: f.shift.removeFromSuperview()
            case 6: f.shift.moveSlide(owner: f.owner, point: CGPoint(x: CGFloat.nan, y: 0))
            case 7: f.shift.moveSlide(owner: f.owner, point: CGPoint(x: 300, y: 400))
            default: f.shift.isEnabled = false
            }
            let release = reason == 7 ? CGPoint(x: 300, y: 400) : f.keyPoint
            XCTAssertFalse(f.shift.endSlide(owner: f.owner, point: release))
            XCTAssertTrue(f.inserted.isEmpty); XCTAssertEqual(f.taps, 0)
            XCTAssertFalse(f.key.pressFeedback.isPressed)
        }
    }
    func testForeignTouchNonCharacterTargetAndReturningToShiftCannotToggleOrInsert() {
        let f = Fixture(), other = NSObject()
        defer { f.window.isHidden = true }
        XCTAssertFalse(f.shift.beginSlide(owner: f.owner, point: CGPoint(x: -1, y: -1)))
        XCTAssertTrue(f.shift.beginSlide(owner: f.owner, point: f.shiftPoint))
        XCTAssertFalse(f.shift.beginSlide(owner: other, point: f.shiftPoint))
        f.shift.moveSlide(owner: other, point: f.keyPoint)
        XCTAssertFalse(f.shift.endSlide(owner: other, point: f.keyPoint))
        f.key.accessibilityIdentifier = "keyboard.return"
        f.shift.moveSlide(owner: f.owner, point: f.keyPoint)
        XCTAssertFalse(f.key.pressFeedback.isPressed)
        XCTAssertFalse(f.shift.endSlide(owner: f.owner, point: f.shiftPoint))
        XCTAssertEqual(f.taps, 0); XCTAssertTrue(f.inserted.isEmpty)
    }
}
#endif
