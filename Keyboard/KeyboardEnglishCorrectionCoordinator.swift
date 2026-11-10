#if canImport(UIKit)
import UIKit

/// Main-actor provider/core adapter. It NEVER executes a document proxy.
///
/// Automatic edits require a complete LOCALLY TRACKED replacement scope, not
/// proof of the whole document. At the first ordinary ASCII key this adapter
/// requires an observed preceding whitespace boundary, present right context
/// (empty or beginning with whitespace), known-empty selection and known scope.
/// EVERY inserted key must then exhibit exact before -> before+key growth with
/// unchanged right context. No word is seeded by scanning host text. An empty
/// left proxy window is not a proven start; that first word stays suggestions-
/// only unless the caller can independently verify the optional empty-document
/// anchor. Nil selectedText is NEVER promoted to known-empty selection.
///
/// Missing context, known truncation, a moving window, scope/selection changes,
/// unexpected callbacks or the 4096-scalar bound revoke verification. Known
/// focus/cursor/selection/mode/trait/preference/external-edit events MUST call
/// invalidate(), even when the visible strings are unchanged. Exact guarded
/// snapshots bind the local target and surrounding window to document AND mode;
/// there is no suffix-only authorization against arbitrary unrelated host text.
@available(iOS 17.0, *)
@MainActor
final class KeyboardEnglishCorrectionCoordinator {
    private struct Insertion {
        let text: String
        let origin: KeyboardCorrectionInputOrigin
        let before: KeyboardCorrectionContext
        let expectedAfter: KeyboardCorrectionContext?
        let verifiedBefore: KeyboardCorrectionContext?
    }

    // Do not instantiate UITextChecker (or its dictionary resources) until an
    // enabled runtime path actually requests suggestions. Invalidation is free
    // to create this adapter while release availability keeps the provider cold.
    private let suppliedProvider: (any EnglishSuggestionProviding)?
    private lazy var provider: any EnglishSuggestionProviding = suppliedProvider ?? EnglishSuggestionProvider()
    private var core = KeyboardAutocorrectionState()
    private var options: KeyboardEnglishCorrectionOptions
    private var insertion: Insertion?
    private var activePlan: KeyboardGuardedReplacementPlan?
    private var verifiedScopeContext: KeyboardCorrectionContext?
    private var lastObserved: KeyboardCorrectionContext?
    private var lastPermission: KeyboardCorrectionHostPermission?
    private var word = ""
    private var prefix = ""
    private var wordContext: KeyboardCorrectionContext?
    private var rollbackAvailable = false

    private(set) var suggestions: [String] = []
    private(set) var dictionaryAvailability: KeyboardEnglishSpellingResult.Availability?
    private(set) var lastSpellingResult: KeyboardEnglishSpellingResult?
    private(set) var correctedOriginalWord: String?

    var hasVerifiedReplacementScope: Bool { verifiedScopeContext != nil }
    /// Compatibility alias; this means a LOCAL scope, never whole-document proof.
    @available(*, deprecated, renamed: "hasVerifiedReplacementScope")
    var hasVerifiedDocument: Bool { hasVerifiedReplacementScope }
    var hasImmediateUndo: Bool { rollbackAvailable }
    var trackedWord: String? { word.isEmpty ? nil : word }

    init(provider: (any EnglishSuggestionProviding)? = nil,
         options: KeyboardEnglishCorrectionOptions = KeyboardEnglishCorrectionOptions()) {
        suppliedProvider = provider
        self.options = options
    }

    func setOptions(_ newOptions: KeyboardEnglishCorrectionOptions) {
        guard options.suggestionsEnabled != newOptions.suggestionsEnabled
                || options.autocorrectionEnabled != newOptions.autocorrectionEnabled else { return }
        invalidate()
        options = newOptions
    }

    func invalidate() {
        core.invalidate()
        insertion = nil
        activePlan = nil
        verifiedScopeContext = nil
        lastObserved = nil
        lastPermission = nil
        word = ""
        prefix = ""
        wordContext = nil
        rollbackAvailable = false
        correctedOriginalWord = nil
        suggestions = []
        lastSpellingResult = nil
        dictionaryAvailability = nil
    }

    /// Opt-in trust boundary. A proxy returning ""/"" is NOT independent proof.
    /// Caller may use this only when it independently knows the whole document
    /// is empty and selection/focus identity is valid. Unknown evidence fails.
    @discardableResult
    func beginIndependentlyVerifiedEmptyDocument(_ context: KeyboardCorrectionContext,
                                                hostPermission: KeyboardCorrectionHostPermission) -> Bool {
        invalidate()
        guard context.completeness == .verified, context.scope != nil,
              context.before == "", context.after == "", context.selectedText == "",
              hostPermission == .permits else { return false }
        verifiedScopeContext = context
        lastObserved = context
        lastPermission = hostPermission
        return true
    }

