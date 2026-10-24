import CoreGraphics
import Foundation

// The movable cursor in the keyboard's text preview (design/preview-cursor
// rev. 2). Everything here is pure: the keyboard reads the host context,
// shapes the line with Core Text and calls
// `adjustTextPosition(byCharacterOffset:)`; these types decide what to send,
// when, and what the host's answer means. Offsets are UTF-16 code units of
// the cursor's line unless a name says otherwise.

/// How a host counts `adjustTextPosition(byCharacterOffset:)`: UIKit text
/// views and fields count UTF-16 code units, WebKit counts grapheme clusters
/// (docs/preview-cursor-findings.md, Q1).
enum KeyboardPreviewCursorUnit: String, Equatable, Sendable {
    case utf16, grapheme
}

enum KeyboardPreviewWritingDirection: Equatable, Sendable {
    case leftToRight, rightToLeft
}

/// The cursor's line as the host exposed it: the text after the last newline
/// before the cursor and up to the first newline after it, from at most
/// `contextLimit` characters either side.
struct KeyboardPreviewCursorLine: Equatable, Sendable {
    static let contextLimit = 96

    let text: String
    /// The host cursor.
    let caret: Int
    /// Grapheme cluster boundaries, ascending, from 0 to `length`.
    let boundaries: [Int]
    let direction: KeyboardPreviewWritingDirection
    /// Exposed text lies before the line (an earlier line, or context beyond
    /// `contextLimit`): the preview may show "…" there.
    let hiddenBefore: Bool
    let hiddenAfter: Bool
    /// A newline or the document start precedes `text`.
    let startsLine: Bool
    /// A newline or the document end follows `text`.
    let endsLine: Bool

    init(before: String?, after: String?, limit: Int = contextLimit) {
        let rawBefore = before ?? "", rawAfter = after ?? ""
        var head = Substring(rawBefore.suffix(max(0, limit)))
        var tail = Substring(rawAfter.prefix(max(0, limit)))
        var newlineBefore = false, newlineAfter = false
        if let index = head.lastIndex(where: \.isNewline) {
            head = head[head.index(after: index)...]
            newlineBefore = true
        }
        if let index = tail.firstIndex(where: \.isNewline) {
            tail = tail[..<index]
            newlineAfter = true
        }
        let clippedBefore = rawBefore.count > max(0, limit)
        let clippedAfter = rawAfter.count > max(0, limit)
        text = String(head) + String(tail)
        caret = head.utf16.count
        boundaries = Self.graphemeBoundaries(in: text)
        direction = Self.baseDirection(of: text)
        hiddenBefore = newlineBefore || clippedBefore
        hiddenAfter = newlineAfter || clippedAfter
        startsLine = newlineBefore || rawBefore.isEmpty
        endsLine = newlineAfter || rawAfter.isEmpty
    }

    var length: Int { text.utf16.count }
    var isEmpty: Bool { text.isEmpty }

    static func graphemeBoundaries(in text: String) -> [Int] {
        var result = [0]
        var offset = 0
        for character in text {
            offset += character.utf16.count
            result.append(offset)
        }
        return result
    }

    /// The first strong character decides (Unicode P2/P3, as a natural
    /// UITextField does); no strong character means left to right.
    static func baseDirection(of text: String) -> KeyboardPreviewWritingDirection {
        for scalar in text.unicodeScalars {
            if let direction = strongDirection(of: scalar) { return direction }
        }
        return .leftToRight
    }

