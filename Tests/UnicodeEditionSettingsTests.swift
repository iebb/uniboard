import Foundation
import XCTest
#if canImport(UniboardCore)
@testable import UniboardCore
#else
@testable import Uniboard
#endif

final class UnicodeEditionSettingsTests: XCTestCase {
    private enum Failure: Error { case unavailable }
    private let injectedContainer = URL(fileURLWithPath: "/injected-edition-container", isDirectory: true)

    private func payload(_ identifier: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "selectionIdentifier": identifier])
    }

    private func withTemporaryContainer(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Uniboard.EditionSettings.Tests.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func load(_ data: Data) -> UnicodeEdition {
        UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in data },
                               writeAtomically: { _, _ in XCTFail("Loading must never write") }).load()
    }

    func testTopBarOptionsRoundTripLegacyMigrationAndRejectMalformedBooleans() throws {
        for bar in [false, true] { for search in [false, true] {
            var bytes = try payload("latest")
            let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes },
                writeAtomically: { data, _ in bytes = data })
            let value = UnicodeEditionSettings.Snapshot(edition: .previous, showsSymbolBar: bar,
                searchBarInsteadOfSymbols: search)
            XCTAssertTrue(settings.save(value)); XCTAssertEqual(settings.loadSnapshot(), value)
            var malformed = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            for field in ["showsSymbolBar", "searchBarInsteadOfSymbols", "showsNumberRow", "showsTextPreview", "showsUCSUR"] {
                for invalid: Any in [0, 1, "true", NSNull(), [], [:]] {
                    var copy = malformed; copy[field] = invalid
                    let data = try JSONSerialization.data(withJSONObject: copy)
                    XCTAssertEqual(UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in data }).loadSnapshot(), .init(edition: .latest))
                }
            }
            // Schema 7 predates UCSUR, which then stays off.
            malformed["schemaVersion"] = 7
            malformed.removeValue(forKey: "showsUCSUR")
            bytes = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertEqual(settings.loadSnapshot(), value)
            // Schema 6 predates the text preview row, which then stays off.
            malformed["schemaVersion"] = 6
            malformed.removeValue(forKey: "showsTextPreview")
            bytes = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertEqual(settings.loadSnapshot(), value)
            // Schema 5 predates layouts, so only English is enabled.
            malformed["schemaVersion"] = 5
            malformed.removeValue(forKey: "layouts")
            bytes = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertEqual(settings.loadSnapshot(), value)
            // Schema 4 predates the number-row setting, which then stays on.
            malformed["schemaVersion"] = 4
            malformed.removeValue(forKey: "showsNumberRow")
            bytes = try JSONSerialization.data(withJSONObject: malformed)
            XCTAssertEqual(settings.loadSnapshot(), value)
            malformed["schemaVersion"] = 3
            malformed.removeValue(forKey: "showsSymbolBar"); malformed.removeValue(forKey: "searchBarInsteadOfSymbols")
            bytes = try JSONSerialization.data(withJSONObject: malformed)
            let legacy = settings.loadSnapshot()
            XCTAssertTrue(legacy.showsSymbolBar); XCTAssertFalse(legacy.searchBarInsteadOfSymbols)
            XCTAssertEqual(legacy.edition, .previous)
        } }
    }

    func testLayoutListRoundTripsInOrderAndRejectsMalformedLists() throws {
        var bytes = try payload("latest")
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes },
            writeAtomically: { data, _ in bytes = data })
        XCTAssertEqual(UnicodeEditionSettings.Snapshot(edition: .latest).layouts, ["en"], "English is the default layout")
        let value = UnicodeEditionSettings.Snapshot(edition: .latest, layouts: ["el", "en", "sr-Cyrl", "tr"])
        XCTAssertTrue(settings.save(value)); XCTAssertEqual(settings.loadSnapshot(), value)
        let all = KeyboardAlphabet.catalog.prefix(UnicodeEditionSettings.maximumLayouts).map(\.id)
        XCTAssertTrue(settings.save(.init(edition: .latest, layouts: all)))
        XCTAssertLessThanOrEqual(bytes.count, UnicodeEditionSettings.maximumPayloadBytes)
        XCTAssertEqual(settings.loadSnapshot().layouts, all)
        for invalid in [[], ["en", "en"], ["xx"], Array(KeyboardAlphabet.catalog.prefix(9).map(\.id))] {
            XCTAssertFalse(settings.save(.init(edition: .draft, layouts: invalid)), "\(invalid)")
        }
        XCTAssertEqual(settings.loadSnapshot().layouts, all, "A rejected list leaves the saved one alone")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        // A newer version's layout is skipped while known ones are kept.
        var future = object; future["layouts"] = ["ja-Kana", "ru"]
        bytes = try JSONSerialization.data(withJSONObject: future)
        XCTAssertEqual(settings.loadSnapshot().layouts, ["ru"])
        for invalid: Any in [[], ["xx"], ["en", "en"], ["en", 1], "en", NSNull(), [:], Array(repeating: "en", count: 9)] {
            var copy = object; copy["layouts"] = invalid
            bytes = try JSONSerialization.data(withJSONObject: copy)
            XCTAssertEqual(settings.loadSnapshot(), .init(edition: .latest), "\(invalid)")
        }
        var missing = object; missing.removeValue(forKey: "layouts")
        bytes = try JSONSerialization.data(withJSONObject: missing)
        XCTAssertEqual(settings.loadSnapshot(), .init(edition: .latest), "Schema 6 requires its layouts")
    }

    func testTextPreviewChoiceRoundTrips() throws {
        var bytes = try payload("latest")
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes },
            writeAtomically: { data, _ in bytes = data })
        XCTAssertFalse(UnicodeEditionSettings.Snapshot(edition: .latest).showsTextPreview, "The preview row is off by default")
        let value = UnicodeEditionSettings.Snapshot(edition: .latest, showsTextPreview: true)
        XCTAssertTrue(settings.save(value)); XCTAssertEqual(settings.loadSnapshot(), value)
        let ucsur = UnicodeEditionSettings.Snapshot(edition: .latest, showsUCSUR: true)
        XCTAssertTrue(settings.save(ucsur)); XCTAssertEqual(settings.loadSnapshot(), ucsur)
    }

    func testNumberRowChoiceRoundTripsAndSurvivesEditionChanges() throws {
        var bytes = try payload("latest")
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes },
            writeAtomically: { data, _ in bytes = data })
        XCTAssertTrue(UnicodeEditionSettings.Snapshot(edition: .latest).showsNumberRow, "The number row is on by default")
        var value = UnicodeEditionSettings.Snapshot(edition: .latest, showsNumberRow: false)
        XCTAssertTrue(settings.save(value)); XCTAssertEqual(settings.loadSnapshot(), value)
        XCTAssertTrue(settings.save(.draft))
        value.edition = .draft
        XCTAssertEqual(settings.loadSnapshot(), value)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(object["showsNumberRow"] as? Bool, false)
    }

    func testPadPresetsAndSymbolMappingsRoundTripAndEditionChangesPreserveEverything() throws {
        for layout in KeyboardPadLayout.allCases { for mapping in KeyboardPadSymbolMapping.allCases {
            XCTAssertFalse(layout.title.isEmpty)
            XCTAssertFalse(mapping.title.isEmpty)
            var bytes = try payload("draft")
            let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer },
                readPrefix: { _, _ in bytes }, writeAtomically: { data, _ in bytes = data })
            var value = UnicodeEditionSettings.Snapshot(edition: .older, useUnicodeFonts: true, showsCollapseKey: true,
                padLayout: layout, padSymbolMapping: mapping)
            XCTAssertTrue(settings.save(value))
            XCTAssertEqual(settings.loadSnapshot(), value)
            XCTAssertLessThanOrEqual(bytes.count, UnicodeEditionSettings.maximumPayloadBytes)
            XCTAssertTrue(settings.save(.previous))
            value.edition = .previous
            XCTAssertEqual(settings.loadSnapshot(), value)
        } }
    }

    func testPadFieldsRejectUnknownTypesMissingAndExtraKeysWithoutWriting() throws {
        let valid: [String: Any] = ["schemaVersion": 3, "selectionIdentifier": "draft", "useUnicodeFonts": true,
            "showsCollapseKey": true, "padLayout": "ansi", "padSymbolMapping": "standard"]
        var cases = [[String: Any]]()
        for field in ["padLayout", "padSymbolMapping"] {
            for invalid: Any in ["", "unknown", true, 1, NSNull(), ["ansi"], ["value": "ansi"]] {
                var object = valid; object[field] = invalid; cases.append(object)
            }
            var absent = valid; absent.removeValue(forKey: field); cases.append(absent)
        }
        var extra = valid; extra["query"] = "not allowed"; cases.append(extra)
        for object in cases {
            let bytes = try JSONSerialization.data(withJSONObject: object)
            let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes },
                writeAtomically: { _, _ in XCTFail("A keyboard never rewrites malformed settings") })
            XCTAssertEqual(settings.loadSnapshot(), .init(edition: .latest))
        }
    }

    func testAllFourSelectionsRoundTripWithoutRollingHistoricalIdentifiers() throws {
        for edition in UnicodeEdition.allCases {
            var stored: Data?
            let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer },
                readPrefix: { _, _ in
                    guard let stored else { throw CocoaError(.fileReadNoSuchFile) }
                    return stored
                },
                writeAtomically: { data, _ in stored = data })
            XCTAssertTrue(settings.save(edition))
            XCTAssertEqual(settings.load(), edition)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(stored)) as? [String: Any])
            XCTAssertEqual(object["selectionIdentifier"] as? String, edition.selectionIdentifier)
        }
    }

    func testWriterContainsOnlyVersionedAppSettingsAndUsesTheFixedChild() throws {
        var observedURL: URL?
        var observedData: Data?
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer },
            readPrefix: { _, _ in throw Failure.unavailable },
            writeAtomically: { observedData = $0; observedURL = $1 })
        XCTAssertTrue(settings.save(.draft))
        XCTAssertEqual(observedURL, injectedContainer.appendingPathComponent(UnicodeEditionSettings.filename))
        let data = try XCTUnwrap(observedData)
        XCTAssertLessThanOrEqual(data.count, UnicodeEditionSettings.maximumPayloadBytes)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "selectionIdentifier", "useUnicodeFonts", "showsCollapseKey", "padLayout", "padSymbolMapping", "showsSymbolBar", "searchBarInsteadOfSymbols", "showsNumberRow", "layouts", "showsTextPreview", "showsUCSUR"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 8)
        XCTAssertEqual(object["showsTextPreview"] as? Bool, false)
        XCTAssertEqual(object["layouts"] as? [String], ["en"])
        XCTAssertEqual(object["selectionIdentifier"] as? String, "draft")
        XCTAssertEqual(object["useUnicodeFonts"] as? Bool, false)
        XCTAssertEqual(object["showsCollapseKey"] as? Bool, false)
    }

    func testLegacyEditionOnlySnapshotDefaultsOptionalFeaturesOffWithoutWritingMigration() throws {
        for edition in UnicodeEdition.allCases {
            let bytes = try payload(edition.selectionIdentifier)
            let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes },
                writeAtomically: { _, _ in XCTFail("A keyboard cannot migrate shared data") })
            XCTAssertEqual(settings.loadSnapshot(), .init(edition: edition))
        }
    }

    func testCombinedSnapshotRoundTripAndEditionCompatibilitySavePreserveFlags() throws {
        for fonts in [false, true] { for collapse in [false, true] {
            var bytes = try payload("draft")
            let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer },
                readPrefix: { _, _ in bytes }, writeAtomically: { data, _ in bytes = data })
            let snapshot = UnicodeEditionSettings.Snapshot(edition: .older, useUnicodeFonts: fonts, showsCollapseKey: collapse)
            XCTAssertTrue(settings.save(snapshot))
            XCTAssertEqual(settings.loadSnapshot(), snapshot)
            XCTAssertEqual(settings.load(), .older)
            XCTAssertTrue(settings.save(.previous))
            XCTAssertEqual(settings.loadSnapshot(), .init(edition: .previous, useUnicodeFonts: fonts, showsCollapseKey: collapse))
            XCTAssertLessThanOrEqual(bytes.count, UnicodeEditionSettings.maximumPayloadBytes)
        } }
    }

    func testCombinedSnapshotRequiresExactFieldsAndActualBooleans() throws {
        let valid: [String: Any] = ["schemaVersion": 2, "selectionIdentifier": "draft", "useUnicodeFonts": true, "showsCollapseKey": true]
        for field in ["useUnicodeFonts", "showsCollapseKey"] {
            for invalid: Any in [0, 1, "true", NSNull(), [], [:]] {
                var object = valid; object[field] = invalid
                let data = try JSONSerialization.data(withJSONObject: object)
                let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in data })
                XCTAssertEqual(settings.loadSnapshot(), .init(edition: .latest))
            }
            var missing = valid; missing.removeValue(forKey: field)
            XCTAssertEqual(load(try JSONSerialization.data(withJSONObject: missing)), .latest)
        }
        var extra = valid; extra["hostText"] = "never shared"
        XCTAssertEqual(load(try JSONSerialization.data(withJSONObject: extra)), .latest)
        var legacyWithFlags = valid; legacyWithFlags["schemaVersion"] = 1
        XCTAssertEqual(load(try JSONSerialization.data(withJSONObject: legacyWithFlags)), .latest)
    }

    func testFailedSnapshotWriteLeavesAllPreviousFieldsUntouched() throws {
        try withTemporaryContainer { directory in
            let settings = UnicodeEditionSettings(containerURL: { directory })
            let previous = UnicodeEditionSettings.Snapshot(edition: .previous, useUnicodeFonts: true, showsCollapseKey: true)
            XCTAssertTrue(settings.save(previous))
            let failed = UnicodeEditionSettings(containerURL: { directory }, writeAtomically: { _, _ in throw Failure.unavailable })
            XCTAssertFalse(failed.save(.init(edition: .draft)))
            XCTAssertEqual(settings.loadSnapshot(), previous)
        }
    }

    func testReadRequestsOnlyTheBoundedPrefixAndNeverWrites() throws {
        let bytes = try payload("draft")
        var reads = 0
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { url, maximum in
            reads += 1
            XCTAssertEqual(maximum, UnicodeEditionSettings.maximumPayloadBytes + 1)
            XCTAssertEqual(maximum, UnicodeEditionSettings.maximumPayloadBytes + 1)
            XCTAssertEqual(url, self.injectedContainer.appendingPathComponent(UnicodeEditionSettings.filename))
            return bytes
        }, writeAtomically: { _, _ in XCTFail("A keyboard load cannot write") })
        XCTAssertEqual(settings.load(), .draft)
        XCTAssertEqual(reads, 1)
    }

    func testExactPayloadByteBoundaryIsAcceptedButOneExtraByteFailsClosed() throws {
        let bytes = try payload("draft")
        let exact = bytes + Data(repeating: 0x20, count: UnicodeEditionSettings.maximumPayloadBytes - bytes.count)
        XCTAssertEqual(load(exact), .draft)
        XCTAssertEqual(load(exact + Data([0x20])), .latest)
    }

    func testCombinedSnapshotAcceptsExactByteLimitAndRejectsOverflowWithoutLosingStoredBytes() throws {
        var stored = Data()
        let writer = UnicodeEditionSettings(containerURL: { self.injectedContainer },
            readPrefix: { _, _ in stored }, writeAtomically: { data, _ in stored = data })
        let expected = UnicodeEditionSettings.Snapshot(edition: .previous, useUnicodeFonts: true, showsCollapseKey: true)
        XCTAssertTrue(writer.save(expected))
        let original = stored
        stored += Data(repeating: 0x20, count: UnicodeEditionSettings.maximumPayloadBytes - stored.count)
        XCTAssertEqual(writer.loadSnapshot(), expected)
        stored.append(0x20)
        XCTAssertEqual(writer.loadSnapshot(), .init(edition: .latest))
        XCTAssertEqual(stored, original + Data(repeating: 0x20, count: UnicodeEditionSettings.maximumPayloadBytes + 1 - original.count),
                       "A read never repairs or truncates over-budget app settings")
    }

    func testUnknownEditionInValidCombinedSnapshotFallsBackToReleaseAndRetainsExplicitFlags() throws {
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 2,
            "selectionIdentifier": "retired", "useUnicodeFonts": true, "showsCollapseKey": false])
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in data },
            writeAtomically: { _, _ in XCTFail("A fallback read cannot overwrite app-owned settings") })
        XCTAssertEqual(settings.loadSnapshot(), .init(edition: .latest, useUnicodeFonts: true))
    }

    func testMalformedSchemaOrUnexpectedFieldsFallBackToLatest() {
        let cases = [
            "{}", "[]", "null", "1", "true",
            #"{"schemaVersion":true,"selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":"1","selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":null,"selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":0,"selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":2,"selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":1.5,"selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":1,"selectionIdentifier":true}"#,
            #"{"schemaVersion":1,"selectionIdentifier":18}"#,
            #"{"schemaVersion":1,"selectionIdentifier":null}"#,
            #"{"schemaVersion":1,"selectionIdentifier":["draft"]}"#,
            #"{"selectionIdentifier":"draft"}"#,
            #"{"schemaVersion":1}"#,
            #"{"schemaVersion":1,"selectionIdentifier":"draft","query":"never shared"}"#
        ]
        for value in cases { XCTAssertEqual(load(Data(value.utf8)), .latest, value) }
    }

    func testUnknownRetiredAndNoncanonicalIdentifiersFallBackWithoutMigration() throws {
        for identifier in ["", "previous", "older", "LATEST", " latest", "draft ", "15.0.0",
                           "99.0.0", "../draft", "\u{0}", "💬", "19.0.0 draft"] {
            XCTAssertEqual(load(try payload(identifier)), .latest, identifier)
        }
    }

    func testNonUTF8TruncatedEmptyAndTrailingGarbageFailClosed() throws {
        let valid = try payload("draft")
        for bytes in [Data(), Data([0xFF, 0xFE]), Data(valid.dropLast()), valid + Data("!".utf8)] {
            XCTAssertEqual(load(bytes), .latest)
        }
    }

    func testMissingContainerDoesNotTouchFileClosuresOrFallbackToOtherStorage() {
        let settings = UnicodeEditionSettings(containerURL: { nil },
            readPrefix: { _, _ in XCTFail("No container means no read"); return Data() },
            writeAtomically: { _, _ in XCTFail("No container means no write") })
        XCTAssertEqual(settings.load(), .latest)
        XCTAssertFalse(settings.save(.draft))
    }

    func testDefaultContainerProviderUsesOnlyTheDeclaredGroupWithInjectedRead() throws {
        // Exercise the real platform container lookup, without reading or
        // modifying any actual shared setting. Unsigned core tests may have
        // no group container; an entitled native test host may have one.
        let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: UnicodeEditionSettings.groupIdentifier)
        let bytes = try payload(UnicodeEdition.previous.selectionIdentifier)
        var readURL: URL?
        let settings = UnicodeEditionSettings(readPrefix: { url, maximum in
            readURL = url
            XCTAssertEqual(maximum, UnicodeEditionSettings.maximumPayloadBytes + 1)
            return bytes
        }, writeAtomically: { _, _ in XCTFail("A default keyboard read must never write") })
        if let container, container.isFileURL {
            XCTAssertEqual(settings.load(), .previous)
            XCTAssertEqual(readURL, container.appendingPathComponent(UnicodeEditionSettings.filename))
        } else {
            XCTAssertEqual(settings.load(), .latest)
            XCTAssertNil(readURL)
        }
    }

    func testNonFileContainerCannotCauseNetworkOrFileActions() {
        let settings = UnicodeEditionSettings(containerURL: { URL(string: "https://example.invalid/edition") },
            readPrefix: { _, _ in XCTFail("Non-file container must not be read"); return Data() },
            writeAtomically: { _, _ in XCTFail("Non-file container must not be written") })
        XCTAssertEqual(settings.load(), .latest)
        XCTAssertFalse(settings.save(.draft))
    }

    func testUnavailableReadAndFailedWriteAreReportedWithoutCrashing() {
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer },
            readPrefix: { _, _ in throw Failure.unavailable },
            writeAtomically: { _, _ in throw Failure.unavailable })
        XCTAssertEqual(settings.load(), .latest)
        XCTAssertFalse(settings.save(.draft))
    }

    func testLoadingRechecksTheCurrentSelectionInsteadOfCachingAStaleChoice() throws {
        var bytes = try payload("draft")
        let settings = UnicodeEditionSettings(containerURL: { self.injectedContainer }, readPrefix: { _, _ in bytes })
        XCTAssertEqual(settings.load(), .draft)
        bytes = try payload(UnicodeEdition.previous.selectionIdentifier)
        XCTAssertEqual(settings.load(), .previous)
        bytes = try payload("retired")
        XCTAssertEqual(settings.load(), .latest)
    }

    func testRealAtomicFileRoundTripAndReplacementUseOnlyTheTemporaryContainer() throws {
        try withTemporaryContainer { directory in
            let settings = UnicodeEditionSettings(containerURL: { directory })
            XCTAssertEqual(settings.load(), .latest)
            for edition in UnicodeEdition.allCases {
                XCTAssertTrue(settings.save(edition))
                XCTAssertEqual(settings.load(), edition)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path),
                               [UnicodeEditionSettings.filename])
            }
        }
    }

    func testFailedInjectedWritePreservesThePreviouslyValidSelection() throws {
        try withTemporaryContainer { directory in
            let real = UnicodeEditionSettings(containerURL: { directory })
            XCTAssertTrue(real.save(.draft))
            let failing = UnicodeEditionSettings(containerURL: { directory },
                writeAtomically: { _, _ in throw Failure.unavailable })
            XCTAssertFalse(failing.save(.latest))
            XCTAssertEqual(real.load(), .draft)
        }
    }

    func testMissingDirectoryIsNotCreatedByEitherPath() throws {
        try withTemporaryContainer { directory in
            let missing = directory.appendingPathComponent("does-not-exist", isDirectory: true)
            let settings = UnicodeEditionSettings(containerURL: { missing })
            XCTAssertEqual(settings.load(), .latest)
            XCTAssertFalse(settings.save(.draft))
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testChildSymbolicLinkIsNeitherFollowedNorWrittenThrough() throws {
        try withTemporaryContainer { directory in
            let target = directory.appendingPathComponent("outside-settings.json")
            let bytes = try payload("draft")
            try bytes.write(to: target)
            let child = directory.appendingPathComponent(UnicodeEditionSettings.filename)
            try FileManager.default.createSymbolicLink(at: child, withDestinationURL: target)
            let settings = UnicodeEditionSettings(containerURL: { directory })
            XCTAssertEqual(settings.load(), .latest, "The valid draft behind a link must not be read")
            XCTAssertFalse(settings.save(.latest))
            XCTAssertEqual(try Data(contentsOf: target), bytes)
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: child.path), target.path)
        }
    }

    func testDirectoryAtTheFixedChildFailsClosed() throws {
        try withTemporaryContainer { directory in
            let child = directory.appendingPathComponent(UnicodeEditionSettings.filename, isDirectory: true)
            try FileManager.default.createDirectory(at: child, withIntermediateDirectories: false)
            let settings = UnicodeEditionSettings(containerURL: { directory })
            XCTAssertEqual(settings.load(), .latest)
            XCTAssertFalse(settings.save(.draft))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: child.path).isEmpty)
        }
    }

    func testRealOversizedFileIsRejectedByTheBoundedReader() throws {
        try withTemporaryContainer { directory in
            let bytes = try payload("draft") + Data(repeating: 0x20, count: 1_024)
            try bytes.write(to: directory.appendingPathComponent(UnicodeEditionSettings.filename))
            XCTAssertEqual(UnicodeEditionSettings(containerURL: { directory }).load(), .latest)
        }
    }
}
