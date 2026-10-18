#if canImport(UIKit)
import UIKit
import XCTest
@testable import Uniboard

@MainActor
final class KeyboardQueryInteractionTests: XCTestCase {
    private final class Touch: NSObject {}
    @MainActor
    private final class Route {
        var context: KeyboardInputActionContext? = .init(modeIdentifier: UUID(), documentIdentifier: UUID(), interactionIdentifier: UUID())
        var resizing = false
        var query = "cat"
        var factories = 0
        var activations = 0
        var moves: [Int] = []
        var local: [Int?] = []
        var onActivate: (() -> Void)?
        func changeMode() {
            let old = context!
            context = .init(modeIdentifier: UUID(), documentIdentifier: old.documentIdentifier, interactionIdentifier: old.interactionIdentifier)
        }
        func changeGeneration() {
            let old = context!
            context = .init(modeIdentifier: old.modeIdentifier, documentIdentifier: old.documentIdentifier, interactionIdentifier: UUID())
        }
        func action(rendered: UUID, renderedQuery: String) -> KeyboardQueryActionSession? {
            factories += 1
            guard let initial = context, initial.modeIdentifier == rendered, !resizing,
                  query.utf16.elementsEqual(renderedQuery.utf16) else { return nil }
            let codeUnits = Array(renderedQuery.utf16)
            return KeyboardQueryActionSession(context: initial, currentContext: {
                self.resizing || !self.query.utf16.elementsEqual(codeUnits) ? nil : self.context
            }, activate: {
                self.activations += 1
                self.changeMode()
                let ownedMode = self.context!.modeIdentifier
                self.onActivate?()
                return ownedMode
            }, moveCaret: { self.moves.append($0) })
        }
    }
    private func configure(_ interaction: KeyboardQueryInteraction, route: Route, enabled: Bool = true) {
        let mode = route.context!.modeIdentifier, query = route.query
        interaction.configure(contextIdentifier: mode, enabled: enabled) { route.action(rendered: mode, renderedQuery: query) }
    }
    @discardableResult
    private func perform(_ state: KeyboardQueryInteraction, route: Route, token: UUID, caret: Int? = 1) -> Bool {
        state.perform(caret: caret, token: token) { route.local.append(caret) }
    }

