import Foundation

/// Destructive work requires a complete REPLACEMENT SCOPE, not the whole host
/// document: the entire locally typed target, observed token boundaries, and an
/// exact stable surrounding proxy window bound to document/mode. .verified may
/// be derived from ordinary-key provenance plus exact context growth at an
/// observed whitespace boundary; it must NEVER be inferred from a scanned word,
/// an empty left proxy window, or non-nil strings alone. Explicitly truncated
/// scopes remain ineligible. Missing context/selection is never treated as empty.
struct KeyboardCorrectionContext: Sendable {
    enum Completeness: Equatable, Sendable {
        case verified
        /// Raw proxy window: replacement-scope completeness not yet established.
        case unknownOrTruncated
        /// The caller knows context was cut/unavailable within the relevant scope.
        case knownTruncated
    }

    let before: String?
    let after: String?
    let selectedText: String?
    let scope: KeyboardEnglishInputScope?
    let completeness: Completeness

    fileprivate var isUsable: Bool {
        guard completeness == .verified, let before, let after,
              let selectedText, selectedText.isEmpty, scope != nil else { return false }
        return before.unicodeScalars.count <= 4096 && after.unicodeScalars.count <= 4096
    }

    /// Swift String == permits canonical equivalence; host edit guards must not.
    func exactlyMatches(_ other: Self) -> Bool {
        isUsable && other.isUsable && scope == other.scope
            && Self.equalScalars(before, other.before)
            && Self.equalScalars(after, other.after)
            && Self.equalScalars(selectedText, other.selectedText)
    }

    fileprivate static func equalScalars(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)): return lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
        case (.none, .none): return true
        default: return false
        }
    }

    fileprivate func replacingBefore(with text: String) -> Self {
        Self(before: text, after: after, selectedText: selectedText, scope: scope, completeness: completeness)
    }
}

struct KeyboardEnglishCorrectionOptions: Sendable {
    // Independent preferences, both opt-in. Autocorrection does not imply a strip.
    var suggestionsEnabled = false
    var autocorrectionEnabled = false
}

enum KeyboardCorrectionHostPermission: Equatable, Sendable {
    case permits, autocorrectionDisabled, literalField, unknown
}

enum KeyboardCorrectionInputOrigin: Equatable, Sendable {
    case ordinaryKey, customEntry, literalAction, unicodeAction, emoji, other
}

/// Provider values, not a vocabulary. Only a full-word OS misspelling can support
/// automatic confidence. Tests can inject these values without asserting OS quality.
struct KeyboardEnglishSpellingResult: Sendable {
    enum Availability: Equatable, Sendable { case available, dictionaryUnavailable }
    enum Spelling: Equatable, Sendable { case misspelledWholeWord, validWord, unknown }
    let word: String
    let availability: Availability
    let spelling: Spelling
    let rankedProposals: [String]
    /// False when the bounded provider omitted proposals: hidden ambiguity must
    /// never become a uniquely confident automatic replacement.
    let proposalsAreComplete: Bool
}

struct KeyboardCorrectionDecision: Sendable {
    let suggestions: [String]
    let replacementPlan: KeyboardGuardedReplacementPlan?
}

/// A value-only authorization, never an instruction to blindly loop deleteBackward.
/// Execution contract:
/// - Execute synchronously on the host-owning actor, without suspension.
/// - Before EVERY delete/insert, call the owning state's authorizesStep, re-read
///   document identity, mode, both contexts, selection and host traits; require
///   the corresponding step's exact snapshot and .permits (including
///   autocorrectionType != .no). An invalidated state revokes even an unchanged
///   snapshot; a retained plan alone is not a live execution capability.
/// - Observe/recheck each step's resulting context before continuing. Abort on
///   any mismatch, truncation, focus/selection/trait event or failed insertion.
/// - Invalidate the owning state on failure; never arm rollback for partial work.
/// UIKit hosts need independent existing identity/selection guards as well. These
/// snapshots cannot detect an unreported edit elsewhere outside proxy context.
struct KeyboardGuardedReplacementPlan: Sendable {
    struct Step: Sendable {
        enum Operation: Sendable { case deleteBackward, insertText(String) }
        let operation: Operation
        let expectedContext: KeyboardCorrectionContext
        let resultingContext: KeyboardCorrectionContext

        func isAuthorized(in context: KeyboardCorrectionContext,
                          hostPermission: KeyboardCorrectionHostPermission) -> Bool {
            hostPermission == .permits && expectedContext.exactlyMatches(context)
        }
    }

