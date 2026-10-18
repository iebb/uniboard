import Foundation

enum KeyboardResizeStepPolicy {
    static let minimumTranslation: CGFloat = 12

    enum Direction: String { case up, down }
    struct Feedback: Equatable {
        let direction: Direction
    }

    /// Show a direction only when release could change the clamped height.
    /// Reversing back into the range restores feedback within the same swipe.
    static func feedback(startHeight: CGFloat, deltaY: CGFloat, range: ClosedRange<CGFloat>,
                         compact: Bool) -> Feedback? {
        guard target(startHeight: startHeight, deltaY: deltaY, range: range, compact: compact) != nil else { return nil }
        return Feedback(direction: deltaY < 0 ? .up : .down)
    }

    static func rowStride(compact: Bool) -> CGFloat {
        (compact ? KeyboardTypingLayoutPolicy.compactKeyHeight : KeyboardTypingLayoutPolicy.regularKeyHeight)
            + KeyboardTypingLayoutPolicy.rowSpacing
    }

    static func isVerticalSwipe(deltaX: CGFloat, deltaY: CGFloat,
                                minimumTranslation: CGFloat = KeyboardResizeStepPolicy.minimumTranslation) -> Bool {
        deltaX.isFinite && deltaY.isFinite && minimumTranslation.isFinite && minimumTranslation > 0
            && abs(deltaY) >= minimumTranslation && abs(deltaY) > abs(deltaX)
    }

    /// A qualifying gesture chooses one row from its original height, never
    /// one row per event or per distance threshold. A clamp can be a partial row.
    static func target(startHeight: CGFloat, deltaY: CGFloat, range: ClosedRange<CGFloat>,
                       compact: Bool, minimumTranslation: CGFloat = KeyboardResizeStepPolicy.minimumTranslation) -> CGFloat? {
        guard let start = validStart(startHeight, range: range), deltaY.isFinite,
              minimumTranslation.isFinite, minimumTranslation > 0,
              abs(deltaY) >= minimumTranslation else { return nil }
        let stride = rowStride(compact: compact)
        let raw = start + (deltaY < 0 ? stride : -stride)
        guard let selected = KeyboardResizePolicy.clampedHeight(raw, in: range, rounded: false),
              selected != start else { return nil }
        return selected
    }

    fileprivate static func validStart(_ start: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat? {
        guard start.isFinite, start > 0 else { return nil }
        return KeyboardResizePolicy.clampedHeight(start, in: range, rounded: false)
    }
}

/// The controller owns one value for a gesture. Only a successful terminal
/// callback can produce a height; cancellation and later callbacks cannot.
struct KeyboardResizeStepSession {
    let id = UUID()
    let initialHeight: CGFloat
    let range: ClosedRange<CGFloat>
    let compact: Bool
    let minimumTranslation: CGFloat
    private var deltaY: CGFloat = 0
    private var valid = true
    private var finished = false

    init?(startHeight: CGFloat, range: ClosedRange<CGFloat>, compact: Bool,
          minimumTranslation: CGFloat = KeyboardResizeStepPolicy.minimumTranslation) {
        guard let start = KeyboardResizeStepPolicy.validStart(startHeight, range: range),
              minimumTranslation.isFinite, minimumTranslation > 0 else { return nil }
        initialHeight = start
        self.range = range
        self.compact = compact
        self.minimumTranslation = minimumTranslation
    }

    @discardableResult
    mutating func update(deltaY: CGFloat) -> Bool {
        guard !finished, valid else { return false }
        guard deltaY.isFinite else { valid = false; return false }
        self.deltaY = deltaY
        return true
    }

    mutating func finish(commit: Bool) -> CGFloat? {
        guard !finished else { return nil }
        finished = true
        guard commit, valid else { return nil }
        return KeyboardResizeStepPolicy.target(startHeight: initialHeight, deltaY: deltaY,
            range: range, compact: compact, minimumTranslation: minimumTranslation)
    }
}

/// Window bounds remain fixed until release. A geometry change cancels rather
/// than guessing which remote host transform applies to a touch sample.
struct KeyboardFixedCanvasResizeMotion {
    private let initialY: CGFloat
    private let bounds: CGRect
    init?(touchY: CGFloat, bounds: CGRect) {
        guard KeyboardResizeSampleSequence.isValid(point: CGPoint(x: bounds.origin.x, y: touchY),
            bounds: bounds, timestamp: 0) else { return nil }
        initialY = touchY
        self.bounds = bounds
    }
    func delta(touchY: CGFloat, bounds: CGRect) -> CGFloat? {
        guard bounds.origin.x == self.bounds.origin.x, bounds.origin.y == self.bounds.origin.y,
              bounds.size.width == self.bounds.size.width, bounds.size.height == self.bounds.size.height,
              touchY.isFinite else { return nil }
        let delta = touchY - initialY
        return delta.isFinite ? delta : nil
    }
}
