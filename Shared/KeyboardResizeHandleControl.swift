#if canImport(UIKit)
import UIKit

private struct ResizeWindowSample {
    let windowID: ObjectIdentifier
    let point: CGPoint
    let bounds: CGRect
    let timestamp: TimeInterval
    var y: CGFloat { point.y }
}

/// Own one touch identity for the entire recognizer sequence. UIKit may send
/// foreign touches before the pan superclass enforces maximumNumberOfTouches.
/// Keep no touch objects, and never let an old/reentrant capture replace a newer
/// sample after reset or another admitted capture.
final class KeyboardPrimaryTouchCollector<Sample> {
    enum Phase { case began, moved, ended, cancelled }
    private var primaryIdentity: ObjectIdentifier?
    private weak var primaryOwner: AnyObject?
    private var captureToken = UUID()
    private(set) var initialSample: Sample?
    private(set) var latestSample: Sample?

    func ownedTouch<Touches: Collection>(in touches: Touches) -> Touches.Element?
        where Touches.Element: AnyObject {
        guard let primaryIdentity, let primaryOwner else { return nil }
        return touches.first { $0 === primaryOwner && ObjectIdentifier($0) == primaryIdentity }
    }

    @discardableResult
    func capture<Touches: Collection>(_ touches: Touches, phase: Phase,
        makeSample: (Touches.Element) -> Sample?) -> Bool where Touches.Element: AnyObject {
        let touch: Touches.Element
        if primaryIdentity != nil {
            guard let owned = ownedTouch(in: touches) else { return false }
            touch = owned
        } else {
            guard phase == .began, let first = touches.first else { return false }
            touch = first
            // Bind before invoking the sample getter. A missing window/sample
            // must not allow a later foreign finger to take over the sequence.
            primaryIdentity = ObjectIdentifier(touch)
            primaryOwner = touch
        }
        let token = UUID()
        captureToken = token
        guard let sample = makeSample(touch), captureToken == token,
              primaryOwner === touch, primaryIdentity == ObjectIdentifier(touch) else { return false }
        if initialSample == nil { initialSample = sample }
        latestSample = sample
        return true
    }

    func reset() {
        captureToken = UUID()
        primaryIdentity = nil
        primaryOwner = nil
        initialSample = nil
        latestSample = nil
    }
}

/// Capture point and window geometry together before a target callback can
/// request the next remote size. No host text or document content is sampled.
private final class ResizePanRecognizer: UIPanGestureRecognizer {
    private let samples = KeyboardPrimaryTouchCollector<ResizeWindowSample>()
    var initialSample: ResizeWindowSample? { samples.initialSample }
    var latestSample: ResizeWindowSample? { samples.latestSample }
#if DEBUG
    // Numeric copies only. A coalesced array includes the main touch again as
    // its final element; these samples never enter the live motion formula.
    private(set) var latestCoalescedDebugSample: [String: Double] = [:]

    private func captureCoalesced(_ touches: Set<UITouch>, event: UIEvent) {
        // A foreign-only event cannot replace the primary finger's diagnostic
        // batch either. Keep the prior timestamp explicit for stale detection.
        guard let touch = samples.ownedTouch(in: touches) else { return }
        var value: [String: Double] = [
            "coalesced.captureTimestamp": CACurrentMediaTime(),
            "coalesced.eventTimestamp": event.timestamp,
            "coalesced.touchPresent": touches.isEmpty ? 0 : 1,
            "coalesced.windowPresent": 0,
            "coalesced.fullCount": 0, "coalesced.retainedCount": 0,
            "coalesced.nilFlag": -1, "coalesced.truncated": 0
        ]
        guard let window = touch.window ?? view?.window else {
            latestCoalescedDebugSample = value.filter { $0.value.isFinite }
            return
        }
        // Read every point in the same handler before super can invoke targets
        // that request a new remote height. UIKit does not promise that these
        // historical points share a remote-host geometry generation.
        let bounds = window.bounds
        value["coalesced.windowPresent"] = 1
        value["coalesced.windowBoundsOriginX"] = Double(bounds.origin.x)
        value["coalesced.windowBoundsOriginY"] = Double(bounds.origin.y)
        value["coalesced.windowBoundsWidth"] = Double(bounds.width)
        value["coalesced.windowBoundsHeight"] = Double(bounds.height)
        value["coalesced.windowBoundsMaxY"] = Double(bounds.maxY)
        value["coalesced.mainTimestamp"] = touch.timestamp
        value["coalesced.mainType"] = Double(touch.type.rawValue)
        value["coalesced.mainRawWindowY"] = Double(touch.location(in: window).y)
        value["coalesced.mainPreviousWindowY"] = Double(touch.previousLocation(in: window).y)
        value["coalesced.mainPreciseWindowY"] = Double(touch.preciseLocation(in: window).y)
        let coalesced = event.coalescedTouches(for: touch)
        value["coalesced.nilFlag"] = coalesced == nil ? 1 : 0
        if let coalesced {
            value["coalesced.fullCount"] = Double(coalesced.count)
            // Preserve the first 31 points and the final main-touch copy if a
            // batch is larger than 32. sourceIndex makes the omitted interval
            // explicit; it must never be interpolated or integrated as a gap.
            let indices = coalesced.count <= 32 ? Array(coalesced.indices)
                : Array(coalesced.indices.prefix(31)) + [coalesced.count - 1]
            value["coalesced.retainedCount"] = Double(indices.count)
            value["coalesced.truncated"] = coalesced.count > indices.count ? 1 : 0
            for (slot, index) in indices.enumerated() {
                let auxiliary = coalesced[index]
                let prefix = "coalesced.\(slot)."
                value[prefix + "sourceIndex"] = Double(index)
                value[prefix + "timestamp"] = auxiliary.timestamp
                value[prefix + "rawWindowY"] = Double(auxiliary.location(in: window).y)
                value[prefix + "previousWindowY"] = Double(auxiliary.previousLocation(in: window).y)
                value[prefix + "preciseWindowY"] = Double(auxiliary.preciseLocation(in: window).y)
            }
        }
        latestCoalescedDebugSample = value.filter { $0.value.isFinite }
    }
#endif

