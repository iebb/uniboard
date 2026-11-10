import Foundation
import XCTest
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// These tests inject OS-shaped results. They exercise policy, NOT UITextChecker
/// dictionary availability, real guess quality, UIKit hosts or proxy execution.
final class KeyboardAutocorrectionTests: XCTestCase {
    private let scope = KeyboardEnglishInputScope(documentIdentifier: UUID(), modeIdentifier: UUID())
    private let on = KeyboardEnglishCorrectionOptions(suggestionsEnabled: true, autocorrectionEnabled: true)

    private struct FakeProvider {
        var proposals = ["receive"]
        var spelling = KeyboardEnglishSpellingResult.Spelling.misspelledWholeWord
        var availability = KeyboardEnglishSpellingResult.Availability.available
        var complete = true
        func result(for word: String) -> KeyboardEnglishSpellingResult {
            KeyboardEnglishSpellingResult(word: word, availability: availability, spelling: spelling,
                                          rankedProposals: proposals, proposalsAreComplete: complete)
        }
    }

    private func context(_ before: String?, after: String? = "", selected: String? = "",
                         scope: KeyboardEnglishInputScope? = nil,
                         completeness: KeyboardCorrectionContext.Completeness = .verified) -> KeyboardCorrectionContext {
        KeyboardCorrectionContext(before: before, after: after, selectedText: selected,
                                  scope: scope ?? self.scope, completeness: completeness)
    }

    private func tracked(_ word: String = "recieve", prefix: String = "Hello ", after: String = "")
        -> (KeyboardAutocorrectionState, KeyboardCorrectionContext) {
        var state = KeyboardAutocorrectionState()
        var before = prefix
        for letter in word {
            let text = String(letter)
            let old = context(before, after: after)
            before += text
            state.recordInsertion(text, origin: .ordinaryKey, before: old, after: context(before, after: after))
        }
        return (state, context(before, after: after))
    }

    private func decision(_ state: inout KeyboardAutocorrectionState, context: KeyboardCorrectionContext,
                          word: String = "recieve", prefix: String = "Hello ", delimiter: String = " ",
                          options: KeyboardEnglishCorrectionOptions? = nil,
                          host: KeyboardCorrectionHostPermission = .permits, custom: Bool = false,
                          provider: FakeProvider = FakeProvider()) -> KeyboardCorrectionDecision {
        state.delimiterDecision(rawWord: word, wordPrefixContext: prefix, delimiter: delimiter,
                                context: context, options: options ?? on, hostPermission: host,
                                isKnownCustomReading: custom, providerResult: provider.result(for: word))
    }

    func testBothOptionsDefaultOffAndIndependentPreferences() throws {
        var (state, current) = tracked()
        let off = decision(&state, context: current, options: KeyboardEnglishCorrectionOptions())
        XCTAssertTrue(off.suggestions.isEmpty)
        XCTAssertNil(off.replacementPlan)

        (state, current) = tracked()
        let suggestionsOnly = decision(&state, context: current,
            options: KeyboardEnglishCorrectionOptions(suggestionsEnabled: true, autocorrectionEnabled: false))
        XCTAssertEqual(suggestionsOnly.suggestions, ["receive"])
        XCTAssertNil(suggestionsOnly.replacementPlan)

        (state, current) = tracked()
        let correctionOnly = decision(&state, context: current,
            options: KeyboardEnglishCorrectionOptions(suggestionsEnabled: false, autocorrectionEnabled: true))
        XCTAssertTrue(correctionOnly.suggestions.isEmpty)
        XCTAssertNotNil(correctionOnly.replacementPlan)
    }

    func testHostNoUnknownAndLiteralFieldsBlockAutomaticCorrection() {
        for host in [KeyboardCorrectionHostPermission.autocorrectionDisabled, .unknown, .literalField] {
            var (state, current) = tracked()
            XCTAssertNil(decision(&state, context: current, host: host).replacementPlan)
        }
    }

    func testCustomReadingStillOffersExplicitSuggestionsWithoutAutocorrection() {
        var (state, current) = tracked()
        let result = decision(&state, context: current, custom: true)
        XCTAssertEqual(result.suggestions, ["receive"])
        XCTAssertNil(result.replacementPlan)
    }

