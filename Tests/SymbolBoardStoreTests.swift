import Foundation
import Combine
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

@MainActor
final class SymbolBoardStoreTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "Uniboard.SymbolBoards.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }
    private func payload(_ defaults: UserDefaults) throws -> [String: Any] {
        let data = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func replace(_ value: [String: Any], in defaults: UserDefaults) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: value)
        defaults.set(data, forKey: SymbolBoardStore.storageKey)
        return data
    }
    private func sharedPages() throws -> (settings: SymbolPageSettings, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SymbolPages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (SymbolPageSettings(containerURL: { directory }), directory)
    }

    func testAppConfiguresPagesThatTheKeyboardReadsButCannotEdit() throws {
        let pages = try sharedPages().settings
        try withDefaults { appDefaults in
            try withDefaults { keyboardDefaults in
                let app = SymbolBoardStore(defaults: appDefaults, pages: pages, configuresPages: true)
                let id = try XCTUnwrap(app.createBoard(named: "Math"))
                XCTAssertNotNil(app.add(text: "∑", to: id))
                XCTAssertTrue(app.setPreferredStarBoard(id))
                XCTAssertNotNil(app.add(text: "☃", to: SymbolBoardStore.favoritesID))
                let shared = try XCTUnwrap(pages.load())
                XCTAssertEqual(shared.pages.map(\.name), ["Symbols", "Favorites", "Math"])
                XCTAssertEqual(shared.starPageID, id)
                XCTAssertTrue(shared.pages.first { $0.id == SymbolBoardStore.favoritesID }?.keys.isEmpty == true,
                              "Favorites keys sync separately")

                let keyboard = SymbolBoardStore(defaults: keyboardDefaults, pages: pages, configuresPages: false)
                XCTAssertEqual(keyboard.boards.map(\.name), ["Symbols", "Favorites", "Math"])
                XCTAssertEqual(keyboard.preferredStarBoardID, id)
                XCTAssertEqual(keyboard.key(boardID: id, keyID: try XCTUnwrap(keyboard.boards.last?.keys.first?.id))?.text, "∑")
                XCTAssertNil(keyboard.createBoard(named: "Local"), "Pages are configured in the app")
                XCTAssertNil(keyboard.add(text: "π", to: id))
                XCTAssertFalse(keyboard.renameBoard(id, to: "Other"))
                XCTAssertFalse(keyboard.setPreferredStarBoard(SymbolBoardStore.favoritesID))
                XCTAssertTrue(keyboard.selectBoard(id), "The open page stays local to the keyboard")
                XCTAssertNotNil(keyboard.add(text: "★", to: SymbolBoardStore.favoritesID), "Save goes to Favorites")
                XCTAssertEqual(try XCTUnwrap(pages.load()).pages.map(\.name), ["Symbols", "Favorites", "Math"])

                XCTAssertTrue(app.moveBoards(fromOffsets: [2], toOffset: 0))
                keyboard.refreshPages()
                XCTAssertEqual(keyboard.boards.map(\.name), ["Math", "Symbols", "Favorites"])
                XCTAssertEqual(keyboard.activeBoardID, id)
                XCTAssertEqual(keyboard.favoriteTexts, ["★"])
            }
        }
    }

    func testPageRowsReachTheKeyboardAndFollowAddedRemovedAndMovedKeys() throws {
        let pages = try sharedPages().settings
        try withDefaults { appDefaults in
            try withDefaults { keyboardDefaults in
                let app = SymbolBoardStore(defaults: appDefaults, pages: pages, configuresPages: true)
                let id = try XCTUnwrap(app.createBoard(named: "Rows"))
                for text in ["a", "b", "c", "d"] { XCTAssertNotNil(app.add(text: text, to: id)) }
                XCTAssertNil(app.boards.last?.layout, "New pages use rows of ten")
                XCTAssertTrue(app.setLayout(boardID: id, layout: SymbolPageLayout("kk/hkk")))
                XCTAssertNotNil(app.add(text: "e", to: id))
                XCTAssertEqual(app.boards.last?.layout, "kk/hkkk", "A new key takes a slot at the end")
                let c = try XCTUnwrap(app.boards.last?.keys[2].id)
                XCTAssertTrue(app.removeKey(boardID: id, keyID: c))
                XCTAssertEqual(app.boards.last?.layout, "kk/hkk", "A removed key's slot goes with it")
                XCTAssertEqual(app.boards.last?.keys.map(\.text), ["a", "b", "d", "e"])
                XCTAssertTrue(app.setLayout(boardID: id, layout: SymbolPageLayout("kk/hkk"), keyMove: .init(from: 3, to: 0)))
                XCTAssertEqual(app.boards.last?.keys.map(\.text), ["e", "a", "b", "d"])
                XCTAssertFalse(app.setLayout(boardID: id, layout: nil, keyMove: .init(from: 0, to: 4)))
                XCTAssertTrue(app.setLayout(boardID: SymbolBoardStore.favoritesID, layout: SymbolPageLayout("hk")))
                XCTAssertEqual(try XCTUnwrap(pages.load()).pages.first { $0.id == SymbolBoardStore.favoritesID }?.layout, "hk",
                               "Favorites keeps its rows in the shared file though its keys sync separately")

                let keyboard = SymbolBoardStore(defaults: keyboardDefaults, pages: pages, configuresPages: false)
                XCTAssertEqual(keyboard.boards.first { $0.id == id }?.layout, "kk/hkk")
                XCTAssertEqual(keyboard.boards.first { $0.id == SymbolBoardStore.favoritesID }?.layout, "hk")
                XCTAssertNotNil(keyboard.add(text: "★", to: SymbolBoardStore.favoritesID), "Saving in the keyboard leaves the rows alone")
                XCTAssertNotNil(keyboard.add(text: "☃", to: SymbolBoardStore.favoritesID))
                XCTAssertEqual(keyboard.boards.first { $0.id == SymbolBoardStore.favoritesID }?.layout, "hk")
                XCTAssertFalse(keyboard.setLayout(boardID: id, layout: nil), "Rows are arranged in the app")

                XCTAssertTrue(app.setLayout(boardID: id, layout: nil))
                keyboard.refreshPages()
                XCTAssertNil(keyboard.boards.first { $0.id == id }?.layout)
            }
        }
    }

    func testAnInvalidSharedPageFileKeepsTheBuiltInPagesAndFavorites() throws {
        let pages = try sharedPages().settings
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults, pages: pages, configuresPages: false)
            XCTAssertNotNil(store.add(text: "☃", to: SymbolBoardStore.favoritesID))
            XCTAssertTrue(store.isFavorite("☃"))
            XCTAssertFalse(store.isFavorite("☃\u{FE0F}"), "Favorites match exact text")
            // A file that decodes but lacks the built-in Symbols page is not adopted.
            XCTAssertTrue(pages.save(.init(pages: [SymbolBoard(id: SymbolBoardStore.favoritesID, name: "Favorites", keys: [])],
                                           starPageID: SymbolBoardStore.favoritesID)))
            store.refreshPages()
            XCTAssertEqual(store.boards.map(\.id), [SymbolBoardStore.stockID, SymbolBoardStore.favoritesID])
            XCTAssertEqual(store.favoriteTexts, ["☃"])
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
        }
    }

    func testCustomPagesExportAndImportAsNewPages() throws {
        try withDefaults { source in
            try withDefaults { target in
                let from = SymbolBoardStore(defaults: source, pages: try sharedPages().settings, configuresPages: true)
                let id = try XCTUnwrap(from.createBoard(named: "Math"))
                for text in ["∑", "∞"] { XCTAssertNotNil(from.add(text: text, to: id)) }
                let sum = try XCTUnwrap(from.boards.last?.keys.first?.id)
                XCTAssertTrue(from.setVariants(boardID: id, keyID: sum, variants: ["∏"]))
                XCTAssertTrue(from.setSwipe(boardID: id, keyID: sum, up: true, choices: ["⅀", "⅀", "Σ"]))
                XCTAssertTrue(from.setSwipe(boardID: id, keyID: sum, up: false, choices: ["∫"]))
                XCTAssertEqual(from.key(boardID: id, keyID: sum)?.up, ["⅀", "Σ"], "Repeats are dropped")
                for bad in [[""], Array(repeating: "x", count: 1).flatMap { _ in (0...16).map { String(UnicodeScalar(0x2200 + $0)!) } }] {
                    XCTAssertFalse(from.setSwipe(boardID: id, keyID: sum, up: true, choices: bad))
                }
                XCTAssertFalse(from.setSwipe(boardID: id, keyID: "missing", up: true, choices: ["x"]))
                XCTAssertFalse(from.setSwipe(boardID: "missing", keyID: sum, up: true, choices: ["x"]))
                let infinity = try XCTUnwrap(from.boards.last?.keys.last?.id)
                XCTAssertTrue(from.setSwipe(boardID: id, keyID: infinity, up: false, choices: ["♾"]))
                XCTAssertTrue(from.setSwipe(boardID: id, keyID: infinity, up: false, choices: []))
                XCTAssertNil(from.key(boardID: id, keyID: infinity)?.down, "No choices turn the swipe off")
                // A choice dragged from hold to swipe down moves in one change.
                XCTAssertTrue(from.setLayers(boardID: id, keyID: infinity, variants: ["∞", "∝"], up: [], down: ["⧜"]))
                XCTAssertEqual(from.key(boardID: id, keyID: infinity)?.variants, ["∝"], "The key itself is not its own variant")
                XCTAssertEqual(from.key(boardID: id, keyID: infinity)?.down, ["⧜"])
                XCTAssertNil(from.key(boardID: id, keyID: infinity)?.up)
                XCTAssertFalse(from.setLayers(boardID: id, keyID: infinity, variants: [""], up: [], down: []))
                XCTAssertFalse(from.setLayers(boardID: id, keyID: "missing", variants: [], up: [], down: []))
                XCTAssertFalse(from.setLayers(boardID: "missing", keyID: infinity, variants: [], up: [], down: []))
                XCTAssertFalse(from.setLayers(boardID: id, keyID: infinity, variants: [],
                                              up: (0...16).map { String(UnicodeScalar(0x2200 + $0)!) }, down: []))
                XCTAssertTrue(from.setLayers(boardID: id, keyID: infinity, variants: [], up: [], down: []))
                XCTAssertTrue(from.setLayout(boardID: id, layout: SymbolPageLayout("hk/k")))
                XCTAssertNotNil(from.add(text: "★", to: SymbolBoardStore.favoritesID))
                let file = try XCTUnwrap(from.exportedPages())
                let to = SymbolBoardStore(defaults: target, pages: try sharedPages().settings, configuresPages: true)
                XCTAssertEqual(to.importPages(file), 1)
                let page = try XCTUnwrap(to.customPages.first)
                XCTAssertEqual(page.name, "Math")
                XCTAssertNotEqual(page.id, id, "Imported pages get new identities")
                XCTAssertEqual(page.keys.map(\.text), ["∑", "∞"])
                XCTAssertEqual(page.keys.first?.variants, ["∏"])
                XCTAssertEqual(page.keys.first?.up, ["⅀", "Σ"])
                XCTAssertEqual(page.keys.first?.down, ["∫"])
                XCTAssertEqual(page.layout, "hk/k")
                XCTAssertTrue(to.favoriteTexts.isEmpty, "Favorites are not part of a page file")
                XCTAssertEqual(to.importPages(file), 1, "Importing again adds another copy")
                for bad in [Data("not json".utf8), Data(#"{"schemaVersion":2,"pages":[]}"#.utf8),
                            Data(#"{"schemaVersion":1,"pages":[]}"#.utf8),
                            Data(#"{"schemaVersion":1,"pages":[{"name":"","keys":[]}]}"#.utf8),
                            Data(#"{"schemaVersion":1,"pages":[{"name":"Rows","keys":[],"layout":"x"}]}"#.utf8)] {
                    XCTAssertNil(to.importPages(bad))
                }
                let many = Data(("{\"schemaVersion\":1,\"pages\":[" + Array(repeating: #"{"name":"P","keys":[]}"#, count: SymbolBoardStore.maximumBoards).joined(separator: ",") + "]}").utf8)
                XCTAssertNil(to.importPages(many), "Pages that would not fit are refused")
                XCTAssertEqual(to.customPages.count, 2)
            }
        }
    }

    func testPagesMadeInsideAnEarlierKeyboardAreNotCarriedOver() throws {
        let pages = try sharedPages().settings
        try withDefaults { defaults in
            let legacy = SymbolBoardStore(defaults: defaults)
            let id = try XCTUnwrap(legacy.createBoard(named: "Old"))
            XCTAssertTrue(legacy.setPreferredStarBoard(id))
            XCTAssertNotNil(legacy.add(text: "☃", to: SymbolBoardStore.favoritesID))
            let keyboard = SymbolBoardStore(defaults: defaults, pages: pages, configuresPages: false)
            XCTAssertEqual(keyboard.boards.map(\.id), [SymbolBoardStore.stockID, SymbolBoardStore.favoritesID])
            XCTAssertEqual(keyboard.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertEqual(keyboard.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertEqual(keyboard.favoriteTexts, ["☃"], "Favorites are kept")
        }
    }

    func testListMovesReorderPagesAndKeysAndRejectBadOffsets() throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let math = try XCTUnwrap(store.createBoard(named: "Math"))
            let arrows = try XCTUnwrap(store.createBoard(named: "Arrows"))
            XCTAssertTrue(store.moveBoards(fromOffsets: [3], toOffset: 0))
            XCTAssertEqual(store.boards.map(\.id), [arrows, SymbolBoardStore.stockID, SymbolBoardStore.favoritesID, math])
            XCTAssertTrue(store.moveBoards(fromOffsets: [0, 1], toOffset: 4))
            XCTAssertEqual(store.boards.map(\.id), [SymbolBoardStore.favoritesID, math, arrows, SymbolBoardStore.stockID])
            XCTAssertFalse(store.moveBoards(fromOffsets: [9], toOffset: 0))
            XCTAssertFalse(store.moveBoards(fromOffsets: [0], toOffset: 9))
            for text in ["a", "b", "c"] { XCTAssertNotNil(store.add(text: text, to: math)) }
            XCTAssertTrue(store.moveKeys(boardID: math, fromOffsets: [2], toOffset: 0))
            XCTAssertEqual(store.boards.first { $0.id == math }?.keys.map(\.text), ["c", "a", "b"])
            XCTAssertFalse(store.moveKeys(boardID: "missing", fromOffsets: [0], toOffset: 1))
        }
    }

    func testEmptyBoardUsesStockStripWithoutChangingStarPreference() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertEqual(store.typingBoard.id, SymbolBoardStore.stockID)
            XCTAssertTrue(store.selectBoard(SymbolBoardStore.favoritesID))
            XCTAssertEqual(store.typingBoard.id, SymbolBoardStore.stockID)
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.favoritesID)
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertNotNil(store.add(text: "☃", to: SymbolBoardStore.favoritesID))
            XCTAssertEqual(store.typingBoard.id, SymbolBoardStore.favoritesID)
            XCTAssertEqual(store.typingBoard.keys.map(\.text), ["☃"])
        }
    }

    func testFreshStockAndEmptyFavoritesPersistWithExactStockVariants() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertNil(store.loadIssue)
            XCTAssertEqual(store.activeBoard.id, SymbolBoardStore.stockID)
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertEqual(store.preferredStarBoard.id, SymbolBoardStore.favoritesID)
            XCTAssertGreaterThan(store.activeBoard.keys.count, 20)
            XCTAssertTrue(store.activeBoard.keys.contains { $0.text == "$" && $0.variants.contains("¥") })
            XCTAssertEqual(store.boards.last?.id, SymbolBoardStore.favoritesID)
            XCTAssertEqual(store.boards.last?.keys, [])
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).boards, store.boards)
        }
    }
    func testPreferredStarTargetAndTemporaryActiveBoardPersistIndependently() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let custom = try XCTUnwrap(store.createBoard(named: "Work"))
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertTrue(store.selectBoard(SymbolBoardStore.stockID))
            XCTAssertTrue(store.setPreferredStarBoard(custom))
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID, "Setting the star target is not a temporary board switch")
            XCTAssertEqual(store.preferredStarBoard.id, custom)
            let restored = SymbolBoardStore(defaults: defaults)
            XCTAssertEqual(restored.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertEqual(restored.preferredStarBoardID, custom)
            XCTAssertTrue(restored.selectPreferredStarBoard())
            XCTAssertEqual(restored.activeBoardID, custom)
            XCTAssertTrue(restored.selectBoard(SymbolBoardStore.favoritesID))
            XCTAssertEqual(restored.preferredStarBoardID, custom)
            XCTAssertTrue(restored.setPreferredStarBoard(SymbolBoardStore.stockID))
            XCTAssertEqual(restored.activeBoardID, SymbolBoardStore.favoritesID)
            XCTAssertTrue(restored.selectPreferredStarBoard())
            XCTAssertEqual(restored.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertEqual(try payload(defaults)["version"] as? Int, 2)
            XCTAssertEqual(try payload(defaults)["preferredStarBoardID"] as? String, SymbolBoardStore.stockID)
        }
    }

    func testSelectingCurrentBoardDoesNotWriteOrPublishEvenWhenPersistenceIsUnavailable() async throws {
        try withDefaults { defaults in
            let seed = SymbolBoardStore(defaults: defaults)
            XCTAssertTrue(seed.setPreferredStarBoard(SymbolBoardStore.stockID))
            let bytes = defaults.data(forKey: SymbolBoardStore.storageKey)
            var writes = 0
            let store = SymbolBoardStore(defaults: defaults, persist: { _ in writes += 1; return false })
            var publications = 0
            let subscription = store.objectWillChange.sink { publications += 1 }
            defer { subscription.cancel() }
            XCTAssertTrue(store.selectBoard(SymbolBoardStore.stockID))
            XCTAssertTrue(store.selectPreferredStarBoard())
            XCTAssertEqual(writes, 0)
            XCTAssertEqual(publications, 0, "A no-op choice cannot reconfigure a held key")
            XCTAssertFalse(store.selectBoard(SymbolBoardStore.favoritesID))
            XCTAssertEqual(writes, 1, "A real change must still wait for persistence")
            XCTAssertEqual(publications, 0)
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), bytes)

            let corrupt = Data("{bad".utf8)
            defaults.set(corrupt, forKey: SymbolBoardStore.storageKey)
            let locked = SymbolBoardStore(defaults: defaults, persist: { _ in writes += 1; return false })
            XCTAssertEqual(locked.loadIssue, .unreadable)
            XCTAssertTrue(locked.selectBoard(SymbolBoardStore.stockID), "The currently displayed recovery board remains usable")
            XCTAssertFalse(locked.selectBoard(SymbolBoardStore.favoritesID))
            XCTAssertFalse(locked.selectBoard("missing"))
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), corrupt)
        }
    }

    func testVersionOneReadMigrationPreservesBoardsActiveAndOriginalBytesUntilSuccessfulMutation() async throws {
        try withDefaults { defaults in
            let seed = SymbolBoardStore(defaults: defaults)
            let board = try XCTUnwrap(seed.createBoard(named: "Exact"))
            for text in ["é", "e\u{0301}", "\0", "👩‍💻"] { XCTAssertNotNil(seed.add(text: text, to: board)) }
            let expectedBoards = seed.boards
            var old = try payload(defaults)
            old["version"] = 1
            old.removeValue(forKey: "preferredStarBoardID")
            let bytes = try replace(old, in: defaults)
            var writes = 0
            let migrated = SymbolBoardStore(defaults: defaults, persist: { _ in writes += 1; return false })
            XCTAssertNil(migrated.loadIssue)
            XCTAssertEqual(migrated.boards, expectedBoards)
            XCTAssertEqual(migrated.activeBoardID, board)
            XCTAssertEqual(migrated.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertEqual(writes, 0, "Read migration cannot overwrite v1 data")
            XCTAssertFalse(migrated.setPreferredStarBoard(board))
            XCTAssertEqual(migrated.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), bytes)
            let retry = SymbolBoardStore(defaults: defaults)
            XCTAssertTrue(retry.setPreferredStarBoard(board))
            XCTAssertEqual(retry.boards, expectedBoards)
            XCTAssertEqual(retry.activeBoardID, board)
            XCTAssertEqual(try payload(defaults)["version"] as? Int, 2)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).preferredStarBoardID, board)
        }
    }

    func testDeletingPreferredBoardFallsBackToFavoritesWithoutChangingOtherActiveChoice() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let preferred = try XCTUnwrap(store.createBoard(named: "Preferred"))
            let temporary = try XCTUnwrap(store.createBoard(named: "Temporary"))
            XCTAssertTrue(store.setPreferredStarBoard(preferred))
            XCTAssertTrue(store.deleteBoard(preferred))
            XCTAssertEqual(store.activeBoardID, temporary)
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertTrue(store.setPreferredStarBoard(temporary))
            XCTAssertTrue(store.deleteBoard(temporary))
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertTrue(store.selectPreferredStarBoard())
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.favoritesID)
        }
    }

    func testCurrentSchemaRejectsMissingInvalidOrNonexistentPreferredReferenceWithoutOverwriting() async throws {
        try withDefaults { defaults in
            _ = SymbolBoardStore(defaults: defaults)
            let original = try payload(defaults)
            for invalid: Any in [NSNull(), 1, true, [], [:], "missing", ""] {
                var object = original; object["preferredStarBoardID"] = invalid
                let bytes = try replace(object, in: defaults)
                let store = SymbolBoardStore(defaults: defaults)
                XCTAssertEqual(store.loadIssue, .unreadable)
                XCTAssertFalse(store.setPreferredStarBoard(SymbolBoardStore.stockID))
                XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), bytes)
            }
            var missing = original; missing.removeValue(forKey: "preferredStarBoardID")
            let bytes = try replace(missing, in: defaults)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).loadIssue, .unreadable)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), bytes)
        }
    }

    func testRejectedPersistenceKeepsAllFieldsAndBytesAtomicThenAllowsFreshRetry() async throws {
        try withDefaults { defaults in
            let seed = SymbolBoardStore(defaults: defaults)
            let board = try XCTUnwrap(seed.createBoard(named: "Custom"))
            let first = try XCTUnwrap(seed.add(text: "é", to: board))
            let second = try XCTUnwrap(seed.add(text: "e\u{0301}", to: board))
            XCTAssertTrue(seed.setPreferredStarBoard(board))
            XCTAssertTrue(seed.selectBoard(SymbolBoardStore.stockID))
            let beforeBytes = defaults.data(forKey: SymbolBoardStore.storageKey)
            let beforeBoards = seed.boards
            var fail = true; var attempts = 0
            let store = SymbolBoardStore(defaults: defaults, persist: { data in
                attempts += 1
                guard !fail else { return false }
                defaults.set(data, forKey: SymbolBoardStore.storageKey)
                return true
            })
            let mutations: [() -> Bool] = [
                { store.setPreferredStarBoard(SymbolBoardStore.favoritesID) },
                { store.selectPreferredStarBoard() }, { store.selectBoard(board) },
                { store.renameBoard(board, to: "Renamed") }, { store.moveBoard(board, by: -1) },
                { store.deleteBoard(board) }, { store.createBoard(named: "New") != nil },
                { store.add(text: "\0", to: board) != nil },
                { store.removeKey(boardID: board, keyID: first) },
                { store.moveKey(boardID: board, keyID: second, by: -1) },
                { store.setVariants(boardID: board, keyID: first, variants: ["👩‍💻"]) }
            ]
            for mutation in mutations {
                XCTAssertFalse(mutation())
                XCTAssertEqual(store.boards, beforeBoards)
                XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID)
                XCTAssertEqual(store.preferredStarBoardID, board)
                XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), beforeBytes)
            }
            XCTAssertEqual(attempts, mutations.count)
            XCTAssertNil(store.loadIssue, "A rejected mutation can be retried without claiming it was saved")
            fail = false
            XCTAssertTrue(store.selectPreferredStarBoard())
            XCTAssertEqual(store.activeBoardID, board)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).preferredStarBoardID, board)
        }
    }

    func testFailedInitialPersistencePreservesLegacyAndShowsReadOnlyFailure() async throws {
        try withDefaults { defaults in
            defaults.set([0, 0x2603], forKey: "favoriteCodePoints")
            var writes = 0
            let store = SymbolBoardStore(defaults: defaults, persist: { _ in writes += 1; return false })
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(store.loadIssue, .unwritable)
            XCTAssertFalse(store.canEdit)
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
            XCTAssertNil(defaults.data(forKey: SymbolBoardStore.storageKey))
            XCTAssertEqual(defaults.array(forKey: "favoriteCodePoints") as? [Int], [0, 0x2603])
            XCTAssertFalse(store.selectPreferredStarBoard())
        }
    }

    func testMigrationPreservesScalarControlsEmojiOrderAndLegacyBytes() async throws {
        try withDefaults { defaults in
            let points = [0x2603, 0, 0x0301, 0x200D, 0xFE0F, 0x2603]
            let emoji = ["1F469-200D-1F4BB", "1F642-200D-2194-FE0F", "2603", "D800", "1f680"]
            defaults.set(points, forKey: "favoriteCodePoints")
            defaults.set(emoji, forKey: "favoriteEmojiSequences")
            let store = SymbolBoardStore(defaults: defaults)
            let favorites = try XCTUnwrap(store.boards.first { $0.id == SymbolBoardStore.favoritesID })
            XCTAssertEqual(favorites.keys.map { Array($0.text.unicodeScalars.map(\.value)) },
                           [[0x2603], [0], [0x0301], [0x200D], [0xFE0F],
                            [0x1F469, 0x200D, 0x1F4BB], [0x1F642, 0x200D, 0x2194, 0xFE0F]])
            XCTAssertEqual(defaults.array(forKey: "favoriteCodePoints") as? [Int], points)
            XCTAssertEqual(defaults.stringArray(forKey: "favoriteEmojiSequences"), emoji)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).boards, store.boards)
        }
    }
    func testMigrationRejectsBooleanFractionalInvalidScalarsAndNoncanonicalEmoji() async throws {
        try withDefaults { defaults in
            defaults.set([true, -1, 65.5, 0xD800, 0x110000, 65] as [Any], forKey: "favoriteCodePoints")
            defaults.set(["01F680", "1F680-", "U+1F680", "1F680"], forKey: "favoriteEmojiSequences")
            let keys = SymbolBoardStore(defaults: defaults).boards.last!.keys
            XCTAssertEqual(keys.map(\.text), ["A", "🚀"])
        }
    }
    func testNormalMigrationRetainsScalarUnassignedInSelectedHistoricalEdition() async throws {
        try withDefaults { defaults in
            XCTAssertEqual(UnicodeEdition.older.catalog.character(at: 0x0558)?.category, "Cn")
            defaults.set([0x0558], forKey: "favoriteCodePoints")
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertNil(store.loadIssue)
            XCTAssertTrue(store.selectBoard(SymbolBoardStore.favoritesID))
            XCTAssertEqual(store.activeBoard.keys.count, 1)
            XCTAssertEqual(store.activeBoard.keys[0].text.unicodeScalars.map(\.value), [0x0558])
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).activeBoard.keys[0].text.unicodeScalars.map(\.value), [0x0558])
            XCTAssertTrue(store.contains("\u{0558}"))
        }
    }
    func testCustomBoardCRUDOrderAndActiveChoiceSurviveRelaunch() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let first = try XCTUnwrap(store.createBoard(named: " Math "))
            let second = try XCTUnwrap(store.createBoard(named: "Work"))
            XCTAssertEqual(store.activeBoardID, second)
            XCTAssertTrue(store.renameBoard(first, to: "Equations"))
            XCTAssertTrue(store.moveBoard(second, by: -1))
            XCTAssertEqual(store.boards.map(\.id), [SymbolBoardStore.stockID, SymbolBoardStore.favoritesID, second, first])
            XCTAssertTrue(store.selectBoard(first))
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).activeBoardID, first)
            XCTAssertTrue(store.deleteBoard(first))
            XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID)
            XCTAssertFalse(store.deleteBoard(SymbolBoardStore.stockID))
            XCTAssertFalse(store.deleteBoard(SymbolBoardStore.favoritesID))
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).boards, store.boards)
        }
    }
    func testPageReorderingIncludesBuiltInsPreservesSelectionAndStarAndPersists() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let custom = try XCTUnwrap(store.createBoard(named: "Work"))
            XCTAssertTrue(store.setPreferredStarBoard(custom))
            let original = store.boards
            for invalid in [Int.min, -2, 0, 2, Int.max] {
                XCTAssertFalse(store.canMoveBoard(custom, by: invalid))
                XCTAssertFalse(store.moveBoard(custom, by: invalid))
            }
            XCTAssertFalse(store.canMoveBoard("missing", by: -1))
            XCTAssertFalse(store.moveBoard("missing", by: 1))
            XCTAssertFalse(store.canMoveBoard(SymbolBoardStore.stockID, by: -1))
            XCTAssertFalse(store.canMoveBoard(custom, by: 1))
            XCTAssertEqual(store.boards, original)
            XCTAssertTrue(store.canMoveBoard(custom, by: -1))
            XCTAssertTrue(store.moveBoard(custom, by: -1))
            XCTAssertTrue(store.moveBoard(custom, by: -1))
            XCTAssertEqual(store.boards.map(\.id), [custom, SymbolBoardStore.stockID, SymbolBoardStore.favoritesID])
            XCTAssertFalse(store.canMoveBoard(custom, by: -1))
            XCTAssertTrue(store.canMoveBoard(SymbolBoardStore.stockID, by: 1))
            XCTAssertTrue(store.moveBoard(SymbolBoardStore.stockID, by: 1))
            XCTAssertEqual(store.boards.map(\.id), [custom, SymbolBoardStore.favoritesID, SymbolBoardStore.stockID])
            XCTAssertEqual(store.activeBoardID, custom)
            XCTAssertEqual(store.preferredStarBoardID, custom)
            let restored = SymbolBoardStore(defaults: defaults)
            XCTAssertEqual(restored.boards, store.boards)
            XCTAssertEqual(restored.activeBoardID, custom)
            XCTAssertEqual(restored.preferredStarBoardID, custom)
        }
    }
    func testExactNFCAndNFDKeysAndVariantsRemainDistinct() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let board = try XCTUnwrap(store.createBoard(named: "Exact"))
            let composed = "\u{00E9}", decomposed = "e\u{0301}"
            XCTAssertEqual(composed, decomposed, "Control: Swift canonical equality differs from keyboard byte identity")
            let key = try XCTUnwrap(store.add(text: composed, to: board))
            let other = try XCTUnwrap(store.add(text: decomposed, to: board))
            XCTAssertNotEqual(key, other)
            XCTAssertEqual(store.add(text: composed, to: board), key)
            XCTAssertTrue(store.setVariants(boardID: board, keyID: key,
                                            variants: [composed, decomposed, decomposed, "\0", "\u{200D}"]))
            let restored = try XCTUnwrap(SymbolBoardStore(defaults: defaults).key(boardID: board, keyID: key))
            XCTAssertEqual(restored.variants.map { Array($0.utf16) }, [decomposed, "\0", "\u{200D}"].map { Array($0.utf16) })
            XCTAssertNotEqual(SymbolBoardKey(id: "same", text: composed, variants: []),
                              SymbolBoardKey(id: "same", text: decomposed, variants: []))
        }
    }
    func testKeysPreserveWholeSequencesMoveAndDeleteByIdentity() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let board = try XCTUnwrap(store.createBoard(named: "Sequences"))
            let a = try XCTUnwrap(store.add(text: "👩‍💻", to: board))
            let b = try XCTUnwrap(store.add(text: "🙂‍↔️", to: board))
            XCTAssertTrue(store.moveKey(boardID: board, keyID: b, by: -1))
            XCTAssertEqual(store.activeBoard.keys.map(\.id), [b, a])
            XCTAssertEqual(store.activeBoard.keys[0].text.unicodeScalars.map(\.value), [0x1F642, 0x200D, 0x2194, 0xFE0F])
            XCTAssertTrue(store.contains("👩‍💻"))
            XCTAssertTrue(store.removeKey(boardID: board, keyID: a))
            XCTAssertFalse(store.removeKey(boardID: board, keyID: a))
            XCTAssertNil(store.key(boardID: board, keyID: a))
        }
    }
    func testAllNonemptyUnicodeAllowedIncludingControlOnlyAndVariationSelectors() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let board = try XCTUnwrap(store.createBoard(named: "Invisible"))
            for text in ["\0", "\n", "\r\t", "\u{0301}", "\u{200D}", "\u{FE0F}", "\u{10FFFF}"] {
                let id = try XCTUnwrap(store.add(text: text, to: board))
                XCTAssertTrue(SymbolBoardKey.exact(try XCTUnwrap(store.key(boardID: board, keyID: id)).text, text))
            }
            XCTAssertNil(store.add(text: "", to: board))
            XCTAssertNil(store.createBoard(named: "\0"))
            XCTAssertNil(store.createBoard(named: "  \n "))
            XCTAssertNil(store.createBoard(named: String(repeating: "a", count: 33)))
            XCTAssertNotNil(store.createBoard(named: "a" + String(repeating: "\u{0301}", count: 127)))
            XCTAssertNil(store.createBoard(named: "a" + String(repeating: "\u{0301}", count: 128)))
            XCTAssertNotNil(store.createBoard(named: String(repeating: "\u{10FFFF}", count: 32)))
        }
    }
    func testTextAndVariantBoundsRejectWithoutPartialMutation() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let board = try XCTUnwrap(store.createBoard(named: "Bounds"))
            let key = try XCTUnwrap(store.add(text: String(repeating: "a", count: 64), to: board))
            let before = defaults.data(forKey: SymbolBoardStore.storageKey)
            XCTAssertNil(store.add(text: String(repeating: "a", count: 65), to: board))
            XCTAssertFalse(store.setVariants(boardID: board, keyID: key, variants: [""]))
            XCTAssertFalse(store.setVariants(boardID: board, keyID: key, variants: (0...SymbolBoardStore.maximumVariants).map { String($0) }))
            XCTAssertFalse(store.moveBoard(board, by: Int.max))
            XCTAssertFalse(store.moveKey(boardID: board, keyID: key, by: Int.min))
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), before)
            XCTAssertTrue(store.setVariants(boardID: board, keyID: key, variants: (0..<SymbolBoardStore.maximumVariants).map { String($0) }))
        }
    }
    func testBoardAndKeyCapacityBoundariesAreAtomic() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            for index in 2..<SymbolBoardStore.maximumBoards { XCTAssertNotNil(store.createBoard(named: "Board \(index)")) }
            XCTAssertNil(store.createBoard(named: "Overflow"))
            let board = store.activeBoardID
            for index in 0..<SymbolBoardStore.maximumKeys { XCTAssertNotNil(store.add(text: "\(index)", to: board)) }
            XCTAssertNil(store.add(text: "Overflow", to: board))
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).activeBoard.keys.count, 256)
        }
    }
    func testMigratedFavoritesRetainLargerBudgetAfterFutureEdits() async throws {
        try withDefaults { defaults in
            defaults.set(Array(0x1000..<0x1000 + 300), forKey: "favoriteCodePoints")
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertTrue(store.selectBoard(SymbolBoardStore.favoritesID))
            XCTAssertEqual(store.activeBoard.keys.count, 300)
            XCTAssertNotNil(store.add(text: "🙂‍↔️", to: SymbolBoardStore.favoritesID))
            let restored = SymbolBoardStore(defaults: defaults)
            XCTAssertNil(restored.loadIssue)
            XCTAssertEqual(restored.activeBoard.keys.count, 301)
        }
    }
    func testOverbudgetMigrationKeepsLegacyAndDoesNotWritePartialPayload() async throws {
        try withDefaults { defaults in
            let points = Array(0x1000..<0x1000 + SymbolBoardStore.maximumMigratedFavorites + 1)
            defaults.set(points, forKey: "favoriteCodePoints")
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertEqual(store.loadIssue, .legacyTooLarge)
            XCTAssertTrue(store.hasLegacyFallback)
            XCTAssertNil(defaults.object(forKey: SymbolBoardStore.storageKey))
            XCTAssertEqual(defaults.array(forKey: "favoriteCodePoints") as? [Int], points)
            XCTAssertNil(store.createBoard(named: "Would hide legacy"))
        }
    }
    func testLegacyImportWithinKeyCountButBeyondPayloadBudgetPreservesEveryOriginal() async throws {
        try withDefaults { defaults in
            let prefix = Array(repeating: "1F680", count: 63)
            let legacy = (0..<2_048).map { index in
                (prefix + [String(format: "%04X", 0x20000 + index)]).joined(separator: "-")
            }
            defaults.set(legacy, forKey: "favoriteEmojiSequences")
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertEqual(store.loadIssue, .legacyTooLarge)
            XCTAssertTrue(store.hasLegacyFallback)
            XCTAssertFalse(store.canEdit)
            XCTAssertNil(defaults.object(forKey: SymbolBoardStore.storageKey), "No partial import may replace the legacy collection")
            XCTAssertEqual(defaults.stringArray(forKey: "favoriteEmojiSequences"), legacy)
        }
    }

    func testInvalidMutationTargetsCannotBreakTheActiveBoardReferenceInvariant() async throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let before = defaults.data(forKey: SymbolBoardStore.storageKey)
            XCTAssertFalse(store.selectBoard("missing"))
            XCTAssertFalse(store.setPreferredStarBoard("missing"))
            XCTAssertFalse(store.renameBoard("missing", to: "Valid name"))
            XCTAssertFalse(store.moveBoard(SymbolBoardStore.stockID, by: -1))
            XCTAssertFalse(store.moveBoard(SymbolBoardStore.favoritesID, by: 1))
            XCTAssertNil(store.add(text: "☃", to: "missing"))
            XCTAssertFalse(store.removeKey(boardID: "missing", keyID: "missing"))
            XCTAssertFalse(store.moveKey(boardID: SymbolBoardStore.stockID, keyID: "stock.0", by: -1))
            XCTAssertFalse(store.setVariants(boardID: "missing", keyID: "missing", variants: ["☃"]))
            XCTAssertEqual(store.activeBoard.id, SymbolBoardStore.stockID)
            XCTAssertTrue(store.boards.contains { $0.id == store.activeBoardID })
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), before)
        }
    }
    func testSelectionPolicyResolvesRequestedBoardMissingReferenceAndEmptyInput() async throws {
        let first = SymbolBoard(id: "first", name: "First", keys: [])
        let second = SymbolBoard(id: "second", name: "Second", keys: [SymbolBoardKey(id: "key", text: "☃", variants: [])])
        XCTAssertEqual(SymbolBoardStore.selectedBoard(in: [first, second], activeBoardID: second.id), second)
        XCTAssertEqual(SymbolBoardStore.selectedBoard(in: [first, second], activeBoardID: "missing"), first)
        let empty = SymbolBoardStore.selectedBoard(in: [], activeBoardID: "missing")
        XCTAssertEqual(empty.id, SymbolBoardStore.stockID)
        XCTAssertEqual(empty.name, "Symbols")
        XCTAssertTrue(empty.keys.contains { SymbolBoardKey.exact($0.text, "$") && $0.variants.contains("¥") })
    }
    func testMalformedWrongTypeOversizeAndUnknownVersionNeverOverwriteStoredBytes() async throws {
        try withDefaults { defaults in
            let values: [Any] = ["wrong", Data("{bad".utf8), Data(repeating: 32, count: SymbolBoardStore.maximumPayloadBytes + 1)]
            for value in values {
                defaults.set(value, forKey: SymbolBoardStore.storageKey)
                let before = defaults.object(forKey: SymbolBoardStore.storageKey) as? NSObject
                let store = SymbolBoardStore(defaults: defaults)
                XCTAssertNotNil(store.loadIssue)
                XCTAssertFalse(store.selectBoard(SymbolBoardStore.favoritesID))
                XCTAssertFalse(store.setPreferredStarBoard(SymbolBoardStore.stockID))
                XCTAssertFalse(store.selectPreferredStarBoard())
                XCTAssertNil(store.createBoard(named: "Ignored"))
                XCTAssertNil(store.add(text: "!", to: SymbolBoardStore.stockID), "A duplicate cannot report a successful save in read-only recovery")
                XCTAssertNil(store.add(text: "☃", to: SymbolBoardStore.stockID))
                XCTAssertFalse(store.renameBoard(SymbolBoardStore.stockID, to: "Changed"))
                XCTAssertFalse(store.canMoveBoard(SymbolBoardStore.stockID, by: 1))
                XCTAssertFalse(store.moveBoard(SymbolBoardStore.stockID, by: 1))
                XCTAssertFalse(store.deleteBoard("missing"))
                let key = store.activeBoard.keys[0]
                XCTAssertFalse(store.removeKey(boardID: SymbolBoardStore.stockID, keyID: key.id))
                XCTAssertFalse(store.moveKey(boardID: SymbolBoardStore.stockID, keyID: key.id, by: 1))
                XCTAssertFalse(store.setVariants(boardID: SymbolBoardStore.stockID, keyID: key.id, variants: ["‼"]))
                XCTAssertEqual(defaults.object(forKey: SymbolBoardStore.storageKey) as? NSObject, before)
            }
            defaults.removeObject(forKey: SymbolBoardStore.storageKey)
            _ = SymbolBoardStore(defaults: defaults)
            var unknown = try payload(defaults)
            unknown["version"] = 4
            let original = try replace(unknown, in: defaults)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).loadIssue, .unsupportedVersion)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), original)
        }
    }
    func testWellFormedLegacySequenceBeyondScalarLimitRetainsReadOnlyFallback() async throws {
        try withDefaults { defaults in
            let id = Array(repeating: "0041", count: 65).joined(separator: "-")
            defaults.set(["1F680", id], forKey: "favoriteEmojiSequences")
            let store = SymbolBoardStore(defaults: defaults)
            XCTAssertEqual(store.loadIssue, .legacyTooLarge)
            XCTAssertNil(defaults.object(forKey: SymbolBoardStore.storageKey))
            XCTAssertEqual(defaults.stringArray(forKey: "favoriteEmojiSequences"), ["1F680", id])
        }
    }
    func testInvalidReferencesDuplicateIDsTextAndVariantsRejectWholePayload() async throws {
        try withDefaults { defaults in
            _ = SymbolBoardStore(defaults: defaults)
            let original = try payload(defaults)
            for mutation in 0..<5 {
                var invalid = original
                var boards = try XCTUnwrap(invalid["boards"] as? [[String: Any]])
                switch mutation {
                case 0: invalid["activeBoardID"] = "missing"
                case 1: boards[1]["id"] = boards[0]["id"]
                case 2: boards[0]["name"] = "\n"
                default:
                    var keys = try XCTUnwrap(boards[0]["keys"] as? [[String: Any]])
                    if mutation == 3 { keys.append(keys[0]) }
                    else { keys[0]["variants"] = [keys[0]["text"]!] }
                    boards[0]["keys"] = keys
                }
                invalid["boards"] = boards
                let data = try replace(invalid, in: defaults)
                XCTAssertEqual(SymbolBoardStore(defaults: defaults).loadIssue, .unreadable)
                XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), data)
            }
        }
    }
}