    private func capture(_ touches: Set<UITouch>, phase: KeyboardPrimaryTouchCollector<ResizeWindowSample>.Phase) {
        samples.capture(touches, phase: phase) { touch in
            guard let window = touch.window ?? view?.window else { return nil }
            return ResizeWindowSample(windowID: ObjectIdentifier(window), point: touch.location(in: window),
                                      bounds: window.bounds, timestamp: touch.timestamp)
        }
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { capture(touches, phase: .began); super.touchesBegan(touches, with: event) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        capture(touches, phase: .moved);
#if DEBUG
        captureCoalesced(touches, event: event)
#endif
        super.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { capture(touches, phase: .ended); super.touchesEnded(touches, with: event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { capture(touches, phase: .cancelled); super.touchesCancelled(touches, with: event) }
    override func reset() {
        super.reset(); samples.reset()
#if DEBUG
        latestCoalescedDebugSample = [:]
#endif
    }
}

/// Only a qualifying vertical swipe can commit a row step on release.
final class ResizeHandleButton: UIButton {
    weak var coordinateView: UIView?
#if DEBUG
    var debugSample: (([String: Double]) -> Void)?
#endif
    var begin: (() -> Void)?
    var change: ((CGFloat) -> Void)?
    var end: ((Bool) -> Void)?
    var step: ((CGFloat) -> Void)?
    private let grip = UIView()
    private var hasActivePan = false
    private weak var motionWindow: UIWindow?
    private var touchDownSample: ResizeWindowSample?
    private var lastSample: ResizeWindowSample?
    private var motion: KeyboardFixedCanvasResizeMotion?
    private var initialPoint: CGPoint?
    private var interactionID: UUID?
    private var activeRecognizer: ObjectIdentifier?
    private var sampleSequence = KeyboardResizeSampleSequence()
    private var candidateDeltaY: CGFloat = 0
    private var lastMovementTimestamp: TimeInterval?
    private var panRecognizer: UIPanGestureRecognizer?
    private let fallbackTimestamp: () -> TimeInterval
#if DEBUG
    private var lastAcceptance: KeyboardResizeSampleSequence.Acceptance?
#endif

    init(backgroundColor: UIColor, pillColor: UIColor = .tertiaryLabel,
         fallbackTimestamp: @escaping () -> TimeInterval = { CACurrentMediaTime() }) {
        self.fallbackTimestamp = fallbackTimestamp
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
        accessibilityTraits = .adjustable
        let pan = ResizePanRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        panRecognizer = pan
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: KeyboardLayoutPolicy.resizeHandleHeight)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        grip.frame = CGRect(x: (bounds.width - 40) / 2, y: 4, width: 40, height: 4)
    }
    override func accessibilityActivate() -> Bool { false }
    override func accessibilityIncrement() { cancelResize(); step?(1) }
    override func accessibilityDecrement() { cancelResize(); step?(-1) }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first, let window = window ?? touch.window {
            motionWindow = window
            touchDownSample = ResizeWindowSample(windowID: ObjectIdentifier(window), point: touch.location(in: window),
                                                 bounds: window.bounds, timestamp: touch.timestamp)
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
        touchDownSample = nil
        lastSample = nil
        motion = nil
        initialPoint = nil
        interactionID = nil
        activeRecognizer = nil
        sampleSequence = KeyboardResizeSampleSequence()
        candidateDeltaY = 0
        lastMovementTimestamp = nil
#if DEBUG
        lastAcceptance = nil
#endif
    }
    private func finishPan(commit: Bool, expectedID: UUID? = nil) {
        if let expectedID, interactionID != expectedID { return }
        let wasActive = hasActivePan
        hasActivePan = false
        clearMotion()
        if wasActive { end?(commit) }
    }
    func cancelResize() { finishPan(commit: false) }
    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        let terminal = gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed
        let recognizerID = ObjectIdentifier(gesture)
        let tokenAtEntry = activeRecognizer == recognizerID ? interactionID : nil
        var traceToken = tokenAtEntry
        var validRelease = false
        defer { if terminal, let tokenAtEntry { finishPan(commit: validRelease, expectedID: tokenAtEntry) } }
#if DEBUG
        // LIFO defers put this sample in the recorder before terminal cleanup
        // invokes end and writes the complete diagnostic file.
        defer { if let traceToken, interactionID == traceToken { recordDebugSample(gesture) } }
#endif
        switch gesture.state {
        case .began:
            guard !hasActivePan, let window = motionWindow ?? window else { return }
            motionWindow = window
            let translationY = gesture.translation(in: window).y
            let sample = sample(for: gesture, in: window)
            guard translationY.isFinite else { clearMotion(); return }
            let initial = (gesture as? ResizePanRecognizer)?.initialSample ?? touchDownSample
                ?? ResizeWindowSample(windowID: ObjectIdentifier(window), point: CGPoint(x: sample.point.x, y: sample.y-translationY),
                                      bounds: sample.bounds, timestamp: sample.timestamp)
            guard initial.windowID == sample.windowID,
                  KeyboardResizeSampleSequence.isValid(point: initial.point, bounds: initial.bounds, timestamp: initial.timestamp),
                  sample.timestamp >= initial.timestamp,
                  sampleSequence.accept(point: sample.point, bounds: sample.bounds, timestamp: sample.timestamp) == .accepted,
                  let motion = KeyboardFixedCanvasResizeMotion(touchY: initial.y, bounds: initial.bounds),
                  let delta = motion.delta(touchY: sample.y, bounds: sample.bounds) else { clearMotion(); return }
            self.motion = motion
            initialPoint = initial.point
            lastSample = sample
            candidateDeltaY = delta
            lastMovementTimestamp = delta == 0 ? nil : sample.timestamp
            hasActivePan = true
            let token = UUID()
            interactionID = token
            activeRecognizer = recognizerID
            traceToken = token
#if DEBUG
            lastAcceptance = .accepted
#endif
            begin?()
            guard interactionID == token, hasActivePan, self.window === window else { return }
            change?(delta)
        case .cancelled, .failed:
            // A cancellation never submits one more target or commits the
            // previous valid target. Cleanup in defer owns this session only.
            break
        case .changed, .ended:
            guard hasActivePan, activeRecognizer == recognizerID, let tokenAtEntry,
                  let window = motionWindow else { return }
            let sample = sample(for: gesture, in: window)
            lastSample = sample
            let acceptance = sampleSequence.accept(point: sample.point, bounds: sample.bounds, timestamp: sample.timestamp)
#if DEBUG
            lastAcceptance = acceptance
#endif
            guard self.window === window, sample.windowID == ObjectIdentifier(window), acceptance != .invalid,
                  let delta = motion?.delta(touchY: sample.y, bounds: sample.bounds) else {
                finishPan(commit: false, expectedID: tokenAtEntry)
                return
            }
            if gesture.state == .ended {
                guard let initialPoint else { return }
                let deltaX = sample.point.x - initialPoint.x
                validRelease = KeyboardResizeStepPolicy.isVerticalSwipe(deltaX: deltaX, deltaY: delta)
                guard validRelease else { return }
            }
            if acceptance == .duplicate { return }
            if delta != candidateDeltaY { lastMovementTimestamp = sample.timestamp }
            candidateDeltaY = delta
            change?(delta)
        default: break
        }
    }
    private func sample(for gesture: UIPanGestureRecognizer, in window: UIWindow) -> ResizeWindowSample {
        (gesture as? ResizePanRecognizer)?.latestSample
            ?? ResizeWindowSample(windowID: ObjectIdentifier(window), point: gesture.location(in: window),
                                  bounds: window.bounds, timestamp: fallbackTimestamp())
    }
#if DEBUG
    private func recordDebugSample(_ gesture: UIPanGestureRecognizer) {
        guard let debugSample else { return }
        var sample: [String: Double] = [
            "timestamp": CACurrentMediaTime(), "state": Double(gesture.state.rawValue),
            "windowPresent": window == nil ? 0 : 1,
            "capturedWindowPresent": motionWindow == nil ? 0 : 1,
            "activePan": hasActivePan ? 1 : 0,
            "candidateDeltaY": Double(candidateDeltaY)
        ]
        if let recognizer = gesture as? ResizePanRecognizer {
            for (key, value) in recognizer.latestCoalescedDebugSample { sample[key] = value }
            // End/cancel callbacks may still carry the last moved batch. Keep
            // its timestamp visible rather than claiming a fresh batch then.
            if let captured = recognizer.latestCoalescedDebugSample["coalesced.mainTimestamp"],
               let input = lastSample {
                sample["coalesced.matchesCurrentInputTimestamp"] = captured == input.timestamp ? 1 : 0
            }
        }
        // Direct public getters, never an AX tree query. These measurements
        // run after the target callback; raw touch capture happened earlier.
        sample["publicGeometryProbeTimestamp"] = CACurrentMediaTime()
        sample["publicGeometryProbeAfterTargetCallback"] = 1
        sample["effectiveGeometry.osAvailable"] = 0
        sample["effectiveGeometry.scenePresent"] = 0
        sample["effectiveGeometry.available"] = 0
        sample["windowPresentation.present"] = 0
        if #available(iOS 26.0, *) { sample["effectiveGeometry.osAvailable"] = 1 }
        let ownAccessibilityFrame = self.accessibilityFrame
        let ownActivationPoint = self.accessibilityActivationPoint
        sample["handleAccessibilityFrameFinite"] = [ownAccessibilityFrame.origin.x,
            ownAccessibilityFrame.origin.y, ownAccessibilityFrame.width,
            ownAccessibilityFrame.height].allSatisfy { $0.isFinite } ? 1 : 0
        sample["handleAccessibilityFrameX"] = Double(ownAccessibilityFrame.origin.x)
        sample["handleAccessibilityFrameMinY"] = Double(ownAccessibilityFrame.minY)
        sample["handleAccessibilityFrameMaxY"] = Double(ownAccessibilityFrame.maxY)
        sample["handleAccessibilityFrameWidth"] = Double(ownAccessibilityFrame.width)
        sample["handleAccessibilityFrameHeight"] = Double(ownAccessibilityFrame.height)
        sample["handleAccessibilityActivationPointFinite"] = ownActivationPoint.x.isFinite && ownActivationPoint.y.isFinite ? 1 : 0
        sample["handleAccessibilityActivationPointX"] = Double(ownActivationPoint.x)
        sample["handleAccessibilityActivationPointY"] = Double(ownActivationPoint.y)
        sample["lastMovementInputTimestamp"] = lastMovementTimestamp
        sample["inputValidation"] = lastAcceptance.map { Double($0.rawValue) }
        if let window = motionWindow {
            let translation = gesture.translation(in: window)
            sample["windowTranslationY"] = Double(translation.y)
            sample["currentWindowBoundsHeight"] = Double(window.bounds.height)
            sample["windowFrameMinY"] = Double(window.frame.minY)
            let velocity = gesture.velocity(in: window)
            sample["windowVelocityX"] = Double(velocity.x)
            sample["windowVelocityY"] = Double(velocity.y)
            sample["windowVelocitySampleTimestamp"] = CACurrentMediaTime()
            // CALayer.frame is in its superlayer coordinates. Preserve the
            // numeric values without labelling them as global screen space.
            sample["windowModel.superlayerPresent"] = window.layer.superlayer == nil ? 0 : 1
            if let presentation = window.layer.presentation() {
                sample["windowPresentation.present"] = 1
                sample["windowPresentation.superlayerPresent"] = presentation.superlayer == nil ? 0 : 1
                sample["windowPresentation.frameX"] = Double(presentation.frame.origin.x)
                sample["windowPresentation.frameY"] = Double(presentation.frame.origin.y)
                sample["windowPresentation.frameWidth"] = Double(presentation.frame.width)
                sample["windowPresentation.frameHeight"] = Double(presentation.frame.height)
                sample["windowPresentation.boundsX"] = Double(presentation.bounds.origin.x)
                sample["windowPresentation.boundsY"] = Double(presentation.bounds.origin.y)
                sample["windowPresentation.boundsWidth"] = Double(presentation.bounds.width)
                sample["windowPresentation.boundsHeight"] = Double(presentation.bounds.height)
                sample["windowPresentation.positionX"] = Double(presentation.position.x)
                sample["windowPresentation.positionY"] = Double(presentation.position.y)
                sample["windowPresentation.anchorPointX"] = Double(presentation.anchorPoint.x)
                sample["windowPresentation.anchorPointY"] = Double(presentation.anchorPoint.y)
                sample["windowPresentation.transformM41"] = Double(presentation.transform.m41)
                sample["windowPresentation.transformM42"] = Double(presentation.transform.m42)
                sample["windowPresentation.transformM43"] = Double(presentation.transform.m43)
            }
        }
        if let input = lastSample {
            sample["inputTimestamp"] = input.timestamp
            sample["eventWindowY"] = Double(input.y)
            sample["eventWindowX"] = Double(input.point.x)
            sample["eventWindowBoundsOriginY"] = Double(input.bounds.origin.y)
            sample["eventWindowBoundsHeight"] = Double(input.bounds.height)
            sample["eventWindowBoundsMaxY"] = Double(input.bounds.maxY)
            sample["capturedBeforeTargetCallback"] = gesture is ResizePanRecognizer ? 1 : 0
            if let window = motionWindow {
                func addPoint(_ name: String, _ value: CGPoint) {
                    sample[name+"X"] = Double(value.x)
                    sample[name+"Y"] = Double(value.y)
                }
                let screen = window.screen.coordinateSpace
                addPoint("windowToScreen", window.convert(input.point, to: screen))
                addPoint("windowToFixedScreen", window.convert(input.point, to: window.screen.fixedCoordinateSpace))
                addPoint("windowBoundsOriginToScreen", window.convert(input.bounds.origin, to: screen))
                addPoint("windowBoundsMaxToScreen", window.convert(CGPoint(x: input.bounds.maxX, y: input.bounds.maxY), to: screen))
                if let scene = window.windowScene?.coordinateSpace {
                    let scenePoint = window.convert(input.point, to: scene)
                    addPoint("windowToScene", scenePoint)
                    addPoint("sceneToScreen", scene.convert(scenePoint, to: screen))
                    addPoint("sceneBoundsOriginToScreen", scene.convert(scene.bounds.origin, to: screen))
                }
                if let scene = window.windowScene {
                    sample["effectiveGeometry.scenePresent"] = 1
                    if #available(iOS 26.0, *) {
                        // Public successor to scene.coordinateSpace. The
                        // unrelated systemFrame property is unavailable iOS.
                        let geometry = scene.effectiveGeometry.coordinateSpace
                        let geometryBounds = geometry.bounds
                        let geometryPoint = window.convert(input.point, to: geometry)
                        sample["effectiveGeometry.available"] = 1
                        sample["effectiveGeometry.boundsX"] = Double(geometryBounds.origin.x)
                        sample["effectiveGeometry.boundsY"] = Double(geometryBounds.origin.y)
                        sample["effectiveGeometry.boundsWidth"] = Double(geometryBounds.width)
                        sample["effectiveGeometry.boundsHeight"] = Double(geometryBounds.height)
                        addPoint("windowToEffectiveGeometry", geometryPoint)
                        addPoint("effectiveGeometryToScreen", geometry.convert(geometryPoint, to: screen))
                        addPoint("effectiveGeometryToFixedScreen", geometry.convert(geometryPoint, to: window.screen.fixedCoordinateSpace))
                        addPoint("effectiveGeometryBoundsOriginToScreen", geometry.convert(geometryBounds.origin, to: screen))
                        addPoint("effectiveGeometryBoundsMaxToScreen", geometry.convert(CGPoint(x: geometryBounds.maxX, y: geometryBounds.maxY), to: screen))
                        addPoint("windowBoundsOriginToEffectiveGeometry", window.convert(input.bounds.origin, to: geometry))
                        addPoint("windowBoundsMaxToEffectiveGeometry", window.convert(CGPoint(x: input.bounds.maxX, y: input.bounds.maxY), to: geometry))
                    }
                }
            }
        }
        if let coordinateView {
            sample["rootHeight"] = Double(coordinateView.bounds.height)
            sample["rootPresentationHeight"] = Double(coordinateView.layer.presentation()?.bounds.height ?? coordinateView.bounds.height)
        }
        debugSample(sample.filter { $0.value.isFinite })
    }
#endif
}
#endif
