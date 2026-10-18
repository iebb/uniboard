import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

@MainActor
final class CharacterStoreTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "Uniboard.Collections.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func emoji(_ points: [UInt32], id: String? = nil) -> UnicodeEmojiEntry {
        UnicodeEmojiEntry(id: id ?? points.map { String(format: "%04X", $0) }.joined(separator: "-"),
                          codePoints: points, name: "Fixture", emojiVersion: "1.0", unicodeVersion: "1.0",
                          group: "Fixture", subgroup: "Fixture")
    }

    func testMissingOrWronglyTypedCollectionsRestoreEmpty() async throws {
        try withDefaults { defaults in
            for key in ["favoriteCodePoints", "recentCodePoints", "favoriteEmojiSequences", "recentEmojiSequences"] {
                defaults.set("old incompatible value", forKey: key)
            }
            let store = CharacterStore(defaults: defaults)
            XCTAssertTrue(store.favorites.isEmpty)
            XCTAssertTrue(store.recents.isEmpty)
            XCTAssertTrue(store.favoriteEmojiIDs.isEmpty)
            XCTAssertTrue(store.recentEmojiIDs.isEmpty)
        }
    }

    func testRestorationRejectsInvalidNumbersWithoutWrappingOrTruncating() async throws {
        try withDefaults { defaults in
            defaults.set([NSNumber(value: 65), NSNumber(value: 65), NSNumber(value: -1),
                          NSNumber(value: UInt32.max), NSNumber(value: 65.5), NSNumber(value: Double.nan),
                          NSNumber(value: Double.infinity), NSNumber(value: true), "66",
                          NSNumber(value: 0xD800), NSNumber(value: 0xDFFF), NSNumber(value: 0x10FFFF),
                          NSNumber(value: 0), NSNumber(value: 0x1F680)] as [Any], forKey: "favoriteCodePoints")
            XCTAssertEqual(CharacterStore(defaults: defaults).favorites, [65, 0x10FFFF, 0, 0x1F680])
        }
    }

    func testRestoredRecentsAreUniqueOrderedAndBounded() async throws {
        try withDefaults { defaults in
            defaults.set(([65, 65] + Array(66...140)).map { NSNumber(value: $0) }, forKey: "recentCodePoints")
            let store = CharacterStore(defaults: defaults)
            XCTAssertEqual(store.recents, Array(65...124).map(UInt32.init))
        }
    }

    func testFavoritesToggleInOrderAndPersist() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            store.toggleFavorite(0x41)
            store.toggleFavorite(0x1F680)
            XCTAssertEqual(store.favorites, [0x1F680, 0x41])
            XCTAssertTrue(store.isFavorite(0x41))
            store.toggleFavorite(0x41)
            XCTAssertEqual(CharacterStore(defaults: defaults).favorites, [0x1F680])
        }
    }

    func testRecentsMoveToFrontAndTrimAtSixty() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            for point in UInt32(65)...134 { store.recordUse(point) }
            store.recordUse(100)
            XCTAssertEqual(store.recents.count, 60)
            XCTAssertEqual(store.recents.first, 100)
            XCTAssertEqual(Set(store.recents).count, store.recents.count)
            XCTAssertEqual(CharacterStore(defaults: defaults).recents, store.recents)
            XCTAssertFalse(store.recents.contains(65))
        }
    }

    func testInvalidScalarMutationsLeaveMemoryAndPreferencesUntouched() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            store.toggleFavorite(0x41)
            store.recordUse(0x41)
            for point: UInt32 in [0xD800, 0xDFFF, 0x110000, .max] {
                store.toggleFavorite(point)
                store.recordUse(point)
            }
            XCTAssertEqual(store.favorites, [0x41])
            XCTAssertEqual(store.recents, [0x41])
            XCTAssertEqual(CharacterStore(defaults: defaults).favorites, [0x41])
            XCTAssertEqual(CharacterStore(defaults: defaults).recents, [0x41])
        }
    }

    func testEmojiRestorationRejectsMalformedIDsAndKeepsOrder() async throws {
        try withDefaults { defaults in
            defaults.set(["1F600", "1F600", "1F642-200D-2194-FE0F", "", "-", "D800", "110000",
                          "1f680", "U+1F680", "01F680", "1F680-", " 1F680", 65] as [Any],
                         forKey: "favoriteEmojiSequences")
            XCTAssertEqual(CharacterStore(defaults: defaults).favoriteEmojiIDs,
                           ["1F600", "1F642-200D-2194-FE0F"])
        }
    }

    func testEmojiMutationsRequireExactCompleteScalarIdentity() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            let sequence = emoji([0x1F642, 0x200D, 0x2194, 0xFE0F])
            store.toggleFavoriteEmoji(sequence)
            store.recordEmojiUse(sequence)
            for invalid in [emoji([]), emoji([0xD800]), emoji([0x110000]), emoji([0x1F600], id: "1F680")] {
                store.toggleFavoriteEmoji(invalid)
                store.recordEmojiUse(invalid)
            }
            XCTAssertEqual(store.favoriteEmojiIDs, [sequence.id])
            XCTAssertEqual(store.recentEmojiIDs, [sequence.id])
            let restored = CharacterStore(defaults: defaults)
            XCTAssertEqual(restored.favoriteEmojiIDs, [sequence.id])
            XCTAssertEqual(restored.recentEmojiIDs, [sequence.id])
            store.toggleFavoriteEmoji(sequence)
            XCTAssertTrue(store.favoriteEmojiIDs.isEmpty)
        }
    }

    func testEmojiRecentsAndRestorationHaveTheSameSixtyItemBound() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            for point in UInt32(0x1F600)...0x1F64F { store.recordEmojiUse(emoji([point])) }
            store.recordEmojiUse(emoji([0x1F620]))
            XCTAssertEqual(store.recentEmojiIDs.count, 60)
            XCTAssertEqual(store.recentEmojiIDs.first, "1F620")
            XCTAssertEqual(Set(store.recentEmojiIDs).count, 60)
            XCTAssertEqual(CharacterStore(defaults: defaults).recentEmojiIDs, store.recentEmojiIDs)
            defaults.set(Array(0x1F600...0x1F64F).map { String(format: "%04X", $0) },
                         forKey: "recentEmojiSequences")
            XCTAssertEqual(CharacterStore(defaults: defaults).recentEmojiIDs.count, 60)
        }
    }

    func testCollectionLookupFiltersUnavailableEntriesWithoutLosingStoredFavorites() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            store.toggleFavorite(0x41)
            store.toggleFavorite(0x0378)
            XCTAssertEqual(store.favoriteCharacters(in: UnicodeCatalog.latest).map(\.codePoint), [0x41])
            XCTAssertEqual(store.favorites, [0x0378, 0x41])
            let rocket = try XCTUnwrap(EmojiCatalog.latest.search("U+1F680").first)
            store.toggleFavoriteEmoji(rocket)
            store.toggleFavoriteEmoji(emoji([0]))
            XCTAssertEqual(store.favoriteEmojiEntries(in: EmojiCatalog.latest).map(\.id), [rocket.id])
            XCTAssertEqual(store.favoriteEmojiIDs, ["0000", rocket.id])
        }
    }

    func testRecentAndDefaultLookupsKeepOrderAndSkipUnavailableEntries() async throws {
        try withDefaults { defaults in
            let store = CharacterStore(defaults: defaults)
            for point: UInt32 in [0x41, 0x1F680, 0x0378] {
                store.toggleFavorite(point)
                store.recordUse(point)
            }
            XCTAssertEqual(store.favoriteCharacters.map(\.codePoint), [0x1F680, 0x41])
            XCTAssertEqual(store.recentCharacters.map(\.codePoint), [0x1F680, 0x41])
            XCTAssertEqual(store.recentCharacters(in: .latest).map(\.codePoint), [0x1F680, 0x41])
            let rocket = try XCTUnwrap(EmojiCatalog.latest.search("U+1F680").first)
            store.recordEmojiUse(rocket)
            store.recordEmojiUse(emoji([0]))
            XCTAssertEqual(store.recentEmojiEntries(in: .latest).map(\.id), [rocket.id])
            XCTAssertFalse(store.isFavoriteEmoji(rocket.id))
            store.toggleFavoriteEmoji(rocket)
            XCTAssertTrue(store.isFavoriteEmoji(rocket.id))
        }
    }

    func testResetRemovesOnlyCollectionsAndSandboxesStayIndependent() async throws {
        try withDefaults { appDefaults in
            try withDefaults { keyboardDefaults in
                appDefaults.set("latest", forKey: "appUnicodeEdition")
                let app = CharacterStore(defaults: appDefaults)
                let keyboard = CharacterStore(defaults: keyboardDefaults)
                app.toggleFavorite(0x41)
                keyboard.toggleFavorite(0x42)
                app.recordEmojiUse(emoji([0x1F680]))
                app.reset()
                XCTAssertEqual(appDefaults.string(forKey: "appUnicodeEdition"), "latest")
                XCTAssertTrue(CharacterStore(defaults: appDefaults).favorites.isEmpty)
                XCTAssertTrue(CharacterStore(defaults: appDefaults).recentEmojiIDs.isEmpty)
                XCTAssertEqual(CharacterStore(defaults: keyboardDefaults).favorites, [0x42])
                for key in ["favoriteCodePoints", "recentCodePoints", "favoriteEmojiSequences", "recentEmojiSequences"] {
                    XCTAssertNil(appDefaults.object(forKey: key))
                }
            }
        }
    }
}