    let expectedContext: KeyboardCorrectionContext
    let graphemeDeleteCount: Int
    let replacementText: String
    let resultingContext: KeyboardCorrectionContext
    fileprivate let identifier: UInt64
    fileprivate let originalWord: String
    fileprivate let delimiter: String
    fileprivate let prefix: String

    /// Counts are Swift Characters, not UTF-16 or scalar deletion counts. Every
    /// deletable suffix is restricted to ASCII, so no Unicode prefix is touched.
    var steps: [Step] {
        guard var before = expectedContext.before else { return [] }
        var context = expectedContext
        var result: [Step] = []
        for _ in 0..<graphemeDeleteCount {
            before.removeLast()
            let next = context.replacingBefore(with: before)
            result.append(Step(operation: .deleteBackward, expectedContext: context, resultingContext: next))
            context = next
        }
        let next = context.replacingBefore(with: before + replacementText)
        result.append(Step(operation: .insertText(replacementText), expectedContext: context, resultingContext: next))
        return result
    }
}

/// All confidence derivation is independent of UIKit ranking or fixed examples.
/// This is English spelling help, not a Japanese/Chinese/Korean converter.
enum KeyboardAutocorrectionPolicy {
    static let maximumProposals = 12

    /// Establish ONLY the start of a local replacement scope. This does not
    /// authorize editing or scan/seed a host word. Caller must feed the FIRST
    /// ordinary key and EVERY following key through exact before/after growth
    /// checks before delimiter authorization. An existing left window may be a
    /// document suffix; seeing the immediate whitespace proves the target token
    /// starts here without needing the rest of the document. Empty left windows
    /// do not supply that proof. Selection must independently be known empty.
    static func locallyVerifiedWordStart(_ context: KeyboardCorrectionContext) -> KeyboardCorrectionContext? {
        guard context.completeness != .knownTruncated, let before = context.before,
              let after = context.after, context.selectedText == "", context.scope != nil,
              before.unicodeScalars.count <= 4096, after.unicodeScalars.count <= 4096,
              let boundary = before.last, isBoundary(boundary),
              after.first.map(isBoundary) ?? true else { return nil }
        return KeyboardCorrectionContext(before: before, after: after, selectedText: "",
                                         scope: context.scope, completeness: .verified)
    }

    /// Promote an actual observation ONLY after one ordinary ASCII-letter key
    /// grew the entire verified window exactly. Window shifts/truncation, scalar
    /// changes, missing context/selection and scope changes cannot be repaired
    /// by comparing only the word suffix.
    static func verifiedOrdinaryInsertion(_ text: String,
                                         before: KeyboardCorrectionContext,
                                         actualAfter: KeyboardCorrectionContext) -> KeyboardCorrectionContext? {
        guard before.isUsable, text.utf8.count == 1, text.utf8.allSatisfy(isLetter),
              actualAfter.completeness != .knownTruncated, let beforeText = before.before else { return nil }
        let promoted = KeyboardCorrectionContext(before: actualAfter.before, after: actualAfter.after,
                                                selectedText: actualAfter.selectedText,
                                                scope: actualAfter.scope, completeness: .verified)
        guard before.replacingBefore(with: beforeText + text).exactlyMatches(promoted) else { return nil }
        return promoted
    }

    static func isASCIIWord(_ word: String) -> Bool {
        let bytes = Array(word.utf8)
        return (3...32).contains(bytes.count) && bytes.allSatisfy(isLetter)
    }

    fileprivate static func isLetter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    fileprivate static func hasOrdinaryCase(_ word: String) -> Bool {
        let tail = word.utf8.dropFirst()
        return tail.allSatisfy { (97...122).contains($0) }
    }