    /// Call BEFORE the ordinary/literal host insertion, then didInsert afterward.
    /// This brackets synchronous/asynchronous expected host callbacks so those
    /// callbacks do not spuriously destroy verified ordinary-key provenance.
    func willInsert(_ text: String, origin: KeyboardCorrectionInputOrigin,
                    context: KeyboardCorrectionContext,
                    hostPermission: KeyboardCorrectionHostPermission) {
        if insertion != nil || activePlan != nil || rollbackAvailable {
            // Any input after a correction consumes immediate rollback, but an
            // exact verified local window can remain valid for the next word.
            let anchor = matchingVerified(context)
            invalidate()
            verifiedScopeContext = anchor
        }
        checkPermission(hostPermission)
        if let lastObserved, !Self.sameProvisionalObservation(lastObserved, context) {
            invalidate()
        }
        let ordinaryLetter = origin == .ordinaryKey && text.utf8.count == 1
            && text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })
        let verifiedBefore = matchingVerified(context)
            ?? (ordinaryLetter && hostPermission == .permits
                ? KeyboardAutocorrectionPolicy.locallyVerifiedWordStart(context) : nil)
        let expected = context.before.map { Self.copy(context, before: $0 + text, verified: false) }
        insertion = Insertion(text: text, origin: origin, before: context,
                              expectedAfter: expected, verifiedBefore: verifiedBefore)
        lastObserved = context
        lastPermission = hostPermission
        // A new insertion is never itself a continuation of immediate Undo.
        rollbackAvailable = false
        correctedOriginalWord = nil
    }

    /// Call only after the host insertion actually returned. False/mismatching
    /// insertions lose provenance; no expected text is substituted for actual.
    @discardableResult
    func didInsert(context: KeyboardCorrectionContext,
                   hostPermission: KeyboardCorrectionHostPermission) -> [String] {
        guard let pending = insertion, let expected = pending.expectedAfter,
              hostPermission == lastPermission,
              Self.sameProvisionalObservation(expected, context) else {
            invalidate()
            return []
        }
        insertion = nil
        activePlan = nil
        let verifiedAfter: KeyboardCorrectionContext?
        if pending.origin == .ordinaryKey, let verifiedBefore = pending.verifiedBefore {
            verifiedAfter = KeyboardAutocorrectionPolicy.verifiedOrdinaryInsertion(
                pending.text, before: verifiedBefore, actualAfter: context)
        } else {
            verifiedAfter = nil
        }
        verifiedScopeContext = verifiedAfter
        if let verifiedBefore = pending.verifiedBefore, let verifiedAfter {
            core.recordInsertion(pending.text, origin: pending.origin,
                                 before: verifiedBefore, after: verifiedAfter)
        } else {
            core.invalidate()
        }
        trackSuggestionWord(pending, after: context)
        lastObserved = context
        lastPermission = hostPermission
        if options.suggestionsEnabled, KeyboardAutocorrectionPolicy.isASCIIWord(word) {
            updateResult(provider.suggestions(for: word))
        } else {
            suggestions = []
            lastSpellingResult = nil
        }
        return suggestions
    }

    /// BEFORE inserting the delimiter. If nil, insert it normally (bracket it
    /// with willInsert/didInsert or invalidate for other input paths).
    func planForDelimiter(_ delimiter: String, context: KeyboardCorrectionContext,
                          hostPermission: KeyboardCorrectionHostPermission,
                          isKnownCustomReading: Bool) -> KeyboardGuardedReplacementPlan? {
        guard options.suggestionsEnabled || options.autocorrectionEnabled else {
            invalidate()
            return nil
        }
        checkPermission(hostPermission)
        guard insertion == nil, activePlan == nil, let wordContext,
              Self.sameProvisionalObservation(wordContext, context),
              KeyboardAutocorrectionPolicy.isASCIIWord(word) else {
            invalidate()
            return nil
        }
        let rawWord = word
        let result = provider.suggestions(for: rawWord)
        updateResult(result)
        let decision = core.delimiterDecision(
            rawWord: rawWord, wordPrefixContext: prefix, delimiter: delimiter,
            context: matchingVerified(context) ?? context,
            options: options, hostPermission: hostPermission,
            isKnownCustomReading: isKnownCustomReading, providerResult: result)
        suggestions = decision.suggestions
        word = ""
        prefix = ""
        self.wordContext = nil
        activePlan = decision.replacementPlan
        if activePlan != nil { correctedOriginalWord = rawWord }
        return activePlan
    }

    /// For EACH operation, re-read the actual host snapshot and traits and also
    /// run the controller's independent document/selection guards. No awaits.
    /// Any denial invalidates the pending plan instead of allowing later retry.
    func authorizesStep(_ index: Int, of plan: KeyboardGuardedReplacementPlan,
                        context: KeyboardCorrectionContext,
                        hostPermission: KeyboardCorrectionHostPermission) -> Bool {
        guard let activePlan, Self.samePlan(activePlan, plan),
              plan.steps.indices.contains(index),
              Self.sameObservedText(plan.steps[index].expectedContext, context),
              core.authorizesStep(index, of: plan, context: Self.verified(context),
                                  hostPermission: hostPermission) else {
            invalidate()
            return false
        }
        return true
    }

    /// Verify the actual result after EACH operation, before proceeding. Like
    /// authorizesStep, this checks only observations backed by a live core plan.
    @discardableResult
    func validateStepResult(_ index: Int, of plan: KeyboardGuardedReplacementPlan,
                            context: KeyboardCorrectionContext,
                            hostPermission: KeyboardCorrectionHostPermission) -> Bool {
        guard let activePlan, Self.samePlan(activePlan, plan), hostPermission == .permits,
              plan.steps.indices.contains(index),
              Self.sameObservedText(plan.steps[index].resultingContext, context) else {
            invalidate()
            return false
        }
        return true
    }

    /// Confirm ONLY after every operation and resulting snapshot passed. If any
    /// operation fails, call invalidate instead. A successful Undo cannot redo.
    @discardableResult
    func didExecute(_ plan: KeyboardGuardedReplacementPlan,
                    context: KeyboardCorrectionContext,
                    hostPermission: KeyboardCorrectionHostPermission) -> Bool {
        let wasUndo = rollbackAvailable
        guard let activePlan, Self.samePlan(activePlan, plan),
              Self.sameObservedText(plan.resultingContext, context),
              core.confirmExecution(of: plan, actualContext: Self.verified(context),
                                    hostPermission: hostPermission) else {
            invalidate()
            return false
        }
        self.activePlan = nil
        verifiedScopeContext = Self.verified(context)
        lastObserved = context
        lastPermission = hostPermission
        rollbackAvailable = !wasUndo
        if wasUndo { correctedOriginalWord = nil; suggestions = [] }
        return true
    }

    /// Design §6: BOTH immediate Backspace and explicit Undo restore the exact
    /// pre-delimiter word, removing the triggering delimiter. Consume Backspace
    /// only when a returned plan is fully executed; do not delete once more.
    func planUndo(context: KeyboardCorrectionContext,
                  hostPermission: KeyboardCorrectionHostPermission) -> KeyboardGuardedReplacementPlan? {
        guard rollbackAvailable, activePlan == nil,
              let verified = matchingVerified(context),
              let plan = core.undoPlan(context: verified, hostPermission: hostPermission,
                                       delimiterDisposition: .remove) else {
            invalidate()
            return nil
        }
        activePlan = plan
        // Leave true until didExecute so it recognizes the one-shot undo.
        return plan
    }

    /// Call from text callbacks. Exact expected before/after insertion snapshots
    /// and in-flight plan steps are harmless acknowledgments, NOT new input.
    /// Explicit selection/focus/external-edit notifications must invalidate()
    /// directly, not pass through this callback acknowledgment method.
    @discardableResult
    func observeHostSnapshot(_ context: KeyboardCorrectionContext) -> Bool {
        if let insertion,
           Self.sameProvisionalObservation(insertion.before, context)
            || insertion.expectedAfter.map({ Self.sameProvisionalObservation($0, context) }) == true {
            return true
        }
        if let activePlan {
            if activePlan.steps.contains(where: {
                Self.sameObservedText($0.expectedContext, context)
                    || Self.sameObservedText($0.resultingContext, context)
            }) { return true }
        }
        if let lastObserved, Self.sameProvisionalObservation(lastObserved, context) { return true }
        invalidate()
        return false
    }

    private func checkPermission(_ permission: KeyboardCorrectionHostPermission) {
        if let lastPermission, lastPermission != permission { invalidate() }
        lastPermission = permission
    }

    private func matchingVerified(_ context: KeyboardCorrectionContext) -> KeyboardCorrectionContext? {
        guard let verifiedScopeContext, Self.sameObservedText(verifiedScopeContext, context) else { return nil }
        return Self.verified(context)
    }

    private func trackSuggestionWord(_ insertion: Insertion, after: KeyboardCorrectionContext) {
        guard insertion.origin == .ordinaryKey, insertion.text.utf8.count == 1,
              insertion.text.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              let before = insertion.before.before else {
            word = ""; prefix = ""; wordContext = nil
            return
        }
        if let wordContext, Self.sameProvisionalObservation(wordContext, insertion.before) {
            word += insertion.text
        } else {
            // Start-of-window is fine ONLY for suggestions; it never establishes
            // the verified local scope used for destructive authorization.
            guard before.last.map({ $0.isWhitespace }) ?? true else {
                word = ""; prefix = ""; self.wordContext = nil
                return
            }
            word = insertion.text
            prefix = before
        }
        guard word.utf8.count <= 32 else { word = ""; wordContext = nil; return }
        wordContext = after
    }

    private func updateResult(_ result: KeyboardEnglishSpellingResult) {
        lastSpellingResult = result
        dictionaryAvailability = result.availability
        suggestions = options.suggestionsEnabled
            ? KeyboardAutocorrectionPolicy.suggestions(for: result, rawWord: result.word) : []
    }

    private static func samePlan(_ lhs: KeyboardGuardedReplacementPlan,
                                 _ rhs: KeyboardGuardedReplacementPlan) -> Bool {
        lhs.expectedContext.exactlyMatches(rhs.expectedContext)
            && lhs.resultingContext.exactlyMatches(rhs.resultingContext)
            && lhs.graphemeDeleteCount == rhs.graphemeDeleteCount
            && lhs.replacementText.unicodeScalars.elementsEqual(rhs.replacementText.unicodeScalars)
    }

    /// Optional-context comparison is ONLY for non-destructive local suggestion
    /// tracking/callback acknowledgment. Matching nil after-context never becomes
    /// an empty right side or establishes replacement-scope verification.
    private static func sameProvisionalObservation(_ lhs: KeyboardCorrectionContext,
                                                   _ rhs: KeyboardCorrectionContext) -> Bool {
        func equal(_ left: String?, _ right: String?) -> Bool {
            switch (left, right) {
            case let (.some(left), .some(right)):
                return left.unicodeScalars.count <= 4096 && right.unicodeScalars.count <= 4096
                    && left.unicodeScalars.elementsEqual(right.unicodeScalars)
            case (.none, .none): return true
            default: return false
            }
        }
        return lhs.completeness != .knownTruncated && rhs.completeness != .knownTruncated
            && lhs.scope != nil && lhs.scope == rhs.scope
            && equal(lhs.before, rhs.before) && equal(lhs.after, rhs.after)
            && equal(lhs.selectedText, rhs.selectedText)
    }

    /// This comparison acknowledges an observation only. It deliberately does
    /// NOT assert completeness and never suffices alone to authorize an edit.
    private static func sameObservedText(_ lhs: KeyboardCorrectionContext,
                                         _ rhs: KeyboardCorrectionContext) -> Bool {
        guard lhs.completeness != .knownTruncated, rhs.completeness != .knownTruncated,
              let leftBefore = lhs.before, let rightBefore = rhs.before,
              let leftAfter = lhs.after, let rightAfter = rhs.after,
              lhs.selectedText == "", rhs.selectedText == "",
              lhs.scope != nil, lhs.scope == rhs.scope,
              leftBefore.unicodeScalars.count <= 4096, rightBefore.unicodeScalars.count <= 4096,
              leftAfter.unicodeScalars.count <= 4096, rightAfter.unicodeScalars.count <= 4096 else { return false }
        return leftBefore.unicodeScalars.elementsEqual(rightBefore.unicodeScalars)
            && leftAfter.unicodeScalars.elementsEqual(rightAfter.unicodeScalars)
    }

    private static func copy(_ context: KeyboardCorrectionContext, before: String,
                             verified: Bool) -> KeyboardCorrectionContext {
        KeyboardCorrectionContext(before: before, after: context.after, selectedText: context.selectedText,
                                  scope: context.scope, completeness: verified ? .verified : .unknownOrTruncated)
    }

    private static func verified(_ context: KeyboardCorrectionContext) -> KeyboardCorrectionContext {
        KeyboardCorrectionContext(before: context.before, after: context.after,
                                  selectedText: context.selectedText, scope: context.scope, completeness: .verified)
    }
}
#endif
