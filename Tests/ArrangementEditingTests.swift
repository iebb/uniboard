import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class ArrangementEditingTests: XCTestCase {
    func testHistoryRecordsOnlyNewestSuccessfulChangeAndHasNoRedo() {
        var history = ArrangementHistory<Int>()
        history.record(before: 0, after: 1, succeeded: false)
        XCTAssertNil(history.step)
        history.record(before: 0, after: 1, succeeded: true)
        history.record(before: 1, after: 1, succeeded: true)
        history.record(before: 1, after: 2, succeeded: false)
        XCTAssertEqual(history.step?.before, 0)
        history.record(before: 1, after: 2, succeeded: true)
        XCTAssertEqual(history.step?.before, 1)
        XCTAssertEqual(history.step?.expectedAfter, 2)
        history.invalidate()
        XCTAssertNil(history.step)
    }

    func testRowScopeIsIndependentAndClampsInvalidRowsToAllRows() {
        XCTAssertNil(ArrangementRowScope().clamped(rowCount: 4).row)
        XCTAssertEqual(ArrangementRowScope(row: 2).clamped(rowCount: 3).row, 2)
        XCTAssertNil(ArrangementRowScope(row: 2).clamped(rowCount: 2).row)
        XCTAssertNil(ArrangementRowScope(row: -1).clamped(rowCount: 3).row)
        XCTAssertNil(ArrangementRowScope(row: 0).clamped(rowCount: 0).row)
    }

    func testTransitionTruthTableOnlyReportsMergedSplitFlips() {
        let states: [KeyboardMergedSymbolsPolicy.Eligibility] = [.merged, .missingDigits, .insufficientSpace]
        for before in states {
            for after in states {
                let message = KeyboardMergedSymbolsPolicy.transitionMessage(from: before, to: after)
                XCTAssertEqual(message != nil, before.isEligible != after.isEligible)
                if let message {
                    XCTAssertTrue(message.hasSuffix("Your key actions are unchanged."))
                    if after == .missingDigits { XCTAssertTrue(message.contains("no longer types all ten digits")) }
                    if after == .insufficientSpace { XCTAssertTrue(message.contains("no longer fit")) }
                }
            }
        }
    }

    func testEligibilityReasonUsesRemappedTapAndDigitsOutrankGeometry() throws {
        let stock = KeyboardKeySettings.Snapshot.defaults
        let remapped = try XCTUnwrap(stock.updating(["one"], for: "digit.1", gesture: .tap))
        XCTAssertEqual(KeyboardMergedSymbolsPolicy.eligibility(settings: stock, alphabet: .english, availableWidth: 386, isPad: false), .merged)
        XCTAssertEqual(KeyboardMergedSymbolsPolicy.eligibility(settings: remapped, alphabet: .english, availableWidth: 386, isPad: false), .missingDigits)
        XCTAssertEqual(KeyboardMergedSymbolsPolicy.eligibility(settings: remapped, alphabet: .english, availableWidth: 1, isPad: false), .missingDigits)
        XCTAssertEqual(KeyboardMergedSymbolsPolicy.eligibility(settings: stock, alphabet: .english, availableWidth: 1, isPad: false), .insufficientSpace)
        for width: CGFloat in [1, 320, 386, 650, .infinity, .nan] {
            for settings in [stock, remapped] {
                let reason = KeyboardMergedSymbolsPolicy.eligibility(settings: settings, alphabet: .english, availableWidth: width, isPad: false)
                XCTAssertEqual(reason.isEligible, KeyboardMergedSymbolsPolicy.isEligible(settings: settings, alphabet: .english, availableWidth: width, isPad: false))
            }
        }
    }
}

