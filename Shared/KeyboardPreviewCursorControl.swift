#if canImport(UIKit)
import Accessibility
import CoreText
import UIKit
import UIKit.UIGestureRecognizerSubclass

// The preview row's movable cursor (design/preview-cursor rev. 2): the view
// that draws the cursor's line as one shaped line with an overlaid caret and
// turns taps, drags, edge holds and VoiceOver adjustments into targets, and
// the driver that sends those targets to the host one move at a time. The
// rules live in KeyboardPreviewCursorPolicy.swift.

/// Watches every touch in the keyboard without taking part in it, so the
/// preview can ignore a touch that begins while a key is held or right after
/// a key touch-up (§5). It never recognizes, delays or cancels anything.
final class KeyboardKeyTouchObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var down = Set<ObjectIdentifier>()
    private(set) var lastRelease: TimeInterval?
    /// Every key touch down and up, so the preview caret stays solid (§1a).
    var onKeyActivity: @MainActor () -> Void = {}
    /// Touches that start in a view this returns true for are not key touches.
    var ignores: @MainActor (UIView?) -> Bool = { _ in false }

    var keysDown: Int { down.count }

    static func make() -> KeyboardKeyTouchObserver {
        let observer = KeyboardKeyTouchObserver(target: nil, action: nil)
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.delegate = observer
        return observer
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        var key = false
        for touch in touches where !ignores(touch.view) { down.insert(ObjectIdentifier(touch)); key = true }
        if key { onKeyActivity() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) { release(touches, at: event.timestamp) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { release(touches, at: event.timestamp) }

    private func release(_ touches: Set<UITouch>, at time: TimeInterval) {
        var key = false
        for touch in touches where down.remove(ObjectIdentifier(touch)) != nil { lastRelease = time; key = true }
        if key { onKeyActivity() }
        if down.isEmpty { state = .failed }
    }

    override func reset() {
        super.reset()
        down.removeAll()
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}

@MainActor
protocol KeyboardPreviewCursorControlDelegate: AnyObject {
    /// Typing protection and the §6 guards: whether a touch beginning at
    /// `time` (the touch's timestamp) may move the cursor.
    func previewCursorShouldBeginTouch(_ control: KeyboardPreviewCursorControl, at time: TimeInterval) -> Bool
    /// A tap or drag target, a boundary of the displayed line.
    func previewCursor(_ control: KeyboardPreviewCursorControl, request offset: Int)
    /// One edge step or VoiceOver adjustment in reading order; false when
    /// nothing more is reachable that way.
    func previewCursor(_ control: KeyboardPreviewCursorControl, step forward: Bool, announce: Bool) -> Bool
    func previewCursor(_ control: KeyboardPreviewCursorControl, lineEdge: KeyboardPreviewCursorSession.Goal) -> Bool
    /// The finger lifted (or the gesture was cancelled).
    func previewCursorDidEndTouch(_ control: KeyboardPreviewCursorControl)
}

/// Draws one shaped CTLine in its own coordinates; the control positions it.
private final class PreviewLineView: UIView {
    var line: CTLine? { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let line, let context = UIGraphicsGetCurrentContext() else { return }
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        // Center the line box (ascent above, descent plus leading below) as
        // the row and Copy Image do.
        context.textPosition = CGPoint(x: 0, y: (bounds.height - (ascent + descent + leading)) / 2 + descent + leading)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

/// The preview row's text area: the cursor's line in Uniboard's fonts, the
/// caret and the "…" caps. Tap, drag and edge hold produce targets for the
/// delegate; the drawn caret is whatever `configure` says.
final class KeyboardPreviewCursorControl: UIView, UIGestureRecognizerDelegate {
    weak var delegate: KeyboardPreviewCursorControlDelegate?
    var caretColor: UIColor = .systemBlue { didSet { caret.backgroundColor = caretColor } }

    private let lineView = PreviewLineView()
    private let caret = UIView()
    private let leftCap = UILabel()
    private let rightCap = UILabel()
    private let lineMask = CALayer()
    private var shaped: CTLine?
    private(set) var lineWidth: CGFloat = 0
    /// The line x at the text area's left edge (§2).
    private(set) var horizontalOffset: CGFloat = 0
    private(set) var line = KeyboardPreviewCursorLine(before: nil, after: nil)
    private(set) var caretOffset = 0
    private(set) var isInteractive = false
    private var placementGeneration = -1
    private var needsReset = true
    private var animateNextScroll = false
    private var stepEdge: KeyboardPreviewCursorPolicy.Edge?
    private var stepStart: TimeInterval = 0
    private var stepToken = 0
    private var tapRecognizer: UITapGestureRecognizer?
    private var dragRecognizer: UIPanGestureRecognizer?
    private var lastActivity: TimeInterval = 0
    private var isDragging = false
    private var fingersDown = 0
    private var blinkToken = 0
    private static let blinkKey = "previewCaretBlink"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        semanticContentAttribute = .forceLeftToRight
        addSubview(lineView)
        lineMask.backgroundColor = UIColor.black.cgColor
        lineView.layer.mask = lineMask
        caret.backgroundColor = .systemBlue
        caret.layer.cornerRadius = 1
        caret.isUserInteractionEnabled = false
        addSubview(caret)
        for cap in [leftCap, rightCap] {
            cap.text = KeyboardTextPreviewLayout.ellipsis
            cap.font = .systemFont(ofSize: KeyboardTextPreviewLayout.fontSize)
            cap.textColor = .secondaryLabel
            cap.textAlignment = .center
            cap.isHidden = true
            cap.isUserInteractionEnabled = false
            addSubview(cap)
        }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        drag.maximumNumberOfTouches = 1
        tap.require(toFail: drag)
        tap.delegate = self
        drag.delegate = self
        addGestureRecognizer(tap)
        addGestureRecognizer(drag)
        tapRecognizer = tap
        dragRecognizer = drag

        isAccessibilityElement = true
        accessibilityIdentifier = "keyboard.textPreview"
        accessibilityLabel = KeyboardPreviewCursorPolicy.accessibilityLabel
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: KeyboardPreviewCursorPolicy.moveToLineStartName) { [weak self] _ in
                guard let self, self.isInteractive else { return false }
                self.noteActivity()
                return self.delegate?.previewCursor(self, lineEdge: .lineStart) ?? false
            },
            UIAccessibilityCustomAction(name: KeyboardPreviewCursorPolicy.moveToLineEndName) { [weak self] _ in
                guard let self, self.isInteractive else { return false }
                self.noteActivity()
                return self.delegate?.previewCursor(self, lineEdge: .lineEnd) ?? false
            }
        ]
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
            (self: KeyboardPreviewCursorControl, _: UITraitCollection) in self.reshape()
        }
        updateAccessibility()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(blinkSettingsChanged),
                           name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
        if #available(iOS 18.0, *) {
            center.addObserver(self, selector: #selector(blinkSettingsChanged),
                               name: AccessibilitySettings.prefersNonBlinkingTextInsertionIndicatorDidChangeNotification,
                               object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `placementGeneration` changes when the app moved the cursor or changed
    /// the text itself: the line is placed afresh (§2 reset). Otherwise the
    /// line keeps its x and scrolls only to keep the caret inside the margins.
    func configure(line: KeyboardPreviewCursorLine, caret: Int, interactive: Bool, placementGeneration: Int) {
        let textChanged = line.text != self.line.text || line.direction != self.line.direction || shaped == nil
        let changed = textChanged || line != self.line || caret != caretOffset || interactive != isInteractive
            || placementGeneration != self.placementGeneration
        guard changed else { return }
        let oldText = self.line.text
        let oldLine = shaped
        if placementGeneration != self.placementGeneration { needsReset = true }
        self.placementGeneration = placementGeneration
        self.line = line
        caretOffset = min(max(0, caret), line.length)
        if isInteractive != interactive {
            isInteractive = interactive
            if !interactive { cancelGestures() }
        }
        if textChanged {
            reshape()
            if !needsReset, let oldLine, let shaped,
               let match = KeyboardPreviewCursorPolicy.alignment(from: oldText, to: line.text) {
                // Keep the text both lines share where it was on screen.
                let oldX = CTLineGetOffsetForStringIndex(oldLine, match.old, nil)
                let newX = CTLineGetOffsetForStringIndex(shaped, match.new, nil)
                horizontalOffset += newX - oldX
            }
        }
        updateAccessibility()
        setNeedsLayout()
        // Any host text or selection change, move or typing: solid, then
        // blinking again once idle.
        noteActivity()
    }

    private func reshape() {
        let attributed = NSMutableAttributedString(attributedString: KeyboardTextPreviewLayout.attributedText(
            line.text, foreground: UIColor.label.resolvedColor(with: traitCollection)))
        if attributed.length > 0 {
            var direction: CTWritingDirection = line.direction == .leftToRight ? .leftToRight : .rightToLeft
            let paragraph = withUnsafeMutablePointer(to: &direction) { pointer in
                var setting = CTParagraphStyleSetting(spec: .baseWritingDirection,
                                                      valueSize: MemoryLayout<CTWritingDirection>.size, value: pointer)
                return CTParagraphStyleCreate(&setting, 1)
            }
            attributed.addAttribute(NSAttributedString.Key(kCTParagraphStyleAttributeName as String), value: paragraph,
                                    range: NSRange(location: 0, length: attributed.length))
        }
        let shaped = CTLineCreateWithAttributedString(attributed)
        self.shaped = shaped
        let width = CGFloat(CTLineGetTypographicBounds(shaped, nil, nil, nil))
        lineWidth = width.isFinite ? max(0, width) : 0
        lineView.line = shaped
        setNeedsLayout()
    }

    private var textWidth: CGFloat { bounds.width.isFinite ? max(0, bounds.width) : 0 }

    /// The caret's x in line coordinates (primary offset, §1).
    func lineX(of offset: Int) -> CGFloat {
        guard let shaped, !line.isEmpty else { return line.direction == .leftToRight ? 0 : lineWidth }
        let x = CTLineGetOffsetForStringIndex(shaped, min(max(0, offset), line.length), nil)
        return x.isFinite ? x : 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = textWidth, height = bounds.height
        let caretX = lineX(of: caretOffset)
        let previous = horizontalOffset
        if needsReset {
            horizontalOffset = KeyboardPreviewCursorPolicy.resetOffset(caretX: caretX, lineWidth: lineWidth, width: width,
                direction: line.direction, ellipsisWidth: KeyboardPreviewCursorPolicy.ellipsisCapWidth)
            needsReset = false
        } else {
            horizontalOffset = KeyboardPreviewCursorPolicy.scrollOffset(caretX: caretX, previous: horizontalOffset,
                lineWidth: lineWidth, width: width, direction: line.direction,
                hidden: KeyboardPreviewCursorPolicy.hiddenSides(of: line))
        }
        let animate = animateNextScroll && abs(previous - horizontalOffset) > 0.5 && !UIAccessibility.isReduceMotionEnabled
        animateNextScroll = false
        let caps = KeyboardPreviewCursorPolicy.ellipsisEdges(offset: horizontalOffset, lineWidth: lineWidth,
                                                             width: width, line: line)
        let cap = KeyboardPreviewCursorPolicy.ellipsisCapWidth
        // Whole characters only beside a "…" (what Copy Image takes too).
        let drawn = KeyboardPreviewCursorPolicy.drawnSpan(characters: characterSpans(),
                                                          visible: visibleRange(width: width, caps: caps), caps: caps,
                                                          ink: characterInk())
        let apply = {
            self.lineView.frame = CGRect(x: -self.horizontalOffset, y: 0, width: max(1, ceil(self.lineWidth) + 2), height: height)
            CATransaction.begin()
            CATransaction.setDisableActions(!animate)
            self.lineMask.frame = CGRect(x: drawn.lowerBound + self.horizontalOffset, y: 0,
                                         width: drawn.upperBound - drawn.lowerBound, height: height)
            CATransaction.commit()
            let x = min(max(0, caretX - self.horizontalOffset - KeyboardTextPreviewLayout.caretWidth / 2),
                        max(0, width - KeyboardTextPreviewLayout.caretWidth))
            self.caret.frame = CGRect(x: x, y: max(0, (height - 22) / 2),
                                      width: KeyboardTextPreviewLayout.caretWidth, height: min(22, height))
        }
        if animate {
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: apply)
        } else { apply() }
        leftCap.isHidden = !caps.left
        rightCap.isHidden = !caps.right
        leftCap.frame = CGRect(x: 0, y: 0, width: cap, height: height)
        rightCap.frame = CGRect(x: width - cap, y: 0, width: cap, height: height)
    }

    // MARK: Hit testing

    /// The grapheme boundary whose primary caret position is nearest the
    /// text-area x (§3): logical, bidi-aware, never inside a cluster; past
    /// the drawn text it is the boundary at that visual end.
    func boundary(atTextAreaX x: CGFloat) -> Int {
        let lineXValue = x + horizontalOffset
        // Past the drawn text: the end of what the app exposed on that side,
        // even when a run of the other direction sits at that visual edge.
        let ltr = line.direction == .leftToRight
        if lineXValue > lineWidth { return ltr ? line.length : 0 }
        if lineXValue < 0 { return ltr ? 0 : line.length }
        let candidates = line.boundaries.map { (offset: $0, x: lineX(of: $0)) }
        return KeyboardPreviewCursorPolicy.nearestBoundary(to: lineXValue, among: candidates) ?? line.caret
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        fingersDown += touches.count
        noteActivity()
        super.touchesBegan(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        fingerLifted(touches)
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Also when the tap or drag takes the touch over; the drag keeps the
        // caret solid until it ends.
        fingerLifted(touches)
        super.touchesCancelled(touches, with: event)
    }

    private func fingerLifted(_ touches: Set<UITouch>) {
        fingersDown = max(0, fingersDown - touches.count)
        noteActivity()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { isInteractive }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isInteractive else { return false }
        return delegate?.previewCursorShouldBeginTouch(self, at: touch.timestamp) ?? false
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, isInteractive else { return }
        let x = gesture.location(in: self).x
        // A tap on a "…" cap reveals more with a short scroll (§3).
        animateNextScroll = true
        delegate?.previewCursor(self, request: boundary(atTextAreaX: x))
        delegate?.previewCursorDidEndTouch(self)
    }

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            guard isInteractive else { cancelGestures(); return }
            if !isDragging { isDragging = true; noteActivity() }
            let x = gesture.location(in: self).x
            let caps = KeyboardPreviewCursorPolicy.ellipsisEdges(offset: horizontalOffset, lineWidth: lineWidth,
                                                                 width: textWidth, line: line)
            if let edge = KeyboardPreviewCursorPolicy.edge(at: x, width: textWidth, caps: caps) {
                if stepEdge != edge { startStepping(toward: edge) }
            } else {
                stopStepping()
                delegate?.previewCursor(self, request: boundary(atTextAreaX: x))
            }
        case .ended, .cancelled, .failed:
            stopStepping()
            isDragging = false
            noteActivity()
            delegate?.previewCursorDidEndTouch(self)
        default: break
        }
    }

    // MARK: Edge stepping (§4)

    private func startStepping(toward edge: KeyboardPreviewCursorPolicy.Edge) {
        stepEdge = edge
        stepStart = ProcessInfo.processInfo.systemUptime
        stepToken += 1
        step(token: stepToken)
    }

    private func step(token: Int) {
        guard token == stepToken, let edge = stepEdge, isInteractive else { return }
        let forward = KeyboardPreviewCursorPolicy.stepsForward(toward: edge, in: line.direction)
        guard delegate?.previewCursor(self, step: forward, announce: false) == true else { stopStepping(); return }
        let interval = KeyboardPreviewCursorPolicy.stepInterval(afterStepping: ProcessInfo.processInfo.systemUptime - stepStart)
        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in self?.step(token: token) }
    }

    private func stopStepping() {
        stepEdge = nil
        stepToken += 1
    }

    var isStepping: Bool { stepEdge != nil }

    func cancelGestures() {
        stopStepping()
        isDragging = false
        fingersDown = 0
        for recognizer in [tapRecognizer, dragRecognizer].compactMap({ $0 }) {
            recognizer.isEnabled = false
            recognizer.isEnabled = true
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow !== window { cancelGestures() }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Hidden: stop blinking; shown again: solid, then blinking when idle.
        noteActivity()
    }

    // MARK: Caret blink (§1a, KeyboardPreviewCaretBlinkPolicy)

    /// False while the keyboard is hidden or a Copy Image or Inspect panel is
    /// open: the caret is solid and nothing runs.
    var isCaretLive = true {
        didSet { if isCaretLive != oldValue { noteActivity() } }
    }

    /// Whether the caret's blink animation is running.
    var isCaretBlinking: Bool { caret.layer.animation(forKey: Self.blinkKey) != nil }

    private var prefersNonBlinkingCaret: Bool {
        if #available(iOS 18.0, *) { return AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator }
        return false
    }

    private var blinkIsLive: Bool { isCaretLive && isInteractive && window != nil }
    private var blinkIsBusy: Bool { isDragging || isStepping || fingersDown > 0 }

    @objc private func blinkSettingsChanged() { noteActivity() }

    /// A finger, key, VoiceOver move or app change: solid now and for the
    /// idle delay after, then blinking from fully visible.
    func noteCaretActivity() { noteActivity() }

    private func noteActivity() {
        lastActivity = ProcessInfo.processInfo.systemUptime
        blinkToken += 1
        caret.layer.removeAnimation(forKey: Self.blinkKey)
        caret.layer.opacity = 1
        guard blinkIsLive, !blinkIsBusy, !prefersNonBlinkingCaret else { return }
        let token = blinkToken
        let delay = KeyboardPreviewCaretBlinkPolicy.delayUntilBlinking(now: lastActivity, lastActivity: lastActivity)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.startBlinking(token: token) }
    }

    private func startBlinking(token: Int) {
        typealias Blink = KeyboardPreviewCaretBlinkPolicy
        guard token == blinkToken, Blink.blinks(live: blinkIsLive, prefersNonBlinking: prefersNonBlinkingCaret,
            busy: blinkIsBusy, now: ProcessInfo.processInfo.systemUptime, lastActivity: lastActivity) else { return }
        // Only the overlay's opacity animates; the shaped line is not redrawn.
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        if UIAccessibility.isReduceMotionEnabled {
            blink.values = Blink.discreteOpacities
            blink.keyTimes = Blink.discreteKeyTimes.map { NSNumber(value: $0) }
            blink.calculationMode = .discrete
        } else {
            blink.values = Blink.opacities
            blink.keyTimes = Blink.keyTimes.map { NSNumber(value: $0) }
            blink.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut),
                                          count: Blink.keyTimes.count - 1)
        }
        blink.duration = Blink.period
        blink.repeatCount = .infinity
        blink.isRemovedOnCompletion = false
        caret.layer.add(blink, forKey: Self.blinkKey)
    }

    // MARK: Copy Image and Inspect (§7)

    /// The text-area x between the edges or the "…" caps.
    private func visibleRange(width: CGFloat, caps: (left: Bool, right: Bool)) -> ClosedRange<CGFloat> {
        let cap = KeyboardPreviewCursorPolicy.ellipsisCapWidth
        let low = caps.left ? cap : 0
        return low...max(low, caps.right ? width - cap : width)
    }

    /// Each character's drawn ink in text-area x (parallel to
    /// `characterSpans()`, nil for blank characters), from the glyph outlines
    /// of the shaped line.
    func characterInk() -> [ClosedRange<CGFloat>?] {
        let boundaries = line.boundaries
        var ink = [ClosedRange<CGFloat>?](repeating: nil, count: max(0, boundaries.count - 1))
        guard let shaped, !ink.isEmpty else { return ink }
        func character(containing index: Int) -> Int? {
            // The last boundary at or before `index`.
            var low = 0, high = boundaries.count - 1
            guard index >= boundaries[0], index < boundaries[high] else { return nil }
            while high - low > 1 {
                let middle = (low + high) / 2
                if boundaries[middle] <= index { low = middle } else { high = middle }
            }
            return low
        }
        for run in (CTLineGetGlyphRuns(shaped) as? [CTRun]) ?? [] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0,
                  let value = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String],
                  CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { continue }
            let font = value as! CTFont
            let all = CFRange(location: 0, length: 0)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            var rects = [CGRect](repeating: .zero, count: count)
            CTRunGetGlyphs(run, all, &glyphs)
            CTRunGetPositions(run, all, &positions)
            CTRunGetStringIndices(run, all, &indices)
            CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, &rects, count)
            for i in 0..<count where rects[i].width > 0 {
                let minX = positions[i].x + rects[i].minX - horizontalOffset
                let maxX = positions[i].x + rects[i].maxX - horizontalOffset
                guard minX.isFinite, maxX.isFinite, let c = character(containing: indices[i]) else { continue }
                ink[c] = ink[c].map { min($0.lowerBound, minX)...max($0.upperBound, maxX) } ?? minX...maxX
            }
        }
        return ink
    }

    /// Each whole character's span in text-area x.
    private func characterSpans() -> [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)] {
        zip(line.boundaries, line.boundaries.dropFirst()).map { start, end in
            let a = lineX(of: start) - horizontalOffset, b = lineX(of: end) - horizontalOffset
            return (start..<end, min(a, b), max(a, b))
        }
    }

    /// The characters fully visible between the edges or caps, split at the
    /// caret, with "…" where the row shows it.
    func visibleExcerpt() -> KeyboardPreviewExcerpt {
        let width = textWidth
        let caps = KeyboardPreviewCursorPolicy.ellipsisEdges(offset: horizontalOffset, lineWidth: lineWidth,
                                                             width: width, line: line)
        let characters = characterSpans()
        // Logical before/after keep the reading order; Copy Image shapes
        // them as one line, as the row draws them.
        let caret = min(max(0, caretOffset), line.length)
        let visible = KeyboardPreviewCursorPolicy.visibleExcerpt(line: line, caret: caret, characters: characters,
                                                                 visible: visibleRange(width: width, caps: caps))
        return KeyboardPreviewExcerpt(before: visible.before, after: visible.after,
                                      beforeTruncated: visible.beforeTruncated, afterTruncated: visible.afterTruncated,
                                      isSingleLine: true)
    }

    // MARK: Accessibility (§8)

    private func updateAccessibility() {
        accessibilityValue = line.text
        accessibilityTraits = isInteractive ? [.adjustable] : [.staticText]
        accessibilityHint = isInteractive ? KeyboardPreviewCursorPolicy.accessibilityHint : nil
    }

    override func accessibilityIncrement() {
        guard isInteractive else { return }
        noteActivity()
        _ = delegate?.previewCursor(self, step: true, announce: true)
    }

    override func accessibilityDecrement() {
        guard isInteractive else { return }
        noteActivity()
        _ = delegate?.previewCursor(self, step: false, announce: true)
    }
}

