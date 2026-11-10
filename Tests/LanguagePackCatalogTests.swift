#if canImport(Uniboard) || canImport(LanguagePackCatalogTransport)
import XCTest
import Foundation
#if canImport(LanguagePackCatalogTransport)
@testable import LanguagePackCatalogTransport
#else
@testable import Uniboard
#endif

final class LanguagePackCatalogTests: XCTestCase {
    private func catalog() throws -> LanguagePackCatalog {
        #if canImport(LanguagePackCatalogTransport)
        return try LanguagePackCatalog.load(bundle: .module)
        #else
        return try LanguagePackCatalog.load(bundle: .main)
        #endif
    }

    func testBundledMetadataDescribesFiveOptionalUnbundledMandarinDownloads() throws {
        let catalog = try catalog()
        let sources = try catalog.validatedMandarinSourceDescriptors()
        XCTAssertEqual(sources.count, 5)
        XCTAssertEqual(catalog.mandarinFiles.count, 5)
        XCTAssertTrue(catalog.mandarinFiles.allSatisfy { !$0.isBundled })
        XCTAssertEqual(catalog.mandarinDownloadBytes, 49_238_294)
        XCTAssertEqual(sources.reduce(Int64(0)) { $0 + $1.archiveByteCount }, 49_238_294)
        XCTAssertTrue(catalog.mandarinSource.contains("Five optional source files"))
        XCTAssertTrue(catalog.mandarinSource.contains("49,238,294 bytes"))
        XCTAssertFalse(catalog.mandarinSource.contains("49,085,918"))
        // Exercise REAL bundled legal/provenance metadata, not hand-written short notices.
        XCTAssertGreaterThan(catalog.mandarinLicense.utf8.count, 25_000)
        XCTAssertGreaterThan(catalog.mandarinSource.utf8.count, 1_000)
        let resources = [MandarinDictionaryCompiler.jichu, MandarinDictionaryCompiler.zi,
                         MandarinDictionaryCompiler.characters, MandarinDictionaryCompiler.phrases,
                         MandarinDictionaryCompiler.compatibility]
        for (source, resource) in zip(sources, resources) {
            XCTAssertNoThrow(try source.validate())
            XCTAssertEqual(source.version, MandarinDictionaryCompiler.corpusCommit)
            XCTAssertEqual(source.modeID, LanguageInputMode.mandarinPinyin.rawValue)
            XCTAssertEqual(source.engineABI, LanguagePackCatalog.mandarinABI)
            XCTAssertEqual(source.sourceURL, resource.downloadURL)
            XCTAssertEqual(source.allowedHosts, ["raw.githubusercontent.com"])
            XCTAssertEqual(source.archiveByteCount, Int64(resource.bytes))
            XCTAssertEqual(source.archiveSHA256, resource.sha256)
            XCTAssertEqual(source.files, [.init(path: resource.filename, byteCount: Int64(resource.bytes), sha256: resource.sha256)])
            XCTAssertEqual(source.licenseNotice, catalog.mandarinLicense)
            XCTAssertEqual(source.sourceNotice, catalog.mandarinSource)
        }
        XCTAssertEqual(sources.map { $0.files[0].path }, ["jichu.dict.yaml", "zi.dict.yaml", "TSCharacters.txt",
                                                        "TSPhrases.txt", "CJK_Compatibility_Ideographs.txt"])
        XCTAssertEqual(sources.map(\.archiveByteCount), [48_469_368, 616_550, 104_516, 8_786, 39_074])
        // The installed pack uses this original primary identity, NOT the new total.
        let primary = try XCTUnwrap(sources.first)
        XCTAssertEqual(primary.packID, "wanxiang-source-0")
        XCTAssertEqual(primary.sourceURL, MandarinDictionaryCompiler.jichu.downloadURL)
        XCTAssertEqual(primary.archiveByteCount, 48_469_368)
        XCTAssertEqual(primary.archiveSHA256, "74abd0a8013d5bbc0f397280fa0949d83234f005690e1631786e9ba9b466a74e")
    }

    func testCompilerInputValidationRejectsWrongOrderMissingDuplicateBundledAndSubstitutedFiles() throws {
        let catalog = try catalog()
        func replacingFiles(_ files: [LanguagePackCatalog.SourceFile]) -> LanguagePackCatalog {
            LanguagePackCatalog(japanese: catalog.japanese, japaneseEngineNotices: catalog.japaneseEngineNotices,
                                mandarinFiles: files, mandarinLicense: catalog.mandarinLicense,
                                mandarinSource: catalog.mandarinSource)
        }
        let files = catalog.mandarinFiles
        var reordered = files
        reordered.swapAt(2, 3)
        var duplicated = files
        duplicated[4] = files[2]
        for invalid in [Array(files.prefix(2)), Array(files.dropLast()), files + [files[0]],
                        Array(files.reversed()), reordered, duplicated] {
            XCTAssertThrowsError(try replacingFiles(invalid).validatedMandarinSourceDescriptors())
        }
        let mapping = files[2]
        let substitutions: [LanguagePackCatalog.SourceFile] = [
            .init(name: mapping.name, url: mapping.url, bytes: mapping.bytes, sha256: mapping.sha256, isBundled: true),
            .init(name: "Other.txt", url: mapping.url, bytes: mapping.bytes, sha256: mapping.sha256),
            .init(name: mapping.name, url: URL(string: "https://raw.githubusercontent.com/other/file.txt")!,
                  bytes: mapping.bytes, sha256: mapping.sha256),
            .init(name: mapping.name, url: mapping.url, bytes: mapping.bytes + 1, sha256: mapping.sha256),
            .init(name: mapping.name, url: mapping.url, bytes: mapping.bytes, sha256: String(repeating: "0", count: 64))
        ]
        for substitution in substitutions {
            var invalid = files
            invalid[2] = substitution
            XCTAssertThrowsError(try replacingFiles(invalid).validatedMandarinSourceDescriptors())
        }
    }

    func testDescriptorConstructionAndCodingPreserveTrustedSourceEquivalence() throws {
        let catalog = try catalog()
        let first = catalog.mandarinSourceDescriptors
        XCTAssertEqual(first, catalog.mandarinSourceDescriptors)
        for source in first {
            let encoded = try JSONEncoder().encode(source)
            XCTAssertLessThanOrEqual(encoded.count, LanguagePackDescriptor.maximumManifestBytes)
            let decoded = try LanguagePackDescriptor.validated(from: encoded)
            XCTAssertEqual(source, decoded)
            XCTAssertTrue(catalog.mandarinSourceDescriptors.contains(decoded))
        }
    }

    func testRealCatalogDescriptorsPassDownloaderPreflightAndReachTransport() async throws {
        let catalog = try catalog()
        let sources = try catalog.validatedMandarinSourceDescriptors()
        XCTAssertEqual(sources.count, 5)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let downloader = LanguagePackDownloader(trustedSources: sources) {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [CatalogUnavailableSourceFixture.self]
            return configuration
        }
        for source in sources {
            let equivalent = try LanguagePackDescriptor.validated(from: JSONEncoder().encode(source))
            do {
                _ = try await downloader.download(source: equivalent, scratchDirectory: scratch)
                XCTFail("Synthetic source must return its sanitized HTTP status")
            } catch let error as LanguagePackDownloadError {
                // Not invalidSource: validates every actual metadata field AND
                // descriptor equality before creating the URLSession request.
                XCTAssertEqual(error, .httpStatus(503))
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: scratch.path), [])
    }
}

private final class CatalogUnavailableSourceFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([0]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
