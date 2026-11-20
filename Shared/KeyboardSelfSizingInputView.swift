#if canImport(UIKit)
import UIKit

/// Isolated sizing candidate. The controller supplies a scene-capped request;
/// UIKit still owns actual remote bounds and required fitting constraints.
/// This class makes no promise about remote input-coordinate synchronization.
class KeyboardSelfSizingInputView: UIInputView {
    /// Enabled only for the iPhone portrait stock typing renderer.
    var routesStockKeyGaps = false

    private func stockKeys() -> [UIView] {
        var result: [UIView] = []
        func visit(_ node: UIView) {
            guard !node.isHidden, node.alpha > 0.01, node.isUserInteractionEnabled else { return }
            if let control = node as? UIControl, !control.isEnabled { return }
            if let id = node.accessibilityIdentifier,
               id.hasPrefix("keyboard.typing.key.") || id.hasPrefix("keyboard.typing.number.")
                || ["keyboard.typing.shift", "keyboard.typing.delete", "keyboard.typing.diacritics",
                    "keyboard.typing.symbols", "keyboard.typing.numbers", "keyboard.typing.letters",
                    "keyboard.toggleUnicodeToolbar", "keyboard.globe", "keyboard.collapse",
                    "keyboard.openFavorites", "keyboard.space", "keyboard.return"].contains(id),
               node is UIControl, node.bounds.width > 0, node.bounds.height > 0 {
                result.append(node)
            } else { node.subviews.forEach(visit) }
        }
        subviews.forEach(visit)
        return result
    }

    private func stockRegions() -> (keys: [[UIView]], regions: [[CGRect]]) {
        let keys = stockKeys()
        let frames = keys.map { $0.convert($0.keyboardVisibleBounds, to: self) }
        let rows = KeyboardKeyHitRegions.rows(of: frames)
        return (rows.map { $0.map { keys[$0] } },
                KeyboardKeyHitRegions.regions(rows: rows.map { $0.map { frames[$0] } }, bounds: bounds))
    }

    func stockTouchRect(for key: UIView) -> CGRect? {
        guard routesStockKeyGaps else { return nil }
        let layout = stockRegions()
        for (r, row) in layout.keys.enumerated() {
            if let i = row.firstIndex(where: { $0 === key }) {
                return key.convert(layout.regions[r][i], from: self)
            }
        }
        return nil
    }

    func stockKey(at point: CGPoint) -> UIView? {
        guard routesStockKeyGaps else { return nil }
        let layout = stockRegions()
        guard let key = KeyboardKeyHitRegions.key(at: point, regions: layout.regions) else { return nil }
        return layout.keys[key.row][key.index]
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard routesStockKeyGaps, bounds.contains(point), !isHidden, alpha > 0.01, isUserInteractionEnabled else {
            return super.hitTest(point, with: event)
        }
        let layout = stockRegions()
        if let key = KeyboardKeyHitRegions.key(at: point, regions: layout.regions) {
            return layout.keys[key.row][key.index]
        }
        return super.hitTest(point, with: event)
    }

    private(set) var requestedHeight: CGFloat = KeyboardLayoutPolicy.defaultHeight
    private var requestedHeightConstraint: NSLayoutConstraint!
#if DEBUG
    private var defaultFittingCalls = 0
    private var priorityFittingCalls = 0
    private var intrinsicQueries = 0
    private var changedHeightRequests = 0
    private var lastFitting: [String: Double] = [:]
    var debugSizingSnapshot: [String: Double] {
        var value = lastFitting
        value["defaultFittingCalls"] = Double(defaultFittingCalls)
        value["priorityFittingCalls"] = Double(priorityFittingCalls)
        value["intrinsicQueries"] = Double(intrinsicQueries)
        value["changedHeightRequests"] = Double(changedHeightRequests)
        value["requestedHeight"] = Double(requestedHeight)
        return value
    }
#endif

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        // Keyboard hosts do not always ask for another fitting size after an
        // intrinsic invalidation. Express the request through the documented
        // root height constraint too, below the host's required constraints.
        requestedHeightConstraint = heightAnchor.constraint(equalToConstant: requestedHeight)
        requestedHeightConstraint.identifier = "keyboard.requestedHeight"
        requestedHeightConstraint.priority = UILayoutPriority(999)
        requestedHeightConstraint.isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Domain caps remain in KeyboardLayoutPolicy; this final boundary rejects
    /// invalid values instead of passing NaN, infinity or a non-size to UIKit.
    @discardableResult
    func requestHeight(_ height: CGFloat) -> Bool {
        guard height.isFinite, height > 0, height != requestedHeight else { return false }
        requestedHeight = height
        requestedHeightConstraint.constant = height
#if DEBUG
        changedHeightRequests += 1
#endif
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.setNeedsLayout()
        return true
    }
    override var intrinsicContentSize: CGSize {
#if DEBUG
        intrinsicQueries += 1
#endif
        return CGSize(width: UIView.noIntrinsicMetric, height: requestedHeight)
    }
    override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
#if DEBUG
        defaultFittingCalls += 1
#endif
        return systemLayoutSizeFitting(targetSize,
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel)
    }
    override func systemLayoutSizeFitting(_ targetSize: CGSize,
        withHorizontalFittingPriority horizontalFittingPriority: UILayoutPriority,
        verticalFittingPriority: UILayoutPriority) -> CGSize {
#if DEBUG
        priorityFittingCalls += 1
#endif
        // Invalid external fitting inputs never enter Auto Layout's solver.
        let target = CGSize(width: Self.validDimension(targetSize.width) ? targetSize.width : 0,
                            height: Self.validDimension(targetSize.height) ? targetSize.height : requestedHeight)
        let horizontal = Self.validPriority(horizontalFittingPriority)
        let vertical = Self.validPriority(verticalFittingPriority)
        var result = super.systemLayoutSizeFitting(target,
            withHorizontalFittingPriority: horizontal, verticalFittingPriority: vertical)
        // UIInputView's superclass can return its current bounds even for a
        // required target. Apply those external dimensions explicitly rather
        // than allowing stale portrait bounds to decide the fitted size.
        if horizontal == .required { result.width = target.width }
        result.height = vertical == .required ? target.height : requestedHeight
        // Defensive final validation also covers pathological descendant
        // fitting implementations. Width remains unconstrained intrinsically.
        if !Self.validDimension(result.width) { result.width = target.width }
        if !Self.validDimension(result.height) { result.height = requestedHeight }
#if DEBUG
        lastFitting = ["lastFittingTimestamp": CACurrentMediaTime(),
            "animationsEnabledAtFitting": UIView.areAnimationsEnabled ? 1 : 0,
            "lastReturnedWidth": Double(result.width), "lastReturnedHeight": Double(result.height),
            "lastTargetWidth": Double(target.width), "lastTargetHeight": Double(target.height),
            "lastHorizontalPriority": Double(horizontal.rawValue), "lastVerticalPriority": Double(vertical.rawValue)]
#endif
        return result
    }
    private static func validDimension(_ value: CGFloat) -> Bool { value.isFinite && value >= 0 }
    private static func validPriority(_ priority: UILayoutPriority) -> UILayoutPriority {
        let value = priority.rawValue
        return value.isFinite && value > 0 && value <= UILayoutPriority.required.rawValue ? priority : .fittingSizeLevel
    }
}

