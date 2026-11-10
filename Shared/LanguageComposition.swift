import Foundation

public enum LanguageInputMode: String, Codable, CaseIterable, Sendable {
    case direct
    case japaneseRomaji
    case mandarinPinyin
    case koreanRomaja
    case koreanTwoSetHangul
}

public enum LanguageCompositionLimits {
    public static let rawInputScalars = 256
    public static let candidates = 48
}

/// A document ID is a fresh identity for a document/focus session, not a host's
/// reusable field identifier. Never reuse it when constructing a new state.
/// Transient tokens and typed buffers must not be persisted or logged.
public struct LanguageCompositionToken: Hashable, Sendable {
    public let documentID: UUID
    public let mode: LanguageInputMode
    public let revision: UInt64
    public let packRevision: String
    public let dictionaryRevision: UInt64

    public init(documentID: UUID, mode: LanguageInputMode, revision: UInt64,
                packRevision: String, dictionaryRevision: UInt64) {
        self.documentID = documentID
        self.mode = mode
        self.revision = revision
        self.packRevision = packRevision
        self.dictionaryRevision = dictionaryRevision
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.documentID == rhs.documentID && lhs.mode == rhs.mode && lhs.revision == rhs.revision
            && lhs.packRevision.utf8.elementsEqual(rhs.packRevision.utf8)
            && lhs.dictionaryRevision == rhs.dictionaryRevision
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(documentID)
        hasher.combine(mode)
        hasher.combine(revision)
        hasher.combine(Array(packRevision.utf8))
        hasher.combine(dictionaryRevision)
    }
}

public struct LanguageConversionRequest: Equatable, Sendable {
    public let token: LanguageCompositionToken
    /// Original input, in exactly the scalar sequence accepted by the state.
    /// Engines may normalize a private lookup reading, never the literal buffer.
    public let rawInput: String
    public let candidateLimit: Int

    public init(token: LanguageCompositionToken, rawInput: String, candidateLimit: Int = 48) {
        self.token = token
        self.rawInput = rawInput
        self.candidateLimit = min(max(candidateLimit, 1), LanguageCompositionLimits.candidates)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token && lhs.rawInput.utf8.elementsEqual(rhs.rawInput.utf8)
            && lhs.candidateLimit == rhs.candidateLimit
    }
}

public enum LanguageConversionCandidateSource: String, Sendable {
    case engine
    case custom
    case literal
    case hiragana
    case katakana
}

public struct LanguageConversionCandidate: Identifiable, Equatable, Sendable {
    /// Stable within a result. IDs may be reused in other results: they are
    /// deliberately NOT sufficient authority for selection without a token.
    public let id: String
    public let output: String
    public let source: LanguageConversionCandidateSource
    /// Number of ORIGINAL request.rawInput Unicode scalars consumed, not kana,
    /// Characters, UTF-8 bytes, UTF-16 units or a normalized reading's length.
    /// Whole-buffer adapters should use request.rawInput.unicodeScalars.count.
    public let consumedInputScalars: Int

    public init(id: String, output: String, source: LanguageConversionCandidateSource,
                consumedInputScalars: Int) {
        self.id = id
        self.output = output
        self.source = source
        self.consumedInputScalars = consumedInputScalars
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.output.utf8.elementsEqual(rhs.output.utf8)
            && lhs.source == rhs.source && lhs.consumedInputScalars == rhs.consumedInputScalars
    }
}

/// No unstructured engine error messages or typed text are needed for UI status.
public enum LanguageConversionStatus: Sendable, Equatable {
    case ready
    case missingResources
    case unsupportedMode
    case unsupportedInput
    case failed
}

public struct LanguageConversionResult: Equatable, Sendable {
    public let token: LanguageCompositionToken
    public let preedit: String
    public let candidates: [LanguageConversionCandidate]
    public let status: LanguageConversionStatus

    public init(token: LanguageCompositionToken, preedit: String,
                candidates: [LanguageConversionCandidate], status: LanguageConversionStatus = .ready) {
        self.token = token
        self.preedit = preedit
        self.candidates = Array(candidates.prefix(LanguageCompositionLimits.candidates))
        self.status = status
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.token == rhs.token && lhs.preedit.utf8.elementsEqual(rhs.preedit.utf8)
            && lhs.candidates == rhs.candidates && lhs.status == rhs.status
    }
}

