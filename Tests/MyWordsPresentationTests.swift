import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class MyWordsPresentationTests: XCTestCase {
    private func snapshot(_ collections: [CustomInputDictionaryCollection]) -> CustomInputDictionarySnapshot {
        .init(revision: UUID(), collections: collections)
    }
    private func entry(_ reading: String, _ output: String = "match", _ weight: Int = 100) -> CustomInputDictionaryEntry {
        .init(reading: reading, output: output, weight: weight)
    }

    func testSearchIncludesOffCollectionsInOriginalOrderAndStopsAt100() {
        let first = CustomInputDictionaryCollection(name: "First", modeID: "direct", enabled: false,
            entries: (0..<60).map { entry("a\($0)") })
        let second = CustomInputDictionaryCollection(name: "Second", modeID: "direct", entries: (0..<60).map { entry("b\($0)") })
        let source = snapshot([first, second])
        let result = MyWordsPresentation.search(source, query: "match")
        XCTAssertEqual(result.entries.count, 100)
        XCTAssertTrue(result.hasMore)
        XCTAssertEqual(result.entries.first?.id.collectionID, first.id)
        XCTAssertEqual(result.entries.last?.id.collectionID, second.id)
        XCTAssertEqual(result.entries.last?.id.index, 39)
        XCTAssertEqual(result.entries.last?.id.revision, source.revision)
        XCTAssertEqual(result.entries.last?.id.identity, second.entries[39].identity)
    }

    func testSearchModeScopeEmptyAndExactly100DoNotClaimTruncation() {
        let direct = CustomInputDictionaryCollection(name: "D", modeID: "direct", entries: (0..<100).map { entry("a\($0)") })
        let japanese = CustomInputDictionaryCollection(name: "J", modeID: "japaneseRomaji", entries: [entry("jp")])
        let source = snapshot([direct, japanese])
        let result = MyWordsPresentation.search(source, query: "match", modeID: "direct")
        XCTAssertEqual(result.entries.count, 100)
        XCTAssertFalse(result.hasMore)
        XCTAssertEqual(MyWordsPresentation.search(source, query: "JP", modeID: "japaneseRomaji").entries.count, 1)
        XCTAssertTrue(MyWordsPresentation.search(source, query: "").entries.isEmpty)
        XCTAssertTrue(MyWordsPresentation.search(source, query: "missing").entries.isEmpty)
    }

    func testEqualPairsAcrossCollectionsAreDistinctAndExactUnicodeIdentitySurvives() {
        let collection = CustomInputDictionaryCollection(name: "D", modeID: "direct", entries: [entry("same", "é"), entry("same", "e\u{301}")])
        let other = CustomInputDictionaryCollection(name: "D", modeID: "direct", entries: collection.entries)
        let result = MyWordsPresentation.search(snapshot([collection, other]), query: "same")
        XCTAssertEqual(Set(result.entries.map(\.id)).count, 4)
        XCTAssertNotEqual(result.entries[0].id.identity, result.entries[1].id.identity)
    }

    func testSortIsPresentationOnlyDeterministicAndWeightDescending() {
        let entries = [entry("z", "b", 20), entry("a", "z", 10), entry("a", "a", 20), entry("a", "a", 20)]
        let before = entries
        XCTAssertEqual(MyWordsPresentation.sortedIndices(entries, query: "", sort: .original), [0, 1, 2, 3])
        XCTAssertEqual(MyWordsPresentation.sortedIndices(entries, query: "", sort: .reading), [2, 3, 1, 0])
        XCTAssertEqual(MyWordsPresentation.sortedIndices(entries, query: "", sort: .weight), [2, 3, 0, 1])
        XCTAssertEqual(MyWordsPresentation.sortedIndices(entries, query: "z", sort: .weight), [0, 1])
        XCTAssertEqual(entries, before)
    }

    func testDuplicatePairIgnoresWeightAndUsesExactOutputBytes() {
        let source = entry("word", "é", 500)
        XCTAssertTrue(MyWordsPresentation.isUnchangedPair(reading: "word", output: "é", source: source))
        XCTAssertFalse(MyWordsPresentation.isUnchangedPair(reading: "word", output: "e\u{301}", source: source))
        XCTAssertFalse(MyWordsPresentation.isUnchangedPair(reading: "words", output: "é", source: source))
    }

    func testInspectionPreservesEveryScalarAndUsesNamesAndStandIns() {
        let text = "👩\u{200D}💻\u{FE0F}e\u{301}\u{200B} "
        let inspection = MyWordsOutputInspection(text)
        XCTAssertEqual(Data(inspection.text.utf8), Data(text.utf8))
        XCTAssertEqual(inspection.scalars.map(\.value), text.unicodeScalars.map(\.value))
        XCTAssertEqual(inspection.scalars[1].name, "Zero Width Joiner")
        XCTAssertEqual(inspection.scalars[1].glyph, "◌")
        XCTAssertEqual(inspection.scalars[3].codePoint, "U+FE0F")
        XCTAssertEqual(inspection.scalars[5].glyph, "◌\u{301}")
        XCTAssertEqual(inspection.scalars.last?.glyph, "␠")
        XCTAssertTrue(inspection.scalars[3].usesStandIn)
        XCTAssertNotEqual(inspection.scalars[0].name, "Not available")
        XCTAssertTrue(MyWordsOutputInspection("").scalars.isEmpty)
    }

    func testPagesClampAndReachEveryEntryAndProblem() {
        XCTAssertEqual(MyWordsPage(total: 101, page: 1, size: 50).range, 50..<100)
        XCTAssertEqual(MyWordsPage(total: 101, page: 10, size: 50).range, 100..<101)
        XCTAssertEqual(MyWordsPage(total: 0, page: 10, size: 50).range, 0..<0)
        XCTAssertEqual(MyWordsPage(total: 101, page: -1, size: 50).index, 0)
        let indices = (0..<3).flatMap { Array(MyWordsPage(total: 51, page: $0, size: 20).range) }
        XCTAssertEqual(indices, Array(0..<51))
        XCTAssertEqual(MyWordsPage(total: 101, page: 1, size: 50).label(noun: "Entries", total: 101), "Entries 51–100 of 101")
    }

    func testEveryBoundedProblemRetainedAndInvalidFileCannotApply() {
        let rules = CustomInputDictionaryRules(isSupportedMode: { _ in true }, normalizeReading: { _, text in text })
        let data = Data(("good\toutput\n" + String(repeating: "invalid\n", count: 9999)).utf8)
        let preview = CustomInputDictionaryParser.preview(data: data, modeID: "direct", baseRevision: UUID(), existingEntryCount: 0, rules: rules)
        XCTAssertEqual(preview.invalidRowCount, 9999)
        XCTAssertEqual(preview.rowErrors.count, 9999)
        XCTAssertEqual(preview.rowErrors.last?.line, 10000)
        XCTAssertEqual(preview.omittedErrorCount, 0)
        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.entries.count, 1)
    }

    func testPreviewSearchAndPagingDoNotChangeWholeImportScope() {
        let rules = CustomInputDictionaryRules(isSupportedMode: { _ in true }, normalizeReading: { _, text in text })
        let rows = (0..<121).map { "word\($0)\toutput\($0)" }.joined(separator: "\n")
        let preview = CustomInputDictionaryParser.preview(data: Data(rows.utf8), modeID: "direct", baseRevision: UUID(), existingEntryCount: 0, rules: rules)
        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(MyWordsPresentation.sortedIndices(preview.entries, query: "word120", sort: .original), [120])
        XCTAssertEqual(preview.uniqueEntryCount, 121)
        XCTAssertEqual(preview.entries.count, 121)
        XCTAssertEqual(MyWordsPage(total: 121, page: 2, size: 50).range, 100..<121)
    }
}