extension SymbolBoardStoreTests {
    func testExplicitStaticPagesPersistLocallyShareAndExchangeWithoutFavoriteCopies() throws {
        try withDefaults { defaults in
            let pages = try sharedPages().settings
            let store = SymbolBoardStore(defaults: defaults, pages: pages)
            let id = try XCTUnwrap(store.createBoard(named: "Explicit"))
            let a = SymbolBoardKey(id: "a", text: "e\u{301}", variants: ["é"], up: ["👩‍💻"], down: nil)
            let b = SymbolBoardKey(id: "b", text: "é", variants: [])
            let rows: [SymbolBoard.Row] = [.init(alignment: .right, cells: [.key(a), .halfGap]),
                                           .init(alignment: .spaced, cells: [.gap, .key(b)])]
            XCTAssertTrue(store.setExplicitRows(boardID: id, rows: rows))
            XCTAssertFalse(store.setExplicitRows(boardID: SymbolBoardStore.favoritesID, rows: rows))
            XCTAssertFalse(store.setExplicitRows(boardID: "missing", rows: rows))
            XCTAssertFalse(store.setExplicitRows(boardID: id, rows: [.init(cells: [.gap])]))
            XCTAssertEqual(try payload(defaults)["version"] as? Int, 3)
            let localData = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
            let reloaded = SymbolBoardStore(defaults: defaults, pages: pages)
            XCTAssertEqual(reloaded.customPages.first?.explicitRows, rows)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), localData, "Reading never rewrites")
            let shared = try XCTUnwrap(pages.load())
            XCTAssertEqual(shared.pages.last?.explicitRows, rows)
            let sharedData = try XCTUnwrap(SymbolPageSettings.encode(shared))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: sharedData) as? [String: Any])
            XCTAssertEqual(object["schemaVersion"] as? Int, 2)
            XCTAssertNil(SymbolPageSettings.decode(Data(String(decoding: sharedData, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":1").utf8)))
            let file = try XCTUnwrap(store.exportedPages())
            let fileObject = try XCTUnwrap(JSONSerialization.jsonObject(with: file) as? [String: Any])
            XCTAssertEqual(fileObject["schemaVersion"] as? Int, 2)
            XCTAssertEqual(store.importPages(file), 1)
            XCTAssertEqual(store.customPages.last?.explicitRows, rows, "Nested payload retains stable key IDs and exact text")
            XCTAssertTrue(store.setVariants(boardID: id, keyID: "a", variants: ["x"]))
            XCTAssertEqual(store.key(boardID: id, keyID: "a")?.variants, ["x"])
            XCTAssertEqual(store.customPages.first?.explicitRows?.first?.alignment, .right)
            XCTAssertNotNil(store.add(text: "★", to: SymbolBoardStore.favoritesID))
            XCTAssertTrue(store.boards.first { $0.id == SymbolBoardStore.favoritesID }?.isLegacy == true)
            XCTAssertTrue(try XCTUnwrap(pages.load()).pages.first { $0.id == SymbolBoardStore.favoritesID }?.keys.isEmpty == true)
            XCTAssertNotNil(store.add(text: "c", to: id))
            XCTAssertTrue(store.moveKey(boardID: id, keyID: "a", by: 1))
            XCTAssertTrue(store.removeKey(boardID: id, keyID: "b"))
            XCTAssertEqual(store.customPages.first?.explicitRows?.last?.alignment, .spaced,
                           "Removing the only key in the first row drops that row, not the surviving row's alignment")
        }
    }

    func testLegacyConversionFitsOldUnderflowOverflowAndIsOptIn() throws {
        let keys = (0..<13).map { SymbolBoardKey(id: "k\($0)", text: String($0), variants: []) }
        for layout: String? in [nil, "hk/gkk", "kkkkkkkkkkkkkkkk/ggk"] {
            var board = SymbolBoard(id: "p", name: "Page", keys: keys, layout: layout)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(board)
            let resolved = board.resolvedRows
            XCTAssertTrue(board.isLegacy)
            XCTAssertEqual(board.layout, layout)
            XCTAssertEqual(try encoder.encode(board), data)
            if resolved.contains(where: { $0.units > SymbolBoard.Row.maximumRowUnits }) {
                XCTAssertFalse(board.convertToExplicitRows())
                XCTAssertTrue(board.isLegacy, "An overlong old page stays legacy until repaired")
                continue
            }
            XCTAssertTrue(board.convertToExplicitRows())
            XCTAssertEqual(board.explicitRows, resolved)
            XCTAssertEqual(board.keys, keys)
            XCTAssertEqual(try JSONDecoder().decode(SymbolBoard.self, from: JSONEncoder().encode(board)), board)
            board.keys.reverse()
            XCTAssertFalse(board.isLegacy)
            board.layout = "k/kkkkkkkkkkkk"
            XCTAssertFalse(board.isLegacy)
        }
        var favorites = SymbolBoard(id: SymbolBoardStore.favoritesID, name: "Favorites", keys: keys)
        XCTAssertFalse(favorites.convertToExplicitRows())
        let empty = SymbolBoard(id: "empty", name: "Empty", rows: [])
        XCTAssertEqual(try JSONDecoder().decode(SymbolBoard.self, from: JSONEncoder().encode(empty)), empty)
    }
}