/// Implement mutable adapters as actors (or otherwise provide real isolation).
/// The owner runs/cancels the async work and returns its result to the reducer;
/// cancellation alone is not sufficient protection against late completion.
public protocol LanguageConversionEngine: Sendable {
    func convert(_ request: LanguageConversionRequest) async throws -> LanguageConversionResult
}

public enum LanguageInputOrigin: CaseIterable, Equatable, Sendable {
    case normalKeyTap
    case customTap
    case hold
    case swipe
    case unicode
    case symbol
    case diacritic
    case shiftSlide
    case query
    case literal
}

public enum LanguageCompositionInputDisposition: Equatable, Sendable {
    case accepted
    /// No mutation, normalization, engine request or host write. Route through
    /// the existing action path (a query, for example, is NOT literal host text).
    case bypass
    case unsupportedInput
    case inputLimitReached
    case revisionExhausted
}

/// No Space, Return, punctuation or dismiss policy is embedded here. A caller
/// must inject the approved decision, including which visible candidate to use.
public enum LanguageCompositionBoundaryResolution: Equatable, Sendable {
    case commitSelected(candidateID: String)
    case commitLiteral
    case cancel
    case keep
}

public enum LanguageCompositionEffect: Equatable, Sendable {
    /// The adapter inserts exactly text, then leaves remainingInput local.
    /// Applying this synchronously to the current document is the owner's job;
    /// do not queue host writes across a focus/context transition.
    case commit(text: String, remainingInput: String)
    case hostDelete

    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.hostDelete, .hostDelete):
            return true
        case let (.commit(leftText, leftRemaining), .commit(rightText, rightRemaining)):
            return leftText.utf8.elementsEqual(rightText.utf8)
                && leftRemaining.utf8.elementsEqual(rightRemaining.utf8)
        default:
            return false
        }
    }
}

/// Authority only for a non-host-writing input/layout continuation after ONE
/// complete commit. Deliberately has no before/after text: a proxy need not expose
/// the resulting context to change local UI. This is NOT host-write authority.
/// The owner must still validate the full composition anchor before inserting.
public struct LanguageCompositionModeTransitionScope: Equatable, Sendable {
    public let document: UUID
    /// Must change on focus/selection boundaries, even when document/text match.
    public let inputMode: UUID
    public let interaction: UUID
    /// Preserve unavailable versus known-empty selection; never normalize nil.
    public let selection: [UInt8]?

    public init(document: UUID, inputMode: UUID, interaction: UUID, selection: [UInt8]?) {
        self.document = document
        self.inputMode = inputMode
        self.interaction = interaction
        self.selection = selection
    }

    public static func completeCommitText(in effects: [LanguageCompositionEffect]) -> String? {
        guard effects.count == 1, case .commit(let text, let remaining) = effects[0],
              !text.isEmpty, remaining.isEmpty else { return nil }
        return text
    }

    public func permitsContinuation(after effects: [LanguageCompositionEffect],
                                    commitAccepted: Bool, current: Self?) -> Bool {
        commitAccepted && Self.completeCommitText(in: effects) != nil
            && selection?.isEmpty != false && current == self
    }
}

/// Pure in-memory reducer. Its owner serializes mutations; immutable requests
/// and results can cross actors. There is no proxy I/O, task creation, storage,
/// networking, automatic learning, logging or implicit engine execution here.
public struct LanguageCompositionState: Sendable {
    public private(set) var documentID: UUID
    public private(set) var mode: LanguageInputMode
    public private(set) var revision: UInt64
    public private(set) var packRevision: String
    public private(set) var dictionaryRevision: UInt64
    public private(set) var rawInput = ""
    public private(set) var visibleResult: LanguageConversionResult?
    public private(set) var pendingRequest: LanguageConversionRequest?
    /// Checked-overflow policy: permanently fail closed rather than wrap a
    /// revision. Recovery requires a new state with a NEW document identity.
    public private(set) var isRevisionExhausted = false

