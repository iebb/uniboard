import Foundation

/// Bundled metadata and notices only. No dictionary/model bytes are bundled here.
struct LanguagePackCatalog: Sendable {
    struct SourceFile: Identifiable, Sendable {
        var id: String { name }
        let name: String
        let url: URL
        let bytes: Int64
        let sha256: String
        let isBundled: Bool
        init(name: String, url: URL, bytes: Int64, sha256: String, isBundled: Bool = false) {
            self.name = name; self.url = url; self.bytes = bytes; self.sha256 = sha256; self.isBundled = isBundled
        }
    }

    var koreanTwoSet: LanguagePackDescriptor? = nil
    let japanese: LanguagePackDescriptor
    let japaneseEngineNotices: String?
    let mandarinFiles: [SourceFile]
    let mandarinLicense: String
    let mandarinSource: String

    static let japaneseABI = "azookey-80b8204f1cdfb364bb2ed355cf52c7ebb2519a0c"
    static let mandarinABI = "uniboard-pinyin-1"
    static let koreanABI = "uniboard-hangul-1"

    /// Real full-corpus compile-twice report: mandarin-validation/remote/
    /// command-output/results/report.json, compiler wanxiang-simplified-subset-1.
    /// Both outputs: 155,074,560 SQLite bytes; SHA-256
    /// bda47d87d0b095d57ee606bbfa1338e82c1f2ad4d853c52171959a4168601f7f.
    /// This is a measured disk size, not an extension-memory estimate. Do not
    /// reuse it for another compiler or source pin; local compilation is rehashed.
    static var measuredMandarinDatabaseBytes: Int64? {
        guard MandarinDictionaryIndex.compilerVersion == "wanxiang-simplified-subset-1",
              MandarinDictionaryCompiler.corpusCommit == "aa9947f3f513ff88a3f7ce4e342fcb519d517025",
              MandarinDictionaryCompiler.mappingCommit == "26753884f1984add422f3b0249ccee8613deaff6" else { return nil }
        return 155_074_560
    }

    /// Compiler order is fixed: corpus first, then the three Simplified mappings.
    static let mandarinResources = [MandarinDictionaryCompiler.jichu, MandarinDictionaryCompiler.zi,
                                   MandarinDictionaryCompiler.characters, MandarinDictionaryCompiler.phrases,
                                   MandarinDictionaryCompiler.compatibility]

    /// Call off the main executor: reads and validates the full per-file catalog.
    static func load(bundle: Bundle = .main) throws -> Self {
        func resource(_ name: String, extension ext: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "LanguagePacks")
                ?? bundle.url(forResource: name, withExtension: ext) else { throw CatalogError.missingResource }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        let japanese = try LanguagePackDescriptor.validated(from: resource("japanese-pack-v1", extension: "json"))
        guard japanese.modeID == LanguageInputMode.japaneseRomaji.rawValue,
              japanese.engineABI == japaneseABI else { throw CatalogError.invalidResource }
        let files = mandarinResources.map { resource in
            SourceFile(name: resource.filename, url: resource.downloadURL,
                       bytes: Int64(resource.bytes), sha256: resource.sha256)
        }
        let wanxiang = String(decoding: try resource("Wanxiang-LICENSE", extension: "txt"), as: UTF8.self)
        let openCC = String(decoding: try resource("OpenCC-LICENSE", extension: "txt"), as: UTF8.self)
        let engineNotices = try? resource("japanese-engine-notices", extension: "txt")
        let korean = try? LanguagePackDescriptor.validated(from: resource("korean-hangul-2set-v1", extension: "json"))
        if let korean { try validateKoreanDescriptor(korean) }
        return Self(koreanTwoSet: korean, japanese: japanese,
                    japaneseEngineNotices: engineNotices.map { String(decoding: $0, as: UTF8.self) },
                    mandarinFiles: files,
                    mandarinLicense: "Wanxiang — CC BY 4.0\n\n" + wanxiang + "\n\nOpenCC — Apache-2.0\n\n" + openCC,
                    mandarinSource: "万象词库 / 万象拼音 (Wanxiang), author amzxyz. Corpus commit \(MandarinDictionaryCompiler.corpusCommit). Five optional source files: jichu.dict.yaml, zi.dict.yaml, TSCharacters.txt, TSPhrases.txt and CJK_Compatibility_Ideographs.txt. All five download only when you choose Download; none are bundled. Simplified adaptation uses OpenCC mapping commit \(MandarinDictionaryCompiler.mappingCommit). Downloads are static files from raw.githubusercontent.com, not server conversion. The app-side compiler verifies every source, excludes three specifically audited malformed corpus rows, combines matching entries at maximum weight and indexes a conservative Simplified mapping subset. This is not the complete OpenCC t2s conversion and does not reproduce Wanxiang’s language model. Traditional output is not available. No Rime engine, schema or executable code is downloaded. Original source and license links are available below; no endorsement is implied. Network transfer is 49,238,294 bytes for all five optional files, including the three independently verified OpenCC mappings. The installed descriptor’s primary source identity is the original jichu URL, 48,469,368 bytes and its listed SHA-256; it is not the aggregate network size or the compiled SQLite identity. The SQLite size/hash are measured locally after verified compilation.")
    }