    /// Letters (and the two directional marks) are strong; right-to-left
    /// letters are those of the Hebrew, Arabic, Syriac, Thaana, N'Ko and other
    /// right-to-left blocks. Digits, punctuation, marks and emoji are not.
    static func strongDirection(of scalar: Unicode.Scalar) -> KeyboardPreviewWritingDirection? {
        switch scalar.value {
        case 0x200E: return .leftToRight
        case 0x200F: return .rightToLeft
        default: break
        }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
            return isRightToLeftBlock(scalar.value) ? .rightToLeft : .leftToRight
        default:
            return nil
        }
    }

    private static func isRightToLeftBlock(_ value: UInt32) -> Bool {
        (0x0590...0x08FF).contains(value) || (0xFB1D...0xFDFF).contains(value) || (0xFE70...0xFEFF).contains(value)
            || (0x10800...0x10FFF).contains(value) || (0x1E800...0x1EFFF).contains(value)
    }

    func isBoundary(_ offset: Int) -> Bool { boundaries.contains(offset) }

    /// The boundary nearest `offset` (the earlier one on a tie).
    func nearestBoundary(to offset: Int) -> Int {
        var best = 0
        for boundary in boundaries where abs(boundary - offset) < abs(best - offset) { best = boundary }
        return best
    }

    func boundary(after offset: Int) -> Int? { boundaries.first { $0 > offset } }
    func boundary(before offset: Int) -> Int? { boundaries.last { $0 < offset } }

    /// Signed number of grapheme clusters between two offsets.
    func graphemeDistance(from start: Int, to end: Int) -> Int {
        if end >= start { return boundaries.filter { $0 > start && $0 <= end }.count }
        return -boundaries.filter { $0 >= end && $0 < start }.count
    }

    /// Where `count` clusters from `offset` lands, or nil beyond the line.
    func boundary(movingGraphemes count: Int, from offset: Int) -> Int? {
        if count >= 0 {
            let later = boundaries.filter { $0 > offset }
            return count == 0 ? offset : (count <= later.count ? later[count - 1] : nil)
        }
        let earlier = boundaries.filter { $0 < offset }
        return -count <= earlier.count ? earlier[earlier.count + count] : nil
    }

    /// The grapheme cluster ending at `offset`, if any.
    func character(endingAt offset: Int) -> String? {
        guard let start = boundary(before: offset), isBoundary(offset) else { return nil }
        let units = Array(text.utf16)
        return String(decoding: units[start..<offset], as: UTF16.self)
    }
}

/// One call to `adjustTextPosition(byCharacterOffset:)` and where it lands
/// under each way of counting.
struct KeyboardPreviewCursorMove: Equatable, Sendable {
    let offset: Int
    /// Landing if the host counts UTF-16 units; nil outside the line.
    let utf16Landing: Int?
    /// Landing if the host counts grapheme clusters; nil outside the line.
    let graphemeLanding: Int?
    /// The user's target this move works toward.
    let target: Int

    /// The landing the host's unit predicts; with no unit, the one landing
    /// both ways of counting agree on.
    func expectedLanding(unit: KeyboardPreviewCursorUnit?) -> Int? {
        switch unit {
        case .utf16: return utf16Landing
        case .grapheme: return graphemeLanding
        case nil: return utf16Landing == graphemeLanding ? utf16Landing : nil
        }
    }

    /// The move from `caret` to the boundary `target`. With the unit known it
    /// is exact. Unknown, the move is chosen so both ways of counting land on
    /// whole characters inside the exposed line and on different spots, so the
    /// host's answer tells them apart: UTF-16 exact first (UIKit is the common
    /// host), then grapheme exact, then any such offset; failing that, the
    /// grapheme count, which a UTF-16 host may stop short of, inside a
    /// cluster, before one correction.
    static func planned(in line: KeyboardPreviewCursorLine, from caret: Int, to target: Int,
                        unit: KeyboardPreviewCursorUnit?) -> KeyboardPreviewCursorMove? {
        guard target != caret else { return nil }
        let units = target - caret
        let clusters = line.graphemeDistance(from: caret, to: target)
        func move(_ offset: Int) -> KeyboardPreviewCursorMove {
            let landing = caret + offset
            return KeyboardPreviewCursorMove(offset: offset,
                utf16Landing: (0...line.length).contains(landing) ? landing : nil,
                graphemeLanding: line.boundary(movingGraphemes: offset, from: caret), target: target)
        }
        if units == clusters { return move(units) }
        switch unit {
        case .utf16: return move(units)
        case .grapheme: return move(clusters)
        case nil: break
        }
        let sign = units > 0 ? 1 : -1
        let magnitudes = [abs(units), abs(clusters)] + Array(abs(clusters)...abs(units)).sorted {
            abs(caret + sign * $0 - target) < abs(caret + sign * $1 - target)
        }
        for magnitude in magnitudes {
            let candidate = move(sign * magnitude)
            if let utf16 = candidate.utf16Landing, line.isBoundary(utf16),
               let grapheme = candidate.graphemeLanding, grapheme != utf16 { return candidate }
        }
        return move(clusters)
    }
}

/// What the host did with a move, read from the context it exposes afterwards.
enum KeyboardPreviewCursorOutcome: Equatable, Sendable {
    /// The cursor is at this offset of the line the move started in;
    /// `unit` is what the landing proves about the host, if anything.
    case landed(Int, unit: KeyboardPreviewCursorUnit?)
    /// The cursor did not move (apps ignore overshoots).
    case ignored
    /// The new context can't be placed in the old line, or fits several spots.
    case unconfirmed