/// Where the preview reads the host and sends moves: the document proxy in
/// the keyboard, a fake in tests.
@MainActor
protocol KeyboardPreviewCursorHost: AnyObject {
    var previewContextBefore: String? { get }
    var previewContextAfter: String? { get }
    var previewDocumentIdentifier: UUID? { get }
    var previewHasSelection: Bool { get }
    var previewIsSecure: Bool { get }
    /// Inspect or Copy Image covers the row.
    var previewPanelOpen: Bool { get }
    func previewAdjust(by offset: Int)
    func previewAnnounce(_ message: String)
}

/// Runs the preview cursor's session against the host: one move in flight,
/// the next after the host's callback (or the 100 ms timeout), the re-read
/// 300 ms after settling, the per-field unit memory and the one repair of a
/// cursor left inside a cluster. Typing always wins: any keyboard edit drops
/// the move in flight.
@MainActor
final class KeyboardPreviewCursorDriver {
    struct State: Equatable {
        var line: KeyboardPreviewCursorLine
        var caret: Int
        var interactive: Bool
        /// Changes when the app moved the cursor or changed the text itself.
        var placementGeneration: Int
    }

    weak var host: KeyboardPreviewCursorHost?
    var publish: @MainActor (State) -> Void = { _ in }
    var now: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    var schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { work() } }
    }

    private(set) var session = KeyboardPreviewCursorSession(line: KeyboardPreviewCursorLine(before: nil, after: nil))
    private(set) var memory = KeyboardPreviewCursorUnitMemory()
    private(set) var state = State(line: KeyboardPreviewCursorLine(before: nil, after: nil), caret: 0,
                                   interactive: false, placementGeneration: 0)
    private var document: UUID?
    private var hasDocument = false
    /// Changes the keyboard itself causes (moves, typing) before this time
    /// never reset the placement.
    private var ownChangesUntil: TimeInterval = -1
    private var moveToken = 0
    private var announceOnSettle = false
    private var repairsLeft = 0

    init() {}

    /// Typing, deleting and the app's callbacks keep a short own-change window.
    static let ownChangeWindow: TimeInterval = 0.5

    private func readLine() -> KeyboardPreviewCursorLine {
        KeyboardPreviewCursorLine(before: host?.previewContextBefore, after: host?.previewContextAfter)
    }

    private var interactive: Bool {
        guard let host else { return false }
        return KeyboardPreviewCursorPolicy.isInteractive(line: session.line,
            contextShared: host.previewContextBefore != nil || host.previewContextAfter != nil,
            hasSelection: host.previewHasSelection, isSecure: host.previewIsSecure, panelOpen: host.previewPanelOpen)
    }

    private var blocked: Bool {
        guard let host else { return true }
        return host.previewHasSelection || host.previewIsSecure || host.previewPanelOpen
    }

    /// A host callback or any other re-read of the context.
    func refresh() {
        let new = readLine()
        let identifier = host?.previewDocumentIdentifier
        if !hasDocument || identifier != document {
            hasDocument = true
            document = identifier
            moveToken += 1
            session = KeyboardPreviewCursorSession(line: new, unit: memory.unit(for: identifier))
            publish(reset: true)
            return
        }
        if session.isMoving {
            if blocked {
                // The app selected text (or a panel opened): forget the move.
                moveToken += 1
                session.cancel(new)
                publish(reset: false)
            } else if session.hasChanged(new) {
                handle(session.confirm(new))
            } else {
                publish(reset: false)
            }
            return
        }
        let changed = new.text != session.line.text || new.caret != session.line.caret
        session.refresh(new)
        publish(reset: changed && now() > ownChangesUntil)
    }

    /// The keyboard is about to insert or delete: never move after that.
    func keyboardWillEdit() {
        ownChangesUntil = now() + Self.ownChangeWindow
        guard session.isMoving else { return }
        moveToken += 1
        session.cancel(readLine())
        publish(reset: false)
    }

    /// The keyboard went away or the field changed: start fresh next time.
    func reset() {
        moveToken += 1
        hasDocument = false
        session.cancel(readLine())
    }

    func request(_ offset: Int) {
        guard interactive else { return }
        begin(announce: false)
        handle(session.request(offset))
    }

    /// One character in reading order from the displayed caret. While a move
    /// is in flight the step waits (never faster than the host confirms).
    func step(forward: Bool, announce: Bool) -> Bool {
        guard interactive else { return false }
        if session.isMoving { return true }
        guard let target = KeyboardPreviewCursorPolicy.steppedTarget(in: session.line, from: session.displayedCaret,
                                                                     forward: forward) else {
            if announce { host?.previewAnnounce(KeyboardPreviewCursorPolicy.announcement(line: session.line,
                                                                                         caret: session.line.caret)) }
            return false
        }
        begin(announce: announce)
        handle(session.request(target))
        return true
    }

    func lineEdge(_ goal: KeyboardPreviewCursorSession.Goal) -> Bool {
        guard interactive else { return false }
        begin(announce: true)
        handle(session.requestLineEdge(goal))
        return true
    }

    /// Release: the final target is already in flight or settled; re-read
    /// after confirmation and again 300 ms later.
    func endTouch() {
        let token = moveToken
        schedule(KeyboardPreviewCursorSession.settleRereadDelay) { [weak self] in
            guard let self, token == self.moveToken, !self.session.isMoving else { return }
            self.refresh()
        }
    }

    private func begin(announce: Bool) {
        if !session.isMoving { repairsLeft = 1 }
        announceOnSettle = announce
    }

    private func handle(_ step: KeyboardPreviewCursorSession.Step) {
        switch step {
        case .none:
            publish(reset: false)
        case .send(let offset):
            send(offset)
            publish(reset: false)
        case .settled:
            moveToken += 1
            if let unit = session.unit { memory.remember(unit, for: document) }
            publish(reset: false)
            let token = moveToken
            if repairsLeft > 0, let host,
               let repair = KeyboardPreviewCursorPolicy.repairOffset(before: host.previewContextBefore ?? "",
                                                                     after: host.previewContextAfter ?? "") {
                // Never leave the app's cursor inside a cluster.
                repairsLeft = 0
                ownChangesUntil = now() + Self.ownChangeWindow
                host.previewAdjust(by: repair)
            }
            if announceOnSettle {
                announceOnSettle = false
                host?.previewAnnounce(KeyboardPreviewCursorPolicy.announcement(line: session.line, caret: session.line.caret))
            }
            schedule(KeyboardPreviewCursorSession.settleRereadDelay) { [weak self] in
                guard let self, token == self.moveToken, !self.session.isMoving else { return }
                self.refresh()
            }
        }
    }

    private func send(_ offset: Int) {
        moveToken += 1
        let token = moveToken
        ownChangesUntil = now() + Self.ownChangeWindow
        host?.previewAdjust(by: offset)
        schedule(KeyboardPreviewCursorSession.confirmationTimeout) { [weak self] in
            guard let self, token == self.moveToken, self.session.isMoving else { return }
            self.handle(self.session.confirm(self.readLine()))
        }
    }

    private func publish(reset: Bool) {
        let next = State(line: session.line, caret: session.displayedCaret, interactive: interactive,
                         placementGeneration: state.placementGeneration + (reset ? 1 : 0))
        guard next != state else { return }
        state = next
        publish(next)
    }
}
#endif