    func testRealisticInjectedTypoProducesPreciseGuardedPlan() throws {
        var (state, current) = tracked()
        let plan = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        XCTAssertEqual(plan.graphemeDeleteCount, 7)
        XCTAssertEqual(plan.replacementText, "receive ")
        XCTAssertEqual(plan.resultingContext.before, "Hello receive ")
        XCTAssertEqual(plan.steps.count, 8)
        var actual = current
        for (index, step) in plan.steps.enumerated() {
            XCTAssertTrue(state.authorizesStep(index, of: plan, context: actual, hostPermission: .permits))
            XCTAssertTrue(step.isAuthorized(in: actual, hostPermission: .permits))
            XCTAssertFalse(step.isAuthorized(in: actual, hostPermission: .autocorrectionDisabled))
            actual = step.resultingContext
        }
        XCTAssertTrue(actual.exactlyMatches(plan.resultingContext))
        XCTAssertTrue(state.confirmExecution(of: plan, actualContext: actual, hostPermission: .permits))
    }

    func testNoBlindHostScanningOrUntrackedSuffixReplacement() {
        var state = KeyboardAutocorrectionState()
        let result = decision(&state, context: context("Hello recieve"))
        XCTAssertEqual(result.suggestions, ["receive"])
        XCTAssertNil(result.replacementPlan)
        let (typedState, _) = tracked()
        state = typedState
        XCTAssertNil(decision(&state, context: context("Other recieve")).replacementPlan)
    }

    func testWordAndExactPrefixAreBoundToTracking() {
        for prefix in ["Other ", "", "Hello\u{00A0}"] {
            var (state, current) = tracked()
            XCTAssertNil(decision(&state, context: current, prefix: prefix).replacementPlan)
        }
        var (state, current) = tracked()
        XCTAssertNil(decision(&state, context: current, word: "receive").replacementPlan)
    }

    func testLiteralCustomUnicodeEmojiAndOtherOriginsNeverArmWordTracking() {
        for origin in [KeyboardCorrectionInputOrigin.literalAction, .customEntry, .unicodeAction, .emoji, .other] {
            var state = KeyboardAutocorrectionState()
            var before = "Hello "
            for letter in "recieve" {
                let text = String(letter)
                state.recordInsertion(text, origin: origin, before: context(before), after: context(before + text))
                before += text
            }
            XCTAssertNil(decision(&state, context: context(before)).replacementPlan)
        }
        var state = KeyboardAutocorrectionState()
        // Even ordinary-key origin cannot claim a pasted/multi-character string.
        state.recordInsertion("recieve", origin: .ordinaryKey,
                              before: context("Hello "), after: context("Hello recieve"))
        XCTAssertNil(decision(&state, context: context("Hello recieve")).replacementPlan)
    }

    func testAnyMixedOriginOrFailedInsertionInvalidatesTrackedWord() {
        for origin in [KeyboardCorrectionInputOrigin.literalAction, .ordinaryKey] {
            var (state, current) = tracked("reciev")
            let wrongAfter = origin == .ordinaryKey ? context("Hello recievX") : context("Hello recieve")
            state.recordInsertion("e", origin: origin, before: current, after: wrongAfter)
            current = context("Hello recieve")
            XCTAssertNil(decision(&state, context: current).replacementPlan)
        }
    }

    func testURLsEmailsCodeUnicodeAndEmojiAdjacentTokensAreExcluded() {
        for prefix in ["https://", "www.", "user@", "foo_", "let=", "`", "#", "'", "é", "🙂", "東京"] {
            var (state, current) = tracked(prefix: prefix)
            XCTAssertNil(decision(&state, context: current, prefix: prefix).replacementPlan, prefix)
        }
        for after in [".com", "@example.com", "/path", "_value", "()", "`", "'", "é", "🙂"] {
            var (state, current) = tracked(after: after)
            XCTAssertNil(decision(&state, context: current).replacementPlan, after)
        }
        for delimiter in [".", "/", "@", "_", "'", "🙂", "", "  "] {
            var (state, current) = tracked()
            XCTAssertNil(decision(&state, context: current, delimiter: delimiter).replacementPlan, delimiter)
        }
    }

