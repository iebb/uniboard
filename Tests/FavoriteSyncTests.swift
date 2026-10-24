import Foundation
import XCTest
#if canImport(Darwin)
import Darwin
#endif
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

@MainActor
final class FavoriteSyncTests: XCTestCase {
    private func fixture(_ body: (URL, FavoriteSync, UserDefaults, UserDefaults) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let names = (0..<2).map { "Uniboard.FavoriteSync.Tests.\(UUID().uuidString).\($0)" }
        let defaults = names.map { UserDefaults(suiteName: $0)! }
        defer {
            try? FileManager.default.removeItem(at: root)
            for (name, store) in zip(names, defaults) { store.removePersistentDomain(forName: name) }
        }
        try body(root, FavoriteSync(container: { root }), defaults[0], defaults[1])
    }
    private func exact(_ values: [String]) -> [[UInt16]] { values.map { Array($0.utf16) } }
    private func key(_ store: SymbolBoardStore, _ text: String) throws -> String {
        try XCTUnwrap(store.boards.first { $0.id == SymbolBoardStore.favoritesID }?.keys.first { SymbolBoardKey.exact($0.text, text) }?.id)
    }
    func testDefaultProviderCanBeResolvedWithoutWriting() throws {
        _ = FavoriteSync().container()
        try fixture { _, _, defaults, _ in CharacterStore(defaults: defaults).removeFavoriteText("missing") }
    }
    func testMergePreservesExactTextAndConcurrentUnrelatedEdits() throws {
        let merged = try FavoriteSync.merge(base: ["Ψ", "x"], local: ["Ψ", "é", "e\u{301}", "👩‍💻"], remote: ["x", "Ψ", "𝚿"])
        XCTAssertEqual(exact(merged), exact(["é", "e\u{301}", "👩‍💻", "Ψ", "𝚿"]))
        XCTAssertEqual(try FavoriteSync.merge(base: ["a", "b"], local: ["b", "a"], remote: ["c", "a", "b"]), ["b", "a", "c"])
        XCTAssertEqual(try FavoriteSync.merge(base: ["a"], local: ["a"], remote: []), [])
        for invalid in [[""], ["a", "a"], [String(repeating: "a", count: 65)]] {
            XCTAssertThrowsError(try FavoriteSync.merge(base: invalid, local: [], remote: []))
        }
        let all = (0..<4096).map { "s\($0)" }
        XCTAssertThrowsError(try FavoriteSync.merge(base: [], local: all, remote: ["extra"]))
    }
    func testAppAndKeyboardMigrateUnionThenSyncBothDirectionsWithoutTouchingCustomBoards() throws {
        try fixture { _, sync, appDefaults, keyboardDefaults in
            appDefaults.set([0x03A8, 0x1D6BF], forKey: "favoriteCodePoints")
            let local = SymbolBoardStore(defaults: keyboardDefaults)
            let custom = try XCTUnwrap(local.createBoard(named: "Work"))
            let privateKey = try XCTUnwrap(local.add(text: "private board", to: custom))
            XCTAssertTrue(local.setVariants(boardID: custom, keyID: privateKey, variants: ["variant"]))
            XCTAssertTrue(local.setPreferredStarBoard(custom))
            for text in ["Δ", "ψ", "Ψ", "π"] { XCTAssertNotNil(local.add(text: text, to: SymbolBoardStore.favoritesID)) }
            let app = SymbolBoardStore(defaults: appDefaults, sync: sync, sharedWriteAllowed: true)
            let saved = CharacterStore(defaults: appDefaults, favoriteBoards: app)
            let keyboard = SymbolBoardStore(defaults: keyboardDefaults, sync: sync)
            XCTAssertEqual(Set(keyboard.favoriteTexts), ["Δ", "ψ", "Ψ", "π", "𝚿"])
            XCTAssertEqual(keyboard.syncStatus, .fullAccessRequired)
            XCTAssertEqual(app.favoriteTexts, ["Ψ", "𝚿"], "A read-only keyboard cannot upload its local favorites")
            keyboard.refreshFavorites(canWrite: true)
            app.refreshFavorites()
            XCTAssertEqual(exact(app.favoriteTexts), exact(keyboard.favoriteTexts))
            XCTAssertEqual(Set(saved.favorites), [0x394, 0x3C8, 0x3A8, 0x3C0, 0x1D6BF])
            XCTAssertEqual(keyboard.preferredStarBoardID, custom)
            XCTAssertEqual(keyboard.key(boardID: custom, keyID: privateKey)?.variants, ["variant"])
            XCTAssertFalse(app.boards.contains { $0.id == custom }, "Only Favorites is shared")
            saved.toggleFavorite(0x03A8)
            keyboard.refreshFavorites()
            XCTAssertFalse(keyboard.favoriteTexts.contains("Ψ"))
            let psi = try key(keyboard, "ψ")
            XCTAssertTrue(keyboard.removeKey(boardID: SymbolBoardStore.favoritesID, keyID: psi))
            saved.refreshFavorites()
            XCTAssertFalse(saved.isFavorite(0x03C8))
            XCTAssertEqual(app.syncStatus, .current)
        }
    }
    func testOfflineEditsSurviveRelaunchAndRemoteChangesThenFlushWhenAccessReturns() throws {
        try fixture { _, sync, a, b in
            let app = SymbolBoardStore(defaults: a, sync: sync, sharedWriteAllowed: true)
            XCTAssertNotNil(app.add(text: "a", to: SymbolBoardStore.favoritesID))
            var keyboard = SymbolBoardStore(defaults: b, sync: sync)
            XCTAssertTrue(keyboard.removeKey(boardID: SymbolBoardStore.favoritesID, keyID: try key(keyboard, "a")))
            XCTAssertNotNil(keyboard.add(text: "local", to: SymbolBoardStore.favoritesID))
            keyboard = SymbolBoardStore(defaults: b, sync: sync)
            XCTAssertEqual(keyboard.favoriteTexts, ["local"])
            XCTAssertNotNil(app.add(text: "remote", to: SymbolBoardStore.favoritesID))
            keyboard.refreshFavorites()
            XCTAssertEqual(keyboard.favoriteTexts, ["local", "remote"])
            keyboard.refreshFavorites(canWrite: true)
            app.refreshFavorites()
            XCTAssertEqual(app.favoriteTexts, ["local", "remote"])
            XCTAssertTrue(app.clearFavorites())
            keyboard.refreshFavorites()
            XCTAssertTrue(keyboard.favoriteTexts.isEmpty)
        }
    }
    func testSavedAdapterIncludesEmojiAndArbitrarySequencesAndReflectsLiveBoardEdits() throws {
        try fixture { _, _, defaults, _ in
            let board = SymbolBoardStore(defaults: defaults)
            let store = CharacterStore(defaults: defaults, favoriteBoards: board)
            store.toggleFavorite(0x41)
            XCTAssertTrue(store.isFavorite(0x41))
            let rocket = try XCTUnwrap(EmojiCatalog.latest.search("U+1F680").first)
            store.toggleFavoriteEmoji(rocket)
            XCTAssertTrue(store.isFavoriteEmoji(rocket.id))
            store.toggleFavoriteEmoji(rocket)
            XCTAssertFalse(store.isFavoriteEmoji(rocket.id))
            let coder = try XCTUnwrap(EmojiCatalog.latest.search("woman technologist").first)
            store.toggleFavoriteEmoji(coder)
            XCTAssertEqual(store.favoriteEmojiEntries(in: .latest).map(\.id), [coder.id])
            for text in ["e\u{301}", "é", "custom text"] { XCTAssertNotNil(board.add(text: text, to: SymbolBoardStore.favoritesID)) }
            XCTAssertEqual(exact(store.otherFavoriteTexts(in: .latest)), exact(["e\u{301}", "custom text"]))
            store.toggleFavorite(0x41)
            XCTAssertFalse(store.isFavorite(0x41))
            store.removeFavoriteText("custom text")
            XCTAssertEqual(exact(store.otherFavoriteTexts(in: .latest)), exact(["e\u{301}"]))
            store.removeFavoriteText("missing")
            store.reset()
            XCTAssertTrue(board.favoriteTexts.isEmpty)
        }
    }
    func testReadOnlyNeverCreatesFilesAndMissingSharedFileReseedsExistingFavorites() throws {
        try fixture { root, sync, _, _ in
            let result = try sync.synchronize(base: ["a"], local: ["a", "b"], canWrite: false)
            XCTAssertEqual(result.texts, ["b", "a"])
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
            XCTAssertTrue(try sync.synchronize(base: ["a"], local: ["a", "b"], canWrite: true).written)
            XCTAssertEqual(try sync.synchronize(base: [], local: [], canWrite: false).texts, ["b", "a"])
        }
    }
    /// A sync with nothing to change never rewrites the file: its bytes are
    /// part of the configuration fingerprint an open editor or review holds.
    func testANoChangeSyncLeavesTheFileUntouched() throws {
        try fixture { root, sync, _, _ in
            let file = root.appendingPathComponent(FavoriteSync.filename)
            var writes = 0
            var counting = sync
            counting.write = { writes += 1; try sync.write($0, $1) }
            XCTAssertTrue(try counting.synchronize(base: [], local: ["a"], canWrite: true).written)
            XCTAssertEqual(String(decoding: try Data(contentsOf: file), as: UTF8.self), #"{"texts":["a"],"version":1}"#)
            // Stored in another key order, as an earlier version may have written it.
            let stored = Data(#"{"version":1,"texts":["a"]}"#.utf8)
            try stored.write(to: file)
            for _ in 0..<3 {
                let result = try counting.synchronize(base: ["a"], local: ["a"], canWrite: true)
                XCTAssertTrue(result.written)
                XCTAssertEqual(result.texts, ["a"])
            }
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(try Data(contentsOf: file), stored)
            // A real change still writes, with sorted keys.
            XCTAssertEqual(try counting.synchronize(base: ["a"], local: ["a", "b"], canWrite: true).texts, ["b", "a"])
            XCTAssertEqual(writes, 2)
            XCTAssertEqual(String(decoding: try Data(contentsOf: file), as: UTF8.self), #"{"texts":["b","a"],"version":1}"#)
        }
    }
    func testUnavailableContainersAndMalformedSharedDataNeverOverwriteLocalOrRemote() throws {
        for root: URL? in [nil, URL(string: "https://invalid.example/")] {
            XCTAssertThrowsError(try FavoriteSync(container: { root }).synchronize(base: [], local: [], canWrite: true))
        }
        try fixture { root, sync, defaults, _ in
            let file = root.appendingPathComponent(FavoriteSync.filename)
            for data in [Data(), Data("{bad".utf8), Data("{\"version\":2,\"texts\":[]}".utf8), Data("{\"version\":1,\"texts\":[\"\"]}".utf8), Data(repeating: 32, count: FavoriteSync.maximumBytes + 1)] {
                try data.write(to: file)
                XCTAssertThrowsError(try sync.synchronize(base: [], local: ["local"], canWrite: true))
                XCTAssertEqual(try Data(contentsOf: file), data)
            }
            let local = SymbolBoardStore(defaults: defaults)
            XCTAssertNotNil(local.add(text: "local", to: SymbolBoardStore.favoritesID))
            let bytes = defaults.data(forKey: SymbolBoardStore.storageKey)
            let failed = SymbolBoardStore(defaults: defaults, sync: sync, sharedWriteAllowed: true)
            XCTAssertEqual(failed.favoriteTexts, ["local"])
            XCTAssertEqual(failed.syncStatus, .unavailable)
            XCTAssertEqual(defaults.data(forKey: SymbolBoardStore.storageKey), bytes)
        }
    }
    func testLockContentionLinkAndDirectoryCannotHangOrReplaceData() throws {
        try fixture { root, sync, _, _ in
            let lockURL = root.appendingPathComponent("favorites-v1.lock")
            let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            XCTAssertGreaterThanOrEqual(fd, 0)
            defer { close(fd) }
            XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
            XCTAssertThrowsError(try sync.synchronize(base: [], local: [], canWrite: true))
            XCTAssertEqual(flock(fd, LOCK_UN), 0)
            try FileManager.default.removeItem(at: lockURL)
            try FileManager.default.createSymbolicLink(at: lockURL, withDestinationURL: root.appendingPathComponent("absent"))
            XCTAssertThrowsError(try sync.synchronize(base: [], local: [], canWrite: true))
            try FileManager.default.removeItem(at: lockURL)
            XCTAssertEqual(mkfifo(lockURL.path, S_IRUSR | S_IWUSR), 0)
            XCTAssertThrowsError(try sync.synchronize(base: [], local: [], canWrite: true))
            try FileManager.default.removeItem(at: lockURL)
            let file = root.appendingPathComponent(FavoriteSync.filename)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            XCTAssertThrowsError(try FavoriteSync.readFile(file))
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root.appendingPathComponent("absent"))
            XCTAssertThrowsError(try FavoriteSync.readFile(file))
            var fake = sync
            fake.read = { _ in nil }
            XCTAssertThrowsError(try fake.synchronize(base: [], local: [], canWrite: true))
            XCTAssertThrowsError(try FavoriteSync.readFile(URL(string: "https://invalid.example/")!))
        }
    }
    func testFailedSharedOrLocalWriteRetainsEditsAndRetriesWithoutDuplicates() throws {
        try fixture { root, sync, a, b in
            var broken = sync
            broken.write = { _, _ in throw FavoriteSync.Issue.unavailable }
            let offline = SymbolBoardStore(defaults: a, sync: broken, sharedWriteAllowed: true)
            XCTAssertNotNil(offline.add(text: "pending", to: SymbolBoardStore.favoritesID))
            XCTAssertEqual(offline.syncStatus, .unavailable)
            let online = SymbolBoardStore(defaults: a, sync: sync, sharedWriteAllowed: true)
            XCTAssertEqual(online.favoriteTexts, ["pending"])
            XCTAssertEqual(online.syncStatus, .current)
            let bytes = b.data(forKey: SymbolBoardStore.storageKey)
            var accepts = true
            let failed = SymbolBoardStore(defaults: b, persist: { data in
                guard accepts else { return false }; b.set(data, forKey: SymbolBoardStore.storageKey); return true
            }, sync: sync)
            accepts = false
            let before = failed.boards
            XCTAssertNotNil(online.add(text: "remote", to: SymbolBoardStore.favoritesID))
            failed.refreshFavorites(canWrite: true)
            XCTAssertEqual(failed.boards, before)
            XCTAssertEqual(failed.syncStatus, .unavailable)
            accepts = true
            failed.refreshFavorites()
            XCTAssertEqual(failed.favoriteTexts, ["remote", "pending"])
            XCTAssertNotNil(b.data(forKey: SymbolBoardStore.storageKey))
            XCTAssertNil(bytes)
            try FileManager.default.removeItem(at: root.appendingPathComponent(FavoriteSync.filename))
            failed.refreshFavorites()
            XCTAssertEqual(failed.favoriteTexts, ["remote", "pending"])
        }
    }
    func testConcurrentWritersKeepEveryUnrelatedFavorite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sync = FavoriteSync(container: { root })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask {
                    for _ in 0..<1000 {
                        do { _ = try sync.synchronize(base: [], local: ["writer-\(index)"], canWrite: true); return }
                        catch FavoriteSync.Issue.unavailable { try await Task.sleep(nanoseconds: 1_000_000) }
                    }
                    throw FavoriteSync.Issue.unavailable
                }
            }
            try await group.waitForAll()
        }
        let result = try sync.synchronize(base: [], local: [], canWrite: false)
        XCTAssertEqual(Set(result.texts), Set((0..<16).map { "writer-\($0)" }))
    }

    func testSerializedWritersMergeFromLatestDiskAndBoundEncodedPayload() throws {
        try fixture { _, sync, _, _ in
            _ = try sync.synchronize(base: [], local: ["a"], canWrite: true)
            _ = try sync.synchronize(base: [], local: ["b"], canWrite: true)
            XCTAssertEqual(try sync.synchronize(base: [], local: [], canWrite: false).texts, ["b", "a"])
            let huge = (0..<4096).map { String($0) + String(repeating: "\u{10FFFF}", count: 60) }
            XCTAssertTrue(FavoriteSync.valid(huge))
            XCTAssertThrowsError(try sync.synchronize(base: ["a", "b"], local: huge, canWrite: true))
            XCTAssertEqual(try sync.synchronize(base: [], local: [], canWrite: false).texts, ["b", "a"])
        }
    }
}
