#if canImport(UIKit)
import UIKit

/// The remote input window remains fixed during a pan. The callbacks preview
/// a candidate height; only a successful release requests a commit.
final class ResizeHandleButton: UIButton {
    weak var coordinateView: UIView?
#if DEBUG
    var debugSample: (([String: Double]) -> Void)?
#endif
    var toggle: (() -> Void)?
    var begin: (() -> Void)?
    var change: ((CGFloat) -> Void)?
    var end: ((Bool) -> Void)?
    var step: ((CGFloat) -> Void)?
    private let grip = UIView()
    private var hasActivePan = false
    private weak var motionWindow: UIWindow?
    private var touchDownWindowY: CGFloat?
    private var initialSlopCorrection: CGFloat = 0
    private var candidateDeltaY: CGFloat = 0
    private var panRecognizer: UIPanGestureRecognizer?

    init(backgroundColor: UIColor, pillColor: UIColor = .tertiaryLabel) {
        super.init(frame: .zero)
        // The remote keyboard hit mask must include the whole grab area,
        // including transparent space around the small visible pill.
        self.backgroundColor = backgroundColor
        isOpaque = false
        grip.backgroundColor = pillColor
        grip.layer.cornerRadius = 2
        grip.isUserInteractionEnabled = false
        addSubview(grip)
        accessibilityIdentifier = "keyboard.resize"
        accessibilityLabel = "Keyboard height"
        isAccessibilityElement = true
        accessibilityTraits = [.button, .adjustable]
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        panRecognizer = pan
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 18)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        grip.frame = CGRect(x: (bounds.width - 40) / 2, y: 4, width: 40, height: 4)
    }
    override func accessibilityActivate() -> Bool { toggle?(); return true }
    override func accessibilityIncrement() { step?(40) }
    override func accessibilityDecrement() { step?(-40) }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, let window = window ?? touch.window {
            let y = touch.location(in: window).y
            motionWindow = window
            touchDownWindowY = y.isFinite ? y : nil
            initialSlopCorrection = 0
            candidateDeltaY = 0
        }
        super.touchesBegan(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if !hasActivePan { clearMotion() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        // A recognized pan intentionally cancels the UIButton's raw touches.
        // Keep the active resize until the recognizer's terminal callback.
        if panRecognizer?.state != .began && panRecognizer?.state != .changed {
            finishPan(commit: false)
        }
    }
    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { finishPan(commit: false) }
        super.willMove(toWindow: newWindow)
    }
    private func clearMotion() {
        motionWindow = nil
        touchDownWindowY = nil
        initialSlopCorrection = 0
        candidateDeltaY = 0
    }
    private func finishPan(commit: Bool) {
        let wasActive = hasActivePan
        hasActivePan = false
        clearMotion()
        if wasActive { end?(commit) }
    }
    @objc private func tapped() { toggle?() }
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let terminal = gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed
        defer { if terminal { finishPan(commit: gesture.state == .ended) } }
#if DEBUG
        // LIFO defers put this sample in the recorder before terminal cleanup
        // invokes end and writes the complete diagnostic file.
        defer { recordDebugSample(gesture) }
#endif
        switch gesture.state {
        case .began:
            guard let window = motionWindow ?? window else { return }
            motionWindow = window
            let translationY = gesture.translation(in: window).y
            let currentY = gesture.location(in: window).y
            guard translationY.isFinite, currentY.isFinite else { return }
            // The controller keeps this window fixed while previewing. Capture
            // the pre-recognition movement once, before the begin callback.
            guard let correction = KeyboardResizePolicy.initialPanCorrection(currentY: currentY, touchDownY: touchDownWindowY, translationY: translationY),
                  let delta = KeyboardResizePolicy.panDelta(translationY: translationY, initialCorrection: correction) else { clearMotion(); return }
            initialSlopCorrection = correction
            candidateDeltaY = delta
            hasActivePan = true
            begin?()
            change?(delta)
        case .changed, .ended, .cancelled, .failed:
            guard hasActivePan, let window = motionWindow else { return }
            guard let delta = KeyboardResizePolicy.panDelta(translationY: gesture.translation(in: window).y, initialCorrection: initialSlopCorrection) else { return }
            candidateDeltaY = delta
            change?(delta)
        default: break
        }
    }
#if DEBUG
    private func recordDebugSample(_ gesture: UIPanGestureRecognizer) {
        guard let debugSample else { return }
        var sample: [String: Double] = [
            "timestamp": CACurrentMediaTime(), "state": Double(gesture.state.rawValue),
            "windowPresent": window == nil ? 0 : 1,
            "capturedWindowPresent": motionWindow == nil ? 0 : 1,
            "activePan": hasActivePan ? 1 : 0,
            "candidateDeltaY": Double(candidateDeltaY),
            "initialSlopCorrectionY": Double(initialSlopCorrection)
        ]
        if let window = motionWindow {
            let translation = gesture.translation(in: window)
            sample["windowTranslationY"] = Double(translation.y)
        }
        debugSample(sample.filter { $0.value.isFinite })
    }
#endif
}
#endif