    func testMissingTruncatedOversizedOrSelectedContextIsSuggestionsOnly() {
        let unknownScope = KeyboardCorrectionContext(before: "Hello recieve", after: "", selectedText: "",
                                                     scope: nil, completeness: .verified)
        let unsafe = [context(nil), context("Hello recieve", after: nil),
                      context("Hello recieve", selected: nil), context("Hello recieve", selected: "x"),
                      context("Hello recieve", completeness: .unknownOrTruncated), unknownScope,
                      context(String(repeating: "a", count: 4097) + " recieve")]
        for current in unsafe {
            var (state, _) = tracked()
            let result = decision(&state, context: current)
            XCTAssertEqual(result.suggestions, ["receive"])
            XCTAssertNil(result.replacementPlan)
        }
        // A known empty after-context is usable, a missing one is NOT empty.
        var (state, current) = tracked()
        XCTAssertNotNil(decision(&state, context: current).replacementPlan)
    }

    func testUnknownContextAtStartCannotBeLaunderedByLaterCompleteSnapshot() {
        var state = KeyboardAutocorrectionState()
        state.recordInsertion("r", origin: .ordinaryKey,
                              before: context("Hello ", completeness: .unknownOrTruncated),
                              after: context("Hello r"))
        var before = "Hello r"
        for letter in "ecieve" {
            let text = String(letter)
            state.recordInsertion(text, origin: .ordinaryKey,
                                  before: context(before), after: context(before + text))
            before += text
        }
        XCTAssertNil(decision(&state, context: context(before)).replacementPlan)
    }

    func testCapitalizationAndASCIIWordBounds() {
        for word in ["ab", String(repeating: "a", count: 33), "récieve", "recie\u{0301}ve", "RECIEVE", "reCieve", "rec1eve"] {
            var (state, current) = tracked(word)
            XCTAssertNil(decision(&state, context: current, word: word).replacementPlan, word)
        }
        var (state, current) = tracked("Recieve")
        let result = decision(&state, context: current, word: "Recieve")
        XCTAssertEqual(result.suggestions, ["Receive"])
        XCTAssertEqual(result.replacementPlan?.replacementText, "Receive ")
    }

