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
            unknown["version"] = 3
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