    func testOriginalPhysicalSnapshotActivatesOnceAndAllowsLongPanAcrossItsOwnModeChange() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertTrue(perform(state, route: route, token: token, caret: 0))
        configure(state, route: route) // Own activation's final mode renders.
        for index in 0..<100 { XCTAssertTrue(perform(state, route: route, token: token, caret: index % 4)) }
        XCTAssertEqual(route.factories, 1)
        XCTAssertEqual(route.activations, 1)
        XCTAssertEqual(route.moves.count, 101)
        XCTAssertEqual(route.local.count, 101)
    }
    func testTapActivationWithNoCaretDoesNotInventAMove() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertTrue(perform(state, route: route, token: token, caret: nil))
        state.endPhysicalTouch(token: token)
        XCTAssertEqual(route.activations, 1)
        XCTAssertTrue(route.moves.isEmpty)
        XCTAssertEqual(route.local.count, 1)
    }
    func testResizeBeginAndEndCannotReviveAStillHeldQueryTouchBeforeConfigure() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        route.resizing = true; route.changeGeneration()
        XCTAssertFalse(perform(state, route: route, token: token))
        route.resizing = false; route.changeGeneration()
        XCTAssertEqual(state.beginPhysicalTouch(owner: touch), token)
        XCTAssertFalse(perform(state, route: route, token: token))
        XCTAssertEqual(route.factories, 1)
        XCTAssertTrue(route.moves.isEmpty)
        XCTAssertTrue(route.local.isEmpty)
    }
    func testABCAndBackCannotReopenSearchOrMoveNativeCaret() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertTrue(perform(state, route: route, token: token))
        route.changeMode(); route.changeMode()
        XCTAssertFalse(perform(state, route: route, token: token, caret: 2))
        XCTAssertEqual(route.activations, 1)
        XCTAssertEqual(route.moves, [1])
        XCTAssertEqual(route.local.count, 1)
    }
    func testDocumentSwitchAndMissingIdentityRejectBeforeAnyActivationOrLocalMove() throws {
        for missing in [false, true] {
            let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
            configure(state, route: route)
            let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch)), old = route.context!
            route.context = missing ? nil : .init(modeIdentifier: old.modeIdentifier, documentIdentifier: UUID(), interactionIdentifier: old.interactionIdentifier)
            XCTAssertFalse(perform(state, route: route, token: token))
            XCTAssertEqual(route.activations, 0)
            XCTAssertTrue(route.moves.isEmpty)
            XCTAssertTrue(route.local.isEmpty)
        }
    }
    func testOwnActivationRechecksDocumentAndResizeGenerationBeforeCaretMutation() throws {
        for kind in 0..<3 {
            let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
            configure(state, route: route)
            route.onActivate = {
                if kind == 0 { route.context = nil }
                else if kind == 1 { route.changeGeneration() }
                else { route.changeMode() }
            }
            let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
            XCTAssertFalse(perform(state, route: route, token: token))
            XCTAssertTrue(route.moves.isEmpty)
            XCTAssertTrue(route.local.isEmpty)
        }
    }
    func testOwnSynchronousReconfigureIsPreservedButExternalReconfigureCancels() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        route.onActivate = { self.configure(state, route: route) }
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertTrue(perform(state, route: route, token: token))
        XCTAssertTrue(perform(state, route: route, token: token, caret: 2))
        route.changeMode(); configure(state, route: route)
        XCTAssertFalse(perform(state, route: route, token: token, caret: 0))
        XCTAssertEqual(route.moves, [1, 2])
    }
    func testDelayedOwnRenderDoesNotLoseAValidGestureOrRetargetItsFactory() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertTrue(perform(state, route: route, token: token))
        XCTAssertTrue(perform(state, route: route, token: token, caret: 2))
        configure(state, route: route)
        XCTAssertTrue(perform(state, route: route, token: token, caret: 3))
        XCTAssertEqual(route.factories, 1)
        XCTAssertEqual(route.activations, 1)
    }
    func testDisabledConfigureAndDetachDiscardQueuedOldCallbacks() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertTrue(state.configure(contextIdentifier: route.context!.modeIdentifier, enabled: false) { nil })
        XCTAssertFalse(perform(state, route: route, token: token))
        state.cancelAll()
        configure(state, route: route)
        XCTAssertFalse(perform(state, route: route, token: token))
        XCTAssertTrue(route.local.isEmpty)
    }
    func testQueryUTF16ChangeRejectsStaleGeometryEvenWithoutAModeChange() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        route.query = "e\u{301}"
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        route.query = "\u{E9}" // String equality would hide different UTF-16 geometry.
        XCTAssertFalse(perform(state, route: route, token: token))
        XCTAssertTrue(route.moves.isEmpty)
        XCTAssertTrue(route.local.isEmpty)
    }
    func testNoFactoryAndStaleRenderedQueryCannotActivateOrMove() {
        let state = KeyboardQueryInteraction(), touch = Touch()
        state.configure(contextIdentifier: UUID(), enabled: true) { nil }
        let token = state.beginPhysicalTouch(owner: touch)!
        var committed = false
        XCTAssertFalse(state.perform(caret: 1, token: token) { committed = true })
        XCTAssertFalse(committed)
        let route = Route(), stale = route.context!.modeIdentifier
        route.query = "changed"
        XCTAssertNil(route.action(rendered: stale, renderedQuery: "old"))
    }
    func testAccessibilityUsesFreshFactoryAndDoesNotAnnounceOrCommitRejectedActions() {
        let route = Route(), state = KeyboardQueryInteraction()
        configure(state, route: route)
        XCTAssertTrue(state.activateFresh(caret: 0) { route.local.append(0) })
        configure(state, route: route)
        XCTAssertTrue(state.activateFresh(caret: 3) { route.local.append(3) })
        route.resizing = true
        XCTAssertFalse(state.activateFresh(caret: 1) { route.local.append(1) })
        XCTAssertEqual(route.moves, [0, 3])
        XCTAssertEqual(route.local.count, 2)
        XCTAssertEqual(route.factories, 3)
    }
    func testDuplicateRecognizerDownAndForeignTouchCannotRetargetLiveAction() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch(), second = Touch()
        configure(state, route: route)
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch))
        XCTAssertEqual(state.beginPhysicalTouch(owner: touch), token)
        XCTAssertNil(state.beginPhysicalTouch(owner: second))
        XCTAssertEqual(route.factories, 1)
        XCTAssertTrue(perform(state, route: route, token: token))
    }
    func testOldDeferredTerminalCannotEndAFreshPhysicalTouch() throws {
        let route = Route(), state = KeyboardQueryInteraction(), old = Touch(), fresh = Touch()
        configure(state, route: route)
        let oldToken = try XCTUnwrap(state.beginPhysicalTouch(owner: old))
        _ = state.cancelCurrentAction()
        let freshToken = try XCTUnwrap(state.beginPhysicalTouch(owner: fresh))
        state.endPhysicalTouch(token: oldToken)
        XCTAssertTrue(perform(state, route: route, token: freshToken))
    }
    func testReentrantFactoryCannotOverwriteAReplacementPhysicalTouch() throws {
        let route = Route(), state = KeyboardQueryInteraction(), old = Touch(), replacement = Touch()
        let mode = route.context!.modeIdentifier
        state.configure(contextIdentifier: mode, enabled: true) {
            state.cancelAll(); self.configure(state, route: route)
            _ = state.beginPhysicalTouch(owner: replacement)
            return route.action(rendered: mode, renderedQuery: route.query)
        }
        XCTAssertNil(state.beginPhysicalTouch(owner: old))
        let token = try XCTUnwrap(state.physicalToken)
        XCTAssertTrue(perform(state, route: route, token: token))
        XCTAssertEqual(route.activations, 1)
    }
    func testContextChangeDuringFactoryCannotBindTheReturnedOldAction() throws {
        let route = Route(), state = KeyboardQueryInteraction(), touch = Touch()
        let mode = route.context!.modeIdentifier
        state.configure(contextIdentifier: mode, enabled: true) {
            let action = route.action(rendered: mode, renderedQuery: route.query)
            route.changeMode(); self.configure(state, route: route)
            return action
        }
        XCTAssertNil(state.beginPhysicalTouch(owner: touch))
        if let token = state.physicalToken { XCTAssertFalse(perform(state, route: route, token: token)) }
        XCTAssertTrue(route.local.isEmpty)
    }
    func testOldActionReturnCannotCancelAReentrantReplacement() throws {
        let route = Route(), state = KeyboardQueryInteraction(), old = Touch(), replacement = Touch()
        configure(state, route: route)
        let oldToken = try XCTUnwrap(state.beginPhysicalTouch(owner: old))
        route.onActivate = {
            state.cancelAll(); self.configure(state, route: route)
            _ = state.beginPhysicalTouch(owner: replacement)
        }
        XCTAssertFalse(perform(state, route: route, token: oldToken))
        XCTAssertTrue(route.moves.isEmpty, "Cancellation inside activation must reject the old model move too")
        route.onActivate = nil
        let newToken = try XCTUnwrap(state.physicalToken)
        XCTAssertTrue(perform(state, route: route, token: newToken))
        XCTAssertEqual(route.local.count, 1)
    }
    func testTouchOwnerIsWeakAndAQueuedCallbackAfterItsReleaseCannotMoveCaret() throws {
        let route = Route(), state = KeyboardQueryInteraction()
        configure(state, route: route)
        var touch: Touch? = Touch()
        weak var weakTouch: Touch?
        weakTouch = touch
        let token = try XCTUnwrap(state.beginPhysicalTouch(owner: touch!))
        touch = nil
        XCTAssertNil(weakTouch)
        XCTAssertFalse(perform(state, route: route, token: token))
        let replacement = Touch(), next = try XCTUnwrap(state.beginPhysicalTouch(owner: replacement))
        XCTAssertTrue(perform(state, route: route, token: next))
        XCTAssertEqual(route.local.count, 1)
    }
}
#endif