    /// Every offset of `old` where the cursor of `new` can be: the new text
    /// before and after the cursor match the old line around it, as far as
    /// both reach. A line known to start or end at a newline (or the document
    /// edge) can't gain or lose text on that side.
    static func candidates(of new: KeyboardPreviewCursorLine, in old: KeyboardPreviewCursorLine) -> [Int] {
        let oldUnits = Array(old.text.utf16), newUnits = Array(new.text.utf16)
        let before = Array(newUnits[..<new.caret]), after = Array(newUnits[new.caret...])
        return (0...oldUnits.count).filter { position in
            let rest = oldUnits.count - position
            if old.startsLine && before.count > position || new.startsLine && position > before.count { return false }
            if old.endsLine && after.count > rest || new.endsLine && rest > after.count { return false }
            let lead = min(before.count, position), trail = min(after.count, rest)
            for index in 0..<lead where !sameUnit(oldUnits[position - lead + index], before[before.count - lead + index]) {
                return false
            }
            for index in 0..<trail where !sameUnit(oldUnits[position + index], after[index]) { return false }
            return true
        }
    }

    /// Equal UTF-16 units, or U+FFFD against a surrogate: a cursor between
    /// surrogates comes back as replacement characters.
    static func sameUnit(_ a: UInt16, _ b: UInt16) -> Bool {
        a == b || (a == 0xFFFD && (0xD800...0xDFFF).contains(b)) || (b == 0xFFFD && (0xD800...0xDFFF).contains(a))
    }

    /// Reads the landing of `move`, sent from `old.caret`, from `new`.
    static func reading(_ move: KeyboardPreviewCursorMove, from old: KeyboardPreviewCursorLine,
                        to new: KeyboardPreviewCursorLine) -> KeyboardPreviewCursorOutcome {
        let spots = candidates(of: new, in: old)
        let utf16 = move.utf16Landing.map { spots.contains($0) } ?? false
        let grapheme = move.graphemeLanding.map { spots.contains($0) } ?? false
        if move.utf16Landing != move.graphemeLanding {
            if utf16 && !grapheme { return .landed(move.utf16Landing!, unit: proof(move.utf16Landing!, old, .utf16)) }
            if grapheme && !utf16 { return .landed(move.graphemeLanding!, unit: .grapheme) }
            if utf16 { return .unconfirmed }
        } else if utf16 {
            return .landed(move.utf16Landing!, unit: proof(move.utf16Landing!, old, nil))
        }
        if spots.contains(old.caret) { return .ignored }
        guard spots.count == 1 else { return .unconfirmed }
        return .landed(spots[0], unit: proof(spots[0], old, nil))
    }

    /// Only a host counting UTF-16 units can stop inside a cluster.
    private static func proof(_ landing: Int, _ line: KeyboardPreviewCursorLine,
                              _ otherwise: KeyboardPreviewCursorUnit?) -> KeyboardPreviewCursorUnit? {
        line.isBoundary(landing) ? otherwise : .utf16
    }
}

/// One host field's preview cursor: the confirmed line, the target the
/// preview caret shows, and the single move in flight. The host gets one
/// move at a time; the next is computed from the confirmed context after the
/// host's text-change callback (or the confirmation timeout), coalesced to
/// the latest target. Calibration happens only inside a move the user asked
/// for; a target gets at most one correction, otherwise the preview shows the
/// real position.
struct KeyboardPreviewCursorSession: Equatable, Sendable {
    static let confirmationTimeout: TimeInterval = 0.1
    static let settleRereadDelay: TimeInterval = 0.3
    /// Moves toward one line edge before giving up (each exposes more text).
    static let maximumEdgeChunks = 64

    enum Goal: Equatable, Sendable { case lineStart, lineEnd }

    enum SettleReason: Equatable, Sendable {
        /// The host cursor is on the target.
        case reached
        /// The host ignored the move.
        case ignored
        /// The landing can't be confirmed, or a correction missed.
        case unconfirmed
    }

    enum Step: Equatable, Sendable {
        case none
        /// Call `adjustTextPosition(byCharacterOffset:)` with this offset.
        case send(Int)
        /// Nothing is in flight; the preview shows the host's cursor.
        case settled(SettleReason)
    }