    var mandarinDownloadBytes: Int64 { mandarinFiles.reduce(0) { $0 + $1.bytes } }
    func mandarinInstalledBytes(databaseBytes: Int64) -> Int64 { databaseBytes + Int64(mandarinLicense.utf8.count) }

    /// Each raw upstream file is independently pinned; these descriptors describe
    /// REAL SOURCE bytes, not the as-yet-uncompiled SQLite output. The transport
    /// verifies raw bytes and does not require the response to be a tar archive.
    var mandarinSourceDescriptors: [LanguagePackDescriptor] {
        mandarinFiles.enumerated().map { position, file in
            LanguagePackDescriptor(packID: "wanxiang-source-\(position)",
                version: MandarinDictionaryCompiler.corpusCommit, modeID: LanguageInputMode.mandarinPinyin.rawValue,
                engineABI: Self.mandarinABI, sourceURL: file.url, allowedHosts: ["raw.githubusercontent.com"],
                archiveByteCount: file.bytes, archiveSHA256: file.sha256,
                installedBytes: file.bytes, fileCount: 1,
                files: [.init(path: file.name, byteCount: file.bytes, sha256: file.sha256)],
                licenseNotice: mandarinLicense, sourceNotice: mandarinSource)
        }
    }
    /// Reject missing, reordered, duplicate, bundled or substituted inputs before
    /// transport. Download results can then safely use the compiler's fixed order;
    /// in particular, descriptor zero remains the original jichu source identity.
    func validatedMandarinSourceDescriptors() throws -> [LanguagePackDescriptor] {
        guard mandarinFiles.count == Self.mandarinResources.count else { throw CatalogError.invalidResource }
        for (file, resource) in zip(mandarinFiles, Self.mandarinResources) {
            guard !file.isBundled, file.name == resource.filename,
                  file.url == resource.downloadURL, file.bytes == Int64(resource.bytes),
                  file.sha256 == resource.sha256 else { throw CatalogError.invalidResource }
        }
        let sources = mandarinSourceDescriptors
        for source in sources { try source.validate() }
        return sources
    }

    /// Runtime policy owns ABI identity, independently of persisted preferences.
    static func engineABI(for mode: LanguageInputMode) -> String? { mode.conversionEngineABI }

    static func validateKoreanDescriptor(_ descriptor: LanguagePackDescriptor) throws {
        try descriptor.validate()
        guard descriptor.packID == "korean-hangul-2set", descriptor.version == "1",
              descriptor.modeID == LanguageInputMode.koreanTwoSetHangul.rawValue,
              descriptor.engineABI == koreanABI,
              Set(descriptor.files.map(\.path)) == Set(["mapping.json", "LICENSE.txt", "SOURCE.txt"]),
              let mapping = descriptor.files.first(where: { $0.path == "mapping.json" }),
              mapping.byteCount > 0, mapping.byteCount <= KoreanHangulComposer.KeyMapping.maximumJSONBytes else {
            throw CatalogError.invalidResource
        }
    }

    /// Run while a verified lease/staging directory is held, before publication,
    /// readiness, or enablement. A descriptor alone never authorizes the engine.
    static func validateKoreanPayload(at directory: URL, descriptor: LanguagePackDescriptor) throws {
        try validateKoreanDescriptor(descriptor)
        guard let data = try SharedConfigurationLocation.readRegularFile(directory.appendingPathComponent("mapping.json"),
            limit: KoreanHangulComposer.KeyMapping.maximumJSONBytes + 1) else { throw CatalogError.invalidResource }
        let mapping = try KoreanHangulComposer.KeyMapping(jsonData: data)
        let composer = KoreanHangulComposer(mapping: mapping)
        // Exact standard key assignments, including the seven Shift forms.
        for key in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let id = String(key)
            guard try composer.compose(id) == KoreanTwoSetKeyboard.label(for: id) else {
                throw CatalogError.invalidResource
            }
        }
    }

    enum CatalogError: Error { case missingResource, invalidResource }
}
