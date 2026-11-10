import XCTest
import Foundation
import CryptoKit
import zlib
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// Entirely generated fixtures: no production dictionary/model is bundled here.
final class LanguagePackArchiveTests: XCTestCase {
    private var sandbox: URL!
    private let root = "fixture-pinned-root"
    private let word = Data("日本語\n".utf8)

    override func setUpWithError() throws {
        sandbox = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: sandbox) }

    private struct Entry {
        let path: String
        var bytes = Data()
        var type: UInt8 = 48
        var link = ""
        var declaredSize: Int64?
    }
    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func descriptor(_ archive: Data, files: [(String, Data)]? = nil) -> LanguagePackDescriptor {
        let payload = files ?? [("Dictionary/words.dat", word)]
        return LanguagePackDescriptor(packID: "generated-fixture", version: "1", modeID: "japanese-romaji", engineABI: "fixture-v1",
                                      sourceURL: URL(string: "https://data.example.test/pinned/archive")!, allowedHosts: ["data.example.test"],
                                      archiveByteCount: Int64(archive.count), archiveSHA256: hash(archive),
                                      installedBytes: payload.reduce(0) { $0 + Int64($1.1.count) }, fileCount: payload.count,
                                      files: payload.map { .init(path: $0.0, byteCount: Int64($0.1.count), sha256: hash($0.1)) },
                                      licenseNotice: "Generated test data only; no upstream content.", sourceNotice: "Generated locally by this test.")
    }
    private func header(_ entry: Entry) -> Data {
        var bytes = [UInt8](repeating: 0, count: 512)
        func put(_ value: String, at start: Int) {
            let field = Array(value.utf8)
            bytes.replaceSubrange(start..<(start + field.count), with: field)
        }
        func number(_ value: Int64, at start: Int, count: Int) {
            let octal = String(value, radix: 8)
            put(String(repeating: "0", count: count - 1 - octal.count) + octal, at: start)
        }
        // Exercise genuine USTAR prefix support rather than a GNU long-name header.
        if entry.path.utf8.count > 100, let slash = entry.path.lastIndex(of: "/") {
            let prefix = String(entry.path[..<slash])
            let name = String(entry.path[entry.path.index(after: slash)...])
            precondition(prefix.utf8.count <= 155 && name.utf8.count <= 100)
            put(prefix, at: 345); put(name, at: 0)
        } else { put(entry.path, at: 0) }
        number(0o755, at: 100, count: 8) // Extractor must NOT preserve executable bits.
        number(0, at: 108, count: 8); number(0, at: 116, count: 8)
        number(entry.declaredSize ?? Int64(entry.bytes.count), at: 124, count: 12)
        number(0, at: 136, count: 12)
        bytes[156] = entry.type
        put(entry.link, at: 157)
        put("ustar\0", at: 257); put("00", at: 263)
        number(0, at: 329, count: 8); number(0, at: 337, count: 8)
        for i in 148..<156 { bytes[i] = 32 }
        let checksum = bytes.reduce(0) { $0 + Int($1) }
        let octal = String(checksum, radix: 8)
        put(String(repeating: "0", count: 6 - octal.count) + octal + "\0 ", at: 148)
        return Data(bytes)
    }
    private func tar(_ entries: [Entry], endBlocks: Int = 2) -> Data {
        var output = Data()
        for entry in entries {
            output.append(header(entry)); output.append(entry.bytes)
            output.append(Data(repeating: 0, count: (512 - entry.bytes.count % 512) % 512))
        }
        output.append(Data(repeating: 0, count: endBlocks * 512))
        return output
    }
    private func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        let capacity = Int(compressBound(uLong(data.count))) + 128
        var output = [UInt8](repeating: 0, count: capacity)
        var produced = 0
        try withUnsafeMutablePointer(to: &stream) { stream in
            guard deflateInit2_(stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY,
                                ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw LanguagePackArchiveError.invalidArchive("fixture gzip init")
            }
            defer { deflateEnd(stream) }
            let status = data.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { destination -> Int32 in
                    stream.pointee.next_in = input.bindMemory(to: Bytef.self).baseAddress.map { UnsafeMutablePointer(mutating: $0) }
                    stream.pointee.avail_in = uInt(input.count)
                    stream.pointee.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.pointee.avail_out = uInt(capacity)
                    let result = deflate(stream, Z_FINISH)
                    produced = capacity - Int(stream.pointee.avail_out)
                    return result
                }
            }
            guard status == Z_STREAM_END else { throw LanguagePackArchiveError.invalidArchive("fixture gzip compression") }
        }
        return Data(output.prefix(produced))
    }
    @discardableResult
    private func extract(_ archive: Data, files: [(String, Data)]? = nil,
                         limits: LanguagePackArchive.Limits = .init(),
                         check: @escaping () throws -> Void = {}) throws -> URL {
        let id = UUID().uuidString
        let input = sandbox.appendingPathComponent(id + ".tar.gz")
        let stage = sandbox.appendingPathComponent(id)
        try archive.write(to: input)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        try LanguagePackArchive.extract(archive: input, descriptor: descriptor(archive, files: files), into: stage,
                                        archiveRoot: root, limits: limits, checkCancellation: check)
        return stage
    }
    private func good() -> Entry { Entry(path: root + "/Dictionary/words.dat", bytes: word) }
    private func fails(_ entries: [Entry], file: StaticString = #filePath, line: UInt = #line) throws {
        let archive = try gzip(tar(entries))
        XCTAssertThrowsError(try extract(archive), file: file, line: line)
    }

    func testContentHashNoticesZeroBytesAndSkippedUncatalogedFiles() throws {
        let notice = Data("Full fixture license notice\n".utf8)
        var entries = [Entry(path: root + "/", type: 53), Entry(path: root + "/Dictionary/", type: 53), good(),
                       Entry(path: root + "/LICENSE", bytes: notice), Entry(path: root + "/README.md", bytes: Data("skip me".utf8))]
        let emptyPaths = (0..<4).map { "Dictionary/empty\($0)/.gitkeep" }
        entries += emptyPaths.map { Entry(path: root + "/" + $0) }
        let files = [("Dictionary/words.dat", word), ("LICENSE", notice)] + emptyPaths.map { ($0, Data()) }
        let stage = try extract(gzip(tar(entries)), files: files)
        for (path, content) in files { XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent(path)), content) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.appendingPathComponent("README.md").path))
        let attributes = try FileManager.default.attributesOfItem(atPath: stage.appendingPathComponent("Dictionary/words.dat").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testLongUSTARPrefixPathAndMultiChunkStreaming() throws {
        let path = "Dictionary/" + String(repeating: "a", count: 95) + "/" + String(repeating: "b", count: 70) + ".dat"
        let bytes = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 * 17) })
        let stage = try extract(gzip(tar([Entry(path: root + "/" + path, bytes: bytes)])), files: [(path, bytes)])
        XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent(path)), bytes)
    }

    func testFullCatalogScaleIncludingEmptyPlaceholders() throws {
        // Same order of magnitude as the real 3,397-entry dictionary, without real data.
        let files = (0..<3_397).map { index in
            ("Dictionary/shards/\(index).dat", index < 4 ? Data() : Data([UInt8(truncatingIfNeeded: index)]))
        }
        let entries = files.map { Entry(path: root + "/" + $0.0, bytes: $0.1) }
        let stage = try extract(gzip(tar(entries)), files: files)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: stage.appendingPathComponent("Dictionary/shards").path).count, 3_397)
    }

    func testRejectTraversalAbsoluteBackslashAndForeignRootEvenForSkippedFiles() throws {
        for path in [root + "/../escape", root + "/Dictionary/../../escape", root + "/./skip", root + "//skip",
                     "/absolute", "foreign/README", root + "/bad\\name", root + "/bad\nname"] {
            try fails([good(), Entry(path: path)])
        }
    }

    func testRejectLinksSpecialFilesAndAllPathOverrideHeaders() throws {
        let forbiddenTypes: [UInt8] = [49, 50, 51, 52, 54, 55, 120, 76, 75, 83]
        for type in forbiddenTypes {
            try fails([good(), Entry(path: root + "/skipped", type: type)])
        }
        try fails([Entry(path: root + "/skipped", link: "target"), good()])
    }

    func testRejectDuplicatesCaseAliasesAndAncestorCollisions() throws {
        try fails([good(), good()])
        try fails([good(), Entry(path: root + "/Dictionary/WORDS.dat")])
        try fails([good(), Entry(path: root + "/dictionary/another.dat")])
        try fails([Entry(path: root + "/Dictionary"), good()])
        try fails([good(), Entry(path: root + "/Dictionary")])
        try fails([good(), Entry(path: root + "/skipped"), Entry(path: root + "/skipped")])
    }

    func testRejectHeaderChecksumAndInvalidOctal() throws {
        var badChecksum = tar([good()]); badChecksum[0] ^= 1
        XCTAssertThrowsError(try extract(gzip(badChecksum)))
        var invalidNumber = header(good())
        invalidNumber[124] = 56 // non-octal '8', with a freshly correct checksum.
        for i in 148..<156 { invalidNumber[i] = 32 }
        let checksum = invalidNumber.reduce(0) { $0 + Int($1) }
        let field = Array((String(format: "%06o", checksum) + "\0 ").utf8)
        invalidNumber.replaceSubrange(148..<156, with: field)
        var raw = invalidNumber; raw.append(word)
        raw.append(Data(repeating: 0, count: (512 - word.count % 512) % 512 + 1_024))
        XCTAssertThrowsError(try extract(gzip(raw)))
    }

    func testRejectPaddingTruncatedTarAndEndMarkerGarbage() throws {
        var badPadding = tar([good()]); badPadding[512 + word.count] = 1
        XCTAssertThrowsError(try extract(gzip(badPadding)))
        XCTAssertThrowsError(try extract(gzip(tar([good()], endBlocks: 1))))
        XCTAssertThrowsError(try extract(gzip(tar([good()], endBlocks: 0))))
        var trailing = tar([good()]); trailing.append(1)
        XCTAssertThrowsError(try extract(gzip(trailing)))
        var partialPadding = tar([good()]); partialPadding.append(0)
        XCTAssertThrowsError(try extract(gzip(partialPadding)))
        _ = try extract(gzip(tar([good()]) + Data(repeating: 0, count: 512)))
        var badSecond = tar([good()]); badSecond[badSecond.count - 512] = 1
        XCTAssertThrowsError(try extract(gzip(badSecond)))
    }

    func testRejectGzipTruncationCRCConcatenationAndTrailingGarbage() throws {
        let archive = try gzip(tar([good()]))
        for drop in [1, 8, 15] { XCTAssertThrowsError(try extract(Data(archive.dropLast(drop)))) }
        var crc = archive; crc[crc.count - 8] ^= 1
        XCTAssertThrowsError(try extract(crc))
        XCTAssertThrowsError(try extract(archive + Data([0])))
        XCTAssertThrowsError(try extract(archive + archive))
    }

    func testCatalogFileSizeHashAndMissingFileAreEnforced() throws {
        let archive = try gzip(tar([good()]))
        XCTAssertThrowsError(try extract(archive, files: [("Dictionary/words.dat", word + Data([0]))]))
        XCTAssertThrowsError(try extract(archive, files: [("Dictionary/words.dat", Data(repeating: 0, count: word.count))]))
        XCTAssertThrowsError(try extract(archive, files: [("Dictionary/missing.dat", word)]))
    }

    func testArchiveMustBeVerifiedAgainBeforeExtraction() throws {
        let archive = try gzip(tar([good()]))
        let input = sandbox.appendingPathComponent("changed.tar.gz")
        try (archive + Data([0])).write(to: input)
        let stage = sandbox.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        XCTAssertThrowsError(try LanguagePackArchive.extract(archive: input, descriptor: descriptor(archive), into: stage, archiveRoot: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: stage.path), [])
    }

    func testDecodedBombIndividualSizeAndEntryLimitsAlsoCoverSkippedFiles() throws {
        let archive = try gzip(tar([good(), Entry(path: root + "/ignored", bytes: Data(repeating: 0, count: 256_000))]))
        XCTAssertThrowsError(try extract(archive, limits: .init(decodedBytes: 4_096))) { error in
            XCTAssertEqual(error as? LanguagePackArchiveError, .limitExceeded("decoded gzip bytes"))
        }
        XCTAssertThrowsError(try extract(archive, limits: .init(individualFileBytes: 64)))
        XCTAssertThrowsError(try extract(archive, limits: .init(entryCount: 1)))
        try fails([Entry(path: root + "/huge", declaredSize: 128 * 1_024 * 1_024), good()])
    }

    func testCancellationBeforeStartingAndBetweenChunks() throws {
        let bytes = Data(repeating: 42, count: 512_000)
        let archive = try gzip(tar([Entry(path: root + "/Dictionary/words.dat", bytes: bytes)]))
        XCTAssertThrowsError(try extract(archive, files: [("Dictionary/words.dat", bytes)], check: { throw CancellationError() })) { error in
            XCTAssertEqual(error as? LanguagePackArchiveError, .cancelled)
        }
        var checks = 0
        XCTAssertThrowsError(try extract(archive, files: [("Dictionary/words.dat", bytes)], check: {
            checks += 1
            if checks > 8 { throw CancellationError() }
        })) { error in XCTAssertEqual(error as? LanguagePackArchiveError, .cancelled) }
    }

    private func pax(_ keyValue: String) -> Data {
        var count = keyValue.utf8.count + 3
        while true {
            let text = "\(count) \(keyValue)\n"
            if text.utf8.count == count { return Data(text.utf8) }
            count = text.utf8.count
        }
    }
    func testOnlySafeBoundedGlobalPAXCommitCommentAccepted() throws {
        let comment = Entry(path: "pax_global_header", bytes: pax("comment=0123456789abcdef"), type: 103)
        _ = try extract(gzip(tar([comment, good()])))
        for metadata in ["path=../../escape", "linkpath=/absolute", "size=99999", "comment=x\npath=escape"] {
            try fails([Entry(path: "pax_global_header", bytes: pax(metadata), type: 103), good()])
        }
        try fails([comment, comment, good()])
        try fails([Entry(path: "../../pax_global_header", bytes: pax("comment=safe"), type: 103), good()])
        try fails([Entry(path: "pax_global_header", bytes: Data("99 comment=x\n".utf8), type: 103), good()])
        try fails([Entry(path: "pax_global_header", bytes: Data(repeating: 0, count: 16_385), type: 103), good()])
    }

    func testNonemptyOrSymlinkStageRejectedWithoutOverwriting() throws {
        let archive = try gzip(tar([good()]))
        let input = sandbox.appendingPathComponent("pack.gz")
        try archive.write(to: input)
        let stage = sandbox.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
        let sentinel = stage.appendingPathComponent("sentinel")
        try word.write(to: sentinel)
        XCTAssertThrowsError(try LanguagePackArchive.extract(archive: input, descriptor: descriptor(archive), into: stage, archiveRoot: root))
        XCTAssertEqual(try Data(contentsOf: sentinel), word)
        let link = sandbox.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: stage)
        XCTAssertThrowsError(try LanguagePackArchive.extract(archive: input, descriptor: descriptor(archive), into: link, archiveRoot: root))
    }
}
