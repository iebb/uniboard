#if canImport(UIKit)
import UIKit

/// A Unicode search character key. A tap still commits the query edit on
/// touch-up through the base button. Holding it for the keyboard's hold
/// threshold, without moving more than the allowed distance, types the key's
/// character into the host once and withdraws that tap, so the release adds
/// nothing. The host action is captured at touch-down, like every key.
final class KeyboardQueryHoldButton: KeyboardTouchActionButton {
    typealias HoldAction = () -> Bool
    typealias HoldFactory = () -> HoldAction?
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Timer

    /// The hold overlay's tint; the keyboard passes its accent color.
    var heldAccent: UIColor = .systemBlue
    var announce: (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }
    /// The catalog name of an invisible character, for its announcement.
    var spokenName: (String) -> String? = { _ in nil }
    private let schedule: Scheduler
    private var key: String?
    private var holdFactory: HoldFactory?
    private var press: KeyboardQueryHoldPolicy.Press?
    private var holdAction: HoldAction?
    private var holdToken: UUID?
    private var timer: Timer?
    private var origin: CGPoint?

    init(schedule: @escaping Scheduler = { interval, action in
        let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }) {
        self.schedule = schedule
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { timer?.invalidate() }

    /// `key` is the query key's character; keys without a hold get none.
    func configureHold(key: String, factory: @escaping HoldFactory) {
        holdFactory = factory
        guard self.key != key else { return }
        clearHold()
        self.key = key
        accessibilityCustomActions = KeyboardQueryHoldPolicy.hostText(forKey: key) == nil ? nil : [
            UIAccessibilityCustomAction(name: KeyboardQueryHoldPolicy.accessibilityActionName) { [weak self] _ in
                self?.accessibilityTypeInText() ?? false
            }
        ]
    }

    var isHolding: Bool { press?.phase == .held }

    override func pressDidBegin() {
        clearHold()
        guard let key, let holdFactory, let started = KeyboardQueryHoldPolicy.Press(key: key) else { return }
        let token = UUID()
        holdToken = token
        let action = holdFactory()
        guard holdToken == token, let action else { return }
        holdAction = action
        press = started
        timer = schedule(KeyboardQueryHoldPolicy.holdThreshold) { [weak self] in self?.holdThresholdReached(token: token) }
    }

    override func pressDidEnd() { clearHold() }

    /// The press moved `distance` points from where it went down.
    func pressMoved(distance: CGFloat) {
        guard var current = press else { return }
        current.moved(distance: distance)
        press = current
        if current.phase == .tapOnly { timer?.invalidate(); timer = nil }
    }

    func holdThresholdReached(token: UUID) {
        guard holdToken == token, var current = press, let action = holdAction else { return }
        timer?.invalidate(); timer = nil
        guard case .insertIntoHost(let text) = current.thresholdReached() else { return }
        press = current
        // No query character on release, whether or not the host accepts.
        withdrawPendingAction()
        guard action(), holdToken == token else { return }
        pressFeedback.setHeld(accent: heldAccent)
        announce(KeyboardQueryHoldPolicy.typedAnnouncement(text, name: spokenName))
    }

    /// VoiceOver's equivalent of the hold: the same captured host insert.
    func accessibilityTypeInText() -> Bool {
        guard let key, let text = KeyboardQueryHoldPolicy.hostText(forKey: key),
              let action = holdFactory?(), action() else { return false }
        announce(KeyboardQueryHoldPolicy.typedAnnouncement(text, name: spokenName))
        return true
    }

    private func clearHold() {
        timer?.invalidate()
        timer = nil
        holdToken = nil
        holdAction = nil
        press = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        origin = touches.first?.location(in: self)
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let origin, let point = touches.first?.location(in: self) {
            pressMoved(distance: hypot(point.x - origin.x, point.y - origin.y))
        }
        super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        origin = nil
        super.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        origin = nil
        super.touchesCancelled(touches, with: event)
    }
}
#endif
