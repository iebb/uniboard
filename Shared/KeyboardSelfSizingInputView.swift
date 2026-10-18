#if canImport(UIKit)
import UIKit

/// Isolated sizing candidate. The controller supplies a scene-capped request;
/// UIKit still owns actual remote bounds and required fitting constraints.
/// This class makes no promise about remote input-coordinate synchronization.
class KeyboardSelfSizingInputView: UIInputView {
    private(set) var requestedHeight: CGFloat = KeyboardLayoutPolicy.defaultPortraitBrowseHeight
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
#endif
