#if canImport(UIKit)
import Foundation
import Combine
import XCTest
@testable import Uniboard

@MainActor
final class CatalogPreferencesTests: XCTestCase {
    private enum Failure: Error { case unavailable }
    private final class SharedFile {
        var data: Data?
        var failWrites = false
        var writeAttempts = 0
        var successfulWrites = 0

        init(_ edition: UnicodeEdition? = nil) throws {
            if let edition { data = try Self.payload(edition) }
        }

        static func payload(_ edition: UnicodeEdition) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "schemaVersion": 1, "selectionIdentifier": edition.selectionIdentifier
            ])
        }
        static func payload(_ snapshot: UnicodeEditionSettings.Snapshot) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schemaVersion": 2,
                "selectionIdentifier": snapshot.edition.selectionIdentifier,
                "useUnicodeFonts": snapshot.useUnicodeFonts, "showsCollapseKey": snapshot.showsCollapseKey])
        }

        var settings: UnicodeEditionSettings {
            UnicodeEditionSettings(containerURL: { URL(fileURLWithPath: "/injected-app-edition") },
                readPrefix: { _, maximum in
                    XCTAssertEqual(maximum, 257)
                    guard let data = self.data else { throw Failure.unavailable }
                    return data
                }, writeAtomically: { data, _ in
                    self.writeAttempts += 1
                    if self.failWrites { throw Failure.unavailable }
                    self.data = data
                    self.successfulWrites += 1
                })
        }

        func storedIdentifier() throws -> String? {
            let object = try JSONSerialization.jsonObject(with: XCTUnwrap(data)) as? [String: Any]
            return object?["selectionIdentifier"] as? String
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "Uniboard.CatalogPreferences.Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    func testFreshInvalidAndSavedSortPreferencesUseAscendingOnlyAsFallback() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.latest)
            XCTAssertEqual(CatalogPreferences(defaults: defaults, editionSettings: storage.settings).order, .codePoint)
            XCTAssertNil(defaults.object(forKey: "appUnicodeSort"), "Reading defaults does not rewrite an explicit selection")
            for order in UnicodeSortOrder.allCases {
                defaults.set(order.rawValue, forKey: "appUnicodeSort")
                XCTAssertEqual(CatalogPreferences(defaults: defaults, editionSettings: storage.settings).order, order)
                XCTAssertEqual(defaults.string(forKey: "appUnicodeSort"), order.rawValue)
            }
            for invalid: Any in ["unrecognized", 123, true] {
                defaults.set(invalid, forKey: "appUnicodeSort")
                XCTAssertEqual(CatalogPreferences(defaults: defaults, editionSettings: storage.settings).order, .codePoint)
            }
        }
    }

    func testMissingSharedContainerDefaultsToLatestDespiteLegacyDraftAndCannotClaimSave() async throws {
        try withDefaults { defaults in
            defaults.set("draft", forKey: "appUnicodeEdition")
            defaults.set("draft", forKey: "keyboard.unicodeEdition")
            let before = defaults.dictionaryRepresentation()
            let settings = UnicodeEditionSettings(containerURL: { nil },
                readPrefix: { _, _ in XCTFail("No global file fallback is permitted"); return Data() },
                writeAtomically: { _, _ in XCTFail("No global file fallback is permitted") })
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: settings)
            XCTAssertEqual(preferences.edition, .latest)
            XCTAssertNil(preferences.editionSaveError)
            preferences.selectEdition(.draft)
            XCTAssertEqual(preferences.edition, .latest)
            XCTAssertFalse(preferences.editionSaveError?.isEmpty ?? true)
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary,
                           "Edition selection must not migrate into either process's independent preferences")
        }
    }

    func testSuccessfulSelectionPublishesOnlyAfterPersistingTheStableHistoricalIdentifier() async throws {
        try withDefaults { defaults in
            defaults.set("legacy-local-choice", forKey: "appUnicodeEdition")
            let storage = try SharedFile(.latest)
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            var published: [UnicodeEdition] = []
            var identifiersAtPublication: [String?] = []
            let observation = preferences.$edition.dropFirst().sink { edition in
                published.append(edition)
                identifiersAtPublication.append(try? storage.storedIdentifier())
            }
            defer { observation.cancel() }
            preferences.selectEdition(.previous)
            XCTAssertEqual(preferences.edition, .previous)
            XCTAssertEqual(published, [.previous])
            XCTAssertEqual(identifiersAtPublication, [UnicodeEdition.previous.versionLabel])
            XCTAssertEqual(try storage.storedIdentifier(), UnicodeEdition.previous.versionLabel)
            XCTAssertNotEqual(try storage.storedIdentifier(), "previous", "A rolling slot is not a historical version")
            XCTAssertEqual(storage.successfulWrites, 1)
            XCTAssertNil(preferences.editionSaveError)
            XCTAssertEqual(defaults.string(forKey: "appUnicodeEdition"), "legacy-local-choice")
        }
    }

    func testFailedSaveKeepsPublishedAndStoredSelectionWithAnActionableError() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.previous)
            let original = storage.data
            storage.failWrites = true
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            var published: [UnicodeEdition] = []
            let observation = preferences.$edition.dropFirst().sink { published.append($0) }
            defer { observation.cancel() }
            preferences.selectEdition(.draft)
            XCTAssertEqual(preferences.edition, .previous)
            XCTAssertEqual(storage.data, original)
            XCTAssertTrue(published.isEmpty)
            XCTAssertEqual(storage.writeAttempts, 1)
            XCTAssertEqual(storage.successfulWrites, 0)
            XCTAssertFalse(preferences.editionSaveError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    func testSuccessfulRetryClearsTheErrorAndAdoptsExactlyTheRetriedChoice() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.previous)
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            storage.failWrites = true
            preferences.selectEdition(.draft)
            XCTAssertNotNil(preferences.editionSaveError)
            XCTAssertEqual(preferences.edition, .previous)
            storage.failWrites = false
            preferences.selectEdition(.older)
            XCTAssertEqual(preferences.edition, .older)
            XCTAssertEqual(try storage.storedIdentifier(), UnicodeEdition.older.selectionIdentifier)
            XCTAssertNil(preferences.editionSaveError)
            XCTAssertEqual(storage.writeAttempts, 2)
            XCTAssertEqual(storage.successfulWrites, 1)
        }
    }

    func testUITestResetPreservesWholeSharedSnapshotAndNeverWritesSharedStorage() async throws {
        try withDefaults { defaults in
            defaults.set(UnicodeSortOrder.oldestFirst.rawValue, forKey: "appUnicodeSort")
            defaults.set(true, forKey: "appUnicodeFonts")
            let storage = try SharedFile(.draft)
            storage.data = try SharedFile.payload(.init(edition: .draft, useUnicodeFonts: true, showsCollapseKey: true))
            let original = storage.data
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            XCTAssertEqual(preferences.order, .oldestFirst)
            XCTAssertTrue(preferences.useUnicodeFonts)
            preferences.reset(preservingEdition: true)
            XCTAssertEqual(preferences.edition, .draft)
            XCTAssertEqual(storage.data, original)
            XCTAssertEqual(storage.writeAttempts, 0)
            XCTAssertEqual(preferences.order, .codePoint)
            XCTAssertTrue(preferences.useUnicodeFonts)
            XCTAssertTrue(preferences.showsCollapseKey)
            XCTAssertEqual(defaults.string(forKey: "appUnicodeSort"), UnicodeSortOrder.codePoint.rawValue)
            XCTAssertEqual(defaults.object(forKey: "appUnicodeFonts") as? Bool, true, "Old local preferences are not an authority or migration target")
        }
    }

    func testExplicitResetPersistsLatestWhileResettingLocalDisplayPreferences() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.older)
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            preferences.order = .codePoint
            preferences.selectUnicodeFonts(true)
            preferences.reset()
            XCTAssertEqual(preferences.edition, .latest)
            XCTAssertEqual(try storage.storedIdentifier(), "latest")
            XCTAssertEqual(storage.successfulWrites, 2)
            XCTAssertEqual(preferences.order, .codePoint)
            XCTAssertFalse(preferences.useUnicodeFonts)
            XCTAssertNil(preferences.editionSaveError)
        }
    }

    func testRefreshOnlyPublishesChangedValuesAndNeverSavesOrMigrates() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.draft)
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            var published: [UnicodeEdition] = []
            let observation = preferences.$edition.dropFirst().sink { published.append($0) }
            defer { observation.cancel() }
            preferences.refreshEdition()
            XCTAssertTrue(published.isEmpty)
            storage.data = try SharedFile.payload(.older)
            preferences.refreshEdition()
            preferences.refreshEdition()
            XCTAssertEqual(published, [.older])
            XCTAssertEqual(preferences.edition, .older)
            storage.data = Data("invalid stale settings".utf8)
            preferences.refreshEdition()
            preferences.refreshEdition()
            XCTAssertEqual(published, [.older, .latest])
            XCTAssertEqual(preferences.edition, .latest)
            XCTAssertEqual(storage.writeAttempts, 0, "A read cannot repair or rewrite app-group storage")
            XCTAssertNil(defaults.object(forKey: "appUnicodeEdition"))
        }
    }

    func testFailedExplicitResetReportsUnsavedEditionWhileResettingLocalOptions() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.previous)
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            preferences.order = .oldestFirst
            preferences.selectUnicodeFonts(true)
            storage.failWrites = true
            preferences.reset()
            XCTAssertEqual(preferences.edition, .previous)
            XCTAssertEqual(try storage.storedIdentifier(), UnicodeEdition.previous.selectionIdentifier)
            XCTAssertNotNil(preferences.editionSaveError)
            XCTAssertEqual(storage.successfulWrites, 1)
            XCTAssertEqual(preferences.order, .codePoint)
            XCTAssertTrue(preferences.useUnicodeFonts, "A failed atomic reset retains every published shared setting")
        }
    }

    func testSharedFontAndCollapseChangesPersistTogetherBeforePublishingAndIgnoreLocalFlags() async throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: "appUnicodeFonts")
            defaults.set(true, forKey: "keyboardUnicodeFonts")
            let storage = try SharedFile(.previous)
            let preferences = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            XCTAssertFalse(preferences.useUnicodeFonts)
            XCTAssertFalse(preferences.showsCollapseKey)
            var persistedAtPublication: [UnicodeEditionSettings.Snapshot] = []
            let observation = preferences.$useUnicodeFonts.dropFirst().sink { _ in persistedAtPublication.append(storage.settings.loadSnapshot()) }
            defer { observation.cancel() }
            preferences.selectUnicodeFonts(true)
            preferences.selectCollapseKey(true)
            preferences.selectEdition(.older)
            let expected = UnicodeEditionSettings.Snapshot(edition: .older, useUnicodeFonts: true, showsCollapseKey: true)
            XCTAssertEqual(storage.settings.loadSnapshot(), expected)
            XCTAssertEqual(persistedAtPublication, [.init(edition: .previous, useUnicodeFonts: true)])
            let restored = CatalogPreferences(defaults: defaults, editionSettings: storage.settings)
            XCTAssertEqual(restored.edition, .older)
            XCTAssertTrue(restored.useUnicodeFonts)
            XCTAssertTrue(restored.showsCollapseKey)
            storage.failWrites = true
            restored.selectUnicodeFonts(false)
            restored.selectCollapseKey(false)
            XCTAssertTrue(restored.useUnicodeFonts)
            XCTAssertTrue(restored.showsCollapseKey)
            XCTAssertEqual(storage.settings.loadSnapshot(), expected)
            XCTAssertNotNil(restored.editionSaveError)
            storage.failWrites = false
            storage.data = try SharedFile.payload(.init(edition: .older))
            restored.refreshEdition()
            restored.refreshEdition()
            XCTAssertFalse(restored.useUnicodeFonts)
            XCTAssertFalse(restored.showsCollapseKey)
            XCTAssertEqual(defaults.object(forKey: "keyboardUnicodeFonts") as? Bool, true)
        }
    }
}
#endif