@MainActor
final class ArrangementStoreTests: XCTestCase {
    private struct Fixture {
        let directory: URL
        let defaults: UserDefaults
        let pages: SymbolPageSettings
        let store: SymbolBoardStore
    }
    private func fixture(writer: SymbolPageSettings.AtomicWriter? = nil,
                         localWriter: ((Data, UserDefaults) -> Bool)? = nil,
                         favorites: Bool = false) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Arrangement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "Arrangement-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let pages: SymbolPageSettings
        if let writer { pages = .init(containerURL: { directory }, writeAtomically: writer) }
        else { pages = .init(containerURL: { directory }) }
        let persist: ((Data) -> Bool)? = localWriter.map { writer in { writer($0, defaults) } }
        let store = SymbolBoardStore(defaults: defaults, persist: persist,
            sync: favorites ? FavoriteSync(container: { directory }) : nil,
            pages: pages, sharedWriteAllowed: favorites)
        return Fixture(directory: directory, defaults: defaults, pages: pages, store: store)
    }
    private func page(_ store: SymbolBoardStore) throws -> SymbolBoard {
        let id = try XCTUnwrap(store.createBoard(named: "Exact"))
        let key = try XCTUnwrap(store.add(text: "e\u{301}", to: id))
        XCTAssertNotNil(store.add(text: "é", to: id))
        XCTAssertTrue(store.setLayers(boardID: id, keyID: key, variants: ["👩🏽‍💻"], up: ["\u{200D}"], down: ["\u{FE0F}"]))
        return try XCTUnwrap(store.boards.first { $0.id == id })
    }
    private func rows(_ page: SymbolBoard, alignment: KeyboardRowAlignment = .center) -> [SymbolBoard.Row] {
        [.init(alignment: alignment, cells: [.halfGap, .key(page.keys[0]), .gap, .key(page.keys[1])])]
    }

    func testUndoRestoresNilLegacyExactKeysIDsAndAllLayers() throws {
        let f = try fixture(), before = try page(f.store)
        XCTAssertTrue(before.isLegacy); XCTAssertNil(before.layout)
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before)))
        XCTAssertEqual(f.store.arrangementUndoBoardID, before.id)
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .restored)
        let after = try XCTUnwrap(f.store.boards.first { $0.id == before.id })
        XCTAssertEqual(after, before); XCTAssertTrue(after.isLegacy); XCTAssertNil(after.layout)
        XCTAssertEqual(Array(after.keys[0].text.utf8), Array("e\u{301}".utf8))
        XCTAssertEqual(after.keys.map(\.id), before.keys.map(\.id))
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .invalidated)
    }

    func testRestoreKeepsLegacyLayoutThenMixedExplicitRowsAndRemovedKeyActions() throws {
        let f = try fixture(), original = try page(f.store)
        XCTAssertTrue(f.store.setLayout(boardID: original.id, layout: SymbolPageLayout("hkk")))
        let legacy = try XCTUnwrap(f.store.boards.first { $0.id == original.id })
        let mixed: [SymbolBoard.Row] = [
            .init(alignment: .center, cells: [.key(original.keys[0]), .halfGap]),
            .init(alignment: .spaced, cells: [.gap, .key(original.keys[1])])
        ]
        XCTAssertTrue(f.store.setExplicitRows(boardID: original.id, rows: mixed))
        XCTAssertEqual(f.store.undoArrangement(boardID: original.id), .restored)
        XCTAssertEqual(f.store.boards.first { $0.id == original.id }, legacy)
        XCTAssertTrue(f.store.setExplicitRows(boardID: original.id, rows: mixed))
        XCTAssertTrue(f.store.setExplicitRows(boardID: original.id,
            rows: SymbolBoard.Row.legacy(keys: original.keys, layout: nil, alignment: .left)))
        XCTAssertEqual(f.store.undoArrangement(boardID: original.id), .restored)
        XCTAssertEqual(f.store.boards.first { $0.id == original.id }?.explicitRows, mixed)
        XCTAssertTrue(f.store.removeKey(boardID: original.id, keyID: original.keys[0].id, recordingArrangement: true))
        XCTAssertEqual(f.store.undoArrangement(boardID: original.id), .restored)
        XCTAssertEqual(f.store.boards.first { $0.id == original.id }?.explicitRows, mixed)
    }

    func testMissingKnownSharedFileAlsoRefusesANewDirectEdit() throws {
        let f = try fixture(), before = try page(f.store)
        let url = f.directory.appendingPathComponent(SymbolPageSettings.filename)
        try FileManager.default.removeItem(at: url)
        XCTAssertFalse(f.store.setExplicitRows(boardID: before.id, rows: rows(before)))
        XCTAssertNil(f.store.arrangementUndoBoardID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLocalOnlyRestoreReloadsAuthoritativeBytesAndFailureHasNoHistory() throws {
        let suite = "Arrangement-local-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var fail = false
        let store = SymbolBoardStore(defaults: defaults, persist: { data in
            guard !fail else { return false }
            defaults.set(data, forKey: SymbolBoardStore.storageKey); return true
        })
        let before = try page(store)
        fail = true
        XCTAssertFalse(store.setExplicitRows(boardID: before.id, rows: rows(before)))
        XCTAssertNil(store.arrangementUndoBoardID)
        fail = false
        XCTAssertTrue(store.setExplicitRows(boardID: before.id, rows: rows(before)))
        let later = Data("unreadable later state".utf8)
        defaults.set(later, forKey: SymbolBoardStore.storageKey)
        XCTAssertEqual(store.undoArrangement(boardID: before.id), .invalidated)
        XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), later)
    }

    func testNewestSuccessfulEditWinsNoopAndFailedEditsLeaveHistory() throws {
        var fail = false
        let f = try fixture(writer: { data, url in
            if fail { throw CocoaError(.fileWriteUnknown) }
            try data.write(to: url, options: .atomic)
        })
        let before = try page(f.store)
        let first = rows(before)
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: first))
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before, alignment: .right)))
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before, alignment: .right)))
        fail = true
        XCTAssertFalse(f.store.setExplicitRows(boardID: before.id, rows: rows(before, alignment: .left)))
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .failed)
        XCTAssertEqual(f.store.arrangementUndoBoardID, before.id)
        fail = false
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .restored)
        XCTAssertEqual(f.store.boards.first { $0.id == before.id }?.explicitRows, first)
    }

    func testSharedRestoreIsSuccessEvenWhenLocalCopyFails() throws {
        var fail = false
        let f = try fixture(localWriter: { data, defaults in
            if fail { return false }
            defaults.set(data, forKey: SymbolBoardStore.storageKey); return true
        })
        let before = try page(f.store)
        fail = true
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before)))
        XCTAssertTrue(f.store.localCopyWarning)
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .restored)
        XCTAssertTrue(f.store.localCopyWarning); XCTAssertNotNil(f.store.localCopyWarningID)
        XCTAssertEqual(f.pages.load()?.pages.first { $0.id == before.id }, before)
    }

    func testRestoreMergesFreshUnrelatedPagesAndStarChoice() throws {
        let f = try fixture(), before = try page(f.store)
        let otherID = try XCTUnwrap(f.store.createBoard(named: "Other"))
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before)))
        var fresh = try XCTUnwrap(f.pages.load())
        let index = try XCTUnwrap(fresh.pages.firstIndex { $0.id == otherID })
        fresh.pages[index].name = "Fresh name"; fresh.starPageID = otherID
        XCTAssertTrue(f.pages.save(fresh))
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .restored)
        XCTAssertEqual(f.pages.load()?.starPageID, otherID)
        XCTAssertEqual(f.pages.load()?.pages.first { $0.id == otherID }?.name, "Fresh name")
        XCTAssertEqual(f.pages.load()?.pages.first { $0.id == before.id }, before)
    }

    func testUnrelatedKeyContentAndConfigurationEditsInvalidate() throws {
        let f = try fixture(), before = try page(f.store)
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before)))
        XCTAssertTrue(f.store.setVariants(boardID: before.id, keyID: before.keys[0].id, variants: ["changed"]))
        XCTAssertNil(f.store.arrangementUndoBoardID)
        let current = try XCTUnwrap(f.store.boards.first { $0.id == before.id })
        XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(current, alignment: .right)))
        let keys = try XCTUnwrap(KeyboardKeySettings.encode(.defaults))
        try keys.write(to: f.directory.appendingPathComponent(KeyboardKeySettings.filename))
        XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .invalidated)
        XCTAssertEqual(f.store.boards.first { $0.id == before.id }?.keys[0].variants, ["changed"])
    }

    func testCorruptAndMissingSharedStateNeverOverwrittenByUndo() throws {
        for missing in [false, true] {
            let f = try fixture(), before = try page(f.store)
            XCTAssertTrue(f.store.setExplicitRows(boardID: before.id, rows: rows(before)))
            let url = f.directory.appendingPathComponent(SymbolPageSettings.filename)
            if missing { try FileManager.default.removeItem(at: url) }
            else { try Data("broken".utf8).write(to: url) }
            XCTAssertEqual(f.store.undoArrangement(boardID: before.id), .invalidated)
            if missing { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
            else { XCTAssertEqual(try Data(contentsOf: url), Data("broken".utf8)) }
        }
    }

    func testConditionalStoreRejectsStaleTargetAndBusyWriterLock() throws {
        let f = try fixture(), before = try page(f.store)
        let revision = try XCTUnwrap(f.pages.arrangementRevision())
        var changed = before; changed.name = "Changed elsewhere"
        var current = try XCTUnwrap(f.pages.load())
        current.pages[current.pages.firstIndex { $0.id == before.id }!] = changed
        XCTAssertTrue(f.pages.save(current))
        XCTAssertNil(f.pages.replaceArrangement(expected: before, replacement: before, revision: revision))
        let location = SharedConfigurationLocation(root: { f.directory })
        try location.withWriterLock {
            XCTAssertNil(f.pages.replaceArrangement(expected: changed, replacement: before, revision: revision))
        }
        XCTAssertEqual(f.pages.load()?.pages.first { $0.id == before.id }, changed)
    }

    func testGenerationChangeRejectsEvenByteIdenticalPage() throws {
        let f = try fixture(), before = try page(f.store)
        var directory = f.directory
        let settings = SymbolPageSettings(containerURL: { directory })
        let revision = try XCTUnwrap(settings.arrangementRevision())
        let next = f.directory.appendingPathComponent("replacement")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        try Data(contentsOf: f.directory.appendingPathComponent(SymbolPageSettings.filename)).write(to: next.appendingPathComponent(SymbolPageSettings.filename))
        directory = next
        XCTAssertNil(settings.replaceArrangement(expected: before, replacement: before, revision: revision))
    }

    func testFavoritesOrderOnlyChangeCannotClaimPublicationWhenLocalWriteFails() throws {
        var fail = false
        let f = try fixture(localWriter: { data, defaults in
            guard !fail else { return false }
            defaults.set(data, forKey: SymbolBoardStore.storageKey); return true
        }, favorites: true)
        let id = SymbolBoardStore.favoritesID
        XCTAssertNotNil(f.store.add(text: "a", to: id)); XCTAssertNotNil(f.store.add(text: "b", to: id))
        XCTAssertTrue(f.store.setLayout(boardID: id, layout: SymbolPageLayout("kk")))
        let before = f.store.favoriteTexts
        let bytes = try Data(contentsOf: f.directory.appendingPathComponent(SymbolPageSettings.filename))
        fail = true
        XCTAssertFalse(f.store.setLayout(boardID: id, layout: SymbolPageLayout("kk"), keyMove: .init(from: 0, to: 1)))
        XCTAssertEqual(f.store.favoriteTexts, before)
        XCTAssertEqual(try Data(contentsOf: f.directory.appendingPathComponent(SymbolPageSettings.filename)), bytes)
    }

    func testFavoritesUndoUsesRealContentAndNeverCreatesExplicitRows() throws {
        let f = try fixture(favorites: true), id = SymbolBoardStore.favoritesID
        XCTAssertNotNil(f.store.add(text: "e\u{301}", to: id))
        XCTAssertNotNil(f.store.add(text: "é", to: id))
        let before = try XCTUnwrap(f.store.boards.first { $0.id == id })
        XCTAssertTrue(f.store.setLayout(boardID: id, layout: SymbolPageLayout("kk"), keyMove: .init(from: 0, to: 1)))
        XCTAssertEqual(f.store.undoArrangement(boardID: id), .restored)
        XCTAssertEqual(f.store.boards.first { $0.id == id }, before)
        XCTAssertTrue(f.store.boards.first { $0.id == id }?.isLegacy == true)
        XCTAssertTrue(f.pages.load()?.pages.first { $0.id == id }?.keys.isEmpty == true)
        XCTAssertTrue(f.store.setLayout(boardID: id, layout: SymbolPageLayout("hkk")))
        let remote = FavoriteSync(container: { f.directory })
        _ = try remote.synchronize(base: f.store.favoriteTexts, local: f.store.favoriteTexts + ["new"], canWrite: true)
        XCTAssertEqual(f.store.undoArrangement(boardID: id), .invalidated)
        XCTAssertTrue(f.store.favoriteTexts.contains("new"))
    }
}