/// Native frames may fill the gaps; the cap and accessibility geometry do not.
@MainActor
protocol KeyboardStockVisibleControl: AnyObject {
    var keyboardVisualInsets: UIEdgeInsets { get set }
    /// The control's own element state, which the outline speaks for.
    var keyboardKeyIsAccessibilityElement: Bool { get }
}

/// A key whose native frame also covers the gaps speaks through this plain,
/// non-interactive subview the size of the visible key, so iOS computes its
/// outline from view geometry as for any other view. Everything it says and
/// does is the owning control's; a touch at its centre hit-tests to the key.
final class KeyboardKeyAccessibilityOutline: UIView {
    private weak var owner: UIView?
    init(owner: UIView) {
        self.owner = owner
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = nil
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Expanded keys expose only the outline; others stay their own element.
    static func sync(_ outline: KeyboardKeyAccessibilityOutline, in control: UIView, expanded: Bool) {
        if expanded {
            if outline.superview !== control { control.insertSubview(outline, at: 0) }
            outline.frame = control.keyboardVisibleBounds
        } else if outline.superview != nil {
            outline.removeFromSuperview()
        }
    }

    override var isAccessibilityElement: Bool {
        get { (owner as? KeyboardStockVisibleControl)?.keyboardKeyIsAccessibilityElement ?? false }
        set {}
    }
    override var accessibilityIdentifier: String? { get { owner?.accessibilityIdentifier } set {} }
    override var accessibilityLabel: String? { get { owner?.accessibilityLabel } set {} }
    override var accessibilityValue: String? { get { owner?.accessibilityValue } set {} }
    override var accessibilityHint: String? { get { owner?.accessibilityHint } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { owner?.accessibilityTraits ?? .none } set {} }
    override var accessibilityLanguage: String? { get { owner?.accessibilityLanguage } set {} }
    override var accessibilityUserInputLabels: [String]! { get { owner?.accessibilityUserInputLabels } set {} }
    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? { get { owner?.accessibilityCustomActions } set {} }
    override func accessibilityActivate() -> Bool { owner?.accessibilityActivate() ?? false }
    override func accessibilityIncrement() { owner?.accessibilityIncrement() }
    override func accessibilityDecrement() { owner?.accessibilityDecrement() }
}

class KeyboardStockButton: UIButton, KeyboardStockVisibleControl {
    var keyboardVisualInsets = UIEdgeInsets.zero { didSet { setNeedsLayout() } }
    private lazy var accessibilityOutline = KeyboardKeyAccessibilityOutline(owner: self)
    override func contentRect(forBounds bounds: CGRect) -> CGRect {
        super.contentRect(forBounds: bounds.inset(by: keyboardVisualInsets))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        KeyboardKeyAccessibilityOutline.sync(accessibilityOutline, in: self, expanded: keyboardVisualInsets != .zero)
    }
    var keyboardKeyIsAccessibilityElement: Bool { super.isAccessibilityElement }
    override var isAccessibilityElement: Bool {
        get { keyboardVisualInsets == .zero && super.isAccessibilityElement }
        set { super.isAccessibilityElement = newValue }
    }
    override var accessibilityElements: [Any]? {
        get { keyboardVisualInsets == .zero ? super.accessibilityElements : [accessibilityOutline] }
        set { super.accessibilityElements = newValue }
    }
}

/// Touch geometry is separate from bounds and accessibility geometry.
extension UIView {
    var keyboardVisibleBounds: CGRect {
        bounds.inset(by: (self as? KeyboardStockVisibleControl)?.keyboardVisualInsets ?? .zero)
    }

    var keyboardStockTouchRect: CGRect {
        var ancestor = superview
        while let node = ancestor {
            if let input = node as? KeyboardSelfSizingInputView {
                return input.stockTouchRect(for: self) ?? bounds
            }
            ancestor = node.superview
        }
        return bounds
    }
}
#endif
