#if canImport(UIKit)
import UIKit

/// A rendered host key can only act in its original panel, document and resize
/// generation. Missing or stale current context fails before any host mutation.
struct KeyboardInputActionContext: Equatable {
    let modeIdentifier: UUID
    let documentIdentifier: UUID
    let interactionIdentifier: UUID

    func guardedAction(currentContext: @escaping () -> KeyboardInputActionContext?,
                       perform: @escaping () -> Bool) -> () -> Bool {
        { guard currentContext() == self else { return false }; return perform() }
    }
}

/// Single actions snapshot one factory at touch-down; updates never retarget a
/// held press. Unlike repeated Delete, these keys execute only on touch-up.
final class KeyboardTouchActionButton: UIButton {
    var contentPosition: KeyboardKeyContentPosition = .center { didSet { setNeedsLayout() } }
    override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
        contentPosition.alignedRect(super.titleRect(forContentRect: contentRect), in: contentRect)
    }
    override func imageRect(forContentRect contentRect: CGRect) -> CGRect {
        contentPosition.alignedRect(super.imageRect(forContentRect: contentRect), in: contentRect)
    }
    typealias Action = () -> Bool
    typealias ActionFactory = () -> Action
    private var contextIdentifier: UUID?
    private var actionFactory: ActionFactory?
    private var pressAction: Action?
    private var pressToken: UUID?
    private var trackingPress = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.02)
        isExclusiveTouch = false
        addTarget(self, action: #selector(startPress), for: .touchDown)
        addTarget(self, action: #selector(finishPress), for: .touchUpInside)
        addTarget(self, action: #selector(endPress), for: [.touchCancel, .touchUpOutside, .touchDragExit])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(contextIdentifier: UUID, actionFactory: @escaping ActionFactory) {
        if self.contextIdentifier != contextIdentifier { cancelPress(ending: false) }
        self.contextIdentifier = contextIdentifier
        self.actionFactory = actionFactory
    }

    @objc private func startPress() { _ = beginPress() }
    private func beginPress() -> UUID? {
        guard !trackingPress, let actionFactory else { return nil }
        trackingPress = true
        let token = UUID()
        pressToken = token
        let action = actionFactory()
        guard pressToken == token else { return nil }
        pressAction = action
        return token
    }

    @objc private func finishPress() {
        guard let token = pressToken else { endPress(); return }
        _ = completePress(token: token)
    }

    private func completePress(token: UUID) -> Bool {
        guard pressToken == token, let action = pressAction else { return false }
        // Clear ownership before the callback. A callback may synchronously
        // create a new press; old completion must not cancel that new action.
        endPress()
        return action()
    }

    @objc private func endPress() { cancelPress(ending: true) }
    private func cancelPress(ending: Bool) {
        if ending { trackingPress = false }
        pressToken = nil
        pressAction = nil
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { endPress() }
        super.willMove(toWindow: newWindow)
    }
    override func accessibilityActivate() -> Bool {
        endPress()
        guard let token = beginPress() else { return false }
        return completePress(token: token)
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 34) }
}

/// A configuration key is deliberately a plain UIView. UIScrollView's public
/// default cancels UIView touches when a drag begins, whereas UIControl keeps
/// tracking. Reuse the same guarded action engine without putting that button
/// in the hit-test hierarchy, so scrolling never commits an editor key.
final class KeyboardConfigurationTouchView: UIView {
    typealias ActionFactory = KeyboardTouchActionButton.ActionFactory
    private let actionEngine = KeyboardTouchActionButton()
    private var contextIdentifier: UUID?
    private var configurationRevision = UUID()
    private weak var primaryOwner: AnyObject?
    private var physicalToken: UUID?
    private var trackingPress = false
    private var initialPoint: CGPoint?
    private weak var capturedWindow: UIWindow?
    private var capturedGeometry: Geometry?

    private struct Geometry: Equatable {
        let windowBounds: CGRect
        let windowFrame: CGRect
        let bounds: CGRect
        let anchor: CGRect
    }

    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            configurationRevision = UUID()
            cancelPhysicalPress()
            isUserInteractionEnabled = isEnabled
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(contextIdentifier: UUID, actionFactory: @escaping ActionFactory) {
        if self.contextIdentifier != contextIdentifier {
            configurationRevision = UUID()
            cancelPhysicalPress()
        }
        self.contextIdentifier = contextIdentifier
        actionEngine.configure(contextIdentifier: contextIdentifier) { [weak self] in
            guard let self, self.isEnabled, self.isUserInteractionEnabled,
                  let window = self.window,
                  let snapshot = self.geometry(in: window) else { return { false } }
            let revision = self.configurationRevision
            let action = actionFactory()
            return { [weak self, weak window] in
                guard let self, let window, self.isEnabled, self.isUserInteractionEnabled,
                      self.configurationRevision == revision, self.window === window,
                      self.geometry(in: window) == snapshot else { return false }
                return action()
            }
        }
    }

