import Foundation

/// UI-owned adapter, matching the existing Japanese adapter's lease isolation.
/// Only bounded read-only lookups occur here. Compilation/downloads are app-only.
/// No host insertion, silent correction, learning, logging, or network requests.
@MainActor
public final class MandarinLanguageConverter: LanguageConversionEngine {
    public static let engineABI = MandarinDictionaryIndex.engineABI
    public static let databaseFilename = "Mandarin.sqlite"

    public enum InitializationError: Error {
        case invalidInstalledPack
    }

    public let packRevision: String
    public let resourceStatus: LanguageConversionStatus
    private let installed: InstalledEngine?

    /// Supply BOTH the store-verified database URL and its live read lease, or
    /// neither for missing-resource mode. Caller relinquishes release/use of the
    /// lease for the lifetime of this converter. A schema check is not a substitute
    /// for LanguagePackStore's authenticated descriptor/file verification.
    public init(installedDictionaryURL: URL? = nil, lease: LanguagePackReadLease? = nil) throws {
        switch (installedDictionaryURL, lease) {
        case (nil, nil):
            installed = nil
            packRevision = ""
            resourceStatus = .missingResources
        case let (databaseURL?, lease?):
            let expected = lease.pack.path.appendingPathComponent(Self.databaseFilename)
                .standardizedFileURL.resolvingSymlinksInPath()
            let actual = databaseURL.standardizedFileURL.resolvingSymlinksInPath()
            guard actual.isFileURL, actual.path == expected.path,
                  lease.pack.descriptor.modeID == LanguageInputMode.mandarinPinyin.rawValue,
                  lease.pack.descriptor.engineABI == Self.engineABI,
                  lease.pack.descriptor.files.contains(where: { $0.path == Self.databaseFilename }) else {
                throw InitializationError.invalidInstalledPack
            }
            installed = try InstalledEngine(lease: lease, databaseURL: actual)
            packRevision = lease.pack.revision
            resourceStatus = .ready
        default:
            throw InitializationError.invalidInstalledPack
        }
    }

    public func convert(_ request: LanguageConversionRequest) async throws -> LanguageConversionResult {
        try Task.checkCancellation()
        guard request.token.mode == .mandarinPinyin else {
            return empty(request, status: .unsupportedMode)
        }
        guard request.token.packRevision.utf8.elementsEqual(packRevision.utf8),
              let index = installed?.index else {
            return empty(request, status: .missingResources)
        }
        guard !request.rawInput.isEmpty else { return empty(request, status: .unsupportedInput) }
        let limit = min(request.candidateLimit, LanguageCompositionLimits.candidates)
        // Reserve a literal escape when there is room, but do not suppress every
        // Chinese candidate when a caller explicitly asks for only one result.
        let engineLimit = max(1, limit - 1)
        let page: MandarinDictionaryPage
        do {
            // Full-reading word/phrase candidates only. Prefix completion and
            // capped paging are separate explicit MandarinDictionaryIndex APIs;
            // this whole-buffer protocol never silently enables prediction.
            page = try index.lookup(request.rawInput, limit: engineLimit)
        } catch MandarinDictionaryError.invalidReading {
            return empty(request, status: .unsupportedInput)
        } catch {
            return empty(request, status: .failed)
        }
        try Task.checkCancellation()
        let consumed = request.rawInput.unicodeScalars.count
        var candidates = page.candidates.enumerated().map { position, candidate in
            LanguageConversionCandidate(id: "zh-engine-\(position)", output: candidate.text,
                source: .engine, consumedInputScalars: consumed)
        }
        if candidates.count < limit,
           !candidates.contains(where: { $0.output.utf8.elementsEqual(request.rawInput.utf8) }) {
            candidates.append(.init(id: "zh-literal", output: request.rawInput,
                source: .literal, consumedInputScalars: consumed))
        }
        return .init(token: request.token, preedit: request.rawInput, candidates: candidates, status: .ready)
    }

    private func empty(_ request: LanguageConversionRequest,
                       status: LanguageConversionStatus) -> LanguageConversionResult {
        .init(token: request.token, preedit: request.rawInput, candidates: [], status: status)
    }

    /// Close SQLite before releasing the version lease. No unchecked Sendable.
    private final class InstalledEngine {
        let lease: LanguagePackReadLease
        private(set) var index: MandarinDictionaryIndex?
        init(lease: LanguagePackReadLease, databaseURL: URL) throws {
            self.lease = lease
            index = try MandarinDictionaryIndex(url: databaseURL)
        }
        deinit { index = nil }
    }
}
