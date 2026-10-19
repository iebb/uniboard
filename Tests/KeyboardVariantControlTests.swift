#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardVariantControlTests: XCTestCase {
    func testPadModifierButtonTextUsesTheRequestedBottomCornerWithoutChangingActions() {
        let button = KeyboardTouchActionButton(frame: CGRect(x: 0, y: 0, width: 100, height: 52))
        button.setTitle("tab", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13)
        var calls = 0
        button.configure(contextIdentifier: UUID()) { { calls += 1; return true } }
        for position in [KeyboardKeyContentPosition.bottomLeft, .bottomRight] {
            button.contentPosition = position
            let rect = button.titleRect(forContentRect: button.bounds)
            XCTAssertEqual(rect.maxY, 46, accuracy: 0.01)
            if position == .bottomLeft { XCTAssertEqual(rect.minX, 8, accuracy: 0.01) }
            else { XCTAssertEqual(rect.maxX, 92, accuracy: 0.01) }
            XCTAssertTrue(button.accessibilityActivate())
        }
        XCTAssertEqual(calls, 2)
        let delete = RepeatingDeleteButton()
        delete.setTitle("delete", for: .normal)
        delete.setImage(nil, for: .normal)
        delete.contentPosition = .bottomRight
        let rect = delete.titleRect(forContentRect: button.bounds)
        XCTAssertEqual(rect.maxX, 92, accuracy: 0.01)
        XCTAssertEqual(rect.maxY, 46, accuracy: 0.01)
    }
    func testRemappedTapLongPressUpAndDownRouteToFourSeparateOutputs() {
        let state = KeyboardVariantInteraction()
        var events: [String] = []
        let owner = NSObject()
        state.configure(context: UUID(), key: "q", text: "w", variants: [], enabled: true) {
            .init(isCurrent: { true }, insert: { _ in XCTFail("Gesture routes cannot fall through to a normal character"); return false },
                options: ["q"], longPressOptions: ["h"], swipeUp: ["u"], swipeDown: ["d"],
                tap: { events.append("w"); return true },
                insertGesture: { value, gesture in events.append(gesture.rawValue + ":" + value); return true })
        }
        XCTAssertTrue(state.begin(owner: owner))
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertTrue(state.activateGesture(.longPress))
        XCTAssertTrue(state.activateGesture(.swipeUp))
        XCTAssertTrue(state.activateGesture(.swipeDown))
        XCTAssertFalse(state.activateGesture(.tap))
        XCTAssertFalse(state.activateGesture(.shiftedTap))
        XCTAssertEqual(events, ["w", "longPress:h", "swipeUp:u", "swipeDown:d"])
    }
    @MainActor private final class GestureClock {
        var jobs: [() -> Void] = []
        var intervals: [TimeInterval] = []
        func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> Timer {
            intervals.append(delay); jobs.append(action)
            return Timer(timeInterval: delay, repeats: false) { _ in }
        }
        func fire(_ index: Int, file: StaticString = #filePath, line: UInt = #line) {
            guard jobs.indices.contains(index) else {
                XCTFail("Missing scheduled gesture job at index \(index)", file: file, line: line)
                return
            }
            jobs[index]()
        }
    }
    @MainActor private final class Clock {
        var jobs: [() -> Void] = []
        var timers: [Timer] = []
        func schedule(_ delay: TimeInterval, _ action: @escaping () -> Void) -> Timer {
            XCTAssertEqual(delay, 0.4)
            let timer = Timer(timeInterval: delay, repeats: false) { _ in }
            jobs.append(action); timers.append(timer)
            return timer
        }
        func fire(_ index: Int = 0, file: StaticString = #filePath, line: UInt = #line) {
            guard jobs.indices.contains(index) else {
                XCTFail("Missing scheduled hold job at index \(index)", file: file, line: line)
                return
            }
            jobs[index]()
        }
    }
    @MainActor private final class Route {
        var context: KeyboardInputActionContext? = .init(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        var inserted: [String] = [], inspected: [String] = []
        var edits = 0, holds = 0, factories = 0
        func factory(rendered: UUID, inspect: Bool = true, edit: Bool = false, hold: Bool = false) -> KeyboardVariantActions? {
            factories += 1
            guard let current = context, current.modeIdentifier == rendered else { return nil }
            let accepts = { self.context == current }
            return .init(isCurrent: accepts, insert: { value in
                guard accepts() else { return false }; self.inserted.append(value); return true
            }, inspect: inspect ? { value in guard accepts() else { return false }; self.inspected.append(value); return true } : nil,
               edit: edit ? { guard accepts() else { return false }; self.edits += 1; return true } : nil,
               hold: hold ? { guard accepts() else { return false }; self.holds += 1; return true } : nil)
        }
    }
    private func setup(_ state: KeyboardVariantInteraction, route: Route, text: String = "a", variants: [String] = ["à", "á"],
                       enabled: Bool = true, inspect: Bool = true, edit: Bool = false, hold: Bool = false,
                       preserveCase: Bool = false) {
        let mode = route.context!.modeIdentifier
        state.configure(context: mode, key: "key", text: text, variants: variants, enabled: enabled,
            preservesPressAcrossTextChanges: preserveCase) { route.factory(rendered: mode, inspect: inspect, edit: edit, hold: hold) }
        state.show = { _, _, _ in true }
    }

    private func gestureSetup(_ state: KeyboardVariantInteraction, route: Route,
                              long: [String]? = nil, up: [String]? = ["A", "À", "Á"], down: [String]? = [],
                              tap: (() -> Bool)? = nil, repeatAction: (() -> Bool)? = nil) {
        let mode = route.context!.modeIdentifier
        state.configure(context: mode, key: "a", text: "a", variants: ["à"], enabled: true) {
            guard var actions = route.factory(rendered: mode, inspect: false) else { return nil }
            actions.longPressOptions = long; actions.swipeUp = up; actions.swipeDown = down
            actions.tap = tap; actions.repeatOnHold = repeatAction
            let isCurrent = actions.isCurrent
            actions.insertGesture = { text, _ in
                guard isCurrent() else { return false }
                route.inserted.append(text); return true
            }
            return actions
        }
        state.show = { _, _, _ in true }
    }

    func testVerticalFlickDefaultsToFirstThenHorizontallyChoosesBeforeOneRelease() {
        let clock = GestureClock(), route = Route(), owner = NSObject()
        let state = KeyboardVariantInteraction(schedule: clock.schedule)
        gestureSetup(state, route: route)
        XCTAssertTrue(state.begin(owner: owner))
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 1, y: -11))
        XCTAssertFalse(state.popupVisible)
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 2, y: -12))
        XCTAssertTrue(state.swipeSelecting)
        XCTAssertTrue(route.inserted.isEmpty)
        clock.fire(0) // A queued hold callback cannot retarget the active flick.
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 74, y: -18))
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 38, y: -18))
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["À"])
        XCTAssertFalse(state.end(owner: owner, inside: true))
    }

    func testVerticalContinuationAcrossPopupCellsKeepsPrimaryFlickChoice() {
        for direction: CGFloat in [-1, 1] {
            let state = KeyboardVariantInteraction(), route = Route(), owner = NSObject()
            gestureSetup(state, route: route, up: ["O", "Ò", "Ó", "Ô", "Ö", "Œ", "Õ", "Ø", "Ō"], down: ["£", "ˆ"])
            XCTAssertTrue(state.begin(owner: owner))
            state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 0, y: direction * 12))
            for y: CGFloat in [18, 28, 40, 60] {
                state.move(owner: owner, index: 8, movedBeforeHold: true, delta: CGPoint(x: 0, y: direction * y), directPopupIndex: direction < 0 ? 8 : 1)
            }
            XCTAssertTrue(state.end(owner: owner, inside: true))
            XCTAssertEqual(route.inserted, [direction < 0 ? "O" : "£"])
        }
    }

    func testEveryWrappedFlickCandidateCanBeSelectedAndOriginalTapRemainsLiteral() {
        let state = KeyboardVariantInteraction(), route = Route(), owner = NSObject()
        let values = (0..<16).map { "choice\($0)" }
        gestureSetup(state, route: route, long: ["custom"], up: values)
        state.begin(owner: owner)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["a"], "A custom hold must not replace a short tap")
        state.begin(owner: owner)
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 0, y: -20))
        state.move(owner: owner, index: 15, movedBeforeHold: true, delta: CGPoint(x: 20, y: -50), directPopupIndex: 15)
        state.move(owner: owner, index: 15, movedBeforeHold: true, delta: CGPoint(x: 0, y: -50), directPopupIndex: 15)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["a", "choice15"])
    }

    func testDisabledHoldAndDownFlickNeverOpenPopupOrRetargetNormalTap() {
        let clock = GestureClock(), route = Route(), owner = NSObject()
        let state = KeyboardVariantInteraction(schedule: clock.schedule)
        gestureSetup(state, route: route, long: [], up: [], down: [])
        state.begin(owner: owner)
        XCTAssertTrue(clock.jobs.isEmpty)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["a"])
        state.begin(owner: owner)
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 0, y: 28))
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertFalse(state.popupVisible)
        XCTAssertEqual(route.inserted, ["a"])
    }

    func testCustomHoldPreservesCanonicalDistinctUnicodeAndOnlyInsertsSelectedRelease() {
        let clock = GestureClock(), route = Route(), owner = NSObject()
        let state = KeyboardVariantInteraction(schedule: clock.schedule)
        let nfd = "e\u{301}", emoji = "🙂\u{200D}↔\u{FE0F}"
        gestureSetup(state, route: route, long: ["é", nfd, emoji, "\0"])
        state.begin(owner: owner); clock.fire(0)
        state.move(owner: owner, index: 1, movedBeforeHold: false)
        XCTAssertTrue(route.inserted.isEmpty)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted.map { Array($0.utf16) }, [Array(nfd.utf16)])
        state.begin(owner: owner); clock.fire(1)
        state.move(owner: owner, index: 2, movedBeforeHold: false)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted.last?.unicodeScalars.map(\.value), emoji.unicodeScalars.map(\.value))
    }

    func testFunctionTapAndConfiguredFlickAreSeparateAndRepeatStopsOnRelease() {
        let clock = GestureClock(), route = Route(), owner = NSObject()
        let state = KeyboardVariantInteraction(schedule: clock.schedule)
        var taps = 0, deletes = 0
        gestureSetup(state, route: route, tap: { taps += 1; return true }, repeatAction: { deletes += 1; return true })
        state.begin(owner: owner)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(taps, 1); XCTAssertEqual(deletes, 0)
        state.begin(owner: owner); clock.fire(1)
        XCTAssertEqual(deletes, 1)
        XCTAssertEqual(clock.intervals.last, 0.085)
        clock.fire(2); clock.fire(2)
        XCTAssertEqual(deletes, 2, "A stale one-shot delivery cannot create duplicate repeat streams")
        XCTAssertTrue(state.end(owner: owner, inside: true))
        clock.fire(3)
        XCTAssertEqual(taps, 1); XCTAssertEqual(deletes, 2)
        state.begin(owner: owner)
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 0, y: -28))
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["A"])
        XCTAssertEqual(taps, 1); XCTAssertEqual(deletes, 2)
    }

    func testExplicitHoldOverrideDisablesRepeatAndMovementCancelsAnExistingRepeat() {
        let clock = GestureClock(), route = Route(), owner = NSObject()
        let state = KeyboardVariantInteraction(schedule: clock.schedule)
        var deletes = 0
        gestureSetup(state, route: route, long: ["literal"], repeatAction: { deletes += 1; return true })
        state.begin(owner: owner); clock.fire(0)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["literal"]); XCTAssertEqual(deletes, 0)
        gestureSetup(state, route: route, repeatAction: { deletes += 1; return true })
        state.begin(owner: owner); clock.fire(1)
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 20, y: 0))
        clock.fire(2)
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertEqual(deletes, 1)
    }

    func testFlickRejectsChangedDocumentModeGenerationInvalidGeometryAndForeignOwner() {
        for kind in 0..<5 {
            let route = Route(), state = KeyboardVariantInteraction(), owner = NSObject()
            gestureSetup(state, route: route)
            state.begin(owner: owner)
            state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 0, y: -28))
            let old = route.context!
            switch kind {
            case 0: route.context = .init(modeIdentifier: old.modeIdentifier, documentIdentifier: UUID(), interactionIdentifier: old.interactionIdentifier)
            case 1: route.context = .init(modeIdentifier: UUID(), documentIdentifier: old.documentIdentifier, interactionIdentifier: old.interactionIdentifier)
            case 2: route.context = .init(modeIdentifier: old.modeIdentifier, documentIdentifier: old.documentIdentifier, interactionIdentifier: UUID())
            case 3: state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: CGFloat.nan, y: -28))
            default:
                XCTAssertFalse(state.end(owner: NSObject(), inside: true))
                state.cancel()
            }
            XCTAssertFalse(state.end(owner: owner, inside: true))
            XCTAssertTrue(route.inserted.isEmpty)
        }
    }

    func testAccessibilityFlickUsesFreshContextAndDoesNotChangeTheDefaultTap() {
        let route = Route(), state = KeyboardVariantInteraction()
        let nfd = "e\u{301}"
        gestureSetup(state, route: route, long: [], up: [nfd])
        XCTAssertTrue(state.activate())
        XCTAssertTrue(state.activateGesture(.swipeUp))
        XCTAssertFalse(state.activateGesture(.longPress))
        XCTAssertFalse(state.activateGesture(.swipeDown))
        XCTAssertEqual(route.inserted.map { Array($0.utf16) }, ["a", nfd].map { Array($0.utf16) })
        route.context = nil
        XCTAssertFalse(state.activateGesture(.swipeUp))
        XCTAssertEqual(route.inserted.count, 2)
    }

    func testPopupCleanupCannotCompleteOldFlickAfterAReplacementPressEndsReentrantly() {
        let route = Route(), state = KeyboardVariantInteraction(), owner = NSObject(), replacement = NSObject()
        gestureSetup(state, route: route)
        state.begin(owner: owner)
        state.move(owner: owner, index: nil, movedBeforeHold: true, delta: CGPoint(x: 0, y: -28))
        state.hide = {
            XCTAssertTrue(state.begin(owner: replacement))
            XCTAssertTrue(state.end(owner: replacement, inside: true))
        }
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["a"], "Only the replacement's deliberate tap may execute")
    }

    func testConfiguredDeleteRepeatCannotContinueAfterItsTouchOwnerDisappears() {
        let route = Route(), clock = GestureClock(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        var owner: NSObject? = NSObject(), deletes = 0
        gestureSetup(state, route: route, repeatAction: { deletes += 1; return true })
        state.begin(owner: owner!); clock.fire(0)
        XCTAssertEqual(deletes, 1)
        owner = nil
        clock.fire(1)
        XCTAssertEqual(deletes, 1)
        XCTAssertNil(state.token)
        XCTAssertEqual(clock.jobs.count, 2)
        state.cancel()
    }

    func testShortTapInsertsOriginalExactlyOnceWithoutWaitingForHold() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route)
        XCTAssertTrue(state.begin(owner: owner))
        XCTAssertTrue(route.inserted.isEmpty)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertFalse(state.end(owner: owner, inside: true))
        clock.fire()
        XCTAssertEqual(route.inserted, ["a"])
        XCTAssertTrue(route.inspected.isEmpty)
        XCTAssertFalse(state.popupVisible)
    }

    func testHoldSlidesToWholeVariantAndInsertsOnlyAtSelectedRelease() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let emoji = "👩🏽\u{200D}💻"
        setup(state, route: route, variants: [emoji])
        state.begin(owner: owner); clock.fire()
        XCTAssertTrue(state.popupVisible)
        XCTAssertTrue(route.inserted.isEmpty)
        state.move(owner: owner, index: 1, movedBeforeHold: true)
        XCTAssertTrue(route.inserted.isEmpty)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted.map { Array($0.utf16) }, [Array(emoji.utf16)])
    }

    func testInspectAndEditNeverInsertAndInspectUsesLastHighlightedVariant() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route, edit: true)
        state.begin(owner: owner); clock.fire()
        state.move(owner: owner, index: 2, movedBeforeHold: true)
        state.move(owner: owner, index: 3, movedBeforeHold: true)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inspected, ["á"])
        XCTAssertTrue(route.inserted.isEmpty)
        state.begin(owner: owner); clock.fire(1)
        state.move(owner: owner, index: 4, movedBeforeHold: true)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.edits, 1)
        XCTAssertTrue(route.inserted.isEmpty)
    }

    func testHoldWithoutVariantsStillProvidesInspectAndManagerHoldDoesNotTap() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route, variants: [])
        state.begin(owner: owner); clock.fire()
        state.move(owner: owner, index: 1, movedBeforeHold: true)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inspected, ["a"])
        setup(state, route: route, variants: [], inspect: false, hold: true)
        state.begin(owner: owner); clock.fire(1)
        XCTAssertEqual(route.holds, 1)
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertTrue(route.inserted.isEmpty)
    }

    func testOutsideReleaseCancelledTouchAndPreholdScrollDoNotInsert() {
        for kind in 0..<3 {
            let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
            setup(state, route: route)
            state.begin(owner: owner)
            switch kind {
            case 0: clock.fire(); state.move(owner: owner, index: nil, movedBeforeHold: false)
            case 1: state.cancel()
            default: state.move(owner: owner, index: 1, movedBeforeHold: true); clock.fire()
            }
            XCTAssertFalse(state.end(owner: owner, inside: kind != 0))
            XCTAssertTrue(route.inserted.isEmpty)
            XCTAssertTrue(route.inspected.isEmpty)
        }
    }

    func testModeDocumentResizeAndMissingIdentityRejectBeforeHoldOrRelease() {
        for atHold in [false, true] {
            for kind in 0..<4 {
                let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
                setup(state, route: route)
                state.begin(owner: owner)
                if !atHold { clock.fire() }
                let old = route.context!
                switch kind {
                case 0: route.context = .init(modeIdentifier: UUID(), documentIdentifier: old.documentIdentifier, interactionIdentifier: old.interactionIdentifier)
                case 1: route.context = .init(modeIdentifier: old.modeIdentifier, documentIdentifier: UUID(), interactionIdentifier: old.interactionIdentifier)
                case 2: route.context = .init(modeIdentifier: old.modeIdentifier, documentIdentifier: old.documentIdentifier, interactionIdentifier: UUID())
                default: route.context = nil
                }
                if atHold { clock.fire() }
                XCTAssertFalse(state.end(owner: owner, inside: true))
                XCTAssertTrue(route.inserted.isEmpty)
                XCTAssertTrue(route.inspected.isEmpty)
            }
        }
    }

    func testConfigureChangeCannotReviveOldPressAfterReturningToOriginalKey() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route)
        state.begin(owner: owner)
        setup(state, route: route, text: "b")
        setup(state, route: route)
        XCTAssertFalse(state.begin(owner: owner))
        clock.fire()
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertTrue(route.inserted.isEmpty)
        XCTAssertTrue(state.begin(owner: owner))
        XCTAssertTrue(state.end(owner: owner, inside: true))
    }

    func testCanonicalEquivalentReconfigurationCancelsRatherThanRetargeting() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route, text: "é", variants: [])
        state.begin(owner: owner)
        setup(state, route: route, text: "e\u{301}", variants: [])
        clock.fire()
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertTrue(route.inserted.isEmpty)
    }

    func testCaseRefreshPreservesCapturedWholePressAndCurrentFactoryCanOverrideStaleLabel() {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route, text: "A", variants: ["À"], inspect: false, preserveCase: true)
        state.begin(owner: owner)
        setup(state, route: route, text: "a", variants: ["à"], inspect: false, preserveCase: true)
        clock.fire()
        state.move(owner: owner, index: 1, movedBeforeHold: true)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["À"])
        let mode = route.context!.modeIdentifier
        state.configure(context: mode, key: "key", text: "a", variants: ["à"], enabled: true) {
            var actions = route.factory(rendered: mode, inspect: false)!
            actions.options = ["A", "À"]
            return actions
        }
        state.begin(owner: owner)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["À", "A"])
    }

    func testForeignOwnerCannotMoveOrReleasePrimaryPress() {
        let clock = Clock(), route = Route(), primary = NSObject(), foreign = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        setup(state, route: route)
        state.begin(owner: primary); clock.fire()
        XCTAssertFalse(state.begin(owner: foreign))
        state.move(owner: foreign, index: 2, movedBeforeHold: true)
        XCTAssertFalse(state.end(owner: foreign, inside: true))
        XCTAssertTrue(state.end(owner: primary, inside: true))
        XCTAssertEqual(route.inserted, ["a"])
    }

    func testOldTimerAndFactoryReturnCannotReplaceAReentrantNewPress() {
        let clock = Clock(), route = Route(), owner = NSObject(), replacement = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let mode = route.context!.modeIdentifier
        state.configure(context: mode, key: "key", text: "a", variants: ["à"], enabled: true) {
            state.cancel()
            self.setup(state, route: route, text: "b", variants: ["β"])
            state.begin(owner: replacement)
            return route.factory(rendered: mode)
        }
        XCTAssertFalse(state.begin(owner: owner))
        XCTAssertTrue(state.end(owner: replacement, inside: true))
        clock.fire()
        XCTAssertEqual(route.inserted, ["b"])
    }

    func testClearedOwnershipBeforeInsertAllowsReentrantReplacementToSurvive() {
        let clock = Clock(), owner = NSObject(), replacement = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let route = Route(), mode = route.context!.modeIdentifier
        var values: [String] = []
        state.configure(context: mode, key: "key", text: "a", variants: [], enabled: true) {
            .init(isCurrent: { true }, insert: { text in
                values.append(text)
                self.setup(state, route: route, text: "b", variants: [])
                state.begin(owner: replacement)
                return false
            })
        }
        state.begin(owner: owner)
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertTrue(state.end(owner: replacement, inside: true))
        XCTAssertEqual(values, ["a"])
        XCTAssertEqual(route.inserted, ["b"])
    }

    func testCurrentContextCallbackCannotStartAReplacementThenAuthorizeTheOldRelease() {
        let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let owner = NSObject(), replacement = NSObject(), route = Route(), mode = UUID()
        var checkingTerminal = false, inserted = 0
        state.configure(context: mode, key: "key", text: "a", variants: [], enabled: true) {
            .init(isCurrent: {
                if checkingTerminal {
                    self.setup(state, route: route, text: "b", variants: [])
                    state.begin(owner: replacement)
                }
                return true
            }, insert: { _ in inserted += 1; return true })
        }
        state.begin(owner: owner)
        checkingTerminal = true
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertEqual(inserted, 0)
        XCTAssertTrue(state.end(owner: replacement, inside: true))
        XCTAssertEqual(route.inserted, ["b"])
    }

    func testUnavailableFactoryPoisonsPhysicalPressUntilItsRealEndWithoutScheduling() {
        for missing in [true, false] {
            let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule), owner = NSObject()
            let mode = UUID()
            state.configure(context: mode, key: "key", text: "a", variants: ["à"], enabled: true) {
                missing ? nil : .init(isCurrent: { false }, insert: { _ in XCTFail("Unavailable route must not insert"); return true })
            }
            XCTAssertFalse(state.begin(owner: owner))
            XCTAssertFalse(state.begin(owner: owner))
            XCTAssertTrue(clock.jobs.isEmpty)
            XCTAssertFalse(state.end(owner: owner, inside: true))
        }
    }

    func testAccessibilityFactoryReentryPreservesReplacementWithoutExecutingOldAction() {
        let clock = Clock(), state = KeyboardVariantInteraction(schedule: clock.schedule), route = Route(), owner = NSObject()
        let mode = route.context!.modeIdentifier
        var oldCalls = 0
        state.configure(context: mode, key: "key", text: "a", variants: [], enabled: true) {
            state.cancel()
            self.setup(state, route: route, text: "b", variants: [])
            state.begin(owner: owner)
            return .init(isCurrent: { true }, insert: { _ in oldCalls += 1; return true })
        }
        XCTAssertFalse(state.activate())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertTrue(state.end(owner: owner, inside: true))
        XCTAssertEqual(route.inserted, ["b"])
    }

    func testAccessibilityUsesFreshGuardAndExactChoicesWithNoSyntheticTouch() {
        let state = KeyboardVariantInteraction(), route = Route()
        setup(state, route: route, variants: ["e\u{301}"], edit: true, hold: true)
        XCTAssertTrue(state.activate(text: "e\u{301}"))
        XCTAssertFalse(state.activate(text: "é"))
        XCTAssertTrue(state.activate(inspect: true))
        XCTAssertTrue(state.activateEdit())
        XCTAssertTrue(state.activateHold())
        route.context = nil
        XCTAssertFalse(state.activate())
        XCTAssertEqual(route.inserted.map { Array($0.utf16) }, [Array("e\u{301}".utf16)])
    }

    func testActualWindowDetachAdditionalFingerAndDisableCancelQueuedHolds() {
        for kind in 0..<3 {
            let clock = Clock(), route = Route(), owner = NSObject()
            let state = KeyboardVariantInteraction(schedule: clock.schedule)
            let button = KeyboardVariantButton(interaction: state)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
            let input = UIInputView(frame: window.bounds, inputViewStyle: .keyboard)
            window.addSubview(input); input.addSubview(button)
            button.frame = CGRect(x: 350, y: 4, width: 42, height: 42)
            let mode = route.context!.modeIdentifier
            button.configure(context: mode, key: "key", text: "a", variants: ["à"], enabled: true, font: .systemFont(ofSize: 23)) { route.factory(rendered: mode) }
            XCTAssertTrue(button.beginPhysicalPress(owner: owner, point: CGPoint(x: 20, y: 20)))
            XCTAssertTrue(button.isHighlighted)
            XCTAssertTrue(button.pressFeedback.isPressed)
            switch kind {
            case 0: button.removeFromSuperview()
            case 1: button.cancelForAdditionalTouch()
            default: button.configure(context: mode, key: "key", text: "a", variants: ["à"], enabled: false, font: .systemFont(ofSize: 23)) { route.factory(rendered: mode) }
            }
            clock.fire()
            XCTAssertFalse(button.isHighlighted)
            XCTAssertFalse(button.pressFeedback.isPressed)
            XCTAssertFalse(state.end(owner: owner, inside: true))
            XCTAssertTrue(route.inserted.isEmpty)
            XCTAssertNil(input.subviews.first { $0.accessibilityIdentifier == "keyboard.variants" })
        }
    }

    func testSecondaryHintRendersAbovePrimaryAndClearsWithoutChangingLiteralOrAccessibleChoices() throws {
        let button = KeyboardVariantButton()
        let route = Route(), mode = route.context!.modeIdentifier
        func configure(_ hint: String?, symbol: String? = nil) {
            button.configure(context: mode, key: "q", text: "q", variants: [], enabled: true,
                font: .systemFont(ofSize: 23), symbol: symbol, swipeDown: ["1"], secondaryText: hint,
                factory: { route.factory(rendered: mode) })
            button.frame = CGRect(x: 0, y: 0, width: 64, height: 52)
            button.setNeedsLayout(); button.layoutIfNeeded()
        }
        configure("1")
        let labels = button.subviews.compactMap { $0 as? UILabel }
        let primary = try XCTUnwrap(labels.first { $0.text == "q" })
        let hint = try XCTUnwrap(labels.first { $0.text == "1" })
        XCTAssertFalse(hint.isHidden)
        XCTAssertFalse(hint.isUserInteractionEnabled)
        XCTAssertFalse(hint.isAccessibilityElement)
        XCTAssertLessThanOrEqual(hint.frame.maxY, primary.frame.minY + 1)
        XCTAssertTrue(button.bounds.contains(hint.frame))
        XCTAssertTrue(button.bounds.contains(primary.frame))
        XCTAssertTrue(button.accessibilityCustomActions?.contains { $0.name.hasPrefix("Swipe down:") } == true)
        configure(nil)
        XCTAssertTrue(hint.isHidden)
        XCTAssertEqual(primary.frame, button.bounds.insetBy(dx: 3, dy: 2))
        configure("")
        XCTAssertTrue(hint.isHidden)
        configure("1", symbol: "star")
        XCTAssertTrue(hint.isHidden)
        XCTAssertTrue(primary.isHidden)
        configure("1")
        XCTAssertFalse(hint.isHidden)
        XCTAssertFalse(primary.isHidden)
    }

    func testActualPopupIsInsideInputViewAndRotationCancelsBeforeInsertion() throws {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let button = KeyboardVariantButton(interaction: state)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        let input = UIInputView(frame: window.bounds, inputViewStyle: .keyboard)
        window.addSubview(input); input.addSubview(button)
        button.frame = CGRect(x: 350, y: 0, width: 42, height: 42)
        let mode = route.context!.modeIdentifier
        button.configure(context: mode, key: "key", text: "a", variants: ["à", "á"], enabled: true, font: .systemFont(ofSize: 23)) { route.factory(rendered: mode) }
        XCTAssertTrue(button.beginPhysicalPress(owner: owner, point: CGPoint(x: 20, y: 20)))
        clock.fire()
        let popup = try XCTUnwrap(input.subviews.first { $0.accessibilityIdentifier == "keyboard.variants" })
        XCTAssertGreaterThanOrEqual(popup.frame.minX, input.bounds.minX)
        XCTAssertGreaterThanOrEqual(popup.frame.minY, input.bounds.minY)
        XCTAssertLessThanOrEqual(popup.frame.maxX, input.bounds.maxX)
        XCTAssertLessThanOrEqual(popup.frame.maxY, input.bounds.maxY)
        window.bounds.size = CGSize(width: 874, height: 220)
        button.setNeedsLayout(); button.layoutIfNeeded()
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertNil(popup.superview)
        XCTAssertTrue(route.inserted.isEmpty)
    }

    func testActualMiddlePopupLeavesEveryWrappedChoiceReachableAndVisibilityCleanupClearsPress() throws {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let button = KeyboardVariantButton(interaction: state)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 220))
        let input = UIInputView(frame: window.bounds, inputViewStyle: .keyboard)
        window.addSubview(input); input.addSubview(button)
        button.frame = CGRect(x: 140, y: 90, width: 42, height: 42)
        let mode = route.context!.modeIdentifier
        button.configure(context: mode, key: "key", text: "a", variants: (0..<11).map(String.init),
            enabled: true, font: .systemFont(ofSize: 23)) { route.factory(rendered: mode, edit: true) }
        XCTAssertTrue(button.beginPhysicalPress(owner: owner, point: CGPoint(x: 20, y: 20)))
        clock.fire()
        let popup = try XCTUnwrap(input.subviews.first { $0.accessibilityIdentifier == "keyboard.variants" })
        XCTAssertTrue(popup.frame.maxY <= button.frame.minY - 6 || popup.frame.minY >= button.frame.maxY + 6)
        XCTAssertEqual(popup.subviews.count, 14)
        for (index, label) in popup.subviews.enumerated() {
            let center = CGPoint(x: popup.frame.minX + label.frame.midX, y: popup.frame.minY + label.frame.midY)
            XCTAssertEqual(button.selectedIndex(at: center), index)
        }
        KeyboardVariantButton.cancelInteractions(in: input)
        XCTAssertFalse(button.isHighlighted)
        XCTAssertNil(popup.superview)
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertTrue(route.inserted.isEmpty)
    }

    func testNativeHoldArbitratesScrollingWithoutOwningInsertionAndControlChoicesHaveSpokenLabels() throws {
        let clock = Clock(), route = Route(), owner = NSObject(), state = KeyboardVariantInteraction(schedule: clock.schedule)
        let button = KeyboardVariantButton(interaction: state)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        let input = UIInputView(frame: window.bounds, inputViewStyle: .keyboard)
        window.addSubview(input); input.addSubview(button)
        button.frame = CGRect(x: 10, y: 100, width: 36, height: 36)
        let hold = try XCTUnwrap(button.gestureRecognizers?.compactMap { $0 as? UILongPressGestureRecognizer }.first)
        XCTAssertEqual(hold.minimumPressDuration, 0.4)
        XCTAssertEqual(hold.allowableMovement, 10)
        XCTAssertFalse(hold.cancelsTouchesInView)
        XCTAssertFalse(hold.delaysTouchesBegan)
        XCTAssertFalse(hold.delaysTouchesEnded)
        XCTAssertEqual(button.intrinsicContentSize.height, KeyboardTypingLayoutPolicy.regularKeyHeight)
        let mode = route.context!.modeIdentifier
        button.configure(context: mode, key: "key", text: "a", variants: ["\0", "\u{200D}"], enabled: true,
            font: .systemFont(ofSize: 23)) { route.factory(rendered: mode) }
        let names = button.accessibilityCustomActions?.map(\.name) ?? []
        XCTAssertTrue(names.contains { $0.contains("U+0000") })
        XCTAssertTrue(names.contains { $0.contains("U+200D") })
        XCTAssertTrue(button.beginPhysicalPress(owner: owner, point: CGPoint(x: 18, y: 18)))
        state.move(owner: owner, index: 1, movedBeforeHold: true)
        clock.fire()
        XCTAssertFalse(state.end(owner: owner, inside: true))
        XCTAssertTrue(route.inserted.isEmpty, "A pre-hold scroll cannot become a tap or a variant insert")
        button.configure(context: mode, key: "key", text: "a", variants: [], enabled: false,
            font: .systemFont(ofSize: 23)) { route.factory(rendered: mode) }
        XCTAssertFalse(hold.isEnabled)
        button.configure(context: mode, key: "key", text: "a", variants: [], enabled: true,
            font: .systemFont(ofSize: 23)) { route.factory(rendered: mode) }
        XCTAssertTrue(hold.isEnabled)
        XCTAssertTrue(button.window === window)
    }
}
#endif