extension SymbolBoardStoreTests {
    func testExplicitPageListMutationsRetainCellsAndOverflowAlignmentAndRejectAmbiguity() throws {
        let a = SymbolBoardKey(id: "a", text: "a", variants: []), b = SymbolBoardKey(id: "b", text: "b", variants: [])
        var page = SymbolBoard(id: "p", name: "Page", rows: [.init(alignment: .right, cells: [.key(a), .halfGap]),
                                                          .init(alignment: .center, cells: [.key(b), .gap])])
        page.keys.removeFirst()
        XCTAssertEqual(page.explicitRows, [.init(alignment: .center, cells: [.key(b), .gap])])
        let keys = (0..<11).map { SymbolBoardKey(id: "x\($0)", text: String($0), variants: []) }
        page.keys = keys
        XCTAssertEqual(page.explicitRows?.last?.alignment, .center)
        XCTAssertEqual(page.keys, keys)
        XCTAssertEqual(page.explicitRows?.count, 2)
        page.layout = "k/kkkkkkkkkk"
        XCTAssertEqual(page.explicitRows?.map(\.alignment), [.center, .center])
        page.keys = []
        XCTAssertEqual(page.explicitRows, [])
        XCTAssertNil(page.layout)
        page.keys.append(a)
        XCTAssertEqual(page.explicitRows, [.init(alignment: .left, cells: [.key(a)])],
                       "An empty explicit page gets its physical default alignment on its first new row")
        var legacy = SymbolBoard(id: "legacy", name: "Legacy", keys: [a])
        XCTAssertTrue(legacy.convertToExplicitRows())
        XCTAssertFalse(legacy.setExplicitRows([.init(cells: [.key(a), .key(a)])]))
        XCTAssertFalse(legacy.setExplicitRows(Array(repeating: .init(cells: [.key(a)]), count: 65)))
        for bad in [
            #"{"id":"p","name":"P","rows":[],"keys":[]}"#,
            #"{"id":"migrated-favorites","name":"Favorites","rows":[]}"#,
            #"{"id":"p","name":"P","rows":[{"alignment":"left","cells":[{"key":{"id":"a","text":"a","variants":[],"future":[]}}]}]}"#,
            #"{"id":"p","name":"P","rows":[{"alignment":"left","cells":[{"key":{"id":"a","text":"a","variants":[]}},{"key":{"id":"a","text":"b","variants":[]}}]}]}"#,
        ] { XCTAssertThrowsError(try JSONDecoder().decode(SymbolBoard.self, from: Data(bad.utf8))) }
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let original = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
            for page in [
                #"{"name":"Mixed","keys":[],"rows":[]}"#,
                #"{"name":"Mixed","layout":"k","rows":[]}"#,
                #"{"name":"Null","keys":null,"rows":[]}"#,
                #"{"name":"Long","rows":[{"alignment":"left","cells":[{"key":{"id":"a","text":"a","variants":[]}}]}]}"#,
            ] {
                let schema = page.contains("Long") ? 1 : 2
                XCTAssertNil(store.importPages(Data("{\"schemaVersion\":\(schema),\"pages\":[\(page)]}".utf8)))
                XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), original)
            }
        }
    }
}

