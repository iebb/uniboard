import Foundation
import XCTest
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class CustomInputDictionaryIndexTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        super.tearDown()
    }

    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CustomInputIndexTests-\(UUID().uuidString)")
        roots.append(url)
        return url
    }

    private func collection(_ entries: [CustomInputDictionaryEntry], mode: String = "test", enabled: Bool = true) -> CustomInputDictionaryCollection {
        .init(name: "Synthetic", modeID: mode, enabled: enabled, entries: entries)
    }

    private func snapshot(_ collections: [CustomInputDictionaryCollection]) -> CustomInputDictionarySnapshot {
        .init(revision: UUID(), collections: collections)
    }

    private func bytes(_ directory: URL) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(CustomInputDictionaryIndex.filename))
    }

    private func assertError<T>(_ expected: CustomInputDictionaryIndexError,
                                file: StaticString = #filePath, line: UInt = #line,
                                _ operation: () throws -> T) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? CustomInputDictionaryIndexError, expected, file: file, line: line)
        }
    }

    private func store(_ path: URL) -> CustomInputDictionaryStore {
        CustomInputDictionaryStore(directory: path, rules: .init(
            isSupportedMode: { $0 == "test" }, normalizeReading: { _, value in value }))
    }

    func testSavedSourceSurvivesFailedIndexAndReopenThenRepair() throws {
        let path = directory()
        let writer = store(path)
        let first = try writer.apply(writer.preview(data: Data("a\tfirst".utf8), modeID: "test"), name: "Words")
        try writer.rebuildIndex()
        let oldIndex = try bytes(path)
        let saved = try writer.addEntry(collectionID: first.collections[0].id, reading: "b", output: "e\u{301}👩🏽‍💻",
                                        expectedRevision: first.revision)
        let sourceURL = path.appendingPathComponent(CustomInputDictionaryStore.filename)
        let savedBytes = try Data(contentsOf: sourceURL)
        assertError(.cancelled) { try writer.rebuildIndex(isCancelled: { true }) }
        XCTAssertEqual(try bytes(path), oldIndex)
        let reopened = store(path)
        XCTAssertEqual(try reopened.snapshot(), saved)
        XCTAssertTrue(try reopened.indexNeedsRebuild(for: saved.revision))
        try reopened.rebuildIndex()
        XCTAssertFalse(try reopened.indexNeedsRebuild(for: saved.revision))
        XCTAssertEqual(try Data(contentsOf: sourceURL), savedBytes)
        XCTAssertEqual(try CustomInputDictionaryIndex(directory: path).lookup(modeID: "test", normalizedReading: "b").first?.output.utf8.map { $0 },
                       Array("e\u{301}👩🏽‍💻".utf8))
    }

    func testMissingIndexDetectionIsReadOnlyAndRepairsEmptyAndSavedSource() throws {
        let path = directory()
        let writer = store(path)
        XCTAssertTrue(try writer.indexNeedsRebuild(for: writer.snapshot().revision))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        try writer.rebuildIndex()
        XCTAssertFalse(try writer.indexNeedsRebuild(for: writer.snapshot().revision))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.appendingPathComponent(CustomInputDictionaryStore.filename).path))
        let saved = try writer.apply(writer.preview(data: Data("a\tword".utf8), modeID: "test"), name: "Words")
        XCTAssertTrue(try writer.indexNeedsRebuild(for: saved.revision))
        try FileManager.default.removeItem(at: path.appendingPathComponent(CustomInputDictionaryIndex.filename))
        XCTAssertTrue(try store(path).indexNeedsRebuild(for: saved.revision))
        try store(path).rebuildIndex()
        XCTAssertEqual(try store(path).snapshot(), saved)
        // Repair leaves the persisted import Undo marker untouched.
        XCTAssertEqual(try writer.undoLastImport(expectedRevision: saved.revision).totalEntryCount, 0)
    }

    func testSourceEditDuringStagingCannotPublishStaleIndex() throws {
        let path = directory()
        let writer = store(path)
        let first = try writer.apply(writer.preview(data: Data("a\tfirst".utf8), modeID: "test"), name: "Words")
        try writer.rebuildIndex()
        let oldIndex = try bytes(path)
        var intervening: CustomInputDictionarySnapshot?
        var editError: Error?
        XCTAssertThrowsError(try writer.rebuildIndex(isCancelled: {
            if intervening == nil && editError == nil,
               (try? FileManager.default.contentsOfDirectory(atPath: path.path).contains(where: { $0.hasPrefix(".custom-input-index-") })) == true {
                do {
                    intervening = try self.store(path).addEntry(collectionID: first.collections[0].id, reading: "b", output: "later",
                                                               expectedRevision: first.revision)
                } catch { editError = error }
            }
            return false
        })) { error in
            guard case CustomInputDictionaryStoreError.revisionConflict = error else {
                return XCTFail("Expected source revision conflict, got \(error)")
            }
        }
        XCTAssertNil(editError)
        let latest = try XCTUnwrap(intervening)
        XCTAssertEqual(try writer.snapshot(), latest)
        XCTAssertEqual(try bytes(path), oldIndex)
        XCTAssertTrue(try writer.indexNeedsRebuild(for: latest.revision))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: path.path).contains(where: { $0.hasPrefix(".custom-input-index-") }))
        try store(path).rebuildIndex()
        XCTAssertFalse(try writer.indexNeedsRebuild(for: latest.revision))
        XCTAssertEqual(try CustomInputDictionaryIndex(directory: path).lookup(modeID: "test", normalizedReading: "b").first?.output, "later")
    }

    func testRecoveryPreservesCompetingIndexPublicationCAS() throws {
        let path = directory()
        let writer = store(path)
        let first = try writer.apply(writer.preview(data: Data("a\tfirst".utf8), modeID: "test"), name: "Words")
        try writer.rebuildIndex()
        let latest = try writer.addEntry(collectionID: first.collections[0].id, reading: "b", output: "later", expectedRevision: first.revision)
        var didPublish = false
        var competingError: Error?
        assertError(.revisionConflict(expected: first.revision, actual: latest.revision)) {
            try writer.rebuildIndex(isCancelled: {
                if !didPublish,
                   (try? FileManager.default.contentsOfDirectory(atPath: path.path).contains(where: { $0.hasPrefix(".custom-input-index-") })) == true {
                    didPublish = true
                    do { try self.store(path).rebuildIndex() } catch { competingError = error }
                }
                return false
            })
        }
        XCTAssertTrue(didPublish)
        XCTAssertNil(competingError)
        XCTAssertEqual(try writer.snapshot(), latest)
        XCTAssertFalse(try writer.indexNeedsRebuild(for: latest.revision))
    }

    func testCorruptIndexRecoveryErrorsWithoutOverwritingEitherFile() throws {
        let path = directory()
        let writer = store(path)
        let saved = try writer.apply(writer.preview(data: Data("a\tword".utf8), modeID: "test"), name: "Words")
        let sourceURL = path.appendingPathComponent(CustomInputDictionaryStore.filename)
        let sourceBytes = try Data(contentsOf: sourceURL)
        let corrupt = Data(repeating: 0x41, count: 4096)
        try corrupt.write(to: path.appendingPathComponent(CustomInputDictionaryIndex.filename))
        XCTAssertThrowsError(try writer.indexNeedsRebuild(for: saved.revision))
        XCTAssertThrowsError(try writer.rebuildIndex())
        XCTAssertEqual(try store(path).snapshot(), saved)
        XCTAssertEqual(try bytes(path), corrupt)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: path.path).contains(where: { $0.hasPrefix(".custom-input-index-") }))
    }

    func testCorruptSourceNeverRebuiltAsEmpty() throws {
        let path = directory()
        let writer = store(path)
        _ = try writer.apply(writer.preview(data: Data("a\tword".utf8), modeID: "test"), name: "Words")
        try writer.rebuildIndex()
        let oldIndex = try bytes(path)
        let sourceURL = path.appendingPathComponent(CustomInputDictionaryStore.filename)
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: sourceURL)
        XCTAssertThrowsError(try writer.snapshot())
        XCTAssertThrowsError(try writer.rebuildIndex())
        XCTAssertEqual(try bytes(path), oldIndex)
        XCTAssertEqual(try Data(contentsOf: sourceURL), corrupt)
    }

    func testEmptyCompiledIndexHasRevisionAndNoResults() throws {
        let path = directory()
        let source = snapshot([])
        let stats = try CustomInputDictionaryIndexCompiler.compile(snapshot: source, directory: path)
        let index = try CustomInputDictionaryIndex(directory: path)
        XCTAssertEqual(stats.revision, source.revision)
        XCTAssertEqual(stats.indexedCandidates, 0)
        XCTAssertEqual(stats.indexedReadings, 0)
        XCTAssertEqual(index.revision, source.revision)
        XCTAssertTrue(try index.lookup(modeID: "test", normalizedReading: "a").isEmpty)
    }

    func testEnabledCollectionsDeduplicateExactOutputByMaximumNotSum() throws {
        let path = directory()
        let source = snapshot([
            collection([.init(reading: "a", output: "same", weight: 9), .init(reading: "a", output: "other", weight: 15)]),
            collection([.init(reading: "a", output: "same", weight: 10)]),
            collection([.init(reading: "a", output: "same", weight: 10000), .init(reading: "a", output: "disabled", weight: 10000)], enabled: false)
        ])
        let stats = try CustomInputDictionaryIndexCompiler.compile(snapshot: source, directory: path)
        let index = try CustomInputDictionaryIndex(directory: path)
        XCTAssertEqual(stats.enabledSourceEntries, 3)
        XCTAssertEqual(stats.indexedCandidates, 2)
        XCTAssertEqual(stats.indexedReadings, 1)
        let found = try index.lookup(modeID: "test", normalizedReading: "a")
        XCTAssertEqual(found.map(\.output), ["other", "same"])
        XCTAssertEqual(found.map(\.weight), [15, 10])
    }

    func testUTF8ExactOutputsReadingsAndModesIncludingCanonicalEquivalence() throws {
        let path = directory()
        let composed = "é", decomposed = "e\u{301}"
        let source = snapshot([
            collection([.init(reading: "a", output: composed, weight: 1), .init(reading: "a", output: decomposed, weight: 1),
                        .init(reading: composed, output: "composed reading"), .init(reading: decomposed, output: "decomposed reading")]),
            collection([.init(reading: "a", output: "composed mode")], mode: composed),
            collection([.init(reading: "a", output: "decomposed mode")], mode: decomposed)
        ])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: source, directory: path)
        let index = try CustomInputDictionaryIndex(directory: path)
        let candidates = try index.lookup(modeID: "test", normalizedReading: "a")
        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(Data(candidates[0].output.utf8), Data(decomposed.utf8)) // binary tie order
        XCTAssertEqual(Data(candidates[1].output.utf8), Data(composed.utf8))
        XCTAssertNotEqual(candidates[0], candidates[1])
        XCTAssertEqual(try index.lookup(modeID: "test", normalizedReading: composed).first?.output, "composed reading")
        XCTAssertEqual(try index.lookup(modeID: "test", normalizedReading: decomposed).first?.output, "decomposed reading")
        XCTAssertEqual(try index.lookup(modeID: composed, normalizedReading: "a").first?.output, "composed mode")
        XCTAssertEqual(try index.lookup(modeID: decomposed, normalizedReading: "a").first?.output, "decomposed mode")
    }

    func testTop48StoredAndReturnedWithDeterministicBinaryTieOrder() throws {
        let entries = (0..<1000).map { CustomInputDictionaryEntry(reading: "a", output: String(format: "o%04d", $0), weight: $0 / 10) }
        let path = directory()
        let source = snapshot([collection(entries)])
        let stats = try CustomInputDictionaryIndexCompiler.compile(snapshot: source, directory: path)
        let index = try CustomInputDictionaryIndex(directory: path)
        XCTAssertEqual(stats.indexedCandidates, 48)
        XCTAssertEqual(index.indexedCandidateCount, 48)
        let expected = entries.sorted {
            $0.weight == $1.weight ? Data($0.output.utf8).lexicographicallyPrecedes(Data($1.output.utf8)) : $0.weight > $1.weight
        }.prefix(48)
        let found = try index.lookup(modeID: "test", normalizedReading: "a", limit: Int.max)
        XCTAssertEqual(found.map(\.output), expected.map(\.output))
        XCTAssertEqual(found.map(\.weight), expected.map(\.weight))
        XCTAssertEqual(try index.lookup(modeID: "test", normalizedReading: "a", limit: 1), Array(found.prefix(1)))
        XCTAssertTrue(try index.lookup(modeID: "test", normalizedReading: "a", limit: 0).isEmpty)
        assertError(.invalidLookup) { try index.lookup(modeID: "test", normalizedReading: "a", limit: -1) }
        let reordered = snapshot([collection(Array(entries.reversed()))])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: reordered, directory: path, expectedPublishedRevision: source.revision)
        XCTAssertEqual(try index.reopened().lookup(modeID: "test", normalizedReading: "a"), found)
    }

    func testModeAndReadingMatchesAreExactNotPrefixesAndNoNormalizerIsInvented() throws {
        let path = directory()
        try CustomInputDictionaryIndexCompiler.compile(snapshot: snapshot([
            collection([.init(reading: "abc", output: "exact")], mode: "mode.one"),
            collection([.init(reading: "abc", output: "different mode")], mode: "mode.two")
        ]), directory: path)
        let index = try CustomInputDictionaryIndex(directory: path)
        XCTAssertTrue(try index.lookup(modeID: "mode.one", normalizedReading: "ab").isEmpty)
        XCTAssertTrue(try index.lookup(modeID: "mode.one", normalizedReading: "ABC").isEmpty)
        XCTAssertTrue(try index.lookup(modeID: "missing", normalizedReading: "abc").isEmpty)
        XCTAssertEqual(try index.lookup(modeID: "mode.two", normalizedReading: "abc").first?.output, "different mode")
        for field in ["", "bad\0", "bad\n", String(repeating: "x", count: 257)] {
            assertError(.invalidLookup) { try index.lookup(modeID: "mode.one", normalizedReading: field) }
            assertError(.invalidLookup) { try index.lookup(modeID: field, normalizedReading: "abc") }
        }
    }

    func testMaximumUTF8FieldsAndExactSupplementaryCombiningSequences() throws {
        let path = directory()
        let mode = String(repeating: "𠀀", count: 256)
        let reading = String(repeating: "𠀁", count: 256)
        let output = "👩🏽‍💻" + String(repeating: "e\u{301}", count: 120)
        XCTAssertLessThanOrEqual(output.unicodeScalars.count, 256)
        let maxOutput = String(repeating: "𠀂", count: 256)
        try CustomInputDictionaryIndexCompiler.compile(snapshot: snapshot([
            collection([.init(reading: reading, output: output), .init(reading: reading, output: maxOutput, weight: 9999)], mode: mode)
        ]), directory: path)
        let index = try CustomInputDictionaryIndex(directory: path)
        let found = try index.lookup(modeID: mode, normalizedReading: reading)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Data(found[0].output.utf8), Data(maxOutput.utf8))
        XCTAssertEqual(Data(found[1].output.utf8), Data(output.utf8))
        XCTAssertLessThanOrEqual(try bytes(path).count, CustomInputDictionaryIndex.maximumFileBytes)
    }

    func testHeldReadersStayOnOldInodeUntilExplicitReopen() throws {
        let path = directory()
        let first = snapshot([collection([.init(reading: "a", output: "old")])])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: first, directory: path)
        let old = try CustomInputDictionaryIndex(directory: path)
        XCTAssertEqual(try old.lookup(modeID: "test", normalizedReading: "a").first?.output, "old")
        let second = snapshot([collection([.init(reading: "a", output: "new")])])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: second, directory: path, expectedPublishedRevision: first.revision)
        XCTAssertEqual(old.revision, first.revision)
        XCTAssertEqual(try old.lookup(modeID: "test", normalizedReading: "a").first?.output, "old")
        let current = try old.reopened()
        XCTAssertEqual(current.revision, second.revision)
        XCTAssertEqual(try current.lookup(modeID: "test", normalizedReading: "a").first?.output, "new")
        let third = snapshot([])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: third, directory: path, expectedPublishedRevision: second.revision)
        XCTAssertEqual(try old.lookup(modeID: "test", normalizedReading: "a").first?.output, "old")
        XCTAssertEqual(try current.lookup(modeID: "test", normalizedReading: "a").first?.output, "new")
        XCTAssertTrue(try current.reopened().lookup(modeID: "test", normalizedReading: "a").isEmpty)
    }

    func testStalePublicationConflictsPreservePriorBytesAndRemoveStaging() throws {
        let path = directory()
        let first = snapshot([collection([.init(reading: "a", output: "first")])])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: first, directory: path)
        let original = try bytes(path)
        let second = snapshot([collection([.init(reading: "a", output: "second")])])
        assertError(.revisionConflict(expected: nil, actual: first.revision)) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: second, directory: path)
        }
        let stale = UUID()
        assertError(.revisionConflict(expected: stale, actual: first.revision)) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: second, directory: path, expectedPublishedRevision: stale)
        }
        XCTAssertEqual(try bytes(path), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path.path), [CustomInputDictionaryIndex.filename])
    }

    func testCancellationBeforeAndDuringStagingNeverChangesPublishedFile() throws {
        let path = directory()
        let first = snapshot([collection([.init(reading: "a", output: "first")])])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: first, directory: path)
        let original = try bytes(path)
        let next = snapshot([collection([.init(reading: "a", output: "next")])])
        assertError(.cancelled) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: next, directory: path,
                expectedPublishedRevision: first.revision, isCancelled: { true })
        }
        assertError(.cancelled) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: next, directory: path, expectedPublishedRevision: first.revision,
                isCancelled: { (try? FileManager.default.contentsOfDirectory(atPath: path.path).contains(where: { $0.hasPrefix(".custom-input-index-") })) == true })
        }
        XCTAssertEqual(try bytes(path), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path.path), [CustomInputDictionaryIndex.filename])
    }

    func testCompilerRejectsInvalidSourceWithoutDamagingWorkingIndex() throws {
        let path = directory()
        let good = snapshot([collection([.init(reading: "a", output: "good")])])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: good, directory: path)
        let original = try bytes(path)
        let invalidEntries: [CustomInputDictionaryEntry] = [
            .init(reading: "", output: "x"), .init(reading: "a", output: "bad\0"),
            .init(reading: "a", output: String(repeating: "𠀀", count: 257)), .init(reading: "a", output: "x", weight: 10001)
        ]
        for entry in invalidEntries {
            assertError(.invalidSnapshot) {
                try CustomInputDictionaryIndexCompiler.compile(snapshot: snapshot([collection([entry])]), directory: path, expectedPublishedRevision: good.revision)
            }
        }
        let duplicate = CustomInputDictionaryEntry(reading: "a", output: "x")
        assertError(.invalidSnapshot) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: snapshot([collection([duplicate, duplicate])]), directory: path, expectedPublishedRevision: good.revision)
        }
        let tooManyEntries = snapshot([collection(Array(repeating: duplicate, count: CustomInputDictionaryLimits.totalEntries + 1))])
        assertError(.invalidSnapshot) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: tooManyEntries, directory: path, expectedPublishedRevision: good.revision)
        }
        let emptyCollection = collection([])
        let tooManyCollections = snapshot(Array(repeating: emptyCollection, count: CustomInputDictionaryLimits.totalCollections + 1))
        assertError(.invalidSnapshot) {
            try CustomInputDictionaryIndexCompiler.compile(snapshot: tooManyCollections, directory: path, expectedPublishedRevision: good.revision)
        }
        XCTAssertEqual(try bytes(path), original)
    }

    func testReadOnlyLookupCreatesNoSidecarsOrSourceJSONAndUsesCoveringPrimaryKey() throws {
        let path = directory()
        let source = snapshot([collection([.init(reading: "a", output: "x")])])
        try CustomInputDictionaryIndexCompiler.compile(snapshot: source, directory: path)
        let original = try bytes(path)
        let before = try FileManager.default.contentsOfDirectory(atPath: path.path)
        let index = try CustomInputDictionaryIndex(directory: path)
        for _ in 0..<20 { XCTAssertEqual(try index.lookup(modeID: "test", normalizedReading: "a").count, 1) }
        XCTAssertEqual(try bytes(path), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: path.path), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.appendingPathComponent(CustomInputDictionaryStore.filename).path))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(path.appendingPathComponent(CustomInputDictionaryIndex.filename).path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let handle = try XCTUnwrap(db)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_db_readonly(handle, "main"), 1)
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, "EXPLAIN QUERY PLAN SELECT output,weight FROM entries WHERE mode=? AND reading=? ORDER BY weight DESC,output LIMIT 48", -1, &statement, nil), SQLITE_OK)
        let query = try XCTUnwrap(statement)
        defer { sqlite3_finalize(query) }
        XCTAssertEqual(sqlite3_step(query), SQLITE_ROW)
        let detail = try XCTUnwrap(sqlite3_column_text(query, 3))
        let plan = String(cString: detail)
        XCTAssertTrue(plan.contains("SEARCH entries USING PRIMARY KEY"))
        XCTAssertFalse(plan.contains("TEMP B-TREE"))
    }

    func testMissingCorruptAndOversizeFilesFailWithoutMutation() throws {
        let missing = directory()
        assertError(.missingIndex) { try CustomInputDictionaryIndex(directory: missing) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let corrupt = directory()
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        let url = corrupt.appendingPathComponent(CustomInputDictionaryIndex.filename)
        let data = Data(repeating: 0x41, count: 4096)
        try data.write(to: url)
        XCTAssertThrowsError(try CustomInputDictionaryIndex(directory: corrupt))
        XCTAssertEqual(try Data(contentsOf: url), data)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: UInt64(CustomInputDictionaryIndex.maximumFileBytes + 4096))
        try file.close()
        assertError(.fileTooLarge) { try CustomInputDictionaryIndex(directory: corrupt) }
    }

    func testDiskCapDerivedFromAuthorizedTotalAndUTF8Bounds() {
        XCTAssertEqual(CustomInputDictionaryIndex.maximumFileBytes,
                       (CustomInputDictionaryLimits.totalEntries * 2 + 256) * 4096)
        XCTAssertGreaterThan(CustomInputDictionaryIndex.maximumFileBytes,
                             CustomInputDictionaryLimits.totalEntries * 3 * CustomInputDictionaryLimits.fieldScalars * 4)
        XCTAssertEqual(CustomInputDictionaryIndex.maximumCandidates, 48)
    }
}

