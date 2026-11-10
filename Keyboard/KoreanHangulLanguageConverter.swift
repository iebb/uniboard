import Foundation

/// A data-required adapter, with no bundled or missing-resource fallback.
/// The worker validates mapping JSON off-main while holding a verified lease;
/// this UI-owned adapter retains that lease until the active engine is released.
@MainActor
final class KoreanHangulLanguageConverter: LanguageConversionEngine {
    static let engineABI = "uniboard-hangul-1"
    static let mappingFilename = "mapping.json"
    enum InitializationError: Error { case invalidInstalledPack, nonstandardMapping }
    private let composer: KoreanHangulComposer
    private let lease: LanguagePackReadLease

    nonisolated static func prepare(mappingJSON: Data) throws -> KoreanHangulComposer.KeyMapping {
        let mapping = try KoreanHangulComposer.KeyMapping(jsonData: mappingJSON)
        // The core validates all 52 keys structurally. This particular pack also
        // promises standard two-set semantics, not an arbitrary custom layout.
        let composer = KoreanHangulComposer(mapping: mapping)
        for byte in Array(UInt8(65)...UInt8(90)) + Array(UInt8(97)...UInt8(122)) {
            let key = String(Unicode.Scalar(byte))
            guard try composer.compose(key) == KoreanTwoSetKeyboard.label(for: key) else {
                throw InitializationError.nonstandardMapping
            }
        }
        return mapping
    }

    init(mapping: KoreanHangulComposer.KeyMapping, lease: LanguagePackReadLease) throws {
        guard lease.pack.descriptor.modeID == LanguageInputMode.koreanTwoSetHangul.rawValue,
              lease.pack.descriptor.packID == "korean-hangul-2set",
              lease.pack.descriptor.version == "1",
              lease.pack.descriptor.engineABI == Self.engineABI,
              lease.pack.descriptor.files.contains(where: { $0.path == Self.mappingFilename }) else {
            throw InitializationError.invalidInstalledPack
        }
        self.lease = lease
        composer = KoreanHangulComposer(mapping: mapping)
    }

    func convert(_ request: LanguageConversionRequest) async throws -> LanguageConversionResult {
        try Task.checkCancellation()
        guard request.token.mode == .koreanTwoSetHangul else {
            return .init(token: request.token, preedit: "", candidates: [], status: .unsupportedMode)
        }
        guard request.token.packRevision == lease.pack.revision else {
            return .init(token: request.token, preedit: "", candidates: [], status: .missingResources)
        }
        guard KoreanTwoSetKeyboard.accepts(request.rawInput), let text = try? composer.compose(request.rawInput), !text.isEmpty else {
            return .init(token: request.token, preedit: "", candidates: [], status: .unsupportedInput)
        }
        return .init(token: request.token, preedit: text, candidates: [
            .init(id: "hangul-word", output: text, source: .engine,
                  consumedInputScalars: request.rawInput.unicodeScalars.count)
        ])
    }
}