extension SymbolBoardStoreTests {
    func testNewJSONPageImportReportsTheNamedOverlongRowAndKeepsPriorBytes() throws {
        try withDefaults { defaults in
            let store = SymbolBoardStore(defaults: defaults)
            let original = defaults.data(forKey: SymbolBoardStore.storageKey)
            let cells = (0..<13).map { "{\"key\":{\"id\":\"k\($0)\",\"text\":\"\($0)\",\"variants\":[]}}" }.joined(separator: ",")
            let file = "{\"schemaVersion\":2,\"pages\":[{\"name\":\"Math\",\"rows\":[{\"alignment\":\"right\",\"cells\":[\(cells)]}]}]}"
            XCTAssertNil(store.importPages(Data(file.utf8)))
            XCTAssertEqual(store.pageImportIssue, "Math, row 1: This row exceeds the limit of 12 standard-key widths. Move keys or remove gaps before applying. (pages[1].rows[1])")
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), original)
            XCTAssertNil(store.importPages(Data(count: SymbolBoardStore.maximumPayloadBytes + 1)))
            XCTAssertNotNil(store.pageImportIssue)
            let oldCells = (0..<13).map { "{\"text\":\"\($0)\",\"variants\":[]}" }.joined(separator: ",")
            let old = "{\"schemaVersion\":1,\"pages\":[{\"name\":\"Old\",\"layout\":\"kkkkkkkkkkkkk\",\"keys\":[\(oldCells)]}]}"
            XCTAssertEqual(store.importPages(Data(old.utf8)), 1)
            XCTAssertNil(store.pageImportIssue)
            XCTAssertTrue(store.customPages[0].isLegacy)
            XCTAssertEqual(store.customPages[0].layout, "kkkkkkkkkkkkk")
        }
    }
}

