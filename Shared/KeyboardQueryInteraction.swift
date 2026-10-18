#if canImport(UIKit)
import UIKit

/// One query touch may accept only the mode transition caused by its own first
/// activation. It never reactivates after ABC, resize or a document switch.
@MainActor
final class KeyboardQueryActionSession {
    private var acceptedContext: KeyboardInputActionContext
    private let currentContext: () -> KeyboardInputActionContext?
    private let activate: () -> UUID?
    private let moveCaret: (Int) -> Void
    private var activated = false
    var acceptedModeIdentifier: UUID { acceptedContext.modeIdentifier }

    init(context: KeyboardInputActionContext,
         currentContext: @escaping () -> KeyboardInputActionContext?,
         activate: @escaping () -> UUID?, moveCaret: @escaping (Int) -> Void) {
        acceptedContext = context
        self.currentContext = currentContext
        self.activate = activate
        self.moveCaret = moveCaret
    }
    func perform(caret: Int?, isCurrent: () -> Bool) -> Bool {
        guard isCurrent(), currentContext() == acceptedContext else { return false }
        if !activated {
            guard let ownMode = activate(), isCurrent(), let after = currentContext(),
                  after.modeIdentifier == ownMode,
                  after.documentIdentifier == acceptedContext.documentIdentifier,
                  after.interactionIdentifier == acceptedContext.interactionIdentifier else { return false }
            acceptedContext = after
            activated = true
        }
        guard isCurrent(), currentContext() == acceptedContext else { return false }
        if let caret { moveCaret(caret) }
        return isCurrent() && currentContext() == acceptedContext
    }
}

/// UIKit recognizers snapshot this state at their original touchesBegan. The
/// Core Text renderer receives a local commit only after the guarded action.
@MainActor
final class KeyboardQueryInteraction {
    typealias ActionFactory = () -> KeyboardQueryActionSession?
    private weak var touchOwner: AnyObject?
    private(set) var physicalToken: UUID?
    private var action: KeyboardQueryActionSession?
    private var originContext: UUID?
    private var renderedContext: UUID?
    private var enabled = false
    private var factory: ActionFactory?
    private var invokingToken: UUID?

    /// Returns true when the renderer should cancel its native recognizers.
    @discardableResult
    func configure(contextIdentifier: UUID, enabled: Bool, actionFactory: @escaping ActionFactory) -> Bool {
        renderedContext = contextIdentifier
        self.enabled = enabled
        factory = actionFactory
        guard enabled else { return cancelCurrentAction() }
        guard let action, let token = physicalToken, invokingToken != token else { return false }
        if contextIdentifier == action.acceptedModeIdentifier { originContext = contextIdentifier; return false }
        if contextIdentifier != originContext { return cancelCurrentAction() }
        return false
    }
    @discardableResult
    func beginPhysicalTouch(owner: AnyObject) -> UUID? {
        if let token = physicalToken, touchOwner === owner { return token }
        if physicalToken != nil, touchOwner == nil { cancelAll() }
        // A second touch cannot retarget a live action. After cancellation a
        // genuinely new physical touch may start; the old owner's token cannot.
        if physicalToken != nil, action != nil { return nil }
        guard enabled, let factory else { return nil }
        let token = UUID()
        physicalToken = token
        touchOwner = owner
        originContext = renderedContext
        let captured = factory()
        guard physicalToken == token, touchOwner === owner, enabled,
              renderedContext == originContext else { return nil }
        action = captured
        return token
    }
    @discardableResult
    func perform(caret: Int?, token: UUID, commitLocal: () -> Void) -> Bool {
        guard enabled, physicalToken == token, touchOwner != nil, let action,
              invokingToken == nil else { return false }
        invokingToken = token
        defer { if invokingToken == token { invokingToken = nil } }
        let accepted = action.perform(caret: caret) {
            self.enabled && self.physicalToken == token && self.touchOwner != nil && self.action === action
        }
        // A callback can synchronously cancel or create a replacement touch.
        guard physicalToken == token, self.action === action, enabled else { return false }
        guard accepted else { _ = cancelCurrentAction(); return false }
        let acceptedMode = action.acceptedModeIdentifier
        if renderedContext == acceptedMode { originContext = acceptedMode }
        else if renderedContext != originContext { _ = cancelCurrentAction(); return false }
        commitLocal()
        return true
    }
    @discardableResult
    func cancelCurrentAction() -> Bool {
        let hadAction = action != nil
        action = nil
        return hadAction
    }
    func endPhysicalTouch(token: UUID) {
        guard physicalToken == token else { return }
        physicalToken = nil
        touchOwner = nil
        action = nil
        originContext = nil
    }
    func cancelAll() {
        physicalToken = nil
        touchOwner = nil
        action = nil
        originContext = nil
    }
    @discardableResult
    func activateFresh(caret: Int?, commitLocal: () -> Void) -> Bool {
        cancelAll()
        let owner = NSObject()
        guard let token = beginPhysicalTouch(owner: owner) else { return false }
        let accepted = perform(caret: caret, token: token, commitLocal: commitLocal)
        endPhysicalTouch(token: token)
        return accepted
    }
}
#endif
