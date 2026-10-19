#if canImport(UIKit)
import UIKit

/// Captures a key's original actions once at touch/hover entry. The renderer
/// owns pixels/recognizers; this small state machine owns delayed actions.
@MainActor
final class KeyboardInspectableInteraction {
    struct Actions {
        let insert: () -> Bool
        let inspect: () -> Bool
    }
    typealias ActionFactory = () -> Actions?
    typealias TimerScheduler = (TimeInterval, @escaping () -> Void) -> Timer
    var activityChanged: ((Bool) -> Void)?
    private let scheduleTimer: TimerScheduler
    private var renderedContext: UUID?
    private var renderedItem: String?
    private var enabled = false
    private var factory: ActionFactory?
    private var trackingPress = false
    private var pressToken: UUID?
    private var pressActions: Actions?
    private var suppressInsert = false
    private var hoverToken: UUID?
    private var hoverInspect: (() -> Bool)?
    private var hoverTimer: Timer?

    init(scheduleTimer: TimerScheduler? = nil) {
        self.scheduleTimer = scheduleTimer ?? { interval, action in
            Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in action() }
        }
    }
    func configure(contextIdentifier: UUID, itemIdentifier: String, enabled: Bool,
                   actionFactory: @escaping ActionFactory) {
        if contextIdentifier != renderedContext || itemIdentifier != renderedItem || !enabled {
            clearPress(ending: false)
            endHover()
        }
        renderedContext = contextIdentifier
        renderedItem = itemIdentifier
        self.enabled = enabled
        factory = actionFactory
    }

    @discardableResult
    func beginPress() -> UUID? {
        guard enabled, !trackingPress, let factory else { return nil }
        endHover()
        trackingPress = true
        suppressInsert = false
        let token = UUID()
        pressToken = token
        let actions = factory()
        guard pressToken == token else { return nil }
        guard let actions else { clearPress(ending: false); return nil }
        pressActions = actions
        activityChanged?(true)
        return token
    }
    @discardableResult
    func endPress() -> Bool {
        let action: (() -> Bool)? = pressToken == nil || suppressInsert ? nil : pressActions?.insert
        clearPress(ending: true)
        return action?() ?? false
    }
    /// UIKit cancels the control's raw touch when its long press recognizes.
    /// Preserve only that original inspection action until the recognizer fires.
    func cancelPress(preserveInspection: Bool = false) {
        if preserveInspection, trackingPress, pressToken != nil { suppressInsert = true }
        else { clearPress(ending: true) }
    }
    @discardableResult
    func inspectHeldPress() -> Bool {
        guard pressToken != nil, let action = pressActions?.inspect else { return false }
        suppressInsert = true
        pressToken = nil
        pressActions = nil
        endHover()
        activityChanged?(false)
        // Clear the old action before reentrant inspection can change scope.
        // Keep the physical-down latch until its terminal event arrives.
        return action()
    }

    func beginHover() {
        guard enabled, !trackingPress, let factory else { return }
        endHover()
        let token = UUID()
        hoverToken = token
        let actions = factory()
        guard hoverToken == token else { return }
        guard let actions else { endHover(); return }
        hoverInspect = actions.inspect
        let timer = scheduleTimer(0.65) { [weak self] in self?.fireHover(token: token) }
        if hoverToken == token { hoverTimer = timer }
        else { timer.invalidate() }
    }
    func endHover() {
        hoverToken = nil
        hoverInspect = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
    private func fireHover(token: UUID) {
        guard hoverToken == token, let action = hoverInspect else { return }
        endHover()
        _ = action()
    }
    func cancelAll() { clearPress(ending: true); endHover() }
    @discardableResult func activateInsert() -> Bool { activate(inspecting: false) }
    @discardableResult func activateInspect() -> Bool { activate(inspecting: true) }
    private func activate(inspecting: Bool) -> Bool {
        cancelAll()
        guard let token = beginPress(), pressToken == token, let actions = pressActions else { return false }
        let action = inspecting ? actions.inspect : actions.insert
        clearPress(ending: true)
        return action()
    }
    private func clearPress(ending: Bool) {
        if ending { trackingPress = false }
        pressToken = nil
        pressActions = nil
        suppressInsert = true
        activityChanged?(false)
    }
    deinit { hoverTimer?.invalidate() }
}
#endif