// Shared publication commits page edits; local-cache rejection is a warning.
// The historical false-after-publication reproduction is preserved in notes.
extension SymbolBoardStoreTests {
    private func withPageCommitFixture(_ body: (UserDefaults, SymbolPageSettings, URL, String) throws -> Void) throws {
        let shared = try sharedPages()
        try withDefaults { defaults in
            let seed = SymbolBoardStore(defaults: defaults, pages: shared.settings)
            let id = try XCTUnwrap(seed.createBoard(named: "Commit ordering"))
            for text in ["e\u{301}", "👩‍💻"] { XCTAssertNotNil(seed.add(text: text, to: id)) }
            XCTAssertTrue(seed.setPreferredStarBoard(id))
            XCTAssertTrue(seed.selectBoard(SymbolBoardStore.stockID))
            try body(defaults, shared.settings, shared.directory, id)
        }
    }

    func testExplicitRowLocalRejectionAcceptsSharedPublicationThenNewerEditRepairsCache() throws {
        try assertRowLocalRejectionAfterSharedPublication(explicit: true)
    }

    func testLegacyRowLocalRejectionAcceptsSharedPublication() throws {
        try assertRowLocalRejectionAfterSharedPublication(explicit: false)
    }

    private func assertRowLocalRejectionAfterSharedPublication(explicit: Bool) throws {
        try withPageCommitFixture { defaults, pages, directory, id in
            try withDefaults { keyboardDefaults in
                let sharedURL = directory.appendingPathComponent(SymbolPageSettings.filename)
                let localBefore = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
                let sharedBefore = try Data(contentsOf: sharedURL)
                let before = try XCTUnwrap(pages.load())
                var expected = before
                let index = try XCTUnwrap(expected.pages.firstIndex { $0.id == id })
                let keys = expected.pages[index].keys
                var rows: [SymbolBoard.Row] = [.init(alignment: .right, cells: [.key(keys[1]), .halfGap, .key(keys[0])])]
                if explicit { XCTAssertTrue(expected.pages[index].setExplicitRows(rows)) }
                else { expected.pages[index].keys.reverse(); expected.pages[index].layout = "hk/k" }
                let keyboard = SymbolBoardStore(defaults: keyboardDefaults, pages: pages, configuresPages: false)
                XCTAssertEqual(keyboard.boards, before.pages)
                var rejectLocal = true
                var localAttempts = 0
                let store = SymbolBoardStore(defaults: defaults, persist: { data in
                    localAttempts += 1
                    XCTAssertEqual(pages.load(), expected, "Real shared file is already replaced when local persistence starts")
                    guard !rejectLocal else { return false }
                    defaults.set(data, forKey: SymbolBoardStore.storageKey)
                    return defaults.data(forKey: SymbolBoardStore.storageKey) == data
                }, pages: pages)
                let boardsBefore = store.boards
                var publications = 0
                let subscription = store.objectWillChange.sink { publications += 1 }
                defer { subscription.cancel() }
                let save = {
                    explicit ? store.setExplicitRows(boardID: id, rows: rows)
                        : store.setLayout(boardID: id, layout: SymbolPageLayout("hk/k"), keyMove: .init(from: 1, to: 0))
                }
                let returned = save()
                XCTAssertTrue(returned, "PageArrangeView must not show its rejected-edit error after publication")
                XCTAssertEqual(localAttempts, 1)
                XCTAssertEqual(store.boards, expected.pages)
                XCTAssertEqual(store.activeBoardID, SymbolBoardStore.stockID)
                XCTAssertEqual(store.preferredStarBoardID, id)
                XCTAssertNil(store.loadIssue, "Commit failure does not lock the editor")
                XCTAssertGreaterThan(publications, 0, "The app renders the committed arrangement")
                XCTAssertTrue(store.localCopyWarning)
                XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), localBefore)
                XCTAssertEqual(SymbolBoardStore(defaults: defaults).boards, boardsBefore, "Local-only reload retains old data")
                XCTAssertNotEqual(try Data(contentsOf: sharedURL), sharedBefore)
                XCTAssertEqual(pages.load(), expected)
                XCTAssertEqual(keyboard.boards, before.pages, "An existing keyboard has not refreshed yet")
                keyboard.refreshPages()
                XCTAssertEqual(keyboard.boards, expected.pages, "Keyboard refresh adopts the rejected row edit")
                let reopened = SymbolBoardStore(defaults: defaults, pages: pages)
                XCTAssertEqual(reopened.boards, expected.pages, "App reopening adopts shared data despite prior false result")
                XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), localBefore, "Shared refresh does not repair the local cache")
                print("SAVE-FIX \(explicit ? "explicit" : "legacy"): return=true, localBytes=unchanged, warning=true, appAndKeyboard=newRows")
                if explicit {
                    rejectLocal = false
                    XCTAssertTrue(save(), "An accepted edit is now a no-op, not an old snapshot retry")
                    XCTAssertEqual(localAttempts, 1)
                    XCTAssertTrue(store.localCopyWarning)
                    XCTAssertNotNil(store.localCopyWarningID)
                    store.dismissLocalCopyWarning()
                    XCTAssertNil(store.localCopyWarningID)
                    XCTAssertTrue(store.localCopyWarning, "Leaving a screen dismisses presentation, not pending persistence")
                    XCTAssertTrue(save())
                    XCTAssertEqual(localAttempts, 1)
                    XCTAssertNil(store.localCopyWarningID, "Reentering or a no-op must not reshow a dismissed warning")
                    rows[0].alignment = .center
                    XCTAssertTrue(expected.pages[index].setExplicitRows(rows))
                    XCTAssertTrue(save(), "A newer current edit repairs only its latest snapshot")
                    XCTAssertEqual(localAttempts, 2)
                    XCTAssertFalse(store.localCopyWarning)
                    XCTAssertEqual(store.boards, expected.pages)
                    XCTAssertEqual(SymbolBoardStore(defaults: defaults).boards, expected.pages)
                    XCTAssertEqual(pages.load(), expected)
                    XCTAssertGreaterThan(publications, 0)
                }
            }
        }
    }

    /// Exercise the production default writer, including defaults.set followed
    /// by a failed readback, rather than only the existing persist closure seam.
    private final class ReadbackMismatchDefaults: UserDefaults {
        var rejectStorageReadback = false
        var rejectedReadbacks = 0
        var interceptedStorageKey: String?
        override func data(forKey defaultName: String) -> Data? {
            if rejectStorageReadback && defaultName == interceptedStorageKey {
                rejectedReadbacks += 1
                return nil
            }
            return super.data(forKey: defaultName)
        }
    }

    func testDefaultWriterReadbackMismatchAcceptsSharedPublicationAndWarns() throws {
        let name = "Uniboard.SymbolBoards.Readback.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(ReadbackMismatchDefaults(suiteName: name))
        defaults.interceptedStorageKey = SymbolBoardStore.storageKey
        defer { defaults.removePersistentDomain(forName: name) }
        let pages = try sharedPages().settings
        let seed = SymbolBoardStore(defaults: defaults, pages: pages)
        let id = try XCTUnwrap(seed.createBoard(named: "Readback"))
        let keyID = try XCTUnwrap(seed.add(text: "★", to: id))
        let localBefore = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
        let store = SymbolBoardStore(defaults: defaults, pages: pages) // No injected persist closure.
        let rows: [SymbolBoard.Row] = [.init(alignment: .center, cells: [.key(try XCTUnwrap(store.key(boardID: id, keyID: keyID))), .gap])]
        defaults.rejectStorageReadback = true
        XCTAssertTrue(store.setExplicitRows(boardID: id, rows: rows))
        XCTAssertEqual(defaults.rejectedReadbacks, 1)
        defaults.rejectStorageReadback = false
        XCTAssertEqual(store.customPages.first?.explicitRows, rows)
        XCTAssertTrue(store.localCopyWarning)
        XCTAssertNil(store.loadIssue)
        XCTAssertNotEqual(defaults.data(forKey: SymbolBoardStore.storageKey), localBefore,
                          "set already changed UserDefaults even though acknowledgement failed")
        XCTAssertEqual(SymbolBoardStore(defaults: defaults).customPages.first?.explicitRows, rows)
        XCTAssertEqual(pages.load()?.pages.first { $0.id == id }?.explicitRows, rows)
        print("SAVE-FIX default-readback: return=true, warning=true, appAndShared=newRows; durable disk status is not observable")
    }

    func testSharedRowWriteRejectionPreventsLocalAttemptAndKeepsBothDestinations() throws {
        try withPageCommitFixture { defaults, pages, directory, id in
            let sharedURL = directory.appendingPathComponent(SymbolPageSettings.filename)
            let localBefore = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
            let sharedBefore = try Data(contentsOf: sharedURL)
            var sharedAttempts = 0
            var localAttempts = 0
            let rejectingPages = SymbolPageSettings(containerURL: { directory }, writeAtomically: { _, _ in
                sharedAttempts += 1
                throw CocoaError(.fileWriteNoPermission)
            })
            let store = SymbolBoardStore(defaults: defaults, persist: { _ in localAttempts += 1; return true }, pages: rejectingPages)
            let boardsBefore = store.boards
            var rows = try XCTUnwrap(store.customPages.first).resolvedRows
            rows[0].alignment = .right
            XCTAssertFalse(store.setExplicitRows(boardID: id, rows: rows))
            XCTAssertEqual(sharedAttempts, 1)
            XCTAssertEqual(localAttempts, 0)
            XCTAssertEqual(store.boards, boardsBefore)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), localBefore)
            XCTAssertEqual(try Data(contentsOf: sharedURL), sharedBefore)
            XCTAssertEqual(pages.load()?.pages, boardsBefore)
        }
    }

    func testSuccessfulRowCommitOrdersSharedThenLocalAndNoOpOrSelectionAvoidsSharedWrite() throws {
        try withPageCommitFixture { defaults, pages, directory, id in
            var order: [String] = []
            let observedPages = SymbolPageSettings(containerURL: { directory }, writeAtomically: { data, url in
                order.append("shared")
                try data.write(to: url, options: [.atomic])
            })
            let store = SymbolBoardStore(defaults: defaults, persist: { data in
                order.append("local")
                defaults.set(data, forKey: SymbolBoardStore.storageKey)
                return defaults.data(forKey: SymbolBoardStore.storageKey) == data
            }, pages: observedPages)
            var rows = try XCTUnwrap(store.customPages.first).resolvedRows
            rows[0].alignment = .spaced
            XCTAssertTrue(store.setExplicitRows(boardID: id, rows: rows))
            XCTAssertEqual(order, ["shared", "local"])
            XCTAssertEqual(store.customPages.first?.explicitRows, rows)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).boards, store.boards)
            XCTAssertEqual(pages.load()?.pages, store.boards)
            order.removeAll()
            XCTAssertTrue(store.setExplicitRows(boardID: id, rows: rows))
            XCTAssertTrue(order.isEmpty, "Exact row no-op does not test persistence")
            let sharedBefore = try Data(contentsOf: directory.appendingPathComponent(SymbolPageSettings.filename))
            XCTAssertTrue(store.selectBoard(id))
            XCTAssertEqual(order, ["local"], "Open-page selection is local, not a shared edit")
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(SymbolPageSettings.filename)), sharedBefore)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).activeBoardID, id)
        }
    }
}