    struct Pending: Equatable, Sendable {
        let move: KeyboardPreviewCursorMove
        let line: KeyboardPreviewCursorLine
        let isCorrection: Bool
    }

    private(set) var line: KeyboardPreviewCursorLine
    private(set) var unit: KeyboardPreviewCursorUnit?
    private(set) var pending: Pending?
    private(set) var goal: Goal?
    /// The target while a move is in flight.
    private var aimed = 0
    private var edgeChunks = 0

    init(line: KeyboardPreviewCursorLine, unit: KeyboardPreviewCursorUnit? = nil) {
        self.line = line
        self.unit = unit
    }

    /// The preview caret's target while a move is under way.
    var target: Int? { pending == nil ? nil : aimed }
    /// Where the preview draws its caret.
    var displayedCaret: Int { target ?? line.caret }
    var isMoving: Bool { pending != nil }

    /// A tap, drag, edge step or adjustable action: the nearest boundary to
    /// `offset` becomes the target. While a move is in flight it only
    /// replaces the target; the next move goes after confirmation.
    mutating func request(_ offset: Int) -> Step {
        goal = nil
        return aim(at: offset)
    }

    /// VoiceOver's "Move to beginning/end of line": moves by the exposed
    /// text, waits for confirmation and repeats until the line edge.
    mutating func requestLineEdge(_ edge: Goal) -> Step {
        goal = edge
        edgeChunks = 0
        return aim(at: edge == .lineStart ? 0 : line.length)
    }

    private mutating func aim(at offset: Int) -> Step {
        let snapped = line.nearestBoundary(to: min(max(0, offset), line.length))
        guard pending == nil else { aimed = snapped; return .none }
        return send(from: line, toward: snapped, isCorrection: false)
    }

    private mutating func send(from line: KeyboardPreviewCursorLine, toward target: Int, isCorrection: Bool) -> Step {
        guard let move = KeyboardPreviewCursorMove.planned(in: line, from: line.caret, to: target, unit: unit) else {
            return settle(.reached)
        }
        aimed = target
        pending = Pending(move: move, line: line, isCorrection: isCorrection)
        return .send(move.offset)
    }

    private mutating func settle(_ reason: SettleReason) -> Step {
        pending = nil
        if reason != .reached { goal = nil }
        return .settled(reason)
    }

    /// Whether `new` shows any change from the line the move started in.
    /// Until it does (and before the timeout), a callback is stale.
    func hasChanged(_ new: KeyboardPreviewCursorLine) -> Bool {
        guard let pending else { return true }
        return new != pending.line
    }

    /// The host confirmed (text-change callback with a changed context) or
    /// the confirmation timeout passed: read the landing, learn the unit,
    /// carry the target into the new line and send the next move.
    mutating func confirm(_ new: KeyboardPreviewCursorLine) -> Step {
        guard let pending else { line = new; return .none }
        let outcome = KeyboardPreviewCursorOutcome.reading(pending.move, from: pending.line, to: new)
        line = new
        guard case let .landed(landing, learned) = outcome else {
            return settle(outcome == .ignored ? .ignored : .unconfirmed)
        }
        if let learned { unit = learned }
        let wanted = aimed
        let carried = new.caret + (wanted - landing)
        guard (0...new.length).contains(carried), new.isBoundary(carried),
              Self.sameText(pending.line, landing, wanted, new, new.caret, carried) else { return settle(.unconfirmed) }
        if carried == new.caret {
            if let goal, edgeChunks < Self.maximumEdgeChunks, new.caret != (goal == .lineStart ? 0 : new.length) {
                edgeChunks += 1
                return send(from: new, toward: goal == .lineStart ? 0 : new.length, isCorrection: false)
            }
            return settle(.reached)
        }
        // Still short of the same target: this send is the one correction.
        let retry = wanted == pending.move.target
        if retry && pending.isCorrection { return settle(.unconfirmed) }
        return send(from: new, toward: carried, isCorrection: retry)
    }

    /// A context read with nothing in flight (typing, the app's own change,
    /// the settle re-read): the preview shows the host cursor.
    mutating func refresh(_ new: KeyboardPreviewCursorLine) {
        guard pending == nil else { return }
        line = new
    }

    /// Forget the move in flight (the app changed the selection, the field
    /// changed, the keyboard went away, or the keyboard typed).
    mutating func cancel(_ new: KeyboardPreviewCursorLine) {
        pending = nil
        goal = nil
        line = new
    }

