#if canImport(UIKit)
import Foundation
import Combine
import XCTest
@testable import Uniboard

@MainActor
final class CatalogPreferencesTests: XCTestCase {
    func testTopBarSettingsPersistIndependentlyAndFailedWritesKeepPreviousValues() throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.previous)
            let value = CatalogPreferences(editionSettings: storage.settings)
            XCTAssertTrue(value.showsSymbolBar); XCTAssertFalse(value.searchBarInsteadOfSymbols)
            value.selectSearchBarInsteadOfSymbols(true); value.selectSymbolBar(false)
            value.selectEdition(.draft)
            XCTAssertFalse(storage.settings.loadSnapshot().showsSymbolBar)
            XCTAssertTrue(storage.settings.loadSnapshot().searchBarInsteadOfSymbols)
            storage.failWrites = true
            value.selectSymbolBar(true); value.selectSearchBarInsteadOfSymbols(false)
            XCTAssertFalse(value.showsSymbolBar); XCTAssertTrue(value.searchBarInsteadOfSymbols)
            XCTAssertNotNil(value.editionSaveError)
            storage.failWrites = false
            let restored = CatalogPreferences(editionSettings: storage.settings)
            XCTAssertFalse(restored.showsSymbolBar); XCTAssertTrue(restored.searchBarInsteadOfSymbols)
        }
    }

    func testLayoutsPersistInOrderAndRejectEmptyOrUnknownLists() throws {
        try withDefaults { _ in
            let storage = try SharedFile(.previous)
            let value = CatalogPreferences(editionSettings: storage.settings)
            XCTAssertEqual(value.layouts, ["en"]); XCTAssertEqual(value.alphabets, [.english])
            XCTAssertTrue(value.selectLayouts(["ru", "en", "el"]))
            XCTAssertEqual(value.alphabets.map(\.nativeName), ["Русский", "English", "Ελληνικά"])
            XCTAssertEqual(storage.settings.loadSnapshot().layouts, ["ru", "en", "el"])
            XCTAssertEqual(storage.settings.loadSnapshot().edition, .previous, "Layouts keep the edition")
            for invalid in [[], ["ru", "ru"], ["en", "xx"]] { XCTAssertFalse(value.selectLayouts(invalid)) }
            storage.failWrites = true
            XCTAssertFalse(value.selectLayouts(["el"]))
            XCTAssertEqual(value.layouts, ["ru", "en", "el"])
            storage.failWrites = false
            XCTAssertEqual(CatalogPreferences(editionSettings: storage.settings).layouts, ["ru", "en", "el"])
        }
    }

    func testPadSettingsPreserveOtherFieldsAcrossSavesRefreshesAndFailedWrites() throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.previous)
            let preferences = CatalogPreferences(editionSettings: storage.settings)
            XCTAssertTrue(storage.settings.save(.init(edition: .previous, padSymbolMapping: .none)))
            preferences.refreshEdition()
            preferences.selectPadLayout(.ansi)
            preferences.selectUnicodeFonts(true)
            preferences.selectCollapseKey(true)
            preferences.selectEdition(.older)
            let expected = UnicodeEditionSettings.Snapshot(edition: .older, useUnicodeFonts: true, showsCollapseKey: true,
                padLayout: .ansi, padSymbolMapping: .none)
            XCTAssertEqual(storage.settings.loadSnapshot(), expected)
            preferences.reset(preservingEdition: true)
            XCTAssertEqual(storage.settings.loadSnapshot(), expected)
            storage.failWrites = true
            preferences.selectPadLayout(.stock)
            XCTAssertEqual(preferences.padLayout, .ansi)
            XCTAssertEqual(preferences.padSymbolMapping, .none)
            XCTAssertNotNil(preferences.editionSaveError)
            XCTAssertEqual(storage.settings.loadSnapshot(), expected)
            storage.failWrites = false
            XCTAssertTrue(storage.settings.save(.init(edition: .draft, padLayout: .stock, padSymbolMapping: .iPad)))
            preferences.refreshEdition()
            XCTAssertEqual(preferences.padLayout, .stock)
            XCTAssertEqual(preferences.padSymbolMapping, .iPad)
            XCTAssertEqual(preferences.edition, .draft)
        }
    }
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
                    XCTAssertEqual(maximum, UnicodeEditionSettings.maximumPayloadBytes + 1)
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

    func testMissingSharedContainerDefaultsToLatestDespiteLegacyDraftAndCannotClaimSave() async throws {
        try withDefaults { defaults in
            defaults.set("draft", forKey: "appUnicodeEdition")
            defaults.set("draft", forKey: "keyboard.unicodeEdition")
            let before = defaults.dictionaryRepresentation()
            let settings = UnicodeEditionSettings(containerURL: { nil },
                readPrefix: { _, _ in XCTFail("No global file fallback is permitted"); return Data() },
                writeAtomically: { _, _ in XCTFail("No global file fallback is permitted") })
            let preferences = CatalogPreferences(editionSettings: settings)
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
            let preferences = CatalogPreferences(editionSettings: storage.settings)
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
            let preferences = CatalogPreferences(editionSettings: storage.settings)
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
            let preferences = CatalogPreferences(editionSettings: storage.settings)
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
            defaults.set(true, forKey: "appUnicodeFonts")
            let storage = try SharedFile(.draft)
            storage.data = try SharedFile.payload(.init(edition: .draft, useUnicodeFonts: true, showsCollapseKey: true))
            let original = storage.data
            let preferences = CatalogPreferences(editionSettings: storage.settings)
            XCTAssertTrue(preferences.useUnicodeFonts)
            preferences.reset(preservingEdition: true)
            XCTAssertEqual(preferences.edition, .draft)
            XCTAssertEqual(storage.data, original)
            XCTAssertEqual(storage.writeAttempts, 0)
            XCTAssertTrue(preferences.useUnicodeFonts)
            XCTAssertTrue(preferences.showsCollapseKey)
            XCTAssertEqual(defaults.object(forKey: "appUnicodeFonts") as? Bool, true, "Old local preferences are not an authority or migration target")
        }
    }

    func testExplicitResetPersistsLatestWhileResettingLocalDisplayPreferences() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.older)
            let preferences = CatalogPreferences(editionSettings: storage.settings)
            preferences.selectUnicodeFonts(true)
            preferences.reset()
            XCTAssertEqual(preferences.edition, .latest)
            XCTAssertEqual(try storage.storedIdentifier(), "latest")
            XCTAssertEqual(storage.successfulWrites, 2)
            XCTAssertFalse(preferences.useUnicodeFonts)
            XCTAssertNil(preferences.editionSaveError)
        }
    }

    func testRefreshOnlyPublishesChangedValuesAndNeverSavesOrMigrates() async throws {
        try withDefaults { defaults in
            let storage = try SharedFile(.draft)
            let preferences = CatalogPreferences(editionSettings: storage.settings)
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
            let preferences = CatalogPreferences(editionSettings: storage.settings)
            preferences.selectUnicodeFonts(true)
            storage.failWrites = true
            preferences.reset()
            XCTAssertEqual(preferences.edition, .previous)
            XCTAssertEqual(try storage.storedIdentifier(), UnicodeEdition.previous.selectionIdentifier)
            XCTAssertNotNil(preferences.editionSaveError)
            XCTAssertEqual(storage.successfulWrites, 1)
            XCTAssertTrue(preferences.useUnicodeFonts, "A failed atomic reset retains every published shared setting")
        }
    }

    func testSharedFontAndCollapseChangesPersistTogetherBeforePublishingAndIgnoreLocalFlags() async throws {
        try withDefaults { defaults in
            defaults.set(true, forKey: "appUnicodeFonts")
            defaults.set(true, forKey: "keyboardUnicodeFonts")
            let storage = try SharedFile(.previous)
            let preferences = CatalogPreferences(editionSettings: storage.settings)
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
            let restored = CatalogPreferences(editionSettings: storage.settings)
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

final class TileGridLayoutTests: XCTestCase {
    func testMaximumColumnsKeepTilesAtLeast32PointsWide() {
        // iPhone portrait grid (402 − 32 padding): 9 tiles of 34pt; a 10th would make them 29.8pt.
        XCTAssertEqual(TileGridLayout.maximumColumns(in: 370), 9)
        XCTAssertGreaterThan(TileGridLayout.maximumColumns(in: 370), 7)
        // iPad and landscape widths allow more.
        XCTAssertEqual(TileGridLayout.maximumColumns(in: 748), 18)
        XCTAssertEqual(TileGridLayout.maximumColumns(in: 780), 19)
        for width: CGFloat in [100, 250, 370, 500, 748, 780, 1194] {
            let maximum = TileGridLayout.maximumColumns(in: width)
            XCTAssertGreaterThanOrEqual(TileGridLayout.tileWidth(columns: maximum, in: width), 32, "\(width)")
            XCTAssertLessThan(TileGridLayout.tileWidth(columns: maximum + 1, in: width), 32, "\(width)")
        }
        // Exactly 32pt tiles still count.
        XCTAssertEqual(TileGridLayout.maximumColumns(in: 32 * 5 + 8 * 4), 5)
        // Never fewer than the minimum, and the old limit before the width is measured.
        XCTAssertEqual(TileGridLayout.maximumColumns(in: 40), 2)
        XCTAssertEqual(TileGridLayout.maximumColumns(in: 0), 7)
    }

    func testStoredColumnsAreClampedForDisplayOnly() {
        XCTAssertEqual(TileGridLayout.columns(stored: 15, in: 780), 15)
        // Rotating to a narrower width shows fewer columns without changing the stored value.
        XCTAssertEqual(TileGridLayout.columns(stored: 15, in: 370), 9)
        XCTAssertEqual(TileGridLayout.columns(stored: 1, in: 370), 2)
        XCTAssertEqual(TileGridLayout.columns(stored: 3, in: 370), 3)
        XCTAssertEqual(TileGridLayout.tileWidth(columns: 3, in: 0), 0)
        XCTAssertEqual(TileGridLayout.tileWidth(columns: 4, in: 370), 86.5)
    }

    func testRibbonBecomesTriangleInBlockViewOrUnder80Points() {
        XCTAssertTrue(TileGridLayout.showsLabeledRibbon(tileWidth: 80, blockView: false))
        XCTAssertTrue(TileGridLayout.showsLabeledRibbon(tileWidth: 118, blockView: false))
        XCTAssertFalse(TileGridLayout.showsLabeledRibbon(tileWidth: 79.9, blockView: false))
        XCTAssertFalse(TileGridLayout.showsLabeledRibbon(tileWidth: 32, blockView: false))
        XCTAssertFalse(TileGridLayout.showsLabeledRibbon(tileWidth: 200, blockView: true))
        XCTAssertFalse(TileGridLayout.showsLabeledRibbon(tileWidth: 0, blockView: true))
        // An unmeasured tile outside block view keeps the ribbon.
        XCTAssertTrue(TileGridLayout.showsLabeledRibbon(tileWidth: 0, blockView: false))
        // The narrowest tiles show only the glyph and triangle.
        XCTAssertTrue(TileGridLayout.showsCodePoint(tileWidth: 46))
        XCTAssertFalse(TileGridLayout.showsCodePoint(tileWidth: 32))
    }

    func testTriangleLegsFollowCornerRadius() {
        XCTAssertEqual(VersionRibbon.triangleSide(cornerRadius: 12), 18)
        XCTAssertEqual(VersionRibbon.triangleSide(cornerRadius: 8), 14)
        XCTAssertEqual(VersionRibbon.triangleSide(cornerRadius: 4), 10)
        XCTAssertEqual(VersionRibbon.triangleSide(cornerRadius: 0), 10)
    }
}
#endif
