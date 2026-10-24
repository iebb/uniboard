import Foundation
import CryptoKit
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UnicodeSearchIndexTests: XCTestCase {
    /// Built once: the index of the bundled catalog, persisted in a temporary store.
    private static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UnicodeSearchIndexTests-\(UUID().uuidString)", isDirectory: true)
    private static let store = UnicodeSearchIndexStore(directory: directory)
    private static let index = store.prepare(for: .shared)
    private let scanOnly = UnicodeSearchIndexStore(directory: nil)

    override class func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Typical, broad, selective, multi-word, numeric, non-ASCII, punctuation,
    /// context-only and algorithmic-name (Hangul syllable, hexadecimal suffix)
    /// queries, plus words and fragments of character names from every
    /// `blockStride`-th block, so every script takes part. `extended` adds
    /// queries whose full scan builds every CJK and Private Use name (slow
    /// unoptimized) and names sampled every 499 assigned characters.
    static func equivalenceQueries(blockStride: Int, extended: Bool) -> [String] {
        var queries = ["ar", "arrow", "Arrow", "greek small", "heart", "cjk", "cjk ideograph", "qzxwvkjplm frobnicate",
                       "letter", "latin small letter a", "ow", "left right", "a b", "12", "one", "no_break space", "BOM",
                       "hangzhou", "additional suzhou numerals", "hangul syllable ga", "hangul", "gag", "ga", "kk",
                       "syllable gyeo", "snowy weather", "tangut 17", "smiling face with", "with", "combining acute",
                       "café", "straße", "ﬁ ligature", "kelvin", "  arrow   left  ", "box drawings light",
                       "braille pattern dots", "zz", "Ω omega", "radical", "variation selector", "tag latin",
                       "white star", "yi syllable"]
        if extended {
            queries += ["face", "cafe", "add", "bead", "ideograph 4e0", "cjk 2a6", "e00", "private use f0", "fffd",
                        "de", "a1", "fe0f", "jurchen 18e", "small seal 3d0"]
        }
        let catalog = UnicodeCatalog.shared
        var sample = stride(from: 0, to: catalog.blocks.count, by: blockStride)
            .flatMap { catalog.characters(in: catalog.blocks[$0], limit: 1) }
        if extended { sample += stride(from: 0, to: 310_000, by: 499).flatMap { catalog.orderedCharacters(offset: $0, limit: 1) } }
        for character in sample {
            let words = character.name.lowercased().split(separator: " ").map(String.init)
            guard let word = words.last else { continue }
            // Without `extended`, skip hexadecimal name suffixes such as "ideograph-4e00".
            if !extended && word.contains("-") { continue }
            queries.append(word)
            if word.count > 3 { queries.append(String(word.dropFirst().prefix(3))) }
            if words.count > 1 { queries.append(words.prefix(2).joined(separator: " ")) }
        }
        return queries
    }

    func testIndexedSearchReturnsTheFullScanResultsInTheSameOrder() throws {
        let index = try XCTUnwrap(Self.index)
        XCTAssertGreaterThan(index.byteCount, UnicodeSearchIndex.headerSize)
        XCTAssertNotNil(UnicodeSearchIndexStore(directory: Self.directory).installedIndex(for: .shared),
                        "A second store, like the keyboard's, maps the persisted file")
        let queries = Self.equivalenceQueries(blockStride: 9, extended: false)
        XCTAssertGreaterThan(queries.count, 120)
        for query in queries {
            let scanned = UnicodeCatalog.shared.search(query, indexStore: scanOnly)
            let indexed = UnicodeCatalog.shared.search(query, indexStore: Self.store)
            XCTAssertEqual(indexed.map(\.codePoint), scanned.map(\.codePoint), query)
            XCTAssertEqual(indexed, scanned, query)
        }
        // Every match, beyond the default limit, in each order, edition and ConScript view.
        for query in ["arrow", "hangzhou", "syllable gyeo", "tangut 17"] {
            for order in UnicodeSortOrder.allCases {
                for catalog in [UnicodeCatalog.shared, .older, UnicodeCatalog.shared.withConScriptSearch()] {
                    XCTAssertEqual(catalog.search(query, limit: 5_000, order: order, indexStore: Self.store).map(\.codePoint),
                                   catalog.search(query, limit: 5_000, order: order, indexStore: scanOnly).map(\.codePoint),
                                   "\(query) \(order) \(catalog.version)")
                }
            }
        }
    }

    func testCandidatesAreASupersetOfEveryScanMatch() throws {
        let index = try XCTUnwrap(Self.index)
        let catalog = UnicodeCatalog.shared
        // "hangzhou" occurs only in the NamesList context of the Suzhou numerals.
        XCTAssertFalse(index.candidates(for: [Array("hangzhou".utf8)]).isEmpty)
        XCTAssertFalse(catalog.search("hangzhou", indexStore: Self.store).isEmpty)
        XCTAssertTrue(index.candidates(for: [Array("qzxwvkjplm".utf8)]).isEmpty)
        XCTAssertTrue(index.candidates(for: [Array("arrow".utf8), Array("qzxwvkjplm".utf8)]).isEmpty)
        XCTAssertTrue(index.candidates(for: []).isEmpty)
        let broad = index.candidates(for: [Array("a".utf8)])
        XCTAssertEqual(broad, broad.sorted())
        XCTAssertEqual(Set(broad).count, broad.count)
    }

    func testCancelledWorkStopsWithoutResults() async throws {
        let index = try XCTUnwrap(Self.index)
        let task = Task { () -> ([Int], Data?) in
            while !Task.isCancelled { await Task.yield() }
            return (index.candidates(for: [Array("arrow".utf8)]), UnicodeCatalog.shared.makeSearchIndex())
        }
        task.cancel()
        let (candidates, built) = await task.value
        XCTAssertTrue(candidates.isEmpty)
        XCTAssertNil(built)
    }

    func testBuildRejectsAnUnusableIdentity() throws {
        let digest = Data(repeating: 1, count: 32)
        for identity in [UnicodeSearchIndexIdentity(catalogDigest: Data([1]), catalogBytes: 1, recordCount: 0, version: "1.0"),
                         UnicodeSearchIndexIdentity(catalogDigest: digest, catalogBytes: 1, recordCount: 0,
                                                    version: String(repeating: "9", count: 33))] {
            XCTAssertNil(Data([0]).withUnsafeBytes { bytes in
                UnicodeSearchIndex.build(identity: identity, bytes: bytes) { _ in (0..<0, 0..<0) }
            })
        }
        // Words split on single spaces; repeated words and shared contexts are listed once.
        let text = Array("ab ab  cd".utf8) + Array("ctx ab".utf8)
        let identity = UnicodeSearchIndexIdentity(catalogDigest: digest, catalogBytes: 9, recordCount: 3, version: "1.0")
        let data = text.withUnsafeBytes { bytes in
            UnicodeSearchIndex.build(identity: identity, bytes: bytes) { record in
                record == 2 ? (0..<0, 0..<0) : (record == 0 ? 0..<9 : 3..<5, 9..<15)
            }
        }
        let index = try XCTUnwrap(UnicodeSearchIndex(data: XCTUnwrap(data), identity: identity))
        XCTAssertEqual(index.candidates(for: [Array("b".utf8)]), [0, 1])
        XCTAssertEqual(index.candidates(for: [Array("ctx".utf8)]), [0, 1])
        XCTAssertEqual(index.candidates(for: [Array("cd".utf8)]), [0])
        XCTAssertEqual(index.candidates(for: [Array("b c".utf8)]), [], "No word holds a space")
    }

    /// Rewrites the body checksum, as a well-formed but wrong build would.
    private func resealed(_ data: Data, patch: (inout Data) -> Void) -> Data {
        var copy = data
        patch(&copy)
        copy.replaceSubrange(48..<80, with: Data(SHA256.hash(data: copy.dropFirst(UnicodeSearchIndex.headerSize))))
        return copy
    }

    private func setU32(_ value: UInt32, at offset: Int, in data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset..<(offset + 4), with: $0) }
    }

    func testStaleOrDamagedIndexesAreRejected() throws {
        let catalog = UnicodeCatalog.shared
        let identity = try XCTUnwrap(catalog.searchIndexIdentity)
        let data = try XCTUnwrap(catalog.makeSearchIndex())
        XCTAssertNotNil(UnicodeSearchIndex(data: data, identity: identity))
        XCTAssertNotNil(UnicodeSearchIndex(data: resealed(data) { _ in }, identity: identity))
        func field(_ offset: Int) -> Int {
            data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
        }
        let postings = UnicodeSearchIndex.headerSize + 4 * (3 * (field(92) + 1) + field(88) + 1)
        let other = UnicodeSearchIndexIdentity(catalogDigest: Data(repeating: 0, count: 32), catalogBytes: identity.catalogBytes,
                                               recordCount: identity.recordCount, version: identity.version)
        var flipped = data
        flipped[data.count - 1] ^= 0xFF
        var version = data
        version[8] = 2
        let damaged: [(String, Data, UnicodeSearchIndexIdentity)] = [
            ("short", data.prefix(100), identity),
            ("magic", Data("NOTANIDX".utf8) + data.dropFirst(8), identity),
            ("format version", version, identity),
            ("other catalog", data, other),
            ("other version", data, UnicodeSearchIndexIdentity(catalogDigest: identity.catalogDigest, catalogBytes: identity.catalogBytes,
                                                                recordCount: identity.recordCount, version: "1.0.0")),
            ("other record count", data, UnicodeSearchIndexIdentity(catalogDigest: identity.catalogDigest, catalogBytes: identity.catalogBytes,
                                                                     recordCount: identity.recordCount + 1, version: identity.version)),
            ("truncated", data.dropLast(), identity),
            ("checksum", flipped, identity),
            ("first start", resealed(data) { self.setU32(1, at: UnicodeSearchIndex.headerSize, in: &$0) }, identity),
            ("descending", resealed(data) { self.setU32(UInt32.max, at: UnicodeSearchIndex.headerSize + 4, in: &$0) }, identity),
            ("record posting", resealed(data) { self.setU32(UInt32.max, at: postings, in: &$0) }, identity)
        ]
        for (label, bytes, expected) in damaged {
            XCTAssertNil(UnicodeSearchIndex(data: bytes, identity: expected), label)
        }
    }

    func testStoreReusesRebuildsAndFallsBack() throws {
        let catalog = UnicodeCatalog.shared
        let directory = temporaryDirectory()
        let store = UnicodeSearchIndexStore(directory: directory)
        let url = try XCTUnwrap(store.fileURL)
        XCTAssertEqual(url.lastPathComponent, "UnicodeSearchIndex-v1.bin")
        XCTAssertNil(store.installedIndex(for: catalog), "Absent: searches keep scanning")
        // A stale or damaged file is ignored, then replaced.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: url)
        XCTAssertNil(store.installedIndex(for: catalog))
        let built = try XCTUnwrap(store.prepare(for: catalog))
        XCTAssertEqual(built.identity, catalog.searchIndexIdentity)
        XCTAssertEqual(try Data(contentsOf: url).count, built.byteCount)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [url.lastPathComponent],
                       "The temporary file is renamed into place")
        XCTAssertEqual(store.installedIndex(for: catalog)?.identity, built.identity)
        XCTAssertEqual(store.prepare(for: catalog.limited(to: .latest))?.identity, built.identity,
                       "Every edition shares the one index of the mapped data")
        XCTAssertEqual(UnicodeSearchIndexStore(directory: directory).installedIndex(for: catalog)?.identity, built.identity)
        // A removed file is no longer used, by this store or another.
        try FileManager.default.removeItem(at: url)
        XCTAssertNil(store.installedIndex(for: catalog))
        XCTAssertNotNil(store.prepare(for: catalog))
        XCTAssertNotNil(store.installedIndex(for: catalog))

        // Without a container, or when writing fails, the app keeps it in memory.
        let memoryOnly = UnicodeSearchIndexStore(directory: nil)
        XCTAssertNotNil(memoryOnly.prepare(for: catalog))
        XCTAssertNotNil(memoryOnly.installedIndex(for: catalog), "An in-memory index stays in use")
        let blocked = temporaryDirectory()
        try Data().write(to: blocked)
        let unwritable = UnicodeSearchIndexStore(directory: blocked.appendingPathComponent("SearchIndex"))
        XCTAssertNotNil(unwritable.prepare(for: catalog))
        XCTAssertNil(UnicodeSearchIndexStore(directory: blocked.appendingPathComponent("SearchIndex")).installedIndex(for: catalog))

        // An unavailable catalog has nothing to index.
        let empty = UnicodeCatalog(resourceURL: temporaryDirectory())
        XCTAssertNil(empty.searchIndexIdentity)
        XCTAssertNil(empty.makeSearchIndex())
        XCTAssertNil(store.prepare(for: empty))
        XCTAssertNil(store.installedIndex(for: empty))
        XCTAssertTrue(empty.search("arrow", indexStore: store).isEmpty)
    }

    func testAtomicWriteLeavesNoTemporaryFileWhenRenameFails() throws {
        let directory = temporaryDirectory()
        let target = directory.appendingPathComponent("occupied", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data().write(to: target.appendingPathComponent("child"))
        XCTAssertThrowsError(try UnicodeSearchIndexStore.write(Data([1, 2, 3]), to: target))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["occupied"])
        let file = directory.appendingPathComponent("index.bin")
        try UnicodeSearchIndexStore.write(Data([1, 2, 3]), to: file)
        try UnicodeSearchIndexStore.write(Data([4]), to: file)
        XCTAssertEqual(try Data(contentsOf: file), Data([4]))
    }
}