    /// The same units between two spots of two lines (U+FFFD matches a
    /// surrogate, as in `KeyboardPreviewCursorOutcome.candidates`).
    private static func sameText(_ a: KeyboardPreviewCursorLine, _ a0: Int, _ a1: Int,
                                 _ b: KeyboardPreviewCursorLine, _ b0: Int, _ b1: Int) -> Bool {
        let first = Array(a.text.utf16)[min(a0, a1)..<max(a0, a1)]
        let second = Array(b.text.utf16)[min(b0, b1)..<max(b0, b1)]
        return first.elementsEqual(second, by: KeyboardPreviewCursorOutcome.sameUnit)
    }
}

/// Fixed rules of the preview cursor: typing protection, the edge zones,
/// selection guard, hit testing, horizontal placement and announcements.
enum KeyboardPreviewCursorPolicy {
    static let edgeMargin: CGFloat = 24
    static let ellipsisCapWidth: CGFloat = 18
    static let tapSlop: CGFloat = 10
    /// A touch beginning this soon after a key touch-up is ignored.
    static let keyQuietPeriod: TimeInterval = 0.3
    static let slowStepInterval: TimeInterval = 0.08
    static let fastStepInterval: TimeInterval = 0.04
    static let fastStepDelay: TimeInterval = 1.0
    static let accessibilityLabel = "Text preview"
    static let accessibilityHint = "Tap or drag in the text to move the cursor. Swipe up or down to move by one character."
    static let moveToLineStartName = "Move to beginning of line"
    static let moveToLineEndName = "Move to end of line"

    /// Typing protection (§5): no key held, and the last key touch-up at
    /// least `keyQuietPeriod` ago.
    static func acceptsTouch(at time: TimeInterval, lastKeyRelease: TimeInterval?, keysDown: Int) -> Bool {
        guard keysDown == 0 else { return false }
        guard let lastKeyRelease else { return true }
        return time - lastKeyRelease >= keyQuietPeriod
    }

    /// §6: the preview moves the cursor only in a shared, non-secure line
    /// with no selection in the app and no panel over the row.
    static func isInteractive(line: KeyboardPreviewCursorLine, contextShared: Bool, hasSelection: Bool,
                              isSecure: Bool, panelOpen: Bool) -> Bool {
        contextShared && !line.isEmpty && !hasSelection && !isSecure && !panelOpen
    }

    /// 80 ms per step, 40 ms after one second of continuous stepping.
    static func stepInterval(afterStepping elapsed: TimeInterval) -> TimeInterval {
        elapsed >= fastStepDelay ? fastStepInterval : slowStepInterval
    }

    enum Edge: Equatable, Sendable { case left, right }

    /// The margin line on a side with a "…" cap (rev. 4): `edgeMargin`
    /// inside the cap's inner edge, 42 pt from the text area edge.
    static let cappedMargin: CGFloat = ellipsisCapWidth + edgeMargin

    /// The edge zone under `x` in a text area `width` wide: up to the margin
    /// line on a capped side (cap included), `edgeMargin` on an uncapped one,
    /// so the caret never jumps back while the line scrolls (§4).
    static func edge(at x: CGFloat, width: CGFloat, caps: (left: Bool, right: Bool) = (false, false)) -> Edge? {
        if x < (caps.left ? cappedMargin : edgeMargin) { return .left }
        if x > width - (caps.right ? cappedMargin : edgeMargin) { return .right }
        return nil
    }

    /// Reading order toward a visual edge: in a left-to-right line the right
    /// edge is next; mirrored in a right-to-left line.
    static func stepsForward(toward edge: Edge, in direction: KeyboardPreviewWritingDirection) -> Bool {
        (edge == .right) == (direction == .leftToRight)
    }

    /// One whole character from `offset` in reading order, inside the line.
    static func steppedTarget(in line: KeyboardPreviewCursorLine, from offset: Int, forward: Bool) -> Int? {
        forward ? line.boundary(after: offset) : line.boundary(before: offset)
    }

    /// The boundary whose primary caret position is nearest `x` (§3: also
    /// decides between the two caret spots at a direction boundary).
    static func nearestBoundary(to x: CGFloat, among candidates: [(offset: Int, x: CGFloat)]) -> Int? {
        var best: (offset: Int, distance: CGFloat)?
        for candidate in candidates where candidate.x.isFinite {
            let distance = abs(candidate.x - x)
            if best == nil || distance < best!.distance { best = (candidate.offset, distance) }
        }
        return best?.offset
    }