    fileprivate static func isBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }

    /// Deliberately narrow delimiters. A period/slash/@/quote can extend a URL,
    /// email, identifier or code token, so these never trigger automatic edits.
    static func isAutomaticDelimiter(_ delimiter: String) -> Bool {
        [" ", "\n", "\t", "!", "?", ",", ";"].contains(delimiter)
    }

    static func suggestions(for result: KeyboardEnglishSpellingResult, rawWord: String) -> [String] {
        guard result.availability == .available,
              KeyboardCorrectionContext.equalScalars(result.word, rawWord) else { return [] }
        var seen = Set<String>()
        return result.rankedProposals.prefix(maximumProposals).compactMap { proposal in
            guard isASCIIWord(proposal), hasOrdinaryCase(proposal) else { return nil }
            let lower = proposal.lowercased()
            guard seen.insert(lower).inserted else { return nil }
            return preservingInitialCapital(lower, from: rawWord)
        }
    }

    /// Unique one-edit candidate among ALL returned proposals, not just the first
    /// ranked guess. Duplicate case variants do not create spurious ambiguity.
    /// Damerau-Levenshtein distance one includes a single adjacent transposition.
    static func safeConservativeConfidence(rawWord: String,
                                          result: KeyboardEnglishSpellingResult) -> String? {
        guard isASCIIWord(rawWord), hasOrdinaryCase(rawWord),
              result.availability == .available, result.spelling == .misspelledWholeWord,
              result.proposalsAreComplete, result.rankedProposals.count <= maximumProposals,
              KeyboardCorrectionContext.equalScalars(result.word, rawWord) else { return nil }
        let lower = rawWord.lowercased()
        // An unchanged proposal or non-word/mixed-case proposal is uncertainty,
        // not evidence to discard while finding an apparently unique correction.
        guard result.rankedProposals.allSatisfy({
            isASCIIWord($0) && hasOrdinaryCase($0) && $0.lowercased() != lower
        }) else { return nil }
        let candidates = Set(result.rankedProposals.map { $0.lowercased() })
            .filter { isExactlyOneEdit(lower, $0) }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        return preservingInitialCapital(candidate, from: rawWord)
    }

    private static func preservingInitialCapital(_ candidate: String, from word: String) -> String {
        guard let first = word.utf8.first, (65...90).contains(first) else { return candidate }
        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }

    private static func isExactlyOneEdit(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a != b, abs(a.count - b.count) <= 1 else { return false }
        if a.count == b.count {
            let different = a.indices.filter { a[$0] != b[$0] }
            if different.count == 1 { return true }
            guard different.count == 2 else { return false }
            let i = different[0], j = different[1]
            return j == i + 1 && a[i] == b[j] && a[j] == b[i]
        }
        let short = a.count < b.count ? a : b
        let long = a.count < b.count ? b : a
        var i = 0, j = 0, skipped = false
        while i < short.count && j < long.count {
            if short[i] == long[j] { i += 1; j += 1 }
            else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }
}

/// Provenance is accumulated only from verified ordinary key insertions. Never
/// seed this state by scanning host text. Caller MUST invalidate on selection,
/// focus, mode/trait/preference change, external edit, any other input, or plan failure,
/// even if the visible suffix is unchanged. Change scope tokens on transitions.
struct KeyboardAutocorrectionState: Sendable {
    enum UndoDelimiterDisposition: Equatable, Sendable {
        /// Immediate Backspace restores the word without the just-added delimiter.
        case remove
        /// An explicit Undo control may elect to keep the original delimiter.
        case keep
    }

    private struct TrackedWord: Sendable {
        let prefix: String
        var word: String
        var context: KeyboardCorrectionContext
    }
    private var tracked: TrackedWord?
    private var pending: KeyboardGuardedReplacementPlan?
    private var pendingCanRollback = false
    private var rollback: KeyboardGuardedReplacementPlan?
    // State-local identity keeps this core deterministic: no clock, random IDs,
    // global state or I/O. Invalidation never reuses an earlier plan identifier.
    private var planSequence: UInt64 = 0

    mutating func invalidate() {
        tracked = nil
        pending = nil
        pendingCanRollback = false
        rollback = nil
    }

    /// Call AFTER a successful insertion, with snapshots taken immediately before
    /// and after it. Only one ordinary ASCII-letter key per call is eligible.
    mutating func recordInsertion(_ text: String, origin: KeyboardCorrectionInputOrigin,
                                  before: KeyboardCorrectionContext, after: KeyboardCorrectionContext) {
        let previous = tracked
        invalidate()
        guard origin == .ordinaryKey, text.utf8.count == 1,
              text.utf8.allSatisfy(KeyboardAutocorrectionPolicy.isLetter),
              before.isUsable, after.isUsable, let prefix = before.before,
              before.replacingBefore(with: prefix + text).exactlyMatches(after) else { return }
        if var previous, previous.context.exactlyMatches(before) {
            previous.word += text
            guard previous.word.utf8.count <= 32 else { return }
            previous.context = after
            tracked = previous
        } else {
            // Requiring an entire whitespace-delimited token excludes URLs,
            // emails, code operators, apostrophes, Unicode and emoji adjacency.
            // The right side is checked too, including non-whitespace continuations.
            guard prefix.last.map(KeyboardAutocorrectionPolicy.isBoundary) ?? true,
                  before.after?.first.map(KeyboardAutocorrectionPolicy.isBoundary) ?? true else { return }
            tracked = TrackedWord(prefix: prefix, word: text, context: after)
        }
    }

