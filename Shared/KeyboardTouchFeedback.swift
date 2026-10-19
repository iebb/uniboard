#if canImport(UIKit)
import UIKit

/// A noninteractive overlay: feedback never changes geometry, hit testing or
/// the captured input action. Cancellation clears it synchronously, without an
/// animation that could leave a reused key looking pressed.
final class KeyboardTouchFeedback: UIView {
    static var hapticsAllowed = false
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private(set) var isPressed = false
    static func attach(to view: UIView) -> KeyboardTouchFeedback {
        let feedback = KeyboardTouchFeedback(frame: view.bounds)
        feedback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(feedback)
        return feedback
    }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.22) : UIColor.black.withAlphaComponent(0.16)
        }
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        isHidden = !pressed
        if pressed, window != nil, Self.hapticsAllowed { Self.impact.impactOccurred(intensity: 0.55) }
    }
}
#endif
