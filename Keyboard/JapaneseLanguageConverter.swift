import Foundation
import KanaKanjiConverterModule

/// UI-owned isolation is deliberate: the pinned converter is mutable/non-Sendable
/// (not itself @MainActor), and the non-Sendable pack lease must never cross actors.
/// Requests/results alone are Sendable. No host text insertion or automatic commit.
@MainActor
public final class JapaneseLanguageConverter: LanguageConversionEngine {
    public static let engineABI = "azookey-80b8204f1cdfb364bb2ed355cf52c7ebb2519a0c"

    public enum InitializationError: Error {
        case invalidInstalledPack
        case invalidScratchDirectory
    }

    /// The reducer only accepts candidates on `.ready` results. Local kana can be
    /// ready while kanji is unavailable; the owner MUST expose this separate status.
    /// DEBUG explicitly disables kanji: upstream DEBUG logging includes typed text.
    public let kanjiResourceStatus: LanguageConversionStatus
    public let packRevision: String
    private let installed: InstalledEngine?
    private let scratchDirectoryURL: URL

    /// Supply both the verified Dictionary directory and its live lease, or neither
    /// for honest kana-only mode. The caller relinquishes use of/release authority
    /// over this lease until the adapter is destroyed. Never pass a released lease.
    /// Scratch must be an existing, dedicated child of this process's temp directory.
    public init(installedDictionaryURL: URL? = nil, lease: LanguagePackReadLease? = nil,
                scratchDirectoryURL: URL) throws {
        let scratch = scratchDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard scratch.isFileURL, scratch.path.hasPrefix(temporary.path + "/"),
              FileManager.default.fileExists(atPath: scratch.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw InitializationError.invalidScratchDirectory }
        self.scratchDirectoryURL = scratch

        switch (installedDictionaryURL, lease) {
        case (nil, nil):
            installed = nil
            packRevision = ""
            kanjiResourceStatus = .missingResources
        case let (dictionaryURL?, lease?):
            let expected = lease.pack.path.appendingPathComponent("Dictionary", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            let actual = dictionaryURL.standardizedFileURL.resolvingSymlinksInPath()
            guard actual.isFileURL, actual.path == expected.path,
                  lease.pack.descriptor.modeID == LanguageInputMode.japaneseRomaji.rawValue,
                  lease.pack.descriptor.engineABI == Self.engineABI else {
                throw InitializationError.invalidInstalledPack
            }
            packRevision = lease.pack.revision
            #if DEBUG
            // SwiftUtils.debug prints composing input when the dependency uses DEBUG.
            // Do not invoke the dictionary converter in a debug app build. A release
            // build (or independently audited dependency logging fix) is required.
            installed = InstalledEngine(lease: lease, dictionaryURL: nil)
            kanjiResourceStatus = .failed
            #else
            installed = InstalledEngine(lease: lease, dictionaryURL: actual)
            kanjiResourceStatus = .ready
            #endif
        default:
            throw InitializationError.invalidInstalledPack
        }
    }

    public func convert(_ request: LanguageConversionRequest) async throws -> LanguageConversionResult {
        try Task.checkCancellation()
        guard request.token.mode == .japaneseRomaji else {
            return empty(request, status: .unsupportedMode)
        }
        guard request.token.packRevision.utf8.elementsEqual(packRevision.utf8) else {
            return empty(request, status: .missingResources)
        }
        guard !request.rawInput.isEmpty, let reading = JapaneseInputReading.parse(request.rawInput) else {
            return empty(request, status: .unsupportedInput)
        }
        let consumed = request.rawInput.unicodeScalars.count
        let limit = min(request.candidateLimit, LanguageCompositionLimits.candidates)
        var local: [LanguageConversionCandidate] = []
        // Never label unfinished Roman suffixes as completed kana. A final n can be
        // explicitly selected as ん without rewriting the unfinished local preedit.
        if let complete = JapaneseInputReading.parse(request.rawInput, finalizeTrailingN: true),
           complete.isComplete {
            local.append(.init(id: "ja-hiragana", output: complete.kana, source: .hiragana,
                               consumedInputScalars: consumed))
            if let katakana = complete.kana.applyingTransform(.hiraganaToKatakana, reverse: false) {
                local.append(.init(id: "ja-katakana", output: katakana, source: .katakana,
                                   consumedInputScalars: consumed))
            }
        }
        local.append(.init(id: "ja-literal", output: request.rawInput, source: .literal,
                           consumedInputScalars: consumed))
        local = Array(local.prefix(limit))
        var candidates: [LanguageConversionCandidate] = []
        let engineLimit = limit - local.count
        if reading.isComplete, engineLimit > 0, let converter = installed?.converter {
            // Feed the stable shared kana normalization directly. No reliance on
            // Roman/kana index equivalence: only full-input candidates are exposed.
            var composing = ComposingText()
            composing.insertAtCursorPosition(reading.kana, inputStyle: .direct)
            converter.stopComposition()
            defer { converter.stopComposition() }
            let options = ConvertRequestOptions(
                N_best: min(10, engineLimit), needTypoCorrection: false,
                requireJapanesePrediction: false, requireEnglishPrediction: false,
                keyboardLanguage: .ja_JP, englishCandidateInRoman2KanaInput: false,
                learningType: .nothing, memoryDirectoryURL: scratchDirectoryURL,
                sharedContainerURL: scratchDirectoryURL, textReplacer: .empty,
                specialCandidateProviders: [], zenzaiMode: .off, preloadDictionary: false,
                metadata: nil
            )
            let results = converter.requestCandidates(composing, options: options)
            var seen = Set(local.map { Array($0.output.utf8) })
            for candidate in results.mainResults {
                guard candidates.count < engineLimit else { break }
                guard candidate.inputable, candidate.actions.isEmpty, !candidate.text.isEmpty,
                      candidate.composingCount == .inputCount(composing.input.count)
                        || candidate.composingCount == .surfaceCount(composing.convertTarget.count),
                      seen.insert(Array(candidate.text.utf8)).inserted else { continue }
                candidates.append(.init(id: "ja-engine-\(candidates.count)", output: candidate.text,
                                        source: .engine, consumedInputScalars: consumed))
            }
        }
        try Task.checkCancellation()
        return .init(token: request.token, preedit: reading.kana,
                     candidates: candidates + local, status: .ready)
    }

    private func empty(_ request: LanguageConversionRequest,
                       status: LanguageConversionStatus) -> LanguageConversionResult {
        .init(token: request.token, preedit: request.rawInput, candidates: [], status: status)
    }

    /// Destruction order is explicit: destroy the converter before dropping the lock
    /// lease, including all lazy shard/cache users. No @unchecked Sendable escape.
    private final class InstalledEngine {
        let lease: LanguagePackReadLease
        private(set) var converter: KanaKanjiConverter?

        init(lease: LanguagePackReadLease, dictionaryURL: URL?) {
            self.lease = lease
            converter = dictionaryURL.map { KanaKanjiConverter(dictionaryURL: $0, preloadDictionary: false) }
        }

        deinit { converter = nil }
    }
}