    func testConfidenceRequiresFullMisspellingAndAvailableCompleteOSResult() {
        for provider in [FakeProvider(proposals: []), FakeProvider(spelling: .validWord),
                         FakeProvider(spelling: .unknown), FakeProvider(availability: .dictionaryUnavailable),
                         FakeProvider(complete: false), FakeProvider(proposals: ["recieve", "receive"]),
                         FakeProvider(proposals: ["receive", "receive!"]),
                         FakeProvider(proposals: ["receive", "reCeive"])] {
            XCTAssertNil(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
                rawWord: "recieve", result: provider.result(for: "recieve")))
        }
        XCTAssertNil(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
            rawWord: "recieve", result: FakeProvider().result(for: "another")))
    }

    func testAmbiguityIsNotHiddenByRankingButDuplicatesAreDeduplicated() {
        let ambiguous = FakeProvider(proposals: ["hello", "help"])
        XCTAssertNil(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
            rawWord: "hellp", result: ambiguous.result(for: "hellp")))
        let reversed = FakeProvider(proposals: ["help", "hello"])
        XCTAssertNil(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
            rawWord: "hellp", result: reversed.result(for: "hellp")))
        let duplicates = FakeProvider(proposals: ["receive", "Receive", "receive"])
        XCTAssertEqual(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
            rawWord: "recieve", result: duplicates.result(for: "recieve")), "receive")
        XCTAssertEqual(KeyboardAutocorrectionPolicy.suggestions(for: duplicates.result(for: "recieve"),
                                                              rawWord: "recieve"), ["receive"])
        let tooMany = FakeProvider(proposals: Array(repeating: "receive", count: 13))
        XCTAssertNil(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
            rawWord: "recieve", result: tooMany.result(for: "recieve")))
    }

    func testUniqueEditDistanceOneAllowsInsertionDeletionSubstitutionAndTranspositionOnly() {
        for (raw, corrected) in [("recieve", "receive"), ("hellp", "hello"),
                                 ("helo", "hello"), ("helllo", "hello")] {
            XCTAssertEqual(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
                rawWord: raw, result: FakeProvider(proposals: [corrected]).result(for: raw)), corrected)
        }
        XCTAssertNil(KeyboardAutocorrectionPolicy.safeConservativeConfidence(
            rawWord: "hxllp", result: FakeProvider(proposals: ["hello"]).result(for: "hxllp")))
    }

    func testUnicodePrefixIsPreservedExactlyThroughCorrectionAndOneShotBackspaceUndo() throws {
        let prefix = "🙂 cafe\u{0301} 東京 "
        var (state, current) = tracked(prefix: prefix)
        let plan = try XCTUnwrap(decision(&state, context: current, prefix: prefix).replacementPlan)
        XCTAssertTrue(Array(plan.resultingContext.before!.unicodeScalars)
            .starts(with: Array(prefix.unicodeScalars)))
        XCTAssertEqual(plan.steps[6].resultingContext.before?.unicodeScalars.map(\.value),
                       prefix.unicodeScalars.map(\.value))
        XCTAssertTrue(state.confirmExecution(of: plan, actualContext: plan.resultingContext, hostPermission: .permits))
        let undo = try XCTUnwrap(state.undoPlan(context: plan.resultingContext, hostPermission: .permits,
                                              delimiterDisposition: .remove))
        XCTAssertEqual(undo.graphemeDeleteCount, "receive ".count)
        XCTAssertEqual(undo.replacementText, "recieve")
        XCTAssertTrue(state.authorizesStep(0, of: undo, context: plan.resultingContext, hostPermission: .permits))
        XCTAssertTrue(undo.resultingContext.exactlyMatches(current))
        XCTAssertTrue(state.confirmExecution(of: undo, actualContext: undo.resultingContext, hostPermission: .permits))
        XCTAssertNil(state.undoPlan(context: plan.resultingContext, hostPermission: .permits,
                                    delimiterDisposition: .remove))
    }

    func testExplicitUndoCanKeepChosenDelimiter() throws {
        var (state, current) = tracked()
        let plan = try XCTUnwrap(decision(&state, context: current, delimiter: "\n").replacementPlan)
        XCTAssertTrue(state.confirmExecution(of: plan, actualContext: plan.resultingContext, hostPermission: .permits))
        let undo = try XCTUnwrap(state.undoPlan(context: plan.resultingContext, hostPermission: .permits,
                                              delimiterDisposition: .keep))
        XCTAssertEqual(undo.replacementText, "recieve\n")
        XCTAssertEqual(undo.resultingContext.before, "Hello recieve\n")
    }

    func testUndoRequiresFullExactContextScopeAndEmptySelection() throws {
        let differentDocument = KeyboardEnglishInputScope(documentIdentifier: UUID(), modeIdentifier: scope.modeIdentifier)
        let differentMode = KeyboardEnglishInputScope(documentIdentifier: scope.documentIdentifier, modeIdentifier: UUID())
        let prefix = "cafe\u{0301} "
        let unsafe = [context("café receive "), context(prefix + "receive ", after: nil),
                      context(prefix + "receive ", after: "changed"),
                      context(prefix + "receive ", selected: "x"),
                      context(prefix + "receive ", scope: differentDocument),
                      context(prefix + "receive ", scope: differentMode), context("Other receive "),
                      context(prefix + "receive ", completeness: .unknownOrTruncated)]
        for stale in unsafe {
            var (state, current) = tracked(prefix: prefix)
            let plan = try XCTUnwrap(decision(&state, context: current, prefix: prefix).replacementPlan)
            XCTAssertTrue(state.confirmExecution(of: plan, actualContext: plan.resultingContext, hostPermission: .permits))
            XCTAssertNil(state.undoPlan(context: stale, hostPermission: .permits, delimiterDisposition: .remove))
            // A rejected attempt cannot be retried later against a matching suffix.
            XCTAssertNil(state.undoPlan(context: plan.resultingContext, hostPermission: .permits,
                                        delimiterDisposition: .remove))
        }
    }

    func testPlanningAndEachStepRejectCanonicallyEquivalentOrDifferentFocus() throws {
        let prefix = "cafe\u{0301} "
        var (state, _) = tracked(prefix: prefix)
        XCTAssertNil(decision(&state, context: context("café recieve"), prefix: prefix).replacementPlan)
        var current: KeyboardCorrectionContext
        (state, current) = tracked(prefix: prefix)
        let plan = try XCTUnwrap(decision(&state, context: current, prefix: prefix).replacementPlan)
        for step in plan.steps {
            let canonicalBefore = step.expectedContext.before!.replacingOccurrences(of: "e\u{0301}", with: "é")
            XCTAssertFalse(step.isAuthorized(in: context(canonicalBefore), hostPermission: .permits))
            let changedScope = KeyboardEnglishInputScope(documentIdentifier: UUID(), modeIdentifier: scope.modeIdentifier)
            XCTAssertFalse(step.isAuthorized(in: context(step.expectedContext.before, scope: changedScope),
                                             hostPermission: .permits))
        }
    }

    func testFailedExecutionNeverArmsUndoAndExplicitInvalidationCancelsEverything() throws {
        var (state, current) = tracked()
        let plan = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        XCTAssertFalse(state.confirmExecution(of: plan, actualContext: current, hostPermission: .permits))
        XCTAssertNil(state.undoPlan(context: plan.resultingContext, hostPermission: .permits, delimiterDisposition: .remove))
        (state, current) = tracked()
        let good = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        XCTAssertTrue(state.confirmExecution(of: good, actualContext: good.resultingContext, hostPermission: .permits))
        // Focus/selection/mode/external edit notifications MUST call this even
        // if the proxy later exposes the same text again.
        state.invalidate()
        XCTAssertNil(state.undoPlan(context: good.resultingContext, hostPermission: .permits, delimiterDisposition: .remove))
        (state, current) = tracked()
        let pending = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        state.invalidate()
        XCTAssertFalse(state.authorizesStep(0, of: pending, context: pending.expectedContext, hostPermission: .permits))
        XCTAssertFalse(state.confirmExecution(of: pending, actualContext: pending.resultingContext, hostPermission: .permits))
    }

    func testNonemptyAfterContextIsPreservedAndMustStillMatch() throws {
        var (state, current) = tracked(after: " next 🙂")
        let plan = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        for step in plan.steps {
            XCTAssertEqual(step.expectedContext.after, " next 🙂")
            XCTAssertEqual(step.resultingContext.after, " next 🙂")
        }
        (state, current) = tracked(after: " next 🙂")
        XCTAssertNil(decision(&state, context: context(current.before, after: " other 🙂")).replacementPlan)
    }

    func testHostNoAlsoBlocksRollbackAndStepAuthorization() throws {
        var (state, current) = tracked()
        let plan = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        XCTAssertFalse(state.authorizesStep(0, of: plan, context: current, hostPermission: .autocorrectionDisabled))
        XCTAssertTrue(state.confirmExecution(of: plan, actualContext: plan.resultingContext, hostPermission: .permits))
        XCTAssertNil(state.undoPlan(context: plan.resultingContext, hostPermission: .autocorrectionDisabled,
                                    delimiterDisposition: .remove))
    }

    func testLocalReplacementScopeRequiresObservedBoundaryAndKnownSelection() throws {
        let raw = context("middle of host document ", after: " next", completeness: .unknownOrTruncated)
        let verified = try XCTUnwrap(KeyboardAutocorrectionPolicy.locallyVerifiedWordStart(raw))
        XCTAssertEqual(verified.completeness, .verified)
        for unsafe in [context("", completeness: .unknownOrTruncated), context(nil), context("word"),
                       context("prefix ", after: nil), context("prefix ", after: ".com"),
                       context("prefix ", selected: nil), context("prefix ", selected: "selected"),
                       context("prefix ", completeness: .knownTruncated)] {
            XCTAssertNil(KeyboardAutocorrectionPolicy.locallyVerifiedWordStart(unsafe))
        }
        XCTAssertNotNil(KeyboardAutocorrectionPolicy.locallyVerifiedWordStart(
            context("prefix ", after: "", completeness: .unknownOrTruncated)))
        var state = KeyboardAutocorrectionState()
        // Boundary verification alone never seeds a scanned host word.
        XCTAssertNil(decision(&state, context: verified).replacementPlan)
    }

    func testLocallyTrackedSpanAuthorizesWithoutClaimingWholeDocumentCompleteness() throws {
        let prefix = "observed bounded host suffix 🙂 "
        var before = try XCTUnwrap(KeyboardAutocorrectionPolicy.locallyVerifiedWordStart(
            context(prefix, after: " next", completeness: .unknownOrTruncated)))
        var state = KeyboardAutocorrectionState()
        var rawBefore = prefix
        for letter in "recieve" {
            let text = String(letter)
            rawBefore += text
            let actual = context(rawBefore, after: " next", completeness: .unknownOrTruncated)
            let after = try XCTUnwrap(KeyboardAutocorrectionPolicy.verifiedOrdinaryInsertion(
                text, before: before, actualAfter: actual))
            state.recordInsertion(text, origin: .ordinaryKey, before: before, after: after)
            before = after
        }
        let plan = try XCTUnwrap(decision(&state, context: before, prefix: prefix).replacementPlan)
        XCTAssertEqual(plan.replacementText, "receive ")
        XCTAssertEqual(plan.resultingContext.after, " next")
        XCTAssertEqual(plan.resultingContext.before, prefix + "receive ")
    }

    func testLocalSpanGrowthRejectsTruncationShiftNilSelectionAndScalarChanges() throws {
        let before = try XCTUnwrap(KeyboardAutocorrectionPolicy.locallyVerifiedWordStart(
            context("cafe\u{0301} ", completeness: .unknownOrTruncated)))
        for actual in [context("café r"), context("e\u{0301} r"), context("cafe\u{0301} r", after: nil),
                       context("cafe\u{0301} r", selected: nil),
                       context("cafe\u{0301} r", completeness: .knownTruncated),
                       context("cafe\u{0301} r", scope: KeyboardEnglishInputScope(
                        documentIdentifier: UUID(), modeIdentifier: scope.modeIdentifier))] {
            XCTAssertNil(KeyboardAutocorrectionPolicy.verifiedOrdinaryInsertion("r", before: before,
                                                                              actualAfter: actual))
        }
        XCTAssertNil(KeyboardAutocorrectionPolicy.verifiedOrdinaryInsertion("rr", before: before,
            actualAfter: context("cafe\u{0301} rr")))
    }

    #if canImport(UIKit)
    @MainActor
    func testHostTraitAutocorrectionRetentionAndPermissionMapping() {
        let field = UITextField()
        field.keyboardType = .default
        field.textContentType = nil
        field.autocorrectionType = .yes
        let enabled = KeyboardHostInputTraits(reading: field)
        XCTAssertEqual(enabled.autocorrectionType, .yes)
        XCTAssertEqual(enabled.englishCorrectionPermission, .permits)
        field.autocorrectionType = .no
        let disabled = KeyboardHostInputTraits(reading: field)
        XCTAssertEqual(disabled.autocorrectionType, .no)
        XCTAssertEqual(disabled.englishCorrectionPermission, .autocorrectionDisabled)
        XCTAssertNotEqual(enabled, disabled)
        field.autocorrectionType = .default
        XCTAssertEqual(KeyboardHostInputTraits(reading: field).englishCorrectionPermission, .permits)
        field.isSecureTextEntry = true
        XCTAssertEqual(KeyboardHostInputTraits(reading: field).englishCorrectionPermission, .literalField)
    }

    @MainActor
    func testMissingHostAutocorrectionGetterIsUnknownNotPermission() {
        final class MissingTraits: NSObject, UITextInputTraits {}
        let traits = KeyboardHostInputTraits(reading: MissingTraits())
        XCTAssertNil(traits.autocorrectionType)
        XCTAssertEqual(traits.englishCorrectionPermission, .unknown)
    }
    #endif

    func testAnyOtherInsertionConsumesImmediateRollback() throws {
        var (state, current) = tracked()
        let plan = try XCTUnwrap(decision(&state, context: current).replacementPlan)
        XCTAssertTrue(state.confirmExecution(of: plan, actualContext: plan.resultingContext, hostPermission: .permits))
        state.recordInsertion("x", origin: .ordinaryKey, before: plan.resultingContext,
                              after: context("Hello receive x"))
        XCTAssertNil(state.undoPlan(context: plan.resultingContext, hostPermission: .permits, delimiterDisposition: .remove))
    }
}
