import Foundation

/// Fixed templates have no persisted height or interactive resize state.
enum KeyboardLayoutPolicy {
    /// The standard keyboard: the number row, three rows and the footer.
    static let defaultHeight = KeyboardTypingLayoutPolicy.regularKeyHeight * 5 + 30
    /// How much taller an iPhone keyboard in portrait is while a panel, such
    /// as Copy Image, covers it.
    static let panelExtraHeight: CGFloat = 96
    /// iPhone landscape (compact height) search: Apple's landscape key rows,
    /// 32 points with 6 between rows, under a 34-point search row that also
    /// carries the results as chips. With the system's bottom inset the
    /// keyboard stays within 255 points, leaving the app at least 147 of 402.
    static let compactSearchKeyHeight: CGFloat = 32
    static let compactSearchRowSpacing: CGFloat = 6
    static let compactSearchBarHeight: CGFloat = 34
    struct Metrics {
        let isCompactLayout: Bool
        let height: CGFloat
        let typingKeyHeight: CGFloat
    }
    /// `keyRows` is the typing rows above the footer: the main keyboard
    /// arrangement's, at least three. `previewImagePanel` asks for the extra panel
    /// height, which an iPhone in portrait gets within the same scene cap;
    /// keys keep the height they type with.
    static func metrics(viewWidth: CGFloat, displaySize: CGSize?, sceneHeight: CGFloat?, isPad: Bool,
                        compactVertical: Bool, keyRows: Int = MainKeyboardArrangement.maximumRows,
                        searching: Bool = false, browsing: Bool = false, showsTextPreview: Bool = false,
                        previewImagePanel: Bool = false) -> Metrics {
        let size = displaySize.flatMap { value -> CGSize? in
            guard value.width.isFinite, value.height.isFinite, value.width > 0, value.height > 0 else { return nil }
            return value
        }
        let compact: Bool
        if isPad { compact = false }
        else if let size, viewWidth.isFinite, viewWidth > 0 {
            let short = min(size.width, size.height)
            compact = viewWidth > short && viewWidth - short > max(24, short * 0.1)
        } else { compact = compactVertical }
        let key = KeyboardTypingLayoutPolicy.typingKeyHeight(availableWidth: viewWidth - 16, isPad: isPad)
        let spacing: CGFloat = isPad && viewWidth.isFinite && viewWidth >= 666 ? 6 : 4
        // The optional text preview is one more row with a gap below it,
        // while typing and searching but not while browsing.
        let preview = showsTextPreview && !browsing
        let chrome: CGFloat = preview ? 22 : 18
        if searching && compact && !isPad { return compactSearchMetrics(sceneHeight: sceneHeight, preview: preview) }
        // Search owns four full-height input rows, a result row above them
        // tall enough for a glyph, its code point and a three-line name, its
        // toolbar and footer, instead of shrinking keys.
        // Each typing row above the footer adds a row and a gap.
        let keys = CGFloat(max(1, keyRows))
        // Browsing Unicode without keys shows two more rows of characters.
        let rows: CGFloat = (searching ? 7.75 : keys + 1 + (browsing ? 2 : 0)) + (preview ? 1 : 0)
        let gaps: CGFloat = searching ? 4 : keys - 1
        let rowSpacing: CGFloat = searching ? 4 : spacing
        let target = key * rows + rowSpacing * gaps + chrome
        // Keep all rows and the footer equal if a host supplies a short scene.
        let sceneCap = sceneHeight.flatMap { $0.isFinite && $0 > chrome + rowSpacing * gaps + rows
            ? max(chrome + rowSpacing * gaps + rows, $0 * 0.85) : nil }
        let typing = min(target, sceneCap ?? target)
        // The extra height belongs to the panel alone; it never shrinks keys.
        let grown = target + (previewImagePanel && !isPad && !compact ? panelExtraHeight : 0)
        let height = min(grown, sceneCap ?? grown)
        let actualKey = max(1, (typing - chrome - rowSpacing * gaps) / rows)
        return Metrics(isCompactLayout: compact, height: height, typingKeyHeight: min(key, actualKey))
    }

    /// Four query rows and the footer at `compactSearchKeyHeight`, 6 points
    /// apart and from the search row; 4 points above it and 6 below the
    /// footer, as in every layout. The optional text preview is one more
    /// search-row height and a 4-point gap. A short scene shrinks only the keys.
    private static func compactSearchMetrics(sceneHeight: CGFloat?, preview: Bool) -> Metrics {
        let keyRows: CGFloat = 5
        let fixed = 4 + compactSearchBarHeight + (preview ? compactSearchBarHeight + 4 : 0) + compactSearchRowSpacing * keyRows + 6
        let target = fixed + compactSearchKeyHeight * keyRows
        let sceneCap = sceneHeight.flatMap { $0.isFinite && $0 > fixed + keyRows ? max(fixed + keyRows, $0 * 0.85) : nil }
        let height = min(target, sceneCap ?? target)
        return Metrics(isCompactLayout: true, height: height, typingKeyHeight: (height - fixed) / keyRows)
    }
}

enum KeyboardQueryPolicy {
    static let bottomRow = ["+", "z", "x", "c", "v", "b", "n", "m", "-"]

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
        // Boundaries always includes zero and the exact UTF-16 end. Select
        // the first following boundary directly, including an empty result.
        var cursor = 0
        for (index, boundary) in boundaries.enumerated() {
            cursor = index
            if boundary >= bounded { break }
        }
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

/// A horizontal gesture commits at most one neighboring symbol page.
enum KeyboardSymbolPagePolicy {
    static let maximumPages = 17
    static func index(offset: CGFloat, width: CGFloat, count: Int, startingAt start: Int? = nil) -> Int? {
        guard offset.isFinite, width.isFinite, width > 0, (1...maximumPages).contains(count) else { return nil }
        let ratio = offset / width
        guard ratio.isFinite else { return nil }
        let index = Int(min(CGFloat(count - 1), max(0, ratio.rounded(.toNearestOrAwayFromZero))))
        guard let start else { return index }
        guard (0..<count).contains(start) else { return nil }
        return min(start + 1, max(start - 1, index))
    }
}