    public init(documentID: UUID, mode: LanguageInputMode = .direct,
                packRevision: String = "", dictionaryRevision: UInt64 = 0,
                revision: UInt64 = 0) {
        self.documentID = documentID
        self.mode = mode
        self.packRevision = packRevision
        self.dictionaryRevision = dictionaryRevision
        self.revision = revision
    }

    public var token: LanguageCompositionToken {
        .init(documentID: documentID, mode: mode, revision: revision,
              packRevision: packRevision, dictionaryRevision: dictionaryRevision)
    }

    /// Only normal key taps in phonetic modes are eligible. The caller supplies
    /// its audited mode-specific normalizer/recognizer for the ENTIRE proposed
    /// raw reading, including actual apostrophes, v/ü, combining marks, etc.
    /// nil rejects input. A non-nil normalized reading authorizes composition,
    /// but we retain the ORIGINAL raw sequence for exact literal fallback and
    /// scalar-consumption accounting. Engine adapters normalize their own lookup
    /// readings. No ASCII-only eligibility heuristic is used.
    @discardableResult
    public mutating func append(_ text: String, origin: LanguageInputOrigin,
                                normalize: (LanguageInputMode, String) -> String?)
        -> LanguageCompositionInputDisposition {
        guard origin == .normalKeyTap, mode != .direct else { return .bypass }
        guard !isRevisionExhausted else { return .revisionExhausted }
        guard !text.isEmpty else { return .unsupportedInput }
        // Bound before concatenating/calling externally supplied normalization.
        let remaining = LanguageCompositionLimits.rawInputScalars - rawInput.unicodeScalars.count
        guard text.unicodeScalars.prefix(remaining + 1).count <= remaining else {
            return .inputLimitReached
        }
        let proposed = rawInput + text
        guard normalize(mode, proposed) != nil else { return .unsupportedInput }
        guard advanceRevision() else { return .revisionExhausted }
        rawInput = proposed
        return .accepted
    }

    /// Explicit scheduling, separate from input/literal actions. Even a retry
    /// gets a new revision so reordered identical-buffer requests cannot win.
    /// The caller may cancel the previously pending task to save work.
    public mutating func requestConversion(candidateLimit: Int = 48) -> LanguageConversionRequest? {
        guard !isRevisionExhausted, mode != .direct, !rawInput.isEmpty,
              advanceRevision() else { return nil }
        let request = LanguageConversionRequest(token: token, rawInput: rawInput,
                                                candidateLimit: candidateLimit)
        pendingRequest = request
        return request
    }

    /// Returns false for stale, replayed or malformed results. A matching bad
    /// result consumes the pending request but cannot leave selectable entries.
    @discardableResult
    public mutating func receive(_ result: LanguageConversionResult) -> Bool {
        guard !isRevisionExhausted, let pendingRequest,
              pendingRequest.token == token, result.token == pendingRequest.token else { return false }
        self.pendingRequest = nil
        visibleResult = nil
        let candidates = result.candidates
        guard candidates.count <= pendingRequest.candidateLimit else { return false }
        if result.status != .ready {
            guard candidates.isEmpty else { return false }
        } else {
            if mode == .koreanTwoSetHangul {
                guard candidates.count == 1, let word = candidates.first,
                      word.source == .engine, word.consumedInputScalars == rawInput.unicodeScalars.count,
                      word.output.utf8.elementsEqual(result.preedit.utf8),
                      word.output.unicodeScalars.allSatisfy({ (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x3163).contains($0.value) }) else { return false }
            }
            var ids = Set<String>()
            let count = rawInput.unicodeScalars.count
            for candidate in candidates {
                guard !candidate.id.isEmpty, !candidate.output.isEmpty,
                      ids.insert(candidate.id).inserted,
                      candidate.consumedInputScalars > 0,
                      candidate.consumedInputScalars <= count else { return false }
            }
        }
        visibleResult = result
        return true
    }