    /// Which edges show "…": the line is clipped there, or exposed text lies
    /// beyond the line on that side (logical before is left in a
    /// left-to-right line).
    static func ellipsisEdges(offset: CGFloat, lineWidth: CGFloat, width: CGFloat,
                              line: KeyboardPreviewCursorLine) -> (left: Bool, right: Bool) {
        let hidden = hiddenSides(of: line)
        let clippedLeft = offset > 0.5
        let clippedRight = offset + width < lineWidth - 0.5
        return (clippedLeft || hidden.left, clippedRight || hidden.right)
    }

    /// Exposed text beyond the line on each visual side.
    static func hiddenSides(of line: KeyboardPreviewCursorLine) -> (left: Bool, right: Bool) {
        line.direction == .leftToRight ? (line.hiddenBefore, line.hiddenAfter) : (line.hiddenAfter, line.hiddenBefore)
    }

    /// The line x at the text area's left edge. A line that fits is aligned
    /// to its start side; a wider one keeps `previous`, moving only as far as
    /// needed to keep the caret inside [L, R] (§2 rev. 4): on a side left
    /// with a "…" cap the margin line `cappedMargin` from the edge, on a side
    /// that shows the line's end uncapped the edge itself (x 1 or W − 1).
    /// `hidden` is exposed text beyond the line on each visual side, which
    /// keeps that side capped.
    static func scrollOffset(caretX: CGFloat, previous: CGFloat, lineWidth: CGFloat, width: CGFloat,
                             direction: KeyboardPreviewWritingDirection,
                             hidden: (left: Bool, right: Bool) = (false, false)) -> CGFloat {
        guard lineWidth > width else { return direction == .leftToRight ? 0 : lineWidth - width }
        var offset = previous
        if caretX - offset < cappedMargin {
            let onLine = caretX - cappedMargin
            if onLine > 0.5 || hidden.left {
                offset = onLine
            } else {
                // The line's start comes into view with no cap: limit x 1.
                offset = min(offset > 0.5 ? 0 : offset, caretX - 1)
            }
        }
        if caretX - offset > width - cappedMargin {
            let onLine = caretX - (width - cappedMargin)
            if onLine + width < lineWidth - 0.5 || hidden.right {
                offset = onLine
            } else {
                // The line's end comes into view with no cap: limit W − 1.
                let end = lineWidth - width
                offset = max(offset + width < lineWidth - 0.5 ? end : offset, caretX - (width - 1))
            }
        }
        return min(max(offset, -1), lineWidth - width + 1)
    }

    /// §2 reset after the app moved the cursor itself: as much text before
    /// the cursor as fits, the cursor at min(width(before),
    /// W − min(width(after), width("…"))) from the start side.
    static func resetOffset(caretX: CGFloat, lineWidth: CGFloat, width: CGFloat,
                            direction: KeyboardPreviewWritingDirection, ellipsisWidth: CGFloat) -> CGFloat {
        guard lineWidth > width else { return direction == .leftToRight ? 0 : lineWidth - width }
        let ltr = direction == .leftToRight
        let before = ltr ? caretX : lineWidth - caretX
        let windowX = min(before, width - min(lineWidth - before - 0, ellipsisWidth))
        let mirrored = min(max(before - windowX, -1), lineWidth - width + 1)
        return ltr ? mirrored : lineWidth - width - mirrored
    }

    /// Where the old line's text sits in the new one, so the shared text
    /// stays put on screen when the context changes: the new line's first
    /// units are found in the old line (or the old line's first units in the
    /// new one when the new line starts earlier). Returns (old, new) offsets
    /// of the same text.
    static func alignment(from old: String, to new: String, probeLength: Int = 12) -> (old: Int, new: Int)? {
        let oldUnits = Array(old.utf16), newUnits = Array(new.utf16)
        func find(_ needle: ArraySlice<UInt16>, in haystack: [UInt16]) -> Int? {
            guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
            return (0...(haystack.count - needle.count)).first { haystack[$0..<($0 + needle.count)].elementsEqual(needle) }
        }
        if let index = find(newUnits.prefix(probeLength), in: oldUnits) { return (index, 0) }
        if let index = find(oldUnits.prefix(probeLength), in: newUnits) { return (0, index) }
        return nil
    }

