import Foundation
import XCTest
import CryptoKit
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UnicodeFontAssetsTests: XCTestCase {
    private func asset(filename: String = "Fixture.ttf", hash: String = String(repeating: "a", count: 64),
                       ranges: [[UInt32]] = [[65, 66]]) -> UnicodeFontAsset {
        .init(filename: filename, displayName: "Fixture", postScriptName: "Fixture-Regular", sha256: hash,
              sourceURL: "https://example.com/font.ttf", licenseFilename: "OFL.txt", ranges: ranges)
    }
    private func download(_ data: Data, filename: String = "Fixture.ttf") -> UnicodeFontDownload {
        .init(asset: asset(filename: filename, hash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()),
              bytes: Int64(data.count), downloadURL: UnicodeFontPackCatalog.downloadBase + filename)
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func fixture(_ data: Data, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(UUID().uuidString + ".ttf")
        try data.write(to: url)
        return url
    }
    private var fontBytes: Data { Data([0, 1, 0, 0] + Array(repeating: 7, count: 100)) }

    func testAssetFilenamesDigestsAndBinarySearchBoundaries() {
        let a = asset(ranges: [[65, 66], [0x10000, 0x10002]])
        XCTAssertTrue(a.isValid)
        for point: UInt32 in [65, 66, 0x10000, 0x10002] { XCTAssertTrue(a.contains(point)) }
        for point: UInt32 in [0, 64, 67, 0xFFFF, 0x10003, UInt32.max] { XCTAssertFalse(a.contains(point)) }
        XCTAssertFalse(asset(ranges: [[]]).contains(1))
        for name in ["", ".", "..", "../a.ttf", "/a.ttf", "a/b.ttf", "a\\b.ttf", "a\0.ttf", String(repeating: "a", count: 161)] {
            XCTAssertFalse(asset(filename: name).isValid, name)
        }
        for hash in ["", String(repeating: "A", count: 64), String(repeating: "g", count: 64)] {
            XCTAssertFalse(asset(hash: hash).isValid)
        }
        for ranges: [[UInt32]] in [[], [[]], [[2, 1]], [[0xD800, 0xD800]], [[1, 4], [4, 5]], [[0x110000, 0x110000]]] {
            XCTAssertFalse(asset(ranges: ranges).isValid)
        }
    }

    func testDownloadURLIsPinnedAndByteBudgetsAreStrict() {
        let a = asset()
        XCTAssertTrue(UnicodeFontDownload(asset: a, bytes: 1, downloadURL: UnicodeFontPackCatalog.downloadBase + a.filename).isValid)
        XCTAssertTrue(UnicodeFontDownload(asset: a, bytes: 1, downloadURL: UnicodeFontPackCatalog.completionDownloadBase + a.filename).isValid)
        XCTAssertTrue(UnicodeFontDownload(asset: a, bytes: 1, downloadURL: UnicodeFontPackCatalog.emojiDownloadBase + a.filename).isValid)
        XCTAssertFalse(UnicodeFontDownload(asset: a, bytes: 1, downloadURL: "https://github.com/iebb/emojifonts/releases/download/latest/" + a.filename).isValid,
                       "A rolling release cannot satisfy a pinned digest")
        for url in ["http://github.com/font.ttf", UnicodeFontPackCatalog.downloadBase + "other.ttf",
                    UnicodeFontPackCatalog.downloadBase + a.filename + "?token=x", "https://evil.example/font.ttf"] {
            XCTAssertFalse(UnicodeFontDownload(asset: a, bytes: 1, downloadURL: url).isValid)
        }
        for url in [UnicodeFontPackCatalog.completionDownloadBase + "other.ttf",
                    UnicodeFontPackCatalog.completionDownloadBase + a.filename + "?token=x",
                    UnicodeFontPackCatalog.completionDownloadBase.replacingOccurrences(of: "-complete/", with: "-unreviewed/") + a.filename] {
            XCTAssertFalse(UnicodeFontDownload(asset: a, bytes: 1, downloadURL: url).isValid)
        }
        for size: Int64 in [0, -1, 40 * 1024 * 1024 + 1, Int64.max] {
            XCTAssertFalse(UnicodeFontDownload(asset: a, bytes: size, downloadURL: UnicodeFontPackCatalog.downloadBase + a.filename).isValid)
        }
        for name in ["a?b.ttf", "a#b.ttf", "a%20b.ttf", "字.ttf", "font.zip"] {
            XCTAssertFalse(download(fontBytes, filename: name).isValid)
        }
        for url in ["https://github.com/path", "https://release-assets.githubusercontent.com/file?signature=x", "https://objects.githubusercontent.com/file"] {
            XCTAssertTrue(UnicodeFontPackCatalog.allowsRedirect(URL(string: url)!))
        }
        for url in ["http://github.com/file", "https://github.com.evil.example/file", "https://evilgithub.com/file",
                    "https://user:secret@github.com/file", "https://github.com:444/file", "https:/missing-host.ttf", "file:///tmp/font.ttf"] {
            XCTAssertFalse(UnicodeFontPackCatalog.allowsRedirect(URL(string: url)!))
        }
        for count: Int64 in [0, 50, 100] { XCTAssertTrue(UnicodeFontPackCatalog.acceptsProgress(count, expected: 100)) }
        for count: Int64 in [-1, 101, Int64.max] { XCTAssertFalse(UnicodeFontPackCatalog.acceptsProgress(count, expected: 100)) }
        XCTAssertFalse(UnicodeFontPackCatalog.acceptsProgress(0, expected: 0))
        XCTAssertFalse(UnicodeFontPackCatalog.acceptsProgress(0, expected: 40 * 1024 * 1024 + 1))
    }

    func testCatalogRejectsMalformedUnknownDuplicateAndOversizedMetadata() throws {
        let pack = UnicodeFontPack(id: "fixture", title: "Fixture", detail: "Native coverage", fonts: [download(fontBytes)])
        let good = UnicodeFontPackCatalog(schemaVersion: 1, unicodeVersion: "18.0.0", packs: [pack])
        XCTAssertTrue(good.isValid)
        XCTAssertEqual(pack.bytes, Int64(fontBytes.count))
        XCTAssertFalse(UnicodeFontPackCatalog(schemaVersion: 2, unicodeVersion: "18.0.0", packs: [pack]).isValid)
        XCTAssertFalse(UnicodeFontPackCatalog(schemaVersion: 1, unicodeVersion: "19.0.0", packs: [pack]).isValid)
        XCTAssertFalse(UnicodeFontPackCatalog(schemaVersion: 1, unicodeVersion: "18.0.0", packs: [pack, pack]).isValid)
        XCTAssertFalse(UnicodeFontPackCatalog(schemaVersion: 1, unicodeVersion: "18.0.0", packs: Array(repeating: pack, count: 9)).isValid)
        for id in ["", "../escape", "UPPER", String(repeating: "a", count: 41)] {
            XCTAssertFalse(UnicodeFontPackCatalog(schemaVersion: 1, unicodeVersion: "18.0.0", packs: [
                .init(id: id, title: "x", detail: "x", fonts: pack.fonts)]).isValid)
        }
        for p in [UnicodeFontPack(id: "x", title: "", detail: "x", fonts: pack.fonts),
                  .init(id: "x", title: "x", detail: "", fonts: pack.fonts),
                  .init(id: "x", title: "x", detail: "x", fonts: []),
                  .init(id: "x", title: "x", detail: "x", fonts: pack.fonts + pack.fonts)] {
            XCTAssertFalse(UnicodeFontPackCatalog(schemaVersion: 1, unicodeVersion: "18.0.0", packs: [p]).isValid)
        }
        for data in [Data(), Data("null".utf8), Data("{bad".utf8), Data(repeating: 0, count: UnicodeFontPackCatalog.maximumCatalogBytes + 1)] {
            XCTAssertNil(UnicodeFontPackCatalog.load(data: data))
        }
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fonts/DownloadableFonts.json")
        if FileManager.default.fileExists(atPath: path.path) {
            let catalog = try XCTUnwrap(UnicodeFontPackCatalog.load(data: Data(contentsOf: path)))
            XCTAssertEqual(catalog.packs.count, 6)
            XCTAssertEqual(catalog.packs.first?.id, "preview-basics", "Preview fonts download on demand first")
            XCTAssertEqual(catalog.packs.flatMap(\.fonts).count, 73)
            let emoji = try XCTUnwrap(catalog.packs.first { $0.id == "emoji" })
            XCTAssertEqual(emoji.fonts.map(\.asset.postScriptName), ["NotoColorEmoji", "UniboardCoverage068-Regular"],
                           "The complete sbix fallback is tried before the Unicode 18 COLR subset")
            XCTAssertLessThanOrEqual(catalog.packs.flatMap(\.fonts).reduce(Int64(0)) { $0 + $1.bytes }, UnicodeFontPackCatalog.maximumTotalBytes)
            XCTAssertEqual(UnicodeFontPackCatalog.loadBundled(resourceURL: path).packs.count, 6)
        }
        XCTAssertTrue(UnicodeFontPackCatalog.loadBundled(resourceURL: nil).packs.isEmpty)
        XCTAssertTrue(UnicodeFontPackCatalog.loadBundled(resourceURL: URL(fileURLWithPath: "/nonexistent/uniboard-font-catalog")).packs.isEmpty)
        _ = UnicodeFontPackCatalog.bundled
    }

    func testInstallVerifiesBeforePublicationAndSupportsReplacementRemovalAndRetry() throws {
        let root = try folder(), source = try fixture(fontBytes, in: root)
        let store = UnicodeFontDownloadStore(directory: root.appendingPathComponent("shared"))
        let font = download(fontBytes)
        XCTAssertNil(store.installedURL(for: font))
        XCTAssertEqual(store.revision, "")
        try store.install(source, font: font)
        let url = try XCTUnwrap(store.installedURL(for: font))
        XCTAssertEqual(try Data(contentsOf: url), fontBytes)
        XCTAssertEqual(try store.directory!.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        let revision = store.revision
        XCTAssertNotNil(UUID(uuidString: revision))
        try store.install(source, font: font)
        XCTAssertNotNil(store.installedURL(for: font))
        XCTAssertNotEqual(store.revision, revision)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: store.directory!.path).contains { $0.hasPrefix(".incoming-") })
        try store.remove(font)
        XCTAssertNil(store.installedURL(for: font))
        try store.remove(font)
        try store.install(source, font: font)
        XCTAssertNotNil(store.installedURL(for: font))
    }

    func testCorruptSizeDigestHeaderReceiptAndChangedFileFailClosed() throws {
        let root = try folder(), source = try fixture(fontBytes, in: root)
        let store = UnicodeFontDownloadStore(directory: root.appendingPathComponent("shared"))
        let font = download(fontBytes)
        let wrongHash = UnicodeFontDownload(asset: asset(hash: String(repeating: "b", count: 64)),
            bytes: font.bytes, downloadURL: font.downloadURL)
        XCTAssertThrowsError(try store.install(source, font: wrongHash))
        XCTAssertNil(store.installedURL(for: font))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory!.path))
        let small = try fixture(Data([0, 1, 0, 0]), in: root)
        XCTAssertThrowsError(try store.install(small, font: font))
        let invalid = Data(repeating: 3, count: 104)
        XCTAssertThrowsError(try store.install(fixture(invalid, in: root), font: download(invalid)))
        try store.install(source, font: font)
        let file = try XCTUnwrap(store.installedURL(for: font))
        let receipt = file.appendingPathExtension("receipt.json")
        let validReceipt = try Data(contentsOf: receipt)
        for bytes in [Data(), Data("{}".utf8), Data(repeating: 0, count: 513)] {
            try bytes.write(to: receipt)
            XCTAssertNil(store.installedURL(for: font))
        }
        try validReceipt.write(to: receipt)
        XCTAssertNotNil(store.installedURL(for: font))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: file.path)
        XCTAssertNil(store.installedURL(for: font))
        try Data([0]).write(to: file)
        XCTAssertNil(store.installedURL(for: font))
        try Data(repeating: 0, count: 65).write(to: store.directory!.appendingPathComponent("revision.txt"))
        XCTAssertEqual(store.revision, "")
    }

    func testUnavailableUnsafeAndSymlinkSourcesNeverInstall() throws {
        let root = try folder(), source = try fixture(fontBytes, in: root)
        let font = download(fontBytes)
        for directory in [nil, URL(string: "https://example.com/fonts")] {
            let store = UnicodeFontDownloadStore(directory: directory)
            XCTAssertNil(store.installedURL(for: font))
            XCTAssertThrowsError(try store.install(source, font: font))
            XCTAssertThrowsError(try store.remove(font))
        }
        let store = UnicodeFontDownloadStore(directory: root.appendingPathComponent("shared"))
        let symlink = root.appendingPathComponent("link.ttf")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: source)
        XCTAssertThrowsError(try store.install(symlink, font: font))
        XCTAssertThrowsError(try store.install(URL(string: "https://example.com/font")!, font: font))
        XCTAssertThrowsError(try store.install(root.appendingPathComponent("missing"), font: font))
        try store.install(source, font: font)
        let file = try XCTUnwrap(store.installedURL(for: font))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: source)
        XCTAssertNil(store.installedURL(for: font))
    }

    func testChangingSourceAndMissingTimestampCannotPublishAnAttestedFont() throws {
        let root = try folder(), font = download(fontBytes)
        for bytes in [Data([0, 1, 0, 0]), Data([0, 1, 0, 0] + Array(repeating: 7, count: 200))] {
            let source = try fixture(bytes, in: root)
            let store = UnicodeFontDownloadStore(directory: root.appendingPathComponent(UUID().uuidString), metadata: { url in
                if url == source {
                    // File length changed between the size query and the read.
                    return .init(regular: true, symlink: false, bytes: font.bytes, modified: Date(timeIntervalSince1970: 1))
                }
                return try UnicodeFontDownloadStore.readMetadata(url)
            })
            XCTAssertThrowsError(try store.install(source, font: font))
            XCTAssertNil(store.installedURL(for: font))
        }
        let source = try fixture(fontBytes, in: root)
        let store = UnicodeFontDownloadStore(directory: root.appendingPathComponent("missing-date"), metadata: { url in
            let facts = try UnicodeFontDownloadStore.readMetadata(url)
            return .init(regular: facts.regular, symlink: facts.symlink, bytes: facts.bytes,
                         modified: url == source ? facts.modified : nil)
        })
        XCTAssertThrowsError(try store.install(source, font: font))
        XCTAssertNil(store.installedURL(for: font))
    }

    func testUnreadableReceiptCannotBeTreatedAsInstalled() throws {
        let root = try folder(), source = try fixture(fontBytes, in: root), font = download(fontBytes)
        let store = UnicodeFontDownloadStore(directory: root.appendingPathComponent("shared"))
        try store.install(source, font: font)
        let file = try XCTUnwrap(store.installedURL(for: font))
        let receipt = file.appendingPathExtension("receipt.json")
        try FileManager.default.removeItem(at: receipt)
        XCTAssertNil(store.installedURL(for: font))
        try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: false)
        XCTAssertNil(store.installedURL(for: font))
    }
}