extension SymbolBoardStoreTests {
    func testAcceptedCreateDeleteAndStarChangesSurviveStaleLocalReopenWithoutReplayingOldPages() throws {
        try withPageCommitFixture { defaults, pages, _, id in
            let before = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
            var reject = true
            let store = SymbolBoardStore(defaults: defaults, persist: { data in
                guard !reject else { return false }
                defaults.set(data, forKey: SymbolBoardStore.storageKey); return true
            }, pages: pages)
            let created = try XCTUnwrap(store.createBoard(named: "Published"))
            XCTAssertTrue(store.localCopyWarning)
            XCTAssertEqual(store.activeBoardID, created)
            XCTAssertTrue(store.setPreferredStarBoard(created))
            XCTAssertTrue(store.deleteBoard(id))
            XCTAssertTrue(store.renameBoard(created, to: "Latest"))
            let reopened = SymbolBoardStore(defaults: defaults, pages: pages)
            XCTAssertEqual(reopened.customPages.map(\.name), ["Latest"])
            XCTAssertEqual(reopened.preferredStarBoardID, created)
            XCTAssertEqual(reopened.activeBoardID, SymbolBoardStore.stockID, "Deleted stale active references fall back safely")
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), before)
            let latestShared = pages.load()
            reject = false
            XCTAssertTrue(store.selectBoard(SymbolBoardStore.stockID), "Local-only repair writes the current in-memory snapshot")
            XCTAssertFalse(store.localCopyWarning)
            XCTAssertEqual(pages.load(), latestShared, "Cache repair never republishes an old shared snapshot")
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).customPages.map(\.name), ["Latest"])
            XCTAssertTrue(store.deleteBoard(created))
            XCTAssertEqual(store.preferredStarBoardID, SymbolBoardStore.favoritesID)
        }
    }

    func testUnreadableLocalPayloadRetainsItsLockAndUnknownFavoritesBytes() throws {
        try withPageCommitFixture { defaults, pages, _, id in
            let corrupt = Data("{unreadable local Favorites".utf8)
            defaults.set(corrupt, forKey: SymbolBoardStore.storageKey)
            var localAttempts = 0
            let store = SymbolBoardStore(defaults: defaults, persist: { _ in localAttempts += 1; return true }, pages: pages)
            XCTAssertEqual(store.loadIssue, .unreadable)
            XCTAssertFalse(store.canEdit, "Unreadable local Favorites keep their edit lock")
            XCTAssertTrue(store.customPages.isEmpty)
            XCTAssertFalse(store.renameBoard(id, to: "Recovered shared page"))
            XCTAssertFalse(store.localCopyWarning)
            XCTAssertFalse(store.selectBoard(id), "Local-only edits cannot overwrite unknown Favorites")
            XCTAssertNil(store.add(text: "★", to: SymbolBoardStore.favoritesID))
            XCTAssertEqual(localAttempts, 0)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), corrupt)
            XCTAssertTrue(SymbolBoardStore(defaults: defaults, pages: pages).customPages.isEmpty)
        }
    }

    func testLocalOnlyFailureRemainsRejectedAndDoesNotClearOutstandingSharedWarning() throws {
        try withPageCommitFixture { defaults, pages, _, id in
            let store = SymbolBoardStore(defaults: defaults, persist: { _ in false }, pages: pages)
            XCTAssertFalse(store.selectBoard(id))
            XCTAssertFalse(store.localCopyWarning)
            XCTAssertTrue(store.renameBoard(id, to: "Saved"))
            XCTAssertTrue(store.localCopyWarning)
            let shared = pages.load()
            XCTAssertNil(store.add(text: "★", to: SymbolBoardStore.favoritesID))
            XCTAssertTrue(store.favoriteTexts.isEmpty)
            XCTAssertTrue(store.localCopyWarning)
            XCTAssertEqual(pages.load(), shared)
        }
    }
}