#if !canImport(UniboardCore)
final class MyWordsPresentationModelTests: XCTestCase {
    private var roots: [URL] = []
    private var rules: CustomInputDictionaryRules {
        .init(isSupportedMode: { _ in true }, normalizeReading: { _, value in value.lowercased() })
    }
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url)
        return url
    }
    override func tearDown() {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots = []
        super.tearDown()
    }
    @MainActor
    func testSupportedModesExplicitlyExcludeBothKoreanMethodsEvenWithPermissiveRules() async throws {
        let model = MyWordsModel(directory: try root(), rules: rules, didMutate: {})
        await model.load()
        XCTAssertEqual(model.supportedModes, [.direct, .japaneseRomaji, .mandarinPinyin])
        XCTAssertEqual(model.choicesPhase, .stale)
        XCTAssertTrue(model.sourceReadable)
        await model.retryIndex()
        XCTAssertEqual(model.choicesPhase, .stale) // A no-op publisher is not success.
    }
    @MainActor
    func testVerifiedRetryHasExplicitUpdatedPhaseAndDoesNotAlterSource() async throws {
        let directory = try root(), rules = rules
        let store = CustomInputDictionaryStore(directory: directory, rules: rules)
        _ = try store.createCollection(name: "D", modeID: "direct", enabled: false, expectedRevision: store.snapshot().revision)
        let before = try store.snapshot()
        let model = MyWordsModel(directory: directory, rules: rules) {
            _ = try await Task.detached { try CustomInputDictionaryStore(directory: directory, rules: rules).rebuildIndex() }.value
        }
        await model.load()
        XCTAssertEqual(model.choicesPhase, .stale)
        await model.retryIndex()
        XCTAssertEqual(model.choicesPhase, .updated)
        XCTAssertFalse(model.needsIndexRetry)
        XCTAssertEqual(try store.snapshot(), before)
        model.dismissUpdatedChoices()
        XCTAssertEqual(model.choicesPhase, .idle)
    }
    @MainActor
    func testExactIdentityMismatchCannotEditOrDeleteEvenWithCurrentRevision() async throws {
        let directory = try root()
        let store = CustomInputDictionaryStore(directory: directory, rules: rules)
        var source = try store.createCollection(name: "D", modeID: "direct", enabled: false, expectedRevision: store.snapshot().revision)
        let id = try XCTUnwrap(source.collections.first?.id)
        source = try store.addEntry(collectionID: id, reading: "a", output: "é", weight: 10, expectedRevision: source.revision)
        let model = MyWordsModel(directory: directory, rules: rules, didMutate: {})
        await model.load()
        let wrong = CustomInputDictionaryEntry(reading: "a", output: "e\u{301}").identity
        let saved = await model.saveEntry(collectionID: id, index: 0, reading: "a", output: "other", weight: 10, revision: source.revision, expectedIdentity: wrong)
        XCTAssertFalse(saved)
        let deleted = await model.deleteEntry(collectionID: id, index: 0, revision: source.revision, expectedIdentity: wrong)
        XCTAssertFalse(deleted)
        XCTAssertEqual(try store.snapshot(), source)
    }
    @MainActor
    func testSearchResultEditsOriginalEntryAndRejectsStaleRevision() async throws {
        let directory = try root()
        let store = CustomInputDictionaryStore(directory: directory, rules: rules)
        var source = try store.createCollection(name: "D", modeID: "direct", expectedRevision: store.snapshot().revision)
        let id = try XCTUnwrap(source.collections.first?.id)
        source = try store.addEntry(collectionID: id, reading: "z", output: "first", weight: 1, expectedRevision: source.revision)
        source = try store.addEntry(collectionID: id, reading: "a", output: "second", weight: 2, expectedRevision: source.revision)
        let model = MyWordsModel(directory: directory, rules: rules, didMutate: {})
        await model.load()
        let result = await MyWordsModel.search(snapshot: model.snapshot, query: "second", modeID: nil)
        let target = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(target.id.index, 1)
        let saved = await model.saveEntry(collectionID: target.id.collectionID, index: target.id.index,
            reading: "a", output: "changed", weight: 2, revision: target.id.revision, expectedIdentity: target.id.identity)
        XCTAssertTrue(saved)
        XCTAssertEqual(model.snapshot.collections[0].entries.map(\.output), ["first", "changed"])
        let deleted = await model.deleteEntry(collectionID: target.id.collectionID, index: target.id.index,
            revision: target.id.revision, expectedIdentity: target.id.identity)
        XCTAssertFalse(deleted)
        XCTAssertEqual(try store.snapshot().collections[0].entries.count, 2)
    }

    @MainActor
    func testDraftValidationAndInspectionDoNotWriteAndDistinctDuplicateAddsOnlyOneEntry() async throws {
        let directory = try root()
        let store = CustomInputDictionaryStore(directory: directory, rules: rules)
        var source = try store.createCollection(name: "D", modeID: "direct", expectedRevision: store.snapshot().revision)
        let id = try XCTUnwrap(source.collections.first?.id)
        source = try store.addEntry(collectionID: id, reading: "word", output: "é", weight: 77, expectedRevision: source.revision)
        let file = directory.appendingPathComponent(CustomInputDictionaryStore.filename)
        let bytes = try Data(contentsOf: file)
        let model = MyWordsModel(directory: directory, rules: rules, didMutate: {})
        await model.load()
        let validation = await model.validate(reading: "word", output: "é", weight: "77", mode: .direct)
        XCTAssertNil(validation)
        let inspection = MyWordsOutputInspection("é")
        XCTAssertEqual(inspection.scalars.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes) // Draft-only operations have no commit.
        let unchanged = await model.saveEntry(collectionID: id, index: nil, reading: "word", output: "é", weight: 999, revision: source.revision)
        XCTAssertFalse(unchanged)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let distinct = await model.saveEntry(collectionID: id, index: nil, reading: "word", output: "e\u{301}", weight: 77, revision: source.revision)
        XCTAssertTrue(distinct)
        XCTAssertEqual(model.snapshot.collections[0].entries.count, 2)
        XCTAssertEqual(model.snapshot.collections[0].entries[0], source.collections[0].entries[0])
        XCTAssertEqual(Data(model.snapshot.collections[0].entries[1].output.utf8), Data("e\u{301}".utf8))
    }

    @MainActor
    func testUnreadableSourceIsDistinctAndCannotRequestRebuild() async throws {
        let directory = try root()
        let file = directory.appendingPathComponent(CustomInputDictionaryStore.filename)
        let bytes = Data("corrupt".utf8)
        try bytes.write(to: file)
        var rebuilds = 0
        let model = MyWordsModel(directory: directory, rules: rules) { rebuilds += 1 }
        await model.load()
        XCTAssertEqual(model.choicesPhase, .sourceUnreadable)
        XCTAssertFalse(model.sourceReadable)
        XCTAssertFalse(model.needsIndexRetry)
        await model.retryIndex()
        XCTAssertEqual(rebuilds, 0)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    @MainActor
    func testCheckingDelayAndVerifiedUpdatedLifetimeAreExplicit() async throws {
        let directory = try root()
        let slowRules = CustomInputDictionaryRules(isSupportedMode: { _ in
            Thread.sleep(forTimeInterval: 0.25)
            return true
        }, normalizeReading: { _, value in value })
        let model = MyWordsModel(directory: directory, rules: slowRules) {
            try await Task.sleep(nanoseconds: 80_000_000)
            _ = try await Task.detached { try CustomInputDictionaryStore(directory: directory, rules: slowRules).rebuildIndex() }.value
        }
        let loading = Task { await model.load() }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.choicesPhase, .idle) // No flash before half a second.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(model.choicesPhase, .checking)
        await loading.value
        XCTAssertEqual(model.choicesPhase, .stale)
        let retry = Task { await model.retryIndex() }
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertEqual(model.choicesPhase, .rebuilding)
        await retry.value
        XCTAssertEqual(model.choicesPhase, .updated)
        try await Task.sleep(nanoseconds: 4_100_000_000)
        XCTAssertEqual(model.choicesPhase, .idle)
    }

    @MainActor
    func testUnreadableIndexCheckDoesNotClaimARebuildAttempt() async throws {
        let directory = try root()
        try Data(repeating: 0x41, count: 4096).write(to: directory.appendingPathComponent(CustomInputDictionaryIndex.filename))
        var rebuilds = 0
        let model = MyWordsModel(directory: directory, rules: rules) { rebuilds += 1 }
        await model.load()
        XCTAssertEqual(model.choicesPhase, .unreadable)
        XCTAssertEqual(rebuilds, 0)
        XCTAssertTrue(model.sourceReadable)
        XCTAssertTrue(model.needsIndexRetry)
        XCTAssertEqual(model.errorMessage, "Keyboard choices couldn’t be read. Your saved dictionaries haven’t been changed.")
    }

}
#endif
