#if canImport(UIKit)
import UIKit

/// A press belongs to the scope shown when it began and to one host document.
/// A delayed representable update must not reroute it into a different scope.
struct KeyboardDeleteContext: Equatable {
    let modeIdentifier: UUID
    let isQuery: Bool
    let documentIdentifier: UUID

    func guardedAction(currentContext: @escaping () -> KeyboardDeleteContext?,
                       delete: @escaping () -> Void) -> () -> Bool {
        { guard currentContext() == self else { return false }; delete(); return true }
    }
}

final class RepeatingDeleteButton: UIButton {
    var contentPosition: KeyboardKeyContentPosition = .center { didSet { setNeedsLayout() } }
    override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
        contentPosition.alignedRect(super.titleRect(forContentRect: contentRect), in: contentRect)
    }
    typealias DeleteAction = () -> Bool
    typealias ActionFactory = () -> DeleteAction
    typealias TimerScheduler = (TimeInterval, Bool, @escaping (Timer) -> Void) -> Timer

    private let scheduleTimer: TimerScheduler
    private var isQuery: Bool?
    private var actionFactory: ActionFactory?
    private var pressAction: DeleteAction?
    private var pressToken: UUID?
    private var isTrackingPress = false
    private var delayTimer: Timer?
    private var repeatTimer: Timer?

    init(scheduleTimer: TimerScheduler? = nil) {
        self.scheduleTimer = scheduleTimer ?? { interval, repeats, action in
            Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats, block: action)
        }
        super.init(frame: .zero)
        setImage(UIImage(systemName: "delete.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 19)), for: .normal)
        tintColor = .label
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        accessibilityIdentifier = "keyboard.delete"
        accessibilityHint = "Hold to delete repeatedly"
        addTarget(self, action: #selector(startDeleting), for: .touchDown)
        addTarget(self, action: #selector(stopDeleting), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(isQuery: Bool, enabled: Bool = true, actionFactory: @escaping ActionFactory) {
        if self.isQuery != isQuery || !enabled { cancelRepeating(endingPress: false) }
        self.isQuery = isQuery
        self.actionFactory = actionFactory
        isEnabled = enabled
        isUserInteractionEnabled = enabled
        isAccessibilityElement = enabled
        accessibilityElementsHidden = !enabled
        isHidden = !enabled
        accessibilityLabel = isQuery ? "Delete search character" : "Delete backward"
    }

    private(set) lazy var pressFeedback = KeyboardTouchFeedback.attach(to: self)

    override func accessibilityActivate() -> Bool {
        stopDeleting()
        guard isEnabled, let actionFactory else { return false }
        let token = UUID()
        pressToken = token
        let action = actionFactory()
        // A factory can hide/reconfigure the control or start another press.
        // Only the still-enabled activation that requested it may invoke it.
        guard pressToken == token else { return false }
        pressToken = nil
        guard isEnabled else { return false }
        return action()
    }

    @objc private func startDeleting() {
        // Duplicate downs cannot create parallel repeat streams or restart a
        // held press after its action has been bound to a document.
        guard isEnabled, !isTrackingPress, let actionFactory else { return }
        isTrackingPress = true
        let token = UUID()
        pressToken = token
        let action = actionFactory()
        // A factory may synchronously end this press and start another one.
        // Never overwrite the action owned by that newer press.
        guard pressToken == token else { return }
        pressAction = action
        guard performDelete(token: token) else { return }
        pressFeedback.setPressed(true)
        delayTimer = scheduleTimer(0.4, false) { [weak self] _ in
            guard let self, self.pressToken == token else { return }
            self.delayTimer = nil
            guard self.performDelete(token: token) else { return }
            self.repeatTimer = self.scheduleTimer(0.085, true) { [weak self] _ in
                _ = self?.performDelete(token: token)
            }
        }
    }

    @discardableResult
    private func performDelete(token: UUID) -> Bool {
        guard pressToken == token, let pressAction else { return false }
        let accepted = pressAction()
        // A deletion can synchronously cancel this press or start a new one.
        // An old callback must not cancel the newer press when it returns.
        guard pressToken == token else { return false }
        guard accepted else { cancelRepeating(endingPress: false); return false }
        return true
    }

    @objc private func stopDeleting() {
        cancelRepeating(endingPress: true)
    }

    private func cancelRepeating(endingPress: Bool) {
        if endingPress { isTrackingPress = false }
        pressToken = nil
        pressAction = nil
        pressFeedback.setPressed(false)
        delayTimer?.invalidate()
        repeatTimer?.invalidate()
        delayTimer = nil
        repeatTimer = nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { stopDeleting() }
        super.willMove(toWindow: newWindow)
    }

    deinit { delayTimer?.invalidate(); repeatTimer?.invalidate() }
}
#endif
