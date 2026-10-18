import Foundation

/// Remote keyboard scenes can retain a stale interfaceOrientation after the
/// host rotates. Phone layout follows the actual view width, never its height.
enum KeyboardLayoutPolicy {
    struct Metrics {
        let isCompactLayout: Bool
        let height: CGFloat
        let portraitResizeRange: ClosedRange<CGFloat>?
    }

    static func metrics(viewWidth: CGFloat, displaySize: CGSize?, sceneHeight: CGFloat?, isPad: Bool,
                        compactVertical: Bool, isSearching: Bool, isInspecting: Bool,
                        portraitBrowseHeight: CGFloat = 300, portraitExpandedHeight: CGFloat = 340) -> Metrics {
        let edges: (short: CGFloat, long: CGFloat)?
        if let size = displaySize,
           size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 {
            edges = (short: Swift.min(size.width, size.height), long: Swift.max(size.width, size.height))
        } else {
            edges = nil
        }
        let compact: Bool
        if isPad { compact = false }
        else if let edges, viewWidth.isFinite, viewWidth > 0 {
            // Subtract instead of adding a tolerance to an extreme dimension.
            compact = viewWidth > edges.short && viewWidth - edges.short > max(24, edges.short * 0.10)
        } else {
            compact = compactVertical
        }
        let expanded = isSearching || isInspecting
        let browseHeight = portraitBrowseHeight.isFinite ? min(420, max(220, portraitBrowseHeight)) : 300
        let expandedHeight = portraitExpandedHeight.isFinite ? min(420, max(340, portraitExpandedHeight)) : 340
        let target: CGFloat = isPad ? (expanded ? 380 : 340) : compact ? 220 : (expanded ? expandedHeight : browseHeight)
        let effectiveHeight: CGFloat?
        if !isPad, let edges { effectiveHeight = compact ? edges.short : edges.long }
        else { effectiveHeight = sceneHeight }
        let fraction: CGFloat = isPad ? 0.50 : compact ? 0.60 : 0.55
        let cap: CGFloat? = effectiveHeight.flatMap {
            guard $0.isFinite, $0 > 0 else { return nil }
            let value = $0 * fraction
            return value.isFinite && value > 0 ? value : nil
        }
        let height = min(target, cap ?? target)
        let maximum = min(420, cap ?? 420)
        let range = !isPad && !compact ? min(expanded ? 340 : 220, maximum)...maximum : nil
        return Metrics(isCompactLayout: compact, height: height, portraitResizeRange: range)
    }
}