    /// The characters fully inside the visible span, split at the caret, as
    /// the frozen excerpt Copy Image and Inspect use (§7). `characters` are
    /// the line's grapheme clusters in logical order with their drawn
    /// extents in text-area coordinates.
    /// The part of the text area the row draws: between the caps, and on a
    /// side with "…" only from the first to the last character shown whole,
    /// so no sliver of a cut glyph sits beside the cap. These are exactly
    /// the characters `visibleExcerpt` takes for Copy Image and Inspect.
    /// `ink` (parallel to `characters`, nil for blank ones) is each glyph's
    /// drawn extent: italic ink overhangs the advance, so a hidden
    /// neighbour's ink is clipped too, as far as the shown ink allows.
    static func drawnSpan(characters: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)],
                          visible: ClosedRange<CGFloat>, caps: (left: Bool, right: Bool),
                          ink: [ClosedRange<CGFloat>?] = []) -> ClosedRange<CGFloat> {
        guard caps.left || caps.right else { return visible }
        let isShown = characters.map {
            $0.minX >= visible.lowerBound - 0.5 && $0.maxX <= visible.upperBound + 0.5
        }
        let shown = characters.indices.filter { isShown[$0] }
        guard let first = shown.map({ characters[$0].minX }).min(),
              let last = shown.map({ characters[$0].maxX }).max() else {
            return visible.lowerBound...visible.lowerBound
        }
        func inkOf(_ index: Int) -> ClosedRange<CGFloat>? {
            guard index < ink.count, let extent = ink[index],
                  extent.lowerBound.isFinite, extent.upperBound.isFinite else { return nil }
            return extent
        }
        let shownInk = shown.compactMap(inkOf)
        let hidden = characters.indices.filter { !isShown[$0] }
        func middle(_ index: Int) -> CGFloat { (characters[index].minX + characters[index].maxX) / 2 }
        var low = visible.lowerBound, high = visible.upperBound
        if caps.left {
            // From the first whole glyph's ink, but over any hidden ink.
            let shownStart = min(first, shownInk.map(\.lowerBound).min() ?? first)
            low = max(visible.lowerBound, shownStart)
            if let spill = hidden.filter({ middle($0) < first }).compactMap(inkOf).map(\.upperBound).max() {
                low = max(low, min(spill + inkPadding, shownInk.map(\.lowerBound).min() ?? .infinity))
            }
        }
        if caps.right {
            let shownEnd = max(last, shownInk.map(\.upperBound).max() ?? last)
            high = min(visible.upperBound, shownEnd)
            if let spill = hidden.filter({ middle($0) > last }).compactMap(inkOf).map(\.lowerBound).min() {
                high = min(high, max(spill - inkPadding, shownInk.map(\.upperBound).max() ?? -.infinity))
            }
        }
        return low...max(low, high)
    }

    /// Antialiasing beyond a glyph's outline bounds.
    static let inkPadding: CGFloat = 1

    static func visibleExcerpt(line: KeyboardPreviewCursorLine, caret: Int,
                               characters: [(range: Range<Int>, minX: CGFloat, maxX: CGFloat)],
                               visible: ClosedRange<CGFloat>, ellipsis: String = "…")
        -> (before: String, after: String, beforeTruncated: Bool, afterTruncated: Bool) {
        let units = Array(line.text.utf16)
        var before = "", after = ""
        var beforeTruncated = line.hiddenBefore, afterTruncated = line.hiddenAfter
        for character in characters {
            let shown = character.minX >= visible.lowerBound - 0.5 && character.maxX <= visible.upperBound + 0.5
            let isBefore = character.range.upperBound <= caret
            let text = String(decoding: units[character.range], as: UTF16.self)
            if !shown {
                if isBefore { beforeTruncated = true } else { afterTruncated = true }
            } else if isBefore { before += text } else { after += text }
        }
        return ((beforeTruncated ? ellipsis : "") + before, after + (afterTruncated ? ellipsis : ""),
                beforeTruncated, afterTruncated)
    }

    /// §8 announcements after a move.
    static func announcement(line: KeyboardPreviewCursorLine, caret: Int) -> String {
        if caret == 0 { return "Beginning of line" }
        if caret == line.length { return "End of line" }
        let character = line.character(endingAt: caret) ?? ""
        let spoken: String
        switch character {
        case " ": spoken = "space"
        case "\t": spoken = "tab"
        default: spoken = character
        }
        return "Cursor after \(spoken)"
    }

    /// Whether the host cursor sits inside a grapheme cluster: the text
    /// either side joins into one character, or a surrogate pair came back
    /// split.
    static func isInsideCluster(before: String?, after: String?) -> Bool {
        repairOffset(before: before ?? "", after: after ?? "") != nil
    }

    /// The move that puts a cursor stuck inside a cluster on the nearer whole
    /// boundary, in UTF-16 units (only UTF-16 hosts stop inside clusters).
    static func repairOffset(before: String, after: String) -> Int? {
        guard let last = before.unicodeScalars.last, let first = after.unicodeScalars.first else { return nil }
        if last.value == 0xFFFD && first.value == 0xFFFD { return -1 }
        let tail = String(before.suffix(4)), head = String(after.prefix(4))
        let caret = tail.utf16.count
        let boundaries = KeyboardPreviewCursorLine.graphemeBoundaries(in: tail + head)
        if boundaries.contains(caret) { return nil }
        let backward = caret - boundaries.last(where: { $0 < caret })!
        let forward = boundaries.first(where: { $0 > caret })! - caret
        return forward < backward ? forward : -backward
    }
}

