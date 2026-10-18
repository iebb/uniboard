import Foundation

enum KeyboardAutomaticCapitalization: CaseIterable, Sendable {
    case none, words, sentences, allCharacters
}

/// Reversible case suggestions for host typing. UIKit input-trait mapping and
/// manual Shift overrides belong to the caller; Unicode queries stay literal.
enum KeyboardEnglishInputPolicy {
    static let maximumContextScalars = 128

    static func shouldCapitalize(mode: KeyboardAutomaticCapitalization, before: String?) -> Bool {
        switch mode {
        case .none: return false
        case .allCharacters: return true
        case .words, .sentences: break
        }
        // A document proxy commonly reports nil at the start of an editor.
        // Suggesting a capital is reversible; destructive edits never infer
        // that a missing context is an empty document.
        guard let before else { return true }
        let context = boundedScalars(before)
        guard !context.isEmpty else { return true }
        if mode == .words { return beginsWord(after: context) }

        var index = context.count
        var hasWhitespace = false
        while index > 0 {
            let scalar = context[index-1]
            if isLineBreak(scalar) { return true }
            if scalar.properties.isWhitespace {
                hasWhitespace = true
                index -= 1
            } else if isQuoteOrBracket(scalar) {
                index -= 1
            } else {
                break
            }
        }
        // Leading whitespace and opening quotation marks still begin text.
        guard index > 0 else { return true }
        // Requiring a word separator avoids capitalization inside decimals,
        // domains and punctuation typed before its following Space.
        return hasWhitespace && isSentenceTerminator(context[index-1])
    }

    fileprivate static func boundedScalars(_ context: String) -> [Unicode.Scalar] {
        Array(context.unicodeScalars.suffix(maximumContextScalars))
    }

    private static func beginsWord(after context: [Unicode.Scalar]) -> Bool {
        var index = context.count
        // A combining mark or join control continues its preceding word.
        while index > 0, isMark(context[index-1]) || isJoinControl(context[index-1]) {
            index -= 1
        }
        guard index > 0 else { return false }
        let last = context[index-1]
        if isWordBody(last) { return false }
        if last == "'" || last == "’" {
            index -= 1
            while index > 0, isMark(context[index-1]) { index -= 1 }
            return index == 0 || !isWordBody(context[index-1])
        }
        return true
    }

    fileprivate static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default: return false
        }
    }

    private static func isWordBody(_ scalar: Unicode.Scalar) -> Bool {
        isLetterOrNumber(scalar) || scalar.properties.generalCategory == .connectorPunctuation
    }

    fileprivate static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private static func isJoinControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x200C || scalar.value == 0x200D
    }

    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x000A...0x000D, 0x0085, 0x2028, 0x2029: return true
        default: return false
        }
    }

    fileprivate static func isClosingDelimiter(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\"" || scalar == "'" { return true }
        let category = scalar.properties.generalCategory
        return category == .closePunctuation || category == .finalPunctuation
    }

    private static func isQuoteOrBracket(_ scalar: Unicode.Scalar) -> Bool {
        if isClosingDelimiter(scalar) { return true }
        let category = scalar.properties.generalCategory
        return category == .openPunctuation || category == .initialPunctuation
    }

    private static func isSentenceTerminator(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0021, 0x002E, 0x003F, 0x061F, 0x2026, 0x203C, 0x2047...0x2049,
             0x3002, 0xFF01, 0xFF0E, 0xFF1F, 0xFF61:
            return true
        default: return false
        }
    }
}

struct KeyboardEnglishInputScope: Equatable, Sendable {
    let documentIdentifier: UUID
    /// The caller changes this token for query, layout, trait or input-mode
    /// transitions; equal trailing text does not make a different mode safe.
    let modeIdentifier: UUID
}

enum KeyboardSpaceTapAction: Equatable, Sendable {
    case insertSpace
    /// Delete precisely the verified preceding ASCII space, then insert ". ".
    case replacePreviousSpaceWithPeriod
}

/// Only deliberate Space taps enter this state machine. Reset on every known
/// intervening edit or mode change, including edits outside the bounded suffix.
/// The second tap verifies actual context; a failed first insertion cannot by
/// itself authorize deletion. No text or clock is read from global state.
struct KeyboardDoubleSpaceState: Sendable {
    static let doubleSpaceInterval: TimeInterval = 0.75

    private struct Pending: Sendable {
        let scope: KeyboardEnglishInputScope
        let timestamp: TimeInterval
        // Scalar equality is exact, unlike canonically equivalent String ==.
        let expectedContext: [Unicode.Scalar]
    }
    private var pending: Pending?

    mutating func reset() { pending = nil }

    mutating func spaceTap(before: String?, at timestamp: TimeInterval,
                           scope: KeyboardEnglishInputScope?, isQuery: Bool = false,
                           enabled: Bool = true) -> KeyboardSpaceTapAction {
        let previous = pending
        pending = nil
        guard enabled, !isQuery, let before, let scope,
              timestamp.isFinite, timestamp >= 0 else { return .insertSpace }
        let context = KeyboardEnglishInputPolicy.boundedScalars(before)
        if let previous {
            let elapsed = timestamp-previous.timestamp
            // Backward or equal clock readings cannot arm another sequence.
            guard elapsed.isFinite, elapsed > 0 else { return .insertSpace }
            if elapsed <= Self.doubleSpaceInterval, previous.scope == scope,
               context == previous.expectedContext, context.last == " " {
                return .replacePreviousSpaceWithPeriod
            }
        }
        guard eligibleWordEnding(context) else { return .insertSpace }
        let expected = Array((context + [" "]).suffix(KeyboardEnglishInputPolicy.maximumContextScalars))
        pending = Pending(scope: scope, timestamp: timestamp, expectedContext: expected)
        return .insertSpace
    }

    private func eligibleWordEnding(_ context: [Unicode.Scalar]) -> Bool {
        var index = context.count
        while index > 0, KeyboardEnglishInputPolicy.isClosingDelimiter(context[index-1]) { index -= 1 }
        while index > 0, KeyboardEnglishInputPolicy.isMark(context[index-1]) {
            // A keycap sequence is an emoji, not a number being punctuated.
            if context[index-1].value == 0x20E3 { return false }
            index -= 1
        }
        return index > 0 && KeyboardEnglishInputPolicy.isLetterOrNumber(context[index-1])
    }
}