    @discardableResult
    func beginPhysicalPress(owner: AnyObject, at point: CGPoint) -> Bool {
        // A vanished owner cannot send its terminal event. Clear only that
        // abandoned stream before accepting a fresh physical press.
        if trackingPress && primaryOwner == nil { cancelPhysicalPress() }
        guard isEnabled, isUserInteractionEnabled, contextIdentifier != nil, !trackingPress, let window,
              let geometry = geometry(in: window), finite(point),
              geometry.anchor.contains(point) else {
            if trackingPress && primaryOwner !== owner { cancelAction() }
            return false
        }
        let token = UUID()
        primaryOwner = owner
        physicalToken = token
        trackingPress = true
        initialPoint = point
        capturedWindow = window
        capturedGeometry = geometry
        actionEngine.sendActions(for: .touchDown)
        return physicalToken == token && primaryOwner === owner
    }

    func movePhysicalPress(owner: AnyObject, at point: CGPoint) {
        guard primaryOwner === owner, trackingPress else { return }
        guard physicalToken != nil, accepts(point) else { cancelAction(); return }
    }

    func endPhysicalPress(owner: AnyObject, at point: CGPoint) {
        guard primaryOwner === owner, trackingPress else { return }
        let accepted = physicalToken != nil && accepts(point)
        clearPhysicalOwnership()
        // Ownership is clear before execution: an action can legitimately
        // start a fresh press without old terminal cleanup cancelling it.
        actionEngine.sendActions(for: accepted ? .touchUpInside : .touchCancel)
    }

    func cancelPhysicalPress() {
        clearPhysicalOwnership()
        actionEngine.sendActions(for: .touchCancel)
    }

    private func cancelAction() {
        physicalToken = nil
        actionEngine.sendActions(for: .touchCancel)
    }

    private func clearPhysicalOwnership() {
        primaryOwner = nil
        physicalToken = nil
        trackingPress = false
        initialPoint = nil
        capturedWindow = nil
        capturedGeometry = nil
    }

    private func accepts(_ point: CGPoint) -> Bool {
        guard isEnabled, isUserInteractionEnabled, let window, window === capturedWindow,
              let current = geometry(in: window), current == capturedGeometry,
              let initialPoint, finite(point), current.anchor.contains(point) else { return false }
        let dx = point.x - initialPoint.x, dy = point.y - initialPoint.y
        return dx.isFinite && dy.isFinite && hypot(dx, dy) <= 10
    }

    private func finite(_ point: CGPoint) -> Bool { point.x.isFinite && point.y.isFinite }
    private func geometry(in window: UIWindow) -> Geometry? {
        let anchor = convert(bounds, to: window)
        let rectangles = [window.bounds, window.frame, bounds, anchor]
        guard rectangles.allSatisfy({ rect in
            [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
                && rect.width > 0 && rect.height > 0
        }) else { return nil }
        return Geometry(windowBounds: window.bounds, windowFrame: window.frame, bounds: bounds, anchor: anchor)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let touch = touches.first, let window else {
            cancelAction(); return
        }
        _ = beginPhysicalPress(owner: touch, at: touch.location(in: window))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0 === primaryOwner }), let window else { return }
        movePhysicalPress(owner: touch, at: touch.location(in: window))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0 === primaryOwner }), let window else { return }
        endPhysicalPress(owner: touch, at: touch.location(in: window))
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.contains(where: { $0 === primaryOwner }) else { return }
        cancelPhysicalPress()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if trackingPress, (primaryOwner == nil || window !== capturedWindow
            || window.flatMap({ geometry(in: $0) }) != capturedGeometry) { cancelAction() }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { cancelPhysicalPress() }
        super.willMove(toWindow: newWindow)
    }
    override func accessibilityActivate() -> Bool {
        cancelPhysicalPress()
        guard isEnabled, isUserInteractionEnabled, contextIdentifier != nil,
              let window, geometry(in: window) != nil else { return false }
        return actionEngine.accessibilityActivate()
    }
}
#endif
