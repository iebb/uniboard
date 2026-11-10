import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class LanguageCompositionTests: XCTestCase {
    private let document = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!

    private func makeState(revision: UInt64 = 0) -> LanguageCompositionState {
        .init(documentID: document, mode: .japaneseRomaji, packRevision: "pack-1",
              dictionaryRevision: 7, revision: revision)
    }

    @discardableResult
    private func append(_ text: String, to state: inout LanguageCompositionState)
        -> LanguageCompositionInputDisposition {
        state.append(text, origin: .normalKeyTap) { _, reading in reading }
    }

    private func candidate(id: String = "reused", output: String = "日本語", consumed: Int = 7)
        -> LanguageConversionCandidate {
        .init(id: id, output: output, source: .engine, consumedInputScalars: consumed)
    }

    private func result(_ request: LanguageConversionRequest, output: String = "日本語")
        -> LanguageConversionResult {
        .init(token: request.token, preedit: "にほんご",
              candidates: [candidate(output: output, consumed: request.rawInput.unicodeScalars.count)])
    }

    private func assertExact(_ actual: String, _ expected: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.unicodeScalars), Array(expected.unicodeScalars), file: file, line: line)
    }

    private func assertCommit(_ effects: [LanguageCompositionEffect], text: String, remaining: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(effects.count, 1, file: file, line: line)
        guard let effect = effects.first, case .commit(let actual, let remainder) = effect else {
            return XCTFail("Expected an explicit commit effect", file: file, line: line)
        }
        assertExact(actual, text, file: file, line: line)
        assertExact(remainder, remaining, file: file, line: line)
    }

    func testModeOnlyContinuationAcceptsOneCompleteCommitWithoutTextContext() {
        // The policy intentionally needs no preceding/following text. Both nil
        // and known-empty selection work, but only when unchanged across insert.
        let selections: [[UInt8]?] = [nil, []]
        for selection in selections {
            let scope = LanguageCompositionModeTransitionScope(document: document,
                inputMode: UUID(), interaction: UUID(), selection: selection)
            let effects: [LanguageCompositionEffect] = [.commit(text: "가", remainingInput: "")]
            XCTAssertEqual(LanguageCompositionModeTransitionScope.completeCommitText(in: effects), "가")
            XCTAssertTrue(scope.permitsContinuation(after: effects, commitAccepted: true, current: scope))
            XCTAssertFalse(scope.permitsContinuation(after: effects, commitAccepted: false, current: scope))
        }
    }

    func testModeOnlyContinuationRejectsMissingOrChangedScope() {
        let mode = UUID(), interaction = UUID()
        let scope = LanguageCompositionModeTransitionScope(document: document,
            inputMode: mode, interaction: interaction, selection: nil)
        let changed: [LanguageCompositionModeTransitionScope?] = [
            nil,
            .init(document: UUID(), inputMode: mode, interaction: interaction, selection: nil),
            .init(document: document, inputMode: UUID(), interaction: interaction, selection: nil),
            .init(document: document, inputMode: mode, interaction: UUID(), selection: nil)
        ]
        for current in changed {
            XCTAssertFalse(scope.permitsContinuation(after: [.commit(text: "가", remainingInput: "")],
                commitAccepted: true, current: current))
        }
    }

    func testModeOnlyContinuationRequiresUnchangedEmptyOrUnavailableSelection() {
        let mode = UUID(), interaction = UUID()
        let selections: [[UInt8]?] = [nil, [], Array("selected".utf8)]
        for before in selections {
            let scope = LanguageCompositionModeTransitionScope(document: document,
                inputMode: mode, interaction: interaction, selection: before)
            for after in selections {
                let current = LanguageCompositionModeTransitionScope(document: document,
                    inputMode: mode, interaction: interaction, selection: after)
                XCTAssertEqual(scope.permitsContinuation(after: [.commit(text: "가", remainingInput: "")],
                    commitAccepted: true, current: current), before == after && before?.isEmpty != false)
            }
        }
    }

    func testModeOnlyContinuationRejectsPartialEmptyMultipleAndDeleteEffects() {
        let scope = LanguageCompositionModeTransitionScope(document: document,
            inputMode: UUID(), interaction: UUID(), selection: nil)
        let commit = LanguageCompositionEffect.commit(text: "가", remainingInput: "")
        let rejected: [[LanguageCompositionEffect]] = [
            [], [.hostDelete], [.commit(text: "", remainingInput: "")],
            [.commit(text: "가", remainingInput: "s")], [commit, commit],
            [commit, .hostDelete], [.hostDelete, commit]
        ]
        for effects in rejected {
            XCTAssertNil(LanguageCompositionModeTransitionScope.completeCommitText(in: effects))
            XCTAssertFalse(scope.permitsContinuation(after: effects, commitAccepted: true, current: scope))
        }
    }

    func testModesHaveStableCodableRawValues() throws {
        XCTAssertEqual(LanguageInputMode.allCases.map(\.rawValue),
                       ["direct", "japaneseRomaji", "mandarinPinyin", "koreanRomaja", "koreanTwoSetHangul"])
        for mode in LanguageInputMode.allCases {
            let data = try JSONEncoder().encode(mode)
            XCTAssertEqual(try JSONDecoder().decode(LanguageInputMode.self, from: data), mode)
        }
    }

    func testRequestAndResultCandidateCaps() throws {
        var state = makeState()
        append("nihongo", to: &state)
        let token = state.token
        for (requested, expected) in [(Int.min, 1), (-1, 1), (0, 1), (1, 1), (20, 20), (48, 48), (Int.max, 48)] {
            XCTAssertEqual(LanguageConversionRequest(token: token, rawInput: "nihongo",
                                                     candidateLimit: requested).candidateLimit, expected)
        }
        let candidates = (0..<60).map { candidate(id: "id-\($0)") }
        let request = try XCTUnwrap(state.requestConversion(candidateLimit: Int.max))
        let capped = LanguageConversionResult(token: request.token, preedit: "にほんご", candidates: candidates)
        XCTAssertEqual(capped.candidates.count, 48)
        XCTAssertTrue(state.receive(capped))
        XCTAssertEqual(state.visibleResult?.candidates.count, 48)
        XCTAssertTrue(state.choose(candidateID: "id-48", expectedToken: request.token).isEmpty)

        let small = try XCTUnwrap(state.requestConversion(candidateLimit: 1))
        XCTAssertFalse(state.receive(.init(token: small.token, preedit: "", candidates: Array(candidates.prefix(2)))))
        XCTAssertNil(state.visibleResult)
    }

    func testRawCapCountsScalarsAndRejectsEntireAppendWithoutMutation() throws {
        var state = makeState()
        XCTAssertEqual(append(String(repeating: "🙂", count: 254), to: &state), .accepted)
        XCTAssertEqual(append("e\u{0301}", to: &state), .accepted)
        XCTAssertEqual(state.rawInput.unicodeScalars.count, 256)
        XCTAssertEqual(state.rawInput.count, 255)
        let request = try XCTUnwrap(state.requestConversion())
        XCTAssertTrue(state.receive(result(request)))
        let oldToken = state.token
        var normalized = false
        XCTAssertEqual(state.append("a", origin: .normalKeyTap) { _, text in
            normalized = true
            return text
        }, .inputLimitReached)
        XCTAssertFalse(normalized)
        XCTAssertEqual(state.token, oldToken)
        XCTAssertNotNil(state.visibleResult)
        XCTAssertEqual(state.rawInput.unicodeScalars.count, 256)
        XCTAssertEqual(state.backspace(), [])
        XCTAssertEqual(state.rawInput.unicodeScalars.count, 254)
        XCTAssertEqual(append("e\u{0301}x", to: &state), .inputLimitReached)
        XCTAssertEqual(state.rawInput.unicodeScalars.count, 254)
    }

    func testOnlyNormalTapIsEligibleAndLiteralOriginsBypassWithoutNormalizationOrLookup() {
        for origin in LanguageInputOrigin.allCases where origin != .normalKeyTap {
            var state = makeState()
            let original = state.token
            var called = false
            XCTAssertEqual(state.append("abc", origin: origin) { _, text in
                called = true
                return text
            }, .bypass)
            XCTAssertFalse(called, "Origin must bypass: \(origin)")
            XCTAssertEqual(state.token, original)
            XCTAssertEqual(state.rawInput, "")
            XCTAssertNil(state.pendingRequest)
            XCTAssertNil(state.visibleResult)
        }
        var direct = LanguageCompositionState(documentID: document)
        XCTAssertEqual(direct.append("abc", origin: .normalKeyTap) { _, _ in
            XCTFail("Direct mode must not invoke a phonetic normalizer")
            return nil
        }, .bypass)
        XCTAssertNil(direct.requestConversion())
    }

    func testModeRecognizerSeesActualPinyinCharactersAndRetainsOriginalScalars() {
        var state = makeState()
        state.changeMode(to: .mandarinPinyin)
        let raw = "xi'an lu\u{0308} v"
        var observed: String?
        XCTAssertEqual(state.append(raw, origin: .normalKeyTap) { mode, proposed in
            XCTAssertEqual(mode, .mandarinPinyin)
            observed = proposed
            return "xi'an lü v" // Lookup normalization must not overwrite literal raw input.
        }, .accepted)
        assertExact(observed ?? "", raw)
        assertExact(state.rawInput, raw)
        let token = state.token
        XCTAssertEqual(state.append("?", origin: .normalKeyTap) { _, _ in nil }, .unsupportedInput)
        XCTAssertEqual(state.token, token)
        assertExact(state.rawInput, raw)
        XCTAssertEqual(append("", to: &state), .unsupportedInput)
    }

    func testExactLiteralActionsDoNotCreateEngineRequestsOrNormalizeOutputs() throws {
        var state = makeState()
        append("nihongo", to: &state)
        let oldRequest = try XCTUnwrap(state.requestConversion())
        let exact = "e\u{0301}𠀀\u{FE0F}\u{200D}🙂"
        XCTAssertEqual(state.append(exact, origin: .unicode) { _, _ in
            XCTFail("Unicode action must not be normalized")
            return nil
        }, .bypass)
        assertCommit(state.commitExact(exact, expectedToken: state.token), text: exact, remaining: "nihongo")
        XCTAssertNil(state.pendingRequest)
        XCTAssertNil(state.visibleResult)
        XCTAssertFalse(state.receive(result(oldRequest)))
        assertExact(state.rawInput, "nihongo")
        // Literal fallback is explicit, and never schedules conversion itself.
        assertCommit(state.resolveBoundary(.commitLiteral, expectedToken: state.token),
                     text: "nihongo", remaining: "")
        XCTAssertNil(state.pendingRequest)
        XCTAssertEqual(state.rawInput, "")

        append("e\u{0301}𠀀", to: &state)
        assertCommit(state.resolveBoundary(.commitLiteral, expectedToken: state.token),
                     text: "e\u{0301}𠀀", remaining: "")
    }

    func testLiteralChoiceCommitsRawUTF8InsteadOfNormalizedReadingOrPreedit() throws {
        var state = makeState()
        let raw = "NiHonGo e\u{0301} \u{2764}\u{FE0F}"
        let normalized = "nihongo é \u{2764}"
        let preedit = "にほんご é \u{2764}"
        // The reducer accepts the caller's recognizer; this deliberately changes
        // case, Unicode normalization and emoji presentation in lookup only.
        XCTAssertEqual(state.append(raw, origin: .normalKeyTap) { _, proposed in
            XCTAssertEqual(Array(proposed.utf8), Array(raw.utf8))
            return normalized
        }, .accepted)
        let stale = try XCTUnwrap(state.requestConversion())
        let current = try XCTUnwrap(state.requestConversion())
        XCTAssertEqual(Array(current.rawInput.utf8), Array(raw.utf8))
        let converted = "日本語 e\u{0301} \u{2764}\u{FE0F}"
        let selected = candidate(id: "converted", output: converted,
                                 consumed: raw.unicodeScalars.count)
        XCTAssertTrue(state.receive(.init(token: current.token, preedit: preedit,
                                          candidates: [selected])))

        let choices: [(LanguageCompositionBoundaryResolution, String)] = [
            (.commitLiteral, raw),
            (.commitSelected(candidateID: selected.id), converted)
        ]
        for (choice, expected) in choices {
            var choosing = state
            // Retrying an identical buffer must not authorize a stale tap.
            XCTAssertTrue(choosing.resolveBoundary(choice, expectedToken: stale.token).isEmpty)
            XCTAssertEqual(choosing.token, current.token)
            XCTAssertEqual(choosing.visibleResult, state.visibleResult)
            XCTAssertEqual(Array(choosing.rawInput.utf8), Array(raw.utf8))

            let effects = choosing.resolveBoundary(choice, expectedToken: current.token)
            assertCommit(effects, text: expected, remaining: "")
            guard let effect = effects.first, case .commit(let text, _) = effect else {
                return XCTFail("Expected the explicit choice to commit")
            }
            // Byte equality rejects added quotes/prefixes as well as changes to
            // case, decomposed accents or the emoji variation selector.
            XCTAssertEqual(Array(text.utf8), Array(expected.utf8))
            XCTAssertTrue(choosing.rawInput.isEmpty)
            XCTAssertNil(choosing.visibleResult)
            XCTAssertNil(choosing.pendingRequest)
            XCTAssertTrue(choosing.resolveBoundary(choice, expectedToken: current.token).isEmpty)
        }
    }

    func testEveryCandidateSourcePreservesExactOutputWithoutImplicitLookup() throws {
        for source in [LanguageConversionCandidateSource.engine, .custom, .literal, .hiragana, .katakana] {
            var state = makeState()
            append("nihongo", to: &state)
            let request = try XCTUnwrap(state.requestConversion())
            let exact = "e\u{0301}𠀀\u{FE0F}"
            let value = LanguageConversionCandidate(id: "exact", output: exact, source: source,
                                                      consumedInputScalars: 7)
            XCTAssertTrue(state.receive(.init(token: request.token, preedit: "not the committed text",
                                              candidates: [value])))
            assertCommit(state.choose(candidateID: "exact", expectedToken: request.token),
                         text: exact, remaining: "")
            XCTAssertNil(state.pendingRequest)
        }
    }

    func testValueEqualityDoesNotHideChangesToExactOutputOrRawScalars() {
        let token = makeState().token
        let decomposed = "e\u{0301}"
        let composed = "é"
        XCTAssertNotEqual(LanguageConversionRequest(token: token, rawInput: decomposed),
                          LanguageConversionRequest(token: token, rawInput: composed))
        let a = candidate(output: decomposed)
        let b = candidate(output: composed)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(LanguageConversionResult(token: token, preedit: decomposed, candidates: [a]),
                          LanguageConversionResult(token: token, preedit: composed, candidates: [a]))
        XCTAssertNotEqual(LanguageCompositionEffect.commit(text: decomposed, remainingInput: ""),
                          LanguageCompositionEffect.commit(text: composed, remainingInput: ""))
        XCTAssertNotEqual(LanguageCompositionEffect.commit(text: "", remainingInput: decomposed),
                          LanguageCompositionEffect.commit(text: "", remainingInput: composed))
    }

    func testPartialConsumptionUsesOriginalScalarCountNotKanaOrUTF16() throws {
        var state = makeState()
        let original = "🙂e\u{0301}xyz"
        append(original, to: &state)
        let request = try XCTUnwrap(state.requestConversion())
        assertExact(request.rawInput, original)
        let output = "𠀀e\u{0301}\u{FE0F}"
        let partial = LanguageConversionCandidate(id: "partial", output: output, source: .custom,
                                                   consumedInputScalars: 3)
        XCTAssertTrue(state.receive(.init(token: request.token, preedit: "arbitrary engine kana",
                                          candidates: [partial])))
        assertCommit(state.choose(candidateID: "partial", expectedToken: request.token),
                     text: output, remaining: "xyz")
        XCTAssertEqual(state.rawInput, "xyz")
        XCTAssertNil(state.visibleResult)
        XCTAssertNil(state.pendingRequest)
        XCTAssertTrue(state.choose(candidateID: "partial", expectedToken: request.token).isEmpty)
        let remainder = try XCTUnwrap(state.requestConversion())
        XCTAssertEqual(remainder.rawInput, "xyz")
    }

    func testConsumptionMayEndAtAnyScalarBoundaryWithoutSplittingUTF16() throws {
        var state = makeState()
        append("🙂e\u{0301}", to: &state)
        let request = try XCTUnwrap(state.requestConversion())
        XCTAssertTrue(state.receive(.init(token: request.token, preedit: "",
                                          candidates: [candidate(output: "X", consumed: 2)])))
        assertCommit(state.choose(candidateID: "reused", expectedToken: request.token),
                     text: "X", remaining: "\u{0301}")
        assertExact(state.rawInput, "\u{0301}")
    }

    func testMalformedConsumptionAndDuplicateCandidateIDsAreNotSelectable() throws {
        for count in [Int.min, -1, 0, 8, Int.max] {
            var state = makeState()
            append("nihongo", to: &state)
            let request = try XCTUnwrap(state.requestConversion())
            XCTAssertFalse(state.receive(.init(token: request.token, preedit: "",
                                               candidates: [candidate(consumed: count)])))
            XCTAssertNil(state.visibleResult)
            XCTAssertNil(state.pendingRequest)
            XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: request.token).isEmpty)
            XCTAssertFalse(state.receive(result(request)), "Malformed response consumed request authority")
        }
        for ids in [["same", "same"], [""]] {
            var state = makeState()
            append("nihongo", to: &state)
            let request = try XCTUnwrap(state.requestConversion())
            XCTAssertFalse(state.receive(.init(token: request.token, preedit: "",
                                               candidates: ids.map { candidate(id: $0) })))
            XCTAssertNil(state.visibleResult)
        }
    }

    func testEmptyCandidateOutputRejectsResultWithoutDiscardingRawOrCommitting() throws {
        var state = makeState()
        let raw = "🙂e\u{0301}nihongo"
        append(raw, to: &state)
        let request = try XCTUnwrap(state.requestConversion())
        let empty = candidate(output: "", consumed: raw.unicodeScalars.count)
        XCTAssertFalse(state.receive(.init(token: request.token, preedit: "", candidates: [empty])))
        assertExact(state.rawInput, raw)
        XCTAssertEqual(state.token, request.token)
        XCTAssertNil(state.visibleResult)
        XCTAssertNil(state.pendingRequest)
        XCTAssertTrue(state.choose(candidateID: empty.id, expectedToken: request.token).isEmpty)
        XCTAssertTrue(state.resolveBoundary(.commitSelected(candidateID: empty.id),
                                             expectedToken: request.token).isEmpty)
        assertExact(state.rawInput, raw)
        XCTAssertFalse(state.receive(result(request)), "Malformed result must consume request authority")

        // Nonempty whitespace/combining output is legitimate exact text; reject
        // only isEmpty, without trimming or normalizing anything.
        let retry = try XCTUnwrap(state.requestConversion())
        let exact = " \u{0301}\t"
        XCTAssertTrue(state.receive(result(retry, output: exact)))
        assertCommit(state.choose(candidateID: "reused", expectedToken: retry.token),
                     text: exact, remaining: "")
    }

    func testFullTokenRequiredForResultAndCandidateAction() throws {
        var state = makeState()
        append("nihongo", to: &state)
        let request = try XCTUnwrap(state.requestConversion())
        let t = request.token
        let wrongTokens: [LanguageCompositionToken] = [
            .init(documentID: UUID(), mode: t.mode, revision: t.revision,
                  packRevision: t.packRevision, dictionaryRevision: t.dictionaryRevision),
            .init(documentID: t.documentID, mode: .mandarinPinyin, revision: t.revision,
                  packRevision: t.packRevision, dictionaryRevision: t.dictionaryRevision),
            .init(documentID: t.documentID, mode: t.mode, revision: t.revision - 1,
                  packRevision: t.packRevision, dictionaryRevision: t.dictionaryRevision),
            .init(documentID: t.documentID, mode: t.mode, revision: t.revision,
                  packRevision: "pack-2", dictionaryRevision: t.dictionaryRevision),
            .init(documentID: t.documentID, mode: t.mode, revision: t.revision,
                  packRevision: t.packRevision, dictionaryRevision: t.dictionaryRevision + 1)
        ]
        for wrong in wrongTokens {
            XCTAssertFalse(state.receive(.init(token: wrong, preedit: "", candidates: [candidate()])))
            XCTAssertEqual(state.pendingRequest?.token, t)
        }
        XCTAssertTrue(state.receive(result(request)))
        for wrong in wrongTokens {
            XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: wrong).isEmpty)
            XCTAssertTrue(state.resolveBoundary(.commitLiteral, expectedToken: wrong).isEmpty)
            XCTAssertTrue(state.resolveBoundary(.cancel, expectedToken: wrong).isEmpty)
            XCTAssertTrue(state.commitExact("literal", expectedToken: wrong).isEmpty)
            XCTAssertEqual(state.token, t)
            XCTAssertEqual(state.rawInput, "nihongo")
        }
        assertCommit(state.choose(candidateID: "reused", expectedToken: t), text: "日本語", remaining: "")
        XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: t).isEmpty)
    }

    func testCandidateIDReuseDoesNotAuthorizeAnOldTap() throws {
        var state = makeState()
        append("nihongo", to: &state)
        let first = try XCTUnwrap(state.requestConversion())
        XCTAssertTrue(state.receive(result(first, output: "old")))
        let second = try XCTUnwrap(state.requestConversion())
        XCTAssertNotEqual(second.token, first.token)
        XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: second.token).isEmpty,
                      "Pending results are not visible candidates")
        XCTAssertTrue(state.receive(result(second, output: "new")))
        XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: first.token).isEmpty)
        XCTAssertEqual(state.visibleResult?.token, second.token)
        assertCommit(state.choose(candidateID: "reused", expectedToken: second.token), text: "new", remaining: "")
    }

    func testReorderedAsyncEngineResultsIncludingIdenticalBufferRetries() async throws {
        var state = makeState()
        append("nihongo", to: &state)
        let first = try XCTUnwrap(state.requestConversion())
        let second = try XCTUnwrap(state.requestConversion())
        XCTAssertEqual(first.rawInput, second.rawInput)
        let engine = ReorderingLanguageEngine()
        async let oldResult = engine.convert(first)
        async let newResult = engine.convert(second)
        await engine.waitUntilRequested(first.token)
        await engine.waitUntilRequested(second.token)
        await engine.complete(second, output: "new")
        let new = try await newResult
        XCTAssertTrue(state.receive(new))
        await engine.complete(first, output: "old")
        let old = try await oldResult
        XCTAssertFalse(state.receive(old))
        XCTAssertFalse(state.receive(new), "A completed request cannot replay its response")
        XCTAssertEqual(state.visibleResult?.token, second.token)
        XCTAssertTrue(state.choose(candidateID: "stable", expectedToken: first.token).isEmpty)
        assertCommit(state.choose(candidateID: "stable", expectedToken: second.token), text: "new", remaining: "")
    }

    func testEditingBeforeAnAsyncResultRevokesIt() throws {
        var state = makeState()
        append("ni", to: &state)
        let old = try XCTUnwrap(state.requestConversion())
        append("hongo", to: &state)
        XCTAssertFalse(state.receive(result(old)))
        XCTAssertNil(state.visibleResult)
        XCTAssertEqual(state.rawInput, "nihongo")
        let current = try XCTUnwrap(state.requestConversion())
        XCTAssertTrue(state.receive(result(current)))
        XCTAssertEqual(state.backspace(), [])
        XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: current.token).isEmpty)
        XCTAssertNil(state.visibleResult)
    }

    func testModeAndDocumentBoundariesAlwaysClearWithoutHostWrites() throws {
        for boundary in 0..<4 {
            var state = makeState()
            append("nihongo", to: &state)
            let old = try XCTUnwrap(state.requestConversion())
            XCTAssertTrue(state.receive(result(old)))
            switch boundary {
            case 0: state.changeMode(to: .koreanRomaja)
            case 1: state.changeDocument(to: UUID())
            case 2: state.changeDocument(to: document) // Selection/context change within same field.
            default: state.changeMode(to: .japaneseRomaji)
            }
            XCTAssertEqual(state.rawInput, "")
            XCTAssertNil(state.visibleResult)
            XCTAssertNil(state.pendingRequest)
            XCTAssertFalse(state.receive(result(old)))
            XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: old.token).isEmpty)
            XCTAssertNil(state.requestConversion())
        }
    }

    func testResourceChangesRevokeVisibleAndInflightEntriesEvenIfAnIdentityReturns() throws {
        for changePack in [false, true] {
            for visible in [false, true] {
                var state = makeState()
                append("nihongo", to: &state)
                let old = try XCTUnwrap(state.requestConversion())
                if visible { XCTAssertTrue(state.receive(result(old))) }
                state.changeResources(packRevision: changePack ? "pack-2" : "pack-1",
                                      dictionaryRevision: changePack ? 7 : 8)
                XCTAssertEqual(state.rawInput, "nihongo")
                XCTAssertNil(state.pendingRequest)
                XCTAssertNil(state.visibleResult)
                XCTAssertFalse(state.receive(result(old)))
                XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: old.token).isEmpty)
                state.changeResources(packRevision: "pack-1", dictionaryRevision: 7)
                XCTAssertFalse(state.receive(result(old)))
                let current = try XCTUnwrap(state.requestConversion())
                XCTAssertTrue(state.receive(result(current)))
                XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: old.token).isEmpty)
                assertCommit(state.choose(candidateID: "reused", expectedToken: current.token),
                             text: "日本語", remaining: "")
            }
        }
    }

    func testPackIdentityUsesExactBytesNotCanonicalStringEquality() {
        let a = LanguageCompositionToken(documentID: document, mode: .japaneseRomaji, revision: 1,
                                         packRevision: "e\u{0301}", dictionaryRevision: 1)
        let b = LanguageCompositionToken(documentID: document, mode: .japaneseRomaji, revision: 1,
                                         packRevision: "é", dictionaryRevision: 1)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(Set([a, b]).count, 2)
    }

    func testBackspaceDeletesOneVisibleCharacterThenRequestsHostDelete() throws {
        var state = makeState()
        append("a🙂e\u{0301}", to: &state)
        let request = try XCTUnwrap(state.requestConversion())
        XCTAssertEqual(state.backspace(), [])
        assertExact(state.rawInput, "a🙂")
        XCTAssertFalse(state.receive(result(request)))
        XCTAssertEqual(state.backspace(), [])
        XCTAssertEqual(state.rawInput, "a")
        XCTAssertEqual(state.backspace(), [])
        XCTAssertEqual(state.rawInput, "")
        XCTAssertEqual(state.backspace(), [.hostDelete])
        XCTAssertNil(state.pendingRequest)
        XCTAssertNil(state.visibleResult)
    }

    func testCancelAndDisappearDiscardWithoutCommittingAndInvalidateLateResults() throws {
        for disappear in [false, true] {
            var state = makeState()
            append("nihongo", to: &state)
            let request = try XCTUnwrap(state.requestConversion())
            if disappear { state.disappear() } else { state.cancel() }
            XCTAssertEqual(state.rawInput, "")
            XCTAssertNil(state.visibleResult)
            XCTAssertNil(state.pendingRequest)
            XCTAssertFalse(state.receive(result(request)))
            XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: request.token).isEmpty)
            XCTAssertTrue(state.resolveBoundary(.commitLiteral, expectedToken: state.token).isEmpty)
            XCTAssertEqual(state.backspace(), [.hostDelete])
        }
    }

    func testBoundaryChoicesAreInjectedAndNeverImplicitlyFallback() throws {
        var state = makeState()
        append("nihongo", to: &state)
        let pending = try XCTUnwrap(state.requestConversion())
        XCTAssertTrue(state.resolveBoundary(.commitSelected(candidateID: "reused"), expectedToken: state.token).isEmpty)
        XCTAssertEqual(state.rawInput, "nihongo")
        XCTAssertTrue(state.receive(result(pending)))
        let visible = state.token
        XCTAssertTrue(state.resolveBoundary(.keep, expectedToken: visible).isEmpty)
        XCTAssertEqual(state.token, visible)
        XCTAssertEqual(state.visibleResult?.token, visible)
        XCTAssertTrue(state.resolveBoundary(.commitSelected(candidateID: "absent"), expectedToken: visible).isEmpty)
        assertCommit(state.resolveBoundary(.commitSelected(candidateID: "reused"), expectedToken: visible),
                     text: "日本語", remaining: "")
        append("literal", to: &state)
        assertCommit(state.resolveBoundary(.commitLiteral, expectedToken: state.token), text: "literal", remaining: "")
        append("cancel me", to: &state)
        XCTAssertTrue(state.resolveBoundary(.cancel, expectedToken: state.token).isEmpty)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertNil(state.visibleResult)
    }

    func testExplicitUnavailableStatusesCannotSupplySelectableCandidates() throws {
        for status in [LanguageConversionStatus.missingResources, .unsupportedMode, .unsupportedInput, .failed] {
            var state = makeState()
            append("nihongo", to: &state)
            let first = try XCTUnwrap(state.requestConversion())
            XCTAssertFalse(state.receive(.init(token: first.token, preedit: "", candidates: [candidate()], status: status)))
            let second = try XCTUnwrap(state.requestConversion())
            XCTAssertTrue(state.receive(.init(token: second.token, preedit: "nihongo", candidates: [], status: status)))
            XCTAssertEqual(state.visibleResult?.status, status)
            XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: second.token).isEmpty)
            assertCommit(state.resolveBoundary(.commitLiteral, expectedToken: state.token), text: "nihongo", remaining: "")
        }
    }

    func testRevisionOverflowFailsClosedWithoutWrappingOrCommitting() throws {
        var state = makeState(revision: UInt64.max - 2)
        append("nihongo", to: &state)
        let last = try XCTUnwrap(state.requestConversion())
        XCTAssertEqual(last.token.revision, UInt64.max)
        XCTAssertTrue(state.receive(result(last)))
        XCTAssertTrue(state.choose(candidateID: "reused", expectedToken: last.token).isEmpty)
        XCTAssertTrue(state.isRevisionExhausted)
        XCTAssertEqual(state.revision, UInt64.max)
        XCTAssertEqual(state.rawInput, "")
        XCTAssertNil(state.visibleResult)
        XCTAssertNil(state.pendingRequest)
        XCTAssertFalse(state.receive(result(last)))
        XCTAssertTrue(state.commitExact("do not insert", expectedToken: last.token).isEmpty)
        XCTAssertTrue(state.backspace().isEmpty)
        XCTAssertEqual(append("x", to: &state), .revisionExhausted)
        XCTAssertNil(state.requestConversion())
        state.changeResources(packRevision: "pack-2", dictionaryRevision: 8)
        state.changeDocument(to: UUID())
        state.changeMode(to: .mandarinPinyin)
        state.cancel()
        XCTAssertEqual(state.revision, UInt64.max)
        XCTAssertTrue(state.isRevisionExhausted)
    }

    func testOverflowDuringRequestAndLiteralBoundaryCannotEmitWrites() {
        var state = makeState(revision: UInt64.max - 1)
        append("e\u{0301}", to: &state)
        XCTAssertEqual(state.revision, UInt64.max)
        XCTAssertTrue(state.resolveBoundary(.commitLiteral, expectedToken: state.token).isEmpty)
        XCTAssertTrue(state.isRevisionExhausted)
        XCTAssertEqual(state.rawInput, "")

        var requestOverflow = makeState(revision: UInt64.max - 1)
        append("x", to: &requestOverflow)
        XCTAssertNil(requestOverflow.requestConversion())
        XCTAssertTrue(requestOverflow.isRevisionExhausted)
        XCTAssertEqual(requestOverflow.rawInput, "")
    }
}

/// A deterministic suspended engine: the test explicitly completes the newer
/// request first. No timers, sleeps, unchecked Sendable or arbitrary MainActor.
private actor ReorderingLanguageEngine: LanguageConversionEngine {
    private var pending: [LanguageCompositionToken: CheckedContinuation<LanguageConversionResult, Error>] = [:]
    private var observers: [LanguageCompositionToken: [CheckedContinuation<Void, Never>]] = [:]

    func convert(_ request: LanguageConversionRequest) async throws -> LanguageConversionResult {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.token] = continuation
            let waiting = observers.removeValue(forKey: request.token) ?? []
            for observer in waiting { observer.resume() }
        }
    }

    func waitUntilRequested(_ token: LanguageCompositionToken) async {
        if pending[token] != nil { return }
        await withCheckedContinuation { continuation in
            observers[token, default: []].append(continuation)
        }
    }

    func complete(_ request: LanguageConversionRequest, output: String) {
        let candidate = LanguageConversionCandidate(id: "stable", output: output, source: .engine,
                                                     consumedInputScalars: request.rawInput.unicodeScalars.count)
        pending.removeValue(forKey: request.token)?.resume(returning:
            .init(token: request.token, preedit: request.rawInput, candidates: [candidate]))
    }
}
