import Foundation
import XCTest
import SQLite3
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

/// All corpora below are SYNTHETIC TEST FIXTURES, not a shipped vocabulary or
/// evidence of language quality. Full pinned-corpus execution is a separate gate.
final class MandarinPinyinTests: XCTestCase {
    private var roots: [URL] = []
    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        super.tearDown()
    }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MandarinPinyinTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url)
        return url
    }
    private func file(_ text: String, name: String, root: URL) throws -> (MandarinDictionaryResource, URL) {
        let data = Data(text.utf8), url = root.appendingPathComponent(name)
        try data.write(to: url)
        return (.init(filename: name, bytes: data.count, sha256: MandarinDictionaryCompiler.hash(data),
                      downloadURL: URL(string: "https://invalid.example/test-only/\(name)")!), url)
    }
    private func compile(_ rows: String, expected: Int? = nil, quarantine: [Int: String] = [:],
                         isCancelled: @escaping () -> Bool = { false },
                         progress: (MandarinCompilationProgress) -> Void = { _ in },
                         now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws
        -> (URL, MandarinDictionaryCompilationStats) {
        let directory = try root()
        let source = try file("# test-only fixture\n" + rows, name: "test-only.tsv", root: directory)
        let characters = try file("# test-only mapping\n國\t国\n", name: "characters.txt", root: directory)
        let phrases = try file("# test-only mapping\n瞭解\t了解\n", name: "phrases.txt", root: directory)
        let compatibility = try file("# test-only mapping\n豈\t豈\n龜\t龟\n龜\t龜\n", name: "compatibility.txt", root: directory)
        let destination = directory.appendingPathComponent("test-only.sqlite")
        let valid = rows.split(separator: "\n").count - quarantine.count
        let stats = try MandarinDictionaryCompiler.compileVerified(sources: [
            .init(resource: source.0, url: source.1, header: ["# test-only fixture"],
                  expectedValidRows: expected ?? valid, quarantined: quarantine)
        ], mappingFiles: [characters, phrases, compatibility], destinationURL: destination,
            isCancelled: isCancelled, progress: progress, now: now)
        return (destination, stats)
    }

    func testCompileProgressHasRealThrottledRowsIndeterminatePhasesAndIdenticalBytes() throws {
        let rows = (0..<4_100).map { "测试\($0)\tcè shì\t1\n" }.joined()
        var events: [MandarinCompilationProgress] = []
        // Frozen clock proves row callbacks are not emitted for every row/chunk.
        let (withProgress, stats) = try compile(rows, progress: { events.append($0) }, now: { 10 })
        XCTAssertEqual(events, [.verifyingSources, .preparingMappings, .rows(processed: 0, total: 4_100),
                                .rows(processed: 4_100, total: 4_100), .indexing, .finalCheck])
        let (withoutProgress, baselineStats) = try compile(rows)
        XCTAssertEqual(stats, baselineStats)
        XCTAssertEqual(try Data(contentsOf: withProgress), try Data(contentsOf: withoutProgress))
        var time: TimeInterval = 0
        var counts: [Int] = []
        _ = try compile(rows, progress: {
            if case .rows(let processed, _) = $0 { counts.append(processed) }
        }, now: { time += 0.11; return time })
        XCTAssertEqual(counts, [0, 1_024, 2_048, 3_072, 4_096, 4_100])
    }

    func testSQLiteWorkCanBeInterruptedBeforeFinalCheck() throws {
        let rows = (0..<4_100).map { "测试\($0)\tcè shì\t1\n" }.joined()
        var indexing = false, reachedFinalCheck = false, indexingChecks = 0
        XCTAssertThrowsError(try compile(rows, isCancelled: {
            guard indexing else { return false }
            indexingChecks += 1
            return indexingChecks >= 2
        }, progress: {
            if $0 == .indexing { indexing = true }
            if $0 == .finalCheck { reachedFinalCheck = true }
        })) { XCTAssertEqual($0 as? MandarinDictionaryError, .cancelled) }
        XCTAssertFalse(reachedFinalCheck, "SQLite progress handler must interrupt work before it finishes")
        XCTAssertGreaterThanOrEqual(indexingChecks, 2)
    }

    func testCancellationAtRowsIndexingAndFinalCheckCleansUnpublishedDatabase() throws {
        for phase in [MandarinCompilationProgress.preparingMappings, .rows(processed: 0, total: 1), .indexing, .finalCheck] {
            var cancelled = false
            XCTAssertThrowsError(try compile("词\tcí\t1\n", isCancelled: { cancelled }, progress: {
                if $0 == phase { cancelled = true }
            })) { error in
                XCTAssertEqual(error as? MandarinDictionaryError, .cancelled)
            }
        }
        for directory in roots {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertFalse(names.contains { $0.hasSuffix(".sqlite") || $0.hasSuffix("-journal") })
        }
    }

    func testUmlautAliasesPreserveDistinctionFromU() throws {
        for input in ["LV4", "lǜ", "lü4", "lu:4", "lu\u{308}\u{300}"] {
            let reading = try MandarinPinyinReading(input)
            XCTAssertEqual(reading.rawInput, input)
            XCTAssertEqual(reading.flat, "lv")
            XCTAssertTrue(reading.matches(syllables: ["lv"], tones: [4]))
            XCTAssertFalse(reading.matches(syllables: ["lu"], tones: [4]))
        }
        XCTAssertEqual(try MandarinPinyinReading("lu4").flat, "lu")
        XCTAssertEqual(try MandarinPinyinReading.sourceSyllables("nǚ lüè").syllables, ["nv", "lve"])
        XCTAssertEqual(try MandarinPinyinReading.sourceSyllables("nǚ lüè").tones, [3, 4])
    }

    func testStrictCustomReadingCanonicalFormPreservesBoundaryAndToneScope() {
        let canonical = MandarinPinyinReading.canonicalCustomReading
        XCTAssertEqual(canonical("NIHAO"), "nihao")
        XCTAssertEqual(canonical("ni'hao"), "ni'hao")
        XCTAssertNotEqual(canonical("xian"), canonical("xi'an"))
        for input in ["NV3", "nü3", "nu:3", "nǚ", "nu\u{308}\u{30c}"] {
            XCTAssertEqual(canonical(input), "nv3", input)
        }
        XCTAssertEqual(canonical("nǐhǎo"), "ni3hǎo")
        XCTAssertEqual(canonical("ni3'hao3"), "ni3'hao3")
        XCTAssertEqual(canonical("NE0"), "ne5")
        XCTAssertEqual(canonical("nǐ3"), "ni3")
        XCTAssertEqual(canonical("xī'an"), "xi1'an")
        // A tone on the vowel can have a different scope from a trailing
        // digit. Preserve it when both xi OR xian are complete possibilities.
        XCTAssertEqual(canonical("xīan"), "xīan")
        for value in ["nihao", "ni'hao", "nv3", "ni3'hao3", "xi1'an", "ne5", "m", "ng", "ni3hǎo", "xīan"] {
            XCTAssertEqual(canonical(canonical(value) ?? ""), canonical(value), value)
        }
    }

    func testCustomReadingRequiresFullSupportedSyllablesAndConsistentTones() {
        for input in ["", "zh", "q", "nihaoz", "hello", "ni'", "'ni", "ni''hao", "ni9", "nǐ2", "ni hao", "ni-hao", "你好", "vv", "x"] {
            XCTAssertNil(MandarinPinyinReading.canonicalCustomReading(input), input)
        }
        // Complete rare syllables from the pinned corpus remain supported.
        for input in ["m", "n", "ng", "biang", "fiao", "zhongguoren", "nv3'lve4"] {
            XCTAssertNotNil(MandarinPinyinReading.canonicalCustomReading(input), input)
        }
    }

    func testBoundaryLatticeNotGreedyAndToneConstraints() throws {
        let unconstrained = try MandarinPinyinReading("xian")
        XCTAssertTrue(unconstrained.matches(syllables: ["xian"], tones: [1]))
        XCTAssertTrue(unconstrained.matches(syllables: ["xi", "an"], tones: [1, 1]))
        let boundary = try MandarinPinyinReading("xi'an")
        XCTAssertFalse(boundary.matches(syllables: ["xian"], tones: [1]))
        XCTAssertTrue(boundary.matches(syllables: ["xi", "an"], tones: [1, 1]))
        let digits = try MandarinPinyinReading("xi1an1")
        XCTAssertFalse(digits.matches(syllables: ["xian"], tones: [1]))
        XCTAssertTrue(digits.matches(syllables: ["xi", "an"], tones: [1, 1]))
        for raw in ["ni3hao3", "nǐhǎo", "ni3'hao3"] {
            let reading = try MandarinPinyinReading(raw)
            XCTAssertTrue(reading.matches(syllables: ["ni", "hao"], tones: [3, 3]))
            XCTAssertFalse(reading.matches(syllables: ["ni", "hao"], tones: [2, 3]))
        }
        XCTAssertTrue(try MandarinPinyinReading("ne0").matches(syllables: ["ne"], tones: [5]))
        XCTAssertTrue(try MandarinPinyinReading("ne5").matches(syllables: ["ne"], tones: [5]))
    }

    func testInvalidInputsAndPreservedPartialPrefixes() throws {
        for input in ["", "ni6", "ni9", "ni33", "'ni", "ni''hao", "ni hao", "ni-hao", "ni🙂", "u::", "n:", "n\u{308}", "你", "ni\0"] {
            XCTAssertThrowsError(try MandarinPinyinReading(input), input)
        }
        for input in ["zh", "n", "xi'"] {
            XCTAssertEqual(try MandarinPinyinReading(input).rawInput, input)
        }
        XCTAssertTrue(try MandarinPinyinReading("xi'").hasTrailingBoundary)
        XCTAssertFalse(try MandarinPinyinReading("xi'").matches(syllables: ["xian"], tones: [1]))
    }

    func testFixtureIndexExactToneBoundaryAndPrefixLookup() throws {
        let (url, _) = try compile("先\txiān\t110\n西安\txī ān\t100\n你好\tnǐ hǎo\t90\n中国\tzhōng guó\t80\n绿\tlǜ\t70\n路\tlù\t60\n呢\tne\t50\n")
        let index = try MandarinDictionaryIndex(url: url)
        XCTAssertEqual(try index.lookup("xian").candidates.map(\.text), ["先", "西安"])
        XCTAssertEqual(try index.lookup("xi'an").candidates.map(\.text), ["西安"])
        XCTAssertEqual(try index.lookup("ni3hao3").candidates.map(\.text), ["你好"])
        XCTAssertTrue(try index.lookup("ni2hao3").candidates.isEmpty)
        XCTAssertEqual(try index.lookup("lv4").candidates.map(\.text), ["绿"])
        XCTAssertEqual(try index.lookup("lu4").candidates.map(\.text), ["路"])
        XCTAssertEqual(try index.lookup("ne0").candidates.map(\.text), ["呢"])
        XCTAssertTrue(try index.lookup("zh").candidates.isEmpty)
        XCTAssertEqual(try index.lookup("zh", prefix: true).candidates.map(\.text), ["中国"])
        XCTAssertTrue(try index.lookup("notaword").candidates.isEmpty)
    }

    func testSimplifiedNormalizationAndMaxNotSumDeduplication() throws {
        let (url, stats) = try compile("中國\tzhōng guó\t90\n中国\tzhōng guó\t70\n中国\tzhōng guó\t50\n瞭解\tliǎo jiě\t40\n𠀀\thē\t2\n")
        XCTAssertEqual(stats.sourceRows["test-only.tsv"], 5)
        XCTAssertEqual(stats.simplifiedChangedRows, 2)
        XCTAssertEqual(stats.uniqueRows, 3)
        XCTAssertEqual(stats.combinedRows, 2)
        let index = try MandarinDictionaryIndex(url: url)
        let country = try XCTUnwrap(index.lookup("zhongguo").candidates.first)
        XCTAssertEqual(country.text, "中国")
        XCTAssertEqual(country.score, 90)
        XCTAssertEqual(country.reading, "zhong'guo")
        XCTAssertEqual(country.tones, [1, 2])
        XCTAssertEqual(try index.lookup("liaojie").candidates.first?.text, "了解")
        XCTAssertEqual(try index.lookup("he").candidates.first?.text, "𠀀")
    }

    func testCompatibilityMappingKeysUseExactScalarsNotCanonicalStringIdentity() throws {
        // U+F907 and U+F908 are canonically equivalent but distinct mapping keys.
        let (url, stats) = try compile("龜\tguī\t9\n龜\tguī\t8\n")
        XCTAssertEqual(stats.simplifiedChangedRows, 2)
        let index = try MandarinDictionaryIndex(url: url)
        let results = try index.lookup("gui").candidates
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].text.unicodeScalars.map(\.value), [0x9F9F])
        XCTAssertEqual(results[1].text.unicodeScalars.map(\.value), [0x9F9C])
    }

    func testPagingAndExplicit512RowCap() throws {
        let rows = (0..<520).map { "测试\($0)\tcè shì\t\(1000 - $0)\n" }.joined()
        let (url, _) = try compile(rows)
        let index = try MandarinDictionaryIndex(url: url)
        let first = try index.lookup("ceshi")
        XCTAssertEqual(first.candidates.count, 48)
        XCTAssertEqual(first.nextOffset, 48)
        XCTAssertTrue(first.searchWasCapped)
        let second = try index.lookup("ceshi", offset: try XCTUnwrap(first.nextOffset))
        XCTAssertEqual(second.candidates.count, 48)
        XCTAssertNotEqual(first.candidates.first?.text, second.candidates.first?.text)
        let last = try index.lookup("ceshi", offset: 480)
        XCTAssertEqual(last.candidates.count, 32)
        XCTAssertNil(last.nextOffset)
        XCTAssertThrowsError(try index.lookup("ceshi", limit: 49))
    }

    func testStrictUnexpectedRowsCountsHeadersAndKnownQuarantine() throws {
        XCTAssertThrowsError(try compile("词\tcí\t10s\n"))
        XCTAssertThrowsError(try compile("词\tcí\n"))
        XCTAssertThrowsError(try compile("词\tcí\t1\n\n"))
        XCTAssertThrowsError(try compile("词\tcí\t1\n", expected: 2))
        let audited = "坏行\thuài háng\t10s"
        let (_, stats) = try compile("词\tcí\t1\n\(audited)\n", quarantine: [3: audited])
        XCTAssertEqual(stats.quarantinedLines["test-only.tsv"], [3])
        XCTAssertThrowsError(try compile("词\tcí\t1\nchanged\n", quarantine: [3: audited]))
    }

    func testHashRejectAndFailureLeavesNoDatabase() throws {
        let directory = try root()
        let source = try file("# fixture\n词\tcí\t1\n", name: "source.tsv", root: directory)
        let corrupt = MandarinDictionaryResource(filename: "source.tsv", bytes: source.0.bytes,
            sha256: String(repeating: "0", count: 64), downloadURL: source.0.downloadURL)
        let destination = directory.appendingPathComponent("must-not-exist.sqlite")
        XCTAssertThrowsError(try MandarinDictionaryCompiler.compileVerified(sources: [
            .init(resource: corrupt, url: source.1, header: ["# fixture"], expectedValidRows: 1, quarantined: [:])
        ], mappingFiles: [], destinationURL: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertThrowsError(try MandarinDictionaryCompiler.compile(jichuURL: source.1, ziURL: source.1,
            mappingURLs: .init(characters: source.1, phrases: source.1, compatibility: source.1),
            destinationURL: destination)) // A tiny fixture can NEVER pass the public production pin.
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDeterministicCompilationAndReadonlyQueries() throws {
        let fixture = "中国\tzhōng guó\t90\n西安\txī ān\t80\n"
        let (first, firstStats) = try compile(fixture)
        let (second, secondStats) = try compile(fixture)
        XCTAssertEqual(firstStats, secondStats)
        let bytes = try Data(contentsOf: first)
        XCTAssertEqual(bytes, try Data(contentsOf: second))
        let index = try MandarinDictionaryIndex(url: first)
        _ = try index.lookup("zhongguo")
        XCTAssertEqual(bytes, try Data(contentsOf: first))
    }

    func testFailedCompilationCleansStagingAndDoesNotOverwriteExistingFile() throws {
        XCTAssertThrowsError(try compile("词\tcí\t1\nbroken\n"))
        for directory in roots {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("test-only.sqlite").path))
        }
        let directory = try root(), destination = directory.appendingPathComponent("existing.sqlite")
        let original = Data("existing-pack-test-sentinel".utf8)
        try original.write(to: destination)
        XCTAssertThrowsError(try MandarinDictionaryCompiler.compileVerified(sources: [], mappingFiles: [], destinationURL: destination))
        XCTAssertEqual(try Data(contentsOf: destination), original)
    }

    func testRuntimeRejectsForeignDatabaseAndABIChange() throws {
        let directory = try root(), invalid = directory.appendingPathComponent("not-sqlite")
        try Data("not a dictionary".utf8).write(to: invalid)
        XCTAssertThrowsError(try MandarinDictionaryIndex(url: invalid))
        let (url, _) = try compile("词\tcí\t1\n")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        guard let db else { return XCTFail("test fixture database failed") }
        XCTAssertEqual(sqlite3_exec(db, "UPDATE metadata SET value='wrong-abi' WHERE key='engineABI'", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        XCTAssertThrowsError(try MandarinDictionaryIndex(url: url))
    }
}