enum KeyboardResizePolicy {
    static func toggledHeight(current: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat? {
        guard let height = clampedHeight(current, in: range, rounded: false) else { return nil }
        let midpoint = range.lowerBound + (range.upperBound - range.lowerBound) / 2
        return height < midpoint ? range.upperBound : range.lowerBound
    }

    static func clampedHeight(_ value: CGFloat, in range: ClosedRange<CGFloat>, rounded: Bool = true) -> CGFloat? {
        guard value.isFinite, range.lowerBound.isFinite, range.upperBound.isFinite,
              range.lowerBound > 0 else { return nil }
        let bounded = min(range.upperBound, max(range.lowerBound, value))
        // Round first, then clamp again: a fractional scene cap is still a
        // strict bound even when it is narrower than one point.
        return min(range.upperBound, max(range.lowerBound, rounded ? bounded.rounded() : bounded))
    }

    static func target(startHeight: CGFloat, translationY: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat? {
        guard let start = clampedHeight(startHeight, in: range, rounded: false), translationY.isFinite else { return nil }
        let value = start - translationY
        if value == .infinity { return range.upperBound }
        if value == -.infinity { return range.lowerBound }
        return clampedHeight(value, in: range)
    }

    static func initialPanCorrection(currentY: CGFloat, touchDownY: CGFloat?, translationY: CGFloat) -> CGFloat? {
        guard currentY.isFinite, translationY.isFinite else { return nil }
        guard let touchDownY else { return 0 }
        guard touchDownY.isFinite else { return nil }
        let value = currentY - touchDownY - translationY
        return value.isFinite ? value : nil
    }

    static func panDelta(translationY: CGFloat, initialCorrection: CGFloat) -> CGFloat? {
        guard translationY.isFinite, initialCorrection.isFinite else { return nil }
        let value = translationY + initialCorrection
        return value.isFinite ? value : nil
    }
}

/// A transient drag must not replace the user's saved height merely because
/// the current scene caps its visible height. Only a successful finish commits.
struct KeyboardResizeSession {
    let startHeight: CGFloat
    private(set) var preferredHeight: CGFloat
    private var finished = false

    init?(preferredHeight: CGFloat, visibleHeight: CGFloat?, fallbackHeight: CGFloat,
          range: ClosedRange<CGFloat>) {
        guard preferredHeight.isFinite, preferredHeight > 0 else { return nil }
        let visible = visibleHeight.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? fallbackHeight
        guard let start = KeyboardResizePolicy.clampedHeight(visible, in: range, rounded: false) else { return nil }
        self.startHeight = start
        self.preferredHeight = preferredHeight
    }

    func target(translationY: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat? {
        guard !finished else { return nil }
        return KeyboardResizePolicy.target(startHeight: startHeight, translationY: translationY, in: range)
    }

    mutating func finish(commitHeight: CGFloat?, range: ClosedRange<CGFloat>) -> CGFloat? {
        guard !finished else { return nil }
        finished = true
        guard let commitHeight, let height = KeyboardResizePolicy.clampedHeight(commitHeight, in: range) else { return nil }
        preferredHeight = height
        return height
    }
}

/// UTF-16 is the UIKit/Core Text boundary; edits always operate on complete
/// Swift Characters. These helpers do not read or edit the host's document.
enum KeyboardQueryPolicy {
    static let maximumCharacters = 100

    struct Edit: Equatable {
        let text: String
        let caretUTF16Offset: Int
        let caretCharacterOffset: Int
    }

    static func utf16Boundaries(in text: String) -> [Int] {
        var boundaries = [0]
        boundaries.reserveCapacity(text.count + 1)
        var offset = 0
        for character in text {
            offset += String(character).utf16.count
            boundaries.append(offset)
        }
        return boundaries
    }

    static func characterOffset(forUTF16Offset offset: Int, in text: String) -> Int {
        let boundaries = utf16Boundaries(in: text)
        let bounded = min(max(0, offset), text.utf16.count)
        var nearest = 0
        for index in boundaries.indices.dropFirst() {
            // Both operands are clamped to the string length before subtraction.
            if abs(boundaries[index] - bounded) < abs(boundaries[nearest] - bounded) { nearest = index }
        }
        return nearest
    }

    static func normalizedUTF16Offset(_ offset: Int, in text: String) -> Int {
        let boundaries = utf16Boundaries(in: text)
        return boundaries[characterOffset(forUTF16Offset: offset, in: text)]
    }

    static func utf16Offset(forCharacterOffset offset: Int, in text: String) -> Int {
        let boundaries = utf16Boundaries(in: text)
        return boundaries[min(max(0, offset), boundaries.count - 1)]
    }

    static func nearestVisualBoundary(to x: CGFloat, boundaries: [Int], offset: (Int) -> CGFloat) -> Int {
        guard x.isFinite else { return boundaries.first ?? 0 }
        var result = boundaries.first ?? 0
        var distance = CGFloat.infinity
        for boundary in boundaries {
            let position = offset(boundary)
            guard position.isFinite else { continue }
            let candidate = abs(position - x)
            if candidate < distance { result = boundary; distance = candidate }
        }
        return result
    }

    static func inserting(_ insertion: String, into text: String, caretUTF16Offset: Int,
                          maximumCharacters limit: Int = maximumCharacters) -> Edit {
        let cursor = characterOffset(forUTF16Offset: caretUTF16Offset, in: text)
        let available = max(0, limit) > text.count ? max(0, limit) - text.count : 0
        let accepted = String(insertion.prefix(available))
        guard !accepted.isEmpty else { return edit(text: text, characterOffset: cursor) }
        var result = text
        let index = result.index(result.startIndex, offsetBy: cursor)
        let insertionEnd = result[..<index].utf16.count + accepted.utf16.count
        result.insert(contentsOf: accepted, at: index)
        return edit(text: result, followingUTF16Offset: insertionEnd)
    }

    static func deletingBackward(from text: String, caretUTF16Offset: Int) -> Edit {
        let cursor = characterOffset(forUTF16Offset: caretUTF16Offset, in: text)
        guard cursor > 0 else { return edit(text: text, characterOffset: 0) }
        var result = text
        let end = result.index(result.startIndex, offsetBy: cursor)
        let start = result.index(before: end)
        let deletionStart = result[..<start].utf16.count
        result.removeSubrange(start..<end)
        return edit(text: result, followingUTF16Offset: deletionStart)
    }

    private static func edit(text: String, characterOffset: Int) -> Edit {
        Edit(text: text, caretUTF16Offset: utf16Offset(forCharacterOffset: characterOffset, in: text),
             caretCharacterOffset: characterOffset)
    }

    private static func edit(text: String, followingUTF16Offset offset: Int) -> Edit {
        let boundaries = utf16Boundaries(in: text)
        let bounded = min(max(0, offset), text.utf16.count)
        let cursor = boundaries.firstIndex(where: { $0 >= bounded }) ?? boundaries.count - 1
        return Edit(text: text, caretUTF16Offset: boundaries[cursor], caretCharacterOffset: cursor)
    }
}

enum KeyboardQueryViewportPolicy {
    static func pixelAligned(_ value: CGFloat, scale: CGFloat, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> CGFloat {
        guard value.isFinite else { return 0 }
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let pixels = value * scale
        guard pixels.isFinite else { return value }
        let aligned = pixels.rounded(rule) / scale
        return aligned.isFinite ? aligned : value
    }

    static func horizontalOffset(caretX: CGFloat, previousOffset: CGFloat, viewportWidth: CGFloat,
                                 contentWidth: CGFloat, scale: CGFloat) -> CGFloat {
        guard caretX.isFinite, viewportWidth.isFinite, viewportWidth > 0,
              contentWidth.isFinite, contentWidth >= 0 else { return 0 }
        let maximumOffset = max(0, contentWidth - viewportWidth)
        let x = min(max(0, caretX), contentWidth)
        if x >= contentWidth - 2 { return maximumOffset }
        let margin = min(8, viewportWidth / 4)
        var offset = previousOffset.isFinite ? min(max(0, previousOffset), maximumOffset) : 0
        if x < offset + margin { offset = x - margin }
        else if x + 2 > offset + viewportWidth - margin { offset = x + 2 - viewportWidth + margin }
        return min(max(0, pixelAligned(offset, scale: scale)), maximumOffset)
    }
}
