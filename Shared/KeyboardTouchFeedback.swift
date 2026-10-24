#if canImport(UIKit)
import UIKit

/// A noninteractive overlay: feedback never changes geometry, hit testing or
/// the captured input action. Cancellation clears it synchronously, without an
/// animation that could leave a reused key looking pressed.
final class KeyboardTouchFeedback: UIView {
    static var hapticsAllowed = false
    private static let impact = UIImpactFeedbackGenerator(style: .light)
    private(set) var isPressed = false
    /// A held query key typed into the host: the accent overlay replaces the
    /// grey press until release.
    private(set) var isHeld = false
    private static let pressedColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.22) : UIColor.black.withAlphaComponent(0.16)
    }
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
        backgroundColor = Self.pressedColor
        layer.cornerRadius = 7
        layer.cornerCurve = .continuous
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setPressed(_ pressed: Bool) {
        if !pressed { showHeld(false, accent: nil) }
        guard pressed != isPressed else { return }
        isPressed = pressed
        isHidden = !pressed
        if pressed, window != nil, Self.hapticsAllowed { Self.impact.impactOccurred(intensity: 0.55) }
    }
    /// Marks the moment a held key typed into the host: the accent overlay at
    /// 35% and one light impact, under the same gating as a press. Only an
    /// already pressed key can become held; release clears it.
    func setHeld(accent: UIColor) {
        guard isPressed, !isHeld else { return }
        showHeld(true, accent: accent)
        if window != nil, Self.hapticsAllowed { Self.impact.impactOccurred(intensity: 0.55) }
    }
    private func showHeld(_ held: Bool, accent: UIColor?) {
        guard held != isHeld else { return }
        isHeld = held
        backgroundColor = held ? (accent ?? .systemBlue).withAlphaComponent(0.35) : Self.pressedColor
    }
}
#endif
