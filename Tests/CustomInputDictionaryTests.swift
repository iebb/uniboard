import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class CustomInputDictionaryTests: XCTestCase {
    // These are synthetic test rules, NOT a claimed language spelling scheme.
    private let rules = CustomInputDictionaryRules(
        isSupportedMode: { $0 == "test" },
        normalizeReading: { _, value in value == "reject" ? nil : value.lowercased() })
    private let identityRules = CustomInputDictionaryRules(
        isSupportedMode: { $0 == "test" }, normalizeReading: { _, value in value })
    private var temporaryRoots: [URL] = []

    override func tearDown() {
        for root in temporaryRoots { try? FileManager.default.removeItem(at: root) }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    private func directory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CustomInputDictionaryTests-\(UUID().uuidString)")
        temporaryRoots.append(root)
        return root.appendingPathComponent("words")
    }

    private func parse(_ text: String, existing: Int = 0, mode: String = "test",
                       exactReadings: Bool = false) -> CustomInputDictionaryPreview {
        CustomInputDictionaryParser.preview(data: Data(text.utf8), modeID: mode,
            baseRevision: CustomInputDictionarySnapshot.empty.revision, existingEntryCount: existing,
            rules: exactReadings ? identityRules : rules)
    }

    private func assertStoreError<T>(_ expected: CustomInputDictionaryStoreError,
                                     file: StaticString = #filePath, line: UInt = #line,
                                     _ action: () throws -> T) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            XCTAssertEqual(error as? CustomInputDictionaryStoreError, expected, file: file, line: line)
        }
    }

    func testBOMCRLFCommentsBlankLinesAndDefaultWeight() {
        let preview = parse("\u{FEFF}# comment\r\n\r\n   \r\nA\toutput\r\nb\tother\t0\r\nc\tthird\t10000\r\n")
        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.entryLineCount, 3)
        XCTAssertEqual(preview.validRowCount, 3)
        XCTAssertEqual(preview.invalidRowCount, 0)
        XCTAssertEqual(preview.entries.map(\.reading), ["a", "b", "c"])
        XCTAssertEqual(preview.entries.map(\.weight), [100, 0, 10000])
        XCTAssertEqual(preview.examples.map(\.line), [4, 5, 6])
    }

    func testInvalidUTF8AndByteBounds() {
        let invalid = CustomInputDictionaryParser.preview(data: Data([0x61, 0x09, 0xFF]), modeID: "test",
            baseRevision: UUID(), existingEntryCount: 0, rules: rules)
        XCTAssertEqual(invalid.fileIssues, [.invalidUTF8])
        let oversized = CustomInputDictionaryParser.preview(data: Data(count: CustomInputDictionaryLimits.importBytes + 1),
            modeID: "test", baseRevision: UUID(), existingEntryCount: 0, rules: rules)
        XCTAssertEqual(oversized.fileIssues, [.tooLarge])
        let suffix = "\na\tb"
        let atLimit = "#" + String(repeating: "x", count: CustomInputDictionaryLimits.importBytes - 1 - suffix.utf8.count) + suffix
        XCTAssertEqual(atLimit.utf8.count, CustomInputDictionaryLimits.importBytes)
        XCTAssertTrue(parse(atLimit).canApply)
    }

    func testInvalidColumnCountsAndEmptyFieldsAreLineSpecific() {
        let preview = parse("# comment\nno tab\na\tb\tc\td\n\toutput\na\t\n\t\n")
        XCTAssertFalse(preview.canApply)
        XCTAssertEqual(preview.invalidRowCount, 5)
        XCTAssertEqual(preview.rowErrors.map(\.line), [2, 3, 4, 5, 6])
        XCTAssertEqual(preview.rowErrors.map(\.issue), [.missingTab, .columnCount, .emptyReading, .emptyOutput, .emptyReading])
    }

    func testCommentsOnlyAtStartAndNoHeaderHeuristic() {
        let preview = parse("#a\tx\nreading\toutput\n #a\t#output\n")
        XCTAssertEqual(preview.entries.count, 2)
        XCTAssertEqual(preview.entries[0].reading, "reading") // no header is consumed
        XCTAssertEqual(preview.entries[1].reading, " #a")
        XCTAssertEqual(preview.entries[1].output, "#output")
        XCTAssertEqual(parse("\n # not a comment\n").rowErrors.first?.line, 2)
    }

    func testWeightsAreStrictASCIIRangeCheckedIntegers() {
        for weight in ["", "-1", "+1", " 1", "1 ", "1.0", "10001", "١", String(repeating: "9", count: 100)] {
            let preview = parse("a\tb\t\(weight)")
            XCTAssertEqual(preview.rowErrors.first?.issue, .invalidWeight)
            XCTAssertFalse(preview.canApply)
        }
        XCTAssertTrue(parse("a\tb\t0001").canApply)
    }

    func testInvalidRowsBlockOtherwiseValidImportAndRetainedErrorsAreBounded() {
        let preview = parse("a\tb\n" + String(repeating: "bad\n", count: 100))
        XCTAssertEqual(preview.validRowCount, 1)
        XCTAssertEqual(preview.invalidRowCount, 100)
        XCTAssertEqual(preview.rowErrors.count, 100)
        XCTAssertEqual(preview.omittedErrorCount, 0)
        XCTAssertLessThanOrEqual(preview.rowErrors.count, CustomInputDictionaryLimits.retainedErrors)
        XCTAssertFalse(preview.canApply)
        let many = parse((0..<100).map { "r\($0)\to\($0)" }.joined(separator: "\n"))
        XCTAssertEqual(many.entries.count, 100)
        XCTAssertEqual(many.examples.count, CustomInputDictionaryLimits.retainedExamples)
    }

    func testDuplicateIdentityIsNormalizedReadingExactOutputHighestResolvedWeight() {
        let preview = parse("A\tone\t1\na\tone\t999\na\tone\t20\na\ttwo\na\ttwo\t1\n")
        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.validRowCount, 5)
        XCTAssertEqual(preview.uniqueEntryCount, 2)
        XCTAssertEqual(preview.duplicateRowCount, 0)
        XCTAssertEqual(preview.combinedCount, 3)
        XCTAssertEqual(preview.entries.map(\.weight), [999, 100])
        XCTAssertEqual(preview.examples[0].entry.weight, 999)
        XCTAssertEqual(preview.examples[0].line, 1)
    }

    func testExactTripleRepeatsAreDuplicatesNotCombinedEvenAfterHigherWeight() {
        let preview = parse("A\tone\t1\na\tone\t999\na\tone\t1\na\tone\t999\na\ttwo\na\ttwo\t100\na\tone\t20")
        XCTAssertTrue(preview.canApply)
        XCTAssertEqual(preview.validRowCount, 7)
        XCTAssertEqual(preview.uniqueEntryCount, 2)
        XCTAssertEqual(preview.duplicateRowCount, 3)
        XCTAssertEqual(preview.combinedCount, 2)
        XCTAssertEqual(preview.invalidRowCount, 0)
        XCTAssertEqual(preview.entries.map(\.weight), [999, 100])
        XCTAssertEqual(preview.validRowCount, preview.uniqueEntryCount + preview.duplicateRowCount + preview.combinedCount)
    }

    func testWeightCombiningNeverMergesCanonicallyEquivalentButDistinctOutputs() {
        let preview = parse("a\té\t1\na\té\t2\na\te\u{301}\t3\na\te\u{301}\t3")
        XCTAssertEqual(preview.uniqueEntryCount, 2)
        XCTAssertEqual(preview.combinedCount, 1)
        XCTAssertEqual(preview.duplicateRowCount, 1)
        XCTAssertEqual(preview.entries.map(\.weight), [2, 3])
        XCTAssertNotEqual(preview.entries[0].identity, preview.entries[1].identity)
    }

    func testCanonicallyEquivalentOutputsAndReadingsAreNotConflated() {
        let composed = "é", decomposed = "e\u{301}"
        XCTAssertEqual(composed, decomposed) // demonstrates why String keys are wrong
        let preview = parse("a\t\(composed)\na\t\(decomposed)\n\(composed)\tx\n\(decomposed)\tx", exactReadings: true)
        XCTAssertEqual(preview.uniqueEntryCount, 4)
        XCTAssertEqual(preview.duplicateRowCount, 0)
        XCTAssertNotEqual(preview.entries[0], preview.entries[1])
        XCTAssertEqual(Array(preview.entries[1].output.unicodeScalars.map(\.value)), [0x65, 0x301])
        XCTAssertEqual(Set(preview.entries).count, 4)
    }

    func testScalarLimitsUseScalarsNotGraphemesOrUTF16() {
        let supplementary = String(repeating: "𠀀", count: 256)
        XCTAssertTrue(parse("a\t\(supplementary)").canApply)
        XCTAssertEqual(parse("a\t\(supplementary)𠀀").rowErrors.first?.issue, .outputTooLong)
        let combining = "a" + String(repeating: "\u{301}", count: 255)
        XCTAssertEqual(combining.count, 1)
        XCTAssertTrue(parse("\(combining)\tx", exactReadings: true).canApply)
        XCTAssertEqual(parse("\(combining)\u{301}\tx", exactReadings: true).rowErrors.first?.issue, .readingTooLong)
    }

    func testControlCharactersAndBareCRAreRejected() {
        for control in ["\0", "\r", "\u{0085}", "\u{2028}", "\u{2029}"] {
            XCTAssertEqual(parse("a\tx\(control)y").rowErrors.first?.issue, .forbiddenCharacter)
        }
        XCTAssertEqual(parse("a\tb\r").rowErrors.first?.issue, .forbiddenCharacter)
        XCTAssertEqual(parse("a\tb\textra\tcolumn").rowErrors.first?.issue, .columnCount)
    }

    func testInjectedModeAndNormalizerAreUsedWithoutInventedSchemes() {
        XCTAssertEqual(parse("a\tb", mode: "unregistered").fileIssues, [.unsupportedMode])
        XCTAssertEqual(parse("reject\tb").rowErrors.first?.issue, .unsupportedReading)
        let expanding = CustomInputDictionaryRules(isSupportedMode: { _ in true }, normalizeReading: { _, _ in String(repeating: "x", count: 257) })
        let preview = CustomInputDictionaryParser.preview(data: Data("a\tb".utf8), modeID: "test", baseRevision: UUID(),
                                                         existingEntryCount: 0, rules: expanding)
        XCTAssertEqual(preview.rowErrors.first?.issue, .readingTooLong)
        let forbidden = CustomInputDictionaryRules(isSupportedMode: { _ in true }, normalizeReading: { _, _ in "a\tb" })
        XCTAssertEqual(forbidden.validate(reading: "a", output: "b", modeID: "test"), .failure(.forbiddenCharacter))
    }

    func testEntryLineLimitIncludesDuplicatesAndInvalidRows() {
        let atLimit = String(repeating: "a\tb\n", count: CustomInputDictionaryLimits.entryLinesPerImport)
        let good = parse(atLimit)
        XCTAssertTrue(good.canApply)
        XCTAssertEqual(good.entries.count, 1)
        XCTAssertEqual(good.duplicateRowCount, 9999)
        XCTAssertEqual(parse(atLimit + "a\tb").fileIssues, [.tooManyEntryLines])
        XCTAssertTrue(parse("# ignored\n\n" + atLimit).canApply)
        let bad = parse(String(repeating: "invalid\n", count: 10001))
        XCTAssertTrue(bad.fileIssues.contains(.tooManyEntryLines))
        XCTAssertEqual(bad.invalidRowCount, 10000)
    }

    func testTotalLimitCountsUniqueEntriesAndIncludesDisabledCollections() {
        XCTAssertTrue(parse("a\tb\na\tb", existing: 49999).canApply)
        XCTAssertEqual(parse("a\tb\na\tc", existing: 49999).fileIssues, [.tooManyTotalEntries])
        XCTAssertEqual(parse("a\tb", existing: 50000).fileIssues, [.tooManyTotalEntries])
        XCTAssertEqual(parse("# comment only\n\n").fileIssues, [.noEntries])
    }

    func testPreviewAndCancelHaveNoFilesystemEffects() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        XCTAssertEqual(try store.snapshot(), .empty)
        let preview = try store.preview(data: Data("a\tb".utf8), modeID: "test")
        XCTAssertTrue(preview.canApply)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
        XCTAssertEqual(try CustomInputDictionarySnapshotReader(directory: path).read(), .empty)
        // Cancel is simply discarding the value: no store call, no writes.
    }

    func testImportPersistenceIndependentCollectionsAndUndoAfterRestart() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        let first = try store.apply(store.preview(data: Data("a\tfirst".utf8), modeID: "test"), name: "First")
        let second = try store.apply(store.preview(data: Data("a\tsecond".utf8), modeID: "test"), name: "Second")
        XCTAssertEqual(second.collections.count, 2)
        XCTAssertEqual(second.collections[0], first.collections[0])
        let reopened = CustomInputDictionaryStore(directory: path, rules: rules)
        XCTAssertEqual(try reopened.snapshot(), second)
        let undone = try reopened.undoLastImport(expectedRevision: second.revision)
        XCTAssertEqual(undone.collections, first.collections)
        XCTAssertNotEqual(undone.revision, first.revision)
        assertStoreError(.noImportToUndo) { try reopened.undoLastImport(expectedRevision: undone.revision) }
    }

    func testRepeatedPairAcrossCollectionsIsNotCombinedOrReweightedInStorage() throws {
        let store = CustomInputDictionaryStore(directory: directory(), rules: rules)
        let first = try store.apply(store.preview(data: Data("a\tx\t1".utf8), modeID: "test"), name: "First")
        let secondPreview = try store.preview(data: Data("a\tx\t9\na\tx\t3\na\tx\t3".utf8), modeID: "test")
        XCTAssertEqual(secondPreview.combinedCount, 1)
        XCTAssertEqual(secondPreview.duplicateRowCount, 1)
        let second = try store.apply(secondPreview, name: "Second")
        XCTAssertEqual(second.collections[0], first.collections[0])
        XCTAssertEqual(second.collections.map { $0.entries[0].weight }, [1, 9])
        // Overlay deduplication is deliberately separate from persistence.
    }

    func testApplyRevalidatesWithCurrentInjectedRules() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        let foreignPreview = CustomInputDictionaryParser.preview(data: Data("A\tx".utf8), modeID: "test",
            baseRevision: CustomInputDictionarySnapshot.empty.revision, existingEntryCount: 0, rules: identityRules)
        XCTAssertTrue(foreignPreview.canApply)
        assertStoreError(.invalidPreview) { try store.apply(foreignPreview, name: "Changed rules") }
        XCTAssertEqual(try store.snapshot(), .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.appendingPathComponent(CustomInputDictionaryStore.filename).path))
    }

    func testStalePreviewsAcrossStoresCannotOverwriteNewerData() throws {
        let path = directory()
        let one = CustomInputDictionaryStore(directory: path, rules: rules)
        let two = CustomInputDictionaryStore(directory: path, rules: rules)
        let p1 = try one.preview(data: Data("a\tone".utf8), modeID: "test")
        let p2 = try two.preview(data: Data("a\ttwo".utf8), modeID: "test")
        let accepted = try one.apply(p1, name: "One")
        let bytesBefore = try Data(contentsOf: path.appendingPathComponent(CustomInputDictionaryStore.filename))
        assertStoreError(.revisionConflict(expected: p2.baseRevision, actual: accepted.revision)) { try two.apply(p2, name: "Two") }
        XCTAssertEqual(try two.snapshot(), accepted)
        XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent(CustomInputDictionaryStore.filename)), bytesBefore)
    }

    func testInvalidApplyAndManualValidationDoNotMutatePriorSnapshot() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        let good = try store.apply(store.preview(data: Data("a\tb".utf8), modeID: "test"), name: "One")
        let id = try XCTUnwrap(good.collections.first?.id)
        let bytes = try Data(contentsOf: path.appendingPathComponent(CustomInputDictionaryStore.filename))
        let invalid = try store.preview(data: Data("a\tb\ninvalid".utf8), modeID: "test")
        assertStoreError(.invalidPreview) { try store.apply(invalid, name: "No") }
        assertStoreError(.invalidName) { try store.renameCollection(id: id, name: "", expectedRevision: good.revision) }
        for (reading, output, weight, issue) in [("", "x", 100, CustomInputDictionaryValidationIssue.emptyReading),
            ("a", "", 100, .emptyOutput), ("reject", "x", 100, .unsupportedReading),
            ("a", "x\t", 100, .forbiddenCharacter), ("a", "x", 10001, .invalidWeight),
            ("#reserved", "x", 100, .unsupportedReading)] {
            assertStoreError(.validation(issue)) {
                try store.addEntry(collectionID: id, reading: reading, output: output, weight: weight, expectedRevision: good.revision)
            }
        }
        XCTAssertEqual(try store.snapshot(), good)
        XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent(CustomInputDictionaryStore.filename)), bytes)
    }

    func testUndoConflictsAfterNewerManualEditAndPreservesIt() throws {
        let store = CustomInputDictionaryStore(directory: directory(), rules: rules)
        let imported = try store.apply(store.preview(data: Data("a\tb".utf8), modeID: "test"), name: "One")
        let id = try XCTUnwrap(imported.collections.first?.id)
        let edited = try store.addEntry(collectionID: id, reading: "c", output: "d", expectedRevision: imported.revision)
        assertStoreError(.revisionConflict(expected: imported.revision, actual: edited.revision)) {
            try store.undoLastImport(expectedRevision: imported.revision)
        }
        assertStoreError(.undoConflict(actual: edited.revision)) { try store.undoLastImport(expectedRevision: edited.revision) }
        XCTAssertEqual(try store.snapshot(), edited)
    }

    func testEnableDisableRemoveAndImmutableAppSnapshot() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        let imported = try store.apply(store.preview(data: Data("a\tb".utf8), modeID: "test"), name: "One")
        let reader = CustomInputDictionarySnapshotReader(directory: path)
        let held = try reader.read()
        let id = try XCTUnwrap(imported.collections.first?.id)
        let disabled = try store.setEnabled(id: id, enabled: false, expectedRevision: imported.revision)
        XCTAssertTrue(try reader.read().enabledCollections.isEmpty)
        XCTAssertEqual(disabled.totalEntryCount, 1)
        XCTAssertEqual(held.enabledCollections.count, 1) // held app/compiler value remains intact
        assertStoreError(.undoConflict(actual: disabled.revision)) { try store.undoLastImport(expectedRevision: disabled.revision) }
        let enabled = try store.setEnabled(id: id, enabled: true, expectedRevision: disabled.revision)
        XCTAssertEqual(enabled.enabledCollections.count, 1)
        let removed = try store.removeCollection(id: id, expectedRevision: enabled.revision)
        XCTAssertTrue(removed.collections.isEmpty)
        XCTAssertEqual(try reader.read(), removed)
    }

    func testManualCRUDNormalizationExactOutputDuplicatesAndStaleIndexProtection() throws {
        let store = CustomInputDictionaryStore(directory: directory(), rules: rules)
        let created = try store.createCollection(name: "Manual", modeID: "test", expectedRevision: CustomInputDictionarySnapshot.empty.revision)
        let id = try XCTUnwrap(created.collections.first?.id)
        let added = try store.addEntry(collectionID: id, reading: "A", output: "é", expectedRevision: created.revision)
        XCTAssertEqual(added.collections[0].entries[0].reading, "a")
        assertStoreError(.duplicateEntry) { try store.addEntry(collectionID: id, reading: "a", output: "é", weight: 1, expectedRevision: added.revision) }
        let distinct = try store.addEntry(collectionID: id, reading: "a", output: "e\u{301}", expectedRevision: added.revision)
        XCTAssertEqual(distinct.totalEntryCount, 2)
        assertStoreError(.revisionConflict(expected: added.revision, actual: distinct.revision)) {
            try store.deleteEntry(collectionID: id, index: 0, expectedRevision: added.revision)
        }
        assertStoreError(.duplicateEntry) {
            try store.editEntry(collectionID: id, index: 1, reading: "a", output: "é", expectedRevision: distinct.revision)
        }
        let edited = try store.editEntry(collectionID: id, index: 0, reading: "B", output: "👩🏽‍💻", weight: 10000, expectedRevision: distinct.revision)
        XCTAssertEqual(edited.collections[0].entries[0].reading, "b")
        XCTAssertEqual(edited.collections[0].entries[0].weight, 10000)
        let deleted = try store.deleteEntry(collectionID: id, index: 1, expectedRevision: edited.revision)
        XCTAssertEqual(deleted.totalEntryCount, 1)
        assertStoreError(.entryNotFound) { try store.deleteEntry(collectionID: id, index: -1, expectedRevision: deleted.revision) }
        assertStoreError(.collectionNotFound) { try store.removeCollection(id: UUID(), expectedRevision: deleted.revision) }
        assertStoreError(.validation(.unsupportedMode)) { try store.createCollection(name: "Wrong", modeID: "unknown", expectedRevision: deleted.revision) }
    }

    func testExportRoundTripPreservesExactScalarsAndResolvedWeights() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: identityRules)
        let original = "a\té\na\te\u{301}\t0\nb\t𠀀👩\u{200D}💻\t10000\n\u{FEFF}c\t x \n"
        let imported = try store.apply(store.preview(data: Data(original.utf8), modeID: "test"), name: "Exact")
        let collection = try XCTUnwrap(imported.collections.first)
        for weights in [CustomInputDictionaryExport.Weights.omitDefault, .explicit] {
            let exported = try store.exportCollection(id: collection.id, weights: weights)
            let reparsed = CustomInputDictionaryParser.preview(data: exported, modeID: "test", baseRevision: UUID(),
                                                               existingEntryCount: 0, rules: identityRules)
            XCTAssertTrue(reparsed.canApply)
            XCTAssertEqual(reparsed.entries, collection.entries)
            for (a, b) in zip(reparsed.entries, collection.entries) {
                XCTAssertEqual(Data(a.output.utf8), Data(b.output.utf8))
                XCTAssertEqual(Data(a.reading.utf8), Data(b.reading.utf8))
            }
        }
        let explicit = String(decoding: try store.exportCollection(id: collection.id, weights: .explicit), as: UTF8.self)
        XCTAssertTrue(explicit.contains("a\té\t100\n"))
    }

    func testExportPartsRespectBothImportBoundsAndPreserveAllEntries() throws {
        let smallEntries = (0..<10001).map { CustomInputDictionaryEntry(reading: "r\($0)", output: "x") }
        let longOutput = String(repeating: "𠀀", count: 256)
        let largeEntries = (0..<1200).map { CustomInputDictionaryEntry(reading: "r\($0)", output: longOutput, weight: $0) }
        for entries in [smallEntries, largeEntries] {
            let collection = CustomInputDictionaryCollection(name: "Parts", modeID: "test", entries: entries)
            let parts = try CustomInputDictionaryExport.tsvParts(collection)
            XCTAssertEqual(parts.count, 2)
            var restored: [CustomInputDictionaryEntry] = []
            for part in parts {
                XCTAssertLessThanOrEqual(part.count, CustomInputDictionaryLimits.importBytes)
                let preview = CustomInputDictionaryParser.preview(data: part, modeID: "test", baseRevision: UUID(), existingEntryCount: restored.count, rules: rules)
                XCTAssertTrue(preview.canApply)
                XCTAssertLessThanOrEqual(preview.entryLineCount, CustomInputDictionaryLimits.entryLinesPerImport)
                restored += preview.entries
            }
            XCTAssertEqual(restored, entries)
        }
    }

    func testLeadingBOMInFirstReadingIsNotLostOnExport() throws {
        let collection = CustomInputDictionaryCollection(name: "BOM", modeID: "test", entries: [.init(reading: "\u{FEFF}a", output: "x")])
        let exported = try CustomInputDictionaryExport.tsv(collection)
        let reparsed = CustomInputDictionaryParser.preview(data: exported, modeID: "test", baseRevision: UUID(), existingEntryCount: 0, rules: identityRules)
        XCTAssertEqual(reparsed.entries, collection.entries)
    }

    func testCorruptSnapshotIsNeverRepairedOrOverwrittenAndHeldSnapshotSurvives() throws {
        let path = directory()
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        let good = try store.apply(store.preview(data: Data("a\tb".utf8), modeID: "test"), name: "One")
        let reader = CustomInputDictionarySnapshotReader(directory: path)
        let held = try reader.read()
        let url = path.appendingPathComponent(CustomInputDictionaryStore.filename)
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: url, options: .atomic)
        assertStoreError(.corruptSnapshot) { try reader.read() }
        assertStoreError(.corruptSnapshot) { try store.setEnabled(id: good.collections[0].id, enabled: false, expectedRevision: good.revision) }
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        XCTAssertEqual(held, good)
    }

    func testCollectionLimitBoundsEmptyMetadataWithoutReducingEntryLimits() throws {
        let path = directory()
        let collections = (0..<CustomInputDictionaryLimits.totalCollections).map {
            CustomInputDictionaryCollection(name: "Empty \($0)", modeID: "test", entries: [])
        }
        let state = CustomInputDictionarySnapshot(revision: UUID(), collections: collections)
        let snapshotObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        let document: [String: Any] = ["schemaVersion": 1, "snapshot": snapshotObject]
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let url = path.appendingPathComponent(CustomInputDictionaryStore.filename)
        let original = try JSONSerialization.data(withJSONObject: document)
        try original.write(to: url, options: .atomic)
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        XCTAssertEqual(try store.snapshot(), state)
        XCTAssertEqual(try store.preview(data: Data("a\tx".utf8), modeID: "test").fileIssues, [.tooManyCollections])
        assertStoreError(.collectionLimit) { try store.createCollection(name: "One more", modeID: "test", expectedRevision: state.revision) }
        XCTAssertEqual(try Data(contentsOf: url), original)
        // Existing collections can still grow to the full authorized entry total.
        let grown = try store.addEntry(collectionID: collections[0].id, reading: "a", output: "x", expectedRevision: state.revision)
        XCTAssertEqual(grown.totalEntryCount, 1)
        XCTAssertEqual(grown.collections.count, CustomInputDictionaryLimits.totalCollections)
    }

    func testSnapshotByteBoundDoesNotReduceAuthorizedEntryOrScalarLimits() throws {
        // JSONEncoder emits non-BMP UTF-8; escaped BMP scalars cost at most 6 bytes.
        let worstFieldsAndEntryMetadata = CustomInputDictionaryLimits.totalEntries *
            (CustomInputDictionaryLimits.fieldScalars * 2 * 6 + 128)
        let worstCollections = CustomInputDictionaryLimits.totalCollections *
            (CustomInputDictionaryLimits.fieldScalars * 2 * 6 + 256)
        XCTAssertGreaterThan(CustomInputDictionaryStore.maximumSnapshotBytes, worstFieldsAndEntryMetadata + worstCollections + 65536)
        XCTAssertEqual(CustomInputDictionaryStore.maximumSnapshotBytes, 192 * 1024 * 1024)
        let escaped = String(repeating: "\u{0001}", count: 256)
        let supplementary = String(repeating: "𠀀", count: 256)
        for field in [escaped, supplementary] {
            let encoded = try JSONEncoder().encode(CustomInputDictionaryEntry(reading: field, output: field, weight: 10000))
            XCTAssertLessThanOrEqual(encoded.count, 2 * 256 * 6 + 128)
        }
    }

    func testFilePreviewUsesByteBoundWithoutWritingStore() throws {
        let path = directory()
        let source = path.deletingLastPathComponent().appendingPathComponent("source.tsv")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("\u{FEFF}a\tb\r\n".utf8).write(to: source)
        let store = CustomInputDictionaryStore(directory: path, rules: rules)
        XCTAssertTrue(try store.preview(fileURL: source, modeID: "test").canApply)
        try Data(count: CustomInputDictionaryLimits.importBytes + 1).write(to: source)
        XCTAssertEqual(try store.preview(fileURL: source, modeID: "test").fileIssues, [.tooLarge])
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testStoreTotalLimitIsEnforcedForManualAddAndImportWithoutTrimming() throws {
        let store = CustomInputDictionaryStore(directory: directory(), rules: rules)
        var state = CustomInputDictionarySnapshot.empty
        for batch in 0..<5 {
            let text = (0..<10000).map { "r\(batch)-\($0)\tx" }.joined(separator: "\n")
            let preview = try store.preview(data: Data(text.utf8), modeID: "test")
            XCTAssertTrue(preview.canApply)
            state = try store.apply(preview, name: "Batch \(batch)", enabled: false)
        }
        XCTAssertEqual(state.totalEntryCount, 50000)
        let full = state
        let id = try XCTUnwrap(full.collections.first?.id)
        assertStoreError(.totalEntryLimit) { try store.addEntry(collectionID: id, reading: "new", output: "x", expectedRevision: full.revision) }
        let rejected = try store.preview(data: Data("new\tx".utf8), modeID: "test")
        XCTAssertEqual(rejected.fileIssues, [.tooManyTotalEntries])
        assertStoreError(.invalidPreview) { try store.apply(rejected, name: "Extra") }
        XCTAssertEqual(try store.snapshot(), full)
    }
}