    public mutating func choose(candidateID: String, expectedToken: LanguageCompositionToken, suffix: String = "")
        -> [LanguageCompositionEffect] {
        guard isCurrent(expectedToken), let result = visibleResult,
              result.token == expectedToken, result.status == .ready,
              let candidate = result.candidates.first(where: { $0.id == candidateID }) else { return [] }
        let scalars = rawInput.unicodeScalars
        guard candidate.consumedInputScalars > 0,
              candidate.consumedInputScalars <= scalars.count,
              suffix.isEmpty || candidate.consumedInputScalars == scalars.count else { return [] }
        // Index in the scalar view, never by UTF-16 or normalized-engine length.
        // Every permitted consumption count lands on a Unicode scalar boundary.
        let end = scalars.index(scalars.startIndex, offsetBy: candidate.consumedInputScalars)
        let remaining = String(String.UnicodeScalarView(scalars[end...]))
        guard advanceRevision() else { return [] }
        rawInput = remaining
        return [.commit(text: candidate.output + suffix, remainingInput: remaining)]
    }

    /// Explicit exact-text action for an existing literal/custom/Unicode path.
    /// It does not resolve an unfinished composition or start an engine lookup.
    /// If ordering requires a boundary, resolve it FIRST using the injected
    /// policy and pass the resulting current token to this action.
    public mutating func commitExact(_ text: String, expectedToken: LanguageCompositionToken)
        -> [LanguageCompositionEffect] {
        guard isCurrent(expectedToken), !text.isEmpty, advanceRevision() else { return [] }
        return [.commit(text: text, remainingInput: rawInput)]
    }

    public mutating func resolveBoundary(_ resolution: LanguageCompositionBoundaryResolution,
                                         expectedToken: LanguageCompositionToken)
        -> [LanguageCompositionEffect] {
        guard isCurrent(expectedToken) else { return [] }
        switch resolution {
        case .keep:
            return []
        case .cancel:
            cancel()
            return []
        case .commitSelected(let candidateID):
            return choose(candidateID: candidateID, expectedToken: expectedToken)
        case .commitLiteral:
            guard mode != .koreanTwoSetHangul, !rawInput.isEmpty else { return [] }
            let literal = rawInput
            guard advanceRevision() else { return [] }
            rawInput = ""
            return [.commit(text: literal, remainingInput: "")]
        }
    }

    /// Delete a visible extended grapheme (Character), not just its last scalar.
    /// Only an empty local composition asks the owner to delete from the host.
    public mutating func backspace() -> [LanguageCompositionEffect] {
        guard !isRevisionExhausted else { return [] }
        let wasEmpty = rawInput.isEmpty
        guard advanceRevision() else { return [] }
        if wasEmpty { return [.hostDelete] }
        rawInput.removeLast()
        return []
    }

    /// Cancellation and disappearance never commit unfinished text.
    public mutating func cancel() {
        _ = advanceRevision()
        rawInput = ""
    }

    public mutating func disappear() { cancel() }

    /// Call on ANY focus, selection, cursor or externally changed host-context
    /// boundary, even if the caller still reports the same document identity.
    public mutating func changeDocument(to documentID: UUID) {
        cancel()
        self.documentID = documentID
    }

    public mutating func changeMode(to mode: LanguageInputMode) {
        cancel()
        self.mode = mode
    }

    /// Resource activation/removal or custom-dictionary changes revoke every
    /// visible/pending entry. Keep raw input local so an explicit new lookup or
    /// literal choice remains possible; never auto-commit or auto-request.
    public mutating func changeResources(packRevision: String, dictionaryRevision: UInt64) {
        _ = advanceRevision()
        self.packRevision = packRevision
        self.dictionaryRevision = dictionaryRevision
    }

    private func isCurrent(_ expectedToken: LanguageCompositionToken) -> Bool {
        !isRevisionExhausted && token == expectedToken
    }

    /// All successful edits/actions invalidate BOTH pending and visible state.
    /// Overflow clears the local buffer, revokes authority and emits no writes.
    @discardableResult
    private mutating func advanceRevision() -> Bool {
        pendingRequest = nil
        visibleResult = nil
        guard !isRevisionExhausted, revision < UInt64.max else {
            isRevisionExhausted = true
            rawInput = ""
            return false
        }
        revision += 1
        return true
    }
}