/// The preview caret blinks like UITextField's insertion point (§1a): solid
/// while anything happens (finger down, drag, edge step, a key press, a
/// VoiceOver move, any context change from the app) and for `idleDelay`
/// after the last of these, then blinking again from fully visible. Only
/// while the preview is live (keyboard shown, no panel open) and never with
/// Prefer Non-Blinking Cursor.
enum KeyboardPreviewCaretBlinkPolicy {
    static let idleDelay: TimeInterval = 0.5
    /// Visible 0.5 s, fade out 0.1 s, hidden 0.3 s, fade in 0.1 s.
    static let period: TimeInterval = 1.0
    /// A timer may fire this much early and still start blinking.
    static let timerSlack: TimeInterval = 0.02
    /// Opacity keyframes over one period, easeInOut between each pair.
    static let keyTimes: [Double] = [0, 0.5, 0.6, 0.9, 1]
    static let opacities: [Double] = [1, 1, 0, 0, 1]
    /// Reduce Motion: the same timing, switched on and off with no fades
    /// (discrete keyframes: each value holds until the next key time).
    static let discreteKeyTimes: [Double] = [0, 0.5, 0.9, 1]
    static let discreteOpacities: [Double] = [1, 0, 1]

    static func blinks(live: Bool, prefersNonBlinking: Bool, busy: Bool,
                       now: TimeInterval, lastActivity: TimeInterval) -> Bool {
        live && !prefersNonBlinking && !busy && now - lastActivity >= idleDelay - timerSlack
    }

    /// How long until an idle caret starts blinking.
    static func delayUntilBlinking(now: TimeInterval, lastActivity: TimeInterval) -> TimeInterval {
        max(0, idleDelay - (now - lastActivity))
    }

    /// The caret's opacity `elapsed` seconds into blinking, as the animation
    /// draws it: eased between keyframes, or hard on/off with Reduce Motion.
    static func opacity(blinkingFor elapsed: TimeInterval, reduceMotion: Bool = false) -> Double {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: period) / period
        if reduceMotion {
            return discreteOpacities[discreteKeyTimes.lastIndex { $0 <= phase }!]
        }
        let index = max(1, keyTimes.firstIndex { $0 >= phase }!)
        let t = (phase - keyTimes[index - 1]) / (keyTimes[index] - keyTimes[index - 1])
        let eased = t * t * (3 - 2 * t)
        return opacities[index - 1] + (opacities[index] - opacities[index - 1]) * eased
    }
}

/// The unit each host field counts in, learned from user moves and
/// remembered per document (newest kept when full).
struct KeyboardPreviewCursorUnitMemory: Equatable, Sendable {
    static let capacity = 32
    private(set) var entries: [(key: UUID, unit: KeyboardPreviewCursorUnit)] = []

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries.map(\.key) == rhs.entries.map(\.key) && lhs.entries.map(\.unit) == rhs.entries.map(\.unit)
    }

    func unit(for key: UUID?) -> KeyboardPreviewCursorUnit? {
        guard let key else { return nil }
        return entries.last { $0.key == key }?.unit
    }

    mutating func remember(_ unit: KeyboardPreviewCursorUnit, for key: UUID?) {
        guard let key else { return }
        entries.removeAll { $0.key == key }
        entries.append((key, unit))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }
}