#if !canImport(UniboardCore)
/// Native app-model coverage (not silently counted as SwiftPM core coverage).
@MainActor
final class MyWordsIndexRecoveryModelTests: XCTestCase {
    private var rules: CustomInputDictionaryRules {
        .init(isSupportedMode: { $0 == LanguageInputMode.direct.rawValue }, normalizeReading: { _, value in value })
    }

    func testFailedPublicationAfterSaveIsRediscoveredByNewModelAndVerifiedOnRetry() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let model = MyWordsModel(directory: path, rules: rules) { throw CocoaError(.fileWriteOutOfSpace) }
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertTrue(model.needsIndexRetry)
        let saved = await model.create(name: "Words", mode: .direct)
        XCTAssertTrue(saved) // Source save succeeded even though publication failed.
        XCTAssertTrue(model.needsIndexRetry)
        let revision = model.snapshot.revision
        let writer = CustomInputDictionaryStore(directory: path, rules: rules)
        let reopened = MyWordsModel(directory: path, rules: rules) {
            _ = try await Task.detached { try writer.rebuildIndex() }.value
        }
        await reopened.load()
        XCTAssertEqual(reopened.snapshot.revision, revision)
        XCTAssertTrue(reopened.needsIndexRetry)
        await reopened.retryIndex()
        XCTAssertFalse(reopened.needsIndexRetry)
        XCTAssertNil(reopened.errorMessage)
        XCTAssertEqual(reopened.snapshot.revision, revision)
    }

    func testLoadDetectsStaleIndexAndNoOpPublisherCannotClaimSuccess() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let writer = CustomInputDictionaryStore(directory: path, rules: rules)
        let first = try writer.createCollection(name: "First", modeID: LanguageInputMode.direct.rawValue,
                                                expectedRevision: CustomInputDictionarySnapshot.empty.revision)
        try writer.rebuildIndex()
        let latest = try writer.renameCollection(id: first.collections[0].id, name: "Later", expectedRevision: first.revision)
        let model = MyWordsModel(directory: path, rules: rules) { }
        await model.load()
        XCTAssertEqual(model.snapshot.revision, latest.revision)
        XCTAssertTrue(model.needsIndexRetry)
        await model.retryIndex()
        XCTAssertTrue(model.needsIndexRetry)
        try writer.rebuildIndex()
        await model.load()
        XCTAssertFalse(model.needsIndexRetry)
    }

    func testCorruptIndexStillLoadsSourceAndRetryDoesNotReplaceCorruptBytes() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let writer = CustomInputDictionaryStore(directory: path, rules: rules)
        let saved = try writer.createCollection(name: "Words", modeID: LanguageInputMode.direct.rawValue,
                                                expectedRevision: CustomInputDictionarySnapshot.empty.revision)
        let corrupt = Data(repeating: 0x41, count: 4096)
        let indexURL = path.appendingPathComponent(CustomInputDictionaryIndex.filename)
        try corrupt.write(to: indexURL)
        let model = MyWordsModel(directory: path, rules: rules) {
            _ = try await Task.detached { try writer.rebuildIndex() }.value
        }
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.snapshot, saved)
        XCTAssertTrue(model.needsIndexRetry)
        XCTAssertNotNil(model.errorMessage)
        await model.retryIndex()
        XCTAssertTrue(model.needsIndexRetry)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(try Data(contentsOf: indexURL), corrupt)
        XCTAssertEqual(try writer.snapshot(), saved)
    }
}
#endif