extension SymbolBoardStoreTests {
    func testMixedFavoritesLayoutAndPermutationAcceptsOnlySharedLayoutWithoutClaimingContentSync() throws {
        try withPageCommitFixture { defaults, pages, _, _ in
            let seed = SymbolBoardStore(defaults: defaults, pages: pages)
            for text in ["★", "∑"] { XCTAssertNotNil(seed.add(text: text, to: SymbolBoardStore.favoritesID)) }
            let before = try XCTUnwrap(defaults.data(forKey: SymbolBoardStore.storageKey))
            let store = SymbolBoardStore(defaults: defaults, persist: { _ in false }, pages: pages)
            XCTAssertTrue(store.setLayout(boardID: SymbolBoardStore.favoritesID, layout: SymbolPageLayout("k/k"), keyMove: .init(from: 1, to: 0)))
            XCTAssertTrue(store.localCopyWarning)
            XCTAssertEqual(store.favoriteTexts, ["∑", "★"], "Current app rendering adopts the accepted edit")
            let favoritePage = try XCTUnwrap(pages.load()?.pages.first { $0.id == SymbolBoardStore.favoritesID })
            XCTAssertEqual(favoritePage.layout, "k/k")
            XCTAssertTrue(favoritePage.keys.isEmpty, "Published static pages never claim Favorites contents were synced")
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), before)
            let reopened = SymbolBoardStore(defaults: defaults, pages: pages)
            XCTAssertEqual(reopened.favoriteTexts, ["★", "∑"], "Unacknowledged local-only permutation is not durably promised")
            XCTAssertEqual(reopened.boards.first { $0.id == SymbolBoardStore.favoritesID }?.layout, "k/k")
        }
    }
}

extension SymbolBoardStoreTests {
    func testCurrentFavoriteRefreshClearsCacheWarningWithoutRewritingSharedPages() throws {
        try withPageCommitFixture { defaults, pages, directory, id in
            var reject = false
            let store = SymbolBoardStore(defaults: defaults, persist: { data in
                guard !reject else { return false }
                defaults.set(data, forKey: SymbolBoardStore.storageKey); return true
            }, sync: FavoriteSync(container: { directory }), pages: pages, sharedWriteAllowed: true)
            reject = true
            XCTAssertTrue(store.renameBoard(id, to: "Latest shared"))
            XCTAssertTrue(store.localCopyWarning)
            let sharedBefore = pages.load()
            store.refreshFavorites()
            XCTAssertTrue(store.localCopyWarning, "Rejected favorite cache acknowledgement keeps warning")
            reject = false
            store.refreshFavorites()
            XCTAssertFalse(store.localCopyWarning)
            XCTAssertEqual(SymbolBoardStore(defaults: defaults).customPages.first?.name, "Latest shared")
            XCTAssertEqual(pages.load(), sharedBefore)
        }
    }
}