    /// Call at a delimiter BEFORE inserting it. If there is no plan, the caller
    /// inserts the delimiter literally. Calling consumes tracking either way.
    mutating func delimiterDecision(rawWord: String, wordPrefixContext: String,
                                   delimiter: String, context: KeyboardCorrectionContext,
                                   options: KeyboardEnglishCorrectionOptions,
                                   hostPermission: KeyboardCorrectionHostPermission,
                                   isKnownCustomReading: Bool,
                                   providerResult: KeyboardEnglishSpellingResult) -> KeyboardCorrectionDecision {
        let word = tracked
        invalidate()
        let suggestions = options.suggestionsEnabled
            ? KeyboardAutocorrectionPolicy.suggestions(for: providerResult, rawWord: rawWord) : []
        guard options.autocorrectionEnabled, hostPermission == .permits, !isKnownCustomReading,
              KeyboardAutocorrectionPolicy.isAutomaticDelimiter(delimiter),
              let word, word.context.exactlyMatches(context),
              KeyboardCorrectionContext.equalScalars(word.word, rawWord),
              KeyboardCorrectionContext.equalScalars(word.prefix, wordPrefixContext),
              let replacement = KeyboardAutocorrectionPolicy.safeConservativeConfidence(
                rawWord: rawWord, result: providerResult) else {
            return KeyboardCorrectionDecision(suggestions: suggestions, replacementPlan: nil)
        }
        let text = replacement + delimiter
        let resultingContext = context.replacingBefore(with: word.prefix + text)
        guard resultingContext.isUsable, planSequence < UInt64.max else {
            return KeyboardCorrectionDecision(suggestions: suggestions, replacementPlan: nil)
        }
        planSequence += 1
        let plan = KeyboardGuardedReplacementPlan(
            expectedContext: context, graphemeDeleteCount: rawWord.count,
            replacementText: text, resultingContext: resultingContext,
            identifier: planSequence, originalWord: rawWord, delimiter: delimiter, prefix: word.prefix)
        pending = plan
        pendingCanRollback = true
        return KeyboardCorrectionDecision(suggestions: suggestions, replacementPlan: plan)
    }

    /// This live-state guard is required for each operation, in addition to the
    /// caller's host identity guards. invalidate() revokes retained plans even
    /// when an external edit later restores canonically/exactly identical text.
    func authorizesStep(_ index: Int, of plan: KeyboardGuardedReplacementPlan,
                        context: KeyboardCorrectionContext,
                        hostPermission: KeyboardCorrectionHostPermission) -> Bool {
        guard let pending, pending.identifier == plan.identifier,
              pending.expectedContext.exactlyMatches(plan.expectedContext),
              pending.resultingContext.exactlyMatches(plan.resultingContext),
              pending.graphemeDeleteCount == plan.graphemeDeleteCount,
              KeyboardCorrectionContext.equalScalars(pending.replacementText, plan.replacementText) else { return false }
        let steps = pending.steps
        guard steps.indices.contains(index) else { return false }
        return steps[index].isAuthorized(in: context, hostPermission: hostPermission)
    }

    /// Arm exactly one immediate rollback ONLY after every guarded operation
    /// succeeded. Confirming an undo only reports success, never arms another undo.
    /// Any event between planning/execution/confirmation invalidates the operation.
    @discardableResult
    mutating func confirmExecution(of plan: KeyboardGuardedReplacementPlan,
                                   actualContext: KeyboardCorrectionContext,
                                   hostPermission: KeyboardCorrectionHostPermission) -> Bool {
        let expected = pending
        let canRollback = pendingCanRollback
        invalidate()
        guard let expected, expected.identifier == plan.identifier,
              hostPermission == .permits,
              expected.resultingContext.exactlyMatches(actualContext) else { return false }
        if canRollback { rollback = expected }
        return true
    }

    /// Used by either immediate Backspace or explicit Undo, with an explicit
    /// delimiter choice. A failed/stale request consumes the one-shot rollback.
    mutating func undoPlan(context: KeyboardCorrectionContext,
                           hostPermission: KeyboardCorrectionHostPermission,
                           delimiterDisposition: UndoDelimiterDisposition) -> KeyboardGuardedReplacementPlan? {
        let previous = rollback
        invalidate()
        guard let previous, hostPermission == .permits,
              previous.resultingContext.exactlyMatches(context) else { return nil }
        let text = previous.originalWord + (delimiterDisposition == .keep ? previous.delimiter : "")
        let plan = KeyboardGuardedReplacementPlan(
            expectedContext: context,
            graphemeDeleteCount: previous.replacementText.count,
            replacementText: text,
            resultingContext: context.replacingBefore(with: previous.prefix + text),
            identifier: previous.identifier, originalWord: previous.originalWord,
            delimiter: previous.delimiter, prefix: previous.prefix)
        pending = plan
        // Confirming an Undo never arms a redo or another rollback.
        return plan
    }
}
